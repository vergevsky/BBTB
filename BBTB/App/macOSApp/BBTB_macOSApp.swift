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
        // Phase 6c / Plan 06C-04 / D-17b/c — one-shot migration of existing manager to on-demand.
        // Идемпотентный fire-and-forget. См. doc-comment в OnDemandMigrationTask.swift.
        Task { await OnDemandMigrationTask.runIfNeeded() }
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
        Task { await tunnel.setFailoverProvider(failoverProvider) }
        // Phase 6c / Plan 06C-04 / Task 1 — TunnelWatchdog для mid-session
        // server failover (D-08, D-09). Late-binding setter mirror того, как
        // failoverProvider wires.
        //
        // Task 3b — register failover observer so successful mid-session swaps
        // surface as `.failover(toServerName:)` banner in VM.
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
        // macOS: TunnelController.startReachability also installs the
        // NSWorkspace.didWakeNotification observer (Pitfall 10).
        Task { await tunnel.startReachability() }
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
            if newPhase == .active {
                Task { await viewModel.importer.runIsSupportedUpgrade() }
                // Phase 6 / NET-09 — cheap foreground hook. macOS additionally
                // observes NSWorkspace.didWakeNotification inside TunnelController.
                if let tc = viewModel.tunnelController {
                    Task { await tc.handleForeground() }
                }
                // Phase 6c re-UAT fix (2026-05-13) — VM UI resync. На macOS
                // System Settings → VPN toggle off аналогично может проглотить
                // NEVPNStatusDidChange пока окно неактивно. См. doc handleForeground().
                Task { await viewModel.handleForeground() }
            }
        }
    }
}
