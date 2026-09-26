import XCTest
import SwiftData
@testable import Morsel

@MainActor
final class QueryTests: XCTestCase {
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today) ?? today }

    // MARK: - Helpers

    /// Fresh in-memory store per test. The container is returned so it outlives the context.
    private func makeStore() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainer.morsel(inMemory: true)
        return (container, container.mainContext)
    }

    private func facts(_ kcal: Double, p: Double = 10, c: Double = 20, f: Double = 5) -> NutritionFacts {
        NutritionFacts(calories: kcal, protein: p, carbs: c, fat: f)
    }

    @discardableResult
    private func insert(_ name: String, kcal: Double, at date: Date, meal: MealType = .lunch,
                        brand: String? = nil, into context: ModelContext) throws -> LogEntry {
        let entry = LogEntry(loggedAt: date, mealType: meal, name: name, brand: brand,
                             servingDescription: "1 serving", perServing: facts(kcal), source: .search)
        context.insert(entry)
        try context.save()
        return entry
    }

    private func at(_ day: Date, hour: Int) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: day) ?? day
    }

    // MARK: - entries(on:) / totals(on:)

    func testEntriesOnDayAreScopedAndNewestFirst() throws {
        let store = try makeStore()
        let context = store.context
        try insert("Oats", kcal: 300, at: at(today, hour: 8), meal: .breakfast, into: context)
        try insert("Salad", kcal: 400, at: at(today, hour: 13), into: context)
        try insert("Pizza", kcal: 900, at: at(yesterday, hour: 19), meal: .dinner, into: context)

        let todays = try context.entries(on: today)
        XCTAssertEqual(todays.count, 2)
        XCTAssertEqual(todays.map(\.name), ["Salad", "Oats"], "newest first")

        let yesterdays = try context.entries(on: at(yesterday, hour: 11))
        XCTAssertEqual(yesterdays.map(\.name), ["Pizza"])
    }

    func testTotalsOnDay() throws {
        let store = try makeStore()
        let context = store.context
        try insert("Oats", kcal: 300, at: at(today, hour: 8), into: context)
        try insert("Salad", kcal: 400, at: at(today, hour: 13), into: context)
        try insert("Pizza", kcal: 900, at: at(yesterday, hour: 19), into: context)

        let totals = try context.totals(on: today)
        XCTAssertEqual(totals.calories, 700, accuracy: 0.001)
        XCTAssertEqual(totals.protein, 20, accuracy: 0.001)
        XCTAssertEqual(totals.carbs, 40, accuracy: 0.001)
        XCTAssertEqual(totals.fat, 10, accuracy: 0.001)
        XCTAssertEqual(try context.totals(on: yesterday).calories, 900, accuracy: 0.001)
    }

    func testTotalsRespectQuantity() throws {
        let store = try makeStore()
        let context = store.context
        let entry = try insert("Almonds", kcal: 160, at: at(today, hour: 15), meal: .snack, into: context)
        entry.quantity = 2.5
        try context.save()
        XCTAssertEqual(try context.totals(on: today).calories, 400, accuracy: 0.001)
    }

    // MARK: - dailyCalories(from:to:)

    func testDailyCaloriesZeroFills() throws {
        let store = try makeStore()
        let context = store.context
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        try insert("Pizza", kcal: 900, at: at(twoDaysAgo, hour: 19), into: context)
        try insert("Oats", kcal: 300, at: at(today, hour: 8), into: context)
        try insert("Salad", kcal: 400, at: at(today, hour: 13), into: context)

        let series = try context.dailyCalories(from: twoDaysAgo, to: tomorrow)
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].day, twoDaysAgo)
        XCTAssertEqual(series[0].calories, 900, accuracy: 0.001)
        XCTAssertEqual(series[1].day, yesterday)
        XCTAssertEqual(series[1].calories, 0, accuracy: 0.001, "unlogged day is zero-filled")
        XCTAssertEqual(series[2].day, today)
        XCTAssertEqual(series[2].calories, 700, accuracy: 0.001)
    }

    func testDailyCaloriesEmptyRangeIsAllZeros() throws {
        let store = try makeStore()
        let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: today))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let series = try store.context.dailyCalories(from: start, to: end)
        XCTAssertEqual(series.count, 7)
        XCTAssertTrue(series.allSatisfy { $0.calories == 0 })
    }

    // MARK: - recentFoods

    func testRecentFoodsDeduplicatesByNameAndBrand() throws {
        let store = try makeStore()
        let context = store.context
        try insert("Oats", kcal: 300, at: at(yesterday, hour: 8), into: context)
        try insert("Eggs", kcal: 150, at: at(yesterday, hour: 9), into: context)
        try insert("oats", kcal: 300, at: at(today, hour: 8), into: context)                 // same food, different case
        try insert("Oats", kcal: 320, at: at(today, hour: 9), brand: "Quaker", into: context) // different brand → distinct

        let recents = try context.recentFoods()
        XCTAssertEqual(recents.count, 3)
        XCTAssertEqual(recents.first?.brand, "Quaker", "most recent first")
        XCTAssertEqual(recents.map { $0.name.lowercased() }, ["oats", "oats", "eggs"])
        XCTAssertEqual(recents.filter { $0.brand == nil }.count, 2)
    }

    func testRecentFoodsHonoursLimit() throws {
        let store = try makeStore()
        for i in 0..<5 {
            try insert("Food \(i)", kcal: 100, at: at(today, hour: i + 1), into: store.context)
        }
        XCTAssertEqual(try store.context.recentFoods(limit: 3).count, 3)
    }

    // MARK: - log(_:)

    func testLogReturnsEntryWithDaySet() throws {
        let store = try makeStore()
        let context = store.context
        let food = FoodItem(name: "Banana", servingDescription: "1 medium", servingGrams: 118,
                            nutritionPerServing: facts(105, p: 1.3, c: 27, f: 0.4), source: .search)
        let when = at(yesterday, hour: 16)
        let entry = try context.log(food, quantity: 2, mealType: .snack, at: when)

        XCTAssertEqual(entry.day, yesterday)
        XCTAssertEqual(entry.loggedAt, when)
        XCTAssertEqual(entry.mealType, .snack)
        XCTAssertEqual(entry.quantity, 2)
        XCTAssertEqual(entry.total.calories, 210, accuracy: 0.001)
        XCTAssertEqual(entry.source, .search)
        XCTAssertNil(entry.confidence)

        // It is persisted and visible to the per-day query.
        XCTAssertEqual(try context.entries(on: yesterday).map(\.id), [entry.id])
        XCTAssertTrue(try context.entries(on: today).isEmpty)
    }

    func testRefreshDayFollowsLoggedAt() throws {
        let store = try makeStore()
        let context = store.context
        let entry = try insert("Oats", kcal: 300, at: at(today, hour: 8), into: context)
        entry.loggedAt = at(yesterday, hour: 8)
        entry.refreshDay()
        try context.save()
        XCTAssertEqual(entry.day, yesterday)
        XCTAssertEqual(try context.entries(on: yesterday).count, 1)
        XCTAssertTrue(try context.entries(on: today).isEmpty)
    }

    // MARK: - History aggregates

    func testHistoryStatsStreakAndAverages() throws {
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let summaries = [
            DaySummary(day: today, totals: facts(1800), entryCount: 2),
            DaySummary(day: yesterday, totals: facts(2400), entryCount: 3),
            DaySummary(day: twoDaysAgo, totals: facts(1500), entryCount: 1)
        ]
        let stats = HistoryStats.compute(summaries: summaries, goal: 2000, today: today, calendar: calendar)
        XCTAssertEqual(stats.loggedDays, 3)
        XCTAssertEqual(stats.averageCalories, 1900, accuracy: 0.001)
        XCTAssertEqual(stats.daysOnTarget, 2)
        XCTAssertEqual(stats.streak, 3)
        XCTAssertEqual(stats.averageMacros.protein, 10, accuracy: 0.001)

        // An unlogged today still counts yesterday's run; a gap before today breaks it.
        let gapped = [summaries[1], summaries[2]]
        XCTAssertEqual(HistoryStats.compute(summaries: gapped, goal: 2000, today: today, calendar: calendar).streak, 2)
        let broken = [summaries[0], summaries[2]]
        XCTAssertEqual(HistoryStats.compute(summaries: broken, goal: 2000, today: today, calendar: calendar).streak, 1)
        XCTAssertEqual(HistoryStats.compute(summaries: [], goal: 2000).streak, 0)
    }

    // MARK: - CSV export

    func testCSVExporterEscapesAndOrders() throws {
        let store = try makeStore()
        let context = store.context
        try insert("Salad, large", kcal: 400, at: at(today, hour: 13), brand: "Joe's \"Fresh\"", into: context)
        try insert("Oats", kcal: 300, at: at(today, hour: 8), meal: .breakfast, into: context)
        let entries = try context.fetch(FetchDescriptor<LogEntry>())
        let csv = CSVExporter.csv(from: entries)
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], CSVExporter.header)
        XCTAssertTrue(lines[1].contains(",breakfast,Oats,"), "oldest entry first")
        XCTAssertTrue(lines[2].contains("\"Salad, large\""))
        XCTAssertTrue(lines[2].contains("\"Joe's \"\"Fresh\"\"\""))
        XCTAssertEqual(CSVExporter.escape("plain"), "plain")
        XCTAssertEqual(CSVExporter.number(2.5), "2.50")
        XCTAssertEqual(CSVExporter.number(300), "300")
    }
}
