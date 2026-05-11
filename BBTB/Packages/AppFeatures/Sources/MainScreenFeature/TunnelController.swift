import Foundation
import NetworkExtension

public protocol TunnelControlling: AnyObject, Sendable {
    func connect() async throws -> Date
    func disconnect() async throws
}

public final class TunnelController: TunnelControlling, @unchecked Sendable {
    public init() {}

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

        // Поллим до .connected или error (Phase 1 — простая логика; Phase 6 NET-08 даст auto-reconnect).
        let started = Date()
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            switch manager.connection.status {
            case .connected: return started
            case .disconnecting, .invalid, .disconnected:
                throw NSError(domain: "BBTB.TunnelController", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Connection failed (status: \(manager.connection.status.rawValue))"])
            default: continue
            }
        }
        throw NSError(domain: "BBTB.TunnelController", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "Connection timed out after 30s"])
    }

    public func disconnect() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        managers.first?.connection.stopVPNTunnel()
    }
}
