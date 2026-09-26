import Foundation

// MARK: - Range

enum HistoryRange: String, CaseIterable, Identifiable {
    case week, month, quarter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "3 Months"
        }
    }

    /// Number of days shown, ending today.
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }

    /// Stride between x-axis labels, in days.
    var axisStride: Int {
        switch self {
        case .week: return 1
        case .month: return 5
        case .quarter: return 15
        }
    }
}

// MARK: - Points

/// One bar in the chart (zero-filled for unlogged days).
struct DayCalories: Identifiable, Hashable {
    let day: Date
    let calories: Double
    var id: Date { day }
}

/// One logged day: totals plus entry count. Only days with at least one entry get a summary.
struct DaySummary: Identifiable, Hashable {
    let day: Date
    let totals: NutritionFacts
    let entryCount: Int
    var id: Date { day }
}

// MARK: - Stats

/// Pure aggregate math over logged days, so it stays unit-testable.
struct HistoryStats: Hashable {
    var averageCalories: Double = 0
    var loggedDays: Int = 0
    var daysOnTarget: Int = 0
    var streak: Int = 0
    var averageMacros = NutritionFacts.zero

    /// - Parameters:
    ///   - summaries: logged days (any order).
    ///   - goal: daily calorie goal; a day counts as "on target" when it is logged and ≤ goal.
    ///   - today: reference day for the streak.
    static func compute(summaries: [DaySummary], goal: Double, today: Date = .now,
                        calendar: Calendar = .current) -> HistoryStats {
        var stats = HistoryStats()
        guard !summaries.isEmpty else { return stats }
        let count = Double(summaries.count)
        let total = summaries.map(\.totals).total()
        stats.loggedDays = summaries.count
        stats.averageCalories = total.calories / count
        stats.averageMacros = NutritionFacts(calories: total.calories / count,
                                             protein: total.protein / count,
                                             carbs: total.carbs / count,
                                             fat: total.fat / count)
        stats.daysOnTarget = summaries.filter { $0.totals.calories <= goal }.count
        stats.streak = streak(days: Set(summaries.map(\.day)), today: today, calendar: calendar)
        return stats
    }

    /// Consecutive logged days ending today. If today has nothing yet, the run may end yesterday
    /// so the number does not drop to zero every morning.
    static func streak(days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }
        var run = 0
        while days.contains(cursor) {
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return run
    }
}
