import ProjectDescription

// MARK: Project — BBTB (Bring Back The Bug)
//
// Tuist 4.x декларативная конфигурация. Генерирует BBTB.xcodeproj
// командой `tuist generate` из корня BBTB/.
//
// Источник истины по идентификаторам — Wiki/product-overview.md секция «Имя и идентификаторы».
// Team ID и xcconfig пути — Config/Common.xcconfig.

let teamID = "UAN8W9Q82U"
let bundlePrefix = "app.bbtb.client"

// Общие settings для всех target'ов через xcconfig (executor'овский в Config/).
// `base` keys применяются ко всем target'ам и переживают `tuist generate` —
// иначе Xcode при каждой регенерации забывает signing setup и просит «Enable Development Signing».
let baseSettings = Settings.settings(
    base: [
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "UAN8W9Q82U",
        "CODE_SIGN_IDENTITY": "Apple Development",
    ],
    configurations: [
        .debug(name: "Debug", xcconfig: .relativeToManifest("Config/Debug.xcconfig")),
        .release(name: "Release", xcconfig: .relativeToManifest("Config/Release.xcconfig")),
    ],
    defaultSettings: .recommended
)

// MARK: Локальные SwiftPM packages
//
// 11 пакетов в Packages/. Tuist резолвит локально и предоставляет products
// как dependency через .package(product: "ProductName").

let localPackages: [Package] = [
    .package(path: .relativeToManifest("Packages/VPNCore")),
    .package(path: .relativeToManifest("Packages/ProtocolRegistry")),
    .package(path: .relativeToManifest("Packages/ProtocolEngine")),
    .package(path: .relativeToManifest("Packages/Protocols/VLESSReality")),
    .package(path: .relativeToManifest("Packages/ConfigParser")),
    .package(path: .relativeToManifest("Packages/KillSwitch")),
    .package(path: .relativeToManifest("Packages/PacketTunnelKit")),
    .package(path: .relativeToManifest("Packages/DesignSystem")),
    .package(path: .relativeToManifest("Packages/Localization")),
    .package(path: .relativeToManifest("Packages/AppFeatures")),
    .package(path: .relativeToManifest("Packages/CrashReporter")),
]

// MARK: Targets

let project = Project(
    name: "BBTB",
    organizationName: "BBTB",
    options: .options(
        automaticSchemesOptions: .enabled(
            targetSchemesGrouping: .notGrouped,
            codeCoverageEnabled: true,
            testingOptions: []
        ),
        defaultKnownRegions: ["en", "ru"],
        developmentRegion: "ru"
    ),
    packages: localPackages,
    settings: baseSettings,
    targets: [

        // MARK: iOS app

        .target(
            name: "BBTB",
            destinations: .iOS,
            product: .app,
            bundleId: "\(bundlePrefix).ios",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .file(path: "App/iOSApp/Info.plist"),
            sources: ["App/iOSApp/**/*.swift"],
            resources: ["App/iOSApp/Assets.xcassets"],
            entitlements: .file(path: "App/iOSApp/BBTB-iOS.entitlements"),
            dependencies: [
                .package(product: "VPNCore"),
                .package(product: "ProtocolRegistry"),
                .package(product: "VLESSReality"),
                .package(product: "ConfigParser"),
                .package(product: "KillSwitch"),
                .package(product: "DesignSystem"),
                .package(product: "Localization"),
                .package(product: "MainScreenFeature"),
                .package(product: "CrashReporter"),
                .target(name: "BBTB-Tunnel-iOS"),
            ],
            settings: .settings(
                base: [
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    // libbox линкуется транзитивно через CrashReporter → PacketTunnelKit → SingBoxBridge
                    // — main app target нуждается в тех же linker flags что и extension.
                    "OTHER_LDFLAGS": "$(inherited) -lresolv",
                ]
            )
        ),

        // MARK: macOS app

        .target(
            name: "BBTB-macOS",
            destinations: [.mac],
            product: .app,
            bundleId: "\(bundlePrefix).macos",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .file(path: "App/macOSApp/Info.plist"),
            sources: ["App/macOSApp/**/*.swift"],
            resources: ["App/macOSApp/Assets.xcassets"],
            entitlements: .file(path: "App/macOSApp/BBTB-macOS.entitlements"),
            dependencies: [
                .package(product: "VPNCore"),
                .package(product: "ProtocolRegistry"),
                .package(product: "VLESSReality"),
                .package(product: "ConfigParser"),
                .package(product: "KillSwitch"),
                .package(product: "DesignSystem"),
                .package(product: "Localization"),
                .package(product: "MainScreenFeature"),
                .package(product: "MenuBarFeature"),
                .package(product: "CrashReporter"),
                .target(name: "BBTB-Tunnel-macOS"),
                .target(name: "BBTB-AppProxy-macOS"),
            ],
            settings: .settings(
                base: [
                    "OTHER_LDFLAGS": "$(inherited) -lresolv -framework SystemConfiguration",
                ]
            )
        ),

        // MARK: iOS PacketTunnel Extension

        .target(
            name: "BBTB-Tunnel-iOS",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "\(bundlePrefix).ios.tunnel",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .file(path: "App/PacketTunnelExtension-iOS/Info.plist"),
            sources: ["App/PacketTunnelExtension-iOS/**/*.swift"],
            entitlements: .file(path: "App/PacketTunnelExtension-iOS/PacketTunnelExtension-iOS.entitlements"),
            dependencies: [
                .package(product: "VPNCore"),
                .package(product: "PacketTunnelKit"),
                .package(product: "SingBoxBridge"),
            ],
            settings: .settings(
                base: [
                    // Tuist 4 фильтрует .sdk() для App Extension targets, поэтому
                    // линкер-флаги выставляем явно. libbox v1.13.11 требует:
                    // - libresolv.tbd для BIND-9 resolver (res_9_nclose / ninit / nsearch)
                    // - UIKit.framework для scoped_critical_action.o (UIApplication background task)
                    "OTHER_LDFLAGS": "$(inherited) -lresolv -framework UIKit",
                ]
            )
        ),

        // MARK: macOS PacketTunnel Extension

        .target(
            name: "BBTB-Tunnel-macOS",
            destinations: [.mac],
            product: .appExtension,
            bundleId: "\(bundlePrefix).macos.tunnel",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .file(path: "App/PacketTunnelExtension-macOS/Info.plist"),
            sources: ["App/PacketTunnelExtension-macOS/**/*.swift"],
            entitlements: .file(path: "App/PacketTunnelExtension-macOS/PacketTunnelExtension-macOS.entitlements"),
            dependencies: [
                .package(product: "VPNCore"),
                .package(product: "PacketTunnelKit"),
                .package(product: "SingBoxBridge"),
            ],
            settings: .settings(
                base: [
                    // libbox macOS branch использует:
                    // - AppKit (NSApplication / NSEvent / NSApp в base::MessagePumpNSApplication)
                    // - SystemConfiguration (SCDynamicStore / SCErrorString / kSCPropNet* в
                    //   net::ProxyConfigServiceMac, net::NetworkConfigWatcherAppleThread)
                    // - libresolv для DNS resolver (res_9_*)
                    "OTHER_LDFLAGS": "$(inherited) -lresolv -framework AppKit -framework SystemConfiguration",
                ]
            )
        ),

        // MARK: macOS AppProxy Extension (placeholder под Phase 8)

        .target(
            name: "BBTB-AppProxy-macOS",
            destinations: [.mac],
            product: .appExtension,
            bundleId: "\(bundlePrefix).macos.appproxy",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .file(path: "App/AppProxyExtension-macOS/Info.plist"),
            sources: ["App/AppProxyExtension-macOS/**/*.swift"],
            entitlements: .file(path: "App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements"),
            dependencies: [
                .package(product: "VPNCore"),
            ]
        ),
    ]
)
