import CoreML
import Foundation
import Observation

/// Downloads, compiles and loads the SAM 2.1 Core ML models on demand into Application Support/SAM2/<variant>.
/// `isInstalled` is derived from disk, never persisted. Every failure is reported in `state`, never thrown to the UI.
@MainActor
@Observable
final class SAM2ModelStore {
    enum State: Equatable {
        case idle
        case downloading(fraction: Double, bytes: Int64)
        case compiling(String)
        case installed
        case failed(String)
    }

    static let shared = SAM2ModelStore()
    static let defaultVariant: SAM2Model.Variant = .small

    let variant: SAM2Model.Variant
    private(set) var state: State = .idle
    @ObservationIgnored private var loaded: SAM2Model?
    @ObservationIgnored private var installTask: Task<Void, Never>?

    init(variant: SAM2Model.Variant = SAM2ModelStore.defaultVariant) {
        self.variant = variant
        state = isInstalled ? .installed : .idle
    }

    // MARK: - Paths

    static func directory(for variant: SAM2Model.Variant) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SAM2", isDirectory: true).appendingPathComponent(variant.rawValue, isDirectory: true)
    }

    var directory: URL { Self.directory(for: variant) }

    /// True when all three compiled models exist on disk.
    var isInstalled: Bool {
        variant.packageNames.allSatisfy { name in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name + ".mlmodelc").path)
        }
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .compiling: return true
        default: return false
        }
    }

    /// Files inside each `.mlpackage` that make up the model (Hugging Face layout).
    static let packageFiles = ["Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"]

    static func downloadURL(repository: String, package: String, file: String) -> URL? {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(package).mlpackage/\(file)")
    }

    // MARK: - Loading

    /// Cached model, loaded on first use. Nil (never throws) when not installed or loading fails.
    func model() -> SAM2Model? {
        if let loaded { return loaded }
        guard isInstalled else { return nil }
        do {
            let model = try SAM2Model(variant: variant, directory: directory)
            loaded = model
            return model
        } catch {
            state = .failed("The Segment Anything model couldn't be loaded: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Install / remove

    func install() {
        guard !isBusy else { return }
        if isInstalled { state = .installed; return }
        state = .downloading(fraction: 0, bytes: 0)
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performInstall()
                self.loaded = nil
                self.state = self.isInstalled ? .installed : .failed("The download finished but the model files are missing.")
            } catch is CancellationError {
                self.state = .idle
            } catch {
                self.state = .failed(Self.message(for: error))
            }
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    func remove() {
        cancelInstall()
        loaded = nil
        try? FileManager.default.removeItem(at: directory)
        state = .idle
    }

    private func performInstall() async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("sam2-download-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let downloader = ProgressDownloader()
        defer { downloader.invalidate() }
        var downloadedBefore: Int64 = 0
        let total = variant.approximateBytes
        for package in variant.packageNames {
            for file in Self.packageFiles {
                try Task.checkCancellation()
                guard let url = Self.downloadURL(repository: variant.repository, package: package, file: file) else {
                    throw URLError(.badURL)
                }
                let destination = staging.appendingPathComponent("\(package).mlpackage/\(file)")
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let before = downloadedBefore
                let size = try await downloader.download(url, to: destination) { [weak self] written, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        let bytes = before + written
                        self.state = .downloading(fraction: min(0.99, Double(bytes) / Double(total)), bytes: bytes)
                    }
                }
                downloadedBefore += size
            }
        }

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for package in variant.packageNames {
            try Task.checkCancellation()
            state = .compiling(package)
            let packageURL = staging.appendingPathComponent("\(package).mlpackage", isDirectory: true)
            let compiled = try await Task.detached(priority: .userInitiated) { () -> URL in
                try MLModel.compileModel(at: packageURL)
            }.value
            let target = directory.appendingPathComponent(package + ".mlmodelc", isDirectory: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: compiled, to: target)
        }
    }

    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: return "No internet connection. Try again when you're online."
            case .cancelled: return "Download cancelled."
            default: return "Download failed. \(urlError.localizedDescription)"
            }
        }
        return "Couldn't install the model. \(error.localizedDescription)"
    }
}

// MARK: - Downloader

/// One-file-at-a-time `URLSessionDownloadTask` with byte progress, bridged to async/await.
final class ProgressDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<Int64, Error>?
    private var destination: URL?
    private var onProgress: ((Int64, Int64) -> Void)?
    private var moveError: Error?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Breaks the session → delegate retain cycle. Call once all downloads are done.
    func invalidate() { session.invalidateAndCancel() }

    /// Downloads `url` to `destination` (replacing any existing file) and returns the byte count.
    func download(_ url: URL, to destination: URL, onProgress: @escaping (Int64, Int64) -> Void) async throws -> Int64 {
        self.destination = destination
        self.onProgress = onProgress
        self.moveError = nil
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int64, Error>) in
                self.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is only valid inside this callback, so move it synchronously.
        guard let destination else { return }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else if let moveError {
            continuation.resume(throwing: moveError)
        } else if let destination,
                  let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value {
            continuation.resume(returning: size)
        } else {
            continuation.resume(throwing: URLError(.cannotCreateFile))
        }
    }
}
