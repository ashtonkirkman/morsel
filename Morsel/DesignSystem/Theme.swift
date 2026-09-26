import SwiftUI

// MARK: - Design tokens
// Minimalist: one accent, warm neutrals, big numerals, generous spacing, soft 20pt cards.

extension Color {
    /// Dynamic color from light/dark hex values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static let mBackground = Color(light: 0xFAF9F6, dark: 0x0F0F10)
    static let mSurface = Color(light: 0xFFFFFF, dark: 0x1B1B1E)
    static let mSurfaceElevated = Color(light: 0xF2F0EB, dark: 0x26262A)
    static let mText = Color(light: 0x141414, dark: 0xF4F4F2)
    static let mTextSecondary = Color(light: 0x6E6E73, dark: 0x9C9CA3)
    static let mTextTertiary = Color(light: 0xA6A6AB, dark: 0x6B6B72)
    static let mSeparator = Color(light: 0xE8E6E1, dark: 0x2E2E33)
    /// Single brand accent: a calm green.
    static let mAccent = Color(light: 0x2F8F5B, dark: 0x4CC38A)
    static let mAccentSoft = Color(light: 0xE4F3EA, dark: 0x173323)
    static let mWarning = Color(light: 0xD98E1B, dark: 0xF0B14E)
    static let mDanger = Color(light: 0xD1453B, dark: 0xF07167)

    // Macro colors (muted, distinguishable, colorblind-friendly triad)
    static let mProtein = Color(light: 0x3B6FD1, dark: 0x7AA2F7)
    static let mCarbs = Color(light: 0xD98E1B, dark: 0xF0B14E)
    static let mFat = Color(light: 0xB65AA8, dark: 0xD68CD0)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let card: CGFloat = 20
    static let control: CGFloat = 14
    static let chip: CGFloat = 999
}

enum MorselFont {
    /// Hero numeral (today's calories).
    static let display = Font.system(size: 56, weight: .semibold, design: .rounded)
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .default)
    static let callout = Font.system(.callout, design: .default)
    static let caption = Font.system(.caption, design: .rounded)
    static let numeral = Font.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()
}

// MARK: - Formatting

enum Format {
    static func kcal(_ value: Double) -> String { "\(Int(value.rounded()))" }
    static func kcalWithUnit(_ value: Double) -> String { "\(Int(value.rounded())) kcal" }
    static func grams(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f g", value) : "\(Int(value.rounded())) g"
    }
    static func quantity(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.2g", value)
    }
    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
}

// MARK: - Haptics

enum Haptics {
    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    @MainActor static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    @MainActor static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
