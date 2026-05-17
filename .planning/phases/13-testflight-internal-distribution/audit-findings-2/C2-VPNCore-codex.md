# C2' — VPNCore re-audit (Codex 5.5)

**Baseline:** commit 55523dd

## Closure Verification

| Plan 02 Finding | Status | Verification |
|---|---|---|
| C2-001 save delete used add dictionary | ✅ Closed | `KeychainStore.swift:54` now builds `lookupQuery` without `kSecValueData`/`kSecAttrAccessible`, derives `addQuery` at lines 71-73. |
| C2-002 missing non-sync pin | ✅ Closed with caveat | All four queries pin `kSecAttrSynchronizable = kCFBooleanFalse`. Caveat: stops matching pre-existing synchronizable items (see C2'-003). |
| C2-003 force-cast в `accessibleFlag` | ✅ Closed | `KeychainStore.swift:135` uses `as? String` и bridges back to `CFString`. |
| A2-001 missing AppIdentifierPrefix fallback | Partially closed | `KeychainStore.swift:153` теперь logs diagnostic via `Logger`. Still falls back to private access group by design. |
| A2-004 accessible attribute crash | ✅ Closed | Same fix as C2-003. |

## New Findings

### [MEDIUM] C2'-001: VPN secrets use `kSecAttrAccessibleWhenUnlocked`
- **Location:** `KeychainStore.swift:72`
- **Description:** VPN secrets saved с `kSecAttrAccessibleWhenUnlocked`. Packet Tunnel extension may be asked to start/restart while device locked (on-demand reconnect, network change). Extension can't read shared Keychain in that state → startTunnel fails.
- **Suggested fix:** Use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for extension-readable VPN credentials; keep `kSecAttrSynchronizable=false`.

### [LOW] C2'-002: Pre-delete failure logged but proceeds к SecItemAdd
- **Location:** `KeychainStore.swift:64`
- **Description:** `save(secret:tag:)` logs non-`errSecItemNotFound` delete failures but still proceeds to `SecItemAdd`. Permission/query failures during overwrite are reported later as `saveFailed` (commonly `errSecDuplicateItem`), hiding real pre-delete failure.
- **Suggested fix:** Throw `KeychainError.deleteFailed(deleteStatus)` for non-success/non-not-found, OR use `SecItemUpdate` for existing items and only `SecItemAdd` on not found.

## Regressions Detected

### [MEDIUM] C2'-003: False-pinned lookup no longer matches pre-existing synchronizable items
- **Location:** `KeychainStore.swift:58`
- **Description:** New false-pinned lookup/load/delete paths не match items stored с `kSecAttrSynchronizable=true`. Clean installs OK; dev/TestFlight builds may have written synchronizable secret → `load`/`delete` treat as missing, `save` doesn't clean up. Leaves synced VPN credential behind.
- **Suggested fix:** One-time cleanup path using `kSecAttrSynchronizableAny` before adding the false-pinned replacement.

No regression found from `import os`; with iOS 18/macOS 15 platforms, `Logger` is appropriate.

## Verdict

T-B3 closes Plan 02 KeychainStore findings in the normal path. Don't block TestFlight on clean-install behavior, but fix C2'-001 before wider beta (locked-device tunnel restart failures hard to explain). C2'-003 important cleanup gap if any prior builds wrote synchronizable Keychain items.
