import Foundation

/// Plugin contract for VPN protocols (CORE-02 per D-02 in CONTEXT.md).
/// Implemented in Phase 1 only by VLESSReality. Future phases add Trojan, WireGuard, etc.
public protocol VPNProtocolHandler: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    var isAvailable: Bool { get }

    func validate(config: ProtocolConfig) throws
    func connect(config: ProtocolConfig) async throws -> TunnelHandle
    func disconnect(handle: TunnelHandle) async throws
    func diagnostics() async -> ProtocolDiagnostics
}

/// Opaque config (concrete types per-protocol; Phase 1 = VLESSReality only).
public struct ProtocolConfig: Sendable {
    public let identifier: String
    public let json: String  // sing-box subset for this protocol
    public init(identifier: String, json: String) {
        self.identifier = identifier
        self.json = json
    }
}

public struct TunnelHandle: Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

public struct ProtocolDiagnostics: Sendable {
    public let latencyMs: Int?
    public let lastError: String?
    public init(latencyMs: Int? = nil, lastError: String? = nil) {
        self.latencyMs = latencyMs
        self.lastError = lastError
    }
}
