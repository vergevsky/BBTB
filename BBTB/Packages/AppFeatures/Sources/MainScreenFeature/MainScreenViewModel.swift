import Foundation
import SwiftUI
import VPNCore

@MainActor
public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState = .empty
    @Published public private(set) var activeServerName: String?
    @Published public var lastError: String?

    public let importer: ConfigImporting
    public let tunnel: TunnelControlling

    public init(importer: ConfigImporting, tunnel: TunnelControlling) {
        self.importer = importer
        self.tunnel = tunnel
        Task { await refresh() }
    }

    public func refresh() async {
        // Phase 1: один активный конфиг (singleton). Если есть — переходим в .idle.
        if let server = importer.loadActiveServer() {
            activeServerName = server.name
            state = .idle
        } else {
            activeServerName = nil
            state = .empty
        }
    }

    public func importFromPasteboard() {
        Task { await performImport() }
    }

    public func toggleConnection() {
        Task { await performToggle() }
    }

    private func performImport() async {
        lastError = nil
        do {
            let server = try await importer.importFromPasteboard()
            activeServerName = server.name
            state = .idle
        } catch {
            lastError = error.localizedDescription
            state = .error(message: error.localizedDescription)
        }
    }

    private func performToggle() async {
        switch state {
        case .idle, .error:
            state = .connecting
            do {
                let since = try await tunnel.connect()
                state = .connected(since: since)
            } catch {
                state = .error(message: error.localizedDescription)
            }
        case .connected:
            do {
                try await tunnel.disconnect()
                state = .idle
            } catch {
                state = .error(message: error.localizedDescription)
            }
        case .connecting, .empty:
            break
        }
    }
}
