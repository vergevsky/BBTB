import Foundation

/// Errors thrown by SingBoxConfigLoader.
///
/// R1 (SEC-01, SEC-02): отказ при попытке передать конфиг с listen-on-localhost
/// inbound'ами или включёнными management gRPC-API. См. [[Wiki/xray-localhost-vulnerability]].
/// SEC-06: отказ при malformed JSON или отсутствии proxy outbound.
///
/// **Phase 2 W0.T4 (RESEARCH §7):** `noVLESSOutbound` → `noProxyOutbound`, поскольку
/// валидатор теперь принимает любой из supported proxy outbound types (vless, trojan,
/// urltest, selector, ...). Добавлен `unresolvedOutboundRef` для urltest/selector
/// references на несуществующие outbound tags.
public enum SingBoxConfigError: Error, LocalizedError, Equatable {
    case malformedJSON
    case forbiddenInboundType(String)
    case experimentalApiEnabled(String)
    case missingOutbounds
    case noProxyOutbound
    case unresolvedOutboundRef(ref: String, in: String)
    /// T-C-H1' (closes CV-H1): `route.rule_set[]` entry has disallowed `type`
    /// (only `"local"` accepted — `"remote"`/url-based rule_sets bypass app's
    /// signed-fetch path).
    case forbiddenRuleSetType(String)
    /// T-C-H1' (closes CV-H1): `route.rule_set[].path` not under
    /// AppGroupContainer.rulesCacheDirectory или basename failed allowlist regex
    /// (operator JSON could otherwise drive libbox `open(2)` к arbitrary
    /// extension-sandbox paths — info disclosure via writeDebugMessage).
    case forbiddenRuleSetPath(String)

    public var errorDescription: String? {
        switch self {
        case .malformedJSON:
            return "sing-box config is not valid JSON"
        case .forbiddenInboundType(let t):
            return "sing-box config contains forbidden inbound type: \(t) (R1: SEC-01)"
        case .experimentalApiEnabled(let api):
            return "sing-box experimental API enabled: \(api) (R1: SEC-02)"
        case .missingOutbounds:
            return "sing-box config has no outbounds (SEC-06)"
        case .noProxyOutbound:
            return "sing-box config has no proxy outbound (SEC-06; supported: vless, trojan, urltest, selector, ...)"
        case .unresolvedOutboundRef(let ref, let group):
            return "sing-box \(group) references unknown outbound tag: '\(ref)' (RESEARCH §7.3)"
        case .forbiddenRuleSetType(let t):
            return "sing-box route.rule_set[] type \"\(t)\" not allowed — only \"local\" supported (T-C-H1')"
        case .forbiddenRuleSetPath(let p):
            return "sing-box route.rule_set[].path \"\(p)\" outside allowed directory or has unsafe basename (T-C-H1')"
        }
    }
}

/// R1 + SEC-06 validation + Phase 1 W3 TUN inbound expansion.
///
/// **Используется:**
/// - `BaseSingBoxTunnel.startTunnel` ПЕРЕД `LibboxNewCommandServer.startOrReloadService` —
///   сначала `validate(json:)`, затем `expandConfigForTunnel(json:)`.
/// - `ConfigBuilder.buildSingBoxJSON(from: parsed)` в W4 импортёре — `validate(json:)`
///   на свеже-собранном template'е после подстановки `${...}` placeholder'ов.
/// - `PoolBuilder.buildSingBoxJSON` (Phase 2 W1.T8) для multi-outbound urltest pool.
///
/// **Контракт `validate`:** fail-fast, не модифицирует, никогда не «санирует».
/// **Контракт `expandConfigForTunnel`:** идемпотентно, чисто-функциональное преобразование.
public enum SingBoxConfigLoader {

    /// Inbound types, **разрешённые** на extension стороне. White-list (default-deny).
    /// - `tun` — PacketTunnel inbound на utun*; loopback не слушает.
    /// - `direct` — pass-through outbound bridge без exposed порта.
    ///
    /// Любой другой тип (socks, http, mixed, redirect, tproxy, или новый listen-on-localhost
    /// тип в будущей версии sing-box) — отвергается. Это сохраняет default-deny принцип.
    private static let allowedInboundTypes: Set<String> = [
        "tun", "direct",
    ]

    /// Outbound types, которые признаются "proxy" — config должен иметь хотя бы один такой.
    ///
    /// **Phase 2 RESEARCH §7.2:** включает все handler'ы (vless, trojan), group outbounds
    /// (urltest, selector) и future-supported types (shadowsocks, vmess, hysteria2,
    /// wireguard, tuic) — чтобы operator JSON с этими outbound'ами не reject'ился
    /// validate (R1 inbound whitelist остаётся главным защитным механизмом; outbound
    /// type сам по себе не несёт inbound-side risk).
    private static let proxyOutboundTypes: Set<String> = [
        "vless", "trojan",                                  // Phase 2 supported handlers
        "urltest", "selector",                              // group outbounds
        "shadowsocks", "vmess", "hysteria2", "wireguard", "tuic",  // future-supported
    ]

    public static func validate(json: String) throws {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SingBoxConfigError.malformedJSON
        }

        // R1 (SEC-01): default-deny white-list. Любой неразрешённый inbound тип → fail-fast.
        if let inbounds = root["inbounds"] as? [[String: Any]] {
            for ib in inbounds {
                let t = (ib["type"] as? String) ?? "<unknown>"
                if !allowedInboundTypes.contains(t) {
                    throw SingBoxConfigError.forbiddenInboundType(t)
                }
            }
        }

        // R1 (SEC-02): запретить experimental APIs
        if let exp = root["experimental"] as? [String: Any] {
            if let clash = exp["clash_api"] as? [String: Any], !clash.isEmpty {
                throw SingBoxConfigError.experimentalApiEnabled("clash_api")
            }
            if let v2ray = exp["v2ray_api"] as? [String: Any], !v2ray.isEmpty {
                throw SingBoxConfigError.experimentalApiEnabled("v2ray_api")
            }
            if let cache = exp["cache_file"] as? [String: Any],
               cache["enabled"] as? Bool == true {
                throw SingBoxConfigError.experimentalApiEnabled("cache_file")
            }
        }

        // SEC-06: должен быть хотя бы один outbound
        guard let outbounds = root["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
            throw SingBoxConfigError.missingOutbounds
        }

        // SEC-06 / Phase 2 RESEARCH §7.2: должен быть хотя бы один proxy outbound
        // (vless/trojan/urltest/selector/etc).
        let hasProxyOutbound = outbounds.contains { outbound in
            guard let type = outbound["type"] as? String else { return false }
            return proxyOutboundTypes.contains(type)
        }
        guard hasProxyOutbound else { throw SingBoxConfigError.noProxyOutbound }

        // Phase 2 RESEARCH §7.3: для urltest/selector — все outbound references
        // должны указывать на существующие tags.
        let allTags: Set<String> = Set(outbounds.compactMap { $0["tag"] as? String })
        for outbound in outbounds {
            guard let type = outbound["type"] as? String,
                  (type == "urltest" || type == "selector"),
                  let refs = outbound["outbounds"] as? [String]
            else { continue }
            for ref in refs where !allTags.contains(ref) {
                throw SingBoxConfigError.unresolvedOutboundRef(ref: ref, in: type)
            }
        }

        // T-C6' (closes C1'-001 + A1'-006): route.rules[].outbound и route.final
        // тоже должны ссылаться на существующие tags. Без этого operator JSON с
        // `route.rules[*].outbound: "<typo-tag>"` тихо проваливается в default
        // outbound (sing-box fallback), и трафик, который должен был быть direct
        // или reject, уходит ЧЕРЕЗ proxy (CRITICAL — localhost / RFC1918 / TSPU
        // DNS могли бы leak через VPN).
        //
        // **dns-out исключение:** legacy sing-box 1.13 deprecation; expand
        // удаляет / переписывает `outbound: "dns-out"` rules в `action: "hijack-dns"`.
        // Operator JSON со старым форматом не должен сразу же reject'иться.
        // См. expandConfigForTunnel шаг 3.
        let reservedOutboundRefs: Set<String> = ["dns-out"]
        if let route = root["route"] as? [String: Any] {
            if let rules = route["rules"] as? [[String: Any]] {
                for rule in rules {
                    guard let ref = rule["outbound"] as? String else { continue }
                    if !allTags.contains(ref) && !reservedOutboundRefs.contains(ref) {
                        throw SingBoxConfigError.unresolvedOutboundRef(
                            ref: ref, in: "route.rules"
                        )
                    }
                }
            }
            if let finalRef = route["final"] as? String,
               !allTags.contains(finalRef),
               !reservedOutboundRefs.contains(finalRef) {
                throw SingBoxConfigError.unresolvedOutboundRef(
                    ref: finalRef, in: "route.final"
                )
            }

            // T-C-H1' (closes CV-H1 / A1'-3-001 + C1'-3-001 HIGH cross-validated):
            // `route.rule_set[]` entries from operator JSON can drive libbox
            // `open(2)` к arbitrary filesystem paths in extension sandbox
            // (App Group container + extension Caches reachable). Adjacent
            // к T-C6' (outbound-ref check) but separate validation surface.
            //
            // Policy (defence-in-depth):
            // 1. Only `type == "local"` accepted. Reject `"remote"`/url-based
            //    rule_sets — those bypass app's hardened SSRF + signed fetch path.
            // 2. `path` must canonicalize under `AppGroupContainer.rulesCacheDirectory`.
            // 3. Basename must match positive regex `^[A-Za-z0-9][A-Za-z0-9._-]+\.srs$`.
            // 4. Reject `..`, symlinks (post-canonicalize check), embedded `/`.
            //
            // BBTB's own injected entries (block 5 в expandConfigForTunnel) use
            // hardcoded basenames `bbtb-baseline-{block,never,always}.srs` —
            // these pass the regex naturally.
            if let ruleSets = route["rule_set"] as? [[String: Any]] {
                // **Plan 09 CV-2-H6 (closes M-A1-4-01 + C1-4-004):** lexical
                // prefix check using NSString.standardizingPath does NOT resolve
                // symlinks. Attacker-controlled operator JSON could reference
                // a `.srs` filename which is replaced by symlink в App Group
                // cache → libbox follow symlink at open(2) → read outside
                // sandbox-permitted area (confused-deputy).
                //
                // Fix (Codex Architect thread `019e367f` two-stage gate):
                // 1) Resolve rulesDir itself через resolvingSymlinksInPath +
                //    standardizedFileURL — defense against symlinked ancestor.
                // 2) Resolve PARENT of `path` (deletingLastPathComponent) +
                //    require strict equality к resolved rulesDirURL.
                // 3) If file EXISTS — reject if it's a symlink via
                //    destinationOfSymbolicLink; also re-verify resolved file
                //    остаётся под rulesDir prefix.
                // 4) Missing file = OK at validate-time (manifest fetch
                //    populates later); rely on basename regex + parent strict
                //    equality. Runtime pre-libbox re-check is separate scope.
                //
                // TOCTOU residual: validator passes at time T, attacker swaps
                // file → symlink at T+1, libbox opens at T+2. Not closed here;
                // would require libbox-side O_NOFOLLOW which we don't control.
                let fm = FileManager.default
                let rulesDirURL = AppGroupContainer.rulesCacheDirectory
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
                let basenameRegex = "^[A-Za-z0-9][A-Za-z0-9._-]+\\.srs$"
                for entry in ruleSets {
                    let entryType = (entry["type"] as? String) ?? ""
                    if entryType != "local" {
                        throw SingBoxConfigError.forbiddenRuleSetType(entryType)
                    }
                    guard let rawPath = entry["path"] as? String, !rawPath.isEmpty else {
                        throw SingBoxConfigError.forbiddenRuleSetPath("(missing)")
                    }
                    // Cheap defense-in-depth: reject lexical traversal markers
                    // before touching filesystem.
                    let lexCanonical = (rawPath as NSString).standardizingPath
                    if lexCanonical.contains("/../") || lexCanonical.hasSuffix("/..") {
                        throw SingBoxConfigError.forbiddenRuleSetPath(rawPath)
                    }
                    // Lexical prefix gate — fast reject for clearly outside paths.
                    let rulesDirPath = rulesDirURL.path
                    let lexPrefix = rulesDirPath.hasSuffix("/") ? rulesDirPath : rulesDirPath + "/"
                    guard lexCanonical.hasPrefix(lexPrefix) else {
                        throw SingBoxConfigError.forbiddenRuleSetPath(rawPath)
                    }
                    // Basename allowlist — only `.srs` files matching name regex.
                    let standardizedFileURL = URL(fileURLWithPath: rawPath).standardizedFileURL
                    let basename = standardizedFileURL.lastPathComponent
                    let nsBase = basename as NSString
                    let nameRange = NSRange(location: 0, length: nsBase.length)
                    let matched = (try? NSRegularExpression(pattern: basenameRegex))?
                        .firstMatch(in: basename, options: [], range: nameRange) != nil
                    guard matched else {
                        throw SingBoxConfigError.forbiddenRuleSetPath(rawPath)
                    }
                    // Symlink-aware check: parent must strictly equal resolved rulesDir.
                    let parentURL = standardizedFileURL
                        .deletingLastPathComponent()
                        .resolvingSymlinksInPath()
                        .standardizedFileURL
                    guard parentURL.path == rulesDirURL.path else {
                        throw SingBoxConfigError.forbiddenRuleSetPath(rawPath)
                    }
                    // **CodeRabbit review (PR #10) + Codex Architect thread
                    // `019e3694`:** ALWAYS check for symlink, regardless of
                    // fileExists. `fileExists(atPath:)` FOLLOWS the final
                    // symlink and returns false for broken symlinks (symlink
                    // → /nonexistent), which would otherwise skip the check
                    // and let attacker pass validator + later create the
                    // target file → confused-deputy. `destinationOfSymbolicLink`
                    // reads the link metadata itself — works even for dangling
                    // symlinks (returns target path string).
                    //
                    // Cases:
                    // - Plain missing path: destinationOfSymbolicLink throws,
                    //   try? → nil, not a symlink, proceed (accept missing).
                    // - Broken symlink: returns target path, reject.
                    // - Existing symlink: returns target path, reject.
                    // - Existing regular file: returns nil, run prefix check.
                    if (try? fm.destinationOfSymbolicLink(atPath: standardizedFileURL.path)) != nil {
                        throw SingBoxConfigError.forbiddenRuleSetPath(rawPath)
                    }
                    if fm.fileExists(atPath: standardizedFileURL.path) {
                        let resolvedFileURL = standardizedFileURL
                            .resolvingSymlinksInPath()
                            .standardizedFileURL
                        guard resolvedFileURL.path.hasPrefix(lexPrefix) else {
                            throw SingBoxConfigError.forbiddenRuleSetPath(rawPath)
                        }
                    }
                }
            }
        }
    }

    /// Phase 1 W3 expansion: добавить TUN inbound и мигрировать DNS-hijack на sing-box 1.13.
    ///
    /// Подробное описание (mtu/tunIP rationale, idempotency) — см. ниже в коде.
    ///
    /// **Phase 8 W5 (D-01) extension:** also injects 3 `route.rule_set` entries
    /// (bbtb-block / bbtb-never / bbtb-always; `type:"local"`, `format:"binary"`,
    /// `path:` под App Group rules cache directory) + 3 priority `route.rules`
    /// (block→reject, never→direct, always→firstProxyTag). Idempotent: повторный
    /// вызов не дублирует ни rule_set declarations, ни priority rules. R1/R10 invariants
    /// preserved (`action:"reject"` — outbound action, не inbound type; post-expand
    /// `validate(json:)` passes без throw).
    // MARK: - Phase 10 / DPI-05 — Mux protocol whitelist helper

    /// DPI-05 / Phase 10 — Protocol whitelist для Mux injection (D-09).
    ///
    /// Возвращает `true` только для:
    /// - VLESS+TLS plain (без Reality block и без xtls-rprx-vision flow),
    /// - Trojan,
    /// - Shadowsocks (включая 2022-blake3-* AEAD variants).
    ///
    /// Возвращает `false` для:
    /// - VLESS+Reality (тихий mux+reality → sing-box panic, SagerNet #453),
    /// - VLESS+Vision (flow=xtls-rprx-vision, XTLS имеет собственный multiplexing),
    /// - TUIC (QUIC нативно multiplexed),
    /// - Hysteria2 (QUIC нативно multiplexed),
    /// - Любые другие типы outbound (urltest, selector, direct, dns и т.д.).
    private static func isMuxCompatible(_ outbound: [String: Any]) -> Bool {
        guard let type = outbound["type"] as? String else { return false }

        switch type {
        case "trojan":
            return true

        case "shadowsocks":
            return true

        case "vless":
            // VLESS+Vision: flow содержит "xtls-rprx-vision" → ЗАПРЕЩЕНО (SagerNet #453).
            if let flow = outbound["flow"] as? String, flow.contains("xtls-rprx-vision") {
                return false
            }
            // VLESS+Reality: старая схема (sing-box 1.9-) — ключ "reality" на верхнем уровне outbound.
            if outbound["reality"] as? [String: Any] != nil {
                return false
            }
            // VLESS+Reality: новая схема (sing-box 1.10+) — reality внутри tls блока.
            if let tls = outbound["tls"] as? [String: Any],
               let reality = tls["reality"] as? [String: Any],
               reality["enabled"] as? Bool == true {
                return false
            }
            // VLESS+TLS plain — допустимо.
            return true

        default:
            return false
        }
    }

    public static func expandConfigForTunnel(
        json: String,
        mtu: Int = 1500,
        tunIP: String = "198.18.0.1",
        logPath: String? = nil,
        logLevel: String = "debug"
    ) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SingBoxConfigError.malformedJSON
        }

        // 0. Diagnostic log sink (idempotent).
        if let logPath = logPath {
            var logBlock = (root["log"] as? [String: Any]) ?? [:]
            logBlock["disabled"] = false
            logBlock["level"] = logLevel
            logBlock["output"] = logPath
            logBlock["timestamp"] = true
            root["log"] = logBlock
        }

        // 1. Inject TUN inbound (idempotent).
        //
        // Phase 6 / Wave 2 (NET-05/06, D-06) — IPv6 blackhole внутри sing-box:
        //   - `address` включает ULA `fd00::1/126` (наряду с IPv4 `<tunIP>/28`) —
        //     sing-box TUN получит v6 локальный адрес чтобы понимать что v6 ему свой.
        //   - `route_address: ["::/0"]` — все v6 destination'ы трактуются как
        //     "in-tunnel"; без этого пакеты с v6 dest могли бы попасть в `direct`
        //     outbound (= leak через физический интерфейс).
        // V6 outbound в конфиге нет → пакеты dropпаются внутри gvisor stack.
        //
        // Используется **unified 1.13 syntax** (`address` + `route_address`). НЕ
        // `inet6_address` / `inet6_route_address` — те deprecated в sing-box 1.10
        // (см. 06-RESEARCH.md §2).
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        let hasTun = inbounds.contains { ($0["type"] as? String) == "tun" }
        if !hasTun {
            inbounds.append([
                "type": "tun",
                "tag": "tun-in",
                "address": ["\(tunIP)/28", "fd00::1/126"],
                "route_address": ["::/0"],
                "mtu": mtu,
                "auto_route": false,
                "stack": "gvisor",
            ])
            root["inbounds"] = inbounds
        }

        // 2. Удалить legacy {type: dns} outbound (sing-box 1.13 removed).
        if var outbounds = root["outbounds"] as? [[String: Any]] {
            let filtered = outbounds.filter { ($0["type"] as? String) != "dns" }
            if filtered.count != outbounds.count {
                outbounds = filtered
                root["outbounds"] = outbounds
            }
        }

        // 3. Переписать route.rules: dns-out → action:hijack-dns.
        if var route = root["route"] as? [String: Any] {
            if var rules = route["rules"] as? [[String: Any]] {
                var changed = false
                for i in rules.indices {
                    var rule = rules[i]
                    let outboundRef = rule["outbound"] as? String
                    let isDnsProto = (rule["protocol"] as? String) == "dns"
                    if outboundRef == "dns-out" || (isDnsProto && outboundRef != nil) {
                        rule.removeValue(forKey: "outbound")
                        rule["action"] = "hijack-dns"
                        rules[i] = rule
                        changed = true
                    }
                }
                if changed {
                    route["rules"] = rules
                    root["route"] = route
                }
            }
            // route.final = "dns-out" бессмыслен — fallback на первый proxy outbound.
            if (route["final"] as? String) == "dns-out" {
                let outbounds = (root["outbounds"] as? [[String: Any]]) ?? []
                let firstProxyTag = outbounds.first { o in
                    guard let t = o["type"] as? String else { return false }
                    return proxyOutboundTypes.contains(t)
                }?["tag"] as? String ?? "vless-out"
                route["final"] = firstProxyTag
                root["route"] = route
            }
        }

        // 4. Phase 1 W3.2 — обязательный sniff action первым правилом route (DNS detection).
        if var route = root["route"] as? [String: Any] {
            var rules = (route["rules"] as? [[String: Any]]) ?? []
            let hasSniff = rules.contains { ($0["action"] as? String) == "sniff" }
            if !hasSniff {
                rules.insert(["action": "sniff"], at: 0)
                route["rules"] = rules
                root["route"] = route
            }
        }

        // 5. Phase 8 D-01 (W5) — inject 3 `route.rule_set` declarations + 3 priority rules.
        //
        // **Phase 13 / D-04 gating:** читаем `app.bbtb.routingRulesEnabled` из App Group
        // suite (записан `SettingsViewModel.routingRulesEnabled` через @AppStorage(store:)).
        // Default = true (если ключ ни разу не writed) → injection активен. OFF → skip
        // блок 5 целиком → full tunnel mode (весь трафик уходит через `route.final`).
        // Паттерн идентичен блоку 6 (`stunBlockEnabled`).
        //
        // Idempotent: `existingTags` / `existingRuleSetRefs` filter prevents duplicate
        // entries on repeated calls (BaseSingBoxTunnel may invoke expand multiple times
        // в test paths; R10 post-expand validate must remain green после повторных вызовов).
        //
        // Order сохраняется top-down (sing-box matches first hit):
        //   1. bbtb-block  → action: reject
        //   2. bbtb-never  → outbound: direct
        //   3. bbtb-always → outbound: firstProxyTag (urltest/selector если Phase 2 pool)
        //
        // R1 invariant preserved: `action: "reject"` — это outbound action, не inbound
        // type; whitelist `{tun, direct}` остаётся неизменным. `validate(json:)` passes.
        //
        // R10 invariant preserved: post-expand `validate(json:)` (вызывается из
        // `BaseSingBoxTunnel.startTunnel` после expand) проверяет inbounds / experimental
        // / proxy outbound — rule_set entries в `route.rule_set` не пересекаются ни с одним
        // из этих гейтов.
        //
        // Path resolution: `rulesCacheDirectory` evaluates на extension стороне
        // (same App Group identifier `group.app.bbtb.shared` как и main app writer).
        // `try? createDirectory(.withIntermediateDirectories)` внутри
        // `rulesCacheDirectory` idempotent — safe для cold-start race (Risk #2 в PATTERNS).
        let routingRulesEnabled: Bool = {
            let defaults = UserDefaults(suiteName: AppGroupContainer.identifier)
            // object(forKey:) nil → ключ ни разу не writed → default = true (matches
            // @AppStorage default в SettingsViewModel.routingRulesEnabled).
            guard let v = defaults?.object(forKey: "app.bbtb.routingRulesEnabled") else {
                return true
            }
            return (v as? Bool) ?? true
        }()

        if routingRulesEnabled, var route = root["route"] as? [String: Any] {
            // 5a. Inject rule_set declarations (deduped by tag).
            var ruleSets = (route["rule_set"] as? [[String: Any]]) ?? []
            let existingTags: Set<String> = Set(ruleSets.compactMap { $0["tag"] as? String })
            let rulesDir = AppGroupContainer.rulesCacheDirectory.path
            let categories: [(tag: String, file: String)] = [
                ("bbtb-block",  "bbtb-baseline-block.srs"),
                ("bbtb-never",  "bbtb-baseline-never.srs"),
                ("bbtb-always", "bbtb-baseline-always.srs"),
            ]
            for (tag, file) in categories where !existingTags.contains(tag) {
                ruleSets.append([
                    "tag": tag,
                    "type": "local",
                    "format": "binary",
                    "path": "\(rulesDir)/\(file)",
                ])
            }
            route["rule_set"] = ruleSets

            // 5b. Inject 3 priority rules (deduped by rule_set ref).
            //
            // Insertion idx — после sniff + hijack-dns (typically index 2). Это гарантирует
            // что DNS hijack продолжает работать (sing-box uses DNS sniffing для domain
            // matching — D-03 prerequisite), а наши rule_set rules матчатся до final outbound.
            var rules = (route["rules"] as? [[String: Any]]) ?? []
            let existingRuleSetRefs: Set<String> = Set(rules.compactMap { $0["rule_set"] as? String })

            // Resolve firstProxyTag — same logic as `route.final` fallback at lines 218-225
            // (single source of truth для proxy tag selection).
            let outbounds = (root["outbounds"] as? [[String: Any]]) ?? []
            let firstProxyTag: String = outbounds.first { o in
                guard let t = o["type"] as? String else { return false }
                return proxyOutboundTypes.contains(t)
            }?["tag"] as? String ?? "vless-out"

            let insertIdx = rules.firstIndex {
                ($0["action"] as? String) == "hijack-dns"
            }.map { $0 + 1 } ?? rules.count

            var newRules: [[String: Any]] = []
            if !existingRuleSetRefs.contains("bbtb-block") {
                newRules.append(["rule_set": "bbtb-block", "action": "reject"])
            }
            if !existingRuleSetRefs.contains("bbtb-never") {
                newRules.append(["rule_set": "bbtb-never", "outbound": "direct"])
            }
            if !existingRuleSetRefs.contains("bbtb-always") {
                newRules.append(["rule_set": "bbtb-always", "outbound": firstProxyTag])
            }
            rules.insert(contentsOf: newRules, at: insertIdx)
            route["rules"] = rules
            root["route"] = route
        }

        // 6. Phase 10 / D-16 / BIO-04 — STUN block route.rule injection.
        //
        // Reads `app.bbtb.stunBlockEnabled` из App Group UserDefaults suite (записан Wave 1
        // SettingsViewModel через @AppStorage(store: App Group suite)).
        //
        // Idempotent: ищем правило с tag="bbtb-stun-block"; если уже есть — skip.
        // Sing-box 1.13.11 НЕ имеет protocol="stun" matcher → используем port+network+action.
        // method="drop" — silent drop, без ICMP unreachable (DPI не получает сигнал блокировки).
        //
        // Insertion point: ПОСЛЕ hijack-dns (DNS должен работать) и ДО Phase 8 priority rules.
        // Sing-box rules матчатся top-down first-hit; STUN drop должен быть до fallthrough.
        let stunBlockEnabled = UserDefaults(suiteName: AppGroupContainer.identifier)?
            .bool(forKey: "app.bbtb.stunBlockEnabled") ?? false

        if stunBlockEnabled, var route = root["route"] as? [String: Any] {
            var rules = (route["rules"] as? [[String: Any]]) ?? []
            // T-B9 / A1-001 fix: sing-box 1.13 `route.rules[]` schema doesn't preserve
            // `tag` field on rules (only on outbounds) — schema validate strips it.
            // Previous idempotency check `tag == "bbtb-stun-block"` could thus fail на
            // repeat expand calls после schema normalize → duplicate STUN rules
            // injected, OR worse, schema-rejection would break entire config.
            //
            // Fingerprint by port + network + action signature instead (preserved fields).
            let alreadyHasStun = rules.contains { rule in
                guard let action = rule["action"] as? String, action == "reject",
                      let network = rule["network"] as? String, network == "udp",
                      let ports = rule["port"] as? [Int], ports == [3478, 5349]
                else { return false }
                return true
            }
            if !alreadyHasStun {
                // Insertion idx — после hijack-dns (DNS hijack должен оставаться выше).
                let insertIdx = rules.firstIndex { ($0["action"] as? String) == "hijack-dns" }
                    .map { $0 + 1 } ?? rules.count
                // T-B9 / A1-001: removed `tag` field (not in sing-box rule schema).
                let stunRule: [String: Any] = [
                    "port": [3478, 5349],
                    "network": "udp",
                    "action": "reject",
                    "method": "drop",
                ]
                rules.insert(stunRule, at: insertIdx)
                route["rules"] = rules
                root["route"] = route
            }
        }

        // 7. Phase 10 / D-08..D-10 — Mux injection (DPI-05).
        //
        // Reads `app.bbtb.muxEnabled` из App Group UserDefaults suite, записанного
        // Wave 1 SettingsViewModel через @AppStorage(store: App Group suite).
        //
        // Whitelist enforced via `isMuxCompatible(_:)` (D-09):
        //   ALLOWED:  VLESS+TLS plain, Trojan, Shadowsocks (including 2022-blake3-* AEAD).
        //   SKIPPED:  VLESS+Reality, VLESS+Vision, TUIC, Hysteria2, all non-proxy outbounds.
        //
        // Idempotent: если outbound уже имеет `multiplex` ключ
        //   (per-server URI override, повторный expand) — skip (не перезаписывать).
        //   D-08 «двойной контроль» — global toggle не overrid'ит per-server setting.
        //
        // D-10 values: protocol=smux, max_connections=4, padding=true
        //   (DPI-03 per-packet padding активируется через padding=true в smux multiplex).
        let muxEnabled = UserDefaults(suiteName: AppGroupContainer.identifier)?
            .bool(forKey: "app.bbtb.muxEnabled") ?? false

        if muxEnabled, var outbounds = root["outbounds"] as? [[String: Any]] {
            for i in outbounds.indices {
                var ob = outbounds[i]
                // Idempotent: не трогаем outbound с уже выставленным multiplex блоком.
                // Это также preserves per-server URI override (D-08).
                guard ob["multiplex"] == nil else { continue }
                // Protocol whitelist (D-09): пропускаем несовместимые типы.
                guard isMuxCompatible(ob) else { continue }
                ob["multiplex"] = [
                    "enabled": true,
                    "protocol": "smux",
                    "max_connections": 4,
                    "padding": true,
                ] as [String: Any]
                outbounds[i] = ob
            }
            root["outbounds"] = outbounds
        }

        let modifiedData = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let modifiedString = String(data: modifiedData, encoding: .utf8) else {
            throw SingBoxConfigError.malformedJSON
        }
        return modifiedString
    }

    /// Загрузить шаблон VLESS+Vision+Reality из bundle.
    public static func loadVLESSRealityTemplate() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "SingBoxConfigTemplate.vless-reality",
            withExtension: "json"
        ) else {
            throw SingBoxConfigError.malformedJSON
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
