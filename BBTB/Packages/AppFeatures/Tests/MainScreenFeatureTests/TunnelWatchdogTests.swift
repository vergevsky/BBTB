// TunnelWatchdogTests.swift — Phase 6c / Plan 06C-03 / Task 3.
//
// 9 тестов (Round 2: was 8, +1 для W-05 `.reasserting` cancellation):
//   1. test_disconnectedBeforeStableSession_noFailover
//   2. test_stableSession_disconnected_firesFailoverAfterDebounce
//   3. test_disconnectButManagerDisabled_noFailover
//   4. test_disconnectButNoUserIntent_noFailover
//   5. test_debounceCancelledByReconnect (.connecting cancels)
//   6. test_debounceCancelledByReasserting (.reasserting cancels — NEW W-05)
//   7. test_userIntentFalseResetsState
//   8. test_failoverNextNil_noAttemptExecuted
//   9. test_failoverNextNonNil_attemptInvoked
//
// Используем `InstantReconnectClock` из `TestClocks.swift` (Round 2 B-02 —
// extracted shared seam). Тесты wallclock-free.

import XCTest
import NetworkExtension
@testable import MainScreenFeature

final class TunnelWatchdogTests: XCTestCase {

    // MARK: - Test doubles

    /// Mock FailoverProviding — records calls, allows stubbing `nextResult`.
    final actor MockFailover: FailoverProviding {
        var nextAttemptCalls = 0
        var resetCalls = 0
        var nextResult: (serverName: String, attempt: @Sendable () async throws -> Date)?

        func setNextResult(_ result: (serverName: String, attempt: @Sendable () async throws -> Date)?) {
            self.nextResult = result
        }

        func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)? {
            nextAttemptCalls += 1
            return nextResult
        }
        func resetCycle() async {
            resetCalls += 1
        }
        func getNextAttemptCalls() -> Int { nextAttemptCalls }
    }

    /// Sendable counter для attempt-closure invocations.
    final actor AttemptCounter {
        var count = 0
        func increment() { count += 1 }
        func get() -> Int { count }
    }

    // MARK: - Helpers

    private func waitUntil(
        iterations: Int = 1_000,
        _ predicate: @Sendable () async -> Bool
    ) async {
        for _ in 0..<iterations {
            if await predicate() { return }
            await Task.yield()
        }
    }

    /// Привод watchdog'а в состояние «userIntent=true, stableSession=true».
    /// Эмитит `.connected` и ждёт пока stable-session task поставит флаг через
    /// `InstantReconnectClock` (yield, instant).
    private func primeStableSession(_ watchdog: TunnelWatchdog) async {
        await watchdog.setUserIntent(true)
        await watchdog.handleStatusChange(.connected, managerEnabled: true)
        await waitUntil { await watchdog.getStableSessionForTest() }
    }

    // MARK: - Tests

    /// Test 1 — .disconnected до stable session → НЕ fire failover.
    func test_disconnectedBeforeStableSession_noFailover() async {
        let mock = MockFailover()
        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: InstantReconnectClock()
        )
        await watchdog.setUserIntent(true)
        // Никакого .connected → stableSession остаётся false.

        await watchdog.handleStatusChange(.disconnected, managerEnabled: true)
        for _ in 0..<200 { await Task.yield() }

        let calls = await mock.getNextAttemptCalls()
        XCTAssertEqual(calls, 0, "до stable session failover не должен запускаться")
    }

    /// Test 2 — stable session + .disconnected → fire failover после debounce.
    func test_stableSession_disconnected_firesFailoverAfterDebounce() async {
        let mock = MockFailover()
        let counter = AttemptCounter()
        let attempt: @Sendable () async throws -> Date = { [counter] in
            await counter.increment()
            return Date()
        }
        await mock.setNextResult((serverName: "test-server", attempt: attempt))

        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: InstantReconnectClock()
        )
        await primeStableSession(watchdog)

        await watchdog.handleStatusChange(.disconnected, managerEnabled: true)
        // Wait until failover invoked (instant clock yields immediately).
        await waitUntil { await mock.getNextAttemptCalls() >= 1 }

        let calls = await mock.getNextAttemptCalls()
        XCTAssertEqual(calls, 1, "после debounce должен быть ровно 1 вызов")

        // attempt closure тоже должен быть выполнен.
        await waitUntil { await counter.get() >= 1 }
        let attemptCalls = await counter.get()
        XCTAssertEqual(attemptCalls, 1)
    }

    /// Test 3 — managerEnabled=false → НЕ fire failover (даже при stable session).
    func test_disconnectButManagerDisabled_noFailover() async {
        let mock = MockFailover()
        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: InstantReconnectClock()
        )
        await primeStableSession(watchdog)

        await watchdog.handleStatusChange(.disconnected, managerEnabled: false)
        for _ in 0..<200 { await Task.yield() }

        let calls = await mock.getNextAttemptCalls()
        XCTAssertEqual(calls, 0, "managerEnabled=false блокирует failover")
    }

    /// Test 4 — userIntent=false → НЕ fire failover (даже при stable session).
    func test_disconnectButNoUserIntent_noFailover() async {
        let mock = MockFailover()
        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: InstantReconnectClock()
        )
        // Прайм stable session чтобы потом сбросить только intent.
        await primeStableSession(watchdog)
        // Сбрасываем intent — stable session тоже сбрасывается (Round 2 contract).
        await watchdog.setUserIntent(false)
        // Возвращаем intent в true, но stable session остался false.
        // Чтобы реально проверить «intent=false блокирует» — оставим false:
        // в plan описании: «userIntent=false → reset». То есть .disconnected
        // c intent=false не должен запускать failover.

        await watchdog.handleStatusChange(.disconnected, managerEnabled: true)
        for _ in 0..<200 { await Task.yield() }

        let calls = await mock.getNextAttemptCalls()
        XCTAssertEqual(calls, 0, "userIntent=false блокирует failover")
    }

    /// Test 5 — debounce cancelled by .connecting.
    func test_debounceCancelledByReconnect() async {
        let mock = MockFailover()
        let counter = AttemptCounter()
        let attempt: @Sendable () async throws -> Date = { [counter] in
            await counter.increment()
            return Date()
        }
        await mock.setNextResult((serverName: "should-not-fire", attempt: attempt))

        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: PausingClock()
        )
        await primeStableSession(watchdog)

        await watchdog.handleStatusChange(.disconnected, managerEnabled: true)
        await waitUntil { await watchdog.getDebounceActiveForTest() }

        // Пока debounce активна, эмитим .connecting → должен отменить.
        await watchdog.handleStatusChange(.connecting, managerEnabled: true)
        for _ in 0..<200 { await Task.yield() }

        let calls = await mock.getNextAttemptCalls()
        XCTAssertEqual(calls, 0, ".connecting должен отменить debounce")
        let stillActive = await watchdog.getDebounceActiveForTest()
        XCTAssertFalse(stillActive, "debounceTask должен быть очищен")
    }

    /// Test 6 (NEW Round 2 W-05) — debounce cancelled by .reasserting.
    func test_debounceCancelledByReasserting() async {
        let mock = MockFailover()
        let counter = AttemptCounter()
        let attempt: @Sendable () async throws -> Date = { [counter] in
            await counter.increment()
            return Date()
        }
        await mock.setNextResult((serverName: "should-not-fire", attempt: attempt))

        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: PausingClock()
        )
        await primeStableSession(watchdog)

        await watchdog.handleStatusChange(.disconnected, managerEnabled: true)
        await waitUntil { await watchdog.getDebounceActiveForTest() }

        // W-05: .reasserting тоже должен отменить debounce (Round 1 не отменял).
        await watchdog.handleStatusChange(.reasserting, managerEnabled: true)
        for _ in 0..<200 { await Task.yield() }

        let calls = await mock.getNextAttemptCalls()
        XCTAssertEqual(calls, 0, "W-05: .reasserting должен отменить debounce")
        let stillActive = await watchdog.getDebounceActiveForTest()
        XCTAssertFalse(stillActive, "debounceTask должен быть очищен")
    }

    /// Test 7 — setUserIntent(false) сбрасывает stable session.
    func test_userIntentFalseResetsState() async {
        let mock = MockFailover()
        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: InstantReconnectClock()
        )
        await primeStableSession(watchdog)
        let before = await watchdog.getStableSessionForTest()
        XCTAssertTrue(before, "перед сбросом stableSession должен быть true")

        await watchdog.setUserIntent(false)

        let after = await watchdog.getStableSessionForTest()
        XCTAssertFalse(after, "userIntent=false должен сбросить stableSession")
    }

    /// Test 8 — nextResult == nil → nextAttempt вызывается, но attempt closure не выполняется.
    func test_failoverNextNil_noAttemptExecuted() async {
        let mock = MockFailover()
        // nextResult = nil (default).
        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: InstantReconnectClock()
        )
        await primeStableSession(watchdog)

        await watchdog.handleStatusChange(.disconnected, managerEnabled: true)
        await waitUntil { await mock.getNextAttemptCalls() >= 1 }

        let calls = await mock.getNextAttemptCalls()
        XCTAssertEqual(calls, 1, "nextServerAttempt должен быть вызван")
        // attempt closure не существует — нет crash, ничего не выполнилось.
    }

    /// Test 9 — non-nil attempt closure → выполняется.
    func test_failoverNextNonNil_attemptInvoked() async {
        let mock = MockFailover()
        let counter = AttemptCounter()
        let attempt: @Sendable () async throws -> Date = { [counter] in
            await counter.increment()
            return Date()
        }
        await mock.setNextResult((serverName: "next-server", attempt: attempt))

        let watchdog = TunnelWatchdog(
            failoverProvider: mock,
            clock: InstantReconnectClock()
        )
        await primeStableSession(watchdog)

        await watchdog.handleStatusChange(.disconnected, managerEnabled: true)
        await waitUntil { await counter.get() >= 1 }

        let attemptCalls = await counter.get()
        XCTAssertEqual(attemptCalls, 1, "attempt closure должен быть вызван 1 раз")
    }
}

/// Test-only clock — пауза по дефолту, чтобы тестам успеть проверить
/// `getDebounceActiveForTest() == true` до того как sleep завершится.
/// Sleep блокируется на CheckedContinuation, который никто не resume'ит —
/// debounceTask остаётся «in flight» пока его не cancel'ят.
private actor PausingClock: ReconnectClock {
    func sleep(seconds: Int) async throws {
        // Используем CancellationError-aware sleep: ждём cancellation вместо
        // реального wall-clock интервала.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // Этот continuation никогда не resume'ится; cancellation бросает
            // CancellationError автоматически через Task.checkCancellation
            // (но withCheckedContinuation не пропускает throw — поэтому делаем
            // post-check после resume).
            // Альтернатива — Task.sleep с большим интервалом и cancellation
            // throw'ет CancellationError. Используем простой long Task.sleep:
            Task {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)  // 60s
                    cont.resume()
                } catch {
                    cont.resume()
                }
            }
        }
        try Task.checkCancellation()
    }
}
