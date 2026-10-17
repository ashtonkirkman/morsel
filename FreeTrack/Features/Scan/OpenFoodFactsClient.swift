import Foundation

// MARK: - Open Food Facts HTTP client
// Implements barcode lookup (world.openfoodfacts.org product API) and free-text search
// (search.openfoodfacts.org, the Elasticsearch-backed "search-a-licious" service).
// The legacy `cgi/search.pl` endpoint is kept only as a last-resort fallback: it is slow,
// rate-limited and frequently answers 503 under load.
// All JSON → FoodItem work lives in `OpenFoodFactsMapper`; this type only does HTTP.

final class OpenFoodFactsClient: BarcodeLookupService, FoodSearchService, @unchecked Sendable {

    // MARK: Configuration

    private static let productBase = "https://world.openfoodfacts.org/api/v2/product/"
    private static let searchBase = "https://search.openfoodfacts.org/search"
    private static let legacySearchBase = "https://us.openfoodfacts.org/cgi/search.pl"
    private static let fields = "code,product_name,product_name_en,brands,serving_size,serving_quantity,nutriments,image_front_small_url,quantity"
    /// Open Food Facts asks every client to identify itself.
    private static let userAgent = "Free Track iOS - https://github.com/ashtonkirkman/morsel"
    private static let timeout: TimeInterval = 15
    /// How many hits to ask the server for. More than we show, because products without a
    /// name or energy value are dropped during mapping.
    private static let requestedHits = 40
    private static let searchPageSize = 30
    /// When the US-only query maps to fewer results than this, widen to every English-language product.
    private static let minimumResultsBeforeWidening = 10
    /// Filters appended to the user's terms (search-a-licious accepts Lucene-style field filters).
    private static let englishFilter = "lang:\"en\""
    private static let unitedStatesFilter = "countries_tags:\"en:united-states\""
    /// Characters with a special meaning to the search query parser; stripped from user input.
    private static let reservedQueryCharacters = CharacterSet(charactersIn: "\":()[]{}^~*?\\/+-!&|<>=")
    /// One automatic retry after a brief pause when the server is momentarily unavailable.
    private static let transientStatuses: Set<Int> = [500, 502, 503, 504]
    private static let retryDelay: Duration = .milliseconds(700)

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

    /// US English products first; widened to all English-language products when the US
    /// catalogue is thin. Falls back to the legacy endpoint only if the search service is down.
    func search(query: String) async throws -> [FoodItem] {
        let terms = Self.sanitizedTerms(query)
        guard !terms.isEmpty else { return [] }

        var items: [FoodItem]
        do {
            items = try await searchAPI(terms: terms, filters: [Self.englishFilter, Self.unitedStatesFilter])
        } catch let error as ServiceError where error.isTransient {
            items = try await legacySearch(terms: terms)
            return Array(items.prefix(Self.searchPageSize))
        }

        if items.count < Self.minimumResultsBeforeWidening,
           let wider = try? await searchAPI(terms: terms, filters: [Self.englishFilter]) {
            items = Self.merged(items, wider)
        }
        return Array(items.prefix(Self.searchPageSize))
    }

    private func searchAPI(terms: String, filters: [String]) async throws -> [FoodItem] {
        guard var components = URLComponents(string: Self.searchBase) else {
            throw ServiceError.network("The search request couldn't be built.")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: ([terms] + filters).joined(separator: " ")),
            URLQueryItem(name: "langs", value: "en"),
            URLQueryItem(name: "page_size", value: String(Self.requestedHits)),
            URLQueryItem(name: "fields", value: Self.fields)
        ]
        guard let url = components.url else {
            throw ServiceError.network("The search request couldn't be built.")
        }
        let (data, http) = try await perform(url, retryOnTransientFailure: true)
        try Self.validate(http)
        return try OpenFoodFactsMapper.mapSearchResponse(data: data)
    }

    private func legacySearch(terms: String) async throws -> [FoodItem] {
        guard var components = URLComponents(string: Self.legacySearchBase) else {
            throw ServiceError.network("The search request couldn't be built.")
        }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "lc", value: "en"),
            URLQueryItem(name: "page_size", value: String(Self.requestedHits)),
            URLQueryItem(name: "fields", value: Self.fields)
        ]
        guard let url = components.url else {
            throw ServiceError.network("The search request couldn't be built.")
        }
        let (data, http) = try await perform(url, retryOnTransientFailure: true)
        try Self.validate(http)
        return try OpenFoodFactsMapper.mapSearchResponse(data: data)
    }

    /// Strips query-parser metacharacters and collapses whitespace.
    static func sanitizedTerms(_ query: String) -> String {
        query.components(separatedBy: reservedQueryCharacters)
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// `first` followed by the entries of `second` not already present (by barcode, else by name+brand).
    static func merged(_ first: [FoodItem], _ second: [FoodItem]) -> [FoodItem] {
        var seen = Set(first.map(identity))
        var out = first
        for item in second where seen.insert(identity(item)).inserted {
            out.append(item)
        }
        return out
    }

    private static func identity(_ item: FoodItem) -> String {
        if let barcode = item.barcode, !barcode.isEmpty { return "code:" + barcode }
        return (item.name + "|" + (item.brand ?? "")).lowercased()
    }

    // MARK: Transport

    private func perform(_ url: URL, retryOnTransientFailure: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let first = try await performOnce(url)
        guard retryOnTransientFailure, Self.transientStatuses.contains(first.1.statusCode) else {
            return first
        }
        try await Task.sleep(for: Self.retryDelay)
        try Task.checkCancellation()
        return try await performOnce(url)
    }

    private func performOnce(_ url: URL) async throws -> (Data, HTTPURLResponse) {
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

private extension ServiceError {
    /// Server-side outage (5xx, or an HTML maintenance page where JSON was expected) worth
    /// retrying against the fallback endpoint. Offline, cancelled, auth and rate-limit errors are not.
    var isTransient: Bool {
        switch self {
        case .server(let status, _): return status >= 500
        case .decoding: return true
        default: return false
        }
    }
}
