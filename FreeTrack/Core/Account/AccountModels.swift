import Foundation

/// Identity providers the account API supports.
enum AuthProvider: String, CaseIterable, Identifiable, Codable {
    case apple, google, facebook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .facebook: return "Facebook"
        }
    }
}

/// The signed-in user as returned by `GET /v1/me` and inside every session bundle.
struct AccountUser: Codable, Equatable, Hashable {
    var id: String
    var displayName: String?
    var email: String?
    var avatarUrl: String?
    var createdAt: Double?
    var providers: [String]?

    /// "Ashton Kirkman" -> "AK"; falls back to the first letter of the email, then "?".
    var initials: String {
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        if !letters.isEmpty { return letters.joined() }
        if let first = email?.first { return String(first).uppercased() }
        return "?"
    }

    /// Something to show as the primary line.
    var primaryLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return "Signed in"
    }
}

/// Tokens issued by the Worker. Timestamps are Unix milliseconds.
struct SessionBundle: Codable, Equatable {
    var accessToken: String
    var accessExpiresAt: Double
    var refreshToken: String
    var refreshExpiresAt: Double
    var user: AccountUser
}

/// One synced document on the wire. `json` is the Codable payload as a JSON string; tombstones
/// carry `deleted == true` and no meaningful `json`. `updatedAt` is Unix milliseconds.
struct SyncDocument: Codable, Equatable {
    var id: String
    var json: String?
    var updatedAt: Double
    var deleted: Bool

    init(id: String, json: String?, updatedAt: Double, deleted: Bool = false) {
        self.id = id
        self.json = json
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    init(id: String, json: String?, updatedAt: Date, deleted: Bool = false) {
        self.init(id: id, json: json, updatedAt: updatedAt.timeIntervalSince1970 * 1000, deleted: deleted)
    }

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }

    private enum CodingKeys: String, CodingKey { case id, json, updatedAt, deleted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        json = try c.decodeIfPresent(String.self, forKey: .json)
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(deleted ? nil : json, forKey: .json)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deleted, forKey: .deleted)
    }
}

struct SyncPullResponse: Codable {
    var collection: String
    var documents: [SyncDocument]
    var serverTime: Double
}

struct SyncPushResponse: Codable {
    var accepted: Int
    var serverTime: Double
}

enum AccountError: LocalizedError, Equatable {
    case notConfigured
    case providerNotConfigured(AuthProvider)
    case cancelled
    case invalidCallback
    case stateMismatch
    case sessionExpired
    case network(String)
    case decoding
    case rateLimited
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Accounts aren't set up on this build yet (no server URL)."
        case .providerNotConfigured(let p): return "\(p.title) sign-in isn't enabled on the server."
        case .cancelled: return "Cancelled."
        case .invalidCallback: return "The sign-in didn't complete. Please try again."
        case .stateMismatch: return "The sign-in response didn't match this request. Please try again."
        case .sessionExpired: return "Your session expired. Please sign in again."
        case .network(let detail): return "Network problem. \(detail)"
        case .decoding: return "The server reply wasn't in a form we understood."
        case .rateLimited: return "Too many attempts right now. Try again in a minute."
        case .server(let status, let message): return "Server error \(status). \(message)"
        }
    }
}

/// Read-only peek into a JWT's payload (no verification; the server verifies).
enum JWTClaims {
    static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    static func expiry(of token: String) -> Date? {
        guard let exp = payload(of: token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
