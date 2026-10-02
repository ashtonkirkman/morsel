import Foundation

/// Launch arguments used by the UI-test / screenshot run on CI. Inert in normal launches.
///
///   --ui-testing          in-memory store seeded with sample data, onboarding skipped, fresh settings
///   --show-onboarding     start on the onboarding flow instead of the main shell
///   --dark                force dark appearance
///   --open <route>        open an add flow immediately: menu | snap | scan | search | quickAdd
enum LaunchOptions {
    static let arguments = ProcessInfo.processInfo.arguments

    static var isUITesting: Bool { arguments.contains("--ui-testing") }
    static var showOnboarding: Bool { arguments.contains("--show-onboarding") }
    static var forceDark: Bool { arguments.contains("--dark") }

    static var initialRoute: AddRoute? {
        guard let index = arguments.firstIndex(of: "--open"), arguments.indices.contains(index + 1) else { return nil }
        return AddRoute(rawValue: arguments[index + 1])
    }

    /// Isolated defaults so a test launch never touches real preferences.
    static func makeTestDefaults() -> UserDefaults {
        let suite = "com.ashtonkirkman.morsel.ui-testing"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
