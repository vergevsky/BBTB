import Foundation
import VPNCore

/// PROTO-08 — TUIC v5 over QUIC (HTTP/3 ALPN).
///
/// Phase 7a (v0.7.1) добавляет 6-й handler в `ProtocolRegistry` рядом с VLESS+Reality,
/// VLESS+TLS/Vision, Trojan, Shadowsocks, Hysteria2. TUIC v5 включается в `urltest` pool
/// для auto-failover (PROTO-10 carry).
///
/// **Sing-box outbound:** `type: "tuic"` с полями `uuid`, `password`, `congestion_control`
/// (cubic/new_reno/bbr), `udp_relay_mode` (native/quic), `tls.{server_name, alpn:["h3"], utls}`.
///
/// **R1 STRICT:** TUIC v5 НЕ получает `allowInsecure` exception (в отличие от Hysteria2 D-08).
/// URI parameter `insecure=1` игнорируется в `TUICURIParser`.
public struct TUICHandler: VPNProtocolHandler {
    public static let identifier = "tuic"  // lowercase, matches AnyParsedConfig.tuic case
    public static let displayName = "TUIC v5"

    public var isAvailable: Bool { true }

    public init() {}

    public func validate(config: ProtocolConfig) throws {
        // Phase 7a: validate просто проверяет identifier; полный sing-box validate
        // делается через PacketTunnelKit.SingBoxConfigLoader перед стартом туннеля.
        guard config.identifier == Self.identifier else {
            throw HandlerError.identifierMismatch(expected: Self.identifier, got: config.identifier)
        }
    }

    public func connect(config: ProtocolConfig) async throws -> TunnelHandle {
        // Phase 7a: connect через VPNProtocolHandler — НЕ используется в production flow.
        // Real start идёт через NETunnelProviderManager.connection.startVPNTunnel.
        return TunnelHandle()
    }

    public func disconnect(handle: TunnelHandle) async throws {
        // Phase 7a — no-op (см. .connect)
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
