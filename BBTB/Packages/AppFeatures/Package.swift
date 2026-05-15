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
        .package(path: "../Protocols/VLESSTLS"),
        .package(path: "../Protocols/Shadowsocks"),
        .package(path: "../Protocols/Hysteria2"),
        .package(path: "../Protocols/TUIC"),  // Phase 7a Wave 1 — PROTO-08
        // Phase 8 W3 — RULES-09/10/MinAppVersion UI потребляет RulesSnapshot +
        // RulesEngineCoordinator + ForceUpdateOutcome + .bbtbRulesEngineDidUpdate
        // notification из leaf-package RulesEngine. SettingsFeature биндит
        // viewer/force-update UI, MainScreenFeature биндит min_app_version sheet.
        .package(path: "../RulesEngine"),
        // Phase 9 W3 — DEEP-05: MainScreenViewModel.handleDeepLink принимает
        // DeepLinkRouter + DeepLinkError через existing error UX path (D-08).
        .package(path: "../DeepLinks"),
        // Phase 10 W4 — DPI-06: ConfigImporter.provisionTunnelProfile применяет CDN overlay через
        // FrontingConfigApplier (main-app-only; tunnel extension не использует CDN logic).
        .package(path: "../FrontingEngine"),
    ],
    targets: [
        .target(
            name: "MainScreenFeature",
            dependencies: [
                "VPNCore", "DesignSystem", "Localization",
                "ConfigParser", "KillSwitch", "VLESSReality",
                "Trojan",  // Phase 2 W2.T1
                "VLESSTLS",
                "Shadowsocks",
                "Hysteria2",
                "TUIC",  // Phase 7a Wave 1 — PROTO-08
                "ServerListFeature",  // Phase 3 Plan 03 — для .sheet(ServerListSheet)
                "RulesEngine",  // Phase 8 W3 — MinAppVersionSheet observes RulesEngineCoordinator
                "DeepLinks",    // Phase 9 W3 — handleDeepLink(_:router:) method
                "FrontingEngine",  // Phase 10 W4 — DPI-06: FrontingConfigApplier in ConfigImporter
            ]
        ),
        .target(
            name: "MenuBarFeature",
            dependencies: ["MainScreenFeature", "Localization", "VPNCore"]
        ),
        .target(
            name: "SettingsFeature",
            // Phase 6c / Plan 06C-03 / Round 2 B-09 — explicit dep on MainScreenFeature
            // для доступа к `OnDemandRulesBuilder.applyCurrentState` и `ManagerSelector.ourManagers`
            // из `SettingsViewModel.applyAutoReconnectToManager` (toggle live-apply path).
            // Cycle safety: MainScreenFeature target deps НЕ содержат SettingsFeature (verified).
            dependencies: ["VPNCore", "DesignSystem", "Localization", "KillSwitch", "MainScreenFeature",
                           // Phase 8 W3 — RulesViewerSection + ForceUpdateRulesButton + MinAppVersionBanner
                           // потребляют RulesSnapshot/ForceUpdateOutcome/RulesEngineCoordinator из leaf-пакета.
                           "RulesEngine"]
        ),
        // Phase 3 Plan 03 — server-list sheet UI.
        // Phase 3 Plan 04 — pull-to-refresh + merge → требуется ConfigParser
        // (UniversalImportParsing, SubscriptionURLFetching, ImportedServer, ImportResult).
        .target(
            name: "ServerListFeature",
            dependencies: ["VPNCore", "DesignSystem", "Localization", "ConfigParser"]
        ),
        .testTarget(
            name: "MainScreenFeatureTests",
            dependencies: ["MainScreenFeature", "SettingsFeature", "DeepLinks"],
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
            dependencies: ["ServerListFeature", "ConfigParser"]
        ),
        // Phase 6 / 06-03 — Settings DNS + AdvancedSettingsView coverage.
        // Phase 8 W3 — добавили RulesEngine для SettingsViewModelTests + MinAppVersionTests + ForceUpdateButtonStateTests.
        .testTarget(
            name: "SettingsFeatureTests",
            dependencies: ["SettingsFeature", "VPNCore", "RulesEngine"]
        ),
    ]
)
