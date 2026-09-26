import Foundation
import SwiftData

extension ModelContainer {
    /// All persisted model types. Keep in sync when adding a new @Model.
    static let morselSchema = Schema([LogEntry.self, FavoriteFood.self])

    static func morsel(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration("Morsel", schema: morselSchema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: morselSchema, configurations: [config])
    }

    /// In-memory container with a few entries, for previews.
    @MainActor
    static var preview: ModelContainer = {
        let container = try! ModelContainer.morsel(inMemory: true)
        let ctx = container.mainContext
        let samples: [(String, MealType, NutritionFacts)] = [
            ("Greek yogurt with berries", .breakfast, NutritionFacts(calories: 220, protein: 18, carbs: 24, fat: 6)),
            ("Chicken burrito bowl", .lunch, NutritionFacts(calories: 640, protein: 42, carbs: 68, fat: 20)),
            ("Almonds", .snack, NutritionFacts(calories: 160, protein: 6, carbs: 6, fat: 14))
        ]
        for (name, meal, n) in samples {
            ctx.insert(LogEntry(mealType: meal, name: name, servingDescription: "1 serving", perServing: n, source: .search))
        }
        return container
    }()
}
