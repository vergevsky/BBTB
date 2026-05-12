// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TransportRegistry",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "TransportRegistry", targets: ["TransportRegistry"])],
    dependencies: [.package(path: "../VPNCore")],
    targets: [
        .target(name: "TransportRegistry", dependencies: ["VPNCore"]),
        .testTarget(name: "TransportRegistryTests", dependencies: ["TransportRegistry", "VPNCore"]),
    ]
)
