import Foundation

// MARK: - Open Food Facts JSON → FoodItem
// Pure, network-free mapping so it can be unit-tested with fixture strings.
// OFF JSON is loose: numbers arrive as numbers *or* strings, keys are optional,
// energy may be kJ-only. Every decoder here is lenient on purpose.

enum OpenFoodFactsMapper {

    /// kJ → kcal.
    static let kilojoulesPerKilocalorie: Double = 4.184

    // MARK: Response-level mapping

    /// Maps a `/api/v2/product/<code>.json` body. Returns nil when the product is unknown
    /// (`status == 0`, no `product` object, or a product with no name/energy data).
    static func mapLookupResponse(data: Data, barcode: String) throws -> FoodItem? {
        let response: OFFLookupResponse
        do {
            response = try JSONDecoder().decode(OFFLookupResponse.self, from: data)
        } catch {
            throw ServiceError.decoding("Open Food Facts product: \(error.localizedDescription)")
        }
        if let status = response.status?.value, status == 0 { return nil }
        guard let product = response.product else { return nil }
        let fallback = response.code?.value ?? barcode
        return mapProduct(product, source: .barcode, fallbackBarcode: fallback)
    }

    /// Maps a `/cgi/search.pl?json=1` body, dropping products without a name or energy data.
    static func mapSearchResponse(data: Data) throws -> [FoodItem] {
        let response: OFFSearchResponse
        do {
            response = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        } catch {
            throw ServiceError.decoding("Open Food Facts search: \(error.localizedDescription)")
        }
        return response.products.elements.compactMap { mapProduct($0, source: .search, fallbackBarcode: nil) }
    }

    // MARK: Product-level mapping

    /// Builds a `FoodItem` from one OFF product. Nil when the product has no usable name or no
    /// energy value (per serving or per 100 g).
    static func mapProduct(_ product: OFFProduct, source: FoodSource, fallbackBarcode: String?) -> FoodItem? {
        guard let name = cleaned(product.productName) else { return nil }
        let nutriments = product.nutriments ?? OFFNutriments(values: [:])
        let servingQuantity = product.servingQuantity?.value ?? 0

        let serving: (facts: NutritionFacts, description: String, grams: Double)
        if servingQuantity > 0,
           let servingFacts = facts(from: nutriments, suffix: "_serving", fallbackScale: servingQuantity / 100) {
            let description = cleaned(product.servingSize) ?? "\(formatGrams(servingQuantity)) g"
            serving = (servingFacts, description, servingQuantity)
        } else if let per100Facts = facts(from: nutriments, suffix: "_100g", fallbackScale: nil) {
            serving = (per100Facts, "100 g", 100)
        } else {
            return nil
        }

        let barcode = cleaned(product.code?.value) ?? cleaned(fallbackBarcode)
        return FoodItem(name: name,
                        brand: primaryBrand(product.brands),
                        barcode: barcode,
                        servingDescription: serving.description,
                        servingGrams: serving.grams,
                        nutritionPerServing: serving.facts,
                        source: source,
                        imageURL: cleaned(product.imageFrontSmallUrl).flatMap { URL(string: $0) })
    }

    // MARK: Nutriment extraction

    /// Reads one nutrient set (`_serving` or `_100g`). When `fallbackScale` is given, a missing
    /// per-serving value is derived from the `_100g` value scaled by `servingGrams / 100`.
    /// Returns nil when no energy value can be found at all.
    static func facts(from nutriments: OFFNutriments, suffix: String, fallbackScale: Double?) -> NutritionFacts? {
        func value(_ base: String) -> Double? {
            if let direct = nutriments[base + suffix] { return direct }
            if let scale = fallbackScale, let per100 = nutriments[base + "_100g"] { return per100 * scale }
            return nil
        }

        let kcal: Double?
        if let direct = value("energy-kcal") {
            kcal = direct
        } else if let kj = value("energy-kj") ?? value("energy") {
            kcal = kj / kilojoulesPerKilocalorie
        } else {
            kcal = nil
        }
        guard let calories = kcal else { return nil }

        let sodiumMg: Double?
        if let sodiumGrams = value("sodium") {
            sodiumMg = sodiumGrams * 1000
        } else if let saltGrams = value("salt") {
            sodiumMg = saltGrams * 400
        } else {
            sodiumMg = nil
        }

        return NutritionFacts(calories: max(0, calories),
                              protein: max(0, value("proteins") ?? 0),
                              carbs: max(0, value("carbohydrates") ?? 0),
                              fat: max(0, value("fat") ?? 0),
                              fiber: value("fiber").map { max(0, $0) },
                              sugar: value("sugars").map { max(0, $0) },
                              sodium: sodiumMg.map { max(0, $0) })
    }

    // MARK: Small helpers

    /// Trimmed, non-empty string or nil.
    static func cleaned(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// OFF `brands` is comma-separated; take the first one.
    static func primaryBrand(_ brands: String?) -> String? {
        guard let brands else { return nil }
        return brands.split(separator: ",").map { String($0) }.compactMap { cleaned($0) }.first
    }

    /// Lenient number parsing for string-typed OFF values ("1.5", "1,5", "30 g").
    static func parseNumber(_ string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if let direct = Double(trimmed) { return direct }
        var prefix = ""
        for character in trimmed {
            if character.isASCII, character.isNumber || character == "." || (character == "-" && prefix.isEmpty) {
                prefix.append(character)
            } else {
                break
            }
        }
        return Double(prefix)
    }

    private static func formatGrams(_ grams: Double) -> String {
        grams == grams.rounded() ? "\(Int(grams))" : String(format: "%.1f", grams)
    }
}

// MARK: - Lenient scalar decoders

/// A number that may be encoded as a JSON number, a numeric string, or anything else (→ nil).
/// Never fails, so it is safe as a dictionary value type.
struct LenientDouble: Decodable, Equatable {
    let value: Double?

    init(_ value: Double?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let string = try? container.decode(String.self) {
            value = OpenFoodFactsMapper.parseNumber(string)
        } else {
            value = nil
        }
    }
}

/// A string that may be encoded as a JSON string or a number (OFF codes are usually strings).
struct LenientString: Decodable, Equatable {
    let value: String?

    init(_ value: String?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int.self) {
            value = String(integer)
        } else if let number = try? container.decode(Double.self) {
            value = String(number)
        } else {
            value = nil
        }
    }
}

/// Decodes an array while skipping elements that fail to decode, so one odd product
/// cannot sink a whole search page.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(_ elements: [Element]) { self.elements = elements }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            let index = container.currentIndex
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                // Advance past the bad element without inspecting it.
                _ = try? container.decode(DiscardedValue.self)
            }
            // Defensive: never spin if the container did not move on.
            if container.currentIndex == index { break }
        }
        elements = result
    }

    /// Consumes any JSON value without reading it. The init never throws so the
    /// unkeyed container always advances.
    private struct DiscardedValue: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

// MARK: - Decodable shapes (only the fields we request)

struct OFFLookupResponse: Decodable {
    var code: LenientString?
    var status: LenientDouble?
    var product: OFFProduct?
}

struct OFFSearchResponse: Decodable {
    var count: LenientDouble?
    var products: LossyArray<OFFProduct>

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(LenientDouble.self, forKey: .count)
        products = try container.decodeIfPresent(LossyArray<OFFProduct>.self, forKey: .products) ?? LossyArray([])
    }

    enum CodingKeys: String, CodingKey {
        case count, products
    }
}

struct OFFProduct: Decodable {
    var code: LenientString?
    var productName: String?
    var brands: String?
    var servingSize: String?
    var servingQuantity: LenientDouble?
    var nutriments: OFFNutriments?
    var imageFrontSmallUrl: String?
    var quantity: String?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments, quantity
        case productName = "product_name"
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case imageFrontSmallUrl = "image_front_small_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(LenientString.self, forKey: .code)
        productName = try? container.decodeIfPresent(String.self, forKey: .productName)
        brands = try? container.decodeIfPresent(String.self, forKey: .brands)
        servingSize = try? container.decodeIfPresent(String.self, forKey: .servingSize)
        servingQuantity = try container.decodeIfPresent(LenientDouble.self, forKey: .servingQuantity)
        nutriments = try? container.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
        imageFrontSmallUrl = try? container.decodeIfPresent(String.self, forKey: .imageFrontSmallUrl)
        quantity = try? container.decodeIfPresent(String.self, forKey: .quantity)
    }
}

/// Flat `nutriments` dictionary with only the numeric entries kept
/// (non-numeric values such as `energy_unit: "kcal"` are dropped).
struct OFFNutriments: Decodable {
    var values: [String: Double]

    init(values: [String: Double]) { self.values = values }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: LenientDouble].self)
        values = raw.compactMapValues { $0.value }
    }

    subscript(key: String) -> Double? { values[key] }
}
