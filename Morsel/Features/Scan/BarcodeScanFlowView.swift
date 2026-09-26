import SwiftUI
import SwiftData
import UIKit

// MARK: - BarcodeScanFlowView
// Sheet-hosted flow: live camera → lookup → bottom result card → one tap to log.
// Owns its NavigationStack; reports inserted entries (or []) through `onLogged`.

@MainActor
struct BarcodeScanFlowView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context

    @State private var model = BarcodeScanViewModel()
    private let onLogged: ([LogEntry]) -> Void
    private let cameraIsLive: Bool
    private let torchAvailable: Bool

    init(onLogged: @escaping ([LogEntry]) -> Void) {
        self.onLogged = onLogged
        let live = BarcodeScannerView.isLiveScanningSupported
        self.cameraIsLive = live
        self.torchAvailable = live && Torch.isAvailable
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mBackground.ignoresSafeArea()
                content
                if model.phase.isLoading {
                    LoadingOverlay(message: "Looking up…")
                        .zIndex(2)
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .animation(.spring(duration: 0.3), value: model.phase)
        }
        .onDisappear {
            model.cancelWork()
            if model.isTorchOn { Torch.set(on: false) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .manualEntry(let code):
            ManualFoodEntryForm(code: code,
                                onLog: { food, meal in log(food, quantity: 1, mealType: meal) },
                                onBack: { model.scanAgain() })
        default:
            ZStack {
                scannerLayer
                if cameraIsLive, model.phase == .scanning {
                    ScanReticleOverlay()
                }
            }
            .overlay(alignment: .bottom) { bottomPanel }
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var scannerLayer: some View {
        // On devices the camera stays up (paused) under the result card. In the Simulator
        // fallback the typed-entry form is replaced by the card so the keyboard goes away.
        if cameraIsLive || model.phase == .scanning {
            BarcodeScannerView(isPaused: model.isScannerPaused, onScan: { code in handleScan(code) })
        } else {
            Color.mBackground.ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        Group {
            switch model.phase {
            case .scanning:
                if cameraIsLive { ScanHint(text: "Point at a barcode") }
            case .loading, .manualEntry:
                EmptyView()
            case .found(let food, let code):
                ScanResultCard(food: food,
                               saveError: model.saveErrorMessage,
                               onLog: { quantity, meal in log(food, quantity: quantity, mealType: meal) },
                               onScanAgain: { model.scanAgain() })
                    .id(code)
            case .notFound(let code):
                ScanNotFoundCard(code: code,
                                 onScanAgain: { model.scanAgain() },
                                 onEnterManually: { model.enterManually() })
            case .failed(let message, _):
                ScanFailureCard(message: message,
                                onRetry: { model.retry(using: services.barcode) },
                                onScanAgain: { model.scanAgain() })
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.m)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                model.cancelWork()
                if model.isTorchOn { Torch.set(on: false) }
                onLogged([])
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if torchAvailable {
                Button {
                    model.isTorchOn = Torch.set(on: !model.isTorchOn)
                } label: {
                    Image(systemName: model.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                }
                .accessibilityLabel(model.isTorchOn ? "Turn torch off" : "Turn torch on")
            }
        }
    }

    // MARK: Actions

    private func handleScan(_ code: String) {
        guard model.phase == .scanning else { return }
        if settings.hapticsEnabled { Haptics.tap() }
        model.handleScan(code, using: services.barcode)
    }

    private func log(_ food: FoodItem, quantity: Double, mealType: MealType) {
        do {
            let entry = try context.log(food, quantity: quantity, mealType: mealType)
            if model.isTorchOn { Torch.set(on: false) }
            onLogged([entry])
        } catch {
            model.reportSaveFailure(error)
        }
    }
}

// MARK: - Camera decorations

/// Subtle rounded frame in the middle of the camera view.
private struct ScanReticleOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Color.white.opacity(0.7), lineWidth: 2)
            .frame(width: 260, height: 170)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// One-line hint pinned above the bottom edge of the camera.
private struct ScanHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(MorselFont.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.35), in: Capsule())
            .padding(.bottom, Spacing.l)
            .accessibilityHidden(true)
    }
}

// MARK: - Result card

/// Product summary + quantity + meal + the single "Log" button.
struct ScanResultCard: View {
    let food: FoodItem
    var saveError: String?
    var onLog: (Double, MealType) -> Void
    var onScanAgain: () -> Void

    @State private var quantity: Double = 1
    @State private var mealType: MealType = .suggested()

    private static let quantityRange: ClosedRange<Double> = 0.25...50
    private var total: NutritionFacts { food.nutritionPerServing.scaled(by: quantity) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                calorieLine
                macroRow
                quantityRow
                mealRow
                if let saveError {
                    Text(saveError)
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mDanger)
                }
                Button("Log · \(Format.kcalWithUnit(total.calories))") {
                    onLog(quantity, mealType)
                }
                .buttonStyle(.morselPrimary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ProductThumbnail(url: food.imageURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(MorselFont.headline)
                    .foregroundStyle(Color.mText)
                    .lineLimit(2)
                if let brand = food.brand, !brand.isEmpty {
                    Text(brand)
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mTextSecondary)
                        .lineLimit(1)
                }
                Text(food.servingDescription)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            Button("Scan again", action: onScanAgain)
                .font(MorselFont.caption.weight(.medium))
                .foregroundStyle(Color.mAccent)
        }
    }

    private var calorieLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(Format.kcal(total.calories))
                .font(Font.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.mText)
                .contentTransition(.numericText())
            Text("kcal")
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var macroRow: some View {
        HStack(spacing: Spacing.m) {
            MacroDot(color: .mProtein, text: "P \(Format.grams(total.protein))")
            MacroDot(color: .mCarbs, text: "C \(Format.grams(total.carbs))")
            MacroDot(color: .mFat, text: "F \(Format.grams(total.fat))")
        }
    }

    private var quantityRow: some View {
        HStack(spacing: Spacing.s) {
            Chip(title: "½", isSelected: quantity == 0.5) { quantity = 0.5 }
            Chip(title: "1", isSelected: quantity == 1) { quantity = 1 }
            Chip(title: "2", isSelected: quantity == 2) { quantity = 2 }
            Spacer(minLength: Spacing.s)
            Text(Self.quantityText(quantity))
                .font(MorselFont.numeral)
                .foregroundStyle(Color.mText)
                .contentTransition(.numericText())
            Stepper("Servings", value: $quantity, in: Self.quantityRange, step: 0.25)
                .labelsHidden()
                .accessibilityLabel("Servings")
                .accessibilityValue(Self.quantityText(quantity))
        }
    }

    private var mealRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(MealType.allCases) { meal in
                    Chip(title: meal.title, symbol: meal.symbolName, isSelected: meal == mealType) {
                        mealType = meal
                    }
                }
            }
        }
    }

    /// 0.25-step friendly formatting: "0.75", "1", "1.25".
    static func quantityText(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// Small product image with a placeholder while loading / when missing.
private struct ProductThumbnail: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "barcode")
                    .font(.title3)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
        .frame(width: 60, height: 60)
        .background(Color.mSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Not found / failure cards

struct ScanNotFoundCard: View {
    let code: String
    var onScanAgain: () -> Void
    var onEnterManually: () -> Void

    var body: some View {
        Card {
            VStack(spacing: Spacing.m) {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.mTextTertiary)
                    Text("Not in the database yet")
                        .font(MorselFont.headline)
                        .foregroundStyle(Color.mText)
                    Text("Barcode \(code)")
                        .font(MorselFont.caption.monospacedDigit())
                        .foregroundStyle(Color.mTextSecondary)
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: Spacing.s) {
                    Button("Scan again", action: onScanAgain)
                        .buttonStyle(.morselSecondary)
                    Button("Enter manually", action: onEnterManually)
                        .buttonStyle(.morselPrimary)
                }
            }
        }
    }
}

struct ScanFailureCard: View {
    let message: String
    var onRetry: () -> Void
    var onScanAgain: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.mWarning)
                    Text("Couldn't look that up")
                        .font(MorselFont.headline)
                        .foregroundStyle(Color.mText)
                }
                Text(message)
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                HStack(spacing: Spacing.s) {
                    Button("Scan again", action: onScanAgain)
                        .buttonStyle(.morselSecondary)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.morselPrimary)
                }
            }
        }
    }
}

// MARK: - Manual entry form

/// Inline form for products Open Food Facts does not know. Builds a `.manual` FoodItem
/// that keeps the scanned barcode.
struct ManualFoodEntryForm: View {
    let code: String
    var onLog: (FoodItem, MealType) -> Void
    var onBack: () -> Void

    @State private var name = ""
    @State private var servingDescription = "1 serving"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var mealType: MealType = .suggested()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, serving, calories, protein, carbs, fat }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var caloriesValue: Double? { Self.parse(calories) }
    private var canLog: Bool { !trimmedName.isEmpty && caloriesValue != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Enter manually")
                        .font(MorselFont.title)
                        .foregroundStyle(Color.mText)
                    Text("Barcode \(code)")
                        .font(MorselFont.caption.monospacedDigit())
                        .foregroundStyle(Color.mTextSecondary)
                }
                .padding(.top, Spacing.s)

                Card {
                    VStack(spacing: Spacing.s) {
                        row("Name", text: $name, field: .name, placeholder: "e.g. Granola bar")
                        row("Serving", text: $servingDescription, field: .serving, placeholder: "1 bar (40 g)")
                    }
                }

                Card {
                    VStack(spacing: Spacing.s) {
                        row("Calories", text: $calories, field: .calories, placeholder: "0", unit: "kcal", keyboard: .decimalPad)
                        row("Protein", text: $protein, field: .protein, placeholder: "0", unit: "g", keyboard: .decimalPad)
                        row("Carbs", text: $carbs, field: .carbs, placeholder: "0", unit: "g", keyboard: .decimalPad)
                        row("Fat", text: $fat, field: .fat, placeholder: "0", unit: "g", keyboard: .decimalPad)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(MealType.allCases) { meal in
                            Chip(title: meal.title, symbol: meal.symbolName, isSelected: meal == mealType) {
                                mealType = meal
                            }
                        }
                    }
                }

                Button("Log · \(Format.kcalWithUnit(caloriesValue ?? 0))", action: submit)
                    .buttonStyle(.morselPrimary)
                    .disabled(!canLog)
                    .opacity(canLog ? 1 : 0.5)

                Button("Back to scanning", action: onBack)
                    .buttonStyle(.morselSecondary)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.mBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear { focusedField = .name }
    }

    private func row(_ label: String, text: Binding<String>, field: Field, placeholder: String,
                     unit: String? = nil, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: Spacing.m) {
            Text(label)
                .font(MorselFont.body)
                .foregroundStyle(Color.mTextSecondary)
            Spacer(minLength: Spacing.s)
            TextField(placeholder, text: text)
                .font(MorselFont.body)
                .foregroundStyle(Color.mText)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .focused($focusedField, equals: field)
                .submitLabel(.next)
                .onSubmit { advance(from: field) }
            if let unit {
                Text(unit)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func advance(from field: Field) {
        switch field {
        case .name: focusedField = .serving
        case .serving: focusedField = .calories
        case .calories: focusedField = .protein
        case .protein: focusedField = .carbs
        case .carbs: focusedField = .fat
        case .fat: focusedField = nil
        }
    }

    private func submit() {
        guard canLog, let kcal = caloriesValue else { return }
        let facts = NutritionFacts(calories: kcal,
                                   protein: Self.parse(protein) ?? 0,
                                   carbs: Self.parse(carbs) ?? 0,
                                   fat: Self.parse(fat) ?? 0)
        let serving = OpenFoodFactsMapper.cleaned(servingDescription) ?? "1 serving"
        let food = FoodItem(name: trimmedName,
                            barcode: code,
                            servingDescription: serving,
                            nutritionPerServing: facts,
                            source: .manual)
        onLog(food, mealType)
    }

    /// Non-negative number or nil. Accepts "1,5" as well as "1.5".
    private static func parse(_ text: String) -> Double? {
        guard let value = OpenFoodFactsMapper.parseNumber(text), value >= 0, value.isFinite else { return nil }
        return value
    }
}
