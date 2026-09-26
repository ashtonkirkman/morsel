import SwiftUI
import SwiftData
import Charts

/// History tab: calorie chart for a range, aggregate stats, averaged macros and a per-day list.
struct HistoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var range: HistoryRange = .week
    @State private var points: [DayCalories] = []
    @State private var summaries: [DaySummary] = []
    @State private var stats = HistoryStats()
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    rangePicker
                    if let loadError {
                        errorCard(loadError)
                    } else if summaries.isEmpty {
                        EmptyStateView(symbol: "chart.bar",
                                       title: "No days logged yet",
                                       message: "Your \(range.title.lowercased()) will fill in as you log meals.")
                    } else {
                        chartCard
                        statsCard
                        macroCard
                        daysList
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, 120)
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("History")
            .navigationDestination(for: Date.self) { day in
                HistoryDayDetailView(day: day)
            }
        }
        .task(id: range) { load() }
        .onAppear { load() }
    }

    // MARK: - Range

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(HistoryRange.allCases) { r in
                Text(r.title).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Chart

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Calories", trailing: "goal \(Format.kcal(settings.calorieGoal))")
                HistoryChart(points: points, goal: settings.calorieGoal, range: range)
                    .frame(height: 200)
            }
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.s) {
                stat(value: Format.kcal(stats.averageCalories), label: "avg / day")
                stat(value: "\(stats.daysOnTarget)/\(stats.loggedDays)", label: "days on target")
                stat(value: "\(stats.streak)", label: "day streak")
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(MorselFont.numeral)
                .foregroundStyle(Color.mText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(MorselFont.caption)
                .foregroundStyle(Color.mTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var macroCard: some View {
        Card {
            VStack(spacing: Spacing.m) {
                SectionHeader(title: "Average macros", trailing: "logged days")
                MacroBar(title: "Protein", value: stats.averageMacros.protein, goal: settings.proteinGoal, color: .mProtein)
                MacroBar(title: "Carbs", value: stats.averageMacros.carbs, goal: settings.carbsGoal, color: .mCarbs)
                MacroBar(title: "Fat", value: stats.averageMacros.fat, goal: settings.fatGoal, color: .mFat)
            }
        }
    }

    // MARK: - Days

    private var daysList: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Days")
                .padding(.top, Spacing.s)
            ForEach(summaries) { summary in
                NavigationLink(value: summary.day) {
                    DaySummaryRow(summary: summary, goal: settings.calorieGoal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Couldn't load your history.")
                    .font(MorselFont.headline)
                    .foregroundStyle(Color.mText)
                Text(message)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextSecondary)
                Button("Try again") { load() }
                    .buttonStyle(.morselSecondary)
            }
        }
    }

    // MARK: - Loading

    private func load() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: today),
              let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) else { return }
        do {
            points = try context.dailyCalories(from: start, to: end).map { DayCalories(day: $0.day, calories: $0.calories) }
            let entries = try context.entries(from: start, to: end)
            var byDay: [Date: (NutritionFacts, Int)] = [:]
            for entry in entries {
                let current = byDay[entry.day] ?? (NutritionFacts.zero, 0)
                byDay[entry.day] = (current.0 + entry.total, current.1 + 1)
            }
            summaries = byDay
                .map { DaySummary(day: $0.key, totals: $0.value.0, entryCount: $0.value.1) }
                .sorted { $0.day > $1.day }
            stats = HistoryStats.compute(summaries: summaries, goal: settings.calorieGoal, today: today, calendar: calendar)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Chart

/// Daily calorie bars with a dashed goal line. Bars over goal use the warning color.
struct HistoryChart: View {
    let points: [DayCalories]
    let goal: Double
    let range: HistoryRange

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Day", point.day, unit: .day),
                        y: .value("Calories", point.calories))
                    .foregroundStyle(point.calories > goal ? Color.mWarning : Color.mAccent)
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Goal", goal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.mTextTertiary)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range.axisStride)) { _ in
                AxisGridLine().foregroundStyle(Color.mSeparator)
                AxisValueLabel(format: axisLabelFormat, centered: range == .week)
                    .foregroundStyle(Color.mTextSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.mSeparator)
                AxisValueLabel().foregroundStyle(Color.mTextTertiary)
            }
        }
        .accessibilityLabel("Daily calories for the last \(range.days) days")
    }

    /// Weekday initials for a week, "Sep 26" style otherwise.
    private var axisLabelFormat: Date.FormatStyle {
        range == .week ? Date.FormatStyle().weekday(.abbreviated) : Date.FormatStyle().month(.abbreviated).day()
    }
}

// MARK: - Day row

/// One logged day in the list: date, calories, macro dots.
struct DaySummaryRow: View {
    let summary: DaySummary
    let goal: Double

    var body: some View {
        Card {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(MorselFont.headline)
                        .foregroundStyle(Color.mText)
                    HStack(spacing: Spacing.s) {
                        MacroDot(color: .mProtein, text: Format.grams(summary.totals.protein))
                        MacroDot(color: .mCarbs, text: Format.grams(summary.totals.carbs))
                        MacroDot(color: .mFat, text: Format.grams(summary.totals.fat))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.kcal(summary.totals.calories))
                        .font(MorselFont.numeral)
                        .foregroundStyle(summary.totals.calories > goal ? Color.mWarning : Color.mText)
                    Text(summary.entryCount == 1 ? "1 item" : "\(summary.entryCount) items")
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mTextTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
    }
}

// MARK: - Day detail

/// Pushed from the Days list; reuses the Today day component with its hero.
struct HistoryDayDetailView: View {
    let day: Date

    var body: some View {
        ScrollView {
            DayLogView(day: day, showsHero: true)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, 120)
        }
        .background(Color.mBackground.ignoresSafeArea())
        .navigationTitle(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
