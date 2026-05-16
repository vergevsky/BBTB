# C3 — AppFeatures/MainScreenFeature audit (Codex 5.5)

**Scope:** BBTB/Packages/AppFeatures/Sources/MainScreenFeature/
**Files audited:** 29
**Total findings:** 5 (CRITICAL: 0, HIGH: 3, MEDIUM: 1, LOW: 1)

## Findings

### [HIGH] C3-001: Foreground re-entry no longer runs VM VPN-status resync
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:680`
- **Dimension:** bugs | logic
- **Description:** `handleForegroundReentry()` calls `await tunnel.handleForeground()`, but production `TunnelController.handleForeground()` is an explicit no-op. The real VM foreground resync is `MainScreenViewModel.handleForeground()` at line 620, but the consolidated hook does not call it.
- **Why it matters:** This regresses the Phase 6c defense-in-depth path for Settings/VPN round trips. If `NEVPNStatusDidChange` is dropped while backgrounded or app was not alive, UI can stay `.connected(since:)` after the system tunnel is already off.
- **Suggested fix:** In `handleForegroundReentry()`, call `await handleForeground()` directly as the authoritative UI resync path. Keep `tunnel.handleForeground()` only for non-UI tunnel-controller hooks if it becomes non-noop.

### [HIGH] C3-002: `disconnect()` can stop the wrong VPN manager
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:479`
- **Dimension:** bugs | security
- **Description:** `disconnect()` does `NETunnelProviderManager.loadAllFromPreferences()` and then uses `managers.first` without `ManagerSelector.ourManagers(...)`.
- **Why it matters:** In mixed-manager installs, this can call `stopVPNTunnel()` on another app's manager while also clearing BBTB user intent. That violates the package-wide multi-manager safety contract used elsewhere.
- **Suggested fix:** Use `ManagerSelector.ourManagers(from: managers).first`, or prefer the already-filtered `cachedManager` after refreshing it.

### [HIGH] C3-003: TUIC imports are saved but cannot be provisioned later
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:679`
- **Dimension:** bugs
- **Description:** `buildServerConfig` and `buildKeychainPayload` handle `.tuic`, but both `reparseFromKeychainScalar(...)` and `reparseFromKeychain(...)` omit the `"tuic"` protocol case and fall through to `nil`.
- **Why it matters:** A TUIC URI can import as supported, but explicit connect fails with config-build error, and auto-mode silently drops TUIC rows. A TUIC-only user sees "no supported servers" despite having a supported server.
- **Suggested fix:** Add TUIC reconstruction in both reparse helpers using the persisted keys at lines 937-945, and add explicit + auto-mode round-trip tests.

### [MEDIUM] C3-004: Disconnect has no synchronous in-flight state guard
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:749`
- **Dimension:** logic | performance
- **Description:** The `.connected` branch starts `tunnel.disconnect()` but does not synchronously move UI state to a `.disconnecting`/guarded state. `ConnectionState` also has no `.disconnecting` case, and `applyVPNStatus(.disconnecting)` maps to `.idle`.
- **Why it matters:** A rapid double tap can enqueue multiple disconnect command tasks before an NE status event updates UI. Because `TunnelController` is actor-reentrant across awaits, this can duplicate save/load/loadAll work and widen race windows around `manualDisconnectInProgress`.
- **Suggested fix:** Add a VM-level `disconnectInProgress` guard or introduce `.disconnecting` in `ConnectionState`, set it before awaiting, and ignore additional toggles until terminal `.disconnected/.invalid`.

### [LOW] C3-005: ViewModel notification observers are not removed
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:110`
- **Dimension:** maintainability | performance
- **Description:** The comment says `rulesUpdateObserver` is removed in `deinit`, and the VM also stores `killSwitchObserver` and `nevpnStatusObserver`, but this class has no `deinit`.
- **Why it matters:** If the VM is recreated in previews, tests, or future app flows, NotificationCenter keeps stale block observers. The closures capture `self` weakly, so this is not a retain cycle, but it is still accumulated observer overhead.
- **Suggested fix:** Add `deinit` removing `rulesUpdateObserver`, `killSwitchObserver`, and `nevpnStatusObserver`.

## Notes

- Read-only audit only. I did not modify code and did not run build/tests.
- `NEVPNStatusDidChange` hot-path wiring itself looks correct in both VM and `TunnelController`: `queue: nil`, status read from `notification.object`, no `loadAllFromPreferences()` inside the handler.
- No `*Coordinator.swift` file exists inside `MainScreenFeature`; coordinator-related code in this package is in `MainScreenViewModel` and the `ServerSelectionCoordinating` extension.
