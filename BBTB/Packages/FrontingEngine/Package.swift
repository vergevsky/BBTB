// swift-tools-version: 6.0
import PackageDescription

// Phase 10 / DPI-06 — CDN-фронтинг пакет.
//
// Архитектура (D-03..D-07 в 10-CONTEXT.md):
//   * FrontingProfile     — Codable Sendable struct: dial target overlay (D-03)
//   * CDNProviderAdapter  — open protocol для Cloudflare/Fastly/Custom/Bunny (D-04)
//   * FrontingConfigApplier — JSON overlay над expandConfigForTunnel output (D-05)
//   * FrontingFailureCache  — actor: score + cooldown 6-24ч + App Group persistence (D-06)
//   * FrontingFallbackChain — actor: sequential provider chain, concurrency=1 (D-06, DEC-06d-04)
//
// Critical decision D-03: FrontingProfile НЕ часть TransportConfig — иначе 50+ транспортов
// дублируют CDN логику. Отдельный struct → CDN config orthogonal к transport config.
//
// PacketTunnelKit dep — только для AppGroupContainer (cdnFailureCacheURL). НЕ для ConfigParser
// или libbox (CDN решение принимается main app в ConfigImporter, не в extension).
//
// NB: Tuist Project.swift wiring (добавить FrontingEngine в manifest) — Plan 06 (Wave 3).
// В Plan 05 только SwiftPM-уровень build.

let package = Package(
    name: "FrontingEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FrontingEngine", targets: ["FrontingEngine"]),
    ],
    dependencies: [
        // Local sibling packages.
        .package(path: "../VPNCore"),
        // PacketTunnelKit — reuse AppGroupContainer.cdnFailureCacheURL (Plan 05 added).
        // FrontingFailureCache needs shared App Group path for JSON persistence.
        .package(path: "../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "FrontingEngine",
            dependencies: [
                "VPNCore",
                "PacketTunnelKit",
            ]
        ),
        .testTarget(
            name: "FrontingEngineTests",
            dependencies: ["FrontingEngine"],
            resources: [
                .process("Fixtures"),
            ],
            linkerSettings: [
                // libbox transitive dep линкуется через PacketTunnelKit → SingBoxBridge →
                // Libbox xcframework. FrontingEngine зависит от PacketTunnelKit напрямую
                // (не через ConfigParser), поэтому Libbox symbols нужно линковать явно.
                // UniformTypeIdentifiers требуется из-за Libbox platform_mime_util_apple.o
                // (UTType / UTTagClassFilenameExtension symbols) — absent если framework
                // не добавлен явно в test target linker.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
    ]
)
