---
phase: 06e-performance-audit-round-2-macos-uat-replay
plan: 01
subsystem: performance-cleanup
tags: [scenephase-coalesce, swiftdata-idempotency, validatedat-guard, applyvpnstatus-guard, r10-defense-in-depth, atomic-medium, phase-6e-wave-1]

requires:
  - phase: 06d-performance-audit
    provides: "Phase 6d post-fix bundle (1467328 / 9b38796 / 55bde6c / bc7bc26 / 5a4db9f) + DEC-06d-01..06 architectural patterns + 26 carved-out findings backlog. Phase 6e Wave 1 closes 4 MEDIUM + 1 LOW (L12 bundled) из этого backlog."

provides:
  - "M7 closed — consolidated scenePhase=.active hooks в MainScreenViewModel.handleForegroundReentry; ОДИН Task spawn вместо 3-4 параллельных в BBTB_iOSApp + BBTB_macOSApp + MainScreenView"
  - "M10 closed — ServerListViewModel.loadFromStore() idempotency guard (loadInProgress flag + 100ms debounce) + confirmDeleteSubscription single-tail-call collapse (раньше 2 calls на cascade-delete normal path)"
  - "M8 + L12 closed — pre-expand validate guarded by configJSONValidatedAt 24h cache marker; ConfigImporter writes ISO8601 timestamp; BaseSingBoxTunnel.startTunnel skip-ает pre-expand validate когда < 24h. R10 post-expand validate ОСТАЁТСЯ unconditional (defense-in-depth preserved)"
  - "M11 closed — explicit early-return guard в applyVPNStatus(.connecting/.reasserting) ветке; semantically equivalent existing nested switch, но documents idempotency intent + skip-ает banner mutation для already-connecting state"
  - "4 new test files: HandleForegroundReentryTests (3 tests), LoadFromStoreIdempotencyTests (4 tests), ValidatedAtGuardTests (5 tests), ApplyVPNStatusGuardTests (3 tests) — total 15 new tests"

affects: [phase-06e-wave-2, phase-06e-wave-3, phase-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Consolidated foreground re-entry hook (handleForegroundReentry) — sequential await вместо параллельных Task spawns; preserves DEC-06d-01 cold-start defer (Task.detached background priority для runIsSupportedUpgrade инкапсулирован)"
    - "SwiftData idempotency guard pattern — loadInProgress flag + lastLoadAt 100ms debounce; defer-based reset; test seam (loadFromStoreCallCountForTests counter инкрементится в успешных executions)"
    - "Pre-expand validate cache marker — ISO8601 timestamp в providerConfiguration через writer side (ConfigImporter) + parser side static helper (BaseSingBoxTunnel.shouldSkipPreExpandValidate) для testable purity"
    - "Explicit early-return guard для applyVPNStatus(.connecting) — documents idempotency перед existing nested switch (secondary safety / readability)"

key-files:
  created:
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift"
    - "BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift"
    - "BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift"
  modified:
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift (handleForegroundReentry + M11 inner guard)"
    - "BBTB/App/iOSApp/BBTB_iOSApp.swift (single-Task scenePhase handler)"
    - "BBTB/App/macOSApp/BBTB_macOSApp.swift (single-Task scenePhase handler)"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift (duplicate scenePhase observer удалён)"
    - "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift (idempotency guard + collapse)"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (writes configJSONValidatedAt timestamp)"
    - "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift (pre-expand validate cache marker + static helper)"

key-decisions:
  - "Hook 2 в handleForegroundReentry использует TunnelControlling.handleForeground() через protocol (а не concrete TunnelController через tunnelController computed prop); тесты с MockTunnel требуют protocol surface"
  - "loadInProgress + 100ms debounce — два guards вместо одного: in-progress flag защищает от concurrent body execution, lastLoadAt от rapid-refresh storms; defer-based reset гарантирует cleanup на throw path"
  - "shouldSkipPreExpandValidate как pure static helper (internal в PacketTunnelKit) — testable без NEPacketTunnelProvider lifecycle; consumes [String: Any] providerConfiguration dict + Date now; returns Bool"
  - "M11 explicit guard — Option A из RESEARCH (preserved Phase 6d 9b38796 outer-level dedupe, added inner-level explicit early-return для readability + secondary safety); existing nested switch остаётся для defensive coverage всех state branches"

patterns-established:
  - "M7 consolidated hook pattern: один async method на ViewModel + один Task spawn на host вместо 3-4 параллельных — снижает Mach-port / cooperative pool contention на foreground re-entry"
  - "M10 SwiftData fetch debounce pattern: lastLoadAt 100ms window + loadInProgress flag — applicable к любому VM с lifecycle fetch-all path"
  - "M8 trust-but-verify cache marker pattern: timestamp в providerConfiguration; reader skip-ает if < 24h; post-process validate ОСТАЁТСЯ unconditional (defense-in-depth preserved)"
  - "M11 explicit-intent guard pattern: early-return guard перед existing branch — documents invariant без functional change; semantically equivalent inner switch break"

requirements-completed: [QUAL-04]

# Metrics
duration: 22m 42s
completed: 2026-05-14
---

# Phase 6e Plan 01: Wave 1 Atomic MEDIUM Fixes (M7 + M10 + M8/L12 + M11)

**4 atomic MEDIUM fixes Phase 6d carved backlog — scenePhase consolidation + SwiftData idempotency guard + pre-expand validate cache marker (R10 preserved) + applyVPNStatus explicit early-return guard**

## Performance

- **Duration:** 22m 42s
- **Started:** 2026-05-14T11:30:46Z
- **Completed:** 2026-05-14T11:53:28Z
- **Tasks:** 4 (M7, M10, M8+L12, M11) — все atomic commits
- **Files modified:** 7 sources + 4 new tests = 11 файлов

## Accomplishments

- **M7 — scenePhase consolidation:** заменены 3+1 параллельных Task'а в host's `.onChange(of: scenePhase)` ОДНИМ consolidated async методом `MainScreenViewModel.handleForegroundReentry()`. Sequential await через 3 hooks (runIsSupportedUpgrade через Task.detached background → tunnel.handleForeground → serverListVM.silentForegroundRefresh). DEC-06d-01 cold-start defer pattern preserved internally.
- **M10 — loadFromStore idempotency:** добавлен 100ms debounce + loadInProgress flag. `confirmDeleteSubscription` collapse-нут к ЕДИНСТВЕННОМУ tail-call (было 2 на cascade-delete normal path: early-exit branch + final).
- **M8 + L12 — validatedAt cache marker:** ConfigImporter записывает ISO8601 timestamp `configJSONValidatedAt` рядом с `configJSON`. BaseSingBoxTunnel.startTunnel skip-ает pre-expand R1/SEC-06 validate когда < 24h. **CRITICAL: post-expand validate (R10 defense-in-depth) ОСТАЁТСЯ unconditional — grep audit confirmed.**
- **M11 — applyVPNStatus explicit guard:** добавлен `guard state != .connecting else { return }` в `.connecting, .reasserting` branch перед existing nested switch. Documents idempotency intent + skip-ает banner mutation для already-connecting state. Outer-level Phase 6d 9b38796 lastAppliedVPNStatus dedupe preserved.

## Task Commits

Each task was committed atomically с per-commit regression gate:

1. **Task 1: M7 — Consolidate scenePhase=.active hooks** — `ca21fa9` (fix)
   - 5 файлов: MainScreenViewModel.swift +handleForegroundReentry, BBTB_iOSApp/BBTB_macOSApp single-Task handler, MainScreenView dup observer удалён, HandleForegroundReentryTests.swift (3 tests).
2. **Task 2: M10 — ServerListViewModel.loadFromStore idempotency + confirmDeleteSubscription collapse** — `6af41db` (fix)
   - 2 файла: ServerListViewModel.swift +loadInProgress/lastLoadAt guards + test seam, LoadFromStoreIdempotencyTests.swift (4 tests).
3. **Task 3: M8 + L12 — validatedAt cache marker (R10 preserved)** — `368c82f` (fix)
   - 3 файла: ConfigImporter.swift writes timestamp, BaseSingBoxTunnel.swift static helper + startTunnel guard, ValidatedAtGuardTests.swift (5 tests).
4. **Task 4: M11 — applyVPNStatus explicit early-return guard** — `4269570` (fix)
   - 2 файла: MainScreenViewModel.swift +inner guard, ApplyVPNStatusGuardTests.swift (3 tests).

**Plan metadata (this SUMMARY.md commit):** будет добавлен далее.

## Files Created/Modified

### Created (4 test files, 15 new tests)
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift` — 3 tests covering M7 invocation + isConnecting guard + serverListVM nil paths
- `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift` — 4 tests covering confirmDeleteSubscription single-call (normal + early-exit) + 100ms debounce
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift` — 5 tests covering within-24h skip + just-now skip + missing/malformed/stale fallthrough
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift` — 3 tests covering idempotency stability + .connecting→.connected transition + .connected→.connecting transition

### Modified (7 source files)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` — добавлен async `handleForegroundReentry()` (M7) + explicit early-return guard в applyVPNStatus(.connecting) (M11)
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` — single-Task scenePhase handler (M7)
- `BBTB/App/macOSApp/BBTB_macOSApp.swift` — mirror single-Task scenePhase handler (M7)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` — duplicate `.onChange(of: scenePhase)` для silentForegroundRefresh УДАЛЁН (M7)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` — loadInProgress/lastLoadAt guards + collapse confirmDeleteSubscription + test seam (M10)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — записывает `providerConfiguration["configJSONValidatedAt"]` (M8)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` — static helper `shouldSkipPreExpandValidate` + startTunnel pre-expand validate guard (M8/L12)

## Decisions Made

1. **Hook 2 в handleForegroundReentry — TunnelControlling protocol surface, не concrete TunnelController.** Original Plan говорил `await tunnelController?.handleForeground()` через computed property `tunnel as? TunnelController`. Однако MockTunnel в тестах не наследуется от TunnelController → tunnelController computed prop = nil → tunnel.handleForeground не вызывался. Решено использовать `await tunnel.handleForeground()` через protocol — production behavior идентичен (TunnelController сам реализует TunnelControlling.handleForeground), но тесты могут verify вызов через MockTunnel.

2. **Loadfromstore guards — loadInProgress + lastLoadAt оба, не один.** loadInProgress защищает от concurrent body execution (когда первый await ещё в полёте, второй вызов skip-ает); lastLoadAt — debounce окно для rapid sequential calls (даже после первого finish, в течение 100ms второй skip-ается). Два guards дают coverage обоих race patterns.

3. **`shouldSkipPreExpandValidate` как pure static helper.** Альтернатива — inline guard внутри startTunnel + spy-pattern на SingBoxConfigLoader. Pure helper выбран потому что: (а) тестируемый без NEPacketTunnelProvider lifecycle / device, (б) explicit signature `(providerConfiguration: [String: Any], now: Date) -> Bool` self-documenting, (в) cold-reboot / malformed timestamp / stale > 24h paths все coverable детерминистическими тестами.

4. **M11 — explicit guard + preservation existing nested switch.** Existing `case .empty, .error, .connecting: break` в nested switch остаётся (defensive для все state branches). Новый `guard state != .connecting else { return }` срабатывает РАНЬШЕ — skip-ает banner mutation для already-connecting state. Outer-level lastAppliedVPNStatus guard (Phase 6d 9b38796) НЕ удалён — он handles 8k duplicate event scenario.

## Deviations from Plan

None - plan executed exactly as written (с одним precise design choice: Hook 2 через TunnelControlling protocol вместо concrete TunnelController, описан выше в Decisions Made #1).

**Total deviations:** 0
**Impact on plan:** Plan executed as written; testability improvement в Hook 2 (protocol vs concrete) — это конкретное implementation decision внутри Plan'а action steps, не deviation.

## Issues Encountered

1. **Tuist xcworkspace отсутствует в worktree** (resolved automatically): worktree был свежий, BBTB/BBTB.xcworkspace отсутствовал. Решение: `tuist generate --no-open` в worktree BBTB/ перед первым xcodebuild gate. Time impact ~10 секунд.

2. **Vendored libbox.xcframework отсутствует в worktree** (resolved): `BBTB/Vendored/libbox.xcframework` — local-only binary (не в git, 0 byte .gitkeep). Решение: symlink из main repo в worktree (`ln -s /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework BBTB/Vendored/`). Time impact ~5 секунд.

3. **Test 2 M7 initial RED → state assertion regression**: applyVPNStatus(.connecting) когда state == .empty (no seeded servers) НЕ переводит state в .connecting (`case .empty: break` в nested switch). Решение: seed один supported ServerConfig + supportedCount=1 в test 2 чтобы refresh() переводил state в .idle → applyVPNStatus(.connecting) теперь срабатывает default branch. Self-discovered + fixed inline без external escalation.

## Regression Gate Evidence (per-commit, Hybrid Closure Rigor D-04)

| Task | swift test AppFeatures | swift test PacketTunnelKit | iOS xcodebuild | macOS xcodebuild |
|------|------------------------|----------------------------|----------------|-------------------|
| Baseline (HEAD pre-M7) | 133/133 PASS | 61/61 PASS | SUCCEEDED | SUCCEEDED |
| Post-M7 (ca21fa9) | 136/136 PASS | (no change) | SUCCEEDED | SUCCEEDED |
| Post-M10 (6af41db) | 140/140 PASS | (no change) | SUCCEEDED | SUCCEEDED |
| Post-M8+L12 (368c82f) | 140/140 PASS | 66/66 PASS | SUCCEEDED | SUCCEEDED |
| Post-M11 (4269570) | 143/143 PASS | 66/66 PASS | SUCCEEDED | SUCCEEDED |

Final: **AppFeatures 143/143 PASS + PacketTunnelKit 66/66 PASS + iOS + macOS BUILD SUCCEEDED.**

## D-09 Invariants Final Grep Audit (post-Wave 1)

| Check | Pattern | Pre-baseline | Post-Wave-1 | Status |
|-------|---------|--------------|-------------|--------|
| Forbidden symbols | `(ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay)` excl Tests/comments | ≤ 7 | 3 | ✅ |
| NEVPN observer queue=.main | `NEVPNStatusDidChange.*queue:.*\.main\b` | 0 | 0 | ✅ |
| #Predicate UUID? actual usage | `#Predicate.*UUID?` (3 hits — все comment-only references к invariant) | ≤ 1 | 3 (comments) | ✅ |
| applyVPNStatus single authority | `func applyVPNStatus` в MainScreenViewModel.swift | = 1 | 1 | ✅ |
| ExternalVPNStopMarker .consume() callers | `\.consume(` через grep (2 hits — оба doc-comments в ExternalVPNStopMarker.swift, 0 actual callers) | = 0 callers | 0 callers | ✅ |
| R18 sliding window | `toggle && intent` в OnDemandRulesBuilder.swift | = 2 | 2 | ✅ |
| R10 defense-in-depth | `SingBoxConfigLoader.validate` в BaseSingBoxTunnel.swift | ≥ 2 | 3 (pre guarded + post unconditional + 1 comment) | ✅ |
| M7 application | `viewModel.handleForegroundReentry` в iOS + macOS apps | (added) | 1 + 1 | ✅ |
| MainScreenView dup .onChange удалён | `silentForegroundRefresh` callsite в MainScreenView.swift | (target = 0 callsite) | 1 hit но это doc-comment, 0 actual callsites | ✅ |

## DEC-06d-01..06 Pattern Preservation

| DEC | Status | Evidence |
|-----|--------|----------|
| DEC-06d-01 (cold-start init defer) | ✅ Preserved | `Task.detached(priority: .background)` для runIsSupportedUpgrade — теперь внутри `handleForegroundReentry`, не убран. |
| DEC-06d-02 (XPC consolidation ≤ 2 trips) | ✅ Preserved | handleForeground = 1 XPC trip; handleForegroundReentry не добавляет новых trips. |
| DEC-06d-03 (event-driven status polling) | ✅ Preserved | M11 не добавляет Task.sleep; applyVPNStatus reactive driver unchanged. |
| DEC-06d-04 (bounded probe concurrency) | ✅ Preserved | maxConcurrentProbes = 8 не тронут; M10 loadFromStore не probe-style. |
| DEC-06d-05 (Apple-canonical options + ExternalVPNStopMarker) | ✅ Preserved | options["manualStart"] semantics unchanged; ExternalVPNStopMarker peek-only API preserved. |
| DEC-06d-06 (PerfSignposter spans) | ✅ Preserved | LibboxStart span в BaseSingBoxTunnel сохранён; ColdLaunch + PerfSignposter usage unchanged. |

## Next Phase Readiness

- **Wave 2 (06E-02-PLAN.md)** — 14+ LOW bundle commits + 3 trivial unused imports + final regression gate. Готов к спавну после merge этой Wave 1.
- **Wave 3 (06E-03-PLAN.md)** — Phase 6e closure (SUMMARY + wiki/log + state/roadmap/requirements sync + final D-09 grep audit). Зависит от Wave 2 completion.
- **No blockers** для Wave 2; D-09 invariants и DEC-06d patterns preserved через Wave 1; baseline 143/143 AppFeatures + 66/66 PacketTunnelKit обеспечивает чистый старт для bundles.

## Self-Check: PASSED

Verified all artifacts:
- Files created:
  - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift` — FOUND
  - `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift` — FOUND
  - `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift` — FOUND
  - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift` — FOUND
- Commits exist:
  - ca21fa9 (M7) — FOUND
  - 6af41db (M10) — FOUND
  - 368c82f (M8+L12) — FOUND
  - 4269570 (M11) — FOUND

---
*Phase: 06e-performance-audit-round-2-macos-uat-replay*
*Plan: 01 (Wave 1 — Atomic MEDIUM fixes M7+M10+M8/L12+M11)*
*Completed: 2026-05-14*
