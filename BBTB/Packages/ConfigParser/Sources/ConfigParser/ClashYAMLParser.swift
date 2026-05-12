import Foundation
import Yams

/// IMP-05 / D-12 / D-13 — parser для Clash YAML subscriptions.
///
/// Разбирает только секцию `proxies:` YAML root документа. Секции `rules:`, `proxy-groups:`,
/// `dns:` игнорируются. Маппинг типов в `AnyParsedConfig`:
///
/// | Clash type           | Mapping                                              |
/// |----------------------|------------------------------------------------------|
/// | `ss`                 | `.shadowsocks` (если cipher в whitelist) / `.unsupported(.unsupportedSSMethod)` |
/// | `trojan`             | `.trojan`                                             |
/// | `vless` + reality-opts | `.vlessReality`                                     |
/// | `vless` + `tls: true`  | `.vlessTLS`                                         |
/// | `vless` (без TLS)    | `.unsupported(.schemaUnsupportedInPhase4)` (R1)      |
/// | `hysteria2` / `hy2`  | `.hysteria2` (skip-cert-verify → allowInsecure)      |
/// | `hysteria2` + `ports:` | `.unsupported(.multiPortNotSupported)` (D-09)       |
/// | `vmess`              | `.unsupported(.schemaUnsupportedInPhase4)`           |
/// | unknown type         | `.unsupported(.schemaUnsupportedInPhase4)`           |
///
/// **Per-proxy error isolation** (T-04-05-04 mitigation): bad proxy (missing required fields,
/// invalid UUID, etc.) → skipped через guard let / continue, не throws на весь YAML. Это
/// гарантирует что один сбоящий proxy entry не блокирует импорт остальных.
///
/// **Pitfall 4 mitigation** (alpn dual-type): `parseALPN(_:)` принимает Any? и возвращает
/// `[String]` независимо от того, был ли alpn записан как YAML array `[h2, http/1.1]`
/// или CSV string `"h2,http/1.1"`. Реальные Clash YAML — un-typed.
///
/// **R1 invariant** (D-08 exception для Hysteria2): `skip-cert-verify: true` → `allowInsecure`
/// ТОЛЬКО для `hysteria2`/`hy2`. Для trojan/ss/vless флаг парсится но игнорируется (структуры
/// не имеют `allowInsecure` field by design — type-level enforcement).
public enum ClashYAMLParser {

    /// Главная entry-функция. Берёт YAML body, возвращает `[ImportedServer]`.
    ///
    /// Throws ТОЛЬКО когда Yams.load даёт unrecoverable parse error на root уровне.
    /// Per-proxy errors (missing fields, bad casts) silently skipped через guard let.
    public static func parse(_ body: String) throws -> [ImportedServer] {
        guard let root = try Yams.load(yaml: body) as? [String: Any],
              let proxies = root["proxies"] as? [[String: Any]]
        else {
            return []
        }

        var results: [ImportedServer] = []
        for proxy in proxies {
            guard let typeRaw = proxy["type"] as? String,
                  let name = proxy["name"] as? String,
                  let server = proxy["server"] as? String,
                  let port = proxy["port"] as? Int
            else { continue }
            let type = typeRaw.lowercased()
            let raw = (try? Yams.dump(object: proxy)) ?? ""

            switch type {
            case "ss":
                if let entry = mapShadowsocks(name: name, server: server, port: port,
                                              proxy: proxy, raw: raw) {
                    results.append(entry)
                }
            case "trojan":
                if let entry = mapTrojan(name: name, server: server, port: port,
                                        proxy: proxy, raw: raw) {
                    results.append(entry)
                }
            case "vless":
                if let entry = mapVLESS(name: name, server: server, port: port,
                                       proxy: proxy, raw: raw) {
                    results.append(entry)
                }
            case "hysteria2", "hy2":
                if let entry = mapHysteria2(name: name, server: server, port: port,
                                           proxy: proxy, raw: raw, scheme: type) {
                    results.append(entry)
                }
            case "vmess":
                results.append(.unsupported(
                    name: name, scheme: "vmess", host: server, port: port,
                    rawURI: raw, reason: .schemaUnsupportedInPhase4
                ))
            default:
                results.append(.unsupported(
                    name: name, scheme: type, host: server, port: port,
                    rawURI: raw, reason: .schemaUnsupportedInPhase4
                ))
            }
        }
        return results
    }

    // MARK: - Per-type mapping helpers

    /// SS: cipher + password required. Whitelist через `ShadowsocksURIParser.supportedSSMethods`.
    /// Unknown method → `.unsupportedSSMethod`. R1: `skip-cert-verify` НЕ honored (ss не имеет TLS).
    private static func mapShadowsocks(name: String, server: String, port: Int,
                                        proxy: [String: Any], raw: String) -> ImportedServer? {
        guard let cipher = proxy["cipher"] as? String, !cipher.isEmpty,
              let password = proxy["password"] as? String
        else {
            return nil  // Per-proxy error isolation — bad ss entry skipped
        }
        if !ShadowsocksURIParser.supportedSSMethods.contains(cipher) {
            return .unsupported(
                name: name, scheme: "ss", host: server, port: port,
                rawURI: raw, reason: .unsupportedSSMethod
            )
        }
        let parsed = ParsedShadowsocks(
            host: server, port: port,
            method: cipher, password: password, remarks: name
        )
        return .supported(name: name, parsed: .shadowsocks(parsed), rawURI: raw)
    }

    /// Trojan: password required. SNI fallback на server. ALPN dual-type через parseALPN.
    /// Transport: tcp default; ws → читает ws-opts.path/host.
    /// R1: `skip-cert-verify` парсится но игнорируется (ParsedTrojan не имеет allowInsecure).
    private static func mapTrojan(name: String, server: String, port: Int,
                                   proxy: [String: Any], raw: String) -> ImportedServer? {
        guard let password = proxy["password"] as? String, !password.isEmpty
        else {
            return nil  // Per-proxy error isolation
        }
        let sni = (proxy["sni"] as? String) ?? server
        let fingerprint = (proxy["client-fingerprint"] as? String) ?? "chrome"
        let alpn = parseALPN(proxy["alpn"])

        let transport: ParsedTrojan.TransportType
        let network = (proxy["network"] as? String)?.lowercased() ?? "tcp"
        if network == "ws" {
            let wsOpts = (proxy["ws-opts"] as? [String: Any]) ?? [:]
            let path = (wsOpts["path"] as? String) ?? "/"
            let headers = (wsOpts["headers"] as? [String: Any]) ?? [:]
            let wsHost = (headers["Host"] as? String) ?? sni
            transport = .ws(path: path, host: wsHost)
        } else {
            transport = .tcp
        }

        let parsed = ParsedTrojan(
            password: password,
            host: server, port: port,
            security: "tls",
            sni: sni,
            fingerprint: fingerprint,
            alpn: alpn,
            transport: transport,
            remarks: name
        )
        return .supported(name: name, parsed: .trojan(parsed), rawURI: raw)
    }

    /// VLESS: uuid required.
    /// - Если есть `reality-opts.public-key` non-empty → `.vlessReality(ParsedVLESS)`.
    /// - Если `tls: true` (без reality-opts) → `.vlessTLS(ParsedVLESSTLS)`.
    /// - Иначе (security=none equivalent) → `.unsupported(.schemaUnsupportedInPhase4)` (R1).
    /// R1: `skip-cert-verify` парсится но игнорируется (R1 strict TLS — структуры не имеют allowInsecure).
    private static func mapVLESS(name: String, server: String, port: Int,
                                  proxy: [String: Any], raw: String) -> ImportedServer? {
        guard let uuidStr = proxy["uuid"] as? String,
              let uuid = UUID(uuidString: uuidStr)
        else {
            return nil  // Per-proxy error isolation — bad UUID skipped
        }

        // Reality detection: reality-opts.public-key non-empty AND short-id non-empty.
        // T-04-05-03 mitigation: partial reality-opts (один из двух) → fall to TLS branch.
        // Tolerance: Yams parses unquoted numeric short-id ("01234567") как Int — используем
        // stringValue() для нормализации (Clash YAML wild — some files quote short-id, some don't).
        let realityOpts = (proxy["reality-opts"] as? [String: Any]) ?? [:]
        let realityPbk = stringValue(realityOpts["public-key"]) ?? ""
        let realityShortID = stringValue(realityOpts["short-id"]) ?? ""
        let hasReality = !realityPbk.isEmpty && !realityShortID.isEmpty

        let sni = (proxy["servername"] as? String) ?? server
        let fingerprintRaw = (proxy["client-fingerprint"] as? String)
            ?? (realityOpts["client-fingerprint"] as? String)
            ?? "chrome"
        let fingerprint = fingerprintRaw.isEmpty ? "chrome" : fingerprintRaw
        let flowRaw = proxy["flow"] as? String
        let networkType = (proxy["network"] as? String) ?? "tcp"

        if hasReality {
            let parsed = ParsedVLESS(
                uuid: uuid,
                host: server, port: port,
                flow: flowRaw ?? "",
                security: "reality",
                sni: sni,
                publicKey: realityPbk,
                shortId: realityShortID,
                fingerprint: fingerprint,
                networkType: networkType,
                remarks: name
            )
            return .supported(name: name, parsed: .vlessReality(parsed), rawURI: raw)
        }

        let tlsEnabled = parseBool(proxy["tls"])
        if tlsEnabled {
            let flow: String? = (flowRaw?.isEmpty ?? true) ? nil : flowRaw
            let alpn = parseALPN(proxy["alpn"])
            let parsed = ParsedVLESSTLS(
                uuid: uuid,
                host: server, port: port,
                flow: flow,
                sni: sni,
                fingerprint: fingerprint,
                alpn: alpn,
                networkType: networkType,
                remarks: name
            )
            return .supported(name: name, parsed: .vlessTLS(parsed), rawURI: raw)
        }

        // VLESS без TLS — нарушает R1 invariant.
        return .unsupported(
            name: name, scheme: "vless", host: server, port: port,
            rawURI: raw, reason: .schemaUnsupportedInPhase4
        )
    }

    /// Hysteria2: password (или auth-str) required. SNI fallback на server.
    /// D-08 R1 EXCEPTION: `skip-cert-verify: true` → `allowInsecure: true`.
    /// D-09 multi-port reject: если есть `ports:` field (Clash multi-port синтаксис) → unsupported.
    /// obfs whitelist: только `salamander` (T-04-04-04 mitigation).
    private static func mapHysteria2(name: String, server: String, port: Int,
                                      proxy: [String: Any], raw: String, scheme: String) -> ImportedServer? {
        // D-09 multi-port reject — наличие `ports:` field любого типа = multi-port.
        if proxy["ports"] != nil {
            return .unsupported(
                name: name, scheme: scheme, host: server, port: port,
                rawURI: raw, reason: .multiPortNotSupported
            )
        }

        // Hysteria2 auth field: `password` (Clash convention) или fallback `auth-str` / `auth`.
        let auth = (proxy["password"] as? String)
            ?? (proxy["auth-str"] as? String)
            ?? (proxy["auth"] as? String)
            ?? ""
        guard !auth.isEmpty else {
            return nil  // Per-proxy error isolation — bad hysteria2 entry skipped
        }

        let sni = (proxy["sni"] as? String) ?? server
        let fingerprintRaw = proxy["client-fingerprint"] as? String
        let fingerprint: String? = (fingerprintRaw?.isEmpty ?? true) ? nil : fingerprintRaw

        // obfs whitelist — только salamander.
        let obfsRaw = proxy["obfs"] as? String
        let obfs: String?
        if let o = obfsRaw, !o.isEmpty {
            if o != "salamander" {
                return .unsupported(
                    name: name, scheme: scheme, host: server, port: port,
                    rawURI: raw, reason: .schemaUnsupportedInPhase4
                )
            }
            obfs = o
        } else {
            obfs = nil
        }

        let obfsPassword = proxy["obfs-password"] as? String
        let allowInsecure = parseBool(proxy["skip-cert-verify"])
        let pinSHA256 = proxy["fingerprint"] as? String  // certificate pin (отдельно от client-fingerprint)

        let parsed = ParsedHysteria2(
            host: server, port: port,
            auth: auth,
            sni: sni,
            fingerprint: fingerprint,
            obfs: obfs,
            obfsPassword: obfsPassword,
            allowInsecure: allowInsecure,
            pinSHA256: pinSHA256,
            remarks: name
        )
        return .supported(name: name, parsed: .hysteria2(parsed), rawURI: raw)
    }

    // MARK: - Type-tolerant helpers (Pitfall 4 mitigation)

    /// Pitfall 4 — alpn в Clash YAML может быть YAML array ИЛИ comma-separated string.
    /// Yams returns `[String]` vs `String` для одного и того же логического поля.
    /// Universal handler: array? → return; CSV string? → split + trim; nil/other → default.
    static func parseALPN(_ raw: Any?) -> [String] {
        if let arr = raw as? [String] {
            return arr
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let arrAny = raw as? [Any] {
            // YAML с mixed quoting (`- "h2"`, `- http/1.1`) может прийти как [Any].
            return arrAny.compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let s = raw as? String, !s.isEmpty {
            let items = s.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !items.isEmpty { return items }
        }
        return ["h2", "http/1.1"]
    }

    /// Bool с tolerant casting — Yams возвращает Bool для unquoted true/false, String для
    /// quoted, Int для 1/0. Все три варианта валидны в Clash YAML файлах из реальной природы.
    static func parseBool(_ raw: Any?) -> Bool {
        if let b = raw as? Bool { return b }
        if let s = raw as? String {
            return ["true", "1", "yes"].contains(s.lowercased())
        }
        if let i = raw as? Int { return i != 0 }
        return false
    }

    /// Tolerant string extraction — Yams вычисляет тип unquoted значений по содержимому:
    /// "01234567" → Int (342391, восьмеричное!), "abc123" → String. Real Clash YAML wild —
    /// some panels quote short-id/uuid, some don't. Этот helper нормализует к String.
    static func stringValue(_ raw: Any?) -> String? {
        if let s = raw as? String { return s }
        if let i = raw as? Int { return String(i) }
        if let d = raw as? Double { return String(d) }
        if let b = raw as? Bool { return b ? "true" : "false" }
        return nil
    }
}
