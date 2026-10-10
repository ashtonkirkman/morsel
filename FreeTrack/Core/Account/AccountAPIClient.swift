import Foundation

/// Everything the app asks the account Worker for. `AccountService` and `SyncEngine` depend on
/// this protocol so UI tests can swap in `StubAccountAPI` and never touch the network.
protocol AccountAPI: AnyObject {
    /// False when no server URL is known; every call then throws `AccountError.notConfigured`.
    var isConfigured: Bool { get }
    func startURL(provider: AuthProvider, codeChallenge: String, state: String) -> URL?
    func signInWithApple(identityToken: String, authorizationCode: String?, fullName: PersonNameComponents?) async throws -> SessionBundle
    func exchange(code: String, codeVerifier: String) async throws -> SessionBundle
    func refresh(refreshToken: String) async throws -> SessionBundle
    func logout(refreshToken: String) async throws
    func me(accessToken: String) async throws -> AccountUser
    func deleteAccount(accessToken: String) async throws
    func pull(collection: String, since: Double, accessToken: String) async throws -> SyncPullResponse
    func push(collection: String, documents: [SyncDocument], accessToken: String) async throws -> SyncPushResponse
}

/// URLSession client for `server/account-api`. The base URL is resolved on every call so a
/// change in Settings takes effect immediately.
final class AccountAPIClient: AccountAPI {
    private let baseURLProvider: () -> URL?
    private let session: URLSession

    init(baseURLProvider: @escaping () -> URL?, session: URLSession = .shared) {
        self.baseURLProvider = baseURLProvider
        self.session = session
    }

    var isConfigured: Bool { baseURLProvider() != nil }

    func startURL(provider: AuthProvider, codeChallenge: String, state: String) -> URL? {
        guard let base = baseURLProvider(),
              var components = URLComponents(url: base.appendingPathComponent("v1/auth/\(provider.rawValue)/start"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "code_challenge", value: codeChallenge),
                                 URLQueryItem(name: "state", value: state)]
        return components.url
    }

    func signInWithApple(identityToken: String, authorizationCode: String?, fullName: PersonNameComponents?) async throws -> SessionBundle {
        var body: [String: Any] = ["identityToken": identityToken]
        if let authorizationCode { body["authorizationCode"] = authorizationCode }
        if let fullName {
            var name: [String: String] = [:]
            if let given = fullName.givenName, !given.isEmpty { name["givenName"] = given }
            if let family = fullName.familyName, !family.isEmpty { name["familyName"] = family }
            if !name.isEmpty { body["fullName"] = name }
        }
        return try await send("POST", "v1/auth/apple", json: body)
    }

    func exchange(code: String, codeVerifier: String) async throws -> SessionBundle {
        try await send("POST", "v1/auth/exchange", json: ["code": code, "codeVerifier": codeVerifier])
    }

    func refresh(refreshToken: String) async throws -> SessionBundle {
        try await send("POST", "v1/auth/refresh", json: ["refreshToken": refreshToken])
    }

    func logout(refreshToken: String) async throws {
        _ = try await sendRaw("POST", "v1/auth/logout", body: try JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken]))
    }

    func me(accessToken: String) async throws -> AccountUser {
        try await send("GET", "v1/me", accessToken: accessToken)
    }

    func deleteAccount(accessToken: String) async throws {
        _ = try await sendRaw("DELETE", "v1/me", accessToken: accessToken)
    }

    func pull(collection: String, since: Double, accessToken: String) async throws -> SyncPullResponse {
        let sinceMs = Int64(max(0, since).rounded(.down))
        return try await send("GET", "v1/sync/\(collection)", query: [URLQueryItem(name: "since", value: String(sinceMs))], accessToken: accessToken)
    }

    func push(collection: String, documents: [SyncDocument], accessToken: String) async throws -> SyncPushResponse {
        let body = try SyncCodec.encoder.encode(PushRequest(documents: documents))
        return try await send("PUT", "v1/sync/\(collection)", body: body, accessToken: accessToken)
    }

    // MARK: - Plumbing

    private struct PushRequest: Encodable { var documents: [SyncDocument] }

    private struct ErrorBody: Decodable {
        struct Inner: Decodable { var type: String?; var message: String? }
        var error: Inner?
    }

    private func send<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil,
                                    body: Data? = nil, query: [URLQueryItem] = [],
                                    accessToken: String? = nil) async throws -> T {
        let data: Data?
        if let json {
            data = try JSONSerialization.data(withJSONObject: json)
        } else {
            data = body
        }
        let (responseData, _) = try await sendRaw(method, path, body: data, query: query, accessToken: accessToken)
        do {
            return try SyncCodec.decoder.decode(T.self, from: responseData)
        } catch {
            throw AccountError.decoding
        }
    }

    @discardableResult
    private func sendRaw(_ method: String, _ path: String, body: Data? = nil, query: [URLQueryItem] = [],
                         accessToken: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let base = baseURLProvider() else { throw AccountError.notConfigured }
        guard var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw AccountError.notConfigured
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw AccountError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw AccountError.cancelled
        } catch {
            throw AccountError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw AccountError.network("No HTTP response.") }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401:
            throw AccountError.sessionExpired
        case 429:
            throw AccountError.rateLimited
        case 503 where path.contains("/auth/"):
            if let provider = AuthProvider.allCases.first(where: { path.contains("/\($0.rawValue)/") }) {
                throw AccountError.providerNotConfigured(provider)
            }
            throw AccountError.server(status: 503, message: Self.message(from: data))
        default:
            throw AccountError.server(status: http.statusCode, message: Self.message(from: data))
        }
    }

    private static func message(from data: Data) -> String {
        (try? SyncCodec.decoder.decode(ErrorBody.self, from: data))?.error?.message ?? ""
    }
}

/// No-network stand-in for UI tests and previews: never configured, every call throws.
final class StubAccountAPI: AccountAPI {
    var isConfigured: Bool { false }
    func startURL(provider: AuthProvider, codeChallenge: String, state: String) -> URL? { nil }
    func signInWithApple(identityToken: String, authorizationCode: String?, fullName: PersonNameComponents?) async throws -> SessionBundle { throw AccountError.notConfigured }
    func exchange(code: String, codeVerifier: String) async throws -> SessionBundle { throw AccountError.notConfigured }
    func refresh(refreshToken: String) async throws -> SessionBundle { throw AccountError.notConfigured }
    func logout(refreshToken: String) async throws { throw AccountError.notConfigured }
    func me(accessToken: String) async throws -> AccountUser { throw AccountError.notConfigured }
    func deleteAccount(accessToken: String) async throws { throw AccountError.notConfigured }
    func pull(collection: String, since: Double, accessToken: String) async throws -> SyncPullResponse { throw AccountError.notConfigured }
    func push(collection: String, documents: [SyncDocument], accessToken: String) async throws -> SyncPushResponse { throw AccountError.notConfigured }
}

/// One JSON encoder/decoder pair for everything that crosses the wire or lands in a document.
enum SyncCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    static func encodeToString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decoder.decode(type, from: Data(string.utf8))
    }
}
