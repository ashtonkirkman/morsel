import Foundation

/// `MealVisionService` over the OpenAI Responses API using plain `URLSession`.
/// Direct mode sends the Keychain key as a bearer token; proxy mode talks to the Cloudflare Worker in
/// `server/ai-proxy`, which holds the key.
final class OpenAIVisionService: MealVisionService, @unchecked Sendable {
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
            return try OpenAIVisionCodec.parse(data: data, statusCode: http.statusCode)
        } catch {
            throw OpenAIVisionCodec.serviceError(from: error)
        }
    }

    // MARK: - Request assembly

    func makeRequest(imageData: Data, hint: String?, previous: MealEstimate?) throws -> URLRequest {
        let url = try endpoint()
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        if settings.visionEndpointMode == .direct {
            let key = (KeychainStore.shared.read(.openAIAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ServiceError.noAPIKey }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        }
        if settings.visionEndpointMode == .proxy {
            let token = (KeychainStore.shared.read(.proxyToken) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "x-morsel-token") }
        }

        request.httpBody = try OpenAIVisionCodec.requestBody(imageData: imageData, hint: hint, previous: previous)
        return request
    }

    private func endpoint() throws -> URL {
        switch settings.visionEndpointMode {
        case .direct:
            guard let url = URL(string: OpenAIVisionCodec.directEndpointString) else {
                throw ServiceError.network("Invalid API endpoint.")
            }
            return url
        case .proxy:
            guard let base = settings.proxyURL else { throw ServiceError.noAPIKey }
            return base.appendingPathComponent("v1/responses")
        }
    }
}
