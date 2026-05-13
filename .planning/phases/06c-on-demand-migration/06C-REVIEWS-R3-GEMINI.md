# Phase 6c — Plan Review (Round 3)

**Date:** 2026-05-13
**Reviewer:** Gemini 2.5 Pro
**Verdict:** APPROVE
**Scope Note:** This review was conducted as an independent third-party assessment of the Round 2 revisions and Round 3 amendment to the Phase 6c plans. It verifies the closure of 18 findings from Round 1 and assesses the introduction of any new issues.

---

## Section 1: Blocker Verification (10/10 CLOSED)

| ID | R1 Issue Summary | REVISION-LOG Claimed Landing | Verified-in-plan? | Verdict |
|---|---|---|---|---|
| B-01 | `ReconnectClock` dependency survival | Plan 03 new Task 2.5 | Yes | **CLOSED** |
| B-02 | `InstantReconnectClock` test helper survival | Plan 03 new Task 2.5 | Yes | **CLOSED** |
| B-03 | Watchdog `manager.isEnabled` gate broken | Plan 04 T1 S2 + T3a; Plan 02 T2 | Yes | **CLOSED** |
| B-04 | Plan 02 risks phantom initial connect | Plan 01 T1; Plan 02 T2; Plan 04 T1 | Yes | **CLOSED** |
| B-05 | Migration flag set on transient failure | Plan 03 T2 | Yes | **CLOSED** |
| B-06 | Multi-manager handling | Plan 02 new Task 0; 5 consumers | Yes | **CLOSED** |
| B-07 | Plan 02 verify is silent false-GREEN | Plan 02 T1 | Yes | **CLOSED** |
| B-08 | Acceptance grep matches doc-comments | Plan 04 T3c | Yes | **CLOSED** |
| B-09 | `SettingsFeature` → `MainScreenFeature` dep | Plan 03 T1 S0 | Yes | **CLOSED** |
| B-10 | Cleanup gate hard-blocker set | Plan 04 T2 | Yes | **CLOSED** |

## Section 2: Warning Verification (8/8 CLOSED)

| ID | R1 Issue Summary | REVISION-LOG Claimed Landing | Verified-in-plan? | Verdict |
|---|---|---|---|---|
| W-01 | Plan 04 Task 3 scope too large | Plan 04 T3 split into T3a/T3b/T3c | Yes | **CLOSED** |
| W-02 | Banner enum breaking change unaudited | Plan 04 T3b | Yes | **CLOSED** |
| W-03 | `applyAutoReconnectToManager` on MainActor | Plan 03 T1 | Yes | **CLOSED** |
| W-04 | OnDemand-config wrapper drift | Plan 01 T1 (via B-04 fix) | Yes | **CLOSED** |
| W-05 | Adaptive debounce in watchdog | Plan 03 T3 | Yes | **CLOSED** |
| W-06 | macOS wake nudge unconditional | Plan 04 T1 S4 + T3a | Yes | **CLOSED** |
| W-07 | Shared manager-selection helper missing | Plan 02 T0 (via B-06 fix) | Yes | **CLOSED** |
| W-08 | Builder ordering documentation | Plan 01 T1 | Yes | **CLOSED** |

## Section 3: Cross-Plan Contract Verification

1.  **`ReconnectClock` + `TestClocks` extract-before-delete**: **PASS**. Plan 03 Task 2.5 explicitly creates `ReconnectClock.swift` and `TestClocks.swift`. Plan 04 Task 3c acceptance criteria correctly asserts these files MUST survive the cleanup of their original source files.
2.  **`ManagerSelector.ourManagers(from:)` usage at 5 sites**: **PASS**. A search confirms the new helper from Plan 02 Task 0 is used in ConfigImporter (Plan 02), SettingsViewModel (Plan 03), OnDemandMigrationTask (Plan 03), and TunnelController (for `cachedManager` refresh and `handleWake`, both in Plan 04).
3.  **`OnDemandRulesBuilder.applyCurrentState` as sole entry point**: **PASS**. Consumers in Plans 02, 03, and 04 correctly call the high-level `applyCurrentState`. No sites call the lower-level `apply(to:isOnDemandEnabled:)` directly, restoring the single source of truth as intended by the B-04/W-04 fix.
4.  **`bbtbProvisionerDidSave` notification flow**: **PASS**. Plan 02 (ConfigImporter) and Plan 03 (Settings toggle helper, Migration task) correctly post the notification after saving. Plan 04 (TunnelController) correctly establishes a `NotificationCenter` observer in `startReachability` to call its `refreshCachedManager` helper, closing the loop for the B-03 fix.

## Section 4: New Issues Introduced by Revisions

No new **BLOCKER** or **MAJOR** issues were identified. The revisions are high-quality.

- **MINOR-01 (Informational):** In Plan 04 Task 1 Step 2, the `applyCurrentStateToCachedManager` helper's `catch` block for the `saveToPreferences` call correctly logs a warning but does not re-throw. This is acceptable behavior as the user's intent (`autoReconnectEnabled` toggle state) has already been persisted to UserDefaults by `@AppStorage`. The next full provisioning event will re-apply the correct state to the manager. The plan should perhaps explicitly state this "graceful degradation" rationale in a comment. This is a documentation nitpick, not a functional bug.

## Section 5: D-decision Integrity Check

**PASS**. The integrity of the 25 locked D-decisions from `06C-CONTEXT.md` is maintained. The revisions expand on the implementation guidance for decisions like D-04 (intent gating), D-08 (watchdog gate), D-17b/c (migration safety), and D-11/12/13 (macOS wake guards), but do so only to implement the fixes for the R1 findings. The core architectural intent of each decision remains unchanged. The file modification dates confirm `06C-CONTEXT.md` was not altered. `06C-05-PLAN.md` was also untouched.

## Section 6: Test Coverage Gap Analysis

**PASS**. The revision log documents a net increase of +14 tests. The new test names and their distribution align well with the fixes:
-   `OnDemandRulesBuilderTests`: +3 tests for the new `applyCurrentState` API (B-04).
-   `ManagerSelectorTests`: +3 new tests for the new helper (B-06/W-07).
-   `OnDemandMigrationTaskTests`: +1 test for the transient failure case (B-05).
-   `TunnelWatchdogTests`: +1 test for `.reasserting` cancellation (W-05).
-   `TunnelControllerTests`: +6 new tests to replace the deleted `TunnelControllerStateTests`.
The coverage appears sufficient for the new code paths introduced.

## Section 7: Round 3 Amendment Specific Verification

**PASS**. The amendment to the `applyCurrentStateToCachedManager` helper in Plan 04 Task 1 Step 2 correctly identifies and closes the nil-cache race condition (N-01).
-   The logic `if cachedManager == nil { await refreshCachedManager() }` correctly handles the cold-start scenario on the first user `Connect` tap.
-   The subsequent `guard let manager = cachedManager else { ... }` with a `log.warning` provides a defensive and observable failure path for the genuinely unreachable case where a manager doesn't exist even after a refresh.
-   This change does not introduce new race conditions; it safely resolves one by ensuring the manager state is loaded on-demand if not already cached.

## Section 8: Final Verdict

**VERDICT: APPROVE**

The Round 2 revisions and Round 3 amendment have successfully and robustly addressed all 10 blockers and 8 warnings from the Round 1 review. The resulting plans are clear, verifiable, and internally consistent. Cross-plan contracts are well-defined and correctly implemented. The introduction of `ManagerSelector`, the expanded `OnDemandRulesBuilder` API, and the `cachedManager` refresh pattern have significantly improved the plan's resilience. The plan is ready for execution.
