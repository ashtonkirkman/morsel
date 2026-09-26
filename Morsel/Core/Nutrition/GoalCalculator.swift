import Foundation

/// Daily calorie and macro targets from body stats. Pure functions; unit-tested.
enum GoalCalculator {
    /// Mifflin–St Jeor basal metabolic rate (kcal/day).
    static func bmr(for p: UserProfile) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        return p.sex == .male ? base + 5 : base - 161
    }

    static func maintenanceCalories(for p: UserProfile) -> Double {
        bmr(for: p) * p.activity.factor
    }

    /// Target calories, never below a safe floor.
    static func targetCalories(for p: UserProfile) -> Double {
        let floor: Double = p.sex == .male ? 1500 : 1200
        return max(floor, (maintenanceCalories(for: p) + p.goal.calorieDelta).rounded(toNearest: 10))
    }

    /// Macro split: protein 1.6–2.0 g/kg depending on goal, fat 30% of calories, carbs fill the rest.
    static func targets(for p: UserProfile) -> NutritionFacts {
        let calories = targetCalories(for: p)
        let proteinPerKg: Double = p.goal == .gain ? 2.0 : (p.goal == .lose ? 1.8 : 1.6)
        let protein = (p.weightKg * proteinPerKg).rounded()
        let fat = (calories * 0.30 / 9).rounded()
        let carbs = max(50, ((calories - protein * 4 - fat * 9) / 4).rounded())
        return NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

extension Double {
    func rounded(toNearest step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step).rounded() * step
    }
}

/// Unit helpers used by onboarding/settings.
enum Units {
    static func kg(fromLb lb: Double) -> Double { lb * 0.45359237 }
    static func lb(fromKg kg: Double) -> Double { kg / 0.45359237 }
    static func cm(feet: Int, inches: Double) -> Double { (Double(feet) * 12 + inches) * 2.54 }
    static func feetInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = (cm / 2.54).rounded()
        return (Int(totalInches) / 12, Int(totalInches) % 12)
    }
}
