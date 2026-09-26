import SwiftUI

/// The four ways to log. Photo first, since it is the lowest-effort path.
@MainActor
struct AddMenuView: View {
    let onChoose: (AddRoute) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Spacing.m) {
            Text("Log food")
                .font(MorselFont.title)
                .foregroundStyle(Color.mText)
                .padding(.top, Spacing.l)
            VStack(spacing: Spacing.s) {
                option(.snap, symbol: "camera.fill", title: "Snap a photo", detail: "AI estimates the whole plate")
                option(.scan, symbol: "barcode.viewfinder", title: "Scan barcode", detail: "Packaged food, instant")
                option(.search, symbol: "magnifyingglass", title: "Search", detail: "Type a food or pick a favorite")
                option(.quickAdd, symbol: "bolt.fill", title: "Quick add", detail: "Just the calories")
            }
            .padding(.horizontal, Spacing.m)
            Spacer(minLength: 0)
        }
        .background(Color.mBackground.ignoresSafeArea())
    }

    private func option(_ route: AddRoute, symbol: String, title: String, detail: String) -> some View {
        Button {
            Haptics.tap()
            onChoose(route)
        } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.mAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.mAccentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MorselFont.headline).foregroundStyle(Color.mText)
                    Text(detail).font(MorselFont.caption).foregroundStyle(Color.mTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.mTextTertiary)
            }
            .padding(Spacing.m)
            .background(Color.mSurface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
