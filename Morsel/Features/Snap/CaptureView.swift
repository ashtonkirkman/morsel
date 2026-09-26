import PhotosUI
import SwiftUI

/// Phase 1: full-screen camera with shutter, library picker, optional hint, and Cancel.
/// Falls back to a library-first layout when there is no usable camera (Simulator, no permission).
struct CaptureView: View {
    @Binding var hint: String
    let isConfigured: Bool
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var camera = MealCameraController()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCapturing = false
    @State private var captureError: String?
    @FocusState private var hintFocused: Bool

    private var showsPreview: Bool { camera.isPreviewAvailable }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                if !isConfigured {
                    NotConfiguredCard()
                        .padding(.horizontal, Spacing.m)
                }
                Spacer()
                controls
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in loadPicked(item) }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if showsPreview {
            MealCameraView(session: camera.session)
                .ignoresSafeArea()
            LinearGradient(colors: [.clear, Color.black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color.mBackground.ignoresSafeArea()
            EmptyStateView(symbol: "camera.metering.unknown",
                           title: MealCameraController.noHardwareMessage,
                           message: unavailableMessage)
        }
    }

    private var unavailableMessage: String {
        if case .unavailable(let message) = camera.state, message != MealCameraController.noHardwareMessage {
            return message
        }
        return "Pick a photo from your library instead."
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(MorselFont.callout.weight(.medium))
                .foregroundStyle(showsPreview ? Color.white : Color.mAccent)
            Spacer()
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Spacing.m) {
            if let captureError {
                Text(captureError)
                    .font(MorselFont.caption)
                    .foregroundStyle(showsPreview ? Color.white : Color.mDanger)
            }
            hintField
            if showsPreview {
                cameraRow
            } else {
                libraryPrimaryButton
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.l)
    }

    private var hintField: some View {
        TextField("Anything to add? e.g. “half portion”", text: $hint)
            .font(MorselFont.callout)
            .foregroundStyle(showsPreview ? Color.white : Color.mText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(showsPreview ? AnyShapeStyle(Material.ultraThinMaterial) : AnyShapeStyle(Color.mSurfaceElevated),
                        in: Capsule())
            .focused($hintFocused)
            .submitLabel(.done)
            .onSubmit { hintFocused = false }
    }

    private var cameraRow: some View {
        HStack {
            libraryIconButton
            Spacer()
            shutterButton
            Spacer()
            Color.clear.frame(width: 56, height: 56)
        }
    }

    private var shutterButton: some View {
        Button(action: capture) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(Color.white)
                    .frame(width: 62, height: 62)
                    .opacity(isCapturing ? 0.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.state != .running || isCapturing)
        .accessibilityLabel("Take photo")
    }

    private var libraryIconButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Image(systemName: "photo.on.rectangle")
                .font(.title2)
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Choose from library")
    }

    private var libraryPrimaryButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Choose a photo", systemImage: "photo.on.rectangle")
                .font(MorselFont.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.mAccent, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
    }

    // MARK: - Actions

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        captureError = nil
        hintFocused = false
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let image = try await camera.capturePhoto()
                Haptics.tap()
                onCapture(image)
            } catch {
                captureError = "Couldn't take the photo. Try again or pick one from your library."
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        captureError = nil
        Task { @MainActor in
            defer { pickerItem = nil }
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                onCapture(image)
            } else {
                captureError = "That photo couldn't be read."
            }
        }
    }
}

// MARK: - Not configured

/// Friendly explainer shown above the camera until a key or proxy URL exists.
struct NotConfiguredCard: View {
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "key")
                    .font(.title3)
                    .foregroundStyle(Color.mAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photo logging isn't set up yet")
                        .font(MorselFont.headline)
                        .foregroundStyle(Color.mText)
                    Text("Set up in Settings → Photo logging with a Claude API key or a proxy URL. You can still snap a photo to see how it works.")
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
        }
    }
}
