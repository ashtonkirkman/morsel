import Foundation

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case female, male
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Desk job, little exercise"
        case .light: return "Light exercise 1–3 days/week"
        case .moderate: return "Moderate exercise 3–5 days/week"
        case .active: return "Hard exercise 6–7 days/week"
        case .veryActive: return "Physical job or twice-daily training"
        }
    }

    /// Multiplier applied to basal metabolic rate.
    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum WeightGoal: String, Codable, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lose: return "Lose weight"
        case .maintain: return "Maintain"
        case .gain: return "Gain muscle"
        }
    }

    /// Daily kcal adjustment applied to maintenance calories.
    var calorieDelta: Double {
        switch self {
        case .lose: return -500
        case .maintain: return 0
        case .gain: return 300
        }
    }
}

/// Body stats captured at onboarding. Stored in metric regardless of display units.
///
/// Age is derived from `birthDate` so it stays correct as years pass. Builds before the date-of-birth
/// picker persisted `age` as an `Int`; that value is kept in `legacyAge` until the user picks a date.
struct UserProfile: Hashable, Sendable {
    var sex: BiologicalSex
    var birthDate: Date?
    var heightCm: Double
    var weightKg: Double
    var activity: ActivityLevel
    var goal: WeightGoal
    /// Integer age stored by older builds. Only consulted while `birthDate` is nil.
    var legacyAge: Int?

    init(sex: BiologicalSex, birthDate: Date?, heightCm: Double, weightKg: Double,
         activity: ActivityLevel, goal: WeightGoal, legacyAge: Int? = nil) {
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.legacyAge = legacyAge
    }

    // MARK: - Age

    /// Age used when neither a birth date nor a legacy age is known.
    static let fallbackAge = 30
    /// Youngest / oldest date of birth the editors accept.
    static let minimumAgeYears = 13
    static let maximumAgeYears = 120

    /// Whole years since `birthDate` as of today. Falls back to `legacyAge`, then `fallbackAge`.
    var age: Int { age(on: .now) }

    /// Whole years since `birthDate` as of `date` (testable form of `age`).
    func age(on date: Date, calendar: Calendar = .current) -> Int {
        if let birthDate {
            return Self.age(from: birthDate, on: date, calendar: calendar)
        }
        return legacyAge ?? Self.fallbackAge
    }

    /// Completed years between `birthDate` and `date`, comparing calendar days so the time of day
    /// never shifts a birthday. Never negative.
    static func age(from birthDate: Date, on date: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: birthDate)
        let end = calendar.startOfDay(for: date)
        guard start <= end else { return 0 }
        return max(0, calendar.dateComponents([.year], from: start, to: end).year ?? 0)
    }

    /// Midnight `years` years before `date` — the birth date of someone who turns `years` today.
    static func birthDate(forAge years: Int, on date: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .year, value: -years, to: today) ?? today
    }

    /// Oldest selectable date of birth (`maximumAgeYears` ago).
    static func earliestBirthDate(on date: Date = .now, calendar: Calendar = .current) -> Date {
        birthDate(forAge: maximumAgeYears, on: date, calendar: calendar)
    }

    /// Youngest selectable date of birth (`minimumAgeYears` ago).
    static func latestBirthDate(on date: Date = .now, calendar: Calendar = .current) -> Date {
        birthDate(forAge: minimumAgeYears, on: date, calendar: calendar)
    }

    /// Date shown in the picker before the user has chosen one (`fallbackAge` years ago).
    static func defaultBirthDate(on date: Date = .now, calendar: Calendar = .current) -> Date {
        birthDate(forAge: fallbackAge, on: date, calendar: calendar)
    }

    /// Selectable date-of-birth span for `DatePicker(in:)`.
    static func birthDateRange(on date: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        earliestBirthDate(on: date, calendar: calendar)...latestBirthDate(on: date, calendar: calendar)
    }
}

// MARK: - Codable

extension UserProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case sex, age, birthDate, heightCm, weightKg, activity, goal
    }

    /// Accepts both the current shape (`birthDate`) and the legacy one (`age` as an Int).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sex = try container.decode(BiologicalSex.self, forKey: .sex)
        let birthDate = try container.decodeIfPresent(Date.self, forKey: .birthDate)
        let heightCm = try container.decode(Double.self, forKey: .heightCm)
        let weightKg = try container.decode(Double.self, forKey: .weightKg)
        let activity = try container.decode(ActivityLevel.self, forKey: .activity)
        let goal = try container.decode(WeightGoal.self, forKey: .goal)
        var legacyAge: Int? = nil
        if birthDate == nil {
            legacyAge = try container.decodeIfPresent(Int.self, forKey: .age)
        }
        self.init(sex: sex, birthDate: birthDate, heightCm: heightCm, weightKg: weightKg,
                  activity: activity, goal: goal, legacyAge: legacyAge)
    }

    /// Writes `birthDate` (plain `JSONEncoder` default: seconds since 2001 as a Double) and still
    /// writes the derived `age` so a profile saved here remains readable by older builds.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sex, forKey: .sex)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encode(age, forKey: .age)
        try container.encode(heightCm, forKey: .heightCm)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encode(activity, forKey: .activity)
        try container.encode(goal, forKey: .goal)
    }
}
