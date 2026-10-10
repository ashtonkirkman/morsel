import SwiftUI

/// Baseline vs. current: body fat headline, significant changes (> 2%), then every metric by group.
@MainActor
struct BodyScanCompareView: View {
    let baseline: BodyScan
    let current: BodyScan

    @Environment(AppSettings.self) private var settings
    @State private var threshold = BodyScanComparison.defaultThresholdPercent

    private var comparison: BodyScanComparison {
        BodyScanComparison(baseline: baseline.measurements ?? BodyMeasurements(),
                           current: current.measurements ?? BodyMeasurements())
    }

    private var unit: UnitSystem { settings.unitSystem }

    var body: some View {
        let comparison = self.comparison
        ScrollView {
            VStack(spacing: Spacing.m) {
                datesCard
                if let bf = comparison.bodyFatChange { bodyFatCard(bf) }
                significantCard(comparison)
                ForEach([BodyMetricGroup.circumferences, .composition, .symmetry, .lengths, .widths], id: \.self) { group in
                    let changes = comparison.changes(in: group)
                    if !changes.isEmpty { groupCard(group, changes: changes) }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.mBackground.ignoresSafeArea())
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var datesCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Baseline").font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                    Text(baseline.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                    Text(BodyFormat.weight(baseline.weightKg, unit)).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(Color.mTextTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Current").font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                    Text(current.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                    Text(BodyFormat.weight(current.weightKg, unit)).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                }
            }
        }
    }

    private func bodyFatCard(_ change: BodyMetricChange) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Body fat (estimated)").font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(BodyFormat.percent(change.current)).font(FreeTrackFont.display).foregroundStyle(Color.mText)
                        Text("from \(BodyFormat.percent(change.baseline))").font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                    }
                }
                Spacer()
                ChangeBadge(text: BodyFormat.percentDelta(change.delta), isImprovement: change.isImprovement, isNeutral: change.direction == .unchanged)
            }
        }
    }

    private func significantCard(_ comparison: BodyScanComparison) -> some View {
        let items = comparison.significant(thresholdPercent: threshold)
        return Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("Significant changes").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                    Spacer()
                    Picker("Threshold", selection: $threshold) {
                        Text("1%").tag(1.0)
                        Text("2%").tag(2.0)
                        Text("3%").tag(3.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 150)
                    .accessibilityLabel("Significance threshold")
                }
                if items.isEmpty {
                    Text("Nothing moved more than \(BodyFormat.number(threshold, decimals: 0))% between these scans.")
                        .font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                } else {
                    ForEach(items) { change in
                        HStack(spacing: Spacing.s) {
                            Image(systemName: change.direction == .increased ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(color(for: change))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.metric.title).font(FreeTrackFont.body).foregroundStyle(Color.mText)
                                Text(change.description).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                            }
                            Spacer()
                            ChangeBadge(text: BodyFormat.percentChange(change.percentChange), isImprovement: change.isImprovement, isNeutral: false)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func groupCard(_ group: BodyMetricGroup, changes: [BodyMetricChange]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(group.title).font(FreeTrackFont.headline).foregroundStyle(Color.mText).padding(.bottom, Spacing.xs)
                ForEach(changes) { change in
                    HStack(spacing: Spacing.s) {
                        Text(change.metric.title).font(FreeTrackFont.body).foregroundStyle(Color.mText)
                        Spacer()
                        Text("\(BodyFormat.value(change.metric, change.baseline, unit)) → \(BodyFormat.value(change.metric, change.current, unit))")
                            .font(FreeTrackFont.caption.monospacedDigit())
                            .foregroundStyle(Color.mTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(BodyFormat.delta(change.metric, change.delta, unit))
                            .font(FreeTrackFont.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(change.direction == .unchanged ? Color.mTextTertiary : color(for: change))
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func color(for change: BodyMetricChange) -> Color {
        switch change.isImprovement {
        case .some(true): return .mAccent
        case .some(false): return .mWarning
        case .none: return .mTextSecondary
        }
    }
}

/// Small pill showing a signed change, green when it is an improvement, amber otherwise, grey when neutral.
struct ChangeBadge: View {
    let text: String
    let isImprovement: Bool?
    let isNeutral: Bool

    private var color: Color {
        if isNeutral { return .mTextSecondary }
        switch isImprovement {
        case .some(true): return .mAccent
        case .some(false): return .mWarning
        case .none: return .mTextSecondary
        }
    }

    var body: some View {
        Text(text)
            .font(FreeTrackFont.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
