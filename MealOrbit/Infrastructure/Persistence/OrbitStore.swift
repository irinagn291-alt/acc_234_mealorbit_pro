import Foundation
import SwiftData

/// Onion ring: Infrastructure / Persistence.
/// Single ModelContainer, created once and injected. Failure is recoverable.
@MainActor
final class OrbitStore {
    let container: ModelContainer?
    let faultMessage: String?

    init(inMemory: Bool) {
        let schema = Schema(versionedSchema: OrbitSchemaV1.self)
        let configuration = ModelConfiguration(
            "MealOrbitVault",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: OrbitMigrationPlan.self,
                configurations: configuration
            )
            faultMessage = nil
        } catch {
            container = nil
            faultMessage = "The local vault could not be opened. Retry after a reset, or reinstall MealOrbit."
        }
    }
}

/// Onion ring: Infrastructure / Persistence.
/// SwiftData seam. UI and application services never touch `@Model` types.
@MainActor
final class SwiftDataOrbitVault: PayloadVault, EntryVault, TargetVault, WishVault {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func cached(barcode: String) async throws -> OrbitPayload? {
        try window(barcode: barcode)?.asPayload()
    }

    func save(_ payload: OrbitPayload) async throws {
        let record = try upsertWindow(payload)
        record.apply(payload)
        try context.save()
    }

    func allCached() async throws -> [OrbitPayload] {
        let descriptor = FetchDescriptor<TransferWindow>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map { $0.asPayload() }
    }

    func entries(dayKey: OrbitDayKey) async throws -> [ApogeeEntry] {
        let key = dayKey.raw
        let descriptor = FetchDescriptor<OrbitEntry>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).compactMap { $0.asEntry() }
    }

    func entries(from start: OrbitDayKey, to end: OrbitDayKey) async throws -> [ApogeeEntry] {
        let startRaw = start.raw
        let endRaw = end.raw
        let descriptor = FetchDescriptor<OrbitEntry>(
            predicate: #Predicate { entry in
                entry.dayKey >= startRaw && entry.dayKey <= endRaw
            },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).compactMap { $0.asEntry() }
    }

    func upsert(_ entry: ApogeeEntry) async throws {
        let window = try upsertWindow(entry.payload)
        let identifier = entry.id
        var descriptor = FetchDescriptor<OrbitEntry>(predicate: #Predicate { $0.entryId == identifier })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.grams = entry.grams
            existing.slotRaw = entry.slot.rawValue
            existing.dayKey = entry.dayKey.raw
            existing.isEaten = entry.isEaten
            existing.payload = window
        } else {
            context.insert(
                OrbitEntry(
                    entryId: entry.id,
                    grams: entry.grams,
                    slotRaw: entry.slot.rawValue,
                    dayKey: entry.dayKey.raw,
                    isEaten: entry.isEaten,
                    createdAt: entry.createdAt,
                    payload: window
                )
            )
        }
        try context.save()
    }

    func delete(id: UUID) async throws {
        let identifier = id
        let descriptor = FetchDescriptor<OrbitEntry>(predicate: #Predicate { $0.entryId == identifier })
        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
        try context.save()
    }

    func resetAll() async throws {
        try deleteAll(OrbitEntry.self)
        try deleteAll(WishChip.self)
        try deleteAll(MassTarget.self)
        try deleteAll(TransferWindow.self)
        try context.save()
        try seedShelf()
        try seedTargetsIfNeeded()
    }

    func load() async throws -> OrbitTargets {
        try seedTargetsIfNeeded()
        let descriptor = FetchDescriptor<MassTarget>()
        if let record = try context.fetch(descriptor).first {
            return record.asTargets()
        }
        return .sensibleDefaults
    }

    func save(_ targets: OrbitTargets) async throws {
        let descriptor = FetchDescriptor<MassTarget>()
        if let record = try context.fetch(descriptor).first {
            record.kcal = targets.kcal
            record.protein = targets.protein
            record.carbs = targets.carbs
            record.fat = targets.fat
        } else {
            context.insert(
                MassTarget(
                    kcal: targets.kcal,
                    protein: targets.protein,
                    carbs: targets.carbs,
                    fat: targets.fat
                )
            )
        }
        try context.save()
    }

    func all() async throws -> [AcquisitionChip] {
        let descriptor = FetchDescriptor<WishChip>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return try context.fetch(descriptor).compactMap { $0.asChip() }
    }

    func upsert(_ chip: AcquisitionChip) async throws {
        let window = try upsertWindow(chip.payload)
        let code = chip.payload.barcode
        let descriptor = FetchDescriptor<WishChip>()
        if let existing = try context.fetch(descriptor).first(where: { $0.payload?.barcode == code }) {
            existing.addedAt = chip.addedAt
            existing.payload = window
        } else {
            context.insert(WishChip(addedAt: chip.addedAt, payload: window))
        }
        try context.save()
    }

    func delete(barcode: String) async throws {
        let descriptor = FetchDescriptor<WishChip>()
        for record in try context.fetch(descriptor) where record.payload?.barcode == barcode {
            context.delete(record)
        }
        try context.save()
    }

    func seedShelf() throws {
        for payload in DemoShelf.payloads {
            let record = try upsertWindow(payload)
            record.apply(payload)
        }
        try context.save()
    }

    func seedTargetsIfNeeded() throws {
        let descriptor = FetchDescriptor<MassTarget>()
        if try context.fetch(descriptor).isEmpty {
            let defaults = OrbitTargets.sensibleDefaults
            context.insert(
                MassTarget(
                    kcal: defaults.kcal,
                    protein: defaults.protein,
                    carbs: defaults.carbs,
                    fat: defaults.fat
                )
            )
            try context.save()
        }
    }

    private func window(barcode: String) throws -> TransferWindow? {
        let code = barcode
        var descriptor = FetchDescriptor<TransferWindow>(predicate: #Predicate { $0.barcode == code })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    private func upsertWindow(_ payload: OrbitPayload) throws -> TransferWindow {
        if let existing = try window(barcode: payload.barcode) {
            return existing
        }
        let created = TransferWindow(
            barcode: payload.barcode,
            name: payload.name,
            brand: payload.brand,
            kcal100: payload.mass.kcal100,
            protein100: payload.mass.protein100,
            carbs100: payload.mass.carbs100,
            fat100: payload.mass.fat100,
            imageURL: payload.imageURL,
            bundledAsset: payload.bundledAsset,
            refreshedAt: payload.refreshedAt
        )
        context.insert(created)
        return created
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for record in try context.fetch(FetchDescriptor<T>()) {
            context.delete(record)
        }
    }
}

/// Onion ring: Infrastructure / Persistence.
/// Background mutations hop here and fetch by identifier, never by live models.
@ModelActor
actor OrbitModelActor {
    func ping() throws -> Int {
        let descriptor = FetchDescriptor<TransferWindow>()
        return try modelContext.fetch(descriptor).count
    }
}

/// Onion ring: Infrastructure / Persistence.
/// Launch flags. Key `mlo.demo.v1` runs the simulator seed exactly once.
@MainActor
final class UserDefaultsLaunchFlags: LaunchFlags {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var didCompleteLaunchSequence: Bool {
        get { defaults.bool(forKey: "mlo.launch.v1") }
        set { defaults.set(newValue, forKey: "mlo.launch.v1") }
    }

    var didSeedDemoDay: Bool {
        get { defaults.bool(forKey: "mlo.demo.v1") }
        set { defaults.set(newValue, forKey: "mlo.demo.v1") }
    }

    var lastRouteRaw: String? {
        get { defaults.string(forKey: "mlo.route") }
        set { defaults.set(newValue, forKey: "mlo.route") }
    }
}
