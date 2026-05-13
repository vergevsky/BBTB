# Phase 6c Architect R5: UAT Regressions After Round 4.1

**Date:** 2026-05-13
**Mode:** Advisory
**Scope:** iOS 26.5 runtime behavior during Phase 6c on-demand reconnect migration.

## Bottom Line

The current regressions are strong evidence that we are patching the wrong layer. The on-demand model is still viable, but the parallel-run compromise has become the bug source: `TunnelController` still contains the old recovery state machine, reachability-triggered reconnects, imperative UI transitions, and XPC-bearing manager mutation inside status handling.

Primary recommendation: execute Plan 04 Task 3 cleanup now, before further UAT, and make the Phase 6c model internally consistent: Apple on-demand owns reconnect, `TunnelWatchdog` owns only stable-session failover, and app UI derives from `NEVPNStatus + local intent` rather than from old reconnect-loop events.

## Key Code Findings

### 1. Bug A is consistent with old machinery winning the UI

Observed UI:

- Banner: `Переподключение... (попытка 1 из 3)`
- Button area: `Подключение`
- Real tunnel: connected

The banner is not produced by Apple's on-demand path. It is produced by `ReconnectStateMachineState.retrying`:

- `ReconnectStateMachine.driveLoop` sets `.retrying(attempt: attemptIdx + 1, delaySeconds: delay)` before sleeping and before calling `connect()` (`ReconnectStateMachine.swift:126-143`).
- `MainScreenViewModel.applyReconnectStateMachineState` maps `.retrying` directly to `reconnectBannerState = .retrying(...)` (`MainScreenViewModel.swift:318-327`).
- `applyVPNStatusToBanner(.connected)` only clears `.connecting`, not `.retrying`, `.failover`, or `.allFailed` (`MainScreenViewModel.swift:286-291`).

So once old recovery publishes `.retrying`, the new NE status observer intentionally does not clear it. This was acceptable only if the old recovery path were not firing during successful connects. UAT shows it is firing.

The stuck main button state also follows from imperative ownership:

- `performToggleImpl` sets `state = .connecting`, awaits provision, then awaits `tunnel.connect()`, and only then sets `state = .connected(since:)` (`MainScreenViewModel.swift:373-390`).
- If the OS tunnel reaches `.connected` outside that awaited success path, the VM does not promote `.connecting` to `.connected`. The Round 4 UI fix only demotes `.connected` to `.idle` on disconnect (`MainScreenViewModel.swift:298-310`); it does not promote connection state reactively.

### 2. Bug B is most likely BBTB self-reenablement, not Apple's on-demand ignoring `isEnabled`

Current Round 4 path:

- On `.disconnected`, if not in connect/disconnect, `handleStatusChange` does `await refreshCachedManager()` (`TunnelController.swift:718-719`).
- If refreshed manager is `!isEnabled && isOnDemandEnabled`, it sets `manager.isOnDemandEnabled = false` and saves (`TunnelController.swift:720-727`).
- It then still routes `.disconnected` into old recovery: `await triggerRecoveryIfNeeded(reason: "status-disconnected")` (`TunnelController.swift:761-767`).
- Reachability events also call `triggerRecoveryIfNeeded` (`TunnelController.swift:667-678`).
- Old recovery calls `stateMachine.run`, whose first attempt is `self.connect()` (`TunnelController.swift:798-864`).
- `connect()` explicitly sets `manager.isEnabled = true`, saves, reloads, and starts the tunnel (`TunnelController.swift:400-408`).

There is a reentrancy window at `await refreshCachedManager()`: before the actor resumes, reachability or another status task can enter `triggerRecoveryIfNeeded` while `userIntendedConnected == true` and cached `isEnabled` may still be true. That old path can schedule a retry and later call `connect()`, which re-enables the profile from inside BBTB. This explains Settings disable -> UI shows disconnected -> tunnel comes back.

The Round 4 patch also only mutates manager state. It does not clear BBTB's persisted `userIntendedConnected`, so any remaining recovery path still considers reconnect legitimate after an external disable.

### 3. `isOnDemandEnabled` should not be treated as durable "always reconnect forever"

`OnDemandRulesBuilder.applyCurrentState` already encodes the correct direction: final `isOnDemandEnabled = autoReconnectToggle && userIntendedConnected` (`OnDemandRulesBuilder.swift:108-115`). The problem is that external disable events do not clear the intent. In the current app, user intent remains true after Settings disables the VPN or another VPN takes over.

For this product, "auto reconnect" should be a sliding session window:

- Opened by explicit BBTB Connect.
- Closed by explicit BBTB Disconnect.
- Closed by external disable or external takeover.
- Reopened only by explicit BBTB Connect.

That preserves the Phase 6c phantom-connect fix and prevents fighting system/user actions.

### 4. Apple/reference-app semantics

Apple's NetworkExtension contract requires VPN configurations to be enabled before use. `isOnDemandEnabled` enables evaluation of on-demand rules, but it is not a substitute for `isEnabled`.

Reference behavior aligns with that:

- WireGuard stores on-demand configuration on the tunnel and uses NE status as the source for tunnel state. Its on-demand display/state logic treats on-demand as enabled only when the tunnel is enabled and `isOnDemandEnabled` is true.
- WireGuard does not run a second reconnect loop beside Apple's on-demand evaluator.
- sing-box-for-apple similarly configures `NETunnelProviderManager` and drives app state around manager/connection status instead of keeping a separate retry-loop UI state competing with NE status. The lesson is architectural, not code reuse: do not keep a custom reconnect machine parallel to on-demand.

Given those semantics, a disabled manager should not be expected to evaluate on-demand rules. If the tunnel comes back after iOS Settings disables BBTB, assume BBTB code called `connect()` or otherwise re-enabled the manager until device logs prove otherwise.

## Primary Recommendation

Execute Plan 04 Task 3 cleanup now. Do not add another guard around Round 4. Delete or fully disconnect the old reconnect/reachability path before the next UAT pass.

This is not an architectural pivot away from on-demand. It is completing the originally locked Phase 6c architecture earlier because the temporary parallel-run is now invalidating UAT.

## Action Plan

1. Remove old reconnect authority from iOS `TunnelController`.
   - Stop constructing `ReconnectStateMachine`.
   - Remove `ReconnectStateObserverRelay` app wiring.
   - Remove `triggerRecoveryIfNeeded` from `.disconnected`, reachability, and wake/reachability paths for iOS.
   - Leave `TunnelWatchdog` wired only for D-08/D-09 stable-session failover.

2. Make external disable/takeover an intent-closing event.
   - On externally observed `.disconnected` plus refreshed manager `isEnabled == false`, set persisted `userIntendedConnected = false`, notify watchdog `setUserIntent(false)`, apply/save on-demand state false.
   - Treat Settings disable and other-VPN takeover the same for reconnect behavior: stay off until explicit BBTB Connect.

3. Keep manager mutation out of the hot status path where possible.
   - The status observer should read `notification.object.status`, update lightweight state, and enqueue one debounced/single-flight reconciliation for external disable.
   - The reconciliation should re-check gates after each `await`.

4. Move main UI state to reactive NE status derivation.
   - `connect()` and `disconnect()` remain command methods.
   - `NEVPNStatusDidChange` becomes the authority for visual state: `.connected -> .connected(since:)`, `.connecting/.reasserting -> .connecting`, `.disconnected/.invalid -> .idle` unless an explicit command error is being shown.
   - Preserve command errors as separate error state, not as proof of tunnel status.

5. Simplify banner semantics.
   - Remove `.retrying` / `.allFailed` from live Phase 6c reconnect UI, or stop feeding them from any runtime path.
   - Use `.connecting` for Apple's reconnect in progress and `.failover` only when `TunnelWatchdog` intentionally swaps server.

6. Re-run the same UAT matrix after cleanup.
   - F-reverse and Settings-disable become the critical validation pair.
   - Wi-Fi/LTE handoff verifies on-demand remains active during the explicit-connect session window.
   - G verifies the old XPC storm path is gone.

## Effort Estimate

**Medium (1-2 days).**

The code deletion is conceptually straightforward, but this touches app wiring, actor state, UI status derivation, and persisted intent semantics. It deserves a careful pass rather than another local guard.

## Risks And Mitigations

- **Risk: Losing mid-session server failover behavior.**
  Mitigation: Keep `TunnelWatchdog` as the only custom recovery component. It already has the right D-08 gates and no XPC in the hot path.

- **Risk: UI briefly shows idle during startup before first NE status notification.**
  Mitigation: Seed from one manager/status read during setup or initial VM refresh, then let notifications own subsequent transitions.

- **Risk: External disable detection still has a race around manager refresh.**
  Mitigation: Make reconciliation single-flight and post-await gated. More importantly, once old recovery is gone, a missed first reconciliation cannot call `connect()` behind the user's back.

- **Risk: Changing intent on other-VPN takeover might surprise users who expected BBTB to resume when the other VPN disconnects.**
  Mitigation: This is the correct anti-fight behavior for Phase 6c. Future advanced settings can distinguish "resume after other VPN" only if the UX explicitly asks for it.

- **Risk: D-15 proposed deleting `userIntendedConnected`, but D-08/watchdog and phantom-connect protection still need a session-intent bit.**
  Mitigation: Keep the persisted intent, but redefine it as the active-session window, not as an unconditional preference.

## Specific Answers

### Should we delete OLD machinery now?

Yes. The parallel-run is now the active source of the regressions. D-10 and D-14 already say `ReconnectStateMachine` and old reachability recovery should be removed. UAT should validate the intended architecture, not the transitional hybrid.

### Should UI state be reactive from NEVPNStatus + intent?

Yes. Commands should request transitions; NE status should confirm them. The current imperative `state = .connecting` then awaited `connect()` success path cannot represent OS-driven success, Settings disable, other-VPN takeover, or on-demand reconnect consistently.

### Should `isOnDemandEnabled` ever be true while the user is not in a tunnel-up state?

It may be true while a user-requested session is connecting, reasserting, or temporarily disconnected due to network churn. It should not remain true after explicit BBTB disconnect, Settings disable, or another VPN takeover. Treat it as a sliding session window opened by BBTB Connect and closed by any user/system action that intentionally removes BBTB from the active VPN role.

### Settings disable vs other-VPN takeover detection

For Phase 6c reconnect behavior, do not distinguish them. Both surface as our manager no longer enabled/active, and both should close BBTB intent and keep BBTB off until explicit Connect. If UX later needs different messaging, add a best-effort display hint, but keep the reconnect policy identical.

## References

- Local: `TunnelController.swift:685-767`, `TunnelController.swift:798-864`, `MainScreenViewModel.swift:266-314`, `MainScreenViewModel.swift:373-390`, `OnDemandRulesBuilder.swift:108-115`, `TunnelWatchdog.swift:89-145`.
- Apple docs: [`NEVPNManager.isEnabled`](https://developer.apple.com/documentation/networkextension/nevpnmanager/isenabled?changes=la), [`NEVPNManager.onDemandRules`](https://developer.apple.com/documentation/networkextension/nevpnmanager/ondemandrules), [`NEOnDemandRuleConnect`](https://developer.apple.com/documentation/networkextension/neondemandruleconnect).
- Reference apps: WireGuard Apple [`TunnelsManager.swift`](https://git.zx2c4.com/wireguard-apple/tree/Sources/WireGuardApp/Tunnel/TunnelsManager.swift?id=3d8de22b967dc95f655c2664438c8e9a4cd429fc), WireGuard commit [`cfd1b168`](https://git.zx2c4.com/wireguard-apple/commit/?id=cfd1b16801cfbd7ece9044b536db831d58a0577b). Public search did not surface an equally direct sing-box-for-apple source hit for these exact symbols; the architectural conclusion does not depend on sing-box app-layer code.
