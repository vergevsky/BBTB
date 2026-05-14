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
import os.signpost

@main
struct BBTB_macOSApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var viewModel: MainScreenViewModel
    /// Phase 6d Wave 02a — ColdLaunch span (init → BBTBMacOSRootView.onAppear).
    /// Instruments → Points of Interest → category=performance.
    private let coldLaunchState: OSSignpostIntervalState

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
            BBTBMacOSRootView(viewModel: viewModel)
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
        Settings {
            SettingsView(viewModel: SettingsViewModel())
                .frame(width: 480, height: 360)
        }

        MenuBarExtra(L10n.appShortName, systemImage: viewModel.state.menuBarSymbol) {
            MenuBarContent(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Phase 2 W4.T9 — NavigationStack для menu icon push на Settings (дубль Cmd+, entry).
private struct BBTBMacOSRootView: View {
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
            // Phase 6e Wave 1 M7 (D-01) — mirror iOS consolidated single-Task
            // handler. Раньше было 3 параллельных Task'а — теперь ОДИН
            // последовательный handleForegroundReentry внутри которого
            // DEC-06d-01 cold-start defer для runIsSupportedUpgrade сохранён.
            // macOS-specific: NSWorkspace.didWakeNotification observer регистрируется
            // отдельно внутри TunnelController.startReachability — тут не трогаем.
            guard newPhase == .active else { return }
            Task { @MainActor in await viewModel.handleForegroundReentry() }
        }
    }
}
