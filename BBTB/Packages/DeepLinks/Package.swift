// swift-tools-version: 6.0
import PackageDescription

// Phase 9 / DEEP-05 — Deep-link routing SwiftPM package.
//
// Domain: парсит входящие URL (bbtb:// custom scheme + https://import.bbtb.app Universal Links)
// и dispatches их на зарегистрированные DeepLinkHandler'ы.
//
// Architecture: actor coordinator (DeepLinkRouter) + extensible handler registry
// (DeepLinkHandler protocol). Phase 9 регистрирует ONE concrete (ImportHandler в Wave 2).
// В v1+ добавляется RemoteTokenFetchHandler (stub уже в пакете per D-03).
//
// External dep: NONE — pure Foundation/OSLog. SSRF/HTTPS validation уже выполняется
// внутри ConfigImporter.importFromRawInput → SubscriptionURLFetcher (Phase 2 hardened).

let package = Package(
    name: "DeepLinks",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DeepLinks", targets: ["DeepLinks"]),
    ],
    dependencies: [
        // Local sibling packages.
        .package(path: "../VPNCore"),
        // ConfigParser — re-used by Wave 2 ImportHandler через ConfigImporting protocol
        // (delivered to handler via dependency injection). Wave 1 пакет НЕ ссылается
        // на ConfigImporter напрямую; зависимость прописана сейчас, чтобы Wave 2 plan
        // не трогал Package.swift вообще.
        .package(path: "../ConfigParser"),
    ],
    targets: [
        .target(
            name: "DeepLinks",
            dependencies: [
                "VPNCore",
                "ConfigParser",
            ]
        ),
        .testTarget(
            name: "DeepLinksTests",
            dependencies: ["DeepLinks"],
            linkerSettings: [
                // libbox transitive dep линкуется через ConfigParser → PoolBuilder
                // → PacketTunnelKit → SingBoxBridge → Libbox xcframework.
                // DeepLinksTests наследует эту цепочку через `.dependencies: ["DeepLinks"]`,
                // потому что DeepLinks target имеет dependency на ConfigParser.
                // Mirror ConfigParser/Package.swift linker flags + RulesEngine/Package.swift
                // pattern для completeness (Rule 3 deviation: plan заявлял "NO linkerSettings",
                // но XCTest linker всё равно требует Libbox symbols — same situation как
                // RulesEngineTests).
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
