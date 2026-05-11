import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import VLESSReality
import ProtocolRegistry
import CrashReporter

@main
struct BBTB_iOSApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: MainScreenViewModel

    init() {
        // TELEM-01: установить crash reporter ПЕРВЫМ — чтобы поймать любые init crashes.
        CrashReporter.shared.install()

        // CORE-02: регистрируем протоколы
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)

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
        self.viewModel = MainScreenViewModel(importer: importer, tunnel: tunnel)
    }

    var body: some Scene {
        WindowGroup {
            MainScreenView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
    }
}
