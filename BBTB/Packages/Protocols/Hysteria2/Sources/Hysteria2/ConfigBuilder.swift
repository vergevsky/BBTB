import Foundation
import VPNCore

/// Hysteria2 outbound builder.
///
/// **T-A2 (closes C8-009 CRITICAL):** Template-based `buildSingBoxJSON(from: Hysteria2Inputs)`
/// removed — raw substitution of user-controlled auth (Hy2 password = arbitrary string),
/// host, SNI в JSON template был JSON-injection surface. Dead code в production.
///
/// ============================================================
/// **R1 EXCEPTION — ONLY Hysteria2 (D-08).**
/// `tls.insecure` reads from `parsed.allowInsecure` (the ONLY protocol builder in BBTB
/// where insecure may be true). Copying this pattern to any other protocol builder is
/// a security bug. See:
///   - wiki/security-gaps.md R17
///   - .planning/phases/04-protocol-expansion/04-CONTEXT.md D-08
///
/// Mitigation layers:
///   1. This comment block (code-level marker for PR review)
///   2. `test_nonHy2_outbounds_neverHaveInsecureTrue` invariant test
///   3. ParsedShadowsocks/ParsedVLESSTLS/ParsedTrojan structs do NOT have an
///      allowInsecure field (type-level enforcement by design)
/// ============================================================
public enum ConfigBuilder {

    // MARK: Phase 5 Wave 7 — pool outbound builder (D-14)

    /// Builds a sing-box outbound dictionary for Hysteria2.
    ///
    /// **D-16**: Hysteria2 is QUIC-based — no transport overlay. The `transport`
    /// parameter is accepted for API consistency (CORE-03) but always ignored.
    ///
    /// **D-08 R1 EXCEPTION**: `tls.insecure` reads from `parsed.allowInsecure`.
    /// This is the ONLY protocol builder in BBTB where insecure may be true.
    ///
    /// Semantics copied verbatim from PoolBuilder.buildHysteria2Outbound (Phase 4).
    public static func buildOutbound(
        from parsed: ParsedHysteria2,
        transport: TransportConfig,    // D-16: ignored — Hy2 is QUIC, no transport layer
        tag: String
    ) -> [String: Any] {
        // R1 EXCEPTION — only Hy2.
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": parsed.sni,
            "insecure": parsed.allowInsecure,    // D-08 EXCEPTION
            "alpn": ["h3"],
        ]
        if let fp = parsed.fingerprint, !fp.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fp]
        } else {
            // Phase 7a Wave 2 — DPI-01 smart default: "random" (was "chrome").
            tls["utls"] = ["enabled": true, "fingerprint": "random"]
        }
        if let pin = parsed.pinSHA256, !pin.isEmpty {
            tls["certificate_public_key_sha256"] = [pin]
        }

        var outbound: [String: Any] = [
            "type": "hysteria2",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "password": parsed.auth,
            "tls": tls,
        ]
        if let obfs = parsed.obfs, obfs == "salamander",
           let obfsPwd = parsed.obfsPassword, !obfsPwd.isEmpty {
            outbound["obfs"] = ["type": "salamander", "password": obfsPwd]
        }
        return outbound
    }
}
