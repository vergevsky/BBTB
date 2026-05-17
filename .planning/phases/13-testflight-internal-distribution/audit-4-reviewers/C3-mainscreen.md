# C3 — MainScreenFeature (Codex 5.5)
**Baseline:** ccbce8a
**Total findings:** 3 (0/3/0/0)

## Plan 07 closure verification
- T-C-R1' intervening-terminal gate: PASS
- T-C-R2' provision split: FAIL
- T-C-C2H1' disconnect resilience: PASS
- T-C-C2H2' single-flight: FAIL
- T-C-C3H1' NEVPN observer coalescing: FAIL
- T-C-C3H2' import reentrancy guards: PASS
- T-C-B2 failoverDismissTask: PASS

## Critical
No critical findings in this MainScreenFeature pass.

## High

### C3-4-001: NEVPN pre-hop coalescer uses unsynchronized nonisolated state from notification callbacks
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:160`
- **Dimension:** Thread Safety / Energy
- **Description:** The Plan 07 coalescer stores `nevpnObserverLastStatus` and `nevpnObserverLastConnectedDate` as `nonisolated(unsafe)` fields (`MainScreenViewModel.swift:160-167`) and reads/writes them directly in the `NEVPNStatusDidChange` observer before hopping to MainActor (`MainScreenViewModel.swift:291-296`). The code comment assumes NotificationCenter serializes callbacks for the same notification name (`MainScreenViewModel.swift:282-290`), but the implementation uses `queue: nil`, so the callback executes synchronously on whatever thread posts the notification (`MainScreenViewModel.swift:262-266`). There is no lock, actor, queue, or atomic around the compare-and-store sequence.
- **Why HIGH:** If two NE status postings arrive from different threads, these `nonisolated(unsafe)` reads/writes are a real Swift data race. At best the dedupe can miss and reintroduce the MainActor task flood Plan 07 intended to close; at worst it is undefined behavior on an `@MainActor` object being touched off-actor. The energy fix is therefore not race-free.
- **Fix:** Put the pre-hop snapshot behind a small lock (`OSAllocatedUnfairLock` or serial `DispatchQueue`) or route observer samples through a dedicated actor/coalescer. Keep the lock scope to the `(status, connectedDate)` compare-and-update, then spawn the MainActor task outside the lock.

### C3-4-002: Moving XPC save outside `ProvisionSerializer` lets older provisions overwrite newer ones
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:584`
- **Dimension:** Thread Safety / Logic
- **Description:** `provisionTunnelProfile(for:)` now serializes only `_legacyProvisionExceptXPC` and then performs `tunnelProvisioner.provisionTunnelProfile(configJSON:serverHost:)` outside the serializer (`ConfigImporter.swift:584-592`). That permits this interleaving: call A builds JSON for server A inside the mutex, exits to a slow XPC save; call B then builds JSON for server B, exits, and its XPC save completes first; A's older XPC save completes last and overwrites the active NETunnel profile with server A. This can happen between user connect provisioning (`MainScreenViewModel.swift:947-952`) and failover provisioning (`FailoverProvider.swift:160-163`).
- **Why HIGH:** The split reduces mutex hold time, but it loses the previous end-to-end ordering guarantee. A failover can report/connect against one selected server while the final persisted provider configuration points back to an older server, causing wrong-server reconnects or stale profile state after the next on-demand start.
- **Fix:** Keep XPC outside the heavy SwiftData/Keychain/PoolBuilder section, but add an ordered commit gate for the XPC stage. For example, issue a monotonically increasing provision generation under the serializer and let only the latest generation save, or serialize just the final XPC save/load stage with a separate short `AsyncMutex` so completion order matches request order.

### C3-4-003: Single-flight tasks ignore caller cancellation and do not arbitrate connect vs disconnect
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:391`
- **Dimension:** Logic / Thread Safety / Energy
- **Description:** `connect()` and `disconnect()` store separate unstructured tasks (`TunnelController.swift:391-397`, `TunnelController.swift:559-565`). This dedupes same-method callers, but cancellation of the caller awaiting `task.value` does not cancel the inner `_doConnect()` / `_doDisconnect()` task, and the two slots do not coordinate with each other. A disconnect can start while an in-flight connect task is suspended in provision/save/start work, set intent false, stop/reset state, then the older connect task can resume and call `startVPNTunnel` (`TunnelController.swift:417-483`). The reverse ordering can also make an older disconnect stop a newer connect.
- **Why HIGH:** Plan 07 closes duplicate `connect()` and duplicate `disconnect()` reentrancy, but not opposite-command reentrancy or cancellation propagation. This is a user-visible command ordering bug: the last user intent is not guaranteed to win, and a cancelled UI task can still carry on doing NEPreferences XPC work and tunnel start/stop operations.
- **Fix:** Model connect/disconnect as one command lane, not two independent single-flight slots. Store a single in-flight command with generation/intent, cancel or supersede the previous opposite command when a new command arrives, and check cancellation/generation before irreversible side effects such as `saveToPreferences()` and `startVPNTunnel()`. If shared-task cancellation is intentionally ignored, document that policy and still enforce last-intent-wins between connect and disconnect.

## Medium
No medium findings in this MainScreenFeature pass.

## Low
No low findings in this MainScreenFeature pass.

## Notes
- The intervening-terminal gate covers all current `NEVPNStatus` enum cases: `.connected` resets the flag (`MainScreenViewModel.swift:638-685`), `.disconnected`, `.invalid`, and `.disconnecting` set it (`MainScreenViewModel.swift:695-704`), and `.connecting` / `.reasserting` leave it unchanged (`MainScreenViewModel.swift:611-637`). The 24h fallback also avoids the Plan 06 long-background 60s regression (`MainScreenViewModel.swift:563-582`).
- Disconnect resilience is structurally closed: `applyCurrentStateToCachedManager()` retries once and returns `false` after final failure (`TunnelController.swift:340-371`), and `_doDisconnect()` marks `ExternalVPNStopMarker` before stopping if persistence failed (`TunnelController.swift:586-592`).
- Import/deep-link admission is structurally closed for MainActor entry points: `performImport` guards and sets `importInProgress` before the first await (`MainScreenViewModel.swift:888-903`), and `handleDeepLink` uses the same pattern (`MainScreenViewModel.swift:1271-1282`).
- `failoverDismissTask` now cancel-and-replaces on re-arm (`MainScreenViewModel.swift:771-784`), closing the stale dismiss task banner race from AUDIT-3.
