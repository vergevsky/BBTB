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
            ]
        ),
    ]
)
