import Foundation
import Observation
import SwiftData
import UIKit

/// State machine for a new scan: setup (weight) → three poses → review → save.
@MainActor
@Observable
final class BodyScanFlowModel {
    enum Step: Equatable {
        case setup
        case pose(BodyPoseType)
        case review
    }

    var step: Step = .setup

    // Inputs (metric)
    var heightCm: Double
    var weightKg: Double
    var sex: BiologicalSex
    var age: Int?
    var notes = ""
    let hasProfile: Bool

    // Per-pose results
    var results: [BodyPoseType: PoseAnalysisResult] = [:]
    var maskImages: [BodyPoseType: UIImage] = [:]
    var analyzingPose: BodyPoseType?
    var poseErrors: [BodyPoseType: String] = [:]
    var saveError: String?
    var measurements: BodyMeasurements?
    private(set) var segmenterName: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    init(profile: UserProfile?) {
        heightCm = profile?.heightCm ?? 170
        weightKg = profile?.weightKg ?? 70
        sex = profile?.sex ?? .male
        age = profile?.age
        hasProfile = profile != nil
    }

    // MARK: - Derived

    var isAnalyzing: Bool { analyzingPose != nil }
    var canReview: Bool { results[.frontArmsDown] != nil }
    var completedPoses: [BodyPoseType] { BodyPoseType.allCases.filter { results[$0] != nil } }
    var isSetupValid: Bool { heightCm >= 100 && heightCm <= 250 && weightKg >= 25 && weightKg <= 400 }

    func result(for pose: BodyPoseType) -> PoseAnalysisResult? { results[pose] }

    // MARK: - Steps

    func startPoses() { step = .pose(.frontArmsDown) }

    func go(to pose: BodyPoseType) { step = .pose(pose) }

    func next(after pose: BodyPoseType) {
        let all = BodyPoseType.allCases
        if let index = all.firstIndex(of: pose), index + 1 < all.count {
            step = .pose(all[index + 1])
        } else {
            review()
        }
    }

    func review() {
        measurements = computeMeasurements()
        step = .review
    }

    // MARK: - Analysis

    func analyze(_ image: UIImage, for pose: BodyPoseType, analyzer: BodyScanAnalyzer) {
        poseErrors[pose] = nil
        analyzingPose = pose
        task?.cancel()
        task = Task { [weak self] in
            do {
                let result = try await analyzer.analyze(image, poseType: pose)
                guard !Task.isCancelled, let self else { return }
                self.results[pose] = result
                self.maskImages[pose] = result.observation.mask?.tintedImage(color: UIColor(Color.mAccent), alpha: 0.32)
                if let name = result.segmenterName { self.segmenterName = name }
                self.measurements = self.computeMeasurements()
                self.analyzingPose = nil
                if result.warning != nil { Haptics.warning() } else { Haptics.success() }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.poseErrors[pose] = error.localizedDescription
                self.analyzingPose = nil
            }
        }
    }

    func retake(_ pose: BodyPoseType) {
        results[pose] = nil
        maskImages[pose] = nil
        poseErrors[pose] = nil
        measurements = results.isEmpty ? nil : computeMeasurements()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Measurements

    func computeMeasurements() -> BodyMeasurements {
        let input = BodyScanInput(front: results[.frontArmsDown]?.observation,
                                  tPose: results[.frontArmsOut]?.observation,
                                  side: results[.sideLeft]?.observation,
                                  heightCm: heightCm, weightKg: weightKg, sex: sex, age: age)
        return BodyMeasurementEngine.measure(input)
    }

    // MARK: - Save

    /// Writes the photos and inserts the scan. Throws with the photos cleaned up on failure.
    func save(into context: ModelContext) throws -> BodyScan {
        let measurements = self.measurements ?? computeMeasurements()
        var filenames: [BodyPoseType: String] = [:]
        do {
            for (pose, result) in results {
                filenames[pose] = try BodyScanPhotoStore.save(result.image)
            }
            var keypoints: [BodyPoseType: BodyKeypoints] = [:]
            for (pose, result) in results { keypoints[pose] = result.observation.keypoints }
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let scan = BodyScan(heightCm: heightCm, weightKg: weightKg, sex: sex,
                                notes: trimmed.isEmpty ? nil : trimmed,
                                measurements: measurements, keypoints: keypoints, segmenterName: segmenterName,
                                frontPhotoFilename: filenames[.frontArmsDown],
                                tPosePhotoFilename: filenames[.frontArmsOut],
                                sidePhotoFilename: filenames[.sideLeft])
            try context.saveBodyScan(scan)
            return scan
        } catch {
            for name in filenames.values { BodyScanPhotoStore.delete(name) }
            throw error
        }
    }
}
