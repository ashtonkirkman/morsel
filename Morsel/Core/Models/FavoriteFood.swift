import Foundation
import SwiftData

/// A food the user starred or logs often, for one-tap re-logging.
@Model
final class FavoriteFood {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var servingDescription: String
    var servingGrams: Double?
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var sourceRaw: String
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int
    /// Quantity (servings) the user usually logs.
    var defaultQuantity: Double

    init(food: FoodItem, defaultQuantity: Double = 1, now: Date = .now) {
        self.id = UUID()
        self.name = food.name
        self.brand = food.brand
        self.barcode = food.barcode
        self.servingDescription = food.servingDescription
        self.servingGrams = food.servingGrams
        self.calories = food.nutritionPerServing.calories
        self.protein = food.nutritionPerServing.protein
        self.carbs = food.nutritionPerServing.carbs
        self.fat = food.nutritionPerServing.fat
        self.fiber = food.nutritionPerServing.fiber
        self.sugar = food.nutritionPerServing.sugar
        self.sodium = food.nutritionPerServing.sodium
        self.sourceRaw = food.source.rawValue
        self.createdAt = now
        self.lastUsedAt = now
        self.useCount = 0
        self.defaultQuantity = defaultQuantity
    }

    var perServing: NutritionFacts {
        NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat,
                       fiber: fiber, sugar: sugar, sodium: sodium)
    }

    func asFoodItem() -> FoodItem {
        FoodItem(name: name, brand: brand, barcode: barcode, servingDescription: servingDescription,
                 servingGrams: servingGrams, nutritionPerServing: perServing, source: .favorite)
    }

    func markUsed(now: Date = .now) {
        useCount += 1
        lastUsedAt = now
    }
}
