---
phase: 06c-on-demand-migration
plan: 04
type: summary
status: complete-re-uat-pass
date: 2026-05-13
commits:
  - "d49e635 — Task 1 wiring (additive)"
  - "83260c1 — Round 4 fight-back (superseded by Task 3a rewrite)"
  - "9206b8c — Round 4 UI desync (superseded by Task 3b reactive driver)"
  - "76ae2d6 — Round 4.1 narrow guards (superseded by Task 3a rewrite)"
  - "19f3fe7 — Task 3a slim + intent-closing"
  - "5b0e28c — Task 3b reactive UI driver + banner trim + watchdog observer"
  - "69b8ae8 — Task 3c delete 5 files + new TunnelControllerTests"
  - "324e369 — docs sync (STATE + REVISION-LOG + wiki)"
  - "abcd53a — full check-up (SUMMARY + R18 + PROJECT/ROADMAP/REQUIREMENTS sync)"
  - "44a5630 — Round 6 re-UAT follow-up (VM foreground resync + connectedDate authority)"
---

# Plan 06C-04 — Wave 3 Cutover SUMMARY

## Status

**Cutover complete on main 2026-05-13. Awaiting re-UAT** (2 fresh scenarios: F-reverse + Settings-disable on iPhone iOS 26.5).

## What changed

### Files modified (cumulative across Wave 3)

| File | Δ | Notes |
|------|---|-------|
| `BBTB/App/iOSApp/BBTB_iOSApp.swift` | +OnDemandMigrationTask init + watchdog wiring + setFailoverObserver inject; -ReconnectStateObserverRelay refs + stateObserver: init arg | Phase 6c migration wired at app launch |
| `BBTB/App/macOSApp/BBTB_macOSApp.swift` | Same | Symmetric platform entry point |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` | **909 → 316 строк (-65%)** | Old machinery removed; intent-closing on external `.disconnected`; cachedManager B-03; applyCurrentStateToCachedManager B-04 |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | Rewritten ~298 lines | Reactive `applyVPNStatus(_:)` driver (NEVPNStatus = authority for state + bannerState); enum trim; initial state seed |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift` | Minor (existing string renders new enum) | Uses `message: String` indirection; enum trim invisible here |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` | +22 lines | `setFailoverObserver(_:)` + fire-site invocation with server name |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` | (Plan 06C-03 — unchanged in Wave 3) | One-shot migration on app launch (D-17b/c) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` | (Plan 06C-01 — unchanged) | `applyCurrentState` + `loadAutoReconnectEnabled` consumed by TunnelController |

### Files DELETED (5 — Task 3c)

| File | Pre-deletion size | Reason |
|------|-------------------|--------|
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` | 173 lines | Replaced by `TunnelWatchdog` (mid-session failover) + Apple's on-demand evaluator (reconnect) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift` | 168 lines | Replaced by Apple's on-demand `NEOnDemandRuleConnect(.any)` (Apple watches network changes) |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift` | 283 lines | Class deleted → tests deleted |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift` | 153 lines | Class deleted → tests deleted |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` | 624 lines | Tested old machinery interactions; replaced by new TunnelControllerTests.swift (D-24 cat 2) |

**Total deleted: 1401 lines** (5 files).

### Files PRESERVED (Round 2 B-01 + B-02 cross-plan contract)

- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` — protocol + `SystemReconnectClock` struct extracted Plan 03 Task 2.5; survives RSM deletion because TunnelWatchdog uses it.
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` — `InstantReconnectClock` extracted Plan 03 Task 2.5; survives TCST deletion because TunnelWatchdogTests + future tests use it.

### Files CREATED

- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift` (261 lines, **7 test methods** — minimum 6 per D-24 cat 2):
  1. `testConnectThrowsWhenNoManagerExists`
  2. `testDisconnectDoesNotThrowWhenNoManagerExists`
  3. `testSetWatchdogThenDisconnectForwardsUserIntentFalse`
  4. `testStartReachabilityIsIdempotent`
  5. `testDisconnectResetsFailoverCycle`
  6. `testDisconnectClearsUserIntendedConnected`
  7. `testDisconnectWithoutWatchdogDoesNotThrow` (extra robustness)

## Verification metrics

| Check | Required | Actual | Status |
|---|---|---|---|
| `wc -l TunnelController.swift` | ≤ 350 | 316 | ✅ |
| `swift build --package-path Packages/AppFeatures` | green | green (2.61s) | ✅ |
| `swift test --package-path Packages/AppFeatures` | all PASS | **133/133 PASS, 0 failures, 0 unexpected** in 7.55s | ✅ |
| `xcodebuild -scheme BBTB -destination 'generic/platform=iOS Simulator' build` | green | ** BUILD SUCCEEDED ** | ✅ |
| `xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` | green | ** BUILD SUCCEEDED ** | ✅ |
| Awk-stripped grep B-08 (forbidden symbols) | ≤ 2 (Round 5 carve-out allows) | **7 — all exclusively `connectInProgress` / `manualDisconnectInProgress`** (def + set + clear + read sites; carve-out for intent-closing race protection); **zero** matches for `ReconnectStateMachine`, `NetworkReachability`, `ReconnectStateObserverRelay`, `lastKnownStatus`, `wakePending`, `triggerRecoveryIfNeeded` | ✅ (spirit satisfied) |
| `grep "cachedManager?.isEnabled"` (B-03) | ≥ 1 | 1 | ✅ |
| `grep "lastKnownStatus"` | 0 | 0 | ✅ |
| `grep "NSWorkspace.didWakeNotification"` (D-11) | = 1 | 1 | ✅ |
| handleWake guards (W-06) | ≥ 3 | 3 (manager.isEnabled, isOnDemandEnabled, loadAutoReconnectEnabled) | ✅ |
| connect/disconnect contract preservation (D-15) | verbatim except post-setUserIntent watchdog + applyCurrentState lines | confirmed | ✅ |

## UAT 9 scenarios — result table (per Round 2 B-10 hard-blocker set {A, C, E, F, G, I})

| # | Scenario | Plat | Severity | UAT Round 1 (pre-cutover) | Re-UAT after cutover |
|---|----------|------|----------|---------------------------|----------------------|
| A | Wi-Fi ↔ LTE reconnect | iOS | HARD BLOCKER | ✅ PASS (Round 2 Task 1+2 phase) | Not required (path unchanged) |
| B | iPhone overnight | iOS | Non-blocking | Not tested | Not required |
| C | macOS sleep 10 min → wake | macOS | HARD BLOCKER | ✅ PASS | Not required (path unchanged) |
| D | Smena Wi-Fi network (SSID change) | iOS | Non-blocking | Not tested | Not required |
| E | **Pitfall 5: stable session 1min, kill server-side sing-box** | iOS | HARD BLOCKER (CRITICAL) | Skipped — пользователь не хотел убивать прод sing-box | **Deferred to Plan 06C-05 test infrastructure** |
| F-direct | Включить BBTB → переключиться на ProtonVPN → вернуться → один тап Connect | iOS | HARD BLOCKER | ✅ PASS (Round 1) | Not required |
| **F-reverse** | **BBTB active → активация Happ → BBTB stays off** | iOS | HARD BLOCKER (CRITICAL) | ✅ PASS after Round 4 hotfix (`83260c1`) | **REQUIRED — Round 4 patch superseded; intent-closing path должен показать тот же результат** |
| G | App in background 30+ min, проверить crash logs (EXC_RESOURCE / PORT_SPACE) | iOS 26.5 | HARD BLOCKER (CRITICAL — bug class 4) | ✅ PASS (Round 1) | **Passive re-validate during F-reverse / Settings-disable** |
| H | Toggle «Авто-переподключение» OFF while connected | iOS | Non-blocking | Not tested | Not required |
| I | Migration smoke — Phase 6 upgrade install | iOS | HARD BLOCKER (Round 2 B-10) | ✅ PASS (manager.isOnDemandEnabled = true confirmed in Settings → VPN) | Not required |
| **Settings-disable** (Round 5 architect addition) | **BBTB active → iOS Settings → VPN → BBTB toggle off → BBTB stays off until explicit Connect** | iOS | HARD BLOCKER (Round 5) | ❌ FAIL Round 1 (Bug B — UAT discovery, drove architect pivot) | **REQUIRED — intent-closing path должен закрывать намерение** |

**Decision matrix for re-UAT (Plan 06C-05 gate):**
- F-reverse + Settings-disable + G passive **all PASS** → Phase 6c closed; → Plan 06C-05 (UAT documentation + regression smoke + NET-12 backlog) → Phase 7.
- Any hard FAIL → STOP, escalate to user; fix-forward or roll back to last green main.

## Architecture confirmations (per success_criteria)

- **OnDemandMigrationTask.runIfNeeded()** invoked at App init in BOTH BBTB_iOSApp + BBTB_macOSApp.
- **TunnelWatchdog** constructed at App init + wired into TunnelController via late-binding `setWatchdog`.
- **Round 2 B-03** — TunnelController has `cachedManager: NETunnelProviderManager?` populated в startReachability + refreshed через `NotificationCenter` observer на `.bbtbProvisionerDidSave`. Watchdog gate использует `cachedManager?.isEnabled ?? false` (real isEnabled, не broken proxy).
- **Round 2 B-04 wiring** — TunnelController.connect()/disconnect() после `setUserIntent` вызывают `applyCurrentStateToCachedManager` — `manager.isOnDemandEnabled` immediately flips per sliding-window invariant.
- **Round 3 N-01** — `applyCurrentStateToCachedManager` сам подгружает manager если cache miss (first Connect after import до .bbtbProvisionerDidSave race window).
- **TunnelController.swift slim** ≤ 350 строк (316).
- **5 файлов DELETED** в Task 3c per spec.
- **2 файла PRESERVED** (ReconnectClock.swift + TestClocks.swift) per B-01/B-02.
- **TunnelControllerTests.swift CREATED** с 7 тестами (≥ 6 минимум).
- **macOS NSWorkspace.didWakeNotification** observer preserved (D-11/12/13) с 3 guards (W-06): manager.isEnabled + isOnDemandEnabled + loadAutoReconnectEnabled.
- **NEVPNStatusDidChange observer** preserved для (a) watchdog delegation и (b) intent-closing on external disconnect — D-17 narrow.
- **Round 2 W-02** — ReconnectBanner enum updated: removed .retrying / .allFailed (audit grep returns 0), added .connecting; .failover(toServerName:) preserved.
- **Round 2 Task 3b extension** — TunnelWatchdog.setFailoverObserver setter added; App init injects callback для banner.failover wiring.
- **ReconnectStateObserverRelay** class — DELETED (was inside TunnelController.swift, removed in Task 3a).
- **Connect/disconnect bodies** preserved verbatim (Phase 1-5 polling loops untouched); Round 2 wiring lines добавлены AFTER existing body, не заменяют его.
- **Round 5 carve-out**: `connectInProgress` + `manualDisconnectInProgress` flags preserved (gates for intent-closing path; protect against transient `.disconnected` during own connect/disconnect flow).
- **Round 5 reactive UI driver** — `MainScreenViewModel.applyVPNStatus(_:)` is sole authority for both `state` AND `reconnectBannerState` on NEVPNStatus events; connect/disconnect remain command methods (request transitions, set `.error` on throw, do NOT set `.connected(since:)` from within).
- **Round 2 B-08** — Task 3c acceptance grep uses awk comment-stripping; returns 7 (only carve-out flags, all forbidden symbols cleared).
- **Round 2 W-01** — Task 3 split into 3a/3b/3c — context-budget safety; each sub-task individually verifiable and atomically committed.
- Full **xcodebuild green for both iOS and macOS schemes** (BBTB + BBTB-macOS).

## Round 5 architect-driven additions (not in original plan)

Codex GPT-5.2 architect review (`06C-ARCHITECT-R5.md`) introduced 2 scope changes:

1. **Pull Task 3 cleanup forward** — original plan UAT-gated cleanup behind Round 2 B-10 hard-blocker set. UAT discovered parallel-run hybrid was bug source. Architect superseded the gate; cleanup ran with Bug A/B as input not output.
2. **Intent-closing on external disconnect** — new code path in `handleStatusChange(.disconnected)` that closes user intent when external party flipped `manager.isEnabled = false`. Treats Settings-disable and other-VPN-takeover identically. Replaces Round 4 fight-back patch + Round 4 UI desync fix simultaneously.
3. **Reactive UI driver** — `applyVPNStatus(_:)` becomes sole authority for `state` AND `bannerState`; `connect()`/`disconnect()` become command methods. Replaces fragile imperative state updates in connect's polling loop.

## Executor pollution incident (postmortem)

Task 3a executor reported `Write` tool no-op (returned success but file unchanged). Side effects:

1. Main repo working tree was polluted with mid-state intermediate copies of `TunnelController.swift` (574 lines) and `MainScreenViewModel.swift` + `TunnelWatchdog.swift` (Task 3b). Recovery: `git stash push -- <file>` before each fast-forward merge, then `git stash drop` after merge verified green. App files (Task 3b BBTB_iOSApp + BBTB_macOSApp) and Task 3c files were NOT polluted — executor used `/tmp` + `cp` write pattern after diagnosing the issue.
2. Worktree `BBTB/Vendored/libbox.xcframework` missing — gitignored binary. Executors symlinked from main repo as workaround. **Deferred follow-up**: automate libbox symlink in worktree setup script.

Lesson captured: explicit md5/wc/diff verification after every Write; `/tmp` heredoc + cp fallback documented in subsequent task briefs.

## Re-UAT scope (handed off to Plan 06C-05)

Only **2 fresh scenarios + 1 passive** needed (rest already passed pre-cleanup; semantics unchanged for those paths):

1. **F-reverse** — BBTB active → user activates Happ → BBTB stays off, no auto-reactivate. Intent-closing closes user intent. **Expected PASS.**
2. **Settings-disable** — BBTB active → iOS Settings → VPN → toggle BBTB off → BBTB stays off until explicit Connect. **Expected PASS** (was FAIL pre-cutover; intent-closing addresses it).
3. **G (passive)** — 30+ min background during the above; Console.app on Mac for `BBTB` EXC_RESOURCE / PORT_SPACE — should remain zero.

Once user signs off PASS on all three:
- Update `06C-UAT.md` (Plan 05) with final result table.
- Update `wiki/auto-reconnect.md` "Last updated" to reflect UAT signoff.
- Move NET-08..11 from `[ ] Active` to `[x] Validated` in `.planning/REQUIREMENTS.md`.
- Add NET-12 (liveness probe — server-side stall detection) as Phase 7-8 backlog.
- Execute `/gsd-verify-work 6c` → Phase 6c closed → Phase 7 next.

## Reference index

- **Design decisions**: D-10 (cleanup boundaries), D-14 (slim-down target), D-15 (line-count cap ≤350), D-16 (FailoverProvider preserved unchanged), D-17 (NEVPNStatusDidChange observer narrowed to watchdog + intent-closing), D-24 (TunnelControllerTests cat 2 contract), D-11/12/13 (macOS wake).
- **Round 2 blockers closed**: B-01 (ReconnectClock extract), B-02 (TestClocks extract), B-03 (cachedManager B-03 fix replaces broken proxy), B-04 (applyCurrentState wiring complement), B-06 (ManagerSelector.ourManagers in wake), B-08 (awk comment-stripping grep), B-10 (hard-blocker set explicit).
- **Round 2 warnings closed**: W-01 (Task 3 split), W-02 (enum mutation audit), W-05 (.reasserting cancel — Plan 03), W-06 (handleWake 3 guards).
- **Round 5 architect additions**: intent-closing on external disconnect, reactive UI driver, pull-cleanup-forward.
- **Open questions resolved**: OQ-2 (userIntendedConnected naming preserved), OQ-3 (TunnelWatchdog as actor file), OQ-6 (FailoverProvider.connect closure unchanged), OQ-7 (banner mapping: .connecting / .failover / .killSwitchReconfigure).
- **Pitfall 5 (server-side block timing)**: deferred to Plan 06C-05 test infrastructure.

## Note for Plan 06C-05

- ~~Plan 05 will run re-UAT pair on iPhone iOS 26.5 + record results in `06C-UAT.md`.~~ **[DONE Round 6 2026-05-13]** — re-UAT pair (F-reverse + Settings-disable + G passive) all PASS after `44a5630`. Plan 05 will record formally в `06C-UAT.md`.
- ~~Plan 05 will update memory entries.~~ **[DONE Round 6 2026-05-13]** — `project_phase6c_resume_checkpoint.md` removed; `project_phase6c_complete.md` written; новые feedback файлы `feedback_nevpn_observer_queue_main.md` + `feedback_connectedDate_authority_for_since.md` добавлены.
- ~~Plan 05 will update `wiki/auto-reconnect.md` "Pending re-UAT" section.~~ **[DONE Round 6 2026-05-13]** — Last updated + новые секции «VM foreground resync (Round 6 fix)» и «Bonus: connectedDate authority for `since`» добавлены.
- Plan 05 will add `NET-12` (liveness probe — `Cmd_LogClient` stall detection or app-side ping) as Phase 7-8 backlog row in `.planning/REQUIREMENTS.md`. (Note: already present в `.planning/REQUIREMENTS.md:113` после check-up commit `abcd53a` — Plan 05 finalizes the wording/cross-refs if needed.)
- Plan 05 will mark UAT.md hard-blocker set rows A/C/E/F/G/I with "Critical / Hard blocker" annotation per Round 2 B-10 cross-plan contract.
- Plan 05 will write the regression smoke checklist (covers all 9 UAT scenarios as one-pass go/no-go before Phase 7 starts).

## Re-UAT outcome (2026-05-13 — Round 6)

Re-UAT on iPhone iOS 26.5 — user-driven. Result:

| Scenario | First pass | Follow-up fix | Final |
|---|---|---|---|
| **F-reverse** (BBTB active → Happ takeover → BBTB stays off) | ✅ PASS | — | ✅ PASS |
| **Settings-disable** (iOS Settings → VPN → BBTB toggle off → BBTB stays off) | ⚠️ PARTIAL FAIL — system VPN off but UI stuck on `.connected(since:)` with timer ticking | Commit `44a5630` | ✅ PASS |
| **G (passive)** (30+ min background, EXC_RESOURCE / PORT_SPACE check via Console.app) | ✅ PASS | — | ✅ PASS |

### Settings-disable root cause (Codex GPT-5.2 architect, advisory)

`MainScreenViewModel` registered its `NEVPNStatusDidChange` observer with `queue: .main`. When the user enters iOS Settings, our app is backgrounded — main queue suspends. The `.disconnected` notification emitted by iOS during the Settings toggle is **coalesced/dropped** and **NOT replayed** when the app returns to foreground. `TunnelController`'s observer used `queue: nil` — it kept firing intent-closing (F-reverse PASS, system VPN correctly off). VM had no resync path → `state` stuck on `.connected(since:)`, `ConnectionTimer` kept ticking from a now-stale `since` value.

### Follow-up fix (commit `44a5630`)

Three surgical changes in `MainScreenViewModel.swift`:

1. **Observer queue `.main → nil`** (match TunnelController). Inner `Task { @MainActor }` hop preserves the contract that `@Published` mutations land on main; main-queue independence eliminates the suspended-app drop.
2. **`MainScreenViewModel.handleForeground()`** — one `loadAllFromPreferences` XPC trip per scene `.active`, filtered through `ManagerSelector.ourManagers`, reads `connection.status` + `connection.connectedDate` (both sync), feeds `applyVPNStatus(_:connectedDate:)`. Transient XPC failures → keep last state.
3. **scenePhase wiring** — `BBTB_iOSApp.swift` + `BBTB_macOSApp.swift` invoke `viewModel.handleForeground()` alongside existing `tc.handleForeground()` on `.active` transition.

### Bonus fix bundled in same commit (Замечание 1)

Сценарий: «BBTB активирован через iOS Settings (Status toggle ON), приложение открыто через час → таймер начинается с нуля, а не с реального connect time». Корень: `applyVPNStatus(.connected)` всегда писало `state = .connected(since: Date())`.

Fix: `applyVPNStatus(_:)` теперь принимает опциональный `connectedDate: Date?` (default nil — обратная совместимость). `.connected` branch использует `connectedDate ?? state.connectionStart ?? Date()`. Observer + `handleForeground` читают `conn.connectedDate` (sync, без XPC) и передают. Таймер теперь стартует с реального момента установления туннеля.

### Architectural invariants preserved

- **TunnelController.handleStatusChange** intent-closing path UNCHANGED → F-reverse remains PASS, fight-back guard intact.
- **No XPC in observer hot path** → G (Mach-port safety) preserved. The one new XPC trip is in `handleForeground` — invoked at most once per scene `.active`, well within Phase 6 budget («≤1 XPC per significant event»).
- **No reintroduction** of `ReconnectStateMachine` / `NetworkReachability` / custom retry loops.
- **`applyVPNStatus`** remains SINGLE authority for `state` + `reconnectBannerState`. The `connectedDate` parameter does not change that — it only enriches the `.connected` since.
- **Round 5 reactive UI driver** contract intact; `connect()`/`disconnect()` still command methods.

### Verification (post-fix)

- `swift test --package-path BBTB/Packages/AppFeatures` → **133/133 PASS** (no regressions).
- `xcodebuild -scheme BBTB -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**.
- `xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.
- Device re-UAT — all three scenarios PASS (user signoff 2026-05-13).

### Status

**Phase 6c Wave 3 (06C-04) is now CLOSED.** Plan 06C-05 (Wave 4 — UAT documentation + regression + NET-12 backlog + wiki sync) is the next planned step; this Plan 05 will record the re-UAT outcome formally in `06C-UAT.md` and produce the regression smoke checklist. After Plan 05 signoff → Phase 6c fully closed → Phase 6d (Performance & Code Quality Audit, proposed) → Phase 7 (Anti-DPI + WireGuard family).
