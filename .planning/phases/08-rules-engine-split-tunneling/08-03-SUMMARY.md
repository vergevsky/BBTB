---
phase: 08-rules-engine-split-tunneling
plan: W2
subsystem: rules-engine
tags: [rules-engine, app-group, atomic-write, baseline-bootstrap, coordinator-actor, cooldown, notification-center, perf-signposter]
dependency_graph:
  requires:
    - phase: 08
      plan: W1
      provides: "RulesFetcher.fetchWithFailover + RulesSigner.verify + RulesManifest Codable schema (incl. CategoryBodies)"
    - phase: 08
      plan: W0
      provides: "Tuist clean state без AppProxy зомби-таргета"
  provides:
    - "AppGroupContainer.rulesCacheDirectory — App Group SRS subdirectory (writer = main app, reader = NE libbox fswatch)"
    - "SRSCacheStore public actor — atomic write/read/mtime/exists через Data.write(.atomic)"
    - "BaselineRulesLoader public enum — Bundle.module pattern loadManifest + loadSRS(category:) для first-launch baseline hydration"
    - "RulesSnapshot + CategoryEntries — public Sendable Equatable value-types для UI consumption (RULES-09 foundation)"
    - "RulesEngineCoordinator public actor — end-to-end pipeline bootstrap/performBackgroundRefresh/forceUpdate/currentSnapshot"
    - "Notification.Name.bbtbRulesEngineDidUpdate — contract для downstream W3 SettingsViewModel observer"
    - "ForceUpdateOutcome public enum — UI-facing toast mapping (6 cases)"
    - "RulesFetcherProtocol + DefaultRulesFetcher + SignatureVerifierProtocol + DefaultRulesSigner + ClockProtocol + SystemClock — DI surface"
    - "Resources baseline placeholders (manifest.json + 3 srs + 4 sig) — replaced by real signed content в W6"
  affects:
    - "08-04-PLAN.md (W3 — SettingsViewModel observes .bbtbRulesEngineDidUpdate)"
    - "08-05-PLAN.md (W4 — BGAppRefreshTask + NSBackgroundActivityScheduler call performBackgroundRefresh)"
    - "08-06-PLAN.md (W5 — sing-box route.rule_set.path = AppGroupContainer.rulesCacheDirectory/...)"
    - "08-07-PLAN.md (W6 — build-baseline-rules.sh заменит Resources placeholders на real signed)"
    - "08-08-PLAN.md (W7 — validate-r1-r6.sh R12 invariant reject .sig = 64 zero bytes в production builds)"
tech_stack:
  added: []  # все deps уже добавлены в W1; W2 reuses PacketTunnelKit local dep
  patterns:
    - "Actor coordinator (Phase 6c TunnelController)"
    - "Two-phase init / late-binding setter (см. feedback_failover_two_phase_init.md — W2 не использует, но shape coordinator готов для W3 SettingsViewModel observer)"
    - "Data.write(.atomic) POSIX rename(2) для App Group concurrent reader (NE) safety"
    - "Subsystem-scoped local PerfSignposter (mirror AppFeatures pattern для leaf packages)"
    - "Protocol-driven DI с production default + test fakes (RulesFetcherProtocol, SignatureVerifierProtocol, ClockProtocol)"
    - "10-step transactional pipeline с failure-reason classification → discriminated outcome mapping"
    - "Re-entry guard (`isInFlight` Bool) — concurrent refresh DoS protection"
    - "Last-write-fences-transaction ordering: .srs files first, manifest+sig last (defense-in-depth для atomic-write race)"
key_files:
  created:
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/BaselineRulesLoader.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSnapshot.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Clock.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/README.md"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/baseline-rules-manifest.json"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/baseline-rules-manifest.json.sig"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-block.srs"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-block.srs.sig"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-never.srs"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-never.srs.sig"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-always.srs"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-always.srs.sig"
    - "BBTB/Packages/RulesEngine/Tests/RulesEngineTests/SRSCacheStoreTests.swift"
    - "BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesManifestTests.swift"
    - "BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift"
  modified:
    - "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift (added rulesCacheDirectory)"
    - "BBTB/Packages/RulesEngine/Package.swift (added PacketTunnelKit local dep)"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift (added RulesFetcherProtocol + DefaultRulesFetcher)"
    - "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift (added SignatureVerifierProtocol + DefaultRulesSigner)"
decisions:
  - "DEC-08-W2-01: добавили SignatureVerifierProtocol DI поверх плана (Rule 3 auto-fix) — success-path тесты требовали бы admin's private key, что нарушает security model. Production path unchanged (DefaultRulesSigner делегирует к RulesSigner.verify)."
  - "DEC-08-W2-02: locally-scoped PerfSignposter в RulesEngine.swift вместо dep на AppFeatures — RulesEngine — leaf package (AppFeatures consumes RulesEngine в W3). Subsystem/category совпадают с AppFeatures.PerfSignposter.client → Instruments unified view."
  - "DEC-08-W2-03: bootstrap recovers cachedManifest из disk если файлы существуют (idempotent guard) — иначе после app restart currentSnapshot() возвращает nil до первого refresh. Phase 8 W3 UI viewer пострадал бы visible пустотой."
  - "DEC-08-W2-04: lastForceUpdateAt set BEFORE pipeline (даже failed attempts count toward cooldown) — иначе attacker мог бы spam force-update через network failures обход cooldown."
  - "DEC-08-W2-05: pipeline write order — .srs files first, manifest + sig LAST. Defense-in-depth: если interrupt между mid-pipeline, reader видит новые .srs против старого manifest → libbox-side sha256 mismatch detection. Manifest update fences transaction."
metrics:
  duration_minutes: 22
  tasks: 3
  files_created: 17
  files_modified: 4
  tests_added: 24  # 6 SRSCacheStore + 7 RulesManifest + 11 Coordinator
  tests_passing: 41  # 17 W1 + 24 W2
  completed: 2026-05-15
---

# Phase 8 Plan W2: RulesEngineCoordinator Pipeline Summary

**One-liner:** End-to-end Rules Engine pipeline implemented as actor — bootstrap (Bundle → App Group), performBackgroundRefresh (fetch+verify+atomic-write+notify), forceUpdate (60s cooldown), currentSnapshot (CategoryBodies materialization для RULES-09); 24 новых unit-тестов pass, 41 total в RulesEngine package.

## Outcome

Phase 8 W2 — vertical slice #2: связали W1 primitives (HTTPS fetch + Ed25519 verify) с persistent storage (App Group atomic write) и event surface (NotificationCenter).

После W2 пайплайн test-verified end-to-end в test harness без реальной сети:

- **Bootstrap path** — baseline files копируются из `Bundle.module` в `AppGroupContainer.rulesCacheDirectory` на first-launch (idempotent). `cachedManifest` materialized в actor state; `currentSnapshot()` сразу возвращает non-nil snapshot с baseline rules (`block.domains = ["max.ru", "mssgr.tatar.ru"]`).
- **Refresh path** — 10-step transactional pipeline с failure classification: tampered sig / network failure / version <= cached / oversized payload — каждый возвращает `false` и **сохраняет cache untouched** (verified mtime stability в тестах).
- **Force-update path** — 60s cooldown enforced; failed attempts count toward cooldown (prevent DoS through network spam); discriminated `ForceUpdateOutcome` mapping (6 cases).
- **Snapshot materialization** — `RulesSnapshot` собран из `RulesManifest.blockCompletely/.neverThroughVpn/.alwaysThroughVpn` (W1.3 CategoryBodies extended schema). **Это закрывает RULES-09 viewer dependency** — без materialization SettingsViewModel был бы permanently empty.

### Что ещё нет после W2 (deliberately)

- **UI** — нет (W3).
- **BGAppRefreshTask / NSBackgroundActivityScheduler** — нет (W4).
- **sing-box чтение SRS** — нет (W5 пропатчит `expandConfigForTunnel`).
- **Реальные signed baseline files** — нет (W6 build-script сгенерирует).
- **Real production mirrors** — placeholders (W7).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| W2.1 | SRSCacheStore + AppGroupContainer.rulesCacheDirectory | `f9887eb` | AppGroupContainer.swift, Package.swift, SRSCacheStore.swift, SRSCacheStoreTests.swift |
| W2.2 | RulesSnapshot + BaselineRulesLoader + baseline placeholders | `0b122df` | RulesSnapshot.swift, BaselineRulesLoader.swift, Resources/(8 files), README.md, RulesManifestTests.swift |
| W2.3 | RulesEngineCoordinator actor — full pipeline | `b942aad` | RulesFetcher.swift, RulesSigner.swift, Clock.swift, RulesEngineCoordinator.swift, RulesEngineCoordinatorTests.swift |

## Public Surface (interfaces for W3-W6 consumption)

```swift
// AppGroupContainer.swift (PacketTunnelKit) — added
public static var rulesCacheDirectory: URL { /* Library/Caches/rules/ */ }

// SRSCacheStore.swift
public actor SRSCacheStore {
    public nonisolated let directory: URL
    public init(directory: URL = AppGroupContainer.rulesCacheDirectory)
    public func write(_ data: Data, filename: String) throws
    public func read(filename: String) -> Data?
    public func mtime(filename: String) -> Date?
    public func exists(filename: String) -> Bool
}

// BaselineRulesLoader.swift
public enum BaselineRulesLoader {
    public enum LoadError: Error, LocalizedError { case resourceMissing(String) }
    public static func loadManifest() throws -> (manifest: Data, signature: Data)
    public static func loadSRS(category: RulesManifest.Category) throws -> (srs: Data, signature: Data)
}

// RulesSnapshot.swift
public struct RulesSnapshot: Sendable, Equatable {
    public let version: Int
    public let lastFetchedAt: Date?
    public let block, never, always: CategoryEntries
    public let minAppVersion: String
}
public struct CategoryEntries: Sendable, Equatable {
    public let domains: [String]
    public let ipCidrs: [String]
    public let countries: [String]
}

// Clock.swift
public protocol ClockProtocol: Sendable { func now() -> Date }
public struct SystemClock: ClockProtocol { /* Date() */ }

// RulesFetcher.swift (extended)
public protocol RulesFetcherProtocol: Sendable {
    func fetchWithFailover(urls: [URL], maxBytes: Int) async throws -> RulesFetcher.FetchResult
}
public struct DefaultRulesFetcher: RulesFetcherProtocol { /* delegation */ }

// RulesSigner.swift (extended)
public protocol SignatureVerifierProtocol: Sendable {
    func verify(message: Data, signature: Data) -> Bool
}
public struct DefaultRulesSigner: SignatureVerifierProtocol { /* delegation */ }

// RulesEngineCoordinator.swift
public actor RulesEngineCoordinator {
    public static let productionMirrors: [URL]  // placeholder, replaced in W7
    public init(
        fetcher: RulesFetcherProtocol = DefaultRulesFetcher(),
        cache: SRSCacheStore = SRSCacheStore(),
        clock: ClockProtocol = SystemClock(),
        mirrorURLs: [URL] = RulesEngineCoordinator.productionMirrors,
        signer: SignatureVerifierProtocol = DefaultRulesSigner()
    )
    public func bootstrap() async
    public func performBackgroundRefresh() async -> Bool
    public func forceUpdate() async -> ForceUpdateOutcome
    public func currentSnapshot() -> RulesSnapshot?
}
public enum ForceUpdateOutcome: Equatable, Sendable {
    case success(version: Int)
    case alreadyLatest(version: Int)
    case networkFailure
    case signatureFailure
    case payloadTooLarge
    case cooldownActive(secondsRemaining: Int)
}
extension Notification.Name {
    public static let bbtbRulesEngineDidUpdate
        = Notification.Name("app.bbtb.client.rulesEngineDidUpdate")
}
```

## Pipeline diagram

```
┌────────────────────────────────────────────────────────────────────┐
│ RulesEngineCoordinator (actor)                                     │
│                                                                    │
│  bootstrap()                  ─── first launch / cold start        │
│    └─→ BaselineRulesLoader → SRSCacheStore.write × 8 files         │
│                                                                    │
│  performBackgroundRefresh()   ─── BGAppRefreshTask / force-update  │
│    └─→ RulesFetcher (manifest) → SignatureVerifier.verify          │
│      └─→ Decode → version > cached? → total_size <= 5MB?           │
│        └─→ RulesFetcher × 3 (.srs) → SignatureVerifier × 3         │
│          └─→ SRSCacheStore.write × 8 (atomic, manifest LAST)       │
│            └─→ NotificationCenter.post .bbtbRulesEngineDidUpdate   │
│                                                                    │
│  forceUpdate()                ─── RULES-10 button                  │
│    └─→ 60s cooldown check (D-10)                                   │
│      └─→ performBackgroundRefresh → mapped ForceUpdateOutcome      │
│                                                                    │
│  currentSnapshot()            ─── RULES-09 viewer foundation       │
│    └─→ Materialize RulesSnapshot из cachedManifest CategoryBodies  │
└────────────────────────────────────────────────────────────────────┘
```

## Test Coverage

`swift test --package-path BBTB/Packages/RulesEngine` → **41 tests passed, 0 failures** (~260 ms wall time).

**SRSCacheStoreTests (6 tests):**
1. write → read round-trip (100 bytes identity)
2. overwrite replaces existing file content + size
3. mtime returns recent date после write (< 5s slack от now)
4. read missing file → nil (no throws)
5. exists toggles false → true after write
6. mtime returns nil для missing file

**RulesManifestTests (7 tests):**
1. baseline manifest decodes без throws (snake_case ↔ camelCase mapping integrity)
2. baseline version == 0
3. baseline files count == 3
4. files cover все три Category enum cases (.block / .never / .always)
5. BaselineRulesLoader loads все 4 resource types (manifest+sig + 3 srs+sig)
6. baseline.block_completely.domains == ["max.ru", "mssgr.tatar.ru"] (sync с wiki/max-messenger.md)
7. RulesSnapshot + CategoryEntries Equatable smoke

**RulesEngineCoordinatorTests (11 tests):**
1. bootstrap copies baseline when cache empty + snapshot != nil after
2. bootstrap idempotent (mtime unchanged на second call)
3. performBackgroundRefresh success writes all 8 files + snapshot.version updated
4. tampered signature → returns false + cache mtime unchanged
5. network failure → returns false + cache mtime unchanged
6. server version <= cached → returns false (replay protection)
7. forceUpdate в 30s окне → .cooldownActive(secondsRemaining: ~30)
8. forceUpdate после +61s → .success(5); same-version repeat → .alreadyLatest(5)
9. NotificationCenter .bbtbRulesEngineDidUpdate posted с non-nil object
10. payloadTooLarge — 10MB manifest → false + .payloadTooLarge outcome
11. **CRITICAL: currentSnapshot materializes CategoryEntries из manifest CategoryBodies** (block.domains == ["max.ru", "mssgr.tatar.ru"], never/always empty arrays) — acceptance test для RULES-09

## Deviations from Plan

### [Rule 3 — Blocking issue] Added SignatureVerifierProtocol DI

- **Found during:** Task W2.3 (writing RulesEngineCoordinatorTests)
- **Issue:** Production `RulesSigner.verify(message:signature:)` использует `PublicKey.publicKey` (W1 placeholder bytes 0x00..0x1F). Никто не имеет corresponding private key → success-path coordinator тесты не могут produce valid signature. Без этого `test_performBackgroundRefresh_success_writesAllFiles` и `test_forceUpdate_afterCooldown_returnsSuccess` impossible.
- **Fix:** Добавил `SignatureVerifierProtocol` + `DefaultRulesSigner` в `RulesSigner.swift`. Coordinator принимает `signer: SignatureVerifierProtocol = DefaultRulesSigner()`. Tests инжектят `AlwaysValidVerifier` / `AlwaysInvalidVerifier` (private structs в test file). Production path — `DefaultRulesSigner` делегирует к `RulesSigner.verify` без изменений; никакого binary cost.
- **Files modified:** `RulesSigner.swift` (+24 lines protocol/struct), `RulesEngineCoordinator.swift` (`+signer` параметр в init).
- **Commit:** `b942aad`
- **Alternative considered:** mutate `PublicKey.publicKeyBytes` в test fixture — отвергнут, поскольку (а) static let immutable, (б) реальная замена через W6 build-script — это правильное архитектурное решение, тесты не должны coupling-ить к нему.

### [Rule 3 — Pattern compliance] Local PerfSignposter в RulesEngineCoordinator

- **Found during:** Task W2.3 (acceptance criterion `grep -c PerfSignposter >= 1` + DEC-06d-06 pattern)
- **Issue:** Плановое требование — span "RulesRefresh" в coordinator. AppFeatures имеет `PerfSignposter` enum, но RulesEngine — leaf package (AppFeatures **consumes** RulesEngine в W3). Зависимость "вверх" сломала бы acyclic dependency graph.
- **Fix:** Local `enum PerfSignposter` (internal) в `RulesEngineCoordinator.swift` mirror'ит AppFeatures pattern (subsystem `app.bbtb.client`, category `performance`). Instruments → Points of Interest показывает unified view (subsystem/category identical → spans от обоих пакетов в одной timeline).
- **Files modified:** `RulesEngineCoordinator.swift` (+8 lines local enum).
- **Commit:** `b942aad`
- **Note:** Если когда-нибудь Phase 9+ extract PerfSignposter в отдельный leaf utility package, leaf-level local enum можно заменить на shared дом.

### [Rule 3 — Operational] Symlink libbox.xcframework в worktree

- **Found during:** baseline test run перед W2.1 start
- **Issue:** Worktree spawning не клонирует `BBTB/Vendored/` (gitignored). `swift test --package-path BBTB/Packages/RulesEngine` падает на linker step через transitive ConfigParser → PoolBuilder → PacketTunnelKit → Libbox dep.
- **Fix:** `ln -s /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework BBTB/Vendored/libbox.xcframework`. Symlink не tracked (директория gitignored), main repo untouched.
- **Files modified:** Только worktree FS, ничего в git.
- **Impact on plan:** Никакого. Worktree-specific environment quirk; downstream waves в main репо имеют полный libbox.

### Все остальные acceptance criteria — выполнены точно по плану

Финальный grep audit ([после commit b942aad](#)):
- `rulesCacheDirectory` в AppGroupContainer.swift → 1 ✓
- `public actor SRSCacheStore` → 1 ✓
- `Data.write|data.write` в SRSCacheStore.swift → 4 ✓
- `.atomic` → 4 ✓
- PacketTunnelKit в RulesEngine/Package.swift → 4 (deps + target deps + comment) ✓
- baseline-rules-manifest.json existence → ✓
- manifest.sig file size = 64 ✓
- 3 .srs files + 3 .srs.sig files ✓
- public struct RulesSnapshot / CategoryEntries / public enum BaselineRulesLoader → 1 каждый ✓
- Bundle.module ≥ 1 → 6 (3 в loadManifest + 3 в loadSRS) ✓
- public actor RulesEngineCoordinator → 1 ✓
- 4 public methods → 4 ✓
- bbtbRulesEngineDidUpdate ≥ 2 → 4 ✓
- public enum ForceUpdateOutcome → 1 ✓
- RulesFetcherProtocol + DefaultRulesFetcher → 2 ✓
- cooldownActive/signatureFailure/networkFailure/payloadTooLarge ≥ 4 → 12 (в enum cases + state logic + tests) ✓
- test_(bootstrap|performBackgroundRefresh|forceUpdate|notification|payloadTooLarge) ≥ 8 → 10 ✓
- PerfSignposter ≥ 1 → 9 (enum + 2 method calls + comments) ✓
- blockCompletely/neverThroughVpn/alwaysThroughVpn ≥ 3 → 3 ✓
- test_currentSnapshot ≥ 1 → 1 ✓

## Threat Coverage

Все 8 plan-listed STRIDE threats (T-08-W2-01..08) mitigated:

| Threat ID | Disposition | Implementation |
|-----------|-------------|----------------|
| T-08-W2-01 | mitigate | Coordinator gates write только после `signer.verify(message: manifestData, signature: manifestSig)` returns true; затем per-srs verify тот же gate. Tampered sig test verified. |
| T-08-W2-02 | mitigate | Step 5: `guard newManifest.version > cachedVersion` — gate before write. Test `test_performBackgroundRefresh_versionNotNewer_returnsFalse` verified. |
| T-08-W2-03 | mitigate | `Data.write(.atomic)` = POSIX rename(2); тест `test_write_overwritesExistingFile` indirectly verifies atomicity via overwrite semantics. NE reader inheritance — `[ASSUMED]` for W5 UAT. |
| T-08-W2-04 | mitigate | `lastForceUpdateAt` set BEFORE pipeline (даже failed attempts count); `isInFlight` re-entry guard rejects concurrent. Tests 7-8 cover. |
| T-08-W2-05 | mitigate | Two-tier defense: RulesFetcher.maxBytes per-call cap (5MB W1) + Coordinator.maxBytesPerFile + manifest.totalSizeBytes gate. Test 10 covers. |
| T-08-W2-06 | mitigate | Step 4: `guard newManifest.srsFormatVersion <= maxSrsFormatVersion (4)` — silent reject incompatible. Logs explicit version mismatch для debug. |
| T-08-W2-07 | mitigate | `RulesEngineLogger.coordinator` logs each step (notice/warning/error); PerfSignposter span "RulesRefresh" tracks duration в Instruments. |
| T-08-W2-08 | accept | Resources/README.md explicit «PLACEHOLDER — replaced в W6»; W7 R12 invariant добавит compile-time gate. |

### Threat Flags (new surface not in plan threat model)

None. W2 не вводит новых auth paths / network endpoints / file access patterns за пределами `<threat_model>`.

## Pending W3+ Integration

Public surface fully declared, ready для downstream consumption:

- **W3 (08-04-PLAN.md):** SettingsViewModel observes `.bbtbRulesEngineDidUpdate` (queue: nil + Task @MainActor hop per Phase 6 pattern). SettingsViewModel.rulesSnapshot = `await coord.currentSnapshot()`. RULES-09/10 UI built на этой основе.
- **W4 (08-05-PLAN.md):** BGAppRefreshTask handler iOS + NSBackgroundActivityScheduler macOS — оба вызывают `await coord.performBackgroundRefresh()`. Foreground sanity fetch (Pitfall 2 mitigation) в `BBTB_iOSApp.scenePhase` observer.
- **W5 (08-06-PLAN.md):** SingBoxConfigLoader.expandConfigForTunnel injects 3 `route.rule_set` entries с paths = `AppGroupContainer.rulesCacheDirectory.appendingPathComponent("bbtb-baseline-{block,never,always}.srs")`. fswatch auto-reload в extension.
- **W6 (08-07-PLAN.md):** scripts/build-baseline-rules.sh + Tuist pre-build phase — заменяет 8 placeholder Resources на real signed content.
- **W7 (08-08-PLAN.md):** validate-r1-r6.sh extension — R12 reject .sig files = 64 zero bytes (placeholder detection); R8 reject PublicKey.publicKeyBytes = 0x00..0x1F sequential pattern.

## Known Stubs

Baseline placeholders в Resources/ — intentional, contract documented в Resources/README.md:

| Stub | File | Reason | Replaced in |
|------|------|--------|-------------|
| `baseline-rules-manifest.json.sig` = 64 zero bytes | `Resources/baseline-rules-manifest.json.sig` | Real Ed25519 detached signature после W6 build-script (admin's private key required) | **W6** (08-07-PLAN.md) |
| `bbtb-baseline-{block,never,always}.srs` = 4 byte magic header `0x53 0x52 0x53 0x04` | 3 files в `Resources/` | Real compiled sing-box rule-sets v4 после W6 build-script (sing-box CLI required) | **W6** |
| `bbtb-baseline-{block,never,always}.srs.sig` = 64 zero bytes | 3 files в `Resources/` | Real Ed25519 detached signatures после W6 | **W6** |
| `RulesEngineCoordinator.productionMirrors` = `rules.bbtb.example` placeholders | `RulesEngineCoordinator.swift` | Real VPS mirror URLs determined в W7 | **W7** (08-08-PLAN.md) |
| `PublicKey.publicKeyBytes` = 0x00..0x1F sequential | `PublicKey.swift` (carried-forward from W1) | Real Ed25519 public key bytes derived от admin's private key | **W6/W7** |

**No stubs prevent W2 goal** — все pipeline paths test-verified без зависимости от real signed content (SignatureVerifierProtocol DI).

## Self-Check: PASSED

**Files verified (all 17 created files exist):**

- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/BaselineRulesLoader.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSnapshot.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Clock.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/README.md`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/baseline-rules-manifest.json`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/baseline-rules-manifest.json.sig`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-block.srs`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-block.srs.sig`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-never.srs`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-never.srs.sig`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-always.srs`
- FOUND: `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/bbtb-baseline-always.srs.sig`
- FOUND: `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/SRSCacheStoreTests.swift`
- FOUND: `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesManifestTests.swift`
- FOUND: `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift`

**Commits verified (all 3 task commits exist in worktree-agent-a18d8aced6d543aa5 branch):**

- FOUND: `f9887eb` — W2.1 SRSCacheStore + AppGroupContainer.rulesCacheDirectory
- FOUND: `0b122df` — W2.2 RulesSnapshot + BaselineRulesLoader + baseline placeholders
- FOUND: `b942aad` — W2.3 RulesEngineCoordinator actor

**Build & test verified:**

- `swift build --package-path BBTB/Packages/RulesEngine` → Build complete (2.21s) ✓
- `swift test --package-path BBTB/Packages/RulesEngine` → **41 tests passed, 0 failures** in 0.243s ✓
  - RulesSignerTests: 6/6 (W1)
  - RulesFetcherTests: 11/11 (W1)
  - SRSCacheStoreTests: 6/6 (W2.1)
  - RulesManifestTests: 7/7 (W2.2)
  - RulesEngineCoordinatorTests: 11/11 (W2.3)

Phase 8 Plan W2 — COMPLETE.
