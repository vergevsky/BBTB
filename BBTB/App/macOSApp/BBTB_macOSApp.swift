import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import MenuBarFeature
import SettingsFeature
import VLESSReality
import Trojan
import ProtocolRegistry
import Localization
import CrashReporter

@main
struct BBTB_macOSApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var viewModel: MainScreenViewModel

    init() {
        // TELEM-01
        CrashReporter.shared.install()

        ProtocolRegistry.shared.register(VLESSRealityHandler.self)
        ProtocolRegistry.shared.register(TrojanHandler.self)  // Phase 2 PROTO-02

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
        let tunnel = TunnelController()
        _viewModel = StateObject(wrappedValue: MainScreenViewModel(importer: importer, tunnel: tunnel))
    }

    var body: some Scene {
        Window(L10n.appShortName, id: "main") {
            BBTBMacOSRootView(viewModel: viewModel)
                .frame(minWidth: 380, minHeight: 520)
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
    }
}
