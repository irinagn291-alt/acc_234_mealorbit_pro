import SwiftUI

/// Onion ring: Infrastructure / UI.
/// Eaten list for a selected day, grouped by window, with confirmed delete.
struct BurnLogView: View {
    @ObservedObject var session: OrbitSession
    var onDeleteCommitted: () -> Void
    var onSweep: () -> Void
    @State private var offset = 0
    @State private var pendingDelete: ApogeeEntry?

    var body: some View {
        let day = OrbitDayKey.offset(session.todayKey, byDays: offset) ?? session.todayKey
        let rows = session.focusedLogEntries.filter(\.isEaten)
        VStack(spacing: 0) {
            HStack {
                Button {
                    offset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: OrbitSpace.tap, height: OrbitSpace.tap)
                }
                .accessibilityLabel("Previous day")
                Spacer()
                Text(day.raw)
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                Spacer()
                Button {
                    offset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: OrbitSpace.tap, height: OrbitSpace.tap)
                }
                .accessibilityLabel("Next day")
            }
            .foregroundStyle(OrbitPalette.color(.accent))
            .padding(.horizontal, OrbitSpace.unit)
            if rows.isEmpty {
                OrbitEmptyState(
                    image: "mlo_EmptyLog",
                    title: "Burn log is quiet",
                    detail: "Nothing eaten on this day. Sweep the catalog or scan a payload.",
                    actionTitle: "Sweep catalog",
                    action: onSweep
                )
            } else {
                List {
                    ForEach(OrbitSlot.allCases, id: \.self) { slot in
                        let group = rows.filter { $0.slot == slot }
                        if !group.isEmpty {
                            Section {
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, entry in
                                    logRow(entry, index: index)
                                }
                            } header: {
                                HStack {
                                    Image(slot.assetName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                        .accessibilityHidden(true)
                                    Text(slot.displayName)
                                        .font(OrbitType.caption.font)
                                        .foregroundStyle(OrbitPalette.color(.muted))
                                    Spacer()
                                    Text(OrbitFigures.energy(TelemetryService.dayTotals(entries: group, eatenOnly: true).kcal100))
                                        .font(OrbitType.figure.font)
                                        .foregroundStyle(OrbitPalette.color(.accent))
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(TextureBackdrop())
        .confirmationDialog(
            "Delete this payload from the burn log?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    Task {
                        try? await session.deleteEntry(id: pendingDelete.id)
                        onDeleteCommitted()
                    }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .task(id: offset) {
            await session.focusLog(day: day)
        }
    }

    private func logRow(_ entry: ApogeeEntry, index: Int) -> some View {
        StaggerRow(index: index, highlighted: session.lastCommittedId == entry.id) {
            HStack {
                PayloadThumb(payload: entry.payload, size: 44)
                VStack(alignment: .leading) {
                    Text(entry.payload.name)
                        .font(OrbitType.body.font)
                        .foregroundStyle(OrbitPalette.color(.ink))
                        .lineLimit(1)
                    Text("\(OrbitFigures.macro(entry.grams)) g")
                        .font(OrbitType.micro.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                }
                Spacer(minLength: OrbitSpace.unit)
                Text(OrbitFigures.energy(TelemetryService.portion(mass: entry.payload.mass, grams: entry.grams).kcal100))
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.accent))
                    .layoutPriority(1)
            }
            .frame(minHeight: OrbitSpace.tap)
        }
        .listRowBackground(OrbitPalette.color(.surface))
        .swipeActions {
            Button("Delete", role: .destructive) {
                pendingDelete = entry
            }
            .accessibilityLabel("Delete \(entry.payload.name)")
        }
        .accessibilityLabel("\(entry.payload.name), \(OrbitFigures.energy(TelemetryService.portion(mass: entry.payload.mass, grams: entry.grams).kcal100)) kilocalories")
    }
}

/// Onion ring: Infrastructure / UI.
/// Acquisition list. Duplicate barcodes stay unique; promote into dossier.
struct AcquisitionListView: View {
    @ObservedObject var session: OrbitSession
    var onPromote: (OrbitPayload) -> Void
    var onSweep: () -> Void
    @State private var pending: AcquisitionChip?

    var body: some View {
        Group {
            if session.wishes.isEmpty {
                OrbitEmptyState(
                    image: "mlo_EmptyWish",
                    title: "Acquisition list empty",
                    detail: "Park payloads you intend to buy. Promoting one opens the dossier to lock a window.",
                    actionTitle: "Sweep catalog",
                    action: onSweep
                )
            } else {
                List {
                    ForEach(Array(session.wishes.enumerated()), id: \.element.id) { index, chip in
                        StaggerRow(index: index, highlighted: false) {
                            Button {
                                onPromote(chip.payload)
                            } label: {
                                HStack {
                                    PayloadThumb(payload: chip.payload)
                                    VStack(alignment: .leading) {
                                        Text(chip.payload.name)
                                            .font(OrbitType.body.font)
                                            .foregroundStyle(OrbitPalette.color(.ink))
                                            .lineLimit(1)
                                        Text(chip.payload.barcode)
                                            .font(OrbitType.micro.font)
                                            .foregroundStyle(OrbitPalette.color(.muted))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: OrbitSpace.unit)
                                    Text("Promote")
                                        .font(OrbitType.caption.font)
                                        .foregroundStyle(OrbitPalette.color(.accent))
                                }
                                .frame(minHeight: OrbitSpace.tap)
                            }
                            .accessibilityLabel("Promote \(chip.payload.name)")
                        }
                        .listRowBackground(OrbitPalette.color(.surface))
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                pending = chip
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(TextureBackdrop())
        .confirmationDialog(
            "Remove this payload from the acquisition list?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pending {
                    Task { try? await session.deleteWish(barcode: pending.payload.barcode) }
                }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }
}

/// Onion ring: Infrastructure / UI.
/// Edit daily targets, re-run launch sequence, reset vault, contact, passcode.
struct MassTargetsView: View {
    @ObservedObject var session: OrbitSession
    var passcode: LocalPasscode
    var onRerunLaunch: () -> Void
    var onReset: () -> Void
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var passcodeDraft = ""
    @State private var confirmReset = false
    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpace.stack) {
                Text("Daily mass targets")
                    .font(OrbitType.title.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                targetField("Energy kcal", text: $kcal)
                targetField("Protein g", text: $protein)
                targetField("Carbs g", text: $carbs)
                targetField("Fat g", text: $fat)
                Button("Save targets") {
                    Task {
                        let next = OrbitTargets(
                            kcal: OrbitFigures.parseGrams(kcal) ?? 0,
                            protein: OrbitFigures.parseGrams(protein) ?? 0,
                            carbs: OrbitFigures.parseGrams(carbs) ?? 0,
                            fat: OrbitFigures.parseGrams(fat) ?? 0
                        )
                        try? await session.saveTargets(next)
                        OrbitHaptics.commit()
                        savedFlash = true
                    }
                }
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.background))
                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .disabled(!targetsOK || session.isMutating)
                .accessibilityLabel("Save targets")
                if savedFlash {
                    Text("Targets written.")
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                }
                Text("Local airlock")
                    .font(OrbitType.title.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                Text("Optional passcode stored on-device via KeychainAccess. Leave blank to clear.")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                SecureField("Passcode", text: $passcodeDraft)
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .frame(minHeight: OrbitSpace.tap)
                    .padding(.horizontal, OrbitSpace.unit)
                    .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                    .accessibilityLabel("Local passcode")
                Button("Store passcode") {
                    let trimmed = passcodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    passcode.value = trimmed.isEmpty ? nil : trimmed
                    OrbitHaptics.commit()
                }
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.ink))
                .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .accessibilityLabel("Store passcode")
                Button("Re-run launch sequence", action: onRerunLaunch)
                    .font(OrbitType.body.font)
                    .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                    .accessibilityLabel("Re-run launch sequence")
                Button("Reset all data") {
                    confirmReset = true
                }
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.muted))
                .accessibilityLabel("Reset all data")
                Link("Contact MealOrbit", destination: URL(string: "https://mealorbit.pro/contact-us") ?? URL(fileURLWithPath: "/"))
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.accent))
                    .frame(minHeight: OrbitSpace.tap)
                    .accessibilityLabel("Contact MealOrbit")
                Text("MealOrbit is a personal food log, not medical advice. Nutrition data is credited to Open Food Facts, a public database.")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
            }
            .padding(OrbitSpace.inset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TextureBackdrop())
        .onAppear {
            kcal = OrbitFigures.kcal(session.targets.kcal)
            protein = OrbitFigures.macro(session.targets.protein)
            carbs = OrbitFigures.macro(session.targets.carbs)
            fat = OrbitFigures.macro(session.targets.fat)
            passcodeDraft = passcode.value ?? ""
        }
        .confirmationDialog(
            "Reset every payload, plan and target on this device?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset all data", role: .destructive) {
                Task {
                    try? await session.resetAllData()
                    onReset()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func targetField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OrbitType.caption.font)
                .foregroundStyle(OrbitPalette.color(.muted))
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .font(OrbitType.figure.font)
                .foregroundStyle(OrbitPalette.color(.ink))
                .frame(minHeight: OrbitSpace.tap)
                .padding(.horizontal, OrbitSpace.unit)
                .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .onChange(of: text.wrappedValue) { _, value in
                    text.wrappedValue = OrbitFigures.sanitiseGrams(value)
                }
                .accessibilityLabel(title)
        }
    }

    private var targetsOK: Bool {
        (OrbitFigures.parseGrams(kcal) ?? 0) > 0
            && (OrbitFigures.parseGrams(protein) ?? -1) >= 0
            && (OrbitFigures.parseGrams(carbs) ?? -1) >= 0
            && (OrbitFigures.parseGrams(fat) ?? -1) >= 0
    }
}
