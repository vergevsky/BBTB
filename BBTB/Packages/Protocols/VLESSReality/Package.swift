// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VLESSReality",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VLESSReality", targets: ["VLESSReality"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "VLESSReality",
            dependencies: ["VPNCore", "PacketTunnelKit"],
            path: "Sources/VLESSReality"
        ),
        .testTarget(
            name: "VLESSRealityTests",
            dependencies: ["VLESSReality"],
            path: "Tests/VLESSRealityTests",
            linkerSettings: [
                // libbox transitive deps — VLESSReality → PacketTunnelKit → SingBoxBridge → libbox.
                // См. PacketTunnelKit/Package.swift для контекста.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
