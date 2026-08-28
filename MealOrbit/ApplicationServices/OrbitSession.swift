import Combine
import Foundation

/// Onion ring: Application Services.
/// UserDefaults-backed flags. The keys themselves live here so UI never invents them.
@MainActor
protocol LaunchFlags: AnyObject {
    var didCompleteLaunchSequence: Bool { get set }
    var didSeedDemoDay: Bool { get set }
    var lastRouteRaw: String? { get set }
}

enum SearchPhase: Equatable, Sendable {
    case idle
    case loading
    case results
    case empty
    case transport
}

/// Onion ring: Application Services.
/// Orchestrates vaults, catalog and domain services for the UI. No SwiftData, no UIKit.
@MainActor
final class OrbitSession: ObservableObject {
    @Published private(set) var todayKey: OrbitDayKey
    @Published private(set) var entriesToday: [ApogeeEntry] = []
    @Published private(set) var horizonEntries: [ApogeeEntry] = []
    @Published private(set) var targets: OrbitTargets = .sensibleDefaults
    @Published private(set) var wishes: [AcquisitionChip] = []
    @Published private(set) var searchHits: [OrbitPayload] = []
    @Published private(set) var searchPhase: SearchPhase = .idle
    @Published private(set) var searchNotice: String?
    @Published private(set) var resolvedPayload: OrbitPayload?
    @Published private(set) var resolveFault: CatalogFault?
    @Published private(set) var isResolving = false
    @Published private(set) var isMutating = false
    @Published private(set) var lastCommittedId: UUID?
    @Published private(set) var didCompleteLaunchSequence: Bool
    @Published private(set) var focusedLogEntries: [ApogeeEntry] = []
    @Published private(set) var vaultNotice: String?
    @Published var searchText = ""

    let vaultReady: Bool

    private let payloads: any PayloadVault
    private let logs: any EntryVault
    private let targetVault: any TargetVault
    private let wishVault: any WishVault
    private let catalog: any CatalogGateway
    private let flags: any LaunchFlags
    private let calendar: Calendar
    private var searchTask: Task<Void, Never>?
    private var spinnerTask: Task<Void, Never>?

    init(
        payloads: any PayloadVault,
        logs: any EntryVault,
        targetVault: any TargetVault,
        wishVault: any WishVault,
        catalog: any CatalogGateway,
        flags: any LaunchFlags,
        vaultReady: Bool,
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) {
        self.payloads = payloads
        self.logs = logs
        self.targetVault = targetVault
        self.wishVault = wishVault
        self.catalog = catalog
        self.flags = flags
        self.vaultReady = vaultReady
        self.calendar = calendar
        self.todayKey = OrbitDayKey.make(from: now, calendar: calendar)
        self.didCompleteLaunchSequence = flags.didCompleteLaunchSequence
    }

    func bootstrap() async {
        refreshDayKey()
        guard vaultReady else { return }
        do {
            try await seedShelfQuietly()
            try await seedDemoDayIfNeeded()
            try await reload()
        } catch {
            vaultNotice = "The local vault failed to refresh. Reset from Mass Targets if this persists."
        }
    }

    func refreshDayKey() {
        todayKey = OrbitDayKey.make(from: Date(), calendar: calendar)
    }

    func reload() async throws {
        refreshDayKey()
        targets = try await targetVault.load()
        entriesToday = try await logs.entries(dayKey: todayKey)
        let end = OrbitDayKey.offset(todayKey, byDays: HorizonTransferService.horizonLength - 1, calendar: calendar) ?? todayKey
        horizonEntries = try await logs.entries(from: todayKey, to: end)
        wishes = try await wishVault.all()
        focusedLogEntries = try await logs.entries(dayKey: todayKey)
        didCompleteLaunchSequence = flags.didCompleteLaunchSequence
    }

    func focusLog(day: OrbitDayKey) async {
        focusedLogEntries = (try? await logs.entries(dayKey: day)) ?? []
    }

    func completeLaunchSequence(targets incoming: OrbitTargets) async throws {
        try await targetVault.save(incoming)
        flags.didCompleteLaunchSequence = true
        didCompleteLaunchSequence = true
        targets = incoming
        try await reload()
    }

    func rerunLaunchSequence() {
        flags.didCompleteLaunchSequence = false
        didCompleteLaunchSequence = false
    }

    func updateSearch(_ text: String) {
        searchText = text
        searchTask?.cancel()
        spinnerTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchHits = []
            searchPhase = .idle
            searchNotice = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.runSearch(trimmed)
        }
    }

    func retrySearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await runSearch(trimmed)
    }

    func resolve(raw: String) async {
        resolveFault = nil
        resolvedPayload = nil
        isResolving = true
        defer { isResolving = false }
        let candidates = TelemetryService.barcodeCandidates(from: raw)
        guard !candidates.isEmpty else {
            resolveFault = .notFound
            return
        }
        var sawTransport = false
        for code in candidates {
            if Task.isCancelled { return }
            if let cached = try? await payloads.cached(barcode: code) {
                resolvedPayload = cached
                return
            }
            if let shelf = DemoShelf.payload(barcode: code) {
                try? await payloads.save(shelf)
                resolvedPayload = shelf
                return
            }
            do {
                let fetched = try await catalog.fetch(barcode: code)
                try await payloads.save(fetched)
                resolvedPayload = fetched
                return
            } catch CatalogFault.notFound {
                continue
            } catch CatalogFault.cancelled {
                return
            } catch CatalogFault.transport, CatalogFault.decoding {
                sawTransport = true
                continue
            } catch {
                sawTransport = true
                continue
            }
        }
        resolveFault = sawTransport ? .transport : .notFound
    }

    func assign(
        payload: OrbitPayload,
        grams: Double,
        slot: OrbitSlot,
        dayKey: OrbitDayKey,
        eaten: Bool
    ) async throws -> ApogeeEntry {
        guard TelemetryService.isGramsAcceptable(grams) else { throw CatalogFault.invalidGrams }
        guard payload.mass.kcal100 != nil else { throw CatalogFault.missingEnergy }
        isMutating = true
        defer { isMutating = false }
        var resolvedSlot = slot
        var resolvedEaten = eaten
        if dayKey > todayKey {
            if resolvedSlot == .drift {
                resolvedSlot = .perigee
            }
            resolvedEaten = false
        }
        if resolvedSlot == .drift {
            resolvedEaten = true
        }
        try await payloads.save(payload)
        let entry = ApogeeEntry(
            id: UUID(),
            payload: payload,
            grams: grams,
            slot: resolvedSlot,
            dayKey: dayKey,
            isEaten: resolvedEaten,
            createdAt: Date()
        )
        try await logs.upsert(entry)
        lastCommittedId = entry.id
        try await reload()
        return entry
    }

    func relocate(id: UUID, to anchor: HorizonAnchor) async throws {
        isMutating = true
        defer { isMutating = false }
        guard let existing = horizonEntries.first(where: { $0.id == id }) ?? entriesToday.first(where: { $0.id == id }) else {
            return
        }
        let moved = HorizonTransferService.relocate(existing, to: anchor, today: todayKey)
        try await logs.upsert(moved)
        try await reload()
    }

    func lockEaten(id: UUID) async throws {
        isMutating = true
        defer { isMutating = false }
        let pool = horizonEntries + entriesToday
        guard let existing = pool.first(where: { $0.id == id }) else { return }
        let eaten = HorizonTransferService.markEaten(existing, today: todayKey)
        try await logs.upsert(eaten)
        lastCommittedId = eaten.id
        try await reload()
    }

    func deleteEntry(id: UUID) async throws {
        isMutating = true
        defer { isMutating = false }
        try await logs.delete(id: id)
        try await reload()
    }

    func addWish(_ payload: OrbitPayload) async throws {
        isMutating = true
        defer { isMutating = false }
        let chip = AcquisitionChip(payload: payload, addedAt: Date())
        try await wishVault.upsert(chip)
        wishes = WishUniquenessService.merging(wishes, with: chip)
        wishes = try await wishVault.all()
    }

    func isWished(_ barcode: String) -> Bool {
        WishUniquenessService.contains(wishes, barcode: barcode)
    }

    func deleteWish(barcode: String) async throws {
        try await wishVault.delete(barcode: barcode)
        wishes = try await wishVault.all()
    }

    func saveTargets(_ incoming: OrbitTargets) async throws {
        guard incoming.kcal > 0, incoming.protein >= 0, incoming.carbs >= 0, incoming.fat >= 0 else {
            throw CatalogFault.invalidGrams
        }
        try await targetVault.save(incoming)
        targets = incoming
    }

    func resetAllData() async throws {
        isMutating = true
        defer { isMutating = false }
        try await logs.resetAll()
        flags.didSeedDemoDay = false
        try await seedDemoDayIfNeeded()
        try await reload()
    }

    func rememberRoute(_ raw: String) {
        flags.lastRouteRaw = raw
    }

    var lastRouteRaw: String? { flags.lastRouteRaw }

    func consumedToday() -> PayloadMass {
        TelemetryService.dayTotals(entries: entriesToday, eatenOnly: true)
    }

    func projected(for day: OrbitDayKey) -> Double {
        let slice = horizonEntries.filter { $0.dayKey == day }
        return HorizonTransferService.projectedKcal(entries: slice)
    }

    private func runSearch(_ query: String) async {
        spinnerTask?.cancel()
        searchNotice = nil
        var showedSpinner = false
        spinnerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.searchPhase = .loading
            showedSpinner = true
        }
        let shelf = DemoShelf.matching(query)
        do {
            let remote = try await catalog.search(terms: query)
            guard !Task.isCancelled else { return }
            spinnerTask?.cancel()
            let merged = Self.merge(remote: remote, local: shelf)
            searchHits = merged
            searchNotice = nil
            searchPhase = merged.isEmpty ? .empty : .results
        } catch CatalogFault.cancelled {
            spinnerTask?.cancel()
            return
        } catch {
            guard !Task.isCancelled else { return }
            spinnerTask?.cancel()
            let merged = Self.merge(remote: [], local: shelf)
            searchHits = merged
            if merged.isEmpty {
                searchPhase = .transport
                searchNotice = "Telemetry link failed. The catalog did not respond."
            } else {
                searchPhase = .results
                searchNotice = "Catalog link dropped — local shelf is standing in."
            }
        }
        _ = showedSpinner
    }

    static func merge(remote: [OrbitPayload], local: [OrbitPayload]) -> [OrbitPayload] {
        var seen: Set<String> = []
        var result: [OrbitPayload] = []
        for item in remote + local {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if seen.insert(item.barcode).inserted {
                result.append(item)
            }
        }
        return result
    }

    private func seedShelfQuietly() async throws {
        for payload in DemoShelf.payloads {
            try await payloads.save(payload)
        }
    }

    private func seedDemoDayIfNeeded() async throws {
        #if targetEnvironment(simulator)
        let existing = try await logs.entries(dayKey: todayKey)
        if !existing.isEmpty {
            flags.didSeedDemoDay = true
            return
        }
        flags.didSeedDemoDay = true
        let eggs = DemoShelf.payloads[0]
        let mince = DemoShelf.payloads[1]
        let oats = DemoShelf.payloads[3]
        let tomorrow = OrbitDayKey.offset(todayKey, byDays: 1, calendar: calendar) ?? todayKey
        try await logs.upsert(
            ApogeeEntry(
                id: UUID(),
                payload: eggs,
                grams: 120,
                slot: .apogee,
                dayKey: todayKey,
                isEaten: true,
                createdAt: Date()
            )
        )
        try await logs.upsert(
            ApogeeEntry(
                id: UUID(),
                payload: mince,
                grams: 150,
                slot: .zenith,
                dayKey: todayKey,
                isEaten: true,
                createdAt: Date()
            )
        )
        try await logs.upsert(
            ApogeeEntry(
                id: UUID(),
                payload: oats,
                grams: 250,
                slot: .apogee,
                dayKey: tomorrow,
                isEaten: false,
                createdAt: Date()
            )
        )
        if wishes.isEmpty {
            try await addWish(DemoShelf.payloads[2])
        }
        #endif
    }
}
