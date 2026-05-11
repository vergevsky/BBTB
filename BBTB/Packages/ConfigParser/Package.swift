// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ConfigParser",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ConfigParser", targets: ["ConfigParser"])],
    dependencies: [
        .package(path: "../VPNCore"),
        // Test target depends on PacketTunnelKit for R1 self-test in integration tests
        // (PATTERNS §3.6: production ConfigParser is independent of PacketTunnelKit).
        .package(path: "../PacketTunnelKit"),
    ],
    targets: [
        .target(name: "ConfigParser", dependencies: ["VPNCore"]),
        .testTarget(
            name: "ConfigParserTests",
            dependencies: ["ConfigParser", "PacketTunnelKit"],
            resources: [.process("Fixtures")],
            linkerSettings: [
                // libbox transitive deps for SingBoxConfigLoader self-tests.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
