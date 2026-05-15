import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import SettingsFeature
import VLESSReality
import VLESSTLS
import Shadowsocks
import Hysteria2
import TUIC  // Phase 7a Wave 4 — PROTO-08
import Trojan
import ProtocolRegistry
import TransportRegistry
import CrashReporter
import PacketTunnelKit
import RulesEngine  // Phase 8 W4 — RULES-04 BGAppRefreshTask host wiring
import DeepLinks    // Phase 9 W3 — DEEP-01/02/05
import BackgroundTasks  // Phase 8 W4 — RULES-04
import OSLog
import os.signpost

/// Phase 8 / W4 — BGAppRefreshTask identifier для iOS rules refresh.
/// Должен **буква в букву** совпадать с `BGTaskSchedulerPermittedIdentifiers`
/// в Info.plist (см. 08-RESEARCH.md § Pattern 3 + § Pitfall 2).
private let rulesRefreshTaskIdentifier = "app.bbtb.client.ios.rules-refresh"

@main
struct BBTB_iOSApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: MainScreenViewModel
    /// Phase 6d Wave 02a — ColdLaunch span (init → BBTBRootView.onAppear).
    /// Instruments → Points of Interest → category=performance.
    private let coldLaunchState: OSSignpostIntervalState
    /// Phase 8 / W4 — Rules Engine coordinator (RULES-04).
    /// **D-12 cold-start defer:** init дешёвый — никаких I/O / network в конструкторе;
    /// `bootstrap()` + `performBackgroundRefresh()` запускаются из detached Tasks.
    /// Captured нагло в BGTaskScheduler register closure (escaping, but Sendable actor).
    private let rulesCoordinator: RulesEngineCoordinator
    /// Phase 9 / W3 — DeepLink router (DEEP-05).
    /// **D-09 cold-start defer:** init cheap, register-handler выполняется в detached Task;
    /// routing запускается только после `applyInitialStatusSnapshot` через `pendingDeepLink`
    /// buffer в BBTBRootView.
    private let deepLinkRouter: DeepLinkRouter

    init() {
        // Phase 6d Wave 02a — open ColdLaunch interval as the very first
        // statement. Closes in BBTBRootView.onAppear. Instrumentation only;
        // никаких behavioral changes.
        let coldID = PerfSignposter.app.makeSignpostID()
        self.coldLaunchState = PerfSignposter.app.beginInterval("ColdLaunch", id: coldID)

        // TELEM-01: установить crash reporter ПЕРВЫМ — чтобы поймать любые init crashes.
        CrashReporter.shared.install()

        // Phase 6d-03a (H1, 2026-05-14): debug bridge gated under #if DEBUG. В Release
        // никаких file copy / диагностических логов на cold start — это закрывает
        // 3/3 strong consensus finding (Opus #40 / Codex #3 / Gemini #1: «синхронный
        // multi-MB file copy на main thread перед первым frame»). Парная гейтация
        // logPath в BaseSingBoxTunnel гарантирует, что DEBUG-only это и для writer-а.
        //
        // History: Phase 1 device debug bridge — вытаскивает sing-box.log из App Group в
        // Documents, откуда Xcode "Download Container" GUI его скачивает (App Group
        // containers недоступны через GUI — Apple ограничение). Сохраняем для разработки.
        #if DEBUG
        let log = Logger(subsystem: "app.bbtb.client.ios", category: "diag")
        if let dst = AppGroupContainer.exportSingBoxLogToDocuments() {
            log.notice("sing-box.log exported to Documents: \(dst.path, privacy: .public)")
        } else {
            log.notice("sing-box.log export skipped — file not found in App Group container")
        }
        #endif

        // CORE-02: регистрируем протоколы
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

        // SwiftData container
        do {
            self.modelContainer = try SwiftDataContainer.makeShared()
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
        let importer = ConfigImporter(
            modelContainer: modelContainer,
            providerBundleIdentifier: "app.bbtb.client.ios.tunnel"
        )
        // Phase 6c / Plan 06C-04 Task 3a/3b — TunnelController slim init; больше нет
        // параметра stateObserver, и старый relay-объект (relay
        // ферил ReconnectStateMachine состояние в VM banner — теперь VM реактивно
        // читает NEVPNStatus сам через `applyVPNStatus(_:)`, без relay).
        let tunnel = TunnelController()
        let vm = MainScreenViewModel(importer: importer, tunnel: tunnel, modelContainer: modelContainer)
        self.viewModel = vm
        // Phase 6 / Wave 6 — SwiftDataFailoverProvider wiring (NET-11).
        // Two-phase init: TunnelController is constructed first with the
        // NoFailoverProvider default; then SwiftDataFailoverProvider is built
        // capturing `[weak tunnel]` to break the cycle; then we swap it in.
        let userDefaults = UserDefaults.standard
        let failoverProvider = SwiftDataFailoverProvider(
            modelContainer: modelContainer,
            provisioner: importer,
            connect: { [weak tunnel] in
                guard let tunnel else { throw CancellationError() }
                return try await tunnel.connect()
            },
            currentServerID: {
                userDefaults.string(forKey: "app.bbtb.selectedServerID").flatMap(UUID.init(uuidString:))
            }
        )

        // Phase 6d Wave 03f (M1) — ONE ordered launch-time Task replaces the
        // 4 separate fire-and-forget Tasks of Phase 6c+6 (OnDemandMigrationTask,
        // setFailoverProvider, setWatchdog+TunnelWatchdog, startReachability).
        // Pre-Wave-03f: каждый Task независимо racing для NetworkExtension XPC /
        // Mach ports на cold start — same crash class as
        // `feedback_nevpn_xpc_mach_port.md` (40+/sec → PORT_SPACE).
        //
        // Ordering invariants (PRESERVED — все были implicit раньше, теперь
        // явно сериализованы):
        //   1. `OnDemandMigrationTask.runIfNeeded()` — должна успеть
        //      запостить `.bbtbProvisionerDidSave` ДО того, как
        //      `startReachability` сделает `refreshCachedManager` (иначе
        //      controller возьмёт устаревший manager без on-demand toggle).
        //   2. `TunnelWatchdog` создаётся ПЕРЕД `bootstrap` чтобы failover
        //      observer был зарегистрирован до того, как reachability начнёт
        //      forward'ить статус-события в watchdog.
        //   3. `bootstrap(failoverProvider:watchdog:)` атомарно делает
        //      setFailoverProvider → setWatchdog → startReachability и
        //      возвращает `InitialStatusSnapshot` — Sendable snapshot из
        //      уже-загруженного `cachedManager`. ОДИН XPC trip
        //      (`loadAllFromPreferences` внутри `refreshCachedManager`).
        //   4. `vm.applyInitialStatusSnapshot(_:)` применяет тот же snapshot
        //      к VM (через `applyVPNStatus` — single UI authority, D-09) и
        //      флипает `initialManagersApplied` так, что in-flight init seed
        //      Task в VM становится no-op перед своим бы XPC trip-ом.
        // Total cold-start XPC: 1 (was 2 — duplicate seed в VM init); total
        // unstructured launch Tasks: 1 ordered chain + 1 detached migration =
        // 2 (was 5).
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

        // Phase 8 / W4 — RULES-04 Rules Engine bootstrap + background scheduler.
        //
        // (1) Construct cheap coordinator (D-12: init без I/O — safe в App.init).
        // (2) Зарегистрировать BGAppRefreshTask handler SYNCHRONOUSLY до завершения
        //     init (Apple requirement — system throws на submit если identifier не
        //     registered к моменту applicationDidFinishLaunching).
        // (3) Defer baseline copy + ViewModel wire-up в detached Task (DEC-06d-01
        //     cold-start defer; rules apply baseline в background ~ms).
        // (4) Submit первый BGAppRefreshTaskRequest с earliestBeginDate = +6h
        //     (lower bound — OS may delay; см. 08-RESEARCH.md § Pattern 3).
        let rulesCoordinator = RulesEngineCoordinator()
        self.rulesCoordinator = rulesCoordinator

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: rulesRefreshTaskIdentifier,
            using: nil  // default OS-managed serial queue
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Phase 8 / Pitfall 2 — expiration handler must call setTaskCompleted
            // ИЛИ дать выполниться основному Task до OS-budget (30 sec). OS убивает
            // фоновую работу когда expirationHandler fires; coordinator завершит
            // refresh самостоятельно или upcoming BG-slot повторит. Принципиально
            // вызвать setTaskCompleted — иначе iOS снизит будущий бюджет приложения.
            refresh.expirationHandler = {
                refresh.setTaskCompleted(success: false)
            }
            // Поспешим зашедулить следующий refresh ДО фактического fetch — даже
            // если performBackgroundRefresh упадёт / OS прервёт, окно через 6h
            // уже в очереди (Pitfall 2 safeguard — Reschedule на failure).
            let nextRequest = BGAppRefreshTaskRequest(identifier: rulesRefreshTaskIdentifier)
            nextRequest.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
            try? BGTaskScheduler.shared.submit(nextRequest)

            Task.detached(priority: .utility) {
                let success = await rulesCoordinator.performBackgroundRefresh()
                refresh.setTaskCompleted(success: success)
            }
        }

        // First-launch submit (idempotent — OS заменяет previous pending request
        // с тем же identifier). try? — submit может выкинуть если user отключил
        // Background App Refresh; foreground sanity fetch (12h threshold) бэкап.
        let initialRequest = BGAppRefreshTaskRequest(identifier: rulesRefreshTaskIdentifier)
        initialRequest.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(initialRequest)

        // Cold-start defer (DEC-06d-01): baseline copy в detached Task — НЕ блокирует
        // App.init / первый frame. coordinator.bootstrap() идемпотентен и идёт ~10ms.
        Task.detached(priority: .utility) { [rulesCoordinator] in
            await rulesCoordinator.bootstrap()
        }

        // Phase 9 / W3 — DEEP-05 DeepLinkRouter init + ImportHandler registration.
        // Actor — Sendable, init cheap (no I/O) — safe в App.init per DEC-06d-01.
        // Register ImportHandler в detached Task (Sendable capture, no main-thread block).
        // RemoteTokenFetchHandler — stub, не регистрируется в v0.9 (per D-03).
        let deepLinkRouter = DeepLinkRouter()
        self.deepLinkRouter = deepLinkRouter
        let importHandler = ImportHandler(importer: importer)
        Task.detached(priority: .utility) { [deepLinkRouter] in
            await deepLinkRouter.register(importHandler)
        }

        // Phase 6d-03e Commit 2 (M2) — deferred Phase 2→3 SwiftData migration.
        // Раньше `SwiftDataContainer.makeShared()` синхронно гонял migration
        // в App.init (блокировал cold start на upgrade-устройствах). Теперь
        // makeShared только открывает контейнер; миграция выполняется в
        // detached background Task ПОСЛЕ того, как viewModel/tunnel уже
        // сконструированы (UI рендерит первый frame параллельно). Idempotent
        // UserDefaults flag → fresh installs скипают за один guard-check.
        // Wave 03f (M1): остаётся отдельной Task.detached потому что (а)
        // background priority, (б) семантически независимая от NE bootstrap'а
        // SwiftData миграция (не contend'ит за XPC) — оставляем параллельной.
        let mc = modelContainer
        Task.detached(priority: .background) {
            await SwiftDataContainer.runMigrationsIfNeeded(in: mc)
        }
    }

    var body: some Scene {
        WindowGroup {
            BBTBRootView(viewModel: viewModel, rulesCoordinator: rulesCoordinator, deepLinkRouter: deepLinkRouter)
                .onAppear {
                    // Phase 6d Wave 02a — close ColdLaunch span on first root
                    // view appearance. Idempotent: SwiftUI may call onAppear
                    // multiple times, but OSSignposter.endInterval guards
                    // against double-end via interval state.
                    PerfSignposter.app.endInterval("ColdLaunch", coldLaunchState)
                }
        }
        .modelContainer(modelContainer)
    }
}

/// Phase 2 W4.T9 — NavigationStack wrapper для iOS push на SettingsView.
private struct BBTBRootView: View {
    @ObservedObject var viewModel: MainScreenViewModel
    /// Phase 8 / W4 — Rules Engine coordinator propagated from App.init для
    /// `wireRulesCoordinator(_:)` на оба ViewModel + foreground sanity fetch (12h).
    let rulesCoordinator: RulesEngineCoordinator
    /// Phase 9 / W3 — DeepLink router (DEEP-05). Используется в `.onOpenURL` /
    /// `.onContinueUserActivity` modifiers + cold-start pending flush в `.task`.
    let deepLinkRouter: DeepLinkRouter
    @State private var showSettings = false
    @StateObject private var settingsVM = SettingsViewModel()
    @Environment(\.scenePhase) private var scenePhase
    /// Phase 9 / D-09 — cold-start pending deep link buffer. Если `.onOpenURL` /
    /// `.onContinueUserActivity` fires ДО `applyInitialStatusSnapshot`, URL буферизуется
    /// здесь и flush'ится в `.task` block после VM ready. Bounded: single-slot —
    /// последующий tap перезаписывает предыдущий (T-09-05 accepted per threat model).
    @State private var pendingDeepLink: URL?

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
        // Phase 8 / W4 — wire RulesEngineCoordinator в оба VM (RULES-04 / RULES-09 / RULES-10 / D-11).
        // `.task` запускается один раз при первом появлении view (~ совпадает с
        // cold-start), на MainActor. Внутри — sequential await chain: сначала
        // settingsVM (нужен для Settings → Расширенные UI), затем mainScreenVM
        // (нужен для min_app_version sheet trigger). Both wires идемпотентны.
        // Phase 9 / D-09 — flush cold-start pending deep link ПОСЛЕ VM ready.
        .task {
            await settingsVM.wireRulesCoordinator(rulesCoordinator)
            await viewModel.wireRulesCoordinator(rulesCoordinator)
            // Phase 9 / D-09 — flush pending deep link after VM is ready for routing.
            if let pending = pendingDeepLink {
                pendingDeepLink = nil
                viewModel.handleDeepLink(pending, router: deepLinkRouter)
            }
        }
        // Phase 9 / DEEP-01 — bbtb:// custom URL scheme доставка через SwiftUI.
        // Fires on iOS когда OS открывает app по custom scheme URL.
        .onOpenURL { url in
            routeOrBuffer(url)
        }
        // Phase 9 / DEEP-02 — Universal Links (https://import.bbtb.app/import?…).
        // iOS доставляет Universal Links через NSUserActivity (НЕ через .onOpenURL).
        // На macOS это ЕДИНСТВЕННЫЙ канал для Universal Links (см. 09-RESEARCH § Pitfall #1).
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            routeOrBuffer(url)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Phase 6e Wave 1 M7 (D-01) — consolidated single-Task scenePhase
            // handler. Раньше было 3 параллельных Task'а (Task.detached для
            // runIsSupportedUpgrade + Task для tc.handleForeground + Task для
            // viewModel.handleForeground) + дополнительный 4-й Task внутри
            // MainScreenView для silentForegroundRefresh — все они contend'или
            // за Mach ports / cooperative pool. Теперь ОДИН Task spawn вызывает
            // последовательный handleForegroundReentry, который держит inside
            // DEC-06d-01 defer pattern для runIsSupportedUpgrade (Task.detached
            // background priority preserved) + sequentially await'ит остальные
            // hooks. Подробности в MainScreenViewModel.handleForegroundReentry doc.
            guard newPhase == .active else { return }
            Task { @MainActor in await viewModel.handleForegroundReentry() }
            // Phase 8 / W4 — Pitfall 2 foreground sanity fetch. Если user отключил
            // iOS Background App Refresh, BGAppRefreshTask никогда не fires → cache
            // правил будет stale. На каждый foreground re-entry проверяем
            // lastFetchedAt; если > 12 * 3600 (12h — двойной cadence) — детач'нем
            // refresh. Threshold 12h — sweet spot между responsiveness и VPS traffic.
            Task { @MainActor in await foregroundSanityFetch() }
        }
    }

    /// Phase 9 / D-09 — cold-start buffer helper.
    /// If VM is ready (`initialManagersApplied`), dispatch immediately via handleDeepLink.
    /// Otherwise buffer the URL for flush in `.task` after wireRulesCoordinator.
    @MainActor
    private func routeOrBuffer(_ url: URL) {
        if viewModel.initialManagersApplied {
            viewModel.handleDeepLink(url, router: deepLinkRouter)
        } else {
            pendingDeepLink = url
        }
    }

    /// Phase 8 / W4 — foreground sanity fetch (RULES-04 / Pitfall 2).
    /// Запускается на scene .active. Threshold = 12 * 3600 секунд (см.
    /// 08-RESEARCH.md § Pitfall 2). Detached в background priority — НЕ блокирует UI.
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
