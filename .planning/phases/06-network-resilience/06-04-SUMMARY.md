# 06-04 Wave 4 — Reachability monitor + Reconnect state machine

**Date:** 2026-05-13
**Plan:** `.planning/phases/06-network-resilience/06-04-PLAN.md`
**Wave:** 4 (independent — `depends_on: []`)
**Requirements:** NET-08, NET-09 (partial — foreground hook wired in Wave 5), NET-10

## Files created

| File | Lines | Role |
|------|-------|------|
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift` | 168 | actor wrapping `NWPathMonitor` with throttle + dedup + physical-interface filter |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` | 182 | actor implementing D-07 retry policy (3 attempts × 2/4/8 s backoff) + D-08 failover |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift` | 153 | 10 tests covering filter, throttle, dedup, stop |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift` | 283 | 9 tests covering idle/retry/failover/allFailed/cancel/reportConnected |

All four files exceed the plan's `min_lines` thresholds (80 / 100 / 80 / 120).

## Test counts

- **NetworkReachabilityTests:** 10 / 10 PASS
  - `test_reachability_filters_loopback_only_path_no_event`
  - `test_reachability_filters_utun_VPN_interface`
  - `test_reachability_initial_wifi_emits_satisfied`
  - `test_reachability_same_type_consecutive_dedups_to_one_event`
  - `test_reachability_stop_clears_listener_so_no_more_events`
  - `test_reachability_throttle_drops_event_within_500ms`
  - `test_reachability_throttle_releases_after_500ms`
  - `test_reachability_unsatisfied_from_satisfied_emits_unsatisfied`
  - `test_reachability_unsatisfied_when_already_unsatisfied_is_noop`
  - `test_reachability_wifi_to_cellular_emits_changed`

- **ReconnectStateMachineTests:** 9 / 9 PASS
  - `test_state_machine_idle_initial`
  - `test_state_machine_first_attempt_success_ends_at_idle`
  - `test_state_machine_success_on_attempt_2_does_not_continue_to_3`
  - `test_state_machine_backoff_2_4_8_seconds` — **asserts `recordedSleeps == [2, 4, 8]` exactly**
  - `test_state_machine_three_failures_lands_at_allFailed`
  - `test_state_machine_failover_invoked_after_three_failures` — asserts `[2, 4, 8, 1, 2]` (3 fails on A + 1s breath + 2s before B's first attempt)
  - `test_state_machine_failover_returning_nil_lands_at_allFailed`
  - `test_state_machine_cancel_during_sleep_returns_to_idle` — measures cancel-to-idle < 500ms wall-clock
  - `test_state_machine_reportConnected_clears_state`

- **Full AppFeatures suite:** 89 / 89 PASS (no regressions — pre-Wave-4 was 70, now 89).

## Threading / discipline confirmations

- **No `DispatchQueue.asyncAfter` usage:** `grep -E "DispatchQueue\.asyncAfter|DispatchQueue\.main\.asyncAfter" ReconnectStateMachine.swift` → 0 lines.
- **All sleeps via `ReconnectClock`:** production uses `SystemReconnectClock` (delegates to `Task.sleep(nanoseconds:)`); tests inject `TestReconnectClock` that records durations and yields. Plan §verification backoff assertion is therefore deterministic and runs in milliseconds.
- **Actor isolation:** both `NetworkReachability` and `ReconnectStateMachine` are `actor`s — no `@unchecked Sendable`, no manual locks inside production code (test helpers use `NSLock` to bridge into `XCTest`'s sync world).
- **Cancellation:** `cancel()` calls `currentTask?.cancel()`; the loop checks `Task.isCancelled` after every sleep and before every attempt. Cancellation also propagates through `clock.sleep(seconds:)` which throws on cancel.

## References

- **D-07 (retry policy):** `.planning/phases/06-network-resilience/06-CONTEXT.md` — 3 attempts × 2/4/8 s backoff.
- **D-08 (failover):** ibid — round-robin to next server after 3 fails; `.allFailed` when exhausted. Wave 4 implements the state machine; Wave 5 supplies the concrete `FailoverProvider` against SwiftData.
- **RESEARCH §3:** canonical `NWPathMonitor` actor wrapper. Implementation mirrors this; the only divergence is splitting the path-processing core into an `internal func processPath(_:now:)` so tests can drive it without the live monitor.
- **RESEARCH §9:** canonical `ReconnectStateMachine` actor code. Implementation matches with one addition — `ReconnectClock` protocol + `SystemReconnectClock` default for deterministic tests.
- **RESEARCH §14 Pitfall 2:** "NWPathMonitor fires during our own tunnel bring-up" → mitigated by physical-interface filter and 500 ms throttle (both verified in tests).
- **RESEARCH §14 Pitfall 3:** "Manual disconnect races with auto-reconnect" → Wave 4 surface (`cancel()` + `reportConnected()`) is the contract; the `manualDisconnectInProgress` flag lives in Wave 5's `TunnelController`.
- **RESEARCH §14 Pitfall 4:** "Failover index reset timing" → Wave 4 leaves the 30-s stable-session gate to Wave 5; `reportConnected()` is the entry point Wave 5 will call once the gate passes.

## Wave 5 readiness

Wave 5 (TunnelController integration) consumes the following public surface:

```swift
public actor NetworkReachability {
    public init()
    public func setListener(_ listener: @escaping NetworkReachability.Listener)
    public func start(_ listener: @escaping NetworkReachability.Listener)
    public func stop()
}

public enum NetworkReachabilityEvent: Equatable, Sendable {
    case satisfied(physical: NWInterface.InterfaceType?)
    case unsatisfied
    case changed(from: NWInterface.InterfaceType?, to: NWInterface.InterfaceType?)
}

public actor ReconnectStateMachine {
    public typealias AttemptHandler = @Sendable () async throws -> Date
    public typealias FailoverProvider = @Sendable () async -> (serverName: String, attempt: AttemptHandler)?
    public typealias StateObserver = @Sendable (ReconnectStateMachineState) -> Void

    public init(clock: ReconnectClock = SystemReconnectClock(), observer: StateObserver? = nil)
    public func run(firstAttempt: @escaping AttemptHandler, failoverNext: @escaping FailoverProvider)
    public func cancel()
    public func reportConnected()
    public func currentState() -> ReconnectStateMachineState
}
```

## Deferred to Wave 6 UAT

- **Live `NWPathMonitor` device behavior:** real Wi-Fi↔LTE handoff timing, multi-callback bursts during VPN handshake, captive-portal probe interactions. Unit tests cover the processing logic; UAT confirms the OS surface matches the assumed callback shape.
- **End-to-end cancel responsiveness on device:** unit test asserts < 500 ms; UAT measures real "tap Disconnect" → "VPN off" latency.
