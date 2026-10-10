import SwiftUI

/// Onboarding page 2: optional sign-in. Both a successful sign-in and "Continue without an
/// account" advance the flow; nothing here is required.
struct AccountPage: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                OnboardingHeading(title: "Back up your data",
                                  subtitle: "Sign in to keep your log, goals and body scans safe and in sync across devices. You can skip this and sign in later from Settings.")
                Card {
                    SignInButtonsView(showsWhy: false, onContinueWithout: nil, onSignedIn: onContinue)
                }
                Button("Continue without an account", action: onContinue)
                    .buttonStyle(.freeTrackSecondary)
                Text("Everything still works offline. Without an account your data stays only on this phone.")
                    .font(FreeTrackFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.l)
        }
    }
}
