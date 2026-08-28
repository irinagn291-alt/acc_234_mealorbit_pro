import Foundation

/// Onion ring: Domain Services.
/// Portion maths, barcode normalisation, day totals. Pure functions, no I/O.
enum TelemetryService {
    static let kilojoulesPerKilocalorie = 4.184
    static let maximumGrams = 10_000.0

    static func kcal100(energyKcal: Double?, energyKj: Double?) -> Double? {
        if let energyKcal {
            return energyKcal
        }
        if let energyKj {
            return energyKj / kilojoulesPerKilocalorie
        }
        return nil
    }

    static func scaled(per100: Double?, grams: Double) -> Double? {
        guard let per100 else { return nil }
        return per100 * grams / 100.0
    }

    static func portion(mass: PayloadMass, grams: Double) -> PayloadMass {
        PayloadMass(
            kcal100: scaled(per100: mass.kcal100, grams: grams),
            protein100: scaled(per100: mass.protein100, grams: grams),
            carbs100: scaled(per100: mass.carbs100, grams: grams),
            fat100: scaled(per100: mass.fat100, grams: grams)
        )
    }

    static func isGramsAcceptable(_ grams: Double) -> Bool {
        grams > 0 && grams <= maximumGrams && grams.isFinite
    }

    /// Digit runs of length 8...14. A 12-digit UPC-A run is prefixed with `0`.
    static func barcodeCandidates(from raw: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in raw {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        var result: [String] = []
        var seen: Set<String> = []
        for run in runs where (8...14).contains(run.count) {
            let normalised: String
            if run.count == 12 {
                normalised = "0" + run
            } else {
                normalised = run
            }
            if seen.insert(normalised).inserted {
                result.append(normalised)
            }
            if run.count == 12, seen.insert(run).inserted {
                result.append(run)
            }
        }
        return result
    }

    static func normalisedBarcode(from raw: String) -> String? {
        barcodeCandidates(from: raw).first
    }

    static func dayTotals(entries: [ApogeeEntry], eatenOnly: Bool) -> PayloadMass {
        var kcal: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        for entry in entries where !eatenOnly || entry.isEaten {
            let portion = portion(mass: entry.payload.mass, grams: entry.grams)
            kcal = sumOptional(kcal, portion.kcal100)
            protein = sumOptional(protein, portion.protein100)
            carbs = sumOptional(carbs, portion.carbs100)
            fat = sumOptional(fat, portion.fat100)
        }
        return PayloadMass(kcal100: kcal, protein100: protein, carbs100: carbs, fat100: fat)
    }

    static func remaining(targets: OrbitTargets, consumed: PayloadMass) -> PayloadMass {
        PayloadMass(
            kcal100: targets.kcal - (consumed.kcal100 ?? 0),
            protein100: targets.protein - (consumed.protein100 ?? 0),
            carbs100: targets.carbs - (consumed.carbs100 ?? 0),
            fat100: targets.fat - (consumed.fat100 ?? 0)
        )
    }

    static func percent(consumed: Double?, target: Double) -> Double? {
        guard target > 0, let consumed else { return nil }
        return consumed / target
    }

    private static func sumOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (let left?, nil): left
        case (nil, let right?): right
        case (let left?, let right?): left + right
        }
    }
}

/// Onion ring: Domain Services.
/// Day-boundary rules using the operator's calendar, including DST short and long days.
enum DayBoundaryService {
    static func key(for date: Date, calendar: Calendar) -> OrbitDayKey {
        OrbitDayKey.make(from: date, calendar: calendar)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }
}

/// Onion ring: Domain Services.
/// Wish-list uniqueness: a second add for the same barcode updates the existing chip.
enum WishUniquenessService {
    static func merging(_ chips: [AcquisitionChip], with incoming: AcquisitionChip) -> [AcquisitionChip] {
        if let index = chips.firstIndex(where: { $0.payload.barcode == incoming.payload.barcode }) {
            var copy = chips
            copy[index] = incoming
            return copy
        }
        return chips + [incoming]
    }

    static func contains(_ chips: [AcquisitionChip], barcode: String) -> Bool {
        chips.contains { $0.payload.barcode == barcode }
    }
}
