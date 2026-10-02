import SwiftUI
import SwiftData

@main
@MainActor
struct MorselApp: App {
    @State private var settings = AppSettings()
    @State private var services: AppServices
    private let container: ModelContainer

    init() {
        if LaunchOptions.isUITesting {
            // Screenshot / UI-test mode: isolated settings, seeded in-memory data, no onboarding unless asked.
            let settings = AppSettings(defaults: LaunchOptions.makeTestDefaults())
            settings.hasCompletedOnboarding = !LaunchOptions.showOnboarding
            settings.calorieGoal = 2200
            settings.proteinGoal = 150
            settings.carbsGoal = 240
            settings.fatGoal = 70
            _settings = State(initialValue: settings)
            _services = State(initialValue: AppServices(settings: settings))
            let testContainer = (try? ModelContainer.morsel(inMemory: true)) ?? ModelContainer.preview
            SampleData.seed(into: testContainer.mainContext)
            container = testContainer
            return
        }
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _services = State(initialValue: AppServices(settings: settings))
        do {
            container = try ModelContainer.morsel()
        } catch {
            // Corrupt store: fall back to in-memory so the app still opens; surfaced in Settings > Diagnostics.
            container = try! ModelContainer.morsel(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(services)
                .tint(Color.mAccent)
                .preferredColorScheme(LaunchOptions.forceDark ? .dark : nil)
        }
        .modelContainer(container)
    }
}
