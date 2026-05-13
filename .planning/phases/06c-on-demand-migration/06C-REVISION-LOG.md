# Phase 6c — Plan Revision Log (Round 1 → Round 2)

**Date:** 2026-05-13
**Revised by:** gsd-planner (revision-mode pass, single-shot)
**Source:** 06C-REVIEWS.md (10 blockers + 8 warnings) + 06C-PLANNER-REVISION-BRIEF.md

## Blocker resolutions

### B-01: ReconnectClock dependency survival
- **Status:** FIXED
- **Landed in:** Plan 03 new Task 2.5 (Step 0 pre-watchdog) — extracts `ReconnectClock` protocol + `SystemReconnectClock` struct from `ReconnectStateMachine.swift` into new file `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift`.
- **Cross-plan touch:** Plan 04 Task 3c acceptance updated — `ReconnectClock.swift` MUST NOT be deleted; `ReconnectStateMachine.swift` deletion no longer takes these types with it (they have been moved). Plan 03 Task 3 `<read_first>` updated: "use the extracted types, do NOT redeclare."
- **Files affected:**
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` (NEW, extracted from RSM)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` (protocol+struct removed, file still exists for parallel-run; deleted in Plan 04 Task 3c)
- **Change summary:** Extract-before-delete contract. Plan 03 acceptance grep verifies `protocol ReconnectClock` lives in new file (count 1) and is removed from RSM (count 0). `swift build` stays green throughout Wave 2/3.

### B-02: InstantReconnectClock test helper survival
- **Status:** FIXED
- **Landed in:** Plan 03 Task 2.5 (same pre-watchdog step as B-01) — extracts `InstantReconnectClock` private nested actor from `TunnelControllerStateTests.swift` into new shared file `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` as `internal` (not private).
- **Cross-plan touch:** Plan 04 Task 3c acceptance updated — `TestClocks.swift` MUST survive deletion of `TunnelControllerStateTests.swift`. Plan 03 Task 3 (Watchdog tests) `<read_first>` references the extracted file instead of the soon-to-be-deleted test file.
- **Files affected:**
  - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` (NEW)
  - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` (private declaration removed, file still exists during parallel-run window; deleted in Plan 04 Task 3c)
- **Change summary:** Shared `internal actor InstantReconnectClock` available to both `TunnelControllerStateTests` (during parallel-run) and `TunnelWatchdogTests`. Plan 04 Task 3c acceptance has explicit `! -f TunnelControllerStateTests.swift && -f TestClocks.swift` assertion.

### B-03: Watchdog manager.isEnabled gate proxy is broken
- **Status:** FIXED
- **Landed in:** Plan 04 Task 1 Step 2 + new Plan 04 Task 3a (slim TunnelController). Plan 03 Task 3 watchdog `<interfaces>` is unchanged (still takes `managerEnabled: Bool`); only the **caller** logic changes.
- **Cross-plan touch:** Plan 02 Task 2 — `provisionTunnelProfile` now posts `NSNotification.Name.bbtbProvisionerDidSave` after save; TunnelController observes this notification (lightweight, no XPC) and refreshes its `cachedManager` reference. Plan 03 Task 1 — `applyAutoReconnectToManager` does the same refresh via direct notification post inside the helper.
- **Files affected:**
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` — new stored property `cachedManager: NETunnelProviderManager?`; populated in `startReachability()` + after every notification-driven refresh.
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — posts `bbtbProvisionerDidSave` after `saveToPreferences()`/`loadFromPreferences()`.
  - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` — same notification post inside `applyAutoReconnectToManager`.
- **Change summary:** Option A (cached manager reference) selected per brief §3 fact #6 ("NEVPNConnection.manager status uncertain"). Watchdog gate now reads `cachedManager?.isEnabled ?? false` (conservative default — `nil` cache → skip failover). The broken `lastKnownStatus != .invalid` proxy is GONE; acceptance grep enforces this.

### B-04: Plan 02 parallel-run risks phantom initial connect
- **Status:** FIXED (Round 2 closed primary issue; Round 3 amendment closed N-01 nil-cache fallback)
- **Landed in:** Plan 01 Task 1 (API extension) + Plan 02 Task 2 (consumer) + Plan 03 Task 1 (toggle live-apply) + Plan 03 Task 2 (migration) + Plan 04 Task 1 (connect/disconnect wiring + Round 3 N-01 load-on-demand fallback).
- **Cross-plan touch:** API contract change to `OnDemandRulesBuilder`. Two new methods (`applyCurrentState`, `loadUserIntendedConnected`), one parameter rename (`autoReconnectEnabled` → `isOnDemandEnabled`). Per user decision in brief preamble: rename **AND** add the high-level method (closes B-04 + W-04 simultaneously).
- **Files affected:**
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` — 4 public methods (was 2).
  - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift` — 8 → 11 tests (8 renamed param + 3 new).
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — calls `OnDemandRulesBuilder.applyCurrentState(to:)` instead of the wrapper (W-04 closure).
  - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` — uses `applyCurrentState`.
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` — uses `applyCurrentState`.
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` — Plan 04 Task 1 Step 2: connect() / disconnect() additionally call `OnDemandRulesBuilder.applyCurrentState(to: cachedManager)` after setting user intent, so the moment intent flips, on-demand flag is brought in sync.
- **Change summary:** `applyCurrentState` is the single source of truth — computes `isOnDemandEnabled = autoReconnectEnabled && userIntendedConnected` and writes to manager. Phantom connect is now impossible at import time: import without prior Connect tap → intent=false → flag=false → OS does NOT auto-connect. The first Connect tap brings flag=true via the post-set call site in `TunnelController.connect()`.

### B-05: Migration flag set on transient failure
- **Status:** FIXED
- **Landed in:** Plan 03 Task 2 — explicit `do/catch` around `loadAllFromPreferences()` and around every `saveToPreferences()`; flag set ONLY on confirmed empty-managers or all-success paths.
- **Cross-plan touch:** Plan 04 Task 2 (UAT) — UAT-Task I covers first-launch-after-upgrade migration success. UAT-Task I is now a **hard blocker** per B-10.
- **Files affected:**
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift`
  - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift` (4 → 5 tests; added `test_runIfNeeded_loadAllThrows_doesNotSetFlag`)
- **Change summary:** Migration logic six-branch decision tree (see Plan 03 Task 2 behavior section). Flag stays `false` on: load-throws, save-throws-on-any-manager. Flag goes `true` on: already-migrated (idempotency), confirmed-empty-managers, our-managers-empty, all-saves-succeed. Test count delta +1.

### B-06: Multi-manager handling
- **Status:** FIXED
- **Landed in:** New file `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` created in **Plan 02 as Task 0** (same wave as the first consumer, ConfigImporter). Used in 5 sites across Plans 02/03/04.
- **Cross-plan touch:** All five `managers.first` callsites replaced with `ManagerSelector.ourManagers(from:).first` (or iteration for apply-to-all behavior in migration + toggle).
- **Files affected:**
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` (NEW)
  - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift` (NEW, 3 tests)
  - 5 consumer sites: ConfigImporter (P02 T2), SettingsViewModel (P03 T1), OnDemandMigrationTask (P03 T2), TunnelController cachedManager (P04 T1 / T3a), macOS handleWake (P04 T1 / T3a).
- **Change summary:** Single helper, hardcoded `Set<String>` of `["app.bbtb.client.ios.tunnel", "app.bbtb.client.macos.tunnel"]` as default (test fixtures use a different ID and naturally do not match — correct behavior since tests don't run real NEM extensions). Test target adds 3 unit tests for ManagerSelector. W-07 closed by this same fix.

### B-07: Plan 02 verify is silent false-GREEN
- **Status:** FIXED
- **Landed in:** Plan 02 Task 1.
- **Cross-plan touch:** none.
- **Files affected:** `06C-02-PLAN.md` only.
- **Change summary:** `<verify>` block on Task 1 (RED phase) deleted entirely. Task 2's `<verify>` covers the GREEN transition. Matches Plan 01 pattern where Task 1 RED has no verify. (Decision recorded per brief §B-07: chose deletion over the negated-verify alternative — it adds noise without information.)

### B-08: Acceptance grep matches doc-comments
- **Status:** FIXED
- **Landed in:** Plan 04 Task 3c (after the split — see W-01).
- **Cross-plan touch:** none.
- **Files affected:** `06C-04-PLAN.md` only.
- **Change summary:** Plan 04 Task 3c acceptance criteria now uses a comment-stripping `awk` pre-step before `grep -c`. Strips both `//` line comments and `/* */` block comments, then runs the symbol grep on the cleaned content. Expected count remains 0. The alternative (explicit Step 7 post-cleanup comment hygiene) is documented in the action but the acceptance step is the awk pipeline.

### B-09: SettingsFeature → MainScreenFeature dependency
- **Status:** FIXED
- **Landed in:** Plan 03 Task 1 Step 0 (the FIRST step of Task 1, before any code) — explicit `Package.swift` edit.
- **Cross-plan touch:** none (module dep is local).
- **Files affected:** `BBTB/Packages/AppFeatures/Package.swift` — SettingsFeature target dependencies now `["VPNCore", "DesignSystem", "Localization", "KillSwitch", "MainScreenFeature"]`.
- **Change summary:** Removed "if needed" language. Explicit diff in plan action. Acceptance grep: `grep -A 5 'name: "SettingsFeature"' Package.swift | grep -c "MainScreenFeature"` ≥ 1. Cycle safety verified per brief §3: `MainScreenFeature` source target deps (lines 27–37 of Package.swift) do NOT reference `SettingsFeature`; only the test target does, which is acceptable.

### B-10: Cleanup gate hard-blocker set
- **Status:** FIXED
- **Landed in:** Plan 04 Task 2 (`<how-to-verify>` decision matrix + `<resume-signal>` text).
- **Cross-plan touch:** Plan 05 — UAT.md table template MUST mark A/C/E/F/G/I rows as "critical / hard blocker". This is FLAGGED for Plan 05 implementation; Plan 05 file itself is NOT edited in this revision pass (per brief §2). The flag is captured under "Cross-plan touches Plan 05" below.
- **Files affected:** `06C-04-PLAN.md` only (this revision pass).
- **Change summary:** Hard-blocker set is `{A, C, E, F, G, I}`. Non-blocking: `{B, D, H}`. Decision matrix: "All 6 hard blockers PASS + 0–3 non-blocking failures → proceed cleanup; record non-blocking failures. Any hard blocker FAIL → STOP, do not proceed to Task 3, escalate to user." `<resume-signal>` text now references the new hard-blocker set explicitly.

## Warning resolutions

### W-01: Plan 04 Task 3 scope too large
- **Status:** FIXED
- **Landed in:** Plan 04 — Task 3 split into **Task 3a / Task 3b / Task 3c** per user decision in brief preamble.
- **Change summary:**
  - **Task 3a** — TunnelController slim-down (delete stored props/methods listed in original Task 3 Step 2; update `handleStatusChange` to use cached manager per B-03; preserve `startReachability`, macOS wake observer, connect/disconnect).
  - **Task 3b** — MainScreenViewModel banner state rewire + ReconnectBanner enum trim (`.connecting` added, `.retrying`/`.allFailed` removed) + add `setFailoverObserver` setter to TunnelWatchdog (the wiring deferred from Plan 03 Task 3). Includes W-02 audit grep step.
  - **Task 3c** — delete the 5 files (ReconnectStateMachine + tests + NetworkReachability + tests + TunnelControllerStateTests); create `TunnelControllerTests.swift` replacement (6 tests); update App entry points. Includes B-08 awk comment-stripping acceptance.
  Each sub-task has its own `<acceptance_criteria>` and `<verify>`. Final chain: 3a green → 3b green → 3c green → full `xcodebuild` green.

### W-02: Banner enum breaking change unaudited
- **Status:** FIXED
- **Landed in:** Plan 04 Task 3b — explicit audit step before mutating the enum.
- **Change summary:** Step 1 of Task 3b is `grep -rn 'case \.retrying\|case \.allFailed\|\.retrying(\|\.allFailed' BBTB/Packages/AppFeatures`. Every match must be updated as part of Step 2 (enum mutation). Acceptance: `grep -rc 'case \.retrying\|case \.allFailed' BBTB/Packages/AppFeatures` returns 0.

### W-03: applyAutoReconnectToManager runs on MainActor
- **Status:** FIXED
- **Landed in:** Plan 03 Task 1.
- **Change summary:** Option 1 selected — helper marked `nonisolated`. Caller invokes via `Task.detached { await viewModel.applyAutoReconnectToManager() }` from the `.onChange(of:)` modifier on the `Form`. Documented in Plan 03 Task 1 behavior section. Type system enforces off-main execution; UI thread does not block on XPC.

### W-04: OnDemand-config wrapper drift
- **Status:** FIXED via B-04
- **Landed in:** Closed by the same `applyCurrentState` single-entry-point introduced for B-04 in Plan 01 Task 1.
- **Change summary:** The `DefaultTunnelProvisioner.applyOnDemandConfiguration` wrapper from the original Plan 02 is DROPPED. All three consumer sites (provisioner, toggle, migration) call `OnDemandRulesBuilder.applyCurrentState(to:)` directly. Single source of truth restored; no drift possible.

### W-05: Adaptive debounce in watchdog
- **Status:** FIXED
- **Landed in:** Plan 03 Task 3 `<behavior>` and tests.
- **Change summary:** Debounce cancellation extended to `.connecting` AND `.reasserting` (was only `.connected`). New Test 9 (`test_debounceCancelledByReasserting`) added, mirror of existing Test 5 with `.reasserting` instead of `.connecting`. Total watchdog tests: 8 → 9.

### W-06: macOS wake nudge unconditional
- **Status:** FIXED
- **Landed in:** Plan 04 Task 1 Step 4 (initial wiring) and Plan 04 Task 3a (post-cleanup `handleWake` form).
- **Change summary:** `handleWake` body gets three guards:
  1. `guard manager.isEnabled else { return }` — profile disabled by another VPN.
  2. `guard manager.isOnDemandEnabled else { return }` — on-demand off (we chose manual mode).
  3. `guard OnDemandRulesBuilder.loadAutoReconnectEnabled() else { return }` — toggle off.
  Only after all three pass does `startVPNTunnel()` get called. No fight-back vector on wake.

### W-07: Shared manager-selection helper missing
- **Status:** FIXED via B-06
- **Landed in:** `ManagerSelector.swift` introduced in Plan 02 Task 0 closes both B-06 and W-07.
- **Change summary:** Single helper used across 5 sites; W-07 is a strict subset of B-06.

### W-08: Builder ordering documentation
- **Status:** FIXED
- **Landed in:** Plan 01 Task 1 action — doc-comments inside `OnDemandRulesBuilder.swift`.
- **Change summary:** `buildRules()` private function gets a Phase 8 extensibility contract doc-comment explaining "first-match-wins; future NEOnDemandRuleEvaluateConnection rules MUST be prepended; catch-all connect remains last." A one-line note in the file header also references the ordering contract.

## Cross-plan contracts verified

| Contract | Verified by reading |
|---|---|
| `ReconnectClock` extract-before-delete | Plan 03 Task 2.5 creates `ReconnectClock.swift`; Plan 04 Task 3c acceptance preserves it (`-f BBTB/.../ReconnectClock.swift`). |
| `InstantReconnectClock` test helper extract-before-delete | Plan 03 Task 2.5 creates `TestClocks.swift`; Plan 04 Task 3c acceptance preserves it. |
| `ManagerSelector.ourManagers(from:)` single helper used in 5 sites | Plan 02 Task 0 creates; Plan 02 Task 2, Plan 03 Task 1, Plan 03 Task 2, Plan 04 Task 1 (cachedManager), Plan 04 Task 3a (handleWake) consume. Acceptance greps per plan verify `ManagerSelector.ourManagers` appears at each callsite. |
| `OnDemandRulesBuilder.applyCurrentState` single entry point | Plan 01 Task 1 introduces; Plan 02 Task 2, Plan 03 Task 1, Plan 03 Task 2 consume. `OnDemandRulesBuilder.apply` direct-call is reserved for tests + internal use only. |
| `loadUserIntendedConnected` UserDefaults key | Plan 01 Task 1 reads `app.bbtb.userIntendedConnected`; TunnelController.swift `UserIntentStore` writes same key. Documented in both files' doc-comments. |
| TunnelController `cachedManager` refresh | Plan 04 Task 1 (B-03 fix) introduces property + `NSNotification.Name.bbtbProvisionerDidSave` observer. Plan 02 Task 2 posts the notification after `saveToPreferences()`. Plan 03 Task 1 toggle helper posts the same notification. |
| API param rename `autoReconnectEnabled` → `isOnDemandEnabled` | Plan 01 Task 1 (declaration + tests renamed); Plan 02 (no direct callsite — uses `applyCurrentState`); Plan 03 (no direct callsite — uses `applyCurrentState`). After revision, `grep -c "autoReconnectEnabled:" BBTB/Packages/AppFeatures` should only match the **method name** `loadAutoReconnectEnabled` and the UserDefaults key string — no `apply(...autoReconnectEnabled:...)` callsites. |
| Hard-blocker UAT scenarios A/C/E/F/G/I | Plan 04 Task 2 decision matrix uses this set verbatim. Plan 05 UAT.md table marks them critical (FLAGGED — Plan 05 unedited in this pass). |
| Banner enum trim | Plan 04 Task 3b audit grep BEFORE enum mutation catches all consumer sites; mutation occurs in Step 2; final acceptance grep returns 0 for removed cases. |
| TunnelWatchdog `setFailoverObserver` callback | Plan 04 Task 3b introduces (decided to place there, not in Plan 03 Task 3 — keeps Plan 03 strictly parallel-run with no API surface for the banner). Banner VM injects closure to update banner state. |

## Cross-plan touches Plan 05 (FLAGGED — not edited per brief §2)

Plan 05 should — when it is implemented — propagate the following from this revision:

1. **UAT.md table critical flags:** The 9 UAT scenarios A–I should be marked with a "Critical" or "Hard blocker" column. Hard-blocker set is `{A, C, E, F, G, I}` per B-10. This affects only the UAT.md table format in Plan 05 Task 1; no functional change.

No other Plan 05 changes are required by this revision pass.

## Test count delta

| Plan | Test File | Before | After | Delta | Notes |
|---|---|---|---|---|---|
| Plan 01 | OnDemandRulesBuilderTests | 8 | 11 | +3 | `applyCurrentState` (2 tests: intent OFF→false, both ON→true) + `loadUserIntendedConnected` (1 test) |
| Plan 02 | ConfigImporterOnDemandWiringTests | 4 | 4 | 0 | Wrapper helper dropped; tests now target `OnDemandRulesBuilder.applyCurrentState` directly (semantic rename, same count) |
| Plan 02 | ManagerSelectorTests (NEW) | 0 | 3 | +3 | empty input / mixed input / exact bundle ID match |
| Plan 03 Task 1 | SettingsViewModelAutoReconnectTests | 4 | 4 | 0 | No count change; behavior shifts to `applyCurrentState` + `nonisolated` |
| Plan 03 Task 2 | OnDemandMigrationTaskTests | 4 | 5 | +1 | `test_runIfNeeded_loadAllThrows_doesNotSetFlag` (B-05) |
| Plan 03 Task 3 | TunnelWatchdogTests | 8 | 9 | +1 | `test_debounceCancelledByReasserting` (W-05) |
| Plan 04 Task 3c | TunnelControllerTests (NEW) | 0 | 6 | +6 | replaces deleted TunnelControllerStateTests |
| **Totals** | | **28** | **42** | **+14** | aggregate new tests across Phase 6c |

## Items requiring user decision

None. All 18 review items addressed within the brief's constraints (including the two user-approved decisions: `applyCurrentState` API + Task 3 split into 3a/3b/3c). No D-decisions were changed.

## D-decision integrity

All 25 D-decisions (D-01..D-22 plus D-17b/c, D-24, etc. — full set as enumerated in 06C-CONTEXT.md) preserved verbatim. D-decisions whose **implementation guidance was expanded** (not changed) in this revision:

- **D-04 / D-06** (toggle + live-apply): intent gating added — semantic `isOnDemandEnabled = toggle && intent`. Toggle decision is unchanged; intent is a new gate that closes B-04.
- **D-08** (watchdog stable-session gate): cached `manager.isEnabled` (B-03) — gate semantics unchanged; the read mechanism changed from a broken proxy to a refreshed cache.
- **D-17b/c** (migration safety): transient-failure guarding added (B-05) — flag-on-success-only invariant strengthened.
- **D-11/D-12/D-13** (macOS wake): three-guard nudge (W-06) — adds defensive guards without changing the nudge primitive.

No D-decision text or intent was modified. All four expansions are mechanical implementation refinements that close review findings.

## Reviewer-facing summary

Round 1 produced REQUEST CHANGES on task-execution and cross-plan contract issues, not on architectural design. This revision pass closes all 18 findings: ten blockers and eight warnings. The cross-cutting fixes are (1) a renamed-and-expanded `OnDemandRulesBuilder` API with the single entry point `applyCurrentState(to:userDefaults:)` that gates `isOnDemandEnabled` on both the user toggle and `userIntendedConnected`, eliminating phantom-connect risk at import time (B-04 + W-04); (2) a new `ManagerSelector.ourManagers(from:)` helper used uniformly across five callsites to handle multi-manager cases (B-06 + W-07); (3) extraction of `ReconnectClock` and `InstantReconnectClock` to standalone files in Plan 03 Task 2.5 so Plan 04's deletion of `ReconnectStateMachine.swift` and `TunnelControllerStateTests.swift` no longer drops live dependencies (B-01 + B-02); (4) replacement of the broken `lastKnownStatus != .invalid` proxy with a cached `manager` reference refreshed via a new `bbtbProvisionerDidSave` notification, so the watchdog gate honors true `isEnabled` semantics during other-VPN fight-back (B-03); and (5) splitting Plan 04 Task 3 into 3a (slim) / 3b (banner rewire + watchdog observer) / 3c (delete + new test file) for context-budget safety (W-01). Plans 01 and 05 are minimally touched (Plan 01 gets the API extension; Plan 05 receives a flagged note for the UAT-table critical column — Plan 05 itself is unedited per the brief). Test count delta is +14 across the phase. To review fastest, read this log's "Cross-plan contracts verified" table top-to-bottom and spot-check each row against the cited PLAN files.

---

# Round 3 Amendment — N-01 nil-cache fallback

**Date:** 2026-05-13
**Trigger:** Codex GPT-5.2 Round 2 review (`06C-REVIEWS-R2-CODEX.md`) flagged **B-04 as PARTIAL** and named **N-01 as NEW BLOCKER**. Internal `gsd-plan-checker` Round 2 review approved the same plan, missing the runtime nil-cache scenario — the dual-review pipeline did its job by surfacing the gap.
**Scope:** Surgical patch — single helper body in Plan 04 Task 1 Step 2, plus two new acceptance criteria. No other plans modified. No cross-plan contracts affected.

## N-01: cachedManager nil-fallback (NEW BLOCKER → CLOSED)

- **Status:** CLOSED via Round 3 amendment.
- **Issue (Codex):** The `applyCurrentStateToCachedManager()` helper added in Round 2 had `guard let manager = cachedManager else { log.debug(...); return }`. On the very first user Connect tap after install, `cachedManager` may still be `nil` (the startup `refreshCachedManager()` may not yet have populated it, especially if the import happened in the prior session or the bbtbProvisionerDidSave observer hasn't fired). Effect: intent flips true, but `manager.isOnDemandEnabled` stays false until a subsequent provisioner save — so the FIRST Wi-Fi change after install would NOT auto-reconnect. This is the inverted twin of the phantom-connect bug Phase 6c eliminates.
- **Fix shape:** Inline load-on-demand. If `cachedManager == nil` at entry, call `refreshCachedManager()` first. Then `guard let manager` — if even after refresh nothing is found, log a `warning` (not debug) and return. The "no manager even after refresh" branch is genuinely unreachable in normal flow (Connect button is gated by import), so the warning serves as defensive observability.
- **Landed in:** `06C-04-PLAN.md` Task 1 Step 2 — `applyCurrentStateToCachedManager` body amended. Two new acceptance criteria added (lines verifying the `await refreshCachedManager` call AND the `log.warning` on the post-refresh nil branch).
- **Files affected:**
  - `06C-04-PLAN.md` only (single plan, single task, single helper).
- **Acceptance grep additions (Plan 04 Task 1):**
  - `awk '/private func applyCurrentStateToCachedManager/,/^[[:space:]]*}[[:space:]]*$/' TunnelController.swift | grep -c "await refreshCachedManager"` ≥ 1.
  - `awk '/private func applyCurrentStateToCachedManager/,/^[[:space:]]*}[[:space:]]*$/' TunnelController.swift | grep -c "log.warning.*no manager available even after refresh"` ≥ 1.
- **Cross-plan effects:** None. Helper is `private` inside `TunnelController`. No new files, no new module deps, no notification flow changes. The N-01 fix consumes the same `refreshCachedManager()` already introduced in Round 2 — no additional API surface.
- **Performance note:** First Connect tap now incurs 3 XPC trips instead of 2 (`loadAllFromPreferences` from `refreshCachedManager` + `saveToPreferences` + `loadFromPreferences` from the helper itself). Subsequent Connect taps remain 2 XPC. Acceptable cost — first-tap latency budget per Phase 6 UAT is generous (≤ 5s reconnect target; XPC trips are sub-100ms each on iOS 26).

## B-04 status update

The Round 2 listing of B-04 above is updated from "Status: FIXED" to "Status: FIXED (Round 2 closed primary issue; Round 3 amendment closed N-01 nil-cache fallback)". The original Round 2 wiring was correct in intent — Round 3 just completes the implementation by removing the nil-cache hole.

## Round 3 reviewer-facing summary

The dual-review pipeline did its job: `gsd-plan-checker` traced the contract correctly and approved on plan-quality grounds; Codex simulated the first-tap runtime path and caught a real semantic hole. The hole was narrowly scoped (one helper, one guard) and the fix is mechanical (5 lines added). After this amendment, the `applyCurrentStateToCachedManager` helper handles both happy-path (cache hit → apply directly) and cold-start (cache miss → refresh → apply) scenarios, and the post-refresh nil branch is `warning`-logged for observability. Re-review target: Codex re-spawn (using thread `019e2114-c21d-7331-a51c-bf49732437a5` for context continuity), confirming N-01 closure. No re-spawn of `gsd-plan-checker` necessary — the structural review hasn't changed.

---

# Round 4 UAT Hotfix — F-reverse fight-back protection

**Date:** 2026-05-13
**Trigger:** Plan 06C-04 Task 2 device UAT on iPhone iOS 26.5 — Test F-reverse FAILED. Scenario: BBTB connected → user taps Connect in another VPN app (Happ) → BBTB pulled the connection back to itself within ~1 second.
**Scope:** Surgical runtime patch in `TunnelController.handleStatusChange(_:)`. No plan-text change, no new files, no API change. ~31 lines added in one method.

## F-reverse: NEW BLOCKER discovered in UAT → CLOSED

- **Status:** FIXED via Round 4 hotfix (`fix(06c-04): fight-back protection on .disconnected — Round 4 F-reverse patch`, commit on main directly without worktree because patch is 1 file / 1 method).

- **Issue (UAT):** Round 2 B-03 fix assumed iOS flips `manager.isEnabled = false` when another VPN takes over, so the cached-manager gate would skip the watchdog failover. In practice on iOS 26 the assumption holds **eventually but not in real-time** — `cachedManager` is only refreshed when WE post `bbtbProvisionerDidSave` (our own saves). When an EXTERNAL VPN takes over, we get no such notification, so `cachedManager.isEnabled` remains stale-true. The watchdog gate sees `true` and may arm failover. More critically, even without our watchdog firing, **Apple's on-demand evaluator** re-evaluates `NEOnDemandRuleConnect(.any)` on every network interface change and re-activates BBTB on the OS side — kicking the other VPN out within ~1 second.

- **Fix shape:** in `handleStatusChange(_:)` at the top of the `.disconnected` branch (BEFORE the watchdog dispatch and before the switch), force-refresh `cachedManager` from preferences. If the refreshed manager reports `isEnabled == false` AND `isOnDemandEnabled == true`, proactively flip on-demand off + save. This releases iOS's auto-reconnect, allowing the other VPN to hold the connection. When the user later explicitly taps Connect in BBTB, `applyCurrentStateToCachedManager` in `connect()` re-establishes `isOnDemandEnabled = toggle && intent` (the existing B-04 wiring complement).

- **Files affected:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` only.

- **Performance cost:** +1 XPC trip per `.disconnected` event (rare event; well under iOS 26 Mach port pressure thresholds — `.disconnected` does not have the 40+/sec storm characteristic that motivated the original Phase 6 hotfix).

- **Test coverage:** No new unit test added — exercising this branch requires a non-trivial test seam refactor to inject a fake `NETunnelProviderManager` with controllable `isEnabled` + `isOnDemandEnabled` properties. AppFeatures suite remains 163/163 PASS (no regression). Verification is the manual UAT retest of Test F-reverse.

## Test E disposition: DEFERRED to Phase 7-8

UAT Test E (mid-session failover when server-side config disabled) did NOT trigger watchdog. Root cause investigation revealed: user disabled the inbound configuration in 3x-ui panel, not the sing-box process. The tunnel-level handshake stays alive; protocol-level traffic fails silently. `NEVPNStatus` never transitions to `.disconnected`, so the watchdog never sees a signal. This is NOT a watchdog bug — it is a feature gap that requires an **active liveness probe** (periodic HTTP probe to a known target, swap server after N consecutive failures). The user's production VPS serves dozens of active users, so we cannot test with full `pkill sing-box` either.

**Phase 6c scope:** the four bug classes Phase 6c targets are (1) phantom reconnect on fresh install / post-import, (2) XPC storm on iOS 26 / EXC_RESOURCE crashes, (3) fight-back with another VPN, (4) Mach port exhaustion. Server-side soft-kill failover was not in this list — the original plan's UAT-E description assumed `pkill -f sing-box` (a HARD kill which would surface `.disconnected`), but the user's production constraint blocks that test scenario.

**Action item for Phase 6c close-out:** document in 06C-UAT.md that Test E is N/A for Phase 6c, and add a new requirement (proposed `NET-12: active liveness probe with N-failure failover trigger`) to REQUIREMENTS.md and the Phase 7 backlog. The current watchdog correctly covers tunnel-level disconnect events; liveness probes for protocol-level failures are a separate concern.

## Round 4 reviewer-facing summary

Phase 6c's planning was thorough — 4 review rounds and triple-reviewer APPROVE before execute. UAT still surfaced one genuine runtime gap (F-reverse fight-back) that no static review could have caught without a hands-on test on iOS 26 with two VPN apps installed. The patch is mechanical: ~31 lines, one method, one branch. No cross-plan contracts touched. Test E result reclassified as out-of-scope rather than failure. With F-reverse fix in place, the only remaining hard blocker awaiting verification is G (30+ minute background, EXC_RESOURCE crash check) — running passively while the user retests F-reverse with this patch.
