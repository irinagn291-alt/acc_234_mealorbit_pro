import Foundation

/// Onion ring: Domain Model.
/// Port for the local payload cache. Implemented in Persistence.
@MainActor
protocol PayloadVault: AnyObject {
    func cached(barcode: String) async throws -> OrbitPayload?
    func save(_ payload: OrbitPayload) async throws
    func allCached() async throws -> [OrbitPayload]
}

/// Onion ring: Domain Model.
/// Port for eaten and planned entries.
@MainActor
protocol EntryVault: AnyObject {
    func entries(dayKey: OrbitDayKey) async throws -> [ApogeeEntry]
    func entries(from start: OrbitDayKey, to end: OrbitDayKey) async throws -> [ApogeeEntry]
    func upsert(_ entry: ApogeeEntry) async throws
    func delete(id: UUID) async throws
    func resetAll() async throws
}

/// Onion ring: Domain Model.
/// Port for daily mass targets.
@MainActor
protocol TargetVault: AnyObject {
    func load() async throws -> OrbitTargets
    func save(_ targets: OrbitTargets) async throws
}

/// Onion ring: Domain Model.
/// Port for the acquisition (wish) list.
@MainActor
protocol WishVault: AnyObject {
    func all() async throws -> [AcquisitionChip]
    func upsert(_ chip: AcquisitionChip) async throws
    func delete(barcode: String) async throws
}

/// Onion ring: Domain Model.
/// Port for Open Food Facts. Implemented in Network.
protocol CatalogGateway: Sendable {
    func search(terms: String) async throws -> [OrbitPayload]
    func fetch(barcode: String) async throws -> OrbitPayload
}
