import Foundation
import VPNCore

/// PROTO-02 — Trojan over TCP+TLS / WebSocket+TLS.
///
/// Phase 2 (v0.2) добавляет второй handler в `ProtocolRegistry` рядом с VLESS+Reality.
/// Trojan включается в `urltest` pool для auto-failover (D-01 / PROTO-10).
///
/// **R1 invariant:** TLS validation всегда строгая — `insecure: false` hardcoded в обоих
/// templates. URI param `allowInsecure=1` ignored в `TrojanURIParser` (D-08).
public struct TrojanHandler: VPNProtocolHandler {
    public static let identifier = "trojan"  // lowercase, matches URI scheme
    public static let displayName = "Trojan"

    public var isAvailable: Bool { true }

    public init() {}

    public func validate(config: ProtocolConfig) throws {
        // Phase 2: validate просто проверяет identifier; полный sing-box validate
        // делается через PacketTunnelKit.SingBoxConfigLoader перед стартом туннеля.
        guard config.identifier == Self.identifier else {
            throw HandlerError.identifierMismatch(expected: Self.identifier, got: config.identifier)
        }
    }

    public func connect(config: ProtocolConfig) async throws -> TunnelHandle {
        // Phase 2: connect через VPNProtocolHandler — НЕ используется в production flow.
        // Real start идёт через NETunnelProviderManager.connection.startVPNTunnel.
        return TunnelHandle()
    }

    public func disconnect(handle: TunnelHandle) async throws {
        // Phase 2 — no-op (см. .connect)
    }

    public func diagnostics() async -> ProtocolDiagnostics {
        ProtocolDiagnostics()
    }

    public enum HandlerError: Error, LocalizedError {
        case identifierMismatch(expected: String, got: String)
        public var errorDescription: String? {
            switch self {
            case .identifierMismatch(let e, let g): return "Handler ID mismatch: expected \(e), got \(g)"
            }
        }
    }
}
