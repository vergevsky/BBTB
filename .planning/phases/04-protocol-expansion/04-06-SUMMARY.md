---
plan: 04-06
wave: 6
status: complete
committed: 463eb39
---

# Plan 04-06 — End-to-End Integration SUMMARY

## What was done

- **ConfigImporter.swift — exhaustive 5-case switches:** added `.vlessTLS`, `.shadowsocks`, `.hysteria2` cases to:
  - `buildServerConfig(from:id:subscriptionID:keychainTag:)` — host/port/sni/protocolID/displayName
  - `buildKeychainPayload(for:)` — Keychain serialization for each protocol
  - `reparseFromKeychain(_:tag:)` — deserialization back to `AnyParsedConfig`
  - Two `serverHost` extraction closures in `importFromRawInput` and `provisionTunnelProfile(for:)`
- **Imports:** `VLESSTLS`, `Shadowsocks`, `Hysteria2` added to `ConfigImporter.swift`
- **AppFeatures/Package.swift:** three new local packages + `MainScreenFeature` target dependencies
- **`runIsSupportedUpgrade()`:** D-14 background reconciliation — scans unsupported rows with `rawURI`, re-parses via `UniversalImportParser`, promotes to supported + Keychain + clears rawURI. Throttled to once per 5 minutes via `UserDefaults`.
- **`protocolIDString(from:)` + `displayNameString(from:)`:** internal 5-case helpers used by `runIsSupportedUpgrade`
- **`ConfigImporting` protocol:** added `runIsSupportedUpgrade() async`; all 3 mock importers updated (`AutoSelectIntegrationTests`, `CascadeDeleteTests`, `PullToRefreshTests`)
- **iOS + macOS apps:** registered `VLESSTLSHandler`, `ShadowsocksHandler`, `Hysteria2Handler` in `ProtocolRegistry.shared`; added `scenePhase` foreground hook calling `importer.runIsSupportedUpgrade()` on `.active`
- **Project.swift:** added VLESSTLS/Shadowsocks/Hysteria2 to `localPackages` + iOS + macOS target `.dependencies`
- **MergeStrategyTests.swift:** fixed non-exhaustive switch for 3 new `AnyParsedConfig` cases

## Test results

```
49/49 PASS (AppFeatures package)
  ConfigImporterAnyParsedConfigTests:  7 tests PASS
  IsSupportedUpgradeTests:             5 tests PASS
  ConfigImporterSubscriptionTests:    existing — PASS (no regression)
  MergeStrategyTests:                 existing — PASS (fixed switch)
  AutoSelectIntegrationTests:         existing — PASS
  CascadeDeleteTests:                 existing — PASS
  PullToRefreshTests:                 existing — PASS
  SectionGroupingTests:               existing — PASS
  ConnectionTimerTests:               existing — PASS
```

## Key decisions / adaptations

1. **SwiftData UUID predicate in `runIsSupportedUpgrade`:** `#Predicate { $0.id == cfg.id }` causes a SwiftData macro expansion error on Swift 6. Used fetch-all + Swift `.filter` instead — same pattern as `SubscriptionMergeService` (known pitfall from memory).

2. **`runIsSupportedUpgrade` on protocol vs concrete type:** Added the method to `ConfigImporting` protocol so the iOS/macOS app foreground hook can call it through `viewModel.importer` (typed as `ConfigImporting`) without force-casting.

3. **`SubscriptionMergeService` already complete:** The merge service already had proper 5-case SNI update logic for all Phase 4 protocols — no changes needed there.

4. **`MergeStrategyTests` fix required:** The stub `buildServerConfig` closure inside the test had a 2-case switch on `AnyParsedConfig` — became non-exhaustive after Phase 4 enum expansion. Added 3 new cases.
