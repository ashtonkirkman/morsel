import Foundation
import Observation

/// Debounced free-text search state. The view drives it via `.task(id: requestKey)`.
/// Results come in two groups: built-in whole foods (instant, offline) and Open Food Facts
/// products (network, re-ranked so plain English names lead).
@MainActor
@Observable
final class FoodSearchViewModel {
    // MARK: - Request identity

    /// Changes whenever a new network request should start (query edit or explicit retry).
    struct RequestKey: Hashable {
        var query: String
        var attempt: Int
    }

    // MARK: - State

    var query: String = ""
    /// Unbranded staples from `BasicFoodCatalog`; shown above products.
    private(set) var basicResults: [FoodItem] = []
    /// Branded products from the food database, already ranked.
    private(set) var productResults: [FoodItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The trimmed query whose products are currently in `productResults`.
    private(set) var completedQuery: String?
    private var attempt = 0

    // MARK: - Derived

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !trimmedQuery.isEmpty }
    var requestKey: RequestKey { RequestKey(query: trimmedQuery, attempt: attempt) }
    var results: [FoodItem] { basicResults + productResults }

    /// True once a search finished for the current query and found nothing at all.
    var showsEmptyState: Bool {
        isSearching && !isLoading && errorMessage == nil && completedQuery == trimmedQuery && results.isEmpty
    }

    /// True when products (or the empty state) for the current query are on screen.
    var hasCompletedCurrentQuery: Bool {
        isSearching && !isLoading && completedQuery == trimmedQuery
    }

    // MARK: - Actions

    func retry() {
        errorMessage = nil
        attempt += 1
    }

    /// Shows built-in matches immediately, waits `debounceMilliseconds`, then searches the
    /// database. Cancelled automatically when the task id changes.
    func runSearch(using service: any FoodSearchService, debounceMilliseconds: Int = 350) async {
        let q = trimmedQuery
        guard !q.isEmpty else {
            reset()
            return
        }

        basicResults = BasicFoodCatalog.matches(q)
        if completedQuery != q {
            productResults = []
            completedQuery = nil
        }

        do {
            try await Task.sleep(for: .milliseconds(debounceMilliseconds))
        } catch {
            return // superseded by a newer keystroke
        }

        isLoading = true
        errorMessage = nil
        do {
            let found = try await service.search(query: q)
            guard !Task.isCancelled, q == trimmedQuery else { return }
            productResults = SearchRanking.rank(found, query: q)
            completedQuery = q
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, q == trimmedQuery else { return }
            isLoading = false
            productResults = []
            completedQuery = nil
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Private

    private func reset() {
        basicResults = []
        productResults = []
        isLoading = false
        errorMessage = nil
        completedQuery = nil
    }

    static func friendlyMessage(for error: Error) -> String {
        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .server(let status, _) where status >= 500:
                return "The food database is busy right now. Tap retry in a moment."
            case .rateLimited:
                return "Too many searches in a row. Wait a few seconds and retry."
            case .decoding:
                return "The food database sent something we couldn't read. Tap retry."
            default:
                if let text = serviceError.errorDescription { return text }
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return "You look offline. Check your connection and try again."
            case .timedOut:
                return "The food database is taking too long. Try again."
            default:
                break
            }
        }
        return "We couldn't reach the food database. Try again in a moment."
    }
}
