import Foundation
import VPNCore

/// Phase 5 D-19 / Pitfall 5 — apply per-server transport override to ParsedXxx.
///
/// Only `.vlessTLS` and `.trojan` accept transport overrides:
/// - D-03: VLESSReality is XTLS-incompatible with transport overlay (Reality only TCP).
/// - D-16: Shadowsocks has no transport layer (encryption at protocol level).
/// - D-16: Hysteria2 is QUIC-based — no transport overlay applies.
///
/// Called by ConfigImporter before PoolBuilder.buildSingBoxJSON to apply per-server
/// transport override (Wave 8 wires the SwiftData field; Wave 7 stub returns nil).
///
/// **Note**: Uses fresh struct construction (not `var v` rebind) to avoid requiring
/// `let` → `var` field migration in ParsedConfigs.swift. This keeps Wave 6
/// ParsedConfigs fully backward-compatible.
public func applyTransportOverride(
    _ parsed: AnyParsedConfig,
    _ override: TransportConfig?
) -> AnyParsedConfig {
    guard let override = override else { return parsed }
    switch parsed {
    case .vlessTLS(let v):
        let mutated = ParsedVLESSTLS(
            uuid: v.uuid, host: v.host, port: v.port,
            flow: v.flow, sni: v.sni, fingerprint: v.fingerprint,
            alpn: v.alpn, transport: override, remarks: v.remarks
        )
        return .vlessTLS(mutated)
    case .trojan(let t):
        let mutated = ParsedTrojan(
            password: t.password, host: t.host, port: t.port,
            security: t.security, sni: t.sni, fingerprint: t.fingerprint,
            alpn: t.alpn, transport: override, remarks: t.remarks
        )
        return .trojan(mutated)
    case .vlessReality, .shadowsocks, .hysteria2:
        return parsed  // D-03/D-16: override ignored for these protocols
    }
}
