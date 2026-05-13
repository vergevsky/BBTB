import Foundation
import SwiftUI
import SwiftData
import VPNCore
import ConfigParser
import Localization
import NetworkExtension
import ServerListFeature

/// Phase 6c / Plan 06C-04 Task 3b — UI state for the reconnect banner.
/// Drives the message inside `ReconnectBanner`.
///
/// Apple's `NEOnDemandRule` owns retries — мы больше не показываем «попытка N
/// из 3», потому что retries у iOS могут длиться значительно дольше нашего
/// прежнего exponential-backoff бюджета (UX-неправильно показывать
/// «всё failed» пока iOS ещё retries). Поэтому Phase 6c набор:
///
/// - `.hidden`              — баннера нет.
/// - `.killSwitchReconfigure` — Phase 2 KillSwitch toggle поменялся при
///                              active tunnel; пользователь должен переподключиться.
/// - `.connecting`          — tunnel в `.connecting` или `.reasserting`
///                            (Apple's on-demand reconnect или явный Connect).
/// - `.failover(toServerName:)` — `TunnelWatchdog` сознательно переключил
///                                сервер из round-robin пула (NET-11).
///
/// **Round 5 trim (commit 06C-04 Task 3b):** `.retrying(attempt:delaySeconds:)`
/// и `.allFailed` УДАЛЕНЫ — их feed'ил `ReconnectStateMachine`, который
/// удаляется в Task 3c.
public enum ReconnectBannerState: Equatable, Sendable {
    case hidden
    case killSwitchReconfigure
    case connecting
    case failover(toServerName: String)
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
    /// Phase 6c / Plan 06C-04 Task 3b — теперь обновляется реактивно из
    /// `applyVPNStatus(_:)` (NEVPNStatus authority) + опционально через
    /// `showFailoverBanner(toServerName:)` (watchdog callback).
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

    /// Phase 6c / Plan 06C-04 Task 3b — `NEVPNStatusDidChange` observer.
    /// Reads `NEVPNConnection.status` directly from `notification.object` (sync
    /// property, NO XPC trips — см. lesson `feedback_nevpn_xpc_mach_port.md`).
    /// Dispatches into `applyVPNStatus(_:)` which is the SINGLE authority for
    /// both `state` (ConnectionState) AND `reconnectBannerState` transitions
    /// driven by NE events. Старый relay-через-ReconnectStateMachine path
    /// УДАЛЁН в Task 3b — NEVPNStatus теперь единственный driver UI.
    private var nevpnStatusObserver: NSObjectProtocol?

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
        if let stored = userDefaults.string(forKey: Self.selectedServerIDKey),
           let uuid = UUID(uuidString: stored) {
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

        // Phase 6c / Plan 06C-04 Task 3b — reactive UI driver. NEVPNStatusDidChange
        // observer; status read DIRECTLY from notification.object (NEVPNConnection.status
        // — synchronous, NOT XPC) чтобы избежать Mach-port storm на iOS 26
        // (см. lesson feedback_nevpn_xpc_mach_port.md). applyVPNStatus(_:)
        // — SINGLE source of truth для main `state` AND `reconnectBannerState`
        // на статус-обновлениях.
        self.nevpnStatusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            let status = conn.status
            Task { @MainActor [weak self] in
                self?.applyVPNStatus(status)
            }
        }

        // Phase 6c / Plan 06C-04 Task 3b (Round 5 amendment) — seed initial
        // status ONCE at init, чтобы избежать «wrong state flash» до прихода
        // первой NEVPNStatusDidChange notification. Single XPC trip
        // (`loadAllFromPreferences`) на app launch — допустимо (не в hot path
        // и не периодическое; один раз при VM creation).
        Task { @MainActor [weak self] in
            let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
            let ours = ManagerSelector.ourManagers(from: managers).first
            let initialStatus = ours?.connection.status ?? .invalid
            self?.applyVPNStatus(initialStatus)
        }

        // После init собственного состояния — подключаем coordinator backlink.
        // ServerListViewModel.coordinator — weak, retain cycle исключён.
        self.serverListViewModel?.coordinator = self
    }

    /// Open server-list sheet (привязка tap ServerLineView).
    public func presentServerList() {
        isPresentingServerList = true
    }

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

    // MARK: - Phase 6c / Plan 06C-04 Task 3b — banner mapping helpers

    /// Localized banner message for the current `reconnectBannerState`.
    /// Returns `nil` when banner should be hidden.
    public var reconnectBannerMessage: String? {
        switch reconnectBannerState {
        case .hidden:
            return nil
        case .killSwitchReconfigure:
            return L10n.bannerReconnectNeeded
        case .connecting:
            // Phase 6c / Plan 06C-04 — Apple's on-demand reconnect в полёте
            // ИЛИ явный Connect tap. NEVPNStatus = `.connecting`/`.reasserting`.
            return L10n.bannerConnecting
        case .failover:
            // TunnelWatchdog успешно переключил сервер из пула (NET-11).
            return L10n.bannerFailover
        }
    }

    /// Plan 06C-04 Task 3b (Round 5) — **the** reactive UI driver. SINGLE authority
    /// для both `state` (ConnectionState) AND `reconnectBannerState` на основе
    /// `NEVPNStatus`. NE status — авторитет; `connect()` / `disconnect()` отныне
    /// command-методы, которые лишь _инициируют_ transition (и могут установить
    /// `.error` на throw), но не пишут `.connected(since:)` сами.
    ///
    /// `.empty` (нет конфигов) НЕ overwrite'ится — пользователь не может подключаться
    /// без profile, статус в этом случае нерелевантен. `.error(...)` тоже
    /// preserve'ится — это явный command failure, который пользователь должен
    /// увидеть, а не маскировать transient `.disconnected`.
    /// Phase 6c / Plan 06C-04 Task 3c — visibility relaxed from `private` to
    /// `internal` так, чтобы integration-тесты (AutoSelectIntegrationTests)
    /// могли симулировать NEVPNStatusDidChange-driven transitions без живого
    /// NEVPNConnection. Production path не меняется — единственный caller
    /// остаётся `nevpnStatusObserver` блок в `init` + initial-status seed.
    internal func applyVPNStatus(_ status: NEVPNStatus) {
        switch status {
        case .connecting, .reasserting:
            // Main state — НЕ трогаем `.empty` (нет конфигов) и `.error`
            // (явный command failure). Иначе → `.connecting` (идемпотентно).
            switch state {
            case .empty, .error, .connecting:
                break
            default:
                state = .connecting
            }
            // Banner — НЕ override killSwitchReconfigure / failover; иначе .connecting.
            switch reconnectBannerState {
            case .killSwitchReconfigure, .failover:
                break
            case .connecting, .hidden:
                reconnectBannerState = .connecting
            }
        case .connected:
            // Promote main state to `.connected(since: Date())`. Preserve
            // `.empty` (нет конфигов — статус идёт от чужого профиля).
            switch state {
            case .empty:
                break
            case .connected:
                // Уже connected — sticky `since`, no-op.
                break
            default:
                state = .connected(since: Date())
            }
            // Banner — `.connecting` снимаем; `.killSwitchReconfigure` и
            // `.failover` оставляем (оба — orthogonal sticky UI signals).
            switch reconnectBannerState {
            case .connecting:
                reconnectBannerState = needsReconnectForKillSwitch ? .killSwitchReconfigure : .hidden
            case .killSwitchReconfigure, .failover, .hidden:
                break
            }
        case .disconnected, .invalid, .disconnecting:
            // Demote main state. Preserve `.empty` (нет конфигов) и `.error`
            // (явный command failure — пользователь должен увидеть).
            switch state {
            case .empty, .error:
                break
            default:
                state = .idle
            }
            // Banner — `.connecting` снимаем; `.killSwitchReconfigure` (пользователь
            // должен переподключиться) оставляем; `.failover` снимаем (одноразовая
            // подсветка состоявшегося свопа — если соединение упало, она нерелевантна).
            switch reconnectBannerState {
            case .connecting, .failover:
                reconnectBannerState = needsReconnectForKillSwitch ? .killSwitchReconfigure : .hidden
            case .killSwitchReconfigure, .hidden:
                break
            }
        @unknown default:
            switch state {
            case .empty, .error:
                break
            default:
                state = .idle
            }
        }
    }

    // MARK: - Phase 6c / Plan 06C-04 Task 3b — watchdog → UI bridge

    /// Called by the `TunnelWatchdog.setFailoverObserver` callback (App init wires
    /// the callback to hop here on MainActor). Sets the failover banner with the
    /// new server's display name. Reactive driver `applyVPNStatus(.connected)`
    /// preserves it через следующий `.connected`; `.disconnected`/`.invalid`/
    /// `.disconnecting` сбросит его в `.hidden` (одноразовая подсветка —
    /// если соединение упало после свопа, "переключение" уже нерелевантно).
    public func showFailoverBanner(toServerName: String) {
        reconnectBannerState = .failover(toServerName: toServerName)
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
            // Eager flip to `.connecting` so the UI updates immediately;
            // the reactive driver (applyVPNStatus) reinforces on the next
            // NEVPNStatusDidChange notification и поставит `.connected(since:)`
            // когда iOS репортит `.connected`. Round 5: command methods просто
            // инициируют transition; NEVPNStatus = authority.
            state = .connecting
            do {
                if let selectedID = selectedServerID {
                    try await importer.provisionTunnelProfile(for: selectedID)
                } else {
                    let winnerID = try await performPreConnectAutoSelect()
                    try await importer.provisionTunnelProfile(for: winnerID)
                }
                _ = try await tunnel.connect()
                // Round 5 — НЕ устанавливаем state = .connected(since:) здесь.
                // Reactive driver увидит `.connected` от NEVPNStatusDidChange
                // и поставит `.connected(since: Date())`. NEVPNStatus = authority.
                needsReconnectForKillSwitch = false
            } catch let err as MainScreenError {
                state = .error(message: err.errorDescription ?? "\(err)")
            } catch {
                state = .error(message: error.localizedDescription)
            }
        case .connected:
            do {
                try await tunnel.disconnect()
                // Round 5 — НЕ устанавливаем state = .idle здесь.
                // Reactive driver увидит `.disconnected` и снимет state.
                needsReconnectForKillSwitch = false
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    /// Phase 3 / Plan 05 — pre-connect parallel TCP probe всех supported → ServerScore.autoSelect.
    private func performPreConnectAutoSelect() async throws -> UUID {
        guard let container = modelContainer else {
            throw MainScreenError.noSupportedServers
        }
        let context = ModelContext(container)
        let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })
        let supported = (try? context.fetch(desc)) ?? []
        guard !supported.isEmpty else { throw MainScreenError.noSupportedServers }

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
    public func reconcileSelectionWithStore() async {
        guard let container = modelContainer,
              let id = selectedServerID else { return }
        let context = ModelContext(container)
        let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
        let found = (try? context.fetch(desc).first) != nil
        if !found {
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
                // Phase 6c / Plan 06C-04 Task 3b — не перезаписываем active
                // failover-баннер (короткоживущ; пользователю полезнее).
                switch reconnectBannerState {
                case .failover:
                    break
                default:
                    reconnectBannerState = .killSwitchReconfigure
                }
            }
        }
    }
}

// MARK: - MainScreenError

/// Phase 3 / Plan 05 — error tags для performToggle / performPreConnectAutoSelect.
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

extension MainScreenViewModel: ServerSelectionCoordinating {
    public func applySelection(_ id: UUID?) {
        let previousID = selectedServerID
        selectedServerID = id
        guard previousID != id else { return }
        Task { @MainActor in await refresh() }
        if case .connected = state {
            Task { @MainActor in await reconnectAfterSelectionChange(newID: id) }
        }
    }

    public func dismissServerList() {
        isPresentingServerList = false
    }

    /// Plan 05 — D-09 reconnect sequence при смене selection в .connected.
    /// Round 5: reactive driver выставит `.connected(since:)` сам, когда iOS
    /// репортит `.connected` после нового `tunnel.connect()`.
    private func reconnectAfterSelectionChange(newID: UUID?) async {
        state = .connecting
        do {
            try await tunnel.disconnect()
            try await importer.provisionTunnelProfile(for: newID)
            _ = try await tunnel.connect()
            // Round 5 — `.connected(since:)` ставит reactive driver.
            needsReconnectForKillSwitch = false
        } catch let err as MainScreenError {
            state = .error(message: err.errorDescription ?? "\(err)")
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }
}
