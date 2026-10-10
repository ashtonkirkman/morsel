import AVFoundation
import SwiftUI
import UIKit

/// Live rear-camera preview for `MealCameraController.session`. Layout only; capture lives in the controller.
struct MealCameraView: UIViewControllerRepresentable {
    let session: AVCaptureSession

    func makeUIViewController(context: Context) -> CameraPreviewViewController {
        CameraPreviewViewController(session: session)
    }

    func updateUIViewController(_ uiViewController: CameraPreviewViewController, context: Context) {}
}

final class CameraPreviewViewController: UIViewController {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}
