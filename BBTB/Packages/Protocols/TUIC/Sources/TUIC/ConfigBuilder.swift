import Foundation
import VPNCore

/// TUIC v5 outbound builder.
///
/// **T-A2 (closes C8-011 CRITICAL):** Template-based `buildSingBoxJSON(from: TUICInputs)`
/// removed — raw substitution of user-controlled UUID / password / SNI / congestion_control
/// / udp_relay_mode / fingerprint в JSON template был JSON-injection surface. Dead code
/// в production.
///
/// Production path: `PoolBuilder.buildSingleOutboundJSON` → dict-based + `JSONSerialization`.
///
/// ============================================================
/// **R1 STRICT** — TUIC v5 НЕ получает `allowInsecure` exception.
/// Это отличает TUIC от Hysteria2 (Phase 4 D-08). `tls.insecure` всегда false.
/// ============================================================
public enum ConfigBuilder {

    /// Builds a sing-box outbound dictionary for TUIC v5.
    ///
    /// **D-16**: TUIC is QUIC-based — no transport overlay. The `transport` parameter
    /// is accepted for API consistency (CORE-03) but always ignored.
    ///
    /// **R1 STRICT**: `tls.insecure` is hardcoded `false` — TUIC does NOT get the D-08
    /// allowInsecure exception (Phase 4 D-08). Any TUIC server with self-signed cert
    /// must arrange certificate trust through pinSHA256, not through insecure=true.
    public static func buildOutbound(
        from parsed: ParsedTUIC,
        transport: TransportConfig,    // D-16: ignored — TUIC is QUIC, no transport layer
        tag: String
    ) -> [String: Any] {
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": parsed.sni,
            "alpn": parsed.alpn,
            "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
        ]
        if let pin = parsed.pinSHA256, !pin.isEmpty {
            tls["certificate_public_key_sha256"] = [pin]
        }

        let outbound: [String: Any] = [
            "type": "tuic",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid,
            "password": parsed.password,
            "congestion_control": parsed.congestionControl,
            "udp_relay_mode": parsed.udpRelayMode,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls": tls,
        ]
        return outbound
    }
}
