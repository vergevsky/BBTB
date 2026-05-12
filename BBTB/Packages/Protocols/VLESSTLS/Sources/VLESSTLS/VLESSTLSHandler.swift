import Foundation
import VPNCore

/// PROTO-03 — VLESS+TLS (без Reality).
///
/// Phase 4 (v0.4) добавляет третий handler в `ProtocolRegistry` рядом с VLESS+Reality и Trojan.
/// VLESS+TLS включается в `urltest` pool для auto-failover (D-01 / PROTO-10).
///
/// **D-01:** Максимальное покрытие — Vision (`flow=xtls-rprx-vision`) частный случай, не
/// единственный. URI без `flow=` query → `ParsedVLESSTLS.flow == nil`, sing-box outbound
/// получит `flow: ""`.
///
/// **R1 invariant:** TLS validation всегда строгая — `insecure: false` hardcoded в template
/// и в ConfigBuilder pipeline. VLESS+TLS не имеет D-08 exception (только Hysteria2).
public struct VLESSTLSHandler: VPNProtocolHandler {
    public static let identifier = "vless-tls"  // lowercase, matches AnyParsedConfig.vlessTLS case
    public static let displayName = "VLESS + TLS"

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
