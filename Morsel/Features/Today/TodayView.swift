import SwiftUI
import SwiftData

/// Home tab: the hero ring, macros and today's meals. Chevrons browse previous days.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Calendar.current.startOfDay(for: .now)
    @State private var day = Calendar.current.startOfDay(for: .now)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    dayHeader
                    DayLogView(day: day, showsHero: true)
                        .id(day)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, 120)
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { rollOverIfNeeded() }
        }
    }

    // MARK: - Header

    private var dayHeader: some View {
        HStack(alignment: .center) {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
            Spacer()
            HStack(spacing: Spacing.xs) {
                chevron(symbol: "chevron.left", label: "Previous day", enabled: true) { shift(by: -1) }
                chevron(symbol: "chevron.right", label: "Next day", enabled: day < today) { shift(by: 1) }
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func chevron(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? Color.mText : Color.mTextTertiary)
                .frame(width: 34, height: 34)
                .background(Color.mSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - Helpers

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }

    private func shift(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        guard next <= today else { return }
        Haptics.tap()
        withAnimation(.easeInOut(duration: 0.2)) { day = next }
    }

    /// Keeps the view on "today" across midnight when the user was already looking at today.
    private func rollOverIfNeeded() {
        let newToday = Calendar.current.startOfDay(for: .now)
        guard newToday != today else { return }
        let wasViewingToday = day == today
        today = newToday
        if wasViewingToday { day = newToday }
    }
}
