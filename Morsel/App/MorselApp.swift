import SwiftUI
import SwiftData

@main
struct MorselApp: App {
    @State private var settings = AppSettings()
    @State private var services: AppServices
    private let container: ModelContainer

    init() {
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
        }
        .modelContainer(container)
    }
}
