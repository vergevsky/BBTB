// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFeatures",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MainScreenFeature", targets: ["MainScreenFeature"]),
        .library(name: "MenuBarFeature", targets: ["MenuBarFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),  // Phase 2 W4.T6
        .library(name: "ServerListFeature", targets: ["ServerListFeature"]),  // Phase 3 Plan 03
    ],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Localization"),
        .package(path: "../ConfigParser"),
        .package(path: "../KillSwitch"),
        .package(path: "../Protocols/VLESSReality"),
        .package(path: "../Protocols/Trojan"),  // Phase 2 W2.T1
    ],
    targets: [
        .target(
            name: "MainScreenFeature",
            dependencies: [
                "VPNCore", "DesignSystem", "Localization",
                "ConfigParser", "KillSwitch", "VLESSReality",
                "Trojan",  // Phase 2 W2.T1
                "ServerListFeature",  // Phase 3 Plan 03 — для .sheet(ServerListSheet)
            ]
        ),
        .target(
            name: "MenuBarFeature",
            dependencies: ["MainScreenFeature", "Localization", "VPNCore"]
        ),
        .target(
            name: "SettingsFeature",
            dependencies: ["VPNCore", "DesignSystem", "Localization", "KillSwitch"]
        ),
        // Phase 3 Plan 03 — server-list sheet UI.
        .target(
            name: "ServerListFeature",
            dependencies: ["VPNCore", "DesignSystem", "Localization"]
        ),
        .testTarget(
            name: "MainScreenFeatureTests",
            dependencies: ["MainScreenFeature", "SettingsFeature"],
            linkerSettings: [
                // libbox transitive — MainScreenFeature → VLESSReality → PacketTunnelKit → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "ServerListFeatureTests",
            dependencies: ["ServerListFeature"]
        ),
    ]
)
