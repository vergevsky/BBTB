// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ProtocolRegistry",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ProtocolRegistry", targets: ["ProtocolRegistry"])],
    dependencies: [.package(path: "../VPNCore")],
    targets: [
        .target(name: "ProtocolRegistry", dependencies: ["VPNCore"]),
    ]
)
