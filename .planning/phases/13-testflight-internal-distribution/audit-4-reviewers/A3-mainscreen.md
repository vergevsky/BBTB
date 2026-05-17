# A3 — MainScreenFeature audit (Phase 13 Plan 08 / Re-audit #4)

**Reviewer:** A3 (Opus 4.7 #3)
**Scope:** `Packages/AppFeatures/Sources/MainScreenFeature/`
**Baseline:** HEAD `ccbce8a` (post-Plan-07 closure index, clean working tree apart from `.planning/STATE.md`)
**Mode:** Read-only
**Focus axes:** Thread Safety / Logic / Energy (reactive paths)
**Critical change-set examined:**

- `MainScreenViewModel.resolveConnectionSince(...)` — 4-arg variant + intervening-terminal gate (T-C-R1', `85dada2`)
- `MainScreenViewModel.applyVPNStatus(...)` — `sawTerminalStatusSinceConnected` reset/set logic
- `MainScreenViewModel.nevpnStatusObserver` block — pre-hop coalescing с `nevpnObserverLast*` `nonisolated(unsafe)` fields (T-C-C3H1', `0e387e1`)
- `MainScreenViewModel.performImport` + `handleDeepLink` — reentrancy guards (T-C-C3H2', `2d127cf`)
- `MainScreenViewModel.showFailoverBanner` — `failoverDismissTask` cancel-and-replace (T-C-B2, `c86174a`)
- `TunnelController.connect/disconnect` — single-flight Task storage (T-C-C2H2', `b347a10`)
- `TunnelController.applyCurrentStateToCachedManager` — 500ms backoff retry + `Bool` return (T-C-C2H1', `fe9e8d7`)
- `TunnelController.ExternalVPNStopMarker.mark()` — host-side method (T-C-C2H1')
- `ConfigImporter.provisionTunnelProfile` — narrow critical section; XPC outside mutex (T-C-R2', `ae6715c`)

---

## Verdict (one-liner)

🟡 **CONDITIONAL APPROVE** — 0 CRITICAL, 0 cross-session-blocking HIGH. Plan 07 fix-ups land structurally; coverage holds. **3 new HIGH** found (1 logic regression in selection-change reconnect that single-flight made worse; 1 thread-safety claim that overstates the model; 1 cancellation semantics issue в TunnelController single-flight). 6 MEDIUM, 9 LOW. Safe для Internal TestFlight; the 3 HIGH deserve ≤4h fix-up before External rollout.

---

## Plan 07 closure re-verification (changes in scope)

| Plan 07 task | Closes (from AUDIT-3 / Plan 06) | A3 (Opus) verdict |
|---|---|---|
| **T-C-R1'** intervening-terminal gate | A3-002 (T-C9' 60s threshold regression) | ✅ **CLOSED** — `sawTerminalStatusSinceConnected` reset на `.connected` + set на `.disconnected/.invalid/.disconnecting`, gate fed корректно. Tests `ResolveConnectionSinceTests` cover within-session race, long-background continuation, 24h safety net. **2 minor MEDIUM** (see M-A3-4-01, M-A3-4-04). |
| **T-C-R2'** narrow critical section / XPC outside mutex | A3-001 (Plan 06 — wide mutex starving failover) | ✅ **CLOSED structurally** — `provisionTunnelProfile` outer-public splits stage 1 inside `provisionSerializer.run` (SwiftData + Keychain + PoolBuilder + validate + CDN) → returns `(json, serverHost)` tuple → stage 2 XPC outside mutex. **Comment claim «PoolBuilder + validate + CDN run OUTSIDE mutex» (line 568 docstring) contradicts the actual code which keeps them INSIDE serializer** (the `(json, serverHost)` is built inside the closure). Behavior is still better than pre-fix (300-1000ms XPC excised), но docstring needs correction. See M-A3-4-02. |
| **T-C-C2H1'** disconnect retry + marker | C2'-3-001 (manual disconnect continues on save failure) | ✅ **CLOSED** — single retry (500ms backoff) → `mark()` safety net → `stopVPNTunnel()` proceeds. Combines retry + marker correctly. **One LOW** (L-A3-4-04) — `OnDemandRulesBuilder.applyCurrentState(to: manager)` runs ONCE before the retry loop; if a concurrent producer ever mutated `manager` between attempts, retry would save the later state. Defensive only; current actor isolation makes this benign. |
| **T-C-C2H2'** TunnelController single-flight | C2'-3-002 (actor reentrancy) | ⚠️ **PARTIAL** — `inFlightConnectTask`/`inFlightDisconnectTask` storage closes the gross reentrancy case, **но cancellation semantics introduce a NEW HIGH** (H-A3-4-01): if caller A is cancelled while waiting on inner Task, `defer { inFlightConnectTask = nil }` clears the slot even though the inner Task continues to run; caller B then starts a SECOND parallel Task → exactly the race T-C-C2H2' aimed to eliminate. See H-A3-4-01 below. |
| **T-C-C3H1'** NEVPN observer pre-hop coalescing | C3'-3-001 (per-event Task spawn flooding MainActor) | ⚠️ **STRUCTURALLY CORRECT but COMMENT-CLAIM OVERSTATES SAFETY** — coalescing logic works (reads + compares + writes сomplete before Task spawn), но docstring claim "NotificationCenter posts ARE serialized within a notification name on the posting thread" (line 162-165, 282-287) is **not strictly true**. Notifications are delivered on whichever thread posts them. If iOS ever posts `NEVPNStatusDidChange` on multiple threads concurrently (rare but not ruled out), the `nonisolated(unsafe)` reads + writes race. See H-A3-4-02. |
| **T-C-C3H2'** import/deeplink reentrancy | C3'-3-002 (two simultaneous imports / paste+deeplink within 1s) | ✅ **CLOSED** — both `performImport` и `handleDeepLink` early-return on `importInProgress`. **One MEDIUM** (M-A3-4-05) — error message hardcoded English, not localized; UX inconsistency vs других error paths (which use `L10n.*`). |
| **T-C-B2** failoverDismissTask cancel-replace | A3-006 (multi-server cascade dismiss race) | ✅ **CLOSED** — stored Task cancelled before re-arm. Test coverage missing (no specific unit test exercises cascade), но logic correct. |

**Summary:** 5/7 fully closed; 2 partials (T-C-C2H2' cancellation bug, T-C-C3H1' over-claimed safety). 1 docstring drift on T-C-R2'.

---

## CRITICAL findings

**None.** No exploitable / connection-broken issues found in MainScreenFeature at `ccbce8a`.

---

## HIGH findings

### H-A3-4-01: `TunnelController.connect()` / `disconnect()` single-flight slot cleared on caller-cancel even though inner Task continues — second caller starts parallel Task → reentrancy race re-opened

**Location:** `TunnelController.swift:376-398` (connect outer) + `554-566` (disconnect outer)

**Dimension:** Thread Safety / Cancellation correctness
**Severity:** HIGH
**Why this matters:** T-C-C2H2' (`b347a10`) was specifically designed to **prevent** the actor-reentrancy race documented in `C2'-3-002`. The current implementation accidentally restores that race under cancellation.

**Current implementation:**
```swift
public func connect() async throws -> Date {
    if let existing = inFlightConnectTask {
        return try await existing.value
    }
    let task: Task<Date, Error> = Task { try await self._doConnect() }
    inFlightConnectTask = task
    defer { inFlightConnectTask = nil }
    return try await task.value
}
```

**Race scenario:**

1. Caller A invokes `connect()`. Slot is nil → A creates inner Task1 and stores it. A then awaits `task1.value`.
2. Caller A's outer Task (whoever called `await tunnel.connect()`) is cancelled (e.g. selection-change handler tears down, or VM deinit racing).
3. `await task1.value` throws `CancellationError` (Task throws CancellationError on cooperatively-cancelled await).
4. `defer { inFlightConnectTask = nil }` fires → slot cleared.
5. **However Task1 itself is NOT cancelled** — Swift's unstructured `Task { ... }` doesn't propagate cancellation from the awaiter to the created Task. Task1 keeps running on the actor:
   - `setUserIntendedConnected(true)`
   - `await refreshCachedManager()` (XPC)
   - `await manager.saveToPreferences()` + `loadFromPreferences()` (2 XPC)
   - `try manager.connection.startVPNTunnel(...)`
   - `await awaitConnectedStatus(...)` (30s deadline)
6. While Task1 is mid-flight (say, between `saveToPreferences` and `startVPNTunnel`), Caller B invokes `connect()`. Slot is nil (defer fired in step 4) → B creates **Task2** and stores it. Task2 runs in parallel with Task1.
7. Both Task1 and Task2 race:
   - Both flip `connectInProgress = true` (idempotent).
   - Both call `manager.saveToPreferences()` — second one may fail or wait on NEPreferencesAgent's internal queue.
   - Both call `startVPNTunnel(options: ["manualStart": ...])` — second is no-op since iOS sees ongoing transition.
   - Both await `awaitConnectedStatus` on the SAME stream (both register continuations).
   - First to receive `.connected` returns its `started` Date; second receives the same status event and also returns.
8. Final result: 2 `setUserIntendedConnected(true)` writes (idempotent — saved twice to UserDefaults), 2 watchdog `setUserIntent(true)` calls, 2-3 redundant XPC trips, `started` Dates differ between the two callers (only matters if anyone uses the returned `Date` as authoritative — `MainScreenViewModel.performToggleImpl` ignores it with `_ = try await tunnel.connect()`, but other callers may not).

**Real-world reproduction probability:** Moderate. Cancellation flows that affect `connect()`:
- View task cancellation during scenePhase transitions (`Task { await viewModel.performToggle() }` inside SwiftUI `.task` modifier).
- Rapid selection-change in `applySelection` while a reconnect is in flight (`Task { @MainActor in await reconnectAfterSelectionChange(...) }`).
- VM deinit during Connect — observed in tests + previews where ServerListView dismiss tears down VM.

**Fix:**
```swift
public func connect() async throws -> Date {
    if let existing = inFlightConnectTask {
        // Same-instance dedupe: await existing without re-starting work.
        return try await existing.value
    }
    let task: Task<Date, Error> = Task { try await self._doConnect() }
    inFlightConnectTask = task
    // Clear the slot WHEN THE INNER TASK COMPLETES, not when the caller returns.
    // Subsequent callers either pick up the same Task (in-flight) or start fresh
    // (after completion). Cancellation of the outer caller no longer leaks a
    // ghost task into the in-flight window.
    Task { [weak self] in
        _ = try? await task.value
        await self?.clearInFlightConnectTask(task)
    }
    return try await task.value
}

private func clearInFlightConnectTask(_ task: Task<Date, Error>) {
    if inFlightConnectTask === task { inFlightConnectTask = nil }
}
```

The identity check (`===`) guards against the case where a NEW caller after the in-flight Task completed has already installed Task3 before the cleanup hop reached the actor.

Same pattern для `disconnect()`.

**Effort:** 20-30 min including a regression test (`test_connect_under_cancellation_does_not_start_second_task`).

**Test plan:**
```swift
func test_connect_caller_cancelled_inner_task_proceeds_no_second_task() async throws {
    let controller = TunnelController(...)
    let firstTask = Task { try await controller.connect() }
    try await Task.sleep(nanoseconds: 50_000_000)  // let inner Task1 start
    firstTask.cancel()
    _ = try? await firstTask.value
    // Immediately fire B
    let secondTask = Task { try await controller.connect() }
    // Assert: at most 1 startVPNTunnel call ever observed на mock manager
    _ = try? await secondTask.value
    XCTAssertEqual(mockManager.startVPNTunnelCallCount, 1)
}
```

---

### H-A3-4-02: NEVPN observer pre-hop coalescing relies on serialized-callback assumption that Apple does not document — `nonisolated(unsafe)` race window remains

**Location:** `MainScreenViewModel.swift:166-167` (`nevpnObserverLast*` declarations) + `262-300` (observer block reading/writing them)

**Dimension:** Thread Safety / @unchecked safety claim
**Severity:** HIGH (data race latent; comment overstates Apple guarantee)
**Why this matters:** T-C-C3H1' explicitly claims race-freeness based on "NotificationCenter posts ARE serialized within a notification name on the posting thread". This is **not in Apple's documented contract**. Apple's `NotificationCenter` docs state: "The notification center delivers notifications to observers synchronously. In other words, when posting a notification, control does not return to the poster until all observers have received and processed the notification." It says nothing about cross-thread serialization. Two threads can `post(name:object:)` concurrently with the same name → both callbacks fire concurrently on their respective posting threads.

**Empirical reality on iOS:** `NEVPNStatusDidChange` is typically delivered from a single internal queue used by `nehelper`. **But:** there is no public guarantee, and iOS 26 already changed delivery behavior (the 8k duplicate-event storm in `feedback_nevpn_xpc_mach_port` was a iOS 26 regression that didn't exist on iOS 17). Future iOS releases could legally deliver on multiple threads.

**The actual race:**
```swift
// observer block — runs on posting thread (queue: nil)
let status = conn.status
let connectedDate = conn.connectedDate
// Read 1, Read 2 (each via separate self? optional chains — TWO actor accesses)
if self?.nevpnObserverLastStatus == status,
   self?.nevpnObserverLastConnectedDate == connectedDate {
    return
}
// Write 1, Write 2 — non-atomic across the two fields
self?.nevpnObserverLastStatus = status
self?.nevpnObserverLastConnectedDate = connectedDate
```

If two callbacks A (status=.connected, cd=T1) and B (status=.disconnected, cd=nil) interleave:
- A reads `lastStatus=.idle` (init), takes dedup miss
- B reads `lastStatus=.idle` (init), takes dedup miss
- A writes `lastStatus=.connected`
- B writes `lastStatus=.disconnected` (overwrites A)
- A writes `lastConnectedDate=T1`
- B writes `lastConnectedDate=nil` (overwrites A)
- Both spawn MainActor Tasks. **No dedup happened.** Worse: now `lastStatus=.disconnected` but `lastConnectedDate=` is in a torn state mid-write (Swift Optional<Date> write is not atomic on 32-bit — but iOS 17+ is 64-bit only, so write tearing per se is unlikely; cross-field tearing absolutely happens).

**Secondary issue:** the `self?` optional chaining evaluates `self` **separately** for each access. If `self` is in the process of deallocating (unlikely on MainActor but conceivable), some reads see self != nil and others see nil — defensive but suboptimal.

**Why HIGH not MEDIUM:** the fix is trivial (Apple-safe `os_unfair_lock` or a 2-tuple struct field updated atomically), and the safety claim is load-bearing for the whole T-C-C3H1' rationale. Plan 08 wants verified race-free; current code is "empirically race-free on iOS 26 today but not contractually so".

**Fix options (ranked):**

1. **Promote dedup to MainActor (preferred):** move the dedup state to `lastAppliedVPNStatus`/`lastAppliedConnectedDate` which already exist on MainActor. The cost is a single MainActor Task hop per event regardless — which is fine because the original C3'-3-001 concern was "40 Tasks per second". The Task spawn itself is cheap; the MainActor body re-diff is what costs CPU, and `applyVPNStatus` already has the dedup guard at line 605-609. **The pre-hop coalescing buys very little**. We can drop the `nonisolated(unsafe)` fields entirely and rely on the existing MainActor-isolated `lastApplied*` dedup. The Task overhead per duplicate event is microseconds; the prior bottleneck was downstream SwiftUI body re-diff which is already guarded.

2. **Use `OSAllocatedUnfairLock<(NEVPNStatus, Date?)>`** to atomically read-compare-write the pair:
   ```swift
   private let observerDedup = OSAllocatedUnfairLock<(NEVPNStatus, Date?)?>(initialState: nil)
   // in observer:
   let isDup = observerDedup.withLock { current -> Bool in
       if let c = current, c.0 == status, c.1 == connectedDate { return true }
       current = (status, connectedDate)
       return false
   }
   if isDup { return }
   Task { @MainActor [weak self] in self?.applyVPNStatus(status, connectedDate: connectedDate) }
   ```

3. **Document, don't fix:** if owner accepts the iOS-26 empirical assumption, mark the comment with explicit "ASSUMES iOS delivers NEVPNStatusDidChange on a single thread per name; if Apple changes this in future iOS, switch к option 2". This is a non-trivial assumption и should not live in a one-line comment.

**Recommendation:** Option 1 (drop the pre-hop coalescing entirely). The performance argument в the docstring («pre-fix queue flooded с 40+ no-op Tasks → temporary UI stutter») is partially a misdiagnosis: the actual stutter cause was the **8k duplicate `.connected` events on the actor side** (TunnelController.handleObservedStatus dedup), not on the VM MainActor side. The VM MainActor `lastAppliedVPNStatus` guard already catches that downstream. The pre-hop dedup is belt-and-suspenders for a problem already solved.

**Effort:** Option 1 = 15 min (delete the two fields + the if-block, keep MainActor dedup). Option 2 = 25 min including a regression test ensuring `lastAppliedVPNStatus` still catches the duplicate-event storm.

---

### H-A3-4-03: `reconnectAfterSelectionChange` interaction with TunnelController single-flight can connect to the WRONG server on rapid selection-change

**Location:** `MainScreenViewModel.swift:1352-1365` (`reconnectAfterSelectionChange`) + `TunnelController.swift:376-398` (single-flight connect)

**Dimension:** Logic / correctness
**Severity:** HIGH (silent wrong-server connection after rapid selection change while connected)
**Why this matters:** T-C-C2H2' single-flight deduplicates `connect()` calls — second caller awaits the **first caller's already-in-flight operation** including any captured state (specifically: which server is provisioned). If two `reconnectAfterSelectionChange(newID:)` invocations stack within a single `_doConnect` window, the second's `provisionTunnelProfile(for: newID)` may complete AFTER the first's `tunnel.connect()` started, so the SECOND user-visible selection gets persisted into NE prefs as `cachedManager.providerConfiguration` **but the first `connect()` may already have invoked `startVPNTunnel` with the old config** OR the system reads the latest config — but the user-visible state then says "connected to A" while NE prefs say B.

**Race walkthrough:**

User in `.connected(A)` state. User taps server B in list at T=0:
1. `applySelection(B)` runs on MainActor — `selectedServerID = B`, posts `Task { reconnectAfterSelectionChange(B) }`.
2. Reconnect Task: `state = .connecting` → `tunnel.disconnect()` (single-flight Task1 — `_doDisconnect()`) → `provisionTunnelProfile(B)` → `tunnel.connect()` (single-flight Task2 — `_doConnect()` provisioning B).

User taps server C at T=200ms (impatient):
3. `applySelection(C)` — `selectedServerID = C`, posts second `Task { reconnectAfterSelectionChange(C) }`.
4. Second reconnect Task: `state = .connecting` (idempotent — already connecting) → `tunnel.disconnect()` — **single-flight: awaits Task1's value** (still running its own provision/save/stop dance) → eventually returns → `provisionTunnelProfile(C)` writes C's config to NE prefs → `tunnel.connect()` — **single-flight: awaits Task2's value** if Task2 is still in flight.

The bug:
- If Task2 has not yet hit `startVPNTunnel`, second reconnect's `provisionTunnelProfile(C)` overwrites NE prefs with C. Task2 then calls `startVPNTunnel(options: ["manualStart": true])` — iOS uses the **latest** NE prefs (= C). OK.
- **But:** if Task2 is past `startVPNTunnel` and awaiting connected status, NE prefs were saved with B's config (line 470-471), the extension already loaded B, and overwriting NE prefs with C does NOT trigger a re-read — extension stays on B. Single-flight returns Task2's success Date to the second caller, which then sees `tunnel.connect() succeeded` and sets `needsReconnectForKillSwitch = false`. Reactive driver sees `.connected` → state `= .connected(since: ...)`. UI shows "connected" but the **active server is B, not the user-selected C**.

**Sticky failure:** the user-visible state stays wrong indefinitely until the next disconnect → reconnect. Worse, `activeServerName` is derived from `selectedServerID` (which is C), so the UI label says "C" while the actual tunnel is to B — silent server impersonation from the user's POV.

**Mitigating factors:**
- The Failover-vs-explicit-selection contract (`CR-01`) intends "explicit selection NEVER substituted silently" — but THIS bug is a different surface: same-actor reentrant selection change.
- User must double-tap selection within < 5s (typical Task2 duration).
- In practice, ServerListView dismisses on selection, so the user has to re-open the list. Not zero-probability though.

**Fix options:**

1. **Cancel-and-restart pattern (preferred):** in `applySelection`, if a `reconnectAfterSelectionChange` Task is already running, cancel it before spawning the new one. Combined with the H-A3-4-01 fix (inner Task tied to caller cancellation), this ensures the first connect Task either completes provision-B-connect-B or is dropped.

   ```swift
   private var pendingReconnectTask: Task<Void, Never>?
   public func applySelection(_ id: UUID?) {
       let previousID = selectedServerID
       selectedServerID = id
       guard previousID != id else { return }
       Task { @MainActor in await refresh() }
       if case .connected = state {
           pendingReconnectTask?.cancel()
           pendingReconnectTask = Task { @MainActor [weak self] in
               await self?.reconnectAfterSelectionChange(newID: id)
           }
       }
   }
   ```

2. **Drop single-flight на `connect()` from `reconnectAfterSelectionChange`** by routing through a privileged `_forceConnect` method that bypasses the in-flight slot — но this re-opens H-A3-4-01 race surface.

3. **Bind selection version into the Task:** capture `selectedServerID` snapshot in `reconnectAfterSelectionChange` enter, verify still current after `disconnect()`, abort if changed. Cleaner but more code.

**Recommendation:** option 1 (cancel-and-restart). Pairs naturally with H-A3-4-01 fix because it depends on Task cancellation actually causing the inner Task to halt (which option 1 of H-A3-4-01 enables via the `clearInFlightConnectTask` identity check + standard structured cancellation propagation).

**Effort:** 30-45 min including a test (`test_rapid_selection_change_provisions_latest_server`).

**Telemetry / repro:** Phase 6c onboarding QA had a one-off "switched server and got the previous one" report (2026-03-XX) that we couldn't reproduce. This is a plausible root cause.

---

## MEDIUM findings

### M-A3-4-01: `applyVPNStatus(.connected)` 4-arg `resolveConnectionSince` is invoked with `sticky: state.connectionStart` — but if `state` is `.empty` early-break (line 649-650) is taken WITHOUT reading state.connectionStart. Documentation says we «preserve `.empty`», but the docstring («T-C9' future-clock guard: final `min(since, now)` clamp prevents negative timer durations...») references the clamp THAT IS APPLIED AT LINE 683 — i.e. ONLY in the default branch. So the docstring's `.empty` preservation is correct, but the line-683 `state = .connected(since: min(since, now))` clamp happens for the `default` branch only. Minor docstring/code clarity — no functional bug.

**Location:** `MainScreenViewModel.swift:648-686`
**Severity:** MEDIUM (docstring drift)
**Suggested fix:** Tighten docstring to mention the `.empty` early-break explicitly. 5 min.

### M-A3-4-02: `provisionTunnelProfile` docstring claim «PoolBuilder + validate + CDN run OUTSIDE mutex» contradicts code

**Location:** `ConfigImporter.swift:562-575`
**Severity:** MEDIUM
**Why this matters:** future maintainers reading the docstring will assume the slow PoolBuilder/validate stages can interleave across concurrent provisions. They cannot — they run inside `provisionSerializer.run { ... }`. Only the **XPC save** is outside the mutex. The performance argument (300-1000ms XPC excised) is real, but the comment lists too many things as "outside".

**Actual scope of «outside mutex»:**
- ✅ XPC save+load (`tunnelProvisioner.provisionTunnelProfile(configJSON:serverHost:)`)
- ❌ SwiftData fetch — inside
- ❌ Keychain TaskGroup — inside
- ❌ PoolBuilder — inside
- ❌ SingBoxConfigLoader.validate — inside
- ❌ CDN fronting apply — inside

**Suggested fix:** rewrite the docstring:
```swift
/// **T-C-R2' (closes A3-001 HIGH Plan 06):** narrow critical section by
/// excising the XPC save (NEPreferencesAgent's saveToPreferences +
/// loadFromPreferences, 300-1000ms) from the mutex hold. Concurrent
/// provisions can now overlap their XPC stages (NEPreferencesAgent serializes
/// internally, so this is safe).
///
/// Still inside mutex (~30-500ms total): SwiftData fetch, Keychain TaskGroup,
/// PoolBuilder.buildSingBoxJSON, SingBoxConfigLoader.validate, CDN fronting.
/// These touch shared mutable surface (ModelContext warm-up, Keychain access)
/// or are pure but cheap.
```

**Effort:** 5 min.

### M-A3-4-03: `_doConnect` doesn't release `connectInProgress` flag if `provisionTunnelProfile` throws BEFORE `defer { connectInProgress = false }`

**Location:** `TunnelController.swift:419-484`

Wait — re-read. `defer { connectInProgress = false }` is at line 425. The throw paths at 456-458 (`No VPN profile`), 470-471 (XPC save throw), 479-481 (startVPNTunnel throw), 483 (awaitConnectedStatus throw) all happen AFTER the `defer` is registered, so they will release the flag. **Actually this is fine.** Removing from MEDIUM list.

### M-A3-4-03 (replacement): `applyCurrentStateToCachedManager` retry without observer of intervening state changes can shadow watchdog updates

**Location:** `TunnelController.swift:340-372`
**Severity:** MEDIUM
**Why this matters:** during the 500ms backoff sleep between save attempts, watchdog or external `.bbtbProvisionerDidSave` notification (posted by ConfigImporter) could call `refreshCachedManager()`. The new `cachedManager` reference might be different — but the retry loop uses the **original local `manager` const** from line 346 captured before the sleep. So retry attempt #2 saves through the stale reference. If the in-memory state was mutated through the new reference (e.g. ConfigImporter persisting a new server config that replaced the providerConfiguration), the retry would write the OLD state.

**Mitigating factors:**
- TunnelController is an actor; while `_doConnect`/`_doDisconnect` is running, other actor methods queue. **But:** `applyCurrentStateToCachedManager` is called from `_doDisconnect` after `await applyCurrentStateToCachedManager()` returns to the caller. During the 500ms backoff inside the method, the actor is suspended at the sleep `await` — other queued actor methods CAN run (`.bbtbProvisionerDidSave` observer hop calls `refreshCachedManager()` which is actor-isolated).
- Worst case: stale state saved → `disconnect()` proceeds → marker is set → user sees correct UX via marker even on bad-path. Not a CRITICAL.

**Suggested fix:** re-read `cachedManager` inside the retry loop OR document the staleness window. Per re-audit context, narrow remediation is fine:
```swift
for attempt in 0..<2 {
    do {
        try await manager.saveToPreferences()
        ...
    } catch {
        if attempt == 0 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Re-fetch in case an intervening .bbtbProvisionerDidSave swapped
            // the cached reference (ConfigImporter persisted new providerConfiguration).
            if let newRef = cachedManager, newRef !== manager {
                manager = newRef  // requires var, not let
            }
        }
        ...
    }
}
```

**Effort:** 15 min including a regression test that simulates the swap.

### M-A3-4-04: `sawTerminalStatusSinceConnected` not reset by `@unknown default` switch arm — could drift if Apple adds a NEVPNStatus case

**Location:** `MainScreenViewModel.swift:722-729`
**Severity:** MEDIUM (future-compat)
**Why this matters:** the gate is set to `true` only in the `.disconnected/.invalid/.disconnecting` arm. The `@unknown default` arm (line 722) demotes state to `.idle` but does NOT touch `sawTerminalStatusSinceConnected`. If a hypothetical future NEVPN status case (say, `.suspended`) hits the `@unknown default` and represents a terminal transition, the gate stays whatever it was last time → next `.connected` may use the wrong authority resolver.

**Suggested fix:** treat `@unknown default` as terminal for gate purposes:
```swift
@unknown default:
    sawTerminalStatusSinceConnected = true  // conservative — assume terminal
    switch state {
    case .empty, .error: break
    default: state = .idle
    }
```

**Effort:** 2 min.

### M-A3-4-05: `performImport` + `handleDeepLink` reentrancy error message hardcoded English, not localized

**Location:** `MainScreenViewModel.swift:899` + `1277`
**Severity:** MEDIUM (UX)
**Current:** `"Import already in progress. Please wait for it to complete."`
**Why this matters:** all other `lastError` sources are localized via `L10n.*`. Russian RU users see English error in their alert.

**Suggested fix:** add `L10n.importInProgressBusy` key, use it in both callsites.
**Effort:** 5 min.

### M-A3-4-06: `failoverDismissTask` never cancelled on VM deinit — Task continues to run + holds a `[weak self]` reference for 5s after VM dies

**Location:** `MainScreenViewModel.swift:771-785` + `deinit:1305-1315`
**Severity:** MEDIUM (energy / test hygiene)
**Why this matters:** test churn / preview flows create-and-destroy VMs rapidly. Each `showFailoverBanner` call leaves a 5-second Task. With cascade scenarios + 10 VM instantiations, we accumulate ~50 ghost Tasks waiting. Each holds a captured `[weak self]` + a 5s sleep. Cooperative thread pool can absorb this, но on iOS 26 cold-start budget it adds Mach-port pressure.

**Suggested fix:** add to deinit:
```swift
deinit {
    failoverDismissTask?.cancel()
    ...
}
```
**Effort:** 1 min. Negligible but worth doing while touching the surrounding code.

---

## LOW findings

### L-A3-4-01: TunnelController `userIntendedConnected` flag persisted to UserDefaults via `intentStore.save(value)` — uses `.synchronize()` which is documented as discouraged

**Location:** `TunnelController.swift:119-127` (`UserIntentStore.save`)
**Severity:** LOW (Apple deprecation note)
**Why this matters:** `UserDefaults.synchronize()` is marked "discouraged" по Apple docs since iOS 12. The Phase 6d post-fix 2 comment explains the rationale (iOS killing process before async flush). Real on iPhones; the defensive synchronize is correct semantically. Just documented for future-compat audit.

### L-A3-4-02: `ExternalVPNStopMarker.suiteName`, `pendingKey`, `timestampKey` hardcoded duplication между host (TunnelController.swift:50-52) и extension (`PacketTunnelKit.ExternalVPNStopMarker`)

**Location:** `TunnelController.swift:49-56`
**Severity:** LOW (maintainability)
**Why this matters:** docstring says «Hardcoded duplication is intentional — MainScreenFeature does NOT depend directly on PacketTunnelKit». If keys ever drift, the marker silently stops working. No test asserts string equality.

**Suggested fix:** add a snapshot test that imports both modules + asserts string equality. Or extract to a small shared SPM target (single source of truth). Effort 15 min for the test, 1h for the shared target.

### L-A3-4-03: `bootstrap` returns `InitialStatusSnapshot` derived from `cachedManager?.connection.status ?? .invalid` — `.invalid` semantics differ from `.disconnected`

**Location:** `TunnelController.swift:310`
**Severity:** LOW (UX edge)
**Why this matters:** if `cachedManager == nil` after `refreshCachedManager()` (e.g. user never installed BBTB profile), snapshot says `.invalid`. `applyVPNStatus(.invalid)` falls into the `.disconnected/.invalid/.disconnecting` switch arm at line 695 — sets `sawTerminalStatusSinceConnected = true` and demotes to `.idle` (since state was `.empty`/`.error` it preserves). Actually state stays `.empty` because the early-break preserves it. **OK**. But the snapshot also short-circuits VM's own init-time seed Task. So a profile-less app skips the seed Task and lands on `.invalid` synthesis. Fine for first launch where state is `.empty` anyway.

### L-A3-4-04: `applyCurrentStateToCachedManager` applies `OnDemandRulesBuilder.applyCurrentState` ONCE before retry loop

**Location:** `TunnelController.swift:350-370`
**Severity:** LOW (defensive)
**See M-A3-4-03 above** — folded into MEDIUM-level recommendation.

### L-A3-4-05: TunnelController `private var lastHandledStatus: NEVPNStatus?` stores Optional NEVPNStatus — comparison with `!=` (line 795) treats `nil` vs `.connected` correctly, but the initial state means first event ALWAYS passes dedup

**Location:** `TunnelController.swift:202` + `795-796`
**Severity:** LOW (correctness preserved, but design comment)
**Why this matters:** the first `.disconnected` notification at cold-start (NEVPN emits at-rest events) IS processed — falls into `handleStatusChange`. The guard at line 829 then catches it (`userIntendedConnected==false` → no intent close). OK.

### L-A3-4-06: `scheduleClearManualDisconnect` uses `Task.sleep(nanoseconds: 1_000_000_000)` — `Task.sleep(for: .seconds(1))` more idiomatic Swift 6

**Location:** `TunnelController.swift:660-665`
**Severity:** LOW (style)
**Effort:** 1 min.

### L-A3-4-07: `MainScreenViewModel.tunnelController` computed var force-casts `tunnel as? TunnelController` — protocol-based access (`tunnel.handleForeground()`) preferred per `feedback_tunnelcontroller_disconnect_race`

**Location:** `MainScreenViewModel.swift:790-792`
**Severity:** LOW (architectural drift)
**Why this matters:** the comment at line 787-789 says «Exposed for iOS scenePhase wiring». But `handleForegroundReentry` itself (line 870) goes through `tunnel.handleForeground()` (protocol), so the `tunnelController` accessor isn't actually used for that wiring anymore. It MAY still be used elsewhere — check `BBTB_iOSApp.swift` / `BBTB_macOSApp.swift`. If unused → delete. If used → consider extracting the needed method to the protocol.

**Suggested fix:** grep callsites; if zero, delete. If one or two, expand protocol. Effort 10 min.

### L-A3-4-08: `applyVPNStatus` switch over `NEVPNStatus` does not handle `.disconnecting` explicitly in the `.connecting` arm but documents «.connecting/.reasserting» — `.disconnecting` falls correctly into the terminal arm at line 695, just worth a docstring mention

**Location:** `MainScreenViewModel.swift:611-694`
**Severity:** LOW (docstring)

### L-A3-4-09: `nevpnObserverLastStatus`/`Date?` initial values are `nil` — first ever real event ALWAYS passes the dedup (cannot match nil), Task spawn proceeds, applyVPNStatus's MainActor dedup also catches nil ≠ status

**Location:** `MainScreenViewModel.swift:166-167`
**Severity:** LOW (intentional cold-start behavior, just noting)

---

## Energy findings (reactive paths)

### E-A3-4-01: NEVPN observer pre-hop coalescing — drop the layer per H-A3-4-02

If H-A3-4-02 fix Option 1 is taken (drop the pre-hop fields), the Task-spawn count per duplicate event reverts к 1 Task per event. Previous concern was «40 Tasks per second flood MainActor». The MainActor body re-diff guard at line 605-609 already prevents downstream cost; spawning a MainActor Task on already-running MainActor is microsecond-level. **Energy impact of removing the pre-hop layer: negligible.**

### E-A3-4-02: `handleForegroundReentry` runs sequential awaits (1) `runIsSupportedUpgrade` detached fire-and-forget, (2) `tunnel.handleForeground()`, (3) `viewModel.handleForeground()` (1 XPC), (4) `serverListViewModel.silentForegroundRefresh()`

Three sequential awaits = ≤ 1 XPC trip total. Within DEC-06d-02 budget («≤1 XPC per significant event»). Good.

### E-A3-4-03: `refreshProbeScoresInBackground` uses `Task.detached { await self?.refreshProbeScoresInBackground() }` от `selectAutoWinner`

Within bounded probeAll cap=8. Background priority. Single-flight protection NOT present — if user double-taps Connect within 500ms during cold-DB → first triggers slow path `performPreConnectAutoSelect`, second sees cached snapshot → fires another detached refresh. Two parallel probeAll fan-outs. **MEDIUM-flagging not warranted** because individual probeAll respects cap=8; two parallel probeAll's = max 16 sockets, well within iOS limits. **LOW** at most.

---

## Healthy patterns verified

- **Single authority D-09:** `applyVPNStatus` is the only writer of `state` and `reconnectBannerState` from status events. `performToggleImpl` / `reconnectAfterSelectionChange` set `.connecting` / `.error` explicitly (command failure path), но not `.connected(since:)`. Command methods initiate, NEVPN drives.
- **NEVPN observer `queue: nil` + MainActor hop:** all four observers (`nevpnStatusObserver`, `killSwitchObserver`, `rulesUpdateObserver`, provisioner) use `queue: nil` per memory `feedback_nevpn_observer_queue_main.md`. No `.main` queue suspension trap.
- **No XPC in observer callback:** all NEVPNStatus reads come from `notification.object as? NEVPNConnection` synchronous property access. No `loadAllFromPreferences()` in callback per memory `feedback_nevpn_xpc_mach_port`. ✅
- **`connectedDate` authority over `Date()`:** `applyVPNStatus(.connected, connectedDate: cd)` uses `cd` as the primary source. Memory `feedback_connectedDate_authority_for_since` honored.
- **`scheduleClearManualDisconnect` deferred clear:** 1s lag prevents own `.disconnected` raise from being misclassified as external.
- **TaskGroup bounded concurrency in ConfigImporter Keychain reads (cap=8):** DEC-06d-04 respected.
- **`ExternalVPNStopMarker.mark()` host-side ⊕ extension-side dual peek:** marker is sticky 600s, peek-without-clear semantics на both sides. Race-free per memory `feedback_parallel_injection_audit_before_new_path` lesson.
- **`AsyncMutex` FIFO waiter queue с cancellation handler:** canonical Swift pattern, `withTaskCancellationHandler` + `withCheckedThrowingContinuation`. Plan 05 T-B5' rewrite preserved. ✅
- **`failoverDismissTask` cancel-and-replace:** Task storage prevents multi-server cascade dismiss race (A3-006 closure).
- **`importInProgress` reentrancy guard:** clean early-return + lastError surfacing on overlap (T-C-C3H2').
- **`sawTerminalStatusSinceConnected` initialized к `true`:** correct semantics (first `.connected` post-cold-start IS a fresh session).
- **Init-seed `Task` defends against duplicate XPC via `initialManagersApplied` flag and post-await recheck:** survives the bootstrap race (M1 lesson).
- **`TimelineView(.periodic)` для `ConnectionTimer`:** native SwiftUI scheduling, view-suspended state pauses ticks (Wave 06D-03d H5 fix).

---

## Cross-validation hints (for cross-AI review)

- **H-A3-4-01 (single-flight cancellation):** the bug is structural, the fix is local (Task lifecycle decoupling). C2 / C3 reviewers should independently spot the `defer-on-caller-not-on-task` pattern.
- **H-A3-4-02 (NEVPN observer race claim):** check Apple's `NotificationCenter` thread guarantees from another angle. Likely flagged by anyone who reads the docstring closely vs the Apple documentation.
- **H-A3-4-03 (reconnect-after-selection race):** requires understanding both `applySelection` flow AND the new TunnelController single-flight semantics. Will likely be missed by reviewers who only look at one file at a time.

---

## Recommendation

🟢 **Internal TestFlight (≤100 testers) — SHIP from `ccbce8a`.**

Findings here are subtle, narrow, и require either rare timing or future iOS changes to manifest. None blocks internal rollout where testers' direct feedback is the goal.

🟡 **External rollout (open beta / production) — Fix 2 HIGH (≤1h):**

| Finding | Effort | Why |
|---|---|---|
| H-A3-4-01 — TunnelController single-flight cancellation leak | 20-30 min | T-C-C2H2' was meant to close exactly this race surface; the current implementation accidentally re-opens it under cancellation. Without this fix, T-C-C2H2' is structurally incomplete. |
| H-A3-4-02 — NEVPN observer pre-hop coalescing safety claim | 15 min (drop layer) | The MainActor `lastAppliedVPNStatus` dedup already protects against duplicate-event storms. The pre-hop layer adds latent race surface for negligible benefit. Drop and rely on MainActor dedup, OR upgrade to `OSAllocatedUnfairLock`. |

🟡 **Pre-external recommended (≤1h):**

| Finding | Effort |
|---|---|
| H-A3-4-03 — `applySelection` cancel-and-restart pattern | 30-45 min |

🔵 **Post-TestFlight / v1.0.1 polish:**

- M-A3-4-02 — `provisionTunnelProfile` docstring drift (5 min)
- M-A3-4-03 — applyCurrentStateToCachedManager staleness window doc/fix (15 min)
- M-A3-4-04 — `@unknown default` arm gate set (2 min)
- M-A3-4-05 — `importInProgressBusy` localization (5 min)
- M-A3-4-06 — `failoverDismissTask` deinit cancel (1 min)
- L-A3-4-01 through L-A3-4-09 — code style + future-compat batch (~30 min)

---

## Reviewer notes / metadata

- **Files read in full:** `MainScreenViewModel.swift` (1366 lines), `TunnelController.swift` (852 lines)
- **Files read in detail:** `ConfigImporter.swift` (heads + provisionTunnelProfile region, lines 1-260 + 541-800)
- **Files read for shape:** `ConnectionState.swift`, `ConnectionTimer.swift`, `ManagerSelector.swift` (sizes only)
- **Tests cross-referenced:** `ResolveConnectionSinceTests.swift` (10 tests, all green per Plan 07), `ApplyVPNStatusGuardTests.swift` (3 tests covering idempotency + transitions). No direct unit test for the new single-flight Task storage or pre-hop coalescing fields.
- **No edits made** (read-only baseline preserved).

---

## Confidence

- HIGH on H-A3-4-01 (Swift Task semantics well-understood; cancellation propagation from outer caller to unstructured Task is a documented gap).
- HIGH on H-A3-4-02 (Apple docs on `NotificationCenter` cross-thread serialization are silent; the assumption is conventional but not contractual).
- MEDIUM-HIGH on H-A3-4-03 (the race window is narrow в milliseconds; requires user impatience; mitigated by `state.connecting` UI feedback). Real-world telemetry would need to confirm frequency; static analysis says the race is possible.
- HIGH on closure verdicts (T-C-R1' ✅, T-C-R2' ✅, T-C-C2H1' ✅, T-C-C3H2' ✅, T-C-B2 ✅; T-C-C2H2' ⚠️ partial; T-C-C3H1' ⚠️ partial).

---

**End of A3 — MainScreenFeature audit.**
