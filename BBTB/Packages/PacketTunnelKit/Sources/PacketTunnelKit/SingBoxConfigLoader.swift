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
    }

    /// Phase 1 W3 expansion: добавить TUN inbound и мигрировать DNS-hijack на sing-box 1.13.
    ///
    /// Подробное описание (mtu/tunIP rationale, idempotency) — см. ниже в коде.
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
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        let hasTun = inbounds.contains { ($0["type"] as? String) == "tun" }
        if !hasTun {
            inbounds.append([
                "type": "tun",
                "tag": "tun-in",
                "address": ["\(tunIP)/28"],
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
