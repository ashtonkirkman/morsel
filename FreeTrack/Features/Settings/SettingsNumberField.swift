import SwiftUI

/// Label + right-aligned numeric text field row. Parses as the user types; reformats only when focus leaves,
/// so partial input ("", "6", "68.") is never clobbered mid-entry. Used by Settings goals/profile and Onboarding.
struct SettingsNumberField: View {
    let title: String
    var unit: String? = nil
    @Binding var value: Double
    var fractionDigits: Int = 0
    var placeholder: String = ""

    @State private var text: String
    @FocusState private var focused: Bool

    init(title: String, unit: String? = nil, value: Binding<Double>, fractionDigits: Int = 0, placeholder: String = "") {
        self.title = title
        self.unit = unit
        self._value = value
        self.fractionDigits = fractionDigits
        self.placeholder = placeholder
        // Seed from the binding on construction so the row is never blank for a frame and never
        // depends on `onAppear` after a TabView page or `.id()` re-creation.
        self._text = State(initialValue: NumberFieldFormat.string(value.wrappedValue, fractionDigits: fractionDigits))
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(title)
                .font(FreeTrackFont.body)
                .foregroundStyle(Color.mText)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(FreeTrackFont.body.monospacedDigit())
                .foregroundStyle(Color.mText)
                .frame(maxWidth: 120)
                .focused($focused)
                .accessibilityLabel(title)
            if let unit {
                Text(unit)
                    .font(FreeTrackFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .onAppear { if !focused { text = formatted(value) } }
        .onChange(of: text) { _, newText in
            // Only push complete numbers; an empty or half-typed field leaves the stored value alone.
            if let parsed = NumberFieldFormat.parse(newText), parsed != value {
                value = parsed
            }
        }
        .onChange(of: value) { _, newValue in
            if !focused { text = formatted(newValue) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = formatted(value) }
        }
    }

    private func formatted(_ v: Double) -> String {
        NumberFieldFormat.string(v, fractionDigits: fractionDigits)
    }
}

/// Narrow numeric field with a trailing unit, for several values on one row (e.g. "5 ft 6 in").
struct CompactNumberField: View {
    let unit: String
    @Binding var value: Double
    var accessibilityLabel: String = ""

    @State private var text: String
    @FocusState private var focused: Bool

    init(unit: String, value: Binding<Double>, accessibilityLabel: String = "") {
        self.unit = unit
        self._value = value
        self.accessibilityLabel = accessibilityLabel
        self._text = State(initialValue: NumberFieldFormat.string(value.wrappedValue, fractionDigits: 0))
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(FreeTrackFont.body.monospacedDigit())
                .foregroundStyle(Color.mText)
                .frame(width: 44)
                .focused($focused)
                .accessibilityLabel(accessibilityLabel.isEmpty ? unit : accessibilityLabel)
            Text(unit)
                .font(FreeTrackFont.callout)
                .foregroundStyle(Color.mTextSecondary)
                .frame(minWidth: 20, alignment: .leading)
        }
        .onAppear { if !focused { text = formatted(value) } }
        .onChange(of: text) { _, newText in
            if let parsed = NumberFieldFormat.parse(newText), parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            if !focused { text = formatted(newValue) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = formatted(value) }
        }
    }

    private func formatted(_ v: Double) -> String {
        NumberFieldFormat.string(v, fractionDigits: 0)
    }
}

/// Shared parse/format rules for the numeric rows.
enum NumberFieldFormat {
    /// Accepts "," as a decimal separator (decimal pads in many locales show it). Returns nil for
    /// empty, partial or non-finite input and for negatives, so typing never writes garbage upstream.
    static func parse(_ raw: String) -> Double? {
        let normalized = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let parsed = Double(normalized), parsed.isFinite, parsed >= 0 else { return nil }
        return parsed
    }

    static func string(_ v: Double, fractionDigits: Int) -> String {
        guard v.isFinite else { return "" }
        if fractionDigits == 0 { return "\(Int(v.rounded()))" }
        return String(format: "%.\(fractionDigits)f", v)
    }
}

// MARK: - Keyboard dismissal

extension View {
    /// Adds a "Done" button above numeric keyboards (which have no return key).
    ///
    /// Apply it *inside* the content that owns the text fields (a `NavigationStack` child, or the page
    /// of a paged `TabView`). Declared above a `TabView` it does not reach the pages, which is why
    /// `ProfilePage` in onboarding carries its own.
    @MainActor func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(FreeTrackFont.callout.weight(.semibold))
            }
        }
    }
}
