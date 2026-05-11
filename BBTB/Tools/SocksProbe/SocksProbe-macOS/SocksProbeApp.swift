import SwiftUI

@main
struct SocksProbeApp: App {
    var body: some Scene {
        Window("BBTB SocksProbe", id: "main") {
            SocksProbeView()
                .frame(minWidth: 480, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
