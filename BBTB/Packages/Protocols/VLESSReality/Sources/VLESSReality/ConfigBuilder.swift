import Foundation
import PacketTunnelKit

/// Подстановка полей parsed VLESS+Reality URI в R1-compliant template
/// (BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json).
///
/// Используется Wave 4 ConfigImporter сразу после VLESSURIParser.parse().
/// Output — JSON-string, который сразу попадёт в `providerConfiguration["configJSON"]`
/// и пройдёт SingBoxConfigLoader.validate как часть стартового pipeline в Wave 3.
public enum ConfigBuilder {
    public struct VLESSRealityInputs {
        public let host: String
        public let port: Int
        public let uuid: String
        public let sni: String
        public let publicKey: String
        public let shortId: String
        public let fingerprint: String  // "chrome", "firefox", ...

        public init(host: String, port: Int, uuid: String, sni: String,
                    publicKey: String, shortId: String, fingerprint: String) {
            self.host = host; self.port = port; self.uuid = uuid; self.sni = sni
            self.publicKey = publicKey; self.shortId = shortId; self.fingerprint = fingerprint
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
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: inputs.fingerprint)
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: inputs.publicKey)
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: inputs.shortId)

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
        let mutated = try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted)
        return String(data: mutated, encoding: .utf8) ?? json
    }
}
