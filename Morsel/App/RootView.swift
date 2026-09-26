import SwiftUI
import SwiftData

/// Tab shell + floating add button + "Logged" toast. Shows onboarding on first launch.
@MainActor
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var tab: Tab = .today
    @State private var addRoute: AddRoute?
    @State private var toast: LoggedToast?

    enum Tab: Hashable { case today, history, settings }

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                mainShell
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: settings.hasCompletedOnboarding)
    }

    private var mainShell: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                TodayView()
                    .tabItem { Label("Today", systemImage: "circle.circle") }
                    .tag(Tab.today)
                HistoryView()
                    .tabItem { Label("History", systemImage: "chart.bar") }
                    .tag(Tab.history)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                    .tag(Tab.settings)
            }

            if tab != .settings {
                FloatingAddButton { addRoute = .menu }
                    .padding(.bottom, 62)
                    .transition(.scale.combined(with: .opacity))
            }

            if let toast {
                LoggedToastView(toast: toast) { self.toast = nil }
                    .padding(.bottom, 140)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: tab)
        .animation(.spring(duration: 0.35), value: toast)
        .sheet(item: $addRoute) { route in
            AddFlowHost(route: route) { entries in
                addRoute = nil
                guard !entries.isEmpty else { return }
                let kcal = entries.map(\.total.calories).reduce(0, +)
                toast = LoggedToast(entryIDs: entries.map(\.id), count: entries.count, calories: kcal)
                if settings.hapticsEnabled { Haptics.success() }
                Task { try? await Task.sleep(for: .seconds(4)); if toast?.entryIDs == entries.map(\.id) { toast = nil } }
            }
        }
        .background(Color.mBackground.ignoresSafeArea())
    }
}

/// Entry points into a logging flow. `.menu` shows the picker first.
enum AddRoute: String, Identifiable {
    case menu, snap, scan, search, quickAdd
    var id: String { rawValue }
}

/// Hosts the add menu and each logging flow inside one sheet. Every flow calls `onLogged`
/// with the entries it inserted (empty array = cancelled).
@MainActor
struct AddFlowHost: View {
    let route: AddRoute
    let onLogged: ([LogEntry]) -> Void
    @State private var current: AddRoute

    init(route: AddRoute, onLogged: @escaping ([LogEntry]) -> Void) {
        self.route = route
        self.onLogged = onLogged
        _current = State(initialValue: route)
    }

    var body: some View {
        switch current {
        case .menu:
            AddMenuView { choice in current = choice } onCancel: { onLogged([]) }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        case .snap:
            SnapMealFlowView(onLogged: onLogged)
        case .scan:
            BarcodeScanFlowView(onLogged: onLogged)
        case .search:
            FoodSearchFlowView(onLogged: onLogged)
        case .quickAdd:
            QuickAddFlowView(onLogged: onLogged)
                .presentationDetents([.medium, .large])
        }
    }
}

struct LoggedToast: Equatable {
    var entryIDs: [UUID]
    var count: Int
    var calories: Double
}

@MainActor
struct LoggedToastView: View {
    @Environment(\.modelContext) private var context
    let toast: LoggedToast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mAccent)
            Text(toast.count == 1 ? "Logged · \(Format.kcalWithUnit(toast.calories))"
                                  : "Logged \(toast.count) items · \(Format.kcalWithUnit(toast.calories))")
                .font(MorselFont.callout.weight(.medium))
                .foregroundStyle(Color.mText)
            Spacer()
            Button("Undo") {
                let ids = toast.entryIDs
                let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate { ids.contains($0.id) })
                if let entries = try? context.fetch(descriptor) {
                    for e in entries { PhotoStore.shared.delete(e.photoFilename); context.delete(e) }
                    try? context.save()
                }
                dismiss()
            }
            .font(MorselFont.callout.weight(.semibold))
            .foregroundStyle(Color.mAccent)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 12)
        .background(Color.mSurface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, Spacing.m)
        .onTapGesture(perform: dismiss)
    }
}
