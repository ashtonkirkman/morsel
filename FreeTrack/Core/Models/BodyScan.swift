import Foundation
import SwiftData

/// One body scan: inputs, the key metrics flattened for queries/charts, the full `BodyMeasurements` as JSON,
/// the joints per pose (to redraw the skeleton overlay) and the photo file names. Photos never sync.
@Model
final class BodyScan {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var heightCm: Double
    var weightKg: Double
    var sexRaw: String
    var notes: String?
    var isBaseline: Bool

    // Flattened key metrics (cm / % / kg) for charts and comparisons.
    var waistCm: Double?
    var chestCm: Double?
    var hipsCm: Double?
    var leftUpperArmCm: Double?
    var rightUpperArmCm: Double?
    var leftThighCm: Double?
    var rightThighCm: Double?
    var leftCalfCm: Double?
    var rightCalfCm: Double?
    var shoulderWidthCm: Double?
    var bodyFatPercent: Double?
    var leanMassKg: Double?
    var armSpanCm: Double?
    var leftArmLengthCm: Double?
    var rightArmLengthCm: Double?
    var leftLegLengthCm: Double?
    var rightLegLengthCm: Double?

    /// Full `BodyMeasurements` (Codable JSON).
    var measurementsJSON: Data
    /// `[BodyPoseType.rawValue: BodyKeypoints]` JSON for the overlay; nil for synced scans without photos.
    var keypointsJSON: Data?
    /// Which segmenter produced the masks ("Apple Vision", "Segment Anything 2.1 small").
    var segmenterName: String?

    var frontPhotoFilename: String?
    var tPosePhotoFilename: String?
    var sidePhotoFilename: String?

    init(id: UUID = UUID(),
         createdAt: Date = .now,
         updatedAt: Date = .now,
         heightCm: Double,
         weightKg: Double,
         sex: BiologicalSex,
         notes: String? = nil,
         isBaseline: Bool = false,
         measurements: BodyMeasurements,
         keypoints: [BodyPoseType: BodyKeypoints] = [:],
         segmenterName: String? = nil,
         frontPhotoFilename: String? = nil,
         tPosePhotoFilename: String? = nil,
         sidePhotoFilename: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.sexRaw = sex.rawValue
        self.notes = notes
        self.isBaseline = isBaseline
        self.measurementsJSON = (try? measurements.encoded()) ?? Data()
        self.keypointsJSON = BodyScan.encodeKeypoints(keypoints)
        self.segmenterName = segmenterName
        self.frontPhotoFilename = frontPhotoFilename
        self.tPosePhotoFilename = tPosePhotoFilename
        self.sidePhotoFilename = sidePhotoFilename
        applyFlattened(measurements)
    }

    // MARK: - Derived

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var measurements: BodyMeasurements? { BodyMeasurements.decode(measurementsJSON) }

    var keypointsByPose: [BodyPoseType: BodyKeypoints] {
        guard let data = keypointsJSON,
              let raw = try? JSONDecoder().decode([String: BodyKeypoints].self, from: data) else { return [:] }
        var out: [BodyPoseType: BodyKeypoints] = [:]
        for (key, value) in raw {
            if let pose = BodyPoseType(rawValue: key) { out[pose] = value }
        }
        return out
    }

    func photoFilename(for pose: BodyPoseType) -> String? {
        switch pose {
        case .frontArmsDown: return frontPhotoFilename
        case .frontArmsOut: return tPosePhotoFilename
        case .sideLeft: return sidePhotoFilename
        }
    }

    var photoFilenames: [String] { [frontPhotoFilename, tPosePhotoFilename, sidePhotoFilename].compactMap { $0 } }

    /// Replaces the measurements (JSON + flattened columns) and bumps `updatedAt`.
    func apply(_ measurements: BodyMeasurements) {
        measurementsJSON = (try? measurements.encoded()) ?? Data()
        applyFlattened(measurements)
        updatedAt = .now
    }

    private func applyFlattened(_ m: BodyMeasurements) {
        waistCm = m.value(.waistCircumference)
        chestCm = m.value(.chestCircumference)
        hipsCm = m.value(.hipsCircumference)
        leftUpperArmCm = m.value(.leftUpperArmCircumference)
        rightUpperArmCm = m.value(.rightUpperArmCircumference)
        leftThighCm = m.value(.leftThighCircumference)
        rightThighCm = m.value(.rightThighCircumference)
        leftCalfCm = m.value(.leftCalfCircumference)
        rightCalfCm = m.value(.rightCalfCircumference)
        shoulderWidthCm = m.value(.shoulderWidth)
        bodyFatPercent = m.value(.bodyFatPercent)
        leanMassKg = m.value(.leanMassKg)
        armSpanCm = m.value(.armSpan)
        leftArmLengthCm = m.value(.leftArm)
        rightArmLengthCm = m.value(.rightArm)
        leftLegLengthCm = m.value(.leftLeg)
        rightLegLengthCm = m.value(.rightLeg)
    }

    static func encodeKeypoints(_ keypoints: [BodyPoseType: BodyKeypoints]) -> Data? {
        guard !keypoints.isEmpty else { return nil }
        var raw: [String: BodyKeypoints] = [:]
        for (pose, kp) in keypoints { raw[pose.rawValue] = kp }
        return try? JSONEncoder().encode(raw)
    }

    /// Flattened value for a chartable metric.
    func flattened(_ metric: BodyMetric) -> Double? {
        switch metric {
        case .waistCircumference: return waistCm
        case .chestCircumference: return chestCm
        case .hipsCircumference: return hipsCm
        case .leftUpperArmCircumference: return leftUpperArmCm
        case .rightUpperArmCircumference: return rightUpperArmCm
        case .leftThighCircumference: return leftThighCm
        case .rightThighCircumference: return rightThighCm
        case .leftCalfCircumference: return leftCalfCm
        case .rightCalfCircumference: return rightCalfCm
        case .shoulderWidth: return shoulderWidthCm
        case .bodyFatPercent: return bodyFatPercent
        case .leanMassKg: return leanMassKg
        case .armSpan: return armSpanCm
        case .leftArm: return leftArmLengthCm
        case .rightArm: return rightArmLengthCm
        case .leftLeg: return leftLegLengthCm
        case .rightLeg: return rightLegLengthCm
        default: return measurements?.value(metric)
        }
    }
}

// MARK: - DTO

/// Sync/export shape of a scan: every scalar column plus the measurements JSON. No photos, no keypoints.
struct BodyScanDTO: Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var heightCm: Double
    var weightKg: Double
    var sexRaw: String
    var notes: String?
    var isBaseline: Bool
    var waistCm: Double?
    var chestCm: Double?
    var hipsCm: Double?
    var leftUpperArmCm: Double?
    var rightUpperArmCm: Double?
    var leftThighCm: Double?
    var rightThighCm: Double?
    var leftCalfCm: Double?
    var rightCalfCm: Double?
    var shoulderWidthCm: Double?
    var bodyFatPercent: Double?
    var leanMassKg: Double?
    var armSpanCm: Double?
    var leftArmLengthCm: Double?
    var rightArmLengthCm: Double?
    var leftLegLengthCm: Double?
    var rightLegLengthCm: Double?
    var measurementsJSON: Data
    var segmenterName: String?
}

extension BodyScan {
    var dto: BodyScanDTO {
        BodyScanDTO(id: id, createdAt: createdAt, updatedAt: updatedAt, heightCm: heightCm, weightKg: weightKg,
                    sexRaw: sexRaw, notes: notes, isBaseline: isBaseline,
                    waistCm: waistCm, chestCm: chestCm, hipsCm: hipsCm,
                    leftUpperArmCm: leftUpperArmCm, rightUpperArmCm: rightUpperArmCm,
                    leftThighCm: leftThighCm, rightThighCm: rightThighCm,
                    leftCalfCm: leftCalfCm, rightCalfCm: rightCalfCm,
                    shoulderWidthCm: shoulderWidthCm, bodyFatPercent: bodyFatPercent, leanMassKg: leanMassKg,
                    armSpanCm: armSpanCm, leftArmLengthCm: leftArmLengthCm, rightArmLengthCm: rightArmLengthCm,
                    leftLegLengthCm: leftLegLengthCm, rightLegLengthCm: rightLegLengthCm,
                    measurementsJSON: measurementsJSON, segmenterName: segmenterName)
    }

    convenience init(dto: BodyScanDTO) {
        self.init(id: dto.id, createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                  heightCm: dto.heightCm, weightKg: dto.weightKg,
                  sex: BiologicalSex(rawValue: dto.sexRaw) ?? .male,
                  notes: dto.notes, isBaseline: dto.isBaseline,
                  measurements: BodyMeasurements.decode(dto.measurementsJSON) ?? BodyMeasurements(),
                  segmenterName: dto.segmenterName)
        update(from: dto)
    }

    /// Copies every DTO field onto this scan (photos and keypoints untouched).
    func update(from dto: BodyScanDTO) {
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        heightCm = dto.heightCm
        weightKg = dto.weightKg
        sexRaw = dto.sexRaw
        notes = dto.notes
        isBaseline = dto.isBaseline
        waistCm = dto.waistCm
        chestCm = dto.chestCm
        hipsCm = dto.hipsCm
        leftUpperArmCm = dto.leftUpperArmCm
        rightUpperArmCm = dto.rightUpperArmCm
        leftThighCm = dto.leftThighCm
        rightThighCm = dto.rightThighCm
        leftCalfCm = dto.leftCalfCm
        rightCalfCm = dto.rightCalfCm
        shoulderWidthCm = dto.shoulderWidthCm
        bodyFatPercent = dto.bodyFatPercent
        leanMassKg = dto.leanMassKg
        armSpanCm = dto.armSpanCm
        leftArmLengthCm = dto.leftArmLengthCm
        rightArmLengthCm = dto.rightArmLengthCm
        leftLegLengthCm = dto.leftLegLengthCm
        rightLegLengthCm = dto.rightLegLengthCm
        measurementsJSON = dto.measurementsJSON
        segmenterName = dto.segmenterName
    }
}
