import AuthenticationServices
import Foundation
import UIKit

/// What the app forwards to `POST /v1/auth/apple`.
struct AppleCredential: Equatable {
    let userID: String
    let identityToken: String
    let authorizationCode: String?
    let fullName: PersonNameComponents?
    let email: String?

    init?(authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8), !token.isEmpty else { return nil }
        userID = credential.user
        identityToken = token
        authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        fullName = credential.fullName
        email = credential.email
    }
}

/// Wraps `ASAuthorizationController` in one async call. Used when sign-in is triggered
/// programmatically (`AccountService.signIn(with: .apple)`); `SignInWithAppleButton` in the UI
/// goes through `AccountService.handleAppleAuthorization` instead.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var controller: ASAuthorizationController?

    func signIn() async throws -> AppleCredential {
        if continuation != nil { throw AccountError.cancelled }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        let pending = continuation
        continuation = nil
        controller = nil
        pending?.resume(with: result)
    }

    // MARK: ASAuthorizationControllerDelegate
    // The protocol requirements are nonisolated; AuthenticationServices calls them on the main
    // queue, so we hop back onto the main actor explicitly.

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = AppleCredential(authorization: authorization)
        Task { @MainActor in
            if let credential {
                self.finish(.success(credential))
            } else {
                self.finish(.failure(AccountError.invalidCallback))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let mapped: Error
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            mapped = AccountError.cancelled
        } else {
            mapped = error
        }
        Task { @MainActor in self.finish(.failure(mapped)) }
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { WebAuthPresenter.keyWindow() ?? ASPresentationAnchor() }
    }
}
