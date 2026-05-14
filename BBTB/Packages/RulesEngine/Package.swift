// swift-tools-version: 6.0
import PackageDescription

// Phase 8 / RULES-01..02 — Rules Engine SwiftPM package.
//
// Domain: fetch signed rules manifest + SRS files from VPS (HTTPS + SSRF + mirror failover)
// и verify Ed25519 detached signature через swift-crypto.
//
// Architecture: separation of concerns —
//   * RulesFetcher — HTTPS+SSRF wrapper над URLSession + sequential mirror failover (DEC-06d-04).
//   * RulesSigner — pure-function Ed25519 verify через CryptoKit re-export (zero binary cost on Apple).
//   * RulesManifest — Codable schema для server-side manifest (snake_case mapping).
//   * RulesEngineCoordinator (W2) — orchestrates fetch → verify → atomic-write → notify.
//
// Public key — 32-байтный hardcoded Ed25519 constant (PHASE 8 W1 placeholder, real bytes per user_setup).
// External dep: apple/swift-crypto 4.x — Apple-supported, на iOS/macOS re-exports CryptoKit
// без бинарного hit для main app или NE extension (verify живёт ТОЛЬКО в main app per Architectural
// Responsibility Map в 08-RESEARCH.md).

let package = Package(
    name: "RulesEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RulesEngine", targets: ["RulesEngine"]),
    ],
    dependencies: [
        // Local sibling packages.
        .package(path: "../VPNCore"),
        // ConfigParser — reuse public SubscriptionURLFetcher.isBlockedHost SSRF helper (W0 promoted).
        .package(path: "../ConfigParser"),
        // swift-crypto 4.x — Apple-supported Ed25519 detached signature verify.
        // На Apple platforms re-exports CryptoKit (zero binary cost); на non-Apple targets
        // — bundled BoringSSL fallback. См. 08-RESEARCH.md § Standard Stack.
        .package(url: "https://github.com/apple/swift-crypto.git", "4.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "RulesEngine",
            dependencies: [
                "VPNCore",
                "ConfigParser",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            resources: [
                // W6 разместит baseline-rules-manifest.json + 3 baseline .srs + .sig sidecars.
                // .gitkeep placeholder сохраняет директорию в репозитории до того момента.
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "RulesEngineTests",
            dependencies: ["RulesEngine", "ConfigParser"],
            resources: [
                // W1.4 разместит fixtures (e.g., тестовые signed messages) если потребуется.
                .process("Fixtures"),
            ]
        ),
    ]
)
