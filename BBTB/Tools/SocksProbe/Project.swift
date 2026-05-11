import ProjectDescription

// MARK: SocksProbe — R1 device proof tool
//
// Standalone iOS+macOS приложение, которое сканирует 127.0.0.1 на стандартные SOCKS-порты
// (методичка РКН: 1080, 9000, 5555, 16000-16100, 3128-9150).
//
// **Критично для R1:** SocksProbe должен жить в полностью изолированном sandbox —
// БЕЗ App Group, БЕЗ Keychain Sharing, БЕЗ shared resources с основным проектом.
// Поэтому Tuist project отдельный, не вложен в основной Workspace.swift.

let teamID = "UAN8W9Q82U"

let project = Project(
    name: "SocksProbe",
    organizationName: "BBTB",
    options: .options(
        automaticSchemesOptions: .enabled(targetSchemesGrouping: .singleScheme),
        developmentRegion: "ru"
    ),
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": .string(teamID),
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "CODE_SIGN_STYLE": "Automatic",
        ]
    ),
    targets: [

        // MARK: SocksProbe iOS

        .target(
            name: "SocksProbe",
            destinations: .iOS,
            product: .app,
            bundleId: "app.bbtb.tools.socksprobe.ios",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "SocksProbe",
                "UILaunchScreen": [:],
            ]),
            sources: [
                "Shared/**/*.swift",
                "SocksProbe-iOS/**/*.swift",
            ],
            entitlements: .file(path: "SocksProbe-iOS/SocksProbe-iOS.entitlements")
        ),

        // MARK: SocksProbe macOS

        .target(
            name: "SocksProbe-macOS",
            destinations: [.mac],
            product: .app,
            bundleId: "app.bbtb.tools.socksprobe.macos",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "SocksProbe",
                "LSMinimumSystemVersion": "15.0",
            ]),
            sources: [
                "Shared/**/*.swift",
                "SocksProbe-macOS/**/*.swift",
            ],
            entitlements: .file(path: "SocksProbe-macOS/SocksProbe-macOS.entitlements")
        ),
    ]
)
