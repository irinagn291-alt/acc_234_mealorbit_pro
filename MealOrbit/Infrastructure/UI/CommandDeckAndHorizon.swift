import SwiftUI

/// Onion ring: Infrastructure / UI.
/// Primary deck: today's burn, four slots, and a surface for the 14-day horizon.
struct CommandDeckView: View {
    @ObservedObject var session: OrbitSession
    var onSearch: () -> Void
    var onScan: () -> Void
    var onHorizon: () -> Void
    var onLog: () -> Void
    var onPayload: (OrbitPayload) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpace.stack) {
                Image("mlo_HeaderDecor")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 96)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: OrbitSpace.radius))
                    .accessibilityHidden(true)
                energyCard
                if let notice = session.vaultNotice {
                    Text(notice)
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                }
                macroRow
                slotColumn
                awaitingLock
                horizonTeaser
                HStack(spacing: OrbitSpace.unit) {
                    deckButton("Sweep catalog", action: onSearch)
                    deckButton("Scan payload", action: onScan)
                }
                Button(action: onLog) {
                    Text("Open burn log")
                        .font(OrbitType.body.font)
                        .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                        .foregroundStyle(OrbitPalette.color(.ink))
                        .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Open burn log")
            }
            .padding(OrbitSpace.inset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TextureBackdrop())
    }

    private var consumed: PayloadMass {
        session.consumedToday()
    }

    private var energyCard: some View {
        let kcal = consumed.kcal100 ?? 0
        let over = kcal > session.targets.kcal
        return OrbitCard {
            VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                Text("Today's burn")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                HStack(alignment: .firstTextBaseline) {
                    Text(OrbitFigures.kcal(kcal))
                        .font(OrbitType.display.font)
                        .foregroundStyle(OrbitPalette.color(.accent))
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : OrbitMotion.curve, value: kcal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("/ \(OrbitFigures.kcal(session.targets.kcal)) kcal")
                        .font(OrbitType.figure.font)
                        .foregroundStyle(OrbitPalette.color(.ink))
                        .lineLimit(1)
                }
                ProgressView(value: min(kcal / max(session.targets.kcal, 1), 1.5), total: 1)
                    .tint(OrbitPalette.color(.accent))
                    .accessibilityLabel("Energy progress")
                if over {
                    Label("Over target", systemImage: "exclamationmark.triangle.fill")
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                        .accessibilityLabel("Energy is over the daily target")
                }
                if session.entriesToday.filter(\.isEaten).isEmpty {
                    Text("No payloads locked as eaten yet.")
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                }
            }
        }
    }

    private var macroRow: some View {
        HStack(spacing: OrbitSpace.unit) {
            macroChip("Protein", asset: "mlo_MacroProtein", consumed: consumed.protein100, target: session.targets.protein)
            macroChip("Carbs", asset: "mlo_MacroCarbs", consumed: consumed.carbs100, target: session.targets.carbs)
            macroChip("Fat", asset: "mlo_MacroFat", consumed: consumed.fat100, target: session.targets.fat)
        }
    }

    private func macroChip(_ title: String, asset: String, consumed: Double?, target: Double) -> some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: OrbitSpace.unit / 2) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                    .lineLimit(1)
                Text(OrbitFigures.nutrient(consumed))
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if target <= 0 {
                    Text("unset")
                        .font(OrbitType.micro.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                } else {
                    Text("of \(OrbitFigures.macro(target)) g")
                        .font(OrbitType.micro.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                        .lineLimit(1)
                }
            }
        }
    }

    private var slotColumn: some View {
        VStack(spacing: OrbitSpace.unit) {
            ForEach(Array(OrbitSlot.allCases.enumerated()), id: \.element) { index, slot in
                let rows = session.entriesToday.filter { $0.slot == slot && $0.isEaten }
                StaggerRow(index: index, highlighted: false) {
                    OrbitCard {
                        VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                            HStack(spacing: OrbitSpace.unit) {
                                Image(slot.assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .accessibilityHidden(true)
                                Text(slot.displayName)
                                    .font(OrbitType.title.font)
                                    .foregroundStyle(OrbitPalette.color(.ink))
                                Spacer(minLength: 0)
                                Text(OrbitFigures.energy(TelemetryService.dayTotals(entries: rows, eatenOnly: true).kcal100))
                                    .font(OrbitType.figure.font)
                                    .foregroundStyle(OrbitPalette.color(.accent))
                            }
                            if rows.isEmpty {
                                Text("Empty window")
                                    .font(OrbitType.caption.font)
                                    .foregroundStyle(OrbitPalette.color(.muted))
                            } else {
                                ForEach(rows) { entry in
                                    Button {
                                        onPayload(entry.payload)
                                    } label: {
                                        HStack {
                                            Text(entry.payload.name)
                                                .font(OrbitType.body.font)
                                                .foregroundStyle(OrbitPalette.color(.ink))
                                                .lineLimit(1)
                                            Spacer(minLength: OrbitSpace.unit)
                                            Text(OrbitFigures.energy(TelemetryService.portion(mass: entry.payload.mass, grams: entry.grams).kcal100))
                                                .font(OrbitType.figure.font)
                                                .foregroundStyle(OrbitPalette.color(.accent))
                                                .layoutPriority(1)
                                        }
                                        .frame(minHeight: OrbitSpace.tap)
                                        .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("\(entry.payload.name), \(OrbitFigures.energy(TelemetryService.portion(mass: entry.payload.mass, grams: entry.grams).kcal100)) kilocalories")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var awaitingLock: some View {
        let planned = session.entriesToday.filter { !$0.isEaten }
        return Group {
            if !planned.isEmpty {
                OrbitCard {
                    VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                        Text("Awaiting lock")
                            .font(OrbitType.title.font)
                            .foregroundStyle(OrbitPalette.color(.ink))
                        Text("Planned payloads for today convert to eaten in one action.")
                            .font(OrbitType.caption.font)
                            .foregroundStyle(OrbitPalette.color(.muted))
                        ForEach(planned) { entry in
                            HStack {
                                Text(entry.payload.name)
                                    .font(OrbitType.body.font)
                                    .foregroundStyle(OrbitPalette.color(.ink))
                                    .lineLimit(1)
                                Spacer(minLength: OrbitSpace.unit)
                                Button("Lock as eaten") {
                                    Task {
                                        try? await session.lockEaten(id: entry.id)
                                        OrbitHaptics.commit()
                                    }
                                }
                                .font(OrbitType.caption.font)
                                .frame(minHeight: OrbitSpace.tap)
                                .padding(.horizontal, OrbitSpace.unit)
                                .foregroundStyle(OrbitPalette.color(.background))
                                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                                .contentShape(Rectangle())
                                .disabled(session.isMutating)
                                .accessibilityLabel("Lock \(entry.payload.name) as eaten")
                            }
                        }
                    }
                }
            }
        }
    }

    private var horizonTeaser: some View {
        Button(action: onHorizon) {
            OrbitCard {
                HStack(spacing: OrbitSpace.stack) {
                    Image("mlo_TwistHero")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: OrbitSpace.radius))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: OrbitSpace.unit / 2) {
                        Text("Fourteen-day horizon")
                            .font(OrbitType.title.font)
                            .foregroundStyle(OrbitPalette.color(.ink))
                        Text("Drag payloads between days. Projected kcal rides each orbit.")
                            .font(OrbitType.caption.font)
                            .foregroundStyle(OrbitPalette.color(.muted))
                            .lineLimit(3)
                        let keys = HorizonTransferService.keys(from: session.todayKey, calendar: Calendar.current).prefix(3)
                        HStack {
                            ForEach(Array(keys), id: \.raw) { key in
                                Text(OrbitFigures.kcal(session.projected(for: key)))
                                    .font(OrbitType.micro.font)
                                    .foregroundStyle(OrbitPalette.color(.accent))
                                    .padding(.horizontal, OrbitSpace.unit)
                                    .padding(.vertical, OrbitSpace.unit / 2)
                                    .background(OrbitPalette.color(.background), in: Capsule())
                            }
                        }
                    }
                }
                .frame(minHeight: OrbitSpace.tap)
                .contentShape(Rectangle())
            }
        }
        .accessibilityLabel("Open fourteen-day horizon")
    }

    private func deckButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.background))
                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }
}

/// Onion ring: Infrastructure / UI.
/// Full-width 14-day grid with drag and drop between days and slots.
struct HorizonGridView: View {
    @ObservedObject var session: OrbitSession
    var onPayload: (OrbitPayload) -> Void
    var onSweep: () -> Void

    var body: some View {
        let keys = HorizonTransferService.keys(from: session.todayKey, calendar: Calendar.current)
        let grouped = HorizonTransferService.grouped(session.horizonEntries)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OrbitSpace.stack) {
                Image("mlo_TwistHero")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: OrbitSpace.radius))
                    .accessibilityHidden(true)
                Text("Hold a payload, then drop it on another day or window. Drift remaps to Perigee when the drop is in the future.")
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                if session.horizonEntries.isEmpty {
                    OrbitEmptyState(
                        image: "mlo_EmptyPlan",
                        title: "Horizon is clear",
                        detail: "Nothing is scheduled across the next fourteen days. Sweep the catalog and lock a future window.",
                        actionTitle: "Sweep catalog",
                        action: onSweep
                    )
                }
                ForEach(keys, id: \.raw) { day in
                    dayBlock(day, slots: grouped[day] ?? [:])
                }
            }
            .padding(OrbitSpace.inset)
        }
        .background(TextureBackdrop())
    }

    private func dayBlock(_ day: OrbitDayKey, slots: [OrbitSlot: [ApogeeEntry]]) -> some View {
        let projected = session.projected(for: day)
        let over = projected > session.targets.kcal
        return OrbitCard {
            VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                HStack {
                    Text(day.raw)
                        .font(OrbitType.figure.font)
                        .foregroundStyle(OrbitPalette.color(.ink))
                    Spacer(minLength: 0)
                    Text("\(OrbitFigures.kcal(projected)) / \(OrbitFigures.kcal(session.targets.kcal)) kcal")
                        .font(OrbitType.figure.font)
                        .foregroundStyle(over ? OrbitPalette.color(.muted) : OrbitPalette.color(.accent))
                        .layoutPriority(1)
                }
                .accessibilityLabel("\(day.raw), projected \(OrbitFigures.kcal(projected)) of \(OrbitFigures.kcal(session.targets.kcal)) kilocalories")
                ProgressView(value: min(projected / max(session.targets.kcal, 1), 1.5), total: 1)
                    .tint(OrbitPalette.color(.accent))
                ForEach(OrbitSlot.allCases, id: \.self) { slot in
                    slotLane(day: day, slot: slot, entries: slots[slot] ?? [])
                }
            }
        }
    }

    private func slotLane(day: OrbitDayKey, slot: OrbitSlot, entries: [ApogeeEntry]) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpace.unit / 2) {
            HStack(spacing: OrbitSpace.unit) {
                Image(slot.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(slot.displayName)
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
            }
            .frame(minHeight: 24)
            ForEach(entries) { entry in
                HStack {
                    Text(entry.payload.name)
                        .font(OrbitType.body.font)
                        .foregroundStyle(OrbitPalette.color(.ink))
                        .lineLimit(1)
                    Spacer(minLength: OrbitSpace.unit)
                    Text(OrbitFigures.energy(TelemetryService.portion(mass: entry.payload.mass, grams: entry.grams).kcal100))
                        .font(OrbitType.figure.font)
                        .foregroundStyle(OrbitPalette.color(.accent))
                        .layoutPriority(1)
                    if day == session.todayKey, !entry.isEaten {
                        Button("Eat") {
                            Task {
                                try? await session.lockEaten(id: entry.id)
                                OrbitHaptics.commit()
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(OrbitType.micro.font)
                        .frame(minHeight: OrbitSpace.tap)
                        .padding(.horizontal, OrbitSpace.unit)
                        .foregroundStyle(OrbitPalette.color(.background))
                        .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                        .contentShape(Rectangle())
                        .accessibilityLabel("Lock \(entry.payload.name) as eaten")
                    }
                }
                .padding(.vertical, OrbitSpace.unit / 2)
                .draggable(entry.id.uuidString)
                .onTapGesture { onPayload(entry.payload) }
            }
            Color.clear
                .frame(minHeight: OrbitSpace.tap)
                .background(OrbitPalette.color(.background).opacity(0.4), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
                    Task { try? await session.relocate(id: id, to: HorizonAnchor(dayKey: day, slot: slot)) }
                    return true
                }
                .accessibilityLabel("Drop zone for \(slot.displayName) on \(day.raw)")
        }
    }
}
