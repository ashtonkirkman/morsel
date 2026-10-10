import Foundation

/// A food as returned by any lookup (barcode DB, search, AI vision, manual entry).
/// Value type; it becomes a `LogEntry` once the user confirms it.
struct FoodItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    /// Human-readable serving, e.g. "1 cup (240 ml)" or "100 g".
    var servingDescription: String
    /// Weight of one serving in grams, when known. Enables gram-based editing.
    var servingGrams: Double?
    var nutritionPerServing: NutritionFacts
    var source: FoodSource
    var imageURL: URL?

    init(id: UUID = UUID(), name: String, brand: String? = nil, barcode: String? = nil,
         servingDescription: String, servingGrams: Double? = nil,
         nutritionPerServing: NutritionFacts, source: FoodSource, imageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.servingDescription = servingDescription
        self.servingGrams = servingGrams
        self.nutritionPerServing = nutritionPerServing
        self.source = source
        self.imageURL = imageURL
    }

    /// "Brand · Name" or just the name.
    var displayTitle: String {
        if let brand, !brand.isEmpty, brand.lowercased() != name.lowercased() {
            return "\(name) · \(brand)"
        }
        return name
    }
}
