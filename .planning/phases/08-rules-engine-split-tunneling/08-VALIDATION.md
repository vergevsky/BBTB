---
phase: 8
slug: rules-engine-split-tunneling
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-15
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `08-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift Testing backport / `swift test` per-package) + `xcodebuild` smoke for iOS/macOS targets |
| **Config file** | `Package.swift` per package (no central test config) |
| **Quick run command** | `cd BBTB/Packages/RulesEngine && swift test` |
| **Full suite command** | `bash BBTB/scripts/validate-r1-r6.sh` (extended in W7 with rule_set assertions) + `swift test` in each affected package (`RulesEngine`, `PacketTunnelKit`, `AppFeatures`) |
| **Phase 8 invariant gate** | `BBTB/scripts/validate-r1-r6.sh` — must be extended in W7 with R8 + RULES-02 + D-08 assertions before phase exit |
| **Estimated runtime** | ~120-180 sec full suite per package set; ~10 sec for RulesEngine quick run |

---

## Sampling Rate

- **After every task commit:** `swift test` for the affected package only (~few seconds; max latency < 30 sec)
- **After every wave merge:** all affected packages `swift test` + `bash BBTB/scripts/validate-r1-r6.sh` (existing R1/R6 gate + new W7 rule_set assertions)
- **Before `/gsd-verify-work 8`:** full suite green on iOS+macOS xcodebuild + R1/R6 gate green + manual UAT M-04 / M-05 / M-07 PASS on iPhone
- **Max feedback latency:** ≤ 30 sec for per-task commit feedback; ≤ 5 min for full-suite/wave-merge feedback

---

## Per-Task Verification Map

| REQ-ID | Behavior | Wave | Test Type | Automated Command | File Exists | Status |
|--------|----------|------|-----------|-------------------|-------------|--------|
| RULES-01 | Download from primary VPS + 3 mirror failover (sequential, DEC-06d-04) | W1 | unit (mock URLSession) | `swift test --filter RulesFetcherTests.testMirrorFailover` | ❌ W0 | ⬜ pending |
| RULES-02 | Ed25519 detached-signature verify via swift-crypto / CryptoKit | W1 | unit | `swift test --filter RulesSignerTests.testVerifyValidSignature` + `.testVerifyTamperedSignature` | ❌ W0 | ⬜ pending |
| RULES-03 | Bad signature → ignore update, keep cache | W2 | unit (integration) | `swift test --filter RulesEngineCoordinatorTests.testTamperedSignatureKeepsCache` | ❌ W0 | ⬜ pending |
| RULES-04 | Fetch on start + every 6h background (BGAppRefreshTask iOS / NSBackgroundActivityScheduler macOS) | W2 | unit + manual UAT M-04 | `swift test --filter RulesEngineCoordinatorTests.testBootstrapTriggersFetch` + UAT M-04 (real device wall-time) | ❌ W0 | ⬜ pending |
| RULES-05 | Apply 3 categories correctly (block / never / always) | W1 | unit (config inspect) + manual UAT M-05 | `swift test --filter SingBoxConfigLoaderTests.testRulesetInjection` + UAT M-05 (real domain blocking on device) | ❌ W0 | ⬜ pending |
| RULES-06 | Priority order block > never > always > default | W1 | unit (config inspect) | `swift test --filter SingBoxConfigLoaderTests.testRulesetOrdering` | ❌ W0 | ⬜ pending |
| RULES-07 | Split-tunnel by domains / IPs / countries (server-resolved CIDR per D-04) | W1 | unit + manual UAT M-07 | `swift test --filter SingBoxConfigLoaderTests.testRulesetInjection` + UAT M-07 | ❌ W0 | ⬜ pending |
| RULES-08 | `min_app_version` numeric semver comparison + sheet display | W3 | unit | `swift test --filter MinAppVersionTests.testNumericComparison` (covers `1.2.0 < 1.2.10`) | ❌ W0 | ⬜ pending |
| RULES-09 | Read-only viewer in Advanced Settings | W3 | unit (ViewModel) + UI snapshot | `swift test --filter SettingsViewModelTests.testRulesSnapshotPublishing` | ❌ W0 | ⬜ pending |
| RULES-10 | Force-update button + 60s cooldown state machine (D-10) | W3 | unit (state machine) | `swift test --filter ForceUpdateButtonStateTests.testCooldownStateMachine` | ❌ W0 | ⬜ pending |
| RULES-11 | (carve-out per CONTEXT D-08 → Out of Scope v0.8) | W0 amendment | N/A — ROADMAP/REQUIREMENTS edit | manual review of W0 commit diff | N/A | ⬜ pending |
| CORE-05 | Background fetch cadence + cold-start defer (DEC-06d-01) | W2 | unit + manual UAT M-04 | shared with RULES-04 | ❌ W0 | ⬜ pending |
| **R1 invariant** | rule_set entries в expanded JSON НЕ открывают forbidden inbound types (no SOCKS5/mixed) | W7 | shell assert | extend `validate-r1-r6.sh` with `! grep "type.*socks\|type.*mixed"` in expanded fixture | ❌ W7 | ⬜ pending |
| **R6 invariant** | swift-crypto Ed25519 pubkey hardcoded as 32-byte literal (not loaded from disk/network) | W7 | shell assert | extend `validate-r1-r6.sh` with hex-byte count check | ❌ W7 | ⬜ pending |
| **R8 invariant** (new) | Template has no inline `rule_set`; runtime expansion injects via AppGroupContainer paths | W7 | shell assert | extend `validate-r1-r6.sh` with `! grep "rule_set" template.json` + `grep "AppGroupContainer.url" SingBoxConfigLoader.swift` | ❌ W7 | ⬜ pending |
| **R10 invariant** | post-expand `SingBoxConfigLoader.validate(json:)` passes after rule_set injection | W1 | unit | `swift test --filter SingBoxConfigLoaderTests.testValidateAfterRulesetExpansion` | ❌ W0 | ⬜ pending |
| **D-08 carve-out** | No `NEAppProxyProvider` imports remain anywhere in main app sources after W0 amendment | W7 | shell assert | extend `validate-r1-r6.sh` with `! grep -rE "NEAppProxyProvider\|app-proxy-provider" BBTB/App/macOSApp BBTB/Packages/AppFeatures` | ❌ W7 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

W0 is dual-purpose for Phase 8: (1) ROADMAP/REQUIREMENTS amendment (RULES-11 → Out of Scope, SC #3 → deferred, AppProxyExtension-macOS target → DELETE) AND (2) create test stubs for the requirements listed below.

- [ ] `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesFetcherTests.swift` — stubs for RULES-01 (URLSession mock + mirror failover)
- [ ] `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesSignerTests.swift` — stubs for RULES-02 (valid + tampered + wrong-key signature)
- [ ] `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift` — stubs for RULES-03..04 + CORE-05
- [ ] `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` (extend existing) — stubs for RULES-05..07 + R10 post-expand
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift` (extend existing) — stubs for RULES-09..10 ViewModel layer
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/MinAppVersionTests.swift` — stubs for RULES-08 (numeric semver edge cases)
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/ForceUpdateButtonStateTests.swift` — stubs for RULES-10 cooldown state machine
- [ ] `BBTB/Packages/Package.swift` (RulesEngine root) — add `swift-crypto` 4.5.0 dep (no current dep — research note)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| **M-04: Background fetch real wall-time** | RULES-04, CORE-05 | iOS/macOS scheduler choice is opportunistic (lower bound only); cannot deterministically force-fire 6h interval in unit test. iOS simulator does honour `_simulateLaunchForTaskWithIdentifier:` but real-device validation closes the loop. | (1) install build on iPhone; (2) connect; (3) leave app backgrounded; (4) approx 6h later (or trigger via Xcode Debug → Simulate Background Fetch on iOS Simulator) verify SRS file mtime advanced + log shows `bbtbRulesEngineDidUpdate` posted. |
| **M-05: Real domain blocking on device** | RULES-05 | Unit tests prove `route.rule_set` correctly injected into expanded config; only real tunnel verifies sing-box actually drops traffic to `block_completely.domains`. | (1) seed baseline rules with test domain (e.g. `example-blocked.test`); (2) connect tunnel on iPhone; (3) `curl -v https://example-blocked.test` from device Safari → connection reset/timeout; (4) repeat for `never_through_vpn` (should leak to direct, verify via local IP); (5) `always_through_vpn` (should route through VPN even if user toggled split). |
| **M-07: Split-tunnel country resolution** | RULES-07 | Server-side country expansion produces a CIDR set baked into SRS; client cannot independently verify CIDR coverage without a known geo-located test endpoint. | (1) admin packs rules with `countries: ["RU"]` in `never_through_vpn`; (2) iPhone connects; (3) request to known-RU IP (e.g. `yandex.ru`) goes direct (`whois` confirms RU AS); (4) request to non-RU IP goes through VPN. |
| **M-08: min_app_version sheet UX flow** | RULES-08, D-11 | UI snapshot tests cover layout; need human validation of dismissal + per-version `@AppStorage` flag durability (kill app, re-open, sheet should re-appear if new minAppVersion delivered). | (1) admin publishes rules with `min_app_version: 99.0.0`; (2) iPhone fetches; (3) sheet appears; (4) dismiss → banner persists in Advanced; (5) force-kill app; (6) re-open → sheet re-appears (because $$ new version inferred from latest fetch). |
| **M-10: Tuist AppProxyExtension-macOS removal** | D-09 carve-out | Tuist regeneration produces an Xcode project diff that should be human-reviewed to confirm no stale references remain. | (1) After W0 commit, run `tuist generate` on a clean checkout; (2) `git status` shows only expected deletions; (3) `xcodebuild -scheme BBTB-macOS` succeeds without `AppProxyProvider.swift` references; (4) Apple Developer Portal: App ID `app.bbtb.client.macos.appproxy` either deleted or has AppProxy capability disabled. |

---

## Validation Sign-Off

- [ ] All tasks have an `<automated>` verify block OR a Wave 0 dependency / Manual-only listing
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING test references
- [ ] No watch-mode flags in any test command
- [ ] Feedback latency: per-task ≤ 30 sec; per-wave ≤ 5 min
- [ ] `nyquist_compliant: true` set in frontmatter after planner finalises plans
- [ ] `wave_0_complete: true` set after W0 PLAN.md tasks land

**Approval:** pending
