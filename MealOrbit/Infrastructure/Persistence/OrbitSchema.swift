import Foundation
import SwiftData

/// Onion ring: Infrastructure / Persistence.
/// Version 1 schema. A migration plan exists from day one even with no stages yet.
enum OrbitSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [OrbitEntry.self, TransferWindow.self, MassTarget.self, WishChip.self]
    }
}

enum OrbitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OrbitSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Onion ring: Infrastructure / Persistence.
/// Cached catalog payload. Unique barcode behaves as an upsert key.
@Model
final class TransferWindow {
    @Attribute(.unique) var barcode: String
    var name: String
    var brand: String
    var kcal100: Double?
    var protein100: Double?
    var carbs100: Double?
    var fat100: Double?
    var imageURL: String?
    var bundledAsset: String?
    var refreshedAt: Date
    @Relationship(deleteRule: .nullify, inverse: \OrbitEntry.payload)
    var entries: [OrbitEntry]
    @Relationship(deleteRule: .nullify, inverse: \WishChip.payload)
    var wishes: [WishChip]

    init(
        barcode: String,
        name: String,
        brand: String,
        kcal100: Double?,
        protein100: Double?,
        carbs100: Double?,
        fat100: Double?,
        imageURL: String?,
        bundledAsset: String?,
        refreshedAt: Date
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.kcal100 = kcal100
        self.protein100 = protein100
        self.carbs100 = carbs100
        self.fat100 = fat100
        self.imageURL = imageURL
        self.bundledAsset = bundledAsset
        self.refreshedAt = refreshedAt
        self.entries = []
        self.wishes = []
    }

    func apply(_ payload: OrbitPayload) {
        name = payload.name
        brand = payload.brand
        kcal100 = payload.mass.kcal100
        protein100 = payload.mass.protein100
        carbs100 = payload.mass.carbs100
        fat100 = payload.mass.fat100
        imageURL = payload.imageURL
        if let bundled = payload.bundledAsset {
            bundledAsset = bundled
        }
        refreshedAt = payload.refreshedAt
    }

    func asPayload() -> OrbitPayload {
        OrbitPayload(
            barcode: barcode,
            name: name,
            brand: brand,
            mass: PayloadMass(kcal100: kcal100, protein100: protein100, carbs100: carbs100, fat100: fat100),
            imageURL: imageURL,
            bundledAsset: bundledAsset,
            refreshedAt: refreshedAt
        )
    }
}

/// Onion ring: Infrastructure / Persistence.
/// Eaten or planned portion. `dayKey` is `yyyy-MM-dd`.
@Model
final class OrbitEntry {
    var entryId: UUID
    var grams: Double
    var slotRaw: String
    var dayKey: String
    var isEaten: Bool
    var createdAt: Date
    var payload: TransferWindow?

    init(
        entryId: UUID,
        grams: Double,
        slotRaw: String,
        dayKey: String,
        isEaten: Bool,
        createdAt: Date,
        payload: TransferWindow?
    ) {
        self.entryId = entryId
        self.grams = grams
        self.slotRaw = slotRaw
        self.dayKey = dayKey
        self.isEaten = isEaten
        self.createdAt = createdAt
        self.payload = payload
    }

    func asEntry() -> ApogeeEntry? {
        guard let payload, let slot = OrbitSlot(rawValue: slotRaw) else { return nil }
        return ApogeeEntry(
            id: entryId,
            payload: payload.asPayload(),
            grams: grams,
            slot: slot,
            dayKey: OrbitDayKey(dayKey),
            isEaten: isEaten,
            createdAt: createdAt
        )
    }
}

/// Onion ring: Infrastructure / Persistence.
/// Singleton-style daily mass targets.
@Model
final class MassTarget {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    func asTargets() -> OrbitTargets {
        OrbitTargets(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }
}

/// Onion ring: Infrastructure / Persistence.
/// Acquisition list row. Uniqueness is enforced via the payload barcode.
@Model
final class WishChip {
    var addedAt: Date
    var payload: TransferWindow?

    init(addedAt: Date, payload: TransferWindow?) {
        self.addedAt = addedAt
        self.payload = payload
    }

    func asChip() -> AcquisitionChip? {
        guard let payload else { return nil }
        return AcquisitionChip(payload: payload.asPayload(), addedAt: addedAt)
    }
}
