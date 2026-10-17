import Foundation
import SwiftData

/// Which way the person faced. Lets "before" and "after" be matched by angle.
enum ProgressPhotoAngle: String, Codable, CaseIterable, Identifiable {
    case front, side, back, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: return "Front"
        case .side: return "Side"
        case .back: return "Back"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .front: return "figure.stand"
        case .side: return "figure.walk"
        case .back: return "figure.stand.line.dotted.figure.stand"
        case .other: return "photo"
        }
    }
}

/// A picture of the person added from the photo library — from any time and any angle — so they can compare
/// an older self with a newer one. Stored next to body-scan photos, never synced, no measurements of its own.
@Model
final class ProgressPhoto {
    @Attribute(.unique) var id: UUID
    /// When the picture was taken (EXIF when available, else chosen by the person).
    var takenAt: Date
    var createdAt: Date
    var filename: String
    var angleRaw: String
    var note: String?
    /// Weight at the time, if the person remembers it.
    var weightKg: Double?

    init(id: UUID = UUID(),
         takenAt: Date,
         createdAt: Date = .now,
         filename: String,
         angle: ProgressPhotoAngle = .front,
         note: String? = nil,
         weightKg: Double? = nil) {
        self.id = id
        self.takenAt = takenAt
        self.createdAt = createdAt
        self.filename = filename
        self.angleRaw = angle.rawValue
        self.note = note
        self.weightKg = weightKg
    }

    var angle: ProgressPhotoAngle {
        get { ProgressPhotoAngle(rawValue: angleRaw) ?? .other }
        set { angleRaw = newValue.rawValue }
    }
}

/// One picture on the progress timeline: an imported `ProgressPhoto` or the front photo of a `BodyScan`.
/// Scans are included so the timeline and the before/after view show everything, without copying files.
struct ProgressTimelineItem: Identifiable, Equatable {
    enum Source: Equatable {
        case imported(UUID)
        case scan(UUID)
    }

    let source: Source
    let date: Date
    let filename: String
    let angle: ProgressPhotoAngle
    let note: String?
    let weightKg: Double?

    var id: String {
        switch source {
        case .imported(let id): return "photo-\(id.uuidString)"
        case .scan(let id): return "scan-\(id.uuidString)"
        }
    }

    var isFromScan: Bool {
        if case .scan = source { return true }
        return false
    }

    var importedID: UUID? {
        if case .imported(let id) = source { return id }
        return nil
    }

    init(photo: ProgressPhoto) {
        source = .imported(photo.id)
        date = photo.takenAt
        filename = photo.filename
        angle = photo.angle
        note = photo.note
        weightKg = photo.weightKg
    }

    /// The scan's front photo (else T-pose, else side), tagged with the matching angle. Nil when it has no photo.
    init?(scan: BodyScan) {
        let candidates: [(String?, ProgressPhotoAngle)] = [(scan.frontPhotoFilename, .front), (scan.tPosePhotoFilename, .front),
                                                            (scan.sidePhotoFilename, .side)]
        guard let match = candidates.first(where: { $0.0 != nil }), let filename = match.0 else { return nil }
        source = .scan(scan.id)
        date = scan.createdAt
        self.filename = filename
        self.angle = match.1
        note = scan.notes
        weightKg = scan.weightKg
    }

    /// Imported photos and scan photos merged, oldest first.
    static func timeline(photos: [ProgressPhoto], scans: [BodyScan]) -> [ProgressTimelineItem] {
        (photos.map(ProgressTimelineItem.init(photo:)) + scans.compactMap(ProgressTimelineItem.init(scan:)))
            .sorted { $0.date < $1.date }
    }
}
