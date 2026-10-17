import XCTest
@testable import FreeTrack

/// Offline whole-food table: matching, ordering and serving math.
final class BasicFoodCatalogTests: XCTestCase {

    func testExactNameComesFirst() {
        let names = BasicFoodCatalog.matches("banana").map(\.name)
        XCTAssertEqual(names.first, "Banana")
    }

    func testCaseAndWhitespaceAreIgnored() {
        XCTAssertEqual(BasicFoodCatalog.matches("  BaNaNa ").first?.name, "Banana")
    }

    func testPrefixOfAWordMatches() {
        XCTAssertEqual(BasicFoodCatalog.matches("blueb").first?.name, "Blueberries")
    }

    func testAliasMatchesButRanksBelowNameMatches() {
        let names = BasicFoodCatalog.matches("cheese").map(\.name)
        XCTAssertFalse(names.isEmpty)
        XCTAssertTrue(names.allSatisfy { $0.lowercased().contains("cheese") })
        XCTAssertEqual(names.first, "Cheddar cheese", "the plainest cheese should lead")
        XCTAssertLessThanOrEqual(names.count, BasicFoodCatalog.maximumMatches)

        let pepper = BasicFoodCatalog.matches("capsicum").map(\.name)
        XCTAssertEqual(Set(pepper), ["Red bell pepper", "Green bell pepper"])
    }

    func testEveryQueryWordMustMatch() {
        XCTAssertEqual(BasicFoodCatalog.matches("sweet potato").map(\.name), ["Sweet potato, baked"])
        XCTAssertTrue(BasicFoodCatalog.matches("banana bread").isEmpty)
    }

    func testEmptyAndNonsenseQueries() {
        XCTAssertTrue(BasicFoodCatalog.matches("").isEmpty)
        XCTAssertTrue(BasicFoodCatalog.matches("   ").isEmpty)
        XCTAssertTrue(BasicFoodCatalog.matches("xqzv").isEmpty)
    }

    func testItemsAreUnbrandedGenericWithServingMath() throws {
        let banana = try XCTUnwrap(BasicFoodCatalog.matches("banana").first)
        XCTAssertNil(banana.brand)
        XCTAssertNil(banana.barcode)
        XCTAssertEqual(banana.source, .generic)
        XCTAssertEqual(banana.servingGrams, 118)
        XCTAssertEqual(banana.servingDescription, "1 medium (118 g)")
        // 89 kcal / 100 g × 118 g
        XCTAssertEqual(banana.nutritionPerServing.calories, 105, accuracy: 0.5)
        XCTAssertEqual(banana.nutritionPerServing.carbs, 26.9, accuracy: 0.1)
    }

    func testCatalogIsSane() {
        var names = Set<String>()
        for food in BasicFoodCatalog.all {
            XCTAssertTrue(names.insert(food.name.lowercased()).inserted, "duplicate: \(food.name)")
            XCTAssertGreaterThan(food.servingGrams, 0, food.name)
            XCTAssertGreaterThanOrEqual(food.per100g.calories, 0, food.name)
            XCTAssertLessThanOrEqual(food.per100g.calories, 900, food.name)
            XCTAssertLessThanOrEqual(food.per100g.protein + food.per100g.carbs + food.per100g.fat, 100.5, food.name)
            // Calories must be in the same ballpark as what the macros imply (water/alcohol/fiber aside).
            let implied = food.per100g.caloriesFromMacros
            if implied > 20 {
                XCTAssertEqual(food.per100g.calories, implied, accuracy: max(25, implied * 0.3), food.name)
            }
        }
        XCTAssertGreaterThan(BasicFoodCatalog.all.count, 100)
    }
}
