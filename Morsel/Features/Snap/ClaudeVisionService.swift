import Foundation

/// `MealVisionService` over the Claude Messages API using plain `URLSession`
/// (there is no official Anthropic Swift SDK). Direct mode sends the Keychain key;
/// proxy mode talks to the Cloudflare Worker in `server/claude-proxy`, which holds the key.
final class ClaudeVisionService: MealVisionService, @unchecked Sendable {
    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    // MARK: - MealVisionService

    func estimate(imageData: Data, hint: String?, previous: MealEstimate?) async throws -> MealEstimate {
        let request = try makeRequest(imageData: imageData, hint: hint, previous: previous)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ServiceError.network("Unexpected response from the server.")
            }
            return try ClaudeVisionCodec.parse(data: data, statusCode: http.statusCode)
        } catch {
            throw ClaudeVisionCodec.serviceError(from: error)
        }
    }

    // MARK: - Request assembly

    func makeRequest(imageData: Data, hint: String?, previous: MealEstimate?) throws -> URLRequest {
        let url = try endpoint()
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(ClaudeVisionCodec.anthropicVersion, forHTTPHeaderField: "anthropic-version")

        if settings.claudeEndpointMode == .direct {
            let key = (KeychainStore.shared.read(.claudeAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ServiceError.noAPIKey }
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        // Follow-up: send `x-morsel-token` here once a `.proxyToken` Keychain key + Settings field exist.

        request.httpBody = try ClaudeVisionCodec.requestBody(imageData: imageData, hint: hint, previous: previous)
        return request
    }

    private func endpoint() throws -> URL {
        switch settings.claudeEndpointMode {
        case .direct:
            guard let url = URL(string: ClaudeVisionCodec.directEndpointString) else {
                throw ServiceError.network("Invalid API endpoint.")
            }
            return url
        case .proxy:
            guard let base = settings.proxyURL else { throw ServiceError.noAPIKey }
            return base.appendingPathComponent("v1/messages")
        }
    }
}
