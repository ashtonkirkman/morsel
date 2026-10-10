import Foundation

/// How much to trust a single measurement. Derived from joint confidence, mask quality and pose match.
enum MeasurementConfidence: String, Codable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: MeasurementConfidence, rhs: MeasurementConfidence) -> Bool { lhs.rank < rhs.rank }

    var title: String { rawValue.capitalized }

    /// Numeric score compatible with the app's `ConfidenceBadge` thresholds (≥0.8 high, ≥0.5 medium).
    var score: Double {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.9
        }
    }
}

/// One measured number with its confidence. Unit depends on the metric (cm, %, kg or a ratio).
struct MeasuredValue: Codable, Equatable {
    var value: Double
    var confidence: MeasurementConfidence

    init(_ value: Double, _ confidence: MeasurementConfidence) {
        self.value = value
        self.confidence = confidence
    }
}

enum BodyMetricUnit: String, Codable {
    case centimetres, percent, kilograms, ratio
}

enum BodyMetricGroup: String, Codable, CaseIterable {
    case lengths, circumferences, widths, composition, symmetry

    var title: String {
        switch self {
        case .lengths: return "Lengths"
        case .circumferences: return "Circumferences"
        case .widths: return "Widths & depths"
        case .composition: return "Composition"
        case .symmetry: return "Symmetry"
        }
    }
}

/// Every number a scan can produce. Raw values are the JSON keys inside `BodyMeasurements`.
enum BodyMetric: String, Codable, CaseIterable, Identifiable {
    // Lengths (cm)
    case leftUpperArm, rightUpperArm, leftForearm, rightForearm, leftArm, rightArm
    case leftThigh, rightThigh, leftShin, rightShin, leftLeg, rightLeg
    case torso, shoulderWidth, hipWidth, armSpan
    // Widths from the mask (cm)
    case leftUpperArmWidth, rightUpperArmWidth, leftForearmWidth, rightForearmWidth
    case leftThighWidth, rightThighWidth, leftCalfWidth, rightCalfWidth
    case chestWidth, waistWidth, hipsWidth, neckWidth
    case chestDepth, waistDepth, hipsDepth
    // Circumferences (cm)
    case leftUpperArmCircumference, rightUpperArmCircumference, leftForearmCircumference, rightForearmCircumference
    case leftThighCircumference, rightThighCircumference, leftCalfCircumference, rightCalfCircumference
    case chestCircumference, waistCircumference, hipsCircumference, neckCircumference
    // Composition
    case bodyFatPercent, bodyFatPercentRFM, bodyFatPercentNavy, leanMassKg, fatMassKg
    case waistToHipRatio, waistToHeightRatio, apeIndex, torsoToLegRatio, shoulderToHipRatio
    // Symmetry (% difference)
    case armAsymmetry, legAsymmetry, shoulderAsymmetry, thighAsymmetry

    var id: String { rawValue }

    var group: BodyMetricGroup {
        switch self {
        case .leftUpperArm, .rightUpperArm, .leftForearm, .rightForearm, .leftArm, .rightArm,
             .leftThigh, .rightThigh, .leftShin, .rightShin, .leftLeg, .rightLeg,
             .torso, .shoulderWidth, .hipWidth, .armSpan:
            return .lengths
        case .leftUpperArmWidth, .rightUpperArmWidth, .leftForearmWidth, .rightForearmWidth,
             .leftThighWidth, .rightThighWidth, .leftCalfWidth, .rightCalfWidth,
             .chestWidth, .waistWidth, .hipsWidth, .neckWidth, .chestDepth, .waistDepth, .hipsDepth:
            return .widths
        case .leftUpperArmCircumference, .rightUpperArmCircumference, .leftForearmCircumference, .rightForearmCircumference,
             .leftThighCircumference, .rightThighCircumference, .leftCalfCircumference, .rightCalfCircumference,
             .chestCircumference, .waistCircumference, .hipsCircumference, .neckCircumference:
            return .circumferences
        case .bodyFatPercent, .bodyFatPercentRFM, .bodyFatPercentNavy, .leanMassKg, .fatMassKg,
             .waistToHipRatio, .waistToHeightRatio, .apeIndex, .torsoToLegRatio, .shoulderToHipRatio:
            return .composition
        case .armAsymmetry, .legAsymmetry, .shoulderAsymmetry, .thighAsymmetry:
            return .symmetry
        }
    }

    var unit: BodyMetricUnit {
        switch group {
        case .lengths, .widths, .circumferences: return .centimetres
        case .symmetry: return .percent
        case .composition:
            switch self {
            case .bodyFatPercent, .bodyFatPercentRFM, .bodyFatPercentNavy: return .percent
            case .leanMassKg, .fatMassKg: return .kilograms
            default: return .ratio
            }
        }
    }

    var title: String {
        switch self {
        case .leftUpperArm: return "Left upper arm"
        case .rightUpperArm: return "Right upper arm"
        case .leftForearm: return "Left forearm"
        case .rightForearm: return "Right forearm"
        case .leftArm: return "Left arm"
        case .rightArm: return "Right arm"
        case .leftThigh: return "Left thigh"
        case .rightThigh: return "Right thigh"
        case .leftShin: return "Left shin"
        case .rightShin: return "Right shin"
        case .leftLeg: return "Left leg"
        case .rightLeg: return "Right leg"
        case .torso: return "Torso"
        case .shoulderWidth: return "Shoulder width"
        case .hipWidth: return "Hip joint span"
        case .armSpan: return "Arm span"
        case .leftUpperArmWidth: return "Left upper arm width"
        case .rightUpperArmWidth: return "Right upper arm width"
        case .leftForearmWidth: return "Left forearm width"
        case .rightForearmWidth: return "Right forearm width"
        case .leftThighWidth: return "Left thigh width"
        case .rightThighWidth: return "Right thigh width"
        case .leftCalfWidth: return "Left calf width"
        case .rightCalfWidth: return "Right calf width"
        case .chestWidth: return "Chest width"
        case .waistWidth: return "Waist width"
        case .hipsWidth: return "Hips width"
        case .neckWidth: return "Neck width"
        case .chestDepth: return "Chest depth"
        case .waistDepth: return "Waist depth"
        case .hipsDepth: return "Hips depth"
        case .leftUpperArmCircumference: return "Left upper arm"
        case .rightUpperArmCircumference: return "Right upper arm"
        case .leftForearmCircumference: return "Left forearm"
        case .rightForearmCircumference: return "Right forearm"
        case .leftThighCircumference: return "Left thigh"
        case .rightThighCircumference: return "Right thigh"
        case .leftCalfCircumference: return "Left calf"
        case .rightCalfCircumference: return "Right calf"
        case .chestCircumference: return "Chest"
        case .waistCircumference: return "Waist"
        case .hipsCircumference: return "Hips"
        case .neckCircumference: return "Neck"
        case .bodyFatPercent: return "Body fat"
        case .bodyFatPercentRFM: return "Body fat (RFM)"
        case .bodyFatPercentNavy: return "Body fat (US Navy)"
        case .leanMassKg: return "Lean mass"
        case .fatMassKg: return "Fat mass"
        case .waistToHipRatio: return "Waist : hip"
        case .waistToHeightRatio: return "Waist : height"
        case .apeIndex: return "Ape index"
        case .torsoToLegRatio: return "Torso : leg"
        case .shoulderToHipRatio: return "Shoulder : hip"
        case .armAsymmetry: return "Arm asymmetry"
        case .legAsymmetry: return "Leg asymmetry"
        case .shoulderAsymmetry: return "Shoulder asymmetry"
        case .thighAsymmetry: return "Thigh asymmetry"
        }
    }

    /// One-line explanation shown in the detail view.
    var hint: String? {
        switch self {
        case .apeIndex: return "Arm span ÷ height. Above 1.0 means your arm span exceeds your height."
        case .torsoToLegRatio: return "Torso length ÷ average leg length. About 0.5 is typical."
        case .shoulderToHipRatio: return "V-taper: shoulder width ÷ hip joint span. Higher is more tapered."
        case .waistToHipRatio: return "Below 0.90 (men) / 0.85 (women) is considered healthy."
        case .waistToHeightRatio: return "Keeping this under 0.5 is a common guideline."
        case .bodyFatPercentRFM: return "Relative Fat Mass from height and waist. Photo estimate, ±5–10%."
        case .bodyFatPercentNavy: return "US Navy tape method from neck, waist (and hips). Photo estimate."
        case .leanMassKg: return "Weight × (1 − body fat)."
        default: return nil
        }
    }

    /// Metrics in the order the comparison and chart pickers show them.
    static let keyMetrics: [BodyMetric] = [
        .waistCircumference, .bodyFatPercent, .leanMassKg, .chestCircumference, .hipsCircumference,
        .leftUpperArmCircumference, .rightUpperArmCircumference, .leftThighCircumference, .rightThighCircumference,
        .leftCalfCircumference, .rightCalfCircumference, .shoulderWidth
    ]
}
