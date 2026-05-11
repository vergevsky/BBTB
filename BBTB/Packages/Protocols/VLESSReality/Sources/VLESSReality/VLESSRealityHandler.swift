import Foundation
import VPNCore

/// PROTO-01 — VLESS + Vision + Reality.
/// Главный anti-ТСПУ протокол Phase 1 (единственный включённый в v0.1).
public struct VLESSRealityHandler: VPNProtocolHandler {
    public static let identifier = "vless-reality"
    public static let displayName = "VLESS + Vision + Reality"

    public var isAvailable: Bool { true }

    public init() {}

    public func validate(config: ProtocolConfig) throws {
        // Phase 1: validate просто проверяет identifier; полный sing-box validate
        // делается через PacketTunnelKit.SingBoxConfigLoader перед стартом туннеля.
        guard config.identifier == Self.identifier else {
            throw HandlerError.identifierMismatch(expected: Self.identifier, got: config.identifier)
        }
    }

    public func connect(config: ProtocolConfig) async throws -> TunnelHandle {
        // Phase 1: connect через VPNProtocolHandler — НЕ используется в production flow.
        // Real start идёт через NETunnelProviderManager.connection.startVPNTunnel,
        // не через handler. handler.connect — для Phase 4+ когда будут multiple протоколы
        // и handler станет orchestration-layer.
        return TunnelHandle()
    }

    public func disconnect(handle: TunnelHandle) async throws {
        // Phase 1 — no-op (см. .connect)
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
