import SwiftUI
import UIKit

// MARK: - Number field

/// Label on the left, right-aligned numeric text field with an optional unit suffix.
struct NumberField: View {
    let title: String
    @Binding var text: String
    var unit: String? = nil
    var placeholder: String = "0"
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(title)
                .font(MorselFont.body)
                .foregroundStyle(Color.mText)
            Spacer(minLength: Spacing.s)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(MorselFont.body.monospacedDigit())
                .foregroundStyle(Color.mText)
                .frame(maxWidth: 120)
                .accessibilityLabel(title)
            if let unit {
                Text(unit)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextSecondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Text field row

/// Label on the left, free-text field on the right (name, brand, serving description).
struct TextFieldRow: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(title)
                .font(MorselFont.body)
                .foregroundStyle(Color.mText)
            Spacer(minLength: Spacing.s)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .font(MorselFont.body)
                .foregroundStyle(Color.mText)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Meal chips

/// Horizontal row of meal-type chips bound to a selection.
struct MealTypeChips: View {
    @Binding var selection: MealType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(MealType.allCases) { meal in
                    Chip(title: meal.title, symbol: meal.symbolName, isSelected: selection == meal) {
                        Haptics.tap()
                        selection = meal
                    }
                    .accessibilityAddTraits(selection == meal ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
    }
}

// MARK: - Inline error

/// Plain-English failure message with an optional retry, shown in place (never modal).
struct InlineErrorView: View {
    let message: String
    var retryTitle: String = "Try again"
    var retry: (() -> Void)? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Color.mWarning)
                    Text(message)
                        .font(MorselFont.callout)
                        .foregroundStyle(Color.mText)
                }
                if let retry {
                    Button(retryTitle, action: retry)
                        .buttonStyle(.morselSecondary)
                }
            }
        }
    }
}

// MARK: - Keyboard helpers

enum KeyboardDismiss {
    /// Resigns whichever text field is first responder.
    @MainActor static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Adds a "Done" button above the keyboard that dismisses it.
    @MainActor func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { KeyboardDismiss.dismiss() }
                    .font(MorselFont.callout.weight(.semibold))
            }
        }
    }
}
