import AuthenticationServices
import Foundation
import UIKit

/// Supplies the window `ASWebAuthenticationSession` (and Sign in with Apple) presents from.
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    @MainActor
    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    /// Called on the main queue by AuthenticationServices.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Self.keyWindow() ?? ASPresentationAnchor() }
    }
}

/// Google / Facebook sign-in through the Worker:
/// open `/v1/auth/{provider}/start` in `ASWebAuthenticationSession`, receive
/// `freetrack://auth/callback?code=…&state=…`, hand the one-time code back to `AccountService`
/// which exchanges it (with the PKCE verifier) for session tokens.
@MainActor
enum WebOAuthFlow {
    /// Strong reference while the sheet is up; the system does not retain the session for us.
    private static var current: ASWebAuthenticationSession?

    /// Runs the browser flow and returns the one-time code from the callback URL.
    static func authenticate(startURL: URL, expectedState: String, presenter: WebAuthPresenter) async throws -> String {
        if current != nil { throw AccountError.cancelled }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: startURL, callbackURLScheme: AccountConfig.urlScheme) { url, error in
                Task { @MainActor in current = nil }
                if let url {
                    continuation.resume(returning: url)
                } else if let webError = error as? ASWebAuthenticationSessionError, webError.code == .canceledLogin {
                    continuation.resume(throwing: AccountError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? (AccountError.invalidCallback as Error))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            current = session
            if !session.start() {
                current = nil
                continuation.resume(throwing: AccountError.invalidCallback)
            }
        }
        return try parseCallback(callback, expectedState: expectedState)
    }

    /// Pure parser for `freetrack://auth/callback?code=…&state=…` (or `?error=…&state=…`).
    nonisolated static func parseCallback(_ url: URL, expectedState: String) throws -> String {
        guard url.scheme?.lowercased() == AccountConfig.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AccountError.invalidCallback
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { throw AccountError.stateMismatch }
        if let error = value("error") {
            throw error == "cancelled" ? AccountError.cancelled : AccountError.server(status: 400, message: error)
        }
        guard let code = value("code"), !code.isEmpty else { throw AccountError.invalidCallback }
        return code
    }
}
