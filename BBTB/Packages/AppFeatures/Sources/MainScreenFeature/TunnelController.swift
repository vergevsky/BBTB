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

/// Phase 6 follow-up (UAT 2026-05-13) — Sendable wrapper around `UserDefaults`
/// for the `userIntendedConnected` flag.
///
/// `UserDefaults` is documented thread-safe by Apple but is not annotated
/// `Sendable` in Foundation (NSObject heritage). Wrapping it in a `final class`
/// marked `@unchecked Sendable` lets us pass it into `TunnelController` (an
/// actor) without tripping Swift 6 strict concurrency, while preserving the
/// thread-safety guarantee at the UserDefaults level.
public final class UserIntentStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = "app.bbtb.userIntendedConnected") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func save(_ value: Bool) {
        defaults.set(value, forKey: key)
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

    /// Cached NE connection status, kept fresh by the NEVPNStatusDidChange
    /// observer. Phase 6 follow-up (UAT 2026-05-13, post-Codex review): under
    /// iOS 26 notification storm (40+/sec), even the post-cheap-guards
    /// `statusProvider.currentStatus()` XPC call in
    /// `triggerRecoveryIfNeeded` reintroduces Mach-port pressure during the
    /// 2s pre-first-attempt window when the state machine is sleeping. Caching
    /// the last observed status here lets the trigger path stay XPC-free.
    /// Seeded by a one-time `loadAllFromPreferences()` in `startReachability`.
    internal var lastKnownStatus: NEVPNStatus = .invalid

    /// Phase 6 follow-up (UAT 2026-05-13, bug #3) — symmetric to
    /// `manualDisconnectInProgress` for the connect side. Set true at the
    /// start of `connect()`, cleared on scope exit via `defer`.
    ///
    /// Without this guard, the saveToPreferences call inside `connect()`
    /// preamble raises NEVPNStatusDidChange with `.disconnected`, which our
    /// observer routes into `triggerRecoveryIfNeeded`. The `userIntendedConnected`
    /// guard is already true at that point (set at the top of `connect()`),
    /// so the state machine spawns a recursive `self.connect()` task. Actor
    /// reentrance lets that second call execute concurrently with the first
    /// while the first is suspended in its polling loop — two concurrent
    /// saveToPreferences/startVPNTunnel calls on the same manager freeze the
    /// status at `.connecting` (UAT repro: button hangs on "connecting";
    /// enabling the profile from iOS Settings → VPN works because it
    /// bypasses both code paths).
    internal var connectInProgress: Bool = false

    /// D-08 / Pitfall 4 — timestamp of last `.connected` transition.
    /// Wave 6 will use this to gate failover-cursor reset after a 30s stable session.
    internal var lastSuccessfulConnectAt: Date?

    /// Phase 6 follow-up (UAT 2026-05-13) — "user wants tunnel on" signal.
    /// Persisted in UserDefaults so it survives app relaunch (covers the case
    /// where the OS keeps the tunnel alive after the app is killed, and the
    /// user expects auto-reconnect to keep working on next launch).
    ///
    /// Gating the auto-reconnect entry point on this flag fixes two UAT bugs:
    /// 1. Clean install (no `connect()` ever called) — `NWPathMonitor` fires
    ///    `.satisfied` on launch and would otherwise kick the state machine
    ///    against a non-existent session.
    /// 2. Import flow — `ConfigImporter.provisionTunnelProfile` calls
    ///    `manager.saveToPreferences()` which raises `NEVPNStatusDidChange`
    ///    with `.disconnected`, and would otherwise auto-connect before the
    ///    user explicitly tapped the button.
    internal var userIntendedConnected: Bool

    /// macOS wake handshake: NSWorkspace.didWake fires before the network is
    /// ready; we set this flag and let the next NetworkReachability.satisfied
    /// event consume it (Pitfall 10).
    private var wakePending: Bool = false

    private var nevpnObserver: NSObjectProtocol?
    #if os(macOS)
    private var wakeObserver: Any?
    #endif
    private var reachabilityStarted: Bool = false

    /// Persistence backing for `userIntendedConnected`. Sendable wrapper around
    /// UserDefaults — see `UserIntentStore` doc-comment.
    private let intentStore: UserIntentStore

    // MARK: - Phase 6c / Plan 06C-04 — additive wiring (parallel-run mode)

    /// Phase 6c / Plan 06C-04 / Task 1 — TunnelWatchdog (D-08/D-09 mid-session
    /// failover) wired через late-binding setter — mirror того, как
    /// failoverProvider wires. App entry point конструирует TunnelWatchdog
    /// после failoverProvider и вызывает `setWatchdog(_:)`.
    ///
    /// Parallel-run window (Plan 06C-04 Task 1): watchdog работает в дополнение
    /// к старой ReconnectStateMachine; обе machinery реагируют на тот же
    /// NEVPNStatusDidChange. Plan 06C-04 Task 3a удалит старую custom-reconnect
    /// логику после успешного UAT.
    private var watchdog: TunnelWatchdog?

    /// Phase 6c / Plan 06C-04 / Round 2 B-03 — cached `NETunnelProviderManager`
    /// snapshot. Используется как **real** `manager.isEnabled` gate для
    /// `watchdog.handleStatusChange(_:managerEnabled:)` — заменяет сломанный
    /// status-based proxy, который проксировал только «есть профиль вообще»,
    /// а не «наш профиль активен прямо сейчас»; во время fight-back с другим
    /// VPN-приложением status корректен, но `isEnabled` = false — watchdog
    /// не должен fire'ать failover в таком случае.
    ///
    /// Populated в `startReachability()` (initial refresh) и в
    /// `bbtbProvisionerDidSave` NotificationCenter observer.
    /// Nil-safe consumer: `cachedManager?.isEnabled ?? false` (conservative
    /// default = false на cache miss → watchdog skip'нет — D-08 safety).
    private var cachedManager: NETunnelProviderManager?

    /// Phase 6c / Plan 06C-04 / Round 2 B-03 — NotificationCenter token
    /// для `.bbtbProvisionerDidSave` observer. Posted by
    /// `ConfigImporter.DefaultTunnelProvisioner.provisionTunnelProfile`,
    /// `SettingsViewModel.applyAutoReconnectToManager`, и
    /// `OnDemandMigrationTask.runIfNeeded` — каждый event'те мы refresh'им
    /// `cachedManager` чтобы watchdog gate видел актуальный `.isEnabled`.
    private var provisionerObserver: NSObjectProtocol?

    // MARK: Init

    public init(
        reachability: NetworkReachability = NetworkReachability(),
        statusProvider: VPNStatusProviding = DefaultVPNStatusProvider(),
        failoverProvider: FailoverProviding = NoFailoverProvider(),
        reconnectClock: ReconnectClock = SystemReconnectClock(),
        stateObserver: ReconnectStateMachine.StateObserver? = nil,
        intentStore: UserIntentStore = UserIntentStore()
    ) {
        self.reachability = reachability
        self.statusProvider = statusProvider
        self.failoverProvider = failoverProvider
        self.reconnectClock = reconnectClock
        self.stateMachine = ReconnectStateMachine(clock: reconnectClock, observer: stateObserver)
        self.intentStore = intentStore
        self.userIntendedConnected = intentStore.load()
    }

    /// Mutates the in-memory flag AND mirrors to UserDefaults in a single
    /// actor-isolated step. UserDefaults is thread-safe; the mirroring is a
    /// synchronous side-effect with no suspension point.
    private func setUserIntendedConnected(_ value: Bool) {
        userIntendedConnected = value
        intentStore.save(value)
    }

    /// Phase 6 / Wave 6 — late-binding setter for the real failover provider.
    /// App code constructs `TunnelController` with the default `NoFailoverProvider`,
    /// then constructs `SwiftDataFailoverProvider` (which captures `[weak self]`
    /// of TunnelController in its `connect` closure to break the cycle), then
    /// calls this to swap the active provider.
    public func setFailoverProvider(_ provider: FailoverProviding) {
        self.failoverProvider = provider
    }

    /// Phase 6c / Plan 06C-04 / Task 1 — late-binding setter for the
    /// `TunnelWatchdog` actor. Mirror того, как `setFailoverProvider` работает:
    /// App entry point конструирует `failoverProvider` (с `[weak tunnel]`
    /// в `connect` closure для cycle break), затем конструирует
    /// `TunnelWatchdog(failoverProvider: failoverProvider)`, затем вызывает
    /// `setWatchdog(_:)`.
    public func setWatchdog(_ watchdog: TunnelWatchdog) {
        self.watchdog = watchdog
    }

    /// Phase 6c / Plan 06C-04 / Round 2 B-03 — обновляет `cachedManager`
    /// reading `NETunnelProviderManager.loadAllFromPreferences()` + фильтрация
    /// через `ManagerSelector.ourManagers` (B-06 multi-manager safety).
    ///
    /// Вызывается:
    /// - Один раз в `startReachability()` (initial seed).
    /// - На каждое `.bbtbProvisionerDidSave` notification (ConfigImporter /
    ///   SettingsViewModel toggle / OnDemandMigrationTask).
    ///
    /// На transient XPC failure: `cachedManager` остаётся в предыдущем
    /// значении (graceful degradation — следующий refresh попробует снова).
    private func refreshCachedManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            cachedManager = ManagerSelector.ourManagers(from: managers).first
            log.debug("TunnelController cachedManager refreshed (nil=\(self.cachedManager == nil, privacy: .public))")
        } catch {
            log.warning("TunnelController.refreshCachedManager failed: \(String(describing: error), privacy: .public)")
            // cachedManager stays at previous value — graceful degradation;
            // следующий refresh трюк попробует снова.
        }
    }

    /// Phase 6c / Plan 06C-04 / Round 2 B-04 wiring complement + Round 3 N-01
    /// load-on-demand fallback.
    ///
    /// Применяет `OnDemandRulesBuilder.applyCurrentState` к cached manager'у +
    /// save + reload. Это нужно потому что `manager.isOnDemandEnabled` =
    /// `toggle && intent` — при flip'е intent (через `setUserIntendedConnected`
    /// в `connect()`/`disconnect()`) manager нужно ОБНОВИТЬ немедленно;
    /// без этого helper'а изменение применилось бы только на следующий
    /// provisioner save, что слишком поздно.
    ///
    /// **Round 3 N-01 fix (load-on-demand on cache miss):** если cachedManager
    /// nil (первый запуск ДО startReachability refresh, или race-condition
    /// между Connect tap и observer dispatch), пробуем refresh ОДИН раз
    /// перед guard. Иначе первый Connect tap не flip'нул бы
    /// `manager.isOnDemandEnabled = true` до СЛЕДУЮЩЕГО provisioner save —
    /// auto-reconnect был бы выключен в окне «пользователь только что
    /// импортировал config и сразу тапнул Connect».
    ///
    /// **Round 3 MINOR-01 graceful degradation (catch block):** не throw'ит
    /// никогда — user intent уже persisted в UserDefaults через @AppStorage
    /// ПЕРЕД вызовом этого helper'а, поэтому следующий provisioner event
    /// сам re-apply'нет state.
    private func applyCurrentStateToCachedManager() async {
        // Round 3 N-01 fix — load-on-demand if cache miss.
        // Сценарий: пользователь только что импортировал config и тапнул Connect, а observer
        // `.bbtbProvisionerDidSave` ещё не успел нас refresh'нуть (или это вообще первый запуск
        // ДО startReachability refresh). Без этого fallback'а Connect tap не flip'нул бы
        // `manager.isOnDemandEnabled = true` до СЛЕДУЮЩЕГО provisioner save — а до тех пор
        // auto-reconnect был бы выключен (UX regression, обратная сторона B-04 fix).
        if cachedManager == nil { await refreshCachedManager() }
        guard let manager = cachedManager else {
            // Даже после refresh manager не найден — пользователь ещё не импортировал config.
            // UI должен блокировать Connect tap в этом state; defensive log на случай если нет.
            log.warning("applyCurrentStateToCachedManager — no manager available even after refresh; skipping.")
            return
        }
        OnDemandRulesBuilder.applyCurrentState(to: manager)
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()  // RESEARCH §9.1
            // Не постим .bbtbProvisionerDidSave — мы САМИ source of this update; не нужно рефрешить
            // собственный cachedManager (это создаст petty cycle).
        } catch {
            // Round 3 MINOR-01 (Gemini R3) — graceful degradation rationale:
            // User intent (`autoReconnectEnabled` toggle state) уже persisted в UserDefaults через
            // @AppStorage ПЕРЕД вызовом этого helper'а. Если save транзитно упал (XPC glitch,
            // pre-warm race, etc.) — следующий provisioner event (re-import, app relaunch, или
            // любая другая operation, вызывающая ConfigImporter.provisionTunnelProfile) сам
            // re-apply'нет current state через OnDemandRulesBuilder.applyCurrentState с тем же
            // toggle && intent gate. Поэтому log-and-continue, никогда throw/escalate —
            // нет user-visible regression от пропуска одного flip'а.
            log.warning("applyCurrentStateToCachedManager save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Phase 1-5 connect/disconnect (preserved)

    public func connect() async throws -> Date {
        // Record user intent BEFORE the work — the flag represents
        // "user asked for tunnel on", not "tunnel actually came up".
        // If the attempt throws, the flag stays true so a subsequent
        // reachability event can legitimately retry.
        setUserIntendedConnected(true)
        // Phase 6c / Plan 06C-04 / Task 1 — mirror intent to watchdog gate (D-08).
        await watchdog?.setUserIntent(true)
        // Round 2 B-04 wiring complement — immediately flip manager.isOnDemandEnabled
        // на основе нового intent. Без этого изменение intent применилось бы
        // ТОЛЬКО на следующий provisioner save, что слишком поздно.
        await applyCurrentStateToCachedManager()
        // Block auto-recovery while the actual connect is in flight —
        // saveToPreferences below raises NEVPNStatusDidChange.disconnected
        // and we must not let it spawn a parallel `self.connect()` via the
        // state machine (actor reentrance would corrupt the manager state).
        connectInProgress = true
        defer { connectInProgress = false }
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
        // Clear user intent BEFORE the work — any reachability event that
        // fires during the teardown window must NOT trigger auto-reconnect.
        setUserIntendedConnected(false)
        // Phase 6c / Plan 06C-04 / Task 1 — mirror intent flip to watchdog
        // (D-08 full state reset: cancel debounce + clear stableSession).
        await watchdog?.setUserIntent(false)
        // Round 2 B-04 wiring complement — flip manager.isOnDemandEnabled = false
        // → tunnel не auto-resurrect после user-initiated disconnect.
        await applyCurrentStateToCachedManager()

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

        // Seed `lastKnownStatus` once at startup so `triggerRecoveryIfNeeded`
        // has accurate status before the observer's first delivery — single
        // XPC call per actor lifetime. The observer keeps it fresh after.
        lastKnownStatus = await statusProvider.currentStatus()

        // NetworkReachability is an actor — closure hops back to self via Task.
        await reachability.start { [weak self] event in
            Task { [weak self] in
                await self?.handleReachability(event)
            }
        }

        // NEVPNStatusDidChange — first-class status observable.
        //
        // CRITICAL: read status DIRECTLY from `notification.object`
        // (`NEVPNConnection.status` is a synchronous property — NOT an XPC
        // call). The earlier implementation called
        // `statusProvider.currentStatus()` which does
        // `NETunnelProviderManager.loadAllFromPreferences()` — that IS an XPC
        // call, allocating a new Mach port each time. On iOS 26 the system
        // raises 40+ status notifications per second under load; the cumulative
        // Mach-port pressure exhausts the 131072 per-process limit in minutes
        // and iOS kills the process with `EXC_RESOURCE / PORT_SPACE`. UAT
        // 2026-05-13 crash logs confirmed exactly this signature, with the
        // triggered thread blocked in `_xpc_try_mach_port_construct` →
        // `xpc_connection_send_message_with_reply` → `-[NEHelper sendRequest:…]`.
        nevpnObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            let status = conn.status
            Task { [weak self] in
                await self?.handleStatusChange(status)
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

        // Phase 6c / Plan 06C-04 / Round 2 B-03 — initial cachedManager
        // population (one XPC call per actor lifetime; observer keeps it fresh).
        await refreshCachedManager()

        // Phase 6c / Plan 06C-04 / Round 2 B-03 — refresh cachedManager on every
        // `.bbtbProvisionerDidSave` event (posted by ConfigImporter /
        // SettingsViewModel toggle / OnDemandMigrationTask after save).
        // Это закрывает window между save и watchdog gate evaluation:
        // например, ConfigImporter сохранил manager с новым isOnDemandEnabled,
        // через 100ms приходит NEVPNStatusDidChange — watchdog должен видеть
        // обновлённый flag, а не предыдущий.
        provisionerObserver = NotificationCenter.default.addObserver(
            forName: .bbtbProvisionerDidSave,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in await self?.refreshCachedManager() }
        }

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
        // Phase 6c / Plan 06C-04 / Round 2 B-03 — unregister provisioner observer.
        if let obs = provisionerObserver {
            NotificationCenter.default.removeObserver(obs)
            provisionerObserver = nil
        }
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
        //
        // No `statusProvider.currentStatus()` smoke check — that call uses
        // `loadAllFromPreferences()` (an XPC trip) and the result is discarded.
        // Mach port hygiene matters more here than diagnostic logging
        // (see Mach-port-leak note in `startReachability`).
        guard !manualDisconnectInProgress else { return }
    }

    // MARK: Phase 6 — internal event handlers

    /// macOS wake handshake — Phase 6c / Plan 06C-04 / Task 1 / Round 2 W-06.
    ///
    /// Старая Phase 6 семантика (wakePending=true → ждать reachability.satisfied
    /// → triggerRecoveryIfNeeded) ПРЕСЕРВИРОВАНА (parallel-run mode — line ниже
    /// `wakePending = true` всё ещё работает; Plan 06C-04 Task 3a удалит её
    /// после UAT).
    ///
    /// Новая Phase 6c семантика (additive): идемпотентный nudge
    /// `startVPNTunnel()` с **3 guards** (W-06):
    ///   1. `manager.isEnabled` — не fire'ать если профиль disabled другим
    ///      VPN-приложением (bug class 3 mitigation: "fight-back").
    ///   2. `manager.isOnDemandEnabled` — уважаем on-demand state
    ///      (если пользователь отключил, manual mode).
    ///   3. `OnDemandRulesBuilder.loadAutoReconnectEnabled()` — toggle в Settings.
    ///
    /// `ManagerSelector.ourManagers(from:).first` — B-06 multi-manager safety:
    /// фильтруем наши `NETunnelProviderManager` (residue от старых установок
    /// или другие приложения не должны trigger'ить nudge).
    ///
    /// XPC-free invariant НЕ нарушается: один `loadAllFromPreferences` per
    /// wake event (≤ 1 раз в 10+ min); `startVPNTunnel` сам по себе тоже
    /// один XPC trip — terminal action, не storm.
    #if os(macOS)
    private func handleWake() async {
        // Phase 6 parallel-run preserve: старая path с wakePending все ещё работает
        // через handleReachability. Plan 06C-04 Task 3a удалит после UAT.
        wakePending = true
        log.notice("TunnelController.handleWake — wakePending set; awaiting reachability.satisfied")

        // Phase 6c / Plan 06C-04 / Round 2 W-06 — additive idempotent nudge.
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        // Round 2 B-06 — фильтруем наши.
        guard let manager = ManagerSelector.ourManagers(from: managers).first else {
            log.notice("handleWake: no BBTB manager — skip nudge.")
            return
        }
        // Round 2 W-06 — 3 guards:
        // 1. Профиль не disabled другим VPN-приложением (bug class 3 mitigation).
        guard manager.isEnabled else {
            log.notice("handleWake: manager.isEnabled == false (другой VPN активен?) → skip nudge.")
            return
        }
        // 2. On-demand включен на manager'е (пользовательский выбор уважён).
        guard manager.isOnDemandEnabled else {
            log.notice("handleWake: manager.isOnDemandEnabled == false (manual mode) → skip nudge.")
            return
        }
        // 3. Toggle включен в Settings.
        guard OnDemandRulesBuilder.loadAutoReconnectEnabled() else {
            log.notice("handleWake: autoReconnectEnabled toggle off → skip nudge.")
            return
        }
        log.notice("handleWake: 3 guards pass — firing idempotent startVPNTunnel nudge.")
        try? manager.connection.startVPNTunnel()  // idempotent nudge
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

    /// Internal (testable) seam — pure logic based on status + manualDisconnect flag.
    internal func handleStatusChange(_ status: NEVPNStatus) async {
        // Keep cache fresh — `triggerRecoveryIfNeeded` reads this instead of
        // doing its own XPC call, avoiding port pressure under storm.
        lastKnownStatus = status

        // Phase 6c / Plan 06C-04 / Round 4 F-reverse fix — fight-back protection.
        //
        // На `.disconnected` мы могли только что потерять туннель потому что
        // другой VPN-приложение (Happ, ProtonVPN, ...) перехватило route.
        // В этом случае iOS флипает наш `manager.isEnabled = false`. Если
        // `cachedManager` — stale (refresh не успел произойти), watchdog gate
        // ниже увидит `isEnabled = true` и попытается failover; одновременно
        // Apple's on-demand evaluator может реактивировать нас сам по правилу
        // `NEOnDemandRuleConnect(.any)`. Это и есть «fight-back» bug class,
        // который Phase 6c обещала устранить.
        //
        // Решение: на `.disconnected` делаем fresh refresh (один XPC trip).
        // Если выяснилось что `isEnabled` flipped в false → proactively
        // выключаем `isOnDemandEnabled` на нашей стороне и сохраняем, чтобы
        // iOS не fight'илась с другим VPN.
        //
        // **Round 4.1 narrow-trigger guard:** срабатываем ТОЛЬКО когда мы НЕ
        // в середине connect/disconnect flow. Без этого guard'а `await
        // refreshCachedManager()` приводит к actor reentrance посреди
        // `connect()`: actor отпускается во время XPC, `connect()` начинает
        // save'ить config с `isOnDemandEnabled=true`, мы возвращаемся из
        // refresh с manager'ом в полу-saved состоянии (`isEnabled=false`
        // транзитно), ошибочно flip'аем `isOnDemandEnabled=false`, потом
        // `connect()` save'ит снова с true → лишние XPC роунды +
        // status flapping + видимый `.connecting`/`.retrying` баннер +
        // 10-15с задержка connect'а. Guard сужает trigger до «реально
        // внешний disconnect», что и есть единственный нужный сценарий.
        if status == .disconnected, !connectInProgress, !manualDisconnectInProgress {
            await refreshCachedManager()
            if let manager = cachedManager, !manager.isEnabled, manager.isOnDemandEnabled {
                manager.isOnDemandEnabled = false
                do {
                    try await manager.saveToPreferences()
                    log.notice("fight-back protection: manager.isEnabled=false detected, disabled on-demand to release iOS auto-reconnect")
                } catch {
                    log.warning("fight-back protection: save failed: \(String(describing: error), privacy: .public)")
                }
            }
        }

        // Phase 6c / Plan 06C-04 / Round 2 B-03 — REAL manager.isEnabled gate
        // (replaces broken status-based proxy from Phase 6).
        // cachedManager.isEnabled false происходит когда:
        //   (a) другой VPN активирован (наш профиль disabled);
        //   (b) пользователь отключил профиль в Settings → VPN.
        // В обоих случаях watchdog НЕ должен fire failover (D-08 +
        // bug class 3 mitigation: "fight-back с другим VPN-приложением").
        // Если cachedManager == nil (startup race до первого refresh) —
        // conservative default false → watchdog skip.
        //
        // Параллельно: старая ReconnectStateMachine path всё ещё работает
        // через triggerRecoveryIfNeeded (см. .disconnected branch). Plan
        // 06C-04 Task 3a удалит старую path после успешного UAT (Task 2).
        let managerEnabled = cachedManager?.isEnabled ?? false
        await watchdog?.handleStatusChange(status, managerEnabled: managerEnabled)

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

    internal func triggerRecoveryIfNeeded(reason: String) async {
        // GUARDS ORDERED CHEAP-FIRST.
        //
        // Each `statusProvider.currentStatus()` call in production goes
        // through `NETunnelProviderManager.loadAllFromPreferences()` — that is
        // an XPC trip and allocates a Mach port. iOS 26 raises
        // NEVPNStatusDidChange 40+ times per second under churn, and even
        // with the in-place `notification.object` read in the observer, the
        // recovery path was still doing an XPC per delivered notification
        // before bailing on the user-intent flag. Cheap actor-isolated reads
        // (userIntendedConnected, connectInProgress, manualDisconnectInProgress)
        // run first; the XPC call happens only when we are actually about to
        // start the state machine.
        guard userIntendedConnected else {
            log.notice("triggerRecovery skipped (userIntendedConnected=false) — reason=\(reason, privacy: .public)")
            return
        }
        guard !connectInProgress else {
            log.notice("triggerRecovery skipped (connectInProgress=true) — reason=\(reason, privacy: .public)")
            return
        }
        guard !manualDisconnectInProgress else {
            log.notice("triggerRecovery skipped (manualDisconnectInProgress=true) — reason=\(reason, privacy: .public)")
            return
        }
        // Use the cached status from `handleStatusChange` (kept fresh by the
        // observer) instead of doing an XPC call here. Under iOS 26
        // notification storm, paying XPC per trigger reintroduces Mach-port
        // pressure during the 2s pre-first-attempt window.
        guard lastKnownStatus != .connected else {
            log.notice("triggerRecovery skipped (already connected) — reason=\(reason, privacy: .public)")
            return
        }
        // Phase 6c / Plan 06C-04 / Round 2 B-03 — REAL manager.isEnabled gate
        // (replaces broken status-based proxy from Phase 6).
        // Старый proxy проксировал только «есть профиль вообще», а не «наш
        // профиль активен прямо сейчас». Например, во время fight-back с
        // другим VPN-приложением `lastKnownStatus` корректен (.disconnected),
        // но `manager.isEnabled` = false — recovery path не должен fire'аться.
        // Conservative default false на cache miss → skip (D-08 safety).
        //
        // Test seam: tests, exercising это recovery path БЕЗ entitlement-gated
        // `NETunnelProviderManager`, могут вызвать
        // `_setCachedManagerEnabledOverrideForTest(true)`. Production never sets
        // override → fall-through к real `cachedManager?.isEnabled ?? false`.
        let enabledGate = cachedManagerEnabledOverrideForTest ?? (cachedManager?.isEnabled ?? false)
        guard enabledGate else {
            log.notice("triggerRecovery skipped (no enabled BBTB profile — cachedManager.isEnabled=false) — reason=\(reason, privacy: .public)")
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

    /// Phase 6c / Plan 06C-04 / Task 1 — test seam для нового `cachedManager.isEnabled`
    /// gate в `triggerRecoveryIfNeeded`. Tests, exercising recovery path БЕЗ
    /// entitlement-gated `NETunnelProviderManager` (Phase 6 tests были написаны до
    /// `cachedManager` existence), могут вызвать
    /// `_setCachedManagerEnabledOverrideForTest(true)` чтобы симулировать
    /// «BBTB profile is enabled and active». Nil — production behavior (real
    /// `cachedManager?.isEnabled ?? false`).
    internal var cachedManagerEnabledOverrideForTest: Bool?

    internal func _setCachedManagerEnabledOverrideForTest(_ value: Bool?) {
        cachedManagerEnabledOverrideForTest = value
    }

    internal func setFirstAttemptOverrideForTest(_ closure: (@Sendable () async throws -> Date)?) {
        self.firstAttemptOverrideForTest = closure
    }

    internal func isManualDisconnectInProgress() -> Bool { manualDisconnectInProgress }
    internal func _setManualDisconnectForTest(_ value: Bool) {
        manualDisconnectInProgress = value
    }
    internal func getLastSuccessfulConnectAt() -> Date? { lastSuccessfulConnectAt }
    internal func isReachabilityStartedForTest() -> Bool { reachabilityStarted }

    internal func _setUserIntendedConnectedForTest(_ value: Bool) {
        setUserIntendedConnected(value)
    }
    internal func getUserIntendedConnectedForTest() -> Bool { userIntendedConnected }

    internal func _setConnectInProgressForTest(_ value: Bool) {
        connectInProgress = value
    }
    internal func getConnectInProgressForTest() -> Bool { connectInProgress }
}
