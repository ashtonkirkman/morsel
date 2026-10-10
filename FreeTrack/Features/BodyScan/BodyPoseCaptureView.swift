import PhotosUI
import SwiftUI

/// Full-screen camera for one pose: faint silhouette guide, self-timer countdown, front/back flip, library picker.
@MainActor
struct BodyPoseCaptureView: View {
    let pose: BodyPoseType
    let countdownSeconds: Int
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var camera = BodyCameraController()
    @State private var pickerItem: PhotosPickerItem?
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var captureError: String?

    private var showsPreview: Bool { camera.isPreviewAvailable }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 12)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel("Taking photo in \(countdown) seconds")
                }
                Spacer()
                controls
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop(); countdownTask?.cancel() }
        .onChange(of: pickerItem) { _, item in loadPicked(item) }
        .statusBarHidden(showsPreview)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if showsPreview {
            MealCameraView(session: camera.session)
                .ignoresSafeArea()
            BodySilhouetteShape(pose: pose)
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [10, 8]))
                .padding(.horizontal, 60)
                .padding(.vertical, 90)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            LinearGradient(colors: [Color.black.opacity(0.5), .clear, .clear, Color.black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color.mBackground.ignoresSafeArea()
            VStack(spacing: Spacing.m) {
                EmptyStateView(symbol: "camera.metering.unknown",
                               title: BodyCameraController.noHardwareMessage,
                               message: unavailableMessage)
            }
        }
    }

    private var unavailableMessage: String {
        if case .unavailable(let message) = camera.state, message != BodyCameraController.noHardwareMessage {
            return message
        }
        return "Pick a photo from your library instead."
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Cancel", action: cancel)
                .font(FreeTrackFont.callout.weight(.medium))
                .foregroundStyle(showsPreview ? Color.white : Color.mAccent)
            Spacer()
            VStack(spacing: 2) {
                Text("\(pose.stepNumber) of \(BodyPoseType.allCases.count) · \(pose.shortName)")
                    .font(FreeTrackFont.headline)
                Text(pose.summary)
                    .font(FreeTrackFont.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(showsPreview ? Color.white : Color.mText)
            Spacer()
            Color.clear.frame(width: 56, height: 1)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Spacing.m) {
            if let captureError {
                Text(captureError)
                    .font(FreeTrackFont.caption)
                    .foregroundStyle(showsPreview ? Color.white : Color.mDanger)
                    .multilineTextAlignment(.center)
            }
            if showsPreview {
                Text(countdown == nil ? "Prop the phone up, tap the shutter, then get into position." : "Hold still…")
                    .font(FreeTrackFont.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                HStack {
                    libraryIconButton
                    Spacer()
                    shutterButton
                    Spacer()
                    flipButton
                }
            } else {
                libraryPrimaryButton
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.l)
    }

    private var shutterButton: some View {
        Button(action: toggleCountdown) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                if countdown == nil {
                    Circle().fill(Color.white).frame(width: 62, height: 62)
                    Text("\(countdownSeconds)s")
                        .font(FreeTrackFont.caption.weight(.semibold))
                        .foregroundStyle(.black)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white).frame(width: 30, height: 30)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.state != .running)
        .accessibilityLabel(countdown == nil ? "Start \(countdownSeconds) second timer" : "Cancel timer")
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

    private var flipButton: some View {
        Button { camera.flip() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.title2)
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(countdown != nil)
        .accessibilityLabel("Switch camera")
    }

    private var libraryPrimaryButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Choose a photo", systemImage: "photo.on.rectangle")
                .font(FreeTrackFont.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.mAccent, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
    }

    // MARK: - Actions

    private func toggleCountdown() {
        if countdown != nil {
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            return
        }
        captureError = nil
        countdown = countdownSeconds
        countdownTask = Task { @MainActor in
            var remaining = countdownSeconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                withAnimation { countdown = remaining }
                if remaining > 0 { Haptics.tap() }
            }
            await capture()
        }
    }

    private func capture() async {
        defer { countdown = nil; countdownTask = nil }
        do {
            let image = try await camera.capturePhoto()
            Haptics.tap()
            onCapture(image)
        } catch {
            captureError = "Couldn't take the photo. Try again or pick one from your library."
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

    private func cancel() {
        countdownTask?.cancel()
        onCancel()
    }
}

// MARK: - Silhouette

/// Faint full-body outline for the requested pose, drawn in the given rect (head at top, feet at bottom).
struct BodySilhouetteShape: Shape {
    let pose: BodyPoseType

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height
        let cx = rect.midX
        let headR = h * 0.065
        let headCenter = CGPoint(x: cx, y: rect.minY + headR)
        let shoulderY = rect.minY + h * 0.19
        let hipY = rect.minY + h * 0.50
        let kneeY = rect.minY + h * 0.74
        let ankleY = rect.maxY - h * 0.02
        let side = pose == .sideLeft
        let shoulderHalf = side ? h * 0.07 : h * 0.13
        let hipHalf = side ? h * 0.075 : h * 0.10

        p.addEllipse(in: CGRect(x: headCenter.x - headR, y: headCenter.y - headR, width: headR * 2, height: headR * 2))
        // Neck
        p.move(to: CGPoint(x: cx, y: headCenter.y + headR))
        p.addLine(to: CGPoint(x: cx, y: shoulderY - h * 0.01))
        // Torso
        var torso = Path()
        torso.move(to: CGPoint(x: cx - shoulderHalf, y: shoulderY))
        torso.addLine(to: CGPoint(x: cx + shoulderHalf, y: shoulderY))
        torso.addLine(to: CGPoint(x: cx + hipHalf, y: hipY))
        torso.addLine(to: CGPoint(x: cx - hipHalf, y: hipY))
        torso.closeSubpath()
        p.addPath(torso)
        // Legs
        let legGap = side ? 0 : h * 0.04
        for sign in [-1.0, 1.0] {
            let hipX = cx + sign * (side ? 0 : hipHalf * 0.5)
            let footX = cx + sign * (side ? h * 0.03 : legGap + hipHalf * 0.5)
            p.move(to: CGPoint(x: hipX, y: hipY))
            p.addLine(to: CGPoint(x: hipX + sign * legGap * 0.3, y: kneeY))
            p.addLine(to: CGPoint(x: footX, y: ankleY))
        }
        // Arms
        switch pose {
        case .frontArmsDown:
            for sign in [-1.0, 1.0] {
                let sx = cx + sign * shoulderHalf
                p.move(to: CGPoint(x: sx, y: shoulderY))
                p.addLine(to: CGPoint(x: sx + sign * h * 0.02, y: shoulderY + h * 0.18))
                p.addLine(to: CGPoint(x: sx + sign * h * 0.035, y: hipY + h * 0.06))
            }
        case .frontArmsOut:
            for sign in [-1.0, 1.0] {
                let sx = cx + sign * shoulderHalf
                p.move(to: CGPoint(x: sx, y: shoulderY))
                p.addLine(to: CGPoint(x: sx + sign * h * 0.17, y: shoulderY + h * 0.005))
                p.addLine(to: CGPoint(x: sx + sign * h * 0.32, y: shoulderY + h * 0.01))
            }
        case .sideLeft:
            p.move(to: CGPoint(x: cx, y: shoulderY))
            p.addLine(to: CGPoint(x: cx + h * 0.02, y: shoulderY + h * 0.18))
            p.addLine(to: CGPoint(x: cx + h * 0.03, y: hipY + h * 0.06))
        }
        return p
    }
}
