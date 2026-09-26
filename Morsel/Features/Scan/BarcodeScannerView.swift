import SwiftUI
import UIKit
import AVFoundation
import Vision
import VisionKit

// MARK: - BarcodeScannerView
// Live camera barcode scanner built on VisionKit's DataScannerViewController.
// Falls back to a typed-barcode form when scanning is unsupported (Simulator, old devices)
// or when camera access was denied, so the whole flow stays testable everywhere.

@MainActor
struct BarcodeScannerView: View {
    /// When true the scanner stops recognising until `isPaused` flips back (after a hit).
    var isPaused: Bool
    var onScan: (String) -> Void

    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    /// True when this device can run the live scanner at all (false on the Simulator).
    static var isLiveScanningSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        if !Self.isLiveScanningSupported {
            ManualBarcodeEntryView(reason: "Camera scanning isn't available on this device.", onSubmit: onScan)
        } else {
            switch cameraStatus {
            case .authorized:
                if DataScannerViewController.isAvailable {
                    DataScannerRepresentable(isPaused: isPaused, onScan: onScan)
                        .ignoresSafeArea()
                } else {
                    ManualBarcodeEntryView(reason: "The camera isn't available right now.", onSubmit: onScan)
                }
            case .notDetermined:
                Color.black
                    .ignoresSafeArea()
                    .task { await requestCameraAccess() }
            default:
                ManualBarcodeEntryView(reason: "Camera access is off. Turn it on in Settings to scan, or type the barcode.",
                                       showsSettingsLink: true,
                                       onSubmit: onScan)
            }
        }
    }

    private func requestCameraAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = granted ? .authorized : .denied
    }
}

// MARK: - Torch

/// Tiny helper around the back camera's torch. Works alongside DataScannerViewController
/// because both talk to the same shared capture device.
enum Torch {
    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    /// Returns the resulting state (false if the device has no torch or could not be configured).
    @discardableResult
    static func set(on: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            return on
        } catch {
            return false
        }
    }
}

// MARK: - VisionKit wrapper

struct DataScannerRepresentable: UIViewControllerRepresentable {
    var isPaused: Bool
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerHostController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        let host = ScannerHostController(scanner: scanner)
        host.isPaused = isPaused
        return host
    }

    func updateUIViewController(_ host: ScannerHostController, context: Context) {
        context.coordinator.onScan = onScan
        host.isPaused = isPaused
    }

    static func dismantleUIViewController(_ host: ScannerHostController, coordinator: Coordinator) {
        host.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    // MARK: Coordinator (delegate + debounce)

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        private var lastCode: String?
        private var lastScanAt: Date = .distantPast
        private let debounceInterval: TimeInterval = 2

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    report(payload)
                    return
                }
            }
        }

        private func report(_ code: String) {
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let now = Date()
            if trimmed == lastCode, now.timeIntervalSince(lastScanAt) < debounceInterval { return }
            lastCode = trimmed
            lastScanAt = now
            onScan(trimmed)
        }
    }
}

/// Hosts the DataScannerViewController as a child so scanning starts only once the view is on
/// screen (VisionKit requires that) and can be paused/resumed from SwiftUI state.
final class ScannerHostController: UIViewController {
    let scanner: DataScannerViewController
    private var isOnScreen = false

    var isPaused = false {
        didSet { applyScanningState() }
    }

    init(scanner: DataScannerViewController) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ScannerHostController is code-only")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        applyScanningState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isOnScreen = false
        stop()
    }

    func stop() {
        if scanner.isScanning { scanner.stopScanning() }
    }

    private func applyScanningState() {
        if isPaused {
            stop()
        } else if isOnScreen, !scanner.isScanning {
            try? scanner.startScanning()
        }
    }
}

// MARK: - Manual entry fallback

/// Simulator / no-camera fallback: type the digits, tap "Look up".
struct ManualBarcodeEntryView: View {
    var reason: String
    var showsSettingsLink: Bool = false
    var onSubmit: (String) -> Void

    @State private var code = ""
    @FocusState private var isFocused: Bool

    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.mTextTertiary)
                    .padding(.top, Spacing.xl)
                Text(reason)
                    .font(MorselFont.callout)
                    .foregroundStyle(Color.mTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.l)

                Card {
                    TextField("Enter barcode", text: $code)
                        .font(MorselFont.numeral)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .submitLabel(.search)
                        .onSubmit(submit)
                }

                Button("Look up", action: submit)
                    .buttonStyle(.morselPrimary)
                    .disabled(trimmedCode.isEmpty)
                    .opacity(trimmedCode.isEmpty ? 0.5 : 1)

                if showsSettingsLink, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .font(MorselFont.callout.weight(.medium))
                        .foregroundStyle(Color.mAccent)
                        .padding(.top, Spacing.s)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.mBackground.ignoresSafeArea())
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !trimmedCode.isEmpty else { return }
        onSubmit(trimmedCode)
    }
}
