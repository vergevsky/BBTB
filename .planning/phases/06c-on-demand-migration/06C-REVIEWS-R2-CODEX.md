# Phase 6c — Round 2 Review (Codex GPT-5.2)

**Date:** 2026-05-13
**Reviewer:** Codex GPT-5.2 (via delegator, advisory / read-only sandbox)
**Thread ID:** `019e2114-c21d-7331-a51c-bf49732437a5` (continuable via codex-reply for follow-ups)
**Verdict:** **REQUEST CHANGES** (1 PARTIAL blocker + 1 NEW BLOCKER)

**Note on save mechanics:** Codex requested permission to write this file itself but was denied due to read-only sandbox. The verdict and findings below are verbatim from Codex's response message; the orchestrator (Claude) saved this file on Codex's behalf so the Round 2 review chain has a durable artifact.

---

## Bottom-line verdict

**REQUEST CHANGES.** Two related issues:

1. **B-04 is only PARTIAL** — the `applyCurrentStateToCachedManager()` helper added in Plan 04 (after `connect()/disconnect()` intent changes) no-ops when `cachedManager == nil` and defers application "until next provisionTunnelProfile" (`06C-04-PLAN.md:383-386`).
2. **N-01 NEW BLOCKER** (introduced by the revision): the nil-cache path leaves a startup race where `userIntendedConnected=true` but `manager.isOnDemandEnabled` stays `false`. After the first Connect tap, on-demand may never get enabled until a subsequent import — meaning the very first Wi-Fi change after install would NOT auto-reconnect.

---

## Top evidence points (Codex's three)

1. **B-04 partial fix** (issue #1 above). Specific finding:
   > "Plan 04 adds `applyCurrentStateToCachedManager()` after `connect()/disconnect()` intent changes, but the helper no-ops when `cachedManager == nil` and says it will apply 'on next provisionTunnelProfile' (`06C-04-PLAN.md:383-386`). That leaves a startup/first-connect path where `userIntendedConnected=true` but `manager.isOnDemandEnabled` remains false."

2. **Core cross-plan fixes otherwise trace cleanly:**
   > "`ReconnectClock`/`TestClocks` extract-before-delete is present (`06C-03:578-666`, `06C-04:811-906`); `ManagerSelector.ourManagers` is specified across the 5 intended sites; direct `OnDemandRulesBuilder.apply(` callsites are absent from plans 02-04."

3. **Notification flow + cache-gate replacement verified:**
   > "`bbtbProvisionerDidSave` is coherently declared, posted, and observed across Plan 02/03/04, and the broken `lastKnownStatus != .invalid` proxy is replaced with `cachedManager?.isEnabled ?? false`."

---

## STILL-OPEN / NEW-BLOCKER items by ID

### B-04 — PARTIAL (originally CLOSED per REVISION-LOG, downgraded)

- **What's missing:** the `cachedManager` nil-path leaves on-demand off after the very first Connect tap. The user-facing symptom (phantom or absent auto-reconnect after first install + connect + network change) is exactly the bug class Phase 6c is meant to eliminate, just inverted.

### N-01 — NEW BLOCKER (Codex-named, introduced by the revision)

- **Description:** `cachedManager` may be `nil` at the moment of first user Connect tap because the revision's wiring populates the cache only on (a) `startReachability()` and (b) `bbtbProvisionerDidSave` observation. Neither path is guaranteed to have fired before the first Connect — `startReachability` runs at app startup but `loadAllFromPreferences()` may not return a manager if profile was just installed in a prior session and not yet observed.
- **Severity:** BLOCKER. Reproduction is the canonical first-time-user flow (install → import → connect → switch network).
- **Recommended fix path (per Codex):**
  - **Option A:** make `connect()/disconnect()` fall back to loading and selecting our manager (`ManagerSelector.ourManagers(from: loadAllFromPreferences())`) when `cachedManager == nil`, then apply current state, then populate cache.
  - **Option B:** guarantee and explicitly verify (in plan acceptance criteria) that cache population completes before any user-facing Connect path can be invoked. This may require an `await` chain at app startup, which is more invasive.
  - Option A is the lighter-touch fix and aligns better with the existing "lazy load on demand" pattern in TunnelController.

---

## Items confirmed CLOSED (per Codex spot-checks)

Codex did not enumerate every B/W explicitly, but its third evidence point and cross-plan trace confirms:

- B-01 / B-02 (ReconnectClock + TestClocks extract-before-delete): **CLOSED**
- B-03 (broken `lastKnownStatus != .invalid` proxy replaced): **CLOSED**
- B-06 / W-07 (ManagerSelector single helper at 5 sites): **CLOSED**
- W-04 (applyCurrentState single entry point, no direct `apply` callsites in consumers): **CLOSED**

Other B-XX and W-XX items not explicitly named by Codex but presumed traced cleanly given his "Core cross-plan fixes otherwise trace cleanly" statement. The orchestrator will cross-reference against the internal reviewer's per-item verdict to confirm.

---

## Continuation hooks

- **Codex thread:** `019e2114-c21d-7331-a51c-bf49732437a5` (continuable via `codex-reply` if Round 3 review needs Codex's confirmation that N-01 is closed).
- **No additional Codex turns spent in Round 2** — single-shot review.

---

## Orchestrator notes (Claude)

- Codex's N-01 finding aligns with the **brief's own §4 / B-04 discussion** which warned: "The moment user taps Connect, intent flips true — but on-demand is still off until the next provisioner call. Document this in Plan 03 Task 2: a Connect tap should be followed by a `refreshOnDemandFromCurrentState()` call on the cached manager."
- The brief tried to close this via the `applyCurrentStateToCachedManager()` wiring in Plan 04 Task 1, **but did not specify the nil-fallback behavior**. The planner implemented the wiring as a no-op when cache is nil, which is what created N-01.
- Round 3 fix is narrowly scoped: amend Plan 04 Task 1's `applyCurrentStateToCachedManager()` to load-on-demand when cache is nil (Option A), and re-spawn dual review. Other 17 items can stay frozen.
