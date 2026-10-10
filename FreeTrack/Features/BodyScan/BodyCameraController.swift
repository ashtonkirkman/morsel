import AVFoundation
import Observation
import UIKit

/// Camera session for body-scan photos. Same shape as `MealCameraController` but with a front/back toggle,
/// because people scan alone with the phone propped up and want to see themselves on screen.
@Observable
final class BodyCameraController {
    enum State: Equatable {
        case idle
        case starting
        case running
        case unavailable(String)
    }

    static let noHardwareMessage = "Camera unavailable"
    static let deniedMessage = "Camera access is off. Allow it in Settings, or pick a photo from your library."

    static var isHardwareAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVCaptureDevice.default(for: .video) != nil
        #endif
    }

    private(set) var state: State
    private(set) var position: AVCaptureDevice.Position = .front
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.ashtonkirkman.morsel.bodycamera")
    @ObservationIgnored private var currentInput: AVCaptureDeviceInput?
    @ObservationIgnored private var inFlight: PhotoCaptureDelegate?

    init() {
        state = Self.isHardwareAvailable ? .idle : .unavailable(Self.noHardwareMessage)
    }

    var isPreviewAvailable: Bool {
        if case .unavailable = state { return false }
        return true
    }

    // MARK: - Lifecycle

    func start() {
        guard Self.isHardwareAvailable else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            state = .starting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.startSession() } else { self.state = .unavailable(Self.deniedMessage) }
                }
            }
        default:
            state = .unavailable(Self.deniedMessage)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func flip() {
        guard state == .running else { return }
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        position = next
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            _ = self.configureInput(position: next)
            self.session.commitConfiguration()
        }
    }

    private func startSession() {
        state = .starting
        queue.async { [weak self] in
            guard let self else { return }
            let ok = self.configureIfNeeded()
            if ok, !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.state = ok ? .running : .unavailable(Self.noHardwareMessage) }
        }
    }

    /// Runs on `queue`.
    private func configureIfNeeded() -> Bool {
        if currentInput != nil { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard configureInput(position: position) else { return false }
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    /// Runs on `queue` inside begin/commitConfiguration. Swaps the device input for `position`.
    private func configureInput(position: AVCaptureDevice.Position) -> Bool {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        if let currentInput { session.removeInput(currentInput) }
        guard session.canAddInput(input) else {
            if let currentInput, session.canAddInput(currentInput) { session.addInput(currentInput) }
            return false
        }
        session.addInput(input)
        currentInput = input
        return true
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        guard state == .running else { throw ServiceError.invalidImage }
        let mirrored = position == .front
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                DispatchQueue.main.async { self?.inFlight = nil }
                switch result {
                case .success(let image):
                    continuation.resume(returning: mirrored ? Self.unmirrored(image) : image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            inFlight = delegate
            let settings: AVCapturePhotoSettings
            if output.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            queue.async { [output] in
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    /// Front-camera stills come out mirrored relative to the preview; flip them so left stays left.
    private static func unmirrored(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let mirroredOrientation: UIImage.Orientation
        switch image.imageOrientation {
        case .up: mirroredOrientation = .upMirrored
        case .down: mirroredOrientation = .downMirrored
        case .left: mirroredOrientation = .leftMirrored
        case .right: mirroredOrientation = .rightMirrored
        case .upMirrored: mirroredOrientation = .up
        case .downMirrored: mirroredOrientation = .down
        case .leftMirrored: mirroredOrientation = .left
        case .rightMirrored: mirroredOrientation = .right
        @unknown default: return image
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: mirroredOrientation)
    }
}
