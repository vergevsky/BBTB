import Foundation
import PacketTunnelKit
import VPNCore

/// VLESS+Reality outbound builder.
///
/// **T-A2 (closes C8-001 CRITICAL):** Template-based `buildSingBoxJSON(from: VLESSRealityInputs)`
/// removed — raw string substitution of user-controlled values (`host`, `uuid`, `flow`,
/// `sni`, `publicKey`, `shortId`, `fingerprint`) inside JSON template was JSON-injection
/// surface (квоты / control chars в parsed values могли corrupt sing-box config). Dead
/// code in production (ConfigImporter уже использует PoolBuilder dict path); kept только
/// для historical/test compatibility.
///
/// Production path: `PoolBuilder.buildSingleOutboundJSON` → `buildSingBoxJSON(from:[parsed])`
/// (dict-based) → `JSONSerialization` (auto-escapes all strings).
public enum ConfigBuilder {

    // MARK: Phase 5 Wave 7 — pool outbound builder (D-14)

    /// Builds a sing-box outbound dictionary for VLESS+Reality.
    ///
    /// **D-03**: Reality is XTLS-incompatible with transport overlay. The `transport`
    /// parameter is accepted for API consistency (CORE-03) but always treated as
    /// `.tcp` internally. Transport overlay is silently ignored.
    ///
    /// Semantics copied verbatim from PoolBuilder.buildVLESSOutbound (Phase 4).
    public static func buildOutbound(
        from parsed: ParsedVLESS,
        transport: TransportConfig,    // D-03: ignored — Reality only TCP
        tag: String
    ) -> [String: Any] {
        // D-03: Reality is XTLS-incompatible with transport overlay. transport param accepted
        // for API consistency (CORE-03) but always treated as .tcp internally.
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": parsed.sni,
            "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
        ]
        if !parsed.publicKey.isEmpty {
            tls["reality"] = [
                "enabled": true,
                "public_key": parsed.publicKey,
                "short_id": parsed.shortId,
            ] as [String: Any]
        }
        return [
            "type": "vless",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid.uuidString.lowercased(),
            "flow": parsed.flow,
            "network": "tcp",
            "tls": tls,
        ]
    }
}
