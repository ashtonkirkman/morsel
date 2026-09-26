import Foundation

// MARK: - Service contracts
// Feature modules implement these; the app wires concrete instances in `AppServices`.

/// Resolves a scanned barcode (EAN-13 / UPC-A / EAN-8 digits) to a food.
protocol BarcodeLookupService: Sendable {
    /// Returns nil when the product is unknown to the database.
    func lookup(barcode: String) async throws -> FoodItem?
}

/// Free-text food search.
protocol FoodSearchService: Sendable {
    func search(query: String) async throws -> [FoodItem]
}

/// Estimates what is on a plate from a photo.
protocol MealVisionService: Sendable {
    /// - Parameters:
    ///   - imageData: JPEG data, already downscaled (≤ ~1600 px on the long edge).
    ///   - hint: optional user text ("half portion", "it's oat milk") to steer the estimate.
    ///   - previous: the prior estimate when the user is answering a clarifying question.
    func estimate(imageData: Data, hint: String?, previous: MealEstimate?) async throws -> MealEstimate
}

// MARK: - Errors

enum ServiceError: LocalizedError, Equatable {
    case notFound
    case network(String)
    case decoding(String)
    case unauthorized
    case rateLimited
    case server(status: Int, message: String)
    case noAPIKey
    case cancelled
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .notFound: return "We couldn't find that one."
        case .network(let detail): return "Network problem. \(detail)"
        case .decoding: return "The response wasn't in a form we understood."
        case .unauthorized: return "The API key was rejected."
        case .rateLimited: return "Too many requests right now. Try again in a moment."
        case .server(let status, let message): return "Server error \(status). \(message)"
        case .noAPIKey: return "Add a Claude API key or proxy URL in Settings to use photo logging."
        case .cancelled: return "Cancelled."
        case .invalidImage: return "That image couldn't be read."
        }
    }
}
