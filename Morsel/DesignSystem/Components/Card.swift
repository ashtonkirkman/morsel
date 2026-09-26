import SwiftUI

/// Soft rounded surface; the only container style in the app.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.m
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(MorselFont.headline)
                .foregroundStyle(Color.mText)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextSecondary)
            }
        }
        .padding(.horizontal, Spacing.xs)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.mTextTertiary)
            Text(title)
                .font(MorselFont.headline)
                .foregroundStyle(Color.mText)
            if let message {
                Text(message)
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}
