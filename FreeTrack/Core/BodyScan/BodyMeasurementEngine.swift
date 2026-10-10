import Foundation

/// Pure measurement math: joints + person mask + height → lengths, widths, circumferences, body composition
/// and symmetry. Ported from FreeFit's `analyzer.py` and extended with mask-based widths. No UI, no Vision.
///
/// Conventions: pixel coordinates have y pointing down; everything returned is metric.
enum BodyMeasurementEngine {
    static let version = 1

    // MARK: - Documented constants

    /// Limb circumference ≈ π × visible width × k. Arms are slightly flatter than round (k < 1).
    static let armCircumferenceFactor = 0.95
    /// Thighs and calves are close to circular in cross-section.
    static let legCircumferenceFactor = 1.0
    /// Neck is nearly round; the front width slightly overstates the lateral diameter.
    static let neckCircumferenceFactor = 0.95
    /// Torso depth ÷ front width used when there is no side photo (typical adult proportions).
    static let waistDepthRatio = 0.72
    static let chestDepthRatio = 0.70
    static let hipsDepthRatio = 0.80
    /// Fallback height scale: nose → ankle is ≈ 88% of standing height (nose ≈ 0.925 H, ankle ≈ 0.04 H).
    /// FreeFit used nose → heel × 1.08; Vision has no heel joint, so the factor is larger.
    static let noseToAnkleHeightFactor = 1.13
    /// Mask-derived height is only trusted when it is between these multiples of the nose → ankle distance.
    static let maskHeightPlausibleRange = 1.05...1.30
    static let bodyFatRange = 3.0...55.0

    // MARK: - Entry point

    static func measure(_ input: BodyScanInput) -> BodyMeasurements {
        var m = BodyMeasurements()
        m.heightCm = input.heightCm
        m.weightKg = input.weightKg
        m.sexRaw = input.sex.rawValue
        m.age = input.age
        m.poses = input.observations.map(\.poseType)

        let front = input.front.flatMap { Frame($0, heightCm: input.heightCm) }
        let tPose = input.tPose.flatMap { Frame($0, heightCm: input.heightCm) }
        let side = input.side.flatMap { Frame($0, heightCm: input.heightCm) }

        if let f = front {
            m.frontPxPerCm = f.pxPerCm
            m.scaleSource = f.scaleSource
        } else if let t = tPose {
            m.frontPxPerCm = t.pxPerCm
            m.scaleSource = t.scaleSource
        }

        // Lengths and ratios come from the front pose, else the T-pose (never the side: one plane only).
        if let primary = front ?? tPose {
            measureLengths(primary, into: &m)
        }
        if let t = tPose {
            measureArmSpan(t, into: &m)
        }
        measureSymmetry(front: front, tPose: tPose, into: &m)

        // Mask widths. Arms are cleanest with the arms out; legs and waist with the arms down.
        if let armsFrame = tPose ?? front { measureArmWidths(armsFrame, into: &m) }
        if let legsFrame = front ?? tPose { measureLegWidths(legsFrame, into: &m) }
        measureTorsoWidths(front: front, tPose: tPose, into: &m)
        if let s = side { measureSideDepths(s, into: &m) }

        measureCircumferences(into: &m, hasSide: side != nil)
        measureComposition(input: input, into: &m)
        return m
    }

    // MARK: - Frame

    /// One observation with its pixel scale resolved.
    struct Frame {
        let observation: PoseObservation
        let pxPerCm: Double
        let scaleSource: String

        var keypoints: BodyKeypoints { observation.keypoints }
        var mask: BodyMask? { observation.mask }
        var poseType: BodyPoseType { observation.poseType }

        init?(_ observation: PoseObservation, heightCm: Double) {
            guard let scale = BodyMeasurementEngine.scale(for: observation, heightCm: heightCm) else { return nil }
            self.observation = observation
            self.pxPerCm = scale.pxPerCm
            self.scaleSource = scale.source
        }

        func cm(_ px: Double) -> Double { px / pxPerCm }

        func distanceCm(_ a: BodyJoint, _ b: BodyJoint) -> Double? {
            guard let pa = keypoints.point(a), let pb = keypoints.point(b) else { return nil }
            return cm(BodyPoint.distance(pa, pb))
        }

        /// y of the row `fraction` of the way from the shoulder line to the hip line.
        func torsoRow(_ fraction: Double) -> Int? {
            guard let s = keypoints.shoulderMid, let h = keypoints.hipMid else { return nil }
            return Int((s.y + (h.y - s.y) * fraction).rounded())
        }

        /// Confidence for a joint-only measurement.
        func lengthConfidence(_ joints: [BodyJoint]) -> MeasurementConfidence {
            let c = keypoints.minConfidence(joints)
            let level: MeasurementConfidence = c >= 0.7 ? .high : (c >= 0.4 ? .medium : .low)
            return observation.poseMatched ? level : min(level, .medium)
        }

        /// Confidence for a mask-derived measurement.
        func maskConfidence(_ joints: [BodyJoint]) -> MeasurementConfidence {
            let c = keypoints.minConfidence(joints)
            let q = observation.maskQuality
            let level: MeasurementConfidence
            if q >= 0.7, c >= 0.6 { level = .high } else if q >= 0.4, c >= 0.4 { level = .medium } else { level = .low }
            return observation.poseMatched ? level : min(level, .medium)
        }
    }

    // MARK: - Scale

    /// Pixels per centimetre. Prefers the mask (top of head → sole) and falls back to nose → ankle × 1.13.
    static func scale(for observation: PoseObservation, heightCm: Double) -> (pxPerCm: Double, source: String)? {
        guard heightCm > 0 else { return nil }
        let kp = observation.keypoints
        guard let nose = kp.point(.nose), let ankleMid = kp.ankleMid else { return nil }
        let noseToAnkle = ankleMid.y - nose.y
        guard noseToAnkle > 1 else { return nil }

        if let mask = observation.mask {
            let shoulderWidth = (kp.point(.leftShoulder).flatMap { l in kp.point(.rightShoulder).map { BodyPoint.distance(l, $0) } }) ?? 0
            let halfWindow = max(shoulderWidth / 2, noseToAnkle * 0.05)
            let top = mask.topForegroundRow(columns: Int(nose.x - halfWindow), Int(nose.x + halfWindow))
            let ankleWindow = max(shoulderWidth / 4, noseToAnkle * 0.03)
            let bottoms = [BodyJoint.leftAnkle, .rightAnkle].compactMap { joint -> Int? in
                guard let p = kp.point(joint) else { return nil }
                return mask.bottomForegroundRow(columns: Int(p.x - ankleWindow), Int(p.x + ankleWindow))
            }
            if let top, let bottom = bottoms.max(), bottom > top {
                let heightPx = Double(bottom - top + 1)
                if maskHeightPlausibleRange.contains(heightPx / noseToAnkle) {
                    return (heightPx / heightCm, "mask")
                }
            }
        }
        return (noseToAnkle * noseToAnkleHeightFactor / heightCm, "keypoints")
    }

    // MARK: - Lengths

    private static func measureLengths(_ f: Frame, into m: inout BodyMeasurements) {
        let pose = f.poseType
        func put(_ metric: BodyMetric, _ a: BodyJoint, _ b: BodyJoint) {
            m.set(metric, f.distanceCm(a, b), f.lengthConfidence([a, b]), source: pose)
        }
        put(.leftUpperArm, .leftShoulder, .leftElbow)
        put(.rightUpperArm, .rightShoulder, .rightElbow)
        put(.leftForearm, .leftElbow, .leftWrist)
        put(.rightForearm, .rightElbow, .rightWrist)
        put(.leftThigh, .leftHip, .leftKnee)
        put(.rightThigh, .rightHip, .rightKnee)
        put(.leftShin, .leftKnee, .leftAnkle)
        put(.rightShin, .rightKnee, .rightAnkle)
        put(.shoulderWidth, .leftShoulder, .rightShoulder)
        put(.hipWidth, .leftHip, .rightHip)

        if let ua = m.value(.leftUpperArm), let fa = m.value(.leftForearm) {
            m.set(.leftArm, ua + fa, f.lengthConfidence([.leftShoulder, .leftElbow, .leftWrist]), source: pose)
        }
        if let ua = m.value(.rightUpperArm), let fa = m.value(.rightForearm) {
            m.set(.rightArm, ua + fa, f.lengthConfidence([.rightShoulder, .rightElbow, .rightWrist]), source: pose)
        }
        if let th = m.value(.leftThigh), let sh = m.value(.leftShin) {
            m.set(.leftLeg, th + sh, f.lengthConfidence([.leftHip, .leftKnee, .leftAnkle]), source: pose)
        }
        if let th = m.value(.rightThigh), let sh = m.value(.rightShin) {
            m.set(.rightLeg, th + sh, f.lengthConfidence([.rightHip, .rightKnee, .rightAnkle]), source: pose)
        }
        if let s = f.keypoints.shoulderMid, let h = f.keypoints.hipMid {
            let torso = f.cm(BodyPoint.distance(s, h))
            let conf = f.lengthConfidence([.leftShoulder, .rightShoulder, .leftHip, .rightHip])
            m.set(.torso, torso, conf, source: pose)
            if let ll = m.value(.leftLeg), let rl = m.value(.rightLeg), (ll + rl) > 0 {
                m.set(.torsoToLegRatio, torso / ((ll + rl) / 2), conf, source: pose)
            }
        }
        if let sw = m.value(.shoulderWidth), let hw = m.value(.hipWidth), hw > 0 {
            m.set(.shoulderToHipRatio, sw / hw, f.lengthConfidence([.leftShoulder, .rightShoulder, .leftHip, .rightHip]), source: pose)
        }
    }

    /// Arm span and ape index are only meaningful with the arms extended (FreeFit: ~0.3 otherwise).
    private static func measureArmSpan(_ t: Frame, into m: inout BodyMeasurements) {
        guard t.poseType == .frontArmsOut, let span = t.distanceCm(.leftWrist, .rightWrist) else { return }
        let conf = t.lengthConfidence([.leftWrist, .rightWrist])
        m.set(.armSpan, span, conf, source: .frontArmsOut)
        if m.heightCm > 0 { m.set(.apeIndex, span / m.heightCm, conf, source: .frontArmsOut) }
    }

    // MARK: - Symmetry

    static func asymmetryPercent(_ a: Double, _ b: Double) -> Double {
        let avg = (a + b) / 2
        return avg > 0 ? abs(a - b) / avg * 100 : 0
    }

    private static func measureSymmetry(front: Frame?, tPose: Frame?, into m: inout BodyMeasurements) {
        let frames = [front, tPose].compactMap { $0 }
        guard !frames.isEmpty else { return }
        func average(_ metric: BodyMetric, _ value: (Frame) -> Double?, joints: [BodyJoint]) {
            let vals = frames.compactMap(value)
            guard !vals.isEmpty else { return }
            let conf = frames.map { $0.lengthConfidence(joints) }.min() ?? .low
            m.set(metric, vals.reduce(0, +) / Double(vals.count), conf, source: frames[0].poseType)
        }
        average(.armAsymmetry, { f in
            guard let l1 = f.distanceCm(.leftShoulder, .leftElbow), let l2 = f.distanceCm(.leftElbow, .leftWrist),
                  let r1 = f.distanceCm(.rightShoulder, .rightElbow), let r2 = f.distanceCm(.rightElbow, .rightWrist) else { return nil }
            return asymmetryPercent(l1 + l2, r1 + r2)
        }, joints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist])
        average(.legAsymmetry, { f in
            guard let l1 = f.distanceCm(.leftHip, .leftKnee), let l2 = f.distanceCm(.leftKnee, .leftAnkle),
                  let r1 = f.distanceCm(.rightHip, .rightKnee), let r2 = f.distanceCm(.rightKnee, .rightAnkle) else { return nil }
            return asymmetryPercent(l1 + l2, r1 + r2)
        }, joints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle])
        average(.thighAsymmetry, { f in
            guard let l = f.distanceCm(.leftHip, .leftKnee), let r = f.distanceCm(.rightHip, .rightKnee) else { return nil }
            return asymmetryPercent(l, r)
        }, joints: [.leftHip, .leftKnee, .rightHip, .rightKnee])
        average(.shoulderAsymmetry, { f in
            guard let mid = f.keypoints.shoulderMid, let l = f.keypoints.point(.leftShoulder), let r = f.keypoints.point(.rightShoulder) else { return nil }
            return asymmetryPercent(BodyPoint.distance(l, mid), BodyPoint.distance(r, mid))
        }, joints: [.leftShoulder, .rightShoulder])
    }

    // MARK: - Limb widths

    private static func measureArmWidths(_ f: Frame, into m: inout BodyMeasurements) {
        guard let mask = f.mask else { return }
        func put(_ metric: BodyMetric, _ a: BodyJoint, _ b: BodyJoint) {
            guard let pa = f.keypoints.point(a), let pb = f.keypoints.point(b),
                  let px = mask.limbWidth(from: pa, to: pb) else { return }
            m.set(metric, f.cm(px), f.maskConfidence([a, b]), source: f.poseType)
        }
        put(.leftUpperArmWidth, .leftShoulder, .leftElbow)
        put(.rightUpperArmWidth, .rightShoulder, .rightElbow)
        put(.leftForearmWidth, .leftElbow, .leftWrist)
        put(.rightForearmWidth, .rightElbow, .rightWrist)
    }

    private static func measureLegWidths(_ f: Frame, into m: inout BodyMeasurements) {
        guard let mask = f.mask else { return }
        func put(_ metric: BodyMetric, _ a: BodyJoint, _ b: BodyJoint) {
            guard let pa = f.keypoints.point(a), let pb = f.keypoints.point(b),
                  let px = mask.limbWidth(from: pa, to: pb) else { return }
            m.set(metric, f.cm(px), f.maskConfidence([a, b]), source: f.poseType)
        }
        put(.leftThighWidth, .leftHip, .leftKnee)
        put(.rightThighWidth, .rightHip, .rightKnee)
        put(.leftCalfWidth, .leftKnee, .leftAnkle)
        put(.rightCalfWidth, .rightKnee, .rightAnkle)
    }

    // MARK: - Torso widths

    /// Row scans across the torso. Waist: minimum width between 45–70% shoulder→hip inside the hip-span window
    /// (arms down, as in analyzer.py). Chest (25%) and hips (widest row 85–110%) prefer the T-pose because the
    /// hanging arms merge with the torso at those rows.
    private static func measureTorsoWidths(front: Frame?, tPose: Frame?, into m: inout BodyMeasurements) {
        let torsoJoints: [BodyJoint] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]

        if let f = front ?? tPose, let mask = f.mask, let hipMid = f.keypoints.hipMid,
           let lh = f.keypoints.point(.leftHip), let rh = f.keypoints.point(.rightHip) {
            let span = abs(lh.x - rh.x)
            let xMin = Int(min(lh.x, rh.x) - span * 0.10), xMax = Int(max(lh.x, rh.x) + span * 0.10)
            let widths = [0.45, 0.50, 0.55, 0.60, 0.65, 0.70].compactMap { frac -> Int? in
                guard let y = f.torsoRow(frac) else { return nil }
                return mask.rowRunWidth(y: y, xRef: Int(hipMid.x.rounded()), xMin: xMin, xMax: xMax)
            }
            if let waist = widths.min() {
                m.set(.waistWidth, f.cm(Double(waist)), f.maskConfidence(torsoJoints), source: f.poseType)
            }
        }

        if let f = tPose ?? front, let mask = f.mask, let shoulderMid = f.keypoints.shoulderMid,
           let ls = f.keypoints.point(.leftShoulder), let rs = f.keypoints.point(.rightShoulder) {
            let span = abs(ls.x - rs.x)
            let usesTPose = f.poseType == .frontArmsOut
            // With the arms down the window is clamped to the shoulder joints so the arms are excluded.
            let margin = usesTPose ? span * 0.15 : 0
            let xMin = Int(min(ls.x, rs.x) - margin), xMax = Int(max(ls.x, rs.x) + margin)
            if let y = f.torsoRow(usesTPose ? 0.25 : 0.20),
               let chest = mask.rowRunWidth(y: y, xRef: Int(shoulderMid.x.rounded()), xMin: xMin, xMax: xMax) {
                let conf = usesTPose ? f.maskConfidence(torsoJoints) : min(f.maskConfidence(torsoJoints), .medium)
                m.set(.chestWidth, f.cm(Double(chest)), conf, source: f.poseType)
            }
        }

        if let f = tPose ?? front, let mask = f.mask, let hipMid = f.keypoints.hipMid,
           let lh = f.keypoints.point(.leftHip), let rh = f.keypoints.point(.rightHip) {
            let span = abs(lh.x - rh.x)
            let usesTPose = f.poseType == .frontArmsOut
            let margin = span * (usesTPose ? 0.5 : 0.35)
            let xMin = Int(min(lh.x, rh.x) - margin), xMax = Int(max(lh.x, rh.x) + margin)
            let widths = stride(from: 0.85, through: 1.10, by: 0.05).compactMap { frac -> Int? in
                guard let y = f.torsoRow(frac) else { return nil }
                return mask.rowRunWidth(y: y, xRef: Int(hipMid.x.rounded()), xMin: xMin, xMax: xMax)
            }
            if let hips = widths.max() {
                let conf = usesTPose ? f.maskConfidence(torsoJoints) : min(f.maskConfidence(torsoJoints), .medium)
                m.set(.hipsWidth, f.cm(Double(hips)), conf, source: f.poseType)
            }
        }

        // Neck: narrowest row between 60–80% of the way from the nose down to the shoulder line.
        if let f = front ?? tPose, let mask = f.mask, let nose = f.keypoints.point(.nose), let shoulderMid = f.keypoints.shoulderMid,
           let ls = f.keypoints.point(.leftShoulder), let rs = f.keypoints.point(.rightShoulder) {
            let half = abs(ls.x - rs.x) / 2
            let widths = [0.6, 0.7, 0.8].compactMap { frac -> Int? in
                let y = Int((nose.y + (shoulderMid.y - nose.y) * frac).rounded())
                return mask.rowRunWidth(y: y, xRef: Int(nose.x.rounded()), xMin: Int(nose.x - half), xMax: Int(nose.x + half))
            }
            if let neck = widths.min() {
                m.set(.neckWidth, f.cm(Double(neck)), min(f.maskConfidence([.nose, .leftShoulder, .rightShoulder]), .medium), source: f.poseType)
            }
        }
    }

    /// Side photo: the same rows give front-to-back depth.
    private static func measureSideDepths(_ s: Frame, into m: inout BodyMeasurements) {
        guard let mask = s.mask, let hipMid = s.keypoints.hipMid, let shoulderMid = s.keypoints.shoulderMid else { return }
        let torso = max(BodyPoint.distance(shoulderMid, hipMid), 1)
        let joints: [BodyJoint] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        func row(_ frac: Double, xRef: Double) -> Int? {
            guard let y = s.torsoRow(frac) else { return nil }
            return mask.rowRunWidth(y: y, xRef: Int(xRef.rounded()), xMin: Int(xRef - torso), xMax: Int(xRef + torso))
        }
        let waist = [0.45, 0.50, 0.55, 0.60, 0.65, 0.70].compactMap { row($0, xRef: hipMid.x) }.min()
        m.set(.waistDepth, waist.map { s.cm(Double($0)) }, s.maskConfidence(joints), source: .sideLeft)
        m.set(.chestDepth, row(0.25, xRef: shoulderMid.x).map { s.cm(Double($0)) }, s.maskConfidence(joints), source: .sideLeft)
        let hips = stride(from: 0.85, through: 1.10, by: 0.05).compactMap { row($0, xRef: hipMid.x) }.max()
        m.set(.hipsDepth, hips.map { s.cm(Double($0)) }, s.maskConfidence(joints), source: .sideLeft)
    }

    // MARK: - Circumferences

    /// Ramanujan's approximation of an ellipse perimeter with diameters `width` and `depth`.
    static func ellipsePerimeter(width: Double, depth: Double) -> Double {
        let a = width / 2, b = depth / 2
        guard a + b > 0 else { return 0 }
        let h = ((a - b) / (a + b)) * ((a - b) / (a + b))
        return Double.pi * (a + b) * (1 + 3 * h / (10 + (4 - 3 * h).squareRoot()))
    }

    private static func measureCircumferences(into m: inout BodyMeasurements, hasSide: Bool) {
        func limb(_ width: BodyMetric, _ circ: BodyMetric, factor: Double) {
            guard let w = m[width] else { return }
            m.set(circ, Double.pi * w.value * factor, w.confidence, source: m.source(width))
        }
        limb(.leftUpperArmWidth, .leftUpperArmCircumference, factor: armCircumferenceFactor)
        limb(.rightUpperArmWidth, .rightUpperArmCircumference, factor: armCircumferenceFactor)
        limb(.leftForearmWidth, .leftForearmCircumference, factor: armCircumferenceFactor)
        limb(.rightForearmWidth, .rightForearmCircumference, factor: armCircumferenceFactor)
        limb(.leftThighWidth, .leftThighCircumference, factor: legCircumferenceFactor)
        limb(.rightThighWidth, .rightThighCircumference, factor: legCircumferenceFactor)
        limb(.leftCalfWidth, .leftCalfCircumference, factor: legCircumferenceFactor)
        limb(.rightCalfWidth, .rightCalfCircumference, factor: legCircumferenceFactor)
        limb(.neckWidth, .neckCircumference, factor: neckCircumferenceFactor)

        func torso(_ widthMetric: BodyMetric, _ depthMetric: BodyMetric, _ circ: BodyMetric, defaultRatio: Double) {
            guard let w = m[widthMetric] else { return }
            if let d = m[depthMetric] {
                m.set(circ, ellipsePerimeter(width: w.value, depth: d.value), min(w.confidence, d.confidence), source: m.source(widthMetric))
            } else {
                // No side photo: assume a typical depth and cap the confidence.
                m.set(circ, ellipsePerimeter(width: w.value, depth: w.value * defaultRatio), min(w.confidence, .medium), source: m.source(widthMetric))
            }
        }
        torso(.waistWidth, .waistDepth, .waistCircumference, defaultRatio: waistDepthRatio)
        torso(.chestWidth, .chestDepth, .chestCircumference, defaultRatio: chestDepthRatio)
        torso(.hipsWidth, .hipsDepth, .hipsCircumference, defaultRatio: hipsDepthRatio)
    }

    // MARK: - Composition

    /// Relative Fat Mass (Woolcott & Bergman 2018): 64 − 20 × height/waist for men, 76 − … for women.
    static func relativeFatMass(heightCm: Double, waistCm: Double, sex: BiologicalSex) -> Double? {
        guard heightCm > 0, waistCm > 0 else { return nil }
        let base = sex == .male ? 64.0 : 76.0
        return clampBodyFat(base - 20 * heightCm / waistCm)
    }

    /// US Navy tape method (Hodgdon & Beckett 1984), centimetres. Women need the hip circumference.
    static func navyBodyFat(heightCm: Double, waistCm: Double, neckCm: Double, hipsCm: Double?, sex: BiologicalSex) -> Double? {
        guard heightCm > 0, waistCm > neckCm, neckCm > 0 else { return nil }
        let value: Double
        switch sex {
        case .male:
            value = 495 / (1.0324 - 0.19077 * log10(waistCm - neckCm) + 0.15456 * log10(heightCm)) - 450
        case .female:
            guard let hipsCm, waistCm + hipsCm > neckCm else { return nil }
            value = 495 / (1.29579 - 0.35004 * log10(waistCm + hipsCm - neckCm) + 0.22100 * log10(heightCm)) - 450
        }
        guard value.isFinite else { return nil }
        return clampBodyFat(value)
    }

    static func clampBodyFat(_ value: Double) -> Double {
        min(max(value, bodyFatRange.lowerBound), bodyFatRange.upperBound)
    }

    private static func measureComposition(input: BodyScanInput, into m: inout BodyMeasurements) {
        let waistSource = m.source(.waistCircumference)
        if let waist = m[.waistCircumference] {
            // Photo-based body fat is never better than "medium".
            let conf = min(waist.confidence, .medium)
            if let rfm = relativeFatMass(heightCm: input.heightCm, waistCm: waist.value, sex: input.sex) {
                m.set(.bodyFatPercentRFM, rfm, conf, source: waistSource)
                m.set(.bodyFatPercent, rfm, conf, source: waistSource)
            }
            if let neck = m[.neckCircumference],
               let navy = navyBodyFat(heightCm: input.heightCm, waistCm: waist.value, neckCm: neck.value,
                                      hipsCm: m.value(.hipsCircumference), sex: input.sex) {
                m.set(.bodyFatPercentNavy, navy, min(conf, neck.confidence), source: waistSource)
            }
            if input.heightCm > 0 {
                m.set(.waistToHeightRatio, waist.value / input.heightCm, waist.confidence, source: waistSource)
            }
            if let hips = m[.hipsCircumference], hips.value > 0 {
                m.set(.waistToHipRatio, waist.value / hips.value, min(waist.confidence, hips.confidence), source: waistSource)
            }
        }
        if let bf = m[.bodyFatPercent], input.weightKg > 0 {
            let fat = input.weightKg * bf.value / 100
            m.set(.fatMassKg, fat, bf.confidence, source: waistSource)
            m.set(.leanMassKg, input.weightKg - fat, bf.confidence, source: waistSource)
        }
    }
}
