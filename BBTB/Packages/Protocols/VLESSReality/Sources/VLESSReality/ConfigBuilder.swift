import Foundation
import PacketTunnelKit
import VPNCore

/// Подстановка полей parsed VLESS+Reality URI в R1-compliant template
/// (BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json
/// — relocated to SingBox/ namespace in Phase 7c, 2026-05-14).
///
/// Используется Wave 4 ConfigImporter сразу после VLESSURIParser.parse().
/// Output — JSON-string, который сразу попадёт в `providerConfiguration["configJSON"]`
/// и пройдёт SingBoxConfigLoader.validate как часть стартового pipeline в Wave 3.
public enum ConfigBuilder {
    public struct VLESSRealityInputs {
        public let host: String
        public let port: Int
        public let uuid: String
        public let flow: String  // "xtls-rprx-vision" или "" (без Vision). Должно matchить server config.
        public let sni: String
        public let publicKey: String
        public let shortId: String
        public let fingerprint: String  // "chrome", "firefox", ...

        public init(host: String, port: Int, uuid: String, flow: String, sni: String,
                    publicKey: String, shortId: String, fingerprint: String) {
            self.host = host; self.port = port; self.uuid = uuid; self.flow = flow
            self.sni = sni; self.publicKey = publicKey; self.shortId = shortId
            self.fingerprint = fingerprint
        }
    }

    public enum BuilderError: Error, LocalizedError {
        case templateLoadFailed(Error)
        case invalidPort(Int)
        public var errorDescription: String? {
            switch self {
            case .templateLoadFailed(let e): return "Template load: \(e.localizedDescription)"
            case .invalidPort(let p): return "Invalid port: \(p)"
            }
        }
    }

    public static func buildSingBoxJSON(from inputs: VLESSRealityInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else {
            throw BuilderError.invalidPort(inputs.port)
        }
        let template: String
        do {
            template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        } catch {
            throw BuilderError.templateLoadFailed(error)
        }

        // server_port в template уже захардкожен как 443 в шаблоне — Wave 1 решение.
        // Wave 4 (IMP-01) для Phase 1 примет, что port из vless:// игнорируется если != 443.
        // Если разработчик использует port ≠ 443 — мы поправим port пост-substitution через
        // JSON-mutation (см. Phase 2). В Wave 3 — простая string substitution, и Phase 2
        // улучшит это через Codable model.
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: inputs.host)
            .replacingOccurrences(of: "${VLESS_UUID}", with: inputs.uuid)
            .replacingOccurrences(of: "${VLESS_FLOW}", with: inputs.flow)
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: inputs.fingerprint)
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: inputs.publicKey)
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: inputs.shortId)
            // Phase 2 W0.T5 (RESEARCH §1.6): single-server case → DNS detour goes to
            // vless-out directly. Pool case (Phase 2 W1.T8 PoolBuilder) bypasses this
            // ConfigBuilder and substitutes ${DNS_DETOUR}=urltest-out itself.
            .replacingOccurrences(of: "${DNS_DETOUR}", with: "vless-out")

        // Port subscription через JSON mutation (только если не дефолт 443).
        if inputs.port != 443 {
            return try mutatePort(in: filled, to: inputs.port)
        }
        return filled
    }

    /// Заменить outbounds[0].server_port на нужное число.
    private static func mutatePort(in json: String, to port: Int) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var outbounds = root["outbounds"] as? [[String: Any]],
              !outbounds.isEmpty
        else {
            return json
        }
        var first = outbounds[0]
        first["server_port"] = port
        outbounds[0] = first
        root["outbounds"] = outbounds
        // Phase 6e Wave 2 Theme A (L13) — drop `.prettyPrinted`. The serialized JSON
        // is fed to sing-box, not displayed; pretty formatting only inflates the
        // payload and slows JSON parse. См. RESEARCH.md L13.
        let mutated = try JSONSerialization.data(withJSONObject: root, options: [])
        return String(data: mutated, encoding: .utf8) ?? json
    }

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
