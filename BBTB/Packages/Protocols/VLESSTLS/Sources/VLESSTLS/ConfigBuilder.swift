import Foundation
import PacketTunnelKit

/// Подстановка полей parsed VLESS+TLS URI в R1-compliant template.
///
/// Используется Phase 4 W3 ConfigImporter в **single-server** случае (когда пул содержит
/// только один VLESS+TLS outbound). Для multi-outbound pool case — `PoolBuilder` в
/// ConfigParser строит outbound dictionary напрямую из `ParsedVLESSTLS`, без обращения
/// к этому builder'у.
///
/// **R1 invariant:** `insecure: false` hardcoded в template; ConfigBuilder не принимает
/// `allowInsecure` поле в inputs — это design-time enforcement (D-08 exception только для Hy2).
public enum ConfigBuilder {
    public struct VLESSTLSInputs: Sendable, Equatable {
        public let uuid: UUID
        public let host: String
        public let port: Int
        public let flow: String?            // nil → template получит "" (no Vision)
        public let sni: String              // mandatory (R1); fallback в parser-е — host
        public let fingerprint: String      // "chrome", "firefox", ...
        public let alpn: [String]           // ["h2", "http/1.1"] default
        public let remark: String?

        public init(uuid: UUID, host: String, port: Int, flow: String?, sni: String,
                    fingerprint: String, alpn: [String], remark: String?) {
            self.uuid = uuid; self.host = host; self.port = port; self.flow = flow
            self.sni = sni; self.fingerprint = fingerprint; self.alpn = alpn; self.remark = remark
        }
    }

    public enum BuilderError: Error, LocalizedError, Equatable {
        case templateLoadFailed(String)
        case invalidPort(Int)
        case missingUUID
        case missingSNI

        public var errorDescription: String? {
            switch self {
            case .templateLoadFailed(let msg): return "Template load: \(msg)"
            case .invalidPort(let p): return "Invalid port: \(p)"
            case .missingUUID: return "VLESS UUID is empty (R1: required)"
            case .missingSNI: return "VLESS+TLS SNI is empty (R1: required for DPI-resistance)"
            }
        }
    }

    public static func buildSingBoxJSON(from inputs: VLESSTLSInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        // UUID(uuidString: "00000000-0000-0000-0000-000000000000") валиден, но defensive —
        // отвергаем nil UUID и пустой uuidString (этого практически не случается, но R1).
        guard !inputs.uuid.uuidString.isEmpty else { throw BuilderError.missingUUID }
        guard !inputs.sni.isEmpty else { throw BuilderError.missingSNI }

        let template = try loadTemplate(named: "SingBoxConfigTemplate.vless-tls")

        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}",       with: inputs.host)
            .replacingOccurrences(of: "${VLESS_UUID}",        with: inputs.uuid.uuidString.lowercased())
            // ${VLESS_FLOW}: Phase 1 W5 pattern — пустая строка если flow=nil (server без Vision).
            .replacingOccurrences(of: "${VLESS_FLOW}",        with: inputs.flow ?? "")
            .replacingOccurrences(of: "${SNI_DOMAIN}",        with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}",  with: inputs.fingerprint)
            // Single-server case: DNS detour goes directly to vless-out. Pool case
            // bypasses this builder (PoolBuilder в ConfigParser).
            .replacingOccurrences(of: "${DNS_DETOUR}",        with: "vless-out")

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

    private static func loadTemplate(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw BuilderError.templateLoadFailed("\(name).json not found in bundle")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw BuilderError.templateLoadFailed(error.localizedDescription)
        }
    }
}
