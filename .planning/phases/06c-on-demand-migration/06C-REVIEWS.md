# Phase 6c — Plan Reviews (Round 1)

**Date:** 2026-05-13
**Status:** REQUEST CHANGES — planner revision required before execution
**Reviewers:** gsd-plan-checker (internal) + Codex gpt-5.2 (external, via delegator)

Both reviewers independently arrived at **REQUEST CHANGES** with overlapping critical findings. Architectural design is sound — revisions are at task-execution and cross-plan contract level.

---

## Blockers (must fix before execute) — 10 total

### B-01: ReconnectClock dependency survival
**Plans:** 06C-03 Task 3, 06C-04 Task 3
**Issue:** `ReconnectClock` + `SystemReconnectClock` defined inside `ReconnectStateMachine.swift` (line 36, 41). Plan 04 deletes that file. TunnelWatchdog (Plan 03) declares `clock: ReconnectClock = SystemReconnectClock()`. After cleanup → `cannot find type 'ReconnectClock' in scope`.
**Fix:** Pre-deletion task to extract `ReconnectClock` + `SystemReconnectClock` to new file `MainScreenFeature/ReconnectClock.swift`. Survives `ReconnectStateMachine.swift` deletion.

### B-02: InstantReconnectClock test helper survival
**Plans:** 06C-03 Task 3, 06C-04 Task 3
**Issue:** `InstantReconnectClock` is a private nested actor in `TunnelControllerStateTests.swift` (line 57). Plan 04 deletes that file. New TunnelWatchdogTests need it.
**Fix:** Plan 03 Task 3 must extract `InstantReconnectClock` to shared `MainScreenFeatureTests/TestClocks.swift` before Plan 04 cleanup runs.

### B-03: Watchdog manager.isEnabled gate is broken
**Plans:** 06C-03, 06C-04 Task 1 Step 2
**Issue:** Plan uses `lastKnownStatus != .invalid` as proxy for `manager.isEnabled`. This is **wrong** for D-08 semantics: when another VPN app activates, our `manager.isEnabled` flips to `false` but `connection.status` stays `.disconnected` (NOT `.invalid`). The proxy lets watchdog fire failover during fight-back — exactly the bug we are fixing.
**Fix:** Read `manager.isEnabled` directly. Either pass `manager` via the cached reference held in TunnelController OR via `notification.object as? NEVPNConnection` and its back-pointer to manager. Both XPC-free.
**Severity:** CRITICAL ARCHITECTURAL.

### B-04: Plan 02 parallel-run risks phantom initial connect (Codex finding)
**Plans:** 06C-02
**Issue:** Plan describes Wave 1 as "no behavior change", but setting `isOnDemandEnabled = true` + `NEOnDemandRuleConnect(.any)` at import time can cause **initial auto-connect** when user has never tapped Connect. Recreates the Phase 6 phantom-reconnect bug class we just killed, now OS-driven.
**Fix:** Gate `manager.isOnDemandEnabled` by user intent (`userIntendedConnected` flag persisted in UserDefaults). Toggle controls whether intent IMPLIES on-demand. Intent itself comes from explicit Connect/Disconnect.
**Severity:** CRITICAL.

### B-05: Migration flag set on transient failure (Codex finding)
**Plans:** 06C-03 Task 2 OnDemandMigrationTask
**Issue:** Plan sets `app.bbtb.autoReconnectMigratedV6c = true` when `loadAllFromPreferences()` throws (treated as "fresh install proxy"). On transient XPC failure this permanently skips migration → user stuck with `isOnDemandEnabled=false` forever.
**Fix:** On throw, **do not set** the migrated flag. Only set it for `managers.isEmpty` (confirmed no profile) OR after successful save+reload.
**Severity:** CRITICAL.

### B-06: Multi-manager handling (Codex finding)
**Plans:** 06C-03 (migration, toggle, watchdog)
**Issue:** All sites use `managers.first`. Users can have multiple `NETunnelProviderManager` instances (after re-imports or legacy installs). May migrate/apply to wrong one.
**Fix:** Select managers by `providerBundleIdentifier` matching our known identifiers (`app.bbtb.client.ios.tunnel` / `app.bbtb.client.macos.tunnel`). Apply to all matching. Share via single helper across migration + toggle + watchdog.

### B-07: Plan 02 verify is silent false-GREEN
**Plans:** 06C-02 Task 1
**Issue:** `swift test --filter ... 2>&1 | grep -E "error|fail" | head -5` always exits 0 due to pipe semantics. Test never actually validates anything.
**Fix:** Replace with `! swift test --filter ConfigImporterOnDemandWiringTests` (expects failure for RED phase) OR remove the Task 1 verify (Task 2 validates RED→GREEN).

### B-08: Acceptance grep for deleted symbols matches doc-comments
**Plans:** 06C-04 Task 3
**Issue:** `grep -c "ReconnectStateMachine|...|triggerRecoveryIfNeeded|wakePending|..." TunnelController.swift returns 0` will fail because the slim-down code may still have comments mentioning these symbols.
**Fix:** Either match only declarations (`grep -cE "^[[:space:]]*(var|let|func|private|internal|public).*(symbol)"`) OR add explicit step to strip comments mentioning deleted symbols.

### B-09: SettingsFeature → MainScreenFeature dependency
**Plans:** 06C-03 Task 1
**Issue:** Plan says "import MainScreenFeature if needed" — non-deterministic. SettingsFeature currently doesn't depend on MainScreenFeature. Toggle helper needs `OnDemandRulesBuilder` (lives in MainScreenFeature) → dependency must be added explicitly.
**Fix:** Explicit Package.swift edit step with diff. Acceptance grep: `grep -c "MainScreenFeature" BBTB/Packages/AppFeatures/Package.swift` ≥ 2.
**Note:** Verify no cycle — MainScreenFeature currently does NOT depend on SettingsFeature, so reverse is safe.

### B-10: Cleanup gate should treat F (other-VPN) and I (migration) as HARD blockers (Codex finding)
**Plans:** 06C-04 Task 2 UAT checkpoint
**Issue:** Cleanup gate treats E/G as critical. But F (fight-with-other-VPN) is explicitly one of the 4 bug classes we eliminate, and I (upgrade migration) is the new D-17b/c safety net. If they fail, deleting the old machinery loses our rollback path.
**Fix:** Elevate F + I to "STOP cleanup if fail", same severity as A/C/E/G.

---

## Warnings (should fix) — 8 total

### W-01: Plan 04 Task 3 scope too large (gsd-checker)
Task 3 alone modifies 6+ files (TunnelController, MainScreenViewModel, ReconnectBanner, both App entry points) + creates TunnelControllerTests + deletes 5 files. Split into 3a/3b/3c for context safety.

### W-02: Banner enum breaking change unaudited (gsd-checker)
Plan 04 Task 3 removes `.retrying` and `.allFailed` from `ReconnectBannerState` but no consumer audit. Add: `grep -rn 'case .retrying\|case .allFailed' BBTB/Packages/AppFeatures` and update every match.

### W-03: applyAutoReconnectToManager runs on MainActor (gsd-checker)
`viewModel.applyAutoReconnectToManager` triggers XPC via `loadAllFromPreferences + saveToPreferences` while @MainActor → blocks UI thread on slow devices. KillSwitch toggle deliberately deferred application; this plan applies live. Either mark `nonisolated` or detach.

### W-04: OnDemand-config wrapper drift from "single source of truth" (gsd-checker)
Plan 02 introduces `DefaultTunnelProvisioner.applyOnDemandConfiguration` helper. Plan 03 inlines `OnDemandRulesBuilder.apply` separately. Violates D-03 spirit. Either export wrapper as public + use everywhere, OR drop wrapper.

### W-05: Adaptive debounce in watchdog (Codex)
Fixed 3s debounce may be insufficient across iOS/macOS quirks. Make adaptive: cancel-on-`.connecting`/`.reasserting`/`.connected`. Consider "disable on-demand during swap" pattern from RESEARCH Pitfall 5.

### W-06: macOS wake nudge unconditional (Codex)
Plan 04 wake nudge calls `startVPNTunnel()` on `managers.first` without checking `isEnabled` / `isOnDemandEnabled`. Can fight back if user disabled. Gate wake nudge on both flags + auto-reconnect toggle.

### W-07: Shared manager-selection helper missing (Codex)
Live-apply + migration + watchdog independently call `loadAllFromPreferences` and pick `managers.first`. Share via single helper (also addresses B-06).

### W-08: Builder ordering documentation (Codex)
OnDemandRulesBuilder should document ordering guarantee: "evaluate rules first, connect-any last" for when Phase 8 prepends `NEEvaluateConnectionRule`. Reserve `buildRules()` internal hook explicitly.

---

## Coverage Assessment

| Phase 6c SC | Status |
|---|---|
| SC1 — Wi-Fi↔LTE | Covered (Plan 02 wiring + Wave 3 UAT-A) |
| SC2 — macOS wake | Covered (Plan 04 + UAT-C) |
| SC3 — No fight-back | Covered, but B-10 elevates UAT-F to hard blocker |
| SC4 — Zero EXC_RESOURCE | Covered (no observer hot path) |
| SC5 — Initial-connect failover | Covered (FailoverProvider untouched) |
| SC6 — Tests adapted | Covered (8+4+16+6 = 34 new tests) |
| SC7 — Phase 1-6 regression | Covered (Plan 05) |

All NET-08..11 covered. All 10 RESEARCH pitfalls referenced. All 7 open questions resolved.

---

## Verdict

**REQUEST CHANGES — return to planner with revisions.**

**Effort estimate:** Short (1-4h) — revisions touch Plans 02, 03, 04. Plans 01, 05 unchanged.

**Re-spawn target:** planner agent (agentId `ae1d96c65245a8a4f` from initial spawn — can continue via SendMessage).

---

## Source Material

- gsd-plan-checker full report: above synthesis is verbatim digest
- Codex review thread: `019e2097-904f-7c60-a3c4-e14a55b7759a` (continuable via codex-reply)
- Reference: `06C-CONTEXT.md` (25 D-decisions), `06C-RESEARCH.md` (10 pitfalls, 7 OQ)
