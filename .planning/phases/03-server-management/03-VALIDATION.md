---
phase: 03
slug: server-management
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-12
completed: 2026-05-12
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (XCTest co-exists per Phase 1/2 baseline) |
| **Config file** | none (SwiftPM auto-discovers `Tests/<Module>Tests/`) |
| **Quick run command** | `xcodebuild test -scheme VPNCore -destination 'platform=iOS Simulator,name=iPhone 15'` |
| **Full suite command** | `xcodebuild test -workspace BBTB.xcworkspace -scheme BBTB -destination 'platform=iOS Simulator,name=iPhone 15' -resultBundlePath /tmp/bbtb-test.xcresult` |
| **Estimated runtime** | ~30-60 seconds (unit), ~2-3 minutes (full) |

---

## Sampling Rate

- **After every task commit:** Run quick module test for the affected module
- **After every plan wave:** Run full SwiftPM test for all affected modules (VPNCore, ConfigParser, AppFeatures)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds (unit), 180 seconds (full)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | SRV-02 | — | N/A | unit (RED) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/SubscriptionModelTests` | ✅ verified | ✅ green |
| 03-01-02 | 01 | 1 | SRV-02 | T-03-06 | Subscription.name clamped to 100 chars | unit (GREEN) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/SubscriptionModelTests` | ✅ verified | ✅ green |
| 03-01-03 | 01 | 1 | SRV-02 | T-03-09 | Migration idempotent on 2nd call | unit (GREEN migration) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/Phase3MigrationTests` | ✅ verified | ✅ green |
| 03-02-01 | 02 | 1 | SRV-01 | T-03-07 | score = latency × (1 + lossRate) correct | unit (RED) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/ServerScoreTests` | ✅ verified | ✅ green |
| 03-02-02 | 02 | 1 | SRV-01 | T-03-07 | TCP probe states, auto-select winner/fallback | unit (GREEN) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/ServerProbeServiceTests,VPNCoreTests/AutoSelectTests` | ✅ verified | ✅ green |
| 03-03-01 | 03 | 2 | SRV-02, SRV-03, UX-04 | — | Country flag `cc=` validation (reject non-[A-Za-z]{2}) | unit + manual UAT | `xcodebuild test -scheme ServerListFeature -only-testing:ServerListFeatureTests/SectionGroupingTests,ServerListFeatureTests/CountryFlagTests` | ✅ verified | ✅ green |
| 03-04-01 | 04 | 3 | SRV-02, SRV-03, UX-04 | T-03-08 | Cascade delete removes all linked ServerConfig | unit (RED) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/CascadeDeleteTests` | ✅ verified | ✅ green |
| 03-04-02 | 04 | 3 | SRV-02, SRV-03, UX-04 | — | Pull-to-refresh: 2-phase sequential (fetch + ping) | unit (GREEN) | `xcodebuild test -scheme ServerListFeature -only-testing:ServerListFeatureTests/PullToRefreshTests,MainScreenFeatureTests/MergeStrategyTests` | ✅ verified | ✅ green |
| 03-05-01 | 05 | 4 | SRV-01 | T-03-08 | All-unreachable → MainScreenError.noReachableServers | unit (RED) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/AutoSelectTests/testAllUnreachable` | ✅ verified | ✅ green |
| 03-05-02 | 05 | 4 | SRV-01 | — | Pre-connect auto-select + UserDefaults persist | unit (GREEN) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/AutoSelectTests` | ✅ verified | ✅ green |
| 03-05-03 | 05 | 4 | SRV-01 | — | UAT: full E2E on device | manual | Device UAT checklist (Plan 05 Task 3) | N/A | ✅ green (UAT T1-T8 PASS 2026-05-12) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerProbeServiceTests.swift` — TCP probe state machine, timeout handling
- [x] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerScoreTests.swift` — pure score formula (no IO)
- [x] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/SubscriptionModelTests.swift` — @Model CRUD + name clamping
- [x] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/CascadeDeleteTests.swift` — manual cascade verification
- [x] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/Phase3MigrationTests.swift` — idempotency, empty store, Phase 2 rows present
- [x] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/CountryFlagTests.swift` — flag derivation (cc= param, fragment regex, fallback 🌐)
- [x] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/AutoSelectTests.swift` — winner selection + allUnreachable fallback
- [x] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderSingleOutboundTests.swift` — degenerate single-outbound path
- [x] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift` — Subscription branch in ConfigImporter
- [x] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MergeStrategyTests.swift` — D-14 merge by identity
- [x] `BBTB/Packages/AppFeatures/Sources/ServerListFeature/` new target + `Tests/ServerListFeatureTests/` — SectionGroupingTests, PullToRefreshTests, CountryFlagTests

_Verified: 162 tests total (VPNCore 32 + ConfigParser 93 + AppFeatures 37). PASS. UAT T1-T8 PASS 2026-05-12._
