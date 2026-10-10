import SwiftUI
import SwiftData

@main
@MainActor
struct FreeTrackApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = AppSettings()
    @State private var services: AppServices
    private let container: ModelContainer

    init() {
        if LaunchOptions.isUITesting {
            // Screenshot / UI-test mode: isolated settings, seeded in-memory data, no onboarding unless asked,
            // and a stub account API so nothing ever hits the network.
            let settings = AppSettings(defaults: LaunchOptions.makeTestDefaults())
            settings.hasCompletedOnboarding = !LaunchOptions.showOnboarding
            settings.calorieGoal = 2200
            settings.proteinGoal = 150
            settings.carbsGoal = 240
            settings.fatGoal = 70
            _settings = State(initialValue: settings)
            let testContainer = (try? ModelContainer.freeTrack(inMemory: true)) ?? ModelContainer.preview
            SampleData.seed(into: testContainer.mainContext)
            container = testContainer
            _services = State(initialValue: AppServices(settings: settings, container: testContainer, accountAPI: StubAccountAPI()))
            return
        }
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let container: ModelContainer
        do {
            container = try ModelContainer.freeTrack()
        } catch {
            // Corrupt store: fall back to in-memory so the app still opens; surfaced in Settings > Diagnostics.
            container = try! ModelContainer.freeTrack(inMemory: true)
        }
        self.container = container
        _services = State(initialValue: AppServices(settings: settings, container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(services)
                .tint(Color.mAccent)
                .preferredColorScheme(LaunchOptions.forceDark ? .dark : nil)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active, !LaunchOptions.isUITesting else { return }
                    let services = services
                    Task {
                        await services.account.refreshIfNeeded()
                        services.sync.scheduleSync(after: 0.5)
                    }
                }
        }
        .modelContainer(container)
    }
}
