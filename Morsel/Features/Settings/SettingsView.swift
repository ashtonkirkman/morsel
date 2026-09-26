import SwiftUI
import SwiftData

/// Settings tab: goals, profile, photo logging, preferences, data, about. `ScrollView` + `Card`s to match the app.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    // Profile
    @State private var profileDraft: UserProfile = .placeholder
    @State private var showProfileSheet = false
    @State private var goalsUpdatedFlash = false

    // Photo logging
    @State private var apiKeyDraft = ""
    @State private var keyStored = false
    @State private var visionConfigured = false

    // Data
    @State private var exportURL: URL?
    @State private var exportCount = 0
    @State private var exportError: String?
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    goalsSection
                    profileSection
                    photoSection
                    preferencesSection
                    dataSection
                    aboutSection
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .keyboardDoneToolbar()
        }
        .onAppear(perform: refresh)
        .onChange(of: profileDraft) { _, newValue in settings.profile = newValue }
        .onChange(of: settings.claudeEndpointMode) { _, _ in refreshVisionStatus() }
        .onChange(of: settings.proxyURLString) { _, _ in refreshVisionStatus() }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSetupSheet(profile: $profileDraft) { applyGoals(from: profileDraft) }
        }
        .confirmationDialog("Delete all data?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive, action: deleteAllData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every logged meal, favorite and photo from this device. Your goals and profile stay.")
        }
    }

    // MARK: - Goals

    private var goalsSection: some View {
        @Bindable var settings = settings
        return SettingsSection(title: "Goals", footer: "Daily targets. Macros are grams.") {
            SettingsNumberField(title: "Calories", unit: "kcal", value: $settings.calorieGoal)
            SettingsSeparator()
            SettingsNumberField(title: "Protein", unit: "g", value: $settings.proteinGoal)
            SettingsSeparator()
            SettingsNumberField(title: "Carbs", unit: "g", value: $settings.carbsGoal)
            SettingsSeparator()
            SettingsNumberField(title: "Fat", unit: "g", value: $settings.fatGoal)
            Button {
                if let profile = settings.profile {
                    applyGoals(from: profile)
                } else {
                    showProfileSheet = true
                }
            } label: {
                Label(goalsUpdatedFlash ? "Updated" : "Recalculate from my profile",
                      systemImage: goalsUpdatedFlash ? "checkmark" : "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.morselSecondary)
            .padding(.top, Spacing.s)
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        @Bindable var settings = settings
        return SettingsSection(title: "Profile", footer: "Only used to compute your goals. Stays on this device.") {
            ProfileFieldsView(profile: $profileDraft, unitSystem: $settings.unitSystem, showsUnitToggle: false)
            SettingsSeparator()
            HStack {
                Text("Activity").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                Picker("Activity", selection: $profileDraft.activity) {
                    ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.vertical, 2)
            SettingsSeparator()
            HStack {
                Text("Goal").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                Picker("Goal", selection: $profileDraft.goal) {
                    ForEach(WeightGoal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Photo logging

    private var photoSection: some View {
        @Bindable var settings = settings
        return SettingsSection(
            title: "Photo logging",
            footer: "Auto-log skips the review sheet when Claude is at least 85% confident. You can always undo from the toast."
        ) {
            HStack {
                Text("Connect via").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                Picker("Connect via", selection: $settings.claudeEndpointMode) {
                    ForEach(ClaudeEndpointMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.vertical, 2)
            SettingsSeparator()
            switch settings.claudeEndpointMode {
            case .proxy:
                TextField("https://your-proxy.workers.dev", text: $settings.proxyURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(MorselFont.body)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Proxy URL")
            case .direct:
                apiKeyRow
            }
            SettingsSeparator()
            Toggle(isOn: $settings.autoLogHighConfidence) {
                Text("Auto-log confident estimates").font(MorselFont.body).foregroundStyle(Color.mText)
            }
            .tint(Color.mAccent)
            .padding(.vertical, 4)
            SettingsSeparator()
            HStack(spacing: Spacing.s) {
                Image(systemName: visionConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(visionConfigured ? Color.mAccent : Color.mWarning)
                Text(visionConfigured ? "Configured" : "Not configured")
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var apiKeyRow: some View {
        HStack(spacing: Spacing.s) {
            SecureField(keyStored ? "Key saved · enter to replace" : "sk-ant-…", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(MorselFont.body)
                .onSubmit(saveAPIKey)
                .accessibilityLabel("Claude API key")
            if !apiKeyDraft.isEmpty {
                Button("Save", action: saveAPIKey)
                    .font(MorselFont.callout.weight(.semibold))
                    .foregroundStyle(Color.mAccent)
            } else if keyStored {
                Button("Remove", role: .destructive, action: removeAPIKey)
                    .font(MorselFont.callout.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        @Bindable var settings = settings
        return SettingsSection(title: "Preferences") {
            HStack {
                Text("Units").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                Picker("Units", selection: $settings.unitSystem) {
                    ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
            .padding(.vertical, 4)
            SettingsSeparator()
            Toggle(isOn: $settings.hapticsEnabled) {
                Text("Haptics").font(MorselFont.body).foregroundStyle(Color.mText)
            }
            .tint(Color.mAccent)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        SettingsSection(title: "Data") {
            if let exportURL {
                ShareLink(item: exportURL) {
                    row(symbol: "square.and.arrow.up",
                        title: exportCount == 1 ? "Share CSV · 1 entry" : "Share CSV · \(exportCount) entries",
                        tint: .mAccent)
                }
            } else {
                Button(action: prepareExport) {
                    row(symbol: "doc.text", title: "Export CSV", tint: .mText)
                }
                .buttonStyle(.plain)
            }
            if let exportError {
                Text(exportError).font(MorselFont.caption).foregroundStyle(Color.mDanger)
            }
            SettingsSeparator()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                row(symbol: "trash", title: "Delete all data", tint: .mDanger)
            }
            .buttonStyle(.plain)
            if let deleteError {
                Text(deleteError).font(MorselFont.caption).foregroundStyle(Color.mDanger)
            }
        }
    }

    private func row(symbol: String, title: String, tint: Color) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 22)
            Text(title).font(MorselFont.body).foregroundStyle(tint)
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            HStack {
                Text("Version").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                Text(versionString).font(MorselFont.callout.monospacedDigit()).foregroundStyle(Color.mTextSecondary)
            }
            .padding(.vertical, 6)
            SettingsSeparator()
            HStack {
                Text("Food data").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                if let url = URL(string: "https://world.openfoodfacts.org") {
                    Link("Open Food Facts (ODbL)", destination: url)
                        .font(MorselFont.callout)
                        .foregroundStyle(Color.mAccent)
                } else {
                    Text("Open Food Facts (ODbL)").font(MorselFont.callout).foregroundStyle(Color.mTextSecondary)
                }
            }
            .padding(.vertical, 6)
            SettingsSeparator()
            HStack {
                Text("Photo estimates").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                Text("Estimates by Claude").font(MorselFont.callout).foregroundStyle(Color.mTextSecondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    private func refresh() {
        if let stored = settings.profile { profileDraft = stored }
        keyStored = !(KeychainStore.shared.read(.claudeAPIKey) ?? "").isEmpty
        exportURL = nil
        refreshVisionStatus()
    }

    private func refreshVisionStatus() {
        visionConfigured = settings.isVisionConfigured
    }

    private func applyGoals(from profile: UserProfile) {
        let targets = GoalCalculator.targets(for: profile)
        settings.profile = profile
        settings.calorieGoal = targets.calories
        settings.proteinGoal = targets.protein
        settings.carbsGoal = targets.carbs
        settings.fatGoal = targets.fat
        if settings.hapticsEnabled { Haptics.success() }
        goalsUpdatedFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            goalsUpdatedFlash = false
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainStore.shared.write(trimmed, for: .claudeAPIKey) {
            apiKeyDraft = ""
            keyStored = true
            if settings.hapticsEnabled { Haptics.success() }
        }
        refreshVisionStatus()
    }

    private func removeAPIKey() {
        KeychainStore.shared.delete(.claudeAPIKey)
        apiKeyDraft = ""
        keyStored = false
        refreshVisionStatus()
    }

    private func prepareExport() {
        do {
            let entries = try context.fetch(FetchDescriptor<LogEntry>())
            let csv = CSVExporter.csv(from: entries)
            exportURL = try CSVExporter.writeTemporaryFile(csv)
            exportCount = entries.count
            exportError = nil
        } catch {
            exportError = "Couldn't build the export. \(error.localizedDescription)"
        }
    }

    private func deleteAllData() {
        do {
            let entries = try context.fetch(FetchDescriptor<LogEntry>())
            for entry in entries { PhotoStore.shared.delete(entry.photoFilename) }
            try context.delete(model: LogEntry.self)
            try context.delete(model: FavoriteFood.self)
            try context.save()
            exportURL = nil
            deleteError = nil
            if settings.hapticsEnabled { Haptics.warning() }
        } catch {
            deleteError = "Couldn't delete everything. \(error.localizedDescription)"
        }
    }
}

// MARK: - Building blocks

/// Caption title, one `Card` of rows, optional footer.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title.uppercased())
                .font(MorselFont.caption.weight(.medium))
                .foregroundStyle(Color.mTextSecondary)
                .padding(.horizontal, Spacing.xs)
            Card {
                VStack(spacing: 0) { content() }
            }
            if let footer {
                Text(footer)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }
}

struct SettingsSeparator: View {
    var body: some View { Divider().overlay(Color.mSeparator) }
}

/// Presented when the user asks to recalculate goals but has no profile yet.
struct ProfileSetupSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Binding var profile: UserProfile
    let onSave: () -> Void

    var body: some View {
        @Bindable var settings = settings
        return NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    Card {
                        ProfileFieldsView(profile: $profile, unitSystem: $settings.unitSystem)
                    }
                    Card {
                        VStack(spacing: Spacing.s) {
                            Picker("Activity", selection: $profile.activity) {
                                ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            SettingsSeparator()
                            Picker("Goal", selection: $profile.goal) {
                                ForEach(WeightGoal.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Button("Save & recalculate") {
                        onSave()
                        dismiss()
                    }
                    .buttonStyle(.morselPrimary)
                }
                .padding(Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .keyboardDoneToolbar()
        }
    }
}
