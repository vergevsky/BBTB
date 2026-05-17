# A3 — AppFeatures/MainScreenFeature Plan 06 audit (Opus 4.7, baseline fb2ff54)

**Scope:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` (29 files, ~6,600 LOC). Tests excluded per A3-PROMPT.
**Dimensions:** Thread Safety + Logic + Energy (per A3-PROMPT — reactive paths, mutex correctness post-T-B5', T-C9' edge cases, XPC trip counts, polling loops).
**Verdict at end of file.**

---

## 1 — Plan 05 closure verification (T-B5', T-C9', T-B7)

| Task | Claim | Verified? | Evidence |
|---|---|---|---|
| **T-B5'** (`2952871`) | `ProvisionSerializer` rewritten as real async mutex via `CheckedContinuation` FIFO queue. Closes A3'-001 / C3'-001 HIGH (Plan 04 partial). | **PASS** | `ConfigImporter.swift:74-130` — `private actor AsyncMutex` with `locked: Bool` + `waiters: [(id, CheckedContinuation)]`. `acquire()` returns immediately if not locked, else `withCheckedThrowingContinuation` parked in `waiters`. `release()` FIFO-pops next waiter or marks unlocked. `withTaskCancellationHandler` removes cancelled waiter via `cancelWaiter(_:)`. `ProvisionSerializer.run` wraps `acquire/op/release` with `defer { Task { await mutex.release() } }`. **True mutual exclusion across `await` suspension points** — second caller blocks at `mutex.acquire()` until first releases, satisfying the original A3-005 invariant. |
| **T-C9'** (`81d7ea6`) | `resolveConnectionSince(cd:cs:now:)` helper with 60s stale threshold + future-clock clamp. Closes C3'-002 MEDIUM (stale prev-session). | **PASS structurally** | `MainScreenViewModel.swift:492-510` — `staleConnectionStartThreshold: TimeInterval = 60`, helper picks `cd` over stale `cs` when `cd - cs > 60s`, else `min(cd, cs)` for within-session WireGuard race. `cd=nil` branch: `now` if `now - cs > 60s`, else `cs`. Both terminal branches reached. Caller at line 586-591 wraps result in `min(since, now)` future-clock clamp. ✅ Logic traces clean. ⚠️ See A3-002 below for one edge case the helper does NOT cover (long-suspended legitimate connection). |
| **T-B7** (`e2173d0` — ImportHandler) | Out of scope for MainScreenFeature; T-B7 changes live in DeepLinks. Listed for completeness only. | **N/A** | Not touched in this audit's scope. |

**Plan 04 carry-forward closures (re-verified from A3'-001..011):**

| ID | A3' status (Plan 04) | A3 (Plan 06) status |
|---|---|---|
| A3'-001 HIGH (serializer covers full 1-3s pipeline) | Open | ⚠️ **Still present** — see A3-001 below. T-B5' fixed reentrancy correctness but did NOT narrow the critical section per the suggested fix. |
| A3'-002 HIGH (`rethrows` dead code) | Open | ✅ **Closed** — `ProvisionSerializer.run` now declares `async throws -> T` (line 122). `rethrows` removed. |
| A3'-003..010 MEDIUM/LOW | Carry-forward | Still present; not re-reported per prompt. |

---

## 2 — New findings (thread safety + logic + energy)

### [HIGH] A3-001: `ProvisionSerializer.run` STILL serializes the entire ~1-3s provisioning pipeline; failover starvation persists post-T-B5'

- **Location:** `ConfigImporter.swift:122-129` (run wrapper) + `567-770` (`_provisionTunnelProfileInternal` body).
- **Dimension:** logic, energy, latency.
- **Description:** T-B5' correctly fixed the **reentrancy bug** (actor-isolation gap across `await`), but the suggested narrowing from Plan 04 A3'-001 was NOT applied. The mutex now covers:
  1. Single SwiftData fetch (`context.fetch(supportedDesc)`) — ~10-30ms.
  2. **Auto-mode TaskGroup of up to 8 concurrent Keychain reads** for N supported servers — ~100-500ms for 50 servers.
  3. CDN fronting overlay (FrontingConfigApplier.apply) — fast.
  4. **PoolBuilder.buildSingBoxJSON** — JSON synthesis for N outbounds, ~50-200ms.
  5. **SingBoxConfigLoader.validate** (R1 self-validate) — parses + validates 50-outbound JSON, ~100-300ms.
  6. **`tunnelProvisioner.provisionTunnelProfile` XPC** — `loadAllFromPreferences + saveToPreferences + loadFromPreferences`, **300-1000ms on contended Mach port**.

  Concurrent callers blocked on entire chain:
  - `SwiftDataFailoverProvider.attempt` closure → `provisioner.provisionTunnelProfile(for: nextID)` (FailoverProvider.swift:162).
  - `MainScreenViewModel.reconnectAfterSelectionChange` (line 1225).
  - `MainScreenViewModel.performToggleImpl` (line 823, 826).
  - **Any concurrent user retap during in-flight Connect.**

  **Concrete scenario:**
  1. T=0: User taps Connect (Auto, 50 servers). Mutex acquired. TaskGroup probes 50 Keychain reads (~400ms). PoolBuilder + validate (~300ms). XPC save (~800ms). Total ~1500ms holding mutex.
  2. T=200ms: Watchdog fires failover (older server unreachable). `nextServerAttempt.attempt()` → blocks at `mutex.acquire()`.
  3. T=1500ms: First call returns. Failover provision unblocks, executes another ~1500ms.
  4. T=3000ms: `awaitConnectedStatus` from step 1 has already thrown timeout (`-3` after 30s would normally be fine but the failover's `tunnel.connect()` in step 2's `attempt` closure now races the original's outstanding `tunnel.connect()` — both refer to the same `cachedManager`, the second `startVPNTunnel` may be applied to a half-saved configuration).

- **Why HIGH:** Failover starvation on slow networks (50+ server pool, weak signal). Watchdog promised mid-session failover; mutex now defers it by 1-3s. Plus the post-await second `tunnel.connect()` competes with the first's `manualDisconnectInProgress` / `connectInProgress` state machine.
- **Suggested fix:** Apply the original A3'-001 suggestion — split `provisionTunnelProfile(for:)` into critical section (SwiftData fetch + Keychain reads = ~30-500ms) and non-critical (PoolBuilder + validate + XPC = ~400-1300ms). Mutex protects ONLY the critical section. Concurrent callers serialize fetches but parallelize XPC saves (NEPreferencesAgent serializes XPC internally, so no harm).

  ```swift
  public func provisionTunnelProfile(for selectedID: UUID?) async throws {
      let (parsedList, dns, serverHost) = try await provisionSerializer.run { [self] in
          try await fetchAndReparse(for: selectedID)  // SwiftData + Keychain
      }
      // Outside mutex:
      let json = try await buildPoolJSON(parsedList: parsedList, dns: dns, selectedID: selectedID)
      try await tunnelProvisioner.provisionTunnelProfile(configJSON: json, serverHost: serverHost)
  }
  ```

---

### [HIGH] A3-002: `resolveConnectionSince` 60s stale threshold INCORRECTLY discards legitimate `state.connectionStart` after suspend/resume — timer resets after ≥60s background

- **Location:** `MainScreenViewModel.swift:494-510` (T-C9' helper).
- **Dimension:** logic, UX.
- **Description:** The threshold logic is asymmetric:
  ```swift
  if let cd, let cs {
      return cd.timeIntervalSince(cs) > staleConnectionStartThreshold ? cd : min(cd, cs)
  }
  ```
  `cd.timeIntervalSince(cs)` is positive when `cd > cs`. The doc-comment claims `cs` is "stale prev-session" when "часы/дни old" — but the actual algebra also fires when **`cd` is legitimately later than `cs` by >60s** in a SINGLE session.

  **Concrete scenario (suspend → resume after long background):**
  1. T=0: User connects. `applyVPNStatus(.connected, cd=T0)` → `cs == nil` branch → `state.connectionStart = cd = T0`.
  2. T=70s: App backgrounded. iOS suspends VPN process. Tunnel stays up.
  3. T=10min: User foregrounds. `handleForeground()` → `applyVPNStatus(.connected, cd=NEW)` where `cd=NEW` is `manager.connection.connectedDate`.

     But here's the rub: `NEVPNConnection.connectedDate` **returns the moment of the LAST `.connected` transition**, which may have been updated by iOS during foreground (NEVPN extension internally restarted). So `cd=NEW` could be `T0 + 5min` (iOS reasserted at T=5min). `cs = T0`. `cd - cs = 5min > 60s` → helper picks `cd=NEW`. Timer jumps from "10:00" to "05:00".

  4. **Worse case:** if `cd=NEW` happens to be near `now` (iOS just reconnected on foreground), timer drops to 00:00:00 even though VPN had real uptime.

  The 60s threshold is meant to discriminate "intra-session WireGuard 5s race" from "cross-session hours leak", but **real iOS sessions get ≥60s spans between `cd` updates within the same logical user session** every time:
  - iOS Wi-Fi handoff to cellular → NE reasserts → new connectedDate.
  - Long background → next foreground event → fresh connectedDate snapshot.
  - On-demand re-fire after network blip → fresh connectedDate.

- **Why HIGH:** Timer regression. T-C9' was supposed to FIX C3'-002 (stale prev-session) but the threshold is too aggressive. Pre-T-C9' (`min(cd, cs)`) would have kept the correct `T0` value in all the above scenarios.

  **Telemetry indicator:** Phase 6 reUAT showed "Замечание 1 — timer resets on foreground" exactly because of this class of behavior. Pre-T-C9' history shows that historically the team kept choosing `cs` as authority for this reason. T-C9' introduces a regression here.

- **Suggested fix:** Remove the 60s threshold for the within-session case OR raise it to a clearly inter-session value (e.g. 24h). The within-session WireGuard race is `cd > cs` by ≤5s; the cross-session leak is `cd` being a fresh new connection where `cs` is from PREVIOUS session disconnect/reconnect cycle — that gap is always >>1h (user had to background app + Settings round-trip + new launch).

  Simpler fix: gate on user-intent transitions. Only reset `state.connectionStart` to `cd` if intervening `.disconnected`/`.idle` was observed since the previous `.connected`. Add `private var lastTerminalStatus: NEVPNStatus?` — if it transitioned through `.disconnected` since last `.connected`, take `cd`; else preserve `min(cd, cs)`.

---

### [MEDIUM] A3-003: `applyInitialStatusSnapshot` and init-time seed Task have a Time-Of-Check-Time-Of-Use race on `initialManagersApplied`

- **Location:** `MainScreenViewModel.swift:286-296` + `642-646`.
- **Dimension:** thread safety, logic.
- **Description:** The init-time seed Task at line 286 is:
  ```swift
  Task { @MainActor [weak self] in
      guard let self, !self.initialManagersApplied else { return }
      let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
      // Recheck — bootstrap could have flipped the flag while await above suspended.
      guard !self.initialManagersApplied else { return }
      let ours = ManagerSelector.ourManagers(from: managers).first
      let initialStatus = ours?.connection.status ?? .invalid
      let initialConnectedDate = ours?.connection.connectedDate
      self.initialManagersApplied = true
      self.applyVPNStatus(initialStatus, connectedDate: initialConnectedDate)
  }
  ```
  And `applyInitialStatusSnapshot` (called from `TunnelController.bootstrap`):
  ```swift
  public func applyInitialStatusSnapshot(_ snapshot: InitialStatusSnapshot) {
      guard !initialManagersApplied else { return }
      initialManagersApplied = true
      applyVPNStatus(snapshot.status, connectedDate: snapshot.connectedDate)
  }
  ```

  Race window:
  1. T=0: VM init. Seed Task enqueued (T1).
  2. T=10ms: T1 starts. Reads `initialManagersApplied=false` → passes first guard → awaits `loadAllFromPreferences`.
  3. T=12ms: App.init's `tunnel.bootstrap(...)` finishes. `applyInitialStatusSnapshot` invoked on MainActor — synchronous. Checks `!initialManagersApplied` (true) → flips to true → calls `applyVPNStatus(snapshot)`.
  4. T=50ms: T1's `await` resumes. Re-checks `!initialManagersApplied` (now true) → returns. **Correct — no double-apply.**

  But! Reverse ordering:
  1. T=0: VM init. Seed Task enqueued.
  2. T=2ms: Seed Task starts. Passes guard. Begins `await loadAllFromPreferences()`. **Critically: `initialManagersApplied` is NOT yet flipped to `true`.**
  3. T=3ms: `tunnel.bootstrap(...)` (App.init's other Task) starts. Inside bootstrap, refreshCachedManager makes its XPC call.
  4. T=8ms: bootstrap returns InitialStatusSnapshot. Caller invokes `applyInitialStatusSnapshot` synchronously on MainActor — sets flag true, calls applyVPNStatus.
  5. T=50ms: Seed Task's await resumes. Re-check: `initialManagersApplied=true` → bail. ✓

  Still fine. But what about — **TunnelController.bootstrap is async** and the App.init might **await** bootstrap on a non-MainActor Task. Then the snapshot delivery may serialize behind MainActor tasks already queued.

  **Actual concern:** If T1 (seed) calls `applyVPNStatus` and `applyInitialStatusSnapshot` is queued BEHIND T1, T1 sets `initialManagersApplied=true` AND `applyVPNStatus(.invalid_or_stale_state)`, THEN snapshot path checks `initialManagersApplied == true` → returns silently → the actual fresh snapshot from bootstrap is DISCARDED. User sees stale state until next NEVPNStatusDidChange.

  In practice both paths read the same `cachedManager` value (one in VM, one in TunnelController), so the apply'd status should be congruent. But the seed Task uses its OWN `loadAllFromPreferences` — different timing → can read a different snapshot than bootstrap's. The discard becomes user-visible.

- **Why MEDIUM:** Two XPC trips race; first-winner's snapshot wins; user may see stale state for 0-100ms post cold start.
- **Suggested fix:** Replace the seed Task with a single oracle. Either:
  - Remove seed Task entirely if `applyInitialStatusSnapshot` is guaranteed to be called by the App layer (verify in BBTB_iOSApp / BBTB_macOSApp).
  - OR have the seed Task await `applyInitialStatusSnapshot` not `applyVPNStatus` (so it goes through same gate).

---

### [MEDIUM] A3-004: `handleForegroundReentry` chains two awaits to the same TunnelController.handleForeground + VM.handleForeground → both potentially XPC

- **Location:** `MainScreenViewModel.swift:759` + `769`.
- **Dimension:** energy, XPC accounting.
- **Description:**
  ```swift
  await tunnel.handleForeground()  // TunnelController.handleForeground = no-op currently
  await handleForeground()           // VM.handleForeground = 1 XPC trip (loadAllFromPreferences)
  ```
  Both run sequentially on MainActor per `scenePhase .active`. Total: 1 XPC + however long iOS coalesces it.

  Plus: `serverListViewModel?.silentForegroundRefresh()` (line 773) — known to make HTTPS calls to subscription URLs (Phase 3 Plan 04 D-12). On a foreground re-entry where user JUST tapped Connect, this can fire HTTPS while extension is starting → bandwidth contention.

  Also: `Task.detached(priority: .background)` at line 748 spawns `importer.runIsSupportedUpgrade` which itself does SwiftData fetch + N concurrent parser invocations + N Keychain writes. Background-priority detached, so unlikely to compete with foreground UI, but worth noting it's all unbounded.

  **DEC-06d-02 compliance check:** "≤1 XPC trip per significant scene event" — handleForegroundReentry calls 1 XPC (VM.handleForeground). ✓ Within budget. BUT if `tunnel.handleForeground` is ever extended to add XPC (currently no-op per line 613), the contract silently breaks because the call site doesn't gate on it.

- **Why MEDIUM:** Defensive coding gap. Today's behavior is fine; future extension of `tunnel.handleForeground` would silently regress XPC budget.
- **Suggested fix:** Add a contract assertion comment at line 759 and `TunnelController.handleForeground` (line 613): "MUST remain ≤1 XPC trip combined with VM.handleForeground; if you add XPC here, remove it from VM.handleForeground."

---

### [MEDIUM] A3-005: `nonisolated(unsafe)` observer fields mutated from `wireRulesCoordinator` (async MainActor) — comment "only init/wireRulesCoordinator" doesn't account for `removeObserver` race against `deinit`

- **Location:** `MainScreenViewModel.swift:114, 147, 158` (declarations) + `1050-1052` (re-wire path).
- **Dimension:** thread safety.
- **Description:** `rulesUpdateObserver` is `nonisolated(unsafe) var`. `wireRulesCoordinator` (line 1047) is `public func ... async` — body runs on MainActor due to class `@MainActor`. Code:
  ```swift
  if let token = rulesUpdateObserver {
      NotificationCenter.default.removeObserver(token)
      rulesUpdateObserver = nil
  }
  ...
  rulesUpdateObserver = NotificationCenter.default.addObserver(...) { ... }
  ```
  Concurrent risk:
  1. T1 (MainActor): `wireRulesCoordinator` called (re-wire). Reads `rulesUpdateObserver=tokenA`. Awaits something internally? No — `removeObserver` + `addObserver` are sync. BUT the function is `async` and the `let snapshot = await coordinator.currentSnapshot()` at line 1056 IS an await suspension. After this `await`, MainActor isolation is RELEASED.
  2. T2 (any thread): `deinit` fires. Reads `rulesUpdateObserver` — `nonisolated(unsafe)` so no isolation check. If T1 has set `rulesUpdateObserver = nil` BEFORE the await, T2 reads `nil` → OK. But if T1 is suspended at the await BEFORE removing/setting → T2 might read the OLD `tokenA` and remove it → T1 resumes, tries to set new observer assuming oldToken state had been cleared. The newly added observer would NOT have its predecessor removed.

  Then later, `deinit` would only see ONE token to remove, but TWO observers are leaking. Concrete: every re-wire after concurrent deinit-race leaks an observer.

  **Probability:** Very low — VM `deinit` is typically `.detached` flow at app teardown when wireRulesCoordinator is never being re-invoked. But if any test or future flow recreates VM mid-flight, race is real.

  Doc-comment at line 113 says "only written from MainActor (init / wireRulesCoordinator)" — but `wireRulesCoordinator` has an `await` suspension which releases MainActor isolation, AND `nonisolated(unsafe)` opt-out means the compiler cannot enforce the ordering. The combined contract is brittle.

- **Why MEDIUM:** Subtle. Likely not hit in TestFlight Internal. Pre-existing pattern (A3'-003 carry-forward).
- **Suggested fix:** Move the await BEFORE the observer dance:
  ```swift
  public func wireRulesCoordinator(_ coordinator: RulesEngineCoordinator) async {
      self.rulesEngineCoordinator = coordinator
      // Snapshot capture FIRST (await).
      if let snapshot = await coordinator.currentSnapshot() {
          self.lastObservedRulesSnapshot = snapshot
      }
      // Observer dance: now no await between read/remove/add.
      if let token = rulesUpdateObserver { NotificationCenter.default.removeObserver(token) }
      rulesUpdateObserver = NotificationCenter.default.addObserver(...) { ... }
  }
  ```

---

### [MEDIUM] A3-006: `showFailoverBanner` 5s auto-dismiss task is STILL not cancelled on re-arm — multi-server cascade can show second banner for <5s

- **Location:** `MainScreenViewModel.swift:663-674`.
- **Dimension:** UX.
- **Description:** A3'-009 carry-forward (per Plan 04 A3' file). Code:
  ```swift
  public func showFailoverBanner(toServerName: String) {
      reconnectBannerState = .failover(toServerName: toServerName)
      Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(5))
          guard let self else { return }
          if case .failover = self.reconnectBannerState {
              self.reconnectBannerState = .hidden
          }
      }
  }
  ```
  Sequence:
  1. T=0: `showFailoverBanner("Server A")`. Task-1 spawned, sleeps until T=5s.
  2. T=2s: Server A failed too. `showFailoverBanner("Server B")`. Task-2 spawned, sleeps until T=7s.
  3. T=5s: Task-1 wakes. State is still `.failover` (Server B label). Pattern-match passes → `reconnectBannerState = .hidden`. **Server B banner disappears after 3s instead of 5s.**

  Plus: when banner is dismissed externally by NEVPN-driven `applyVPNStatus(.connected)` (line 597) or `applyVPNStatus(.disconnected/.invalid)` (line 615), the lurking Task is NOT cancelled — it's still scheduled to fire. If a new failover arrives BEFORE that lurker fires AND lurker's `if case .failover` matches the NEW one, same bug.

  Plan 04 noted this as carry-forward LOW. Re-rating to **MEDIUM** for this audit cycle because TestFlight will surface multi-server failover scenarios that haven't been exercised in dev.

- **Why MEDIUM:** UX inconsistency in failover cascade. Not a blocker but noticeable when chain failover occurs.
- **Suggested fix:** Store the task and cancel on each re-arm:
  ```swift
  private var failoverDismissTask: Task<Void, Never>?
  public func showFailoverBanner(toServerName: String) {
      reconnectBannerState = .failover(toServerName: toServerName)
      failoverDismissTask?.cancel()
      failoverDismissTask = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(5))
          guard !Task.isCancelled, let self else { return }
          if case .failover = self.reconnectBannerState {
              self.reconnectBannerState = .hidden
          }
      }
  }
  ```

---

### [MEDIUM] A3-007: `Task.detached { [weak self] in await self?.refreshProbeScoresInBackground() }` spawns from `selectAutoWinner` without cancellation tracking → multiple concurrent background probe storms

- **Location:** `MainScreenViewModel.swift:905-907`.
- **Dimension:** energy, thread safety.
- **Description:**
  ```swift
  Task.detached { [weak self] in
      await self?.refreshProbeScoresInBackground()
  }
  ```
  Called every time `selectAutoWinner` returns via fast path (cache hit). User rapid-taps Connect (e.g. error → retry) → spawns N background probe storms in parallel. Each storm:
  - Re-fetches all supported ServerConfigs (SwiftData round trip).
  - Calls `probeService.probeAll(...)` — bounded concurrency cap 8, but each storm has its own pool of 8.
  - Writes back `lastLatencyMs`, `failedProbeCount`, `lastPingedAt` to SwiftData (same rows).
  - Updates `supportedServerSnapshot` (`@Published` write).

  **Concurrent SwiftData writes race:** two background tasks could write to the same `row.lastLatencyMs` for the same ServerConfig instance from different `ModelContext`s. SwiftData semantics around this are: each context gets its own snapshot; on `save()`, conflicts merged via store coordinator. **Best case:** newer write wins. **Worst case:** observed in past phases (per `feedback_swiftdata_uuid_predicate.md`-class issues), SwiftData ON DEVICE may raise NSPersistentStoreConflict.

  Plus: refreshProbeScoresInBackground is **NOT** annotated `@MainActor` despite the comment claiming "Метод сам исполняется на MainActor (как и весь VM)". Looking at the function — its containing class is `@MainActor` (class-level), so the actual method IS MainActor isolated. But `Task.detached` LEAVES MainActor for the await call. The await of `self?.refreshProbeScoresInBackground()` then re-enters MainActor. **OK, but the comment is misleading** — the body is MainActor, but the `Task.detached` itself doesn't preserve isolation across `await`.

  Bigger concern: probeAll AsyncStream consumption (line 934) runs on MainActor → main thread does TCP probes — should be Task.detached on cooperative pool for I/O. ServerProbeService probably handles this internally but worth confirming.

- **Why MEDIUM:** Energy + correctness. Rapid Connect taps can spawn 5-10 parallel background probe storms with overlapping SwiftData writes. iPhone battery + potential SwiftData write conflict.
- **Suggested fix:** Single-flight pattern:
  ```swift
  private var backgroundProbeTask: Task<Void, Never>?
  private func selectAutoWinner() async throws -> UUID {
      ...
      // Only spawn if no in-flight task.
      if backgroundProbeTask?.isCancelled ?? true {
          backgroundProbeTask = Task.detached { [weak self] in
              await self?.refreshProbeScoresInBackground()
              await MainActor.run { [weak self] in self?.backgroundProbeTask = nil }
          }
      }
      return winnerID
  }
  ```

---

### [MEDIUM] A3-008: `applyVPNStatus` inner-state mutations write @Published on every state-machine cycle → SwiftUI body re-diff on every transition pair

- **Location:** `MainScreenViewModel.swift:512-627`.
- **Dimension:** energy (SwiftUI re-diff cost), latency.
- **Description:** The outer `lastAppliedVPNStatus` / `lastAppliedConnectedDate` dedupe (lines 516-520) blocks **identical** events. But the inner state-machine mutates `@Published var state` AND `@Published var reconnectBannerState` independently. Sequence:
  1. Status `.connecting` arrives, lastApplied=nil. Dedupe miss. Sets `state = .connecting`. **SwiftUI re-diff #1.**
  2. Banner-switch fires: `reconnectBannerState = .connecting`. **SwiftUI re-diff #2** (separate publish).
  3. Status `.connected` arrives. Dedupe miss. Sets `state = .connected(since: T)`. **Re-diff #3.**
  4. Banner-switch: `.connecting → .hidden`. **Re-diff #4.**

  Plus on `.connected` path: `since = Self.resolveConnectionSince(...)` → computes; **wrapped in `min(since, now)`** at line 591. If `since` differs from previous `state.connectionStart` by even 1µs, that's a NEW `state` value (Equatable check inside @Published?). SwiftUI Equatable check on `ConnectionState` (line 3 of ConnectionState.swift) compares `.connected(since: A)` vs `.connected(since: B)` → different `Date` → publish fires re-diff even though semantically equivalent.

  Per memory `feedback_phase6d_architectural_patterns.md` — DEC-06d-03 event-driven, but `Date` equality is razor-thin (sub-second precision).

  **Practical impact:** modest. SwiftUI is cheap on a single body re-eval. But on every `.connected` echo, `since` may shift by ≤1s due to NEVPN updating `connectedDate` mid-session → body re-diffs every echo. The 8k duplicate event class was supposedly fixed by `lastAppliedConnectedDate` dedupe AND the lower-level TunnelController `lastHandledStatus` dedupe — but `lastAppliedConnectedDate` keys on `Date?` Equatable which uses absolute time → ANY tiny update breaks dedupe.

- **Why MEDIUM:** Defense-in-depth concern. Today's flow with the two-level dedupe (TunnelController `handleObservedStatus` + VM `applyVPNStatus`) is probably fine. But the inner `since` Date equality means SwiftUI keeps re-rendering ConnectionTimer/StatusPill on every echo where iOS updates connectedDate.
- **Suggested fix:** Add a "since within 1s" guard before resetting `state = .connected(since: ...)`:
  ```swift
  if case let .connected(currentSince) = state,
     abs(currentSince.timeIntervalSince(since)) < 1.0 {
      // Same session, sub-second since drift — preserve current state value.
      break
  }
  state = .connected(since: min(since, now))
  ```

---

### [LOW] A3-009: `TunnelController.makeStatusStream` retains `self` strongly inside `AsyncStream` builder closure

- **Location:** `TunnelController.swift:196-205`.
- **Dimension:** thread safety, memory.
- **Description:**
  ```swift
  private func makeStatusStream() -> (id: UUID, stream: AsyncStream<NEVPNStatus>) {
      let id = UUID()
      let stream = AsyncStream<NEVPNStatus> { continuation in
          self.statusContinuations[id] = continuation  // ← self captured strongly
          continuation.onTermination = { [weak self] _ in
              Task { [weak self] in await self?.removeStatusContinuation(id) }
          }
      }
      return (id, stream)
  }
  ```
  The AsyncStream builder closure captures `self` strongly to write to `statusContinuations`. This builder closure runs **once** at stream creation, so the strong ref is short-lived — the closure is released after construction. **OK in theory.**

  Actually re-reading: `AsyncStream<T> { (continuation: Continuation) -> Void in ... }` — Swift's `AsyncStream` runs the builder eagerly to set up the continuation; once it returns, no closure retained.

  **Verdict:** Not a leak. False alarm. Leaving here as **VERIFIED HEALTHY** for the audit trail.

---

### [LOW] A3-010: `handleStatusChange` reads `cachedManager?.isEnabled` synchronously from actor BUT cachedManager is mutated via `refreshCachedManager` from observer Task — observer-spawned Task can race the synchronous read

- **Location:** `TunnelController.swift:692-696`.
- **Dimension:** thread safety.
- **Description:** Reading `cachedManager?.isEnabled` on actor TunnelController is actor-isolated (safe). Mutating `cachedManager` only happens inside `refreshCachedManager` (line 283) — also actor-isolated. So actor isolation prevents races.

  BUT — `NETunnelProviderManager` itself is a reference type. The actor holds a reference. iOS may mutate the manager's `.isEnabled` property out-of-band (when user toggles VPN in Settings). When the actor reads `cachedManager?.isEnabled` on a different actor "tick" than when `refreshCachedManager` populated `cachedManager`, the iOS underlying property can have changed.

  **This is by design** — `manager.isEnabled` is the cached-on-disk profile state, kept in sync by NE preferences manager. Read is sync and cheap. No XPC trip. ✓

  **Verdict:** Not a defect. The read is read-snapshot-of-iOS-state, which is exactly the contract Phase 6c relied on. Leaving as **VERIFIED HEALTHY**.

---

### [LOW] A3-011: `OnDemandMigrationTask.runIfNeeded` not guarded against concurrent execution; double app launch / re-init can cause double migration

- **Location:** `OnDemandMigrationTask.swift:62-130`.
- **Dimension:** thread safety, idempotency.
- **Description:** `runIfNeeded` is a static func with no in-flight guard. The flag-check at start (`userDefaults.bool(forKey: migratedKey)`) is the only gate; if two callers enter simultaneously (both saw `false`), both proceed to:
  - Load preferences (2 XPC trips).
  - Apply OnDemandRules + save + load (4 XPC trips per call).
  - Set flag at end.

  Concrete risk: BBTB_iOSApp.init might call this on launch + scenePhase observer might call it on first foreground transition before init's call returned. Both see flag=false, both proceed.

  Real-world: probably never hits — App.init is the only known caller, and runs once. But defensive coding suggests an in-flight Task<Void, Never>? lock pattern.

- **Why LOW:** Pre-existing pattern. Not a new defect introduced by Plan 05. Carry-forward priority backlog.
- **Suggested fix:** Add `private static var inflight: Task<Void, Never>?`. Wrap body in `if inflight == nil { inflight = Task { ... }; await inflight?.value }` pattern.

---

### [LOW] A3-012: `Notification.Name.bbtbProvisionerDidSave` observer in `TunnelController.startReachability` fires `Task { await self?.refreshCachedManager() }` per notification — no debounce for batched provisioning

- **Location:** `TunnelController.swift:585-589`.
- **Dimension:** energy.
- **Description:** Three callsites POST this notification:
  - `ConfigImporter.DefaultTunnelProvisioner.provisionTunnelProfile` (single post per provision).
  - `SettingsViewModel.applyAutoReconnectToManager` (multi-manager loop posts N times per OnDemandMigrationTask comment).
  - `OnDemandMigrationTask` (single post per migration).

  Per notification, the observer spawns a Task that does `loadAllFromPreferences` (1 XPC). If 5 managers exist (rare multi-install case) and SettingsViewModel posts 5 times, that's 5 XPC trips back-to-back. iOS will probably coalesce, but the Task spawn rate on the actor is 5 per ~10ms.

  Pre-existing pattern. Carry-forward.

- **Why LOW:** Unlikely to hit in practice. Single-install case = 1 post per event. Multi-install requires user-mixed installs.
- **Suggested fix:** Add a 250ms debounce on the refreshCachedManager task — cancel pending + reschedule. Use the existing actor's `scheduleClearManualDisconnect` pattern for inspiration.

---

### [LOW] A3-013: `ConfigImporter.runIsSupportedUpgrade` doesn't honor `Task.isCancelled` between candidates

- **Location:** `ConfigImporter.swift:1179-1230`.
- **Dimension:** energy, responsiveness.
- **Description:** Loop iterates candidates, each iteration awaits `uParser.import` (HTTPS + parsing). If the parent Task is cancelled (e.g. app backgrounded, scenePhase → .inactive cancels detached background tasks), the loop continues. No `try Task.checkCancellation()` inside.

  Per memory `feedback_phase6d_architectural_patterns.md` DEC-06d-01: cold-start defer pattern says these long-running tasks should be cancellable on background transitions.

  Carry-forward from A3-010 / A3'-010 (Plan 02 / 04 carry-forward). Not introduced by Plan 05.

- **Why LOW:** Minor energy waste — task continues for ~5-30s on background and may issue HTTPS requests post-suspend.
- **Suggested fix:** Add `try? Task.checkCancellation()` at top of loop body. Or `guard !Task.isCancelled else { break }`.

---

### [LOW] A3-014: `handleDeepLink` does NOT check `importInProgress` before setting it — concurrent deeplinks can stomp each other

- **Location:** `MainScreenViewModel.swift:1147-1164`.
- **Dimension:** logic, UX.
- **Description:**
  ```swift
  public func handleDeepLink(_ url: URL, router: DeepLinkRouter) {
      Task { @MainActor in
          lastError = nil
          importInProgress = true   // sets true even if another import in flight
          defer { importInProgress = false }
          ...
      }
  }
  ```
  If a paste import is in flight (`importInProgress=true`), then a deep-link arrives → second Task sets `importInProgress=true` (idempotent), runs, then `defer` sets it to FALSE → progress overlay disappears while first import is still in flight.

  Carry-forward from A3-012 Plan 02.

- **Why LOW:** Rare overlap (paste + deeplink in <1s). Visual glitch only — both imports still complete.
- **Suggested fix:** Early-return if `importInProgress`:
  ```swift
  guard !importInProgress else {
      lastError = L10n.importErrorAlreadyInProgress
      return
  }
  ```

---

### [LOW] A3-015: `applyVPNStatus` `@unknown default` branch silently demotes state to `.idle` — masks future iOS NEVPNStatus additions

- **Location:** `MainScreenViewModel.swift:619-626`.
- **Dimension:** logic, future-compat.
- **Description:**
  ```swift
  @unknown default:
      switch state {
      case .empty, .error:
          break
      default:
          state = .idle
      }
  ```
  If a future iOS adds NEVPNStatus.somethingNew (`.preparing`?), this code path silently demotes our state to `.idle`, hiding the new status. Banner isn't updated. Reactive driver D-09 contract says NEVPNStatus is the authority — but `@unknown` collapses to `.idle` not `.connecting/.connected`.

- **Why LOW:** Defensive. Will not bite TestFlight (iOS 18/19 stable). Future iOS upgrade may surface.
- **Suggested fix:** Log at error level with the unknown rawValue so it's caught in os.Logger; keep the `.idle` fallback for robustness.

---

## 3 — Regressions introduced by Plan 05 fixes

| Fix | Risk hypothesis | Verdict |
|---|---|---|
| T-B5' AsyncMutex rewrite | Mutex correctness wins, but might introduce deadlock (waiter never released) or cancellation race. | **PASS structurally.** `withTaskCancellationHandler` properly removes cancelled waiter via `cancelWaiter`. `release()` resumes next FIFO waiter. `defer { Task { await mutex.release() } }` in `run` covers throw + cancellation. ✅ Reentrancy correctly fixed. But A3-001 says **critical section is still too wide** — wins on correctness, loses on latency. |
| T-C9' connectedDate guard | 60s threshold might be incorrect. | **A3-002 IDENTIFIED.** Threshold incorrectly discards legitimate `cs` after long background. Suggested raise to ≥1h or gate on intervening `.disconnected`. |
| T-C9' future-clock clamp `min(since, now)` | Clamp might over-clamp if iOS reports `connectedDate` slightly in future due to clock skew. | **PASS.** Clamp guarantees `since ≤ now`; ConnectionTimer.format then uses `max(0, ...)`. Combined, timer is always ≥0. ✓ |

---

## 4 — MEMORY.md / project-rule compliance

- ✅ `feedback_nevpn_xpc_mach_port.md` — VM observer at line 257-268 reads status from `notification.object` directly. No `loadAllFromPreferences` in callback. TunnelController observer at line 562-580 same pattern. Compliant.
- ✅ `feedback_nevpn_observer_queue_main.md` — All four observers use `queue: nil`: VM killSwitchObserver L236, VM nevpnStatusObserver L256, VM rulesUpdateObserver L1063, TC nevpnObserver L563, TC provisionerObserver L586, TC wakeObserver L594. Compliant.
- ✅ `feedback_connectedDate_authority_for_since.md` — T-C9' helper uses connectedDate as authority. ✅ But A3-002 flags edge case where this regresses against pre-T-C9'.
- ✅ `feedback_swiftdata_uuid_predicate.md` — `refresh()` uses `#Predicate { $0.isSupported == true }` (Bool, safe). UUID lookups use fetch-all + Swift filter (line 343-344, 1206). Compliant.
- ✅ `feedback_phase6d_architectural_patterns.md` — DEC-06d-01 cold-start defer (handleForegroundReentry Task.detached for runIsSupportedUpgrade). DEC-06d-02 ≤2 XPC trips (mostly — A3-004 calls this out for future-proofing). DEC-06d-03 event-driven (observer streams everywhere, no polling outside the fallback test path). A3-008 raises an inner echo storm concern at the SwiftUI re-diff level.
- ✅ `feedback_failover_two_phase_init.md` — `rulesEngineCoordinator` is `weak var`, set via `wireRulesCoordinator` late. Compliant. ⚠️ See A3-005 for the await-suspension race in that exact path.

---

## 5 — Healthy patterns observed

- **AsyncMutex rewrite (T-B5')** is well-engineered. FIFO waiter queue + cancellation propagation via `withTaskCancellationHandler` + idempotent release. Codex Architect consult cited per the doc-comment, and the implementation matches the canonical pattern (e.g. swift-collections AsyncSemaphore reference).
- **Observer-stream architecture in TunnelController** (statusContinuations, broadcastStatus, finishStatusContinuation) is clean. Per-stream deadline tasks finish only their own stream, preserving others. DEC-06d-03 event-driven satisfied without polling.
- **`handleObservedStatus` two-layer filter** (stale-terminal suppression + edge dedupe) is well-commented and explicitly addresses the 8k duplicate event class. The narrow `live == .connected || .connecting || .reasserting` set correctly excludes `.disconnecting` from the suppression bucket (post-fix 2 narrowing).
- **`ExternalVPNStopMarker` peek-without-clear** (Phase 6d post-fix 5) avoids the host/extension race elegantly. Sticky maxAge windowing is the right pattern.
- **`bootstrap → InitialStatusSnapshot` value-type handoff** eliminates one XPC trip on cold start and avoids passing `NETunnelProviderManager` (non-Sendable) across actor hops. ✓
- **`OnDemandRulesBuilder` single-source-of-truth pattern** (4 callsites all → `applyCurrentState`) cleanly preserves W-04 invariant; new consumers join the same flow.

---

## 6 — Pre-TestFlight priority summary

**Block TestFlight (must fix):** None — none of the findings introduce a CRITICAL regression vs Plan 05 baseline. Plan 05 fixes themselves are sound.

**Fix before TestFlight if time permits (HIGH):**
- **A3-001** — Narrow `ProvisionSerializer.run` critical section to SwiftData fetch + Keychain reads only. Failover starvation on slow networks is the main user-visible risk. Estimated 1-2h.
- **A3-002** — Raise T-C9' 60s threshold to 1h+ OR gate on intervening `.disconnected` transition. Timer regression on long background. Estimated 30min.

**Tier B+ (recommended pre-broader rollout):**
- A3-003 — init-time seed Task TOCTOU race with `applyInitialStatusSnapshot`.
- A3-004 — XPC accounting comment guard for future `tunnel.handleForeground` extension.
- A3-005 — `wireRulesCoordinator` await-suspension race; reorder snapshot before observer dance.
- A3-006 — `failoverDismissTask` cancel-and-replace.
- A3-007 — single-flight `backgroundProbeTask` guard.
- A3-008 — sub-second `since` Date drift filter in `.connected` branch.

**Tier C/D backlog (post-TestFlight iteration):**
- A3-011..A3-015 — defensive coding, future-compat, edge cases.
- All A3'-001..A3'-011 carry-forward from Plan 04 that remain.

---

## 7 — Closure verdict

| Plan 05 Task | Pre-audit closure claim | A3 (Plan 06) verdict |
|---|---|---|
| **T-B5'** (`2952871`) | Real async mutex via CheckedContinuation FIFO; closes A3'-001 / C3'-001 / A3'-002. | ✅ **Reentrancy CLOSED.** ✅ `rethrows` removed (A3'-002 closed). ⚠️ Critical-section width still too broad → **NEW HIGH A3-001** (was partial in A3'-001; T-B5' didn't apply the narrowing suggestion). |
| **T-C9'** (`81d7ea6`) | 60s stale-cs threshold + future-clock clamp; closes C3'-002. | ⚠️ **Future-clock clamp PASS.** ⚠️ Stale-cs threshold over-aggressive → **NEW HIGH A3-002** (regression against pre-T-C9' for legitimate long-background sessions). |

**Net:** 2 closures verified, 1 with new HIGH side-effect (A3-001 carry-forward not fully applied), 1 with new HIGH side-effect (A3-002 regression). **Plan 06 should add a Tier A++ for A3-001 + A3-002 before broad TestFlight rollout. Internal Testing is safe to ship as-is.**

---

## 8 — Tally

- CRITICAL: **0**
- HIGH: **2** (A3-001, A3-002)
- MEDIUM: **6** (A3-003, A3-004, A3-005, A3-006, A3-007, A3-008)
- LOW: **7** (A3-009 verified healthy, A3-010 verified healthy, A3-011, A3-012, A3-013, A3-014, A3-015)
- Verified healthy: **2** (A3-009, A3-010)

**Recommendation:** ✅ APPROVE for Internal TestFlight. ⚠️ Address A3-001 + A3-002 before external/wider rollout.
