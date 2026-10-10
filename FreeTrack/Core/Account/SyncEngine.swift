import CryptoKit
import Foundation
import Observation
import SwiftData

// MARK: - Collection contracts

/// A Codable snapshot of one synced object. `updatedAt` drives last-writer-wins.
protocol SyncableDTO: Codable {
    var id: UUID { get }
    var updatedAt: Date { get set }
}

/// A SwiftData model that syncs through a `ModelSyncCollection`. Conform `BodyScan` to this and
/// register `ModelSyncCollection<BodyScan>(name: "body-scans")` to sync it.
protocol SyncableModel: PersistentModel {
    associatedtype DTO: SyncableDTO
    /// The object's stable UUID (named `syncID` to avoid clashing with `PersistentModel.id`).
    var syncID: UUID { get }
    var updatedAt: Date { get set }
    func makeDTO() -> DTO
    func apply(_ dto: DTO)
    init(syncDTO dto: DTO)
}

/// What the engine remembers about each local document between runs (to notice edits made
/// without bumping `updatedAt`, and deletions made without a tombstone).
struct LocalDocumentState: Codable, Equatable {
    var updatedAt: Date
    var fingerprint: String
}

/// One syncable collection. `ModelSyncCollection` covers SwiftData models; `SettingsSyncCollection`
/// covers the single profile/goals document.
@MainActor
protocol SyncCollection: AnyObject {
    /// Server collection name: `^[a-z][a-z0-9_-]{0,39}$`.
    var name: String { get }
    func snapshot(in context: ModelContext) throws -> [String: LocalDocumentState]
    func documents(ids: Set<String>, in context: ModelContext) throws -> [SyncDocument]
    /// Bump `updatedAt` for an object that changed without saying so.
    func touch(id: String, at date: Date, in context: ModelContext) throws
    /// Apply remote documents (last-writer-wins against the local copy).
    func apply(_ documents: [SyncDocument], in context: ModelContext) throws
}

// MARK: - Merge rules (pure, unit-tested)

enum SyncMerge {
    /// True when the remote document should replace (or delete) the local one.
    /// Ties keep the local copy, so a document we just pushed is not re-applied.
    static func remoteWins(localUpdatedAt: Date?, remote: SyncDocument) -> Bool {
        guard let localUpdatedAt else { return !remote.deleted }
        return remote.updatedDate > localUpdatedAt
    }

    /// Decide what to push: anything newer than the last push, anything never seen, and
    /// anything whose content changed while `updatedAt` stayed put (returned in `touched`).
    static func changes(current: [String: LocalDocumentState],
                        previous: [String: LocalDocumentState],
                        lastPush: Date?) -> (push: Set<String>, touched: Set<String>, deleted: Set<String>) {
        var push = Set<String>()
        var touched = Set<String>()
        for (id, state) in current {
            if let prior = previous[id] {
                if prior.fingerprint != state.fingerprint && state.updatedAt <= prior.updatedAt {
                    touched.insert(id)
                    push.insert(id)
                    continue
                }
            } else {
                push.insert(id)
                continue
            }
            if let lastPush {
                if state.updatedAt > lastPush { push.insert(id) }
            } else {
                push.insert(id)
            }
        }
        let deleted = Set(previous.keys).subtracting(current.keys)
        return (push, touched, deleted)
    }

    static func fingerprint<T: SyncableDTO>(_ dto: T) -> String {
        var copy = dto
        copy.updatedAt = .distantPast
        guard let data = try? SyncCodec.encoder.encode(copy) else { return UUID().uuidString }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Generic SwiftData collection

/// Syncs every instance of one `SyncableModel`. Fetches are whole-table (the app's data is
/// small: a few thousand rows at most) so no generic `#Predicate` is needed.
@MainActor
final class ModelSyncCollection<M: SyncableModel>: SyncCollection {
    let name: String

    init(name: String) {
        self.name = name
    }

    private func fetchAll(in context: ModelContext) throws -> [M] {
        try context.fetch(FetchDescriptor<M>())
    }

    private func index(in context: ModelContext) throws -> [String: M] {
        var out: [String: M] = [:]
        for model in try fetchAll(in: context) { out[model.syncID.uuidString] = model }
        return out
    }

    func snapshot(in context: ModelContext) throws -> [String: LocalDocumentState] {
        var out: [String: LocalDocumentState] = [:]
        for model in try fetchAll(in: context) {
            let dto = model.makeDTO()
            out[model.syncID.uuidString] = LocalDocumentState(updatedAt: model.updatedAt, fingerprint: SyncMerge.fingerprint(dto))
        }
        return out
    }

    func documents(ids: Set<String>, in context: ModelContext) throws -> [SyncDocument] {
        let byID = try index(in: context)
        return try ids.compactMap { id -> SyncDocument? in
            guard let model = byID[id] else { return nil }
            let dto = model.makeDTO()
            return SyncDocument(id: id, json: try SyncCodec.encodeToString(dto), updatedAt: dto.updatedAt)
        }
    }

    func touch(id: String, at date: Date, in context: ModelContext) throws {
        guard let model = try index(in: context)[id] else { return }
        model.updatedAt = date
    }

    func apply(_ documents: [SyncDocument], in context: ModelContext) throws {
        let byID = try index(in: context)
        for document in documents {
            let local = byID[document.id]
            guard SyncMerge.remoteWins(localUpdatedAt: local?.updatedAt, remote: document) else { continue }
            if document.deleted {
                if let local { context.delete(local) }
                continue
            }
            guard let json = document.json else { continue }
            let dto: M.DTO
            do {
                dto = try SyncCodec.decode(M.DTO.self, from: json)
            } catch {
                continue   // a newer app version wrote a shape we cannot read; leave it for later
            }
            if let local {
                local.apply(dto)
                local.updatedAt = document.updatedDate
            } else {
                let model = M(syncDTO: dto)
                model.updatedAt = document.updatedDate
                context.insert(model)
            }
        }
    }
}

// MARK: - Engine

/// Pushes local changes and pulls remote ones for every registered collection. Never blocks the
/// UI; failures are silent apart from `lastError` / "Last synced" in Settings.
@Observable
@MainActor
final class SyncEngine {
    private(set) var isSyncing = false
    private(set) var lastError: String?
    var lastSyncedAt: Date? {
        get { settings.lastSyncedAt }
        set { settings.lastSyncedAt = newValue }
    }

    private let account: AccountService
    private let settings: AppSettings
    private let container: ModelContainer?
    private let store = SyncStateStore()
    private var collections: [any SyncCollection] = []
    private var debounce: Task<Void, Never>?
    private var queuedAgain = false
    private var applyingRemote = false
    /// Our own `context.save()` posts `ModelContext.didSave` too (delivered asynchronously on
    /// the main queue); saves within a second of one are ours and must not re-trigger a sync.
    private var lastEngineSaveAt: Date = .distantPast
    private var observer: NSObjectProtocol?

    init(account: AccountService, settings: AppSettings, container: ModelContainer?) {
        self.account = account
        self.settings = settings
        self.container = container
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.noteLocalChange() }
        }
    }

    /// Order matters only for readability. Register before the first sync.
    func register(_ collection: any SyncCollection) {
        collections.append(collection)
    }

    /// Call after anything that changed local data; coalesces into one sync a few seconds later.
    func noteLocalChange() {
        guard !applyingRemote, Date.now.timeIntervalSince(lastEngineSaveAt) > 1 else { return }
        scheduleSync(after: 3)
    }

    /// Debounced sync (sign-in, app foreground, local edits).
    func scheduleSync(after seconds: Double = 0.5) {
        guard account.isSignedIn, account.isConfigured else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Session changed: forget cursors so a different account starts clean, then sync.
    func sessionDidChange() {
        store.reset(collections: collections.map(\.name))
        settings.clearSyncCursors()
        lastError = nil
        if account.isSignedIn { scheduleSync(after: 0.2) }
    }

    /// Full push + pull for every collection. Safe to call repeatedly; overlapping calls queue one more run.
    func syncNow() async {
        guard account.isSignedIn, account.isConfigured, let container else { return }
        if isSyncing { queuedAgain = true; return }
        isSyncing = true
        defer { isSyncing = false }
        let context = container.mainContext
        do {
            let token = try await account.validAccessToken()
            for collection in collections {
                try await sync(collection, token: token, context: context)
            }
            lastSyncedAt = .now
            lastError = nil
        } catch {
            if (error as? AccountError) != .cancelled { lastError = error.localizedDescription }
        }
        if queuedAgain {
            queuedAgain = false
            scheduleSync(after: 1)
        }
    }

    private func sync(_ collection: any SyncCollection, token: String, context: ModelContext) async throws {
        let name = collection.name
        let now = Date.now
        let previous = store.loadSnapshot(name)
        var current = try collection.snapshot(in: context)
        let lastPush = settings.syncLastPush(for: name)
        let change = SyncMerge.changes(current: current, previous: previous, lastPush: lastPush)

        // Edits that did not bump updatedAt: bump now so other devices accept them.
        for id in change.touched {
            try collection.touch(id: id, at: now, in: context)
            current[id]?.updatedAt = now
        }

        // Deletions we noticed by absence: write tombstones unless one already exists.
        let existingTombstones = try tombstones(for: name, since: nil, in: context)
        let tombstoned = Set(existingTombstones.map(\.docID))
        for id in change.deleted.subtracting(tombstoned) {
            context.insert(SyncTombstone(docID: id, collection: name, deletedAt: now))
        }
        if context.hasChanges { try save(context) }

        // Push.
        var outgoing = try collection.documents(ids: change.push, in: context)
        let pendingTombstones = try tombstones(for: name, since: lastPush, in: context)
        outgoing += pendingTombstones.map { SyncDocument(id: $0.docID, json: nil, updatedAt: $0.deletedAt, deleted: true) }
        if !outgoing.isEmpty {
            for batch in stride(from: 0, to: outgoing.count, by: 400).map({ Array(outgoing[$0..<min($0 + 400, outgoing.count)]) }) {
                _ = try await account.api.push(collection: name, documents: batch, accessToken: token)
            }
        }
        settings.setSyncLastPush(now, for: name)

        // Pull.
        let since = settings.syncCursor(for: name)
        let pulled = try await account.api.pull(collection: name, since: since, accessToken: token)
        if !pulled.documents.isEmpty {
            applyingRemote = true
            defer { applyingRemote = false }
            try collection.apply(pulled.documents, in: context)
            if context.hasChanges { try save(context) }
        }
        settings.setSyncCursor(pulled.serverTime, for: name)

        // Remember what we have so the next run can spot silent edits and deletions.
        store.saveSnapshot(try collection.snapshot(in: context), for: name)
    }

    private func save(_ context: ModelContext) throws {
        applyingRemote = true
        defer { applyingRemote = false }
        lastEngineSaveAt = .now
        try context.save()
    }

    private func tombstones(for collection: String, since: Date?, in context: ModelContext) throws -> [SyncTombstone] {
        let descriptor = FetchDescriptor<SyncTombstone>(predicate: #Predicate { $0.collection == collection })
        let all = try context.fetch(descriptor)
        guard let since else { return all }
        return all.filter { $0.deletedAt > since }
    }
}

// MARK: - Snapshot persistence

/// Per-collection fingerprints, stored as JSON files in Application Support/SyncState.
struct SyncStateStore {
    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SyncState", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func url(for collection: String) -> URL {
        directory.appendingPathComponent(collection + ".json")
    }

    func loadSnapshot(_ collection: String) -> [String: LocalDocumentState] {
        guard let data = try? Data(contentsOf: url(for: collection)) else { return [:] }
        return (try? SyncCodec.decoder.decode([String: LocalDocumentState].self, from: data)) ?? [:]
    }

    func saveSnapshot(_ snapshot: [String: LocalDocumentState], for collection: String) {
        guard let data = try? SyncCodec.encoder.encode(snapshot) else { return }
        try? data.write(to: url(for: collection), options: .atomic)
    }

    func reset(collections: [String]) {
        for name in collections { try? FileManager.default.removeItem(at: url(for: name)) }
    }
}
