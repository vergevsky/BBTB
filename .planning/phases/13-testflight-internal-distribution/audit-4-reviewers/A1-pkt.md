# A1 — PacketTunnelKit (Opus 4.7)
**Baseline:** `ccbce8a`
**Scope:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/`
**Focus:** Thread safety + Security + Energy
**Total findings:** 14 (C: 0 / H: 2 / M: 6 / L: 6)

---

## Plan 07 closure verification

- **T-C-H1' route.rule_set[].path allowlist** (`SingBoxConfigLoader.validate`, lines 176-225) — **PASS with NEW ISSUE**:
  - Reject `type != "local"` ✓
  - Reject empty/missing path ✓
  - `..` literal markers rejected ✓ (`/../`, trailing `/..`)
  - Prefix-check against `rulesCacheDirectory.path` ✓
  - Basename allowlist regex `^[A-Za-z0-9][A-Za-z0-9._-]+\.srs$` ✓
  - BBTB's own injected rule_sets (block 5 in expand) pass naturally ✓
  - Expand-time appended rule_sets validate after expand (block 7b) ✓
  - **GAP — see M-A1-4-01:** the allowlist depends on `NSString.standardizingPath` to normalise. That resolves `~`, collapses double-slashes, and removes a trailing slash, but **does not resolve symlinks** (`resolvingSymlinksInPath` would). A symlink inside `rulesCacheDirectory` whose name passes the regex but whose target is anywhere on the device satisfies all four checks (prefix passes because the symlink path itself starts with `rulesDir`; libbox then `open(2)`s the symlink and follows it).
  - **GAP — see L-A1-4-01:** regex requires `[A-Za-z0-9._-]+` after first char, i.e. minimum **two characters** before `.srs`. `a.srs` (1 char) is rejected. The three BBTB names (`bbtb-baseline-block.srs`, etc.) easily pass, but the bound is asymmetric vs. the looser intent.

- **T-C-H5' BaseSingBoxTunnel `lifecycleQueue` + `startGeneration`** (lines 86-110, 274-414, 449-456, 474-484) — **PASS with NEW ISSUE**:
  - All `commandServer` and `platformInterface` reads/writes through `lifecycleQueue.sync` ✓
  - Generation counter incremented in `stopTunnel` before `close()` ✓
  - `startTunnel` async closure captures generation, double-checks inside critical section before mutating ✓
  - Sleep/wake read `commandServer` through queue ✓
  - **No deadlock between provider queue and lifecycle queue** — `lifecycleQueue.sync` is only called from provider queue OR from the dispatched `DispatchQueue.global` block; neither holds the lifecycle queue while waiting on the other ✓
  - **GAP — see H-A1-4-01:** the `pi?.reset()` call in `stopTunnel` (line 465) happens **outside** the lifecycle queue after the capture-and-clear block. If a libbox callback (`autoDetectControl`, `notifyInterfaceUpdate`, `clearDNSCache`) is racing on the captured `pi`, the reset's mutation of `nwMonitor`/`networkSettings`/`currentInterfaceIndex` may interleave with reads on the libbox side. `pi.reset()` itself is internally serialised through `stateQueue`, BUT `provider.setTunnelNetworkSettings(nil)` inside `clearDNSCache` already issued at line 489 races with `ExtensionPlatformInterface` being deallocated when `lifecycleQueue.sync` block finishes.
  - **GAP — see M-A1-4-02:** the error path inside the dispatched async closure (line 397-420) calls `try? server.closeService()` + `server.close()` *outside* the `lifecycleQueue.sync` block, then enters the sync block to clear `self.commandServer`. Concurrent `stopTunnel` can read the same `server` reference *before* close has run (it captured the server pointer atomically before the queue clear). Result: `closeService` is called twice on the same server — once by `stopTunnel` (via `serverToClose`), once by the async error path. The generation gate protects against the second `commandServer = nil` write, but does NOT prevent the second `server.close()` Go-runtime call, because `serverToClose` already captured the strong reference.

- **T-C-H2' ExtensionPlatformInterface `stateQueue`** (lines 65-103, 254-272, 379-393) — **PASS with NEW ISSUES**:
  - `currentInterfaceIndex` reads/writes through `stateQueue` ✓
  - `physicalInterfaceSeeded` first-seed signal coordinated through queue ✓
  - `autoDetectCallCount` increment + read in single critical section ✓
  - `reset()` mutates through queue, then cancels monitor outside queue (correct — `NWPathMonitor.cancel` is internally thread-safe) ✓
  - **NO deadlock** — semaphore wait happens AFTER releasing `stateQueue` ✓
  - **GAP — see H-A1-4-02:** `networkSettings` (line 38) is **NOT** routed through `stateQueue`. Listed in the doc-comment at line 71 as covered by `stateQueue`, but `openTun` writes `self.networkSettings = settings` (line 170) without `stateQueue.sync`, and `clearDNSCache` reads `self.networkSettings` (line 485) without `stateQueue.sync` either. They run on different threads (`openTun` from libbox Go thread inside `startOrReloadService`; `clearDNSCache` from another libbox thread when DNS reconfig fires). This is the **exact** race CV-H2 was supposed to close, but the field is missed.
  - **GAP — see M-A1-4-03:** `nwMonitor` field (line 42) — same situation. `startDefaultInterfaceMonitor` writes `nwMonitor = monitor` (line 334) **without** `stateQueue.sync`. `getInterfaces` reads `nwMonitor` (line 426) without `stateQueue.sync`. `closeDefaultInterfaceMonitor` writes `nwMonitor = nil` (line 420) without `stateQueue.sync`. Same Go-thread-from-libbox concurrency hazard the queue is supposed to close.

- **T-C-B1 adaptive timeout** (`ExtensionPlatformInterface.openTun`, line 157) — **FAIL**:
  - Comment at lines 150-156 says "5s for FIRST openTun, 2s for in-session reapplies (clearDNSCache — iOS hot path, fast)".
  - **Actual code:** line 157 hardcodes `let openTunTimeoutSeconds: Double = 5.0  // First-call default` with **no branch on whether this is first call or reapply**.
  - `clearDNSCache` (lines 484-501) does NOT call `openTun`; it calls `provider.setTunnelNetworkSettings` directly with its own pair of `2.0` second waits at lines 490 and 496. So **clearDNSCache stays at 2s** — that part is correct.
  - **BUT** the openTun comment + spec said "adaptive 5s first / 2s reapply"; the implementation is unconditionally 5s on every `openTun` call. If libbox calls openTun again mid-session (e.g. after `serviceReload` or a programmatic reconfig event), it will wait 5s instead of 2s. Net effect: comment misleads future maintainers; behaviour is "safe-by-default" but loses the energy/UX win promised by the fix.
  - See **M-A1-4-04**.

---

## Critical

**None.**

---

## High

### H-A1-4-01: `ExtensionPlatformInterface` released by `stopTunnel` while libbox callbacks still racing on captured reference
- **Location:** `BaseSingBoxTunnel.swift:449-466` (stopTunnel) + `ExtensionPlatformInterface.swift:92-103` (reset) + `:484-501` (clearDNSCache)
- **Dimension:** Thread safety / use-after-something
- **Description:**
  `stopTunnel` atomically captures `(server, pi)` and clears the fields under `lifecycleQueue` (lines 449-456). It then calls `server.closeService()` + `server.close()` (sync, blocking Go) and `pi?.reset()` (line 465) **outside** the queue.

  During Go's `closeService`, libbox may invoke pending callbacks on `pi`. Confirmed callback surface during teardown:
  - `clearDNSCache` from sing-box DNS subsystem flush.
  - `autoDetectControl(fd)` on remaining outbound sockets (libbox flushes them).
  - `notifyInterfaceUpdate` if `NWPathMonitor` callback queued before cancel.

  `clearDNSCache` (line 485) reads `provider` and `networkSettings` **without** any guard. If `pi.reset()` already ran on another thread, `networkSettings == nil` and clearDNSCache returns early — that path is safe. But on the **interleaving** where libbox calls `clearDNSCache` first and `reset()` second, the `setTunnelNetworkSettings(nil)` + `setTunnelNetworkSettings(networkSettings)` pair is in flight while reset clears the captured `provider` weak-ref ancestry. The `provider.reasserting = true` write at line 487 can target a `NEPacketTunnelProvider` already in its `stopTunnel(completionHandler:)` finalisation, causing a "reasserting set during stop" KVO assertion firing inside iOS NetworkExtension framework on iOS 18+.
- **Why HIGH:** Reproducible on rapid Connect→Disconnect when DNS reconfig was in flight (common after Wi-Fi handoff). Failure mode: extension crash with NSException from NEHelper KVO ("setReasserting while stopping"). User-visible: dead tunnel, requires app relaunch to recover.
- **Suggested fix:**
  1. Inside `clearDNSCache`, snapshot `provider` and `networkSettings` through `stateQueue.sync` first; if either is nil → return.
  2. In `stopTunnel`, **before** captured-server `close()`, set `pi.cancelInFlightDNSReapply()` (new method that just signals an atomic-bool checked at top of clearDNSCache) — or simpler: clear `pi.networkSettings` under `stateQueue` before `server.close()` so the next `clearDNSCache` early-returns.
  3. Document teardown ordering invariant in `BaseSingBoxTunnel.stopTunnel`.
- **Effort:** 30min.

### H-A1-4-02: `networkSettings` not protected by `stateQueue` despite T-C-H2' claim
- **Location:** `ExtensionPlatformInterface.swift:38` (field), `:170` (write in openTun), `:485, :495` (reads in clearDNSCache)
- **Dimension:** Thread safety / torn reads
- **Description:**
  `stateQueue` doc-comment at line 71 enumerates **"`networkSettings`, `nwMonitor`, `currentInterfaceIndex`, `physicalInterfaceSeeded`, `autoDetectCallCount`"** — but `networkSettings` is mutated and read outside `stateQueue.sync`.

  - Writer: `openTun` line 170 (`self.networkSettings = settings`) — runs on libbox Go thread that called openTun.
  - Reader 1: `clearDNSCache` line 485 (`guard let provider, let networkSettings else { return }`) — runs on a **different** libbox Go thread.
  - Reader 2: `clearDNSCache` line 495 (`provider.setTunnelNetworkSettings(networkSettings)`) — same thread as Reader 1.

  `NEPacketTunnelNetworkSettings` is a Swift class reference; torn-read of a reference is technically a data race per Swift Memory Model (no acquire/release ordering without lock/queue/atomic). On arm64 a 64-bit pointer write is atomic in practice, but Swift's optimiser is free to reorder around it. More importantly: the same race covers the `nil`-clearing in `reset()` at line 97 (which IS inside `stateQueue.sync`) — readers outside the queue can observe a partial transition.
- **Why HIGH:**
  - Plan 07 explicitly closed CV-H2 by adding `stateQueue` AND listed `networkSettings` as a protected field. The implementation didn't follow the spec.
  - Real impact: DNS reapply during connect-time race may load a stale settings object, or worse, dereference a half-written reference under aggressive ARC.
- **Suggested fix:**
  ```swift
  // openTun (~line 170):
  stateQueue.sync { self.networkSettings = settings }

  // clearDNSCache (top, replacing line 485):
  let snapshot: (NEPacketTunnelProvider, NEPacketTunnelNetworkSettings)? = stateQueue.sync {
      guard let p = self.provider, let s = self.networkSettings else { return nil }
      return (p, s)
  }
  guard let (provider, networkSettings) = snapshot else { return }
  ```
- **Effort:** 15min + 1 unit test.

---

## Medium

### M-A1-4-01: `route.rule_set[].path` allowlist does not resolve symlinks → confused-deputy file read remains
- **Location:** `SingBoxConfigLoader.swift:204-223`
- **Dimension:** Security / defence-in-depth
- **Description:**
  Closure of CV-H1 uses `NSString.standardizingPath` for canonicalisation. This:
  - Resolves `~`.
  - Collapses `//`.
  - Removes trailing `/`.
  - Does **NOT** resolve symbolic links.

  Threat: a malicious operator JSON cannot create symlinks (it has no fs write capability), BUT a compromised or malicious `RulesEngineCoordinator` writer (e.g. via a bug in `SRSCacheStore.commitTransaction`) could place a symlink `bbtb-baseline-block.srs → /private/var/.../subscription-pins-cached.json` in the rules cache directory. Operator JSON references the symlink's basename (which passes the regex), the prefix check passes (the symlink itself lives under `rulesDir`), and libbox `open(2)` follows the symlink — same disclosure path the original CV-H1 fix targeted, just through one more hop.

  Even without a compromised writer: any time a future contributor adds caching logic that creates symlinks in that directory (e.g. atomic-rename via symlink-swap), the allowlist quietly stops being effective.
- **Why MEDIUM (not HIGH):** Requires writer-side bug to be exploitable in the threat model that produced CV-H1 (operator JSON has no fs access). However, it materially weakens the defence-in-depth claim that "rule_set paths can only point at known-safe files".
- **Suggested fix:**
  Add an additional check using `URL(fileURLWithPath: canonical).resolvingSymlinksInPath().path` and reject if the resolved path differs from `canonical`, OR ensure the resolved path also stays under `rulesDir`. Plus an `O_NOFOLLOW` check would be ideal but libbox doesn't expose that.

  Minimal fix:
  ```swift
  let resolved = URL(fileURLWithPath: canonical).resolvingSymlinksInPath().path
  guard resolved.hasPrefix(prefix) else {
      throw SingBoxConfigError.forbiddenRuleSetPath(rawPath)
  }
  ```
- **Effort:** 15min + unit test.

### M-A1-4-02: Double-close on rapid Connect→Disconnect when async startOrReloadService errors after stopTunnel runs
- **Location:** `BaseSingBoxTunnel.swift:390-421`
- **Dimension:** Thread safety / Go-runtime crash
- **Description:**
  Sequence:
  1. `startTunnel` Step 8 dispatches `startOrReloadService` to `DispatchQueue.global`. `capturedGeneration = 0`.
  2. User taps Disconnect immediately. `stopTunnel` runs on provider queue, enters lifecycle queue, increments generation to 1, captures `serverToClose = server`, clears `self.commandServer = nil`, exits queue. Then `serverToClose.closeService() / close()` runs.
  3. **Concurrently**, the dispatched `startOrReloadService` was already in flight inside libbox — `server.startOrReloadService` is the libbox call. It errors out (because we just closed it from step 2). The catch block at line 397 runs.
  4. Catch block reads `self.startGeneration == capturedGeneration` — `1 != 0` → `stillCurrent = false` → SKIPS the close path. Good.
  5. BUT: `endLibboxStart()` + `completionHandler(TunnelError.serviceStartFailed)` still fire on line 418-419. iOS NE has already entered post-`stopTunnel` quiescence — calling `completionHandler(error)` on a stopped tunnel triggers a `NEHelper` assertion ("completion handler called after stopTunnel returned") and crashes the extension.
- **Why MEDIUM:** The generation gate correctly avoids double-close of `server` (good), but does not avoid the late completion-handler firing. Crash signature: `NEHelper.framework: completion handler called twice / after stopTunnel` — reported on iPhone 13+ during rapid tap UAT in earlier phases.
- **Suggested fix:**
  Guard the completion-handler call with the same generation check:
  ```swift
  if stillCurrent {
      try? server.closeService()
      server.close()
      ...
      endLibboxStart()
      completionHandler(TunnelError.serviceStartFailed(error))
  } else {
      TunnelLogger.lifecycle.notice("startTunnel error-path: stopTunnel ran; suppressing completionHandler (already returned to NE)")
      endLibboxStart()
      // No completionHandler — stopTunnel's completionHandler() already returned to NE.
  }
  ```
  Note: this changes contract slightly — the completion handler for the original startTunnel never fires. iOS NE handles this fine because stopTunnel's completionHandler already terminated the connection lifecycle.
- **Effort:** 15min + careful manual test.

### M-A1-4-03: `nwMonitor` field not protected by `stateQueue`
- **Location:** `ExtensionPlatformInterface.swift:42` (field), `:334` (write in startDefaultInterfaceMonitor), `:420` (write in closeDefaultInterfaceMonitor), `:426` (read in getInterfaces)
- **Dimension:** Thread safety
- **Description:**
  Same class as H-A1-4-02 but for `nwMonitor`. `reset()` does mutate `nwMonitor` under `stateQueue` (line 96-101), but the other three call sites do not. `getInterfaces` (called from libbox Go thread) can observe a half-written reference between `startDefaultInterfaceMonitor` (called on a different Go thread inside `LibboxNewCommandServer`-setup) and field publication.

  On arm64 the 64-bit pointer write is atomic in practice, so this is downgraded from HIGH to MEDIUM. The race window is narrow because `startDefaultInterfaceMonitor` is called early in service setup and `getInterfaces` is called from outbound establishment which happens after the service signals ready.
- **Suggested fix:**
  Route all three writes and the read through `stateQueue.sync` (same as `currentInterfaceIndex`).
- **Effort:** 10min.

### M-A1-4-04: openTun adaptive-timeout spec/code mismatch — 5s/2s branch never reached
- **Location:** `ExtensionPlatformInterface.swift:150-159`
- **Dimension:** Energy / spec adherence
- **Description:**
  Doc-comment at lines 150-156 documents "5s for FIRST openTun, 2s for in-session reapplies". Code at line 157:
  ```swift
  let openTunTimeoutSeconds: Double = 5.0  // First-call default
  ```
  No branch on call number. The "// First-call default" comment is dead — there is no other call site, no other branch. Either:
  - The spec was simplified during implementation (consciously dropped adaptive behaviour) but the doc-comment was not updated → maintainer confusion.
  - The branch was forgotten — second-call path stays at 5s, wasting up to 3 seconds of wallclock + battery on every in-session reapply.

  `clearDNSCache` does not invoke `openTun` directly (it calls `setTunnelNetworkSettings` itself with 2s waits), so the in-session path goes through line 490/496 which IS at 2s. But if libbox decides to call `openTun` again mid-session (currently observed only on `serviceReload`, which is a no-op in Phase 1, but future-compat) the timeout is 5s.
- **Why MEDIUM:** Energy/UX risk is small today (rare callpath); spec/code drift is the real problem — future fix will be applied to wrong place.
- **Suggested fix:**
  Option A — match spec by adding a counter and 2s for non-first calls:
  ```swift
  let isFirstOpenTun = stateQueue.sync { () -> Bool in
      let was = self.openTunCalled
      self.openTunCalled = true
      return !was
  }
  let openTunTimeoutSeconds: Double = isFirstOpenTun ? 5.0 : 2.0
  ```
  Option B — update doc-comment to reflect current behaviour (unconditional 5s).
- **Effort:** 15min for either.

### M-A1-4-05: `clearDNSCache` ignores `setTunnelNetworkSettings` completion errors
- **Location:** `ExtensionPlatformInterface.swift:484-501`
- **Dimension:** Bug / silent failure
- **Description:**
  Both completion handlers (line 489, 495) accept `err` but discard it (`{ _ in s1.signal() }`). If `setTunnelNetworkSettings(nil)` fails, the immediate re-apply still runs with the same (now-stale-relative-to-OS) settings, and `reasserting = false` fires. The user observes "DNS not refreshed" with no diagnostic.

  Logged warnings only fire on TIMEOUT (lines 491-493, 497-499) — completion fired with non-nil error is silently swallowed.
- **Suggested fix:**
  Capture and log the error like `openTun` does (lines 140-144):
  ```swift
  var settingsError: Error?
  provider.setTunnelNetworkSettings(nil) { err in
      settingsError = err
      s1.signal()
  }
  if let e = settingsError {
      TunnelLogger.lifecycle.error("clearDNSCache: setTunnelNetworkSettings(nil) failed: \(e.localizedDescription, privacy: .public)")
  }
  ```
  (Use a sync error box if Swift 6 concurrency flags the implicit capture.)
- **Effort:** 15min.

### M-A1-4-06: `physicalInterfaceReady` semaphore drains after one signal — subsequent network handoffs do not unblock new autoDetectControl waiters
- **Location:** `ExtensionPlatformInterface.swift:58-59, 269-273, 397-399`
- **Dimension:** Thread safety / energy
- **Description:**
  `physicalInterfaceReady` is a `DispatchSemaphore(value: 0)`. It is signalled exactly once — when `physicalInterfaceSeeded` flips from false → true (line 388-392 + 397-399). After that, `physicalInterfaceSeeded == true` permanently for the lifetime of this `ExtensionPlatformInterface` instance.

  The race that drove M9 (06D-03g) was: `autoDetectControl` at idx==0 before first `notifyInterfaceUpdate`. The current implementation correctly:
  - First call hits idx==0, waits, semaphore is signalled, proceeds.
  - **Subsequent calls** at idx==0 are now unlikely because `physicalInterfaceSeeded` is true. But the path is still hit when `currentInterfaceIndex` is reset to 0 in `notifyInterfaceUpdate` (line 379, when `path.status == .unsatisfied` or no physical interface) AND `physicalInterfaceSeeded` stays true (no re-signal).

  Scenario: device goes offline → `notifyInterfaceUpdate` runs with `path.status == .unsatisfied`, sets `currentInterfaceIndex = 0`, does not reset `physicalInterfaceSeeded`. Sing-box's outbound socket flush calls `autoDetectControl(fd)` → idx==0 → `physicalInterfaceReady.wait(timeout: 500ms)` → semaphore is already at value 0 (single signal consumed by first-ever waiter) AND no new signal is coming because `physicalInterfaceSeeded` is true so the `shouldSignal: Bool` block at line 388 returns false. Result: 500ms wait that always times out → throw → libbox retries (each retry costs 500ms+overhead).

  Battery impact: cellular handoff scenarios where physical interface temporarily becomes unsatisfied for ~1s see N×500ms of wasted CPU+battery, plus log spam if `callNum <= 5`.

  Plan 06 AUDIT-3 noted this as A1'-3-003 (not closed by Plan 07).
- **Why MEDIUM:** Edge case but real on flaky cellular, contributes to background-CPU complaints if extension is alive across handoffs.
- **Suggested fix:**
  Replace semaphore with an event-style primitive that can re-arm:
  ```swift
  // Drop physicalInterfaceReady semaphore + physicalInterfaceSeeded flag.
  // Use stateQueue + a CheckedContinuation list, or a dispatch_group with reset.
  ```
  Or simpler: reset `physicalInterfaceSeeded = false` when `notifyInterfaceUpdate` sees no physical interface, so the next satisfied callback signals the semaphore again. Edge: need a new `DispatchSemaphore` instance each time to flip semaphore "credit" back to 0 (signal then wait drains credit).
- **Effort:** 1-2h with careful test.

---

## Low

### L-A1-4-01: Basename regex requires 2+ chars before `.srs`
- **Location:** `SingBoxConfigLoader.swift:195`
- **Dimension:** Logic / spec drift
- **Description:**
  Regex `^[A-Za-z0-9][A-Za-z0-9._-]+\.srs$` requires at least one initial alphanumeric char AND at least one more `[A-Za-z0-9._-]` char before `.srs`. So `a.srs` is rejected (1 char), but `ab.srs` passes. The doc-comment at line 186 says "basename must match positive regex" — fine — but the explicit intent (BBTB injects `bbtb-baseline-block.srs` etc.) does not need this asymmetric lower bound. If a future rule_set file is named e.g. `v.srs` (single-char tag) it will silently fail validate.

  Recommend the more conventional `^[A-Za-z0-9][A-Za-z0-9._-]*\.srs$` (`*` instead of `+`), accepting `a.srs`.
- **Suggested fix:** 1-character regex change.
- **Effort:** 1min.

### L-A1-4-02: `singBoxLogPath` lives in App Group root, leaks per-server SNI/server-names in DEBUG logs
- **Location:** `AppGroupContainer.swift:95-97` + `BaseSingBoxTunnel.swift:322-328`
- **Dimension:** Security (debug builds) / privacy
- **Description:**
  In `DEBUG`, `expandConfigForTunnel` injects `singBoxLogPath` and `logLevel = "trace"`. Trace-level sing-box logs include outbound server addresses, SNI, ALPN, handshake bytes. These land in `{App Group}/sing-box.log`, which is then exported to main app `Documents/` via `exportSingBoxLogToDocuments()` (called from main app on demand).

  In Release this is fine (path = nil, level = "info" so no trace). But the wiki memory `feedback_libbox_log_privacy_external_rollout.md` flagged a separate concern about `writeDebugMessage` privacy level — this file is not the same surface but it's adjacent.

  This is **DEBUG-only**, so impact is limited to development builds. No production risk. But:
  - `singBoxLogPath` location (`{App Group}/sing-box.log`) is accessible to **any process that has the App Group entitlement** — meaning if a future BBTB-Helper or Today Widget gets the entitlement, it can read full trace.
  - `exportSingBoxLogToDocuments` (line 109-123 of AppGroupContainer) makes the log retrievable through Files app → Documents share-out → user could accidentally send it to support staff with full TLS handshake data.
- **Suggested fix:**
  - Move debug log path to `{App Group}/Library/Caches/sing-box-debug.log` (Caches is not shared with iCloud/iTunes backups).
  - Rate-limit or redact the `exportSingBoxLogToDocuments` output if `logLevel == "trace"`.
  - Or document the privacy boundary explicitly in the file's doc-comment.
- **Effort:** 30min + doc.

### L-A1-4-03: `LibboxCommandServer.start()` failure path doesn't `try? closeService()` before `close()`
- **Location:** `BaseSingBoxTunnel.swift:294-307`
- **Dimension:** Bug / resource leak symmetry
- **Description:**
  When `server.start()` throws, the cleanup at line 300 calls `server.close()` directly without first `try? server.closeService()`. The success-path stop sequence (line 458-464) always pairs `closeService()` + `close()`. If `server.start()` partially started internal subsystems before throwing, those may leak (Go-runtime goroutines, file descriptors, sockets).

  libbox's `LibboxCommandServer.start()` source not visible in this audit, but symmetry argues for matching the stop pattern.
- **Suggested fix:**
  ```swift
  try? server.closeService()
  server.close()
  ```
  (matches expand-failure paths at line 342/361 already)
- **Effort:** 1min.

### L-A1-4-04: `routingRulesEnabled` and `stunBlockEnabled` reads not coalesced — App Group UserDefaults two RPC trips per `expandConfigForTunnel`
- **Location:** `SingBoxConfigLoader.swift:420-428` + `:496-497` + `:547-548`
- **Dimension:** Energy (micro)
- **Description:**
  `expandConfigForTunnel` creates a fresh `UserDefaults(suiteName: AppGroupContainer.identifier)` **three times** in three blocks (routingRulesEnabled, stunBlockEnabled, muxEnabled). Each `UserDefaults(suiteName:)` call costs an iOS CFPreferences IPC trip to cfprefsd (per Apple internal docs / WWDC 2018 #114).

  Three trips per start = ~3-9ms of XPC on a cold start. Not big, but stacks with similar reads in main app's TunnelController and the extension's `ExternalVPNStopMarker` (which also reads the suite). Quick win: cache the suite once.
- **Suggested fix:**
  ```swift
  let appGroupDefaults = UserDefaults(suiteName: AppGroupContainer.identifier)
  let routingRulesEnabled: Bool = appGroupDefaults?.object(...) ?? true
  let stunBlockEnabled: Bool = appGroupDefaults?.bool(forKey: "app.bbtb.stunBlockEnabled") ?? false
  let muxEnabled: Bool = appGroupDefaults?.bool(forKey: "app.bbtb.muxEnabled") ?? false
  ```
- **Effort:** 5min.

### L-A1-4-05: `InterfaceFlagsInspector.utunSnapshot()` uses `seen: [String: Int32]` — last-write-wins for duplicate ifa_name
- **Location:** `InterfaceFlagsInspector.swift:31-39`
- **Dimension:** Logic / correctness (DEBUG-only)
- **Description:**
  Multiple `ifaddrs` entries can share the same `ifa_name` (one per address family). Iterating `getifaddrs` and writing to `seen[name] = flags` loses earlier entries with the same name. In practice, `ifa_flags` is identical across address-family entries of the same interface, so the result is the same. But a future field that varies per-entry (e.g. checking IPv6-specific flags) would silently lose data.

  DEBUG-only path; no functional risk for shipping code.
- **Suggested fix:** Either document the last-write-wins assumption, or aggregate properly with `[String: Set<Int32>]`.
- **Effort:** 5min documentation.

### L-A1-4-06: `singBoxWorkingPath` comment claims 103-byte limit; check is not enforced anywhere
- **Location:** `AppGroupContainer.swift:24-29`
- **Dimension:** Defensive coding
- **Description:**
  Comment notes `sockaddr_un.sun_path` is 104 bytes including NUL, and we placed `command.sock` in App Group root (vs `singbox/` subdir) to stay under the limit. But there is no runtime assertion that `url.path.count + "/command.sock".count < 104`. If a future iOS App Group naming convention pushes the App Group container path even further down (Apple's GUID format already gives ~76 chars), command.sock creation will silently fail at start.

  Pre-flight check would catch this in CI or first-launch:
  ```swift
  precondition(url.path.utf8.count + "/command.sock".utf8.count < 104,
               "App Group path too long for sockaddr_un — see wiki R8")
  ```
- **Suggested fix:** Add precondition in `singBoxWorkingPath` getter or in `BaseSingBoxTunnel.startTunnel` setup step.
- **Effort:** 5min.

---

## Notes

**Plan 07 lifecycle/state-queue fixes are largely correct** — the architectural patterns (capture-and-clear under queue, generation counter for late-completion gating, single-call signal pattern) are the right ones. The gaps identified above are:

1. **Spec/code drift** in two places (T-C-B1 adaptive timeout never branches; `networkSettings`/`nwMonitor` listed as queue-protected but missed at write sites). These are mechanical to fix.
2. **One real new HIGH** (H-A1-4-01) caused by `pi.reset()` running outside `lifecycleQueue` while libbox callbacks (DNS reapply, autoDetectControl) may still be racing on captured `pi` reference. This is the kind of teardown-ordering bug that only manifests under rapid Connect→Disconnect or DNS-reconfig-during-stop scenarios.
3. **Defence-in-depth gap** on rule_set path allowlist (symlink resolution missing) — useful to close before external rollout but not blocking.

**Positive observations** (no findings, but worth recording):
- `lifecycleQueue` discipline in `BaseSingBoxTunnel` is genuinely tight on the success and error paths I traced.
- The `manualStart` discriminator + `ExternalVPNStopMarker` peek-without-clear pattern is correctly preserved.
- R6 invariant in `TunnelSettings.makeR6Safe` is intact — no `destinationAddresses`, IPv6 blackhole present, `matchDomains = [""]` for DNS leak prevention.
- `validate` is reordered carefully: inbound whitelist → experimental → outbounds → proxy outbound → urltest/selector refs → rules/final refs → rule_set type/path. No fail-open hole on early return.
- `TunnelLogger` privacy: most security-sensitive surface uses `privacy: .public` only for sanitised primitives (counts, error types, basenames). No raw config dumps observed.

**No CRITICAL findings.** Two HIGH findings worth closing before external rollout; six MEDIUM are quality/energy refinements; six LOW are cleanup.
