# A3' — AppFeatures/MainScreenFeature RE-AUDIT (Opus 4.7, Plan 04 / commit 55523dd)

**Scope:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` (29 files, 6,481 lines).
**Mode:** Closure verification of 8 Plan 02/03 fixes + regression hunt on touched paths + fresh findings.
**Total new findings:** 11 (CRITICAL: 0, HIGH: 2, MEDIUM: 4, LOW: 5).

---

## 1 — Closure Verification

| ID         | Fix commit | Claim | Verified? | Evidence |
|------------|-----------|-------|-----------|----------|
| A3-001     | `c661634` T-A4 | `deinit` removes 3 observers; observer fields `nonisolated(unsafe)`. | **PASS** | `MainScreenViewModel.swift:1125-1135` — explicit `deinit { ... }` removes `rulesUpdateObserver` / `killSwitchObserver` / `nevpnStatusObserver`. All three fields declared `private nonisolated(unsafe) var ... : NSObjectProtocol?` at lines 114, 147, 158 with correct Swift 6 rationale doc-comment. |
| A3-002     | `41349c2` T-B8 | `.connected` branch uses `min(connectedDate, state.connectionStart)` when both non-nil. | **PASS** | `MainScreenViewModel.swift:522-541` — `if let cd = connectedDate, let cs = state.connectionStart { since = min(cd, cs) } else if let cd { ... } else if let cs { ... } else { since = Date() }`. Comment explicitly cites A3-002 / WireGuard iOS history. |
| A3-004     | `cc88712` T-B4 | `killSwitchObserver` uses `queue: nil`. | **PASS** | `MainScreenViewModel.swift:233-239` — `queue: nil`, body keeps `Task { @MainActor [weak self] in self?.handleUserDefaultsChange() }`. Matches `nevpnStatusObserver` pattern at line 253. |
| A3-005     | `ce54f72` T-B5 | `provisionTunnelProfile` wrapped in `provisionSerializer.run`; internal method renamed `_provisionTunnelProfileInternal`. | **PASS (with caveat — see A3'-002)** | `ConfigImporter.swift:66-70` declares `private actor ProvisionSerializer { func run<T: Sendable>(_:) async rethrows -> T }`. Public `provisionTunnelProfile(for:)` (line 501-505) delegates to `_provisionTunnelProfileInternal` (line 507) inside `try await provisionSerializer.run { [self] in ... }`. Mutual-exclusion guaranteed. Caveat: serializer is on a *new* per-importer actor, NOT MainActor as A3-005 originally suggested — but mutual exclusion still holds and SwiftData ModelContext is created fresh per call. |
| C3-001     | `41349c2` T-B8 | `handleForegroundReentry` calls `handleForeground()` after `tunnel.handleForeground()`. | **PASS** | `MainScreenViewModel.swift:710-720` — after `await tunnel.handleForeground()` (no-op in production per line 613) the method calls `await handleForeground()` (line 720, with comment crediting C3-001). |
| C3-002     | `7dc86b1` T-B2 | `TunnelController.disconnect` uses `ManagerSelector.ourManagers(from:).first`. | **PASS** | `TunnelController.swift:484-491` — `let managers = try await NETunnelProviderManager.loadAllFromPreferences()` then `guard let manager = ManagerSelector.ourManagers(from: managers).first else { scheduleClearManualDisconnect(); return }`. |
| C3-003     | `32c45d0` T-B1 | Both `reparseFromKeychainScalar` and `reparseFromKeychain` have `case "tuic":`. | **PASS** | `ConfigImporter.swift:796-820` (scalar variant) AND `ConfigImporter.swift:928-950` (legacy variant). Both branches require identical payload keys (uuid/password/congestionControl/udpRelayMode) and reconstruct `ParsedTUIC` with congruent shape. Payload schema matches `buildKeychainPayload` `.tuic` branch (line 1010-1022) — round-trip safe. |
| A6-001/002 | `bdba28d` T-B6 | `killSwitchEnabled` default = `true` everywhere. | **PASS** | 4 reads grepped:<br>• `SettingsViewModel.swift:36` `@AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = true`<br>• `SettingsViewModel.swift:602` `... as? Bool ?? true`<br>• `ConfigImporter.swift:1426` `... as? Bool ?? true`<br>• `MainScreenViewModel.swift:204` `... as? Bool ?? true`<br>• `MainScreenViewModel.swift:971` `... as? Bool ?? true`<br>All five sites consistent. R4 invariant restored. |

**Verdict:** 8/8 closures verified PASS. No partial closures or backtrack. Comment-trail (`T-A4 / T-B8 / T-B4 / T-B5 / T-B2 / T-B1 / T-B6`) is correctly anchored in source.

---

## 2 — New Findings (re-audit)

### [HIGH] A3'-001: `_provisionTunnelProfileInternal` performs second SwiftData fetch on auto-mode CDN path while a concurrent call already holds the serializer — re-blocked Connect

- **Location:** `ConfigImporter.swift:507-668` (T-B5 actor-serialized body).
- **Dimension:** logic, energy, performance.
- **Description:** T-B5 fix wraps `_provisionTunnelProfileInternal` in `provisionSerializer.run { ... }`. Mutual exclusion is correct. **But** the body is now ~160 lines (includes TaskGroup of up to 8 concurrent Keychain reads + CDN apply branch + PoolBuilder + R1 validate + `tunnelProvisioner.provisionTunnelProfile` XPC). In Auto-mode with 50 supported servers the bounded TaskGroup alone is 100-500ms; PoolBuilder builds a 50-outbound urltest JSON; SingBoxConfigLoader.validate parses it. **All under serializer lock.** Concurrent callers (SwiftDataFailoverProvider mid-failover; user re-taps Connect during in-flight provisioning; ServerListVM background refresh that calls importer) are *blocked* not just on SwiftData fetch (the original A3-005 race target) but on the FULL provisioning pipeline, including a synchronous-on-the-actor `tunnelProvisioner.provisionTunnelProfile` XPC trip (`saveToPreferences + loadFromPreferences`, 200-1000ms on a contended port).

  Worst-case path:
  1. User taps Connect (Auto mode) → enters serializer → starts 50-server keychain TaskGroup + R1 validate + XPC save (~3s).
  2. Mid-failover watchdog fires `failoverProvider.nextServerAttempt()` → `SwiftDataFailoverProvider.attempt` closure calls `provisioner.provisionTunnelProfile(for: nextID)` → **blocks on serializer** for the remaining ~3s of the first call.
  3. By the time the failover provision lands, `awaitConnectedStatus` in step 1 has already timed out and thrown -3. The watchdog's `next.attempt()` then drives a SECOND `tunnel.connect()` which competes with the now-failed original Connect's `manualDisconnectInProgress` state machine.

- **Why it matters:** Original A3-005 only needed to serialize the SwiftData-touching window (≤30ms of fetch+save). Serializing the entire 1-3s provisioning pipeline introduces a new contention class: failover and concurrent reconnect attempts can stall behind a slow Connect. This wasn't a regression *test* failure (no integration test simulates this overlap) but it's a real-device regression for users with large server pools on slow networks.
- **Suggested fix:** Narrow the serialization window to ONLY the SwiftData ModelContext fetch+save block. Concretely:
  ```swift
  public func provisionTunnelProfile(for selectedID: UUID?) async throws {
      // Critical section: SwiftData fetch + keychain reads (FetchDescriptor crossing).
      let parsedList = try await provisionSerializer.run { [self] in
          try await fetchSupportedAndReparse(for: selectedID)
      }
      // Non-critical: PoolBuilder + validate + CDN + provisioner.provisionTunnelProfile.
      // Multiple concurrent callers serialize their fetches but can run their downstream
      // build+save in parallel (XPC save serializes inside NEPreferencesAgent anyway).
      try await buildAndSave(parsedList: parsedList, selectedID: selectedID)
  }
  ```
  Acceptable interim: leave serializer wrapping the whole flow but document the latency contract in `06C-CONTEXT.md` so failover RFC is aware of the bound.

---

### [HIGH] A3'-002: `ProvisionSerializer` uses `rethrows` but operation closure is `@Sendable () async throws -> T` — `rethrows` is dead code

- **Location:** `ConfigImporter.swift:67-69`.
- **Dimension:** logic, type-safety.
- **Description:** Declaration:
  ```swift
  private actor ProvisionSerializer {
      func run<T: Sendable>(_ op: @Sendable () async throws -> T) async rethrows -> T {
          try await op()
      }
  }
  ```
  `rethrows` is meaningful only when the function is throwing iff one of its closure args throws. Here the closure is declared `throws` (not `rethrows`) — Swift's `rethrows` semantics on the parent require the closure to be ANY throwing closure, but actually the parent ALWAYS throws when the closure throws. Functionally equivalent to `throws`. The `rethrows` keyword in actor isolation has historical bugs (SR-15924 family) — `Task { try await serializer.run { try await x() } }` should compile, BUT some Xcode 26-betas reject `rethrows` across actor hops with `cannot satisfy 'rethrows' requirement` when `T` is non-Sendable in a downstream caller.

  Inspection of the only callsite (`provisionTunnelProfile(for:)` line 502-504) confirms it uses `try await provisionSerializer.run { ... }` — works because `_provisionTunnelProfileInternal` also throws. But if any future test or callsite passes a non-throwing closure, the compiler still requires `try` (because `rethrows` resolves to throws at the static call site here). The annotation is technically misleading.

- **Why it matters:** Subtle. Not a runtime bug today. But if a refactor adds a non-throwing op (e.g. async-only diagnostics), the compiler error surface is non-obvious (`rethrows` + actor hop + generic T). Future tech debt.
- **Suggested fix:** Replace `rethrows` with `throws` — the body always throws when `op` throws, no behavior change:
  ```swift
  func run<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
      try await op()
  }
  ```

---

### [MEDIUM] A3'-003: `nonisolated(unsafe)` observer fields are mutated from `wireRulesCoordinator` (MainActor) — not just init — Swift 6 strict mode may flag

- **Location:** `MainScreenViewModel.swift:111-114, 998-1027`.
- **Dimension:** thread-safety, Swift 6.
- **Description:** A3-001 closure correctly added `nonisolated(unsafe)` to enable `deinit` access. The doc-comment at line 111-113 claims "only written from MainActor (init / wireRulesCoordinator)". `wireRulesCoordinator` is `public func ... async` (line 998) — `MainActor` isolation is implicit because the enclosing class is `@MainActor`. But `async` methods on MainActor classes can be called from any actor; the body **runs on MainActor** but the call boundary is an actor hop. The mutation `rulesUpdateObserver = NotificationCenter.default.addObserver(...)` at line 1011 is inside an async function — fine, runs on MainActor.

  However, `nonisolated(unsafe)` opts the field out of MainActor isolation entirely. The compiler will NOT enforce that the mutation happens on MainActor anymore — it's the developer's responsibility. The pattern works today because `wireRulesCoordinator` is `async` so the await boundary forces a MainActor hop, and `deinit` is non-isolated so it can read. But if a future maintainer adds a synchronous setter (or another async method that touches the field), the type system won't catch a cross-actor write.

  This is borderline acceptable for Swift 6 — the doc-comment is the contract. Pre-TestFlight: low risk. Post-TestFlight: code review should explicitly check any future write site.

- **Why it matters:** Subtle invariant relying on doc-comment discipline rather than the type system. Not a defect today.
- **Suggested fix:** Keep `nonisolated(unsafe)` (no clean alternative without `Atomic` or `OSAllocatedUnfairLock`). Add a precondition assertion in `wireRulesCoordinator`:
  ```swift
  public func wireRulesCoordinator(_ coordinator: RulesEngineCoordinator) async {
      assert(Thread.isMainThread, "wireRulesCoordinator must execute on MainActor")
      // ... existing body
  }
  ```
  Runtime-only check, defends the invariant.

---

### [MEDIUM] A3'-004: `applyVPNStatus` `.connected` `min(cd, cs)` can lock to a future-dated `connectedDate` if iOS clock was rewound

- **Location:** `MainScreenViewModel.swift:533-541`.
- **Dimension:** logic.
- **Description:** The A3-002 fix `since = min(cd, cs)` correctly handles the legitimate case where path-1 fired Date()-fallback before iOS populated connectedDate. But consider: user has VPN connected for 6 hours, manually changes system clock backward by 1 hour (e.g. crossing timezone on iOS that lacks NTP, or settings sync). `NEVPNConnection.connectedDate` is wall-clock absolute (not monotonic). Next observer fires `.connected` → `cd` = "1 hour ago" wall-clock; `cs` = "5 hours ago" wall-clock. `min(cd, cs) = cs = 5h ago`. Timer shows 5h:00m. **But** the connection in reality has been up for 6 wall-clock hours (relative to the now-rewound clock, this is "6h ago old-time = 5h ago new-time"). Timer is now subtly wrong by the clock-shift delta.

  Conversely, clock rolled FORWARD (rare, but iOS DST transition for users in some regions): `cd` becomes "1 hour ahead" of `cs`. `min` picks `cs`. Timer correct.

  Practical impact: clock-rewind during a live session shows timer drift. Most users won't notice; the original buggy `??` fallback had identical behavior. Fix did not regress this; just worth noting that absolute-time min() retains this property.

- **Why it matters:** Edge case. Clock drift on iOS via NTP can occur quietly and is bounded to ~30s. DST jumps are 1h. Timer drift visible but not user-blocking.
- **Suggested fix:** Out-of-scope for TestFlight. Long-term: use `Date.now`-based mono interval recording on first `.connected` and ignore subsequent `connectedDate` updates within same session. Tracking only.

---

### [MEDIUM] A3'-005: `dedupe` guard at line 475 still keys on `(NEVPNStatus, Date?)` — for `.connected` with `connectedDate=nil`, dedupe collapses on the second event even when first was a Date() fallback

- **Location:** `MainScreenViewModel.swift:471-479` (outer dedupe). Related to A3-002 fix.
- **Dimension:** logic.
- **Description:** The A3-002 fix improved the `since` resolution inside the `.connected` branch but did NOT change the **outer dedupe key**:
  ```swift
  guard lastAppliedVPNStatus != status || lastAppliedConnectedDate != connectedDate else { return }
  ```
  Scenario:
  1. `.connecting` → dedupe miss → applied, lastApplied = (.connecting, nil).
  2. Path-1 fires `.connected` with `connectedDate=nil` → dedupe miss (status differs) → applies; the `.connected` branch sets `state.connectionStart = Date()` via the `cs = nil` fallback (line 540).
  3. Path-2 (foreground or NEVPN echo) fires `.connected` with `connectedDate=<real>` → dedupe miss (lastApplied was nil, now real Date) → applies; **but** `min(cd, cs)` picks `min(<real>, Date()_from_step_2)`. If `<real>` is from BEFORE step 2 (which it is — connectedDate ≤ event arrival time), then `cd < cs` and `since = cd` (correct).
  4. **However**, if a third event arrives later with the SAME `connectedDate=<real>` (very common — NEVPN emits identical echoes), dedupe collapses → no-op. Correct dedupe.

  But: if the *first* observed event is `.connected` + `connectedDate=nil` (which the field history of WireGuard iOS shows happens on slow XPC paths), then a SECOND event arrives with `.connected` + `connectedDate=nil` AGAIN (iOS still hasn't populated), dedupe collapses → second event no-op. Bootstrap path with `applyInitialStatusSnapshot` would *also* be ignored if it fires after — `applyInitialStatusSnapshot` checks `initialManagersApplied` flag, not the dedupe key, so it's OK. **But** subsequent `foregroundReentry → handleForeground → applyVPNStatus(.connected, real_cd)` correctly bypasses dedupe (new connectedDate) — handled.

  The narrow remaining gap: if NEVPN never produces an event with non-nil connectedDate, AND the user never foregrounds, the timer stays anchored at Date() from step 2. This is the original A3-002 concern with the fix in place. The fix narrows but does not eliminate.

- **Why it matters:** Edge case. `handleForeground` is the safety net (called on every scene `.active`). Without `.active` cycle, timer drift = `connectedDate population delay` ≈ 50-500ms. Acceptable for TestFlight.
- **Suggested fix:** Not required pre-TestFlight. Track for v1.1 if telemetry shows nonzero "timer Date()-only" sessions.

---

### [MEDIUM] A3'-006: `TunnelController.disconnect` pays unconditional XPC `loadAllFromPreferences` even when `cachedManager` is fresh

- **Location:** `TunnelController.swift:484-491` (T-B2 fix code).
- **Dimension:** energy, performance.
- **Description:** The C3-002 fix filters disconnect through `ManagerSelector.ourManagers(from: managers).first`, BUT it **always** loads all managers from preferences via XPC, even when `cachedManager` is non-nil (refreshed on bootstrap + every `.bbtbProvisionerDidSave`). Connect path (line 371) reuses `cachedManager` and only falls back to refresh when nil — DEC-06d-02 ≤2 XPC trips contract. Disconnect now pays +1 unnecessary XPC trip per Disconnect tap.

  In practice: ~150-400ms additional tap latency. Not a crash class, but a regression vs the connect-side optimization. The ManagerSelector filter is correct; the cost is the extra `loadAllFromPreferences`.

- **Why it matters:** Inconsistent with connect-path optimization. Phase 6d perf budget (DEC-06d-02) tracks XPC trips per command; disconnect now has 1 extra.
- **Suggested fix:** Prefer cached manager, fall back to load:
  ```swift
  let manager: NETunnelProviderManager
  if let cached = cachedManager,
     ManagerSelector.ourManagers(from: [cached]).first != nil {
      manager = cached
  } else {
      let managers = try await NETunnelProviderManager.loadAllFromPreferences()
      guard let m = ManagerSelector.ourManagers(from: managers).first else {
          scheduleClearManualDisconnect()
          return
      }
      manager = m
  }
  ```
  Same safety contract, 1 fewer XPC trip on warm cache path.

---

### [LOW] A3'-007: `TUIC reparse` payload schema reconstruction omits `pinSHA256` validation vs Hysteria2 path

- **Location:** `ConfigImporter.swift:796-820` (scalar TUIC) and `928-950` (legacy TUIC).
- **Dimension:** correctness, defense-in-depth.
- **Description:** Both new TUIC branches read `payload["pinSHA256"] ?? ""` and convert empty-string to nil via `pin.isEmpty ? nil : pin`. **But** they do NOT validate the format — Hysteria2's same field is also just-read-as-string, so this is consistent with prior behavior. SubscriptionPinManager handling lives elsewhere; reparse stage trusts the keychain payload. Fine for round-trip from `buildKeychainPayload .tuic` (which writes the validated pin from `parsed.pinSHA256`).

  However: if a malicious adversary writes a corrupt pinSHA256 directly to Keychain (T-A7 hardening), the reparse path doesn't re-validate. T-A7 closed the placeholder issue (DEBUG gate) but the reparse path doesn't enforce length/hex shape. Out of scope for T-B1 closure (which only fixes the absence of `case "tuic":`), but worth flagging.

- **Why it matters:** Defense-in-depth gap. Keychain write path is the primary trust boundary; reparse just consumes. Low severity.
- **Suggested fix:** Add a thin `pinSHA256` shape check (`pin.count == 64 && pin.allSatisfy { $0.isHexDigit }`) before assignment in both reparse branches. Mirror to Hysteria2 for parity.

---

### [LOW] A3'-008: `ConfigImporter.@unchecked Sendable` annotation still present despite ProvisionSerializer fix — annotation is now defensible but doc-comment outdated

- **Location:** `ConfigImporter.swift:72`.
- **Dimension:** documentation, type-safety.
- **Description:** `public final class ConfigImporter: ConfigImporting, @unchecked Sendable` — opt-out remains. T-B5 introduced `ProvisionSerializer` actor for the hot path, but `@unchecked Sendable` was the original A3-005 concern. Now most SwiftData fetches go through the serializer, but:
  - `loadActiveServer()` (line 102): creates `ModelContext` on caller actor (not serialized).
  - `countSupportedConfigs()` (line 116): creates `ModelContext` on caller actor (not serialized).
  - `importFromRawInput` (line 139): creates `ModelContext` on caller actor; touches subscription tables.
  - `runIsSupportedUpgrade` (line 1028 — not shown, but referenced): also unserialized.

  Concurrent calls between these and `provisionTunnelProfile` can still happen. The original A3-005 race was specifically `provisionTunnelProfile` ↔ `failoverProvider.attempt` → also `provisionTunnelProfile` → that pair is now serialized. But `provisionTunnelProfile` ↔ `importFromRawInput` (concurrent user QR scan during failover) — NOT serialized.

  Probability low (user has to scan QR mid-failover), impact medium (SwiftData crash).

- **Why it matters:** Original A3-005 scope was narrower than full ConfigImporter actor isolation. T-B5 closed the most-trafficked race but not all of them.
- **Suggested fix:** Long-term: make ConfigImporter an actor. Pre-TestFlight: acceptable. Update class-level doc-comment to clarify "ProvisionSerializer protects provisionTunnelProfile but other SwiftData-touching public methods remain unsynchronized; user-facing UX rarely overlaps them."

---

### [LOW] A3'-009: `showFailoverBanner` 5s auto-dismiss Task still not cancelled on re-arm — second banner can disappear early (A3-014 carry-forward, NOT closed by Plan 03)

- **Location:** `MainScreenViewModel.swift:614-625`.
- **Dimension:** UX.
- **Description:** Same pattern as flagged in A3-014. Each `showFailoverBanner` call spawns a Task `{ sleep(5); if .failover { hide } }`. If two failovers fire within 5s (multi-server cascade), the FIRST task can clear the SECOND banner prematurely. Not in T-B8 scope; carry-forward.
- **Why it matters:** Multi-server failover UX. Second banner shows for less than 5s, sometimes ~1s.
- **Suggested fix:** Store `failoverDismissTask: Task<Void, Never>?`; cancel and replace on each call. Pattern at `TunnelWatchdog.stableSessionTask` shows the canonical form.

---

### [LOW] A3'-010: `ConnectionTimer.format(interval:)` displays "00:00:00" for negative interval — silent corruption mask if `since > Date()`

- **Location:** `ConnectionTimer.swift:46-52`.
- **Dimension:** correctness.
- **Description:** `let total = max(0, Int(interval))` — if `since > Date()` (e.g. corrupted bootstrap snapshot reading clock-rewind state), timer reads "00:00:00" even when state is `.connected(since:)`. The fix is sane (no negative timer), but combined with A3'-004 (clock rewind), a clock-rolled-back session could show 00:00:00 timer instead of the real elapsed since UTC start.

  Acceptable today: A3-002 fix makes `min(cd, cs)` resolution sound enough that future-dated `since` should only arise from corrupted snapshots, not normal flow.

- **Why it matters:** Defensive coding gap. Low priority.
- **Suggested fix:** Log a warning when `interval < -1s` (1s slack for atomic clock skew). Telemetry signal for malformed snapshots.

---

### [LOW] A3'-011: `_provisionTunnelProfileInternal` extracts `serverHost` from `parsedList[0]` — fragile in Auto-mode if first parsed entry is unreachable

- **Location:** `ConfigImporter.swift:677-687`.
- **Dimension:** UX, robustness.
- **Description:** In Auto-mode (selectedID == nil), `parsedList` may contain 50 servers. `serverHost = parsedList[0]` is the first **by enumeration order from SwiftData fetch sorted by id.uuidString** (per FailoverProvider convention). This is fed to `NEPacketTunnelNetworkSettings.tunnelRemoteAddress` (line 1406 → memory `feedback_netunnelnetworksettings_tunnelRemoteAddress.md`). If the first server's host is invalid (e.g. malformed via subscription corruption that slipped past SubscriptionMergeService), the tunnel display field gets garbage even though sing-box uses urltest and picks a different server. Status pill might show wrong server name.

  In practice: probably fine. SubscriptionMergeService + KeychainStore + R1 validate gate corrupt entries out. But the contract here is brittle.

- **Why it matters:** Defensive coding. Auto-mode failover already cycles through pool; first-entry as display anchor doesn't break functionality.
- **Suggested fix:** Document the contract in source. Optionally use the urltest winner (after probe) if cached in `supportedServerSnapshot`.

---

## 3 — Regressions Introduced by Plan 02/03 Fixes

| Fix | Risk hypothesis | Verdict |
|-----|------------------|---------|
| T-A4 deinit + `nonisolated(unsafe)` | Swift 6 race risk on observer field writes outside init. | **Low risk.** Only write sites: init (lines 233, 253, in init) and `wireRulesCoordinator` (line 1011, async MainActor). `deinit` is non-isolated, reads tokens. NotificationCenter.removeObserver is thread-safe. No write-from-non-MainActor path observed. Doc-comment correct. See A3'-003 for nuance. |
| T-B8 timer `min()` | Edge case both Dates equal, one far in future (bad data). | **Identified A3'-004 (clock rewind) and A3'-010 (future-dated since masked).** Neither is a TestFlight blocker — A3-002 fix is strictly better than the previous `??` short-circuit. No regression. |
| T-B5 actor wrap | provisionSerializer might serialize too much, quick re-import blocks Connect. | **Confirmed A3'-001 (HIGH).** Serializer covers the whole 1-3s pipeline (TaskGroup, R1 validate, XPC save). Failover and concurrent reconnect can block. Narrow the critical section. |
| T-B1 TUIC reparse correctness | Payload schema reconstruction. | **PASS.** Both branches mirror `buildKeychainPayload .tuic` exactly. Round-trip safe. See A3'-007 for defense-in-depth gap (no shape validation of pinSHA256 — but parity with existing protocols). |
| T-B4 killSwitchObserver queue: nil | UserDefaults.didChange storm potential. | **PASS.** `queue: nil` matches the project-wide pattern. Internal `Task { @MainActor [weak self] in ... }` hop is canonical. No spawn-storm exposure beyond what `nevpnStatusObserver` already has. |
| T-B2 disconnect ManagerSelector | First-manager grab from mixed install. | **PASS for safety.** **Regression A3'-006 for energy** — extra XPC trip vs cached path. |
| T-B6 killSwitch default `true` | Boolean cascade through 5 sites. | **PASS.** All 5 sites consistent. R4 (kill-switch must be ON for ToS compliance) invariant restored. |

---

## 4 — Notes / Healthy Patterns

- **MEMORY.md compliance:**
  - `feedback_nevpn_xpc_mach_port.md` — observer (line 257-268) reads status from `notification.object` directly, NO `loadAllFromPreferences` in callback. Compliant.
  - `feedback_nevpn_observer_queue_main.md` — all three VM observers (`killSwitchObserver` L233, `nevpnStatusObserver` L253, `rulesUpdateObserver` L1011) use `queue: nil`. T-B4 closure compliant.
  - `feedback_connectedDate_authority_for_since.md` — `applyVPNStatus` `.connected` branch uses `connectedDate` as primary authority with `min(cd, cs)` improvement. T-B8 compliant.
  - `feedback_tunnelcontroller_disconnect_race.md` — `disconnect()` early-exits on `.disconnected/.invalid` (line 490). Compliant.
  - `feedback_auto_reconnect_user_intent_guard.md` — `userIntendedConnected` guard at TunnelController line 713-716. Compliant.
  - `feedback_swiftdata_uuid_predicate.md` — `_provisionTunnelProfileInternal` uses `#Predicate { $0.isSupported == true }` (Bool, safe). Explicit-selection `if let id = selectedID, supported.first(where: { $0.id == id })` — Swift filter, safe. FailoverProvider uses fetch-all + Swift filter. Compliant.
  - `feedback_phase6d_architectural_patterns.md` — DEC-06d-01 cold-start defer (foreground reentry detached Task at line 698). DEC-06d-02 ≤2 XPC trips (regressed by A3'-006 — disconnect now +1). DEC-06d-03 event-driven (observer streams, no polling). Mostly compliant.

- **What looks healthy:**
  - Observer-stream architecture in `TunnelController` (status broadcast, makeStatusStream, finishStatusContinuation) is well-isolated and survives across reconnect cycles.
  - `OnDemandRulesBuilder` single-source-of-truth pattern (4 callsites all go through `applyCurrentState`).
  - `ManagerSelector` filter usage now consistent across connect/disconnect/bootstrap/handleWake.
  - `applyVPNStatus` state-machine dedupe (outer + inner) is well-commented and explicitly named in source.
  - `ConfigImporter.reparseFromKeychainScalar` Sendable-friendly variant correctly avoids passing `@Model` objects across Task boundaries.
  - `TunnelWatchdog` 4-gate D-08 invariant remains intact; no regressions on debounce / stable-session logic.

- **What's NOT changed but worth post-TestFlight follow-up:**
  - A3-003 init-time seed Task race (carry-forward, Tier C).
  - A3-006 (cached manager miss on first install, second XPC trip).
  - A3-007 performToggleImpl race with concurrent delete.
  - A3-008 OnDemandRulesBuilder reads UserDefaults non-atomically.
  - A3-009 ExternalVPNStopMarker disk I/O on every disconnect (energy).
  - A3-010 runIsSupportedUpgrade ignores `Task.isCancelled`.
  - A3-011 `.error` state preserved across `.connecting` (UX divergence).
  - A3-012 handleDeepLink re-enters importInProgress without check.
  - A3-013 runIsSupportedUpgrade priority should be `.utility` not `.background`.
  - A3-014 showFailoverBanner auto-dismiss not cancelled → A3'-009 (still present).

---

## 5 — Pre-TestFlight Priority Summary

**Block TestFlight (must fix before submission):** None. All closures are PASS; no new CRITICAL.

**Fix before TestFlight if time permits (HIGH):**
- A3'-001 — Narrow `ProvisionSerializer.run` critical section to SwiftData fetch only.
- A3'-002 — Replace `rethrows` with `throws` in `ProvisionSerializer.run` (1-line fix).

**Backlog for v1.1 (MEDIUM/LOW):**
- A3'-003 (assertion in wireRulesCoordinator).
- A3'-005 (dedupe key edge case under repeated nil connectedDate).
- A3'-006 (disconnect cached-manager reuse).
- A3'-007 (pinSHA256 shape validation in reparse).
- A3'-008 (`@unchecked Sendable` non-`provisionTunnelProfile` paths).
- A3'-009 (cancel-and-replace failoverDismissTask).
- A3'-010 (log warning on future-dated since).
- A3'-011 (Auto-mode tunnelRemoteAddress display anchor).
- A3'-004 (clock-rewind drift — out of scope, tracking only).

**Conclusion:** Plan 02 / Plan 03 fixes are SAFE for TestFlight. T-B5 introduces a HIGH latency regression for the rare failover-during-Connect overlap (A3'-001) which should be narrowed before broad rollout, but does not block Internal Testing. T-A4/T-B4/T-B6/T-B8/T-B2/T-B1 are all clean closures with no detected regressions.
