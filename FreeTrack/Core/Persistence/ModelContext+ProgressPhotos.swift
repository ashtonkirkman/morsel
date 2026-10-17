import Foundation
import SwiftData

extension ModelContext {
    /// All imported progress photos, oldest first.
    func progressPhotos() throws -> [ProgressPhoto] {
        try fetch(FetchDescriptor<ProgressPhoto>(sortBy: [SortDescriptor(\.takenAt, order: .forward)]))
    }

    func progressPhoto(id: UUID) throws -> ProgressPhoto? {
        var descriptor = FetchDescriptor<ProgressPhoto>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// Inserts every photo and saves once.
    func saveProgressPhotos(_ photos: [ProgressPhoto]) throws {
        for photo in photos { insert(photo) }
        try save()
    }

    /// Deletes the record and its file. Progress photos never sync, so no tombstone is needed.
    func deleteProgressPhoto(_ photo: ProgressPhoto) throws {
        BodyScanPhotoStore.delete(photo.filename)
        delete(photo)
        try save()
    }
}
