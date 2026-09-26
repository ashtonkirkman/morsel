import SwiftUI
import SwiftData

/// Keyboard-first "just the calories" entry. Presented at a medium detent; owns its NavigationStack.
struct QuickAddFlowView: View {
    // MARK: - Inputs

    let prefillName: String?
    let onLogged: ([LogEntry]) -> Void

    init(prefillName: String? = nil, onLogged: @escaping ([LogEntry]) -> Void) {
        self.prefillName = prefillName
        self.onLogged = onLogged
        _name = State(initialValue: prefillName ?? "")
    }

    // MARK: - Environment & state

    private enum Field: Hashable { case calories, name }

    @Environment(\.modelContext) private var context
    @FocusState private var focus: Field?
    @State private var caloriesText = ""
    @State private var name: String
    @State private var showMacros = false
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var mealType: MealType = .suggested()
    @State private var errorMessage: String?

    // MARK: - Derived

    private var calories: Double? { NumberParsing.nonNegativeDouble(caloriesText) }
    private var canLog: Bool { (calories ?? 0) > 0 }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    caloriesHero
                    detailsCard
                    MealTypeChips(selection: $mealType)
                    if let errorMessage {
                        InlineErrorView(message: errorMessage)
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.mBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { logButton }
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onLogged([]) }
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: focusCalories)
        }
    }

    // MARK: - Sections

    private var caloriesHero: some View {
        VStack(spacing: Spacing.xs) {
            TextField("0", text: $caloriesText)
                .keyboardType(.numberPad)
                .font(MorselFont.display)
                .foregroundStyle(Color.mText)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .calories)
                .accessibilityLabel("Calories")
            Text("kcal")
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s)
    }

    private var detailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                TextField("Name (optional, defaults to “Quick add”)", text: $name)
                    .font(MorselFont.body)
                    .foregroundStyle(Color.mText)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focus, equals: .name)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Name")
                DisclosureGroup(isExpanded: $showMacros) {
                    VStack(spacing: 0) {
                        NumberField(title: "Protein", text: $proteinText, unit: "g")
                        NumberField(title: "Carbs", text: $carbsText, unit: "g")
                        NumberField(title: "Fat", text: $fatText, unit: "g")
                    }
                    .padding(.top, Spacing.xs)
                } label: {
                    Text("Add macros")
                        .font(MorselFont.callout)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
        }
    }

    private var logButton: some View {
        Button {
            logEntry()
        } label: {
            Text(canLog ? "Log · \(Format.kcalWithUnit(calories ?? 0))" : "Log")
        }
        .buttonStyle(.morselPrimary)
        .disabled(!canLog)
        .opacity(canLog ? 1 : 0.5)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Color.mBackground)
    }

    // MARK: - Actions

    private func focusCalories() {
        // A short delay lets the sheet finish presenting before the keyboard comes up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            focus = .calories
        }
    }

    private func logEntry() {
        guard let kcal = calories, kcal > 0 else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nutrition = NutritionFacts(
            calories: kcal,
            protein: NumberParsing.nonNegativeDouble(proteinText) ?? 0,
            carbs: NumberParsing.nonNegativeDouble(carbsText) ?? 0,
            fat: NumberParsing.nonNegativeDouble(fatText) ?? 0
        )
        let food = FoodItem(name: trimmedName.isEmpty ? "Quick add" : trimmedName,
                            servingDescription: "1 serving",
                            nutritionPerServing: nutrition,
                            source: .manual)
        do {
            let entry = try context.log(food, quantity: 1, mealType: mealType)
            Haptics.tap()
            onLogged([entry])
        } catch {
            errorMessage = "Couldn't save that entry. Please try again."
        }
    }
}
