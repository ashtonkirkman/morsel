import Foundation
import Observation

// MARK: - BarcodeScanViewModel
// Drives the scan → lookup → confirm flow. Holds the phase state machine so the views stay small.

@MainActor
@Observable
final class BarcodeScanViewModel {

    // MARK: Phase

    enum Phase: Equatable {
        /// Camera live, waiting for a barcode.
        case scanning
        /// Lookup in flight for `code`.
        case loading(code: String)
        /// Product resolved; the result card is showing.
        case found(FoodItem, code: String)
        /// Open Food Facts does not know this code.
        case notFound(code: String)
        /// Lookup (or save) failed with a plain-English message.
        case failed(message: String, code: String)
        /// User chose "Enter manually" for `code`.
        case manualEntry(code: String)

        /// The barcode this phase refers to, if any.
        var code: String? {
            switch self {
            case .scanning: return nil
            case .loading(let code), .notFound(let code), .manualEntry(let code): return code
            case .found(_, let code), .failed(_, let code): return code
            }
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    // MARK: State

    var phase: Phase = .scanning
    /// Shown inline on the result card when saving to SwiftData fails.
    var saveErrorMessage: String?
    var isTorchOn = false

    private var lookupTask: Task<Void, Never>?

    /// The camera should stop recognising while anything but the live view is showing.
    var isScannerPaused: Bool { phase != .scanning }

    // MARK: Intents

    /// Called by the scanner (or manual code entry). Ignored unless we are actively scanning.
    func handleScan(_ code: String, using service: any BarcodeLookupService) {
        guard case .scanning = phase else { return }
        startLookup(code, using: service)
    }

    func retry(using service: any BarcodeLookupService) {
        guard let code = phase.code else {
            phase = .scanning
            return
        }
        startLookup(code, using: service)
    }

    func scanAgain() {
        lookupTask?.cancel()
        lookupTask = nil
        saveErrorMessage = nil
        phase = .scanning
    }

    func enterManually() {
        guard let code = phase.code else { return }
        saveErrorMessage = nil
        phase = .manualEntry(code: code)
    }

    func reportSaveFailure(_ error: Error) {
        saveErrorMessage = "Couldn't save that entry. \(error.localizedDescription)"
    }

    func cancelWork() {
        lookupTask?.cancel()
        lookupTask = nil
    }

    // MARK: Lookup

    private func startLookup(_ code: String, using service: any BarcodeLookupService) {
        lookupTask?.cancel()
        saveErrorMessage = nil
        phase = .loading(code: code)
        lookupTask = Task { [weak self] in
            do {
                let food = try await service.lookup(barcode: code)
                guard let self, !Task.isCancelled else { return }
                if let food {
                    self.phase = .found(food, code: code)
                } else {
                    self.phase = .notFound(code: code)
                }
            } catch is CancellationError {
                return
            } catch let error as ServiceError {
                guard let self, !Task.isCancelled else { return }
                if error == .cancelled { return }
                if error == .notFound {
                    self.phase = .notFound(code: code)
                } else {
                    self.phase = .failed(message: error.errorDescription ?? "Something went wrong.", code: code)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed(message: error.localizedDescription, code: code)
            }
        }
    }
}
