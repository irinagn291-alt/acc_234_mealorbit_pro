import Foundation

/// Onion ring: Domain Model.
/// Four orbital meal windows. Drift is a snack — eaten only, never planned ahead.
enum OrbitSlot: String, CaseIterable, Codable, Sendable, Hashable {
    case apogee
    case zenith
    case perigee
    case drift

    var displayName: String {
        switch self {
        case .apogee: "Apogee"
        case .zenith: "Zenith"
        case .perigee: "Perigee"
        case .drift: "Drift"
        }
    }

    var canBePlanned: Bool {
        self != .drift
    }

    var assetName: String {
        switch self {
        case .apogee: "mlo_SlotApogee"
        case .zenith: "mlo_SlotZenith"
        case .perigee: "mlo_SlotPerigee"
        case .drift: "mlo_SlotDrift"
        }
    }

    var sortIndex: Int {
        switch self {
        case .apogee: 0
        case .zenith: 1
        case .perigee: 2
        case .drift: 3
        }
    }
}

/// Onion ring: Domain Model.
/// Calendar day as `yyyy-MM-dd`. Used in storage, queries and identifiers.
struct OrbitDayKey: Hashable, Codable, Sendable, Comparable, RawRepresentable {
    let raw: String

    var rawValue: String { raw }

    init(rawValue: String) {
        self.raw = rawValue
    }

    init(_ raw: String) {
        self.raw = raw
    }

    static func < (lhs: OrbitDayKey, rhs: OrbitDayKey) -> Bool {
        lhs.raw < rhs.raw
    }
}

/// Onion ring: Domain Model.
/// Typed failures the UI can present without reading infrastructure types.
enum CatalogFault: Error, Equatable, Sendable {
    case transport
    case notFound
    case missingEnergy
    case decoding
    case cancelled
    case invalidGrams
}

/// Onion ring: Domain Model.
/// Per-100 g nutriments. Missing macros stay `nil` — never coerced to zero.
struct PayloadMass: Equatable, Hashable, Codable, Sendable {
    var kcal100: Double?
    var protein100: Double?
    var carbs100: Double?
    var fat100: Double?
}

/// Onion ring: Domain Model.
/// A catalog product resolved from Open Food Facts or the local shelf.
struct OrbitPayload: Equatable, Hashable, Codable, Sendable, Identifiable {
    var barcode: String
    var name: String
    var brand: String
    var mass: PayloadMass
    var imageURL: String?
    var bundledAsset: String?
    var refreshedAt: Date

    var id: String { barcode }
}

/// Onion ring: Domain Model.
/// One logged or planned portion locked into an orbit window.
struct ApogeeEntry: Equatable, Hashable, Codable, Sendable, Identifiable {
    var id: UUID
    var payload: OrbitPayload
    var grams: Double
    var slot: OrbitSlot
    var dayKey: OrbitDayKey
    var isEaten: Bool
    var createdAt: Date
}

/// Onion ring: Domain Model.
/// Daily energy and macro targets. Zero is not a valid shipped value.
struct OrbitTargets: Equatable, Hashable, Codable, Sendable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let sensibleDefaults = OrbitTargets(kcal: 2100, protein: 140, carbs: 220, fat: 70)
}

/// Onion ring: Domain Model.
/// A product the operator intends to acquire. Unique by barcode.
struct AcquisitionChip: Equatable, Hashable, Codable, Sendable, Identifiable {
    var payload: OrbitPayload
    var addedAt: Date

    var id: String { payload.barcode }
}

/// Onion ring: Domain Model.
/// One cell in the fourteen-day horizon — a day plus a slot.
struct HorizonAnchor: Equatable, Hashable, Codable, Sendable {
    var dayKey: OrbitDayKey
    var slot: OrbitSlot
}

/// Onion ring: Domain Model.
/// Computed 14-day plan. Never persisted as a blob; derived from entries.
struct OrbitPlan: Equatable, Sendable {
    var origin: OrbitDayKey
    var entries: [ApogeeEntry]
    var targets: OrbitTargets

    var dayKeys: [OrbitDayKey] {
        (0..<14).compactMap { offset in
            OrbitDayKey.offset(origin, byDays: offset)
        }
    }
}

extension OrbitDayKey {
    static func make(from date: Date, calendar: Calendar) -> OrbitDayKey {
        let start = calendar.startOfDay(for: date)
        return OrbitDayKey(posixDayString(from: start, calendar: calendar))
    }

    static func offset(_ key: OrbitDayKey, byDays days: Int, calendar: Calendar = Calendar.current) -> OrbitDayKey? {
        guard let date = key.date(calendar: calendar) else { return nil }
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return make(from: shifted, calendar: calendar)
    }

    func date(calendar: Calendar) -> Date? {
        var components = DateComponents()
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private static func posixDayString(from date: Date, calendar: Calendar) -> String {
        let pieces = calendar.dateComponents([.year, .month, .day], from: date)
        let year = pieces.year ?? 0
        let month = pieces.month ?? 0
        let day = pieces.day ?? 0
        let monthText = month < 10 ? "0\(month)" : "\(month)"
        let dayText = day < 10 ? "0\(day)" : "\(day)"
        return "\(year)-\(monthText)-\(dayText)"
    }
}
