import XCTest
@testable import FreeTrack

/// Client-side re-ranking of Open Food Facts search hits.
final class SearchRankingTests: XCTestCase {

    private func item(_ name: String, brand: String? = nil) -> FoodItem {
        FoodItem(name: name, brand: brand, servingDescription: "100 g", servingGrams: 100,
                 nutritionPerServing: NutritionFacts(calories: 100), source: .search)
    }

    func testPlainNameBeatsBrandAndCategoryMatches() {
        let hits = [
            item("Caprice des Dieux", brand: "Savencia"),          // category match only
            item("La Hollandaise Cheddar", brand: "La Hollandaise"),
            item("Sliced Sharp Cheddar Cheese", brand: "Sargento"),
            item("Cheddar cheese", brand: "Great Value"),
            item("Cheese", brand: "Tesco")
        ]
        let names = SearchRanking.rank(hits, query: "cheese").map(\.name)
        XCTAssertEqual(names.first, "Cheese")
        XCTAssertEqual(names[1], "Cheddar cheese")
        XCTAssertEqual(names[2], "Sliced Sharp Cheddar Cheese")
        // Neither of these has "cheese" in its name; they keep the server's relative order at the bottom.
        XCTAssertEqual(Array(names.suffix(2)), ["Caprice des Dieux", "La Hollandaise Cheddar"])
    }

    func testNameStartingWithQueryBeatsNameContainingIt() {
        let hits = [
            item("Organic Chewy Banana Bites", brand: "Barnana"),
            item("Apple & Eve 100% Juice, Apple", brand: "Apple & Eve"),
            item("Bananas", brand: "Tesco")
        ]
        let names = SearchRanking.rank(hits, query: "banana").map(\.name)
        XCTAssertEqual(names, ["Bananas", "Organic Chewy Banana Bites", "Apple & Eve 100% Juice, Apple"])
    }

    func testNonLatinNamesAreDropped() {
        let hits = [item("Българско бяло саламурено сирене", brand: "Домлян"), item("Feta", brand: "Dodoni")]
        XCTAssertEqual(SearchRanking.rank(hits, query: "cheese").map(\.name), ["Feta"])
    }

    func testDuplicatesCollapseKeepingFirst() {
        let hits = [item("Cheddar Cheese", brand: "Sargento"), item("cheddar cheese", brand: "SARGENTO"),
                    item("Cheddar Cheese", brand: "Kraft")]
        XCTAssertEqual(SearchRanking.rank(hits, query: "cheddar").count, 2)
    }

    func testDiacriticsAreIgnoredWhenMatching() {
        let hits = [item("Jalapeño peppers"), item("Pepper Jack")]
        XCTAssertEqual(SearchRanking.rank(hits, query: "jalapeno").first?.name, "Jalapeño peppers")
    }

    func testOrderIsStableWithinATier() {
        let hits = [item("Milk A"), item("Milk B"), item("Milk C")]
        XCTAssertEqual(SearchRanking.rank(hits, query: "milk").map(\.name), ["Milk A", "Milk B", "Milk C"])
    }

    func testEmptyQueryOnlyDedupes() {
        let hits = [item("A"), item("a"), item("B")]
        XCTAssertEqual(SearchRanking.rank(hits, query: "   ").map(\.name), ["A", "B"])
    }

    // MARK: - Client query hygiene

    func testSanitizedTermsStripQueryParserCharacters() {
        XCTAssertEqual(OpenFoodFactsClient.sanitizedTerms("  cheese: \"sharp\" (aged)  "), "cheese sharp aged")
        XCTAssertEqual(OpenFoodFactsClient.sanitizedTerms("ben & jerry's"), "ben jerry's")
        XCTAssertEqual(OpenFoodFactsClient.sanitizedTerms("   "), "")
    }

    func testMergedKeepsOrderAndDropsDuplicatesByBarcodeThenName() {
        var a = item("Bananas", brand: "Tesco"); a.barcode = "1"
        var b = item("Bananas", brand: "Tesco"); b.barcode = "1"
        let c = item("Bananas", brand: "Asda")
        let d = item("bananas", brand: "asda")
        let merged = OpenFoodFactsClient.merged([a, c], [b, d, item("Banana chips")])
        XCTAssertEqual(merged.map(\.name), ["Bananas", "Bananas", "Banana chips"])
    }
}
