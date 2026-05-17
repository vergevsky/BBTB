// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trojan",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Trojan", targets: ["Trojan"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
        .package(path: "../../TransportRegistry"),
    ],
    targets: [
        .target(
            name: "Trojan",
            dependencies: ["VPNCore", "PacketTunnelKit", "TransportRegistry"],
            path: "Sources/Trojan"
            // T-C8' (closes A6'-001): dead JSON templates removed.
        ),
        .testTarget(
            name: "TrojanTests",
            dependencies: ["Trojan"],
            path: "Tests/TrojanTests",
            linkerSettings: [
                // libbox transitive deps — Trojan → PacketTunnelKit → SingBoxBridge → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
