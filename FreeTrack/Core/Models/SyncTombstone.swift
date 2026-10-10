import Foundation
import SwiftData

/// Records a local deletion so the server (and other devices) learn about it on the next sync.
/// `collection` is the sync collection name ("log-entries", "favorites", ...), `docID` the
/// deleted object's id. Created by `ModelContext.recordDeletion` or inferred by `SyncEngine`
/// when an object it previously saw has vanished.
@Model
final class SyncTombstone {
    @Attribute(.unique) var id: UUID
    var docID: String
    var collection: String
    var deletedAt: Date

    init(docID: String, collection: String, deletedAt: Date = .now) {
        self.id = UUID()
        self.docID = docID
        self.collection = collection
        self.deletedAt = deletedAt
    }
}
