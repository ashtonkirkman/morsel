import Foundation

/// The three photos a body scan is made of. Ported from FreeFit's `POSE_STEPS` (the back view was dropped).
/// Each photo may show the whole body or only the upper body (`BodyFraming`).
enum BodyPoseType: String, Codable, CaseIterable, Identifiable {
    case frontArmsDown = "front_arms_down"
    case frontArmsOut = "front_arms_out"
    case sideLeft = "side_left"

    var id: String { rawValue }

    /// 1-based position in the capture flow.
    var stepNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    var title: String {
        switch self {
        case .frontArmsDown: return "Front — arms at sides"
        case .frontArmsOut: return "Front — arms extended"
        case .sideLeft: return "Left side profile"
        }
    }

    var shortName: String {
        switch self {
        case .frontArmsDown: return "Front"
        case .frontArmsOut: return "T-pose"
        case .sideLeft: return "Side"
        }
    }

    var summary: String {
        switch self {
        case .frontArmsDown: return "Stand facing the camera. Arms relaxed at your sides, feet together."
        case .frontArmsOut: return "Same position, but extend both arms straight out to the sides (T-pose)."
        case .sideLeft: return "Turn 90° to your right so your left side faces the camera."
        }
    }

    var tips: [String] {
        switch self {
        case .frontArmsDown:
            return ["Feet together, toes pointing forward",
                    "Arms straight down at your sides",
                    "Look directly into the camera",
                    "Head to toes in frame for every number; head to hips also works"]
        case .frontArmsOut:
            return ["Feet shoulder-width apart",
                    "Arms extended horizontally, palms down",
                    "Keep arms at shoulder height",
                    "Head to toes in frame for every number; head to hips also works"]
        case .sideLeft:
            return ["Turn 90° — left side toward camera",
                    "Arms at your sides",
                    "Stand straight, feet together",
                    "Head to toes in frame for every number; head to hips also works"]
        }
    }

    var keyMetrics: [String] {
        switch self {
        case .frontArmsDown: return ["Waist", "Thighs & calves", "Body fat estimate", "Torso : leg ratio"]
        case .frontArmsOut: return ["Arm span & ape index", "Arm circumferences", "Chest & hips"]
        case .sideLeft: return ["Torso depth", "Better waist / chest / hip circumferences"]
        }
    }

    /// SF Symbol shown on the step chip.
    var symbolName: String {
        switch self {
        case .frontArmsDown: return "figure.stand"
        case .frontArmsOut: return "figure.arms.open"
        case .sideLeft: return "figure.walk"
        }
    }
}
