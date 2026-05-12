// ReconnectStateMachineTests.swift — Phase 6 / Plan 06-04 / Wave 4 / Task 2.
//
// Tests for `ReconnectStateMachine`:
// - 3 attempts per server with exp backoff 2s / 4s / 8s (D-07).
// - Failover on all-3-fails: caller-provided `failoverNext()` swaps to next server.
// - `.allFailed` when `failoverNext()` returns nil (D-08 round-robin exhausted).
// - Cancellation propagates through `Task.isCancelled` + `clock.sleep` throw.
// - `reportConnected()` resets to `.idle`.
//
// Determinism: `TestReconnectClock` records the sleep durations and yields
// immediately, so backoff assertions don't burn 14 wall-clock seconds per test.

import XCTest
@testable import MainScreenFeature

final class ReconnectStateMachineTests: XCTestCase {

    // MARK: - Test doubles

    /// Records `sleep(seconds:)` calls and returns instantly. Supports cancellation
    /// (Task.checkCancellation) so cancel-during-sleep tests behave realistically.
    actor TestReconnectClock: ReconnectClock {
        private(set) var recordedSleeps: [Int] = []
        func sleep(seconds: Int) async throws {
            recordedSleeps.append(seconds)
            try Task.checkCancellation()
            await Task.yield()
        }
        func sleeps() -> [Int] { recordedSleeps }
    }

    /// Records observed state transitions. Sendable-safe via NSLock.
    final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var states: [ReconnectStateMachineState] = []
        func append(_ s: ReconnectStateMachineState) {
            lock.lock(); defer { lock.unlock() }
            states.append(s)
        }
        func snapshot() -> [ReconnectStateMachineState] {
            lock.lock(); defer { lock.unlock() }
            return states
        }
    }

    /// Sendable counter for AttemptHandler invocations.
    final class AttemptCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int = 0
        func incrementAndGet() -> Int {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
        func get() -> Int {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    // MARK: - Helpers

    /// Spin-wait (via Task.yield) until `predicate()` is true or `iterations`
    /// elapse. Avoids real sleeps — the actor + TestClock both progress only
    /// when we yield.
    private func waitUntil(
        iterations: Int = 1_000,
        _ predicate: @Sendable () async -> Bool
    ) async {
        for _ in 0..<iterations {
            if await predicate() { return }
            await Task.yield()
        }
    }

    private func makeMachine(
        clock: ReconnectClock,
        recorder: StateRecorder
    ) -> ReconnectStateMachine {
        ReconnectStateMachine(clock: clock) { state in
            recorder.append(state)
        }
    }

    // MARK: - Tests

    func test_state_machine_idle_initial() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)
        let s = await sm.currentState()
        XCTAssertEqual(s, .idle)
        XCTAssertEqual(recorder.snapshot(), [])
    }

    func test_state_machine_first_attempt_success_ends_at_idle() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)

        let attempt: ReconnectStateMachine.AttemptHandler = { Date() }
        let failover: ReconnectStateMachine.FailoverProvider = { nil }

        await sm.run(firstAttempt: attempt, failoverNext: failover)
        await waitUntil { await sm.currentState() == .idle && recorder.snapshot().count >= 2 }

        let states = recorder.snapshot()
        XCTAssertEqual(states.first, .retrying(attempt: 1, delaySeconds: 2))
        XCTAssertEqual(states.last, .idle)
        // Backoff slept once (before the successful attempt).
        let slept = await clock.sleeps()
        XCTAssertEqual(slept, [2])
    }

    func test_state_machine_success_on_attempt_2_does_not_continue_to_3() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)
        let counter = AttemptCounter()

        let attempt: ReconnectStateMachine.AttemptHandler = {
            let n = counter.incrementAndGet()
            if n == 1 {
                throw NSError(domain: "test", code: -1)
            }
            return Date()
        }
        let failover: ReconnectStateMachine.FailoverProvider = { nil }

        await sm.run(firstAttempt: attempt, failoverNext: failover)
        await waitUntil { await sm.currentState() == .idle && recorder.snapshot().last == .idle }

        XCTAssertEqual(counter.get(), 2)
        let states = recorder.snapshot()
        XCTAssertEqual(states, [
            .retrying(attempt: 1, delaySeconds: 2),
            .retrying(attempt: 2, delaySeconds: 4),
            .idle
        ])
        let slept = await clock.sleeps()
        XCTAssertEqual(slept, [2, 4])
    }

    func test_state_machine_backoff_2_4_8_seconds() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)

        // Always fail this server's 3 attempts; failoverNext returns nil → .allFailed.
        let attempt: ReconnectStateMachine.AttemptHandler = {
            throw NSError(domain: "test", code: -1)
        }
        let failover: ReconnectStateMachine.FailoverProvider = { nil }

        await sm.run(firstAttempt: attempt, failoverNext: failover)
        await waitUntil { await sm.currentState() == .allFailed }

        let slept = await clock.sleeps()
        XCTAssertEqual(slept, [2, 4, 8], "backoff must be exactly 2/4/8 seconds per D-07")
    }

    func test_state_machine_three_failures_lands_at_allFailed() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)

        let attempt: ReconnectStateMachine.AttemptHandler = {
            throw NSError(domain: "test", code: -1)
        }
        let failover: ReconnectStateMachine.FailoverProvider = { nil }

        await sm.run(firstAttempt: attempt, failoverNext: failover)
        await waitUntil { await sm.currentState() == .allFailed }

        let states = recorder.snapshot()
        XCTAssertEqual(states, [
            .retrying(attempt: 1, delaySeconds: 2),
            .retrying(attempt: 2, delaySeconds: 4),
            .retrying(attempt: 3, delaySeconds: 8),
            .allFailed
        ])
    }

    func test_state_machine_failover_invoked_after_three_failures() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)

        let firstCounter = AttemptCounter()
        let firstAttempt: ReconnectStateMachine.AttemptHandler = {
            _ = firstCounter.incrementAndGet()
            throw NSError(domain: "test", code: -1)
        }
        let secondAttempt: ReconnectStateMachine.AttemptHandler = { Date() }
        let failover: ReconnectStateMachine.FailoverProvider = {
            (serverName: "B", attempt: secondAttempt)
        }

        await sm.run(firstAttempt: firstAttempt, failoverNext: failover)
        await waitUntil { await sm.currentState() == .idle && recorder.snapshot().last == .idle }

        XCTAssertEqual(firstCounter.get(), 3, "server A must be tried 3 times before failover")
        let states = recorder.snapshot()
        XCTAssertEqual(states, [
            .retrying(attempt: 1, delaySeconds: 2),
            .retrying(attempt: 2, delaySeconds: 4),
            .retrying(attempt: 3, delaySeconds: 8),
            .failover(toServerName: "B"),
            .retrying(attempt: 1, delaySeconds: 2),
            .idle
        ])
        // Sleeps: 2/4/8 for server A, 1s "breath" before server B, 2s before B's first attempt.
        let slept = await clock.sleeps()
        XCTAssertEqual(slept, [2, 4, 8, 1, 2])
    }

    func test_state_machine_failover_returning_nil_lands_at_allFailed() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)

        let attempt: ReconnectStateMachine.AttemptHandler = {
            throw NSError(domain: "test", code: -1)
        }
        let failover: ReconnectStateMachine.FailoverProvider = { nil }

        await sm.run(firstAttempt: attempt, failoverNext: failover)
        await waitUntil { await sm.currentState() == .allFailed }
        XCTAssertEqual(recorder.snapshot().last, .allFailed)
    }

    func test_state_machine_cancel_during_sleep_returns_to_idle() async {
        // Use a real-time clock that sleeps long enough for cancellation to land.
        struct LongClock: ReconnectClock {
            func sleep(seconds: Int) async throws {
                // Sleep for the requested seconds (cap so test is bounded).
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 1)) * 1_000_000_000)
            }
        }
        let recorder = StateRecorder()
        let sm = ReconnectStateMachine(clock: LongClock()) { s in recorder.append(s) }

        let attempt: ReconnectStateMachine.AttemptHandler = {
            throw NSError(domain: "test", code: -1)
        }
        let failover: ReconnectStateMachine.FailoverProvider = { nil }

        await sm.run(firstAttempt: attempt, failoverNext: failover)
        // Wait until we're inside the first sleep (state moved to .retrying).
        await waitUntil { recorder.snapshot().contains(.retrying(attempt: 1, delaySeconds: 2)) }

        let cancelStart = Date()
        await sm.cancel()
        // Give the cancelled task a tick to unwind.
        await waitUntil { await sm.currentState() == .idle }
        let elapsedMs = Date().timeIntervalSince(cancelStart) * 1000

        let finalState = await sm.currentState()
        XCTAssertEqual(finalState, .idle)
        XCTAssertLessThan(elapsedMs, 500, "cancel must return to .idle quickly")
        XCTAssertEqual(recorder.snapshot().last, .idle)
    }

    func test_state_machine_reportConnected_clears_state() async {
        let clock = TestReconnectClock()
        let recorder = StateRecorder()
        let sm = makeMachine(clock: clock, recorder: recorder)

        // Kick off a loop that never finishes (always fails, no failover) — then
        // simulate the OS reporting `.connected`, which should reset to `.idle`.
        let attempt: ReconnectStateMachine.AttemptHandler = {
            throw NSError(domain: "test", code: -1)
        }
        let failover: ReconnectStateMachine.FailoverProvider = { nil }

        await sm.run(firstAttempt: attempt, failoverNext: failover)
        await waitUntil { !recorder.snapshot().isEmpty }
        await sm.reportConnected()
        await waitUntil { await sm.currentState() == .idle }
        let finalState = await sm.currentState()
        XCTAssertEqual(finalState, .idle)
    }
}
