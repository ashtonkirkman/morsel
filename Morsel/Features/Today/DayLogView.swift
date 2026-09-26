import SwiftUI
import SwiftData

/// One calendar day of entries: hero ring, macro bars and meals grouped by type.
/// Not scrollable itself — the parent supplies the `ScrollView` so it can add its own header.
/// `@Query` predicates must be static, so the day is captured in `init`.
struct DayLogView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query private var entries: [LogEntry]

    let day: Date
    let showsHero: Bool

    @State private var selectedEntry: LogEntry?
    @State private var pendingDelete: LogEntry?

    init(day: Date, showsHero: Bool = true) {
        self.day = day
        self.showsHero = showsHero
        _entries = Query(filter: #Predicate<LogEntry> { $0.day == day },
                         sort: \LogEntry.loggedAt,
                         order: .reverse)
    }

    private var totals: NutritionFacts { entries.map(\.total).total() }

    var body: some View {
        VStack(spacing: Spacing.m) {
            if showsHero {
                heroCard
                macroCard
            }
            if entries.isEmpty {
                EmptyStateView(symbol: "fork.knife",
                               title: "Nothing logged yet",
                               message: "Tap + to snap, scan, or search.")
            } else {
                ForEach(MealType.allCases) { meal in
                    let group = entries.filter { $0.mealType == meal }
                    if !group.isEmpty {
                        MealCard(meal: meal, entries: group,
                                 onSelect: { selectedEntry = $0 },
                                 onMove: move,
                                 onDelete: delete)
                    }
                }
            }
        }
        .sheet(item: $selectedEntry, onDismiss: flushPendingDelete) { entry in
            EntryDetailView(entry: entry) {
                pendingDelete = entry
                selectedEntry = nil
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        Card(padding: Spacing.l) {
            HStack(spacing: Spacing.s) {
                heroStat(title: "Eaten", value: totals.calories)
                    .frame(maxWidth: .infinity)
                CalorieRing(consumed: totals.calories, goal: settings.calorieGoal)
                    .frame(width: 184, height: 184)
                heroStat(title: "Goal", value: settings.calorieGoal)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func heroStat(title: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(Format.kcal(value))
                .font(MorselFont.numeral)
                .foregroundStyle(Color.mText)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(MorselFont.caption)
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    // MARK: - Macros

    private var macroCard: some View {
        Card {
            VStack(spacing: Spacing.m) {
                MacroBar(title: "Protein", value: totals.protein, goal: settings.proteinGoal, color: .mProtein)
                MacroBar(title: "Carbs", value: totals.carbs, goal: settings.carbsGoal, color: .mCarbs)
                MacroBar(title: "Fat", value: totals.fat, goal: settings.fatGoal, color: .mFat)
            }
        }
    }

    // MARK: - Mutations

    private func move(_ entry: LogEntry, to meal: MealType) {
        entry.mealType = meal
        try? context.save()
        if settings.hapticsEnabled { Haptics.tap() }
    }

    private func delete(_ entry: LogEntry) {
        PhotoStore.shared.delete(entry.photoFilename)
        context.delete(entry)
        try? context.save()
    }

    /// Deletion requested from the detail sheet runs after the sheet has gone away,
    /// so the sheet never renders a deleted model.
    private func flushPendingDelete() {
        guard let entry = pendingDelete else { return }
        pendingDelete = nil
        delete(entry)
    }
}

// MARK: - Meal card

/// All entries of one meal type inside a `Card`, with context-menu actions per row.
private struct MealCard: View {
    let meal: MealType
    let entries: [LogEntry]
    let onSelect: (LogEntry) -> Void
    let onMove: (LogEntry, MealType) -> Void
    let onDelete: (LogEntry) -> Void

    private var calories: Double { entries.map(\.total.calories).reduce(0, +) }

    var body: some View {
        Card {
            VStack(spacing: Spacing.xs) {
                SectionHeader(title: meal.title, trailing: Format.kcalWithUnit(calories))
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { onSelect(entry) } label: {
                        FoodRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: entry) }
                    if index < entries.count - 1 {
                        Divider().overlay(Color.mSeparator)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for entry: LogEntry) -> some View {
        Menu {
            ForEach(MealType.allCases.filter { $0 != entry.mealType }) { target in
                Button {
                    onMove(entry, target)
                } label: {
                    Label(target.title, systemImage: target.symbolName)
                }
            }
        } label: {
            Label("Move to…", systemImage: "arrow.turn.down.right")
        }
        Button(role: .destructive) {
            onDelete(entry)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
