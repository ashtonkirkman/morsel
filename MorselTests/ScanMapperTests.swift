import XCTest
@testable import Morsel

/// Pure mapping tests for Open Food Facts JSON → FoodItem. No network.
final class ScanMapperTests: XCTestCase {

    // MARK: Fixtures

    private enum Fixtures {
        /// Typical US product: serving_quantity present, per-serving nutriments, numbers as numbers.
        static let perServing = """
        {
          "code": "0012345678905",
          "status": 1,
          "status_verbose": "product found",
          "product": {
            "code": "0012345678905",
            "product_name": "Crunchy Peanut Butter",
            "brands": "Nutty Co, Some Parent Brand",
            "serving_size": "2 tbsp (32 g)",
            "serving_quantity": 32,
            "quantity": "454 g",
            "image_front_small_url": "https://images.openfoodfacts.org/images/products/001/234/567/8905/front_en.4.200.jpg",
            "nutriments": {
              "energy-kcal_100g": 588,
              "energy-kcal_serving": 188,
              "energy_100g": 2460,
              "energy_serving": 787,
              "energy_unit": "kcal",
              "proteins_100g": 25,
              "proteins_serving": 8,
              "carbohydrates_100g": 20,
              "carbohydrates_serving": 6.4,
              "fat_100g": 50,
              "fat_serving": 16,
              "fiber_100g": 6,
              "fiber_serving": 1.9,
              "sugars_100g": 9.4,
              "sugars_serving": 3,
              "salt_100g": 0.42,
              "salt_serving": 0.13,
              "sodium_100g": 0.168,
              "sodium_serving": 0.054,
              "nova-group": 4
            }
          }
        }
        """

        /// EU-style product: no serving info, kJ-only energy, every number encoded as a string.
        static let per100gKilojoules = """
        {
          "code": "4001234567890",
          "status": 1,
          "status_verbose": "product found",
          "product": {
            "code": "4001234567890",
            "product_name": "  Rye Bread ",
            "brands": "",
            "serving_size": "",
            "serving_quantity": "",
            "nutriments": {
              "energy_100g": "1046",
              "energy_unit": "kJ",
              "proteins_100g": "8.5",
              "carbohydrates_100g": "45",
              "fat_100g": "1.2",
              "fiber_100g": "6",
              "salt_100g": "1.1"
            }
          }
        }
        """

        /// Unknown barcode.
        static let notFound = """
        { "code": "0000000000000", "status": 0, "status_verbose": "product not found" }
        """

        /// serving_quantity given but no `_serving` nutriments → scale the `_100g` values.
        static let servingQuantityOnly = """
        {
          "code": "5001234567890",
          "status": 1,
          "product": {
            "code": "5001234567890",
            "product_name": "Oat Bar",
            "serving_size": "1 bar (50 g)",
            "serving_quantity": "50",
            "nutriments": {
              "energy-kcal_100g": 400,
              "proteins_100g": 10,
              "carbohydrates_100g": 60,
              "fat_100g": 12
            }
          }
        }
        """

        /// Search page with one good product, one nameless, one without energy, one blank-named.
        static let search = """
        {
          "count": 4,
          "page": 1,
          "page_size": 25,
          "products": [
            {
              "code": "1111111111111",
              "product_name": "Oat Milk",
              "brands": "Oatly",
              "nutriments": { "energy-kcal_100g": 46, "proteins_100g": 1, "carbohydrates_100g": 6.6, "fat_100g": 1.5 }
            },
            {
              "code": "2222222222222",
              "product_name": "",
              "nutriments": { "energy-kcal_100g": 100 }
            },
            {
              "code": "3333333333333",
              "product_name": "Mystery Snack",
              "nutriments": { "proteins_100g": 5 }
            },
            {
              "code": "4444444444444",
              "product_name": "   ",
              "nutriments": { "energy_100g": 500 }
            }
          ]
        }
        """
    }

    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: Lookup mapping

    func testPerServingProductUsesServingFields() throws {
        let food = try XCTUnwrap(OpenFoodFactsMapper.mapLookupResponse(data: data(Fixtures.perServing),
                                                                        barcode: "0012345678905"))
        XCTAssertEqual(food.name, "Crunchy Peanut Butter")
        XCTAssertEqual(food.brand, "Nutty Co")
        XCTAssertEqual(food.barcode, "0012345678905")
        XCTAssertEqual(food.source, .barcode)
        XCTAssertEqual(food.servingDescription, "2 tbsp (32 g)")
        XCTAssertEqual(food.servingGrams, 32)
        XCTAssertEqual(food.imageURL?.absoluteString,
                       "https://images.openfoodfacts.org/images/products/001/234/567/8905/front_en.4.200.jpg")

        let n = food.nutritionPerServing
        XCTAssertEqual(n.calories, 188, accuracy: 0.001)
        XCTAssertEqual(n.protein, 8, accuracy: 0.001)
        XCTAssertEqual(n.carbs, 6.4, accuracy: 0.001)
        XCTAssertEqual(n.fat, 16, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(n.fiber), 1.9, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(n.sugar), 3, accuracy: 0.001)
        // sodium_serving is grams → 54 mg (preferred over salt × 400 = 52 mg)
        XCTAssertEqual(try XCTUnwrap(n.sodium), 54, accuracy: 0.001)
    }

    func testPer100gOnlyProductConvertsKilojoulesAndStringNumbers() throws {
        let food = try XCTUnwrap(OpenFoodFactsMapper.mapLookupResponse(data: data(Fixtures.per100gKilojoules),
                                                                        barcode: "4001234567890"))
        XCTAssertEqual(food.name, "Rye Bread")
        XCTAssertNil(food.brand)
        XCTAssertEqual(food.barcode, "4001234567890")
        XCTAssertEqual(food.servingDescription, "100 g")
        XCTAssertEqual(food.servingGrams, 100)
        XCTAssertNil(food.imageURL)

        let n = food.nutritionPerServing
        XCTAssertEqual(n.calories, 1046 / 4.184, accuracy: 0.001)   // ≈ 250 kcal
        XCTAssertEqual(n.calories, 250, accuracy: 0.01)
        XCTAssertEqual(n.protein, 8.5, accuracy: 0.001)
        XCTAssertEqual(n.carbs, 45, accuracy: 0.001)
        XCTAssertEqual(n.fat, 1.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(n.fiber), 6, accuracy: 0.001)
        XCTAssertNil(n.sugar)
        // salt 1.1 g → sodium 440 mg
        XCTAssertEqual(try XCTUnwrap(n.sodium), 440, accuracy: 0.001)
    }

    func testStatusZeroReturnsNil() throws {
        let food = try OpenFoodFactsMapper.mapLookupResponse(data: data(Fixtures.notFound), barcode: "0000000000000")
        XCTAssertNil(food)
    }

    func testMissingProductObjectReturnsNil() throws {
        let food = try OpenFoodFactsMapper.mapLookupResponse(data: data("{\"code\":\"1\",\"status\":1}"), barcode: "1")
        XCTAssertNil(food)
    }

    func testServingQuantityWithoutServingFieldsScalesPer100g() throws {
        let food = try XCTUnwrap(OpenFoodFactsMapper.mapLookupResponse(data: data(Fixtures.servingQuantityOnly),
                                                                        barcode: "5001234567890"))
        XCTAssertEqual(food.servingDescription, "1 bar (50 g)")
        XCTAssertEqual(food.servingGrams, 50)
        XCTAssertEqual(food.nutritionPerServing.calories, 200, accuracy: 0.001)
        XCTAssertEqual(food.nutritionPerServing.protein, 5, accuracy: 0.001)
        XCTAssertEqual(food.nutritionPerServing.carbs, 30, accuracy: 0.001)
        XCTAssertEqual(food.nutritionPerServing.fat, 6, accuracy: 0.001)
    }

    func testMalformedJSONThrowsDecodingError() {
        XCTAssertThrowsError(try OpenFoodFactsMapper.mapLookupResponse(data: data("not json"), barcode: "1")) { error in
            guard case ServiceError.decoding = error else {
                return XCTFail("Expected ServiceError.decoding, got \(error)")
            }
        }
    }

    // MARK: Search mapping

    func testSearchDropsProductsWithoutNameOrEnergy() throws {
        let items = try OpenFoodFactsMapper.mapSearchResponse(data: data(Fixtures.search))
        XCTAssertEqual(items.count, 1)
        let oatMilk = try XCTUnwrap(items.first)
        XCTAssertEqual(oatMilk.name, "Oat Milk")
        XCTAssertEqual(oatMilk.brand, "Oatly")
        XCTAssertEqual(oatMilk.barcode, "1111111111111")
        XCTAssertEqual(oatMilk.source, .search)
        XCTAssertEqual(oatMilk.servingDescription, "100 g")
        XCTAssertEqual(oatMilk.nutritionPerServing.calories, 46, accuracy: 0.001)
    }

    func testSearchWithoutProductsArrayIsEmpty() throws {
        let items = try OpenFoodFactsMapper.mapSearchResponse(data: data("{\"count\": 0}"))
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: Lenient scalars

    func testLenientDoubleAcceptsNumbersStringsAndJunk() throws {
        let decoded = try JSONDecoder().decode([LenientDouble].self,
                                               from: data("[1, \"2.5\", \"3,5\", \"30 g\", null, \"abc\", true, {\"a\":1}]"))
        XCTAssertEqual(decoded.map(\.value), [1, 2.5, 3.5, 30, nil, nil, nil, nil])
    }

    func testPrimaryBrandTakesFirstNonEmptyEntry() {
        XCTAssertEqual(OpenFoodFactsMapper.primaryBrand(" , Acme, Other"), "Acme")
        XCTAssertNil(OpenFoodFactsMapper.primaryBrand(" , "))
        XCTAssertNil(OpenFoodFactsMapper.primaryBrand(nil))
    }
}
