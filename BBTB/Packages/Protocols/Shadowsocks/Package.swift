// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shadowsocks",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Shadowsocks", targets: ["Shadowsocks"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "Shadowsocks",
            dependencies: ["VPNCore", "PacketTunnelKit"],
            path: "Sources/Shadowsocks",
            resources: [
                .process("Resources/SingBoxConfigTemplate.shadowsocks.json"),
            ]
        ),
        .testTarget(
            name: "ShadowsocksTests",
            dependencies: ["Shadowsocks"],
            path: "Tests/ShadowsocksTests",
            linkerSettings: [
                // libbox transitive deps — Shadowsocks → PacketTunnelKit → SingBoxBridge → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
