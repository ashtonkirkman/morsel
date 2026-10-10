import Foundation

/// Compile-time account/sync configuration. The server URL can be overridden at runtime in
/// Settings > Account > Server URL (`AppSettings.accountAPIURLString`).
enum AccountConfig {
    /// TODO: replace with the URL `npx wrangler deploy` prints for `server/account-api`
    /// (e.g. "https://freetrack-account-api.ashton.workers.dev"). While it still contains the
    /// `<your-subdomain>` placeholder the app treats accounts as "not configured".
    static let defaultBaseURL = "https://freetrack-account-api.<your-subdomain>.workers.dev"

    /// Custom URL scheme registered in project.yml (`CFBundleURLTypes`); the Worker redirects
    /// Google/Facebook sign-ins back to `freetrack://auth/callback`.
    static let urlScheme = "freetrack"

    /// Audience the Worker expects in Apple identity tokens. Must match PRODUCT_BUNDLE_IDENTIFIER.
    static let bundleID = "com.ashtonkirkman.morsel"

    /// Effective base URL: the Settings override when valid, else the compiled-in default when
    /// it has been filled in, else nil ("not configured").
    static func baseURL(settings: AppSettings) -> URL? {
        if let override = settings.accountAPIURL { return override }
        guard !defaultBaseURL.contains("<"), let url = URL(string: defaultBaseURL),
              url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
}
