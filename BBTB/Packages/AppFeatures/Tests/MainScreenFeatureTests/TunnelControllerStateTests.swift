// TunnelControllerStateTests.swift — Phase 6 / Plan 06-05 / Wave 5 / Task 2.
//
// Tests the `TunnelController` actor's status-change wiring, manual-disconnect
// race fix (Pitfall 3), idempotent reachability startup, and the cheap
// foreground hook (Pitfall 8).
//
// Live NEVPNStatusDidChange notifications require a real NETunnelProviderManager
// (entitlement-gated), so tests drive the actor's status path through the
// internal `handleStatusChange(_:)` seam combined with a fake `VPNStatusProviding`.

import XCTest
import NetworkExtension
@testable import MainScreenFeature

final class TunnelControllerStateTests: XCTestCase {

    // MARK: - Test doubles

    /// Records invocations of `ReconnectStateMachine`-equivalent hooks.
    /// `TunnelController.triggerRecoveryIfNeeded` actually invokes the real
    /// ReconnectStateMachine; we observe through `StateRecorder` to detect that
    /// the cycle started without burning a real attempt.
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

    /// Sendable status holder for the fake `VPNStatusProviding`.
    final class StatusBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: NEVPNStatus = .invalid
        func set(_ s: NEVPNStatus) {
            lock.lock(); defer { lock.unlock() }
            value = s
        }
        func get() -> NEVPNStatus {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    final class FakeStatusProvider: VPNStatusProviding, @unchecked Sendable {
        let box: StatusBox
        init(box: StatusBox) { self.box = box }
        func currentStatus() async -> NEVPNStatus { box.get() }
    }

    /// Test clock — yields immediately so cycle starts but doesn't burn time.
    actor InstantReconnectClock: ReconnectClock {
        func sleep(seconds: Int) async throws {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    /// Tunnel-controlling protocol stub that throws on connect (so the state
    /// machine sees a failure, increments attempt count without succeeding —
    /// enough to assert the cycle was started).
    final class FailingTunnelControl: @unchecked Sendable {
        nonisolated func connect() async throws -> Date {
            throw NSError(domain: "Test", code: 1, userInfo: nil)
        }
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

    /// Build a controller with injected fake dependencies. The connect/disconnect
    /// paths still go through `NETunnelProviderManager.loadAllFromPreferences()`
    /// — but we never call them in these tests; we exercise the internal
    /// `handleStatusChange(_:)` + `handleForeground()` seams directly.
    ///
    /// Defaults to an isolated `UserIntentStore` so tests cannot pollute
    /// each other through the persisted `userIntendedConnected` flag.
    private func makeController(
        statusBox: StatusBox = StatusBox(),
        recorder: StateRecorder = StateRecorder(),
        intentStore: UserIntentStore? = nil
    ) -> (TunnelController, StatusBox, StateRecorder) {
        let provider = FakeStatusProvider(box: statusBox)
        let observer: ReconnectStateMachine.StateObserver = { state in
            recorder.append(state)
        }
        let store = intentStore ?? Self.makeIsolatedIntentStore()
        let controller = TunnelController(
            reachability: NetworkReachability(),
            statusProvider: provider,
            failoverProvider: NoFailoverProvider(),
            reconnectClock: InstantReconnectClock(),
            stateObserver: observer,
            intentStore: store
        )
        return (controller, statusBox, recorder)
    }

    /// Per-test isolated `UserIntentStore` — prevents cross-test leakage
    /// of the persisted `userIntendedConnected` flag.
    static func makeIsolatedIntentStore() -> UserIntentStore {
        let suiteName = "TunnelControllerStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserIntentStore(defaults: defaults)
    }

    // MARK: - Tests

    /// Test 1: After calling disconnect()-like setter, manualDisconnectInProgress is true.
    /// We can't invoke real disconnect() without a manager, so we test the
    /// internal mutator that disconnect() uses.
    func test_manualDisconnect_setsFlag() async throws {
        let (controller, _, _) = makeController()

        let before = await controller.isManualDisconnectInProgress()
        XCTAssertFalse(before)

        await controller._setManualDisconnectForTest(true)
        let after = await controller.isManualDisconnectInProgress()
        XCTAssertTrue(after)
    }

    /// Test 2: handleStatusChange(.disconnected) during manualDisconnect → no recovery.
    func test_handleStatusChange_ignoresDisconnectedDuringManualDisconnect() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)
        await controller._setManualDisconnectForTest(true)

        await controller.handleStatusChange(.disconnected)
        // Allow any spawned Task to run (none should be spawned, but yield just in case).
        for _ in 0..<10 { await Task.yield() }

        // State machine observer was never invoked with retrying/failover/allFailed.
        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            if case .failover = $0 { return true }
            if case .allFailed = $0 { return true }
            return false
        }), "Recovery should not start during manual disconnect; got \(states)")
    }

    /// Test 3: handleStatusChange(.disconnected) without manualDisconnect → recovery kicks off.
    ///
    /// Precondition: user must have previously consented to a tunnel session
    /// (`userIntendedConnected == true`). Phase 6 UAT 2026-05-13 added that
    /// guard to block auto-reconnect from firing on fresh installs / right
    /// after `provisionTunnelProfile` (saveToPreferences emits
    /// NEVPNStatusDidChange with `.disconnected`). The realistic precursor
    /// is a successful `connect()` — we simulate it with the test seam.
    func test_handleStatusChange_triggersRecoveryOnUnexpectedDisconnect() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)
        await controller._setUserIntendedConnectedForTest(true)

        await controller.handleStatusChange(.disconnected)
        // Give the state machine task a few yields to publish .retrying(1, 2).
        await waitUntil { recorder.snapshot().contains(where: {
            if case .retrying = $0 { return true }
            return false
        }) }

        let states = recorder.snapshot()
        XCTAssertTrue(states.contains(where: {
            if case .retrying = $0 { return true }
            return false
        }), "Expected .retrying in observer states; got \(states)")

        await controller.stopReachability()  // cleanup
    }

    /// Test 3b (fresh-install regression): when status is `.invalid` (no
    /// NETunnelProviderManager installed — the DefaultVPNStatusProvider returns
    /// `.invalid` if `loadAllFromPreferences()` is empty), reachability events
    /// must NOT start the reconnect state machine. Otherwise the user sees
    /// a phantom retry banner + .allFailed notification on a pristine install
    /// where there is literally no profile to connect to.
    ///
    /// Phase 6 / Wave 6 follow-up — reported during UAT prep 2026-05-13.
    func test_triggerRecovery_skipsOnInvalidStatus_freshInstall() async throws {
        let statusBox = StatusBox()
        statusBox.set(.invalid)  // No VPN profile installed
        let (controller, _, recorder) = makeController(statusBox: statusBox)
        // Pretend user has consented to a session, so the only reason
        // recovery should skip is the `.invalid` status — otherwise the
        // userIntendedConnected guard would silently absorb this test.
        await controller._setUserIntendedConnectedForTest(true)

        // Simulate the reachability `.satisfied` path that fires on app launch.
        // `triggerRecoveryIfNeeded` is `internal` for tests; production calls
        // it from `handleReachability(_:)`.
        await controller.triggerRecoveryIfNeeded(reason: "test-fresh-install")

        // Give any spuriously-spawned state machine task generous time to publish
        // a state — none should appear if the guard is working.
        for _ in 0..<200 { await Task.yield() }

        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            if case .failover = $0 { return true }
            if case .allFailed = $0 { return true }
            return false
        }), "Fresh install (.invalid status) must not trigger recovery; got \(states)")
    }

    /// Test 4: handleStatusChange(.connected) → cancels machine (reportConnected) + updates lastSuccessfulConnectAt.
    func test_handleStatusChange_onConnected_updatesLastConnectAndReports() async throws {
        let statusBox = StatusBox()
        statusBox.set(.connected)
        let (controller, _, _) = makeController(statusBox: statusBox)

        let beforeDate = await controller.getLastSuccessfulConnectAt()
        XCTAssertNil(beforeDate)

        await controller.handleStatusChange(.connected)

        let afterDate = await controller.getLastSuccessfulConnectAt()
        XCTAssertNotNil(afterDate)
    }

    /// Test 5: startReachability is idempotent.
    func test_startReachability_isIdempotent() async throws {
        let (controller, _, _) = makeController()
        await controller.startReachability()
        await controller.startReachability()  // second call — no-op (no crash, no duplicate observer)

        // We can only assert it didn't crash and that the started flag is set.
        let started = await controller.isReachabilityStartedForTest()
        XCTAssertTrue(started)

        await controller.stopReachability()
    }

    /// Test 6: handleForeground while .disconnected → no-op (Pitfall 8).
    func test_handleForeground_disconnected_noOp() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)

        await controller.handleForeground()
        for _ in 0..<10 { await Task.yield() }

        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            return false
        }), "handleForeground must not start recovery on .disconnected; got \(states)")
    }

    /// Test 7: handleForeground while .connected → no-op (Pitfall 8).
    func test_handleForeground_connected_noOp() async throws {
        let statusBox = StatusBox()
        statusBox.set(.connected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)

        await controller.handleForeground()
        for _ in 0..<10 { await Task.yield() }

        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            return false
        }), "handleForeground must be a cheap no-op when connected; got \(states)")
    }

    // MARK: - Wave 6 — Failover wiring

    /// Spy FailoverProvider — records resetCycle/nextServerAttempt calls.
    actor SpyFailoverProvider: FailoverProviding {
        var resetCount = 0
        var nextCount = 0
        /// If non-nil, `nextServerAttempt()` returns this tuple. Tests use this
        /// to simulate "failover available" without driving real state machine.
        var stub: (serverName: String, attempt: @Sendable () async throws -> Date)?

        func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)? {
            nextCount += 1
            return stub
        }
        func resetCycle() async {
            resetCount += 1
        }
        func getResetCount() -> Int { resetCount }
        func getNextCount() -> Int { nextCount }
    }

    /// Recordable clock — captures `sleep(seconds:)` invocations. Yields
    /// immediately, optionally awaits a `continuation` to allow tests to gate
    /// when the post-sleep code runs.
    actor RecordingClock: ReconnectClock {
        var sleeps: [Int] = []
        var sleepCount = 0
        var paused = false
        private var continuation: CheckedContinuation<Void, Never>?

        func sleep(seconds: Int) async throws {
            sleeps.append(seconds)
            sleepCount += 1
            if paused {
                await withCheckedContinuation { cont in
                    self.continuation = cont
                }
            }
        }

        func setPaused(_ v: Bool) { paused = v }
        func resume() {
            continuation?.resume()
            continuation = nil
        }
        func snapshotSleeps() -> [Int] { sleeps }
        func getSleepCount() -> Int { sleepCount }
    }

    /// Test 8 (Wave 6): manual disconnect resets the failover cycle.
    ///
    /// We exercise disconnect()'s `failoverProvider.resetCycle()` call. The
    /// real disconnect path requires a NETunnelProviderManager (entitlement-
    /// gated); however the first thing disconnect() does after setting
    /// manualDisconnectInProgress is the resetCycle() call. We can't run the
    /// full disconnect, but we test the same observable effect via the
    /// internal `_setManualDisconnectForTest(_:)` + invoking the helper that
    /// disconnect() uses. Since disconnect() also calls
    /// `failoverProvider.resetCycle()`, the cleanest test is a smoke test
    /// that invokes disconnect() and tolerates the NetworkExtension failure
    /// — what we assert is that resetCycle was called before the NE error
    /// propagated.
    func test_manualDisconnect_resetsFailoverCycle() async throws {
        let spy = SpyFailoverProvider()
        let controller = TunnelController(
            reachability: NetworkReachability(),
            statusProvider: FakeStatusProvider(box: StatusBox()),
            failoverProvider: spy,
            reconnectClock: InstantReconnectClock(),
            stateObserver: nil,
            intentStore: Self.makeIsolatedIntentStore()
        )
        // disconnect() will likely throw (no NEManager) — that's fine;
        // resetCycle() runs BEFORE NETunnelProviderManager.loadAllFromPreferences.
        _ = try? await controller.disconnect()

        let count = await spy.getResetCount()
        XCTAssertEqual(count, 1, "disconnect() must call failoverProvider.resetCycle() exactly once")
    }

    /// Test 9 (Wave 6): handleStatusChange(.connected) schedules a 30s-deferred
    /// resetCycle. Using a paused RecordingClock, we assert the sleep was
    /// scheduled with 30s and that resetCycle fires only after we resume.
    func test_handleStatusChange_connected_schedules_30s_reset() async throws {
        let spy = SpyFailoverProvider()
        let clock = RecordingClock()
        await clock.setPaused(true)

        let statusBox = StatusBox()
        statusBox.set(.connected)
        let controller = TunnelController(
            reachability: NetworkReachability(),
            statusProvider: FakeStatusProvider(box: statusBox),
            failoverProvider: spy,
            reconnectClock: clock,
            stateObserver: nil,
            intentStore: Self.makeIsolatedIntentStore()
        )

        await controller.handleStatusChange(.connected)

        // Wait for the scheduled Task to actually call clock.sleep(seconds: 30).
        // The Task body is `await self?.scheduleFailoverResetAfterStableSession(...)`
        // → enters sleep → blocks on continuation.
        await waitUntil(iterations: 5_000) {
            await clock.getSleepCount() >= 1
        }
        let sleeps = await clock.snapshotSleeps()
        XCTAssertEqual(sleeps.first, 30, "stable-session reset must sleep 30s")
        let earlyResets = await spy.getResetCount()
        XCTAssertEqual(earlyResets, 0, "resetCycle must NOT fire before the 30s sleep completes")

        // Resume the clock → post-sleep code runs → resetCycle should be called.
        await clock.resume()

        await waitUntil(iterations: 5_000) {
            await spy.getResetCount() >= 1
        }
        let resets = await spy.getResetCount()
        XCTAssertEqual(resets, 1, "resetCycle must fire after 30s+ stable .connected")
    }

    /// Test 10 (Wave 6): if status leaves .connected before the 30s timer fires,
    /// resetCycle is NOT called.
    ///
    /// Implementation: drive .connected → status flips to .disconnected before
    /// the clock resumes. After resume, `scheduleFailoverResetAfterStableSession`
    /// observes the non-connected status and skips the reset.
    func test_handleStatusChange_connectedThenDisconnected_doesNotReset() async throws {
        let spy = SpyFailoverProvider()
        let clock = RecordingClock()
        await clock.setPaused(true)

        let statusBox = StatusBox()
        statusBox.set(.connected)
        let controller = TunnelController(
            reachability: NetworkReachability(),
            statusProvider: FakeStatusProvider(box: statusBox),
            failoverProvider: spy,
            reconnectClock: clock,
            stateObserver: nil,
            intentStore: Self.makeIsolatedIntentStore()
        )

        await controller.handleStatusChange(.connected)
        await waitUntil(iterations: 5_000) {
            await clock.getSleepCount() >= 1
        }

        // Flip status to .disconnected before the 30s sleep completes.
        statusBox.set(.disconnected)
        await clock.resume()

        // Give the scheduled Task time to wake up and observe the new status.
        for _ in 0..<200 { await Task.yield() }

        let resets = await spy.getResetCount()
        XCTAssertEqual(resets, 0,
                       "resetCycle must NOT fire when status leaves .connected before 30s")
    }

    /// Test 11 (Wave 6): the failoverNext closure passed into the state machine
    /// calls failoverProvider.nextServerAttempt() when the 3-attempt budget is
    /// exhausted on the current server.
    ///
    /// Approach: trigger handleStatusChange(.disconnected) without
    /// manualDisconnect → triggerRecoveryIfNeeded fires → ReconnectStateMachine
    /// runs. We inject `firstAttemptOverrideForTest` with a closure that always
    /// throws (so all 3 attempts fail and the SM falls through to
    /// failoverNext). InstantReconnectClock yields immediately. The fake
    /// `currentStatus()` stays .disconnected throughout so triggerRecovery
    /// doesn't short-circuit.
    ///
    /// Why the override: in xctest env without entitlements,
    /// `NETunnelProviderManager.loadAllFromPreferences()` takes real wall-clock
    /// seconds per attempt — 3 attempts can blow past any reasonable test
    /// timeout. The override bypasses NE entirely; the wiring under test
    /// (triggerRecoveryIfNeeded → stateMachine.run → failoverNext = failover
    /// provider) still goes through every layer except the NE call itself.
    func test_allFailed_consults_failoverProvider() async throws {
        let spy = SpyFailoverProvider()
        // No stub → nextServerAttempt returns nil → SM transitions to .allFailed.

        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let recorder = StateRecorder()
        let observer: ReconnectStateMachine.StateObserver = { state in
            recorder.append(state)
        }
        let controller = TunnelController(
            reachability: NetworkReachability(),
            statusProvider: FakeStatusProvider(box: statusBox),
            failoverProvider: spy,
            reconnectClock: InstantReconnectClock(),
            stateObserver: observer,
            intentStore: Self.makeIsolatedIntentStore()
        )
        // Phase 6 UAT 2026-05-13 — userIntendedConnected guard requires a
        // prior user-initiated connect before recovery can fire. Simulate it.
        await controller._setUserIntendedConnectedForTest(true)
        // Inject a fast-failing attempt closure so all 3 SM attempts throw
        // immediately and the SM consults failoverNext.
        await controller.setFirstAttemptOverrideForTest({
            throw NSError(domain: "TestAttempt", code: 1, userInfo: nil)
        })

        await controller.handleStatusChange(.disconnected)

        // Wait until SM has consulted the failover provider (.allFailed published).
        await waitUntil(iterations: 5_000) {
            recorder.snapshot().contains(where: {
                if case .allFailed = $0 { return true }
                return false
            })
        }

        let count = await spy.getNextCount()
        XCTAssertGreaterThanOrEqual(count, 1,
                                    "After 3 attempts, SM must consult failoverProvider.nextServerAttempt at least once")
    }

    // MARK: - userIntendedConnected guard (Phase 6 UAT follow-up, 2026-05-13)

    /// Bug #2 from UAT — after `ConfigImporter.provisionTunnelProfile` calls
    /// `manager.saveToPreferences()`, iOS/macOS emits NEVPNStatusDidChange
    /// with `.disconnected`. Without the `userIntendedConnected` guard, this
    /// fired the reconnect state machine even though the user had not
    /// requested a connection yet. The guard must skip recovery whenever
    /// the flag is false.
    func test_triggerRecovery_skipsWhenUserHasNotIntendedConnect() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)  // Profile exists (e.g. just saved) but user did not tap connect.
        let (controller, _, recorder) = makeController(statusBox: statusBox)
        // userIntendedConnected defaults to false on a fresh isolated suite —
        // do NOT set it.

        await controller.triggerRecoveryIfNeeded(reason: "test-no-intent")
        for _ in 0..<200 { await Task.yield() }

        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            if case .failover = $0 { return true }
            if case .allFailed = $0 { return true }
            return false
        }), "Recovery must not fire when userIntendedConnected==false; got \(states)")
    }

    /// Bug #1 (post-fix variant) — same reachability `.satisfied` path that
    /// fires on app launch, but exercised through `handleStatusChange` to
    /// catch a separate code path. `.disconnected` + intent=false → no-op.
    func test_handleStatusChange_disconnected_skipsWhenUserHasNotIntendedConnect() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)

        await controller.handleStatusChange(.disconnected)
        for _ in 0..<200 { await Task.yield() }

        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            return false
        }), "saveToPreferences-style .disconnected must not auto-reconnect on fresh install; got \(states)")
    }

    /// `disconnect()` must clear the persisted intent flag so subsequent
    /// reachability events do not auto-reconnect. We invoke the real
    /// disconnect() — it'll throw because there's no NETunnelProviderManager,
    /// but the flag mutation happens BEFORE `loadAllFromPreferences()`.
    func test_disconnect_clearsUserIntendedConnected() async throws {
        let store = Self.makeIsolatedIntentStore()
        let (controller, _, _) = makeController(intentStore: store)
        await controller._setUserIntendedConnectedForTest(true)

        _ = try? await controller.disconnect()

        let intent = await controller.getUserIntendedConnectedForTest()
        XCTAssertFalse(intent, "disconnect() must clear userIntendedConnected before any failure point")
    }

    /// Bug #3 from UAT — `connect()` is already running; saveToPreferences in
    /// its preamble raises `NEVPNStatusDidChange` with `.disconnected`. The
    /// observer routes it into `triggerRecoveryIfNeeded`, where the
    /// `userIntendedConnected` flag is already true. Without the
    /// `connectInProgress` guard, the state machine would spawn a recursive
    /// `self.connect()` and race against the in-flight original — the manager
    /// status freezes at `.connecting` until 30s poll timeout.
    func test_triggerRecovery_skipsWhileConnectInProgress() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)
        await controller._setUserIntendedConnectedForTest(true)
        await controller._setConnectInProgressForTest(true)

        await controller.triggerRecoveryIfNeeded(reason: "test-connect-in-progress")
        for _ in 0..<200 { await Task.yield() }

        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            if case .failover = $0 { return true }
            if case .allFailed = $0 { return true }
            return false
        }), "Recovery must not fire while connect() is in progress; got \(states)")
    }

    /// Same flow as bug #3 but via `handleStatusChange` (the production entry
    /// point that NEVPNStatusDidChange observer feeds into).
    func test_handleStatusChange_disconnected_skipsWhileConnectInProgress() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)
        await controller._setUserIntendedConnectedForTest(true)
        await controller._setConnectInProgressForTest(true)

        await controller.handleStatusChange(.disconnected)
        for _ in 0..<200 { await Task.yield() }

        let states = recorder.snapshot()
        XCTAssertFalse(states.contains(where: {
            if case .retrying = $0 { return true }
            return false
        }), "saveToPreferences-style .disconnected during connect() must not fire recovery; got \(states)")
    }

    /// Intent persists across TunnelController instances — covers
    /// "app killed while connected → relaunch → tunnel still alive in OS →
    /// drops → must auto-reconnect" because in-memory state is lost.
    func test_userIntendedConnected_persistsAcrossControllerInstances() async throws {
        let store = Self.makeIsolatedIntentStore()
        let (controllerA, _, _) = makeController(intentStore: store)
        await controllerA._setUserIntendedConnectedForTest(true)

        let (controllerB, _, _) = makeController(intentStore: store)
        let intent = await controllerB.getUserIntendedConnectedForTest()
        XCTAssertTrue(intent, "userIntendedConnected must survive TunnelController re-construction (UserDefaults-backed)")
    }
}
