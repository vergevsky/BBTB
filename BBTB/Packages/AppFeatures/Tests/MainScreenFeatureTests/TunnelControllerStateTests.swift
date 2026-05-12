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
    private func makeController(
        statusBox: StatusBox = StatusBox(),
        recorder: StateRecorder = StateRecorder()
    ) -> (TunnelController, StatusBox, StateRecorder) {
        let provider = FakeStatusProvider(box: statusBox)
        let observer: ReconnectStateMachine.StateObserver = { state in
            recorder.append(state)
        }
        let controller = TunnelController(
            reachability: NetworkReachability(),
            statusProvider: provider,
            failoverProvider: NoFailoverProvider(),
            reconnectClock: InstantReconnectClock(),
            stateObserver: observer
        )
        return (controller, statusBox, recorder)
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
    func test_handleStatusChange_triggersRecoveryOnUnexpectedDisconnect() async throws {
        let statusBox = StatusBox()
        statusBox.set(.disconnected)
        let (controller, _, recorder) = makeController(statusBox: statusBox)

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
}
