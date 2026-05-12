import Foundation
import SwiftUI
import SwiftData
import VPNCore
import ConfigParser
import Localization
import ServerListFeature

/// Phase 6 / Wave 5 / NET-09/10 — UI state for the reconnect banner above the
/// main screen. Drives the message inside `ReconnectBanner`.
///
/// `.hidden`              — no banner.
/// `.killSwitchReconfigure` — Phase 2 KillSwitch toggle changed while connected.
/// `.retrying(attempt:)`  — auto-reconnect in progress (NET-09).
/// `.failover(toServerName:)` — switching to the next server (NET-11).
/// `.allFailed`           — all reconnect attempts exhausted (NET-10).
public enum ReconnectBannerState: Equatable, Sendable {
    case hidden
    case killSwitchReconfigure
    case retrying(attempt: Int, delaySeconds: Int)
    case failover(toServerName: String)
    case allFailed
}

@MainActor
public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState = .empty
    @Published public private(set) var activeServerName: String?
    @Published public private(set) var supportedConfigCount: Int = 0
    @Published public private(set) var unsupportedConfigCount: Int = 0
    @Published public private(set) var needsReconnectForKillSwitch: Bool = false
    @Published public private(set) var importInProgress: Bool = false
    @Published public var lastError: String?

    /// Phase 6 / Wave 5 — drives `ReconnectBanner` message + visibility.
    /// State-machine variants (retrying/failover/allFailed) override the
    /// KillSwitch banner when present (auto-reconnect is a stronger signal
    /// than "kill switch changed — please reconnect").
    @Published public private(set) var reconnectBannerState: ReconnectBannerState = .hidden

    // Phase 3 Plan 03 — server list sheet driver + manual selection state.
    @Published public var isPresentingServerList: Bool = false
    /// Phase 3 / Plan 05 — selectedServerID PERSIST'ится в UserDefaults через didSet.
    /// nil = Auto mode (default).
    @Published public var selectedServerID: UUID? = nil {
        didSet { saveSelectedServerID() }
    }

    /// ServerListFeature view-model. Создаётся при наличии modelContainer/probeService;
    /// nil-safe для existing Phase 2 callsites без DI (backward compat).
    public let serverListViewModel: ServerListViewModel?

    public let importer: ConfigImporting
    public let tunnel: TunnelControlling

    // Phase 3 / Plan 05 — pre-connect probe + UserDefaults persist.
    private let probeService: ServerProbing
    private let userDefaults: UserDefaults
    private let modelContainer: ModelContainer?
    private static let selectedServerIDKey = "app.bbtb.selectedServerID"

    private var killSwitchObserver: NSObjectProtocol?
    private var lastKillSwitchValue: Bool

    /// Phase 2 backward-compat init — без modelContainer/probeService → serverListViewModel = nil.
    public convenience init(importer: ConfigImporting, tunnel: TunnelControlling) {
        self.init(importer: importer,
                  tunnel: tunnel,
                  modelContainer: nil,
                  probeService: nil)
    }

    /// Phase 3 full DI init.
    ///
    /// **Plan 05 extensions** к старой Plan 03 сигнатуре:
    /// - `probeService` теперь принимает `ServerProbing` protocol (вместо concrete
    ///   `ServerProbeService?`) — позволяет тестам инжектить mock.
    /// - `userDefaults` injection (default `.standard`) — изоляция persistance в тестах.
    public init(importer: ConfigImporting,
                tunnel: TunnelControlling,
                modelContainer: ModelContainer?,
                probeService: ServerProbing? = nil,
                userDefaults: UserDefaults = .standard) {
        self.importer = importer
        self.tunnel = tunnel
        self.modelContainer = modelContainer
        self.userDefaults = userDefaults
        self.probeService = probeService ?? ServerProbeService()
        self.lastKillSwitchValue = userDefaults.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true

        if let container = modelContainer {
            // Plan 04 — pass importer для pullToRefresh/merge через ConfigImporting protocol.
            let listVM = ServerListViewModel(
                modelContainer: container,
                probeService: self.probeService,
                importer: importer
            )
            self.serverListViewModel = listVM
        } else {
            self.serverListViewModel = nil
        }

        // Plan 05 — восстановить selectedServerID из UserDefaults.
        // Запись напрямую в backing storage чтобы didSet не сработал повторно
        // на init-стадии (UserDefaults уже содержит значение).
        if let stored = userDefaults.string(forKey: Self.selectedServerIDKey),
           let uuid = UUID(uuidString: stored) {
            // Используем backing assignment — но в Swift нет direct backing access;
            // присваиваем через свойство, didSet безопасен (set с уже сохранённым value).
            self.selectedServerID = uuid
        }

        Task { @MainActor in await refresh() }

        // D-14: observe UserDefaults killSwitchEnabled change.
        self.killSwitchObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleUserDefaultsChange() }
        }

        // После init собственного состояния — подключаем coordinator backlink.
        // ServerListViewModel.coordinator — weak, retain cycle исключён.
        self.serverListViewModel?.coordinator = self
    }

    /// Open server-list sheet (привязка tap ServerLineView).
    public func presentServerList() {
        isPresentingServerList = true
    }

    // Swift 6 strict concurrency: cannot access non-Sendable killSwitchObserver from
    // nonisolated deinit. NotificationCenter observers are auto-cleaned on app termination;
    // ViewModel lives entire app lifecycle so manual removal is не критичен. Phase 11
    // refactor может выделить ObservationCenter helper если потребуется.

    public func refresh() async {
        let count = importer.countSupportedConfigs()
        supportedConfigCount = count
        if count == 0 {
            activeServerName = nil
            state = .empty
        } else {
            activeServerName = await resolveServerLineName(supportedCount: count)
            if case .empty = state { state = .idle }
        }
        await reconcileSelectionWithStore()
    }

    /// Resolve the server line label for the bottom bar.
    /// Manual selection → show server name. Auto mode → "Авто" (≥2) or the single server name.
    private func resolveServerLineName(supportedCount: Int) async -> String? {
        guard supportedCount > 0 else { return nil }
        if let id = selectedServerID, let container = modelContainer {
            let context = ModelContext(container)
            let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
            if let server = try? context.fetch(desc).first {
                return server.name
            }
        }
        if supportedCount > 1 { return L10n.serverAuto }
        return importer.loadActiveServer()?.name
    }

    public func importFromPasteboard() {
        Task { @MainActor in await performImport(.pasteboard, raw: nil) }
    }

    public func importFromQRString(_ raw: String) {
        Task { @MainActor in await performImport(.qrCode, raw: raw) }
    }

    public func toggleConnection() {
        Task { @MainActor in await performToggleImpl() }
    }

    /// Alias used in W4 MainScreenView rewrite.
    public func performToggle() {
        toggleConnection()
    }

    public func dismissReconnectBanner() {
        needsReconnectForKillSwitch = false
        if reconnectBannerState == .killSwitchReconfigure {
            reconnectBannerState = .hidden
        }
    }

    // MARK: - Phase 6 / Wave 5 — banner mapping helpers

    /// Localized banner message for the current `reconnectBannerState`.
    /// Returns `nil` when banner should be hidden.
    public var reconnectBannerMessage: String? {
        switch reconnectBannerState {
        case .hidden:
            return nil
        case .killSwitchReconfigure:
            return L10n.bannerReconnectNeeded
        case .retrying(let attempt, _):
            return L10n.bannerReconnecting(attempt)
        case .failover:
            return L10n.bannerFailover
        case .allFailed:
            return L10n.bannerAllFailed
        }
    }

    /// Phase 6 / Wave 5 — bridge from ReconnectStateMachine state to UI state.
    /// Build a `@Sendable` closure that hops to MainActor and updates the
    /// published banner state. Caller wires this into `TunnelController.init`'s
    /// `stateObserver:` parameter.
    public nonisolated func makeReconnectStateObserver() -> ReconnectStateMachine.StateObserver {
        let weakSelf = WeakBox(self)
        return { machineState in
            Task { @MainActor in
                weakSelf.value?.applyReconnectStateMachineState(machineState)
            }
        }
    }

    /// Apply a fresh `ReconnectStateMachineState` to the published banner state +
    /// schedule a local notification on `.allFailed` (NET-10).
    private func applyReconnectStateMachineState(_ machineState: ReconnectStateMachineState) {
        switch machineState {
        case .idle:
            // State machine collapsed — if kill-switch banner is also gone, hide.
            if reconnectBannerState != .killSwitchReconfigure {
                reconnectBannerState = needsReconnectForKillSwitch ? .killSwitchReconfigure : .hidden
            }
        case .retrying(let attempt, let delaySeconds):
            reconnectBannerState = .retrying(attempt: attempt, delaySeconds: delaySeconds)
        case .failover(let serverName):
            reconnectBannerState = .failover(toServerName: serverName)
        case .allFailed:
            reconnectBannerState = .allFailed
            // Best-effort local notification — silent failure if user denied.
            let name = activeServerName
            Task { @MainActor in
                await UserNotificationsHelper.notifyReconnectFailed(serverName: name)
            }
        }
    }

    /// Exposed for iOS scenePhase wiring — `BBTB_iOSApp` calls `tunnelController.handleForeground()`
    /// on every `.active` transition. Returns `nil` when `tunnel` isn't a concrete
    /// `TunnelController` (e.g. test mocks) — caller is expected to skip in that case.
    public var tunnelController: TunnelController? {
        return tunnel as? TunnelController
    }

    private func performImport(_ source: ImportSource, raw: String?) async {
        importInProgress = true
        defer { importInProgress = false }
        lastError = nil
        do {
            let result: ImportResult
            switch source {
            case .qrCode where raw != nil:
                result = try await importer.importFromQRCode(raw!)
            default:
                result = try await importer.importFromPasteboard()
            }
            supportedConfigCount = result.supported.count
            unsupportedConfigCount = result.unsupported.count
            await refresh()
            if case .empty = state, supportedConfigCount > 0 {
                state = .idle
            }
        } catch {
            lastError = error.localizedDescription
            // Не выставляем .error если нет конфигов — оставляем .empty.
            if supportedConfigCount > 0 {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    private func performToggleImpl() async {
        switch state {
        case .empty, .connecting:
            return
        case .idle, .error:
            state = .connecting
            do {
                if let selectedID = selectedServerID {
                    // Manual — direct provision 1-outbound pool.
                    try await importer.provisionTunnelProfile(for: selectedID)
                } else {
                    // Auto — pre-connect probe → winner → 1-outbound pool.
                    let winnerID = try await performPreConnectAutoSelect()
                    try await importer.provisionTunnelProfile(for: winnerID)
                }
                let since = try await tunnel.connect()
                state = .connected(since: since)
                needsReconnectForKillSwitch = false
            } catch let err as MainScreenError {
                state = .error(message: err.errorDescription ?? "\(err)")
            } catch {
                state = .error(message: error.localizedDescription)
            }
        case .connected:
            do {
                try await tunnel.disconnect()
                state = .idle
                needsReconnectForKillSwitch = false
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    /// Phase 3 / Plan 05 — pre-connect parallel TCP probe всех supported → ServerScore.autoSelect.
    ///
    /// **Pitfall 8 mitigation:** если все 3/3 timeout → throws `MainScreenError.noReachableServers`.
    /// **Edge case:** 1 supported (без других для сравнения) — возвращается даже если
    /// ping failed (degenerate; пользователь сам может попробовать reconnect).
    private func performPreConnectAutoSelect() async throws -> UUID {
        guard let container = modelContainer else {
            // Phase 2 fallback path — нет container'а → throw, чтобы caller получил error.
            throw MainScreenError.noSupportedServers
        }
        let context = ModelContext(container)
        let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })
        let supported = (try? context.fetch(desc)) ?? []
        guard !supported.isEmpty else { throw MainScreenError.noSupportedServers }

        // Degenerate: 1 server — sразу возвращаем, без ping (бессмысленный).
        if supported.count == 1 {
            return supported[0].id
        }

        let payload: [(id: UUID, host: String, port: Int)] = supported.map {
            (id: $0.id, host: $0.host, port: $0.port)
        }

        var aggregates: [UUID: ProbeAggregate] = [:]
        for await (id, agg) in probeService.probeAll(payload) {
            aggregates[id] = agg
        }

        let candidates: [(id: UUID, score: Double?)] = supported.map {
            (id: $0.id, score: aggregates[$0.id]?.score)
        }
        guard let winner = ServerScore.autoSelect(candidates) else {
            throw MainScreenError.noReachableServers
        }
        return winner
    }

    /// Phase 3 / Plan 05 — UserDefaults mirror for selectedServerID.
    private func saveSelectedServerID() {
        if let id = selectedServerID {
            userDefaults.set(id.uuidString, forKey: Self.selectedServerIDKey)
        } else {
            userDefaults.removeObject(forKey: Self.selectedServerIDKey)
        }
    }

    /// Phase 3 / Plan 05 / Pitfall 10 — reconcile selectedServerID with current store
    /// content. Если selected ID отсутствует среди supported серверов (например, deleted
    /// внешним путём вроде Phase 11 context menu) → reset в nil (fallback to Auto).
    ///
    /// **НЕ trigger'ит reconnect** — это passive recovery, не active state transition.
    /// Вызывается из refresh() и доступна тестам напрямую.
    public func reconcileSelectionWithStore() async {
        guard let container = modelContainer,
              let id = selectedServerID else { return }
        let context = ModelContext(container)
        let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
        let found = (try? context.fetch(desc).first) != nil
        if !found {
            // НЕ через applySelection — это бы trigger'нуло reconnect-on-active.
            // Прямое присваивание (didSet обновит UserDefaults).
            selectedServerID = nil
        }
    }

    /// D-14 — UserDefaults observer. Если значение killSwitchEnabled поменялось И туннель
    /// активен → показать ReconnectBanner.
    private func handleUserDefaultsChange() {
        let current = userDefaults.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true
        if current != lastKillSwitchValue {
            lastKillSwitchValue = current
            if case .connected = state {
                needsReconnectForKillSwitch = true
                // Don't overwrite an active auto-reconnect banner.
                switch reconnectBannerState {
                case .retrying, .failover, .allFailed:
                    break
                default:
                    reconnectBannerState = .killSwitchReconfigure
                }
            }
        }
    }
}

// MARK: - WeakBox

/// `Sendable` weak wrapper — used to ferry a reference into a `@Sendable` closure
/// without capturing `self` strongly (and without making the closure non-Sendable).
/// Property access is unsafe across actor boundaries; we only ever read `value`
/// inside a `Task { @MainActor in … }` block where the VM is main-actor-isolated.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - MainScreenError

/// Phase 3 / Plan 05 — error tags для performToggle / performPreConnectAutoSelect.
/// Маппятся на L10n keys через `errorDescription`.
public enum MainScreenError: Error, Equatable, LocalizedError {
    case noReachableServers
    case noSupportedServers
    public var errorDescription: String? {
        switch self {
        case .noReachableServers: return L10n.serverListNoReachableServers
        case .noSupportedServers: return L10n.serverListNoSupportedServers
        }
    }
}

// MARK: - ServerSelectionCoordinating (Phase 3 Plan 03 + Plan 05)
//
// One-way coordination MainScreenFeature → ServerListFeature.
// Plan 05 расширение: applySelection во время active tunnel → автоматический reconnect
// (D-09, без алерта).
extension MainScreenViewModel: ServerSelectionCoordinating {
    public func applySelection(_ id: UUID?) {
        let previousID = selectedServerID
        selectedServerID = id
        guard previousID != id else { return }
        // Refresh bottom-bar label immediately after selection change.
        Task { @MainActor in await refresh() }
        // D-09 — reconnect-on-active без алерта.
        if case .connected = state {
            Task { @MainActor in await reconnectAfterSelectionChange(newID: id) }
        }
    }

    public func dismissServerList() {
        isPresentingServerList = false
    }

    /// Plan 05 — D-09 reconnect sequence при смене selection в .connected.
    private func reconnectAfterSelectionChange(newID: UUID?) async {
        // Старая state была .connected — переходим в .connecting (UI bounce, но без
        // banner / алерта; UI MainScreenView просто покажет .connecting индикатор).
        state = .connecting
        do {
            try await tunnel.disconnect()
            try await importer.provisionTunnelProfile(for: newID)
            let since = try await tunnel.connect()
            state = .connected(since: since)
            needsReconnectForKillSwitch = false
        } catch let err as MainScreenError {
            state = .error(message: err.errorDescription ?? "\(err)")
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }
}
