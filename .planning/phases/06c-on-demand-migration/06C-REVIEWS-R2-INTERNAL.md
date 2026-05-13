# Phase 6c — Plan Reviews (Round 2 Internal)

**Date:** 2026-05-13
**Reviewer:** gsd-plan-checker (R2 trace-by-trace)
**Mode:** Verify Round 1 findings closed without regressions

---

## Section 1: Per-blocker verdict table

| ID | Round 1 issue | Fix landing claimed in REVISION-LOG | Verified in plan? | Verdict |
|----|---------------|--------------------------------------|-------------------|---------|
| B-01 | `ReconnectClock` extracted before RSM delete | Plan 03 Task 2.5 creates `ReconnectClock.swift`; Plan 04 Task 3c preserves it | ✅ Plan 03 lines 583-613 explicitly extract protocol+struct to new file. Plan 04 Task 3c line 834 PRESERVE clause + `test -f` acceptance line 890. Plan 03 acceptance lines 654-658 verify grep counts. | **CLOSED** |
| B-02 | `InstantReconnectClock` extracted before TCS delete | Plan 03 Task 2.5 creates `TestClocks.swift`; Plan 04 Task 3c preserves it | ✅ Plan 03 lines 621-637 move actor to `TestClocks.swift` as `internal`. Plan 04 line 835 + line 891 `test -f`. Plan 03 acceptance lines 658-660. | **CLOSED** |
| B-03 | Watchdog `manager.isEnabled` proxy is broken | Plan 04 Task 1 Step 2 adds cachedManager + bbtbProvisionerDidSave observer; broken proxy replaced | ✅ Plan 04 lines 338-365 declare property + refresh helper. handleStatusChange uses `cachedManager?.isEnabled ?? false` (lines 400-409). Acceptance line 485 verifies `lastKnownStatus != .invalid` grep returns 0. Plan 02 Task 2 posts notification (line 421); Plan 03 toggle helper posts (line 325); Plan 03 migration posts (line 553); Plan 04 observer (lines 358-364). | **CLOSED** |
| B-04 | Plan 02 parallel-run risks phantom initial connect | Plan 01 adds `applyCurrentState` + `loadUserIntendedConnected`; all consumers use applyCurrentState; intent default false | ✅ Plan 01 lines 143-165 declare 4 public methods. `loadUserIntendedConnected` defaults `false` (line 254). `applyCurrentState` computes `toggle && intent` (line 251). Plan 02 Task 2 consumer (line 413). Plan 03 toggle (line 322), migration (line 550). Plan 04 connect/disconnect (lines 368-379). Phantom mitigation explicit. Tests 9-11 in Plan 01. | **CLOSED** |
| B-05 | Migration flag set on transient failure | Plan 03 Task 2 explicit do/catch around loadAll AND saveToPreferences; flag set only on confirmed-success/empty | ✅ Plan 03 lines 489-503 describe six-branch decision tree. Branch 2 (loadAll throws) → NO flag. Branch 5 (any save throws) → NO flag. Test 5 (line 514) uses `loader:` seam to force throw. Acceptance line 566 `try? await` count == 0. Helper signature line 544 adds loader parameter. | **CLOSED** |
| B-06 | Multi-manager handling — single helper used in 5 sites | New ManagerSelector.swift in Plan 02 Task 0; used in 5 sites across P02/P03/P04 | ✅ Plan 02 Task 0 (lines 200-294) creates helper + 3 tests. 5 callsites verified: ConfigImporter (P02 line 402), SettingsViewModel (P03 line 320), OnDemandMigrationTask (P03 line 548), TunnelController.refreshCachedManager (P04 line 344), TunnelController.handleWake (P04 line 430). Plan 03 also documents B-06 line 314. | **CLOSED** |
| B-07 | Plan 02 verify is silent false-GREEN | Task 1 `<verify>` block removed; Task 2 verify covers GREEN | ✅ Plan 02 Task 1 (lines 296-374) has no `<verify>` block; only `<acceptance_criteria>`. Task 2 `<verify>` line 440 covers RED→GREEN. Decision documented line 64. | **CLOSED** |
| B-08 | Acceptance grep matches doc-comments | Plan 04 Task 3c uses awk comment-stripping before grep | ✅ Plan 04 lines 873-885 explicit awk pipeline pre-stripping `//` line comments AND `/* */` block comments. Acceptance line 912 reproduces awk pipeline. | **CLOSED** |
| B-09 | SettingsFeature → MainScreenFeature dependency | Plan 03 Task 1 Step 0 explicit Package.swift edit | ✅ Plan 03 lines 367-388 detail explicit edit + cycle safety check (`grep -A 10 'MainScreenFeature' must not contain SettingsFeature`). Acceptance lines 448-449 enforce both directions. | **CLOSED** |
| B-10 | Cleanup gate must elevate F and I to hard blocker | Plan 04 Task 2 `<how-to-verify>` + `<resume-signal>` updated | ✅ Plan 04 line 292 explicit hard-blocker set {A,C,E,F,G,I}. Decision matrix lines 528-531. `<resume-signal>` line 537-540 references new set. UAT table lines 282-290 mark each scenario with HARD BLOCKER tag. Plan 05 flagged for UAT table update (Plan 05 untouched per brief §2). | **CLOSED** |

---

## Section 2: Per-warning verdict table

| ID | Round 1 issue | Fix landing claimed in REVISION-LOG | Verified in plan? | Verdict |
|----|---------------|--------------------------------------|-------------------|---------|
| W-01 | Plan 04 Task 3 scope too large | Split into 3a / 3b / 3c with separate acceptance | ✅ Plan 04 Task 3a (line 549), 3b (line 695), 3c (line 811) each have own action+acceptance+verify. Final chain documented line 106. | **CLOSED** |
| W-02 | Banner enum breaking change unaudited | Task 3b Step 1 audits BEFORE enum mutation | ✅ Plan 04 lines 705-711 grep BEFORE Step 2 mutates. Step 3 (line 727) updates consumer sites. Acceptance lines 799-800 enforce 0 references post-mutation. | **CLOSED** |
| W-03 | applyAutoReconnectToManager on MainActor | Helper `nonisolated`; caller uses `Task.detached` | ✅ Plan 03 line 317 `nonisolated public func`. View modifier (line 355) uses `Task.detached`. Acceptance line 454 grep count ≥ 1 for `nonisolated`. | **CLOSED** |
| W-04 | OnDemand-config wrapper drift | Wrapper dropped; `applyCurrentState` single entry point | ✅ Plan 02 line 64 + line 188-191 drops `applyOnDemandConfiguration`. All consumers use `applyCurrentState`. Acceptance Plan 02 line 448 (`applyOnDemandConfiguration` returns 0), Plan 03 lines 453+564 direct `apply\b` returns 0. | **CLOSED** |
| W-05 | Adaptive debounce in watchdog | `.connecting` AND `.reasserting` cancel debounce; Test 9 added | ✅ Plan 03 line 732-736 explicit `.reasserting` parity. Test 9 (lines 779-783) mirrors Test 5 with `.reasserting`. Acceptance line 823 grep `case .reasserting` ≥ 1. Test count 8→9. | **CLOSED** |
| W-06 | macOS wake nudge unconditional | 3 guards in handleWake | ✅ Plan 04 lines 422-450 explicit 3 guards (isEnabled, isOnDemandEnabled, loadAutoReconnectEnabled). Acceptance line 488 grep ≥ 3 guards. Task 3a Step 6 (line 666) finalizes form. | **CLOSED** |
| W-07 | Shared manager-selection helper missing | Closed by B-06 | ✅ Same ManagerSelector helper closes W-07 (B-06 verified above). Plan 02 line 16 explicitly mentions both B-06 + W-07. | **CLOSED** |
| W-08 | Builder ordering documentation | `buildRules()` doc-comment + file header note | ✅ Plan 01 lines 254-263 detail explicit doc-comment with "first-match-wins; prepend; catch-all last". Acceptance line 291 grep `first-match-wins\|prepend` ≥ 1. | **CLOSED** |

---

## Section 3: Cross-plan contract verification

| Contract | Plan A reference | Plan B reference | Holds? |
|----------|------------------|------------------|--------|
| ReconnectClock extract-before-delete | P03 Task 2.5 lines 593-613 creates `ReconnectClock.swift` | P04 Task 3c line 834 PRESERVE; line 890 `test -f` | ✅ HOLDS |
| InstantReconnectClock extract-before-delete | P03 Task 2.5 lines 621-637 creates `TestClocks.swift` (internal) | P04 Task 3c line 835 PRESERVE; line 891 `test -f` | ✅ HOLDS |
| ManagerSelector used in 5 callsites | P02 Task 0 lines 200-294 creates helper | P02 Task 2 line 402 (ConfigImporter); P03 Task 1 line 320 (SettingsVM); P03 Task 2 line 548 (Migration); P04 Task 1 line 344 (refreshCachedManager); P04 Task 1 line 430 (handleWake) | ✅ HOLDS — 5 distinct callsites |
| applyCurrentState single entry point | P01 Task 1 lines 151-153 introduces | P02 line 413; P03 line 322; P03 line 550; P04 lines 373+379 (via helper). Direct `apply\b` callsites = 0 per grep guards. | ✅ HOLDS |
| `loadUserIntendedConnected` UserDefaults key | P01 reads `app.bbtb.userIntendedConnected` (line 254) | Same key written by `UserIntentStore` in TunnelController.swift (~line 73, verified via brief §3) | ✅ HOLDS — key string identical |
| cachedManager refresh notification flow | P02 Task 2 line 421 posts; P03 Task 1 line 325 posts; P03 Task 2 line 553 posts | P04 Task 1 lines 358-364 declares observer; refreshCachedManager called from observer (line 363) | ✅ HOLDS — 3 posters + 1 observer; helper `applyCurrentStateToCachedManager` deliberately skips post to avoid cycle (line 392) |
| API param rename `autoReconnectEnabled` → `isOnDemandEnabled` | P01 Task 1 line 146 renames | P02 + P03 use `applyCurrentState` so no direct param exposure. Acceptance P01 line 290 enforces `autoReconnectEnabled:` count == 0 (excluding method `loadAutoReconnectEnabled`) | ✅ HOLDS |
| Hard-blocker UAT set {A,C,E,F,G,I} | P04 Task 2 line 292 + 526-531 | Plan 05 explicitly flagged (P04 line 92-93, REVISION-LOG line 158, P05 NOT edited per brief §2) | ✅ HOLDS (flagged for future P05 edit) |
| Banner enum trim audit before mutation | P04 Task 3b Step 1 (lines 705-711) | P04 Task 3b Steps 2-3 (lines 714-735); acceptance lines 799-800 enforce post-mutation 0 | ✅ HOLDS |
| TunnelWatchdog `setFailoverObserver` | P04 Task 3b Step 4 (lines 737-754) introduces setter; P03 Task 3 explicitly defers per line 263-264 | P04 Task 3b Step 5 (lines 779-787) VM injects closure | ✅ HOLDS |

---

## Section 4: New issues introduced by the revision

### NEW-MINOR-1: Plan 03 Test 2 commentary is stale vs B-05 fix
**Severity:** MINOR
**Location:** Plan 03 line 508 (Test 2 description)
**Issue:** Test 2 description says: "loadAllFromPreferences НЕ throws в `swift test` — она возвращает []; ИЛИ throws — оба case'а: branch 3 OR branch 4 leads to flag=true". This commentary contradicts the new B-05 logic where Branch 2 (loadAll throws) → flag stays FALSE. If `loadAllFromPreferences` actually throws in test env, Test 2 assertion `flag == true` would fail.
**Mitigation:** Test 5 explicitly covers the throws case with `loader:` seam, so the throws-path coverage exists. Test 2 likely relies on test env returning `[]` (branch 3) in practice. Real-world existing test usage in `TunnelControllerStateTests.swift` is consistent with empty-return behavior.
**Severity rationale:** Test commentary is misleading but the actual test assertion likely passes in practice. Worth fixing for clarity. Not a blocker.

### NEW-MINOR-2: connect()/disconnect() add 2 XPC trips on every tap
**Severity:** MINOR
**Location:** Plan 04 lines 369-379 (connect/disconnect wiring) + lines 383-397 (`applyCurrentStateToCachedManager` helper)
**Issue:** Round 2 B-04 wiring adds `await applyCurrentStateToCachedManager()` AFTER `setUserIntendedConnected(true)` but BEFORE `manager.connection.startVPNTunnel()` (verified line 264 → 279 in actual code). Helper performs `saveToPreferences()` + `loadFromPreferences()` (2 XPC trips per tap). This was per-brief and is functionally correct, but represents a NEW performance characteristic: every connect tap incurs 2 additional XPC roundtrips before the tunnel actually starts.
**Mitigation:** Per actor isolation, these trips do not block MainActor. Connect timeouts in Phase 1-5 polling loops (existing) are generous; 2 XPC trips should not exceed those.
**Severity rationale:** Per-brief instruction; not unintended; not a regression in correctness. Worth a UAT observation rather than a blocker. Plan acknowledges this is the expected wiring complement.

### NEW-MINOR-3: handleStatusChange location ambiguity post-3a
**Severity:** MINOR
**Location:** Plan 04 Task 1 Step 2 (line 400-409) vs Task 3a Step 3 (lines 600-610)
**Issue:** Task 1 adds the new `managerEnabled = cachedManager?.isEnabled ?? false` line "AFTER existing branches (или вместо обработки в Task 3a slim)" (line 400). Task 3a Step 3 then simplifies `handleStatusChange` body to ONLY delegate to watchdog (lines 604-609). During Task 1's parallel-run window, both old recovery branches AND watchdog delegation may co-exist in `handleStatusChange`. The plan acknowledges this is intentional but does not specify whether old recovery branches CONTINUE to fire failover (race with watchdog) or are guarded by some flag.
**Mitigation:** This is exactly the "parallel-run double-trigger race" already acknowledged as Pitfall 5 / T-06C-02-01 (accepted threat). UAT-Task E validates whether the race is user-visible.
**Severity rationale:** Already documented as accepted threat; planner explicit. Not a new issue per se.

### No NEW-BLOCKER issues identified.

---

## Section 5: D-decision integrity

CONTEXT.md not modified (verified by git status: untracked = REVISION-LOG + BRIEF; modified = plans 01-04 only). Git log shows last CONTEXT.md commit is 391cc33 (before review cycle). File mtime May 13 13:04 < plan edit mtimes May 13 14:02-14:20. ✅ CONTEXT.md INTACT.

Spot-check D-decisions per request:

- **D-04 (toggle ON default + Auto-reconnect setting)** — Plan 03 Task 1 line 301 sets `@AppStorage` default `true`; live-apply uses `applyCurrentState`. **Decision text unchanged; implementation extended with intent-gate composition (gate = toggle && intent), not changed.** ✅ INTACT.

- **D-08 (watchdog stable-session gate with manager.isEnabled)** — Plan 03 Task 3 line 691 watchdog API unchanged: takes `managerEnabled: Bool` parameter. Plan 04 Task 1 changes the CALLER's source from broken proxy to `cachedManager?.isEnabled` — **decision intent (read the real isEnabled) preserved; only mechanism changed**. ✅ INTACT.

- **D-11/D-12/D-13 (macOS wake observer + idempotent nudge)** — Plan 04 Task 1 Step 4 (lines 422-450) preserves `NSWorkspace.didWakeNotification` observer; `startVPNTunnel()` remains the nudge primitive. **3 guards ADDED (W-06) without changing the nudge itself.** ✅ INTACT.

- **D-17b/c (migration safety net)** — Plan 03 Task 2 line 482-503 preserves migration intent (one-shot, idempotent, applied to existing managers). **B-05 strengthens flag-on-success-only invariant; does not change the migration goal.** ✅ INTACT.

REVISION-LOG explicitly states all 25 D-decisions preserved verbatim (line 187-196). My spot checks confirm: implementation guidance was expanded (intent gating, real isEnabled read, 3 guards, transient-failure guard) but no D-decision text or intent was changed.

---

## Section 6: Final verdict and severity

**Verdict:** **APPROVE**

All 10 blockers (B-01..B-10) are CLOSED. All 8 warnings (W-01..W-08) are CLOSED. All 10 cross-plan contract rows in REVISION-LOG verified by tracing both plans. CONTEXT.md is intact (git + mtime). D-decision intent preserved across all 4 spot checks.

Three NEW-MINOR findings (no NEW-BLOCKER, no NEW-MAJOR) — all are documentation/UX clarity issues that do not block execution:
- NEW-MINOR-1: Plan 03 Test 2 commentary contradicts B-05 fix; assertion likely still holds in practice but commentary is stale.
- NEW-MINOR-2: connect/disconnect adds 2 XPC trips per tap (per-brief; UAT will reveal whether observable).
- NEW-MINOR-3: parallel-run window has both old recovery branches + new watchdog delegation in handleStatusChange — already documented as accepted threat (Pitfall 5).

Recommendation: Proceed to `/gsd-execute-phase 6c`. The three minor findings can be addressed during execution if any UAT signal surfaces, or in a follow-up tidy commit; they are not blocking.

