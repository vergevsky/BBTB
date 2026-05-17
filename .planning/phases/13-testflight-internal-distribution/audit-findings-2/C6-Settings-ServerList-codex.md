# C6' — SettingsFeature + ServerListFeature re-audit (Codex 5.5)

**Baseline:** commit 55523dd

## Closure Verification

| Plan 02 ID | Fix | Status | Evidence |
|---|---|---|---|
| C6-001 IPv6 masking / T-A5 | `f1d0a15` | **🛑 FAIL** | `prepareLog` calls `maskIPv6(maskIPv4(tail))` at `DiagnosticsExporter.swift:71`, full 8-group IPv6 masks. But compressed IPv6 regex at `DiagnosticsExporter.swift:148` misses common forms `fe80::1`, `fe80::1%en0`, `2001:db8::8a2e:7334`, IPv4-mapped `::ffff:192.0.2.128` after IPv4 masking. |
| A6-001/A6-002 killSwitch defaults / T-B6 | `bdba28d` | ✅ PASS | `SettingsViewModel.swift:36` has `@AppStorage(...killSwitchEnabled) = true`; `:602` reads `?? true`. |

## New Findings

### [HIGH] C6'-001: `maskIPv6` misses most compressed IPv6 addresses
- **Location:** `DiagnosticsExporter.swift:148`
- **Description:** The prefix side of the compressed regex uses `(?:[0-9a-fA-F]{1,4}:){0,7}::` — prefix group consumes colon immediately before `::`. Addresses such as `fe80::1` и `2001:db8::8a2e:7334` do not match. IPv4-mapped forms also remain partially exposed after `maskIPv4`, e.g. `::ffff:192.0.2.128 -> ::ffff:192.0.2.xxx`.
- **Why it matters:** Original privacy closure incomplete для dominant IPv6 notation used in logs, including link-local zone-id cases.
- **Suggested fix:** Prefer numeric IP parsing/normalization; otherwise replace P2 c tested compressed-IPv6 pattern that handles prefix groups, suffix groups, zone IDs, dotted-quad mapped IPv6. Add explicit tests for `::1`, `fe80::1`, `fe80::1%en0`, `2001:db8::8a2e:7334`, `::ffff:192.0.2.128`, и timestamp non-matches.

### [MEDIUM] C6'-002: 100 ms debounce в `loadFromStore()` skips mandatory post-mutation UI reloads
- **Location:** `ServerListViewModel.swift:395`
- **Description:** `deleteServer`, `confirmDeleteSubscription`, `pullToRefresh`, `silentForegroundRefresh` rely на `await loadFromStore()` after SwiftData mutation. If previous lifecycle load happened within 100 ms, reload returns early и `sections` stays stale.
- **Why it matters:** Users can see deleted servers/subscriptions remain visible or miss freshly merged subscription rows until later reload.
- **Suggested fix:** Make debounce opt-in для lifecycle duplicate suppression, OR add `loadFromStore(force: true)` для mutation tail-calls.

## Verdict

**Not ready for TestFlight on this scope.** T-B6 closed, но T-A5 НЕ полностью closed — compressed IPv6 masking still leaks common IPv6 literals.
