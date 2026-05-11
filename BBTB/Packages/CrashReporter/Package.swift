// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrashReporter",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "CrashReporter", targets: ["CrashReporter"])],
    dependencies: [
        .package(path: "../PacketTunnelKit"),
    ],
    targets: [
        .target(name: "CrashReporter", dependencies: ["PacketTunnelKit"]),
        .testTarget(
            name: "CrashReporterTests",
            dependencies: ["CrashReporter"],
            linkerSettings: [
                // libbox transitive — CrashReporter → PacketTunnelKit → SingBoxBridge → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
