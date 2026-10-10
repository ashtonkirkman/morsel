import Foundation
import Observation

/// How the app reaches Claude for photo estimates.
enum ClaudeEndpointMode: String, CaseIterable, Identifiable, Codable {
    /// Through the bundled Cloudflare Worker proxy (recommended; the key never leaves the server).
    case proxy
    /// Directly against api.anthropic.com with a key stored in the Keychain (dev / personal use).
    case direct

    var id: String { rawValue }
    var title: String {
        switch self {
        case .proxy: return "Proxy server"
        case .direct: return "Direct (API key on device)"
        }
    }
}

enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// User preferences + goals, backed by UserDefaults. Inject once via `.environment(settings)`.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        calorieGoal = defaults.object(forKey: Keys.calorieGoal) as? Double ?? 2000
        proteinGoal = defaults.object(forKey: Keys.proteinGoal) as? Double ?? 150
        carbsGoal = defaults.object(forKey: Keys.carbsGoal) as? Double ?? 225
        fatGoal = defaults.object(forKey: Keys.fatGoal) as? Double ?? 65
        unitSystem = UnitSystem(rawValue: defaults.string(forKey: Keys.unitSystem) ?? "") ?? .imperial
        claudeEndpointMode = ClaudeEndpointMode(rawValue: defaults.string(forKey: Keys.claudeEndpointMode) ?? "") ?? .proxy
        proxyURLString = defaults.string(forKey: Keys.proxyURL) ?? ""
        hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        autoLogHighConfidence = defaults.object(forKey: Keys.autoLogHighConfidence) as? Bool ?? false
        useSAM2Segmentation = defaults.object(forKey: Keys.useSAM2Segmentation) as? Bool ?? false
        profileData = defaults.data(forKey: Keys.profile)
        accountAPIURLString = defaults.string(forKey: Keys.accountAPIURL) ?? ""
        accountUserData = defaults.data(forKey: Keys.accountUser)
        lastSyncedAt = (defaults.object(forKey: Keys.lastSyncedAt) as? Double).map { Date(timeIntervalSince1970: $0) }
        settingsUpdatedAt = (defaults.object(forKey: Keys.settingsUpdatedAt) as? Double).map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        syncCursors = defaults.dictionary(forKey: Keys.syncCursors) as? [String: Double] ?? [:]
        syncLastPushes = defaults.dictionary(forKey: Keys.syncLastPushes) as? [String: Double] ?? [:]
    }

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) } }
    var calorieGoal: Double { didSet { defaults.set(calorieGoal, forKey: Keys.calorieGoal); touchSettings() } }
    var proteinGoal: Double { didSet { defaults.set(proteinGoal, forKey: Keys.proteinGoal); touchSettings() } }
    var carbsGoal: Double { didSet { defaults.set(carbsGoal, forKey: Keys.carbsGoal); touchSettings() } }
    var fatGoal: Double { didSet { defaults.set(fatGoal, forKey: Keys.fatGoal); touchSettings() } }
    var unitSystem: UnitSystem { didSet { defaults.set(unitSystem.rawValue, forKey: Keys.unitSystem); touchSettings() } }
    var claudeEndpointMode: ClaudeEndpointMode { didSet { defaults.set(claudeEndpointMode.rawValue, forKey: Keys.claudeEndpointMode) } }
    var proxyURLString: String { didSet { defaults.set(proxyURLString, forKey: Keys.proxyURL) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) } }
    /// When true, photo estimates with confidence ≥ 0.85 are logged without the review sheet.
    var autoLogHighConfidence: Bool { didSet { defaults.set(autoLogHighConfidence, forKey: Keys.autoLogHighConfidence) } }
    /// Body scans segment with Segment Anything 2.1 (downloaded on demand) instead of Apple Vision. Falls back when not installed.
    var useSAM2Segmentation: Bool { didSet { defaults.set(useSAM2Segmentation, forKey: Keys.useSAM2Segmentation) } }

    private var profileData: Data? { didSet { defaults.set(profileData, forKey: Keys.profile); touchSettings() } }

    // MARK: Account + sync

    /// Account API base URL override (Settings > Account > Server URL). Empty = use `AccountConfig.defaultBaseURL`.
    var accountAPIURLString: String { didSet { defaults.set(accountAPIURLString, forKey: Keys.accountAPIURL) } }
    /// Cached `AccountUser` JSON so the UI knows who is signed in before any network call.
    var accountUserData: Data? { didSet { defaults.set(accountUserData, forKey: Keys.accountUser) } }
    /// When the last full sync finished (all collections). Shown in Settings.
    var lastSyncedAt: Date? { didSet { defaults.set(lastSyncedAt?.timeIntervalSince1970, forKey: Keys.lastSyncedAt) } }
    /// Last change to goals / units / profile; the `updatedAt` of the synced "settings/profile" document.
    var settingsUpdatedAt: Date { didSet { defaults.set(settingsUpdatedAt.timeIntervalSince1970, forKey: Keys.settingsUpdatedAt) } }
    /// Per-collection server cursors (`serverTime` from the last pull, Unix ms).
    private var syncCursors: [String: Double] { didSet { defaults.set(syncCursors, forKey: Keys.syncCursors) } }
    /// Per-collection time of the last push, so only newer local changes are sent.
    private var syncLastPushes: [String: Double] { didSet { defaults.set(syncLastPushes, forKey: Keys.syncLastPushes) } }

    private func touchSettings() {
        settingsUpdatedAt = .now
    }

    var accountAPIURL: URL? {
        let trimmed = accountAPIURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
        return url
    }

    func syncCursor(for collection: String) -> Double { syncCursors[collection] ?? 0 }
    func setSyncCursor(_ value: Double, for collection: String) { syncCursors[collection] = value }
    func syncLastPush(for collection: String) -> Date? {
        syncLastPushes[collection].map { Date(timeIntervalSince1970: $0) }
    }
    func setSyncLastPush(_ date: Date, for collection: String) { syncLastPushes[collection] = date.timeIntervalSince1970 }
    func clearSyncCursors() {
        syncCursors = [:]
        syncLastPushes = [:]
    }

    /// Body stats used by `GoalCalculator`; nil until onboarding stores one.
    var profile: UserProfile? {
        get { profileData.flatMap { try? JSONDecoder().decode(UserProfile.self, from: $0) } }
        set { profileData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var proxyURL: URL? {
        let trimmed = proxyURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    var macroGoals: NutritionFacts {
        NutritionFacts(calories: calorieGoal, protein: proteinGoal, carbs: carbsGoal, fat: fatGoal)
    }

    /// True when photo logging can actually reach Claude with the current configuration.
    var isVisionConfigured: Bool {
        switch claudeEndpointMode {
        case .proxy: return proxyURL != nil
        case .direct: return !(KeychainStore.shared.read(.claudeAPIKey) ?? "").isEmpty
        }
    }

    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let calorieGoal = "calorieGoal"
        static let proteinGoal = "proteinGoal"
        static let carbsGoal = "carbsGoal"
        static let fatGoal = "fatGoal"
        static let unitSystem = "unitSystem"
        static let claudeEndpointMode = "claudeEndpointMode"
        static let proxyURL = "proxyURL"
        static let hapticsEnabled = "hapticsEnabled"
        static let autoLogHighConfidence = "autoLogHighConfidence"
        static let useSAM2Segmentation = "useSAM2Segmentation"
        static let profile = "userProfile"
        static let accountAPIURL = "accountAPIURL"
        static let accountUser = "accountUser"
        static let lastSyncedAt = "lastSyncedAt"
        static let settingsUpdatedAt = "settingsUpdatedAt"
        static let syncCursors = "syncCursors"
        static let syncLastPushes = "syncLastPushes"
    }
}
