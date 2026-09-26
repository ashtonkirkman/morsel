import Foundation
import Observation

/// Debounced free-text search state. The view drives it via `.task(id: requestKey)`.
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
    private(set) var results: [FoodItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The trimmed query whose results are currently in `results`.
    private(set) var completedQuery: String?
    private var attempt = 0

    // MARK: - Derived

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !trimmedQuery.isEmpty }
    var requestKey: RequestKey { RequestKey(query: trimmedQuery, attempt: attempt) }

    /// True once a search finished for the current query and found nothing.
    var showsEmptyState: Bool {
        isSearching && !isLoading && errorMessage == nil && completedQuery == trimmedQuery && results.isEmpty
    }

    /// True when results (or the empty state) for the current query are on screen.
    var hasCompletedCurrentQuery: Bool {
        isSearching && !isLoading && completedQuery == trimmedQuery
    }

    // MARK: - Actions

    func retry() {
        errorMessage = nil
        attempt += 1
    }

    /// Waits `debounceMilliseconds`, then searches. Cancelled automatically when the task id changes.
    func runSearch(using service: any FoodSearchService, debounceMilliseconds: Int = 350) async {
        let q = trimmedQuery
        guard !q.isEmpty else {
            reset()
            return
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
            results = found
            completedQuery = q
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, q == trimmedQuery else { return }
            isLoading = false
            results = []
            completedQuery = nil
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Private

    private func reset() {
        results = []
        isLoading = false
        errorMessage = nil
        completedQuery = nil
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let serviceError = error as? ServiceError, let text = serviceError.errorDescription {
            return text
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
