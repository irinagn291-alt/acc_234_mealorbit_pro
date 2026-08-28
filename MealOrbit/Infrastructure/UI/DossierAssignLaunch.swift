import SwiftUI

/// Onion ring: Infrastructure / UI.
/// Per-100 g dossier plus live portion maths. Unknown macros stay unknown.
struct PayloadDossierView: View {
    let payload: OrbitPayload
    @ObservedObject var session: OrbitSession
    var onAssign: (OrbitPayload, Double) -> Void
    var onWish: (OrbitPayload) -> Void
    @State private var gramsText = "100"
    @FocusState private var gramsFocused: Bool
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpace.stack) {
                ZStack(alignment: .bottomLeading) {
                    Image("mlo_CardBackdrop")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipped()
                        .accessibilityHidden(true)
                    HStack(spacing: OrbitSpace.unit) {
                        PayloadThumb(payload: payload, size: 72)
                        VStack(alignment: .leading) {
                            Text(payload.name)
                                .font(OrbitType.title.font)
                                .foregroundStyle(OrbitPalette.color(.ink))
                                .lineLimit(2)
                            Text(payload.brand.isEmpty ? "Unbranded" : payload.brand)
                                .font(OrbitType.caption.font)
                                .foregroundStyle(OrbitPalette.color(.muted))
                                .lineLimit(1)
                        }
                    }
                    .padding(OrbitSpace.inset)
                }
                .clipShape(RoundedRectangle(cornerRadius: OrbitSpace.radius))
                perHundred
                gramsField
                liveTotals
                if payload.mass.kcal100 == nil {
                    missingEnergy
                }
                actions
            }
            .padding(OrbitSpace.inset)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { gramsFocused = false })
        .background(TextureBackdrop())
        .overlay {
            if showSuccess {
                Image("mlo_SuccessMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            }
        }
    }

    private var grams: Double? {
        OrbitFigures.parseGrams(gramsText)
    }

    private var portion: PayloadMass {
        TelemetryService.portion(mass: payload.mass, grams: grams ?? 0)
    }

    private var gramsOK: Bool {
        if let grams {
            return TelemetryService.isGramsAcceptable(grams)
        }
        return false
    }

    private var perHundred: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                Text("Per 100 g")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                metric("Energy", OrbitFigures.energy(payload.mass.kcal100), unit: "kcal")
                metric("Protein", OrbitFigures.nutrient(payload.mass.protein100), unit: "g")
                metric("Carbs", OrbitFigures.nutrient(payload.mass.carbs100), unit: "g")
                metric("Fat", OrbitFigures.nutrient(payload.mass.fat100), unit: "g")
            }
        }
    }

    private var gramsField: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                Text("Portion mass")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                TextField("Grams", text: $gramsText)
                    .keyboardType(.decimalPad)
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .focused($gramsFocused)
                    .frame(minHeight: OrbitSpace.tap)
                    .onChange(of: gramsText) { _, value in
                        gramsText = OrbitFigures.sanitiseGrams(value)
                    }
                    .accessibilityLabel("Portion grams")
                if !gramsOK {
                    Text("Enter a mass greater than 0 and at most 10,000 g.")
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                }
            }
        }
    }

    private var liveTotals: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                Text("This portion")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                metric("Energy", gramsOK ? OrbitFigures.energy(portion.kcal100) : "—", unit: "kcal")
                metric("Protein", gramsOK ? OrbitFigures.nutrient(portion.protein100) : "—", unit: "g")
                metric("Carbs", gramsOK ? OrbitFigures.nutrient(portion.carbs100) : "—", unit: "g")
                metric("Fat", gramsOK ? OrbitFigures.nutrient(portion.fat100) : "—", unit: "g")
            }
        }
    }

    private var missingEnergy: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                Text("Energy unknown")
                    .font(OrbitType.title.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                Text("Open Food Facts has no usable energy for this payload. You can still park it on the acquisition list. Locking a window needs energy.")
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: OrbitSpace.unit) {
            Button {
                if let grams, gramsOK {
                    onAssign(payload, grams)
                }
            } label: {
                ZStack {
                    Image("mlo_ControlFace")
                        .resizable()
                        .scaledToFill()
                        .opacity(0.35)
                        .accessibilityHidden(true)
                    Text("Lock into a window")
                        .font(OrbitType.body.font)
                        .foregroundStyle(OrbitPalette.color(.ink))
                }
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .background(OrbitPalette.color(.accent).opacity(0.2), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .contentShape(Rectangle())
            }
            .disabled(!gramsOK || payload.mass.kcal100 == nil || session.isMutating)
            .accessibilityLabel("Lock into a window")
            Button {
                onWish(payload)
                showSuccess = true
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    showSuccess = false
                }
            } label: {
                Text(session.isWished(payload.barcode) ? "Already on acquisition list" : "Park on acquisition list")
                    .font(OrbitType.body.font)
                    .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                    .contentShape(Rectangle())
            }
            .disabled(session.isWished(payload.barcode) || session.isMutating)
            .accessibilityLabel(session.isWished(payload.barcode) ? "Already on acquisition list" : "Park on acquisition list")
        }
    }

    private func metric(_ title: String, _ value: String, unit: String) -> some View {
        HStack {
            Text(title)
                .font(OrbitType.body.font)
                .foregroundStyle(OrbitPalette.color(.ink))
                .lineLimit(1)
            Spacer(minLength: OrbitSpace.unit)
            Text("\(value) \(unit)")
                .font(OrbitType.figure.font)
                .foregroundStyle(OrbitPalette.color(.accent))
                .layoutPriority(1)
                .lineLimit(1)
        }
        .frame(minHeight: 28)
    }
}

/// Onion ring: Infrastructure / UI.
/// Pick Apogee / Zenith / Perigee / Drift and eaten-today or a future day.
struct WindowAssignView: View {
    let payload: OrbitPayload
    let grams: Double
    @ObservedObject var session: OrbitSession
    var onCancel: () -> Void
    var onCommitted: (ApogeeEntry) -> Void
    @State private var slot: OrbitSlot = .apogee
    @State private var eatenToday = true
    @State private var futureOffset = 1
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpace.stack) {
                Text(payload.name)
                    .font(OrbitType.title.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .lineLimit(2)
                Text("\(OrbitFigures.macro(grams)) g")
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.accent))
                Text("Window")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                ForEach(OrbitSlot.allCases, id: \.self) { item in
                    let disabled = !eatenToday && item == .drift
                    Button {
                        slot = item
                    } label: {
                        HStack(spacing: OrbitSpace.unit) {
                            Image(item.assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                            Text(item.displayName)
                                .font(OrbitType.body.font)
                                .foregroundStyle(disabled ? OrbitPalette.color(.muted) : OrbitPalette.color(.ink))
                            Spacer()
                            if slot == item {
                                Circle()
                                    .fill(OrbitPalette.color(.accent))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .frame(minHeight: OrbitSpace.tap)
                        .padding(.horizontal, OrbitSpace.unit)
                        .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                        .contentShape(Rectangle())
                    }
                    .disabled(disabled)
                    .accessibilityLabel(item.displayName)
                    .accessibilityHint(disabled ? "Drift is eaten-only. It remaps to Perigee on a future day." : "")
                }
                Toggle("Eaten today", isOn: $eatenToday)
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .tint(OrbitPalette.color(.accent))
                    .frame(minHeight: OrbitSpace.tap)
                    .onChange(of: eatenToday) { _, value in
                        if !value, slot == .drift {
                            slot = .perigee
                        }
                    }
                    .accessibilityLabel("Eaten today")
                if !eatenToday {
                    Stepper(value: $futureOffset, in: 1...13) {
                        Text("Future day +\(futureOffset)")
                            .font(OrbitType.body.font)
                            .foregroundStyle(OrbitPalette.color(.ink))
                    }
                    .frame(minHeight: OrbitSpace.tap)
                    .accessibilityLabel("Future day offset")
                    Text("Drift remaps to Perigee on a future lock.")
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                }
                Button("Confirm lock") {
                    Task {
                        guard !session.isMutating else { return }
                        let day = eatenToday
                            ? session.todayKey
                            : (OrbitDayKey.offset(session.todayKey, byDays: futureOffset) ?? session.todayKey)
                        if let entry = try? await session.assign(
                            payload: payload,
                            grams: grams,
                            slot: slot,
                            dayKey: day,
                            eaten: eatenToday
                        ) {
                            showSuccess = true
                            try? await Task.sleep(for: .milliseconds(500))
                            onCommitted(entry)
                        }
                    }
                }
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.background))
                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .contentShape(Rectangle())
                .disabled(session.isMutating)
                .accessibilityLabel("Confirm lock")
                Button("Back to dossier", action: onCancel)
                    .font(OrbitType.body.font)
                    .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .contentShape(Rectangle())
                    .accessibilityLabel("Back to dossier")
            }
            .padding(OrbitSpace.inset)
        }
        .background(TextureBackdrop())
        .overlay {
            if showSuccess {
                Image("mlo_SuccessMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct LaunchSequenceView: View {
    var onFinish: (OrbitTargets) -> Void
    @State private var page = 0
    @State private var kcal = "2100"
    @State private var protein = "140"
    @State private var carbs = "220"
    @State private var fat = "70"

    var body: some View {
        ZStack {
            TextureBackdrop()
            VStack(spacing: OrbitSpace.stack) {
                TabView(selection: $page) {
                    launchPage(
                        image: "mlo_Onboarding1",
                        title: "Two weeks on rails",
                        detail: "MealOrbit is a personal food log. Plan payloads across a fourteen-day horizon, then lock them as eaten when the day arrives."
                    ).tag(0)
                    launchPage(
                        image: "mlo_Onboarding2",
                        title: "Sweep and scan",
                        detail: "Search Open Food Facts or lock a barcode into an orbit window. The local shelf stands in when telemetry drops."
                    ).tag(1)
                    launchPage(
                        image: "mlo_Onboarding3",
                        title: "Mass targets",
                        detail: "Set daily energy and macros. Figures stay on the Command Deck as telemetry, not medical advice."
                    ).tag(2)
                    targetsPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == page ? OrbitPalette.color(.ink) : OrbitPalette.color(.muted).opacity(0.45))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHidden(true)
                HStack {
                    Button("Skip with defaults") {
                        onFinish(.sensibleDefaults)
                    }
                    .font(OrbitType.body.font)
                    .frame(minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.muted))
                    .contentShape(Rectangle())
                    .accessibilityLabel("Skip with defaults")
                    Spacer()
                    Button(page == 3 ? "Write targets" : "Next") {
                        if page == 3 {
                            onFinish(parsedTargets)
                        } else {
                            page += 1
                        }
                    }
                    .font(OrbitType.body.font)
                    .frame(minWidth: 120, minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.background))
                    .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                    .contentShape(Rectangle())
                    .disabled(page == 3 && !targetsOK)
                    .accessibilityLabel(page == 3 ? "Write targets" : "Next")
                }
                .padding(.horizontal, OrbitSpace.inset)
            }
            .padding(.vertical, OrbitSpace.inset)
        }
    }

    private func launchPage(image: String, title: String, detail: String) -> some View {
        VStack(spacing: OrbitSpace.stack) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .accessibilityHidden(true)
            Text(title)
                .font(OrbitType.title.font)
                .foregroundStyle(OrbitPalette.color(.ink))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(OrbitType.body.font)
                .foregroundStyle(OrbitPalette.color(.muted))
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrbitSpace.inset)
            Spacer(minLength: 12)
        }
        .padding(OrbitSpace.inset)
    }

    private var targetsPage: some View {
        VStack(alignment: .leading, spacing: OrbitSpace.unit) {
            Text("Initial mass targets")
                .font(OrbitType.title.font)
                .foregroundStyle(OrbitPalette.color(.ink))
            targetField("Energy kcal", text: $kcal)
            targetField("Protein g", text: $protein)
            targetField("Carbs g", text: $carbs)
            targetField("Fat g", text: $fat)
            Text("These are personal logging targets, not medical advice. Nutrition data comes from Open Food Facts.")
                .font(OrbitType.caption.font)
                .foregroundStyle(OrbitPalette.color(.muted))
        }
        .padding(OrbitSpace.inset)
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

    private var parsedTargets: OrbitTargets {
        OrbitTargets(
            kcal: OrbitFigures.parseGrams(kcal) ?? 2100,
            protein: OrbitFigures.parseGrams(protein) ?? 140,
            carbs: OrbitFigures.parseGrams(carbs) ?? 220,
            fat: OrbitFigures.parseGrams(fat) ?? 70
        )
    }

    private var targetsOK: Bool {
        parsedTargets.kcal > 0 && parsedTargets.protein >= 0 && parsedTargets.carbs >= 0 && parsedTargets.fat >= 0
    }
}
