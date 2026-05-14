---
phase: 6e
slug: performance-audit-round-2-macos-uat-replay
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-05-14
---

# Phase 6e — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from `06E-RESEARCH.md` Section 6 (Validation Architecture / Nyquist).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `swift-testing` (Apple Testing Library 1902) + XCTest (mixed in AppFeatures) |
| **Config file** | `BBTB/Packages/AppFeatures/Package.swift` (test target declaration) |
| **Quick run command** | `swift test --package-path BBTB/Packages/AppFeatures` |
| **Full suite (multi-package)** | `swift test --package-path BBTB/Packages/AppFeatures` + `swift test --package-path BBTB/Packages/PacketTunnelKit` + `swift test --package-path BBTB/Packages/VPNCore` + `swift test --package-path BBTB/Packages/ConfigParser` + `swift test --package-path BBTB/Packages/Localization` |
| **Cross-package iOS gate** | `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build` |
| **Cross-package macOS gate** | `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` |
| **Periphery scan** | `periphery scan --workspace BBTB/BBTB.xcworkspace --schemes BBTB BBTB-macOS --retain-public --report json` |
| **Baseline (post-6d HEAD `584fcbd`)** | **AppFeatures: 133/133 PASS in 7.20s** (verified 2026-05-14) |
| **Estimated runtime (quick gate)** | ~10 sec (AppFeatures only) |
| **Estimated runtime (full regression gate)** | ~3–5 min (all packages + iOS + macOS xcodebuild) |

---

## Sampling Rate

Hybrid closure rigor per Phase 6e CONTEXT.md D-04:

- **After each MEDIUM atomic commit (Wave 1, 4×):** Full regression gate
  - `swift test --package-path BBTB/Packages/AppFeatures` (≥133/133)
  - `xcodebuild` iOS scheme build
  - `xcodebuild` macOS scheme build
  - Plus targeted package tests если MEDIUM трогает PacketTunnelKit (M8) или TransportRegistry
- **Within Wave 2 LOW bundle commits (optional intra-bundle):** `swift build --package-path BBTB/Packages/AppFeatures` (compile-only, fast)
- **After Wave 2 final bundle commit:** Full regression gate + D-09 grep audit + Periphery delta confirmation
- **Before Wave 3 closure commit:** Full regression gate + final D-09 grep audit
- **Before `/gsd-verify-work 6e`:** Full suite must be green
- **Max feedback latency:** ~3-5 min per gate (full regression)

---

## Per-Task Verification Map

> Filled provisionally; planner re-confirms exact Task IDs в PLAN.md и synchronizes table.

| Task ID | Plan | Wave | Requirement | Finding Ref | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-------------|-----------|-------------------|-------------|--------|
| 06E-W1-M7 | 01 | 1 | QUAL-04 | M7 — scenePhase consolidation | unit + integration | `swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenViewModelTests` + full gate | ✅ existing + 1 NEW | ⬜ pending |
| 06E-W1-M10 | 01 | 1 | QUAL-04 | M10 — loadFromStore idempotency | unit | `swift test --package-path BBTB/Packages/AppFeatures --filter ServerListViewModelTests` + full gate | ✅ existing + 2 NEW | ⬜ pending |
| 06E-W1-M8 | 01 | 1 | QUAL-04 + QUAL-03 (R10 invariant) | M8 — validatedAt guard + L12 | unit | `swift test --package-path BBTB/Packages/PacketTunnelKit` (61/61 + new) + full gate | ✅ existing + 3 NEW | ⬜ pending |
| 06E-W1-M11 | 01 | 1 | QUAL-04 + QUAL-01 (D-09) | M11 — applyVPNStatus early-return guard | unit + integration | `swift test --package-path BBTB/Packages/AppFeatures --filter AutoSelectIntegrationTests` + full gate | ✅ existing + 1 NEW | ⬜ pending |
| 06E-W2-themeA | 02 | 2 | QUAL-04 | LOW bundle: L3, L7, L8, L11, L13 (perf) | unit (compile-only intra) | `swift build` intra + full gate at bundle end | ✅ existing | ⬜ pending |
| 06E-W2-themeB | 02 | 2 | QUAL-04 | LOW bundle: L1, L5, L9, L10, L14 (correctness) | unit | `swift build` intra + full gate at bundle end + 2 NEW tests | ✅ existing + 2 NEW | ⬜ pending |
| 06E-W2-themeC1 | 02 | 2 | QUAL-04 | LOW bundle: L2, L4, L15, L18, L20 (maintainability) | compile + grep | `swift build` intra + full gate at bundle end | ✅ existing | ⬜ pending |
| 06E-W2-themeC2 | 02 | 2 | QUAL-04 + QUAL-01 (D-09) | LOW bundle: L16 standalone (applyVPNStatus extraction, HIGH RISK) | unit + code-reviewer | `swift test --package-path BBTB/Packages/AppFeatures` + full gate + Codex code review | ✅ existing + 2 NEW | ⬜ pending |
| 06E-W2-themeD | 02 | 2 | QUAL-04 + QUAL-05 (Periphery) | trivial imports (3) + Periphery scan | compile | `swift build` + Periphery scan + full gate | ✅ existing | ⬜ pending |
| 06E-W3-closure | 03 | 3 | QUAL-01 + QUAL-04 | D-09 grep audit + SUMMARY + wiki/STATE/ROADMAP/REQUIREMENTS sync | grep audit + docs | manual grep script + full final gate | ✅ existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

**Wave 0 complete (existing).** No new test framework setup required for Phase 6e — `swift-testing` + XCTest infrastructure unchanged from Phase 6d. 133-test AppFeatures baseline ready.

**Optional new test files (per RESEARCH.md Section 6):**
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift` (M7)
- [ ] `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift` (M8 + L12)
- [ ] `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift` (M10)
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift` (M11)
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift` (L16, if extraction goes ahead)

Planner re-confirms test file scope in PLAN.md (per Open Question Q3 — L16 execute vs defer).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cross-platform PacketTunnelKit M8 / L1 / L20 fixes on macOS host | QUAL-03 (R10 invariant) | Full sing-box import + connect smoke is environment-dependent; UAT deferred to Phase 11/12 per D-03 | macOS xcodebuild build gate ONLY (compile coverage); full smoke deferred. Documented в SUMMARY как known-deferred. |
| Numerical Instruments baseline (Time Profiler cold-launch, Energy Log 5-min idle, Allocations) | DEFERRED per D-02 | User chose velocity over capture; PerfSignposter (DEC-06d-06) preserved for Phase 11/12 pre-TestFlight | Not in Phase 6e scope. Will be captured Phase 11/12. |
| macOS UAT replay (scenarios A / F-direct / F-reverse / Settings-disable / G) | DEFERRED per D-03 | Same source code as iOS, risk low | Not in Phase 6e scope. Will be replayed Phase 11/12. |

---

## Failure Modes (Nyquist Dim 7)

Per RESEARCH.md Section 6:

| Failure mode | Detection |
|--------------|-----------|
| Regression in `applyVPNStatus` authority (M11, L16) | AppFeatures swift test, especially `AutoSelectIntegrationTests` + Phase 6d post-fix 8k duplicate-event coverage |
| R10 defense-in-depth violation (M8) | PacketTunnelKit swift test; `grep 'SingBoxConfigLoader.validate'` ≥ 2 occurrences; manual smoke deferred per D-03 |
| SwiftData regression (M10) | AppFeatures swift test (ServerList* paths) |
| D-09 forbidden symbol resurrection | RESEARCH.md Section 4 final grep audit (≤7 forbidden hits, observer queue=`.main`=0, `#Predicate` UUID? = 0, etc.) |
| Phase 6c R18 sliding-window regression | `grep 'toggle && intent'` = 2 hits in `OnDemandRulesBuilder.swift` |
| ExternalVPNStopMarker semantics break (peek-only API) | `grep 'ExternalVPNStopMarker'` — verify no new `.consume()` callers |
| DEC-06d-01..06 pattern regression | Section 4 invariant map cross-check + Periphery scan delta |

---

## D-09 Final Grep Audit (Nyquist Dim 8)

Run before Wave 3 closure commit. Pattern adopted from `06D-INVARIANT-AUDIT.md`:

```bash
# 1. Forbidden symbols (≤7 allowed)
grep -rIn --include='*.swift' -E '(Task\.detached|MainActor\.assumeIsolated|preconditionFailure|fatalError|os_unfair_lock|@MainActor\.preconditionIsolated)' BBTB/ | grep -v '/Tests/' | wc -l   # ≤ 7

# 2. NEVPNStatusDidChange observer queue = .main → 0
grep -rIn --include='*.swift' 'addObserver.*NEVPNStatusDidChange' BBTB/ | grep -E 'queue:\s*\.main' | wc -l   # 0

# 3. #Predicate UUID? → 0
grep -rIn --include='*.swift' -E '#Predicate.*UUID\?' BBTB/ | wc -l   # 0

# 4. applyVPNStatus single authority
grep -rIn --include='*.swift' 'func applyVPNStatus' BBTB/ | wc -l   # 1

# 5. ExternalVPNStopMarker — no new .consume() callers
grep -rIn --include='*.swift' 'ExternalVPNStopMarker' BBTB/ | grep '.consume(' | wc -l   # 0

# 6. R18 sliding window invariant
grep -rIn --include='*.swift' 'toggle && intent' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift | wc -l   # 2

# 7. AppFeatures baseline
swift test --package-path BBTB/Packages/AppFeatures   # 133/133 PASS (или ≥133 если new tests added)
```

If any check fails — STOP, revert, investigate root cause per D-08 (Phase 6c R18 lesson: НЕ "fix forward").

---

## Validation Sign-Off

- [ ] All Wave 1 MEDIUM tasks have per-commit regression gate
- [ ] Wave 2 LOW bundles have single end-of-bundle regression gate
- [ ] Wave 3 closure has final D-09 grep audit + Periphery scan
- [ ] AppFeatures swift test stays ≥ 133/133 на каждом gate
- [ ] iOS + macOS xcodebuild SUCCEEDED на каждом gate
- [ ] Phase 6d DEC-06d-01..06 patterns preserved (Section 4 invariant map)
- [ ] Phase 6c R18 sliding window invariant preserved
- [ ] `nyquist_compliant: true` set in frontmatter after planner approval

**Approval:** pending (set by planner upon PLAN.md creation)

---

*Phase: 06e — Performance Audit Round 2*
*Derived from: 06E-RESEARCH.md Section 6 (Validation Architecture / Nyquist)*
*Created: 2026-05-14 via plan-phase orchestrator (Nyquist gate, nyquist_validation_enabled=true)*
