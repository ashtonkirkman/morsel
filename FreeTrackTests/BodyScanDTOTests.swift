import XCTest
import SwiftData
@testable import FreeTrack

@MainActor
final class BodyScanDTOTests: XCTestCase {
    private func sampleMeasurements() -> BodyMeasurements {
        var m = BodyMeasurements()
        m.poses = [.frontArmsDown, .sideLeft]
        m.heightCm = 180
        m.weightKg = 80
        m.sexRaw = BiologicalSex.male.rawValue
        m.frontPxPerCm = 10
        m.scaleSource = "mask"
        m.set(.waistCircumference, 79.3, .high, source: .frontArmsDown)
        m.set(.chestCircumference, 119.9, .medium, source: .frontArmsOut)
        m.set(.hipsCircumference, 128.5, .high, source: .frontArmsOut)
        m.set(.leftUpperArmCircumference, 29.9, .high)
        m.set(.rightUpperArmCircumference, 30.1, .high)
        m.set(.leftThighCircumference, 56.5, .high)
        m.set(.rightThighCircumference, 56.6, .high)
        m.set(.leftCalfCircumference, 37.7, .medium)
        m.set(.rightCalfCircumference, 37.6, .medium)
        m.set(.shoulderWidth, 50, .high)
        m.set(.bodyFatPercent, 18.6, .medium)
        m.set(.leanMassKg, 65.1, .medium)
        m.set(.armSpan, 166, .high)
        m.set(.leftArm, 58, .high)
        m.set(.rightArm, 58, .high)
        m.set(.leftLeg, 85, .high)
        m.set(.rightLeg, 85, .high)
        m.set(.torso, 61.2, .high)
        return m
    }

    private func sampleKeypoints() -> BodyKeypoints {
        BodyKeypoints(imageWidth: 1000, imageHeight: 1500, joints: [
            BodyKeypoint(joint: .nose, x: 500, y: 100, confidence: 0.9),
            BodyKeypoint(joint: .leftAnkle, x: 540, y: 1400, confidence: 0.8)
        ])
    }

    func testFlattenedColumnsMirrorMeasurements() {
        let scan = BodyScan(heightCm: 180, weightKg: 80, sex: .male, notes: "fasted", measurements: sampleMeasurements())
        XCTAssertEqual(scan.waistCm, 79.3)
        XCTAssertEqual(scan.chestCm, 119.9)
        XCTAssertEqual(scan.hipsCm, 128.5)
        XCTAssertEqual(scan.leftUpperArmCm, 29.9)
        XCTAssertEqual(scan.rightThighCm, 56.6)
        XCTAssertEqual(scan.leftCalfCm, 37.7)
        XCTAssertEqual(scan.shoulderWidthCm, 50)
        XCTAssertEqual(scan.bodyFatPercent, 18.6)
        XCTAssertEqual(scan.leanMassKg, 65.1)
        XCTAssertEqual(scan.armSpanCm, 166)
        XCTAssertEqual(scan.leftLegLengthCm, 85)
        XCTAssertEqual(scan.flattened(.torso), 61.2)
        XCTAssertEqual(scan.measurements, sampleMeasurements())
        XCTAssertEqual(scan.sex, .male)
    }

    func testDTORoundTripPreservesEveryScalarAndMeasurements() throws {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_700_000_500)
        let scan = BodyScan(id: id, createdAt: created, updatedAt: updated, heightCm: 180, weightKg: 80, sex: .female,
                            notes: "evening", isBaseline: true, measurements: sampleMeasurements(),
                            keypoints: [.frontArmsDown: sampleKeypoints()], segmenterName: "Apple Vision",
                            frontPhotoFilename: "bodyscan-front.jpg")
        let dto = scan.dto
        XCTAssertEqual(dto.id, id)
        XCTAssertEqual(dto.createdAt, created)
        XCTAssertEqual(dto.updatedAt, updated)
        XCTAssertEqual(dto.sexRaw, "female")
        XCTAssertTrue(dto.isBaseline)
        XCTAssertEqual(dto.waistCm, 79.3)
        XCTAssertEqual(dto.measurementsJSON, scan.measurementsJSON)

        // JSON round trip of the DTO itself (what the sync layer ships).
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(BodyScanDTO.self, from: data)
        XCTAssertEqual(decoded, dto)

        // Back into a model: photos and keypoints are intentionally not part of the DTO.
        let restored = BodyScan(dto: decoded)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.createdAt, created)
        XCTAssertEqual(restored.updatedAt, updated)
        XCTAssertEqual(restored.heightCm, 180)
        XCTAssertEqual(restored.weightKg, 80)
        XCTAssertEqual(restored.sex, .female)
        XCTAssertEqual(restored.notes, "evening")
        XCTAssertTrue(restored.isBaseline)
        XCTAssertEqual(restored.waistCm, 79.3)
        XCTAssertEqual(restored.rightCalfCm, 37.6)
        XCTAssertEqual(restored.leftArmLengthCm, 58)
        XCTAssertEqual(restored.measurements, sampleMeasurements())
        XCTAssertEqual(restored.segmenterName, "Apple Vision")
        XCTAssertNil(restored.frontPhotoFilename)
        XCTAssertTrue(restored.keypointsByPose.isEmpty)
        XCTAssertEqual(restored.dto, dto)
    }

    func testUpdateFromDTOKeepsPhotosAndKeypoints() {
        let scan = BodyScan(heightCm: 170, weightKg: 70, sex: .male, measurements: BodyMeasurements(),
                            keypoints: [.sideLeft: sampleKeypoints()], frontPhotoFilename: "bodyscan-a.jpg")
        var dto = scan.dto
        dto.weightKg = 68.5
        dto.notes = "synced"
        dto.measurementsJSON = (try? sampleMeasurements().encoded()) ?? Data()
        dto.waistCm = 79.3
        scan.update(from: dto)
        XCTAssertEqual(scan.weightKg, 68.5)
        XCTAssertEqual(scan.notes, "synced")
        XCTAssertEqual(scan.waistCm, 79.3)
        XCTAssertEqual(scan.measurements?.value(.waistCircumference), 79.3)
        XCTAssertEqual(scan.frontPhotoFilename, "bodyscan-a.jpg")
        XCTAssertEqual(scan.keypointsByPose[.sideLeft], sampleKeypoints())
    }

    func testKeypointsJSONRoundTrip() throws {
        let scan = BodyScan(heightCm: 170, weightKg: 70, sex: .male, measurements: BodyMeasurements(),
                            keypoints: [.frontArmsDown: sampleKeypoints(), .sideLeft: sampleKeypoints()])
        let back = scan.keypointsByPose
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[.frontArmsDown], sampleKeypoints())
        let scaled = try XCTUnwrap(back[.sideLeft]).scaled(toWidth: 500, height: 750)
        XCTAssertEqual(scaled[.nose]?.x ?? 0, 250, accuracy: 1e-9)
        XCTAssertEqual(scaled[.leftAnkle]?.y ?? 0, 700, accuracy: 1e-9)
    }

    func testQueriesBaselineAndDelete() throws {
        let container = try ModelContainer.freeTrack(inMemory: true)
        let context = container.mainContext
        let first = BodyScan(createdAt: Date(timeIntervalSince1970: 1_000), heightCm: 180, weightKg: 80, sex: .male, measurements: sampleMeasurements())
        let second = BodyScan(createdAt: Date(timeIntervalSince1970: 2_000), heightCm: 180, weightKg: 79, sex: .male, measurements: sampleMeasurements())
        try context.saveBodyScan(first)
        try context.saveBodyScan(second)

        // The first scan becomes the baseline automatically; the list is newest first.
        XCTAssertTrue(first.isBaseline)
        XCTAssertFalse(second.isBaseline)
        XCTAssertEqual(try context.bodyScans().map(\.id), [second.id, first.id])
        XCTAssertEqual(try context.bodyScansChronological().map(\.id), [first.id, second.id])
        XCTAssertEqual(try context.latestBodyScan()?.id, second.id)
        XCTAssertEqual(try context.baselineBodyScan()?.id, first.id)
        XCTAssertEqual(try context.bodyScan(id: second.id)?.id, second.id)

        try context.setBaselineBodyScan(second)
        XCTAssertFalse(first.isBaseline)
        XCTAssertTrue(second.isBaseline)

        try context.deleteBodyScan(second)
        XCTAssertEqual(try context.bodyScans().count, 1)
        XCTAssertTrue(first.isBaseline, "deleting the baseline promotes the oldest remaining scan")
    }
}
