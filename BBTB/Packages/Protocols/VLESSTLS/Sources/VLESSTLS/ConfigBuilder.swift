import Foundation
import PacketTunnelKit
import VPNCore
import TransportRegistry

/// VLESS+TLS outbound builder.
///
/// **T-A2 (closes C8-003 CRITICAL):** Template-based `buildSingBoxJSON(from: VLESSTLSInputs)`
/// removed — raw string substitution of user-controlled values was JSON-injection surface.
/// Dead code in production (ConfigImporter уже использует PoolBuilder dict path).
///
/// Production path: `PoolBuilder.buildSingleOutboundJSON` → dict-based + `JSONSerialization`
/// auto-escapes all strings.
///
/// **R1 invariant:** `tls.insecure: false` hardcoded в `buildOutbound`; D-08 exception
/// (insecure=true) только для Hysteria2.
public enum ConfigBuilder {

    // MARK: Phase 5 Wave 7 — pool outbound builder (D-14)

    /// Builds a sing-box outbound dictionary for VLESS+TLS with optional transport overlay.
    ///
    /// **R1 invariant**: `tls.insecure` is hardcoded `false` — never reads from parsed.
    /// D-08 R1 EXCEPTION applies ONLY to Hysteria2; copying `insecure: parsed.xxx` to this
    /// method would be a security bug.
    ///
    /// **ALPN h2-strip (Phase 2 W4 invariant)**: WS transport is HTTP/1.1 upgrade —
    /// if ALPN includes "h2", TLS negotiates h2 and rejects the WS upgrade (framing mismatch).
    /// Strip "h2" from ALPN when transport == .ws.
    ///
    /// **Empty WS host fallback (Phase 6d / Wave 06D-03h — M12 fix):** когда
    /// `transport == .ws` с пустым host (URI без `&host=`), подставляем SNI в качестве
    /// WS `Host` header — иначе большинство CDN отвергают WS upgrade без Host. Mirror
    /// Trojan special-case (`Trojan/ConfigBuilder.swift:159-169`). Option A выбран
    /// (минимальное изменение) вместо unified `sniFallback:` параметра в
    /// `WSTransportHandler` (Option B), потому что Option B менял бы signature всех
    /// 5 handler'ов через `TransportHandler` protocol — слишком инвазивно для 5+ файлов.
    ///
    /// **Transport block**: delegated to TransportRegistry.shared (D-13). TCP returns nil
    /// (no block), other transports return their respective JSON block.
    public static func buildOutbound(
        from parsed: ParsedVLESSTLS,
        transport: TransportConfig,
        tag: String
    ) -> [String: Any] {
        // Pitfall 1 — ALPN h2 strip for WS (Phase 2 W4 invariant).
        let alpn: [String]
        if case .ws = transport {
            let filtered = parsed.alpn.filter { $0 != "h2" }
            alpn = filtered.isEmpty ? ["http/1.1"] : filtered
        } else {
            alpn = parsed.alpn
        }

        // Phase 7a Wave 2 — DPI-02 smart default: `tls.record_fragment = true` enables
        // TLS handshake record fragmentation as the recommended starting point for РФ
        // ТСПУ anti-DPI (Codex thread `019e26cb-...`, sing-box upstream «start with
        // record_fragment, escalate to fragment per-server only when blocked»). NOT
        // applied to VLESS+Reality (XTLS-Vision owns that path). NOT applied to TUIC
        // (QUIC: sing-box supports only ECH for QUIC).
        var outbound: [String: Any] = [
            "type": "vless",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid.uuidString.lowercased(),
            "flow": parsed.flow ?? "",
            "network": "tcp",  // VLESS+TLS over transport overlay always network=tcp
            "tls": [
                "enabled": true,
                "server_name": parsed.sni,
                "insecure": false,    // R1 invariant — hardcoded, never reads from parsed
                "alpn": alpn,
                "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
                "record_fragment": true,    // Phase 7a Wave 2 — DPI-02 smart default
            ] as [String: Any],
        ]

        // Phase 6e Wave 2 Theme C-1 (L2) — unified «empty host → SNI fallback» через
        // WSTransportHandler.buildTransportBlock(for:sniFallback:). Раньше logic
        // дублировался здесь (Phase 6d M12 fix `1621a08`) и в Trojan/ConfigBuilder
        // (Phase 2 backward-compat); теперь — single source of truth в
        // WSTransportHandler. Большинство CDN отвергают WS upgrade без Host header
        // — это connectivity-фикс для пользователей, чей URI не содержит `&host=`.
        if case .ws = transport {
            if let block = WSTransportHandler.buildTransportBlock(for: transport,
                                                                   sniFallback: parsed.sni) {
                outbound["transport"] = block
            }
        } else if let block = TransportRegistry.shared.handler(for: transport.identifier)?
            .buildTransportBlock(for: transport) {
            outbound["transport"] = block
        }
        // If block is nil (TCP or unregistered) — no transport block, sing-box uses defaults.

        return outbound
    }
}
