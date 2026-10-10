import Foundation
import SwiftData

extension ModelContext {
    /// Entries logged on the calendar day containing `date`, newest first.
    func entries(on date: Date, calendar: Calendar = .current) throws -> [LogEntry] {
        let day = calendar.startOfDay(for: date)
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.day == day },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return try fetch(descriptor)
    }

    /// Entries in `[start, end)`.
    func entries(from start: Date, to end: Date) throws -> [LogEntry] {
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt < end },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return try fetch(descriptor)
    }

    func totals(on date: Date) throws -> NutritionFacts {
        try entries(on: date).map(\.total).total()
    }

    /// Most recent distinct foods (by name+brand), for the "Recents" list.
    func recentFoods(limit: Int = 20) throws -> [FoodItem] {
        var descriptor = FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        var seen = Set<String>()
        var out: [FoodItem] = []
        for entry in try fetch(descriptor) {
            let key = (entry.name + "|" + (entry.brand ?? "")).lowercased()
            if seen.insert(key).inserted {
                out.append(entry.asFoodItem())
                if out.count == limit { break }
            }
        }
        return out
    }

    /// Insert and save; returns the entry for follow-up UI (undo, haptics).
    @discardableResult
    func log(_ food: FoodItem, quantity: Double = 1, mealType: MealType = .suggested(),
             at date: Date = .now, photoFilename: String? = nil, confidence: Double? = nil) throws -> LogEntry {
        let entry = LogEntry(food: food, quantity: quantity, mealType: mealType, loggedAt: date,
                             photoFilename: photoFilename, confidence: confidence)
        insert(entry)
        try save()
        return entry
    }

    /// Per-day calorie totals for a date range, zero-filled. Used by History charts.
    func dailyCalories(from start: Date, to end: Date, calendar: Calendar = .current) throws -> [(day: Date, calories: Double)] {
        let fetched = try entries(from: calendar.startOfDay(for: start), to: end)
        var byDay: [Date: Double] = [:]
        for e in fetched { byDay[e.day, default: 0] += e.total.calories }
        var out: [(Date, Double)] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            out.append((cursor, byDay[cursor] ?? 0))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return out.map { (day: $0.0, calories: $0.1) }
    }
}
