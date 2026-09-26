import SwiftUI

/// Shared confirm step: pick quantity (servings or grams), meal, optionally tweak nutrition, then log.
/// Pushed inside a `NavigationStack`; the caller owns the meal-type binding and performs the write.
struct ServingEditorView: View {
    // MARK: - Inputs

    let food: FoodItem
    @Binding var mealType: MealType
    let onConfirm: (FoodItem, Double) -> Void

    // MARK: - State

    private enum QuantityMode: Hashable { case servings, grams }

    @State private var quantity: Double
    @State private var mode: QuantityMode = .servings
    @State private var gramsText: String = ""
    @State private var showNutritionEditor = false
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String

    init(food: FoodItem, initialQuantity: Double, mealType: Binding<MealType>,
         onConfirm: @escaping (FoodItem, Double) -> Void) {
        self.food = food
        self._mealType = mealType
        self.onConfirm = onConfirm
        _quantity = State(initialValue: ServingMath.clamped(initialQuantity))
        let n = food.nutritionPerServing
        _caloriesText = State(initialValue: NumberParsing.string(from: n.calories))
        _proteinText = State(initialValue: NumberParsing.string(from: n.protein))
        _carbsText = State(initialValue: NumberParsing.string(from: n.carbs))
        _fatText = State(initialValue: NumberParsing.string(from: n.fat))
    }

    // MARK: - Derived

    /// `food` with any nutrition edits applied. Source is preserved.
    private var currentFood: FoodItem {
        var item = food
        var n = item.nutritionPerServing
        if let v = NumberParsing.nonNegativeDouble(caloriesText) { n.calories = v }
        if let v = NumberParsing.nonNegativeDouble(proteinText) { n.protein = v }
        if let v = NumberParsing.nonNegativeDouble(carbsText) { n.carbs = v }
        if let v = NumberParsing.nonNegativeDouble(fatText) { n.fat = v }
        item.nutritionPerServing = n
        return item
    }

    private var total: NutritionFacts {
        ServingMath.nutrition(currentFood.nutritionPerServing, quantity: quantity)
    }

    private var currentGrams: Double? {
        ServingMath.grams(forQuantity: quantity, servingGrams: food.servingGrams)
    }

    private var supportsGrams: Bool { (food.servingGrams ?? 0) > 0 }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                header
                calorieHero
                quantityCard
                mealCard
                nutritionEditor
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.mBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { logButton }
        .navigationTitle("Serving")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .onChange(of: mode) { _, newMode in
            if newMode == .grams, let grams = currentGrams {
                gramsText = NumberParsing.string(from: grams, maxFractionDigits: 1)
            }
        }
        .onChange(of: gramsText) { _, newText in
            guard mode == .grams, let grams = NumberParsing.nonNegativeDouble(newText),
                  let q = ServingMath.quantity(forGrams: grams, servingGrams: food.servingGrams) else { return }
            quantity = q
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            Text(food.name)
                .font(MorselFont.title)
                .foregroundStyle(Color.mText)
                .multilineTextAlignment(.center)
            if let brand = food.brand, !brand.isEmpty {
                Text(brand)
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
            }
            Text("Per serving: \(food.servingDescription)")
                .font(MorselFont.caption)
                .foregroundStyle(Color.mTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.s)
    }

    private var calorieHero: some View {
        VStack(spacing: Spacing.xs) {
            Text(Format.kcal(total.calories))
                .font(MorselFont.display)
                .foregroundStyle(Color.mText)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: total.calories)
            Text("kcal")
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
            HStack(spacing: Spacing.m) {
                MacroDot(color: .mProtein, text: "Protein \(Format.grams(total.protein))")
                MacroDot(color: .mCarbs, text: "Carbs \(Format.grams(total.carbs))")
                MacroDot(color: .mFat, text: "Fat \(Format.grams(total.fat))")
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var quantityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Amount")
                    .font(MorselFont.headline)
                    .foregroundStyle(Color.mText)

                if supportsGrams {
                    Picker("Amount mode", selection: $mode) {
                        Text("Servings").tag(QuantityMode.servings)
                        Text("Grams").tag(QuantityMode.grams)
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .grams && supportsGrams {
                    gramsControls
                } else {
                    servingsControls
                }
            }
        }
    }

    private var servingsControls: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                ForEach(ServingMath.chipQuantities, id: \.self) { preset in
                    Chip(title: ServingMath.label(for: preset),
                         isSelected: ServingMath.matches(quantity, preset)) {
                        Haptics.tap()
                        quantity = preset
                    }
                    .accessibilityLabel("\(ServingMath.label(for: preset)) servings")
                }
            }
            Stepper(value: $quantity,
                    in: ServingMath.minimumQuantity...ServingMath.maximumQuantity,
                    step: ServingMath.step) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ServingMath.label(for: quantity)) × \(food.servingDescription)")
                        .font(MorselFont.body)
                        .foregroundStyle(Color.mText)
                    if let grams = currentGrams {
                        Text("≈ \(Format.grams(grams))")
                            .font(MorselFont.caption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                }
            }
        }
    }

    private var gramsControls: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                TextField("0", text: $gramsText)
                    .keyboardType(.decimalPad)
                    .font(MorselFont.numeral)
                    .foregroundStyle(Color.mText)
                    .frame(maxWidth: 140)
                    .accessibilityLabel("Grams")
                Text("g")
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                Spacer()
                Text("= \(ServingMath.label(for: quantity)) servings")
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextSecondary)
            }
            if let servingGrams = food.servingGrams {
                Text("One serving is \(Format.grams(servingGrams)).")
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    private var mealCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Meal")
                    .font(MorselFont.headline)
                    .foregroundStyle(Color.mText)
                MealTypeChips(selection: $mealType)
            }
        }
    }

    private var nutritionEditor: some View {
        Card {
            DisclosureGroup(isExpanded: $showNutritionEditor) {
                VStack(spacing: 0) {
                    Text("Per serving")
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.s)
                    NumberField(title: "Calories", text: $caloriesText, unit: "kcal")
                    NumberField(title: "Protein", text: $proteinText, unit: "g")
                    NumberField(title: "Carbs", text: $carbsText, unit: "g")
                    NumberField(title: "Fat", text: $fatText, unit: "g")
                }
            } label: {
                Text("Edit nutrition")
                    .font(MorselFont.headline)
                    .foregroundStyle(Color.mText)
            }
        }
    }

    private var logButton: some View {
        Button {
            Haptics.tap()
            onConfirm(currentFood, quantity)
        } label: {
            Text("Log · \(Format.kcalWithUnit(total.calories))")
                .contentTransition(.numericText())
        }
        .buttonStyle(.morselPrimary)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Color.mBackground)
    }
}
