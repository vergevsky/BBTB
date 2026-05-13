// TunnelController.swift — Phase 6c / Plan 06C-04 / Task 3a.
//
// Phase 6c: Apple's NEOnDemandRule owns reconnect; TunnelWatchdog owns
// mid-session failover (D-08/D-09); TunnelController is a thin command surface.
// NEVPNStatusDidChange observer only (a) forwards to watchdog with the real
// manager.isEnabled gate (B-03) and (b) closes intent on EXTERNAL .disconnected
// (Settings VPN-off, other-VPN takeover) per 06C-ARCHITECT-R5.md.
import Foundation
import NetworkExtension
import OSLog
import os.signpost
#if os(macOS)
import AppKit
#endif

public protocol TunnelControlling: AnyObject, Sendable {
    func connect() async throws -> Date
    func disconnect() async throws
    func startReachability() async
    func stopReachability() async
    func handleForeground() async
}

// MARK: - Injection seams

public protocol VPNStatusProviding: Sendable {
    func currentStatus() async -> NEVPNStatus
}

public struct DefaultVPNStatusProvider: VPNStatusProviding {
    public init() {}
    public func currentStatus() async -> NEVPNStatus {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        return managers.first?.connection.status ?? .invalid
    }
}

/// Sendable wrapper around UserDefaults for `userIntendedConnected`.
public final class UserIntentStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard,
                key: String = "app.bbtb.userIntendedConnected") {
        self.defaults = defaults
        self.key = key
    }
    public func load() -> Bool { defaults.object(forKey: key) as? Bool ?? false }
    public func save(_ value: Bool) { defaults.set(value, forKey: key) }
}

/// Wave 5 default `NoFailoverProvider`; Wave 6 swaps via `setFailoverProvider(_:)`.
public protocol FailoverProviding: Sendable {
    func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)?
    /// Resets the failover cursor — called after a 30s+ stable session (D-08).
    func resetCycle() async
}

public struct NoFailoverProvider: FailoverProviding {
    public init() {}
    public func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)? { nil }
    public func resetCycle() async {}
}

// MARK: - TunnelController

public actor TunnelController: TunnelControlling {

    private let statusProvider: VPNStatusProviding
    private var failoverProvider: FailoverProviding
    private let log = Logger(subsystem: "app.bbtb.client", category: "tunnel-controller")

    // Round 5 carve-out — flags survive as gates for the intent-closing path.
    // Transient .disconnected raised by our own saveToPreferences/stopVPNTunnel
    // would otherwise close intent during our own flow.
    internal var manualDisconnectInProgress: Bool = false
    internal var connectInProgress: Bool = false

    /// "User wants tunnel on", persisted. Phase 6c = active-session window
    /// opened by Connect, closed by Disconnect OR external disable. Feeds
    /// OnDemandRulesBuilder.applyCurrentState.
    internal var userIntendedConnected: Bool

    private var nevpnObserver: NSObjectProtocol?
    #if os(macOS)
    private var wakeObserver: Any?
    #endif
    private var reachabilityStarted: Bool = false
    private let intentStore: UserIntentStore

    /// TunnelWatchdog (D-08/D-09) — late-binding setter mirror of failoverProvider.
    private var watchdog: TunnelWatchdog?

    /// Cached manager — real isEnabled gate for watchdog (B-03) and intent-closing.
    /// false when (a) другой VPN активирован or (b) profile disabled в Settings.
    /// Refreshed on every `.bbtbProvisionerDidSave` + initial seed in startReachability.
    private var cachedManager: NETunnelProviderManager?
    private var provisionerObserver: NSObjectProtocol?

    public init(
        statusProvider: VPNStatusProviding = DefaultVPNStatusProvider(),
        failoverProvider: FailoverProviding = NoFailoverProvider(),
        intentStore: UserIntentStore = UserIntentStore()
    ) {
        self.statusProvider = statusProvider
        self.failoverProvider = failoverProvider
        self.intentStore = intentStore
        self.userIntendedConnected = intentStore.load()
    }

    private func setUserIntendedConnected(_ value: Bool) {
        userIntendedConnected = value
        intentStore.save(value)
    }

    public func setFailoverProvider(_ provider: FailoverProviding) { self.failoverProvider = provider }
    public func setWatchdog(_ watchdog: TunnelWatchdog) { self.watchdog = watchdog }

    /// B-06 multi-manager filter. Transient XPC failure → graceful degradation.
    private func refreshCachedManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            cachedManager = ManagerSelector.ourManagers(from: managers).first
            log.debug("TunnelController cachedManager refreshed (nil=\(self.cachedManager == nil, privacy: .public))")
        } catch {
            log.warning("TunnelController.refreshCachedManager failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// B-04 + N-01 + MINOR-01: apply OnDemandRulesBuilder.applyCurrentState
    /// (isOnDemandEnabled = toggle && intent) + save + reload, so intent flips
    /// propagate immediately. Load-on-demand if cachedManager nil (race на
    /// первый запуск). Never throws — intent already persisted.
    ///
    /// Phase 6d Wave 02a — instrumented with `ProvisionProfile` span
    /// (saveToPreferences + loadFromPreferences are the expensive XPC ops).
    private func applyCurrentStateToCachedManager() async {
        let provisionID = PerfSignposter.client.makeSignpostID()
        let provisionState = PerfSignposter.client.beginInterval("ProvisionProfile", id: provisionID)
        defer { PerfSignposter.client.endInterval("ProvisionProfile", provisionState) }

        if cachedManager == nil { await refreshCachedManager() }
        guard let manager = cachedManager else {
            log.warning("applyCurrentStateToCachedManager — no manager available even after refresh; skipping.")
            return
        }
        OnDemandRulesBuilder.applyCurrentState(to: manager)
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()  // RESEARCH §9.1
        } catch {
            log.warning("applyCurrentStateToCachedManager save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: connect/disconnect (PRESERVED VERBATIM from Phase 6)

    public func connect() async throws -> Date {
        // Phase 6d Wave 02a — `ConnectTap` outer span обёртывает весь connect
        // flow (intent + provision + probe + startVPNTunnel + poll). Nested:
        // `ProvisionProfile` (inside applyCurrentStateToCachedManager) +
        // `PreConnectProbe` (XPC loadAllFromPreferences below). Instrumentation
        // only — никаких изменений в семантике flow.
        let connectID = PerfSignposter.client.makeSignpostID()
        let connectState = PerfSignposter.client.beginInterval("ConnectTap", id: connectID)
        defer { PerfSignposter.client.endInterval("ConnectTap", connectState) }

        // Intent BEFORE work — "user asked for tunnel on", not "tunnel up".
        // If attempt throws, flag stays true so subsequent event can retry.
        setUserIntendedConnected(true)
        await watchdog?.setUserIntent(true)
        await applyCurrentStateToCachedManager()  // B-04
        // Round 5 carve-out — block intent-closing while connect is in flight.
        connectInProgress = true
        defer { connectInProgress = false }

        // Phase 6d Wave 02a — `PreConnectProbe` nested span обёртывает
        // первичную проверку наличия профиля (XPC loadAllFromPreferences).
        // Это classic «pre-connect probe»: убедиться, что профиль есть, прежде
        // чем startVPNTunnel.
        let probeID = PerfSignposter.client.makeSignpostID()
        let probeState = PerfSignposter.client.beginInterval("PreConnectProbe", id: probeID)
        let managers: [NETunnelProviderManager]
        do {
            managers = try await NETunnelProviderManager.loadAllFromPreferences()
            PerfSignposter.client.endInterval("PreConnectProbe", probeState)
        } catch {
            PerfSignposter.client.endInterval("PreConnectProbe", probeState)
            throw error
        }

        guard let manager = managers.first else {
            throw NSError(domain: "BBTB.TunnelController", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No VPN profile — import config first"])
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()
        // Poll до .connected или terminal. .disconnecting transient → continue.
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
        manualDisconnectInProgress = true  // Round 5 carve-out — set BEFORE stop.
        setUserIntendedConnected(false)
        await watchdog?.setUserIntent(false)
        await applyCurrentStateToCachedManager()  // B-04 → isOnDemandEnabled=false
        await failoverProvider.resetCycle()  // D-08
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else { scheduleClearManualDisconnect(); return }
        let status = manager.connection.status
        guard status != .disconnected, status != .invalid else { scheduleClearManualDisconnect(); return }
        manager.connection.stopVPNTunnel()
        // Wait for OS to bring tunnel down (max 5s) so subsequent connect()
        // doesn't race against a still-disconnecting tunnel.
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let s = manager.connection.status
            if s == .disconnected || s == .invalid { scheduleClearManualDisconnect(); return }
        }
        scheduleClearManualDisconnect()
    }

    private func scheduleClearManualDisconnect() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.clearManualDisconnect()
        }
    }

    private func clearManualDisconnect() { manualDisconnectInProgress = false }

    // MARK: Observers (status + provisioner + macOS wake)

    public func startReachability() async {
        guard !reachabilityStarted else { return }
        reachabilityStarted = true
        // D-17 narrow: read status DIRECTLY from notification.object
        // (NEVPNConnection.status is synchronous — NOT XPC). UAT 2026-05-13
        // crash (40+/sec → EXC_RESOURCE/PORT_SPACE) was caused by an XPC
        // loadAllFromPreferences() in this observer; we stay XPC-free.
        nevpnObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: nil
        ) { [weak self] notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            let status = conn.status
            Task { [weak self] in await self?.handleStatusChange(status) }
        }
        await refreshCachedManager()  // B-03 initial seed
        // B-03 — refresh on every `.bbtbProvisionerDidSave` (posted by
        // ConfigImporter / SettingsViewModel toggle / OnDemandMigrationTask).
        provisionerObserver = NotificationCenter.default.addObserver(
            forName: .bbtbProvisionerDidSave, object: nil, queue: nil
        ) { [weak self] _ in
            Task { [weak self] in await self?.refreshCachedManager() }
        }
        #if os(macOS)
        // D-11/12/13 + W-06. Pitfall 10 — wake events post only to
        // NSWorkspace.shared.notificationCenter, NOT NotificationCenter.default.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { [weak self] in await self?.handleWake() }
        }
        #endif
        log.notice("TunnelController.startReachability — observers active")
    }

    public func stopReachability() async {
        reachabilityStarted = false
        if let obs = nevpnObserver { NotificationCenter.default.removeObserver(obs); nevpnObserver = nil }
        if let obs = provisionerObserver { NotificationCenter.default.removeObserver(obs); provisionerObserver = nil }
        #if os(macOS)
        if let obs = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs); wakeObserver = nil }
        #endif
        log.notice("TunnelController.stopReachability — observers removed")
    }

    /// iOS scenePhase=.active — cheap no-op (NE status drives transitions).
    public func handleForeground() async {}

    // MARK: Internal event handlers

    /// macOS wake — W-06 3-guard idempotent `startVPNTunnel` nudge:
    /// (1) manager.isEnabled (else: bug class 3 fight-back guard);
    /// (2) manager.isOnDemandEnabled; (3) loadAutoReconnectEnabled() toggle.
    /// B-06: ManagerSelector.ourManagers filter. XPC-free invariant intact
    /// (≤1 loadAllFromPreferences per wake; ≤1 per 10+ min).
    #if os(macOS)
    private func handleWake() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        guard let manager = ManagerSelector.ourManagers(from: managers).first else {
            log.notice("handleWake: no BBTB manager — skip nudge."); return
        }
        guard manager.isEnabled else {
            log.notice("handleWake: manager.isEnabled == false (другой VPN активен?) → skip nudge."); return
        }
        guard manager.isOnDemandEnabled else {
            log.notice("handleWake: manager.isOnDemandEnabled == false (manual mode) → skip nudge."); return
        }
        guard OnDemandRulesBuilder.loadAutoReconnectEnabled() else {
            log.notice("handleWake: autoReconnectEnabled toggle off → skip nudge."); return
        }
        log.notice("handleWake: 3 guards pass — firing idempotent startVPNTunnel nudge.")
        try? manager.connection.startVPNTunnel()
    }
    #endif

    /// Round 5 status observer:
    /// (1) forward to watchdog with real manager.isEnabled gate (B-03);
    /// (2) close intent on EXTERNAL .disconnected (Settings VPN-off, other-VPN
    ///     takeover) per 06C-ARCHITECT-R5.md.
    /// Supersedes Round 4 fight-back (commit 83260c1) and Round 4.1 narrow
    /// guards (commit 76ae2d6) — dead code with the old recovery path gone.
    internal func handleStatusChange(_ status: NEVPNStatus) async {
        // B-03 — real manager.isEnabled gate. false → другой VPN активен или
        // profile disabled в Settings. Watchdog skips in both (D-08).
        let managerEnabled = cachedManager?.isEnabled ?? false
        await watchdog?.handleStatusChange(status, managerEnabled: managerEnabled)
        // Round 5 — intent-closing on EXTERNAL .disconnected. Guards:
        // status == .disconnected (terminal, not .disconnecting);
        // !connectInProgress && !manualDisconnectInProgress (avoid racing
        // our own flows — both raise transient .disconnected);
        // refreshed manager.isEnabled == false (external party flipped profile
        // off; healthy disconnects keep isEnabled=true).
        if status == .disconnected, !connectInProgress, !manualDisconnectInProgress {
            await refreshCachedManager()
            if let manager = cachedManager, !manager.isEnabled {
                log.notice("intent-closing: external .disconnected detected (manager.isEnabled=false) → close user intent")
                setUserIntendedConnected(false)
                await watchdog?.setUserIntent(false)
                await applyCurrentStateToCachedManager()
            }
        }
    }
}
