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
    ],
    targets: [
        .target(name: "DesignSystem"),
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
