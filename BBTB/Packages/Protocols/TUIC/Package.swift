// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TUIC",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "TUIC", targets: ["TUIC"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "TUIC",
            dependencies: ["VPNCore", "PacketTunnelKit"],
            path: "Sources/TUIC"
            // T-C8' (closes A6'-001): dead JSON template removed.
        ),
        .testTarget(
            name: "TUICTests",
            dependencies: ["TUIC"],
            path: "Tests/TUICTests",
            linkerSettings: [
                // libbox transitive deps — TUIC → PacketTunnelKit → SingBoxBridge → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
