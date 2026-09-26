import SwiftUI

/// Body-stat inputs shared by Settings > Profile and Onboarding. Stores metric, displays per `unitSystem`.
struct ProfileFieldsView: View {
    @Binding var profile: UserProfile
    @Binding var unitSystem: UnitSystem
    var showsUnitToggle: Bool = true

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if showsUnitToggle {
                Picker("Units", selection: $unitSystem) {
                    ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, Spacing.s)
            }
            HStack {
                Text("Sex").font(MorselFont.body).foregroundStyle(Color.mText)
                Spacer()
                Picker("Sex", selection: $profile.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
            .padding(.vertical, 6)
            separator
            SettingsNumberField(title: "Age", unit: "yrs", value: ageBinding)
            separator
            heightFields
            separator
            weightField
        }
        .id(unitSystem)
    }

    private var separator: some View { Divider().overlay(Color.mSeparator) }

    // MARK: - Height / weight

    @ViewBuilder
    private var heightFields: some View {
        switch unitSystem {
        case .metric:
            SettingsNumberField(title: "Height", unit: "cm", value: $profile.heightCm)
        case .imperial:
            SettingsNumberField(title: "Height", unit: "ft", value: feetBinding)
            separator
            SettingsNumberField(title: "", unit: "in", value: inchesBinding)
                .accessibilityLabel("Height inches")
        }
    }

    @ViewBuilder
    private var weightField: some View {
        switch unitSystem {
        case .metric:
            SettingsNumberField(title: "Weight", unit: "kg", value: $profile.weightKg, fractionDigits: 1)
        case .imperial:
            SettingsNumberField(title: "Weight", unit: "lb", value: poundsBinding)
        }
    }

    // MARK: - Bindings

    private var ageBinding: Binding<Double> {
        Binding(get: { Double(profile.age) },
                set: { profile.age = max(1, min(120, Int($0.rounded()))) })
    }

    private var feetBinding: Binding<Double> {
        Binding(get: { Double(Units.feetInches(fromCm: profile.heightCm).feet) },
                set: { feet in
                    let inches = Units.feetInches(fromCm: profile.heightCm).inches
                    profile.heightCm = Units.cm(feet: Int(feet.rounded()), inches: Double(inches))
                })
    }

    private var inchesBinding: Binding<Double> {
        Binding(get: { Double(Units.feetInches(fromCm: profile.heightCm).inches) },
                set: { inches in
                    let feet = Units.feetInches(fromCm: profile.heightCm).feet
                    profile.heightCm = Units.cm(feet: feet, inches: inches)
                })
    }

    private var poundsBinding: Binding<Double> {
        Binding(get: { Units.lb(fromKg: profile.weightKg).rounded() },
                set: { profile.weightKg = Units.kg(fromLb: $0) })
    }
}

extension UserProfile {
    /// Starting point for the editors before the user has entered anything.
    static let placeholder = UserProfile(sex: .female, age: 30, heightCm: 168, weightKg: 68,
                                         activity: .moderate, goal: .maintain)
}
