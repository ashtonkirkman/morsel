import Foundation
import Observation
import SwiftData
import UIKit

/// State machine for the snap-a-photo flow: capture → analyzing → review (or failed).
@MainActor
@Observable
final class SnapMealViewModel {
    enum Phase: Equatable {
        case capture
        case analyzing
        case review
        case failed(String)
    }

    static let notConfiguredMessage = "Photo logging needs a Claude API key or proxy URL. Add one in Settings."
    static let autoLogThreshold = 0.85

    // MARK: - State

    var phase: Phase = .capture
    /// Optional free-text steer typed before capture ("half portion").
    var hint = ""
    var image: UIImage?
    private(set) var imageData: Data?
    private(set) var estimate: MealEstimate?
    /// Editable copy of the estimate's items; this is what gets logged.
    var items: [EstimatedFoodItem] = []
    var mealType: MealType = .suggested()
    var answer = ""
    var isRevising = false
    var reviseErrorMessage: String?
    var logErrorMessage: String?
    var expandedItemID: UUID?
    /// Set when the estimate qualifies for auto-logging; the view commits and dismisses.
    var pendingAutoLog = false

    @ObservationIgnored private var task: Task<Void, Never>?

    // MARK: - Derived

    var total: NutritionFacts { items.map(\.total).total() }
    var overallConfidence: Double { estimate?.overallConfidence ?? 0 }
    var summary: String { estimate?.summary ?? "Your meal" }
    var clarifyingQuestion: String? { estimate?.clarifyingQuestion }
    var canLog: Bool { items.contains { $0.quantity > 0 } }

    // MARK: - Capture → analyze

    func begin(with image: UIImage, vision: any MealVisionService, isConfigured: Bool, autoLog: Bool) {
        self.image = image
        logErrorMessage = nil
        guard isConfigured else {
            phase = .failed(Self.notConfiguredMessage)
            return
        }
        do {
            imageData = try ImageResizer.jpegData(from: image, maxDimension: 1280, quality: 0.8)
        } catch {
            phase = .failed(ServiceError.invalidImage.errorDescription ?? "That image couldn't be read.")
            return
        }
        phase = .analyzing
        runInitialAnalysis(vision: vision, autoLog: autoLog)
    }

    func retry(vision: any MealVisionService, isConfigured: Bool, autoLog: Bool) {
        guard let image else {
            phase = .capture
            return
        }
        begin(with: image, vision: vision, isConfigured: isConfigured, autoLog: autoLog)
    }

    private func runInitialAnalysis(vision: any MealVisionService, autoLog: Bool) {
        guard let imageData else { return }
        let hintText = ClaudeVisionCodec.cleaned(hint)
        task?.cancel()
        task = Task { [weak self] in
            do {
                let result = try await vision.estimate(imageData: imageData, hint: hintText, previous: nil)
                guard !Task.isCancelled, let self else { return }
                self.apply(result)
                if autoLog, result.overallConfidence >= Self.autoLogThreshold, result.clarifyingQuestion == nil {
                    self.pendingAutoLog = true
                } else {
                    self.phase = .review
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.phase = .failed(Self.message(for: error))
            }
        }
    }

    // MARK: - Clarifying question round trip

    func submitAnswer(vision: any MealVisionService) {
        guard let imageData, let current = currentEstimate(),
              let text = ClaudeVisionCodec.cleaned(answer) else { return }
        isRevising = true
        reviseErrorMessage = nil
        task?.cancel()
        task = Task { [weak self] in
            do {
                let result = try await vision.estimate(imageData: imageData, hint: text, previous: current)
                guard !Task.isCancelled, let self else { return }
                self.apply(result)
                self.answer = ""
                self.isRevising = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.reviseErrorMessage = Self.message(for: error)
                self.isRevising = false
            }
        }
    }

    func skipQuestion() {
        estimate?.clarifyingQuestion = nil
        reviseErrorMessage = nil
    }

    // MARK: - Item editing

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if expandedItemID == id { expandedItemID = nil }
    }

    func toggleExpanded(_ id: UUID) {
        expandedItemID = expandedItemID == id ? nil : id
    }

    // MARK: - Logging

    /// Saves the photo once and inserts one `LogEntry` per item with a positive quantity.
    func log(into context: ModelContext) throws -> [LogEntry] {
        guard let image else { return [] }
        let toLog = items.filter { $0.quantity > 0 }
        guard !toLog.isEmpty else { return [] }
        let filename = try PhotoStore.shared.save(image)
        do {
            var entries: [LogEntry] = []
            for item in toLog {
                let entry = try context.log(item.food,
                                            quantity: item.quantity,
                                            mealType: mealType,
                                            photoFilename: filename,
                                            confidence: item.confidence)
                entries.append(entry)
            }
            return entries
        } catch {
            PhotoStore.shared.delete(filename)
            throw error
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Helpers

    private func apply(_ result: MealEstimate) {
        estimate = result
        items = result.items
        expandedItemID = nil
    }

    /// The estimate as currently edited, for the `previous:` parameter of a revision call.
    private func currentEstimate() -> MealEstimate? {
        guard let estimate else { return nil }
        return MealEstimate(items: items,
                            summary: estimate.summary,
                            overallConfidence: estimate.overallConfidence,
                            clarifyingQuestion: estimate.clarifyingQuestion)
    }

    private static func message(for error: Error) -> String {
        ClaudeVisionCodec.serviceError(from: error).errorDescription ?? "Something went wrong."
    }
}
