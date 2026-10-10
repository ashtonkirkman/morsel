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
        entry.updatedAt = .now
        insert(entry)
        try save()
        return entry
    }

    // MARK: - Sync bookkeeping

    /// Mark an entry as modified so the change is pushed on the next sync. (SyncEngine also
    /// detects silent edits by content, so forgetting this only delays the push by one cycle.)
    func touch(_ entry: LogEntry, now: Date = .now) {
        entry.updatedAt = now
    }

    func touch(_ favorite: FavoriteFood, now: Date = .now) {
        favorite.updatedAt = now
    }

    /// Delete an entry and leave a tombstone so other devices delete it too. Does not save.
    func deleteSynced(_ entry: LogEntry, now: Date = .now) {
        recordDeletion(of: entry.id, in: SyncCollectionNames.logEntries, at: now)
        delete(entry)
    }

    func deleteSynced(_ favorite: FavoriteFood, now: Date = .now) {
        recordDeletion(of: favorite.id, in: SyncCollectionNames.favorites, at: now)
        delete(favorite)
    }

    /// Insert a `SyncTombstone` for an object deleted by other means (e.g. `delete(model:)`).
    func recordDeletion(of id: UUID, in collection: String, at date: Date = .now) {
        insert(SyncTombstone(docID: id.uuidString, collection: collection, deletedAt: date))
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

/// Server collection names, shared by `SyncCollections.registerAll` and the tombstone helpers.
enum SyncCollectionNames {
    static let logEntries = "log-entries"
    static let favorites = "favorites"
    static let settings = "settings"
    static let bodyScans = "body-scans"
}
