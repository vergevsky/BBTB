// TunnelController.swift — Phase 6 / Plan 06-05 / Wave 5.
//
// Promoted Phase 1-5 stateless wrapper to a full `actor` with reachability
// monitoring, NEVPNStatusDidChange + macOS NSWorkspace.didWakeNotification
// observers, and the auto-reconnect state machine. Preserves Phase 1-5
// `connect()` / `disconnect()` contracts verbatim (same polling loops, same
// timeouts) — Wave 5 adds the new methods alongside.
//
// Reference: `.planning/phases/06-network-resilience/06-RESEARCH.md` §10 +
// `.planning/phases/06-network-resilience/06-CONTEXT.md` D-07/D-08.
//
// Key Wave-5 changes:
// - `actor TunnelController` replaces `final class … @unchecked Sendable`.
// - `manualDisconnectInProgress` flag (Pitfall 3) prevents disconnect-vs-reconnect race.
// - `startReachability()` wires NetworkReachability + NEVPNStatusDidChange +
//   (macOS) NSWorkspace.didWakeNotification (NOT NotificationCenter.default —
//   RESEARCH §5 gotcha + Pitfall 10).
// - `handleForeground()` is a cheap no-op except for the narrow case where
//   the user un-locked the device and the tunnel needs nudging
//   (RESEARCH §14 Pitfall 8).
// - `triggerRecoveryIfNeeded` invokes the ReconnectStateMachine; failover stub
//   (NoFailoverProvider) lives here for Wave 5 and is replaced in Wave 6.

import Foundation
import NetworkExtension
import OSLog

#if os(macOS)
import AppKit
#endif

public protocol TunnelControlling: AnyObject, Sendable {
    func connect() async throws -> Date
    func disconnect() async throws
    /// Phase 6 — main-app starts reachability + observers + reconnect machine.
    func startReachability() async
    func stopReachability() async
    /// Phase 6 — iOS scenePhase = .active hook. macOS uses NSWorkspace.didWakeNotification
    /// internally; this method is cheap on both platforms.
    func handleForeground() async
}

// MARK: - Injection seams (testability)

/// Phase 6 — abstracts `NETunnelProviderManager.loadAllFromPreferences().first?.connection.status`
/// so tests can drive the status path without entitlement-gated NetworkExtension calls.
public protocol VPNStatusProviding: Sendable {
    func currentStatus() async -> NEVPNStatus
}

/// Default impl — production uses this; tests inject fakes.
public struct DefaultVPNStatusProvider: VPNStatusProviding {
    public init() {}
    public func currentStatus() async -> NEVPNStatus {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        return managers.first?.connection.status ?? .invalid
    }
}

/// Phase 6 — Wave 5 stubs failover (always returns nil); Wave 6 replaces with
/// SwiftData-backed FailoverProvider over the supported-server list.
public protocol FailoverProviding: Sendable {
    /// Returns the next-server attempt closure, or nil when the cycle is exhausted.
    func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)?
    /// Resets the failover cursor — call after a stable 30s+ session (D-08).
    func resetCycle() async
}

/// Wave 5 default — no failover. Wave 6 replaces.
public struct NoFailoverProvider: FailoverProviding {
    public init() {}
    public func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)? {
        return nil
    }
    public func resetCycle() async {}
}

/// Phase 6 / Wave 5 — relay box for the ReconnectStateMachine observer.
/// `TunnelController.init` requires the observer at construction time, but
/// `MainScreenViewModel` (which provides the observer) needs a constructed
/// `TunnelController` to exist. The relay breaks the cycle: app code creates
/// the relay (empty), passes it to TunnelController, constructs VM, then
/// calls `relay.set(observer:)` with VM-built observer.
public final class ReconnectStateObserverRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var observer: ReconnectStateMachine.StateObserver?

    public init() {}

    public func set(observer: @escaping ReconnectStateMachine.StateObserver) {
        lock.lock(); defer { lock.unlock() }
        self.observer = observer
    }

    public func makeStateObserver() -> ReconnectStateMachine.StateObserver {
        let weakSelf = self
        return { state in
            weakSelf.lock.lock()
            let obs = weakSelf.observer
            weakSelf.lock.unlock()
            obs?(state)
        }
    }
}

// MARK: - TunnelController

public actor TunnelController: TunnelControlling {

    // MARK: Dependencies

    private let reachability: NetworkReachability
    private let stateMachine: ReconnectStateMachine
    private let statusProvider: VPNStatusProviding
    /// Phase 6 / Wave 6 — failover provider is `var` because Wave 6 wiring
    /// uses a two-phase init pattern: app code constructs `TunnelController`
    /// first (with `NoFailoverProvider`), then constructs the real
    /// `SwiftDataFailoverProvider` (which needs `[weak controller]` to break
    /// the cycle), then calls `setFailoverProvider(_:)`.
    private var failoverProvider: FailoverProviding
    /// Phase 6 / Wave 6 — clock used for the 30s stable-session reset task.
    /// Stored separately from `stateMachine`'s clock so tests can inject a
    /// fake clock and verify `resetCycle()` fires after the timeout.
    private let reconnectClock: ReconnectClock
    private let log = Logger(subsystem: "app.bbtb.client", category: "tunnel-controller")

    // MARK: Phase 6 state

    /// Pitfall 3 — set true at the start of `disconnect()`, cleared 1s after .disconnected.
    /// `handleStatusChange` checks this before triggering recovery.
    internal var manualDisconnectInProgress: Bool = false

    /// D-08 / Pitfall 4 — timestamp of last `.connected` transition.
    /// Wave 6 will use this to gate failover-cursor reset after a 30s stable session.
    internal var lastSuccessfulConnectAt: Date?

    /// macOS wake handshake: NSWorkspace.didWake fires before the network is
    /// ready; we set this flag and let the next NetworkReachability.satisfied
    /// event consume it (Pitfall 10).
    private var wakePending: Bool = false

    private var nevpnObserver: NSObjectProtocol?
    #if os(macOS)
    private var wakeObserver: Any?
    #endif
    private var reachabilityStarted: Bool = false

    // MARK: Init

    public init(
        reachability: NetworkReachability = NetworkReachability(),
        statusProvider: VPNStatusProviding = DefaultVPNStatusProvider(),
        failoverProvider: FailoverProviding = NoFailoverProvider(),
        reconnectClock: ReconnectClock = SystemReconnectClock(),
        stateObserver: ReconnectStateMachine.StateObserver? = nil
    ) {
        self.reachability = reachability
        self.statusProvider = statusProvider
        self.failoverProvider = failoverProvider
        self.reconnectClock = reconnectClock
        self.stateMachine = ReconnectStateMachine(clock: reconnectClock, observer: stateObserver)
    }

    /// Phase 6 / Wave 6 — late-binding setter for the real failover provider.
    /// App code constructs `TunnelController` with the default `NoFailoverProvider`,
    /// then constructs `SwiftDataFailoverProvider` (which captures `[weak self]`
    /// of TunnelController in its `connect` closure to break the cycle), then
    /// calls this to swap the active provider.
    public func setFailoverProvider(_ provider: FailoverProviding) {
        self.failoverProvider = provider
    }

    // MARK: Phase 1-5 connect/disconnect (preserved)

    public func connect() async throws -> Date {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            throw NSError(domain: "BBTB.TunnelController", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No VPN profile — import config first"])
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()

        // Поллим до .connected или terminal error.
        // .disconnecting — transient (предыдущий туннель ещё гасится при reconnect) → continue.
        // .invalid / .disconnected — terminal failure → throw.
        let started = Date()
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            switch manager.connection.status {
            case .connected: return started
            case .invalid, .disconnected:
                throw NSError(domain: "BBTB.TunnelController", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Connection failed (status: \(manager.connection.status.rawValue))"])
            default: continue
            }
        }
        throw NSError(domain: "BBTB.TunnelController", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "Connection timed out after 30s"])
    }

    public func disconnect() async throws {
        // Pitfall 3 — set BEFORE issuing stop so handleStatusChange ignores
        // the .disconnected status that follows.
        manualDisconnectInProgress = true

        // D-08 Wave 6 — manual disconnect resets the failover cursor so the
        // next user-initiated connect starts from the originally-selected
        // server (no leftover round-robin state).
        await failoverProvider.resetCycle()

        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            scheduleClearManualDisconnect()
            return
        }
        let status = manager.connection.status
        guard status != .disconnected, status != .invalid else {
            scheduleClearManualDisconnect()
            return
        }
        manager.connection.stopVPNTunnel()
        // Wait for OS to actually bring the tunnel down (max 5s) before returning,
        // so a subsequent connect() doesn't race against a still-disconnecting tunnel.
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let s = manager.connection.status
            if s == .disconnected || s == .invalid {
                scheduleClearManualDisconnect()
                return
            }
        }
        scheduleClearManualDisconnect()
    }

    /// Pitfall 3 — schedule clearing the flag 1s after a `.disconnected` so any
    /// transient NEVPNStatusDidChange callbacks during the teardown window
    /// don't trigger reconnect.
    private func scheduleClearManualDisconnect() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.clearManualDisconnect()
        }
    }

    internal func clearManualDisconnect() {
        manualDisconnectInProgress = false
    }

    // MARK: Phase 6 — reachability + observers

    /// Start the live reachability + NEVPN status observer + (macOS) wake observer.
    /// Idempotent — repeated calls are a no-op.
    public func startReachability() async {
        guard !reachabilityStarted else { return }
        reachabilityStarted = true

        // NetworkReachability is an actor — closure hops back to self via Task.
        await reachability.start { [weak self] event in
            Task { [weak self] in
                await self?.handleReachability(event)
            }
        }

        // NEVPNStatusDidChange — first-class status observable.
        nevpnObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleStatusChangeNotification()
            }
        }

        #if os(macOS)
        // RESEARCH §5 / Pitfall 10 — NSWorkspace.shared.notificationCenter
        // (NOT NotificationCenter.default — wake events are only posted to
        // the workspace notification center).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleWake()
            }
        }
        #endif

        log.notice("TunnelController.startReachability — observers active")
    }

    /// Tear down reachability + observers (call on app termination if at all).
    public func stopReachability() async {
        if reachabilityStarted {
            await reachability.stop()
            reachabilityStarted = false
        }
        if let obs = nevpnObserver {
            NotificationCenter.default.removeObserver(obs)
            nevpnObserver = nil
        }
        #if os(macOS)
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        #endif
        log.notice("TunnelController.stopReachability — observers removed")
    }

    /// iOS scenePhase = .active hook. Pitfall 8 — must be a cheap no-op except
    /// for the narrow case where we want to do real recovery work. Currently
    /// we trust NEVPNStatusDidChange + NetworkReachability to cover the
    /// interesting cases; this method just early-returns.
    public func handleForeground() async {
        // Pitfall 8 — scenePhase = .active fires on every screen unlock. Do NOT
        // start the state machine here unconditionally. The NEVPNStatusDidChange
        // observer already kicks the cycle off when the tunnel actually drops.
        guard !manualDisconnectInProgress else { return }
        // Read status as a smoke check (cheap). If anything looks live, no-op.
        _ = await statusProvider.currentStatus()
    }

    // MARK: Phase 6 — internal event handlers

    /// macOS wake handshake — defer reconnect until network is ready (Pitfall 10).
    #if os(macOS)
    private func handleWake() async {
        wakePending = true
        log.notice("TunnelController.handleWake — wakePending set; awaiting reachability.satisfied")
    }
    #endif

    private func handleReachability(_ event: NetworkReachabilityEvent) async {
        switch event {
        case .satisfied:
            if wakePending {
                wakePending = false
                await triggerRecoveryIfNeeded(reason: "wake+reachable")
            } else {
                await triggerRecoveryIfNeeded(reason: "network-satisfied")
            }
        case .changed:
            await triggerRecoveryIfNeeded(reason: "network-changed")
        case .unsatisfied:
            // Don't preemptively tear down; let kill switch hold the line.
            log.notice("reachability: unsatisfied — holding")
            break
        }
    }

    private func handleStatusChangeNotification() async {
        let status = await statusProvider.currentStatus()
        await handleStatusChange(status)
    }

    /// Internal (testable) seam — pure logic based on status + manualDisconnect flag.
    internal func handleStatusChange(_ status: NEVPNStatus) async {
        switch status {
        case .connected:
            let now = Date()
            lastSuccessfulConnectAt = now
            await stateMachine.reportConnected()
            // D-08 / Pitfall 4 (Wave 6) — schedule failover-cursor reset after
            // 30s of stable .connected session. The `startedAt` guard prevents
            // a stale task from resetting the cursor if a disconnect+reconnect
            // happened within the 30s window (which would update
            // lastSuccessfulConnectAt to a fresher Date, so the stale task's
            // captured `now` no longer matches).
            Task { [weak self] in
                await self?.scheduleFailoverResetAfterStableSession(startedAt: now)
            }
        case .disconnected:
            guard !manualDisconnectInProgress else {
                log.notice("status .disconnected during manualDisconnect — ignoring")
                return
            }
            await triggerRecoveryIfNeeded(reason: "status-disconnected")
        default:
            break
        }
    }

    /// D-08 / Pitfall 4 — sleeps 30s, then resets the failover cursor IFF the
    /// tunnel is still `.connected` AND `lastSuccessfulConnectAt == startedAt`
    /// (proving no disconnect+reconnect happened in the meantime).
    ///
    /// Marked `internal` so tests can invoke directly with a custom timestamp.
    internal func scheduleFailoverResetAfterStableSession(startedAt: Date) async {
        do {
            try await reconnectClock.sleep(seconds: 30)
        } catch {
            return  // cancelled — abort
        }
        // Race guard: if a disconnect happened mid-sleep and a new connect
        // produced a fresh timestamp, our `startedAt` is stale → bail.
        guard lastSuccessfulConnectAt == startedAt else {
            log.notice("stable-session reset skipped — startedAt stale")
            return
        }
        let currentStatus = await statusProvider.currentStatus()
        guard currentStatus == .connected else {
            log.notice("stable-session reset skipped — status=\(currentStatus.rawValue, privacy: .public)")
            return
        }
        log.notice("stable-session reset firing — 30s+ connected, resetting failover cycle")
        await failoverProvider.resetCycle()
    }

    private func triggerRecoveryIfNeeded(reason: String) async {
        // Skip if we're already connected (e.g. simultaneous .satisfied during a
        // healthy session — let the kernel handle it).
        let currentStatus = await statusProvider.currentStatus()
        guard currentStatus != .connected else {
            log.notice("triggerRecovery skipped (already connected) — reason=\(reason, privacy: .public)")
            return
        }
        log.notice("triggerRecovery starting — reason=\(reason, privacy: .public)")

        let failover = self.failoverProvider
        let override = self.firstAttemptOverrideForTest
        await stateMachine.run(
            firstAttempt: { [weak self] in
                if let override {
                    return try await override()
                }
                guard let self else { throw CancellationError() }
                return try await self.connect()
            },
            failoverNext: {
                await failover.nextServerAttempt()
            }
        )
    }

    // MARK: - Internal test seams

    /// Test-only seam (Wave 6 Task 2 / Test 11). When non-nil, replaces the
    /// `self.connect()` closure passed to `ReconnectStateMachine.run`. Tests
    /// drive the failover wiring without paying the cost of real
    /// `NETunnelProviderManager.loadAllFromPreferences()` round-trips per
    /// attempt — which in xctest env take real wall-clock seconds and make the
    /// otherwise-deterministic state machine flaky.
    internal var firstAttemptOverrideForTest: (@Sendable () async throws -> Date)?

    internal func setFirstAttemptOverrideForTest(_ closure: (@Sendable () async throws -> Date)?) {
        self.firstAttemptOverrideForTest = closure
    }

    internal func isManualDisconnectInProgress() -> Bool { manualDisconnectInProgress }
    internal func _setManualDisconnectForTest(_ value: Bool) {
        manualDisconnectInProgress = value
    }
    internal func getLastSuccessfulConnectAt() -> Date? { lastSuccessfulConnectAt }
    internal func isReachabilityStartedForTest() -> Bool { reachabilityStarted }
}
