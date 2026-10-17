import XCTest
import SwiftData
import UIKit
@testable import FreeTrack

@MainActor
final class ProgressPhotoTests: XCTestCase {
    // MARK: - EXIF dates

    func testParsesExifDateTime() throws {
        let date = try XCTUnwrap(ProgressPhotoImporter.parseExifDate("2021:06:14 09:30:12"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(parts.year, 2021)
        XCTAssertEqual(parts.month, 6)
        XCTAssertEqual(parts.day, 14)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 30)
        XCTAssertEqual(parts.second, 12)
    }

    func testParsesDateOnlyAndRejectsUnsetExifDates() throws {
        let date = try XCTUnwrap(ProgressPhotoImporter.parseExifDate("2019:12:01"))
        XCTAssertEqual(Calendar.current.component(.year, from: date), 2019)
        XCTAssertNil(ProgressPhotoImporter.parseExifDate("0000:00:00 00:00:00"))
        XCTAssertNil(ProgressPhotoImporter.parseExifDate("    :  :     :  :  "))
        XCTAssertNil(ProgressPhotoImporter.parseExifDate(""))
        XCTAssertNil(ProgressPhotoImporter.parseExifDate("yesterday"))
    }

    func testCaptureDateIsNilForImageDataWithoutMetadata() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let png = renderer.pngData { ctx in ctx.cgContext.setFillColor(UIColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        XCTAssertNil(ProgressPhotoImporter.captureDate(in: png))
        XCTAssertNotNil(ProgressPhotoImporter.load(png)?.image)
        XCTAssertNil(ProgressPhotoImporter.load(Data([0, 1, 2])))
    }

    // MARK: - Timeline

    func testTimelineMergesImportedAndScanPhotosOldestFirst() {
        let old = ProgressPhoto(takenAt: Date(timeIntervalSince1970: 1_000), filename: "a.jpg", angle: .side, weightKg: 90)
        let recent = ProgressPhoto(takenAt: Date(timeIntervalSince1970: 3_000), filename: "b.jpg")
        let scanWithPhoto = BodyScan(createdAt: Date(timeIntervalSince1970: 2_000), heightCm: 180, weightKg: 82, sex: .male,
                                     measurements: BodyMeasurements(), sidePhotoFilename: "bodyscan-s.jpg")
        let scanWithout = BodyScan(createdAt: Date(timeIntervalSince1970: 2_500), heightCm: 180, weightKg: 81, sex: .male,
                                   measurements: BodyMeasurements())
        let items = ProgressTimelineItem.timeline(photos: [recent, old], scans: [scanWithout, scanWithPhoto])
        XCTAssertEqual(items.map(\.filename), ["a.jpg", "bodyscan-s.jpg", "b.jpg"])
        XCTAssertEqual(items[0].angle, .side)
        XCTAssertEqual(items[0].weightKg, 90)
        XCTAssertEqual(items[0].importedID, old.id)
        XCTAssertTrue(items[1].isFromScan)
        XCTAssertEqual(items[1].angle, .side, "a scan with only a side photo is tagged as a side view")
        XCTAssertEqual(items[1].weightKg, 82)
        XCTAssertNil(items[1].importedID)
        XCTAssertFalse(items[2].isFromScan)
    }

    func testScanTimelineItemPrefersFrontPhoto() throws {
        let scan = BodyScan(heightCm: 180, weightKg: 82, sex: .male, measurements: BodyMeasurements(),
                            frontPhotoFilename: "f.jpg", tPosePhotoFilename: "t.jpg", sidePhotoFilename: "s.jpg")
        let item = try XCTUnwrap(ProgressTimelineItem(scan: scan))
        XCTAssertEqual(item.filename, "f.jpg")
        XCTAssertEqual(item.angle, .front)
    }

    // MARK: - Persistence

    func testProgressPhotoQueriesAndDelete() throws {
        let container = try ModelContainer.freeTrack(inMemory: true)
        let context = container.mainContext
        let later = ProgressPhoto(takenAt: Date(timeIntervalSince1970: 5_000), filename: "later.jpg", angle: .back, note: "beach")
        let earlier = ProgressPhoto(takenAt: Date(timeIntervalSince1970: 1_000), filename: "earlier.jpg")
        try context.saveProgressPhotos([later, earlier])

        XCTAssertEqual(try context.progressPhotos().map(\.filename), ["earlier.jpg", "later.jpg"])
        let found = try XCTUnwrap(try context.progressPhoto(id: later.id))
        XCTAssertEqual(found.angle, .back)
        XCTAssertEqual(found.note, "beach")
        XCTAssertNil(found.weightKg)

        found.angle = .front
        XCTAssertEqual(found.angleRaw, "front")

        try context.deleteProgressPhoto(earlier)
        XCTAssertEqual(try context.progressPhotos().map(\.filename), ["later.jpg"])
        XCTAssertNil(try context.progressPhoto(id: earlier.id))
    }

    func testReferenceShoulderWidthComesFromLatestFullBodyScan() throws {
        let container = try ModelContainer.freeTrack(inMemory: true)
        let context = container.mainContext
        XCTAssertNil(try context.referenceShoulderWidthCm())

        var full = BodyMeasurements()
        full.scaleSource = "mask"
        full.set(.shoulderWidth, 48, .high)
        var partial = BodyMeasurements()
        partial.scaleSource = "referenceShoulders"
        partial.set(.shoulderWidth, 47, .medium)
        try context.saveBodyScan(BodyScan(createdAt: Date(timeIntervalSince1970: 1_000), heightCm: 180, weightKg: 80, sex: .male, measurements: full))
        try context.saveBodyScan(BodyScan(createdAt: Date(timeIntervalSince1970: 2_000), heightCm: 180, weightKg: 79, sex: .male, measurements: partial))

        XCTAssertEqual(try context.referenceShoulderWidthCm(), 48, "a partial scan's own estimate is never used as a reference")
    }
}
