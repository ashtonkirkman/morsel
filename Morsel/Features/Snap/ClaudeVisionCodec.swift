import Foundation

/// Pure translation between Morsel types and the Claude Messages API wire format.
/// No networking lives here, so request bodies and response parsing are unit-testable byte for byte.
enum ClaudeVisionCodec {

    // MARK: - Constants

    static let model = "claude-opus-5"
    static let maxTokens = 4096
    static let anthropicVersion = "2023-06-01"
    static let directEndpointString = "https://api.anthropic.com/v1/messages"
    static let refusalMessage = "The model declined to analyze this image."

    /// Byte-stable so the `cache_control` breakpoint on it can hit the prompt cache.
    static let systemPrompt = """
    You are Morsel's nutrition estimator. You look at one photo of a meal and return a careful, structured estimate.

    Method:
    1. Identify each distinct food or drink on the plate. List components separately when they are visually separable (rice, chicken, sauce); keep a dish as one item only when its parts cannot be told apart (a smoothie, a casserole).
    2. Estimate each portion in a common household unit (cup, tablespoon, slice, piece, oz) and in grams. Use visual scale cues: a dinner plate is about 27 cm across, a fork is about 19 cm long, an adult palm is about 9 cm wide, a standard can holds 12 oz.
    3. Define ONE serving for each item (serving_description and serving_grams) and report nutrition for that single serving. Then set quantity to how many of those servings are visible. Use USDA-typical values for the food as prepared.
    4. Be conservative with cooking oil, butter, dressings and sauces: include them only when they are visible or clearly implied by the dish, and prefer modest amounts.
    5. Give a confidence from 0 to 1 for each item and for the whole plate. Lower it when food is partly hidden, mixed, or the portion is ambiguous.
    6. Ask at most ONE clarifying question, and only when the answer would change total calories by more than about 20 percent (for example "Is that whole milk or skim?" or "Is the dressing full-fat or light?"). Otherwise set clarifying_question to null.
    7. summary is a plain description of the plate in 12 words or fewer.

    If the user adds a note, treat it as ground truth about the plate. If a previous estimate is supplied, revise it in light of the note instead of starting over, keeping unaffected items unchanged. If the image does not show food, return an empty items list, overall_confidence 0 and a summary saying what you see instead.
    """

    // MARK: - Request

    /// Builds the JSON body for `POST /v1/messages`.
    static func requestBody(imageData: Data, hint: String?, previous: MealEstimate?) throws -> Data {
        let imageSource: [String: Any] = [
            "type": "base64",
            "media_type": "image/jpeg",
            "data": imageData.base64EncodedString()
        ]
        let imageBlock: [String: Any] = ["type": "image", "source": imageSource]
        let textBlock: [String: Any] = ["type": "text", "text": userText(hint: hint, previous: previous)]
        let systemBlock: [String: Any] = [
            "type": "text",
            "text": systemPrompt,
            "cache_control": ["type": "ephemeral"]
        ]
        let message: [String: Any] = ["role": "user", "content": [imageBlock, textBlock]]
        let format: [String: Any] = ["type": "json_schema", "schema": outputSchema]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [systemBlock],
            "messages": [message],
            "output_config": ["format": format]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The text block that accompanies the image: instruction, optional user hint, optional previous estimate.
    static func userText(hint: String?, previous: MealEstimate?) -> String {
        var parts = ["Estimate the nutrition of the meal in this photo."]
        if let hint = cleaned(hint) {
            parts.append("Note from the user: \"\(hint)\"")
        }
        if let previous {
            parts.append("""
            Your previous estimate for this same photo was:
            \(estimateJSONString(previous))
            Revise that estimate using the user's note. Change only what the note implies, keep everything else, and do not ask another clarifying question unless it is essential.
            """)
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Output schema

    /// Structured-output schema. Every object has `additionalProperties: false` and a full `required` list;
    /// no `minimum`/`maximum`/`minLength` (unsupported by the structured-output grammar).
    static var outputSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": "number"]
        let nullableString: [String: Any] = ["anyOf": [["type": "string"], ["type": "null"]]]
        let nullableNumber: [String: Any] = ["anyOf": [["type": "number"], ["type": "null"]]]

        let itemProperties: [String: Any] = [
            "name": describe(string, "Short food name, e.g. 'Grilled chicken breast'."),
            "brand": describe(nullableString, "Brand or restaurant when recognisable, else null."),
            "serving_description": describe(string, "One serving in household units, e.g. '1 cup (160 g)'."),
            "serving_grams": describe(nullableNumber, "Weight of one serving in grams, or null if unknown."),
            "quantity": describe(number, "How many servings are visible, e.g. 1.5."),
            "confidence": describe(number, "0 to 1 confidence for this item."),
            "rationale": describe(nullableString, "One sentence on the visual cues used, or null."),
            "calories": describe(number, "kcal per ONE serving."),
            "protein_g": describe(number, "Grams of protein per serving."),
            "carbs_g": describe(number, "Grams of carbohydrate per serving."),
            "fat_g": describe(number, "Grams of fat per serving."),
            "fiber_g": describe(nullableNumber, "Grams of fibre per serving, or null."),
            "sugar_g": describe(nullableNumber, "Grams of sugar per serving, or null."),
            "sodium_mg": describe(nullableNumber, "Milligrams of sodium per serving, or null.")
        ]
        let item: [String: Any] = [
            "type": "object",
            "properties": itemProperties,
            "required": itemRequiredKeys,
            "additionalProperties": false
        ]
        let itemsArray: [String: Any] = ["type": "array", "items": item]
        let rootProperties: [String: Any] = [
            "summary": describe(string, "Plate description in 12 words or fewer."),
            "overall_confidence": describe(number, "0 to 1 confidence for the whole estimate."),
            "clarifying_question": describe(nullableString, "One question that would change calories by more than 20 percent, else null."),
            "items": itemsArray
        ]
        return [
            "type": "object",
            "properties": rootProperties,
            "required": rootRequiredKeys,
            "additionalProperties": false
        ]
    }

    static let itemRequiredKeys = [
        "name", "brand", "serving_description", "serving_grams", "quantity", "confidence", "rationale",
        "calories", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g", "sodium_mg"
    ]
    static let rootRequiredKeys = ["summary", "overall_confidence", "clarifying_question", "items"]

    private static func describe(_ base: [String: Any], _ description: String) -> [String: Any] {
        var copy = base
        copy["description"] = description
        return copy
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

        let envelope: MessageResponse
        do {
            envelope = try decoder.decode(MessageResponse.self, from: data)
        } catch {
            throw ServiceError.decoding("Unreadable response envelope")
        }

        if envelope.stopReason == "refusal" {
            throw ServiceError.server(status: 200, message: refusalMessage)
        }
        if envelope.stopReason == "max_tokens" {
            throw ServiceError.decoding("Response was cut off")
        }
        guard let text = envelope.content.first(where: { $0.type == "text" })?.text else {
            throw ServiceError.decoding("No text block in response")
        }

        let payload: EstimatePayload
        do {
            payload = try decoder.decode(EstimatePayload.self, from: Data(text.utf8))
        } catch {
            throw ServiceError.decoding("Estimate JSON did not match the schema")
        }
        return payload.mealEstimate
    }

    /// `error.message` from an Anthropic error body, if present.
    static func errorMessage(in data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else { return nil }
        return cleaned(envelope.error?.message)
    }

    /// Normalises any thrown error into a `ServiceError` for the UI.
    static func serviceError(from error: Error) -> ServiceError {
        if let service = error as? ServiceError { return service }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .network(urlError.localizedDescription)
        }
        return .network(error.localizedDescription)
    }

    // MARK: - Previous estimate → JSON (same shape the model must output)

    static func estimateJSONObject(_ estimate: MealEstimate) -> [String: Any] {
        let items: [[String: Any]] = estimate.items.map { item in
            let n = item.food.nutritionPerServing
            return [
                "name": item.food.name,
                "brand": orNull(item.food.brand),
                "serving_description": item.food.servingDescription,
                "serving_grams": orNull(item.food.servingGrams),
                "quantity": item.quantity,
                "confidence": item.confidence,
                "rationale": orNull(item.rationale),
                "calories": n.calories,
                "protein_g": n.protein,
                "carbs_g": n.carbs,
                "fat_g": n.fat,
                "fiber_g": orNull(n.fiber),
                "sugar_g": orNull(n.sugar),
                "sodium_mg": orNull(n.sodium)
            ]
        }
        return [
            "summary": estimate.summary,
            "overall_confidence": estimate.overallConfidence,
            "clarifying_question": orNull(estimate.clarifyingQuestion),
            "items": items
        ]
    }

    static func estimateJSONString(_ estimate: MealEstimate) -> String {
        let object = estimateJSONObject(estimate)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    // MARK: - Helpers

    static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func nonNegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func orNull(_ value: Any?) -> Any {
        value ?? NSNull()
    }
}

// MARK: - Wire types

extension ClaudeVisionCodec {
    struct MessageResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        let content: [ContentBlock]
        let stopReason: String?
    }

    struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let type: String?
            let message: String?
        }
        let error: Detail?
    }

    struct EstimatePayload: Decodable {
        let summary: String
        let overallConfidence: Double
        let clarifyingQuestion: String?
        let items: [ItemPayload]

        var mealEstimate: MealEstimate {
            MealEstimate(items: items.map(\.estimatedItem),
                         summary: ClaudeVisionCodec.cleaned(summary) ?? "Meal",
                         overallConfidence: ClaudeVisionCodec.clamp01(overallConfidence),
                         clarifyingQuestion: ClaudeVisionCodec.cleaned(clarifyingQuestion))
        }
    }

    struct ItemPayload: Decodable {
        let name: String
        let brand: String?
        let servingDescription: String
        let servingGrams: Double?
        let quantity: Double
        let confidence: Double
        let rationale: String?
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double?
        let sugarG: Double?
        let sodiumMg: Double?

        var estimatedItem: EstimatedFoodItem {
            let facts = NutritionFacts(calories: ClaudeVisionCodec.nonNegative(calories),
                                       protein: ClaudeVisionCodec.nonNegative(proteinG),
                                       carbs: ClaudeVisionCodec.nonNegative(carbsG),
                                       fat: ClaudeVisionCodec.nonNegative(fatG),
                                       fiber: fiberG.map(ClaudeVisionCodec.nonNegative),
                                       sugar: sugarG.map(ClaudeVisionCodec.nonNegative),
                                       sodium: sodiumMg.map(ClaudeVisionCodec.nonNegative))
            let grams = servingGrams.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let food = FoodItem(name: ClaudeVisionCodec.cleaned(name) ?? "Food",
                                brand: ClaudeVisionCodec.cleaned(brand),
                                servingDescription: ClaudeVisionCodec.cleaned(servingDescription) ?? "1 serving",
                                servingGrams: grams,
                                nutritionPerServing: facts,
                                source: .photo)
            let safeQuantity = quantity.isFinite && quantity > 0 ? quantity : 1
            return EstimatedFoodItem(food: food,
                                     quantity: safeQuantity,
                                     confidence: ClaudeVisionCodec.clamp01(confidence),
                                     rationale: ClaudeVisionCodec.cleaned(rationale))
        }
    }
}
