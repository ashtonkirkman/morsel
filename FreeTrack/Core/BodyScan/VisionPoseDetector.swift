import CoreGraphics
import Foundation
import Vision

/// `VNDetectHumanBodyPoseRequest` → `BodyKeypoints` in pixel coordinates (y down). Runs off the main thread.
enum VisionPoseDetector {
    /// Vision joint → our joint. Vision (like MediaPipe) uses the person's own left/right.
    private static let jointMap: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.root, .root), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
    ]

    /// Joints of the most prominent person in the image, or nil when nobody was found.
    static func detect(in image: CGImage) async throws -> BodyKeypoints? {
        try await Task.detached(priority: .userInitiated) { () -> BodyKeypoints? in
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            try handler.perform([request])
            guard let observations = request.results, !observations.isEmpty else { return nil }
            let candidates = observations.map { keypoints(from: $0, width: image.width, height: image.height) }
            return candidates.max { verticalExtent($0) < verticalExtent($1) }
        }.value
    }

    private static func verticalExtent(_ kp: BodyKeypoints) -> Double {
        guard let b = kp.bounds else { return 0 }
        return b.maxY - b.minY
    }

    static func keypoints(from observation: VNHumanBodyPoseObservation, width: Int, height: Int) -> BodyKeypoints {
        let points = (try? observation.recognizedPoints(.all)) ?? [:]
        var joints: [BodyKeypoint] = []
        for (visionName, joint) in jointMap {
            guard let p = points[visionName], p.confidence > 0 else { continue }
            // Vision's origin is bottom-left with normalised coordinates.
            joints.append(BodyKeypoint(joint: joint,
                                       x: Double(p.location.x) * Double(width),
                                       y: (1 - Double(p.location.y)) * Double(height),
                                       confidence: Double(p.confidence)))
        }
        return BodyKeypoints(imageWidth: width, imageHeight: height, joints: joints)
    }
}
