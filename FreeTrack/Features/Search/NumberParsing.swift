import Foundation

/// Tolerant number parsing for hand-typed nutrition fields. Pure, unit-tested.
enum NumberParsing {
    // MARK: - Parsing

    /// Accepts "1,5", "1.5", " 12 ", "150 kcal", "1.234,5", "1,500".
    /// Returns nil for empty or non-numeric text.
    static func double(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: " ", with: "")

        // Drop a trailing unit such as "g", "kcal", "mg".
        while let last = s.last, last.isLetter {
            s.removeLast()
        }
        guard !s.isEmpty else { return nil }

        s = normalizeSeparators(s)
        guard let value = Double(s), value.isFinite else { return nil }
        return value
    }

    /// Like `double(_:)` but rejects negative values.
    static func nonNegativeDouble(_ text: String) -> Double? {
        guard let value = double(text), value >= 0 else { return nil }
        return value
    }

    /// Optional field: empty text is a valid "not provided"; junk is still nil.
    static func optionalNonNegativeDouble(_ text: String) -> Double? {
        nonNegativeDouble(text)
    }

    // MARK: - Formatting

    /// "2", "1.5", "12.25" — integers without a decimal point, otherwise trailing zeros trimmed.
    static func string(from value: Double, maxFractionDigits: Int = 2) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        var s = String(format: "%.\(max(0, maxFractionDigits))f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: - Private

    /// Turns "1,5" into "1.5", "1.234,5" into "1234.5", "1,500" into "1500", "1,000.5" into "1000.5".
    private static func normalizeSeparators(_ input: String) -> String {
        let hasComma = input.contains(",")
        let hasDot = input.contains(".")

        if hasComma && hasDot {
            guard let lastComma = input.lastIndex(of: ","), let lastDot = input.lastIndex(of: ".") else { return input }
            if lastComma > lastDot {
                // European: "." groups, "," is the decimal mark.
                return input.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
            // US: "," groups, "." is the decimal mark.
            return input.replacingOccurrences(of: ",", with: "")
        }

        if hasComma {
            let parts = input.split(separator: ",", omittingEmptySubsequences: false)
            // A single comma followed by exactly three digits reads as a thousands separator ("1,500"),
            // unless the integer part is just "0" ("0,500" is a decimal).
            if parts.count == 2 {
                let head = parts[0]
                let tail = parts[1]
                let headIsInt = !head.isEmpty && head.allSatisfy { $0.isNumber }
                let tailIsThreeDigits = tail.count == 3 && tail.allSatisfy { $0.isNumber }
                if headIsInt && tailIsThreeDigits && head != "0" {
                    return String(head) + String(tail)
                }
            }
            return input.replacingOccurrences(of: ",", with: ".")
        }

        return input
    }
}
