import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .mAccent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MorselFont.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(tint.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MorselFont.headline)
            .foregroundStyle(Color.mText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.mSurfaceElevated.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var morselPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var morselSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Pill chip for selections (meal type, serving presets).
struct Chip: View {
    let title: String
    var symbol: String? = nil
    var isSelected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption) }
                Text(title).font(MorselFont.callout.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? Color.mAccentSoft : Color.mSurfaceElevated,
                        in: Capsule())
            .foregroundStyle(isSelected ? Color.mAccent : Color.mText)
        }
        .buttonStyle(.plain)
    }
}

/// The big floating "+" that opens the add menu.
struct FloatingAddButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.mAccent, in: Circle())
                .shadow(color: Color.mAccent.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log food")
    }
}
