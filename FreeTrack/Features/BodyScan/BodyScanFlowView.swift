import SwiftData
import SwiftUI

/// New-scan sheet: weight → front / T-pose / side photos (each analysed on device) → review → save.
/// Calls `onSaved(scan)` on success and `onSaved(nil)` on cancel; the host dismisses the sheet.
@MainActor
struct BodyScanFlowView: View {
    let onSaved: (BodyScan?) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var model: BodyScanFlowModel?
    @State private var capturingPose: BodyPoseType?
    @AppStorage("bodyScanCountdownSeconds") private var countdownSeconds = 3

    init(onSaved: @escaping (BodyScan?) -> Void) {
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.mBackground
                }
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("New scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
            }
            .keyboardDoneToolbar()
        }
        .onAppear { if model == nil { model = BodyScanFlowModel(profile: settings.profile) } }
        .onDisappear { model?.cancel() }
        .fullScreenCover(item: $capturingPose) { pose in
            BodyPoseCaptureView(pose: pose, countdownSeconds: countdownSeconds, onCapture: { image in
                capturingPose = nil
                begin(image, for: pose)
            }, onCancel: { capturingPose = nil })
        }
        .interactiveDismissDisabled(model?.results.isEmpty == false)
    }

    @ViewBuilder
    private func content(_ model: BodyScanFlowModel) -> some View {
        switch model.step {
        case .setup:
            ScanSetupView(model: model) { model.startPoses() }
        case .pose(let pose):
            PoseStepView(model: model, pose: pose, unitSystem: settings.unitSystem,
                         onCapture: { capturingPose = pose },
                         onNext: { model.next(after: pose) },
                         onSkip: { model.next(after: pose) })
        case .review:
            ScanReviewView(model: model, unitSystem: settings.unitSystem, onSave: save) { pose in model.go(to: pose) }
        }
    }

    // MARK: - Actions

    private func begin(_ image: UIImage, for pose: BodyPoseType) {
        let analyzer = BodyScanAnalyzer.make(useSAM2: settings.useSAM2Segmentation)
        model?.analyze(image, for: pose, analyzer: analyzer)
    }

    private func save() {
        guard let model else { return }
        do {
            let scan = try model.save(into: context)
            writeBackWeight(model.weightKg)
            if settings.hapticsEnabled { Haptics.success() }
            onSaved(scan)
        } catch {
            model.saveError = "Couldn't save this scan. \(error.localizedDescription)"
        }
    }

    /// Keeps the profile (and the goals derived from it) in step with the weight entered for the scan.
    private func writeBackWeight(_ weightKg: Double) {
        guard var profile = settings.profile, profile.weightKg != weightKg else { return }
        profile.weightKg = weightKg
        settings.profile = profile
        let targets = GoalCalculator.targets(for: profile)
        settings.calorieGoal = targets.calories
        settings.proteinGoal = targets.protein
        settings.carbsGoal = targets.carbs
        settings.fatGoal = targets.fat
    }

    private func cancel() {
        model?.cancel()
        onSaved(nil)
    }
}

// MARK: - Setup

/// Step 0: confirm weight (pre-filled from the profile), height and sex if there is no profile, optional note.
struct ScanSetupView: View {
    @Bindable var model: BodyScanFlowModel
    let onStart: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Today's numbers")
                            .font(FreeTrackFont.headline)
                            .foregroundStyle(Color.mText)
                        Text("Your height sets the scale for every measurement; weight feeds lean-mass and your calorie goals.")
                            .font(FreeTrackFont.caption)
                            .foregroundStyle(Color.mTextSecondary)
                        weightField
                        Divider().overlay(Color.mSeparator)
                        heightFields
                        if !model.hasProfile {
                            Divider().overlay(Color.mSeparator)
                            HStack {
                                Text("Sex").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                                Spacer()
                                Picker("Sex", selection: $model.sex) {
                                    ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 190)
                            }
                            .padding(.vertical, 6)
                        }
                        Divider().overlay(Color.mSeparator)
                        TextField("Note (optional), e.g. “morning, fasted”", text: $model.notes)
                            .font(FreeTrackFont.body)
                            .foregroundStyle(Color.mText)
                            .padding(.vertical, 6)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Label("How it works", systemImage: "figure.stand")
                            .font(FreeTrackFont.headline)
                            .foregroundStyle(Color.mText)
                        ForEach(BodyPoseType.allCases) { pose in
                            HStack(alignment: .top, spacing: Spacing.s) {
                                Text("\(pose.stepNumber).")
                                    .font(FreeTrackFont.callout.weight(.semibold))
                                    .foregroundStyle(Color.mAccent)
                                Text(pose.summary)
                                    .font(FreeTrackFont.callout)
                                    .foregroundStyle(Color.mTextSecondary)
                            }
                        }
                        Text("Plain background, even light, fitted clothing. Prop the phone at hip height about 2–3 m away. Everything is analysed on this phone; photos never leave it.")
                            .font(FreeTrackFont.caption)
                            .foregroundStyle(Color.mTextTertiary)
                            .padding(.top, Spacing.xs)
                    }
                }
                Button("Start", action: onStart)
                    .buttonStyle(.freeTrackPrimary)
                    .disabled(!model.isSetupValid)
            }
            .padding(Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var weightField: some View {
        switch settings.unitSystem {
        case .metric:
            SettingsNumberField(title: "Weight", unit: "kg", value: $model.weightKg, fractionDigits: 1)
        case .imperial:
            SettingsNumberField(title: "Weight", unit: "lb",
                                value: Binding(get: { Units.lb(fromKg: model.weightKg).rounded() },
                                               set: { model.weightKg = Units.kg(fromLb: $0) }))
        }
    }

    @ViewBuilder
    private var heightFields: some View {
        switch settings.unitSystem {
        case .metric:
            SettingsNumberField(title: "Height", unit: "cm", value: $model.heightCm)
        case .imperial:
            HStack(spacing: Spacing.s) {
                Text("Height").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                Spacer()
                CompactNumberField(unit: "ft", value: Binding(
                    get: { Double(Units.feetInches(fromCm: model.heightCm).feet) },
                    set: { feet in
                        let inches = Units.feetInches(fromCm: model.heightCm).inches
                        model.heightCm = Units.cm(feet: Int(feet.rounded()), inches: Double(inches))
                    }), accessibilityLabel: "Height feet")
                CompactNumberField(unit: "in", value: Binding(
                    get: { Double(Units.feetInches(fromCm: model.heightCm).inches) },
                    set: { inches in
                        let feet = Units.feetInches(fromCm: model.heightCm).feet
                        model.heightCm = Units.cm(feet: feet, inches: inches)
                    }), accessibilityLabel: "Height inches")
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Pose step

/// One of the three poses: tips, capture button or the annotated result with retake / next.
struct PoseStepView: View {
    @Bindable var model: BodyScanFlowModel
    let pose: BodyPoseType
    let unitSystem: UnitSystem
    let onCapture: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    private var result: PoseAnalysisResult? { model.result(for: pose) }
    private var isAnalyzing: Bool { model.analyzingPose == pose }
    private var isLast: Bool { pose == BodyPoseType.allCases.last }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    stepChips
                    header
                    if let result {
                        resultCard(result)
                    } else {
                        tipsCard
                        if let error = model.poseErrors[pose] { errorCard(error) }
                        Button(action: onCapture) { Label("Take photo", systemImage: "camera") }
                            .buttonStyle(.freeTrackPrimary)
                            .accessibilityHint("Opens the camera with a countdown timer")
                        if pose != .frontArmsDown {
                            Button("Skip this pose", action: onSkip)
                                .buttonStyle(.freeTrackSecondary)
                        }
                    }
                }
                .padding(Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            if isAnalyzing {
                LoadingOverlay(message: "Measuring on device…")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAnalyzing)
    }

    private var stepChips: some View {
        HStack(spacing: Spacing.s) {
            ForEach(BodyPoseType.allCases) { p in
                Chip(title: p.shortName,
                     symbol: model.results[p] != nil ? "checkmark" : p.symbolName,
                     isSelected: p == pose) { model.go(to: p) }
                    .accessibilityLabel("\(p.title)\(model.results[p] != nil ? ", done" : "")")
            }
            Spacer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(pose.stepNumber). \(pose.title)")
                .font(FreeTrackFont.title)
                .foregroundStyle(Color.mText)
            Text(pose.summary)
                .font(FreeTrackFont.callout)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tipsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("How to pose").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                ForEach(pose.tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Image(systemName: "checkmark.circle").font(.caption).foregroundStyle(Color.mAccent).padding(.top, 3)
                        Text(tip).font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                    }
                }
                Text("Measures: " + pose.keyMetrics.joined(separator: " · "))
                    .font(FreeTrackFont.caption)
                    .foregroundStyle(Color.mTextTertiary)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Detection failed", systemImage: "exclamationmark.triangle")
                    .font(FreeTrackFont.headline)
                    .foregroundStyle(Color.mDanger)
                Text(message).font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
            }
        }
    }

    private func resultCard(_ result: PoseAnalysisResult) -> some View {
        VStack(spacing: Spacing.m) {
            if let warning = result.warning {
                Card {
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.mWarning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check this photo").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                            Text(warning + " You can keep it, but the numbers will be marked low confidence.")
                                .font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                        }
                    }
                }
            } else {
                Label("Pose captured", systemImage: "checkmark.circle.fill")
                    .font(FreeTrackFont.headline)
                    .foregroundStyle(Color.mAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PoseOverlayView(image: result.image, keypoints: result.observation.keypoints, maskImage: model.maskImages[pose])
                .frame(maxHeight: 420)
            quickMetrics
            HStack(spacing: Spacing.s) {
                Button { model.retake(pose) } label: { Label("Retake", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.freeTrackSecondary)
                Button(action: onNext) { Label(isLast ? "Review" : "Next pose", systemImage: isLast ? "checkmark" : "chevron.right") }
                    .buttonStyle(.freeTrackPrimary)
            }
        }
    }

    /// A few numbers from this pose alone, so each photo gives immediate feedback.
    private var quickMetrics: some View {
        let m = model.measurements ?? BodyMeasurements()
        let items: [(String, String)] = [
            ("Waist", m.value(.waistCircumference).map { BodyFormat.length($0, unitSystem) } ?? "—"),
            ("Body fat", m.value(.bodyFatPercent).map { BodyFormat.percent($0) } ?? "—"),
            ("Arm span", m.value(.armSpan).map { BodyFormat.length($0, unitSystem) } ?? "—"),
            ("Shoulders", m.value(.shoulderWidth).map { BodyFormat.length($0, unitSystem) } ?? "—")
        ]
        return Card {
            HStack(alignment: .top) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 2) {
                        Text(item.1).font(FreeTrackFont.numeral).foregroundStyle(Color.mText).lineLimit(1).minimumScaleFactor(0.6)
                        Text(item.0).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Review

/// Last step: headline numbers with confidence, which poses were used, Save.
struct ScanReviewView: View {
    @Bindable var model: BodyScanFlowModel
    let unitSystem: UnitSystem
    let onSave: () -> Void
    let onEditPose: (BodyPoseType) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                if let m = model.measurements {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            HStack {
                                Text("Your measurements").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                                Spacer()
                                ConfidenceBadge(confidence: m.overallConfidence.score)
                            }
                            ForEach(BodyMetric.keyMetrics) { metric in
                                if let v = m[metric] {
                                    HStack {
                                        Text(metric.title).font(FreeTrackFont.body).foregroundStyle(Color.mText)
                                        Spacer()
                                        Text(BodyFormat.value(metric, v.value, unitSystem))
                                            .font(FreeTrackFont.numeral)
                                            .foregroundStyle(v.confidence == .low ? Color.mWarning : Color.mText)
                                    }
                                }
                            }
                            Text("Photo estimates are typically within ±5–10%. Compare scans taken the same way (time of day, clothes, distance) rather than reading single numbers as truth.")
                                .font(FreeTrackFont.caption)
                                .foregroundStyle(Color.mTextTertiary)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Photos").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                        ForEach(BodyPoseType.allCases) { pose in
                            HStack {
                                Image(systemName: model.results[pose] != nil ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(model.results[pose] != nil ? Color.mAccent : Color.mTextTertiary)
                                Text(pose.title).font(FreeTrackFont.body).foregroundStyle(Color.mText)
                                Spacer()
                                Button(model.results[pose] != nil ? "Retake" : "Add") { onEditPose(pose) }
                                    .font(FreeTrackFont.callout.weight(.semibold))
                                    .foregroundStyle(Color.mAccent)
                            }
                            .padding(.vertical, 4)
                        }
                        if model.results[.sideLeft] == nil {
                            Text("Without a side photo, waist, chest and hip circumferences assume typical depth and are marked medium confidence.")
                                .font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
                        }
                    }
                }
                if let error = model.saveError {
                    Text(error).font(FreeTrackFont.caption).foregroundStyle(Color.mDanger)
                }
                Button("Save scan", action: onSave)
                    .buttonStyle(.freeTrackPrimary)
                    .disabled(!model.canReview)
            }
            .padding(Spacing.m)
        }
    }
}
