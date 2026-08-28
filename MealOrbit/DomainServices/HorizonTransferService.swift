import Foundation

/// Onion ring: Domain Services.
/// Pure relocator for the 14-day horizon. Drift on a future day remaps to Perigee.
enum HorizonTransferService {
    static let horizonLength = 14

    static func relocate(
        _ entry: ApogeeEntry,
        to window: HorizonAnchor,
        today: OrbitDayKey
    ) -> ApogeeEntry {
        var slot = window.slot
        var isEaten = entry.isEaten
        if window.dayKey > today {
            if slot == .drift {
                slot = .perigee
            }
            isEaten = false
        }
        if window.dayKey == today, slot == .drift {
            isEaten = true
        }
        return ApogeeEntry(
            id: entry.id,
            payload: entry.payload,
            grams: entry.grams,
            slot: slot,
            dayKey: window.dayKey,
            isEaten: isEaten,
            createdAt: entry.createdAt
        )
    }

    static func markEaten(_ entry: ApogeeEntry, today: OrbitDayKey) -> ApogeeEntry {
        ApogeeEntry(
            id: entry.id,
            payload: entry.payload,
            grams: entry.grams,
            slot: entry.slot,
            dayKey: today,
            isEaten: true,
            createdAt: entry.createdAt
        )
    }

    static func projectedKcal(entries: [ApogeeEntry]) -> Double {
        TelemetryService.dayTotals(entries: entries, eatenOnly: false).kcal100 ?? 0
    }

    static func eatenKcal(entries: [ApogeeEntry]) -> Double {
        TelemetryService.dayTotals(entries: entries, eatenOnly: true).kcal100 ?? 0
    }

    static func keys(from origin: OrbitDayKey, calendar: Calendar) -> [OrbitDayKey] {
        (0..<horizonLength).compactMap { OrbitDayKey.offset(origin, byDays: $0, calendar: calendar) }
    }

    static func grouped(_ entries: [ApogeeEntry]) -> [OrbitDayKey: [OrbitSlot: [ApogeeEntry]]] {
        var result: [OrbitDayKey: [OrbitSlot: [ApogeeEntry]]] = [:]
        for entry in entries {
            var slots = result[entry.dayKey] ?? [:]
            slots[entry.slot, default: []].append(entry)
            result[entry.dayKey] = slots
        }
        return result
    }
}
