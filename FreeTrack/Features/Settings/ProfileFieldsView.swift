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
                Text("Sex").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                Spacer()
                Picker("Sex", selection: $profile.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
            .padding(.vertical, 6)
            separator
            birthDateField
            separator
            heightFields
            separator
            weightField
        }
        // No `.id(unitSystem)` here: the height/weight rows already get fresh identities from their
        // `switch`, and re-creating the whole stack dropped focus (and the keyboard) on every toggle.
    }

    private var separator: some View { Divider().overlay(Color.mSeparator) }

    // MARK: - Date of birth

    /// Compact picker: tapping the date opens the calendar popover. Same row metrics as `SettingsNumberField`.
    private var birthDateField: some View {
        HStack(spacing: Spacing.s) {
            Text("Date of birth")
                .font(FreeTrackFont.body)
                .foregroundStyle(Color.mText)
            Spacer()
            DatePicker("Date of birth",
                       selection: birthDateBinding,
                       in: UserProfile.birthDateRange(),
                       displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Color.mAccent)
                .accessibilityLabel("Date of birth")
        }
        .padding(.vertical, 6)
    }

    // MARK: - Height / weight

    @ViewBuilder
    private var heightFields: some View {
        switch unitSystem {
        case .metric:
            SettingsNumberField(title: "Height", unit: "cm", value: $profile.heightCm)
        case .imperial:
            HStack(spacing: Spacing.s) {
                Text("Height").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                Spacer()
                CompactNumberField(unit: "ft", value: feetBinding, accessibilityLabel: "Height feet")
                CompactNumberField(unit: "in", value: inchesBinding, accessibilityLabel: "Height inches")
            }
            .padding(.vertical, 6)
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

    /// Shows 30 years ago until the user picks a date; stores midnight so the time of day never
    /// nudges the derived age.
    private var birthDateBinding: Binding<Date> {
        Binding(get: { profile.birthDate ?? UserProfile.defaultBirthDate() },
                set: { profile.birthDate = Calendar.current.startOfDay(for: $0) })
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
    /// Starting point for the editors before the user has entered anything (age 30 today).
    static let placeholder = UserProfile(sex: .female, birthDate: UserProfile.defaultBirthDate(),
                                         heightCm: 168, weightKg: 68, activity: .moderate, goal: .maintain)
}
