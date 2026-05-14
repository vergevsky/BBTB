import Foundation
import PacketTunnelKit
import VPNCore
import TransportRegistry

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

    /// Builds a sing-box outbound dictionary for VLESS+TLS with optional transport overlay.
    ///
    /// **R1 invariant**: `tls.insecure` is hardcoded `false` — never reads from parsed.
    /// D-08 R1 EXCEPTION applies ONLY to Hysteria2; copying `insecure: parsed.xxx` to this
    /// method would be a security bug.
    ///
    /// **ALPN h2-strip (Phase 2 W4 invariant)**: WS transport is HTTP/1.1 upgrade —
    /// if ALPN includes "h2", TLS negotiates h2 and rejects the WS upgrade (framing mismatch).
    /// Strip "h2" from ALPN when transport == .ws.
    ///
    /// **Empty WS host fallback (Phase 6d / Wave 06D-03h — M12 fix):** когда
    /// `transport == .ws` с пустым host (URI без `&host=`), подставляем SNI в качестве
    /// WS `Host` header — иначе большинство CDN отвергают WS upgrade без Host. Mirror
    /// Trojan special-case (`Trojan/ConfigBuilder.swift:159-169`). Option A выбран
    /// (минимальное изменение) вместо unified `sniFallback:` параметра в
    /// `WSTransportHandler` (Option B), потому что Option B менял бы signature всех
    /// 5 handler'ов через `TransportHandler` protocol — слишком инвазивно для 5+ файлов.
    ///
    /// **Transport block**: delegated to TransportRegistry.shared (D-13). TCP returns nil
    /// (no block), other transports return their respective JSON block.
    public static func buildOutbound(
        from parsed: ParsedVLESSTLS,
        transport: TransportConfig,
        tag: String
    ) -> [String: Any] {
        // Pitfall 1 — ALPN h2 strip for WS (Phase 2 W4 invariant).
        let alpn: [String]
        if case .ws = transport {
            let filtered = parsed.alpn.filter { $0 != "h2" }
            alpn = filtered.isEmpty ? ["http/1.1"] : filtered
        } else {
            alpn = parsed.alpn
        }

        // Phase 7a Wave 2 — DPI-02 smart default: `tls.record_fragment = true` enables
        // TLS handshake record fragmentation as the recommended starting point for РФ
        // ТСПУ anti-DPI (Codex thread `019e26cb-...`, sing-box upstream «start with
        // record_fragment, escalate to fragment per-server only when blocked»). NOT
        // applied to VLESS+Reality (XTLS-Vision owns that path). NOT applied to TUIC
        // (QUIC: sing-box supports only ECH for QUIC).
        var outbound: [String: Any] = [
            "type": "vless",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid.uuidString.lowercased(),
            "flow": parsed.flow ?? "",
            "network": "tcp",  // VLESS+TLS over transport overlay always network=tcp
            "tls": [
                "enabled": true,
                "server_name": parsed.sni,
                "insecure": false,    // R1 invariant — hardcoded, never reads from parsed
                "alpn": alpn,
                "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
                "record_fragment": true,    // Phase 7a Wave 2 — DPI-02 smart default
            ] as [String: Any],
        ]

        // Phase 6e Wave 2 Theme C-1 (L2) — unified «empty host → SNI fallback» через
        // WSTransportHandler.buildTransportBlock(for:sniFallback:). Раньше logic
        // дублировался здесь (Phase 6d M12 fix `1621a08`) и в Trojan/ConfigBuilder
        // (Phase 2 backward-compat); теперь — single source of truth в
        // WSTransportHandler. Большинство CDN отвергают WS upgrade без Host header
        // — это connectivity-фикс для пользователей, чей URI не содержит `&host=`.
        if case .ws = transport {
            if let block = WSTransportHandler.buildTransportBlock(for: transport,
                                                                   sniFallback: parsed.sni) {
                outbound["transport"] = block
            }
        } else if let block = TransportRegistry.shared.handler(for: transport.identifier)?
            .buildTransportBlock(for: transport) {
            outbound["transport"] = block
        }
        // If block is nil (TCP or unregistered) — no transport block, sing-box uses defaults.

        return outbound
    }
}
