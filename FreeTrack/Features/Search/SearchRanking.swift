import Foundation

// MARK: - Client-side ordering of product search results
// The server ranks by relevance across name, brand, categories and labels, which lets
// "Caprice des Dieux" surface for "cheese" (category match) and "Apple & Eve juice" for
// "apple" (brand match). Re-rank so products whose *name* is the query come first, drop
// names written in a non-Latin script, and collapse duplicates.

enum SearchRanking {

    /// Stable re-ordering of `items` for `query`: exact names, then names starting with the
    /// query, then names containing every query word, then everything else (brand/category hits).
    /// Within a tier, shorter names win. Duplicates (same name and brand) and names without
    /// Latin letters are removed.
    static func rank(_ items: [FoodItem], query: String) -> [FoodItem] {
        let folded = SearchText.folded(query)
        let tokens = SearchText.tokens(query)
        guard !tokens.isEmpty else { return dedupe(items) }

        let scored: [(index: Int, item: FoodItem, score: Int)] = dedupe(items).enumerated().compactMap { index, item in
            guard hasLatinLetters(item.name) else { return nil }
            return (index, item, score(name: item.name, foldedQuery: folded, queryTokens: tokens))
        }
        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
            }
            .map(\.item)
    }

    static func score(name: String, foldedQuery: String, queryTokens: [String]) -> Int {
        let foldedName = SearchText.folded(name)
        let nameTokens = SearchText.tokens(name)
        var score: Int
        if foldedName == foldedQuery {
            score = 400
        } else if foldedName.hasPrefix(foldedQuery) {
            score = 300
        } else if queryTokens.allSatisfy({ token in nameTokens.contains { $0 == token || $0.hasPrefix(token) } }) {
            score = 200
        } else if queryTokens.contains(where: { token in nameTokens.contains { $0.hasPrefix(token) } }) {
            score = 100
        } else {
            score = 0
        }
        // Prefer plain names: "Cheddar cheese" over "Sliced Sharp Cheddar Cheese, Family Size".
        score -= min(60, nameTokens.count * 6)
        return score
    }

    /// True when at least one character is a basic Latin letter, so Cyrillic/Thai/Arabic-only
    /// names (which an English speaker cannot read) are filtered out.
    static func hasLatinLetters(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }

    static func dedupe(_ items: [FoodItem]) -> [FoodItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = SearchText.folded(item.name) + "|" + SearchText.folded(item.brand ?? "")
            return seen.insert(key).inserted
        }
    }
}
