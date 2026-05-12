import Foundation
import VPNCore

/// PROTO-04 — Shadowsocks (SIP002 / SIP022).
///
/// Phase 4 (v0.4) добавляет четвёртый handler в `ProtocolRegistry` рядом с VLESS+Reality,
/// Trojan, VLESS+TLS. Shadowsocks включается в `urltest` pool для auto-failover (D-01 / PROTO-10).
///
/// **D-04:** Whitelist методов в `ShadowsocksURIParser.supportedSSMethods` — SS-2022 + legacy AEAD.
/// **D-05:** sing-box outbound `type: "shadowsocks"` с полями `method` / `password` / `network`.
/// **D-11:** Outline access keys = SIP002 ss:// — обрабатываются тем же handler-ом.
///
/// **R1 invariant trivial:** Shadowsocks НЕ использует TLS на транспортном уровне — encryption
/// делается на уровне протокола (поэтому `SingBoxConfigTemplate.shadowsocks.json` НЕ содержит
/// `tls` block в outbound[0]). D-08 R1 exception (`insecure: true`) применяется ТОЛЬКО к
/// Hysteria2, не к Shadowsocks.
public struct ShadowsocksHandler: VPNProtocolHandler {
    public static let identifier = "shadowsocks"  // lowercase, matches AnyParsedConfig.shadowsocks case
    public static let displayName = "Shadowsocks"

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
