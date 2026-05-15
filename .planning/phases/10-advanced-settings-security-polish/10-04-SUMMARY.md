---
phase: 10
plan: "04"
subsystem: cert-pinning
tags: [cert-pinning, spki, subscription, ed25519, tdd, dpi-08]
dependency_graph:
  requires: [10-01, 08-rules-engine]
  provides: [PinnedSessionDelegate, PinStore, PinManifest, SubscriptionPinManager, PinnedSubscriptionURLFetcher]
  affects: [SubscriptionURLFetcher, AppGroupContainer, ConfigParser-Package]
tech_stack:
  added: [swift-crypto 4.5.0]
  patterns: [SPKI-SHA256-pinning, actor-pattern-mirror-RulesEngineCoordinator, TDD-RED-GREEN]
key_files:
  created:
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/PinManifest.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/PinnedSessionDelegate.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/Resources/subscription-pins-bootstrap.json
    - scripts/generate-spki-pin.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PinnedSessionDelegateTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionPinManagerTests.swift
  modified:
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift
    - BBTB/Packages/ConfigParser/Package.swift
decisions:
  - "SubscriptionPinManager.cacheDir has no default parameter (AppGroupContainer is in PacketTunnelKit, not ConfigParser — would create circular dep); caller provides explicitly"
  - "makeSession(pinningEnabled:false) returns ephemeral session with delegate==nil (not URLSession.shared) to allow invalidateAndCancel() on test sessions"
  - "Ed25519 public key bytes duplicated from RulesEngine/PublicKey.swift with explicit doc-comment to sync on rotation"
  - "SubscriptionPinManager.performBackgroundRefresh re-entry guard returns silently (not throws) to match RulesEngineCoordinator pattern"
metrics:
  duration: "~9 minutes"
  completed: "2026-05-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 8
  files_modified: 3
---

# Phase 10 Plan 04: DPI-08 Certificate Pinning for Subscription URL Summary

**One-liner:** SPKI SHA-256 cert pinning via Apple SecKeyCopyExternalRepresentation pipeline + Ed25519-signed remote manifest + validUntil hard reject, protecting Marzban subscription endpoint from MITM (T-10-W4-01).

## Tasks Completed

| Task | Description | Commits | Result |
|------|-------------|---------|--------|
| 1 (RED) | Failing tests for PinStore, PinManifest, PinnedSessionDelegate | ff391f4 | 5 tests RED |
| 1 (GREEN) | PinStore + PinManifest + PinnedSessionDelegate + AppGroupContainer + Package.swift | 2a5cb41 | 5 tests PASS |
| 2 (RED) | Failing tests for SubscriptionPinManager + PinnedSubscriptionURLFetcher + makeSession | f9caf9d | 7 tests RED |
| 2 (GREEN) | SubscriptionPinManager + bootstrap JSON + generate-spki-pin.swift + SubscriptionURLFetcher | 9ca6461 | 7 tests PASS |

## Implementation Details

### Task 1: PinStore + PinManifest + PinnedSessionDelegate

**PinManifest.swift:** Codable struct with snake_case CodingKeys:
- `valid_from` → `validFrom`, `valid_until` → `validUntil`, `spki_sha256_pins` → `spkiSha256Pins`, `backup_pins` → `backupPins`

**PinStore.swift:**
- `BootstrapPins.vpnVergevskyRu`: 2 placeholder entries (0x00 × 32 primary, 0x01 × 32 backup). **Phase 12 prerequisite** to replace with real SPKI hashes via `generate-spki-pin.swift`.
- `PinStore.isValid(spkiHash:for:)`: O(1) Set lookup of SHA-256 Data per host.
- Merges bootstrap (UInt8 arrays) + manifest (hex strings) with dedup.

**PinnedSessionDelegate.swift** (NSObject + URLSessionDelegate):
- `SecTrustEvaluateWithError` pre-check (T-10-W4-02 mitigation — blocks expired/wrong-hostname before pin matching).
- `SecTrustCopyCertificateChain` → `SecCertificateCopyKey` → `SecKeyCopyExternalRepresentation` → `SHA256.hash`.
- Chain walks all certs: first match → `.useCredential`; no match → `.cancelAuthenticationChallenge`.

**AppGroupContainer.certPinManifestDirectory:** Added `Library/Caches/pins/` (idempotent createDirectory, mirror of `rulesCacheDirectory` pattern).

**Package.swift:** swift-crypto 4.5.0 resolved + `Crypto` product dependency + `.process("Resources")`.

### Task 2: SubscriptionPinManager + PinnedSubscriptionURLFetcher

**SubscriptionPinManager (actor):**
- Mirrors `RulesEngineCoordinator` pattern exactly (same re-entry guard, same bootstrap idempotency, same atomic write).
- `bootstrap()`: bundle resource → App Group cache (no overwrite if exists).
- `performBackgroundRefresh()`: sequential mirror fetch → 64-byte Ed25519 verify → validUntil hard reject → atomic write `.json` + `.json.sig`.
- `currentPins(for:)`: union of bootstrap hardcoded pins + cached manifest pins.
- `currentPinStore()`: builds `PinStore` from merged pins.
- Ed25519 public key: mirror of `RulesEngine/PublicKey.swift` (same 32 bytes with explicit doc-comment to update both on rotation).

**PinnedSubscriptionURLFetcher:** `SubscriptionURLFetching` conforming struct; creates ephemeral URLSession + `PinnedSessionDelegate` per fetch; `defer { session.invalidateAndCancel() }`.

**SubscriptionURLFetcher.makeSession(pinningEnabled:pinStore:):** Thin static factory for DPI-08 toggle:
- `pinningEnabled=true` → ephemeral session + `PinnedSessionDelegate` as delegate.
- `pinningEnabled=false` → ephemeral session with `delegate==nil` (default OS trust).
- Enables `test_noPinningWhenDisabled` (Test 8) to assert `session.delegate == nil`.

**subscription-pins-bootstrap.json:** Placeholder manifest (version=0, host=vpn.vergevsky.ru, placeholder hex zeros for primary + ones for backup). Valid until 2027-05-15.

**scripts/generate-spki-pin.swift:** CLI using `NWConnection` TLS + `sec_protocol_metadata_access_peer_certificate_chain` → `SecCertificateCopyKey` → `SecKeyCopyExternalRepresentation` → `SHA256`. Outputs depth-labeled hex hashes. Run before Phase 12 to replace `BootstrapPins` placeholder bytes.

### Test Coverage

| Test File | Tests | Result |
|-----------|-------|--------|
| PinnedSessionDelegateTests.swift | 5 | 5 PASS |
| SubscriptionPinManagerTests.swift | 7 | 7 PASS |
| Full ConfigParser suite | 240 | 240 PASS |

New tests added: **12 total** (5 Task 1 + 7 Task 2, exceeding requirement of ≥ 11).

Test 8 (`test_noPinningWhenDisabled`) covers DPI-08 toggle OFF path as required by the 2026-05-15 revision per checker task_completeness warning.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict concurrency: waitForExpectations in async context**
- **Found during:** Task 1 GREEN phase (swift test run)
- **Issue:** `waitForExpectations(timeout:)` is `@MainActor` in Swift 6. Calling from non-isolated `func test_...()` → `#SendingRisksDataRace` error.
- **Fix:** Changed test method to `async` + replaced `waitForExpectations` + `XCTestExpectation` with `await withCheckedContinuation { }` bridge.
- **Files modified:** PinnedSessionDelegateTests.swift (Test 3)
- **Commit:** 2a5cb41

**2. [Rule 1 - Bug] AppGroupContainer not in ConfigParser scope**
- **Found during:** Task 2 GREEN phase (swift build)
- **Issue:** `SubscriptionPinManager.init` had `cacheDir: URL = AppGroupContainer.certPinManifestDirectory` as default parameter. `AppGroupContainer` lives in `PacketTunnelKit` which is only a test dependency of ConfigParser (PATTERNS §3.6). Using it in production source would create a circular dependency.
- **Fix:** Removed default value from `cacheDir` parameter — caller must always provide explicitly. Tests use temp directories; production callers (`BBTB_iOSApp.swift` eventually) will pass `AppGroupContainer.certPinManifestDirectory` from their PacketTunnelKit import context.
- **Files modified:** SubscriptionPinManager.swift
- **Commit:** 9ca6461

**3. [Rule 1 - Bug] Resources directory location**
- **Found during:** Task 1 GREEN build (Package.swift `.process("Resources")` expects `Sources/ConfigParser/Resources`)
- **Issue:** Created `Packages/ConfigParser/Resources/` (top-level) instead of `Sources/ConfigParser/Resources/` (required by SPM `.process("Resources")` target resources).
- **Fix:** Created correct `Sources/ConfigParser/Resources/` directory; removed erroneous top-level directory.
- **Files modified:** N/A (directory structure only)
- **Commit:** 2a5cb41

## Known Stubs

**BootstrapPins placeholder bytes** (intentional, documented, tracked):
- File: `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift`, lines ~30-38
- `BootstrapPins.vpnVergevskyRu[0]` = `[UInt8](repeating: 0x00, count: 32)` (placeholder primary)
- `BootstrapPins.vpnVergevskyRu[1]` = `[UInt8](repeating: 0x01, count: 32)` (placeholder backup)
- Reason: PHASE 12 PREREQUISITE — replace via `scripts/generate-spki-pin.swift --host vpn.vergevsky.ru` before TestFlight.
- **These stubs will reject all real TLS connections** (no production cert has SHA-256(SPKI) = all-zeros). This is the correct behavior for Phase 10: the pinning infrastructure is wired but not yet armed with real hashes.

## Threat Model Compliance

All threats from plan's `<threat_model>` are mitigated as implemented:

| Threat | Status |
|--------|--------|
| T-10-W4-01 (MITM cert) | MITIGATED — PinnedSessionDelegate cancels on no pin match |
| T-10-W4-02 (trust bypass) | MITIGATED — SecTrustEvaluateWithError pre-check (step 3 in delegate) |
| T-10-W4-04 (manifest tampering) | MITIGATED — Ed25519 verify + validUntil hard reject in performBackgroundRefresh |
| T-10-W4-06 (SPKI format mismatch) | MITIGATED — generate-spki-pin.swift uses same Apple pipeline as delegate (A4 verified) |
| T-10-W4-08 (mirror failure) | MITIGATED — bootstrap pins always included in currentPins() (graceful degradation) |
| T-10-W4-09 (delegate retention) | MITIGATED — verified by test_PinnedSubscriptionURLFetcher_uses_delegate_when_provided |

## TDD Gate Compliance

- RED gate commit: `ff391f4` (`test(10-04): add failing tests for PinStore...`) — all types missing
- GREEN gate commit: `2a5cb41` (`feat(10-04): Task 1 — PinStore + PinManifest...`) — 5 tests passing
- RED gate commit: `f9caf9d` (`test(10-04): add failing tests for SubscriptionPinManager...`)
- GREEN gate commit: `9ca6461` (`feat(10-04): Task 2 — SubscriptionPinManager...`) — 7 tests passing

## Open Follow-ups

1. **Phase 12 prerequisite:** Replace `BootstrapPins.vpnVergevskyRu` placeholder bytes with real SPKI SHA-256 hashes from `vpn.vergevsky.ru` production certificate chain. Command: `swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru`. Copy leaf hash → `[0]`, intermediate/backup → `[1]`.

2. **Wire SubscriptionPinManager into app:** `BBTB_iOSApp.swift` needs to create `SubscriptionPinManager(cacheDir: AppGroupContainer.certPinManifestDirectory, ...)` and call `bootstrap()` on launch + `performBackgroundRefresh()` in background task (similar to `RulesEngineCoordinator`). This is a Phase 12 integration step.

3. **Wire PinnedSubscriptionURLFetcher in ServerListViewModel:** When `certPinningEnabled == true`, inject `PinnedSubscriptionURLFetcher(pinStore: await pinManager.currentPinStore())` instead of `DefaultSubscriptionURLFetcher`. Phase 12 integration.

## Threat Flags

No new network endpoints introduced beyond what was planned in `<threat_model>`. The `.well-known/subscription-pins.json` endpoint is the designed manifest delivery path.

## Self-Check: PASSED

- PinStore.swift: FOUND
- PinManifest.swift: FOUND
- PinnedSessionDelegate.swift: FOUND
- SubscriptionPinManager.swift: FOUND
- subscription-pins-bootstrap.json: FOUND
- scripts/generate-spki-pin.swift: FOUND
- PinnedSessionDelegateTests.swift: FOUND
- SubscriptionPinManagerTests.swift: FOUND
- AppGroupContainer.swift (certPinManifestDirectory added): FOUND
- SubscriptionURLFetcher.swift (PinnedSubscriptionURLFetcher + makeSession added): FOUND
- Package.swift (swift-crypto dependency added): FOUND
- Commits ff391f4, 2a5cb41, f9caf9d, 9ca6461: all present in git log
- swift build Packages/ConfigParser: Build complete, 0 errors
- swift test Packages/ConfigParser: 240/240 PASS
- PinnedSessionDelegateTests: 5/5 PASS
- SubscriptionPinManagerTests: 7/7 PASS
