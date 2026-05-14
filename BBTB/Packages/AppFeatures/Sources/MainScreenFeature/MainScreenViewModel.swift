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

/// Phase 6d / Wave 06D-03c — value-type snapshot одного supported `ServerConfig`,
/// который можно безопасно держать @Published в @MainActor VM без удержания
/// SwiftData @Model object reference. Используется:
///  - **fast-path auto-select** в `performToggleImpl()` — winner выбирается
///    из cached `lastLatencyMs` / `failedProbeCount` без блокирующего
///    `performPreConnectAutoSelect()` probe-fan-out.
///  - в будущем (UI hooks) — server picker может рендерить snapshot без
///    дополнительного fetch (T-NA — non-goal for 06D-03c).
///
/// Populated **из того же fetch'а**, который `refresh()` использует для count/active-name,
/// поэтому никакого extra SwiftData round-trip-а не добавляется (closes H4 part 2:
/// "performPreConnectAutoSelect повторно fetches ServerConfig rows, которые
/// refresh() уже посчитал").
public struct SupportedServerSnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let lastLatencyMs: Int?
    public let failedProbeCount: Int

    public init(id: UUID, name: String, lastLatencyMs: Int?, failedProbeCount: Int) {
        self.id = id
        self.name = name
        self.lastLatencyMs = lastLatencyMs
        self.failedProbeCount = failedProbeCount
    }
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

    /// Phase 6d / Wave 06D-03c (H4) — cached snapshot of all supported servers.
    /// Populated в `refresh()` из того же fetch'а, который драйвит
    /// `supportedConfigCount` / `activeServerName` — без extra SwiftData round-trip.
    /// Используется hot-path auto-mode в `performToggleImpl()` чтобы
    /// **избежать** блокирующего N-сервер probe-fan-out на каждый Connect tap;
    /// фоновое обновление latencies — `refreshProbeScoresInBackground()`.
    @Published public private(set) var supportedServerSnapshot: [SupportedServerSnapshot] = []

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

    /// Phase 6d Wave 03f (M1) — guards the init-time `loadAllFromPreferences()`
    /// seed Task. App.init runs `tunnel.bootstrap(...)` which seeds the cached
    /// manager via ONE XPC trip and then calls `applyInitialStatusSnapshot(_:)`
    /// here. Whichever of the two completes first flips this flag; the other
    /// becomes a no-op. Eliminates the duplicate `loadAllFromPreferences()` XPC
    /// trip on cold start (one of the 6-8 Mach-port-contending init tasks that
    /// triggered the M1 finding from Wave 06D-01).
    private var initialManagersApplied: Bool = false

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
        //
        // queue: nil (а не .main) — критично: с queue: .main notification теряется
        // во время Settings → VPN → toggle off, потому что main queue приостановлена
        // пока приложение в background, и iOS не replays. Internal Task { @MainActor }
        // hop ниже всё равно гарантирует, что мутация `state`/`reconnectBannerState`
        // происходит на main. См. re-UAT 2026-05-13 Settings-disable PARTIAL FAIL.
        self.nevpnStatusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            // Both reads — NEVPNConnection.status и NEVPNConnection.connectedDate
            // — синхронные свойства (НЕ XPC; см. lesson feedback_nevpn_xpc_mach_port.md).
            // connectedDate — реальный момент установления туннеля; используется
            // как авторитет для UI таймера, чтобы он не обнулялся при возврате
            // приложения в foreground (re-UAT 2026-05-13 Замечание 1).
            let status = conn.status
            let connectedDate = conn.connectedDate
            Task { @MainActor [weak self] in
                self?.applyVPNStatus(status, connectedDate: connectedDate)
            }
        }

        // Phase 6c / Plan 06C-04 Task 3b (Round 5 amendment) — seed initial
        // status ONCE at init, чтобы избежать «wrong state flash» до прихода
        // первой NEVPNStatusDidChange notification.
        //
        // Phase 6d Wave 03f (M1) — теперь GUARDED через `initialManagersApplied`.
        // `BBTB_iOSApp.init` / `BBTB_macOSApp.init` после Wave 03f запускают
        // `tunnel.bootstrap(...)` который сам делает ОДИН `loadAllFromPreferences`
        // (внутри `refreshCachedManager`) и затем вызывает
        // `applyInitialStatusSnapshot(_:)` с уже прочитанным status/connectedDate.
        // Если bootstrap успел первым — этот Task видит `initialManagersApplied
        // == true` ДО XPC trip и сразу выходит, никакого второго `loadAllFromPreferences`.
        // Если этот Task случайно стартует раньше bootstrap (test paths / VM
        // создан без App.init wiring) — он делает свой XPC trip и сам флипнет
        // флаг, делая последующий `applyInitialStatusSnapshot` идемпотентным
        // no-op. Идёт через тот же `applyVPNStatus(_:)` авторитет (D-09).
        Task { @MainActor [weak self] in
            guard let self, !self.initialManagersApplied else { return }
            let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
            // Recheck — bootstrap could have flipped the flag while await above suspended.
            guard !self.initialManagersApplied else { return }
            let ours = ManagerSelector.ourManagers(from: managers).first
            let initialStatus = ours?.connection.status ?? .invalid
            let initialConnectedDate = ours?.connection.connectedDate
            self.initialManagersApplied = true
            self.applyVPNStatus(initialStatus, connectedDate: initialConnectedDate)
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
        // Phase 6d / Wave 06D-03c (H4) — ЕДИНСТВЕННЫЙ fetch supported серверов.
        // Старая реализация делала count-fetch здесь + повторный fetch в
        // performPreConnectAutoSelect; теперь оба источника едят из одного
        // массива. Если modelContainer недоступен (Phase 2 backward-compat
        // init без DI) — fallback на старую count-only ветку через importer.
        //
        // Wave 06D-03e Commit 4 (M4 residual): inline selection-reconcile вместо
        // отдельного `await reconcileSelectionWithStore()` — мы уже держим
        // `supported` массив, проверяем `selectedServerID` membership через
        // Swift filter (O(N) in memory) вместо второго SwiftData fetch с
        // #Predicate { $0.id == id }. Закрывает M4 N+1 fully:
        //   refresh() = 1 fetch на DI path; 0 fetches на legacy fallback path.
        // Public `reconcileSelectionWithStore()` остаётся для тестов
        // (AutoSelectIntegrationTests.T6) и других callers, ведущих к delete-race.
        if let container = modelContainer {
            let context = ModelContext(container)
            // memory feedback_swiftdata_uuid_predicate.md: для UUID? используем
            // fetch-all + Swift filter; здесь predicate БЕЗ UUID? (isSupported Bool),
            // поэтому #Predicate безопасен.
            let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })
            let supported = (try? context.fetch(desc)) ?? []
            // Snapshot — Sendable value-type slice from already-fetched rows.
            // No extra round-trip.
            supportedServerSnapshot = supported.map {
                SupportedServerSnapshot(
                    id: $0.id,
                    name: $0.name,
                    lastLatencyMs: $0.lastLatencyMs,
                    failedProbeCount: $0.failedProbeCount ?? 0
                )
            }
            supportedConfigCount = supported.count
            // Inline selection-reconcile (M4 residual): O(N) Swift filter against
            // the already-fetched array — отдельный SwiftData fetch не нужен.
            if let id = selectedServerID,
               !supported.contains(where: { $0.id == id }) {
                selectedServerID = nil
            }
            if supported.isEmpty {
                activeServerName = nil
                state = .empty
            } else {
                activeServerName = resolveServerLineNameFromSnapshot()
                if case .empty = state { state = .idle }
            }
        } else {
            let count = importer.countSupportedConfigs()
            supportedConfigCount = count
            supportedServerSnapshot = []
            if count == 0 {
                activeServerName = nil
                state = .empty
            } else {
                activeServerName = await resolveServerLineName(supportedCount: count)
                if case .empty = state { state = .idle }
            }
            // Legacy fallback path: container nil → нет источника для reconcile;
            // selectedServerID остаётся (поведение совпадает с прежним
            // reconcileSelectionWithStore guard, который тоже возвращал early).
        }
    }

    /// Wave 06D-03c — derive server line name из cached snapshot без отдельного
    /// SwiftData fetch. Поведение совпадает с прежним `resolveServerLineName`:
    /// если selectedID matches snapshot — возвращаем имя; если supported > 1 —
    /// `L10n.serverAuto`; единственный supported — его имя.
    private func resolveServerLineNameFromSnapshot() -> String? {
        guard !supportedServerSnapshot.isEmpty else { return nil }
        if let id = selectedServerID,
           let match = supportedServerSnapshot.first(where: { $0.id == id }) {
            return match.name
        }
        if supportedServerSnapshot.count > 1 { return L10n.serverAuto }
        return supportedServerSnapshot.first?.name
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
    internal func applyVPNStatus(_ status: NEVPNStatus, connectedDate: Date? = nil) {
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
            // Promote main state to `.connected(since:)`. `since` авторитетно
            // берётся из `NEVPNConnection.connectedDate` (когда вызывающий смог
            // прочитать его) — это РЕАЛЬНЫЙ момент установления туннеля. Иначе
            // sticky-fallback к существующему `state.connectionStart`, а в
            // самом крайнем случае — `Date()`. Это критично для сценария
            // «BBTB включён из iOS Settings, app открыли через час»: без
            // connectedDate таймер начал бы считать от момента foreground, а
            // не от реального connect (re-UAT 2026-05-13 Замечание 1).
            // Preserve `.empty` (нет конфигов — статус идёт от чужого профиля).
            switch state {
            case .empty:
                break
            default:
                let since = connectedDate ?? state.connectionStart ?? Date()
                state = .connected(since: since)
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

    /// Phase 6d Wave 03f (M1) — receive an already-loaded snapshot of NEVPN
    /// state from `TunnelController.bootstrap(...)` so the App.init flow
    /// reuses ONE `loadAllFromPreferences()` XPC trip across (a) seeding the
    /// `TunnelController.cachedManager` AND (b) seeding the VM UI state. Prior
    /// flow paid 2 XPC trips (one in `startReachability` → `refreshCachedManager`,
    /// one in this VM's own init seed Task) competing with watchdog/migration
    /// tasks for Mach ports.
    ///
    /// Idempotent — sets `initialManagersApplied` so the in-flight init seed
    /// Task becomes a no-op on its post-`await` recheck. Uses
    /// `applyVPNStatus(_:connectedDate:)` as the single UI authority (D-09).
    /// `connectedDate` propagates so the connection timer authority (re-UAT
    /// 2026-05-13 Замечание 1) survives the bootstrap path.
    public func applyInitialStatusSnapshot(_ snapshot: InitialStatusSnapshot) {
        guard !initialManagersApplied else { return }
        initialManagersApplied = true
        applyVPNStatus(snapshot.status, connectedDate: snapshot.connectedDate)
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

    /// Phase 6c / Plan 06C-04 Task 3b — foreground resync of authoritative VPN status.
    ///
    /// Why this exists: при отключении BBTB через iOS Settings → VPN → toggle off
    /// приложение в этот момент находится в background; `NEVPNStatusDidChange` для
    /// итогового `.disconnected` может быть coalesced/dropped пока main queue
    /// приостановлена, и iOS не воспроизводит её при возврате. Итог — VM `state`
    /// зависает на `.connected(since:)` даже когда системный туннель уже выключен
    /// (Settings-disable re-UAT 2026-05-13, PARTIAL FAIL). `TunnelController` observer
    /// использует `queue: nil` и поэтому выживает; VM observer вынужден трогать
    /// `@Published` на main, поэтому мы добавляем foreground-resync: одна XPC-поездка,
    /// фильтр через `ManagerSelector`, чтение `connection.status`, прогон через
    /// `applyVPNStatus(_:)` (единственный авторитет UI).
    ///
    /// Стоимость: одно `loadAllFromPreferences` на каждый scene `.active`. Не в hot
    /// loop, укладывается в "≤1 XPC per significant event" из Phase 6 (нет
    /// PORT_SPACE-риска, см. `feedback_nevpn_xpc_mach_port.md`).
    public func handleForeground() async {
        let managers: [NETunnelProviderManager]
        do {
            managers = try await NETunnelProviderManager.loadAllFromPreferences()
        } catch {
            // Transient XPC failure — keep last state rather than flipping to `.invalid`.
            return
        }
        guard let ours = ManagerSelector.ourManagers(from: managers).first else {
            // No BBTB profile installed — leave `.empty`/current state alone.
            return
        }
        // connectedDate — sync read, без XPC; для сценария «BBTB включён из
        // iOS Settings без захода в app» это единственный источник реального
        // start time (re-UAT 2026-05-13 Замечание 1).
        applyVPNStatus(ours.connection.status, connectedDate: ours.connection.connectedDate)
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
                    let winnerID = try await selectAutoWinner()
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

    /// Phase 6d / Wave 06D-03c (H4) — Auto-mode winner selection с двумя путями:
    ///
    ///  1. **Fast path (hot tap):** есть cached `supportedServerSnapshot` (refresh()
    ///     уже отработал). Winner выбирается по `lastLatencyMs` ascending; серверы
    ///     с `failedProbeCount >= 3` (unreachable) исключаются. После tap'а
    ///     spawn background `refreshProbeScoresInBackground()` чтобы данные были
    ///     свежими для следующего tap'а.
    ///
    ///  2. **Slow path (cold first launch):** snapshot пустой (например, app
    ///     только что запустился и `refresh()` ещё не закончился, либо у нас нет
    ///     modelContainer в backward-compat init). Падаем на старый
    ///     `performPreConnectAutoSelect()` — теперь с bounded probeAll (cap=8,
    ///     см. Wave 06D-03c Commit 1).
    private func selectAutoWinner() async throws -> UUID {
        let cache = supportedServerSnapshot
        if cache.isEmpty {
            // Cold path — нет cache (modelContainer == nil branch refresh()'a
            // ИЛИ store пуст). Делаем full pre-connect probe.
            return try await performPreConnectAutoSelect()
        }

        // Cache полезна только если есть достоверная probe-история хотя бы
        // об одном сервере. Свежий store на cold launch имеет
        // `lastLatencyMs == nil` И `failedProbeCount == 0` у всех серверов —
        // в этом случае cache бесполезна, fall back на full probe чтобы получить
        // настоящие latency-данные. Также гарантирует semantics существующих
        // тестов AutoSelectIntegrationTests (cold-DB → probe-driven selection).
        let hasUsableData = cache.contains {
            $0.lastLatencyMs != nil || $0.failedProbeCount > 0
        }
        guard hasUsableData else {
            return try await performPreConnectAutoSelect()
        }

        // Fast path — выбираем из cache. Исключаем unreachable (failed >= 3).
        let reachable = cache.filter { $0.failedProbeCount < 3 }
        guard !reachable.isEmpty else {
            // Все cached серверы помечены unreachable → попробуем fresh probe
            // (медленно, но даёт шанс что что-то «поднялось»).
            return try await performPreConnectAutoSelect()
        }
        // По latency ascending; nil latency считается hugest (Int.max).
        let winner = reachable.min(by: { lhs, rhs in
            let l = lhs.lastLatencyMs ?? Int.max
            let r = rhs.lastLatencyMs ?? Int.max
            return l < r
        })
        guard let winnerID = winner?.id else {
            return try await performPreConnectAutoSelect()
        }

        // Spawn background probe refresh — НЕ блокирует connect tap, обновит
        // latencies в SwiftData rows, refresh() при следующем cycle прочтёт
        // свежий snapshot. weak self чтобы избежать retain через captured Task.
        // Bounded probe (cap=8) обеспечивает безопасность parallel fan-out.
        Task.detached { [weak self] in
            await self?.refreshProbeScoresInBackground()
        }

        return winnerID
    }

    /// Phase 6d / Wave 06D-03c (H4) — background probe refresh. Probes ВСЕ
    /// supported серверы (bounded cap=8 в ServerProbeService), сохраняет
    /// результаты в SwiftData rows (`lastLatencyMs` + `failedProbeCount` +
    /// `lastPingedAt`). НЕ блокирует Connect tap — вызывается из
    /// `Task.detached { await self?.refreshProbeScoresInBackground() }` **после**
    /// того, как winner уже выбран из cache и provisioning стартовал.
    ///
    /// Метод сам исполняется на MainActor (как и весь VM); главное —
    /// внешний `Task.detached` развязал его от call-site, чтобы Connect tap
    /// не блокировался ожиданием probes (~500-1500ms на 30-50 серверах).
    private func refreshProbeScoresInBackground() async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })
        let rows = (try? context.fetch(desc)) ?? []
        guard !rows.isEmpty else { return }
        let payload: [(id: UUID, host: String, port: Int)] = rows.map {
            (id: $0.id, host: $0.host, port: $0.port)
        }

        // probeService.probeAll использует bounded concurrency (cap=8, Commit 1).
        var aggregates: [UUID: ProbeAggregate] = [:]
        for await (id, agg) in probeService.probeAll(payload) {
            aggregates[id] = agg
        }
        guard !aggregates.isEmpty else { return }

        // Write-back обновлённых latency/failedProbeCount в SwiftData.
        // Используем тот же fetch массив (rows), чтобы не делать двойной round-trip.
        for row in rows {
            if let agg = aggregates[row.id] {
                row.lastLatencyMs = agg.avgLatencyMs
                row.failedProbeCount = agg.failures
                row.lastPingedAt = agg.probedAt
            }
        }
        try? context.save()

        // Refresh @Published snapshot чтобы следующий Connect tap читал
        // свежие данные. Используем уже-загруженный массив rows.
        supportedServerSnapshot = rows.map {
            SupportedServerSnapshot(
                id: $0.id,
                name: $0.name,
                lastLatencyMs: $0.lastLatencyMs,
                failedProbeCount: $0.failedProbeCount ?? 0
            )
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
