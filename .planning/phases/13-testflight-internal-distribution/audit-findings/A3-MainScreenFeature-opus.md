# A3 — AppFeatures/MainScreenFeature audit (Opus 4.7)

**Scope:** BBTB/Packages/AppFeatures/Sources/MainScreenFeature/
**Files audited:** 16 (focused: MainScreenViewModel, TunnelController, ConfigImporter, TunnelWatchdog, FailoverProvider, OnDemandRulesBuilder, OnDemandMigrationTask, ManagerSelector, MainScreenView, ConnectionButton, ConnectionTimer, MAXDetector, UserNotificationsHelper, ReconnectClock, ImportProgressOverlay, ConnectionState)
**Total findings:** 14 (CRITICAL: 1, HIGH: 4, MEDIUM: 6, LOW: 3)

## Findings

### [CRITICAL] A3-001: `MainScreenViewModel` has no `deinit`; NEVPN observer remains registered after VM release
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:73-290` (class body; the comment at :110 promises `removed в deinit` but there is no `deinit { ... }` block anywhere in the file).
- **Dimension:** thread-safety, bugs, energy
- **Description:** `MainScreenViewModel` registers THREE long-lived observers in `init`:
  1. `killSwitchObserver` on `UserDefaults.didChangeNotification` (line 222)
  2. `nevpnStatusObserver` on `.NEVPNStatusDidChange` (line 242, `queue: nil`)
  3. `rulesUpdateObserver` on `.bbtbRulesEngineDidUpdate` (line 971, `queue: nil`)
  None of them are ever removed because the file has no `deinit`. In production VM is a singleton owned by `BBTB_iOSApp` (`@StateObject`), so today this is benign — but the observers all do `Task { @MainActor [weak self] ... }`. If any test, future tab, or memory-warning recreation drops the VM, the OLD observer closures stay registered. NEVPN posts events for ALL connections in the system at very high rates on iOS 26 (`feedback_nevpn_xpc_mach_port.md` — 40+/sec storm). Each dead closure still spawns a Task that resolves `weak self -> nil` and exits; cheap, but the cumulative storm of spawned-then-cancelled Tasks on the main actor is exactly the same class as the EXC_RESOURCE/PORT_SPACE crash the Phase 6d fixes were designed to prevent.
  Worse: `UserDefaults.didChangeNotification` observer is `queue: .main` (line 225) — every dead closure pumps the main queue with a Task even when VM is gone. AppFeatures tests that construct multiple VMs in one process will gradually accumulate observers.
- **Why it matters:** Pre-TestFlight this is the only place in the package where a known crash class (NEVPN observer storm) can re-emerge if anything (SwiftUI scene recreation on `iCloudIdentityDidChange`, multi-window on iPadOS, or future deep-link cold-restart) recreates the VM. Even with current singleton ownership, the explicit promise in the source comment (line 110: `removed в deinit`) is silently broken — a violation of the project's own observer lifecycle pattern (compare with `TunnelController.stopReachability()` line 594, which explicitly removes all three observers).
- **Suggested fix:** Add explicit `deinit`:
  ```swift
  deinit {
      if let t = killSwitchObserver { NotificationCenter.default.removeObserver(t) }
      if let t = nevpnStatusObserver { NotificationCenter.default.removeObserver(t) }
      if let t = rulesUpdateObserver { NotificationCenter.default.removeObserver(t) }
  }
  ```
  Note: `deinit` on a `@MainActor` class is non-isolated in Swift 6 — `NotificationCenter.removeObserver(_:)` is thread-safe, so this is fine. Token reads are non-isolated property reads of `let`-like NSObjectProtocol values; if Swift 6 complains, mark the three properties `nonisolated(unsafe)` since they are written once on `@MainActor` and never mutated.

---

### [HIGH] A3-002: `applyVPNStatus` dedupe key drops `.connected → .connected (different connectedDate)` updates — timer authority can stick to first observed start
- **Location:** `MainScreenViewModel.swift:460-468` (`applyVPNStatus(_:connectedDate:)` outer guard).
- **Dimension:** logic, bugs
- **Description:** Dedupe condition is `lastAppliedVPNStatus != status || lastAppliedConnectedDate != connectedDate`. Sound on paper, but `NEVPNConnection.connectedDate` is `nil` for `.connecting`, the observer reads it directly from `notification.object` (lines 247-254), AND there are at least three paths that feed `applyVPNStatus` with potentially-stale `connectedDate`:
  1. `nevpnStatusObserver` block (line 256) — reads `conn.connectedDate` synchronously; for a fast `.connecting → .connected` flip the first `.connected` event can arrive before `connectedDate` is populated (Apple sets `connectedDate` *after* `status` flips on some iOS builds — observed in WireGuard iOS bug history).
  2. `handleForeground()` (line 635) — fresh `loadAllFromPreferences()` then `ours.connection.connectedDate`; this is the authoritative path per `feedback_connectedDate_authority_for_since.md`.
  3. `applyInitialStatusSnapshot(_:)` (line 566) — passes `snapshot.connectedDate` from `TunnelController.bootstrap` (synchronous read at bootstrap moment).
  If path 1 fires `.connected` with `connectedDate = nil`, `lastAppliedConnectedDate` is set to nil and `state` is set to `.connected(since: state.connectionStart ?? Date())` (line 511). Then path 2 fires foreground resync, sees `(status: .connected, connectedDate: realDate)`. Outer dedupe sees `connectedDate` differs (`nil` vs `realDate`) and falls through — GOOD, that branch updates. But within the `.connected` case (line 511) the fallback is `connectedDate ?? state.connectionStart ?? Date()`. `state.connectionStart` is already `Date()` from path 1, so the **wrong (later) start time wins** — the foreground resync NEVER overwrites the stale Date() with the real `connectedDate`, because line 511 prefers `state.connectionStart` over `connectedDate` whenever `connectedDate` is nil **OR equal but `state.connectionStart` is also non-nil**.
  Re-read: `let since = connectedDate ?? state.connectionStart ?? Date()` — if `connectedDate != nil`, it always wins. So actually the foreground path DOES correct it. The narrower bug: if path 1 fires `.connected` with `connectedDate = nil`, dedupe locks `lastAppliedConnectedDate = nil`, then **second** path-1 event arrives with `connectedDate = nil` AGAIN (same nil) → dedupe collapses to no-op even when the second event might be a legit `.connected` echo after iOS finally populated connectedDate **on the source NEVPNConnection** (which the observer re-reads as nil because the observer captured `let connectedDate = conn.connectedDate` at the wrong moment).
- **Why it matters:** Connection timer in `ConnectionButton.connectedTimerView` (line 144) uses `connectedSince` directly for `TimelineView(.periodic(from: since, ...))`. If `since` is `Date()` from the moment of the `.connected` notification rather than from `connectedDate`, after the user backgrounds for hours and returns, the timer is reset to short again (the exact scenario `feedback_connectedDate_authority_for_since.md` warns about). The fix in `handleForeground` only triggers on `.active` scenePhase — between active-status updates and foreground, the timer is wrong.
- **Suggested fix:** Within `case .connected:` branch (line 497-513), if `connectedDate != nil` AND `state.connectionStart != nil`, prefer the **earlier** of the two (`min(connectedDate, state.connectionStart)`). NEVPNConnection's `connectedDate` only goes monotonically forward within one session; if both are non-nil and disagree, the earlier is the truth and the later is a fallback artifact.

---

### [HIGH] A3-003: `init` seed Task races with `bootstrap` cancellation window — initial NEVPN status can be lost
- **Location:** `MainScreenViewModel.swift:275-285` (init-time seed Task).
- **Dimension:** thread-safety, logic
- **Description:** The init seed Task does:
  ```swift
  Task { @MainActor [weak self] in
      guard let self, !self.initialManagersApplied else { return }
      let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
      guard !self.initialManagersApplied else { return }    // re-check
      // ...
      self.initialManagersApplied = true
      self.applyVPNStatus(initialStatus, connectedDate: initialConnectedDate)
  }
  ```
  Comment says `bootstrap` (called from `BBTB_iOSApp.init` line 123+) "could have flipped the flag while await above suspended". True. But the order of operations in `bootstrap` (TunnelController.swift:270-280) is `setFailoverProvider → setWatchdog → startReachability → return snapshot`. The snapshot is then forwarded to `MainScreenViewModel.applyInitialStatusSnapshot(_:)` by the host via `await vm.applyInitialStatusSnapshot(snapshot)`. If this host await is suspended (it's an actor-hop from TunnelController actor → MainActor) AT THE SAME MOMENT the seed Task's `await loadAllFromPreferences()` resumes, the seed Task can:
  1. Re-check `initialManagersApplied == false` (TRUE — bootstrap snapshot not delivered yet).
  2. Set `initialManagersApplied = true`.
  3. Call `applyVPNStatus(...)` with its own freshly-fetched status.
  4. Bootstrap host hop finally lands → `applyInitialStatusSnapshot` sees `initialManagersApplied == true` → early-return. **OK, idempotent.**
  But there's a worse race: the seed Task's `loadAllFromPreferences()` is an XPC call. On cold start under iOS 26 mach-port pressure (the exact scenario `feedback_phase6d_architectural_patterns.md` DEC-06d-02 was designed for), it can be SLOW or even throw. If it throws → `managers = []` → `ours = nil` → `initialStatus = .invalid`. The Task then sets `initialManagersApplied = true` and calls `applyVPNStatus(.invalid, connectedDate: nil)`. If bootstrap's snapshot (which is the AUTHORITY per Wave 03f) had been about to deliver `.connected` with real connectedDate, that update is permanently lost — the bootstrap path early-returns due to the flag.
- **Why it matters:** Cold start with VPN already running (e.g., user backgrounded an active session for hours, force-quits VM via memory pressure, relaunches) — without the bootstrap snapshot winning, the timer starts at 0 instead of the real elapsed time. Worse, an extra XPC trip is paid (the whole point of DEC-06d-02 was to eliminate it). The "fallback" was for test paths only (line 271 comment), but it can fire in production under load.
- **Suggested fix:** Either (a) gate the seed Task behind a debounce delay (e.g. `try? await Task.sleep(for: .milliseconds(50))` before the XPC trip — gives bootstrap a clear lane), or (b) check `initialManagersApplied` after computing the status but BEFORE calling `applyVPNStatus` and only commit if bootstrap STILL hasn't landed (which it already does), and ALSO require `ours != nil` — i.e. don't commit `.invalid` from the fallback path:
  ```swift
  guard !self.initialManagersApplied, ours != nil else { return }
  ```
  This makes the seed Task strictly less authoritative than bootstrap — bootstrap wins if it has anything, the seed Task is a true last-resort that only commits real data.

---

### [HIGH] A3-004: `killSwitchObserver` uses `queue: .main` — violates `feedback_nevpn_observer_queue_main.md` pattern; can drop notifications when app suspended
- **Location:** `MainScreenViewModel.swift:222-228`.
- **Dimension:** thread-safety, bugs
- **Description:** Observer registration:
  ```swift
  self.killSwitchObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main          // ← .main, not nil
  ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.handleUserDefaultsChange() }
  }
  ```
  Memory `feedback_nevpn_observer_queue_main.md` is specifically the lesson "queue: .main loses notifications when app suspended". `UserDefaults.didChangeNotification` is local-process so it usually fires while app is active, BUT during background reconnect (`TunnelController.handleForeground` triggers `applyCurrentStateToCachedManager` which can mutate `UserDefaults` for `app.bbtb.killSwitchEnabled` if the user toggled it in Settings via Shortcuts/quick toggle), the app can be in `.background` with main queue suspended. Notification is **coalesced** with no replay.
- **Why it matters:** The `needsReconnectForKillSwitch` banner is meant to alert user that the kill-switch toggle changed while connected. If the notification is dropped due to `.main` suspension, the banner never shows even though the underlying invariant changed — security UX regression. Identical class to the Settings VPN-off failure that motivated the `queue: nil` migration in TunnelController.
- **Suggested fix:** Change `queue: .main` to `queue: nil` and add `Task { @MainActor [weak self] in self?.handleUserDefaultsChange() }` inside the closure (already present). Pattern is identical to `nevpnStatusObserver` block immediately below it (line 245). Verify `handleUserDefaultsChange` body is @MainActor-safe — it currently reads `userDefaults.object(...)`, mutates `lastKillSwitchValue`, `needsReconnectForKillSwitch`, `reconnectBannerState`. All MainActor-isolated. Hop is correct.

---

### [HIGH] A3-005: `ConfigImporter` is `@unchecked Sendable` but holds non-Sendable `modelContainer` accessed without isolation — SwiftData concurrent fetches across `provisionTunnelProfile` calls can crash
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:59` (class declaration) and :481, :487 (concurrent fetch sites).
- **Dimension:** thread-safety, bugs
- **Description:** `public final class ConfigImporter: ConfigImporting, @unchecked Sendable` — opt-out of Swift 6 isolation checking. `provisionTunnelProfile(for:)` is called from:
  - `MainScreenViewModel.performToggleImpl()` (MainActor)
  - `reconnectAfterSelectionChange(newID:)` (MainActor)
  - `SwiftDataFailoverProvider.attempt` closure (failover actor, line FailoverProvider.swift:162)
  - `MainScreenViewModel.handleDeepLink` indirectly via DeepLinkRouter
  - `serverListViewModel.silentForegroundRefresh` chain via importer
  `provisionTunnelProfile` creates a `ModelContext(modelContainer)` and fetches (line 481-490). Two concurrent calls (e.g. user taps Connect while watchdog is mid-failover) create two ModelContexts on different actors hitting the same ModelContainer. SwiftData claims ModelContainer is thread-safe and ModelContext is per-thread, but in iOS 18+ practice there are still races on the schema's persistent coordinator — particularly when writes (line 245 `context.save()` in unrelated import flows) happen concurrently with reads. The `@unchecked Sendable` annotation hides this from the compiler.
- **Why it matters:** Symptom would be either a `SwiftDataError.invalidGenerationToken`-style crash, or silent stale reads (which `feedback_swiftdata_uuid_predicate.md` already documents as a SwiftData wart). For TestFlight this is rare (need failover + manual reconnect overlap) but the impact is high — crash on connect retry path.
- **Suggested fix:** Long-term: make `ConfigImporter` an `actor`. Short-term, before TestFlight: at minimum serialize the SwiftData-touching public methods by hopping to `@MainActor` (the project's existing convention for SwiftData — `FailoverProvider.fetchSupportedSnapshots` already does `await MainActor.run { ... }`, line 197). Concretely:
  - Annotate `provisionTunnelProfile(for:)` body to wrap the fetch+save section in `await MainActor.run { ... }`, OR
  - Add a serial dispatch queue inside `ConfigImporter` that all SwiftData accesses go through.
  The TaskGroup for parallel Keychain reads (line 554-589) is OK — it touches Keychain via the Sendable-safe `KeychainStore.load`, no ModelContext crossing.

---

### [MEDIUM] A3-006: `connect()` does not verify `ours.first` is OUR manager — falls back to picking any first manager from `cachedManager` lineage
- **Location:** `TunnelController.swift:283-291` (`refreshCachedManager`) seeds `cachedManager` via `ManagerSelector.ourManagers(from: managers).first`. Then `connect()` (line 374) uses `cachedManager` directly, but `DefaultTunnelProvisioner.provisionTunnelProfile` (ConfigImporter.swift:1316-1374) on FIRST install (when no manager exists yet) does:
  ```swift
  let manager = ours.first ?? NETunnelProviderManager()  // ← creates fresh
  ```
- **Dimension:** logic, bugs
- **Description:** On first install: provisioner creates a fresh `NETunnelProviderManager()`, sets protocol, save+load, posts `.bbtbProvisionerDidSave`. TunnelController's observer for that notification calls `refreshCachedManager` which calls `loadAllFromPreferences`. At this stage the manager is saved BUT its `protocolConfiguration` (i.e. `providerBundleIdentifier`) might not be re-fetched yet from iOS preferences DB (race between save → load → broadcast). `ManagerSelector.ourManagers` requires `providerBundleIdentifier` to match (line 70 `proto.providerBundleIdentifier`). If the broadcast arrives before iOS has flushed the protocol config to disk, `ours.first` is nil → `cachedManager` stays nil → next `connect()` tap goes through line 371 `if cachedManager == nil { await refreshCachedManager() }` → second XPC trip. Idempotent but adds 200-500ms latency on the first-ever Connect tap. Not a crash, but exactly the "cold-start XPC contention" pattern Phase 6d Wave 03f was designed to prevent.
- **Why it matters:** First TestFlight install UX — fresh user imports config, taps Connect, sees 500ms-1s extra latency vs subsequent taps. Phase 6d perf targets explicitly track this metric (DEC-06d-02 ≤2 XPC trips).
- **Suggested fix:** In `provisionerObserver` block (TunnelController.swift:577-581), inspect `notification.object as? NETunnelProviderManager` first; if non-nil AND `ManagerSelector.ourManagers(from: [m])` is non-empty, set `cachedManager = m` directly (no XPC). Else fall through to `refreshCachedManager`. This is exactly the `object` parameter contract documented in `ManagerSelector.swift:90` but never used by the observer.

---

### [MEDIUM] A3-007: `performToggleImpl` race between fast-path winner selection and concurrent server delete
- **Location:** `MainScreenViewModel.swift:721-759` (`performToggleImpl`) + `selectAutoWinner` (line 774-821).
- **Dimension:** bugs, logic
- **Description:** Fast path in `selectAutoWinner` reads `supportedServerSnapshot` (cached @Published array) and picks `winnerID = winner.id`. Then `performToggleImpl` calls `try await importer.provisionTunnelProfile(for: winnerID)`. Between the snapshot read and provision call, an external delete (user opens server list sheet in another window, deletes the winner) can run on MainActor in the same `await` boundary. By the time `provisionTunnelProfile` does its SwiftData fetch (ConfigImporter.swift:481-490), the row is gone → throws `noSupportedServers` → state = `.error("Нет поддерживаемых серверов")` (UI shows "Reconnect" error). User is confused: they pressed Connect, got an error, but the server they expected to use was the one they JUST deleted.
- **Why it matters:** Edge case but reachable: user has 2+ servers, in Auto mode, opens main screen, taps Connect, then before it completes deletes the server they think is being used. SwiftUI permits this — no modal lock. Pre-TestFlight bug class.
- **Suggested fix:** In `performToggleImpl`, catch `ImporterError.noSupportedServers` specifically and instead of going to `.error`, call `await refresh()` then either retry once (if `supportedServerSnapshot` non-empty) or transition to `.empty`. The user sees their actual state instead of a stale error.

---

### [MEDIUM] A3-008: `OnDemandRulesBuilder.loadAutoReconnectEnabled` reads `.standard` UserDefaults without explicit MainActor — `applyCurrentState` callable from any context
- **Location:** `OnDemandRulesBuilder.swift:107-115` (`applyCurrentState`), :130-135 (`loadAutoReconnectEnabled`), :155-160 (`loadUserIntendedConnected`).
- **Dimension:** thread-safety
- **Description:** `applyCurrentState` is called from:
  - `TunnelController.connect/disconnect` (actor isolation)
  - `TunnelController.applyCurrentStateToCachedManager` (actor isolation)
  - `OnDemandMigrationTask.runIfNeeded` (no isolation, called from `Task.detached`)
  - `ConfigImporter.DefaultTunnelProvisioner.provisionTunnelProfile` (no isolation)
  - `SettingsViewModel.applyAutoReconnectToManager` (MainActor)
  All read `UserDefaults.standard.object(forKey:)`. UserDefaults is documented as thread-safe for read/write, BUT the value can change MID-read (e.g., SettingsViewModel writes `app.bbtb.autoReconnectEnabled = false` on MainActor while OnDemandMigrationTask reads it from a detached Task). The two reads inside `applyCurrentState` (toggle + intent) are NOT atomic — between them, both keys can flip. Resulting `enabled = toggle && intent` would be computed from inconsistent snapshot.
- **Why it matters:** Subtle inconsistency in on-demand rules state. Rare in practice (settings toggle requires user gesture, migration is one-shot) but for TestFlight diagnostics this could produce confusing logs ("toggle=true, intent=false, enabled=true" — impossible per code, possible per real race).
- **Suggested fix:** Snapshot both values into local `let` constants within the same line for slightly tighter atomicity, OR refactor to take `(toggle: Bool, intent: Bool)` from caller (caller reads both under its own isolation). The latter is the design improvement.

---

### [MEDIUM] A3-009: `ExternalVPNStopMarker.isPending` performs disk I/O on every NEVPN status change to `.disconnected`
- **Location:** `TunnelController.swift:66-86` + caller line 717.
- **Dimension:** energy, performance
- **Description:** Every `.disconnected` notification routed through `handleStatusChange` calls `ExternalVPNStopMarker.isPending()`. That method constructs `UserDefaults(suiteName: "group.app.bbtb.shared")` on EACH call (line 54-56) — App Group UserDefaults init is not free (file open + parse plist on first miss). With `feedback_nevpn_xpc_mach_port.md` documenting 40+/sec NEVPN storms, even with the edge-dedupe in `handleObservedStatus`, the deduped path still calls this when status flips from non-`.disconnected` to `.disconnected`. Each call also calls `.bool(forKey:)` + `.double(forKey:)` + `.removeObject` (when stale) + `.synchronize()` (in `clear()` from line 84). `.synchronize()` is deprecated for a reason — it forces a flush.
- **Why it matters:** On a flapping network (subway, lift, garage), every `.disconnected` event pays App Group plist I/O. Battery + CPU cost in the tail. Not a TestFlight blocker but a real energy regression vs the dedupe guarantees Phase 6d ships.
- **Suggested fix:** Cache `UserDefaults(suiteName:)` once as an actor-isolated `private let externalStopDefaults: UserDefaults? = UserDefaults(suiteName: "group.app.bbtb.shared")` — same suite, one allocation. The static `enum ExternalVPNStopMarker` could be promoted to a small Sendable struct holding the defaults reference. Remove `.synchronize()` — Apple specifically deprecated it.

---

### [MEDIUM] A3-010: `runIsSupportedUpgrade` ignores `Task.isCancelled` between candidates — long pass can outlive scene background
- **Location:** `ConfigImporter.swift:1028-1079`.
- **Dimension:** energy, logic
- **Description:** Called from `MainScreenViewModel.handleForegroundReentry` (line 669-672) via `Task.detached(priority: .background)`. Iterates over potentially many unsupported rows, each one calls `parser.import(...)` (network + parse) + Keychain save + SwiftData save. No `try Task.checkCancellation()` inside the loop, no cancellation propagation. If user backgrounds the app mid-pass, this Task continues running on the background priority pool until completion. For a 50-row unsupported pool that's 5-30s of background work iOS could have suspended.
- **Why it matters:** Energy regression on cold-start foreground re-entry; also wastes BGAppRefresh budget. Phase 6e tightened similar paths; this one is the last surviving offender.
- **Suggested fix:** Add `try Task.checkCancellation()` (or `if Task.isCancelled { break }`) at the top of the `for cfg in candidates` loop and after each `try? await uParser.import(...)`. Also: caller passes `Task.detached(priority: .background)` — switch to `Task(priority: .background)` so cancellation propagates from the structured tree of the parent (MainActor task on foreground re-entry).

---

### [MEDIUM] A3-011: `applyVPNStatus` `.error` state transitions cannot be cleared by `.connecting` re-enter — UI sticks in error after dismiss
- **Location:** `MainScreenViewModel.swift:482-489` and :525-530 (state demotion paths preserve `.error`).
- **Dimension:** logic, UI
- **Description:** Once `performToggleImpl` sets `state = .error(message:)` (e.g. line 745), the next user tap on the Connect button (which is *enabled* in `.error` state per `ConnectionButton.swift:191-195`) flows into `performToggleImpl` again, which has cases `.idle, .error: ... state = .connecting`. Good — error CAN be cleared by tapping again. BUT if NEVPN posts `.connecting` while we're still in `.error` for an UNRELATED reason (e.g., system on-demand try after a `.error` toggle attempt that threw before extension was even invoked), `applyVPNStatus` `case .connecting:` branch (line 484-489) explicitly preserves `.error`. So if the extension actually starts on its own (on-demand activation), the UI is still showing "ошибка" — user has no clue the tunnel is reconnecting.
- **Why it matters:** UI/state divergence. Mid-tier severity because the user can clear it by tapping; but for a kiosk-mode user (left phone in pocket) the banner stays "ошибка" even after iOS auto-recovers.
- **Suggested fix:** Allow `.error → .connecting` transition: change the `case .empty, .error, .connecting: break` in line 485 to `case .empty, .connecting: break` (drop `.error`). The dedupe already prevents thrash. The `.connected` branch (line 507) already handles error properly by replacing.

---

### [LOW] A3-012: `handleDeepLink` re-enters `importInProgress=true` without checking if a prior import is in flight
- **Location:** `MainScreenViewModel.swift:1058-1075`.
- **Dimension:** logic
- **Description:** If user taps a deep link while a pasteboard import is in progress (`importInProgress = true`), the deep-link Task ALSO sets `importInProgress = true` then `defer { importInProgress = false }`. When the deep-link Task completes first, it clears the flag — even though the pasteboard import is still running, the `ImportProgressOverlay` disappears. User thinks import failed; if they tap again, two concurrent imports race in SwiftData (same as A3-005).
- **Why it matters:** Edge case (deep link + pasteboard tap collision) but reachable.
- **Suggested fix:** Add a `guard !importInProgress else { return }` at the top of `handleDeepLink` (and consider the same in `performImport`). Alternative: convert `importInProgress` from Bool to a counter or to a `Set<UUID>` so each task owns one entry; overlay shows iff count > 0.

---

### [LOW] A3-013: `MainScreenViewModel.handleForegroundReentry` calls `runIsSupportedUpgrade` via `Task.detached`, losing the priority-inheritance lane that Wave 03f cleanup secured
- **Location:** `MainScreenViewModel.swift:668-672`.
- **Dimension:** energy
- **Description:** Comment says "DEC-06d-01 cold-start defer pattern: не блокирует main render queue, не contend'ит за cooperative thread pool". Correct in spirit. But `Task.detached(priority: .background)` ALSO opts out of structured concurrency cancellation. Foreground re-entry doesn't have a long parent lifetime, so cancellation propagation is moot — but the `.background` priority on iOS 26 is heavily throttled (10× slower than utility) when device is on battery. The 5-minute throttle inside `runIsSupportedUpgrade` already ensures it doesn't fire often; running it at `.utility` would be more honest about the work.
- **Why it matters:** Subtle perf; tail-latency of subscription upgrades.
- **Suggested fix:** Change `priority: .background` to `priority: .utility` in line 669, matching `MAXDetector.detectAndLog` callsite convention.

---

### [LOW] A3-014: `showFailoverBanner` auto-dismiss timer leaks if VM deallocates mid-sleep (related to A3-001)
- **Location:** `MainScreenViewModel.swift:584-595`.
- **Dimension:** thread-safety
- **Description:** `Task { @MainActor [weak self] in ... try? await Task.sleep(for: .seconds(5)) ... }` — uses `[weak self]`, good. But Task itself is not stored anywhere — if VM is replaced (theoretically) the sleeping Task keeps running, just no-ops after the weak check. Minor energy cost. Bigger issue: there's no cancellation if another `showFailoverBanner` fires within 5s — the new banner gets the new server name, but the OLD task's `case .failover = self.reconnectBannerState` check passes (new banner is also `.failover(...)`) and sets `.hidden` PREMATURELY. The newer banner is visible for less than 5s — between 0 and 5s depending on when the prior call fired.
- **Why it matters:** Failover-burst UX (multi-server failover cascade) — second banner can disappear in 1s instead of 5s.
- **Suggested fix:** Store the auto-dismiss Task as `private var failoverDismissTask: Task<Void, Never>?`; cancel and replace on each `showFailoverBanner` call. Pattern is identical to `TunnelWatchdog.stableSessionTask` re-arm in line 187.

---

## Notes

- **MEMORY.md compliance status:**
  - `feedback_nevpn_xpc_mach_port.md` — observer (line 246) reads status from `notification.object` directly, NO `loadAllFromPreferences` in callback. Compliant.
  - `feedback_nevpn_observer_queue_main.md` — `nevpnStatusObserver` uses `queue: nil` (compliant); `killSwitchObserver` uses `queue: .main` (NON-compliant — see A3-004); `rulesUpdateObserver` uses `queue: nil` (compliant).
  - `feedback_connectedDate_authority_for_since.md` — `applyVPNStatus` reads conn.connectedDate as authority (compliant), but `.connected` branch fallback order has a sequencing bug (see A3-002).
  - `feedback_tunnelcontroller_disconnect_race.md` — `disconnect()` early-exits on `.disconnected/.invalid` (compliant); `awaitDisconnectedStatus` uses stream + deadline (compliant).
  - `feedback_auto_reconnect_user_intent_guard.md` — `userIntendedConnected` guard present in `handleStatusChange` (line 706, compliant).
  - `feedback_swiftdata_uuid_predicate.md` — `FailoverProvider.fetchSupportedSnapshots` uses fetch-all + Swift filter (compliant); `ConfigImporter.runIsSupportedUpgrade` uses fetch-all + filter (compliant); `ConfigImporter.provisionTunnelProfile` uses `#Predicate { $0.id == id }` with `selectedID: UUID?` carve-out via `let id = selectedID` non-optional bind (acceptable — id is non-Optional inside the if-let; verified line 921).
  - `feedback_phase6d_architectural_patterns.md` — DEC-06d-01 cold-start defer in foreground hook (compliant); DEC-06d-02 ≤2 XPC trips in connect path (compliant, but see A3-006 fresh-install delta); DEC-06d-03 event-driven (compliant — observer streams replace polling).

- **What looks healthy:** TunnelController actor isolation + observer stream pattern, OnDemandRulesBuilder single-source-of-truth design, ManagerSelector dedupe, edge dedupe in `handleObservedStatus`, the stale-terminal-suppression narrow rule (positive-list `.connected/.connecting/.reasserting`), TaskGroup-with-bounded-concurrency in `provisionTunnelProfile` auto-mode path.

- **No findings on:** QRScannerView/QRScannerViewController (camera permission flow looks correct), MinAppVersionSheet (pure presentational), ImportProgressOverlay, ConnectionState (value-only enum), MAXDetector (well-isolated, logged-only), Localization references.

- **Recommended pre-TestFlight priority order:** A3-001 (CRITICAL deinit, fix is 6 lines) → A3-004 (HIGH `.main` → `nil`, 1-line fix) → A3-005 (HIGH ConfigImporter isolation, MainActor.run wrap) → A3-002 (HIGH timer min() fix) → A3-003 (HIGH seed-Task guard) → batch the MEDIUM/LOW items as Phase 13.x post-TestFlight backlog.
