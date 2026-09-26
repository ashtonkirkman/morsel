import Foundation

// MARK: - Open Food Facts HTTP client
// Implements both barcode lookup and free-text search against world.openfoodfacts.org.
// All JSON → FoodItem work lives in `OpenFoodFactsMapper`; this type only does HTTP.

final class OpenFoodFactsClient: BarcodeLookupService, FoodSearchService, @unchecked Sendable {

    // MARK: Configuration

    private static let productBase = "https://world.openfoodfacts.org/api/v2/product/"
    private static let searchBase = "https://world.openfoodfacts.org/cgi/search.pl"
    private static let fields = "code,product_name,brands,serving_size,serving_quantity,nutriments,image_front_small_url,quantity"
    /// Open Food Facts asks every client to identify itself.
    private static let userAgent = "Morsel iOS - https://github.com/ashtonkirkman/morsel"
    private static let timeout: TimeInterval = 15
    private static let searchPageSize = 25

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: BarcodeLookupService

    func lookup(barcode: String) async throws -> FoodItem? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        guard let escaped = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: Self.productBase + escaped + ".json") else {
            throw ServiceError.network("That barcode couldn't be turned into a request.")
        }
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        guard let url = components.url else {
            throw ServiceError.network("That barcode couldn't be turned into a request.")
        }

        let (data, http) = try await perform(url)
        if http.statusCode == 404 { return nil }
        try Self.validate(http)
        return try OpenFoodFactsMapper.mapLookupResponse(data: data, barcode: code)
    }

    // MARK: FoodSearchService

    func search(query: String) async throws -> [FoodItem] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty else { return [] }
        guard var components = URLComponents(string: Self.searchBase) else {
            throw ServiceError.network("The search request couldn't be built.")
        }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(Self.searchPageSize)),
            URLQueryItem(name: "fields", value: Self.fields)
        ]
        guard let url = components.url else {
            throw ServiceError.network("The search request couldn't be built.")
        }

        let (data, http) = try await perform(url)
        try Self.validate(http)
        let items = try OpenFoodFactsMapper.mapSearchResponse(data: data)
        return Array(items.prefix(Self.searchPageSize))
    }

    // MARK: Transport

    private func perform(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeout
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ServiceError.network("Unexpected response from Open Food Facts.")
            }
            return (data, http)
        } catch let error as ServiceError {
            throw error
        } catch is CancellationError {
            throw ServiceError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw ServiceError.cancelled
            case .timedOut: throw ServiceError.network("Open Food Facts took too long to answer.")
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw ServiceError.network("You appear to be offline.")
            default: throw ServiceError.network(error.localizedDescription)
            }
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }
    }

    /// Maps non-2xx statuses to `ServiceError`. 404 is handled by callers (it means "unknown product").
    private static func validate(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw ServiceError.unauthorized
        case 429:
            throw ServiceError.rateLimited
        default:
            throw ServiceError.server(status: http.statusCode,
                                      message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized)
        }
    }
}
