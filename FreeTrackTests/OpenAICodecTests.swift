import XCTest
@testable import FreeTrack

final class OpenAICodecTests: XCTestCase {

    // MARK: - Request

    func testRequestBodyShape() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let body = try OpenAIVisionCodec.requestBody(imageData: image, hint: "half portion", previous: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(json["max_output_tokens"] as? Int, 4096)
        XCTAssertEqual(json["store"] as? Bool, false, "Photos must not be retained as stored responses")
        XCTAssertEqual(json["instructions"] as? String, ClaudeVisionCodec.systemPrompt)
        let reasoning = try XCTUnwrap(json["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "low")

        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input[0]["role"] as? String, "user")
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        XCTAssertEqual(content[0]["type"] as? String, "input_image")
        XCTAssertEqual(content[0]["image_url"] as? String, "data:image/jpeg;base64," + image.base64EncodedString())
        XCTAssertEqual(content[0]["detail"] as? String, "high")

        XCTAssertEqual(content[1]["type"] as? String, "input_text")
        let text = try XCTUnwrap(content[1]["text"] as? String)
        XCTAssertTrue(text.contains("half portion"))
        XCTAssertFalse(text.contains("previous estimate"), "No revision instruction without a previous estimate")

        let textConfig = try XCTUnwrap(json["text"] as? [String: Any])
        let format = try XCTUnwrap(textConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "meal_estimate")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertNil(json["stream"])
    }

    func testRequestIncludesPreviousEstimateForRevision() throws {
        let previous = MealEstimate(items: [Self.item(name: "Latte", calories: 190)],
                                    summary: "Latte",
                                    overallConfidence: 0.6,
                                    clarifyingQuestion: "Whole milk or skim?")
        let body = try OpenAIVisionCodec.requestBody(imageData: Data([0x01]), hint: "skim", previous: previous)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content[1]["text"] as? String)
        XCTAssertTrue(text.contains("\"skim\""))
        XCTAssertTrue(text.contains("\"name\":\"Latte\""))
        XCTAssertTrue(text.contains("Revise that estimate"))
    }

    // MARK: - Response

    func testParsesCompletedResponseSkippingReasoningItem() throws {
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
        let data = try Self.responseData(payload: payload)

        let estimate = try OpenAIVisionCodec.parse(data: data, statusCode: 200)

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
        {"id":"resp_1","object":"response","status":"completed","output":[
          {"type":"message","role":"assistant","status":"completed","content":[{"type":"refusal","refusal":"I can't help with that."}]}
        ]}
        """.utf8)
        XCTAssertThrowsError(try OpenAIVisionCodec.parse(data: data, statusCode: 200)) { error in
            XCTAssertEqual(error as? ServiceError,
                           .server(status: 200, message: "The model declined to analyze this image."))
        }
    }

    func testMaxOutputTokensBecomesDecodingError() throws {
        let data = Data("""
        {"id":"resp_1","object":"response","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},
         "output":[{"type":"message","role":"assistant","status":"incomplete","content":[{"type":"output_text","text":"{\\"summary\\":\\"cut"}]}]}
        """.utf8)
        XCTAssertThrowsError(try OpenAIVisionCodec.parse(data: data, statusCode: 200)) { error in
            XCTAssertEqual(error as? ServiceError, .decoding("Response was cut off"))
        }
    }

    func testFailedStatusSurfacesModelError() throws {
        let data = Data("""
        {"id":"resp_1","object":"response","status":"failed","error":{"code":"server_error","message":"Upstream hiccup"},"output":[]}
        """.utf8)
        XCTAssertThrowsError(try OpenAIVisionCodec.parse(data: data, statusCode: 200)) { error in
            XCTAssertEqual(error as? ServiceError, .server(status: 200, message: "Upstream hiccup"))
        }
    }

    func testRateLimitStatus() {
        let data = Data("""
        {"error":{"type":"rate_limit_error","message":"Slow down","code":null,"param":null}}
        """.utf8)
        XCTAssertThrowsError(try OpenAIVisionCodec.parse(data: data, statusCode: 429)) { error in
            XCTAssertEqual(error as? ServiceError, .rateLimited)
        }
    }

    func testUnauthorizedAndServerStatuses() {
        XCTAssertThrowsError(try OpenAIVisionCodec.parse(data: Data(), statusCode: 401)) { error in
            XCTAssertEqual(error as? ServiceError, .unauthorized)
        }
        let body = Data("""
        {"error":{"type":"server_error","message":"Overloaded","code":null,"param":null}}
        """.utf8)
        XCTAssertThrowsError(try OpenAIVisionCodec.parse(data: body, statusCode: 503)) { error in
            XCTAssertEqual(error as? ServiceError, .server(status: 503, message: "Overloaded"))
        }
    }

    // MARK: - Fixtures

    private static func responseData(payload: [String: Any]) throws -> Data {
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let text = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        let envelope: [String: Any] = [
            "id": "resp_1",
            "object": "response",
            "status": "completed",
            "model": "gpt-6-luna",
            "output": [
                ["type": "reasoning", "id": "rs_1", "summary": []],
                ["type": "message", "id": "msg_1", "role": "assistant", "status": "completed",
                 "content": [["type": "output_text", "text": text, "annotations": []]]]
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
