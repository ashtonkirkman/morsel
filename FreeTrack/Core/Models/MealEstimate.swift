import Foundation

/// What the AI vision service returns for one meal photo.
struct MealEstimate: Codable, Hashable, Sendable {
    var items: [EstimatedFoodItem]
    /// One-line description of the plate, e.g. "Grilled chicken salad with vinaigrette".
    var summary: String
    /// 0...1 overall confidence.
    var overallConfidence: Double
    /// Optional follow-up the model wants answered to tighten the estimate, e.g.
    /// "Is the dressing full-fat or light?". Nil when the estimate is already solid.
    var clarifyingQuestion: String?

    var total: NutritionFacts { items.map(\.total).total() }
}

struct EstimatedFoodItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var food: FoodItem
    /// Number of servings of `food` visible on the plate.
    var quantity: Double
    /// 0...1
    var confidence: Double
    var rationale: String?

    init(id: UUID = UUID(), food: FoodItem, quantity: Double = 1, confidence: Double, rationale: String? = nil) {
        self.id = id
        self.food = food
        self.quantity = quantity
        self.confidence = confidence
        self.rationale = rationale
    }

    var total: NutritionFacts { food.nutritionPerServing.scaled(by: quantity) }
}
