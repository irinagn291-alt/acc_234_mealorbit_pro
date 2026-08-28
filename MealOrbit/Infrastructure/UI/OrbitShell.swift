import Combine
import SwiftUI
import UIKit

enum OrbitRoute: String, CaseIterable, Hashable, Sendable {
    case commandDeck
    case catalogSweep
    case telemetryScan
    case burnLog
    case horizon
    case acquisition
    case massTargets

    var title: String {
        switch self {
        case .commandDeck: "Command Deck"
        case .catalogSweep: "Catalog Sweep"
        case .telemetryScan: "Telemetry Scan"
        case .burnLog: "Burn Log"
        case .horizon: "Fourteen-Day Horizon"
        case .acquisition: "Acquisition List"
        case .massTargets: "Mass Targets"
        }
    }
}

/// Onion ring: Infrastructure / UI.
/// Composition root. Wires outer rings into the session and the split shell.
enum OrbitComposition {
    @MainActor
    static func makeSession(inMemory: Bool = false) -> (OrbitSession, OrbitStore, LocalPasscode) {
        let store = OrbitStore(inMemory: inMemory)
        let flags = UserDefaultsLaunchFlags()
        let catalog = TelemetryCatalogClient()
        let passcode = LocalPasscode()
        if let container = store.container {
            let vault = SwiftDataOrbitVault(container: container)
            let session = OrbitSession(
                payloads: vault,
                logs: vault,
                targetVault: vault,
                wishVault: vault,
                catalog: catalog,
                flags: flags,
                vaultReady: true
            )
            return (session, store, passcode)
        }
        let session = OrbitSession(
            payloads: EmptyVault(),
            logs: EmptyVault(),
            targetVault: EmptyVault(),
            wishVault: EmptyVault(),
            catalog: catalog,
            flags: flags,
            vaultReady: false
        )
        return (session, store, passcode)
    }
}

/// Fallback vault when the container cannot open. Every call is a no-op.
@MainActor
final class EmptyVault: PayloadVault, EntryVault, TargetVault, WishVault {
    func cached(barcode: String) async throws -> OrbitPayload? { nil }
    func save(_ payload: OrbitPayload) async throws {}
    func allCached() async throws -> [OrbitPayload] { DemoShelf.payloads }
    func entries(dayKey: OrbitDayKey) async throws -> [ApogeeEntry] { [] }
    func entries(from start: OrbitDayKey, to end: OrbitDayKey) async throws -> [ApogeeEntry] { [] }
    func upsert(_ entry: ApogeeEntry) async throws {}
    func delete(id: UUID) async throws {}
    func resetAll() async throws {}
    func load() async throws -> OrbitTargets { .sensibleDefaults }
    func save(_ targets: OrbitTargets) async throws {}
    func all() async throws -> [AcquisitionChip] { [] }
    func upsert(_ chip: AcquisitionChip) async throws {}
    func delete(barcode: String) async throws {}
}

@main
final class OrbitAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = OrbitSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

/// Onion ring: Infrastructure / UI.
/// Scene chrome. Owns the window and presents the split shell.
final class OrbitSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var session: OrbitSession?
    private var split: OrbitSplitController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        let composed = OrbitComposition.makeSession()
        self.session = composed.0
        let split = OrbitSplitController(
            session: composed.0,
            storeFault: composed.1.faultMessage,
            passcode: composed.2
        )
        self.split = split
        window.rootViewController = split
        window.makeKeyAndVisible()
        self.window = window
        Task { await composed.0.bootstrap() }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        session?.refreshDayKey()
        Task { try? await session?.reload() }
        split?.handleDayChange()
    }
}

/// Onion ring: Infrastructure / UI.
/// Two-column split. Sidebar of orbits; detail and assign replace each other.
/// Horizon takes the full width. Compact width collapses to a stack.
@MainActor
final class OrbitSplitController: UISplitViewController, UISplitViewControllerDelegate {
    let session: OrbitSession
    private let passcode: LocalPasscode
    private let storeFault: String?
    private let sidebarHost: UIHostingController<OrbitSidebarView>
    private let detailNav: UINavigationController
    private var currentRoute: OrbitRoute = .commandDeck
    private var cancellables = Set<AnyCancellable>()
    private var didPresentLaunch = false
    private var didPresentLock = false

    init(session: OrbitSession, storeFault: String?, passcode: LocalPasscode) {
        self.session = session
        self.storeFault = storeFault
        self.passcode = passcode
        self.detailNav = UINavigationController()
        let sidebar = OrbitSidebarView(
            selected: .commandDeck,
            onSelect: { _ in }
        )
        self.sidebarHost = UIHostingController(rootView: sidebar)
        super.init(style: .doubleColumn)
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        presentsWithGesture = true
        delegate = self
        displayModeButtonVisibility = .always
        minimumPrimaryColumnWidth = 220
        maximumPrimaryColumnWidth = 300
        primaryBackgroundStyle = .sidebar
    }

    /// Programmer error: this controller is created in code, never from a storyboard.
    required init?(coder: NSCoder) {
        fatalError("OrbitSplitController is not loaded from a storyboard.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OrbitPalette.uiColor(.background)
        sidebarHost.view.backgroundColor = OrbitPalette.uiColor(.background)
        detailNav.navigationBar.prefersLargeTitles = false
        detailNav.navigationBar.tintColor = OrbitPalette.uiColor(.accent)
        setViewController(sidebarHost, for: .primary)
        setViewController(detailNav, for: .secondary)
        rebuildSidebar()
        if let raw = session.lastRouteRaw, let route = OrbitRoute(rawValue: raw) {
            showRoute(route)
        } else {
            showRoute(.commandDeck)
        }
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleDayChange()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.notifyScannerBackground()
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentGatesIfNeeded()
    }

    func handleDayChange() {
        session.refreshDayKey()
        Task { try? await session.reload() }
        if currentRoute != .horizon {
            showRoute(currentRoute)
        } else {
            showRoute(.horizon)
        }
    }

    func showRoute(_ route: OrbitRoute) {
        currentRoute = route
        session.rememberRoute(route.rawValue)
        applyHorizonChrome(route == .horizon)
        let controller = makeDetailController(for: route)
        controller.navigationItem.largeTitleDisplayMode = .never
        controller.navigationItem.title = route.title
        if route == .horizon {
            controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Deck",
                style: .plain,
                target: self,
                action: #selector(returnToDeck)
            )
        }
        let animated = !UIAccessibility.isReduceMotionEnabled
        detailNav.setViewControllers([controller], animated: animated)
        show(.secondary)
        rebuildSidebar()
    }

    func showDossier(_ payload: OrbitPayload) {
        applyHorizonChrome(false)
        let view = PayloadDossierView(
            payload: payload,
            session: session,
            onAssign: { [weak self] payload, grams in
                self?.showAssign(payload: payload, grams: grams)
            },
            onWish: { [weak self] payload in
                Task { @MainActor in
                    try? await self?.session.addWish(payload)
                    OrbitHaptics.commit()
                }
            }
        )
        let host = hosted(view, title: "Payload Dossier")
        replaceDetail(with: host)
    }

    func showAssign(payload: OrbitPayload, grams: Double) {
        applyHorizonChrome(false)
        let view = WindowAssignView(
            payload: payload,
            grams: grams,
            session: session,
            onCancel: { [weak self] in
                self?.showDossier(payload)
            },
            onCommitted: { [weak self] entry in
                OrbitHaptics.commit()
                if entry.isEaten {
                    self?.showRoute(.commandDeck)
                } else {
                    self?.showRoute(.horizon)
                }
            }
        )
        let host = hosted(view, title: "Lock Window")
        replaceDetail(with: host)
    }

    @objc private func returnToDeck() {
        showRoute(.commandDeck)
    }

    private func applyHorizonChrome(_ fullWidth: Bool) {
        if fullWidth {
            hide(.primary)
            preferredDisplayMode = .secondaryOnly
        } else {
            show(.primary)
            preferredDisplayMode = .oneBesideSecondary
        }
    }

    private func replaceDetail(with controller: UIViewController) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        detailNav.setViewControllers([controller], animated: animated)
        show(.secondary)
    }

    private func makeDetailController(for route: OrbitRoute) -> UIViewController {
        switch route {
        case .telemetryScan:
            return TelemetryScanController(
                session: session,
                onResolved: { [weak self] payload in
                    self?.showDossier(payload)
                }
            )
        case .commandDeck:
            return hosted(
                CommandDeckView(
                    session: session,
                    onSearch: { [weak self] in self?.showRoute(.catalogSweep) },
                    onScan: { [weak self] in self?.showRoute(.telemetryScan) },
                    onHorizon: { [weak self] in self?.showRoute(.horizon) },
                    onLog: { [weak self] in self?.showRoute(.burnLog) },
                    onPayload: { [weak self] payload in self?.showDossier(payload) }
                ),
                title: route.title
            )
        case .catalogSweep:
            return hosted(
                CatalogSweepView(
                    session: session,
                    onSelect: { [weak self] payload in self?.showDossier(payload) }
                ),
                title: route.title
            )
        case .burnLog:
            return hosted(
                BurnLogView(
                    session: session,
                    onDeleteCommitted: { OrbitHaptics.commit() },
                    onSweep: { [weak self] in self?.showRoute(.catalogSweep) }
                ),
                title: route.title
            )
        case .horizon:
            return hosted(
                HorizonGridView(
                    session: session,
                    onPayload: { [weak self] payload in self?.showDossier(payload) },
                    onSweep: { [weak self] in self?.showRoute(.catalogSweep) }
                ),
                title: route.title
            )
        case .acquisition:
            return hosted(
                AcquisitionListView(
                    session: session,
                    onPromote: { [weak self] payload in self?.showDossier(payload) },
                    onSweep: { [weak self] in self?.showRoute(.catalogSweep) }
                ),
                title: route.title
            )
        case .massTargets:
            return hosted(
                MassTargetsView(
                    session: session,
                    passcode: passcode,
                    onRerunLaunch: { [weak self] in
                        self?.session.rerunLaunchSequence()
                        self?.presentLaunchSequence(force: true)
                    },
                    onReset: { OrbitHaptics.commit() }
                ),
                title: route.title
            )
        }
    }

    private func hosted<Content: View>(_ view: Content, title: String) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = OrbitPalette.uiColor(.background)
        host.title = title
        host.navigationItem.title = title
        return host
    }

    private func rebuildSidebar() {
        sidebarHost.rootView = OrbitSidebarView(
            selected: currentRoute,
            onSelect: { [weak self] route in
                self?.showRoute(route)
            }
        )
    }

    private func presentGatesIfNeeded() {
        if let storeFault {
            presentVaultFault(storeFault)
            return
        }
        if let expected = passcode.value, !expected.isEmpty, !didPresentLock {
            didPresentLock = true
            presentLock(expected: expected)
            return
        }
        if !session.didCompleteLaunchSequence, !didPresentLaunch {
            presentLaunchSequence(force: false)
        }
    }

    private func presentLaunchSequence(force: Bool) {
        if didPresentLaunch, !force { return }
        didPresentLaunch = true
        let view = LaunchSequenceView(
            onFinish: { [weak self] targets in
                Task { @MainActor in
                    try? await self?.session.completeLaunchSequence(targets: targets)
                    OrbitHaptics.commit()
                    self?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
                    self?.didPresentLaunch = false
                }
            }
        )
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        present(host, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func presentLock(expected: String) {
        let view = PasscodeLockView(expected: expected) { [weak self] in
            self?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
            self?.didPresentLock = false
            if let self, !self.session.didCompleteLaunchSequence {
                self.presentLaunchSequence(force: false)
            }
        }
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        host.isModalInPresentation = true
        present(host, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func presentVaultFault(_ message: String) {
        let view = VaultFaultView(message: message)
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        present(host, animated: false)
    }

    private func notifyScannerBackground() {
        NotificationCenter.default.post(name: .orbitScannerShouldStop, object: nil)
    }

    func splitViewController(
        _ svc: UISplitViewController,
        collapseSecondary secondaryViewController: UIViewController,
        onto primaryViewController: UIViewController
    ) -> Bool {
        false
    }
}

extension Notification.Name {
    static let orbitScannerShouldStop = Notification.Name("orbitScannerShouldStop")
}

struct OrbitSidebarView: View {
    var selected: OrbitRoute
    var onSelect: (OrbitRoute) -> Void

    var body: some View {
        ZStack {
            OrbitPalette.color(.background).ignoresSafeArea()
            Image("mlo_Texture")
                .resizable(resizingMode: .tile)
                .opacity(0.12)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            List {
                ForEach(OrbitRoute.allCases, id: \.self) { route in
                    Button {
                        onSelect(route)
                    } label: {
                        HStack(spacing: OrbitSpace.unit) {
                            Text(route.title)
                                .font(OrbitType.body.font)
                                .foregroundStyle(OrbitPalette.color(.ink))
                                .lineLimit(2)
                            Spacer(minLength: OrbitSpace.unit)
                            if route == selected {
                                Circle()
                                    .fill(OrbitPalette.color(.accent))
                                    .frame(width: 8, height: 8)
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .frame(minHeight: OrbitSpace.tap)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: OrbitSpace.radius)
                            .fill(route == selected ? OrbitPalette.color(.surface) : Color.clear)
                    )
                    .accessibilityLabel(route.title)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }
}
