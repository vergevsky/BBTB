import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import MenuBarFeature
import SettingsFeature
import VLESSReality
import VLESSTLS
import Shadowsocks
import Hysteria2
import TUIC  // Phase 7a Wave 4 — PROTO-08
import Trojan
import ProtocolRegistry
import TransportRegistry
import Localization
import CrashReporter
import RulesEngine  // Phase 8 W4 — RULES-04 NSBackgroundActivityScheduler host wiring
import os.signpost

/// Phase 8 / W4 — NSBackgroundActivityScheduler identifier для macOS rules refresh.
/// macOS не требует Info.plist declaration (unlike iOS) и не требует extra entitlement
/// (см. 08-RESEARCH.md § Pattern 4).
private let rulesRefreshActivityIdentifier = "app.bbtb.client.macos.rules-refresh"

@main
struct BBTB_macOSApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var viewModel: MainScreenViewModel
    /// Phase 6d Wave 02a — ColdLaunch span (init → BBTBMacOSRootView.onAppear).
    /// Instruments → Points of Interest → category=performance.
    private let coldLaunchState: OSSignpostIntervalState
    /// Phase 8 / W4 — Rules Engine coordinator (RULES-04). Mirror iOS pattern.
    /// **D-12 cold-start defer:** init дешёвый; bootstrap+refresh — detached Tasks.
    private let rulesCoordinator: RulesEngineCoordinator
    /// Phase 8 / W4 — 6-hour periodic scheduler (tolerance 10 min). macOS analog
    /// of iOS BGAppRefreshTask. Held как stored property чтобы predictable lifetime
    /// pinned к App; on process exit OS снимает с schedule.
    private let rulesScheduler: NSBackgroundActivityScheduler

    init() {
        // Phase 6d Wave 02a — open ColdLaunch interval as the very first
        // statement (mirrors iOS app). Closes в Window root view.onAppear.
        let coldID = PerfSignposter.appMac.makeSignpostID()
        self.coldLaunchState = PerfSignposter.appMac.beginInterval("ColdLaunch", id: coldID)

        // TELEM-01
        CrashReporter.shared.install()

        ProtocolRegistry.shared.register(VLESSRealityHandler.self)
        ProtocolRegistry.shared.register(TrojanHandler.self)  // Phase 2 PROTO-02
        ProtocolRegistry.shared.register(VLESSTLSHandler.self)
        ProtocolRegistry.shared.register(ShadowsocksHandler.self)
        ProtocolRegistry.shared.register(Hysteria2Handler.self)
        ProtocolRegistry.shared.register(TUICHandler.self)  // Phase 7a Wave 4 — PROTO-08 TUIC v5

        // CORE-03 (Phase 5) — register transport handlers.
        // Pitfall 8: registration must happen before any provisionTunnelProfile call.
        TransportRegistry.shared.register(TCPTransportHandler.self)
        TransportRegistry.shared.register(WSTransportHandler.self)
        TransportRegistry.shared.register(HTTPTransportHandler.self)
        TransportRegistry.shared.register(HTTPUpgradeTransportHandler.self)
        TransportRegistry.shared.register(GRPCTransportHandler.self)

        let container: ModelContainer
        do {
            container = try SwiftDataContainer.makeShared()
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
        self.modelContainer = container
        let importer = ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "app.bbtb.client.macos.tunnel"
        )
        // Phase 6c / Plan 06C-04 Task 3a/3b — TunnelController slim init; больше нет
        // параметра stateObserver, и старый relay-объект (relay
        // ферил ReconnectStateMachine состояние в VM banner — теперь VM реактивно
        // читает NEVPNStatus сам через `applyVPNStatus(_:)`, без relay).
        let tunnel = TunnelController()
        let vm = MainScreenViewModel(importer: importer, tunnel: tunnel, modelContainer: container)
        _viewModel = StateObject(wrappedValue: vm)
        // Phase 6 / Wave 6 — SwiftDataFailoverProvider wiring (NET-11).
        let userDefaults = UserDefaults.standard
        let failoverProvider = SwiftDataFailoverProvider(
            modelContainer: container,
            provisioner: importer,
            connect: { [weak tunnel] in
                guard let tunnel else { throw CancellationError() }
                return try await tunnel.connect()
            },
            currentServerID: {
                userDefaults.string(forKey: "app.bbtb.selectedServerID").flatMap(UUID.init(uuidString:))
            }
        )

        // Phase 6d Wave 03f (M1) — ordered launch-time Task chain (mirror iOS).
        // Заменяет 4 fire-and-forget Tasks (OnDemandMigrationTask,
        // setFailoverProvider, setWatchdog+TunnelWatchdog, startReachability)
        // одной сериализованной цепочкой. См. doc-comment в `BBTB_iOSApp.swift`
        // для полного описания ordering invariants и motivation.
        //
        // macOS-specific: `startReachability()` дополнительно регистрирует
        // `NSWorkspace.didWakeNotification` observer (Pitfall 10) — он
        // installs внутри `bootstrap(...)` атомарно вместе с NEVPN observer.
        Task { [vm] in
            await OnDemandMigrationTask.runIfNeeded()
            let watchdog = TunnelWatchdog(failoverProvider: failoverProvider)
            await watchdog.setFailoverObserver { [weak vm] serverName in
                await MainActor.run { [weak vm] in
                    vm?.showFailoverBanner(toServerName: serverName)
                }
            }
            let snapshot = await tunnel.bootstrap(failoverProvider: failoverProvider,
                                                  watchdog: watchdog)
            await MainActor.run { [weak vm] in
                vm?.applyInitialStatusSnapshot(snapshot)
            }
        }

        // Phase 8 / W4 — RULES-04 Rules Engine bootstrap + macOS scheduler.
        //
        // (1) Construct cheap coordinator (D-12 — init без I/O, safe в App.init).
        // (2) Создать NSBackgroundActivityScheduler с interval 6h, tolerance 10 min,
        //     repeats=true, qos=.utility (mirror iOS BGAppRefreshTask semantics).
        // (3) `schedule { … }` — closure запускается опortunistically когда OS даёт
        //     execution budget. Внутри Task.detached → performBackgroundRefresh →
        //     completion(.finished) даёт OS зашедулить следующий interval.
        // (4) Defer baseline copy в detached Task (DEC-06d-01 cold-start defer).
        let rulesCoordinator = RulesEngineCoordinator()
        self.rulesCoordinator = rulesCoordinator

        let scheduler = NSBackgroundActivityScheduler(identifier: rulesRefreshActivityIdentifier)
        scheduler.repeats = true
        scheduler.interval = 6 * 3600     // 6 hours periodic
        scheduler.tolerance = 10 * 60     // 10 min tolerance — OS power-aware flexibility
        scheduler.qualityOfService = .utility
        self.rulesScheduler = scheduler

        scheduler.schedule { [rulesCoordinator] completion in
            // closure invoked off-MainActor on OS-managed queue; coordinator — actor,
            // safe для cross-actor call. completion(.finished) обязателен — иначе
            // scheduler НЕ зашедулит next slot.
            Task.detached(priority: .utility) {
                _ = await rulesCoordinator.performBackgroundRefresh()
                completion(.finished)
            }
        }

        // Cold-start defer (DEC-06d-01): baseline copy в detached Task — НЕ блокирует
        // App.init / первый frame. coordinator.bootstrap() идемпотентен.
        Task.detached(priority: .utility) { [rulesCoordinator] in
            await rulesCoordinator.bootstrap()
        }

        // Phase 6d-03e Commit 2 (M2) — deferred Phase 2→3 SwiftData migration
        // (mirror iOS). makeShared() выше теперь открывает контейнер
        // синхронно, миграция уезжает в background detached Task — UI
        // не ждёт её на cold start. Idempotent UserDefaults flag.
        // Wave 03f (M1): остаётся отдельной Task.detached (background
        // priority, не contend'ит за NE XPC).
        let mc = modelContainer
        Task.detached(priority: .background) {
            await SwiftDataContainer.runMigrationsIfNeeded(in: mc)
        }
    }

    var body: some Scene {
        Window(L10n.appShortName, id: "main") {
            BBTBMacOSRootView(viewModel: viewModel, rulesCoordinator: rulesCoordinator)
                .frame(minWidth: 380, minHeight: 520)
                .onAppear {
                    // Phase 6d Wave 02a — close ColdLaunch span on first root
                    // window appearance. Idempotent (см. iOS analog).
                    PerfSignposter.appMac.endInterval("ColdLaunch", coldLaunchState)
                }
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)

        // Phase 2 W4.T9 — Cmd+, Settings Scene (D-12).
        // Phase 8 / W4 — VM wired через wrapper view с `.task` чтобы получить
        // RulesEngineCoordinator (Cmd+, scene создаёт свежий VM каждое open;
        // wrapper выполняет idempotent wireRulesCoordinator).
        Settings {
            MacSettingsSceneWrapper(rulesCoordinator: rulesCoordinator)
                .frame(width: 480, height: 360)
        }

        MenuBarExtra(L10n.appShortName, systemImage: viewModel.state.menuBarSymbol) {
            MenuBarContent(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Phase 8 / W4 — Cmd+, Settings scene wrapper. Создаёт SettingsViewModel @StateObject
/// и через `.task` инжектит coordinator (idempotent — vm может wire'иться многократно
/// при повторном open/close Settings window). Изолировано от main scene's settingsVM,
/// которая живёт в BBTBMacOSRootView как @StateObject.
private struct MacSettingsSceneWrapper: View {
    let rulesCoordinator: RulesEngineCoordinator
    @StateObject private var settingsVM = SettingsViewModel()

    var body: some View {
        SettingsView(viewModel: settingsVM)
            .task {
                await settingsVM.wireRulesCoordinator(rulesCoordinator)
            }
    }
}

/// Phase 2 W4.T9 — NavigationStack для menu icon push на Settings (дубль Cmd+, entry).
private struct BBTBMacOSRootView: View {
    @ObservedObject var viewModel: MainScreenViewModel
    /// Phase 8 / W4 — Rules Engine coordinator propagated from App.init для
    /// `wireRulesCoordinator(_:)` на оба ViewModel + foreground sanity fetch (12h).
    let rulesCoordinator: RulesEngineCoordinator
    @State private var showSettings = false
    @StateObject private var settingsVM = SettingsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            MainScreenView(
                viewModel: viewModel,
                onOpenSettings: { showSettings = true }
            )
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(viewModel: settingsVM)
            }
        }
        // Phase 8 / W4 — wire RulesEngineCoordinator в оба VM (mirror iOS pattern;
        // RULES-04 / RULES-09 / RULES-10 / D-11). Sequential — settings первым (для
        // Cmd+, push), mainScreen вторым (для min_app_version sheet на cold start).
        .task {
            await settingsVM.wireRulesCoordinator(rulesCoordinator)
            await viewModel.wireRulesCoordinator(rulesCoordinator)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Phase 6e Wave 1 M7 (D-01) — mirror iOS consolidated single-Task
            // handler. Раньше было 3 параллельных Task'а — теперь ОДИН
            // последовательный handleForegroundReentry внутри которого
            // DEC-06d-01 cold-start defer для runIsSupportedUpgrade сохранён.
            // macOS-specific: NSWorkspace.didWakeNotification observer регистрируется
            // отдельно внутри TunnelController.startReachability — тут не трогаем.
            guard newPhase == .active else { return }
            Task { @MainActor in await viewModel.handleForegroundReentry() }
            // Phase 8 / W4 — Pitfall 2 foreground sanity fetch (mirror iOS).
            // Если user отключил scheduling в System Settings → Login Items или
            // macOS отказал OS-budget — fallback через 12h staleness check на
            // каждом foreground re-entry.
            Task { @MainActor in await foregroundSanityFetch() }
        }
    }

    /// Phase 8 / W4 — foreground sanity fetch (RULES-04 / Pitfall 2). Mirror iOS.
    /// Threshold = 12 * 3600 секунд. Detached в background priority — НЕ блокирует UI.
    @MainActor
    private func foregroundSanityFetch() async {
        let lastFetched = await rulesCoordinator.currentSnapshot()?.lastFetchedAt ?? .distantPast
        if Date().timeIntervalSince(lastFetched) > 12 * 3600 {
            Task.detached(priority: .utility) { [rulesCoordinator] in
                _ = await rulesCoordinator.performBackgroundRefresh()
            }
        }
    }
}
