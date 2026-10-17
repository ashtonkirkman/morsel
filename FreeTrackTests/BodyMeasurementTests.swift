import XCTest
@testable import FreeTrack

/// Synthetic stick figure at exactly 10 px/cm (180 cm tall in a 1800×2000 image). Expected values were
/// cross-checked with a numpy prototype of the same drawing before the Swift port.
enum SyntheticFigure {
    static let width = 1800
    static let height = 2000
    static let heightCm = 180.0
    static let weightKg = 80.0

    static func frontMask(tPose: Bool) -> BodyMask {
        var m = BodyMask(width: width, height: height)
        m.fillCircle(cx: 900, cy: 220, radius: 120)              // head, top row 100
        m.fillRect(x0: 860, x1: 940, y0: 330, y1: 424)           // neck
        m.fillRect(x0: 650, x1: 1150, y0: 400, y1: 1036)         // torso, 500 px wide
        m.fillRect(x0: 0, x1: width, y0: 700, y1: 860, value: 0) // waist indent rows
        m.fillRect(x0: 750, x1: 1050, y0: 700, y1: 860)          // waist, 300 px
        m.fillRect(x0: 640, x1: 1160, y0: 950, y1: 1100)         // hips, 520 px
        if tPose {
            m.fillRect(x0: 1150, x1: 1470, y0: 374, y1: 474); m.fillRect(x0: 1470, x1: 1770, y0: 384, y1: 464)
            m.fillRect(x0: 330, x1: 650, y0: 374, y1: 474); m.fillRect(x0: 30, x1: 330, y0: 384, y1: 464)
        } else {
            m.fillRect(x0: 1100, x1: 1200, y0: 380, y1: 744); m.fillRect(x0: 1110, x1: 1190, y0: 744, y1: 1044)
            m.fillRect(x0: 600, x1: 700, y0: 380, y1: 744); m.fillRect(x0: 610, x1: 690, y0: 744, y1: 1044)
        }
        for cx in [1050, 750] {
            m.fillRect(x0: cx - 90, x1: cx + 90, y0: 1036, y1: 1486)   // thigh 180 px
            m.fillRect(x0: cx - 60, x1: cx + 60, y0: 1486, y1: 1900)   // calf 120 px
            m.fillRect(x0: cx - 90, x1: cx + 110, y0: 1860, y1: 1900)  // foot, sole row 1899
        }
        return m
    }

    static func sideMask() -> BodyMask {
        var m = BodyMask(width: width, height: height)
        m.fillCircle(cx: 900, cy: 220, radius: 120)
        m.fillRect(x0: 860, x1: 940, y0: 330, y1: 424)
        m.fillRect(x0: 780, x1: 1020, y0: 400, y1: 1036)         // torso depth 240
        m.fillRect(x0: 0, x1: width, y0: 700, y1: 860, value: 0)
        m.fillRect(x0: 800, x1: 1000, y0: 700, y1: 860)          // waist depth 200
        m.fillRect(x0: 760, x1: 1040, y0: 950, y1: 1100)         // hips depth 280
        m.fillRect(x0: 820, x1: 980, y0: 1036, y1: 1486)
        m.fillRect(x0: 850, x1: 950, y0: 1486, y1: 1900)
        m.fillRect(x0: 820, x1: 1080, y0: 1860, y1: 1900)
        return m
    }

    static func keypoints(_ points: [BodyJoint: (Double, Double)], confidence: Double = 0.95) -> BodyKeypoints {
        BodyKeypoints(imageWidth: width, imageHeight: height,
                      joints: points.map { BodyKeypoint(joint: $0.key, x: $0.value.0, y: $0.value.1, confidence: confidence) })
    }

    static let frontPoints: [BodyJoint: (Double, Double)] = [
        .nose: (900, 240), .leftShoulder: (1150, 424), .rightShoulder: (650, 424),
        .leftElbow: (1150, 744), .rightElbow: (650, 744), .leftWrist: (1150, 1004), .rightWrist: (650, 1004),
        .leftHip: (1050, 1036), .rightHip: (750, 1036), .leftKnee: (1050, 1486), .rightKnee: (750, 1486),
        .leftAnkle: (1050, 1886), .rightAnkle: (750, 1886)
    ]

    static var tPosePoints: [BodyJoint: (Double, Double)] {
        var p = frontPoints
        p[.leftElbow] = (1470, 424); p[.rightElbow] = (330, 424)
        p[.leftWrist] = (1730, 424); p[.rightWrist] = (70, 424)
        return p
    }

    static let sidePoints: [BodyJoint: (Double, Double)] = [
        .nose: (900, 240), .leftShoulder: (900, 424), .rightShoulder: (900, 424),
        .leftElbow: (900, 744), .rightElbow: (900, 744), .leftWrist: (900, 1004), .rightWrist: (900, 1004),
        .leftHip: (900, 1036), .rightHip: (900, 1036), .leftKnee: (900, 1486), .rightKnee: (900, 1486),
        .leftAnkle: (900, 1886), .rightAnkle: (900, 1886)
    ]

    /// Front points with the legs out of frame (photo cropped at the hips).
    static var upperBodyPoints: [BodyJoint: (Double, Double)] {
        var p = frontPoints
        for joint in [BodyJoint.leftKnee, .rightKnee, .leftAnkle, .rightAnkle] { p[joint] = nil }
        return p
    }

    /// Nose and shoulders only (a selfie-style photo), elbows visible, no wrists.
    static var headAndShouldersPoints: [BodyJoint: (Double, Double)] {
        [.nose: (900, 240), .leftShoulder: (1150, 424), .rightShoulder: (650, 424), .leftElbow: (1150, 744), .rightElbow: (650, 744)]
    }

    /// Mask of the front figure cut off below row `y` (what a cropped photo's segmentation looks like).
    static func croppedFrontMask(below y: Int) -> BodyMask {
        var m = frontMask(tPose: false)
        m.fillRect(x0: 0, x1: width, y0: y, y1: height, value: 0)
        return m
    }

    static func upperBody() -> PoseObservation {
        PoseObservation(poseType: .frontArmsDown, keypoints: keypoints(upperBodyPoints), mask: croppedFrontMask(below: 1150), framing: .upperBody)
    }

    static func headAndShoulders() -> PoseObservation {
        PoseObservation(poseType: .frontArmsDown, keypoints: keypoints(headAndShouldersPoints), mask: croppedFrontMask(below: 800),
                        framing: .headAndShoulders)
    }

    static func front(withMask: Bool = true) -> PoseObservation {
        PoseObservation(poseType: .frontArmsDown, keypoints: keypoints(frontPoints), mask: withMask ? frontMask(tPose: false) : nil)
    }

    static func tPose() -> PoseObservation {
        PoseObservation(poseType: .frontArmsOut, keypoints: keypoints(tPosePoints), mask: frontMask(tPose: true))
    }

    static func side() -> PoseObservation {
        PoseObservation(poseType: .sideLeft, keypoints: keypoints(sidePoints), mask: sideMask())
    }

    static func input(front: PoseObservation? = SyntheticFigure.front(), tPose: PoseObservation? = SyntheticFigure.tPose(),
                      side: PoseObservation? = SyntheticFigure.side(), sex: BiologicalSex = .male) -> BodyScanInput {
        BodyScanInput(front: front, tPose: tPose, side: side, heightCm: heightCm, weightKg: weightKg, sex: sex, age: 30)
    }
}

final class BodyMeasurementTests: XCTestCase {
    private func value(_ m: BodyMeasurements, _ metric: BodyMetric, file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard let v = m.value(metric) else {
            XCTFail("\(metric) missing", file: file, line: line)
            return .nan
        }
        return v
    }

    // MARK: - Scale

    func testScaleFromMaskIsTenPixelsPerCentimetre() throws {
        let scale = try XCTUnwrap(BodyMeasurementEngine.scale(for: SyntheticFigure.front(), heightCm: 180))
        XCTAssertEqual(scale.pxPerCm, 10, accuracy: 0.01)
        XCTAssertEqual(scale.source, "mask")
    }

    func testScaleFallsBackToNoseAnkleFactorWithoutMask() throws {
        let scale = try XCTUnwrap(BodyMeasurementEngine.scale(for: SyntheticFigure.front(withMask: false), heightCm: 180))
        // (1886 − 240) × 1.13 / 180
        XCTAssertEqual(scale.pxPerCm, 1646 * 1.13 / 180, accuracy: 0.001)
        XCTAssertEqual(scale.source, "keypoints")
    }

    func testScaleRejectsImplausibleMaskHeight() throws {
        // A mask that is only the torso: top of head is missing, so mask height ≪ nose→ankle × 1.05.
        var tiny = BodyMask(width: SyntheticFigure.width, height: SyntheticFigure.height)
        tiny.fillRect(x0: 650, x1: 1150, y0: 400, y1: 1036)
        let obs = PoseObservation(poseType: .frontArmsDown, keypoints: SyntheticFigure.keypoints(SyntheticFigure.frontPoints), mask: tiny)
        let scale = try XCTUnwrap(BodyMeasurementEngine.scale(for: obs, heightCm: 180))
        XCTAssertEqual(scale.source, "keypoints")
    }

    // MARK: - Lengths

    func testLengthsFromKeypoints() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(m, .leftUpperArm), 32, accuracy: 0.05)
        XCTAssertEqual(value(m, .rightUpperArm), 32, accuracy: 0.05)
        XCTAssertEqual(value(m, .leftForearm), 26, accuracy: 0.05)
        XCTAssertEqual(value(m, .leftArm), 58, accuracy: 0.05)
        XCTAssertEqual(value(m, .leftThigh), 45, accuracy: 0.05)
        XCTAssertEqual(value(m, .leftShin), 40, accuracy: 0.05)
        XCTAssertEqual(value(m, .rightLeg), 85, accuracy: 0.05)
        XCTAssertEqual(value(m, .torso), 61.2, accuracy: 0.05)
        XCTAssertEqual(value(m, .shoulderWidth), 50, accuracy: 0.05)
        XCTAssertEqual(value(m, .hipWidth), 30, accuracy: 0.05)
        XCTAssertEqual(value(m, .torsoToLegRatio), 61.2 / 85, accuracy: 0.001)
        XCTAssertEqual(value(m, .shoulderToHipRatio), 50 / 30, accuracy: 0.001)
        XCTAssertEqual(m.source(.torso), .frontArmsDown)
    }

    func testArmSpanAndApeIndexOnlyFromTPose() {
        let withT = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(withT, .armSpan), 166, accuracy: 0.05)
        XCTAssertEqual(value(withT, .apeIndex), 166.0 / 180.0, accuracy: 0.001)
        let frontOnly = BodyMeasurementEngine.measure(SyntheticFigure.input(tPose: nil, side: nil))
        XCTAssertNil(frontOnly.value(.armSpan))
        XCTAssertNil(frontOnly.value(.apeIndex))
    }

    // MARK: - Widths

    func testLimbWidthsFromMask() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(m, .leftUpperArmWidth), 10, accuracy: 0.15)
        XCTAssertEqual(value(m, .rightUpperArmWidth), 10, accuracy: 0.15)
        XCTAssertEqual(value(m, .leftForearmWidth), 8, accuracy: 0.15)
        XCTAssertEqual(value(m, .leftThighWidth), 18, accuracy: 0.15)
        XCTAssertEqual(value(m, .rightCalfWidth), 12, accuracy: 0.15)
        XCTAssertEqual(m.source(.leftUpperArmWidth), .frontArmsOut)
        XCTAssertEqual(m.source(.leftThighWidth), .frontArmsDown)
    }

    func testArmWidthsSurviveArmAgainstTorso() {
        // Front-only: the upper arm touches the torso, so one side of the scan never reaches background.
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input(tPose: nil, side: nil))
        XCTAssertEqual(value(m, .leftUpperArmWidth), 10, accuracy: 0.15)
        XCTAssertEqual(value(m, .leftForearmWidth), 8, accuracy: 0.15)
    }

    func testTorsoWidthsAndDepths() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(m, .waistWidth), 30, accuracy: 0.15)
        XCTAssertEqual(value(m, .chestWidth), 50, accuracy: 0.15)
        XCTAssertEqual(value(m, .hipsWidth), 52, accuracy: 0.15)
        XCTAssertEqual(value(m, .neckWidth), 8, accuracy: 0.15)
        XCTAssertEqual(value(m, .waistDepth), 20, accuracy: 0.15)
        XCTAssertEqual(value(m, .chestDepth), 24, accuracy: 0.15)
        XCTAssertEqual(value(m, .hipsDepth), 28, accuracy: 0.15)
        XCTAssertEqual(m.source(.waistWidth), .frontArmsDown)
        XCTAssertEqual(m.source(.chestWidth), .frontArmsOut)
        XCTAssertEqual(m.source(.waistDepth), .sideLeft)
    }

    func testWaistIsMinimumAcrossRows() {
        // Row at 45% (y = 699) is still full torso width; the minimum over 45–70% must pick the indent.
        let mask = SyntheticFigure.frontMask(tPose: false)
        XCTAssertEqual(mask.rowRunWidth(y: 699, xRef: 900, xMin: 720, xMax: 1080), 361)
        XCTAssertEqual(mask.rowRunWidth(y: 730, xRef: 900, xMin: 720, xMax: 1080), 300)
    }

    // MARK: - Circumferences

    func testLimbCircumferencesUseDocumentedFactors() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(m, .leftUpperArmCircumference), Double.pi * 10 * 0.95, accuracy: 0.5)
        XCTAssertEqual(value(m, .leftForearmCircumference), Double.pi * 8 * 0.95, accuracy: 0.5)
        XCTAssertEqual(value(m, .leftThighCircumference), Double.pi * 18, accuracy: 0.5)
        XCTAssertEqual(value(m, .leftCalfCircumference), Double.pi * 12, accuracy: 0.5)
    }

    func testRamanujanEllipsePerimeter() {
        XCTAssertEqual(BodyMeasurementEngine.ellipsePerimeter(width: 30, depth: 20), 79.327, accuracy: 0.01)
        // A circle reduces to π × d.
        XCTAssertEqual(BodyMeasurementEngine.ellipsePerimeter(width: 10, depth: 10), Double.pi * 10, accuracy: 1e-9)
    }

    func testTorsoCircumferencesWithSidePhoto() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(m, .waistCircumference), 79.33, accuracy: 0.5)
        XCTAssertEqual(value(m, .chestCircumference), 119.85, accuracy: 0.5)
        XCTAssertEqual(value(m, .hipsCircumference), 128.51, accuracy: 0.5)
        XCTAssertEqual(m[.waistCircumference]?.confidence, .high)
    }

    func testTorsoCircumferencesWithoutSidePhotoUseDepthRatios() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input(side: nil))
        XCTAssertEqual(value(m, .waistCircumference), 81.59, accuracy: 0.5)   // depth = 0.72 × width
        XCTAssertEqual(value(m, .chestCircumference), 134.56, accuracy: 0.5)  // 0.70
        XCTAssertEqual(value(m, .hipsCircumference), 147.48, accuracy: 0.5)   // 0.80
        XCTAssertEqual(m[.waistCircumference]?.confidence, .medium)
    }

    // MARK: - Composition

    func testRelativeFatMass() {
        XCTAssertEqual(BodyMeasurementEngine.relativeFatMass(heightCm: 180, waistCm: 79.327, sex: .male)!, 18.62, accuracy: 0.05)
        XCTAssertEqual(BodyMeasurementEngine.relativeFatMass(heightCm: 180, waistCm: 79.327, sex: .female)!, 30.62, accuracy: 0.05)
        // Clamped to 3…55.
        XCTAssertEqual(BodyMeasurementEngine.relativeFatMass(heightCm: 180, waistCm: 40, sex: .male), 3)
        XCTAssertEqual(BodyMeasurementEngine.relativeFatMass(heightCm: 150, waistCm: 200, sex: .female), 55)
        XCTAssertNil(BodyMeasurementEngine.relativeFatMass(heightCm: 0, waistCm: 80, sex: .male))
    }

    func testNavyBodyFat() {
        let male = BodyMeasurementEngine.navyBodyFat(heightCm: 180, waistCm: 79.327, neckCm: 23.876, hipsCm: nil, sex: .male)
        XCTAssertEqual(male!, 22.20, accuracy: 0.05)
        XCTAssertNil(BodyMeasurementEngine.navyBodyFat(heightCm: 180, waistCm: 79, neckCm: 24, hipsCm: nil, sex: .female))
        let female = BodyMeasurementEngine.navyBodyFat(heightCm: 180, waistCm: 79.327, neckCm: 23.876, hipsCm: 128.507, sex: .female)
        XCTAssertEqual(female!, 44.28, accuracy: 0.05)
    }

    func testCompositionFromFullScan() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(m, .bodyFatPercent), 18.62, accuracy: 0.15)
        XCTAssertEqual(value(m, .bodyFatPercentRFM), value(m, .bodyFatPercent), accuracy: 1e-9)
        XCTAssertEqual(value(m, .bodyFatPercentNavy), 22.20, accuracy: 0.3)
        XCTAssertEqual(value(m, .leanMassKg), 80 * (1 - 0.1862), accuracy: 0.15)
        XCTAssertEqual(value(m, .fatMassKg) + value(m, .leanMassKg), 80, accuracy: 1e-6)
        XCTAssertEqual(value(m, .waistToHipRatio), 79.33 / 128.51, accuracy: 0.01)
        XCTAssertEqual(value(m, .waistToHeightRatio), 79.33 / 180, accuracy: 0.01)
        // Photo-based body fat is never more than medium confidence.
        XCTAssertEqual(m[.bodyFatPercent]?.confidence, .medium)
    }

    // MARK: - Symmetry

    func testSymmetricFigureHasZeroAsymmetry() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(value(m, .armAsymmetry), 0, accuracy: 1e-6)
        XCTAssertEqual(value(m, .legAsymmetry), 0, accuracy: 1e-6)
        XCTAssertEqual(value(m, .thighAsymmetry), 0, accuracy: 1e-6)
        XCTAssertEqual(value(m, .shoulderAsymmetry), 0, accuracy: 1e-6)
    }

    func testAsymmetryPercent() {
        XCTAssertEqual(BodyMeasurementEngine.asymmetryPercent(58, 60), 2 / 59 * 100, accuracy: 1e-9)
        XCTAssertEqual(BodyMeasurementEngine.asymmetryPercent(0, 0), 0)
    }

    func testShorterLeftArmShowsUp() {
        var points = SyntheticFigure.frontPoints
        points[.leftWrist] = (1150, 984) // forearm 24 cm instead of 26
        let obs = PoseObservation(poseType: .frontArmsDown, keypoints: SyntheticFigure.keypoints(points), mask: SyntheticFigure.frontMask(tPose: false))
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input(front: obs, tPose: nil, side: nil))
        XCTAssertEqual(value(m, .armAsymmetry), BodyMeasurementEngine.asymmetryPercent(56, 58), accuracy: 0.01)
    }

    // MARK: - Confidence

    func testConfidenceFollowsJointConfidenceAndPoseMatch() {
        let high = BodyMeasurementEngine.measure(SyntheticFigure.input())
        XCTAssertEqual(high[.leftUpperArm]?.confidence, .high)
        XCTAssertEqual(high[.leftThighWidth]?.confidence, .high)
        XCTAssertEqual(high.overallConfidence, .medium) // body fat caps the key-metric minimum

        let shaky = PoseObservation(poseType: .frontArmsDown, keypoints: SyntheticFigure.keypoints(SyntheticFigure.frontPoints, confidence: 0.5),
                                    mask: SyntheticFigure.frontMask(tPose: false))
        let medium = BodyMeasurementEngine.measure(SyntheticFigure.input(front: shaky, tPose: nil, side: nil))
        XCTAssertEqual(medium[.leftUpperArm]?.confidence, .medium)

        let mismatched = PoseObservation(poseType: .frontArmsDown, keypoints: SyntheticFigure.keypoints(SyntheticFigure.frontPoints),
                                         mask: SyntheticFigure.frontMask(tPose: false), maskQuality: 1, poseMatched: false)
        let capped = BodyMeasurementEngine.measure(SyntheticFigure.input(front: mismatched, tPose: nil, side: nil))
        XCTAssertEqual(capped[.leftUpperArm]?.confidence, .medium)

        let noMask = BodyMeasurementEngine.measure(SyntheticFigure.input(front: SyntheticFigure.front(withMask: false), tPose: nil, side: nil))
        XCTAssertNil(noMask.value(.waistWidth))
        XCTAssertNotNil(noMask.value(.torso))
    }

    // MARK: - Pose validation

    func testPoseValidatorMatchesPoses() {
        let front = SyntheticFigure.keypoints(SyntheticFigure.frontPoints)
        let tPose = SyntheticFigure.keypoints(SyntheticFigure.tPosePoints)
        let side = SyntheticFigure.keypoints(SyntheticFigure.sidePoints)
        XCTAssertTrue(PoseValidator.validate(front, poseType: .frontArmsDown).poseMatched)
        XCTAssertFalse(PoseValidator.validate(front, poseType: .frontArmsOut).poseMatched)
        XCTAssertFalse(PoseValidator.validate(front, poseType: .sideLeft).poseMatched)
        XCTAssertTrue(PoseValidator.validate(tPose, poseType: .frontArmsOut).poseMatched)
        XCTAssertFalse(PoseValidator.validate(tPose, poseType: .frontArmsDown).poseMatched)
        XCTAssertTrue(PoseValidator.validate(side, poseType: .sideLeft).poseMatched)
        XCTAssertEqual(PoseValidator.validate(front, poseType: .frontArmsOut).message, PoseValidator.mismatchMessage(for: .frontArmsOut))
    }

    func testPoseValidatorDetectsFraming() {
        let full = PoseValidator.validate(SyntheticFigure.keypoints(SyntheticFigure.frontPoints), poseType: .frontArmsDown)
        XCTAssertEqual(full.framing, .fullBody)
        XCTAssertTrue(full.isFullBody)

        // No ankles: head to hips. Still a valid arms-down photo, no warning.
        let upper = PoseValidator.validate(SyntheticFigure.keypoints(SyntheticFigure.upperBodyPoints), poseType: .frontArmsDown)
        XCTAssertEqual(upper.framing, .upperBody)
        XCTAssertFalse(upper.isFullBody)
        XCTAssertTrue(upper.poseMatched)
        XCTAssertNil(upper.message)

        // Head and shoulders only, no wrists: accepted as arms-down because the person faces the camera,
        // but a T-pose cannot be confirmed without wrists.
        let head = PoseValidator.validate(SyntheticFigure.keypoints(SyntheticFigure.headAndShouldersPoints), poseType: .frontArmsDown)
        XCTAssertEqual(head.framing, .headAndShoulders)
        XCTAssertTrue(head.poseMatched)
        XCTAssertFalse(PoseValidator.validate(SyntheticFigure.keypoints(SyntheticFigure.headAndShouldersPoints), poseType: .frontArmsOut).poseMatched)

        // A side view of the upper body only needs narrow shoulders.
        var sideUpper = SyntheticFigure.sidePoints
        for joint in [BodyJoint.leftKnee, .rightKnee, .leftAnkle, .rightAnkle] { sideUpper[joint] = nil }
        XCTAssertTrue(PoseValidator.validate(SyntheticFigure.keypoints(sideUpper), poseType: .sideLeft).poseMatched)

        // Ankles Vision guessed below the bottom edge of a cropped photo don't make it a full-body photo.
        var offFrame = SyntheticFigure.frontPoints
        offFrame[.leftAnkle] = (1050, 2100)
        offFrame[.rightAnkle] = (750, 2100)
        XCTAssertEqual(PoseValidator.validate(SyntheticFigure.keypoints(offFrame), poseType: .frontArmsDown).framing, .upperBody)

        // Without the head and shoulders there is nothing to work with.
        var noShoulders = SyntheticFigure.frontPoints
        noShoulders[.leftShoulder] = nil
        let missing = PoseValidator.validate(SyntheticFigure.keypoints(noShoulders), poseType: .frontArmsDown)
        XCTAssertNil(missing.framing)
        XCTAssertEqual(missing.message, PoseValidator.headAndShouldersMessage)
        let empty = PoseValidator.validate(BodyKeypoints(imageWidth: 10, imageHeight: 10, joints: []), poseType: .frontArmsDown)
        XCTAssertEqual(empty.message, PoseValidator.noPoseMessage)
    }

    func testBodyScaleEstimatesFromWhatIsVisible() {
        let full = PoseValidator.bodyScale(SyntheticFigure.keypoints(SyntheticFigure.frontPoints))
        XCTAssertEqual(full, 1646, accuracy: 0.01)
        // Nose → hip (796 px) × 2.55 × 0.885 ≈ 1796: the right order of magnitude for threshold tests.
        let upper = PoseValidator.bodyScale(SyntheticFigure.keypoints(SyntheticFigure.upperBodyPoints))
        XCTAssertEqual(upper / full, 1, accuracy: 0.15)
        let head = PoseValidator.bodyScale(SyntheticFigure.keypoints(SyntheticFigure.headAndShouldersPoints))
        XCTAssertEqual(head / full, 1.2, accuracy: 0.2)
    }

    func testKeypointsRestrictedToFramingDropExtrapolatedJoints() {
        let kp = SyntheticFigure.keypoints(SyntheticFigure.frontPoints)
        let upper = kp.restricted(to: .upperBody)
        XCTAssertNil(upper[.leftKnee])
        XCTAssertNil(upper[.rightAnkle])
        XCTAssertNotNil(upper[.leftHip])
        let head = kp.restricted(to: .headAndShoulders)
        XCTAssertNil(head[.leftHip])
        XCTAssertNotNil(head[.leftWrist])
        XCTAssertEqual(kp.restricted(to: .fullBody), kp)
    }

    // MARK: - Partial framing

    func testUpperBodyScanScalesFromProportionsAtLowConfidence() throws {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input(front: SyntheticFigure.upperBody(), tPose: nil, side: nil))
        XCTAssertEqual(m.scaleSource, "noseHipEstimate")
        XCTAssertEqual(m.framing, .upperBody)
        // Nose → hip is 796 px; height ≈ 796 × 2.55 cm → 11.28 px/cm instead of the true 10.
        XCTAssertEqual(try XCTUnwrap(m.frontPxPerCm), 796 * 2.55 / 180, accuracy: 0.001)
        XCTAssertNotNil(m.value(.waistCircumference))
        XCTAssertNotNil(m.value(.bodyFatPercent))
        XCTAssertNotNil(m.value(.shoulderWidth))
        XCTAssertNil(m.value(.leftThigh), "legs are not in the photo")
        XCTAssertNil(m.value(.leftCalfCircumference))
        XCTAssertNil(m.value(.torsoToLegRatio))
        XCTAssertEqual(m[.shoulderWidth]?.confidence, .low, "population-proportion scale caps everything at low")
        XCTAssertEqual(m[.waistCircumference]?.confidence, .low)
    }

    func testUpperBodyScanUsesReferenceShouldersFromEarlierScan() throws {
        var input = SyntheticFigure.input(front: SyntheticFigure.upperBody(), tPose: nil, side: nil)
        input.referenceShoulderWidthCm = 50 // what the full-body figure measures
        let m = BodyMeasurementEngine.measure(input)
        XCTAssertEqual(m.scaleSource, "referenceShoulders")
        XCTAssertEqual(try XCTUnwrap(m.frontPxPerCm), 10, accuracy: 0.001)
        let full = BodyMeasurementEngine.measure(SyntheticFigure.input(tPose: nil, side: nil))
        XCTAssertEqual(try XCTUnwrap(m.value(.waistCircumference)), try XCTUnwrap(full.value(.waistCircumference)), accuracy: 0.01)
        XCTAssertEqual(m[.shoulderWidth]?.confidence, .medium, "a reference scale is never better than medium")
    }

    func testPartialTPoseIsCalibratedByFullBodyFrontInSameScan() throws {
        var points = SyntheticFigure.tPosePoints
        for joint in [BodyJoint.leftKnee, .rightKnee, .leftAnkle, .rightAnkle] { points[joint] = nil }
        let partialT = PoseObservation(poseType: .frontArmsOut, keypoints: SyntheticFigure.keypoints(points),
                                       mask: SyntheticFigure.frontMask(tPose: true), framing: .upperBody)
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input(tPose: partialT, side: nil))
        XCTAssertEqual(m.scaleSource, "mask", "the front photo still sets the headline scale")
        XCTAssertEqual(m.framing, .fullBody)
        // Arm span comes from the T-pose, scaled by the front photo's 50 cm shoulder width → 10 px/cm.
        XCTAssertEqual(try XCTUnwrap(m.value(.armSpan)), 166, accuracy: 0.05)
        XCTAssertEqual(m[.armSpan]?.confidence, .medium)
        XCTAssertNotNil(m.value(.leftThigh), "legs still come from the full-body front photo")
    }

    func testHeadAndShouldersScanGivesShoulderWidthOnly() {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input(front: SyntheticFigure.headAndShoulders(), tPose: nil, side: nil))
        XCTAssertEqual(m.scaleSource, "shoulderEstimate")
        XCTAssertEqual(m.framing, .headAndShoulders)
        XCTAssertNotNil(m.value(.shoulderWidth))
        XCTAssertNil(m.value(.waistCircumference))
        XCTAssertNil(m.value(.bodyFatPercent))
        XCTAssertNil(m.value(.torso))
    }

    func testSideViewWithoutHipsHasNoScale() {
        var points = SyntheticFigure.sidePoints
        for joint in [BodyJoint.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle] { points[joint] = nil }
        let obs = PoseObservation(poseType: .sideLeft, keypoints: SyntheticFigure.keypoints(points), mask: nil, framing: .headAndShoulders)
        XCTAssertNil(BodyMeasurementEngine.scale(for: obs, heightCm: 180, referenceShoulderWidthCm: 50),
                     "a foreshortened side shoulder span must not be used as a scale")
    }

    func testMaskQualityHighForMatchingMask() {
        let kp = SyntheticFigure.keypoints(SyntheticFigure.frontPoints)
        XCTAssertGreaterThan(PoseValidator.maskQuality(SyntheticFigure.frontMask(tPose: false), keypoints: kp), 0.8)
        XCTAssertFalse(PoseValidator.looksLikeBusyBackground(SyntheticFigure.frontMask(tPose: false), keypoints: kp))
        // A big blob far from the body counts as a busy background.
        var busy = SyntheticFigure.frontMask(tPose: false)
        busy.fillRect(x0: 0, x1: 500, y0: 0, y1: 2000)
        XCTAssertTrue(PoseValidator.looksLikeBusyBackground(busy, keypoints: kp))
    }

    // MARK: - Mask helpers

    func testMaskResampleAndRuns() {
        var small = BodyMask(width: 4, height: 4)
        small.fillRect(x0: 1, x1: 3, y0: 1, y1: 3)
        let big = small.resampled(toWidth: 8, height: 8)
        XCTAssertTrue(big.isForeground(2, 2))
        XCTAssertTrue(big.isForeground(5, 5))
        XCTAssertFalse(big.isForeground(0, 0))
        XCTAssertFalse(big.isForeground(7, 7))
        XCTAssertEqual(big.foregroundCount, 16)
        XCTAssertEqual(small.topForegroundRow(columns: 0, 3), 1)
        XCTAssertEqual(small.bottomForegroundRow(columns: 0, 3), 2)
        XCTAssertNil(small.rowRunWidth(y: 0, xRef: 1, xMin: 0, xMax: 3))
        XCTAssertEqual(small.rowRunWidth(y: 1, xRef: 2, xMin: 0, xMax: 3), 2)
    }

    func testMeasurementsRoundTripThroughJSON() throws {
        let m = BodyMeasurementEngine.measure(SyntheticFigure.input())
        let data = try m.encoded()
        let back = try XCTUnwrap(BodyMeasurements.decode(data))
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.poses, [.frontArmsDown, .frontArmsOut, .sideLeft])
    }
}
