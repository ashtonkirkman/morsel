import SwiftUI

/// Thin ring for calories consumed vs. goal, with the hero numeral inside.
struct CalorieRing: View {
    let consumed: Double
    let goal: Double
    var lineWidth: CGFloat = 12

    private var fraction: Double { goal > 0 ? min(consumed / goal, 1) : 0 }
    private var over: Bool { goal > 0 && consumed > goal }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.mSurfaceElevated, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(over ? Color.mWarning : Color.mAccent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text(Format.kcal(max(goal - consumed, 0)))
                    .font(MorselFont.display)
                    .foregroundStyle(Color.mText)
                    .contentTransition(.numericText())
                Text(over ? "\(Format.kcal(consumed - goal)) over" : "left")
                    .font(MorselFont.callout)
                    .foregroundStyle(over ? Color.mWarning : Color.mTextSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.kcal(consumed)) of \(Format.kcal(goal)) calories")
    }
}

/// Horizontal macro bar with label + grams.
struct MacroBar: View {
    let title: String
    let value: Double
    let goal: Double
    let color: Color

    private var fraction: Double { goal > 0 ? min(value / goal, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(MorselFont.caption).foregroundStyle(Color.mTextSecondary)
                Spacer()
                Text("\(Format.grams(value)) / \(Format.grams(goal))")
                    .font(MorselFont.caption.monospacedDigit())
                    .foregroundStyle(Color.mTextSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mSurfaceElevated)
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                        .animation(.spring(duration: 0.5), value: fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Small colored dot + label used in legends.
struct MacroDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(MorselFont.caption).foregroundStyle(Color.mTextSecondary)
        }
    }
}

/// Full-screen translucent progress overlay for network work.
struct LoadingOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Spacing.m) {
                ProgressView().controlSize(.large).tint(.white)
                Text(message).font(MorselFont.callout).foregroundStyle(.white)
            }
            .padding(Spacing.l)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .transition(.opacity)
    }
}

/// Compact confidence indicator for AI estimates.
struct ConfidenceBadge: View {
    let confidence: Double
    private var label: String {
        confidence >= 0.8 ? "High confidence" : (confidence >= 0.5 ? "Medium confidence" : "Low confidence")
    }
    private var color: Color {
        confidence >= 0.8 ? .mAccent : (confidence >= 0.5 ? .mWarning : .mDanger)
    }
    var body: some View {
        Text(label)
            .font(MorselFont.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
