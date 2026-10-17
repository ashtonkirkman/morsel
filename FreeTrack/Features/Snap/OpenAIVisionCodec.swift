import Foundation

/// Pure translation between Free Track types and the OpenAI Responses API wire format.
/// The prompt, output schema and estimate mapping are shared with `ClaudeVisionCodec`, which stays in the
/// tree as the alternative backend; only the envelope differs. No networking lives here.
enum OpenAIVisionCodec {

    // MARK: - Constants

    static let model = "gpt-6-luna"
    static let maxOutputTokens = 4096
    /// `none` / `low` / `medium` / `high`. Low keeps replies fast and cheap; raise it if portions come back sloppy.
    static let reasoningEffort = "low"
    static let directEndpointString = "https://api.openai.com/v1/responses"
    static let refusalMessage = ClaudeVisionCodec.refusalMessage
    static let schemaName = "meal_estimate"

    // MARK: - Request

    /// Builds the JSON body for `POST /v1/responses`.
    static func requestBody(imageData: Data, hint: String?, previous: MealEstimate?) throws -> Data {
        let imageBlock: [String: Any] = [
            "type": "input_image",
            "image_url": "data:image/jpeg;base64," + imageData.base64EncodedString(),
            "detail": "high"
        ]
        let textBlock: [String: Any] = [
            "type": "input_text",
            "text": ClaudeVisionCodec.userText(hint: hint, previous: previous)
        ]
        let message: [String: Any] = ["role": "user", "content": [imageBlock, textBlock]]
        let format: [String: Any] = [
            "type": "json_schema",
            "name": schemaName,
            "strict": true,
            "schema": ClaudeVisionCodec.outputSchema
        ]
        let body: [String: Any] = [
            "model": model,
            "instructions": ClaudeVisionCodec.systemPrompt,
            "input": [message],
            "text": ["format": format],
            "reasoning": ["effort": reasoningEffort],
            "max_output_tokens": maxOutputTokens,
            "store": false
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    // MARK: - Response

    /// Turns an HTTP status + body into a `MealEstimate`, or throws the matching `ServiceError`.
    static func parse(data: Data, statusCode: Int) throws -> MealEstimate {
        switch statusCode {
        case 200..<300:
            break
        case 401:
            throw ServiceError.unauthorized
        case 429:
            throw ServiceError.rateLimited
        default:
            throw ServiceError.server(status: statusCode, message: errorMessage(in: data) ?? "Unexpected response.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let envelope: ResponseEnvelope
        do {
            envelope = try decoder.decode(ResponseEnvelope.self, from: data)
        } catch {
            throw ServiceError.decoding("Unreadable response envelope")
        }

        if envelope.status == "failed" {
            throw ServiceError.server(status: 200, message: envelope.error?.message ?? "The model failed to respond.")
        }
        if envelope.status == "incomplete" {
            if envelope.incompleteDetails?.reason == "max_output_tokens" {
                throw ServiceError.decoding("Response was cut off")
            }
            throw ServiceError.server(status: 200, message: refusalMessage)
        }

        let parts = envelope.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if parts.contains(where: { $0.type == "refusal" }) {
            throw ServiceError.server(status: 200, message: refusalMessage)
        }
        guard let text = parts.first(where: { $0.type == "output_text" })?.text else {
            throw ServiceError.decoding("No text in response")
        }

        let payload: ClaudeVisionCodec.EstimatePayload
        do {
            payload = try decoder.decode(ClaudeVisionCodec.EstimatePayload.self, from: Data(text.utf8))
        } catch {
            throw ServiceError.decoding("Estimate JSON did not match the schema")
        }
        return payload.mealEstimate
    }

    /// `error.message` from an OpenAI (or proxy) error body, if present.
    static func errorMessage(in data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(ClaudeVisionCodec.ErrorEnvelope.self, from: data) else { return nil }
        return ClaudeVisionCodec.cleaned(envelope.error?.message)
    }

    /// Normalises any thrown error into a `ServiceError` for the UI.
    static func serviceError(from error: Error) -> ServiceError {
        ClaudeVisionCodec.serviceError(from: error)
    }
}

// MARK: - Wire types

extension OpenAIVisionCodec {
    struct ResponseEnvelope: Decodable {
        struct OutputItem: Decodable {
            struct Part: Decodable {
                let type: String
                let text: String?
                let refusal: String?
            }
            let type: String
            let content: [Part]?
        }
        struct IncompleteDetails: Decodable {
            let reason: String?
        }
        struct ErrorDetail: Decodable {
            let message: String?
        }
        let status: String?
        let output: [OutputItem]
        let incompleteDetails: IncompleteDetails?
        let error: ErrorDetail?
    }
}
