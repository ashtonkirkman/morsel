import AVFoundation
import Observation
import UIKit

/// Owns the `AVCaptureSession` for the meal camera: permission, configuration on a serial queue,
/// and single-shot JPEG capture. `state` is only mutated on the main thread.
@Observable
final class MealCameraController {
    enum State: Equatable {
        case idle
        case starting
        case running
        case unavailable(String)
    }

    static let noHardwareMessage = "Camera unavailable"
    static let deniedMessage = "Camera access is off. Allow it in Settings, or pick a photo from your library."

    /// False on the Simulator and on devices without a video capture device.
    static var isHardwareAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVCaptureDevice.default(for: .video) != nil
        #endif
    }

    private(set) var state: State
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.ashtonkirkman.morsel.camera")
    @ObservationIgnored private var isConfigured = false
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
                    if granted {
                        self.startSession()
                    } else {
                        self.state = .unavailable(Self.deniedMessage)
                    }
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

    private func startSession() {
        state = .starting
        queue.async { [weak self] in
            guard let self else { return }
            let ok = self.configureIfNeeded()
            if ok, !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.state = ok ? .running : .unavailable(Self.noHardwareMessage)
            }
        }
    }

    /// Runs on `queue`.
    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        isConfigured = true
        return true
    }

    // MARK: - Capture

    /// Takes one still. Throws `ServiceError.invalidImage` when the camera is not running or the data is unreadable.
    func capturePhoto() async throws -> UIImage {
        guard state == .running else { throw ServiceError.invalidImage }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                DispatchQueue.main.async { self?.inFlight = nil }
                continuation.resume(with: result)
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
}

// MARK: - Photo delegate

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, Error>) -> Void

    init(completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(.failure(ServiceError.invalidImage))
            return
        }
        completion(.success(image))
    }
}
