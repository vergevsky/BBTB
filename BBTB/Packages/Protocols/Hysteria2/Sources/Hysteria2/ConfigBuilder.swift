import Foundation
import PacketTunnelKit
import VPNCore

/// Подстановка полей parsed Hysteria2 URI в sing-box template.
///
/// Используется Phase 4 W3 ConfigImporter в **single-server** случае (когда пул содержит
/// только один Hysteria2 outbound). Для multi-outbound pool case — `PoolBuilder` в
/// ConfigParser строит outbound dictionary напрямую из `ParsedHysteria2`, без обращения
/// к этому builder'у.
///
/// ============================================================
/// R1 EXCEPTION — ONLY Hysteria2 (D-08).
/// ${ALLOW_INSECURE} placeholder в `SingBoxConfigTemplate.hysteria2.json` заменяется
/// на `true` или `false` — JSON boolean literal, НЕ строка. Это ЕДИНСТВЕННОЕ место
/// в codebase, где `tls.insecure` может legitimately быть true.
/// Любое копирование этого паттерна в builder'ы других протоколов = security bug.
/// См. также: PoolBuilder.buildHysteria2Outbound, wiki R17,
/// .planning/phases/04-protocol-expansion/04-CONTEXT.md D-08.
/// ============================================================
public enum ConfigBuilder {
    public struct Hysteria2Inputs: Sendable, Equatable {
        public let host: String
        public let port: Int
        public let password: String        // auth (Hy2 URI userinfo)
        public let sni: String             // mandatory (R1)
        public let fingerprint: String?    // если nil — default "chrome" из template
        public let obfs: String?           // только "salamander" (validated в parser-е)
        public let obfsPassword: String?
        public let allowInsecure: Bool     // D-08 R1 EXCEPTION
        public let pinSHA256: String?      // certificate_public_key_sha256 pinning
        public let remark: String?

        public init(
            host: String,
            port: Int,
            password: String,
            sni: String,
            fingerprint: String?,
            obfs: String?,
            obfsPassword: String?,
            allowInsecure: Bool,
            pinSHA256: String?,
            remark: String?
        ) {
            self.host = host
            self.port = port
            self.password = password
            self.sni = sni
            self.fingerprint = fingerprint
            self.obfs = obfs
            self.obfsPassword = obfsPassword
            self.allowInsecure = allowInsecure
            self.pinSHA256 = pinSHA256
            self.remark = remark
        }
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
            case .missingPassword: return "Hysteria2 password (auth) is empty"
            case .missingSNI: return "Hysteria2 SNI is empty (R1: required for DPI-resistance)"
            }
        }
    }

    public static func buildSingBoxJSON(from inputs: Hysteria2Inputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        guard !inputs.password.isEmpty else { throw BuilderError.missingPassword }
        guard !inputs.sni.isEmpty else { throw BuilderError.missingSNI }

        let template = try loadTemplate(named: "SingBoxConfigTemplate.hysteria2")

        // ============================================================
        // R1 EXCEPTION — ONLY Hysteria2 (D-08).
        // ${ALLOW_INSECURE} placeholder заменяется на `true` или `false` — JSON boolean
        // literal, НЕ строка. В template видно как `"insecure": ${ALLOW_INSECURE}` —
        // БЕЗ кавычек вокруг placeholder. После replace получается valid JSON:
        // `"insecure": true` или `"insecure": false`.
        // Это ЕДИНСТВЕННОЕ место в codebase, где tls.insecure может legitimately
        // быть true. Любое копирование этого паттерна в builder'ы других
        // протоколов (VLESS+TLS / Trojan / SS) = security bug (Pitfall 2).
        // ============================================================
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}",    with: inputs.host)
            .replacingOccurrences(of: "${HY2_PASSWORD}",   with: inputs.password)
            .replacingOccurrences(of: "${SNI_DOMAIN}",     with: inputs.sni)
            .replacingOccurrences(of: "${ALLOW_INSECURE}", with: inputs.allowInsecure ? "true" : "false")
            // Single-server case: DNS detour goes directly to hysteria2-out. Pool case
            // bypasses this builder (PoolBuilder в ConfigParser).
            .replacingOccurrences(of: "${DNS_DETOUR}",     with: "hysteria2-out")

        // mutate-port + optional fields (fingerprint / pinSHA256 / obfs) — через
        // JSONSerialization round-trip. Все эти поля в template имеют default values,
        // которые мы перезаписываем по необходимости.
        var json = filled
        if inputs.port != 443 {
            json = try mutatePort(in: json, to: inputs.port)
        }
        if inputs.fingerprint != nil || inputs.pinSHA256 != nil
            || (inputs.obfs != nil && (inputs.obfsPassword?.isEmpty == false)) {
            json = try mutateOptionalFields(in: json, inputs: inputs)
        }
        return json
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

    /// Optional Hy2 fields (fingerprint override / pinSHA256 / obfs salamander) —
    /// мутируем outbound[0] через JSONSerialization. Все три поля независимы;
    /// если значение nil/empty, мы не трогаем соответствующее поле в JSON.
    private static func mutateOptionalFields(in json: String, inputs: Hysteria2Inputs) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var outbounds = root["outbounds"] as? [[String: Any]],
              !outbounds.isEmpty
        else {
            return json
        }
        var first = outbounds[0]
        var tls = (first["tls"] as? [String: Any]) ?? [:]

        // fingerprint override: utls.fingerprint.
        if let fp = inputs.fingerprint, !fp.isEmpty {
            var utls = (tls["utls"] as? [String: Any]) ?? ["enabled": true]
            utls["fingerprint"] = fp
            tls["utls"] = utls
        }

        // certificate_public_key_sha256 pinning (array of one element).
        if let pin = inputs.pinSHA256, !pin.isEmpty {
            tls["certificate_public_key_sha256"] = [pin]
        }

        first["tls"] = tls

        // obfs (salamander) — separate top-level key в outbound.
        if let obfs = inputs.obfs, obfs == "salamander",
           let obfsPwd = inputs.obfsPassword, !obfsPwd.isEmpty {
            first["obfs"] = ["type": "salamander", "password": obfsPwd]
        }

        outbounds[0] = first
        root["outbounds"] = outbounds
        // Phase 6e Wave 2 Theme A (L13) — drop `.prettyPrinted`. The serialized JSON
        // is fed to sing-box, not displayed; pretty formatting only inflates the
        // payload and slows JSON parse. См. RESEARCH.md L13.
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

    // MARK: Phase 5 Wave 7 — pool outbound builder (D-14)

    // ============================================================
    // R1 EXCEPTION — ONLY Hysteria2 (D-08).
    // This is the ONLY buildOutbound in BBTB where tls.insecure
    // may legitimately be set to true. Copying this pattern to any
    // other protocol builder is a security bug (Pitfall 2 RESEARCH).
    //
    // Mitigation layers:
    //   1. This comment block (code-level marker for PR review).
    //   2. test_nonHy2_outbounds_neverHaveInsecureTrue invariant test.
    //   3. ParsedShadowsocks/ParsedVLESSTLS/ParsedTrojan structs do NOT
    //      have an allowInsecure field (type-level by design).
    //
    // See: wiki/security-gaps.md R17,
    //      .planning/phases/04-protocol-expansion/04-CONTEXT.md D-08.
    // ============================================================

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
            tls["utls"] = ["enabled": true, "fingerprint": "chrome"]
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
