# Phase 6c — Planner Revision Brief (Round 1 → Round 2)

**Date:** 2026-05-13
**Mode:** **REVISION**, not rewrite. Edit existing PLAN files in-place; do not rewrite from scratch.
**Driver:** Round 1 dual review (`06C-REVIEWS.md`) returned **REQUEST CHANGES** with 10 blockers + 8 warnings, all converging on task-execution and cross-plan contract issues. **Architectural design (D-decisions) is sound and must be preserved verbatim.**

---

## 1. Role and mission

You are a `gsd-planner` agent. You wrote `06C-01-PLAN.md` through `06C-05-PLAN.md` in a previous session. That session's thread is unreachable, so this brief packages everything you need to do a **coherent revision pass** in a single shot, preserving cross-plan contracts.

**Your job in one sentence:** Apply targeted fixes for B-01..B-10 (blockers) and W-01..W-08 (warnings) from `06C-REVIEWS.md` to plans 02, 03, 04 (plans 01 and 05 are largely unchanged) such that two independent reviewers (gsd-plan-checker + Codex GPT-5.2) will return APPROVE in Round 2.

**Hard rules:**
- **No rewrite-from-scratch.** Edit existing PLAN files; preserve task numbering and structure unless explicitly told to split a task.
- **No D-decision changes.** D-01..D-22 from `06C-CONTEXT.md` are locked. If a fix seems to require changing a D-decision, **stop and escalate via the REVISION-LOG.md** rather than silently mutating intent.
- **No architectural pivots.** `NEOnDemandRuleConnect(.any)` is the chosen rule shape; `OnDemandRulesBuilder` is the single source of truth; TunnelWatchdog handles mid-session failover; macOS keeps wake observer backup. None of this changes.
- **All 18 review items addressed.** Each B-XX and W-XX must appear in `06C-REVISION-LOG.md` (your output) with: status (FIXED / NEEDS-USER-DECISION / NOT-APPLICABLE-WITH-REASON), what landed where (plan + task + step), and code/spec changes summary.
- **Cross-plan coherence is non-negotiable.** Six of the ten blockers are cross-plan contracts (B-01, B-02, B-04, B-06, B-09, B-10). The cross-plan contracts table in §5 is your reference.
- **Russian doc-comments, English identifiers** per `CLAUDE.md` — match existing PLAN files' style.

---

## 2. Authoritative inputs (read in this order)

These are **read-only** for you. They are the ground truth. Do not modify them.

1. **`.planning/phases/06c-on-demand-migration/06C-CONTEXT.md`** — 25 D-decisions. Locked.
2. **`.planning/phases/06c-on-demand-migration/06C-RESEARCH.md`** — 10 pitfalls (P-1..P-10), 7 open questions (resolved). Locked.
3. **`.planning/phases/06c-on-demand-migration/06C-DISCUSSION-LOG.md`** — discussion-phase reasoning.
4. **`.planning/phases/06c-on-demand-migration/06C-REVIEWS.md`** — the 10 blockers + 8 warnings you must address. **This is the delta.**

**Files you will edit (revision targets):**

- `.planning/phases/06c-on-demand-migration/06C-01-PLAN.md` — minor signature additions only (see B-04 below).
- `.planning/phases/06c-on-demand-migration/06C-02-PLAN.md` — touched by B-04, B-06, B-07, W-04.
- `.planning/phases/06c-on-demand-migration/06C-03-PLAN.md` — touched by B-01, B-02, B-04, B-05, B-06, B-09, W-03, W-04, W-05, W-08.
- `.planning/phases/06c-on-demand-migration/06C-04-PLAN.md` — touched by B-01, B-02, B-03, B-06, B-08, B-10, W-01, W-02, W-06.
- `.planning/phases/06c-on-demand-migration/06C-05-PLAN.md` — unchanged. (If your revisions affect verification narrative, note in REVISION-LOG without editing 05 yet.)

**Files you will create:**

- `.planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md` — your deliverable. Format in §7.

---

## 3. Codebase facts you must rely on (verified at brief-time, 2026-05-13)

These are facts about the current repo that affect your fixes. Confirm by reading the cited files; do not re-derive.

| Fact | Source | Implication |
|---|---|---|
| `ReconnectClock` protocol + `SystemReconnectClock` struct live inside `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` (lines 36, 41 — confirm with `grep -n "ReconnectClock\|SystemReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift`). | Review B-01 | Plan 04 Task 3 deletes this file → these types vanish. Extract them **before** the delete (see §4 B-01). |
| `InstantReconnectClock` is a private nested actor in `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` (~line 57). | Review B-02 | Plan 04 Task 3 deletes this file → helper vanishes. TunnelWatchdogTests needs it. Extract to shared file before delete. |
| `UserIntentStore` is a Sendable wrapper over UserDefaults, declared **inside** `TunnelController.swift` (~line 68). Key: `app.bbtb.userIntendedConnected`. | grep verified | Plan 03 Task 2 (migration) and Plan 02 Task 2 (provisioner) can read this UserDefaults key **directly** — no need to import UserIntentStore. Both sides share the key verbatim; document this contract in PLAN doc-comments. |
| Provider bundle IDs in production: `app.bbtb.client.ios.tunnel` (iOS), `app.bbtb.client.macos.tunnel` (macOS). Confirmed in `BBTB/App/iOSApp/BBTB_iOSApp.swift:60` and `BBTB/App/macOSApp/BBTB_macOSApp.swift:49`. Test fixtures use `app.bbtb.test.tunnel`. | grep verified | The ManagerSelector helper (B-06) can hardcode a `Set<String>` of `[ios.tunnel, macos.tunnel]` as the default; per-target tests can override. |
| `SettingsFeature` target deps in `BBTB/Packages/AppFeatures/Package.swift` (lines 42–45) currently: `["VPNCore", "DesignSystem", "Localization", "KillSwitch"]`. **Does NOT depend on MainScreenFeature.** | grep verified | B-09 fix: explicit edit step to add `"MainScreenFeature"` to this array. `MainScreenFeatureTests` already depends on `SettingsFeature` (line 55), but that's a *test* target — no cycle. |
| `MainScreenFeature` source target deps (lines 27–37) do NOT reference `SettingsFeature`. | Cycle safety check | Confirms direction `SettingsFeature → MainScreenFeature` is safe. Document this in your B-09 fix. |
| `NEVPNConnection.status` is a synchronous property read (no XPC) — pattern already used and documented in `TunnelController.swift:373` comment. | Existing code | This validates Plan 03 Task 3 watchdog's invariant that statuses arrive XPC-free. |
| `NEVPNConnection.manager` back-pointer: **status uncertain.** Apple's public NEVPNConnection class reference does not document a `manager` property, though some Apple sample code suggests it may exist. **Verify before relying on it for B-03 (option B).** Fallback path (option A, cached manager) is always available. | Review B-03 note | Your B-03 fix should choose option (A) "cached manager reference" unless you verify NEVPNConnection.manager exists and is documented. |

---

## 4. Blocker-by-blocker landing map

Each entry is: **what's wrong → where the fix lands → fix shape → cross-plan effects**.

### B-01: ReconnectClock dependency survival

**Wrong:** `ReconnectClock` + `SystemReconnectClock` (protocol + struct) live inside `ReconnectStateMachine.swift`, which Plan 04 Task 3 deletes. TunnelWatchdog (Plan 03 Task 3) declares `clock: ReconnectClock = SystemReconnectClock()`. After cleanup → `cannot find type 'ReconnectClock' in scope`.

**Lands in:** Plan 03 Task 3, as a **new step BEFORE creating TunnelWatchdog.swift**. Call it Task 3 Step 0 or split into a separate Task 2b.

**Fix shape:**
- Create new file `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift`. Move `ReconnectClock` protocol and `SystemReconnectClock` struct verbatim from `ReconnectStateMachine.swift` to the new file.
- In `ReconnectStateMachine.swift`, **delete** the protocol + struct (they are now imported transitively via the same module since both files are in `MainScreenFeature`).
- Acceptance grep:
  - `grep -c "protocol ReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` == 1
  - `grep -c "protocol ReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` == 0
- Verify: `swift build` still green after this extraction (Plan 04 won't have deleted `ReconnectStateMachine.swift` yet).

**Cross-plan effects:**
- Plan 04 Task 3 cleanup: now deleting `ReconnectStateMachine.swift` does NOT break `ReconnectClock`/`SystemReconnectClock` consumers, because they live in the new file. Update Plan 04's acceptance grep to confirm `ReconnectClock.swift` is preserved (NOT deleted).
- Add note to Plan 03 Task 3 `<read_first>`: "do NOT redeclare these types; use the extracted ones".

### B-02: InstantReconnectClock test helper survival

**Wrong:** `InstantReconnectClock` is a private nested actor inside `TunnelControllerStateTests.swift`. Plan 04 deletes that file. New `TunnelWatchdogTests` needs the helper.

**Lands in:** Plan 03 Task 3, as the same pre-Task 3 step as B-01.

**Fix shape:**
- Create new file `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift`. Move `InstantReconnectClock` from `TunnelControllerStateTests.swift` to it. Make it `internal` (not `private`) so other test files in the same target can use it.
- In `TunnelControllerStateTests.swift`, replace the private declaration with usage of the shared helper (test file still works during the parallel-run window).
- Acceptance grep:
  - `grep -c "actor InstantReconnectClock" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` == 1
  - `grep -c "private.*actor InstantReconnectClock" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` == 0

**Cross-plan effects:**
- Plan 04 Task 3 cleanup: when deleting `TunnelControllerStateTests.swift`, `TestClocks.swift` must remain. Update Plan 04 acceptance: `! -f TunnelControllerStateTests.swift && -f TestClocks.swift`.
- Plan 03 Task 3 TunnelWatchdogTests `<read_first>` should reference `TestClocks.swift`, not the deleted file.

### B-03: Watchdog `manager.isEnabled` gate proxy is broken (CRITICAL ARCHITECTURAL)

**Wrong:** Plan 04 Task 1 Step 2 uses `let cachedEnabled = lastKnownStatus != .invalid` as proxy for `manager.isEnabled`. When another VPN app activates, our `manager.isEnabled` flips to `false` but `connection.status` stays `.disconnected` (NOT `.invalid`). Watchdog will fire failover and fight back — exactly the bug class we are eliminating.

**Lands in:** Plan 04 Task 1 Step 2 + Plan 04 Task 3 Step 2 (slim TunnelController). Also implicitly affects Plan 03 Task 3 watchdog contract docs.

**Fix shape:**

Read `manager.isEnabled` directly via one of:

- **Option A (recommended, low-risk):** Cache a manager reference inside `TunnelController` actor. Populate at `startReachability()` time (one XPC), refresh after `ConfigImporter.provisionTunnelProfile` save (post-save hook OR a `refreshCachedManager()` method on TunnelController called from ConfigImporter / SettingsViewModel). On `handleStatusChange`, read `cachedManager?.isEnabled ?? false` (conservative default).
- **Option B (only if verified):** `notification.object as? NEVPNConnection`, then `connection.manager?.isEnabled`. **Verify NEVPNConnection.manager exists** before relying on this; if uncertain, use Option A.

Plan 04 must:
1. Replace the `lastKnownStatus != .invalid` proxy with the real `isEnabled` read.
2. Add caching logic to TunnelController (Option A) — one new stored property `cachedManager: NETunnelProviderManager?` + assignment in `startReachability()` and after `provisionTunnelProfile` save. Cache update is XPC-free if done piggyback on existing `loadFromPreferences()` calls.
3. When `cachedManager` is `nil` (startup race), pass `managerEnabled: false` → watchdog skips. This is the conservative default — correct.

Plan 03 Task 3 watchdog contract (already in `<interfaces>`) is unchanged — it still takes `managerEnabled: Bool` as parameter. Only the **caller**'s logic changes.

**Cross-plan effects:**
- Plan 02 (ConfigImporter) should call `tunnel.refreshCachedManager()` after `provisionTunnelProfile` save. This requires Plan 02 to know about `TunnelController` — but ConfigImporter currently does NOT know about TunnelController (they're loosely coupled). **Alternative:** ConfigImporter posts a notification (`.bbtbProvisionerDidSave`); TunnelController observes it and refreshes its cache. Cleaner. Document in Plan 02.
- Update Plan 04 Task 1 acceptance grep: confirm `lastKnownStatus != .invalid` proxy is GONE; confirm `cachedManager` property exists.

### B-04: Plan 02 parallel-run risks phantom initial connect (CRITICAL)

**Wrong:** Plan 02 sets `isOnDemandEnabled = true` at import time via `OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: true)`. If user has imported config but never tapped Connect, the OS will auto-connect on next network event. Reproduces the Phase 6 phantom-reconnect bug — now OS-driven.

**Lands in:** Plan 01 Task 1 (API extension) + Plan 02 Task 2 + Plan 03 Task 1 (toggle live-apply) + Plan 03 Task 2 (migration). Affects four touchpoints because the fix is a contract change to `OnDemandRulesBuilder` API.

**Fix shape:**

Extend `OnDemandRulesBuilder` API in Plan 01 Task 1 — minimal addition, preserves existing tests:

```swift
public enum OnDemandRulesBuilder {
    // Existing — rename parameter for clarity. Old name conflated toggle and final flag.
    public static func apply(to manager: NETunnelProviderManager,
                             isOnDemandEnabled: Bool)  // RENAMED from autoReconnectEnabled

    // NEW (W-04 single-source-of-truth entry point):
    // Reads current toggle AND user intent; sets isOnDemandEnabled = toggle && intent.
    public static func applyCurrentState(to manager: NETunnelProviderManager,
                                         userDefaults: UserDefaults = .standard)

    // Existing.
    public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard,
                                                key: String = "app.bbtb.autoReconnectEnabled") -> Bool

    // NEW (B-04 helper):
    // Reads user intent flag (same UserDefaults key UserIntentStore writes).
    public static func loadUserIntendedConnected(userDefaults: UserDefaults = .standard,
                                                  key: String = "app.bbtb.userIntendedConnected") -> Bool
}
```

Semantics:
- `apply(to:isOnDemandEnabled:)` — low-level, caller controls the flag explicitly. Always writes rules (so re-enable later is cheap).
- `applyCurrentState(to:userDefaults:)` — high-level single source of truth: computes `isOnDemandEnabled = loadAutoReconnectEnabled() && loadUserIntendedConnected()` and calls low-level `apply`.

**Cross-plan effects:**

- **Plan 01 Task 1:** add 2 new tests for `applyCurrentState` (intent OFF → flag false; both ON → flag true) + 1 new test for `loadUserIntendedConnected`. Rename existing tests' param from `autoReconnectEnabled` to `isOnDemandEnabled` to match new API. Total new test count ≈ 11.
- **Plan 02 Task 2:** `provisionTunnelProfile` calls `OnDemandRulesBuilder.applyCurrentState(to: manager)` instead of the (now-removed) `DefaultTunnelProvisioner.applyOnDemandConfiguration` wrapper. This **simultaneously closes W-04** (drop the wrapper; everyone uses `applyCurrentState`). Remove the `applyOnDemandConfiguration` helper from Plan 02 entirely; revise Task 1 tests to target `OnDemandRulesBuilder.applyCurrentState` instead.
- **Plan 03 Task 1:** `SettingsViewModel.applyAutoReconnectToManager` uses `OnDemandRulesBuilder.applyCurrentState(to: manager)` (no need to read toggle separately).
- **Plan 03 Task 2:** `OnDemandMigrationTask.runIfNeeded` uses `OnDemandRulesBuilder.applyCurrentState(to: manager)`. This means: a user who upgraded but never connected on Phase 6 will have `userIntendedConnected = false` → migration sets `isOnDemandEnabled = false` (correct — no phantom connect). When they tap Connect post-upgrade, TunnelController sets intent true → next applyCurrentState call (on subsequent import OR explicit toggle) will flip on-demand on. **However**, this opens a new issue: the moment user taps Connect, intent flips true — but on-demand is still off until the next provisioner call. Document this in Plan 03 Task 2: a Connect tap should be followed by a `refreshOnDemandFromCurrentState()` call on the cached manager. This couples Plan 03 Task 1 helper extraction with the connect/disconnect path. **Add this as an explicit additional Plan 03 / Plan 04 Task 1 wiring step.**

Specifically: in Plan 04 Task 1 Step 2 (TunnelController watchdog wiring), the same site that calls `await watchdog?.setUserIntent(true)` in `connect()` should also call `await OnDemandRulesBuilder.applyCurrentState(to: cachedManager)` + save/reload. Same for `disconnect()` (intent → false → on-demand off → tunnel won't auto-resurrect).

### B-05: Migration flag set on transient failure (CRITICAL)

**Wrong:** Plan 03 Task 2 `OnDemandMigrationTask` sets `app.bbtb.autoReconnectMigratedV6c = true` even when `loadAllFromPreferences()` throws (treated as "fresh install proxy"). On transient XPC failure → migration permanently skipped → user stuck with auto-reconnect off.

**Lands in:** Plan 03 Task 2.

**Fix shape:**

Revise the migration logic:

1. If `userDefaults.bool(forKey: migratedKey) == true` → return (already done).
2. Try `let managers = try await NETunnelProviderManager.loadAllFromPreferences()`.
3. If **throws** → log warn, **DO NOT set flag**, return (retry next launch).
4. If `managers.isEmpty` → fresh install, no profile to migrate. Set flag = true (idempotent invariant — ConfigImporter Plan 02 will write on-demand on first import).
5. Else if `ourManagers(from: managers).isEmpty` → no OUR manager (different app's profile or stale). Same as managers.isEmpty: set flag = true.
6. Else → apply `applyCurrentState` to all `ourManagers(from: managers)`, save each, reload each. If ALL succeed → set flag = true. If ANY save throws → log error, **DO NOT set flag**, return (retry next launch).

Plan 03 Task 2 must:
- Change `try?` to explicit `do/catch` for `loadAllFromPreferences()`.
- Add new test: `test_runIfNeeded_loadAllThrows_doesNotSetFlag` — uses a test seam (or operates on real `loadAllFromPreferences` which throws in test env) and asserts flag stays false. This adds test count from 4 → 5.
- Rename existing Test 2 (`test_runIfNeeded_freshInstallNoManager_setsFlag`) to clarify it now means `managers.isEmpty` path, not "throws path".
- Add Test for "save throws → flag stays false". This may require test seam — see if `OnDemandMigrationTask` can be parameterized for testability or extracted into a helper.

**Cross-plan effects:**
- Plan 04 (App init wiring): no changes — migration task still fire-and-forget. But add a note: if migration fails repeatedly (e.g., persistent XPC failure on every launch), user sees Phase 6 behavior preserved (manager still has old config, no on-demand). UAT-Task I in Plan 04 should specifically check first-launch-after-upgrade success.

### B-06: Multi-manager handling

**Wrong:** All sites use `managers.first`. Users can have multiple `NETunnelProviderManager` instances (after re-imports, legacy installs, app reinstall residue). May migrate/apply to wrong one.

**Lands in:** new shared helper file + revisions to **five sites**.

**Fix shape:**

Create new file `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift`:

```swift
public enum ManagerSelector {
    /// Provider bundle IDs for the BBTB tunnel extension across iOS + macOS.
    /// Test fixtures use `app.bbtb.test.tunnel` and won't match (correct — tests don't
    /// run with real NEM extensions).
    public static let ourProviderBundleIdentifiers: Set<String> = [
        "app.bbtb.client.ios.tunnel",
        "app.bbtb.client.macos.tunnel"
    ]

    /// Filter to managers our app owns. Caller iterates over result for all-managers
    /// behavior, OR takes .first for legacy single-manager behavior.
    public static func ourManagers(
        from managers: [NETunnelProviderManager],
        knownBundleIDs: Set<String> = ourProviderBundleIdentifiers
    ) -> [NETunnelProviderManager] {
        managers.filter { manager in
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
                  let id = proto.providerBundleIdentifier else { return false }
            return knownBundleIDs.contains(id)
        }
    }
}
```

This file is created in Plan 03 (suggest: Plan 03 Task 2.5 — a small dedicated step) so it's available before migration + watchdog wiring needs it. Plan 02 callsite (provisionTunnelProfile) is patched in Plan 03 too (it's in MainScreenFeature, no module-crossing issue).

Wait — Plan 02 is `wave: 2` and Plan 03 is `wave: 3`. Plan 02 runs first. So `ManagerSelector.swift` must be created in Plan 01 OR Plan 02. **Decision:** Create it in **Plan 02 as a new Task 0 (or Task 1.5)** — same wave as the first consumer (`ConfigImporter`). Plan 03/04 then reference it.

**Five sites to use it:**

1. `Plan 02 Task 2` — `DefaultTunnelProvisioner.provisionTunnelProfile`:
   ```swift
   let managers = try await NETunnelProviderManager.loadAllFromPreferences()
   let ours = ManagerSelector.ourManagers(from: managers)
   let manager = ours.first ?? NETunnelProviderManager()  // fresh manager keeps fallback
   ```
2. `Plan 03 Task 1` — `SettingsViewModel.applyAutoReconnectToManager`: iterate over `ourManagers(from:)` and apply to all (covers multi-manager residue).
3. `Plan 03 Task 2` — `OnDemandMigrationTask.runIfNeeded`: same — apply to all `ourManagers(from:)`. If any save throws → flag stays false (per B-05).
4. `Plan 04 Task 1` — TunnelController's `cachedManager` (per B-03): set from `ourManagers(from:).first`.
5. `Plan 04 Task 3` — macOS `handleWake`: `try? ourManagers(from: managers).first?.connection.startVPNTunnel()` (after the W-06 gate — see below).

**Cross-plan effects:**
- Plan 02 introduces the file; Plans 03 and 04 just use it. No module-crossing needed (all in `MainScreenFeature`).
- Add a unit test in Plan 02 (or as part of Plan 02 Task 0): `ManagerSelectorTests.swift` with 3 tests: empty input, mixed input (ours + foreign), bundle ID match exact.

### B-07: Plan 02 verify is silent false-GREEN

**Wrong:** Plan 02 Task 1 `<verify>` uses `swift test --filter ... 2>&1 | grep -E "error|fail" | head -5` — always exits 0 due to pipe semantics.

**Lands in:** Plan 02 Task 1.

**Fix shape:** **Delete the `<verify>` block from Task 1 entirely.** Task 2's `<verify>` covers the GREEN transition. Rationale: Task 1 is RED — failing tests are expected; we don't need a CI gate that "expects failure" (which is what `! swift test --filter ...` would do, but adds noise). Plan 06C-01 and other plans use this pattern (Task 1 RED has no verify; Task 2 GREEN has verify).

Alternative if you want to keep a verify: `! cd BBTB && swift test --package-path Packages/AppFeatures --filter ConfigImporterOnDemandWiringTests` (negate — Task 1's verify passes iff tests fail to compile or fail to run, which is the RED state). Choose one; document choice in REVISION-LOG.

### B-08: Acceptance grep matches doc-comments

**Wrong:** Plan 04 Task 3 acceptance grep `grep -c "ReconnectStateMachine|NetworkReachability|..." TunnelController.swift returns 0` will fail because slim-down code may still mention these symbols in doc-comments (`/// Phase 6c replaced ReconnectStateMachine with TunnelWatchdog`).

**Lands in:** Plan 04 Task 3 acceptance criteria.

**Fix shape:**

Replace the broad grep with a comment-stripping pre-step:

```bash
# Strip line comments + block comments, then check for symbol usage in remaining code
awk '
  BEGIN { in_block = 0 }
  /\/\*/ { in_block = 1 }
  /\*\// { in_block = 0; next }
  in_block { next }
  { sub(/\/\/.*/, ""); print }
' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift \
  | grep -cE "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay|manualDisconnectInProgress|connectInProgress|lastKnownStatus|wakePending|triggerRecoveryIfNeeded"
```

Expected: returns 0.

Alternative (simpler but less robust): explicit step in Task 3 action: "After cleanup, audit doc-comments — strip references to deleted types from comments using a single grep+sed pass; then plain grep can verify 0 matches." Add as Step 7 (post-cleanup comment hygiene).

**Cross-plan effects:** none — purely Task 3 internal.

### B-09: SettingsFeature → MainScreenFeature dependency

**Wrong:** Plan 03 Task 1 says "import MainScreenFeature if needed" — non-deterministic. The toggle helper needs `OnDemandRulesBuilder` (lives in `MainScreenFeature`); dependency must be added explicitly.

**Lands in:** Plan 03 Task 1 — add explicit Package.swift edit as the FIRST step of Task 1.

**Fix shape:**

In Plan 03 Task 1, add Step 0 BEFORE writing any code:

```swift
// Edit BBTB/Packages/AppFeatures/Package.swift, line 42-45:
.target(
    name: "SettingsFeature",
    dependencies: ["VPNCore", "DesignSystem", "Localization", "KillSwitch", "MainScreenFeature"]  // ADDED "MainScreenFeature"
),
```

Acceptance grep (replaces "if needed" language):
- `grep -c "MainScreenFeature" BBTB/Packages/AppFeatures/Package.swift` ≥ 2 (one in `.library` line 8, one new in SettingsFeature target deps).
- Specifically: `grep -A 5 'name: "SettingsFeature"' BBTB/Packages/AppFeatures/Package.swift | grep -c "MainScreenFeature"` ≥ 1.

**Verify no cycle** before committing:
- `grep -A 10 'name: "MainScreenFeature"' BBTB/Packages/AppFeatures/Package.swift` (lines 27–37) must NOT contain `SettingsFeature`. Document this check in Plan 03 Task 1 Step 0 action.
- Note: `MainScreenFeatureTests` (line 55) already lists `SettingsFeature` as a dep — that's a test target, not a source cycle. OK.

**Cross-plan effects:** none — module dep is local.

### B-10: Cleanup gate must treat F (other-VPN) and I (migration) as HARD blockers

**Wrong:** Plan 04 Task 2 UAT checkpoint treats E/G as critical. But F (fight-with-other-VPN) is explicitly one of the 4 bug classes we eliminate, and I (upgrade migration) is the D-17b/c safety net.

**Lands in:** Plan 04 Task 2 `<how-to-verify>` and `<resume-signal>` sections.

**Fix shape:**

Update the PASS criterion language:

- Old: "9/9 PASS = full success → proceed Task 3 cleanup. 6-8/9 PASS = partial success → анализировать failure."
- New: "**Hard blockers — must PASS: A, C, E, F, G, I.** If any of these fails → STOP cleanup, fix-forward in Task 1. Non-blocking (may proceed with notes): B, D, H. Decision matrix:
  - All 6 hard blockers PASS + 0–3 non-blocking failures: proceed cleanup; record non-blocking failures in REVISION-LOG.
  - Any hard blocker FAIL: STOP, do not proceed to Task 3, escalate to user."

Update `<resume-signal>` text to reference the new hard-blocker set.

**Cross-plan effects:**
- Plan 05 Task 1 UAT documentation will record PASS/FAIL per scenario; ensure A/C/E/F/G/I rows are visually marked as "critical / hard blocker" in the UAT.md table template described in Plan 05.

---

## 5. Warning landings (W-01..W-08)

### W-01: Plan 04 Task 3 scope too large — split

**Lands in:** Plan 04. Split Task 3 into:
- **Task 3a:** TunnelController slim-down (delete stored properties + methods listed in current Task 3 Step 2); update `handleStatusChange` to use cached manager (B-03 fix); preserve `startReachability`, macOS wake observer, connect/disconnect.
- **Task 3b:** MainScreenViewModel banner state rewire + ReconnectBanner enum trim + add `setFailoverObserver` to TunnelWatchdog (Plan 03 Task 3 deferred this; bring it into Plan 04 wiring).
- **Task 3c:** Delete the 5 files (ReconnectStateMachine + tests + NetworkReachability + tests + TunnelControllerStateTests); create TunnelControllerTests.swift replacement; update App entry points.

Each sub-task has its own `<acceptance_criteria>` and `<verify>`. Final `<verify>` chain: 3a green → 3b green → 3c green → full `xcodebuild` green.

### W-02: Banner enum breaking change unaudited

**Lands in:** Plan 04 Task 3b (after the split).

Add explicit audit step in Task 3b action:

```bash
grep -rn 'case \.retrying\|case \.allFailed\|\.retrying(\|\.allFailed' BBTB/Packages/AppFeatures
```

Update each match. Add acceptance: `grep -rc 'case \.retrying\|case \.allFailed' BBTB/Packages/AppFeatures` returns 0.

### W-03: applyAutoReconnectToManager runs on MainActor

**Lands in:** Plan 03 Task 1.

Two options — pick one and document:

- **Option 1 (recommended):** Make the helper `nonisolated`:
  ```swift
  nonisolated public func applyAutoReconnectToManager(userDefaults: UserDefaults = .standard) async {
      // Reads UserDefaults (nonisolated-safe), calls async NEM APIs off main.
  }
  ```
  Caller invokes via `Task.detached { await viewModel.applyAutoReconnectToManager() }` from the `.onChange` modifier.
- **Option 2:** Keep it on @MainActor but detach internally: `Task.detached { ... }` body.

Option 1 is cleaner because it lets the type system enforce off-main execution. Document choice + the `.onChange` call shape in Plan 03 Task 1.

### W-04: OnDemand-config wrapper drift — closed by B-04

The `applyCurrentState` single entry point in `OnDemandRulesBuilder` (introduced for B-04) **replaces** the `DefaultTunnelProvisioner.applyOnDemandConfiguration` wrapper from Plan 02. Drop the wrapper entirely; everyone calls `OnDemandRulesBuilder.applyCurrentState(to: manager)`. This **also closes W-04**. Note this explicitly in REVISION-LOG: "W-04 resolved via B-04 fix — single entry point in builder."

### W-05: Adaptive debounce in watchdog

**Lands in:** Plan 03 Task 3 `<behavior>` and tests.

Current Plan 03: cancels debounce on `.connected`. Extend cancellation to `.connecting` and `.reasserting`:

```swift
handleStatusChange(.connecting | .reasserting, ...) {
    debounceTask?.cancel()
    debounceTask = nil
    // Do NOT reset stableSession — transient state.
}
```

Add Test 9: `test_debounceCancelledByReasserting` — same shape as existing Test 5 (`test_debounceCancelledByReconnect`) but with `.reasserting`. Total watchdog tests: 8 → 9.

### W-06: macOS wake nudge unconditional

**Lands in:** Plan 04 Task 1 Step 4 (initial wiring) and Task 3a (post-cleanup `handleWake`).

Update `handleWake`:

```swift
#if os(macOS)
private func handleWake() async {
    let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
    guard let manager = ManagerSelector.ourManagers(from: managers).first else { return }
    guard manager.isEnabled else { return }
    guard manager.isOnDemandEnabled else { return }
    guard OnDemandRulesBuilder.loadAutoReconnectEnabled() else { return }
    try? manager.connection.startVPNTunnel()  // idempotent nudge
}
#endif
```

The three guards prevent wake-nudge fighting back when:
- Profile disabled by another VPN (`manager.isEnabled == false`).
- On-demand off (we explicitly chose manual mode).
- Toggle off (user disabled auto-reconnect).

### W-07: Shared manager-selection helper missing — closed by B-06

The `ManagerSelector.ourManagers(from:)` helper (B-06) is the W-07 closure. Mention in REVISION-LOG: "W-07 resolved via B-06 fix."

### W-08: Builder ordering documentation

**Lands in:** Plan 01 Task 1 action (doc-comments inside `OnDemandRulesBuilder.swift`).

Add doc-comment to `buildRules()`:

```swift
/// Returns the rule array. Phase 6c emits exactly one `NEOnDemandRuleConnect(.any)`.
///
/// Phase 8 extensibility contract: future `NEOnDemandRuleEvaluateConnection` rules
/// (per-SSID, per-domain) MUST be prepended to the array — `onDemandRules` is
/// first-match-wins per Apple's NetworkExtension semantics. The catch-all
/// connect rule remains the last entry so specific rules can short-circuit.
private static func buildRules() -> [NEOnDemandRule] { ... }
```

Also add a one-line note in the file header doc-comment referencing this ordering contract.

---

## 6. Cross-plan contracts table (the connections that must stay coherent)

| Contract | Plan A | Plan B | What must agree |
|---|---|---|---|
| `ReconnectClock` / `SystemReconnectClock` location | Plan 03 (extracts to `ReconnectClock.swift`) | Plan 04 Task 3c (deletes `ReconnectStateMachine.swift`) | Extraction happens BEFORE deletion. Plan 04 acceptance does NOT delete `ReconnectClock.swift`. |
| `InstantReconnectClock` test helper | Plan 03 (extracts to `TestClocks.swift`) | Plan 04 Task 3c (deletes `TunnelControllerStateTests.swift`) | Same: extract before delete; `TestClocks.swift` survives. |
| `ManagerSelector.ourManagers(from:)` helper | Plan 02 (creates) | Plan 03 + Plan 04 (use in 4 more sites) | Single source of truth; all 5 sites import from `ManagerSelector.swift`. |
| `OnDemandRulesBuilder.applyCurrentState` single entry point | Plan 01 Task 1 (introduces) | Plan 02 Task 2 + Plan 03 Task 1 + Plan 03 Task 2 (consume) | All 3 consumer sites call `applyCurrentState`, NOT `apply` directly. The low-level `apply` is reserved for tests + the `applyCurrentState` internal implementation. |
| `loadUserIntendedConnected` UserDefaults key | Plan 01 Task 1 reads `app.bbtb.userIntendedConnected` | TunnelController.swift `UserIntentStore` writes same key | Document the shared key in both file's doc-comments. Future Phase may extract to a `Keys` module. |
| TunnelController `cachedManager` | Plan 04 Task 1 (B-03 fix) | Plan 02 (post-save notification or refresh hook) + Plan 03 Task 1 (toggle apply hook) | Cache invalidated/refreshed after every provisioner save AND every toggle live-apply. Use `NotificationCenter` (`.bbtbProvisionerDidSave`) for loose coupling. |
| `OnDemandRulesBuilder` API param rename `autoReconnectEnabled` → `isOnDemandEnabled` | Plan 01 Task 1 | Plan 02 + Plan 03 (consumers) | If you rename the param, all callers and tests use the new name. Verify with `grep -c "autoReconnectEnabled:" BBTB/Packages/AppFeatures` after revisions: only `loadAutoReconnectEnabled` (which is its own method) and UserDefaults key strings should match — no callsites of `apply`. |
| Hard-blocker UAT scenarios A/C/E/F/G/I | Plan 04 Task 2 (decision matrix) | Plan 05 Task 1 (UAT.md table marks them critical) | Same hard-blocker set in both docs. |
| Banner enum trim (remove `.retrying`, `.allFailed`; add `.connecting`) | Plan 04 Task 3b | Plan 04 Task 3b audit step | grep -rn audit catches all consumer sites BEFORE the enum mutates. |
| TunnelWatchdog `setFailoverObserver` callback | Plan 03 Task 3 introduces / Plan 04 Task 3b uses | TunnelWatchdog API has the setter; VM injects closure to update banner | If you don't add this in Plan 03 Task 3, add it explicitly in Plan 04 Task 3b. Either is fine; document the choice. |

---

## 7. Deliverables (what you produce)

### 7.1. Edited PLAN files

In-place edits to:
- `06C-01-PLAN.md` (param rename + 1 new method + 2 new methods + 3 new tests for B-04 / W-08)
- `06C-02-PLAN.md` (drop the wrapper helper; create `ManagerSelector.swift` as new Task 0; use `applyCurrentState`; fix B-07)
- `06C-03-PLAN.md` (substantial — see below)
- `06C-04-PLAN.md` (substantial — see below)

**Plan 03 specific changes:**
- New Task between Task 2 and Task 3 (call it Task 2.5 or insert in Task 3 as Step 0): extract `ReconnectClock.swift` + `TestClocks.swift` (B-01, B-02).
- Task 1: Add Step 0 for Package.swift dep (B-09). `applyAutoReconnectToManager` nonisolated (W-03). Use `applyCurrentState` not direct `apply` (W-04 via B-04). Apply to all `ourManagers(from:)` (B-06).
- Task 2: Don't set flag on `loadAllFromPreferences` throw (B-05). Use `applyCurrentState`. Apply to all `ourManagers(from:)`. Add test for transient-failure path. Test count 4 → 5.
- Task 3: Watchdog uses extracted `ReconnectClock` (B-01). Tests use shared `InstantReconnectClock` (B-02). Adaptive debounce — cancel on `.connecting`/`.reasserting` too (W-05). Test count 8 → 9. Consider adding `setFailoverObserver` here (or defer to Plan 04 Task 3b).

**Plan 04 specific changes:**
- Task 1: Replace `lastKnownStatus != .invalid` proxy with cached manager + real `isEnabled` (B-03). Add NotificationCenter observer for `.bbtbProvisionerDidSave`. macOS wake nudge gets 3 guards (W-06). UAT checkpoint resume-signal text updated (B-10).
- Task 2: UAT pass criteria updated — hard-blocker set is `{A, C, E, F, G, I}` (B-10). Non-blocking: `{B, D, H}`. Decision matrix in `<resume-signal>`.
- Task 3 split into 3a/3b/3c (W-01). Each with own acceptance + verify. Add comment-stripping pre-step for acceptance grep (B-08). Banner enum audit grep (W-02). Preserve `ReconnectClock.swift` + `TestClocks.swift` in delete list.

### 7.2. New file: `06C-REVISION-LOG.md`

Format (must use exactly this structure for verification):

```markdown
# Phase 6c — Plan Revision Log (Round 1 → Round 2)

**Date:** 2026-05-13
**Revised by:** gsd-planner (revision-mode pass)
**Source:** 06C-REVIEWS.md (10 blockers + 8 warnings)

## Blocker resolutions

### B-01: ReconnectClock dependency survival
- **Status:** FIXED
- **Landed in:** Plan 03 Task 2.5 (new step) — extracts to `ReconnectClock.swift`
- **Cross-plan touch:** Plan 04 Task 3c acceptance updated — preserves `ReconnectClock.swift`
- **Files affected:** [list]
- **Change summary:** [2-3 sentences]

### B-02: InstantReconnectClock test helper
[same format]

[continue for B-03..B-10]

## Warning resolutions

### W-01: Plan 04 Task 3 scope too large
- **Status:** FIXED
- **Landed in:** Plan 04 — Task 3 split into Task 3a/3b/3c
- **Change summary:** [...]

[continue for W-02..W-08]

## Cross-plan contracts verified

| Contract | Verified by reading |
|---|---|
| ReconnectClock extract-before-delete | Plan 03 Task 2.5 creates it; Plan 04 Task 3c acceptance preserves it |
| ManagerSelector single helper used in 5 sites | grep candidates listed in each plan |
[...]

## Test count delta

| Plan | Before | After | Delta | Notes |
|---|---|---|---|---|
| Plan 01 | 8 | 11 | +3 | applyCurrentState (2) + loadUserIntendedConnected (1) |
| Plan 02 | 4 | 4 | 0 | (Manager Selector tests in new Task 0; wrapper helper dropped) |
| ManagerSelectorTests (new in Plan 02) | 0 | 3 | +3 | empty / mixed / exact match |
| Plan 03 Migration | 4 | 5 | +1 | transient-failure test |
| Plan 03 Watchdog | 8 | 9 | +1 | .reasserting cancellation |
| Plan 03 Settings | 4 | 4 | 0 | no change |
| Plan 04 TunnelControllerTests (new) | 0 | 6 | +6 | per Plan 04 Task 3c |
| Total NEW tests | 28 | 42 | +14 | |

## Items requiring user decision (if any)

[Empty if all 18 items fully addressed. If any item has ambiguity that needs user input, list it here with the question and your recommended default.]

## D-decision integrity

All 25 D-decisions preserved verbatim. List of D-decisions whose **implementation guidance was expanded** (not changed) in this revision:
- D-04 / D-06: intent gating added (B-04) — toggle ON + intent ON = on-demand ON.
- D-08: cached manager.isEnabled (B-03) — gate semantics preserved.
- D-17b/c: migration guards transient failures (B-05).

## Reviewer-facing summary

[3-5 sentences for the Round 2 reviewer: what changed, why, where to look first.]
```

---

## 8. Acceptance criteria (how I verify your output)

After your revision pass, I will check the following before sending to Round 2 review:

1. **`06C-REVISION-LOG.md` exists** and every B-XX (10 items) and W-XX (8 items) has a status entry.
2. **Each PLAN file's `git diff`** shows additions and replacements only at the specific sites identified in §4 + §5. No accidental rewrites of unrelated sections.
3. **D-decisions preserved:** `grep -c "D-01\b\|D-02\b\|...\|D-22\b" 06C-CONTEXT.md` is unchanged (you do not touch CONTEXT.md). `grep -c "D-01\b" 06C-0X-PLAN.md` counts in each plan are equal or greater (additions, no removals).
4. **Cross-plan contracts** in §6 — for each contract row, I will visually trace both plans and confirm the contract holds.
5. **Test counts** in REVISION-LOG match plan-level counts.
6. **No introduced regressions**: existing acceptance grep patterns that were correct (e.g., Plan 01 file existence checks) still appear unchanged.
7. **Russian doc-comments preserved** in all PLAN behavior/action sections (`CLAUDE.md` rule).
8. **Sanity check**: ROUND 2 dual review (gsd-plan-checker + Codex via delegator) returns APPROVE — or REQUEST CHANGES with only NEW minor findings (i.e., not re-raising B-01..B-10 or W-01..W-08).

---

## 9. Out-of-scope (do NOT touch)

- `06C-CONTEXT.md`, `06C-RESEARCH.md`, `06C-DISCUSSION-LOG.md` — locked.
- `06C-REVIEWS.md` — append nothing, do not edit.
- Any file outside `.planning/phases/06c-on-demand-migration/`.
- Any architectural decision (D-XX). If your revision would require changing a D-decision, **stop** and log the issue in `06C-REVISION-LOG.md` § "Items requiring user decision" — do not proceed.
- ROADMAP.md, REQUIREMENTS.md, STATE.md, PROJECT.md — Plan 05 handles those; not your concern here.

---

## 10. Style notes

- Match existing PLAN file's mixed Russian/English style: doc-comments and prose in Russian; identifiers and code in English.
- Each plan has YAML frontmatter at the top (`---` block) listing `files_modified`, `must_haves.truths`, `artifacts`, `key_links`. If your fix adds a new file or new acceptance pattern, update the frontmatter consistently.
- Each plan has a `<tasks>` block with `<task>` children that have `<read_first>`, `<behavior>`, `<action>`, `<verify>`, `<acceptance_criteria>`, `<done>` subblocks. Preserve this structure.
- `<acceptance_criteria>` uses `grep -c` patterns. If you add an acceptance check, follow the existing `grep -c "PATTERN" FILE returns N` style.

---

**Start with `06C-REVISION-LOG.md` skeleton (so the structure is committed early), then proceed plan-by-plan in this order: 01 → 02 → 03 → 04. Fill REVISION-LOG as you go. Self-verify the cross-plan contracts table at the end before declaring done.**
