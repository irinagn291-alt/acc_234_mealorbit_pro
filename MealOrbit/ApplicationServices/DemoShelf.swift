import Foundation

/// Onion ring: Application Services.
/// Bundled catalog so search and scan never dead-end without a network.
enum DemoShelf {
    static let payloads: [OrbitPayload] = [
        item(
            barcode: "0072700005005",
            name: "Apogee Eggs",
            brand: "Orbital Yard",
            kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5,
            asset: "mlo_SlotApogee"
        ),
        item(
            barcode: "0208570000000",
            name: "Zenith Beef Mince 5%",
            brand: "Station Butcher",
            kcal: 137, protein: 21.4, carbs: 0.0, fat: 5.0,
            asset: "mlo_SlotZenith"
        ),
        item(
            barcode: "5000232002501",
            name: "Perigee Smoked Mackerel",
            brand: "Dock Smokehouse",
            kcal: 254, protein: 18.9, carbs: 0.0, fat: 19.8,
            asset: "mlo_SlotPerigee"
        ),
        item(
            barcode: "7394376616037",
            name: "Drift Oat Milk",
            brand: "Lunar Dairy",
            kcal: 45, protein: 1.0, carbs: 6.7, fat: 1.5,
            asset: "mlo_SlotDrift"
        ),
        item(
            barcode: "3178530403022",
            name: "Station Butter",
            brand: "Habitat Creamery",
            kcal: 717, protein: 0.9, carbs: 0.1, fat: 81.1,
            asset: "mlo_MacroFat"
        ),
        item(
            barcode: "0029000016613",
            name: "Payload Mixed Nuts",
            brand: "Cargo Pantry",
            kcal: 607, protein: 20.0, carbs: 21.0, fat: 54.0,
            asset: "mlo_MacroProtein"
        )
    ]

    static func matching(_ query: String) -> [OrbitPayload] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return payloads }
        return payloads.filter { payload in
            payload.name.lowercased().contains(needle)
                || payload.brand.lowercased().contains(needle)
                || payload.barcode.contains(needle)
        }
    }

    static func payload(barcode: String) -> OrbitPayload? {
        payloads.first { $0.barcode == barcode }
    }

    private static func item(
        barcode: String,
        name: String,
        brand: String,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        asset: String
    ) -> OrbitPayload {
        OrbitPayload(
            barcode: barcode,
            name: name,
            brand: brand,
            mass: PayloadMass(kcal100: kcal, protein100: protein, carbs100: carbs, fat100: fat),
            imageURL: nil,
            bundledAsset: asset,
            refreshedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
