import XCTest
@testable import Morsel

final class GoalCalculatorTests: XCTestCase {
    /// Male, 30 y, 180 cm, 80 kg — a textbook Mifflin–St Jeor example.
    private let male = UserProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                   activity: .moderate, goal: .maintain)

    func testBMRKnownProfile() {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        XCTAssertEqual(GoalCalculator.bmr(for: male), 1780, accuracy: 0.001)
    }

    func testBMRFemaleOffset() {
        var female = male
        female.sex = .female
        // Same base, minus 161 instead of plus 5.
        XCTAssertEqual(GoalCalculator.bmr(for: female), 1780 - 166, accuracy: 0.001)
    }

    func testMaintenanceModerate() {
        // 1780 * 1.55 = 2759
        XCTAssertEqual(GoalCalculator.maintenanceCalories(for: male), 2759, accuracy: 0.001)
    }

    func testTargetRoundsToTen() {
        // 2759 → rounded to nearest 10 → 2760
        XCTAssertEqual(GoalCalculator.targetCalories(for: male), 2760, accuracy: 0.001)
        var lose = male
        lose.goal = .lose
        // 2759 - 500 = 2259 → 2260
        XCTAssertEqual(GoalCalculator.targetCalories(for: lose), 2260, accuracy: 0.001)
        var gain = male
        gain.goal = .gain
        // 2759 + 300 = 3059 → 3060
        XCTAssertEqual(GoalCalculator.targetCalories(for: gain), 3060, accuracy: 0.001)
    }

    func testLoseFloorsAtSafeMinimum() {
        // Small sedentary female: BMR 926.5 → maintenance 1111.8 → -500 = 611.8, floored to 1200.
        let small = UserProfile(sex: .female, age: 60, heightCm: 150, weightKg: 45,
                                activity: .sedentary, goal: .lose)
        XCTAssertEqual(GoalCalculator.targetCalories(for: small), 1200, accuracy: 0.001)

        // Male floor is 1500.
        let smallMale = UserProfile(sex: .male, age: 70, heightCm: 155, weightKg: 50,
                                    activity: .sedentary, goal: .lose)
        // BMR = 500 + 968.75 - 350 + 5 = 1123.75 → *1.2 = 1348.5 → -500 = 848.5 → floor 1500
        XCTAssertEqual(GoalCalculator.targetCalories(for: smallMale), 1500, accuracy: 0.001)
    }

    func testMacroSplitSumsToTarget() {
        for goal in WeightGoal.allCases {
            var p = male
            p.goal = goal
            let t = GoalCalculator.targets(for: p)
            XCTAssertEqual(t.caloriesFromMacros, t.calories, accuracy: 40,
                           "macros should sum to within ±40 kcal for goal \(goal)")
            XCTAssertGreaterThan(t.protein, 0)
            XCTAssertGreaterThan(t.carbs, 0)
            XCTAssertGreaterThan(t.fat, 0)
        }
    }

    func testProteinPerKgByGoal() {
        var lose = male; lose.goal = .lose
        var gain = male; gain.goal = .gain
        XCTAssertEqual(GoalCalculator.targets(for: male).protein, 128)   // 80 * 1.6
        XCTAssertEqual(GoalCalculator.targets(for: lose).protein, 144)   // 80 * 1.8
        XCTAssertEqual(GoalCalculator.targets(for: gain).protein, 160)   // 80 * 2.0
    }

    func testFatIsThirtyPercent() {
        let t = GoalCalculator.targets(for: male)
        XCTAssertEqual(t.fat * 9, t.calories * 0.30, accuracy: 9)
    }

    func testRoundedToNearest() {
        XCTAssertEqual(2759.0.rounded(toNearest: 10), 2760)
        XCTAssertEqual(2754.0.rounded(toNearest: 10), 2750)
        XCTAssertEqual(123.0.rounded(toNearest: 0), 123)
    }

    func testUnitsRoundTrip() {
        XCTAssertEqual(Units.kg(fromLb: Units.lb(fromKg: 80)), 80, accuracy: 0.0001)
        XCTAssertEqual(Units.cm(feet: 5, inches: 11), 180.34, accuracy: 0.01)
        let fi = Units.feetInches(fromCm: 180.34)
        XCTAssertEqual(fi.feet, 5)
        XCTAssertEqual(fi.inches, 11)
    }

    func testPlanBuilderKeepsComputedWhenUnchanged() {
        let computed = GoalCalculator.targets(for: male)
        XCTAssertEqual(PlanBuilder.plan(for: male, calories: nil), computed)
        XCTAssertEqual(PlanBuilder.plan(for: male, calories: computed.calories), computed)
    }

    func testPlanBuilderRespectsEditedCalories() {
        let plan = PlanBuilder.plan(for: male, calories: 2200)
        XCTAssertEqual(plan.calories, 2200)
        XCTAssertEqual(plan.protein, GoalCalculator.targets(for: male).protein)
        XCTAssertEqual(plan.caloriesFromMacros, 2200, accuracy: 40)
        XCTAssertEqual(PlanBuilder.plan(for: male, calories: 200).calories, PlanBuilder.minimumCalories)
    }
}
