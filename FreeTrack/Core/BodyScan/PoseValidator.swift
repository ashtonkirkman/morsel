import Foundation

/// Sanity checks on detected joints: how much of the body is in frame, does it look like the requested pose,
/// and how well does the person mask agree with the joints. Pure Swift.
enum PoseValidator {
    struct Result: Equatable {
        /// Nil when nothing usable was found (no pose, or the head and shoulders are missing).
        var framing: BodyFraming?
        var poseMatched: Bool
        /// Plain-English problem, nil when everything looks right.
        var message: String?

        var isFullBody: Bool { framing == .fullBody }
    }

    static let noPoseMessage = "No pose detected. Make sure you're visible and well-lit."
    static let headAndShouldersMessage = "We couldn't see your head and shoulders. Face the camera with at least your head and shoulders in the frame."
    /// Kept for callers that want the old wording for a "step back" hint.
    static let notFullBodyMessage = "We couldn't see your whole body. Step back so your head and feet are both in the frame."
    static let busyBackgroundMessage = "The background looks busy. Stand in front of a plain wall with nothing else in the frame."

    static let minimumJoints: [BodyJoint] = [.nose, .leftShoulder, .rightShoulder]
    static let upperBodyJoints: [BodyJoint] = minimumJoints + [.leftHip, .rightHip]
    static let fullBodyJoints: [BodyJoint] = upperBodyJoints + [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
    /// Kept for compatibility with older call sites: the joints a full-body photo must contain.
    static let requiredJoints: [BodyJoint] = fullBodyJoints

    /// Height ≈ nose → hip × this (nose ≈ 0.93 H above the floor, hip joint ≈ 0.53 H).
    static let noseToHipHeightFactor = 2.55
    /// Height ≈ shoulder joint span × this (biacromial breadth ≈ 0.225 H).
    static let shoulderSpanHeightFactor = 4.4

    static func validate(_ kp: BodyKeypoints, poseType: BodyPoseType) -> Result {
        guard !kp.joints.isEmpty else { return Result(framing: nil, poseMatched: false, message: noPoseMessage) }
        guard let framing = framing(of: kp) else {
            return Result(framing: nil, poseMatched: false, message: headAndShouldersMessage)
        }
        let scale = bodyScale(kp)
        let matched = matches(kp, poseType: poseType, bodyScale: scale, framing: framing)
        return Result(framing: framing, poseMatched: matched, message: matched ? nil : mismatchMessage(for: poseType))
    }

    /// Which part of the body is visible, or nil when even the head and shoulders are missing.
    static func framing(of kp: BodyKeypoints) -> BodyFraming? {
        guard kp.has(minimumJoints, minConfidence: 0.2), let nose = kp.point(.nose), let shoulderMid = kp.shoulderMid,
              shoulderMid.y - nose.y > 1 else { return nil }
        // Vision extrapolates joints past the bottom edge of a cropped photo; only joints inside the frame count.
        let frameHeight = Double(kp.imageHeight)
        func inFrame(_ p: BodyPoint) -> Bool { frameHeight <= 0 || p.y < frameHeight }
        if kp.has(fullBodyJoints, minConfidence: 0.2), let ankleMid = kp.ankleMid, ankleMid.y - nose.y > 1,
           let hipMid = kp.hipMid, ankleMid.y > hipMid.y, inFrame(ankleMid) {
            return .fullBody
        }
        if kp.has(upperBodyJoints, minConfidence: 0.2), let hipMid = kp.hipMid, hipMid.y - shoulderMid.y > 1, inFrame(hipMid) {
            return .upperBody
        }
        return .headAndShoulders
    }

    /// Nose → ankle distance in pixels, or an estimate of it from what is visible (nose → hip, or the shoulder
    /// span), so thresholds expressed as fractions of body height work for partial photos too.
    static func bodyScale(_ kp: BodyKeypoints) -> Double {
        guard let nose = kp.point(.nose) else { return 1 }
        if let ankleMid = kp.ankleMid, ankleMid.y - nose.y > 1 { return ankleMid.y - nose.y }
        // Nose → ankle ≈ 0.885 H.
        if let hipMid = kp.hipMid, hipMid.y - nose.y > 1 { return (hipMid.y - nose.y) * noseToHipHeightFactor * 0.885 }
        if let ls = kp.point(.leftShoulder), let rs = kp.point(.rightShoulder) {
            let span = BodyPoint.distance(ls, rs)
            if span > 1 { return span * shoulderSpanHeightFactor * 0.885 }
        }
        return 1
    }

    static func mismatchMessage(for poseType: BodyPoseType) -> String {
        switch poseType {
        case .frontArmsDown: return "Arms don't look relaxed at your sides. Let them hang straight down and face the camera."
        case .frontArmsOut: return "Arms don't look extended. Raise them straight out to the sides at shoulder height."
        case .sideLeft: return "This doesn't look like a side view. Turn 90° so your left side faces the camera."
        }
    }

    /// Geometric pose test. `bodyScale` is the (possibly estimated) nose → ankle distance in pixels. With a
    /// partial photo the test only uses what is visible: arms-down is accepted without wrists as long as the
    /// person faces the camera, the T-pose always needs the wrists, and the side view only needs narrow shoulders.
    static func matches(_ kp: BodyKeypoints, poseType: BodyPoseType, bodyScale: Double, framing: BodyFraming = .fullBody) -> Bool {
        guard bodyScale > 0, let ls = kp.point(.leftShoulder), let rs = kp.point(.rightShoulder) else { return false }
        let shoulderSpan = abs(ls.x - rs.x)
        let hips: (BodyPoint, BodyPoint)? = {
            guard let lh = kp.point(.leftHip), let rh = kp.point(.rightHip) else { return nil }
            return (lh, rh)
        }()
        switch poseType {
        case .sideLeft:
            guard shoulderSpan < 0.10 * bodyScale else { return false }
            if let hips { return abs(hips.0.x - hips.1.x) < 0.10 * bodyScale }
            return true
        case .frontArmsDown:
            guard shoulderSpan > 0.12 * bodyScale else { return false }
            guard let lw = kp.point(.leftWrist, minConfidence: 0.2), let rw = kp.point(.rightWrist, minConfidence: 0.2) else {
                // A head-and-shoulders or head-to-hips photo rarely shows the hands; facing the camera is enough.
                return framing != .fullBody
            }
            if let hips {
                let (lh, rh) = hips
                let hipY = (lh.y + rh.y) / 2
                let handsLow = lw.y > hipY - 0.10 * bodyScale && rw.y > hipY - 0.10 * bodyScale
                let handsClose = abs(lw.x - lh.x) < 0.25 * bodyScale && abs(rw.x - rh.x) < 0.25 * bodyScale
                return handsLow && handsClose
            }
            // Head and shoulders only: hands below the shoulders and not flung out.
            let handsLow = lw.y > ls.y + 0.15 * bodyScale && rw.y > rs.y + 0.15 * bodyScale
            let handsClose = abs(lw.x - ls.x) < 0.25 * bodyScale && abs(rw.x - rs.x) < 0.25 * bodyScale
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
        guard let b = kp.bounds, kp.point(.nose) != nil else { return 0 }
        let scale = max(bodyScale(kp), 1)
        let padX = max((b.maxX - b.minX) * 0.35, scale * 0.15)
        // With a partial photo the body continues below the lowest joint to the frame edge.
        let bottom = kp.ankleMid != nil ? Int(b.maxY + scale * 0.08) : mask.height - 1
        let inside = mask.foregroundFraction(insideX: Int(b.minX - padX), Int(b.maxX + padX),
                                             y: Int(b.minY - scale * 0.18), bottom)
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
    /// With a partial photo the body fills the frame below the joints, so the box is extended to the bottom edge.
    static func looksLikeBusyBackground(_ mask: BodyMask, keypoints kp: BodyKeypoints) -> Bool {
        guard let b = kp.bounds, kp.point(.nose) != nil else { return false }
        let scale = max(bodyScale(kp), 1)
        let padX = max((b.maxX - b.minX) * 0.35, scale * 0.15)
        let bottom = kp.ankleMid != nil ? Int(b.maxY + scale * 0.08) : mask.height - 1
        let inside = mask.foregroundFraction(insideX: Int(b.minX - padX), Int(b.maxX + padX),
                                             y: Int(b.minY - scale * 0.18), bottom)
        return inside < 0.75
    }
}
