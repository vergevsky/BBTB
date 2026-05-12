import Foundation
import SwiftUI
import SwiftData
import VPNCore
import ConfigParser
import Localization
import ServerListFeature

@MainActor
public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState = .empty
    @Published public private(set) var activeServerName: String?
    @Published public private(set) var supportedConfigCount: Int = 0
    @Published public private(set) var unsupportedConfigCount: Int = 0
    @Published public private(set) var needsReconnectForKillSwitch: Bool = false
    @Published public private(set) var importInProgress: Bool = false
    @Published public var lastError: String?

    // Phase 3 Plan 03 — server list sheet driver + manual selection state.
    @Published public var isPresentingServerList: Bool = false
    /// nil = Auto mode (default). Plan 05 будет persist'ить + reconnect-on-active.
    @Published public var selectedServerID: UUID? = nil

    /// ServerListFeature view-model. Создаётся при наличии modelContainer/probeService;
    /// nil-safe для existing Phase 2 callsites без DI (backward compat).
    public let serverListViewModel: ServerListViewModel?

    public let importer: ConfigImporting
    public let tunnel: TunnelControlling

    private var killSwitchObserver: NSObjectProtocol?
    private var lastKillSwitchValue: Bool

    /// Phase 2 backward-compat init — без modelContainer/probeService → serverListViewModel = nil.
    public convenience init(importer: ConfigImporting, tunnel: TunnelControlling) {
        self.init(importer: importer,
                  tunnel: tunnel,
                  modelContainer: nil,
                  probeService: nil)
    }

    /// Phase 3 full DI init. При наличии modelContainer создаётся ServerListViewModel и
    /// linkуется к coordinator = self (через ServerSelectionCoordinating extension ниже).
    public init(importer: ConfigImporting,
                tunnel: TunnelControlling,
                modelContainer: ModelContainer?,
                probeService: ServerProbeService? = nil) {
        self.importer = importer
        self.tunnel = tunnel
        self.lastKillSwitchValue = UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true

        if let container = modelContainer {
            let probe = probeService ?? ServerProbeService()
            // Plan 04 — pass importer для pullToRefresh/merge через ConfigImporting protocol.
            let listVM = ServerListViewModel(
                modelContainer: container,
                probeService: probe,
                importer: importer
            )
            self.serverListViewModel = listVM
        } else {
            self.serverListViewModel = nil
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
            if let server = importer.loadActiveServer() {
                activeServerName = currentServerLineText(supportedCount: count, fallbackName: server.name)
            } else {
                activeServerName = currentServerLineText(supportedCount: count, fallbackName: nil)
            }
            if case .empty = state { state = .idle }
            // Otherwise preserve the current state (.connecting, .connected, .error).
        }
    }

    /// D-11 — Server line text:
    /// - Если ≥2 supported → "Авто".
    /// - Если 1 supported → ServerConfig.name (или fallback).
    /// - Если 0 → nil.
    private func currentServerLineText(supportedCount: Int, fallbackName: String?) -> String? {
        guard supportedCount > 0 else { return nil }
        if supportedCount > 1 { return L10n.serverAuto }
        return fallbackName
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
                let since = try await tunnel.connect()
                state = .connected(since: since)
                needsReconnectForKillSwitch = false
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

    /// D-14 — UserDefaults observer. Если значение killSwitchEnabled поменялось И туннель
    /// активен → показать ReconnectBanner.
    private func handleUserDefaultsChange() {
        let current = UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true
        if current != lastKillSwitchValue {
            lastKillSwitchValue = current
            if case .connected = state {
                needsReconnectForKillSwitch = true
            }
        }
    }
}

// MARK: - ServerSelectionCoordinating (Phase 3 Plan 03)
//
// One-way coordination MainScreenFeature → ServerListFeature. Plan 03 пишет
// selectedServerID + закрывает sheet; Plan 05 расширит reconnect-on-active-tunnel.
extension MainScreenViewModel: ServerSelectionCoordinating {
    public func applySelection(_ id: UUID?) {
        selectedServerID = id
        // Plan 05: если case .connected = state → call ConfigImporter.provisionTunnelProfile(for: id) + reconnect.
    }

    public func dismissServerList() {
        isPresentingServerList = false
    }
}

