import Charts
import SwiftUI

struct BodyTrendPoint: Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Line of one metric over scan dates, in the same visual language as `HistoryChart`.
struct BodyTrendChart: View {
    let points: [BodyTrendPoint]
    let metric: BodyMetric
    let unitSystem: UnitSystem

    static let chartMetrics: [BodyMetric] = [.waistCircumference, .bodyFatPercent, .leanMassKg, .chestCircumference,
                                             .hipsCircumference, .leftUpperArmCircumference, .rightUpperArmCircumference,
                                             .leftThighCircumference, .rightThighCircumference, .shoulderWidth]

    private var displayPoints: [BodyTrendPoint] {
        points.map { BodyTrendPoint(date: $0.date, value: displayValue($0.value)) }
    }

    private var unitLabel: String {
        switch metric.unit {
        case .centimetres: return unitSystem == .metric ? "cm" : "in"
        case .kilograms: return unitSystem == .metric ? "kg" : "lb"
        case .percent: return "%"
        case .ratio: return ""
        }
    }

    var body: some View {
        if displayPoints.count < 2 {
            VStack(spacing: Spacing.xs) {
                Image(systemName: "chart.xyaxis.line").font(.title2).foregroundStyle(Color.mTextTertiary)
                Text(displayPoints.isEmpty ? "No \(metric.title.lowercased()) in your scans yet." : "One more scan and the trend starts here.")
                    .font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(displayPoints) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                        .foregroundStyle(Color.mAccent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                        .foregroundStyle(Color.mAccent)
                        .symbolSize(40)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.mSeparator)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Color.mTextSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.mSeparator)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(BodyFormat.number(v, decimals: 1)) \(unitLabel)").foregroundStyle(Color.mTextTertiary)
                        }
                    }
                }
            }
            .accessibilityLabel("\(metric.title) over \(displayPoints.count) scans")
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = displayPoints.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.25, 0.5)
        return (lo - pad)...(hi + pad)
    }

    private func displayValue(_ v: Double) -> Double {
        switch metric.unit {
        case .centimetres: return unitSystem == .metric ? v : v / BodyFormat.cmPerInch
        case .kilograms: return unitSystem == .metric ? v : v / BodyFormat.kgPerPound
        case .percent, .ratio: return v
        }
    }
}
