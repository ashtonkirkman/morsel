import Foundation

/// Sanity checks on detected joints: is the whole body in frame, does it look like the requested pose,
/// and how well does the person mask agree with the joints. Pure Swift.
enum PoseValidator {
    struct Result: Equatable {
        var isFullBody: Bool
        var poseMatched: Bool
        /// Plain-English problem, nil when everything looks right.
        var message: String?
    }

    static let noPoseMessage = "No pose detected. Ensure your full body is visible and well-lit."
    static let notFullBodyMessage = "We couldn't see your whole body. Step back so your head and feet are both in the frame."
    static let busyBackgroundMessage = "The background looks busy. Stand in front of a plain wall with nothing else in the frame."

    static let requiredJoints: [BodyJoint] = [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip,
                                              .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]

    static func validate(_ kp: BodyKeypoints, poseType: BodyPoseType) -> Result {
        guard !kp.joints.isEmpty else { return Result(isFullBody: false, poseMatched: false, message: noPoseMessage) }
        guard kp.has(requiredJoints, minConfidence: 0.2), let nose = kp.point(.nose), let ankleMid = kp.ankleMid,
              ankleMid.y - nose.y > 1 else {
            return Result(isFullBody: false, poseMatched: false, message: notFullBodyMessage)
        }
        let bodyScale = ankleMid.y - nose.y
        let matched = matches(kp, poseType: poseType, bodyScale: bodyScale)
        return Result(isFullBody: true, poseMatched: matched, message: matched ? nil : mismatchMessage(for: poseType))
    }

    static func mismatchMessage(for poseType: BodyPoseType) -> String {
        switch poseType {
        case .frontArmsDown: return "Arms don't look relaxed at your sides. Let them hang straight down and face the camera."
        case .frontArmsOut: return "Arms don't look extended. Raise them straight out to the sides at shoulder height."
        case .sideLeft: return "This doesn't look like a side view. Turn 90° so your left side faces the camera."
        }
    }

    /// Geometric pose test. `bodyScale` is the nose → ankle distance in pixels.
    static func matches(_ kp: BodyKeypoints, poseType: BodyPoseType, bodyScale: Double) -> Bool {
        guard bodyScale > 0, let ls = kp.point(.leftShoulder), let rs = kp.point(.rightShoulder),
              let lh = kp.point(.leftHip), let rh = kp.point(.rightHip) else { return false }
        let shoulderSpan = abs(ls.x - rs.x), hipSpan = abs(lh.x - rh.x)
        switch poseType {
        case .sideLeft:
            return shoulderSpan < 0.10 * bodyScale && hipSpan < 0.10 * bodyScale
        case .frontArmsDown:
            guard shoulderSpan > 0.12 * bodyScale,
                  let lw = kp.point(.leftWrist, minConfidence: 0.2), let rw = kp.point(.rightWrist, minConfidence: 0.2) else { return false }
            let hipY = (lh.y + rh.y) / 2
            let handsLow = lw.y > hipY - 0.10 * bodyScale && rw.y > hipY - 0.10 * bodyScale
            let handsClose = abs(lw.x - lh.x) < 0.25 * bodyScale && abs(rw.x - rh.x) < 0.25 * bodyScale
            return handsLow && handsClose
        case .frontArmsOut:
            guard shoulderSpan > 0.12 * bodyScale,
                  let lw = kp.point(.leftWrist, minConfidence: 0.2), let rw = kp.point(.rightWrist, minConfidence: 0.2) else { return false }
            let level = abs(lw.y - ls.y) < 0.15 * bodyScale && abs(rw.y - rs.y) < 0.15 * bodyScale
            let wide = abs(lw.x - ls.x) > 0.20 * bodyScale && abs(rw.x - rs.x) > 0.20 * bodyScale
            return level && wide
        }
    }

    /// 0…1 agreement between the mask and the joints: how much of the foreground sits inside the (padded)
    /// joint box, how many joints land on foreground, and whether the overall coverage is plausible.
    static func maskQuality(_ mask: BodyMask, keypoints kp: BodyKeypoints) -> Double {
        guard let b = kp.bounds, let nose = kp.point(.nose), let ankleMid = kp.ankleMid else { return 0 }
        let bodyScale = max(ankleMid.y - nose.y, 1)
        let padX = max((b.maxX - b.minX) * 0.35, bodyScale * 0.15)
        let inside = mask.foregroundFraction(insideX: Int(b.minX - padX), Int(b.maxX + padX),
                                             y: Int(b.minY - bodyScale * 0.18), Int(b.maxY + bodyScale * 0.08))
        let hits = kp.joints.filter { j in
            let x = Int(j.x.rounded()), y = Int(j.y.rounded())
            return mask.isForeground(x, y) || mask.isForeground(x + 3, y) || mask.isForeground(x - 3, y)
                || mask.isForeground(x, y + 3) || mask.isForeground(x, y - 3)
        }.count
        let jointHit = kp.joints.isEmpty ? 0 : Double(hits) / Double(kp.joints.count)
        let coverage = mask.coverage
        let coveragePenalty = (0.02...0.75).contains(coverage) ? 1.0 : 0.5
        return min(1, max(0, (0.5 * inside + 0.5 * jointHit) * coveragePenalty))
    }

    /// True when a large share of the mask lies away from the body (another person, furniture, a busy wall).
    static func looksLikeBusyBackground(_ mask: BodyMask, keypoints kp: BodyKeypoints) -> Bool {
        guard let b = kp.bounds, let nose = kp.point(.nose), let ankleMid = kp.ankleMid else { return false }
        let bodyScale = max(ankleMid.y - nose.y, 1)
        let padX = max((b.maxX - b.minX) * 0.35, bodyScale * 0.15)
        let inside = mask.foregroundFraction(insideX: Int(b.minX - padX), Int(b.maxX + padX),
                                             y: Int(b.minY - bodyScale * 0.18), Int(b.maxY + bodyScale * 0.08))
        return inside < 0.75
    }
}
