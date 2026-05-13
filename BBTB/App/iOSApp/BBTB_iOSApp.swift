import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import SettingsFeature
import VLESSReality
import VLESSTLS
import Shadowsocks
import Hysteria2
import Trojan
import ProtocolRegistry
import TransportRegistry
import CrashReporter
import PacketTunnelKit
import OSLog
import os.signpost

@main
struct BBTB_iOSApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: MainScreenViewModel
    /// Phase 6d Wave 02a — ColdLaunch span (init → BBTBRootView.onAppear).
    /// Instruments → Points of Interest → category=performance.
    private let coldLaunchState: OSSignpostIntervalState

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
        // Phase 6c / Plan 06C-04 / D-17b/c — one-shot migration of existing manager to on-demand.
        // Async fire-and-forget; идемпотентный (UserDefaults flag); безопасно если другая
        // часть приложения тоже могла бы это вызвать. Запускаем ДО конструирования
        // TunnelController, чтобы migration успела post `.bbtbProvisionerDidSave` к моменту,
        // когда controller'у понадобится cachedManager (race-safe — initial refresh в
        // `startReachability` всё равно подхватит обновлённый manager).
        Task { await OnDemandMigrationTask.runIfNeeded() }
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
        Task { await tunnel.setFailoverProvider(failoverProvider) }
        // Phase 6c / Plan 06C-04 / Task 1 — TunnelWatchdog для mid-session
        // server failover (D-08, D-09). Late-binding setter mirror того, как
        // failoverProvider wires (cycle-safety не нужна — watchdog не cycle'ит
        // обратно в TunnelController; держим тот же pattern для consistency).
        //
        // Task 3b — register failover observer so successful mid-session swaps
        // surface as `.failover(toServerName:)` banner in VM. The closure
        // hops to MainActor to mutate `reconnectBannerState` safely.
        Task { [weak vm] in
            let watchdog = TunnelWatchdog(failoverProvider: failoverProvider)
            await watchdog.setFailoverObserver { serverName in
                await MainActor.run { [weak vm] in
                    vm?.showFailoverBanner(toServerName: serverName)
                }
            }
            await tunnel.setWatchdog(watchdog)
        }
        // Phase 6 / NET-08..10 — start live reachability observer on launch.
        Task { await tunnel.startReachability() }
    }

    var body: some Scene {
        WindowGroup {
            BBTBRootView(viewModel: viewModel)
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.importer.runIsSupportedUpgrade() }
                // Phase 6 / NET-09 — cheap foreground hook (Pitfall 8). Does NOT
                // unconditionally trigger reconnect — relies on
                // NEVPNStatusDidChange + NetworkReachability for real recovery.
                if let tc = viewModel.tunnelController {
                    Task { await tc.handleForeground() }
                }
                // Phase 6c re-UAT fix (2026-05-13) — resync VM UI state с актуальным
                // NEVPN status: Settings → VPN → toggle off backgrounds app, и
                // итоговый `.disconnected` notification теряется (queue dropped while
                // suspended). См. MainScreenViewModel.handleForeground() doc.
                Task { await viewModel.handleForeground() }
            }
        }
    }
}
