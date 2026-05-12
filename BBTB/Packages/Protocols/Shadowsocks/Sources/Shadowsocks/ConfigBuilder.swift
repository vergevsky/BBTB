import Foundation
import PacketTunnelKit

/// Подстановка полей parsed Shadowsocks URI в sing-box template.
///
/// Используется Phase 4 W3 ConfigImporter в **single-server** случае (когда пул содержит
/// только один Shadowsocks outbound). Для multi-outbound pool case — `PoolBuilder` в
/// ConfigParser строит outbound dictionary напрямую из `ParsedShadowsocks`, без обращения
/// к этому builder'у.
///
/// **R1 invariant trivial:** Shadowsocks outbound НЕ содержит TLS block (encrypted на
/// уровне протокола). D-08 R1 exception (`insecure: true`) применяется ТОЛЬКО к Hysteria2.
/// Sing-box `type: "shadowsocks"` различает SS-2022 от legacy по строке `method`.
public enum ConfigBuilder {
    public struct ShadowsocksInputs: Sendable, Equatable {
        public let host: String
        public let port: Int
        public let method: String          // ∈ supportedSSMethods (валидируется на parse этапе)
        public let password: String        // base64 (SS-2022) или plain UTF-8 (legacy)
        public let remark: String?

        public init(host: String, port: Int, method: String, password: String, remark: String?) {
            self.host = host; self.port = port; self.method = method
            self.password = password; self.remark = remark
        }
    }

    public enum BuilderError: Error, LocalizedError, Equatable {
        case templateLoadFailed(String)
        case invalidPort(Int)
        case missingMethod
        case missingPassword

        public var errorDescription: String? {
            switch self {
            case .templateLoadFailed(let msg): return "Template load: \(msg)"
            case .invalidPort(let p): return "Invalid port: \(p)"
            case .missingMethod: return "Shadowsocks method is empty"
            case .missingPassword: return "Shadowsocks password is empty"
            }
        }
    }

    public static func buildSingBoxJSON(from inputs: ShadowsocksInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        guard !inputs.method.isEmpty else { throw BuilderError.missingMethod }
        guard !inputs.password.isEmpty else { throw BuilderError.missingPassword }

        let template = try loadTemplate(named: "SingBoxConfigTemplate.shadowsocks")

        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}",  with: inputs.host)
            .replacingOccurrences(of: "${SS_METHOD}",    with: inputs.method)
            .replacingOccurrences(of: "${SS_PASSWORD}",  with: inputs.password)
            // Single-server case: DNS detour goes directly to shadowsocks-out. Pool case
            // bypasses this builder (PoolBuilder в ConfigParser).
            .replacingOccurrences(of: "${DNS_DETOUR}",   with: "shadowsocks-out")

        if inputs.port != 8388 {
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
