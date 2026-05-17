# C2 — VPNCore (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 5 (0/2/3/0)

## Scope Note
Strict `BBTB/Packages/VPNCore/Sources/VPNCore/` contains `KeychainStore` and data/probe models only. The task also required `TunnelController`, `NEVPNStatus`, `OnDemandRulesBuilder`, and KillSwitch review, so this pass audited the requested adjacent files in `AppFeatures/MainScreenFeature` and `KillSwitch` as supporting VPNCore control-plane code.

## Critical
No critical findings found in this VPNCore pass.

## High
### C2'-3-001: Explicit disconnect can continue after failing to persist `isOnDemandEnabled=false`
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:312`
- **Dimension:** Logic / OnDemandRulesBuilder.applyCurrentState
- **Description:** `disconnect()` clears user intent, then calls `applyCurrentStateToCachedManager()` to persist the new on-demand state before stopping the tunnel (`TunnelController.swift:473`, `TunnelController.swift:477`, `TunnelController.swift:491`). However, `applyCurrentStateToCachedManager()` catches `saveToPreferences()` / `loadFromPreferences()` errors and only logs them (`TunnelController.swift:312`, `TunnelController.swift:315`), so `disconnect()` proceeds even when NetworkExtension preferences still have the previous `manager.isOnDemandEnabled=true`. `OnDemandRulesBuilder.applyCurrentState` correctly computes `toggle && intent` (`OnDemandRulesBuilder.swift:111`), but the computed false value is only in memory if the save fails.
- **Why HIGH:** A user-visible Disconnect can stop the current tunnel while leaving persisted Connect On Demand enabled. The extension-side marker only blocks Settings/user-disabled auto-restarts (`BaseSingBoxTunnel.swift:157`, `BaseSingBoxTunnel.swift:161`); manual app disconnect does not mark that path. On a transient NE preferences failure, iOS can therefore restart the profile after an explicit disconnect.
- **Suggested fix:** Make `applyCurrentStateToCachedManager()` throw or return success/failure. `disconnect()` should not call `stopVPNTunnel()` until the on-demand disable save+reload has succeeded, or it should set an equivalent explicit-disconnect marker that blocks OS-driven on-demand starts until a later manual Connect. Add a test seam that simulates save failure and asserts no stop/restart-prone state is reached.

### C2'-3-002: `TunnelController` command methods are actor-reentrant and can interleave session intent mutations
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:321`
- **Dimension:** Thread Safety / actor isolation
- **Description:** `TunnelController` is an actor, but public `connect()` and `disconnect()` both mutate shared session flags and then suspend on async work. `connect()` sets `userIntendedConnected=true` and `connectInProgress=true` (`TunnelController.swift:340`, `TunnelController.swift:343`), then suspends on watchdog and NE preference calls before `startVPNTunnel` (`TunnelController.swift:341`, `TunnelController.swift:389`, `TunnelController.swift:398`). `disconnect()` can enter while the first call is suspended, set intent false and `manualDisconnectInProgress=true` (`TunnelController.swift:473`, `TunnelController.swift:475`), then save/stop the manager. The existing flags are gates for status handling, not a command serializer.
- **Why HIGH:** This can invert the last user command under rapid UI/programmatic operations or foreground/status races: for example, a disconnect that enters during a connect can clear intent and watchdog state, then the original connect resumes and starts a manual VPN session using stale assumptions. The result is a connected tunnel with `userIntendedConnected=false`, on-demand disabled, and watchdog user intent false, or the reverse ordering where Disconnect appears to succeed but Connect starts afterward.
- **Suggested fix:** Serialize lifecycle commands with a private command task chain / async mutex / generation token. At minimum, reject or await `connect()` while `manualDisconnectInProgress` is true and reject or queue `disconnect()` while `connectInProgress` is true. Keep the serialization around the whole command, not only around individual flag writes.

## Medium
### C2'-3-003: `KeychainStore.delete` does not sweep legacy synchronizable items
- **Location:** `BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift:119`
- **Dimension:** Security / Keychain cleanup
- **Description:** Plan 05 added a `kSecAttrSynchronizableAny` cleanup sweep before `save()` (`KeychainStore.swift:75`, `KeychainStore.swift:77`), which closes the re-save path. `delete(tag:)` still deletes only the false-pinned item (`KeychainStore.swift:120`, `KeychainStore.swift:124`, `KeychainStore.swift:128`). If a user deletes a server/subscription that was created by an older synchronizable build before it is ever re-saved by the fixed build, the legacy synced secret remains in Keychain/iCloud.
- **Why MEDIUM:** This is not the closed C2'-003 save-path cleanup gap; it is the delete/cascade-delete path. It leaves stale VPN credentials behind after the user believes the server was removed.
- **Suggested fix:** Mirror the save-path sweep in `delete(tag:)`: first delete with `kSecAttrSynchronizableAny`, then delete the false-pinned lookup, treating `errSecItemNotFound` as success. Add a regression test or static assertion for delete including `kSecAttrSynchronizableAny`.

### C2'-3-004: Keychain overwrite still hides pre-delete failures behind later add failures
- **Location:** `BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift:80`
- **Dimension:** Security / correctness
- **Description:** `save(secret:tag:)` logs non-success/non-not-found delete failures but proceeds to `SecItemAdd` (`KeychainStore.swift:80`, `KeychainStore.swift:82`, `KeychainStore.swift:91`). If delete failed due access-group, entitlement, interaction, or query mismatch, the eventual thrown error is commonly `saveFailed(errSecDuplicateItem)` from the add, not the real delete failure.
- **Why MEDIUM:** The Plan 02 add-dictionary misuse is closed, but this residual behavior makes credential rotation/import failures harder to diagnose and can leave the old secret active while reporting only a generic save failure.
- **Suggested fix:** Treat unexpected delete failures as fatal (`KeychainError.deleteFailed`) or switch to `SecItemUpdate` for existing rows and `SecItemAdd` only on `errSecItemNotFound`.

### C2'-3-005: Keychain accessibility regression test still asserts the pre-Plan-05 value
- **Location:** `BBTB/Packages/VPNCore/Tests/VPNCoreTests/KeychainStoreTests.swift:39`
- **Dimension:** Security verification
- **Description:** Runtime code now writes `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`KeychainStore.swift:89`), matching Plan 05 T-C1'. The test still says `test_sec05_accessibleFlag_isWhenUnlocked` and asserts `kSecAttrAccessibleWhenUnlocked` (`KeychainStoreTests.swift:29`, `KeychainStoreTests.swift:39`).
- **Why MEDIUM:** The source fix is present, but the regression test encodes the closed vulnerable policy. On environments where `accessibleFlag` is returned instead of skipped, the test fails; on environments where it skips, it does not protect the new AfterFirstUnlockThisDeviceOnly invariant.
- **Suggested fix:** Rename the test and assert `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Keep the existing skip for CLI Keychain environments that do not expose the attribute.

## Notes
- I read `AUDIT-2.md` first and did not re-report the closed T-C1' `AfterFirstUnlockThisDeviceOnly` save-path fix or the T-C2' save-path synchronizable cleanup sweep.
- `KillSwitch.apply(to:enabled:)` still sets `includeAllNetworks=true`, `enforceRoutes` by platform policy, `excludeLocalNetworks=false`, and `disconnectOnSleep=false`; no new KillSwitch critical issue was found in this pass.
