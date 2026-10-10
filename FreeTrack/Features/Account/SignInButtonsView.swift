import AuthenticationServices
import SwiftUI

/// Three full-width sign-in buttons (Apple, Google, Facebook) plus the "why" line and an optional
/// "Continue without an account" escape hatch. Used by onboarding and Settings.
struct SignInButtonsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    var showsWhy = true
    var onContinueWithout: (() -> Void)? = nil
    var onSignedIn: (() -> Void)? = nil

    @State private var busyProvider: AuthProvider?

    private var account: AccountService { services.account }

    var body: some View {
        VStack(spacing: Spacing.s) {
            if showsWhy {
                Text("Why sign in? Keeps your log and body scans backed up across devices.")
                    .font(FreeTrackFont.caption)
                    .foregroundStyle(Color.mTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Spacing.xs)
            }

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await completeApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .disabled(account.isBusy)
            .accessibilityLabel("Continue with Apple")

            providerButton(.google, symbol: "g.circle.fill", title: "Continue with Google")
            providerButton(.facebook, symbol: "f.circle.fill", title: "Continue with Facebook")

            if let message = account.lastError {
                Text(message)
                    .font(FreeTrackFont.caption)
                    .foregroundStyle(Color.mDanger)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if !account.isConfigured {
                Text("Accounts aren't set up on this build yet. Add the server URL in Settings > Account.")
                    .font(FreeTrackFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let onContinueWithout {
                Button("Continue without an account", action: onContinueWithout)
                    .font(FreeTrackFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private func providerButton(_ provider: AuthProvider, symbol: String, title: String) -> some View {
        Button {
            Task { await signIn(provider) }
        } label: {
            HStack(spacing: Spacing.s) {
                if busyProvider == provider {
                    ProgressView().tint(Color.mText)
                } else {
                    Image(systemName: symbol).font(.title3)
                }
                Text(title)
            }
        }
        .buttonStyle(.freeTrackSecondary)
        .disabled(account.isBusy)
        .accessibilityLabel(title)
    }

    private func signIn(_ provider: AuthProvider) async {
        busyProvider = provider
        defer { busyProvider = nil }
        do {
            try await account.signIn(with: provider)
            if account.isSignedIn { onSignedIn?() }
        } catch {
            // `account.lastError` carries the message; cancellation is silent.
        }
    }

    private func completeApple(_ result: Result<ASAuthorization, Error>) async {
        busyProvider = .apple
        defer { busyProvider = nil }
        await account.handleAppleAuthorization(result)
        if account.isSignedIn { onSignedIn?() }
    }
}
