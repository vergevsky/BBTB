import Foundation
import PacketTunnelKit

/// Подстановка полей parsed Trojan URI в R1-compliant template.
///
/// Используется Phase 2 W3 ConfigImporter в **single-server** случае (когда пул содержит
/// только один Trojan outbound). Для multi-outbound pool case — PoolBuilder (ConfigParser)
/// строит outbound dictionary напрямую из ParsedTrojan, без обращения к этому builder'у.
public enum ConfigBuilder {
    public struct TrojanInputs: Sendable, Equatable {
        public let host: String
        public let port: Int
        public let password: String
        public let sni: String
        public let fingerprint: String  // "chrome", "firefox", ...
        public let alpn: [String]       // ["h2", "http/1.1"] default
        public let transport: TransportType
        public let remark: String?

        public init(host: String, port: Int, password: String, sni: String,
                    fingerprint: String, alpn: [String], transport: TransportType, remark: String?) {
            self.host = host; self.port = port; self.password = password; self.sni = sni
            self.fingerprint = fingerprint; self.alpn = alpn; self.transport = transport
            self.remark = remark
        }
    }

    public enum TransportType: Sendable, Equatable {
        case tcp
        case ws(path: String, host: String)
    }

    public enum BuilderError: Error, LocalizedError, Equatable {
        case templateLoadFailed(String)
        case invalidPort(Int)
        case missingPassword
        case missingSNI

        public var errorDescription: String? {
            switch self {
            case .templateLoadFailed(let msg): return "Template load: \(msg)"
            case .invalidPort(let p): return "Invalid port: \(p)"
            case .missingPassword: return "Trojan password is empty"
            case .missingSNI: return "Trojan SNI is empty (R1: required for DPI-resistance)"
            }
        }
    }

    public static func buildSingBoxJSON(from inputs: TrojanInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        guard !inputs.password.isEmpty else { throw BuilderError.missingPassword }
        guard !inputs.sni.isEmpty else { throw BuilderError.missingSNI }

        let templateName: String
        switch inputs.transport {
        case .tcp: templateName = "SingBoxConfigTemplate.trojan-tcp"
        case .ws:  templateName = "SingBoxConfigTemplate.trojan-ws"
        }
        let template = try loadTemplate(named: templateName)

        var filled = template
            .replacingOccurrences(of: "${SERVER_HOST}",        with: inputs.host)
            .replacingOccurrences(of: "${TROJAN_PASSWORD}",    with: inputs.password)
            .replacingOccurrences(of: "${SNI_DOMAIN}",         with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}",   with: inputs.fingerprint)
            // Single-server case: DNS detour goes directly to trojan-out. Pool case
            // bypasses this builder (PoolBuilder в ConfigParser).
            .replacingOccurrences(of: "${DNS_DETOUR}",         with: "trojan-out")

        if case let .ws(path, host) = inputs.transport {
            let wsHost = host.isEmpty ? inputs.sni : host
            filled = filled
                .replacingOccurrences(of: "${WS_PATH}", with: path)
                .replacingOccurrences(of: "${WS_HOST}", with: wsHost)
        }

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
