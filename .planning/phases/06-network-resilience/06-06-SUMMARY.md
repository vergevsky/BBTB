# 06-06 Wave 6 — Failover (SwiftDataFailoverProvider + reset wiring)

**Date:** 2026-05-13
**Plan:** `.planning/phases/06-network-resilience/06-06-PLAN.md`
**Wave:** 6 (depends_on: 06-02, 06-05) — final implementation wave of Phase 6
**Requirements:** NET-11 (failover on server failure)
**UAT:** deferred per user request (Phase 6 closure pending manual sub-tests A-I).

## Files created

| File | Lines | Role |
|------|-------|------|
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift` | 221 | `actor SwiftDataFailoverProvider` implementing `FailoverProviding` from Wave 5 — round-robin cursor over supported `ServerConfig` rows, edge-case notifications, deterministic ordering |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FailoverProviderTests.swift` | 323 | 11 tests covering single-server edge, empty pool, round-robin advance, wrap-around, isSupported filter, deterministic ordering by `id.uuidString`, `resetCycle`, attempt-closure provisioning, nil-current Auto-mode |

## Files modified

| File | Change |
|------|--------|
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` | + `var failoverProvider` (was `let`) + `setFailoverProvider(_:)` late-binder + `scheduleFailoverResetAfterStableSession(startedAt:)` (30s post-`.connected` timer with `startedAt` race guard per Pitfall 4) + `await failoverProvider.resetCycle()` at top of `disconnect()` + reconnectClock injection + test seam `firstAttemptOverrideForTest` |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift` | + `notifySingleServerUnavailable()` (identifier `"app.bbtb.single-server-unavailable"`) — on-demand UN auth + posts D-08 edge notification |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` | + 4 Wave 6 tests (8-11): `test_manualDisconnect_resetsFailoverCycle`, `test_handleStatusChange_connected_schedules_30s_reset`, `test_handleStatusChange_connectedThenDisconnected_doesNotReset`, `test_allFailed_consults_failoverProvider` — plus `SpyFailoverProvider` actor + `RecordingClock` test doubles |
| `BBTB/Packages/Localization/Sources/Localization/L10n.swift` | + `notificationSingleServerUnavailableTitle`, `notificationSingleServerUnavailableBody` |
| `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` | + ru/en string units for two new keys ("Сервер недоступен" / "Server unavailable") |
| `BBTB/App/iOSApp/BBTB_iOSApp.swift` | Two-phase init replaces `NoFailoverProvider`: constructs `SwiftDataFailoverProvider` with `[weak tunnel]` connect closure + `UserDefaults`-backed `currentServerID` reader, then `Task { await tunnel.setFailoverProvider(failoverProvider) }` |
| `BBTB/App/macOSApp/BBTB_macOSApp.swift` | Identical two-phase init wiring |

## Test counts (Wave 6)

- **FailoverProviderTests:** 11 / 11 PASS
  - `test_nextServer_single_server_returns_nil` — D-08 edge: notifies + returns nil
  - `test_nextServer_zero_servers_returns_nil` — empty pool silent nil
  - `test_nextServer_returns_next_when_two_servers` — pair wraps after one step
  - `test_nextServer_advances_round_robin_4_servers` — names match positions 1/2/3 of sorted pool
  - `test_nextServer_wraps_when_current_is_middle` — startIndex anywhere in pool
  - `test_nextServer_skips_unsupported` — isSupported=false rows filtered
  - `test_nextServer_deterministic_order` — `id.uuidString` ascending across insertion order
  - `test_resetCycle_starts_fresh_snapshot` — cursor + snapshot zeroed
  - `test_nextServer_attempt_closure_provisions_next_uuid` — attempt closure passes correct UUID to provisioner
  - `test_nextServer_with_nil_current_starts_at_zero` — Auto mode (nil currentServerID)
  - `test_nextServer_uses_fetchAll_filter_not_predicate` — D-12 / Pitfall 4 invariant

- **TunnelControllerStateTests (Wave 6 additions):** 4 / 4 PASS (total in file: 11 / 11 — 7 Wave 5 + 4 Wave 6)
  - `test_manualDisconnect_resetsFailoverCycle` — disconnect() calls `failoverProvider.resetCycle()` before NE round-trip
  - `test_handleStatusChange_connected_schedules_30s_reset` — RecordingClock paused during sleep, then resumed → resetCycle fires exactly once
  - `test_handleStatusChange_connectedThenDisconnected_doesNotReset` — status flips before 30s → reset skipped (race guard)
  - `test_allFailed_consults_failoverProvider` — 3 failed attempts via `firstAttemptOverrideForTest` → SM consults nextServerAttempt

- **AppFeatures full suite:** 120 / 120 PASS (105 baseline from Wave 5 + 15 net new in Wave 6).
- **Adjacent packages:** VPNCore 57/57, ConfigParser 210/210, PacketTunnelKit 61/61, Localization 3/3, VLESSReality + VLESSTLS + Shadowsocks + Hysteria2 + Trojan — all green, no regressions.

## Invariant verifications

- **Yandex eradication** — `grep -RIn "77.88.8.8" Packages/ | grep -v '.build/' | grep -v Tests/` returns **0** (zero shipping references; only regression-guard tests retain the literal to assert absence; stale `.build/` cache entries are intermediate index artifacts).
- **R1 (default-deny SOCKS)** — unchanged in this wave; no `inbounds` touched in TunnelController/FailoverProvider.
- **R6 (no destinationAddresses in NEPacketTunnelNetworkSettings)** — `grep -n "destinationAddresses" Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift | grep -v '//' | wc -l` returns **0**.
- **R10 (TUN inbound expansion + DNS-hijack)** — unchanged; SingBoxConfigLoader.expandConfigForTunnel preserved.
- **D-12 (no `#Predicate` with UUID)** — `grep -c "#Predicate" FailoverProvider.swift` returns 5, **all 5 are doc-comment WARNINGS against `#Predicate`** (lines 31, 33, 34, 188, 189); zero actual usage. Fetch path uses `context.fetch(FetchDescriptor<ServerConfig>())` + `.filter { $0.isSupported }.sorted { $0.id.uuidString < $1.id.uuidString }`.
- **`actor SwiftDataFailoverProvider`** declared once (line 58).
- **`scheduleFailoverResetAfterStableSession` + `failoverProvider.resetCycle`** appear 4 times in TunnelController.swift (definition + manual-disconnect path + stable-session path + observer wiring).
- **`SwiftDataFailoverProvider` injection** present in both `BBTB_iOSApp.swift` and `BBTB_macOSApp.swift` (2 hits each via `grep -c`).
- **`notifySingleServerUnavailable`** registered with stable identifier `"app.bbtb.single-server-unavailable"` and an injectable seam in `SwiftDataFailoverProvider.init` so tests substitute a no-op (UNUserNotificationCenter crashes in SPM xctest — `bundleProxyForCurrentProcess is nil`).

## Build verification

- `swift test --package-path Packages/AppFeatures` — `Executed 120 tests, with 0 failures`.
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -configuration Debug -destination 'generic/platform=iOS' build` — `** BUILD SUCCEEDED **`.
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` — `** BUILD SUCCEEDED **` (signing-allowed flag carried over from Wave 5 — known dev-cert config issue documented in Phase 12 prerequisites memory, unrelated to Wave 6 code correctness).
- sing-box template sizes (Pitfall 6): VLESS-Reality 1831 B, VLESS-TLS 1742 B, Trojan-TCP 1723 B, Trojan-WS 1861 B, Shadowsocks 1513 B, Hysteria2 1692 B — all well under the 256 KB limit; failover swap does not enlarge runtime configs.

## Decisions referenced

- **D-08 failover semantics** — round-robin over `ServerConfig.isSupported == true`, sorted by `id.uuidString`; cursor seeded at the currently-selected server (so the cycle "starts at next" and exhausts when wrapping back); single-server pool fires `notifySingleServerUnavailable` once per cycle.
- **D-12 fetch-all + Swift filter** — project-wide ban on `#Predicate` with UUID lookups (real-device empty-result bug observed in Phase 3); preserved here defensively in the failover hot path.
- **Pitfall 4 stable-session reset** — `handleStatusChange(.connected)` captures the current Date as `startedAt`, spawns a Task that sleeps 30s on `reconnectClock`, then re-checks both `lastSuccessfulConnectAt == startedAt` **and** `currentStatus == .connected` before firing `failoverProvider.resetCycle()`. A disconnect+reconnect mid-window updates `lastSuccessfulConnectAt` to a fresher Date, invalidating the stale task's captured `startedAt`.

## Pitfalls mitigated

- **Pitfall 3 (Manual disconnect race)** — preserved from Wave 5; Wave 6 adds `await failoverProvider.resetCycle()` as the first body statement in `disconnect()`, so even if NE round-trip fails, the cursor is reset.
- **Pitfall 4 (Failover cursor reset timing)** — two reset triggers (manual disconnect + 30s stable session) plus the `startedAt` race guard; verified by tests 8-10.
- **Pitfall 6 (sing-box JSON size)** — failover swap only changes provisioned profile UUID, no config bloat.
- **VM↔TunnelController init cycle** — two-phase init pattern: `TunnelController` constructed with `NoFailoverProvider` default; `SwiftDataFailoverProvider` then constructed with `[weak tunnel]` connect closure; finally `tunnel.setFailoverProvider(failoverProvider)` swaps in the real provider on the actor's mailbox. The `setFailoverProvider` body mutates `var failoverProvider` — actor isolation prevents data races; the `Task { await ... }` wrapping in app launchers tolerates the brief gap during which `NoFailoverProvider` is active.
- **UNUserNotificationCenter unavailable in SPM xctest** — `SwiftDataFailoverProvider.init` accepts `notifySingleServerUnavailable: @escaping @Sendable () async -> Void` so production wires the real `UserNotificationsHelper.notifySingleServerUnavailable` and tests inject a counting no-op.

## Architecture notes

- **Failover provider is mutable on the actor** — `var failoverProvider` (was `let` in Wave 5). Late-bound by `setFailoverProvider(_:)` because the production wiring captures `[weak tunnel]` inside the provider's `connect` closure, so the provider can't be constructed until the controller exists. Tests still pass via init parameter (default Wave 5 path remains valid).
- **Snapshot at cycle start, not per-call** — `cycleSnapshot` is fetched once when the cycle begins and held until `resetCycle()` empties it. T-06-W6-03 (stale-snapshot) is accepted: a freshly imported server doesn't participate in the in-flight cycle but does in the next one. Acceptable for MVP because cycles are <1 minute and server-list edits during a reconnect storm are rare.
- **`startIndex` "origin" marker** — the originally-selected server's index in the snapshot. Cursor advances `(cursor + 1) % count` and the cycle terminates when `cursor == startIndex` (full circle). For `currentServerID == nil` (Auto mode) the origin defaults to index 0.
- **Snapshot type `ServerSnapshot`** — minimal Sendable struct `{ id, name }` projected from `@Model` `ServerConfig` (which is not Sendable). Pattern reused from ServerProbeService.
- **`ConfigProvisioning` protocol** — narrow seam exposing only `provisionTunnelProfile(for:)`. `ConfigImporter` already implements that signature, so the conformance is a one-line extension; tests inject `RecordingProvisioner` (12 lines) instead of stubbing the entire importer.
- **End-to-end manual UAT** — Plan Task 3 specifies 9 device sub-tests (DNS leak, IPv6 leak, Wi-Fi↔LTE handoff, sleep wake, failover, single-server notification, manual disconnect race, R1/R6 invariants). Deferred per user request — to be completed in a follow-up UAT session.

## Phase 6 closure

With Wave 6 merged, all 6 implementation waves of Phase 6 are complete. NET-01..11 requirements are implemented and unit-tested. The remaining gate is device UAT (Plan 06-06 Task 3, sub-tests A-I) plus the deferred Phase 5 UAT and Wave 1-5 manual checks. Next step (per the user-skipped UAT): `/gsd-verify-work 6` once UAT signoff is collected.

## Follow-ups for Phase 7

- **LibboxCommandClient stall detection** — `06-RESEARCH.md` §6 flags an optional hook for detecting tunnel stalls beyond NE status. Phase 7 may revisit if anti-DPI work surfaces silent-stall failure modes.
- **Server health beyond reachability** — Failover currently treats any `.allFailed` cycle on the current server as a failure; Phase 7's anti-DPI work may want a finer per-server health signal (e.g., per-protocol probe history).

## References

- `.planning/phases/06-network-resilience/06-CONTEXT.md` D-07, D-08, D-12
- `.planning/phases/06-network-resilience/06-RESEARCH.md` §10 (FailoverProviding integration), §14 Pitfall 4 (failover index reset timing)
- `.planning/phases/06-network-resilience/06-PATTERNS.md` SwiftData fetch-all pattern from Phase 3 ConfigImporter
- `.planning/phases/06-network-resilience/06-05-SUMMARY.md` Wave 5 baseline (NoFailoverProvider stub, ReconnectStateMachine, TunnelController actor)
- PROJECT.md D-12 / memory `feedback_swiftdata_uuid_predicate.md`
