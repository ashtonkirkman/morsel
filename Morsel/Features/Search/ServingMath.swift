import Foundation

/// Pure quantity ↔ grams math for the serving editor. No UI, unit-tested.
enum ServingMath {
    // MARK: - Limits

    static let minimumQuantity: Double = 0.25
    static let maximumQuantity: Double = 50
    static let step: Double = 0.25
    /// Preset chips shown in the editor: ½ · 1 · 1½ · 2 · 3.
    static let chipQuantities: [Double] = [0.5, 1, 1.5, 2, 3]

    // MARK: - Quantity

    /// Clamps into `minimumQuantity...maximumQuantity`; NaN/inf fall back to the minimum.
    static func clamped(_ quantity: Double) -> Double {
        guard quantity.isFinite else { return minimumQuantity }
        return min(max(quantity, minimumQuantity), maximumQuantity)
    }

    /// True when `quantity` is (within float noise) equal to `preset`.
    static func matches(_ quantity: Double, _ preset: Double) -> Bool {
        abs(quantity - preset) < 0.001
    }

    // MARK: - Grams

    /// Grams for `quantity` servings, or nil when the food has no known serving weight.
    static func grams(forQuantity quantity: Double, servingGrams: Double?) -> Double? {
        guard let servingGrams, servingGrams > 0, quantity.isFinite else { return nil }
        return quantity * servingGrams
    }

    /// Servings for a typed gram amount (clamped), or nil when unknown / not positive.
    static func quantity(forGrams grams: Double, servingGrams: Double?) -> Double? {
        guard let servingGrams, servingGrams > 0, grams.isFinite, grams > 0 else { return nil }
        return clamped(grams / servingGrams)
    }

    // MARK: - Nutrition

    static func nutrition(_ perServing: NutritionFacts, quantity: Double) -> NutritionFacts {
        perServing.scaled(by: quantity)
    }

    // MARK: - Labels

    /// "½", "1", "1½", "2¼", or a trimmed decimal ("1.3") for off-grid values.
    static func label(for quantity: Double) -> String {
        guard quantity.isFinite, quantity > 0 else { return "0" }
        let whole = Int(quantity.rounded(.down))
        let fraction = quantity - Double(whole)
        if fraction < 0.001 || fraction > 0.999 {
            return NumberParsing.string(from: quantity.rounded())
        }
        let glyph: String?
        if abs(fraction - 0.25) < 0.001 {
            glyph = "¼"
        } else if abs(fraction - 0.5) < 0.001 {
            glyph = "½"
        } else if abs(fraction - 0.75) < 0.001 {
            glyph = "¾"
        } else {
            glyph = nil
        }
        if let glyph {
            return whole == 0 ? glyph : "\(whole)\(glyph)"
        }
        return NumberParsing.string(from: quantity, maxFractionDigits: 2)
    }
}
