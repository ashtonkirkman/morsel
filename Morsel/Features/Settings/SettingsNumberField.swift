import SwiftUI

/// Label + right-aligned numeric text field row. Parses as the user types; reformats when focus leaves.
/// Used by Settings goals/profile and Onboarding.
struct SettingsNumberField: View {
    let title: String
    var unit: String? = nil
    @Binding var value: Double
    var fractionDigits: Int = 0
    var placeholder: String = ""

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(title)
                .font(MorselFont.body)
                .foregroundStyle(Color.mText)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(MorselFont.body.monospacedDigit())
                .foregroundStyle(Color.mText)
                .frame(maxWidth: 120)
                .focused($focused)
                .accessibilityLabel(title)
            if let unit {
                Text(unit)
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .onAppear { text = formatted(value) }
        .onChange(of: text) { _, newText in
            let normalized = newText.replacingOccurrences(of: ",", with: ".")
            if let parsed = Double(normalized), parsed >= 0, parsed != value {
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
        if fractionDigits == 0 { return "\(Int(v.rounded()))" }
        return String(format: "%.\(fractionDigits)f", v)
    }
}

/// Narrow numeric field with a trailing unit, for several values on one row (e.g. "5 ft 6 in").
struct CompactNumberField: View {
    let unit: String
    @Binding var value: Double
    var accessibilityLabel: String = ""

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(MorselFont.body.monospacedDigit())
                .foregroundStyle(Color.mText)
                .frame(width: 44)
                .focused($focused)
                .accessibilityLabel(accessibilityLabel.isEmpty ? unit : accessibilityLabel)
            Text(unit)
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
                .frame(minWidth: 20, alignment: .leading)
        }
        .onAppear { text = "\(Int(value.rounded()))" }
        .onChange(of: text) { _, newText in
            if let parsed = Double(newText), parsed >= 0, parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            if !focused { text = "\(Int(newValue.rounded()))" }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = "\(Int(value.rounded()))" }
        }
    }
}

// MARK: - Keyboard dismissal

extension View {
    /// Adds a "Done" button above numeric keyboards (which have no return key).
    @MainActor func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(MorselFont.callout.weight(.semibold))
            }
        }
    }
}
