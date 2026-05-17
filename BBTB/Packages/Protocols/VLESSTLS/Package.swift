// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VLESSTLS",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VLESSTLS", targets: ["VLESSTLS"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
        .package(path: "../../TransportRegistry"),
    ],
    targets: [
        .target(
            name: "VLESSTLS",
            dependencies: ["VPNCore", "PacketTunnelKit", "TransportRegistry"],
            path: "Sources/VLESSTLS"
            // T-C8' (closes A6'-001): dead JSON template removed.
        ),
        .testTarget(
            name: "VLESSTLSTests",
            dependencies: ["VLESSTLS"],
            path: "Tests/VLESSTLSTests",
            linkerSettings: [
                // libbox transitive deps — VLESSTLS → PacketTunnelKit → SingBoxBridge → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
