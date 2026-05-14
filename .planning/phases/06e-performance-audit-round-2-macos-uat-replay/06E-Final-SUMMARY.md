---
phase: 06e-performance-audit-round-2
plan: Final
type: summary
status: closed
date: 2026-05-14
version: v0.6.3
findings_total: 26
findings_closed_in_6e: 19           # SCENARIO B + L18 deferral (W1: 5; W2 bundles: 14)
findings_subsumed_by_6d: 5          # M6, M15, L6, L17, L19
findings_deferred: 2                # L16 (Theme C-2 — Codex no-go), L18 (lazy var architectural incompatibility)
trivial_imports_closed: 3           # QUAL-05 (Periphery-derived, separate from L#/M# IDs)
commits_total: 9                    # Wave 1: 4 atomic; Wave 2: 4 bundles; Wave 3: 1 closure (this commit)
regression_gates_total: 6           # Wave 1: 4 per-commit; Wave 2: 1 end-of-bundle; Wave 3: 1 pre-closure
hard_blockers_passed: "9/9 (D-07 PASS criteria fulfilled)"
math_scenario: "B + L18"            # SCENARIO B (L16 deferred) + L18 carved
requirements_completed: [QUAL-04, QUAL-05]
---

# Phase 6e Final Summary — Performance Audit Round 2 (Closure)

## Status

**Phase 6e ✅ Closed 2026-05-14 — v0.6.3 (patch).**

Tactical cleanup-фаза после Phase 6d. Закрыты остатки 26 carved-out finding'ов с hybrid closure rigor: 4 atomic MEDIUM commit'а (Wave 1) + 4 LOW bundle commit'а (Wave 2) + closure (Wave 3). Phase 7 (Anti-DPI suite + WireGuard family, v0.7) теперь next-active.

---

## 1. What Phase 6e delivered

**Code changes (по Wave):**

| Wave | Plan | Commits | Findings closed |
|------|------|---------|------------------|
| Wave 1 — atomic MEDIUM | 06E-01 | 4 atomic | M7, M10, M8, L12 (bundled with M8), M11 |
| Wave 2 — LOW bundles | 06E-02 | 4 themes (Theme C-2 deferred) | L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L20 + 3 trivial imports |
| Wave 3 — closure | 06E-03 | 1 (this commit) | (documentation only) |

**Distribution по 26 carved finding IDs (SCENARIO B + L18 deferral):**

- **19 code-fixed IDs** в Phase 6e:
  - Wave 1: M7, M10, M8, L12, M11 (5)
  - Wave 2: L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L20 (14)
- **5 bookkeeping IDs** subsumed-by-Phase-6d (no code change в 6e, tracking rows only):
  - M6, M15 (medium subsumed)
  - L6, L17, L19 (low subsumed)
- **2 deferred IDs**:
  - L16 — Theme C-2 (applyVPNStatus reduceStateBanner extraction) — **Codex Plan Reviewer HIGH-RISK no-go** + AUTO_MODE first-option safe-default = "Defer to Phase 6f". Authorized в 06E-02-PLAN Task 5 skip-clause.
  - L18 — lazy `serverListViewModel` в MainScreenViewModel — coordinator backlink на init line 252 (`self.serverListViewModel?.coordinator = self`) форсирует lazy resolution immediately (defeats laziness purpose); `public let → public private(set) lazy var` меняет ObservedObject mutation semantics. Authorized в 06E-02-PLAN Task 1 fallback clause.

**Math invariant check:** 19 (closed) + 5 (subsumed) + 2 (deferred) = **26 ✓** — все carved finding IDs из Phase 6d учтены.

**Trivial imports (3)** — закрыты отдельно (Wave 2 Theme D, `f42499f`); attributed к **QUAL-05** (Periphery actionable count), не к 26 L#/M# IDs (Periphery-derived из `06D-PERIPHERY-POST-FIX.md`, separate accounting).

**Test artifacts added в Wave 1:**
- 4 new test files (15 new tests total):
  - `HandleForegroundReentryTests.swift` (M7) — 3 tests
  - `LoadFromStoreIdempotencyTests.swift` (M10) — 4 tests
  - `ValidatedAtGuardTests.swift` (M8 + L12) — 5 tests
  - `ApplyVPNStatusGuardTests.swift` (M11) — 3 tests
- Wave 2 не добавил test файлов (Theme C-2 L16 deferred → `ReduceStateBannerTests.swift` НЕ создан).

---

## 2. Closed findings table — 26 carved + 3 trivial imports

| ID | Severity | Action | Commit SHA |
|----|----------|--------|------------|
| **M7** | MEDIUM | `fix(06e-M7)` consolidate scenePhase=.active hooks → handleForegroundReentry | `ca21fa9` |
| **M10** | MEDIUM | `fix(06e-M10)` ServerListViewModel.loadFromStore idempotency + confirmDeleteSubscription single-tail-call | `6af41db` |
| **M8** | MEDIUM | `fix(06e-M8 + L12)` pre-expand validate guarded by configJSONValidatedAt 24h cache (R10 post-expand preserved) | `368c82f` |
| **L12** | LOW (bundled with M8) | (same as M8) | `368c82f` |
| **M11** | MEDIUM | `fix(06e-M11)` explicit applyVPNStatus(.connecting) early-return guard (D-09 single authority preserved) | `4269570` |
| **M6** | MEDIUM | subsumed-by-Phase-6d (no code change in 6e — tracking row only) | `1467328` + `9b38796` |
| **M15** | MEDIUM | subsumed-by-Phase-6d | `55bde6c` |
| **L1** | LOW (Theme B correctness) | `chore(06e)` clearDNSCache 2s timeout | `f857763` |
| **L9** | LOW (Theme B correctness) | `chore(06e)` failover banner 5s TTL | `f857763` |
| **L10** | LOW (Theme B correctness) | `chore(06e)` observer-fire-before-attempt | `f857763` |
| **L20** | LOW (Theme B correctness) | `chore(06e)` commandServer cleanup | `f857763` |
| **L2** | LOW (Theme C-1 maintainability) | `chore(06e)` WS sniFallback unification (Option A2 WS-overload) | `a03007f` |
| **L5** | LOW (Theme C-1 maintainability) | `chore(06e)` UserNotificationsHelper extraction | `a03007f` |
| **L14** | LOW (Theme C-1 maintainability) | `chore(06e)` print → Logger importer-upgrade | `a03007f` |
| **L15** | LOW (Theme C-1 maintainability) | `chore(06e)` autoDetectControl log level downgrade | `a03007f` |
| **L3** | LOW (Theme A perf) | `chore(06e)` L10n lazy keys (83 var; 22 static let preserved) | `5c74423` |
| **L4** | LOW (Theme A perf) | `chore(06e)` ImportProgressOverlay → `.overlay {}` modifier | `5c74423` |
| **L7** | LOW (Theme A perf) | `chore(06e)` ServerListSheet detents → @State + .onChange | `5c74423` |
| **L8** | LOW (Theme A perf) | `chore(06e)` QRScannerViewController QoS → .userInteractive | `5c74423` |
| **L11** | LOW (Theme A perf) | `chore(06e)` SettingsViewModel notification once outside for-loop | `5c74423` |
| **L13** | LOW (Theme A perf) | `chore(06e)` .prettyPrinted → [] в 6 ConfigBuilder call-sites | `5c74423` |
| **L16** | LOW (Theme C-2) | **DEFERRED** — Codex Plan Reviewer HIGH-RISK no-go + AUTO_MODE safe-default | (no commit — Phase 6f либо Phase 7+ refactor) |
| **L18** | LOW (Theme A bundle fallback) | **DEFERRED** — lazy var incompatible с init-time coordinator backlink + ObservedObject ABI change | (no commit — Phase 6f либо Phase 7+ refactor) |
| **L6** | LOW | subsumed-by-Phase-6d (Phase 6d H5) | `5ef3888` |
| **L17** | LOW | subsumed-by-Phase-6d post-fix bundle | `bc7bc26` + `1467328` |
| **L19** | LOW | subsumed-by-Phase-6d (Phase 6d H7) | `b8d9294` |
| Trivial-1 | trivial (QUAL-05) | `chore(06e)` ServerDetailView remove `import ConfigParser` | `f42499f` |
| Trivial-2 | trivial (QUAL-05) | `chore(06e)` ServerListSheet remove `import ConfigParser` | `f42499f` |
| Trivial-3 | trivial (QUAL-05) | `chore(06e)` TransportPicker remove `import DesignSystem` | `f42499f` |

**Out-of-scope discovery (carry-forward, not in 26):** `MainScreenView.swift:15 @Environment(\.scenePhase)` declaration — leftover from Wave 1 M7 `ca21fa9` (после удаления `.onChange(of: scenePhase)` declaration остался). Trivial 1-line removal. Documented в 06E-02-SUMMARY Deferred Items #3. **Carry-forward к Phase 6f / Phase 7+.**

---

## 3. Regression gate evidence

### Wave 1 (4× per-commit gate, см. 06E-01-SUMMARY)

| Task | swift test AppFeatures | swift test PacketTunnelKit | iOS xcodebuild | macOS xcodebuild |
|------|------------------------|----------------------------|----------------|-------------------|
| Baseline (HEAD pre-M7) | 133/133 PASS | 61/61 PASS | SUCCEEDED | SUCCEEDED |
| Post-M7 (`ca21fa9`) | 136/136 PASS | (no change) | SUCCEEDED | SUCCEEDED |
| Post-M10 (`6af41db`) | 140/140 PASS | (no change) | SUCCEEDED | SUCCEEDED |
| Post-M8+L12 (`368c82f`) | 140/140 PASS | 66/66 PASS | SUCCEEDED | SUCCEEDED |
| Post-M11 (`4269570`) | 143/143 PASS | 66/66 PASS | SUCCEEDED | SUCCEEDED |

### Wave 2 (1× end-of-bundle gate, см. 06E-02-SUMMARY)

| Package | Tests | Status |
|---------|-------|--------|
| AppFeatures | 143/143 | ✅ PASS |
| PacketTunnelKit | 66/66 | ✅ PASS |
| VPNCore | 57/57 (1 skipped) | ✅ PASS |
| ConfigParser | 210/210 | ✅ PASS |
| Localization | 3/3 | ✅ PASS |
| TransportRegistry | 42/42 | ✅ PASS |
| Protocols/Trojan | 16/16 | ✅ PASS |
| Protocols/VLESSTLS | 20/20 | ✅ PASS |
| Protocols/VLESSReality | 4/4 | ✅ PASS |
| Protocols/Shadowsocks | 10/10 | ✅ PASS |
| Protocols/Hysteria2 | 14/14 | ✅ PASS |

**Total Wave 2 end-of-bundle:** 585 tests + 1 skipped, 0 failures.

### Wave 3 (D-05a pre-closure final gate — этот замер, 2026-05-14T12:42Z)

| Package | Tests | Status |
|---------|-------|--------|
| AppFeatures | 143/143 | ✅ PASS (11.94s) |
| PacketTunnelKit | 66/66 | ✅ PASS (0.02s) |
| VPNCore | 57/57 (1 skipped) | ✅ PASS (0.68s) |
| ConfigParser | 210/210 | ✅ PASS (0.19s) |
| Localization | 3/3 | ✅ PASS (0.004s) |
| TransportRegistry | 42/42 | ✅ PASS (0.01s) |
| Protocols/Trojan | 16/16 | ✅ PASS |
| Protocols/VLESSTLS | 20/20 | ✅ PASS |
| Protocols/VLESSReality | 4/4 | ✅ PASS |
| Protocols/Shadowsocks | 10/10 | ✅ PASS |
| Protocols/Hysteria2 | 14/14 | ✅ PASS |

**Total Wave 3 pre-closure:** 585 tests + 1 skipped, 0 failures.

### xcodebuild — Wave 3 D-05a final replay

| Scheme | Destination | Result |
|--------|-------------|--------|
| BBTB (iOS) | `generic/platform=iOS Simulator` | ✅ BUILD SUCCEEDED |
| BBTB-macOS | `platform=macOS` (unsigned) | ✅ BUILD SUCCEEDED |

---

## 4. D-09 invariants final 8-check grep audit (Wave 3, 2026-05-14)

| # | Check | Expected | Actual | Status |
|---|-------|----------|--------|--------|
| 1 | Forbidden symbols (ReconnectStateMachine / NetworkReachability / ReconnectStateObserverRelay) excl Tests | ≤ 7 actual usages | **15 hits → 0 actual usages (all doc-comments / historical refs in ReconnectClock.swift, MainScreenViewModel.swift, TunnelWatchdog.swift, ConfigImporter.swift, FailoverProvider.swift, BBTB_iOSApp.swift, BBTB_macOSApp.swift, UserNotificationsHelper.swift)** | ✅ |
| 2 | NEVPNStatusDidChange observer queue=.main | 0 | **0** | ✅ |
| 3 | `#Predicate UUID?` actual usage | ≤ 1 (comments allowed) | **3 hits → 0 actual (all comment-only references к invariant в ServerListViewModel.swift x2 + ConfigImporter.swift)** | ✅ |
| 4 | applyVPNStatus definitions | = 1 | **2 hits → 1 actual definition + 1 docstring (ApplyVPNStatusGuardTests.swift comment)** | ✅ |
| 5 | ExternalVPNStopMarker `.consume(` actual callers | = 0 | **2 hits → 0 actual callers (oba — doc-comments в самом ExternalVPNStopMarker.swift)** | ✅ |
| 6 | R18 sliding window `toggle && intent` в OnDemandRulesBuilder.swift | = 2 | **2** (comment + code) | ✅ |
| 7 | PerfSignposter spans в production code | ≥ 20 (Phase 6d baseline) | **20** | ✅ |
| 8 | R10 defense-in-depth `SingBoxConfigLoader.validate` в BaseSingBoxTunnel.swift | ≥ 2 | **3** (pre-expand guarded + post-expand unconditional + 1 comment) | ✅ |

**8/8 D-09 checks PASS.** Все "extra" hits в checks 1, 3, 4, 5 — это **comment-only references** (docstrings, historical references, invariant documentation), не actual code usages. Идентично результатам 06E-01-SUMMARY + 06E-02-SUMMARY.

---

## 5. DEC-06d-01..06 architectural patterns preservation

| DEC | Pattern | Status | Evidence |
|-----|---------|--------|----------|
| **DEC-06d-01** | Cold-start init defer (Task.detached) | ✅ Preserved | M7 `handleForegroundReentry` сохраняет `Task.detached(priority: .background)` для runIsSupportedUpgrade; L3 L10n lazy keys **усиливают** паттерн (Bundle.module не парсится eagerly на enum-access). |
| **DEC-06d-02** | XPC consolidation ≤ 2 trips в TunnelController | ✅ Preserved | M7 / M10 / M11 не добавляют новых XPC trips. L11 (`f857763`) REDUCES posts `.bbtbProvisionerDidSave` с N→1 outside for-loop — улучшение DEC-06d-02 направления. |
| **DEC-06d-03** | Event-driven status polling (AsyncStream, не sleep-loops) | ✅ Preserved | L9 `showFailoverBanner` 5s TTL — one-shot `Task.sleep(.seconds(5))`, не poll-loop. L10 reorder сохраняет async observer pattern. |
| **DEC-06d-04** | Bounded probe concurrency (limit 4-8) | ✅ Preserved | `ServerProbeService.maxConcurrentProbes = 8` не тронут. M10 loadFromStore — не probe-style. |
| **DEC-06d-05** | Apple-canonical `options["manualStart"]` + ExternalVPNStopMarker peek-only | ✅ Preserved | options["manualStart"] semantics unchanged; `ExternalVPNStopMarker.isPending` peek-only API preserved (D-09 Check 5: 0 `.consume(` actual callers). |
| **DEC-06d-06** | PerfSignposter spans в production code | ✅ Preserved | 20 PerfSignposter callsites preserved (ColdLaunch iOS+macOS, ProvisionProfile ×2, ConnectTap, PreConnectProbe + setup pairs). |

**6/6 DEC-06d preservation checks PASS.**

---

## 6. R10 defense-in-depth preservation (M8 critical)

**M8 (`368c82f`) добавил `configJSONValidatedAt` 24h cache marker, который guards только PRE-EXPAND validate в `BaseSingBoxTunnel.startTunnel`.**

Post-expand `SingBoxConfigLoader.validate(json: expandedJSON)` ОСТАЁТСЯ unconditional (выполняется ВСЕГДА после `expandConfigForTunnel`). Это R10 defense-in-depth invariant из `wiki/security-gaps.md` R10 — preserved.

**Grep evidence (D-09 Check 8):** 3 hits на `SingBoxConfigLoader.validate` в `BaseSingBoxTunnel.swift`:
1. Pre-expand validate (теперь guarded by `shouldSkipPreExpandValidate`).
2. Post-expand validate (unconditional).
3. Comment reference.

R10 sanitization invariant из `wiki/security-gaps.md` (Phase 1 W3.1 gap-closure) — **untouched**.

---

## 7. Phase 6c R18 + other invariants final audit

| Invariant | Source | Status |
|-----------|--------|--------|
| R18 sliding window — `toggle && intent` = 2 hits в OnDemandRulesBuilder.swift | `wiki/auto-reconnect.md` | ✅ Preserved (D-09 Check 6) |
| ExternalVPNStopMarker peek-only — 0 `.consume(` actual callers | `wiki/security-gaps.md` R19 | ✅ Preserved (D-09 Check 5) |
| R10 defense-in-depth — post-expand validate ALWAYS runs | `wiki/security-gaps.md` R10 | ✅ Preserved (D-09 Check 8 + M8 design) |
| D-09 applyVPNStatus single authority — = 1 func definition | D-09 invariant | ✅ Preserved (Theme C-2 L16 deferred = no func count change) |
| NEVPNStatusDidChange observer queue = nil (NOT .main) | `feedback_nevpn_observer_queue_main.md` | ✅ Preserved (D-09 Check 2) |
| SwiftData `#Predicate` UUID? = 0 actual usage | `feedback_swiftdata_uuid_predicate.md` | ✅ Preserved (D-09 Check 3) |

---

## 8. Periphery scan post-Phase-6e result

**Scan command (Wave 3 D-05a):**
```bash
cd BBTB && periphery scan --project BBTB.xcworkspace --schemes BBTB BBTB-macOS --retain-public --format json
```

**Result:** 37 findings total, breakdown:
- 9 unused functions (`*ForTest()` test helpers — XCTest reflection false-positive)
- 6 unused modules (false-positive cross-package indirect dependencies: `VPNCore` в `ImportedServer.swift` + `TransportRegistry.swift`; `PacketTunnelKit` в 4 ConfigBuilder файлах — Hysteria2/Shadowsocks/Trojan/VLESSTLS — все documented как safe в `06D-PERIPHERY-POST-FIX.md`)
- 5 assign-only properties (NotificationCenter token ownership + closure capture — documented как safe в `06D-PERIPHERY-POST-FIX.md`)
- 17 unused parameters (protocol stub-параметры в handler conformances — architectural pattern)

**Actionable count: 0** ✅ — все 3 Phase 6d-identified actionable trivial imports (ServerDetailView/ServerListSheet ConfigParser + TransportPicker DesignSystem) закрыты в Wave 2 Theme D commit `f42499f`. Остаётся 0 actionable findings; 37 false-positive / architectural.

Это closes **QUAL-05** (Periphery dead-code scan post-Phase-6e: actionable = 0).

---

## 9. Deferred items (carry-forward backlog)

| Item | Reason | Carry-forward |
|------|--------|---------------|
| **L16** — applyVPNStatus `reduceStateBanner` extraction | Codex Plan Reviewer HIGH-RISK no-go (touches D-09 single authority + Phase 6c R18 sliding window invariant; outer-level dedupe guard `9b38796` уже даёт 8k-duplicate-event protection — extraction is cosmetic, not corrective). AUTO_MODE first-option = "Defer". | Phase 6f либо Phase 7+ refactor (когда applyVPNStatus body будет рефакториться в составе larger work) |
| **L18** — lazy `serverListViewModel` | Coordinator backlink на init line 252 (`self.serverListViewModel?.coordinator = self`) форсирует lazy resolution immediately (defeats laziness). Также `public let → public private(set) lazy var` меняет ObservedObject mutation ABI. | Phase 6f либо отложить до Phase 7+ когда MainScreenViewModel init будет рефакториться |
| **MainScreenView.swift:15** unused `@Environment(\.scenePhase)` declaration | Leftover из Wave 1 M7 (`ca21fa9`) — после удаления `.onChange(of: scenePhase)` declaration остался. Periphery flagged out-of-scope в Wave 2 final gate. | Phase 6f либо Phase 7+ — trivial 1-line removal |
| **Numerical Instruments baseline** (Time Profiler / Energy Log / Allocations) | Phase 6e D-02 explicit defer — user velocity priority; PerfSignposter (DEC-06d-06) preserved для будущего capture | Phase 11/12 (pre-TestFlight obligatory snap) |
| **macOS UAT replay** (5 scenarios A / F-direct / F-reverse / Settings-disable / G) | Phase 6e D-03 explicit defer — same source code as iOS, risk low | Phase 11/12 (pre-TestFlight polish) |
| **NET-12** (active liveness probe) | Phase 6c R18 carve-out — НЕ в scope 6e | Phase 7-8 |

---

## 10. Next phase signal

**Phase 6e closure complete.** Next-active phase: **Phase 7 — Anti-DPI suite + WireGuard family (v0.7)**.

User command для следующего шага:
```
/gsd-discuss-phase 7
```

**Что войдёт в Phase 7 (по ROADMAP.md):**
- PROTO-06 (WireGuard через WireGuardKit)
- PROTO-07 (AmneziaWG — modified WireGuard с anti-DPI obfuscation)
- PROTO-08 (TUIC v5 — QUIC-based)
- PROTO-09 (OpenVPN over TLS — legacy совместимость)
- DPI-01..05 + DPI-07 (uTLS fingerprinting, TLS ClientHello фрагментация, packet padding, random TCP/UDP delay, Mux, разные порты)

---

## Self-Check: PASSED

**Verified artifacts:**

Files created в Wave 3 (this commit):
- `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` — present (this file)
- `wiki/performance-baseline.md` — § Open follow-ups updated к post-6e state (Task 3 — separate commit step)
- `wiki/log.md` — appended closure entry (Task 3)
- `.planning/STATE.md` — Phase 6e ✅ Closed; Active Phase → 7 (Task 4)
- `.planning/ROADMAP.md` — Phase 6e plans `[x]`; Success Criteria checkboxes per Wave 1+2 outcome (Task 4)
- `.planning/REQUIREMENTS.md` — QUAL-04 + QUAL-05 added Validated (Task 4)

**Commits exist (Wave 1):**
- `ca21fa9` (M7) ✓
- `6af41db` (M10) ✓
- `368c82f` (M8 + L12) ✓
- `4269570` (M11) ✓

**Commits exist (Wave 2):**
- `5c74423` (Theme A perf, L3/L4/L7/L8/L11/L13) ✓
- `f857763` (Theme B correctness, L1/L9/L10/L20) ✓
- `a03007f` (Theme C-1 maintainability, L2/L5/L14/L15) ✓
- `f42499f` (Theme D trivial imports, 3 imports) ✓

**NOT created (correctly, per L16 deferral):**
- `ReduceStateBannerTests.swift` — INTENTIONALLY ABSENT (would only be needed if L16 extraction proceeded)

**Regression gate evidence:**
- Wave 1: 4× per-commit gate PASS (см. Section 3)
- Wave 2: 1× end-of-bundle gate PASS (585 tests + 1 skipped, iOS+macOS xcodebuild SUCCEEDED)
- Wave 3: 1× pre-closure D-05a gate PASS (replay — 585 tests + 1 skipped, iOS+macOS xcodebuild SUCCEEDED)

**D-09 8-check audit: 8/8 PASS** (см. Section 4)
**DEC-06d-01..06 preservation: 6/6 PASS** (см. Section 5)
**Periphery actionable count: 0** (down from 3 в Phase 6d closure → 0 в Phase 6e Wave 2 Theme D)

---

*Phase: 06e — Performance Audit Round 2 + macOS UAT replay (slug ROADMAP-derived; macOS UAT deferred per D-03)*
*Plan: Final (Wave 3 closure)*
*Completed: 2026-05-14*
*Version: v0.6.3 (patch)*
*Next: /gsd-discuss-phase 7 — Anti-DPI suite + WireGuard family (v0.7)*
