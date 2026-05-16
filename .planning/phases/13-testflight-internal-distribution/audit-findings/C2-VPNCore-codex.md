# C2 — VPNCore audit (Codex 5.5)

**Scope:** BBTB/Packages/VPNCore/Sources/VPNCore/
**Files audited:** 13
**Total findings:** 3 (CRITICAL: 0, HIGH: 1, MEDIUM: 1, LOW: 1)

## Findings

### [HIGH] C2-001: Keychain overwrite path can fail because delete uses the add dictionary
- **Location:** `BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift:47`
- **Dimension:** bugs | security
- **Description:** `save(secret:tag:)` builds a dictionary containing add-only fields such as `kSecValueData` and then passes that same dictionary to `SecItemDelete` before `SecItemAdd`.
- **Why it matters:** `SecItemDelete` should use a lookup query, not the add payload. If the delete is rejected or fails to match an existing item, the following `SecItemAdd` can fail with duplicate-item on key rotation / re-import / updating a live server's secret. The delete status is also ignored, so this failure mode is hidden until add.
- **Suggested fix:** Split `baseQuery` (`class`, `service`, `account`, `accessGroup`, sync flag) from `addQuery`; call `SecItemUpdate` for existing items or check `SecItemDelete` status before `SecItemAdd`.

### [MEDIUM] C2-002: VPN secrets are not explicitly marked non-synchronizable
- **Location:** `BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift:38`
- **Dimension:** security
- **Description:** Keychain add/load/delete queries do not set `kSecAttrSynchronizable` to `kCFBooleanFalse`.
- **Why it matters:** VPN credentials should be device-local and not eligible for iCloud Keychain sync. The platform default is usually non-synchronizable, but this is a security-sensitive credential path shared with the extension; relying on omission makes the invariant implicit and easy to regress.
- **Suggested fix:** Add `kSecAttrSynchronizable as String: kCFBooleanFalse` to the base query used by save/load/delete/attribute checks, and cover it with a static or unit-level assertion.

### [LOW] C2-003: Public Keychain inspection helper can crash on unexpected attribute type
- **Location:** `BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift:102`
- **Dimension:** bugs
- **Description:** `accessibleFlag(tag:)` force-casts `dict[kSecAttrAccessible]` with `as! CFString?`.
- **Why it matters:** This is a public API in `VPNCore`; if Security returns a different bridged type or malformed attributes, the app/test process crashes instead of returning `nil` or throwing `loadFailed`.
- **Suggested fix:** Replace with a conditional cast, e.g. `return dict[kSecAttrAccessible as String] as? CFString`, or throw a typed error for malformed attributes.

## Notes

- No `TunnelController`, `NEVPNStatus` state machine, on-demand builder, or kill switch implementation exists under `BBTB/Packages/VPNCore/Sources/VPNCore/` in the current tree; those are in other packages/paths.
- Confirmed no `#Predicate` over `UUID?` in this scoped package. Existing predicates are over `subscriptionURL != nil` and `Subscription.url == String`.
- No code changes, builds, or tests were run.
