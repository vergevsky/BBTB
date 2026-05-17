import Foundation
import VPNCore

/// Shadowsocks outbound builder.
///
/// **T-A2 (closes C8-007 CRITICAL):** Template-based `buildSingBoxJSON(from: ShadowsocksInputs)`
/// removed — raw substitution of user-controlled password (arbitrary UTF-8 / base64) в JSON
/// template был JSON-injection surface. Dead code в production.
///
/// **R1 invariant trivial:** Shadowsocks outbound НЕ содержит TLS block (encrypted на
/// уровне протокола).
public enum ConfigBuilder {

    // MARK: Phase 5 Wave 7 — pool outbound builder (D-14)

    /// Builds a sing-box outbound dictionary for Shadowsocks.
    ///
    /// **D-16**: Shadowsocks has no transport overlay — encryption is at the protocol
    /// layer. The `transport` parameter is accepted for API consistency (CORE-03) but
    /// always ignored.
    ///
    /// **R1 invariant trivial**: no TLS block — encryption is at protocol layer, so
    /// `insecure` field cannot exist.
    ///
    /// Semantics copied verbatim from PoolBuilder.buildShadowsocksOutbound (Phase 4).
    public static func buildOutbound(
        from parsed: ParsedShadowsocks,
        transport: TransportConfig,    // D-16: ignored — Shadowsocks has no transport layer
        tag: String
    ) -> [String: Any] {
        // R1 invariant trivial: no TLS block — encryption is at protocol layer.
        return [
            "type": "shadowsocks",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "method": parsed.method,
            "password": parsed.password,
            "network": "tcp",
        ]
    }
}
