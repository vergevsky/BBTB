// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hysteria2",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Hysteria2", targets: ["Hysteria2"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "Hysteria2",
            dependencies: ["VPNCore", "PacketTunnelKit"],
            path: "Sources/Hysteria2"
            // T-C8' (closes A6'-001): dead JSON template removed.
        ),
        .testTarget(
            name: "Hysteria2Tests",
            dependencies: ["Hysteria2"],
            path: "Tests/Hysteria2Tests",
            linkerSettings: [
                // libbox transitive deps — Hysteria2 → PacketTunnelKit → SingBoxBridge → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
