import SwiftData
import SwiftUI

/// Photo → Claude estimate → review → log. Presented in a sheet by `RootView`; owns its `NavigationStack`.
@MainActor
struct SnapMealFlowView: View {
    let onLogged: ([LogEntry]) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @State private var model = SnapMealViewModel()

    init(onLogged: @escaping ([LogEntry]) -> Void) {
        self.onLogged = onLogged
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color.mBackground.ignoresSafeArea())
        }
        .onChange(of: model.pendingAutoLog) { _, pending in
            if pending { commitLog() }
        }
        .onDisappear { model.cancel() }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .capture:
            CaptureView(hint: $model.hint,
                        isConfigured: settings.isVisionConfigured,
                        onCapture: begin,
                        onCancel: cancel)
        case .analyzing:
            AnalyzingView(image: model.image, onCancel: cancel)
        case .review:
            EstimateReviewView(model: model, onLog: commitLog, onCancel: cancel)
        case .failed(let message):
            SnapErrorView(message: message, onRetry: retry, onCancel: cancel)
        }
    }

    // MARK: - Actions

    private func begin(_ image: UIImage) {
        model.begin(with: image,
                    vision: services.vision,
                    isConfigured: settings.isVisionConfigured,
                    autoLog: settings.autoLogHighConfidence)
    }

    private func retry() {
        model.retry(vision: services.vision,
                    isConfigured: settings.isVisionConfigured,
                    autoLog: settings.autoLogHighConfidence)
    }

    private func commitLog() {
        do {
            let entries = try model.log(into: context)
            onLogged(entries)
        } catch {
            model.pendingAutoLog = false
            model.logErrorMessage = "Couldn't save this meal. \(error.localizedDescription)"
            model.phase = .review
        }
    }

    private func cancel() {
        model.cancel()
        onLogged([])
    }
}

// MARK: - Analyzing

/// Captured photo, softly blurred, under the loading overlay.
struct AnalyzingView: View {
    let image: UIImage?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 8)
                    .ignoresSafeArea()
            } else {
                Color.mBackground.ignoresSafeArea()
            }
            LoadingOverlay(message: "Reading your plate…")
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Error

/// Plain-English failure with retry, per the design rules.
struct SnapErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Spacing.m) {
            Spacer()
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label("Couldn't estimate this meal", systemImage: "exclamationmark.triangle")
                        .font(MorselFont.headline)
                        .foregroundStyle(Color.mText)
                    Text(message)
                        .font(MorselFont.body)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
            Button("Try again", action: onRetry)
                .buttonStyle(.morselPrimary)
            Button("Cancel", action: onCancel)
                .buttonStyle(.morselSecondary)
            Spacer()
        }
        .padding(Spacing.m)
        .toolbar(.hidden, for: .navigationBar)
    }
}
