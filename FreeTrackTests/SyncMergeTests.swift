import XCTest
@testable import FreeTrack

final class SyncMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    private func remote(_ id: String = "a", at seconds: Double, deleted: Bool = false) -> SyncDocument {
        SyncDocument(id: id, json: deleted ? nil : "{}", updatedAt: at(seconds), deleted: deleted)
    }

    // MARK: remoteWins

    func testRemoteNewerWins() {
        XCTAssertTrue(SyncMerge.remoteWins(localUpdatedAt: at(10), remote: remote(at: 20)))
    }

    func testLocalNewerKeepsLocal() {
        XCTAssertFalse(SyncMerge.remoteWins(localUpdatedAt: at(30), remote: remote(at: 20)))
    }

    func testTieKeepsLocal() {
        XCTAssertFalse(SyncMerge.remoteWins(localUpdatedAt: at(20), remote: remote(at: 20)))
    }

    func testNewerTombstoneDeletesLocal() {
        XCTAssertTrue(SyncMerge.remoteWins(localUpdatedAt: at(10), remote: remote(at: 20, deleted: true)))
    }

    func testOlderTombstoneIsIgnored() {
        XCTAssertFalse(SyncMerge.remoteWins(localUpdatedAt: at(30), remote: remote(at: 20, deleted: true)))
    }

    func testMissingLocalAcceptsDocumentButNotTombstone() {
        XCTAssertTrue(SyncMerge.remoteWins(localUpdatedAt: nil, remote: remote(at: 20)))
        XCTAssertFalse(SyncMerge.remoteWins(localUpdatedAt: nil, remote: remote(at: 20, deleted: true)))
    }

    // MARK: changes()

    private func state(_ seconds: Double, _ fingerprint: String) -> LocalDocumentState {
        LocalDocumentState(updatedAt: at(seconds), fingerprint: fingerprint)
    }

    func testFirstRunPushesEverything() {
        let current = ["a": state(1, "fa"), "b": state(2, "fb")]
        let change = SyncMerge.changes(current: current, previous: [:], lastPush: nil)
        XCTAssertEqual(change.push, ["a", "b"])
        XCTAssertTrue(change.touched.isEmpty)
        XCTAssertTrue(change.deleted.isEmpty)
    }

    func testOnlyNewerThanLastPushIsPushed() {
        let previous = ["a": state(1, "fa"), "b": state(2, "fb")]
        let current = ["a": state(1, "fa"), "b": state(50, "fb2")]
        let change = SyncMerge.changes(current: current, previous: previous, lastPush: at(10))
        XCTAssertEqual(change.push, ["b"])
        XCTAssertTrue(change.touched.isEmpty)
    }

    func testSilentEditIsTouchedAndPushed() {
        // Content changed but updatedAt did not move: the engine must bump it and push.
        let previous = ["a": state(1, "fa")]
        let current = ["a": state(1, "fa-changed")]
        let change = SyncMerge.changes(current: current, previous: previous, lastPush: at(10))
        XCTAssertEqual(change.touched, ["a"])
        XCTAssertEqual(change.push, ["a"])
    }

    func testNewObjectSinceLastRunIsPushedEvenIfOld() {
        // An object that appeared with an old updatedAt (e.g. imported) is still new to the server.
        let previous = ["a": state(1, "fa")]
        let current = ["a": state(1, "fa"), "c": state(0, "fc")]
        let change = SyncMerge.changes(current: current, previous: previous, lastPush: at(10))
        XCTAssertEqual(change.push, ["c"])
    }

    func testVanishedObjectsBecomeDeletions() {
        let previous = ["a": state(1, "fa"), "b": state(2, "fb")]
        let current = ["a": state(1, "fa")]
        let change = SyncMerge.changes(current: current, previous: previous, lastPush: at(10))
        XCTAssertEqual(change.deleted, ["b"])
        XCTAssertTrue(change.push.isEmpty)
    }

    // MARK: fingerprint + wire format

    func testFingerprintIgnoresUpdatedAt() {
        var a = LogEntryDTO(id: UUID(), loggedAt: t0, mealType: "lunch", name: "Soup", brand: nil, barcode: nil,
                            servingDescription: "1 bowl", servingGrams: nil, quantity: 1, calories: 200, protein: 10,
                            carbs: 20, fat: 5, fiber: nil, sugar: nil, sodium: nil, source: "manual", notes: nil,
                            confidence: nil, updatedAt: at(1))
        var b = a
        b.updatedAt = at(999)
        XCTAssertEqual(SyncMerge.fingerprint(a), SyncMerge.fingerprint(b))
        a.name = "Stew"
        XCTAssertNotEqual(SyncMerge.fingerprint(a), SyncMerge.fingerprint(b))
    }

    func testSyncDocumentRoundTripsThroughWireFormat() throws {
        let doc = SyncDocument(id: "x", json: "{\"k\":1}", updatedAt: at(5))
        let data = try SyncCodec.encoder.encode(doc)
        let back = try SyncCodec.decoder.decode(SyncDocument.self, from: data)
        XCTAssertEqual(back, doc)
        XCTAssertEqual(back.updatedAt, at(5).timeIntervalSince1970 * 1000, accuracy: 0.5)

        // Tombstones drop json and default `deleted` when absent on decode.
        let tomb = try SyncCodec.decoder.decode(SyncDocument.self, from: Data("{\"id\":\"t\",\"updatedAt\":1}".utf8))
        XCTAssertFalse(tomb.deleted)
        let encodedTomb = String(decoding: try SyncCodec.encoder.encode(SyncDocument(id: "t", json: "{}", updatedAt: at(1), deleted: true)), as: UTF8.self)
        XCTAssertFalse(encodedTomb.contains("\"json\""))
        XCTAssertTrue(encodedTomb.contains("\"deleted\":true"))
    }

    func testProfileDocumentDecodesLenientlyWithoutProfile() throws {
        let json = "{\"calorieGoal\":2100,\"proteinGoal\":150,\"carbsGoal\":200,\"fatGoal\":70,\"profile\":{\"unexpected\":true}}"
        let doc = try SyncCodec.decode(ProfileDocument.self, from: json)
        XCTAssertNil(doc.profile)
        XCTAssertEqual(doc.calorieGoal, 2100)
        XCTAssertEqual(doc.unitSystem, UnitSystem.imperial.rawValue)
        XCTAssertEqual(doc.updatedAt, .distantPast)
    }
}
