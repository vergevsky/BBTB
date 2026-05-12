import Foundation
import VPNCore

/// PROTO-05 — Hysteria2 over QUIC/UDP (HTTP/3 ALPN).
///
/// Phase 4 (v0.4) добавляет пятый handler в `ProtocolRegistry` рядом с VLESS+Reality,
/// Trojan, VLESS+TLS, Shadowsocks. Hysteria2 включается в `urltest` pool для auto-failover
/// (D-01 / PROTO-10).
///
/// **D-07/D-08:** sing-box outbound `type: "hysteria2"` с полями `password` (auth),
/// `tls.{server_name,insecure,alpn:["h3"],utls,certificate_public_key_sha256?}`, опционально
/// `obfs:{type:"salamander",password}`.
///
/// **R1 EXCEPTION (D-08):** Hysteria2 — ЕДИНСТВЕННЫЙ протокол, где `tls.insecure: true`
/// legitimate. Управляется через URI flag `insecure=1` (или синонимы allowInsecure/skip-cert-verify);
/// обусловлено реальностью self-hosted Hy2 серверов с self-signed certs.
public struct Hysteria2Handler: VPNProtocolHandler {
    public static let identifier = "hysteria2"  // lowercase, matches AnyParsedConfig.hysteria2 case
    public static let displayName = "Hysteria2"

    public var isAvailable: Bool { true }

    public init() {}

    public func validate(config: ProtocolConfig) throws {
        // Phase 4: validate просто проверяет identifier; полный sing-box validate
        // делается через PacketTunnelKit.SingBoxConfigLoader перед стартом туннеля.
        guard config.identifier == Self.identifier else {
            throw HandlerError.identifierMismatch(expected: Self.identifier, got: config.identifier)
        }
    }

    public func connect(config: ProtocolConfig) async throws -> TunnelHandle {
        // Phase 4: connect через VPNProtocolHandler — НЕ используется в production flow.
        // Real start идёт через NETunnelProviderManager.connection.startVPNTunnel.
        return TunnelHandle()
    }

    public func disconnect(handle: TunnelHandle) async throws {
        // Phase 4 — no-op (см. .connect)
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
