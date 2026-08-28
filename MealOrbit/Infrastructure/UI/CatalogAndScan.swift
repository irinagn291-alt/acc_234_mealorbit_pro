import Combine
import SwiftUI
import UIKit
import Vision
import VisionKit
import AVFoundation

/// Onion ring: Infrastructure / UI.
/// Catalog sweep against Open Food Facts with local-shelf fallback.
struct CatalogSweepView: View {
    @ObservedObject var session: OrbitSession
    var onSelect: (OrbitPayload) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OrbitSpace.unit) {
                TextField("Search the catalog", text: $session.searchText)
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onChange(of: session.searchText) { _, value in
                        session.updateSearch(value)
                    }
                    .accessibilityLabel("Search the catalog")
            }
            .padding(.horizontal, OrbitSpace.inset)
            .frame(minHeight: OrbitSpace.tap)
            .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
            .padding(OrbitSpace.inset)
            content
        }
        .background(TextureBackdrop())
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { searchFocused = false })
    }

    @ViewBuilder
    private var content: some View {
        switch session.searchPhase {
        case .idle:
            OrbitEmptyState(
                image: "mlo_EmptySearch",
                title: "Sweep the catalog",
                detail: "Type a name. Hits merge from Open Food Facts and the local shelf.",
                actionTitle: "Try Apogee Eggs"
            ) {
                session.searchText = "eggs"
                session.updateSearch("eggs")
            }
        case .loading:
            ProgressView("Listening to the catalog…")
                .font(OrbitType.body.font)
                .foregroundStyle(OrbitPalette.color(.ink))
                .tint(OrbitPalette.color(.accent))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            OrbitEmptyState(
                image: "mlo_EmptySearch",
                title: "No payloads in this sweep",
                detail: "Nothing matched that name, even on the local shelf.",
                actionTitle: "Retry sweep"
            ) {
                Task { await session.retrySearch() }
            }
        case .transport:
            OrbitErrorState(
                title: "Telemetry link failed",
                detail: session.searchNotice ?? "The catalog did not respond.",
                retryTitle: "Retry sweep"
            ) {
                Task { await session.retrySearch() }
            }
        case .results:
            List {
                if let notice = session.searchNotice {
                    Text(notice)
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                        .listRowBackground(Color.clear)
                }
                ForEach(session.searchHits, id: \.barcode) { payload in
                    Button {
                        onSelect(payload)
                    } label: {
                        HStack(spacing: OrbitSpace.unit) {
                            PayloadThumb(payload: payload)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(payload.name)
                                    .font(OrbitType.body.font)
                                    .foregroundStyle(OrbitPalette.color(.ink))
                                    .lineLimit(1)
                                Text(payload.brand.isEmpty ? "Unbranded" : payload.brand)
                                    .font(OrbitType.caption.font)
                                    .foregroundStyle(OrbitPalette.color(.muted))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: OrbitSpace.unit)
                            Text(kcalLabel(payload))
                                .font(OrbitType.figure.font)
                                .foregroundStyle(OrbitPalette.color(.accent))
                                .layoutPriority(1)
                                .lineLimit(1)
                        }
                        .frame(minHeight: OrbitSpace.tap)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(OrbitPalette.color(.surface))
                    .accessibilityLabel("\(payload.name), \(kcalLabel(payload))")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func kcalLabel(_ payload: OrbitPayload) -> String {
        if let kcal = payload.mass.kcal100 {
            return "\(OrbitFigures.kcal(kcal))/100 g"
        }
        return "unknown /100 g"
    }
}

/// Onion ring: Infrastructure / UI.
/// VisionKit DataScanner with a telemetry overlay of every code in frame.
final class TelemetryScanController: UIViewController, DataScannerViewControllerDelegate {
    private let session: OrbitSession
    private let onResolved: (OrbitPayload) -> Void
    private var scanner: DataScannerViewController?
    private let overlay = TelemetryOverlayView()
    private var chromeHost: UIHostingController<ScanChromeView>?
    private var lastPayload: String?
    private var lastAcceptedAt = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init(session: OrbitSession, onResolved: @escaping (OrbitPayload) -> Void) {
        self.session = session
        self.onResolved = onResolved
        super.init(nibName: nil, bundle: nil)
    }

    /// Programmer error: created in code.
    required init?(coder: NSCoder) {
        fatalError("TelemetryScanController is not loaded from a storyboard.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OrbitPalette.uiColor(.background)
        let chrome = ScanChromeView(
            session: session,
            cameraAvailable: Self.hasCaptureDevice,
            permission: AVCaptureDevice.authorizationStatus(for: .video),
            onManual: { [weak self] raw in
                self?.accept(raw)
            },
            onOpenSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            },
            onRequestPermission: { [weak self] in
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in
                        self?.reloadChrome()
                        self?.startScannerIfPossible()
                    }
                }
            }
        )
        let host = UIHostingController(rootView: chrome)
        chromeHost = host
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            host.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        host.didMove(toParent: self)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.stopScanner()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .orbitScannerShouldStop)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.stopScanner()
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScannerIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanner()
    }

    private static var hasCaptureDevice: Bool {
        AVCaptureDevice.default(for: .video) != nil
            && DataScannerViewController.isSupported
            && DataScannerViewController.isAvailable
    }

    private func reloadChrome() {
        chromeHost?.rootView = ScanChromeView(
            session: session,
            cameraAvailable: Self.hasCaptureDevice,
            permission: AVCaptureDevice.authorizationStatus(for: .video),
            onManual: { [weak self] raw in
                self?.accept(raw)
            },
            onOpenSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            },
            onRequestPermission: { [weak self] in
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in
                        self?.reloadChrome()
                        self?.startScannerIfPossible()
                    }
                }
            }
        )
    }

    private func startScannerIfPossible() {
        guard Self.hasCaptureDevice else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else { return }
        stopScanner()
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce, .qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(scanner.view, at: 0)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanner.didMove(toParent: self)
        self.scanner = scanner
        try? scanner.startScanning()
        applyOverlayArt(on: scanner.view)
    }

    private func applyOverlayArt(on host: UIView) {
        host.viewWithTag(7102)?.removeFromSuperview()
        let art = UIImageView(image: UIImage(named: "mlo_ScanOverlay"))
        art.tag = 7102
        art.contentMode = .scaleAspectFit
        art.isUserInteractionEnabled = false
        art.translatesAutoresizingMaskIntoConstraints = false
        art.accessibilityIgnoresInvertColors = true
        host.addSubview(art)
        NSLayoutConstraint.activate([
            art.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            art.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            art.widthAnchor.constraint(equalTo: host.widthAnchor, multiplier: 0.72),
            art.heightAnchor.constraint(equalTo: art.widthAnchor)
        ])
    }

    private func stopScanner() {
        scanner?.stopScanning()
        scanner?.willMove(toParent: nil)
        scanner?.view.removeFromSuperview()
        scanner?.removeFromParent()
        scanner = nil
        overlay.update(codes: [])
    }

    private func accept(_ raw: String) {
        let now = Date()
        if raw == lastPayload, now.timeIntervalSince(lastAcceptedAt) < 1.7 {
            return
        }
        lastPayload = raw
        lastAcceptedAt = now
        Task { @MainActor in
            await session.resolve(raw: raw)
            if let payload = session.resolvedPayload {
                onResolved(payload)
            }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        publish(allItems)
        for item in addedItems {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, !value.isEmpty {
                accept(value)
                return
            }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        publish(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        publish(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
            accept(value)
        }
    }

    private func publish(_ items: [RecognizedItem]) {
        var codes: [String] = []
        for item in items {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                codes.append(value)
            }
        }
        overlay.update(codes: codes)
    }
}

final class TelemetryOverlayView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("TelemetryOverlayView is not loaded from a storyboard.")
    }

    func update(codes: [String]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let header = UILabel()
        header.font = OrbitType.micro.uiFont
        header.textColor = OrbitPalette.uiColor(.accent)
        header.text = codes.isEmpty ? "NO CODES IN FRAME" : "CODES IN FRAME \(codes.count)"
        stack.addArrangedSubview(header)
        for code in codes {
            let label = UILabel()
            label.font = OrbitType.figure.uiFont
            label.textColor = OrbitPalette.uiColor(.ink)
            label.text = code
            label.numberOfLines = 1
            stack.addArrangedSubview(label)
        }
    }
}

struct ScanChromeView: View {
    @ObservedObject var session: OrbitSession
    var cameraAvailable: Bool
    var permission: AVAuthorizationStatus
    var onManual: (String) -> Void
    var onOpenSettings: () -> Void
    var onRequestPermission: () -> Void
    @State private var manual = ""

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpace.unit) {
            if !cameraAvailable {
                Text("No capture device on this station. Use a sample chip or type a code.")
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                sampleChips
            } else {
                permissionBlock
            }
            if session.isResolving {
                ProgressView("Resolving payload…")
                    .tint(OrbitPalette.color(.accent))
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
            }
            if let fault = session.resolveFault {
                faultBlock(fault)
            }
            HStack {
                TextField("Manual barcode or URL", text: $manual)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .accessibilityLabel("Manual barcode")
                Button("Lock") {
                    onManual(manual)
                }
                .font(OrbitType.body.font)
                .frame(minWidth: 64, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.background))
                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .contentShape(Rectangle())
                .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty || session.isResolving)
                .accessibilityLabel("Lock typed barcode")
            }
            .padding(.horizontal, OrbitSpace.inset)
            .frame(minHeight: OrbitSpace.tap)
            .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
        }
        .padding(OrbitSpace.inset)
        .background(OrbitPalette.color(.background).opacity(0.92))
    }

    @ViewBuilder
    private var permissionBlock: some View {
        switch permission {
        case .notDetermined:
            Button("Enable camera telemetry", action: onRequestPermission)
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.background))
                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .contentShape(Rectangle())
                .accessibilityLabel("Enable camera telemetry")
        case .denied:
            permissionCallout(
                title: "Camera is denied",
                detail: "MealOrbit cannot lock a barcode without camera access. Open Settings to allow it."
            )
        case .restricted:
            permissionCallout(
                title: "Camera is restricted",
                detail: "Parental controls or device policy blocked the camera. Open Settings if you can change that."
            )
        default:
            EmptyView()
        }
    }

    private func permissionCallout(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpace.unit) {
            Text(title)
                .font(OrbitType.title.font)
                .foregroundStyle(OrbitPalette.color(.ink))
            Text(detail)
                .font(OrbitType.body.font)
                .foregroundStyle(OrbitPalette.color(.muted))
            Button("Open Settings", action: onOpenSettings)
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.background))
                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .contentShape(Rectangle())
                .accessibilityLabel("Open Settings")
        }
    }

    @ViewBuilder
    private func faultBlock(_ fault: CatalogFault) -> some View {
        switch fault {
        case .transport:
            VStack(alignment: .leading, spacing: OrbitSpace.unit) {
                Text("No telemetry link. That code is not cached. Retry when the station is online.")
                    .font(OrbitType.caption.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                Button("Retry lock") {
                    onManual(manual)
                }
                .font(OrbitType.body.font)
                .frame(minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.accent))
                .contentShape(Rectangle())
                .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty || session.isResolving)
                .accessibilityLabel("Retry lock")
            }
        case .notFound:
            Text("That barcode is not in Open Food Facts. You can still type another code.")
                .font(OrbitType.caption.font)
                .foregroundStyle(OrbitPalette.color(.muted))
        default:
            Text("Resolve failed. Retry the lock.")
                .font(OrbitType.caption.font)
                .foregroundStyle(OrbitPalette.color(.muted))
        }
    }

    private var sampleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(DemoShelf.payloads) { payload in
                    Button(payload.name) {
                        onManual(payload.barcode)
                    }
                    .font(OrbitType.caption.font)
                    .padding(.horizontal, OrbitSpace.stack)
                    .frame(minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .background(OrbitPalette.color(.surface), in: Capsule())
                    .contentShape(Rectangle())
                    .accessibilityLabel("Sample \(payload.name)")
                }
            }
            .padding(.trailing, OrbitSpace.inset)
        }
    }
}
