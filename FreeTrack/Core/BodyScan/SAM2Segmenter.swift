import CoreGraphics
import Foundation

/// `BodySegmenter` backed by SAM 2.1. Positive prompts sit on torso and limb joints, negative prompts in the
/// image corners (a plain background is required anyway). Throws on any model problem so the analyzer can
/// fall back to `VisionPersonSegmenter`.
struct SAM2Segmenter: BodySegmenter {
    let model: SAM2Model

    var name: String { "Segment Anything 2.1 \(model.variant.rawValue)" }

    func segment(image: CGImage, keypoints: BodyKeypoints?) async throws -> BodyMask {
        let prompts = Self.prompts(for: keypoints, width: image.width, height: image.height)
        let model = self.model
        return try await Task.detached(priority: .userInitiated) { () -> BodyMask in
            try model.segment(image: image, prompts: prompts)
        }.value
    }

    /// Up to 10 foreground points on reliable joints plus 4 background points near the corners (≤ 14 total).
    static func prompts(for keypoints: BodyKeypoints?, width: Int, height: Int) -> [SAM2Model.PointPrompt] {
        var out: [SAM2Model.PointPrompt] = []
        if let kp = keypoints {
            if let s = kp.shoulderMid { out.append(.init(x: s.x, y: s.y, isForeground: true)) }
            if let h = kp.hipMid { out.append(.init(x: h.x, y: h.y, isForeground: true)) }
            if let s = kp.shoulderMid, let h = kp.hipMid {
                out.append(.init(x: (s.x + h.x) / 2, y: (s.y + h.y) / 2, isForeground: true))
            }
            let limbJoints: [BodyJoint] = [.nose, .leftKnee, .rightKnee, .leftElbow, .rightElbow, .leftAnkle, .rightAnkle]
            for joint in limbJoints where out.count < 10 {
                if let p = kp.point(joint, minConfidence: 0.3) { out.append(.init(x: p.x, y: p.y, isForeground: true)) }
            }
        }
        if out.isEmpty {
            out.append(.init(x: Double(width) / 2, y: Double(height) / 2, isForeground: true))
        }
        let inset = 0.04
        let w = Double(width), h = Double(height)
        out.append(.init(x: w * inset, y: h * inset, isForeground: false))
        out.append(.init(x: w * (1 - inset), y: h * inset, isForeground: false))
        out.append(.init(x: w * inset, y: h * (1 - inset), isForeground: false))
        out.append(.init(x: w * (1 - inset), y: h * (1 - inset), isForeground: false))
        return Array(out.prefix(SAM2Model.maxPoints))
    }
}
