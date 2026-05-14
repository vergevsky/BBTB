---
phase: 08-rules-engine-split-tunneling
plan: W1
subsystem: rules-engine
tags: [rules-engine, swiftpm, ed25519, swift-crypto, https-fetcher, ssrf, mirror-failover]
dependency_graph:
  requires:
    - phase: 08
      plan: W0
      provides: "ConfigParser.SubscriptionURLFetcher.isBlockedHost/normalizeHostForLog promoted public"
  provides:
    - "RulesEngine SwiftPM package со swift-crypto 4.5.0 dependency"
    - "RulesSigner.verify(message:signature:) — Ed25519 detached signature verify (pure function)"
    - "RulesFetcher.fetch + fetchWithFailover — HTTPS + SSRF + sequential mirror failover"
    - "RulesManifest Codable schema (snake_case server JSON ↔ camelCase Swift)"
    - "RulesEngineLogger OSLog categories (coordinator/fetcher/signer)"
    - "MockURLProtocol test helper (reusable в W2 coordinator tests)"
  affects:
    - "BBTB/Project.swift — RulesEngine добавлен в localPackages + iOS+macOS app dependencies"
tech_stack:
  added:
    - "apple/swift-crypto 4.5.0 (transitive deps: swift-asn1 1.7.0; CryptoKit re-export на Apple)"
  patterns:
    - "Pure-function verify (PATTERNS §3 enum-namespace + S-3)"
    - "Sequential mirror failover concurrency=1 (DEC-06d-04)"
    - "Pre-flight max-bytes cap для NE memory ceiling defense (Pitfall 3)"
    - "Snake_case ↔ camelCase CodingKeys mapping для server JSON contract"
key_files:
  created:
    - "BBTB/Packages/RulesEngine/Package.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesManifest.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/.gitkeep"
    - "BBTB/Packages/RulesEngine/Tests/RulesEngineTests/MockURLProtocol.swift"
    - "BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesSignerTests.swift"
    - "BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesFetcherTests.swift"
    - "BBTB/Packages/RulesEngine/Tests/RulesEngineTests/Fixtures/.gitkeep"
  modified:
    - "BBTB/Project.swift (localPackages + BBTB iOS + BBTB-macOS dependencies)"
decisions:
  - "RulesSigner exposes verify(_:_:) public + verify(_:_:key:) internal overload — testable без mocking PublicKey"
  - "5 MB payload cap (Pitfall 3 NE memory defense) configurable per call; default constant exposed как RulesFetcher.defaultMaxBytes"
  - "Test target inherits libbox linkerSettings (resolv/SystemConfiguration/AppKit/UIKit) from ConfigParser pattern — нужно из-за transitive deps"
  - "MockURLProtocol перенесён из Fixtures/ в Tests root — SwiftPM не компилирует .swift в resource directories"
metrics:
  duration_minutes: 12
  tasks: 4
  files_created: 11
  files_modified: 1
  tests_added: 17
  tests_passing: 17
  completed: 2026-05-15
---

# Phase 8 Plan W1: RulesEngine SwiftPM Package Summary

**One-liner:** Создан SwiftPM пакет `RulesEngine` со swift-crypto 4.5.0 для Ed25519 signature verify + HTTPS fetcher с SSRF blocklist + sequential mirror failover; 17 unit tests passing.

## Outcome

Phase 8 W1 заложил foundation для Rules Engine vertical slice #1:

- **Vertical slice #1 complete:** RulesEngine package может (а) fetch с HTTPS mirror failover, (б) verify Ed25519 detached signature через swift-crypto. Both primitives — pure functions, fully tested in isolation.
- **swift-crypto 4.5.0 резолвится** через apple/swift-crypto.git, на Apple platforms re-exports CryptoKit без бинарного hit. Transitive dependency swift-asn1 1.7.0 тоже зарезолвен.
- **Package linked в Tuist** для обеих платформ (iOS + macOS app targets).
- **W0 dependency reused:** RulesFetcher вызывает `SubscriptionURLFetcher.isBlockedHost(_:)` напрямую (W0 promoted public) — SSRF blocklist не дублируется.
- **17 unit-тестов, 0 failures** (план требовал ≥9).

## Tasks Completed

| Task    | Name                                                        | Commit    | Files                                                                      |
| ------- | ----------------------------------------------------------- | --------- | -------------------------------------------------------------------------- |
| W1.1    | Scaffold RulesEngine package + register in Tuist            | `b1cbdea` | Package.swift, Project.swift, Resources/.gitkeep, Fixtures/.gitkeep, placeholder RulesEngine.swift (later removed) |
| W1.2    | Implement PublicKey + RulesSigner + RulesEngineLogger       | `58bc77f` | PublicKey.swift, RulesSigner.swift, RulesEngineLogger.swift                |
| W1.3    | Implement RulesFetcher + RulesManifest                      | `714de6c` | RulesFetcher.swift, RulesManifest.swift                                    |
| W1.4    | MockURLProtocol + RulesSignerTests + RulesFetcherTests      | `c8d38d8` | MockURLProtocol.swift, RulesSignerTests.swift, RulesFetcherTests.swift + Package.swift (linkerSettings) |

## Public Surface (interfaces for W2 consumption)

```swift
// RulesSigner.swift
public enum RulesSigner {
    public static func verify(message: Data, signature: Data) -> Bool
}

// RulesFetcher.swift
public enum RulesFetcher {
    public struct FetchResult: Sendable, Equatable {
        public let body: Data; public let etag: String?; public let mirrorURL: URL
    }
    public enum FetchError: Error, LocalizedError, Equatable {
        case nonHTTPS(String); case malformedURL; case blockedHost(String)
        case notHTTPResponse; case httpStatusError(Int); case timeout
        case payloadTooLarge(Int); case allMirrorsFailed([FetchError])
    }
    public static let defaultMaxBytes: Int = 5 * 1024 * 1024
    public static func fetch(url: URL, session: URLSession, maxBytes: Int) async throws -> FetchResult
    public static func fetchWithFailover(urls: [URL], session: URLSession, maxBytes: Int) async throws -> FetchResult
}

// RulesManifest.swift
public struct RulesManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let minAppVersion: String
    public let srsFormatVersion: Int
    public let totalSizeBytes: Int
    public let files: [FileEntry]
    public let blockCompletely: CategoryBodies?
    public let neverThroughVpn: CategoryBodies?
    public let alwaysThroughVpn: CategoryBodies?
    public enum Category: String, Codable, Sendable { case block, never, always }
    public struct FileEntry: Codable, Sendable, Equatable { public let name, sha256, sigPath: String; public let category: Category }
    public struct CategoryBodies: Codable, Sendable, Equatable {
        public let domains: [String]?
        public let ipCidrs: [String]?  // CodingKey "ip_cidrs"
        public let countries: [String]?
    }
}
```

## Test Coverage

`swift test --package-path BBTB/Packages/RulesEngine` → **17 tests passed, 0 failures** (~20 ms wall time).

**RulesSignerTests (6 tests):**
1. `test_verify_acceptsValidSignature` — fresh CryptoKit keypair, known message, signature.count == 64 verified.
2. `test_verify_rejectsTamperedSignature` — single-bit-flip on last byte.
3. `test_verify_rejectsWrongLengthSignature` — 63, 65, 0, 1024 byte signatures all → false без crash.
4. `test_verify_rejectsWrongMessage` — valid sig для message1 → false against message2.
5. `test_verify_rejectsWrongPublicKey` — unrelated keypair pubkey rejects.
6. `test_verify_acceptsValidSignatureOnEmptyMessage` — RFC 8032 allows empty message verify.

**RulesFetcherTests (11 tests):**
- 5 single-URL: nonHTTPS reject, SSRF (127.0.0.1) reject, successful 200 (body + ETag + UA + Accept assertions), HTTP 500 → httpStatusError, 10 MB body > 5 MB cap → payloadTooLarge.
- 4 mirror failover: empty URLs → allMirrorsFailed([]), succeeds on mirror2 (verifies mirror3 NOT tried), all 3 fail → aggregated 3-element error list in order, mixed pre-flight+http failures aggregate correctly.
- 2 RulesManifest decode integration: minimal payload (no CategoryBodies), rich payload (verifies `"ip_cidrs"` CodingKey + optional CategoryBodies).

## Deviations from Plan

### [Rule 3 — Blocking issue] MockURLProtocol moved from `Fixtures/` to test target root

- **Found during:** W1.4
- **Issue:** Plan specified path `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/Fixtures/MockURLProtocol.swift`, но Package.swift declares `resources: [.process("Fixtures")]` — SwiftPM treats `Fixtures/` как resource bundle path, .swift files there are NOT compiled as source. Result: `cannot find 'MockURLProtocol' in scope` errors in RulesFetcherTests.
- **Fix:** Moved file to `Tests/RulesEngineTests/MockURLProtocol.swift` (test target source root). `Fixtures/.gitkeep` preserved для future signed-message fixtures (binary data, не .swift).
- **Files modified:** `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/MockURLProtocol.swift` (relocated).
- **Commit:** `c8d38d8`

### [Rule 3 — Blocking issue] linkerSettings added to testTarget

- **Found during:** W1.4 (first `swift test` run)
- **Issue:** Test target link failed with `_kSCPropNetProxiesSOCKSEnable` (SystemConfiguration), `_res_9_*` (resolv) symbols not found. Cause: ConfigParser dependency transitively pulls in libbox.xcframework (Vendored binary через PoolBuilder → PacketTunnelKit → SingBoxBridge); тест target наследует chain но не linker flags.
- **Fix:** Mirrored ConfigParser/Package.swift `linkerSettings` block on RulesEngineTests testTarget — `.linkedLibrary("resolv")`, `.linkedFramework("SystemConfiguration", .when(platforms: [.macOS]))`, AppKit/UIKit conditionals.
- **Files modified:** `BBTB/Packages/RulesEngine/Package.swift`
- **Commit:** `c8d38d8` (bundled with same patch)

### [Rule 3 — Worktree path safety] Files initially written to main repo instead of worktree

- **Found during:** W1.1 (immediately после first Write tool call)
- **Issue:** Сначала использовал absolute paths под `/Users/vergevsky/ClaudeProjects/VPN/BBTB/...` (main repo location); worktree находится по `/Users/vergevsky/ClaudeProjects/VPN/.claude/worktrees/agent-aec719d24f30abe16/BBTB/...`. Файлы landed в main repo, не в worktree → git commit в worktree не видел их.
- **Fix:** Скопировал RulesEngine package directory из main repo в worktree, удалил из main repo (был untracked), revert'нул случайно-изменённый main repo Project.swift через `git checkout`. С этого момента все Write/Edit использовали полный путь, начинающийся с worktree root.
- **Additional defense:** Symlink `BBTB/Vendored/libbox.xcframework` from main repo into worktree (xcframework gitignored — не клонировался; transitive Libbox dependency требует наличия binary для swift package resolve).
- **Commit:** Files landed correctly starting с `b1cbdea`.

### [Plan acceptance criteria typo — informational only]

- Plan acceptance criterion для W1.1: `grep -c 'product: "Crypto"' Package.swift equals 1`. Канонический SwiftPM синтаксис — `.product(name: "Crypto", package: "swift-crypto")` (использует `name:`, не `product:`). Spirit acceptance — наличие `.product(name: "Crypto", ...)` — выполнен (1 match). Не affecting функциональность.

## Stub Tracking — Known Stubs

Один intentional placeholder, planned for replacement in later wave:

| Stub | File | Line | Reason | Replaced in |
|------|------|------|--------|-------------|
| `publicKeyBytes = [0x00..0x1F]` (sequential placeholder) | `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` | 47–52 | W1 contract — real bytes derived via `openssl pkey -in priv.pem -pubin -outform DER \| tail -c 32 \| xxd -i` после генерации production Ed25519 keypair (admin developer task). Tests inject fresh CryptoKit keypair через internal overload — production placeholder pubkey никогда не используется тестами. | **W6.2** (08-07-PLAN.md) populate real bytes; **W7** (08-08-PLAN.md) add R12 invariant validator rejecting sequential-byte pattern. |

## Threat Flags

W1 не вводит новой security surface не из plan's `<threat_model>`. Все 8 plan-listed STRIDE threats (T-08-W1-01..08) mitigated либо carried-forward to W2/W7:

- T-08-W1-01..02 (HTTPS downgrade, SSRF) — mitigated via RulesFetcher guards + reused W0 helper.
- T-08-W1-03 (forged manifest) — verify primitive correctness asserted via 4+ unit tests.
- T-08-W1-04 (oversized payload DoS) — `payloadTooLarge` case + 5 MB default cap.
- T-08-W1-05 (private key leak) — placeholder pubkey only; private key never enters codebase.
- T-08-W1-06 (swift-crypto API regression) — version-pinned 4.x; tests catch regressions.
- T-08-W1-07 (wrong-length sig crash) — `guard signature.count == 64` covered by `test_verify_rejectsWrongLengthSignature`.
- T-08-W1-08 (mirror failover budget) — sequential 10s timeout per mirror; works within 30s BGAppRefreshTask budget.

## Pending W2 Integration

Public surface fully declared in `<interfaces>` block of 08-02-PLAN.md, ready for downstream consumption:

- **W2 (08-03-PLAN.md):** `RulesEngineCoordinator` actor wraps RulesFetcher + RulesSigner + (new) SRSCacheStore. Two-phase init for ↔ SettingsViewModel cycle.
- **W7 (08-08-PLAN.md):** add validate-r1-r6.sh R12 invariant rejecting placeholder 0x00..0x1F sequence в `publicKeyBytes`.

## Self-Check: PASSED

**Files verified (all 11 created files exist):**

- FOUND: `BBTB/Packages/RulesEngine/Package.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesManifest.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/.gitkeep`
- FOUND: `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/MockURLProtocol.swift`
- FOUND: `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesSignerTests.swift`
- FOUND: `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesFetcherTests.swift`
- FOUND: `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/Fixtures/.gitkeep`

**Commits verified (all 4 task commits exist in worktree-agent-aec719d24f30abe16 branch):**

- FOUND: `b1cbdea` — W1.1 scaffold
- FOUND: `58bc77f` — W1.2 Ed25519 primitive
- FOUND: `714de6c` — W1.3 fetcher + manifest
- FOUND: `c8d38d8` — W1.4 tests

**Build & test verified:**

- `swift build --package-path BBTB/Packages/RulesEngine` → `Build complete!` exit 0
- `swift test --package-path BBTB/Packages/RulesEngine` → `Executed 17 tests, with 0 failures (0 unexpected) in 0.022s`
