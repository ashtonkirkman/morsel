import Foundation
import SwiftData

extension ModelContext {
    /// All scans, newest first.
    func bodyScans() throws -> [BodyScan] {
        try fetch(FetchDescriptor<BodyScan>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    /// Scans oldest first, for trend charts.
    func bodyScansChronological() throws -> [BodyScan] {
        try fetch(FetchDescriptor<BodyScan>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
    }

    func latestBodyScan() throws -> BodyScan? {
        var descriptor = FetchDescriptor<BodyScan>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func baselineBodyScan() throws -> BodyScan? {
        var descriptor = FetchDescriptor<BodyScan>(predicate: #Predicate { $0.isBaseline },
                                                   sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func bodyScan(id: UUID) throws -> BodyScan? {
        var descriptor = FetchDescriptor<BodyScan>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// Inserts and saves. The first scan ever becomes the baseline automatically.
    @discardableResult
    func saveBodyScan(_ scan: BodyScan) throws -> BodyScan {
        if try baselineBodyScan() == nil { scan.isBaseline = true }
        insert(scan)
        try save()
        return scan
    }

    /// Marks `scan` as the baseline and clears the flag everywhere else.
    func setBaselineBodyScan(_ scan: BodyScan) throws {
        for other in try bodyScans() where other.isBaseline && other.id != scan.id {
            other.isBaseline = false
            other.updatedAt = .now
        }
        scan.isBaseline = true
        scan.updatedAt = .now
        try save()
    }

    /// Deletes the scan and its photos. If it was the baseline, the oldest remaining scan takes over.
    func deleteBodyScan(_ scan: BodyScan) throws {
        let wasBaseline = scan.isBaseline
        for name in scan.photoFilenames { BodyScanPhotoStore.delete(name) }
        recordDeletion(of: scan.id, in: SyncCollectionNames.bodyScans)
        delete(scan)
        try save()
        if wasBaseline, let oldest = try bodyScansChronological().first {
            oldest.isBaseline = true
            oldest.updatedAt = .now
            try save()
        }
    }
}
