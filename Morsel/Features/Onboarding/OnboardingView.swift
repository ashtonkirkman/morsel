import SwiftUI

/// First-launch flow: welcome → profile → activity & goal → plan. Four pages, lots of whitespace.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings

    @State private var page = 0
    @State private var profile: UserProfile = .placeholder
    @State private var planCalories: Double = 0

    private static let pageCount = 4

    var body: some View {
        @Bindable var settings = settings
        return VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage(onStart: { go(to: 1) }, onSkip: finishWithDefaults)
                    .tag(0)
                ProfilePage(profile: $profile, unitSystem: $settings.unitSystem)
                    .tag(1)
                ActivityPage(profile: $profile)
                    .tag(2)
                PlanPage(profile: profile, calories: $planCalories)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: page)

            if page > 0 {
                footer
            }
        }
        .background(Color.mBackground.ignoresSafeArea())
        .onChange(of: page) { _, newPage in
            if newPage == 3 { planCalories = GoalCalculator.targetCalories(for: profile) }
        }
        .keyboardDoneToolbar()
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.m) {
            PageDots(count: Self.pageCount, current: page)
            HStack(spacing: Spacing.m) {
                Button("Back") { go(to: page - 1) }
                    .buttonStyle(.morselSecondary)
                    .frame(maxWidth: 120)
                Button(page == Self.pageCount - 1 ? "Start" : "Next") {
                    if page == Self.pageCount - 1 { finish() } else { go(to: page + 1) }
                }
                .buttonStyle(.morselPrimary)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.l)
        .padding(.top, Spacing.s)
    }

    // MARK: - Navigation / completion

    private func go(to target: Int) {
        guard (0..<Self.pageCount).contains(target) else { return }
        Haptics.tap()
        withAnimation { page = target }
    }

    private func finish() {
        let plan = PlanBuilder.plan(for: profile, calories: planCalories)
        settings.profile = profile
        settings.calorieGoal = plan.calories
        settings.proteinGoal = plan.protein
        settings.carbsGoal = plan.carbs
        settings.fatGoal = plan.fat
        if settings.hapticsEnabled { Haptics.success() }
        settings.hasCompletedOnboarding = true
    }

    /// Keeps the 2000-kcal defaults from `AppSettings`; no profile stored.
    private func finishWithDefaults() {
        settings.hasCompletedOnboarding = true
    }
}

// MARK: - Page dots

struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.mAccent : Color.mSeparator)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: - Page 1: Welcome

struct WelcomePage: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            HStack(spacing: Spacing.l) {
                icon("camera.fill")
                icon("barcode.viewfinder")
                icon("magnifyingglass")
            }
            VStack(spacing: Spacing.s) {
                Text("Morsel")
                    .font(MorselFont.display)
                    .foregroundStyle(Color.mText)
                Text("Log meals in seconds")
                    .font(MorselFont.title)
                    .foregroundStyle(Color.mTextSecondary)
            }
            Spacer()
            Spacer()
            VStack(spacing: Spacing.m) {
                Button("Get started", action: onStart)
                    .buttonStyle(.morselPrimary)
                Button("Skip, use defaults", action: onSkip)
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
            }
            .padding(.bottom, Spacing.xl)
        }
        .padding(.horizontal, Spacing.l)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(Color.mAccent)
            .frame(width: 64, height: 64)
            .background(Color.mAccentSoft, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Page 2: Profile

struct ProfilePage: View {
    @Binding var profile: UserProfile
    @Binding var unitSystem: UnitSystem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                OnboardingHeading(title: "About you", subtitle: "Used once to estimate how much you burn each day.")
                Card {
                    ProfileFieldsView(profile: $profile, unitSystem: $unitSystem)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Page 3: Activity + goal

struct ActivityPage: View {
    @Binding var profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                OnboardingHeading(title: "Your week", subtitle: "How active are you, and what are you after?")
                VStack(spacing: Spacing.s) {
                    ForEach(ActivityLevel.allCases) { level in
                        activityRow(level)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Goal")
                        .font(MorselFont.headline)
                        .foregroundStyle(Color.mText)
                    HStack(spacing: Spacing.s) {
                        ForEach(WeightGoal.allCases) { goal in
                            Chip(title: goal.title, isSelected: profile.goal == goal) {
                                Haptics.tap()
                                profile.goal = goal
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.l)
        }
    }

    private func activityRow(_ level: ActivityLevel) -> some View {
        let selected = profile.activity == level
        return Button {
            Haptics.tap()
            profile.activity = level
        } label: {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title).font(MorselFont.headline).foregroundStyle(Color.mText)
                    Text(level.detail).font(MorselFont.caption).foregroundStyle(Color.mTextSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.mAccent : Color.mTextTertiary)
            }
            .padding(Spacing.m)
            .background(selected ? Color.mAccentSoft : Color.mSurface,
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Page 4: Plan

struct PlanPage: View {
    let profile: UserProfile
    @Binding var calories: Double

    @State private var text = ""
    @FocusState private var focused: Bool

    private var plan: NutritionFacts { PlanBuilder.plan(for: profile, calories: calories) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                OnboardingHeading(title: "Your plan", subtitle: "A daily target you can tweak any time in Settings.")
                VStack(spacing: Spacing.xs) {
                    HStack(spacing: Spacing.m) {
                        adjust(symbol: "minus", label: "Lower by 50", delta: -50)
                        TextField("", text: $text)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(MorselFont.display)
                            .foregroundStyle(Color.mText)
                            .frame(minWidth: 150, maxWidth: 190)
                            .focused($focused)
                            .accessibilityLabel("Daily calorie target")
                        adjust(symbol: "plus", label: "Raise by 50", delta: 50)
                    }
                    Text("kcal per day")
                        .font(MorselFont.callout)
                        .foregroundStyle(Color.mTextSecondary)
                }
                .frame(maxWidth: .infinity)
                Card {
                    HStack(spacing: Spacing.s) {
                        macro("Protein", grams: plan.protein, color: .mProtein)
                        macro("Carbs", grams: plan.carbs, color: .mCarbs)
                        macro("Fat", grams: plan.fat, color: .mFat)
                    }
                }
                Text("Based on your stats: about \(Format.kcal(GoalCalculator.maintenanceCalories(for: profile))) kcal to maintain.")
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { text = Format.kcal(calories) }
        .onChange(of: calories) { _, newValue in
            if !focused { text = Format.kcal(newValue) }
        }
        .onChange(of: text) { _, newText in
            if let parsed = Double(newText), parsed > 0, parsed != calories { calories = parsed }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                calories = max(PlanBuilder.minimumCalories, calories)
                text = Format.kcal(calories)
            }
        }
    }

    private func adjust(symbol: String, label: String, delta: Double) -> some View {
        Button {
            Haptics.tap()
            focused = false
            calories = max(PlanBuilder.minimumCalories, calories + delta)
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.mText)
                .frame(width: 44, height: 44)
                .background(Color.mSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func macro(_ title: String, grams: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(Format.grams(grams))
                .font(MorselFont.numeral)
                .foregroundStyle(Color.mText)
            MacroDot(color: color, text: title)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Heading

struct OnboardingHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(MorselFont.title)
                .foregroundStyle(Color.mText)
            Text(subtitle)
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
