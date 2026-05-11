import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import MenuBarFeature
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
            MainScreenView(viewModel: viewModel)
                .frame(minWidth: 380, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)

        MenuBarExtra(L10n.appShortName, systemImage: viewModel.state.menuBarSymbol) {
            MenuBarContent(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
