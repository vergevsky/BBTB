import Foundation
import os
import Yams
import VPNCore

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
    /// T-C-B5: log channel для YAML octal-coercion warnings.
    static let log = Logger(subsystem: "app.bbtb", category: "ClashYAMLParser")


    /// Главная entry-функция. Берёт YAML body, возвращает `[ImportedServer]`.
    ///
    /// Throws ТОЛЬКО когда Yams.load даёт unrecoverable parse error на root уровне.
    /// Per-proxy errors (missing fields, bad casts) silently skipped через guard let.
    public static func parse(_ body: String) throws -> [ImportedServer] {
        // T-C-B5-P09 (Plan 09 closes T-C-B5 regression from Plan 07):
        // Pre-process body — force-quote unquoted digit-only short-id values
        // INSIDE `reality-opts:` blocks only. This prevents YAML 1.1 Int
        // coercion (`01234567` → octal `Int(342391)`; `12345678` → decimal
        // `Int(12345678)`) which corrupts Reality short-id byte-exact matching.
        //
        // Plan 07 T-C-B5 attempted к reconstruct via `String(i, radix: 8)`
        // but that ASSUMED octal source — broke decimal-looking hex IDs.
        // Pre-quoting preserves the EXACT source spelling, only path that
        // guarantees byte-for-byte fidelity post-Yams.
        //
        // **Scope:** only lines inside a `reality-opts:` mapping (state-machine
        // tracked by indentation). Avoids mutating block-scalar content where
        // `short-id:` text может appear как plain string (Codex review found
        // this risk in unscoped regex).
        let normalized = Self.forceQuoteRealityShortIds(in: body)

        guard let root = try Yams.load(yaml: normalized) as? [String: Any],
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
            case "tuic":
                // Phase 7a Wave 1 — PROTO-08 TUIC v5 Clash YAML mapping.
                if let entry = mapTUIC(name: name, server: server, port: port,
                                       proxy: proxy, raw: raw) {
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
        // Phase 7a Wave 2 — DPI-01 smart default: "random" (was "chrome").
        let fingerprint = (proxy["client-fingerprint"] as? String) ?? "random"
        let alpn = parseALPN(proxy["alpn"])

        // Phase 5 D-06 — `ParsedTrojan.TransportType` мигрирован в `TransportConfig`.
        // Семантика парсинга Clash YAML не меняется: WS host fallback на SNI сохранён
        // для feature-parity с TrojanURIParser reviewer-choice.
        let transport: TransportConfig
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
        // T-C-B5-P09 (Plan 09): post-preprocessing short-id ALWAYS arrives as
        // String (digit-only values force-quoted в parse() entry point).
        // Validate hex charset + length 0..16 per sing-box spec — invalid
        // values fall back к non-Reality path (returns "", `hasReality` becomes
        // false).
        //
        // Codex Architect consult (thread 019e35f8) verdict: surface validation
        // error rather than silent fallback ONLY when public-key also present
        // (mid-Reality config). Otherwise empty short-id silently drops к TLS
        // gracefully.
        //
        // Plan 09 Codex Code Reviewer follow-up (thread 019e35ff issue #1):
        // current implementation returned "" silently AND fell through к
        // `.vlessTLS` if `tls: true` — that mis-imports broken Reality config
        // as TLS. Fix: differentiate via `realityShortIDInvalid` flag — if
        // public-key non-empty but short-id failed validation, classify as
        // `.unsupported` to surface к user rather than silent misclassification.
        var realityShortIDInvalid = false
        let realityShortID: String = {
            guard let s = stringValue(realityOpts["short-id"]) else { return "" }
            if s.isEmpty { return "" }
            // Reality short-id must be hex string, max 16 chars (8 bytes).
            let isHex = s.allSatisfy { $0.isHexDigit }
            guard isHex, s.count <= 16 else {
                ClashYAMLParser.log.warning("Reality short-id \(s, privacy: .public) invalid (must be hex 1..16 chars)")
                realityShortIDInvalid = true
                return ""
            }
            return s
        }()
        let hasReality = !realityPbk.isEmpty && !realityShortID.isEmpty

        // Plan 09 (Codex Code Reviewer issue #1): mid-Reality config с invalid
        // short-id — public-key present, short-id failed validation. Don't
        // silently downgrade к TLS (would misclassify broken Reality as working
        // TLS connection). Classify as unsupported to surface к user.
        if !realityPbk.isEmpty && realityShortIDInvalid {
            return .unsupported(
                name: name, scheme: "vless",
                host: server, port: port,
                rawURI: raw,
                reason: .schemaUnsupportedInPhase4
            )
        }

        let sni = (proxy["servername"] as? String) ?? server
        // Phase 7a Wave 2 — DPI-01 smart default: "random" (was "chrome").
        let fingerprintRaw = (proxy["client-fingerprint"] as? String)
            ?? (realityOpts["client-fingerprint"] as? String)
            ?? "random"
        let fingerprint = fingerprintRaw.isEmpty ? "random" : fingerprintRaw
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
            // Phase 5 D-05 — мигрируем networkType:String → transport:TransportConfig.
            // Clash YAML `network: ...` нормализуется через тот же TransportParamParser
            // (он принимает type=tcp/ws/grpc/http/httpupgrade case-insensitively); ws-opts
            // отдельно собирается ниже как самостоятельный path/host fallback.
            // Для Clash WS используем `ws-opts.path` и SNI fallback на host (как и в Trojan
            // ветке выше). Для tcp / unknown — `.tcp` fallback (D-10).
            let vlessTLSTransport: TransportConfig
            switch networkType.lowercased() {
            case "ws":
                let wsOpts = (proxy["ws-opts"] as? [String: Any]) ?? [:]
                let path = (wsOpts["path"] as? String) ?? "/"
                let headers = (wsOpts["headers"] as? [String: Any]) ?? [:]
                let wsHost = (headers["Host"] as? String) ?? sni
                vlessTLSTransport = .ws(path: path, host: wsHost)
            default:
                vlessTLSTransport = .tcp
            }
            let parsed = ParsedVLESSTLS(
                uuid: uuid,
                host: server, port: port,
                flow: flow,
                sni: sni,
                fingerprint: fingerprint,
                alpn: alpn,
                transport: vlessTLSTransport,
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

    /// Phase 7a Wave 1 — PROTO-08 TUIC v5 Clash YAML mapping.
    /// Required fields: `uuid`, `password`. SNI fallback to server.
    /// Aliases supported: `congestion-controller` ↔ `congestion_control`,
    /// `udp-relay-mode` ↔ `udp_relay_mode`.
    /// **R1 STRICT:** `skip-cert-verify: true` парсится но игнорируется (нет allowInsecure exception).
    private static func mapTUIC(name: String, server: String, port: Int,
                                 proxy: [String: Any], raw: String) -> ImportedServer? {
        // TUIC required fields per upstream docs.
        guard let uuid = proxy["uuid"] as? String, !uuid.isEmpty,
              let password = proxy["password"] as? String, !password.isEmpty
        else {
            return nil  // Per-proxy error isolation — bad tuic entry skipped
        }

        // congestion_control aliases.
        let ccRaw = (proxy["congestion-controller"] as? String)
            ?? (proxy["congestion_control"] as? String)
            ?? "bbr"
        let cc = ccRaw.trimmingCharacters(in: .whitespaces).lowercased()
        guard ParsedTUIC.supportedCongestionControl.contains(cc) else {
            return .unsupported(
                name: name, scheme: "tuic", host: server, port: port,
                rawURI: raw, reason: .schemaUnsupportedInPhase4
            )
        }

        // udp_relay_mode aliases.
        let modeRaw = (proxy["udp-relay-mode"] as? String)
            ?? (proxy["udp_relay_mode"] as? String)
            ?? "native"
        let mode = modeRaw.trimmingCharacters(in: .whitespaces).lowercased()
        guard ParsedTUIC.supportedUDPRelayMode.contains(mode) else {
            return .unsupported(
                name: name, scheme: "tuic", host: server, port: port,
                rawURI: raw, reason: .schemaUnsupportedInPhase4
            )
        }

        let sni = (proxy["sni"] as? String) ?? server
        let alpn: [String] = {
            let parsed = parseALPN(proxy["alpn"])
            return parsed.isEmpty ? ["h3"] : parsed
        }()

        // Phase 7a Wave 2 — DPI-01 smart default: "random" (was "chrome").
        let fingerprintRaw = (proxy["client-fingerprint"] as? String) ?? "random"
        let fingerprint = fingerprintRaw.isEmpty ? "random" : fingerprintRaw

        let pinSHA256: String? = {
            guard let pin = proxy["fingerprint"] as? String, !pin.isEmpty else { return nil }
            return pin
        }()

        let parsed = ParsedTUIC(
            host: server, port: port,
            uuid: uuid, password: password,
            congestionControl: cc, udpRelayMode: mode,
            sni: sni, alpn: alpn,
            fingerprint: fingerprint,
            pinSHA256: pinSHA256,
            remarks: name
        )
        return .supported(name: name, parsed: .tuic(parsed), rawURI: raw)
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

    /// **T-C-B5-P09 (Plan 09):** static cached regex для matching `short-id:`
    /// lines с digit-only unquoted values + optional trailing whitespace and/or
    /// comment. Captures: 1=prefix incl. indent, 2=digits, 3=trailing suffix.
    ///
    /// Pattern allows but does NOT require leading whitespace (top-level `short-id:`
    /// outside any mapping technically valid YAML, hence `\s*`). `[0-9]{1,16}` —
    /// matches digit-only values up to 16 chars (sing-box spec max length); hex
    /// strings с a-f letters parse as String anyway (no Int coercion in Yams).
    ///
    /// Anchored `^...$` (with `.anchorsMatchLines`) к single-line matches.
    /// `try!` justified: pattern is compile-time string constant.
    private static let shortIdLineRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: #"^(\s*short-id:\s+)([0-9]{1,16})(\s*(?:#.*)?)$"#,
            options: [.anchorsMatchLines]
        )
    }()

    /// **T-C-B5-P09 (Plan 09 closes T-C-B5 regression):** force-quote unquoted
    /// digit-only `short-id:` values INSIDE `reality-opts:` mappings only.
    /// State-machine tracks indentation context — avoids mutating block-scalar
    /// content где `short-id:` may appear as plain text (e.g. в YAML `|`
    /// literal containing example config strings).
    ///
    /// Behavior:
    /// - Lines outside `reality-opts:` block → preserved verbatim.
    /// - Inside `reality-opts:` block (after `reality-opts:` key,
    ///   до dedent to or below parent indent), digit-only short-id values are
    ///   wrapped с double quotes.
    /// - Quoted, alphanumeric hex (`abcdef12`), missing values: untouched.
    ///
    /// Pre-processing is one O(n) pass через body. Typical Clash YAML body
    /// ~few KB, regex apply на short-id lines only.
    /// Regex matching block-scalar start: `<key>: |` или `<key>: >` с optional
    /// chomping indicator (`+`/`-`) and explicit indentation digit. YAML 1.2
    /// spec: block scalar starts with `|` (literal) или `>` (folded).
    private static let blockScalarStartRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: #"^(\s*)[A-Za-z0-9._-]+:\s*[|>][+\-]?\d*\s*(?:#.*)?$"#,
            options: [.anchorsMatchLines]
        )
    }()

    internal static func forceQuoteRealityShortIds(in body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        var inRealityOpts = false
        var realityOptsParentIndent = -1
        // Block scalar tracking (Codex critical issue #2): skip mutation
        // while inside `|` / `>` block scalar even if line indent suggests
        // inside reality-opts.
        var inBlockScalar = false
        var blockScalarParentIndent = -1

        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty lines / comments without state change.
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Compute indent = count of leading space chars (YAML standard).
            let indent = line.prefix(while: { $0 == " " }).count

            // Exit block scalar on dedent to or below parent.
            if inBlockScalar, indent <= blockScalarParentIndent {
                inBlockScalar = false
                blockScalarParentIndent = -1
            }

            // Enter reality-opts block.
            if trimmed.hasPrefix("reality-opts:") {
                inRealityOpts = true
                realityOptsParentIndent = indent
                continue
            }

            // Exit reality-opts block on dedent to OR below parent indent.
            if inRealityOpts, indent <= realityOptsParentIndent {
                inRealityOpts = false
                realityOptsParentIndent = -1
            }

            // Detect block scalar start (e.g. `description: |`).
            let nsLine = line as NSString
            let nsRange = NSRange(location: 0, length: nsLine.length)
            if Self.blockScalarStartRegex.firstMatch(
                in: line, options: [], range: nsRange
            ) != nil {
                inBlockScalar = true
                blockScalarParentIndent = indent
                continue
            }

            // Mutate only inside reality-opts mapping AND outside any block scalar.
            if inRealityOpts && !inBlockScalar {
                if let match = Self.shortIdLineRegex.firstMatch(
                    in: line, options: [], range: nsRange
                ) {
                    let prefix = nsLine.substring(with: match.range(at: 1))
                    let digits = nsLine.substring(with: match.range(at: 2))
                    let suffix = nsLine.substring(with: match.range(at: 3))
                    lines[i] = "\(prefix)\"\(digits)\"\(suffix)"
                }
            }
        }
        return lines.joined(separator: "\n")
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
