import Foundation

/// Display formatting for body measurements. Values are metric internally; `UnitSystem` picks cm/in and kg/lb.
enum BodyFormat {
    static let cmPerInch = 2.54
    static let kgPerPound = 0.45359237

    // MARK: - Lengths

    static func length(_ cm: Double, _ unit: UnitSystem, decimals: Int = 1) -> String {
        switch unit {
        case .metric: return "\(number(cm, decimals: decimals)) cm"
        case .imperial: return "\(number(cm / cmPerInch, decimals: decimals)) in"
        }
    }

    static func lengthDelta(_ deltaCm: Double, _ unit: UnitSystem, decimals: Int = 1) -> String {
        let value = unit == .metric ? deltaCm : deltaCm / cmPerInch
        return "\(signed(value, decimals: decimals)) \(unit == .metric ? "cm" : "in")"
    }

    /// "180 cm" or "5 ft 11 in".
    static func height(_ cm: Double, _ unit: UnitSystem) -> String {
        switch unit {
        case .metric: return "\(Int(cm.rounded())) cm"
        case .imperial:
            let fi = Units.feetInches(fromCm: cm)
            return "\(fi.feet) ft \(fi.inches) in"
        }
    }

    // MARK: - Weight

    static func weight(_ kg: Double, _ unit: UnitSystem, decimals: Int = 1) -> String {
        switch unit {
        case .metric: return "\(number(kg, decimals: decimals)) kg"
        case .imperial: return "\(number(kg / kgPerPound, decimals: decimals)) lb"
        }
    }

    static func weightDelta(_ deltaKg: Double, _ unit: UnitSystem, decimals: Int = 1) -> String {
        let value = unit == .metric ? deltaKg : deltaKg / kgPerPound
        return "\(signed(value, decimals: decimals)) \(unit == .metric ? "kg" : "lb")"
    }

    // MARK: - Other units

    static func percent(_ value: Double, decimals: Int = 1) -> String { "\(number(value, decimals: decimals))%" }

    static func percentDelta(_ delta: Double, decimals: Int = 1) -> String { "\(signed(delta, decimals: decimals)) pts" }

    static func ratio(_ value: Double) -> String { number(value, decimals: 2) }

    /// Any metric in its own unit.
    static func value(_ metric: BodyMetric, _ value: Double, _ unit: UnitSystem) -> String {
        switch metric.unit {
        case .centimetres: return length(value, unit)
        case .kilograms: return weight(value, unit)
        case .percent: return percent(value)
        case .ratio: return ratio(value)
        }
    }

    /// Signed change for a metric: cm/in, kg/lb, percentage points or a plain ratio delta.
    static func delta(_ metric: BodyMetric, _ delta: Double, _ unit: UnitSystem) -> String {
        switch metric.unit {
        case .centimetres: return lengthDelta(delta, unit)
        case .kilograms: return weightDelta(delta, unit)
        case .percent: return percentDelta(delta)
        case .ratio: return signed(delta, decimals: 2)
        }
    }

    static func percentChange(_ pct: Double) -> String { "\(signed(pct, decimals: 1))%" }

    // MARK: - Helpers

    static func number(_ value: Double, decimals: Int) -> String {
        let rounded = (value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        if decimals == 0 || rounded == rounded.rounded() { return "\(Int(rounded.rounded()))" }
        return String(format: "%.\(decimals)f", rounded)
    }

    static func signed(_ value: Double, decimals: Int) -> String {
        let magnitude = number(abs(value), decimals: decimals)
        if magnitude == "0" { return "0" }
        return value < 0 ? "−\(magnitude)" : "+\(magnitude)"
    }

    static func scanDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}
