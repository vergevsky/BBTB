# 06-05 Wave 5 — TunnelController integration (reconnect + DNS + wake + banner + notifications)

**Date:** 2026-05-13
**Plan:** `.planning/phases/06-network-resilience/06-05-PLAN.md`
**Wave:** 5 (depends_on: 06-01, 06-03, 06-04)
**Requirements:** NET-01 (wiring), NET-08, NET-09, NET-10

## Files created

| File | Lines | Role |
|------|-------|------|
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift` | 78 | `notifyReconnectFailed(serverName:)` — on-demand UN auth + local notification |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterDNSTests.swift` | 257 | 9 tests covering D-01..D-04 priority + end-to-end PoolBuilder integration |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` | 206 | 7 tests covering manualDisconnect race, idempotent reachability, foreground no-op (Pitfall 8) |

## Files modified

| File | Change |
|------|--------|
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` | +120 lines: `buildDNSConfig(for:)` + private helpers (`extractHost`, `looksLikeIPv4`, `isValidIPv4`, `isValidHostname`, `formatCustomDNS`); both `PoolBuilder.buildSingBoxJSON` call sites thread `dns:` parameter |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` | Rewritten — `actor TunnelController` with `manualDisconnectInProgress`, `lastSuccessfulConnectAt`, `wakePending`, `startReachability/stopReachability/handleForeground/handleStatusChange` |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift` | Extended with `message: String` parameter + optional dismiss — backward-compat via existing `init(onDismiss:)` |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | `ReconnectBannerState` enum + `@Published reconnectBannerState` + `makeReconnectStateObserver()` factory + `tunnelController` accessor + `applyReconnectStateMachineState` mapper |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` | Banner driven by `reconnectBannerMessage`; dismiss button only for kill-switch variant |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift` | `MockTunnel` conforms to extended `TunnelControlling` (no-op `startReachability/stopReachability/handleForeground`) |
| `BBTB/Packages/Localization/Sources/Localization/L10n.swift` | 6 new keys: `bannerReconnecting(_:)`, `bannerFailover`, `bannerAllFailed`, `notificationReconnectFailedTitle`, `notificationReconnectFailedBody(_:)`, `notificationReconnectFailedBodyGeneric` |
| `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` | 6 corresponding ru/en string units |
| `BBTB/App/iOSApp/BBTB_iOSApp.swift` | `ReconnectStateObserverRelay` wires VM↔TunnelController; `startReachability()` on launch; scenePhase = .active calls `handleForeground()` |
| `BBTB/App/macOSApp/BBTB_macOSApp.swift` | Same wiring; macOS uses NSWorkspace wake notification inside `startReachability()` |
| 6 × `SingBoxConfigTemplate.*.json` (PacketTunnelKit + 5 protocol packages) | Replaced Yandex `tcp://77.88.8.8` with AdGuard `tcp://94.140.14.14` per D-01; these are legacy single-protocol templates (no production callers — PoolBuilder owns the runtime path) |

## Test counts

- **ConfigImporterDNSTests:** 9 / 9 PASS
  - `test_buildDNSConfig_defaultEmptySettings_numericHost_usesServerIPBootstrap`
  - `test_buildDNSConfig_defaultEmptySettings_hostnameHost_fallsBackToAdGuardBootstrap` (Pitfall 5)
  - `test_buildDNSConfig_customDNSIPv4_winsAndIgnoresAdBlock` (D-03)
  - `test_buildDNSConfig_customDNSHost_formatsAsDohURL`
  - `test_buildDNSConfig_adBlockOnly_usesAdGuardTunnelDNS` (D-04)
  - `test_buildDNSConfig_invalidCustomDNS_treatedAsEmpty`
  - `test_buildDNSConfig_invalidCustomDNS_withAdBlock_fallsToAdGuard`
  - `test_buildDNSConfig_multipleServers_usesFirstForBootstrap`
  - `test_importFromRawInput_threadsDNSConfigIntoPoolJSON` — end-to-end integration

- **TunnelControllerStateTests:** 7 / 7 PASS
  - `test_manualDisconnect_setsFlag` (Pitfall 3)
  - `test_handleStatusChange_ignoresDisconnectedDuringManualDisconnect` (Pitfall 3)
  - `test_handleStatusChange_triggersRecoveryOnUnexpectedDisconnect`
  - `test_handleStatusChange_onConnected_updatesLastConnectAndReports`
  - `test_startReachability_isIdempotent`
  - `test_handleForeground_disconnected_noOp` (Pitfall 8)
  - `test_handleForeground_connected_noOp` (Pitfall 8)

- **AppFeatures full suite:** 105 / 105 PASS (89 baseline + 16 Wave 5).
- **Adjacent packages:** VPNCore 57/57, ConfigParser 210/210, PacketTunnelKit 61/61, Localization 3/3, VLESSTLS 19/19, Trojan 16/16, Hysteria2 14/14, Shadowsocks 10/10 — no regressions.

## Invariant verifications

- **Yandex eradication** — `grep -RIn "77.88.8.8" BBTB/Packages/ 2>/dev/null | grep -v ".build/"` returns only test files (asserting absence). All production source files Yandex-free.
- **R6 invariant** — `grep -n "destinationAddresses" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift | grep -v '//' | wc -l` returns 0. Wave 5 didn't touch TunnelSettings; R6 preserved.
- **Correct wake notification center** — `grep -c "NSWorkspace.shared.notificationCenter" TunnelController.swift` returns 3 (add observer + remove observer + macOS attribution); `grep -c "NotificationCenter.default.addObserver.*didWakeNotification" TunnelController.swift` returns 0 (RESEARCH §5 / Pitfall 10).
- **`actor TunnelController`** declared once (line 84).
- **`manualDisconnectInProgress`** appears 8× in TunnelController.swift (declaration + setter in disconnect + guard in handleStatusChange + test seam + comments).
- **`buildDNSConfig`** appears 4× in ConfigImporter.swift (definition + 2 call sites + 1 doc reference).

## Build verification

- `cd BBTB/Packages/AppFeatures && swift build` — succeeds (iOS + macOS).
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -sdk iphonesimulator build` — `** BUILD SUCCEEDED **`.
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` — `** BUILD SUCCEEDED **` (default signing requires development certificate; signing is unrelated to Wave 5 code correctness).

## Decisions referenced

- **D-01 bootstrap DNS strategy** — `buildDNSConfig` selects `tcp://<server-IP>` when first parsed config has IPv4 host; otherwise AdGuard `tcp://94.140.14.14` fallback.
- **D-02 tunnel DNS default** — Cloudflare DoH when no custom + no AdBlock.
- **D-03 custom DNS priority** — non-empty validated `customDNS` overrides; AdBlock toggle ignored.
- **D-04 AdBlock toggle** — when custom is empty and `adBlockEnabled == true` → `.adguard`.
- **D-07 retry policy** — 3 attempts × 2/4/8 s exp backoff (consumed via Wave 4 `ReconnectStateMachine`).
- **D-08 failover** — Wave 5 stubs `NoFailoverProvider` (always returns nil → `.allFailed`); Wave 6 implements real round-robin against SwiftData.

## Pitfalls mitigated

- **Pitfall 3 (Manual disconnect race)** — `manualDisconnectInProgress` set at top of `disconnect()`, cleared 1s after the polling loop hits `.disconnected`. `handleStatusChange(.disconnected)` early-returns when flag is true. Tested.
- **Pitfall 5 (Bootstrap DNS chicken-and-egg)** — hostname-only server hosts trigger AdGuard fallback `tcp://94.140.14.14`. Tested.
- **Pitfall 8 (scenePhase storm)** — `handleForeground()` is a cheap status read with no state-machine work; tests verify it's a no-op for both `.disconnected` and `.connected`.
- **Pitfall 10 (macOS wake before network ready)** — `handleWake()` sets `wakePending = true`; the next `handleReachability(.satisfied)` consumes the flag and triggers recovery. Uses `NSWorkspace.shared.notificationCenter` (NOT `NotificationCenter.default`).
- **UNUserNotificationCenter extension limitation** — `UserNotificationsHelper` is invoked from `MainScreenViewModel` (main app target only); never reached from the PacketTunnel extension.

## Architecture notes

- **Promotion to actor** — `TunnelController` is now `public actor` (was `final class @unchecked Sendable`). Existing `connect()` / `disconnect()` bodies preserved verbatim; new state is actor-isolated which removes the need for ad-hoc locking. `TunnelControlling` protocol gained `startReachability()`, `stopReachability()`, `handleForeground()` — all `async`.
- **State machine observer wiring** — `ReconnectStateObserverRelay` (new public type) breaks the VM↔TunnelController init cycle: app code creates an empty relay, passes its observer to `TunnelController.init(stateObserver:)`, constructs the VM, then calls `relay.set(observer: vm.makeReconnectStateObserver())`. Subsequent state-machine transitions reach the VM's `applyReconnectStateMachineState`, which updates `@Published reconnectBannerState` and triggers `UserNotificationsHelper` on `.allFailed`.
- **Failover stub** — `NoFailoverProvider` always returns nil, so the state machine immediately collapses to `.allFailed` after 3 attempts on the current server. Wave 6 replaces with a SwiftData-backed implementation that supplies the next server's attempt closure.
- **End-to-end manual UAT** — deferred to Wave 6 device testing once failover ships.

## References

- `.planning/phases/06-network-resilience/06-CONTEXT.md` D-01..D-04, D-07, D-08
- `.planning/phases/06-network-resilience/06-RESEARCH.md` §5 (macOS wake), §6 (NEVPN status path), §8 (PoolBuilder DNS API), §10 (TunnelController evolution), §11 (UNUserNotificationCenter), §14 Pitfalls 3, 5, 8, 10
- `.planning/phases/06-network-resilience/06-PATTERNS.md` ReconnectBanner Option B, Threading section
