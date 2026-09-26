import SwiftUI
import SwiftData

/// Hand-entered food. Not a flow: has no NavigationStack of its own so it can be pushed or wrapped
/// in a sheet by the caller. Calls `onSave` with the built `FoodItem`; the caller logs it.
struct ManualFoodFormView: View {
    // MARK: - Inputs

    let initialName: String?
    let barcode: String?
    let onSave: (FoodItem) -> Void

    init(initialName: String? = nil, barcode: String? = nil, onSave: @escaping (FoodItem) -> Void) {
        self.initialName = initialName
        self.barcode = barcode
        self.onSave = onSave
        _name = State(initialValue: initialName ?? "")
    }

    // MARK: - Environment & state

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brand = ""
    @State private var servingDescription = "1 serving"
    @State private var servingGramsText = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var fiberText = ""
    @State private var sugarText = ""
    @State private var sodiumText = ""
    @State private var showMore = false
    @State private var alsoFavorite = false
    @State private var attemptedSave = false

    // MARK: - Validation

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var calories: Double? { NumberParsing.nonNegativeDouble(caloriesText) }

    /// Nil when the form can be saved.
    private var validationMessage: String? {
        if trimmedName.isEmpty { return "Give the food a name." }
        if calories == nil { return "Enter calories (0 or more)." }
        for (label, text) in [("Serving grams", servingGramsText), ("Protein", proteinText), ("Carbs", carbsText),
                              ("Fat", fatText), ("Fiber", fiberText), ("Sugar", sugarText), ("Sodium", sodiumText)] {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && NumberParsing.nonNegativeDouble(trimmed) == nil {
                return "\(label) should be a number, 0 or more."
            }
        }
        return nil
    }

    private var canSave: Bool { validationMessage == nil }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                identityCard
                nutritionCard
                moreCard
                favoriteToggle
                if attemptedSave, let validationMessage {
                    InlineErrorView(message: validationMessage)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.mBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { saveButton }
        .navigationTitle("Create food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .keyboardDoneButton()
    }

    // MARK: - Sections

    private var identityCard: some View {
        Card {
            VStack(spacing: 0) {
                TextFieldRow(title: "Name", text: $name, placeholder: "Required")
                TextFieldRow(title: "Brand", text: $brand, placeholder: "Optional")
                TextFieldRow(title: "Serving", text: $servingDescription, placeholder: "1 serving")
                NumberField(title: "Serving weight", text: $servingGramsText, unit: "g", placeholder: "Optional")
                if let barcode, !barcode.isEmpty {
                    HStack {
                        Text("Barcode")
                            .font(MorselFont.body)
                            .foregroundStyle(Color.mText)
                        Spacer()
                        Text(barcode)
                            .font(MorselFont.body.monospacedDigit())
                            .foregroundStyle(Color.mTextSecondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var nutritionCard: some View {
        Card {
            VStack(spacing: 0) {
                Text("Per serving")
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NumberField(title: "Calories", text: $caloriesText, unit: "kcal", placeholder: "Required")
                NumberField(title: "Protein", text: $proteinText, unit: "g")
                NumberField(title: "Carbs", text: $carbsText, unit: "g")
                NumberField(title: "Fat", text: $fatText, unit: "g")
            }
        }
    }

    private var moreCard: some View {
        Card {
            DisclosureGroup(isExpanded: $showMore) {
                VStack(spacing: 0) {
                    NumberField(title: "Fiber", text: $fiberText, unit: "g")
                    NumberField(title: "Sugar", text: $sugarText, unit: "g")
                    NumberField(title: "Sodium", text: $sodiumText, unit: "mg")
                }
                .padding(.top, Spacing.xs)
            } label: {
                Text("Fiber, sugar, sodium")
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
            }
        }
    }

    private var favoriteToggle: some View {
        Card {
            Toggle(isOn: $alsoFavorite) {
                Label("Also save to favorites", systemImage: "star")
                    .font(MorselFont.body)
                    .foregroundStyle(Color.mText)
            }
            .tint(Color.mAccent)
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save & log")
        }
        .buttonStyle(.morselPrimary)
        .opacity(canSave ? 1 : 0.6)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Color.mBackground)
    }

    // MARK: - Actions

    private func positiveOrNil(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func save() {
        attemptedSave = true
        guard canSave, let kcal = calories else {
            Haptics.warning()
            return
        }
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedServing = servingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let nutrition = NutritionFacts(
            calories: kcal,
            protein: NumberParsing.nonNegativeDouble(proteinText) ?? 0,
            carbs: NumberParsing.nonNegativeDouble(carbsText) ?? 0,
            fat: NumberParsing.nonNegativeDouble(fatText) ?? 0,
            fiber: NumberParsing.nonNegativeDouble(fiberText),
            sugar: NumberParsing.nonNegativeDouble(sugarText),
            sodium: NumberParsing.nonNegativeDouble(sodiumText)
        )
        let food = FoodItem(name: trimmedName,
                            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
                            barcode: barcode,
                            servingDescription: trimmedServing.isEmpty ? "1 serving" : trimmedServing,
                            servingGrams: positiveOrNil(NumberParsing.nonNegativeDouble(servingGramsText)),
                            nutritionPerServing: nutrition,
                            source: .manual)
        if alsoFavorite {
            context.insert(FavoriteFood(food: food))
            try? context.save()
        }
        Haptics.tap()
        onSave(food)
    }
}
