import Foundation

/// How much of the person is in the photo. A scan no longer needs the whole body: a head-and-shoulders or
/// head-to-hips photo is accepted and simply yields fewer numbers (and a coarser pixel scale).
enum BodyFraming: String, Codable, CaseIterable, Comparable {
    /// Head to ankles visible — every measurement, scale from the silhouette height.
    case fullBody = "full_body"
    /// Head to hips visible — torso, arms, waist and body fat; no legs. Scale from a reference or proportions.
    case upperBody = "upper_body"
    /// Head and shoulders only — shoulder width and neck; mostly a progress photo.
    case headAndShoulders = "head_and_shoulders"

    private var rank: Int {
        switch self {
        case .headAndShoulders: return 0
        case .upperBody: return 1
        case .fullBody: return 2
        }
    }

    static func < (lhs: BodyFraming, rhs: BodyFraming) -> Bool { lhs.rank < rhs.rank }

    var title: String {
        switch self {
        case .fullBody: return "Full body"
        case .upperBody: return "Head to hips"
        case .headAndShoulders: return "Head and shoulders"
        }
    }

    /// Shown under a captured partial photo so people know what the framing cost them.
    var note: String? {
        switch self {
        case .fullBody: return nil
        case .upperBody:
            return "Only your upper body is in frame, so legs weren't measured and the scale is approximate. Step back until your feet are visible for the full set."
        case .headAndShoulders:
            return "Only your head and shoulders are in frame, so this photo gives shoulder and neck numbers plus a progress picture. Include your hips for waist and body fat, or your feet for everything."
        }
    }

    /// Joints that can genuinely be seen with this framing. Anything else Vision reports is extrapolated
    /// off the bottom of the photo and is dropped before measuring or drawing.
    var visibleJoints: Set<BodyJoint> {
        let head: Set<BodyJoint> = [.nose, .leftEye, .rightEye, .leftEar, .rightEar, .neck,
                                    .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
        switch self {
        case .headAndShoulders: return head
        case .upperBody: return head.union([.root, .leftHip, .rightHip])
        case .fullBody: return Set(BodyJoint.allCases)
        }
    }
}
