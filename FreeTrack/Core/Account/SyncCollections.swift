import Foundation
import SwiftData

// MARK: - Log entries

/// Wire shape of a `LogEntry`. Photos stay on the device (only the file name is device-local
/// and is deliberately not synced).
struct LogEntryDTO: SyncableDTO, Equatable {
    var id: UUID
    var loggedAt: Date
    var mealType: String
    var name: String
    var brand: String?
    var barcode: String?
    var servingDescription: String
    var servingGrams: Double?
    var quantity: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var source: String
    var notes: String?
    var confidence: Double?
    var updatedAt: Date
}

extension LogEntry: SyncableModel {
    var syncID: UUID { id }

    func makeDTO() -> LogEntryDTO {
        LogEntryDTO(id: id, loggedAt: loggedAt, mealType: mealTypeRaw, name: name, brand: brand, barcode: barcode,
                    servingDescription: servingDescription, servingGrams: servingGrams, quantity: quantity,
                    calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar,
                    sodium: sodium, source: sourceRaw, notes: notes, confidence: confidence, updatedAt: updatedAt)
    }

    func apply(_ dto: LogEntryDTO) {
        loggedAt = dto.loggedAt
        refreshDay()
        mealTypeRaw = dto.mealType
        name = dto.name
        brand = dto.brand
        barcode = dto.barcode
        servingDescription = dto.servingDescription
        servingGrams = dto.servingGrams
        quantity = dto.quantity
        calories = dto.calories
        protein = dto.protein
        carbs = dto.carbs
        fat = dto.fat
        fiber = dto.fiber
        sugar = dto.sugar
        sodium = dto.sodium
        sourceRaw = dto.source
        notes = dto.notes
        confidence = dto.confidence
        updatedAt = dto.updatedAt
    }

    convenience init(syncDTO dto: LogEntryDTO) {
        self.init(id: dto.id,
                  loggedAt: dto.loggedAt,
                  mealType: MealType(rawValue: dto.mealType) ?? .snack,
                  name: dto.name,
                  brand: dto.brand,
                  barcode: dto.barcode,
                  servingDescription: dto.servingDescription,
                  servingGrams: dto.servingGrams,
                  quantity: dto.quantity,
                  perServing: NutritionFacts(calories: dto.calories, protein: dto.protein, carbs: dto.carbs, fat: dto.fat,
                                             fiber: dto.fiber, sugar: dto.sugar, sodium: dto.sodium),
                  source: FoodSource(rawValue: dto.source) ?? .manual,
                  notes: dto.notes,
                  confidence: dto.confidence)
        updatedAt = dto.updatedAt
    }
}

// MARK: - Favorites

struct FavoriteFoodDTO: SyncableDTO, Equatable {
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var servingDescription: String
    var servingGrams: Double?
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var source: String
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int
    var defaultQuantity: Double
    var updatedAt: Date
}

extension FavoriteFood: SyncableModel {
    var syncID: UUID { id }

    func makeDTO() -> FavoriteFoodDTO {
        FavoriteFoodDTO(id: id, name: name, brand: brand, barcode: barcode, servingDescription: servingDescription,
                        servingGrams: servingGrams, calories: calories, protein: protein, carbs: carbs, fat: fat,
                        fiber: fiber, sugar: sugar, sodium: sodium, source: sourceRaw, createdAt: createdAt,
                        lastUsedAt: lastUsedAt, useCount: useCount, defaultQuantity: defaultQuantity, updatedAt: updatedAt)
    }

    func apply(_ dto: FavoriteFoodDTO) {
        name = dto.name
        brand = dto.brand
        barcode = dto.barcode
        servingDescription = dto.servingDescription
        servingGrams = dto.servingGrams
        calories = dto.calories
        protein = dto.protein
        carbs = dto.carbs
        fat = dto.fat
        fiber = dto.fiber
        sugar = dto.sugar
        sodium = dto.sodium
        sourceRaw = dto.source
        createdAt = dto.createdAt
        lastUsedAt = dto.lastUsedAt
        useCount = dto.useCount
        defaultQuantity = dto.defaultQuantity
        updatedAt = dto.updatedAt
    }

    convenience init(syncDTO dto: FavoriteFoodDTO) {
        let food = FoodItem(name: dto.name, brand: dto.brand, barcode: dto.barcode,
                            servingDescription: dto.servingDescription, servingGrams: dto.servingGrams,
                            nutritionPerServing: NutritionFacts(calories: dto.calories, protein: dto.protein, carbs: dto.carbs,
                                                                fat: dto.fat, fiber: dto.fiber, sugar: dto.sugar, sodium: dto.sodium),
                            source: FoodSource(rawValue: dto.source) ?? .manual)
        self.init(food: food, defaultQuantity: dto.defaultQuantity, now: dto.createdAt)
        id = dto.id
        lastUsedAt = dto.lastUsedAt
        useCount = dto.useCount
        updatedAt = dto.updatedAt
    }
}

// MARK: - Profile + goals (one document: settings/profile)

/// The user's body stats and daily targets from `AppSettings`. `UserProfile` is embedded as an
/// opaque Codable value (never field-by-field) and decoded leniently so an older app can read a
/// document written by a newer one.
struct ProfileDocument: Codable, Equatable {
    var profile: UserProfile?
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
    var unitSystem: String
    var updatedAt: Date

    init(settings: AppSettings) {
        profile = settings.profile
        calorieGoal = settings.calorieGoal
        proteinGoal = settings.proteinGoal
        carbsGoal = settings.carbsGoal
        fatGoal = settings.fatGoal
        unitSystem = settings.unitSystem.rawValue
        updatedAt = settings.settingsUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case profile, calorieGoal, proteinGoal, carbsGoal, fatGoal, unitSystem, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try? c.decodeIfPresent(UserProfile.self, forKey: .profile)
        calorieGoal = try c.decode(Double.self, forKey: .calorieGoal)
        proteinGoal = try c.decode(Double.self, forKey: .proteinGoal)
        carbsGoal = try c.decode(Double.self, forKey: .carbsGoal)
        fatGoal = try c.decode(Double.self, forKey: .fatGoal)
        unitSystem = try c.decodeIfPresent(String.self, forKey: .unitSystem) ?? UnitSystem.imperial.rawValue
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(profile, forKey: .profile)
        try c.encode(calorieGoal, forKey: .calorieGoal)
        try c.encode(proteinGoal, forKey: .proteinGoal)
        try c.encode(carbsGoal, forKey: .carbsGoal)
        try c.encode(fatGoal, forKey: .fatGoal)
        try c.encode(unitSystem, forKey: .unitSystem)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    @MainActor
    func apply(to settings: AppSettings) {
        if let profile { settings.profile = profile }
        settings.calorieGoal = calorieGoal
        settings.proteinGoal = proteinGoal
        settings.carbsGoal = carbsGoal
        settings.fatGoal = fatGoal
        settings.unitSystem = UnitSystem(rawValue: unitSystem) ?? settings.unitSystem
        // The setters above bumped the local clock; pin it to the remote value so this
        // document is not pushed straight back.
        settings.settingsUpdatedAt = updatedAt
    }
}

/// Collection "settings" with the single document "profile".
@MainActor
final class SettingsSyncCollection: SyncCollection {
    let name = SyncCollectionNames.settings
    static let documentID = "profile"
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var isMeaningful: Bool { settings.settingsUpdatedAt > .distantPast }

    func snapshot(in context: ModelContext) throws -> [String: LocalDocumentState] {
        guard isMeaningful else { return [:] }
        let document = ProfileDocument(settings: settings)
        var copy = document
        copy.updatedAt = .distantPast
        let data = (try? SyncCodec.encoder.encode(copy)) ?? Data()
        return [Self.documentID: LocalDocumentState(updatedAt: document.updatedAt, fingerprint: data.base64EncodedString())]
    }

    func documents(ids: Set<String>, in context: ModelContext) throws -> [SyncDocument] {
        guard ids.contains(Self.documentID), isMeaningful else { return [] }
        let document = ProfileDocument(settings: settings)
        return [SyncDocument(id: Self.documentID, json: try SyncCodec.encodeToString(document), updatedAt: document.updatedAt)]
    }

    func touch(id: String, at date: Date, in context: ModelContext) throws {
        settings.settingsUpdatedAt = date
    }

    func apply(_ documents: [SyncDocument], in context: ModelContext) throws {
        for document in documents where document.id == Self.documentID && !document.deleted {
            let localUpdatedAt: Date? = isMeaningful ? settings.settingsUpdatedAt : nil
            guard SyncMerge.remoteWins(localUpdatedAt: localUpdatedAt, remote: document), let json = document.json,
                  let remote = try? SyncCodec.decode(ProfileDocument.self, from: json) else { continue }
            var pinned = remote
            pinned.updatedAt = document.updatedDate
            pinned.apply(to: settings)
        }
    }
}

// MARK: - Registration

enum SyncCollections {
    /// Registers every built-in collection. To add a new SwiftData model: conform it to
    /// `SyncableModel` (see `BodyScanSync.swift`) and add one line here.
    @MainActor
    static func registerAll(on engine: SyncEngine, settings: AppSettings) {
        engine.register(ModelSyncCollection<LogEntry>(name: SyncCollectionNames.logEntries))
        engine.register(ModelSyncCollection<FavoriteFood>(name: SyncCollectionNames.favorites))
        engine.register(ModelSyncCollection<BodyScan>(name: SyncCollectionNames.bodyScans))
        engine.register(SettingsSyncCollection(settings: settings))
    }
}
