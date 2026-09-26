import SwiftUI
import SwiftData

/// Sheet for one logged entry: photo (if any), editable quantity, meal, nutrition and delete.
/// Edits are written to the model immediately; deletion is delegated to the parent via `onDelete`.
struct EntryDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let entry: LogEntry
    let onDelete: () -> Void

    @State private var quantity: Double
    @State private var mealType: MealType
    @State private var photo: UIImage?

    init(entry: LogEntry, onDelete: @escaping () -> Void) {
        self.entry = entry
        self.onDelete = onDelete
        _quantity = State(initialValue: entry.quantity)
        _mealType = State(initialValue: entry.mealType)
    }

    private var total: NutritionFacts { entry.perServing.scaled(by: quantity) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .accessibilityLabel("Meal photo")
                    }
                    headerCard
                    quantityCard
                    nutritionCard
                    if let confidence = entry.confidence {
                        HStack {
                            ConfidenceBadge(confidence: confidence)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.xs)
                    }
                    Button(role: .destructive) {
                        if settings.hapticsEnabled { Haptics.warning() }
                        onDelete()
                    } label: {
                        Text("Delete entry")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .mDanger))
                    .padding(.top, Spacing.s)
                }
                .padding(Spacing.m)
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { photo = PhotoStore.shared.load(entry.photoFilename) }
        .onChange(of: quantity) { _, newValue in
            entry.quantity = newValue
            try? context.save()
        }
        .onChange(of: mealType) { _, newValue in
            entry.mealType = newValue
            try? context.save()
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.kcal(total.calories))
                        .font(MorselFont.display)
                        .foregroundStyle(Color.mText)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(MorselFont.callout)
                        .foregroundStyle(Color.mTextSecondary)
                }
                if let brand = entry.brand, !brand.isEmpty {
                    Text(brand).font(MorselFont.callout).foregroundStyle(Color.mTextSecondary)
                }
                HStack(spacing: Spacing.s) {
                    Image(systemName: entry.source.symbolName)
                    Text(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(MorselFont.caption)
                .foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    private var quantityCard: some View {
        Card {
            VStack(spacing: Spacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Servings").font(MorselFont.callout).foregroundStyle(Color.mText)
                        Text(entry.servingDescription).font(MorselFont.caption).foregroundStyle(Color.mTextSecondary)
                    }
                    Spacer()
                    Text(Format.quantity(quantity))
                        .font(MorselFont.numeral)
                        .foregroundStyle(Color.mText)
                        .contentTransition(.numericText())
                    Stepper("Servings", value: $quantity, in: 0.25...50, step: 0.25)
                        .labelsHidden()
                }
                Divider().overlay(Color.mSeparator)
                HStack {
                    Text("Meal").font(MorselFont.callout).foregroundStyle(Color.mText)
                    Spacer()
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.title, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.mAccent)
                }
            }
        }
    }

    private var nutritionCard: some View {
        Card {
            VStack(spacing: Spacing.s) {
                nutrientRow("Protein", grams: total.protein, color: .mProtein)
                nutrientRow("Carbs", grams: total.carbs, color: .mCarbs)
                nutrientRow("Fat", grams: total.fat, color: .mFat)
                if let fiber = total.fiber { nutrientRow("Fiber", grams: fiber, color: .mTextTertiary) }
                if let sugar = total.sugar { nutrientRow("Sugar", grams: sugar, color: .mTextTertiary) }
                if let sodium = total.sodium {
                    HStack {
                        MacroDot(color: .mTextTertiary, text: "Sodium")
                        Spacer()
                        Text("\(Int(sodium.rounded())) mg")
                            .font(MorselFont.caption.monospacedDigit())
                            .foregroundStyle(Color.mText)
                    }
                }
            }
        }
    }

    private func nutrientRow(_ title: String, grams: Double, color: Color) -> some View {
        HStack {
            MacroDot(color: color, text: title)
            Spacer()
            Text(Format.grams(grams))
                .font(MorselFont.caption.monospacedDigit())
                .foregroundStyle(Color.mText)
        }
    }
}
