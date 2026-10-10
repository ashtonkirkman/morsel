import XCTest
@testable import FreeTrack

final class UserProfileTests: XCTestCase {
    /// Fixed Gregorian/UTC calendar so the maths never depends on the test host's locale or zone.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func profile(birthDate: Date?, legacyAge: Int? = nil) -> UserProfile {
        UserProfile(sex: .female, birthDate: birthDate, heightCm: 165, weightKg: 60,
                    activity: .light, goal: .maintain, legacyAge: legacyAge)
    }

    // MARK: - Age derivation

    func testAgeAcrossBirthdayBoundary() {
        let born = date(1990, 3, 14)
        XCTAssertEqual(UserProfile.age(from: born, on: date(2026, 3, 13), calendar: calendar), 35)
        XCTAssertEqual(UserProfile.age(from: born, on: date(2026, 3, 14), calendar: calendar), 36)
        XCTAssertEqual(UserProfile.age(from: born, on: date(2026, 3, 15), calendar: calendar), 36)
        XCTAssertEqual(UserProfile.age(from: born, on: date(2027, 3, 13), calendar: calendar), 36)
    }

    func testAgeIgnoresTimeOfDay() {
        // Born late in the evening, checked early on the birthday morning: still a full year older.
        let born = date(1990, 3, 14, hour: 23, minute: 30)
        XCTAssertEqual(UserProfile.age(from: born, on: date(2026, 3, 14, hour: 0, minute: 5), calendar: calendar), 36)
        XCTAssertEqual(UserProfile.age(from: born, on: date(2026, 3, 13, hour: 23, minute: 59), calendar: calendar), 35)
    }

    func testAgeNeverNegative() {
        XCTAssertEqual(UserProfile.age(from: date(2030, 1, 1), on: date(2026, 1, 1), calendar: calendar), 0)
        XCTAssertEqual(UserProfile.age(from: date(2026, 1, 1), on: date(2026, 1, 1), calendar: calendar), 0)
    }

    func testInstanceAgePrefersBirthDateThenLegacyThenFallback() {
        let today = date(2026, 10, 10)
        XCTAssertEqual(profile(birthDate: date(1996, 10, 10), legacyAge: 99).age(on: today, calendar: calendar), 30)
        XCTAssertEqual(profile(birthDate: nil, legacyAge: 42).age(on: today, calendar: calendar), 42)
        XCTAssertEqual(profile(birthDate: nil).age(on: today, calendar: calendar), UserProfile.fallbackAge)
    }

    func testPlaceholderIsFallbackAgeToday() {
        XCTAssertEqual(UserProfile.placeholder.age, UserProfile.fallbackAge)
        XCTAssertNotNil(UserProfile.placeholder.birthDate)
    }

    // MARK: - Date-of-birth helpers

    func testBirthDateForAgeRoundTrips() {
        let today = date(2026, 10, 10)
        for years in [UserProfile.minimumAgeYears, 30, 65, UserProfile.maximumAgeYears] {
            let born = UserProfile.birthDate(forAge: years, on: today, calendar: calendar)
            XCTAssertEqual(UserProfile.age(from: born, on: today, calendar: calendar), years, "age \(years)")
            // One day earlier the birthday hasn't happened yet.
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            XCTAssertEqual(UserProfile.age(from: born, on: yesterday, calendar: calendar), years - 1, "age \(years) eve")
        }
    }

    func testBirthDateForAgeOnLeapDayClampsToFebruary() {
        let leapDay = date(2024, 2, 29)
        let born = UserProfile.birthDate(forAge: 30, on: leapDay, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: born)
        XCTAssertEqual(parts.year, 1994)
        XCTAssertEqual(parts.month, 2)
        XCTAssertEqual(parts.day, 28)
        XCTAssertEqual(UserProfile.age(from: born, on: leapDay, calendar: calendar), 30)
    }

    func testBirthDateRangeSpansMinimumToMaximumAge() {
        let today = date(2026, 10, 10)
        let range = UserProfile.birthDateRange(on: today, calendar: calendar)
        XCTAssertEqual(range.lowerBound, UserProfile.earliestBirthDate(on: today, calendar: calendar))
        XCTAssertEqual(range.upperBound, UserProfile.latestBirthDate(on: today, calendar: calendar))
        XCTAssertEqual(range.lowerBound, date(1906, 10, 10))
        XCTAssertEqual(range.upperBound, date(2013, 10, 10))
        XCTAssertEqual(UserProfile.age(from: range.lowerBound, on: today, calendar: calendar), UserProfile.maximumAgeYears)
        XCTAssertEqual(UserProfile.age(from: range.upperBound, on: today, calendar: calendar), UserProfile.minimumAgeYears)

        let fallback = UserProfile.defaultBirthDate(on: today, calendar: calendar)
        XCTAssertTrue(range.contains(fallback))
        XCTAssertEqual(fallback, date(1996, 10, 10))
        XCTAssertEqual(UserProfile.age(from: fallback, on: today, calendar: calendar), UserProfile.fallbackAge)
    }

    func testRangeBoundsAreMidnight() {
        let noon = date(2026, 10, 10, hour: 12, minute: 30)
        let range = UserProfile.birthDateRange(on: noon, calendar: calendar)
        XCTAssertEqual(range.lowerBound, calendar.startOfDay(for: range.lowerBound))
        XCTAssertEqual(range.upperBound, calendar.startOfDay(for: range.upperBound))
    }

    // MARK: - Codable

    func testDecodesLegacyJSONWithIntegerAge() throws {
        let json = """
        {"sex":"female","age":42,"heightCm":165,"weightKg":60,"activity":"light","goal":"lose"}
        """
        let decoded = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertNil(decoded.birthDate)
        XCTAssertEqual(decoded.legacyAge, 42)
        XCTAssertEqual(decoded.age, 42)
        XCTAssertEqual(decoded.sex, .female)
        XCTAssertEqual(decoded.heightCm, 165)
        XCTAssertEqual(decoded.weightKg, 60)
        XCTAssertEqual(decoded.activity, .light)
        XCTAssertEqual(decoded.goal, .lose)
    }

    func testLegacyProfileRoundTripsUntilBirthDateIsSet() throws {
        let legacy = profile(birthDate: nil, legacyAge: 42)
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded, legacy)
        XCTAssertEqual(decoded.age, 42)

        var upgraded = decoded
        upgraded.birthDate = date(1984, 6, 1)
        let data2 = try JSONEncoder().encode(upgraded)
        let decoded2 = try JSONDecoder().decode(UserProfile.self, from: data2)
        XCTAssertEqual(decoded2.birthDate, date(1984, 6, 1))
        XCTAssertNil(decoded2.legacyAge, "legacy age is dropped once a birth date is stored")
    }

    func testRoundTripWithBirthDateUsingPlainJSONCoders() throws {
        let original = profile(birthDate: date(1992, 3, 14))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.birthDate, date(1992, 3, 14))
        XCTAssertNil(decoded.legacyAge)
    }

    func testEncodedJSONStillCarriesAgeForOlderBuilds() throws {
        let original = profile(birthDate: UserProfile.birthDate(forAge: 34))
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["age"] as? Int, 34)
        XCTAssertNotNil(object["birthDate"])
        XCTAssertEqual(object["sex"] as? String, "female")
    }

    func testDecodingWithoutAgeOrBirthDateFallsBack() throws {
        let json = """
        {"sex":"male","heightCm":180,"weightKg":80,"activity":"moderate","goal":"gain"}
        """
        let decoded = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertNil(decoded.birthDate)
        XCTAssertNil(decoded.legacyAge)
        XCTAssertEqual(decoded.age, UserProfile.fallbackAge)
    }
}
