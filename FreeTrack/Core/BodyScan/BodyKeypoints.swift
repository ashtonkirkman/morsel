import Foundation

/// Body joints we measure with. Names follow Vision's `VNHumanBodyPoseObservation.JointName`; "left" is the
/// person's left (same convention as MediaPipe in FreeFit), which appears on the image's right in a front photo.
enum BodyJoint: String, Codable, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

    /// Bones drawn by the skeleton overlay.
    static let connections: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder)
    ]
}

/// One detected joint in image pixel coordinates (origin top-left, y down).
struct BodyKeypoint: Codable, Equatable {
    var joint: BodyJoint
    var x: Double
    var y: Double
    /// 0…1 detector confidence.
    var confidence: Double

    var point: BodyPoint { BodyPoint(x: x, y: y) }
}

/// Minimal 2-D point so the measurement code has no CoreGraphics dependency.
struct BodyPoint: Codable, Equatable {
    var x: Double
    var y: Double

    static func distance(_ a: BodyPoint, _ b: BodyPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    static func midpoint(_ a: BodyPoint, _ b: BodyPoint) -> BodyPoint {
        BodyPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// All joints detected in one photo, with the pixel size of the image they refer to.
/// Stored as JSON alongside each scan so the skeleton overlay can be redrawn without the mask.
struct BodyKeypoints: Codable, Equatable {
    var imageWidth: Int
    var imageHeight: Int
    var joints: [BodyKeypoint]

    init(imageWidth: Int, imageHeight: Int, joints: [BodyKeypoint]) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.joints = joints
    }

    subscript(joint: BodyJoint) -> BodyKeypoint? {
        joints.first { $0.joint == joint }
    }

    /// Joint position when detected with at least `minConfidence`.
    func point(_ joint: BodyJoint, minConfidence: Double = 0) -> BodyPoint? {
        guard let kp = self[joint], kp.confidence >= minConfidence else { return nil }
        return kp.point
    }

    func confidence(_ joint: BodyJoint) -> Double { self[joint]?.confidence ?? 0 }

    /// Lowest confidence among `joints` (0 when any is missing).
    func minConfidence(_ joints: [BodyJoint]) -> Double {
        joints.map { confidence($0) }.min() ?? 0
    }

    func has(_ joints: [BodyJoint], minConfidence: Double = 0.2) -> Bool {
        joints.allSatisfy { confidence($0) >= minConfidence }
    }

    /// Axis-aligned bounds of the detected joints, nil when none.
    var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        let xs = joints.map(\.x), ys = joints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return (minX, minY, maxX, maxY)
    }

    var shoulderMid: BodyPoint? {
        guard let l = point(.leftShoulder), let r = point(.rightShoulder) else { return nil }
        return BodyPoint.midpoint(l, r)
    }

    var hipMid: BodyPoint? {
        guard let l = point(.leftHip), let r = point(.rightHip) else { return nil }
        return BodyPoint.midpoint(l, r)
    }

    var ankleMid: BodyPoint? {
        guard let l = point(.leftAnkle), let r = point(.rightAnkle) else { return nil }
        return BodyPoint.midpoint(l, r)
    }

    /// Same joints expressed in another image size (e.g. after resizing the photo).
    func scaled(toWidth width: Int, height: Int) -> BodyKeypoints {
        guard imageWidth > 0, imageHeight > 0 else { return self }
        let sx = Double(width) / Double(imageWidth), sy = Double(height) / Double(imageHeight)
        return BodyKeypoints(imageWidth: width, imageHeight: height,
                             joints: joints.map { BodyKeypoint(joint: $0.joint, x: $0.x * sx, y: $0.y * sy, confidence: $0.confidence) })
    }
}
