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
import CrashReporter
import PacketTunnelKit
import OSLog

@main
struct BBTB_iOSApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: MainScreenViewModel

    init() {
        // TELEM-01: установить crash reporter ПЕРВЫМ — чтобы поймать любые init crashes.
        CrashReporter.shared.install()

        // Phase 1 device debug bridge: вытащить sing-box.log из App Group в Documents,
        // откуда Xcode "Download Container" GUI его уже скачивает (App Group containers
        // через GUI недоступны — Apple ограничение). См. AppGroupContainer.exportSingBoxLogToDocuments.
        // TODO Phase 5: убрать вместе с logPath инъекцией.
        let log = Logger(subsystem: "app.bbtb.client.ios", category: "diag")
        if let dst = AppGroupContainer.exportSingBoxLogToDocuments() {
            log.notice("sing-box.log exported to Documents: \(dst.path, privacy: .public)")
        } else {
            log.notice("sing-box.log export skipped — file not found in App Group container")
        }

        // CORE-02: регистрируем протоколы
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)
        ProtocolRegistry.shared.register(TrojanHandler.self)  // Phase 2 PROTO-02
        ProtocolRegistry.shared.register(VLESSTLSHandler.self)
        ProtocolRegistry.shared.register(ShadowsocksHandler.self)
        ProtocolRegistry.shared.register(Hysteria2Handler.self)

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
        let tunnel = TunnelController()
        self.viewModel = MainScreenViewModel(importer: importer, tunnel: tunnel, modelContainer: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            BBTBRootView(viewModel: viewModel)
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
            }
        }
    }
}
