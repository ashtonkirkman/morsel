import XCTest
@testable import Morsel

final class SnapCodecTests: XCTestCase {

    // MARK: - Request

    func testRequestBodyShape() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let body = try ClaudeVisionCodec.requestBody(imageData: image, hint: "half portion", previous: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "claude-opus-5")
        XCTAssertEqual(json["max_tokens"] as? Int, 4096)
        XCTAssertNil(json["thinking"], "Thinking is on by default for this model; the field must not be sent")

        let system = try XCTUnwrap(json["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 1)
        XCTAssertEqual(system[0]["text"] as? String, ClaudeVisionCodec.systemPrompt)
        let cacheControl = try XCTUnwrap(system[0]["cache_control"] as? [String: Any])
        XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        XCTAssertEqual(content[0]["type"] as? String, "image")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, image.base64EncodedString())

        XCTAssertEqual(content[1]["type"] as? String, "text")
        let text = try XCTUnwrap(content[1]["text"] as? String)
        XCTAssertTrue(text.contains("half portion"))
        XCTAssertFalse(text.contains("previous estimate"), "No revision instruction without a previous estimate")

        let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    func testRequestIncludesPreviousEstimateForRevision() throws {
        let previous = MealEstimate(items: [Self.item(name: "Latte", calories: 190)],
                                    summary: "Latte",
                                    overallConfidence: 0.6,
                                    clarifyingQuestion: "Whole milk or skim?")
        let body = try ClaudeVisionCodec.requestBody(imageData: Data([0x01]), hint: "skim", previous: previous)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content[1]["text"] as? String)
        XCTAssertTrue(text.contains("\"skim\""))
        XCTAssertTrue(text.contains("\"name\":\"Latte\""))
        XCTAssertTrue(text.contains("Revise that estimate"))
    }

    func testSchemaRequiredListsEveryProperty() throws {
        let root = ClaudeVisionCodec.outputSchema
        let rootProperties = try XCTUnwrap(root["properties"] as? [String: Any])
        XCTAssertEqual(Set(rootProperties.keys), Set(ClaudeVisionCodec.rootRequiredKeys))
        XCTAssertEqual(root["additionalProperties"] as? Bool, false)

        let items = try XCTUnwrap(rootProperties["items"] as? [String: Any])
        let item = try XCTUnwrap(items["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertEqual(Set(itemProperties.keys), Set(ClaudeVisionCodec.itemRequiredKeys))
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
    }

    // MARK: - Response

    func testParsesSuccessWithLeadingNonTextBlock() throws {
        let chicken: [String: Any] = [
            "name": "Grilled chicken breast", "brand": NSNull(),
            "serving_description": "1 breast (120 g)", "serving_grams": 120,
            "quantity": 1, "confidence": 0.9, "rationale": "About the size of a palm.",
            "calories": 300, "protein_g": 40, "carbs_g": 0, "fat_g": 8,
            "fiber_g": NSNull(), "sugar_g": NSNull(), "sodium_mg": 120
        ]
        let rice: [String: Any] = [
            "name": "White rice", "brand": NSNull(),
            "serving_description": "1/2 cup cooked (80 g)", "serving_grams": 80,
            "quantity": 2, "confidence": 0.7, "rationale": NSNull(),
            "calories": 100, "protein_g": 2, "carbs_g": 22, "fat_g": 0.2,
            "fiber_g": 0.3, "sugar_g": 0, "sodium_mg": NSNull()
        ]
        let payload: [String: Any] = [
            "summary": "Grilled chicken with rice",
            "overall_confidence": 1.4,
            "clarifying_question": NSNull(),
            "items": [chicken, rice]
        ]
        let data = try Self.responseData(payload: payload, stopReason: "end_turn")

        let estimate = try ClaudeVisionCodec.parse(data: data, statusCode: 200)

        XCTAssertEqual(estimate.items.count, 2)
        XCTAssertEqual(estimate.summary, "Grilled chicken with rice")
        XCTAssertEqual(estimate.overallConfidence, 1.0, "Confidence is clamped to 0…1")
        XCTAssertNil(estimate.clarifyingQuestion)
        XCTAssertEqual(estimate.items[0].food.source, .photo)
        XCTAssertEqual(estimate.items[0].food.nutritionPerServing.sodium, 120)
        XCTAssertNil(estimate.items[0].food.brand)
        XCTAssertEqual(estimate.items[1].quantity, 2)
        XCTAssertEqual(estimate.total.calories, 500, accuracy: 0.001)
        XCTAssertEqual(estimate.total.protein, 44, accuracy: 0.001)
        XCTAssertEqual(estimate.total.carbs, 44, accuracy: 0.001)
        XCTAssertEqual(estimate.total.fat, 8.4, accuracy: 0.001)
    }

    func testRefusalBecomesFriendlyServerError() throws {
        let data = Data("""
        {"id":"msg_1","type":"message","role":"assistant","content":[],"stop_reason":"refusal","model":"claude-opus-5"}
        """.utf8)
        XCTAssertThrowsError(try ClaudeVisionCodec.parse(data: data, statusCode: 200)) { error in
            XCTAssertEqual(error as? ServiceError,
                           .server(status: 200, message: "The model declined to analyze this image."))
        }
    }

    func testMaxTokensBecomesDecodingError() throws {
        let data = Data("""
        {"content":[{"type":"text","text":"{\\"summary\\":\\"cut"}],"stop_reason":"max_tokens"}
        """.utf8)
        XCTAssertThrowsError(try ClaudeVisionCodec.parse(data: data, statusCode: 200)) { error in
            XCTAssertEqual(error as? ServiceError, .decoding("Response was cut off"))
        }
    }

    func testRateLimitStatus() {
        let data = Data("""
        {"type":"error","error":{"type":"rate_limit_error","message":"Slow down"}}
        """.utf8)
        XCTAssertThrowsError(try ClaudeVisionCodec.parse(data: data, statusCode: 429)) { error in
            XCTAssertEqual(error as? ServiceError, .rateLimited)
        }
    }

    func testUnauthorizedAndServerStatuses() {
        XCTAssertThrowsError(try ClaudeVisionCodec.parse(data: Data(), statusCode: 401)) { error in
            XCTAssertEqual(error as? ServiceError, .unauthorized)
        }
        let body = Data("""
        {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
        """.utf8)
        XCTAssertThrowsError(try ClaudeVisionCodec.parse(data: body, statusCode: 529)) { error in
            XCTAssertEqual(error as? ServiceError, .server(status: 529, message: "Overloaded"))
        }
    }

    func testURLErrorMapping() {
        XCTAssertEqual(ClaudeVisionCodec.serviceError(from: URLError(.cancelled)), .cancelled)
        XCTAssertEqual(ClaudeVisionCodec.serviceError(from: CancellationError()), .cancelled)
        if case .network = ClaudeVisionCodec.serviceError(from: URLError(.notConnectedToInternet)) {
            // expected
        } else {
            XCTFail("URLError should map to .network")
        }
    }

    // MARK: - Fixtures

    private static func responseData(payload: [String: Any], stopReason: String) throws -> Data {
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let text = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        let envelope: [String: Any] = [
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "model": "claude-opus-5",
            "stop_reason": stopReason,
            "content": [
                ["type": "thinking", "thinking": "", "signature": "abc"],
                ["type": "text", "text": text]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private static func item(name: String, calories: Double) -> EstimatedFoodItem {
        EstimatedFoodItem(food: FoodItem(name: name,
                                         servingDescription: "1 cup",
                                         nutritionPerServing: NutritionFacts(calories: calories),
                                         source: .photo),
                          quantity: 1,
                          confidence: 0.6)
    }
}
