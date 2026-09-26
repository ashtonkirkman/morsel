import Foundation
import SwiftData

/// One logged food, persisted with SwiftData. Nutrition is stored *per serving* and
/// multiplied by `quantity` (number of servings) for totals. Fields are flattened
/// (no nested Codable structs) to keep the SwiftData schema simple and migratable.
@Model
final class LogEntry {
    @Attribute(.unique) var id: UUID
    var loggedAt: Date
    /// Start of the calendar day of `loggedAt`, stored for fast per-day queries.
    var day: Date
    var mealTypeRaw: String
    var name: String
    var brand: String?
    var barcode: String?
    var servingDescription: String
    var servingGrams: Double?
    var quantity: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var sourceRaw: String
    /// File name inside `PhotoStore` (JPEG) for photo-logged meals.
    var photoFilename: String?
    var notes: String?
    /// 0...1 confidence for AI estimates; nil for database/manual entries.
    var confidence: Double?

    init(id: UUID = UUID(),
         loggedAt: Date = .now,
         mealType: MealType,
         name: String,
         brand: String? = nil,
         barcode: String? = nil,
         servingDescription: String,
         servingGrams: Double? = nil,
         quantity: Double = 1,
         perServing: NutritionFacts,
         source: FoodSource,
         photoFilename: String? = nil,
         notes: String? = nil,
         confidence: Double? = nil) {
        self.id = id
        self.loggedAt = loggedAt
        self.day = Calendar.current.startOfDay(for: loggedAt)
        self.mealTypeRaw = mealType.rawValue
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.servingDescription = servingDescription
        self.servingGrams = servingGrams
        self.quantity = quantity
        self.calories = perServing.calories
        self.protein = perServing.protein
        self.carbs = perServing.carbs
        self.fat = perServing.fat
        self.fiber = perServing.fiber
        self.sugar = perServing.sugar
        self.sodium = perServing.sodium
        self.sourceRaw = source.rawValue
        self.photoFilename = photoFilename
        self.notes = notes
        self.confidence = confidence
    }

    convenience init(food: FoodItem, quantity: Double = 1, mealType: MealType = .suggested(),
                     loggedAt: Date = .now, photoFilename: String? = nil, confidence: Double? = nil) {
        self.init(loggedAt: loggedAt,
                  mealType: mealType,
                  name: food.name,
                  brand: food.brand,
                  barcode: food.barcode,
                  servingDescription: food.servingDescription,
                  servingGrams: food.servingGrams,
                  quantity: quantity,
                  perServing: food.nutritionPerServing,
                  source: food.source,
                  photoFilename: photoFilename,
                  confidence: confidence)
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var perServing: NutritionFacts {
        get {
            NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat,
                           fiber: fiber, sugar: sugar, sodium: sodium)
        }
        set {
            calories = newValue.calories
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
            fiber = newValue.fiber
            sugar = newValue.sugar
            sodium = newValue.sodium
        }
    }

    /// Nutrition for the logged quantity.
    var total: NutritionFacts { perServing.scaled(by: quantity) }

    /// Re-derive `day` after changing `loggedAt`.
    func refreshDay(calendar: Calendar = .current) {
        day = calendar.startOfDay(for: loggedAt)
    }

    /// Back to a value type (e.g. "log this again").
    func asFoodItem() -> FoodItem {
        FoodItem(name: name, brand: brand, barcode: barcode, servingDescription: servingDescription,
                 servingGrams: servingGrams, nutritionPerServing: perServing, source: source)
    }
}
