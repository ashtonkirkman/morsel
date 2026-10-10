import SwiftUI

/// Body-scan preferences: segmentation model (Apple Vision vs. Segment Anything 2.1) and the self-timer.
/// Presented as a sheet from the Body tab so `SettingsView` stays untouched.
@MainActor
struct BodyScanSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    private var store: SAM2ModelStore { SAM2ModelStore.shared }
    @AppStorage("bodyScanCountdownSeconds") private var countdownSeconds = 3

    var body: some View {
        @Bindable var settings = settings
        return NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    SettingsSection(title: "Segmentation",
                                    footer: "Apple Vision runs on every iPhone with no download. Segment Anything 2.1 (Meta, converted by Apple) traces the body outline more precisely, which tightens waist, arm and thigh estimates. If it is not installed or fails, Apple Vision is used automatically.") {
                        Toggle(isOn: $settings.useSAM2Segmentation) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use Segment Anything").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                                Text("Higher accuracy, ~\(sizeMB) MB download").font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                            }
                        }
                        .tint(Color.mAccent)
                        .padding(.vertical, 4)
                        .onChange(of: settings.useSAM2Segmentation) { _, on in
                            if on, !store.isInstalled { store.install() }
                        }
                        SettingsSeparator()
                        modelStatus
                    }
                    SettingsSection(title: "Camera", footer: "Time between tapping the shutter and the photo, so you can get into position.") {
                        Picker("Self-timer", selection: $countdownSeconds) {
                            Text("3 s").tag(3)
                            Text("5 s").tag(5)
                            Text("10 s").tag(10)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)
                    }
                    SettingsSection(title: "Privacy", footer: "Body-scan photos are analysed and stored only on this phone. They are never uploaded, and never synced to an account. Only the measurements are.") {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "lock.shield").foregroundStyle(Color.mAccent)
                            Text("On-device only").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("Body scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var sizeMB: Int { Int((Double(store.variant.approximateBytes) / 1_000_000).rounded()) }

    @ViewBuilder
    private var modelStatus: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            switch store.state {
            case .idle:
                statusRow(symbol: "arrow.down.circle", color: .mTextSecondary, text: "Not installed")
                Button("Download model (\(sizeMB) MB)") { store.install() }
                    .buttonStyle(.freeTrackSecondary)
            case .downloading(let fraction, let bytes):
                statusRow(symbol: "arrow.down.circle", color: .mAccent, text: "Downloading… \(Int(Double(bytes) / 1_000_000)) MB")
                ProgressView(value: fraction).tint(Color.mAccent)
                Button("Cancel") { store.cancelInstall() }
                    .buttonStyle(.freeTrackSecondary)
            case .compiling(let name):
                statusRow(symbol: "gearshape.2", color: .mAccent, text: "Preparing \(name)…")
                ProgressView().tint(Color.mAccent)
            case .installed:
                statusRow(symbol: "checkmark.circle.fill", color: .mAccent, text: "Installed · SAM 2.1 \(store.variant.rawValue)")
                Button("Remove model") { store.remove() }
                    .buttonStyle(.freeTrackSecondary)
            case .failed(let message):
                statusRow(symbol: "exclamationmark.circle", color: .mWarning, text: message)
                Button("Try again") { store.install() }
                    .buttonStyle(.freeTrackSecondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func statusRow(symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
            Spacer()
        }
    }
}
