import SwiftUI

/// One-time explainer before the first scan: on-device only, what is stored, what syncs, accuracy.
struct BodyScanIntroSheet: View {
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.mAccent)
                        Text("Body scans stay on your phone")
                            .font(FreeTrackFont.title)
                            .foregroundStyle(Color.mText)
                        Text("Free Track measures you from three photos using Apple's on-device vision models. Nothing is uploaded to analyse them.")
                            .font(FreeTrackFont.body)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                    point("lock.shield", "Photos never leave this phone",
                          "They are stored only in the app's private folder. If you later sign in and turn on sync, only the numbers (waist, body fat, …) are synced. Photos are not.")
                    point("ruler", "Estimates, not a tape measure",
                          "Lengths come from detected joints, circumferences from your silhouette. Expect ±5–10%. The value is in the trend: scan the same way each time.")
                    point("heart.text.square", "Not medical advice",
                          "Body fat is estimated with the Relative Fat Mass formula from your waist and height. It is a rough guide, not a diagnosis.")
                    point("camera", "Plain background, full body",
                          "Prop the phone at hip height 2–3 m away, stand against a plain wall in fitted clothes, and use the self-timer.")
                }
                .padding(Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.mBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button("Got it, start scanning", action: onContinue)
                    .buttonStyle(.freeTrackPrimary)
                    .padding(Spacing.m)
                    .background(Color.mBackground)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.mAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                Text(detail).font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
            }
        }
    }
}
