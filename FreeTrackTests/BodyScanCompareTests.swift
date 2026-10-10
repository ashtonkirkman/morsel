import XCTest
@testable import FreeTrack

final class BodyScanCompareTests: XCTestCase {
    private func measurements(_ values: [BodyMetric: Double]) -> BodyMeasurements {
        var m = BodyMeasurements()
        for (metric, value) in values { m.set(metric, value, .high) }
        return m
    }

    private let baseline: [BodyMetric: Double] = [
        .waistCircumference: 90, .chestCircumference: 100, .leftUpperArmCircumference: 32,
        .bodyFatPercent: 22, .leanMassKg: 60, .leftArm: 58, .armAsymmetry: 1.5, .torsoToLegRatio: 0.72
    ]

    func testPercentChangeAndDirection() {
        let comparison = BodyScanComparison(baseline: measurements(baseline),
                                            current: measurements([.waistCircumference: 87.3, .chestCircumference: 100]))
        let waist = comparison.change(.waistCircumference)!
        XCTAssertEqual(waist.delta, -2.7, accuracy: 1e-9)
        XCTAssertEqual(waist.percentChange, -3.0, accuracy: 1e-9)
        XCTAssertEqual(waist.direction, .decreased)
        XCTAssertEqual(waist.description, "Waist decreased by 3.0%")
        XCTAssertEqual(waist.isImprovement, true)
        let chest = comparison.change(.chestCircumference)!
        XCTAssertEqual(chest.direction, .unchanged)
        XCTAssertNil(chest.isImprovement)
        XCTAssertEqual(chest.description, "Chest unchanged")
        // Metrics missing on either side are skipped.
        XCTAssertNil(comparison.change(.bodyFatPercent))
        XCTAssertEqual(comparison.changes.count, 2)
    }

    func testSignificantChangesSortedAndThresholded() {
        var current = baseline
        current[.waistCircumference] = 85.5          // −5%
        current[.chestCircumference] = 102.5         // +2.5%
        current[.leftUpperArmCircumference] = 32.3   // +0.94%
        current[.bodyFatPercent] = 20                // −9.09%
        current[.leanMassKg] = 60.5                  // +0.83%
        current[.leftArm] = 62                       // +6.9% but lengths are excluded
        current[.armAsymmetry] = 4                   // symmetry excluded
        current[.torsoToLegRatio] = 0.80             // composition group, +11.1%
        let comparison = BodyScanComparison(baseline: measurements(baseline), current: measurements(current))

        let twoPercent = comparison.significant()
        XCTAssertEqual(twoPercent.map(\.metric), [.torsoToLegRatio, .bodyFatPercent, .waistCircumference, .chestCircumference])
        XCTAssertEqual(twoPercent.first?.percentChange ?? 0, 11.11, accuracy: 0.01)

        let threePercent = comparison.significant(thresholdPercent: 3)
        XCTAssertEqual(threePercent.map(\.metric), [.torsoToLegRatio, .bodyFatPercent, .waistCircumference])

        let onePercent = comparison.significant(thresholdPercent: 1)
        XCTAssertFalse(onePercent.contains { $0.metric == .leftUpperArmCircumference })
        XCTAssertFalse(onePercent.contains { $0.metric == .leftArm })
        XCTAssertFalse(onePercent.contains { $0.metric == .armAsymmetry })
    }

    func testBodyFatChangeAndImprovementSemantics() {
        let comparison = BodyScanComparison(baseline: measurements(baseline),
                                            current: measurements([.bodyFatPercent: 20, .leanMassKg: 61, .armAsymmetry: 0.5, .leftArm: 58.5]))
        let bf = comparison.bodyFatChange!
        XCTAssertEqual(bf.delta, -2, accuracy: 1e-9)
        XCTAssertEqual(bf.isImprovement, true)
        XCTAssertEqual(comparison.change(.leanMassKg)?.isImprovement, true)
        XCTAssertEqual(comparison.change(.armAsymmetry)?.isImprovement, true)
        XCTAssertNil(comparison.change(.leftArm)?.isImprovement)
        let worse = BodyScanComparison(baseline: measurements(baseline), current: measurements([.leanMassKg: 58, .waistCircumference: 95]))
        XCTAssertEqual(worse.change(.leanMassKg)?.isImprovement, false)
        XCTAssertEqual(worse.change(.waistCircumference)?.isImprovement, false)
    }

    func testZeroBaselineGivesZeroPercent() {
        let change = BodyMetricChange(metric: .waistCircumference, baseline: 0, current: 5)
        XCTAssertEqual(change.percentChange, 0)
        XCTAssertEqual(change.direction, .increased)
    }

    func testGroupFilter() {
        let comparison = BodyScanComparison(baseline: measurements(baseline), current: measurements(baseline))
        XCTAssertEqual(comparison.changes(in: .circumferences).map(\.metric), [.leftUpperArmCircumference, .chestCircumference, .waistCircumference])
        XCTAssertEqual(comparison.changes(in: .lengths).map(\.metric), [.leftArm])
        XCTAssertTrue(comparison.significant().isEmpty)
    }

    // MARK: - Formatting used by the comparison UI

    func testBodyFormat() {
        XCTAssertEqual(BodyFormat.length(81.59, .metric), "81.6 cm")
        XCTAssertEqual(BodyFormat.length(81.59, .imperial), "32.1 in")
        XCTAssertEqual(BodyFormat.lengthDelta(-2.7, .metric), "−2.7 cm")
        XCTAssertEqual(BodyFormat.lengthDelta(2.54, .imperial), "+1 in")
        XCTAssertEqual(BodyFormat.weight(65.1, .metric), "65.1 kg")
        XCTAssertEqual(BodyFormat.weight(65.1, .imperial), "143.5 lb")
        XCTAssertEqual(BodyFormat.percent(18.62), "18.6%")
        XCTAssertEqual(BodyFormat.percentDelta(-2), "−2 pts")
        XCTAssertEqual(BodyFormat.percentChange(-3), "−3%")
        XCTAssertEqual(BodyFormat.ratio(0.9222), "0.92")
        XCTAssertEqual(BodyFormat.height(180, .metric), "180 cm")
        XCTAssertEqual(BodyFormat.height(180.34, .imperial), "5 ft 11 in")
        XCTAssertEqual(BodyFormat.signed(0.001, decimals: 1), "0")
        XCTAssertEqual(BodyFormat.value(.leanMassKg, 65.1, .metric), "65.1 kg")
        XCTAssertEqual(BodyFormat.delta(.bodyFatPercent, 1.5, .metric), "+1.5 pts")
    }
}
