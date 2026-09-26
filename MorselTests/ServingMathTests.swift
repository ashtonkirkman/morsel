import XCTest
@testable import Morsel

final class ServingMathTests: XCTestCase {
    // MARK: - Clamping

    func testClampedKeepsInRangeValues() {
        XCTAssertEqual(ServingMath.clamped(1), 1)
        XCTAssertEqual(ServingMath.clamped(2.75), 2.75)
        XCTAssertEqual(ServingMath.clamped(ServingMath.minimumQuantity), ServingMath.minimumQuantity)
        XCTAssertEqual(ServingMath.clamped(ServingMath.maximumQuantity), ServingMath.maximumQuantity)
    }

    func testClampedLimitsOutOfRangeValues() {
        XCTAssertEqual(ServingMath.clamped(0), ServingMath.minimumQuantity)
        XCTAssertEqual(ServingMath.clamped(-3), ServingMath.minimumQuantity)
        XCTAssertEqual(ServingMath.clamped(100), ServingMath.maximumQuantity)
    }

    func testClampedHandlesNonFiniteValues() {
        XCTAssertEqual(ServingMath.clamped(.nan), ServingMath.minimumQuantity)
        XCTAssertEqual(ServingMath.clamped(.infinity), ServingMath.minimumQuantity)
    }

    // MARK: - Grams ↔ quantity

    func testGramsForQuantity() {
        XCTAssertEqual(ServingMath.grams(forQuantity: 2, servingGrams: 30), 60)
        XCTAssertEqual(ServingMath.grams(forQuantity: 0.5, servingGrams: 100), 50)
    }

    func testGramsNilWithoutServingWeight() {
        XCTAssertNil(ServingMath.grams(forQuantity: 2, servingGrams: nil))
        XCTAssertNil(ServingMath.grams(forQuantity: 2, servingGrams: 0))
        XCTAssertNil(ServingMath.grams(forQuantity: 2, servingGrams: -5))
    }

    func testQuantityForGrams() {
        XCTAssertEqual(ServingMath.quantity(forGrams: 60, servingGrams: 30), 2)
        XCTAssertEqual(ServingMath.quantity(forGrams: 150, servingGrams: 100), 1.5)
    }

    func testQuantityForGramsIsClamped() {
        XCTAssertEqual(ServingMath.quantity(forGrams: 1, servingGrams: 100), ServingMath.minimumQuantity)
        XCTAssertEqual(ServingMath.quantity(forGrams: 100_000, servingGrams: 10), ServingMath.maximumQuantity)
    }

    func testQuantityForGramsRejectsInvalidInput() {
        XCTAssertNil(ServingMath.quantity(forGrams: 50, servingGrams: nil))
        XCTAssertNil(ServingMath.quantity(forGrams: 50, servingGrams: 0))
        XCTAssertNil(ServingMath.quantity(forGrams: 0, servingGrams: 50))
        XCTAssertNil(ServingMath.quantity(forGrams: -10, servingGrams: 50))
        XCTAssertNil(ServingMath.quantity(forGrams: .nan, servingGrams: 50))
    }

    func testGramsQuantityRoundTrip() {
        let servingGrams = 42.0
        for quantity in [0.25, 0.5, 1, 1.5, 2.25, 3, 12.75] {
            guard let grams = ServingMath.grams(forQuantity: quantity, servingGrams: servingGrams),
                  let back = ServingMath.quantity(forGrams: grams, servingGrams: servingGrams) else {
                XCTFail("Round trip returned nil for \(quantity)")
                continue
            }
            XCTAssertEqual(back, quantity, accuracy: 1e-9)
        }
    }

    // MARK: - Chips & labels

    func testChipValues() {
        XCTAssertEqual(ServingMath.chipQuantities, [0.5, 1, 1.5, 2, 3])
        XCTAssertEqual(ServingMath.chipQuantities.map(ServingMath.label(for:)), ["½", "1", "1½", "2", "3"])
    }

    func testChipValuesAreWithinLimits() {
        for chip in ServingMath.chipQuantities {
            XCTAssertEqual(ServingMath.clamped(chip), chip)
        }
    }

    func testLabelsForOffGridValues() {
        XCTAssertEqual(ServingMath.label(for: 0.25), "¼")
        XCTAssertEqual(ServingMath.label(for: 2.75), "2¾")
        XCTAssertEqual(ServingMath.label(for: 1.3), "1.3")
        XCTAssertEqual(ServingMath.label(for: 12), "12")
        XCTAssertEqual(ServingMath.label(for: 0), "0")
    }

    func testMatchesToleratesFloatNoise() {
        XCTAssertTrue(ServingMath.matches(1.5000001, 1.5))
        XCTAssertFalse(ServingMath.matches(1.25, 1.5))
    }

    // MARK: - Nutrition

    func testNutritionScalesWithQuantity() {
        let per = NutritionFacts(calories: 100, protein: 10, carbs: 20, fat: 5, fiber: 2)
        let total = ServingMath.nutrition(per, quantity: 2.5)
        XCTAssertEqual(total.calories, 250)
        XCTAssertEqual(total.protein, 25)
        XCTAssertEqual(total.carbs, 50)
        XCTAssertEqual(total.fat, 12.5)
        XCTAssertEqual(total.fiber, 5)
        XCTAssertNil(total.sugar)
    }
}
