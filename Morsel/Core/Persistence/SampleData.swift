import Foundation
import SwiftData

/// Deterministic demo content for previews, screenshots and UI tests.
enum SampleData {
    struct Meal { let name: String; let brand: String?; let serving: String; let meal: MealType; let facts: NutritionFacts; let source: FoodSource }

    static let today: [Meal] = [
        Meal(name: "Greek yogurt with berries", brand: nil, serving: "1 bowl (250 g)", meal: .breakfast,
             facts: NutritionFacts(calories: 240, protein: 18, carbs: 26, fat: 7, fiber: 3, sugar: 14), source: .photo),
        Meal(name: "Oat latte", brand: nil, serving: "12 fl oz", meal: .breakfast,
             facts: NutritionFacts(calories: 130, protein: 3, carbs: 17, fat: 5, sugar: 9), source: .search),
        Meal(name: "Chicken burrito bowl", brand: "Chipotle", serving: "1 bowl", meal: .lunch,
             facts: NutritionFacts(calories: 655, protein: 44, carbs: 70, fat: 21, fiber: 11, sodium: 1280), source: .photo),
        Meal(name: "Almonds", brand: "Blue Diamond", serving: "1 oz (28 g)", meal: .snack,
             facts: NutritionFacts(calories: 160, protein: 6, carbs: 6, fat: 14, fiber: 3), source: .barcode),
        Meal(name: "Apple", brand: nil, serving: "1 medium", meal: .snack,
             facts: NutritionFacts(calories: 95, protein: 0.5, carbs: 25, fat: 0.3, fiber: 4, sugar: 19), source: .search)
    ]

    static let pastDinners: [Meal] = [
        Meal(name: "Salmon, rice and broccoli", brand: nil, serving: "1 plate", meal: .dinner,
             facts: NutritionFacts(calories: 620, protein: 42, carbs: 58, fat: 22), source: .photo),
        Meal(name: "Margherita pizza", brand: nil, serving: "3 slices", meal: .dinner,
             facts: NutritionFacts(calories: 810, protein: 33, carbs: 96, fat: 30), source: .photo),
        Meal(name: "Turkey chili", brand: nil, serving: "1 bowl", meal: .dinner,
             facts: NutritionFacts(calories: 430, protein: 36, carbs: 40, fat: 12), source: .search),
        Meal(name: "Pad thai", brand: nil, serving: "1 plate", meal: .dinner,
             facts: NutritionFacts(calories: 760, protein: 28, carbs: 92, fat: 30), source: .photo)
    ]

    /// Seeds today plus the previous `days` days (varied totals so History charts have shape).
    @MainActor
    static func seed(into context: ModelContext, days: Int = 21, now: Date = .now, calendar: Calendar = .current) {
        func insert(_ m: Meal, at date: Date, quantity: Double = 1) {
            let food = FoodItem(name: m.name, brand: m.brand, servingDescription: m.serving,
                                nutritionPerServing: m.facts, source: m.source)
            context.insert(LogEntry(food: food, quantity: quantity, mealType: m.meal, loggedAt: date,
                                    confidence: m.source == .photo ? 0.86 : nil))
        }

        let startOfToday = calendar.startOfDay(for: now)
        let hours: [MealType: Int] = [.breakfast: 8, .lunch: 12, .dinner: 19, .snack: 15]
        // Clamp to "a moment ago" so an early-morning run (CI at 02:00) still shows a full day.
        for (i, m) in today.enumerated() {
            let scheduled = calendar.date(byAdding: .hour, value: hours[m.meal] ?? 12, to: startOfToday) ?? now
            let at = min(scheduled, now.addingTimeInterval(-Double(60 * (today.count - i))))
            insert(m, at: at)
        }

        for offset in 1...max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            if offset % 9 == 4 { continue }   // an unlogged day now and then
            let breakfast = today[offset % 2]
            let lunch = today[2]
            let dinner = pastDinners[offset % pastDinners.count]
            let scale = 0.8 + Double(offset % 5) * 0.12
            insert(breakfast, at: calendar.date(byAdding: .hour, value: 8, to: day) ?? day)
            insert(lunch, at: calendar.date(byAdding: .hour, value: 12, to: day) ?? day, quantity: scale)
            insert(dinner, at: calendar.date(byAdding: .hour, value: 19, to: day) ?? day)
            if offset % 3 == 0 { insert(today[3], at: calendar.date(byAdding: .hour, value: 16, to: day) ?? day) }
        }

        let favorites = [today[0], today[2], today[3]]
        for (i, m) in favorites.enumerated() {
            let food = FoodItem(name: m.name, brand: m.brand, servingDescription: m.serving,
                                nutritionPerServing: m.facts, source: m.source)
            let fav = FavoriteFood(food: food)
            fav.useCount = 12 - i * 3
            context.insert(fav)
        }
        try? context.save()
    }
}
