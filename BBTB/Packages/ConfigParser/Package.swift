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
        // Phase 4 IMP-05 — YAML parsing for Clash subscription import.
        // jpsim/Yams 6.2.1 (MIT, verified 04-RESEARCH.md Security Domain).
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        // Phase 5 Wave 7 — PoolBuilder coordinator delegates to each protocol package.
        .package(path: "../Protocols/VLESSReality"),
        .package(path: "../Protocols/VLESSTLS"),
        .package(path: "../Protocols/Trojan"),
        .package(path: "../Protocols/Shadowsocks"),
        .package(path: "../Protocols/Hysteria2"),
        // Phase 7a Wave 1 — TUIC v5 protocol package (PROTO-08).
        .package(path: "../Protocols/TUIC"),
        // Phase 5 Wave 7 — test target needs TransportRegistry to register handlers in integration tests.
        .package(path: "../TransportRegistry"),
    ],
    targets: [
        .target(
            name: "ConfigParser",
            dependencies: [
                "VPNCore",
                .product(name: "Yams", package: "Yams"),
                "VLESSReality",
                "VLESSTLS",
                "Trojan",
                "Shadowsocks",
                "Hysteria2",
                "TUIC",  // Phase 7a Wave 1 — PROTO-08
            ]
        ),
        .testTarget(
            name: "ConfigParserTests",
            dependencies: ["ConfigParser", "PacketTunnelKit", "TransportRegistry"],
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
