import Foundation
import PacketTunnelKit
import VPNCore
import TransportRegistry

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
            ] as [String: Any],
        ]

        // Special-case: legacy Trojan-WS block. If transport == .ws AND host is empty,
        // substitute SNI as Host header (Phase 2 backward-compat invariant).
        if case let .ws(path, wsHost) = transport, wsHost.isEmpty {
            outbound["transport"] = [
                "type": "ws",
                "path": path,
                "headers": ["Host": parsed.sni],
            ] as [String: Any]
        } else if let block = TransportRegistry.shared.handler(for: transport.identifier)?
            .buildTransportBlock(for: transport) {
            outbound["transport"] = block
        }

        return outbound
    }
}
