import XCTest
import SwiftData
@testable import MealOrbit

final class PortionMathsTests: XCTestCase {
    func testKilocaloriePath() {
        let kcal = TelemetryService.kcal100(energyKcal: 200, energyKj: 900)
        XCTAssertEqual(kcal, 200)
        let portion = TelemetryService.scaled(per100: kcal, grams: 50)
        XCTAssertEqual(portion, 100)
    }

    func testKilojouleFallback() {
        let kcal = TelemetryService.kcal100(energyKcal: nil, energyKj: 418.4)
        XCTAssertEqual(kcal ?? 0, 100, accuracy: 0.001)
    }

    func testMissingEnergyStaysMissing() {
        XCTAssertNil(TelemetryService.kcal100(energyKcal: nil, energyKj: nil))
        XCTAssertNil(TelemetryService.scaled(per100: nil, grams: 80))
    }
}

final class BarcodeNormaliserTests: XCTestCase {
    func testEAN8() {
        XCTAssertEqual(TelemetryService.normalisedBarcode(from: "12345670"), "12345670")
    }

    func testEAN13() {
        XCTAssertEqual(TelemetryService.normalisedBarcode(from: "3017620422003"), "3017620422003")
    }

    func testUPCAPadding() {
        XCTAssertEqual(TelemetryService.normalisedBarcode(from: "012345678905"), "0012345678905")
    }

    func testURLInput() {
        let raw = "https://world.openfoodfacts.org/product/3017620422003/nutella"
        XCTAssertEqual(TelemetryService.normalisedBarcode(from: raw), "3017620422003")
    }

    func testNoValidRun() {
        XCTAssertNil(TelemetryService.normalisedBarcode(from: "no-digits-here"))
        XCTAssertTrue(TelemetryService.barcodeCandidates(from: "123").isEmpty)
    }
}

final class MissingMacroTests: XCTestCase {
    func testUnknownStaysUnknown() {
        let mass = PayloadMass(kcal100: 120, protein100: nil, carbs100: 4, fat100: nil)
        let portion = TelemetryService.portion(mass: mass, grams: 50)
        XCTAssertEqual(portion.kcal100, 60)
        XCTAssertNil(portion.protein100)
        XCTAssertEqual(portion.carbs100, 2)
        XCTAssertNil(portion.fat100)
        XCTAssertNotEqual(portion.protein100, 0)
        XCTAssertNotEqual(portion.fat100, 0)
    }
}

final class DayTotalTests: XCTestCase {
    func testAggregationAcrossFourSlots() {
        let payload = DemoShelf.payloads[0]
        let day = OrbitDayKey("2026-08-27")
        func entry(_ grams: Double, _ slot: OrbitSlot, eaten: Bool = true) -> ApogeeEntry {
            ApogeeEntry(
                id: UUID(),
                payload: payload,
                grams: grams,
                slot: slot,
                dayKey: day,
                isEaten: eaten,
                createdAt: Date(timeIntervalSince1970: 0)
            )
        }
        let entries = [
            entry(100, .apogee),
            entry(100, .zenith),
            entry(100, .perigee),
            entry(100, .drift),
            entry(500, .apogee, eaten: false)
        ]
        let totals = TelemetryService.dayTotals(entries: entries, eatenOnly: true)
        XCTAssertEqual(totals.kcal100, 143 * 4)
        XCTAssertEqual(totals.protein100 ?? 0, 12.6 * 4, accuracy: 0.001)
        let projected = TelemetryService.dayTotals(entries: entries, eatenOnly: false)
        XCTAssertEqual(projected.kcal100, 143 * 9)
    }
}

final class WishUniquenessTests: XCTestCase {
    func testDuplicateUpdatesExisting() {
        let first = AcquisitionChip(payload: DemoShelf.payloads[0], addedAt: Date(timeIntervalSince1970: 1))
        let second = AcquisitionChip(payload: DemoShelf.payloads[0], addedAt: Date(timeIntervalSince1970: 2))
        let other = AcquisitionChip(payload: DemoShelf.payloads[1], addedAt: Date(timeIntervalSince1970: 3))
        let merged = WishUniquenessService.merging(WishUniquenessService.merging([first], with: second), with: other)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.payload.barcode == first.payload.barcode }?.addedAt, second.addedAt)
        XCTAssertTrue(WishUniquenessService.contains(merged, barcode: other.payload.barcode))
    }
}

final class DayBoundaryTests: XCTestCase {
    func testSpringForwardSameDayKey() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 30)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 15)))
        XCTAssertEqual(
            DayBoundaryService.key(for: morning, calendar: calendar),
            DayBoundaryService.key(for: evening, calendar: calendar)
        )
        XCTAssertEqual(DayBoundaryService.key(for: morning, calendar: calendar).raw, "2026-03-08")
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: morning))
        XCTAssertEqual(DayBoundaryService.key(for: next, calendar: calendar).raw, "2026-03-09")
    }

    func testFallBackLongDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 15)))
        let late = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 22, minute: 45)))
        XCTAssertTrue(DayBoundaryService.isSameDay(morning, late, calendar: calendar))
        XCTAssertEqual(DayBoundaryService.key(for: morning, calendar: calendar).raw, "2026-11-01")
    }
}

final class DecodingTests: XCTestCase {
    func testStringEncodedAndMissingNutriments() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": 3017620422003,
            "product_name": "",
            "generic_name": "Hazelnut spread",
            "brands": "Orbital Pantry",
            "nutriments": {
              "energy-kcal_100g": "539",
              "energy_100g": 2255,
              "proteins_100g": "6.3",
              "carbohydrates_100g": 57.5
            }
          }
        }
        """.data(using: .utf8)
        let data = try XCTUnwrap(json)
        let document = try JSONDecoder().decode(ProductDocumentDTO.self, from: data)
        let payload = try XCTUnwrap(document.product?.mappedPayload())
        XCTAssertEqual(payload.name, "Hazelnut spread")
        XCTAssertEqual(payload.barcode, "3017620422003")
        XCTAssertEqual(payload.mass.kcal100, 539)
        XCTAssertEqual(payload.mass.protein100, 6.3)
        XCTAssertEqual(payload.mass.carbs100, 57.5)
        XCTAssertNil(payload.mass.fat100)
    }

    func testStatusZeroIsNotFoundShape() throws {
        let json = """
        {"status": 0, "status_verbose": "product not found"}
        """.data(using: .utf8)
        let document = try JSONDecoder().decode(ProductDocumentDTO.self, from: try XCTUnwrap(json))
        XCTAssertEqual(document.status, 0)
        XCTAssertNil(document.product?.mappedPayload())
    }

    func testKilojouleOnlyNutriment() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": "12345670",
            "product_name": "Test",
            "nutriments": { "energy_100g": "418.4" }
          }
        }
        """.data(using: .utf8)
        let payload = try XCTUnwrap(try JSONDecoder().decode(ProductDocumentDTO.self, from: try XCTUnwrap(json)).product?.mappedPayload())
        XCTAssertEqual(payload.mass.kcal100 ?? 0, 100, accuracy: 0.01)
    }
}

final class HorizonTwistTests: XCTestCase {
    func testDragToFutureRemapsDriftAndClearsEaten() {
        let origin = ApogeeEntry(
            id: UUID(),
            payload: DemoShelf.payloads[3],
            grams: 250,
            slot: .drift,
            dayKey: OrbitDayKey("2026-08-27"),
            isEaten: true,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let moved = HorizonTransferService.relocate(
            origin,
            to: HorizonAnchor(dayKey: OrbitDayKey("2026-08-29"), slot: .drift),
            today: OrbitDayKey("2026-08-27")
        )
        XCTAssertEqual(moved.slot, .perigee)
        XCTAssertFalse(moved.isEaten)
        XCTAssertEqual(moved.dayKey.raw, "2026-08-29")
        XCTAssertEqual(moved.id, origin.id)
    }

    func testProjectedKcalAgainstTarget() {
        let day = OrbitDayKey("2026-08-28")
        let entries = [
            ApogeeEntry(
                id: UUID(),
                payload: DemoShelf.payloads[0],
                grams: 100,
                slot: .apogee,
                dayKey: day,
                isEaten: false,
                createdAt: Date(timeIntervalSince1970: 0)
            )
        ]
        XCTAssertEqual(HorizonTransferService.projectedKcal(entries: entries), 143)
        XCTAssertEqual(HorizonTransferService.eatenKcal(entries: entries), 0)
    }

    func testMarkEatenWhenDayArrives() {
        let planned = ApogeeEntry(
            id: UUID(),
            payload: DemoShelf.payloads[1],
            grams: 150,
            slot: .zenith,
            dayKey: OrbitDayKey("2026-08-28"),
            isEaten: false,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let eaten = HorizonTransferService.markEaten(planned, today: OrbitDayKey("2026-08-27"))
        XCTAssertTrue(eaten.isEaten)
        XCTAssertEqual(eaten.dayKey.raw, "2026-08-27")
    }
}

final class OnionArchitectureTests: XCTestCase {
    func testDomainRingsDoNotImportOuterRings() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MealOrbit")
        try assertFolder(root.appendingPathComponent("DomainModel"), forbids: [
            "import SwiftUI", "import UIKit", "import SwiftData", "import VisionKit", "import Combine"
        ])
        try assertFolder(root.appendingPathComponent("DomainServices"), forbids: [
            "import SwiftUI", "import UIKit", "import SwiftData", "import VisionKit"
        ])
        try assertFolder(root.appendingPathComponent("ApplicationServices"), forbids: [
            "import SwiftUI", "import UIKit", "import SwiftData", "import VisionKit"
        ])
    }

    func testIllegalFutureDriftTransitionIsRejectedByPureRelocator() {
        let entry = ApogeeEntry(
            id: UUID(),
            payload: DemoShelf.payloads[3],
            grams: 200,
            slot: .apogee,
            dayKey: OrbitDayKey("2026-08-27"),
            isEaten: false,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let result = HorizonTransferService.relocate(
            entry,
            to: HorizonAnchor(dayKey: OrbitDayKey("2026-09-01"), slot: .drift),
            today: OrbitDayKey("2026-08-27")
        )
        XCTAssertNotEqual(result.slot, .drift)
        XCTAssertEqual(result.slot, .perigee)
    }

    private func assertFolder(_ folder: URL, forbids tokens: [String]) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "Missing sources at \(folder.path)")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in tokens {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) must not contain \(token)")
            }
        }
    }
}

@MainActor
final class PersistenceRoundTripTests: XCTestCase {
    func testInMemoryWriteReload() async throws {
        let store = OrbitStore(inMemory: true)
        let container = try XCTUnwrap(store.container)
        let writer = SwiftDataOrbitVault(container: container)
        try writer.seedShelf()
        let payload = DemoShelf.payloads[0]
        let entry = ApogeeEntry(
            id: UUID(),
            payload: payload,
            grams: 87.5,
            slot: .zenith,
            dayKey: OrbitDayKey("2026-08-27"),
            isEaten: true,
            createdAt: Date(timeIntervalSince1970: 42)
        )
        try await writer.upsert(entry)
        try await writer.upsert(AcquisitionChip(payload: payload, addedAt: Date(timeIntervalSince1970: 42)))
        try await writer.save(OrbitTargets(kcal: 1900, protein: 130, carbs: 200, fat: 60))

        let reader = SwiftDataOrbitVault(container: container)
        let loaded = try await reader.entries(dayKey: OrbitDayKey("2026-08-27"))
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.grams, 87.5)
        XCTAssertEqual(loaded.first?.slot, .zenith)
        XCTAssertEqual(loaded.first?.payload.barcode, payload.barcode)
        let wishes = try await reader.all()
        XCTAssertEqual(wishes.count, 1)
        let targets = try await reader.load()
        XCTAssertEqual(targets.kcal, 1900)
        let cached = try await reader.cached(barcode: payload.barcode)
        XCTAssertEqual(cached?.name, payload.name)
    }
}
