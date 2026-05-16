// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
    dependencies: [
        // Phase 12 / DS-15 — pin 1.18.3+ per RESEARCH Risk #6 (main-thread deadlock fix in 1.18.0).
        // Test-only dep — НЕ попадает в shipping bundle (verified threat_model T-12-01-01).
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.3"),
        // Phase 12 (2026-05-16 design pass) — Phosphor Icons Bold семейство.
        // Re-exported из DesignSystem через PhosphorReexport.swift → доступно во всех
        // features через `import DesignSystem` (Ph.list.bold, Ph.plus.bold, etc.).
        // iOS 13+ / macOS 10.15+ — fully compatible с нашими iOS 18 / macOS 15 minimums.
        .package(url: "https://github.com/phosphor-icons/swift", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                // 2026-05-16 — re-export Phosphor icons как часть design system surface.
                .product(name: "PhosphorSwift", package: "swift"),
            ]
        ),
        // Phase 12 / DS-15 — unit token assertions (DSColor + DSTokens).
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        ),
        // Phase 12 / DS-15 — pixel-perfect image snapshots (baselines под __Snapshots__/).
        // N1: StrictConcurrency=complete для ловли concurrency issues в @MainActor snapshot setUp blocks
        // до того, как они проявятся при расширении test corpus в Plan 12-02.
        .testTarget(
            name: "DesignSystemSnapshotTests",
            dependencies: [
                "DesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
            ]
        ),
    ]
)
