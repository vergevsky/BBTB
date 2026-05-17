import Foundation
import PacketTunnelKit
import VPNCore
import TransportRegistry

/// Trojan outbound builder.
///
/// **T-A2 (closes C8-005 CRITICAL):** Template-based `buildSingBoxJSON(from: TrojanInputs)`
/// removed — raw substitution of user-controlled password / host / SNI / WS path / WS host
/// в JSON template был JSON-injection surface (Trojan password = arbitrary user string,
/// квоты в нём могли corrupt sing-box config). Dead code в production.
///
/// Production path: `PoolBuilder.buildSingleOutboundJSON` → dict-based + `JSONSerialization`.
public enum ConfigBuilder {

    // MARK: Phase 5 Wave 7 — pool outbound builder (D-14)

    /// Builds a sing-box outbound dictionary for Trojan with optional transport overlay.
    ///
    /// **R1 invariant**: `tls.insecure` is hardcoded `false` — never reads from parsed.
    ///
    /// **ALPN h2-strip (Phase 2 W4 invariant)**: WS transport is HTTP/1.1 upgrade —
    /// if ALPN includes "h2", TLS negotiates h2 and rejects the WS upgrade (framing mismatch).
    /// Strip "h2" from ALPN when transport == .ws.
    ///
    /// **Empty WS host fallback**: when transport == .ws with empty host, the SNI is
    /// substituted as the WS Host header (Phase 2 backward-compat invariant).
    ///
    /// **Transport block**: delegated to TransportRegistry.shared (D-13). For .ws with empty
    /// host, we build the block directly (SNI substitution) rather than delegating.
    public static func buildOutbound(
        from parsed: ParsedTrojan,
        transport: TransportConfig,
        tag: String
    ) -> [String: Any] {
        // Pitfall 1 ALPN h2-strip
        let alpn: [String]
        if case .ws = transport {
            let filtered = parsed.alpn.filter { $0 != "h2" }
            alpn = filtered.isEmpty ? ["http/1.1"] : filtered
        } else {
            alpn = parsed.alpn
        }

        // Phase 7a Wave 2 — DPI-02 smart default: `tls.record_fragment = true` enables
        // TLS handshake record fragmentation as the recommended starting point for РФ
        // ТСПУ anti-DPI (Codex GPT-5 advisory thread `019e26cb-cf49-78c3-af80-d437a5b22f28`,
        // referencing sing-box upstream «start with record_fragment, escalate to fragment
        // per-server only when blocked»). NOT applied to TUIC (QUIC: sing-box supports only
        // ECH for QUIC). NOT applied to VLESS+Reality / VLESS+Vision (XTLS owns that path).
        var outbound: [String: Any] = [
            "type": "trojan",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "password": parsed.password,
            "network": "tcp",
            "tls": [
                "enabled": true,
                "server_name": parsed.sni,
                "insecure": false,
                "alpn": alpn,
                "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
                "record_fragment": true,    // Phase 7a Wave 2 — DPI-02 smart default
            ] as [String: Any],
        ]

        // Phase 6e Wave 2 Theme C-1 (L2) — unified «empty host → SNI fallback» через
        // WSTransportHandler.buildTransportBlock(for:sniFallback:). Раньше logic
        // дублировался здесь и в VLESSTLS (Phase 6d M12 fix `1621a08`); теперь —
        // single source of truth в WSTransportHandler.
        if case .ws = transport {
            if let block = WSTransportHandler.buildTransportBlock(for: transport,
                                                                   sniFallback: parsed.sni) {
                outbound["transport"] = block
            }
        } else if let block = TransportRegistry.shared.handler(for: transport.identifier)?
            .buildTransportBlock(for: transport) {
            outbound["transport"] = block
        }

        return outbound
    }
}
