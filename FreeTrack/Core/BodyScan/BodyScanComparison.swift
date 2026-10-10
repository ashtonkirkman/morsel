import Foundation

/// Baseline vs. current change for one metric. Ported from FreeFit's `comparator.py`.
struct BodyMetricChange: Identifiable, Equatable {
    let metric: BodyMetric
    let baseline: Double
    let current: Double

    var id: String { metric.rawValue }
    var delta: Double { current - baseline }
    /// Percent change relative to the baseline (0 when the baseline is 0).
    var percentChange: Double { baseline != 0 ? delta / baseline * 100 : 0 }
    var direction: Direction { abs(delta) < 1e-9 ? .unchanged : (delta > 0 ? .increased : .decreased) }

    enum Direction: String { case increased, decreased, unchanged }

    /// "Waist decreased by 3.1%"
    var description: String {
        switch direction {
        case .unchanged: return "\(metric.title) unchanged"
        case .increased, .decreased:
            return "\(metric.title) \(direction.rawValue) by \(String(format: "%.1f", abs(percentChange)))%"
        }
    }

    /// Whether the change is in the direction most people want: smaller waist / body fat / asymmetry,
    /// bigger lean mass and limb circumferences. Nil for neutral metrics (lengths, ratios).
    var isImprovement: Bool? {
        guard direction != .unchanged else { return nil }
        switch metric {
        case .waistCircumference, .waistWidth, .waistDepth, .bodyFatPercent, .bodyFatPercentRFM, .bodyFatPercentNavy,
             .fatMassKg, .waistToHipRatio, .waistToHeightRatio,
             .armAsymmetry, .legAsymmetry, .shoulderAsymmetry, .thighAsymmetry:
            return direction == .decreased
        case .leanMassKg, .leftUpperArmCircumference, .rightUpperArmCircumference, .leftForearmCircumference,
             .rightForearmCircumference, .leftThighCircumference, .rightThighCircumference, .leftCalfCircumference,
             .rightCalfCircumference, .chestCircumference, .shoulderToHipRatio:
            return direction == .increased
        default:
            return nil
        }
    }
}

/// All metric deltas between two scans plus the "significant changes" list.
struct BodyScanComparison {
    static let defaultThresholdPercent = 2.0

    let changes: [BodyMetricChange]

    init(baseline: BodyMeasurements, current: BodyMeasurements) {
        changes = BodyMetric.allCases.compactMap { metric in
            guard let b = baseline.value(metric), let c = current.value(metric) else { return nil }
            return BodyMetricChange(metric: metric, baseline: b, current: c)
        }
    }

    init(changes: [BodyMetricChange]) {
        self.changes = changes
    }

    func change(_ metric: BodyMetric) -> BodyMetricChange? { changes.first { $0.metric == metric } }

    func changes(in group: BodyMetricGroup) -> [BodyMetricChange] { changes.filter { $0.metric.group == group } }

    /// Groups whose percent change is compared against the threshold. Lengths are bone and only move with
    /// detection noise; symmetry is already a percentage and is shown as an absolute delta instead.
    static let significantGroups: [BodyMetricGroup] = [.circumferences, .widths, .composition]

    /// Metrics that moved by more than `thresholdPercent`, largest first. FreeFit used 3%; 2% is the default here
    /// because circumference estimates are steadier than normalised lengths.
    func significant(thresholdPercent: Double = BodyScanComparison.defaultThresholdPercent) -> [BodyMetricChange] {
        changes
            .filter { Self.significantGroups.contains($0.metric.group) && abs($0.percentChange) > thresholdPercent }
            .sorted { abs($0.percentChange) > abs($1.percentChange) }
    }

    var bodyFatChange: BodyMetricChange? { change(.bodyFatPercent) }
}
