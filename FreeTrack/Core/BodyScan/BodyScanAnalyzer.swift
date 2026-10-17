import CoreGraphics
import Foundation
import UIKit

/// Result of analysing one photo: the normalised image we keep, the joints + mask, and any warning.
struct PoseAnalysisResult {
    /// Orientation-normalised, downscaled copy of the photo (what gets stored and overlaid).
    let image: UIImage
    let observation: PoseObservation
    let validation: PoseValidator.Result
    /// Non-fatal problem (pose mismatch, busy background) shown above the result.
    let warning: String?
    let segmenterName: String?
}

enum BodyScanAnalysisError: LocalizedError {
    case invalidImage
    case noPose
    /// Not even the head and shoulders were found. (A partial body is fine — see `BodyFraming`.)
    case headNotVisible

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not decode image."
        case .noPose: return PoseValidator.noPoseMessage
        case .headNotVisible: return PoseValidator.headAndShouldersMessage
        }
    }
}

/// Runs the on-device pipeline for a single pose photo: normalise → Vision pose → framing/validation →
/// segmentation (SAM 2 when enabled and installed, Apple Vision otherwise or on any failure). The photo may
/// show the whole body, head to hips, or just head and shoulders. Nothing leaves the phone.
struct BodyScanAnalyzer {
    static let analysisMaxDimension: CGFloat = 1280

    var primary: (any BodySegmenter)?
    var fallback: any BodySegmenter = VisionPersonSegmenter()

    /// Picks SAM 2 when the setting is on and the model is installed; otherwise Apple Vision only.
    @MainActor
    static func make(useSAM2: Bool, store: SAM2ModelStore? = nil) -> BodyScanAnalyzer {
        let store = store ?? SAM2ModelStore.shared
        if useSAM2, let model = store.model() {
            return BodyScanAnalyzer(primary: SAM2Segmenter(model: model))
        }
        return BodyScanAnalyzer(primary: nil)
    }

    func analyze(_ original: UIImage, poseType: BodyPoseType) async throws -> PoseAnalysisResult {
        let image = Self.normalized(original, maxDimension: Self.analysisMaxDimension)
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0 else { throw BodyScanAnalysisError.invalidImage }

        guard let detected = try await VisionPoseDetector.detect(in: cgImage) else { throw BodyScanAnalysisError.noPose }
        let validation = PoseValidator.validate(detected, poseType: poseType)
        guard let framing = validation.framing else { throw BodyScanAnalysisError.headNotVisible }
        // Joints Vision guessed below the edge of a partial photo are dropped before segmenting and measuring.
        let keypoints = detected.restricted(to: framing)

        var mask: BodyMask?
        var segmenterName: String?
        if let primary {
            if let result = try? await primary.segment(image: cgImage, keypoints: keypoints) {
                mask = result
                segmenterName = primary.name
            }
        }
        if mask == nil, let result = try? await fallback.segment(image: cgImage, keypoints: keypoints) {
            mask = result
            segmenterName = fallback.name
        }

        var quality = 0.0
        var warning = validation.message
        if let mask {
            quality = PoseValidator.maskQuality(mask, keypoints: keypoints)
            if warning == nil, PoseValidator.looksLikeBusyBackground(mask, keypoints: keypoints) {
                warning = PoseValidator.busyBackgroundMessage
            }
        }
        let observation = PoseObservation(poseType: poseType, keypoints: keypoints, mask: mask,
                                          maskQuality: quality, poseMatched: validation.poseMatched, framing: framing)
        return PoseAnalysisResult(image: image, observation: observation, validation: validation,
                                  warning: warning, segmenterName: segmenterName)
    }

    /// Redraws the image with `.up` orientation and the long edge at most `maxDimension` points (scale 1).
    static func normalized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return image }
        let scale = min(1, maxDimension / longest)
        let newSize = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
