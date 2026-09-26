import XCTest
@testable import Morsel

final class SearchHelpersTests: XCTestCase {
    // MARK: - NumberParsing.double

    func testCommaDecimal() {
        XCTAssertEqual(NumberParsing.double("1,5"), 1.5)
    }

    func testDotDecimal() {
        XCTAssertEqual(NumberParsing.double("1.5"), 1.5)
    }

    func testEmptyIsNil() {
        XCTAssertNil(NumberParsing.double(""))
        XCTAssertNil(NumberParsing.double("   "))
    }

    func testLettersAreNil() {
        XCTAssertNil(NumberParsing.double("abc"))
        XCTAssertNil(NumberParsing.double("kcal"))
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(NumberParsing.double("  12 "), 12)
        XCTAssertEqual(NumberParsing.double("\n7\n"), 7)
    }

    func testTrailingUnitIsIgnored() {
        XCTAssertEqual(NumberParsing.double("150 kcal"), 150)
        XCTAssertEqual(NumberParsing.double("12g"), 12)
        XCTAssertEqual(NumberParsing.double("0,5 g"), 0.5)
    }

    func testThousandsSeparators() {
        XCTAssertEqual(NumberParsing.double("1,500"), 1500)
        XCTAssertEqual(NumberParsing.double("1,000.5"), 1000.5)
        XCTAssertEqual(NumberParsing.double("1.234,5"), 1234.5)
        XCTAssertEqual(NumberParsing.double("0,500"), 0.5)
    }

    func testNegativeNumbersParseButAreRejectedByNonNegative() {
        XCTAssertEqual(NumberParsing.double("-3"), -3)
        XCTAssertNil(NumberParsing.nonNegativeDouble("-3"))
        XCTAssertEqual(NumberParsing.nonNegativeDouble("0"), 0)
        XCTAssertNil(NumberParsing.nonNegativeDouble(""))
        XCTAssertNil(NumberParsing.nonNegativeDouble("abc"))
    }

    // MARK: - NumberParsing.string(from:)

    func testFormattingIntegers() {
        XCTAssertEqual(NumberParsing.string(from: 2), "2")
        XCTAssertEqual(NumberParsing.string(from: 150), "150")
    }

    func testFormattingTrimsTrailingZeros() {
        XCTAssertEqual(NumberParsing.string(from: 1.5), "1.5")
        XCTAssertEqual(NumberParsing.string(from: 12.25), "12.25")
        XCTAssertEqual(NumberParsing.string(from: 12.345, maxFractionDigits: 1), "12.3")
    }

    func testFormattingRoundTripsThroughParsing() {
        for value in [0.25, 1, 1.5, 33, 99.75] {
            XCTAssertEqual(NumberParsing.double(NumberParsing.string(from: value)), value)
        }
    }

    func testFormattingNonFiniteIsEmpty() {
        XCTAssertEqual(NumberParsing.string(from: .nan), "")
        XCTAssertEqual(NumberParsing.string(from: .infinity), "")
    }
}
