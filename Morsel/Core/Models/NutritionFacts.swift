import Foundation

/// Macro + micro nutrition for one serving (or one logged quantity) of food.
/// Energy is kilocalories; macros are grams; sodium is milligrams.
struct NutritionFacts: Codable, Hashable, Sendable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?

    init(calories: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
         fiber: Double? = nil, sugar: Double? = nil, sodium: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
    }

    static let zero = NutritionFacts(calories: 0)

    /// Multiply every field by `factor` (e.g. number of servings).
    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            fiber: fiber.map { $0 * factor },
            sugar: sugar.map { $0 * factor },
            sodium: sodium.map { $0 * factor }
        )
    }

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            fiber: addOptional(lhs.fiber, rhs.fiber),
            sugar: addOptional(lhs.sugar, rhs.sugar),
            sodium: addOptional(lhs.sodium, rhs.sodium)
        )
    }

    static func += (lhs: inout NutritionFacts, rhs: NutritionFacts) { lhs = lhs + rhs }

    private static func addOptional(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (nil, nil): return nil
        default: return (a ?? 0) + (b ?? 0)
        }
    }

    /// Calories implied by the macros (4/4/9). Useful for sanity-checking AI or database data.
    var caloriesFromMacros: Double { protein * 4 + carbs * 4 + fat * 9 }
}

extension Sequence where Element == NutritionFacts {
    func total() -> NutritionFacts { reduce(.zero, +) }
}
