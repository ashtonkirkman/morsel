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
struct UserProfile: Codable, Hashable, Sendable {
    var sex: BiologicalSex
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var activity: ActivityLevel
    var goal: WeightGoal
}
