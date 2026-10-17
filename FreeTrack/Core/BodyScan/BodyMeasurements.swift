import Foundation

/// One analysed photo: which pose it was meant to be, the joints found, and the person mask (nil when
/// segmentation failed; lengths still work, widths don't).
struct PoseObservation {
    var poseType: BodyPoseType
    var keypoints: BodyKeypoints
    var mask: BodyMask?
    /// 0…1 estimate of how well the mask matches the joints (coverage inside the joint box, no stray blobs).
    var maskQuality: Double
    /// Whether the joints look like the requested pose (`PoseValidator`).
    var poseMatched: Bool
    /// How much of the body the photo shows (`PoseValidator.framing(of:)`).
    var framing: BodyFraming

    init(poseType: BodyPoseType, keypoints: BodyKeypoints, mask: BodyMask?, maskQuality: Double = 1, poseMatched: Bool = true,
         framing: BodyFraming = .fullBody) {
        self.poseType = poseType
        self.keypoints = keypoints
        self.mask = mask
        self.maskQuality = maskQuality
        self.poseMatched = poseMatched
        self.framing = framing
    }
}

/// Everything the measurement engine needs for one scan. Metric units.
struct BodyScanInput {
    var front: PoseObservation?
    var tPose: PoseObservation?
    var side: PoseObservation?
    var heightCm: Double
    var weightKg: Double
    var sex: BiologicalSex
    var age: Int?
    /// Shoulder joint span in cm from an earlier full-body scan. Lets a head-to-hips photo be scaled from the
    /// shoulders instead of population proportions.
    var referenceShoulderWidthCm: Double? = nil

    var observations: [PoseObservation] { [front, tPose, side].compactMap { $0 } }
}

/// Full result of a scan. Values are keyed by `BodyMetric.rawValue` so the JSON stays flat and forward-compatible.
struct BodyMeasurements: Codable, Equatable {
    /// Which photos contributed.
    var poses: [BodyPoseType] = []
    var heightCm: Double = 0
    var weightKg: Double = 0
    var sexRaw: String = BiologicalSex.male.rawValue
    var age: Int?
    /// Pixel-per-centimetre scale of the front photo and how it was derived ("mask", "keypoints",
    /// "referenceShoulders", "noseHipEstimate", "shoulderEstimate").
    var frontPxPerCm: Double?
    var scaleSource: String?
    /// `BodyFraming` of the primary (front, else T-pose) photo. Nil in scans made before partial framing existed.
    var framingRaw: String?
    /// Which pose each metric was taken from (for "from T-pose" labels).
    var sources: [String: String] = [:]
    var values: [String: MeasuredValue] = [:]
    /// Bumped when the formulas change so old scans can be flagged.
    var engineVersion: Int = BodyMeasurementEngine.version

    var sex: BiologicalSex { BiologicalSex(rawValue: sexRaw) ?? .male }

    var framing: BodyFraming? { framingRaw.flatMap(BodyFraming.init(rawValue:)) }

    /// Human label for how the pixel scale was derived.
    var scaleSourceTitle: String? {
        switch scaleSource {
        case "mask": return "scale from silhouette"
        case "keypoints": return "scale from joints"
        case "referenceShoulders": return "scale from an earlier full-body scan"
        case "noseHipEstimate", "shoulderEstimate": return "approximate scale (partial photo)"
        default: return nil
        }
    }

    subscript(metric: BodyMetric) -> MeasuredValue? {
        get { values[metric.rawValue] }
        set { values[metric.rawValue] = newValue }
    }

    func value(_ metric: BodyMetric) -> Double? { self[metric]?.value }

    func source(_ metric: BodyMetric) -> BodyPoseType? {
        sources[metric.rawValue].flatMap(BodyPoseType.init(rawValue:))
    }

    mutating func set(_ metric: BodyMetric, _ value: Double?, _ confidence: MeasurementConfidence, source: BodyPoseType? = nil) {
        guard let value, value.isFinite else { return }
        self[metric] = MeasuredValue(value, confidence)
        if let source { sources[metric.rawValue] = source.rawValue }
    }

    /// Metrics present, in declaration order, filtered to a group.
    func metrics(in group: BodyMetricGroup) -> [BodyMetric] {
        BodyMetric.allCases.filter { $0.group == group && values[$0.rawValue] != nil }
    }

    /// Lowest confidence across the key metrics, used for the summary badge.
    var overallConfidence: MeasurementConfidence {
        let present = BodyMetric.keyMetrics.compactMap { self[$0]?.confidence }
        return present.min() ?? .low
    }

    // MARK: - JSON

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    func encoded() throws -> Data { try Self.encoder.encode(self) }

    static func decode(_ data: Data) -> BodyMeasurements? {
        try? JSONDecoder().decode(BodyMeasurements.self, from: data)
    }
}
