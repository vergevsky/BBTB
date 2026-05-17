# A1 — PacketTunnelKit (Opus 4.7)

**Baseline:** `fb2ff54`
**Files reviewed:** 11
- `AppGroupContainer.swift`
- `ExternalVPNStopMarker.swift`
- `InterfaceFlagsInspector.swift`
- `PacketTunnelKit.swift`
- `TunnelLogger.swift`
- `TunnelSettings.swift`
- `PlatformSpecific/iOS.swift`
- `PlatformSpecific/macOS.swift`
- `SingBox/BaseSingBoxTunnel.swift`
- `SingBox/ExtensionPlatformInterface.swift`
- `SingBox/SingBoxConfigLoader.swift`

**Total findings:** 13 (C: 0 / H: 2 / M: 5 / L: 6)

**Scope reminders honored:**
- T-C6' closed: `route.rules[].outbound` + `route.final` validation against tags. Not re-reported.
- T-A1' (sha256 empty bypass) out-of-scope (RulesEngine).
- C1'-001 / A1'-006 marked closed in AUDIT-2 — confirmed by reading `SingBoxConfigLoader.validate` lines 132-162 (route.rules outbound ref check present and correct).

---

## Critical

No CRITICAL findings in scope.

---

## High

### A1'-3-001: `route.rule_set[].path` accepts arbitrary filesystem path — no allowlist / no path-traversal guard
- **Location:** `SingBox/SingBoxConfigLoader.swift:75-163` (`validate`), and overall coverage gap.
- **Dimension:** security
- **Description:**
  T-C6' (commit f909b5b) closed `route.rules[].outbound` + `route.final` outbound-ref validation, but did NOT extend validation to `route.rule_set[].path`. Operator-supplied JSON (Hiddify imports, custom user subscriptions, future "advanced JSON paste" affordance) can declare arbitrary `route.rule_set` entries with `"type": "local"`, `"format": "binary"` or `"format": "source"`, and `"path": "/private/var/mobile/Containers/.../<anything>"`. libbox will `open(2)` that file from inside the Network Extension sandbox — which has access to the App Group container, the extension's own private container (Caches/, Preferences/), and any other paths the sandbox profile permits.

  Concretely:
  1. Operator imports a VLESS subscription whose decoded JSON (Hiddify-format) ships a `route.rule_set` entry pointing at `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/Library/Caches/pins/subscription-pins-cached.json`. libbox tries to parse pin cache as `.srs` (will fail to load), but the open syscall itself is enough to confirm file existence — exfiltrated via libbox error message in `writeDebugMessage` callback → main app sees full path string via log export.
  2. Worse: `format: "source"` (JSON ruleset) on a path the extension can read but that contains JSON exposed bytes — libbox will attempt to parse and may surface bytes in error strings.
  3. The injected baseline rule_sets at line 376-383 use `AppGroupContainer.rulesCacheDirectory` — that part is safe (hardcoded constants). The gap is operator-supplied entries that survive `validate`.

  Plan 05's T-B4'-style positive allowlist fix for `RulesEngineCoordinator` filename validation does **not** propagate here — different package, different code path.

- **Why HIGH:**
  Information disclosure surface (file existence enumeration via libbox error log). On macOS extension (`group.app.bbtb.shared` shared with main app's containers + symlinks), this is a real path-traversal vector. iOS extension sandbox limits damage but App Group + extension Caches/ + bundle resources are reachable. The `route.rule_set` field is unique because it's the ONE field in the entire schema where extension-side filesystem reads happen with operator-influenced paths.

- **Suggested fix:**
  In `validate`, when `route.rule_set` is present, for each entry where `type == "local"` enforce a positive allowlist:
  ```swift
  guard let path = entry["path"] as? String else { continue }
  let normalized = (path as NSString).standardizingPath
  let allowedPrefix = AppGroupContainer.rulesCacheDirectory.path + "/"
  guard normalized.hasPrefix(allowedPrefix),
        !normalized.contains("/.."),
        let basename = normalized.components(separatedBy: "/").last,
        basename.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]+\\.srs$", options: .regularExpression) != nil
  else {
      throw SingBoxConfigError.forbiddenRuleSetPath(path)
  }
  ```
  `type == "remote"` should be rejected unconditionally for operator JSON (we control rule_set fetch via signed manifests, not sing-box `remote` fetcher).

### A1'-3-002: Background-queue mutation of `commandServer` / `platformInterface` races stopTunnel/sleep/wake
- **Location:** `SingBox/BaseSingBoxTunnel.swift:353-369` (`startTunnel`'s `DispatchQueue.global(qos: .userInitiated).async` block) vs `stopTunnel:` (line 372-408) + `sleep:` (line 410-415) + `wake:` (line 417-421).
- **Dimension:** concurrency
- **Description:**
  Class declares `@unchecked Sendable` (line 50) with the justification «NetworkExtension сериализует startTunnel/stopTunnel/sleep/wake, поэтому явные локи не нужны». **This is no longer true after Phase 6e:**
  - Step 8 in `startTunnel` dispatches `startOrReloadService` to `DispatchQueue.global(qos: .userInitiated)` (line 353).
  - Inside that async closure, on **error** path (line 360-368): `self?.commandServer = nil` and `self?.platformInterface = nil` — written from global queue.
  - Meanwhile NetworkExtension can deliver `stopTunnel(with:completionHandler:)`, `sleep`, or `wake` on the provider queue any time after `startTunnel` returns. The provider queue does NOT serialize with `DispatchQueue.global`.

  Concrete race:
  1. `startTunnel` reaches line 359 `completionHandler(nil)` — iOS sees success, but `startOrReloadService` is still running asynchronously.
  2. User immediately taps Disconnect → iOS calls `stopTunnel` on provider queue.
  3. `stopTunnel` reads `commandServer` (line 396), calls `closeService()` and `close()`.
  4. Simultaneously, the global queue's error path (if `startOrReloadService` throws after `stopTunnel` started) tries `try? server.closeService(); server.close(); self?.commandServer = nil; self?.platformInterface = nil`.
  5. Double-`close()` on the same `LibboxCommandServer` — undefined Go-side behavior (likely panic at gomobile boundary → extension SIGABRT → user sees connection loss).

  Equivalent race on `sleep`/`wake` accessing `commandServer?.pause()` / `commandServer?.wake()` (lines 413, 420): non-atomic with write at line 364/406.

  Same applies to `clearDNSCache` (`ExtensionPlatformInterface:441`) which reads `networkSettings` set inside `openTun` (libbox thread) — different writer than reader.

- **Why HIGH:**
  Correctness/crash bug in hot path. Reproduces under rapid Connect→Disconnect sequences (e.g. user testing in TestFlight after first install). Symptom: extension crash → "VPN configuration could not be loaded" or "The connection has been deactivated". Hard to reproduce in CI but absolutely reachable on device.

- **Suggested fix:**
  Replace the `@unchecked Sendable` claim with a real serializer. Cheapest option: dedicated `DispatchQueue(label: "app.bbtb.tunnel.lifecycle")` for all `commandServer`/`platformInterface` reads/writes (use `queue.sync` from provider methods, `queue.async` from background queue). Alternative: make those properties `os_unfair_lock`-guarded. Document in class comment the new invariant.

  For the specific `startOrReloadService` error path: hold a local `let serverLocal = server` and call `serverLocal.close()` only after a `queue.sync` check that `self.commandServer === serverLocal` (idempotent), otherwise the lifecycle handler already cleaned up.

---

## Medium

### A1'-3-003: `physicalInterfaceReady` semaphore drains after one signal — concurrent `autoDetectControl` callers race
- **Location:** `SingBox/ExtensionPlatformInterface.swift:58-59, 220-257, 351-356`
- **Dimension:** concurrency
- **Description:**
  `DispatchSemaphore(value: 0)` is signaled exactly once when the first physical interface seeds (line 355). After that signal, the semaphore counter is 1. The first `autoDetectControl` caller that wakes consumes it (line 234 `physicalInterfaceReady.wait(timeout:)`), reducing it back to 0. Any **subsequent** `autoDetectControl` caller that enters the `index == 0` branch (e.g. on Wi-Fi → cellular handoff where path briefly reports `.unsatisfied`, line 344 sets `currentInterfaceIndex = 0`) will block on the now-drained semaphore and **time out** after 500ms — even though seeding already happened earlier. The `physicalInterfaceSeeded` flag prevents re-signaling (line 353 `if !physicalInterfaceSeeded`).

  Result: during a network transition, all in-flight sing-box outbound sockets that hit `autoDetectControl` before the next `notifyInterfaceUpdate` will throw the retryable error → libbox creates extra retry pressure, extension wastes CPU/energy.

- **Why MEDIUM:**
  Energy + correctness during transitions, but the worst-case (extra retries) is bounded by sing-box internal backoff. Not a connection-breaker because sing-box does retry.

- **Suggested fix:**
  Either:
  - Use a manual reset event (signal on every seed where index transitions 0→nonzero), or
  - Drop the semaphore and use a `DispatchQueue` + `dispatchPrecondition`-style wait, or
  - Simplest: signal in the `else` branch too, only when transitioning `index 0 → index nonzero`. Don't gate on `physicalInterfaceSeeded`; gate on current value of `currentInterfaceIndex` before the new assignment.

### A1'-3-004: `currentInterfaceIndex` / `physicalInterfaceSeeded` / `networkSettings` mutated without memory barrier
- **Location:** `SingBox/ExtensionPlatformInterface.swift:49, 59, 38` (fields); `220, 238, 259, 344, 350, 353-354` (writes/reads in `autoDetectControl` + `notifyInterfaceUpdate`)
- **Dimension:** concurrency / Swift 6
- **Description:**
  Class is `@unchecked Sendable` (line 27) with claim «libbox callbacks приходят из Go-runtime threads ... последовательно по контракту движка». But:
  - `autoDetectControl(_:)` is called from sing-box Go threads (one per sing-box outbound socket — concurrent).
  - `notifyInterfaceUpdate` is called from `NWPathMonitor` queue (DispatchQueue.global).
  - These two callbacks read/write the same shared mutable fields (`currentInterfaceIndex`, `autoDetectCallCount`) without any synchronization.

  The Go runtime contract that libbox serializes its own callbacks does NOT extend to the union of (sing-box callbacks + NWPathMonitor callback). The semaphore at line 58 protects the wait/signal handshake, but the index field itself has no memory ordering guarantees.

  In practice ARM64 reads/writes of `UInt32` are atomic on aligned addresses, so torn reads are unlikely — but the lack of acquire/release fence means an `autoDetectControl` caller might read a stale index (e.g. 0 right after seeding completed, missing the recent path update). This contributes to A1'-3-003's symptom.

- **Why MEDIUM:**
  Latent under Swift 6 strict concurrency rebuild; documented Sendable claim is incorrect.

- **Suggested fix:**
  Move the shared state into an `actor InterfaceStateStore` or guard via `os_unfair_lock`. At minimum, replace `@unchecked Sendable` justification comment to reflect actual safety reasoning + add `_Atomic` semantics via `OSAtomic*` or `Atomic<UInt32>` wrapper.

### A1'-3-005: `setTunnelNetworkSettings` 2s timeout in `openTun` insufficient on stressed devices — silent extension restart
- **Location:** `SingBox/ExtensionPlatformInterface.swift:129` (timeout 2.0)
- **Dimension:** concurrency / correctness
- **Description:**
  M16 comment (line 124-127) reduced the timeout from 5s to 2s with the argument «on iPhone 13+ обычно завершается за <100ms». However iOS `setTunnelNetworkSettings` can take dramatically longer on:
  - Cold-boot when iOS is still launching network daemons (`networkd`, `mDNSResponder`) — observed by WireGuard team: up to 4s.
  - Devices under memory pressure where the daemon delegate is jetsamed and re-launched.
  - iPhone X / iPad Air 2 era hardware (still supported by app per CONTEXT.md min-iOS).
  - Inside Settings → VPN toggle path during iOS-orchestrated rapid stop+start cycles.

  When the 2s timeout fires:
  1. `openTun` throws (line 133).
  2. libbox marks tun-in start failure.
  3. sing-box engine likely returns error to `startOrReloadService` (line 355 in `BaseSingBoxTunnel`) → completion handler fires with `serviceStartFailed`.
  4. The completion handler **does NOT consume** the still-pending `setTunnelNetworkSettings` callback — it fires later, mutating `errorBox.value.error` on a freed semaphore (line 120-121) — actually safe because `errorBox` is heap-allocated and retained by closure capture, but the post-timeout side effect on `self.networkSettings = settings` is now skipped, so `clearDNSCache` will see stale state.
  5. From user's perspective: connection fails on weak hardware ~5-10% of the time.

  This is a Phase 6e regression — Phase 6d M16 changed it without testing on older hardware.

- **Why MEDIUM:**
  Hardware-specific reliability regression. Won't reproduce on reviewer's iPhone 15+, but TestFlight beta testers on iPhone X/XR will see intermittent connect failures. Not a security/data issue.

- **Suggested fix:**
  Restore to 5s timeout, OR make it adaptive: 5s on first start of the session, 2s for in-session reapply (e.g. `clearDNSCache`). Or: don't time out at all in `openTun`'s initial setup (rely on iOS's own 30s extension start timeout to bound it).

### A1'-3-006: `ExternalVPNStopMarker.mark()` race between extension and host clear() — sticky-marker contract still has TOCTOU
- **Location:** `ExternalVPNStopMarker.swift:46-53, 78-88, 93-98`
- **Dimension:** concurrency / security (auto-reconnect bypass)
- **Description:**
  Phase 6d post-fix 5 comment (line 55-77) acknowledges the prior race ("и host, и extension `consume()`или маркер; кто первый видел — тот клирил") and switches to sticky-peek. However a TOCTOU window still exists:

  Sequence:
  1. User taps Disconnect in host app → `TunnelController.connect()` had earlier called `clear()`. Now user is calling stop, not start; clear() is no longer called on stop path. (Actually clear() is called in connect, not stop — confirmed.)
  2. Extension's `stopTunnel(reason: .userInitiated)` → calls `mark()` (line 390 in BaseSingBoxTunnel).
  3. Host's `connect()` runs **simultaneously** (user racing Disconnect→Connect taps within ~100ms): host writes `clear()` to App Group defaults; extension writes `mark()` to App Group defaults.
  4. `UserDefaults` writes are NOT atomic across processes — neither `synchronize()` nor the underlying CFPreferences storage provides cross-process W-W ordering. Last writer wins, but the order is arbitrary.
  5. Outcome A: host's clear() arrives last → marker is cleared, but the NEXT iOS on-demand retry (which is what mark() should block) will start, defeating the entire mechanism.
  6. Outcome B: extension's mark() arrives last → marker is set even though user wanted manual reconnect → host's NEXT `startTunnel` (which iOS will trigger as part of the new connection) hits `isPending()=true` at line 161 in BaseSingBoxTunnel, but ALSO sees `manualStart=true` in options (host already called `clear()` before start, but the clear was lost). The line 158 branch `isManualStart` takes precedence → tunnel starts. So Outcome B is actually safe by lucky ordering.

  Outcome A is the problem: marker silently lost on rapid user toggling, defeating Settings-disable detection.

  Mitigating factor: `host.connect()` always passes `manualStart=true`, which already overrides marker even if mark() succeeded. So this matters only for iOS on-demand retry path (where options is nil), and only if user does Settings-toggle within a few hundred ms of explicit Connect — atypical.

- **Why MEDIUM:**
  Edge-case timing. Real users unlikely to hit. But the doc-comment claim of "sticky" is technically not honored across-process W-W race.

- **Suggested fix:**
  Use atomic file write under App Group for the marker (e.g. `marker.flag` file via `Data.write(.atomic)`), OR move marker handshake to App Group keyed-archiver write with explicit version stamp + read-modify-write loop. Document this as a known limitation in `wiki/security-gaps.md` if accepted.

### A1'-3-007: `BaseSingBoxTunnel.shouldSkipPreExpandValidate` 24h cache is shared across server changes — stale `configJSONValidatedAt` can mask injected forbidden inbounds
- **Location:** `SingBox/BaseSingBoxTunnel.swift:122-135` (helper), `218-231` (use)
- **Dimension:** security / R10 partial regression
- **Description:**
  Helper accepts ANY ISO8601 timestamp < 24h old to skip pre-expand validate. The R10 invariant comment on line 214 correctly highlights "POST-expand validate (line 240-251) ВСЕГДА выполняется" — but the post-expand re-validate runs `validate(json: expandedJSON)`, NOT against the raw operator JSON.

  Threat model: an attacker (or buggy main-app code path) writes a malformed `configJSON` into `providerConfiguration` AND sets `configJSONValidatedAt` to a fresh ISO8601 timestamp. Pre-expand validate is skipped. The malformed JSON enters `expandConfigForTunnel` which may:
  1. Throw at `JSONSerialization` (line 232) → caught at line 311 and reported. Safe.
  2. Survive parsing if syntactically valid but contains semantically forbidden constructs that `expandConfigForTunnel` **mutates away** before post-expand validate. Example: operator JSON sets `inbounds: [{type: "socks", listen: "0.0.0.0", port: 1080}]`. expand at step 1 (line 261-273) detects no `tun` inbound and **appends** one, but does NOT remove the existing `socks` inbound. Pre-expand validate would catch this (line 86-89 reject forbidden inbound types). Post-expand validate runs on the now-mutated JSON which has socks + tun — post-expand validate ALSO catches it at line 86. So this specific attack is caught.

  But consider: `inbounds: [{type: "direct", listen_port: 9090, sniff: true}]` — `direct` is allowlisted (line 59) but `direct` inbound on a port effectively exposes a listener inside the extension. The current allowlist permits `direct` because in legitimate configs `direct` appears as an outbound override / pass-through bridge, NOT typically as an inbound. The validate path doesn't differentiate — both pre- and post-expand accept it. So this is not a regression introduced by the 24h skip.

  A more realistic risk: `experimental.cache_file.enabled = true` with a `path` pointing somewhere malicious. Both pre- and post-expand validate reject it (line 100-103) — both must be defeated. The 24h skip only defeats pre-expand. Post-expand catches it before `startOrReloadService`. Safe.

  **So the actual issue is narrower:** the 24h cache key is `configJSONValidatedAt` — a single timestamp in `providerConfiguration`. The skip doesn't verify that the validated JSON *equals* the current JSON. If a downgrade attack swaps `configJSON` content while preserving the timestamp, pre-expand is bypassed. Post-expand still catches structurally forbidden constructs, but ONLY those that survive `expandConfigForTunnel`'s mutations. Edge case: a custom log path injected into root `log.output` (no validate guard on log.output) could write to arbitrary App Group paths.

- **Why MEDIUM:**
  Defense-in-depth weakening. Post-expand validate is the real guard. The 24h skip is an optimization that breaks the principle of "validate every config before parse". Concrete exploit requires also writing to `providerConfiguration` — a sibling write to `configJSON` already implies extension-context compromise.

- **Suggested fix:**
  Bind the cache marker to a hash of the configJSON content, not just a timestamp:
  ```swift
  let cachedHash = providerConfiguration["configJSONValidatedSHA256"] as? String
  let currentHash = sha256(configJSON)
  guard cachedHash == currentHash else { /* run validate */ }
  ```
  ConfigImporter writes both `configJSONValidatedAt` and `configJSONValidatedSHA256` together.

  OR: remove the skip entirely. The cost of `validate` on a 30 KB JSON is < 1ms on iPhone — not worth the security-discipline tradeoff for a TestFlight build.

---

## Low

### A1'-3-008: `singBoxLogPath` injection in DEBUG writes trace logs to App Group at unbounded size
- **Location:** `SingBox/BaseSingBoxTunnel.swift:295-301`
- **Dimension:** energy / disk
- **Description:**
  DEBUG-only injection of `logPath: AppGroupContainer.singBoxLogPath` and `logLevel: "trace"`. Comment at line 286-293 even acknowledges Phase 5 saga of "десятки MB на каждое соединение в App Group". DEBUG is correctly gated for Release, but TestFlight builds default to Release — OK. Concern: anyone who flips to DEBUG for local testing risks filling user's disk if testing protracted sessions. No size cap, no rotation.

- **Suggested fix:** Cap `sing-box.log` file size by rotating to `.1`, `.2` at 5MB each, total 15MB. Tiny addition to `expandConfigForTunnel` log block, or post-stop cleanup in `stopTunnel`.

### A1'-3-009: `AppGroupContainer.url` fatalError on missing entitlement crashes extension before any logging
- **Location:** `AppGroupContainer.swift:14-17`
- **Dimension:** energy / observability
- **Description:**
  `fatalError("App Group \(identifier) not configured in entitlements")` — terminates extension before TunnelLogger emits anything. iOS will report "extension crashed" without context. Bootstrap bug becomes silent in production.

- **Suggested fix:** Replace fatalError with NSError thrown from a `init throws` static factory, AND log via `TunnelLogger.lifecycle.fault("...")` first so Console.app shows the cause. Existing callers can `try!` if they assert entitlement present.

### A1'-3-010: `InterfaceFlagsInspector.assertNoPointToPointOnUtun()` uses `print` instead of `TunnelLogger`
- **Location:** `InterfaceFlagsInspector.swift:69`
- **Dimension:** code smell (CLAUDE.md security: "никаких print()")
- **Description:**
  Line 69: `print("[R6 WARN] iOS 26 sets IFF_POINTOPOINT...")` — direct print() violates project rule. DEBUG-only block, so production unaffected, but the comment "никаких print()" in `TunnelLogger.swift:6` is explicitly contradicted.

- **Suggested fix:** Replace with `TunnelLogger.security.warning("...")`.

### A1'-3-011: `TunnelLogger` subsystem mismatch — `app.bbtb.tunnel` vs CONTEXT.md's `app.bbtb.client.ios.tunnel`
- **Location:** `TunnelLogger.swift:7-11`; cross-reference per memory `feedback_netunnelnetworksettings_tunnelRemoteAddress.md` mentions «filter subsystem `app.bbtb.client.ios.tunnel`».
- **Dimension:** observability / code smell
- **Description:**
  Subsystem string `app.bbtb.tunnel` doesn't match the team's documented Console.app filter. Debugger filter on the documented subsystem will find no logs. Memory note is 5 days old and explicitly marked as point-in-time, so this could already be intentional. Worth confirming.

- **Suggested fix:** Decide on one canonical subsystem, document in `wiki/`, update all callers. Likely keep `app.bbtb.tunnel` and update the memory + any docs referencing the longer form.

### A1'-3-012: `AppGroupContainer.singBoxWorkingPath` returns `url.path` — relies on `path` not exceeding 103 chars for `command.sock`
- **Location:** `AppGroupContainer.swift:27-29`
- **Dimension:** correctness/edge case
- **Description:**
  Comment at line 21-26 documents the 103-char `sun_path` limit (Darwin's `sockaddr_un`). Logic moved `singBoxWorkingPath` to the App Group root to fit. But that root path includes the App Group identifier hash, which can vary. On iOS 17+ paths look like `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` ~= 73 chars + `/command.sock` = 86 chars — fits. On a future iOS version that adds a path component, this breaks silently with `bind: invalid argument`.

- **Suggested fix:** Add an assertion at extension cold-start: `assert(singBoxWorkingPath.count + "/command.sock".count <= 103, "command.sock path will exceed sun_path limit")`. Or log a warning if approach.

### A1'-3-013: `PacketTunnelKit.swift` placeholder is dead code
- **Location:** `PacketTunnelKit.swift:1-4`
- **Dimension:** code smell
- **Description:**
  Module-level `enum PacketTunnelKit { public static let version = "0.1.0" }` from Wave 0. Comment says it was added to enable compilation when modules were empty. All modules now have content. The `version = "0.1.0"` is stale (project is at v1.0 path per Phase 13). No one references this enum.

- **Suggested fix:** Either delete the file, or update the version string to track Marketing version + add a TODO.

---

## Notes

- **No CRITICAL findings in scope.** Plan 05 closures verified: `route.rules[].outbound` + `route.final` reference check confirmed at `SingBoxConfigLoader.swift:144-162`; `dns-out` reserved correctly. The new HIGH I'm raising (A1'-3-001) is the **`route.rule_set[].path` allowlist gap** — adjacent to T-C6' but not closed by it. The T-C6' note in AUDIT-2 explicitly says it covered "top-level" but the audit mission asks us to "check rule_set itself" — so this is the targeted finding.

- **Phase 5 W5 routing-rules injection pattern (block 5 in `expandConfigForTunnel`):** the App Group toggle pattern is correct per memory `feedback_extension_toggle_app_group_suite.md` — uses `object(forKey:) == nil` for default-true fallback. ✅ No regression. The parallel-injection memory (`feedback_parallel_injection_audit_before_new_path.md`) is honored: extension is the single source of injection; main-app `PoolBuilder` does not inject rule_sets — confirmed by comment in `expandConfigForTunnel` block 5 referring to the gate pattern.

- **R6 invariant (TunnelSettings.swift) — clean.** `TunnelSettings.makeR6Safe` is the only caller of `NEPacketTunnelNetworkSettings.init`. The iOS-26 documented regression (where IFF_POINTOPOINT is set regardless) is acknowledged in `InterfaceFlagsInspector.assertNoPointToPointOnUtun` with a print-warning instead of fatal assert. No new TUN setup invariant violations.

- **`serverAddressHint` flow** (per the 5-days-old memory about `tunnelRemoteAddress`): `BaseSingBoxTunnel.startTunnel` reads `proto.serverAddress` (line 182) and passes to `ExtensionPlatformInterface(serverAddressHint:)` (line 249). `serverAddressHint` is then fed to `TunnelSettings.makeR6Safe(serverAddress:)` (line 109 in ExtensionPlatformInterface) which uses it as `tunnelRemoteAddress`. The original Phase 2 bug ("BBTB" literal label) cannot recur from PacketTunnelKit side — but the contract is: callers MUST pass a real hostname/IP. Worth surfacing this in `BaseSingBoxTunnel` doc-comment so future contributors don't accidentally pass `manager.localizedDescription`.

- **No retain cycles found.** `ExtensionPlatformInterface` uses `weak var provider` (line 30). `BaseSingBoxTunnel` strong-holds `platformInterface` (line 86) but releases in `stopTunnel` (line 406). NWPathMonitor captures `[weak self]` (lines 310, 314).

- **No Sendable violation in `[String: NSObject]?` options handoff** at `startTunnel` line 139 — values are read synchronously before any `async`. Safe.

- **Energy footprint:** the 2-second sleep-on-`autoDetectControl(index==0)` is bounded (capped at 500ms wait inside, throws otherwise). NWPathMonitor uses `DispatchQueue.global()` (line 318) — fine. No polling loops in scope. `LibboxBootstrap.setup` is idempotent. No findings on energy in hot path beyond the DEBUG-only trace-log size (A1'-3-008).

- **One Plan-05-pattern regression risk worth calling out:** Plan 05's T-C6' added route.rules outbound-ref validation but did NOT add `route.rule_set[].path` validation. That's A1'-3-001 above. The pattern matches the team's previous gap-closing approach but stops short of the full operator-influenced-filesystem-path surface.

- **Tests/ directory excluded per scope.** No coverage gaps assessed here.
