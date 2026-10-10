import AuthenticationServices
import Foundation
import Observation

/// Who is signed in, and how to sign in/out. Tokens live in the Keychain; the cached user
/// profile lives in `AppSettings` so the UI is right at launch before any network call.
@Observable
@MainActor
final class AccountService {
    enum State: Equatable {
        case signedOut
        case signedIn(AccountUser)
    }

    private(set) var state: State = .signedOut
    private(set) var isBusy = false
    /// Last sign-in / sign-out failure, for the UI. Cleared on the next attempt.
    var lastError: String?
    /// Called after sign-in, sign-out and account deletion (the `SyncEngine` hooks in here).
    var onSessionChanged: (() -> Void)?

    let api: any AccountAPI
    private let settings: AppSettings
    private let keychain = KeychainStore.shared
    private let appleCoordinator = AppleSignInCoordinator()
    private let presenter = WebAuthPresenter()
    private var refreshTask: Task<SessionBundle, Error>?

    init(api: any AccountAPI, settings: AppSettings) {
        self.api = api
        self.settings = settings
        if let data = settings.accountUserData,
           let user = try? SyncCodec.decoder.decode(AccountUser.self, from: data),
           keychain.read(.refreshToken) != nil {
            state = .signedIn(user)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var user: AccountUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var isConfigured: Bool { api.isConfigured }

    // MARK: - Sign in

    /// Programmatic sign-in with any provider. Throws `AccountError.cancelled` when the user backs out.
    func signIn(with provider: AuthProvider) async throws {
        guard api.isConfigured else { throw AccountError.notConfigured }
        lastError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            switch provider {
            case .apple:
                let credential = try await appleCoordinator.signIn()
                try await completeAppleSignIn(credential)
            case .google, .facebook:
                let pkce = PKCE.generate()
                let state = PKCE.randomState()
                guard let url = api.startURL(provider: provider, codeChallenge: pkce.challenge, state: state) else {
                    throw AccountError.notConfigured
                }
                let code = try await WebOAuthFlow.authenticate(startURL: url, expectedState: state, presenter: presenter)
                let bundle = try await api.exchange(code: code, codeVerifier: pkce.verifier)
                install(bundle)
            }
        } catch {
            if (error as? AccountError) != .cancelled { lastError = error.localizedDescription }
            throw error
        }
    }

    /// Completion handler for `SignInWithAppleButton`.
    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        lastError = nil
        switch result {
        case .success(let authorization):
            guard let credential = AppleCredential(authorization: authorization) else {
                lastError = AccountError.invalidCallback.localizedDescription
                return
            }
            isBusy = true
            defer { isBusy = false }
            do {
                try await completeAppleSignIn(credential)
            } catch {
                lastError = error.localizedDescription
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            lastError = error.localizedDescription
        }
    }

    private func completeAppleSignIn(_ credential: AppleCredential) async throws {
        guard api.isConfigured else { throw AccountError.notConfigured }
        let bundle = try await api.signInWithApple(identityToken: credential.identityToken,
                                                   authorizationCode: credential.authorizationCode,
                                                   fullName: credential.fullName)
        install(bundle)
    }

    // MARK: - Sign out / delete

    func signOut() async {
        lastError = nil
        if let refresh = keychain.read(.refreshToken) {
            try? await api.logout(refreshToken: refresh)
        }
        clearLocalSession()
    }

    /// Deletes the server account and everything synced to it. Local data stays on the phone.
    func deleteAccount() async throws {
        lastError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let token = try await validAccessToken()
            try await api.deleteAccount(accessToken: token)
        } catch AccountError.sessionExpired {
            // Session already gone server-side; treat as deleted locally.
        } catch {
            lastError = error.localizedDescription
            throw error
        }
        clearLocalSession()
    }

    // MARK: - Tokens

    /// Refreshes the access token when it is within five minutes of expiry. Silent on failure
    /// unless the refresh token itself was rejected, in which case the user is signed out.
    func refreshIfNeeded() async {
        guard isSignedIn, api.isConfigured else { return }
        guard let access = keychain.read(.accessToken),
              let expiry = JWTClaims.expiry(of: access),
              expiry.timeIntervalSinceNow > 5 * 60 else {
            _ = try? await refreshSession()
            return
        }
    }

    /// An access token that is good for at least a minute, refreshing when necessary.
    func validAccessToken() async throws -> String {
        guard isSignedIn else { throw AccountError.sessionExpired }
        if let access = keychain.read(.accessToken),
           let expiry = JWTClaims.expiry(of: access),
           expiry.timeIntervalSinceNow > 60 {
            return access
        }
        return try await refreshSession().accessToken
    }

    /// One refresh in flight at a time; concurrent callers share it.
    private func refreshSession() async throws -> SessionBundle {
        if let running = refreshTask { return try await running.value }
        guard let refresh = keychain.read(.refreshToken) else {
            clearLocalSession()
            throw AccountError.sessionExpired
        }
        let task = Task { [api] in try await api.refresh(refreshToken: refresh) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let bundle = try await task.value
            install(bundle, notify: false)
            return bundle
        } catch AccountError.sessionExpired {
            clearLocalSession()
            throw AccountError.sessionExpired
        }
    }

    private func install(_ bundle: SessionBundle, notify: Bool = true) {
        keychain.write(bundle.accessToken, for: .accessToken)
        keychain.write(bundle.refreshToken, for: .refreshToken)
        settings.accountUserData = try? SyncCodec.encoder.encode(bundle.user)
        let switchedUser = user?.id != bundle.user.id
        state = .signedIn(bundle.user)
        if notify || switchedUser { onSessionChanged?() }
    }

    private func clearLocalSession() {
        keychain.delete(.accessToken)
        keychain.delete(.refreshToken)
        settings.accountUserData = nil
        settings.lastSyncedAt = nil
        state = .signedOut
        onSessionChanged?()
    }
}
