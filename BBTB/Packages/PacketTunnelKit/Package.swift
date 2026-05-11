// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PacketTunnelKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "PacketTunnelKit", targets: ["PacketTunnelKit"])],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../ProtocolEngine"),
    ],
    targets: [
        .target(
            name: "PacketTunnelKit",
            dependencies: [
                "VPNCore",
                .product(name: "SingBoxBridge", package: "ProtocolEngine"),
            ],
            resources: [
                .process("Resources/SingBoxConfigTemplate.vless-reality.json")
            ]
        ),
        .testTarget(
            name: "PacketTunnelKitTests",
            dependencies: ["PacketTunnelKit"],
            resources: [
                .process("Fixtures")
            ],
            linkerSettings: [
                // libbox v1.13.11 транзитивные зависимости (R8 wiki) — нужны и для test-бинарника,
                // потому что он линкует PacketTunnelKit → SingBoxBridge → libbox.xcframework.
                // В production targets (BBTB-Tunnel-{iOS,macOS}) эти флаги выставляет Tuist
                // через OTHER_LDFLAGS; SPM testTarget делает это сам через linkerSettings.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),  // _audit_token_to_pid
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
