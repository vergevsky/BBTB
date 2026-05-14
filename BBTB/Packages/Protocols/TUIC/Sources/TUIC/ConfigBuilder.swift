import Foundation
import PacketTunnelKit
import VPNCore

/// Подстановка полей parsed TUIC v5 URI в sing-box template.
///
/// Используется Phase 7a W1 ConfigImporter в **single-server** случае (когда пул содержит
/// только один TUIC outbound). Для multi-outbound pool case — `PoolBuilder` в ConfigParser
/// строит outbound dictionary напрямую через `TUIC.ConfigBuilder.buildOutbound`.
///
/// ============================================================
/// **R1 STRICT** — TUIC v5 НЕ получает `allowInsecure` exception.
/// Это отличает TUIC от Hysteria2 (Phase 4 D-08). `tls.insecure` всегда false.
/// ============================================================
public enum ConfigBuilder {
    public struct TUICInputs: Sendable, Equatable {
        public let host: String
        public let port: Int
        public let uuid: String              // TUIC v5 UUID
        public let password: String          // TUIC v5 password
        public let congestionControl: String // "cubic" | "new_reno" | "bbr"
        public let udpRelayMode: String      // "native" | "quic"
        public let sni: String               // mandatory (R1)
        public let fingerprint: String?      // если nil — default "chrome" из template
        public let pinSHA256: String?        // certificate_public_key_sha256 pinning
        public let remark: String?

        public init(
            host: String,
            port: Int,
            uuid: String,
            password: String,
            congestionControl: String,
            udpRelayMode: String,
            sni: String,
            fingerprint: String?,
            pinSHA256: String?,
            remark: String?
        ) {
            self.host = host
            self.port = port
            self.uuid = uuid
            self.password = password
            self.congestionControl = congestionControl
            self.udpRelayMode = udpRelayMode
            self.sni = sni
            self.fingerprint = fingerprint
            self.pinSHA256 = pinSHA256
            self.remark = remark
        }
    }

    public enum BuilderError: Error, LocalizedError, Equatable {
        case templateLoadFailed(String)
        case invalidPort(Int)
        case missingUUID
        case missingPassword
        case missingSNI
        case invalidCongestionControl(String)
        case invalidUDPRelayMode(String)

        public var errorDescription: String? {
            switch self {
            case .templateLoadFailed(let msg): return "Template load: \(msg)"
            case .invalidPort(let p): return "Invalid port: \(p)"
            case .missingUUID: return "TUIC UUID is empty"
            case .missingPassword: return "TUIC password is empty"
            case .missingSNI: return "TUIC SNI is empty (R1: required for DPI-resistance)"
            case .invalidCongestionControl(let cc):
                return "TUIC congestion_control \"\(cc)\" not supported (allowed: cubic, new_reno, bbr)"
            case .invalidUDPRelayMode(let m):
                return "TUIC udp_relay_mode \"\(m)\" not supported (allowed: native, quic)"
            }
        }
    }

    public static func buildSingBoxJSON(from inputs: TUICInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        guard !inputs.uuid.isEmpty else { throw BuilderError.missingUUID }
        guard !inputs.password.isEmpty else { throw BuilderError.missingPassword }
        guard !inputs.sni.isEmpty else { throw BuilderError.missingSNI }
        guard ParsedTUIC.supportedCongestionControl.contains(inputs.congestionControl) else {
            throw BuilderError.invalidCongestionControl(inputs.congestionControl)
        }
        guard ParsedTUIC.supportedUDPRelayMode.contains(inputs.udpRelayMode) else {
            throw BuilderError.invalidUDPRelayMode(inputs.udpRelayMode)
        }

        let template = try loadTemplate(named: "SingBoxConfigTemplate.tuic")

        // Phase 7a Wave 1: default uTLS fingerprint = "chrome".
        // Wave 2 (D-05 smart defaults) перейдёт default на "random".
        let fp = inputs.fingerprint ?? "chrome"

        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}",        with: inputs.host)
            .replacingOccurrences(of: "${TUIC_UUID}",          with: inputs.uuid)
            .replacingOccurrences(of: "${TUIC_PASSWORD}",      with: inputs.password)
            .replacingOccurrences(of: "${CONGESTION_CONTROL}", with: inputs.congestionControl)
            .replacingOccurrences(of: "${UDP_RELAY_MODE}",     with: inputs.udpRelayMode)
            .replacingOccurrences(of: "${SNI_DOMAIN}",         with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}",   with: fp)
            // Single-server case: DNS detour goes directly to tuic-out. Pool case
            // bypasses this builder (PoolBuilder в ConfigParser).
            .replacingOccurrences(of: "${DNS_DETOUR}",         with: "tuic-out")

        var json = filled
        if inputs.port != 443 {
            json = try mutatePort(in: json, to: inputs.port)
        }
        if let pin = inputs.pinSHA256, !pin.isEmpty {
            json = try mutatePinSHA256(in: json, pin: pin)
        }
        return json
    }

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
        let mutated = try JSONSerialization.data(withJSONObject: root, options: [])
        return String(data: mutated, encoding: .utf8) ?? json
    }

    private static func mutatePinSHA256(in json: String, pin: String) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var outbounds = root["outbounds"] as? [[String: Any]],
              !outbounds.isEmpty
        else {
            return json
        }
        var first = outbounds[0]
        var tls = (first["tls"] as? [String: Any]) ?? [:]
        tls["certificate_public_key_sha256"] = [pin]
        first["tls"] = tls
        outbounds[0] = first
        root["outbounds"] = outbounds
        let mutated = try JSONSerialization.data(withJSONObject: root, options: [])
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

    // MARK: Phase 7a Wave 1 — pool outbound builder (D-14 pattern from Phase 5)

    /// Builds a sing-box outbound dictionary for TUIC v5.
    ///
    /// **D-16 (Phase 5):** TUIC is QUIC-based — no transport overlay. The `transport`
    /// parameter is accepted for API consistency (CORE-03) but always ignored.
    ///
    /// **R1 STRICT:** `tls.insecure` is NEVER set. TUIC does NOT get the Hysteria2
    /// allowInsecure exception (Phase 4 D-08). Any TUIC server with self-signed cert
    /// must arrange certificate trust through pinSHA256, not through insecure=true.
    public static func buildOutbound(
        from parsed: ParsedTUIC,
        transport: TransportConfig,    // D-16: ignored — TUIC is QUIC, no transport layer
        tag: String
    ) -> [String: Any] {
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": parsed.sni,
            "alpn": parsed.alpn,
            "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
        ]
        if let pin = parsed.pinSHA256, !pin.isEmpty {
            tls["certificate_public_key_sha256"] = [pin]
        }

        let outbound: [String: Any] = [
            "type": "tuic",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid,
            "password": parsed.password,
            "congestion_control": parsed.congestionControl,
            "udp_relay_mode": parsed.udpRelayMode,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls": tls,
        ]
        return outbound
    }
}
