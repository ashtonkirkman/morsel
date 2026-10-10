import Foundation

/// Turns a profile plus an optionally user-edited calorie number into a full macro plan.
/// Mirrors `GoalCalculator`'s split (protein by body weight, fat 30%, carbs fill) so an edited
/// calorie target still gets sensible macros.
enum PlanBuilder {
    static let minimumCalories: Double = 1000

    static func plan(for profile: UserProfile, calories requested: Double?) -> NutritionFacts {
        let computed = GoalCalculator.targets(for: profile)
        guard let requested, requested.rounded() != computed.calories else { return computed }
        let calories = max(minimumCalories, requested.rounded())
        let protein = computed.protein
        let fat = (calories * 0.30 / 9).rounded()
        let carbs = max(50, ((calories - protein * 4 - fat * 9) / 4).rounded())
        return NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}
