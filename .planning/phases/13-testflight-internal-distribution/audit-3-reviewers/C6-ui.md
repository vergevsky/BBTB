# C6 — SettingsFeature + ServerListFeature (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 2 (0/1/1/0)

## Critical
No critical findings found in this SettingsFeature + ServerListFeature pass.

## High
### C6'-3-001: IPv4-mapped IPv6 literals still leak after the T-A5' masking rewrite
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:71`
- **Dimension:** Privacy / diagnostics export redaction
- **Description:** `prepareLog` still applies `maskIPv4` before `maskIPv6`. That order converts dotted-quad IPv4-mapped IPv6 literals into forms the new T-A5' IPv6 regexes no longer match. For example, `::ffff:192.0.2.128` becomes `::ffff:192.0.2.xxx`, and `0:0:0:0:0:ffff:192.0.2.128` becomes `0:0:0:0:0:ffff:192.0.2.xxx`; neither is replaced by `[ipv6:xxx]` because the patterns at `DiagnosticsExporter.swift:149` only accept hex groups plus optional zone IDs. I verified the T-A5' compressed-form cases themselves now pass (`::1`, `fe80::1`, `fe80::1%en0`, `2001:db8::8a2e:7334`, and full 8-group IPv6), so this is the remaining mapped-address path rather than a re-report of the closed compressed-form bug.
- **Why HIGH:** The diagnostics export can still disclose the network prefix and the fact that the user connected to an IPv4-mapped IPv6 endpoint. This is exactly the file users are asked to share for support, so partial endpoint leakage remains production-visible.
- **Suggested fix:** Mask IPv6 before IPv4, or add IPv4-embedded IPv6 alternatives that accept dotted quads before `maskIPv4` mutates the tail. Prefer a small parser/normalizer over chained regexes if Foundation/Network parsing is available. Add tests for `::ffff:192.0.2.128`, `0:0:0:0:0:ffff:192.0.2.128`, and `::ffff:c000:0280`.

## Medium
### C6'-3-002: Subscription refresh does not update existing servers' raw config or Keychain secret
- **Location:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:493`
- **Dimension:** Correctness / ImporterUI integration
- **Description:** ServerList refresh fetches and parses each subscription, then calls `SubscriptionMergeService.merge(...)` with closures that can persist Keychain secrets and build fresh `ServerConfig` rows. That works only on the insert path. When a fetched server matches an existing identity, the merge path updates `name`, `missingFromLastFetch`, and `sni` only (`BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift:88`); it does not update `rawURI`, `outboundJSON`, `keychainTag`, or the Keychain payload. A provider can rotate UUID/password/public-key/transport settings while keeping the same `host:port:protocolID`, and the UI will report refresh success while connect continues using the stale stored config.
- **Why MEDIUM:** This breaks the main subscription maintenance flow without an obvious user-facing error. It is not an immediate security boundary bypass, but it can leave TestFlight users on revoked credentials or obsolete transport settings until they delete/re-import the subscription.
- **Suggested fix:** On existing-identity merges, rebuild the current server config fields from the freshly parsed `ImportedServer` and overwrite the Keychain item atomically, while preserving user-owned fields such as latency, selection, and possibly `transportOverride`. If preserving per-user overrides is intended, document and test that merge policy explicitly.

## Low
No low findings found in this pass.

## Notes
- I read `AUDIT-2.md` first and did not re-report C6'-002 / T-C7' `loadFromStore(force:)`; mutation paths now force reload in `deleteServer`, `confirmDeleteSubscription`, `pullToRefresh`, and `silentForegroundRefresh` (`ServerListViewModel.swift:278`, `ServerListViewModel.swift:313`, `ServerListViewModel.swift:339`, `ServerListViewModel.swift:383`).
- App Group suite usage for extension-read settings looks correct in this scope: `routingRulesEnabled`, `stunBlockEnabled`, `muxEnabled`, `utlsFingerprint`, and macOS `macOSDisableEnforceRoutes` are written via `@AppStorage(..., store: UserDefaults(suiteName: "group.app.bbtb.shared"))` (`SettingsViewModel.swift:72`, `SettingsViewModel.swift:77`, `SettingsViewModel.swift:94`, `SettingsViewModel.swift:99`, `SettingsViewModel.swift:106`) and read from the same suite downstream (`SingBoxConfigLoader.swift:356`, `SingBoxConfigLoader.swift:432`, `SingBoxConfigLoader.swift:483`, `PoolBuilder.swift:69`, `PlatformSpecific/macOS.swift:20`).
- Force-update state machine has the expected MainActor race guard and cooldown transitions (`SettingsViewModel.swift:460`, `SettingsViewModel.swift:477`, `SettingsViewModel.swift:515`); no new force-update finding in this pass.
