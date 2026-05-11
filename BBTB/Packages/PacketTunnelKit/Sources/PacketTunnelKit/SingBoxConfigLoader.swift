import Foundation

/// Errors thrown by SingBoxConfigLoader.
///
/// R1 (SEC-01, SEC-02): отказ при попытке передать конфиг с listen-on-localhost
/// inbound'ами или включёнными management gRPC-API. См. [[Wiki/xray-localhost-vulnerability]].
/// SEC-06: отказ при malformed JSON или отсутствии VLESS outbound.
public enum SingBoxConfigError: Error, LocalizedError, Equatable {
    case malformedJSON
    case forbiddenInboundType(String)
    case experimentalApiEnabled(String)
    case missingOutbounds
    case noVLESSOutbound

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
        case .noVLESSOutbound:
            return "sing-box config has no vless outbound (SEC-06 / PROTO-01)"
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
///
/// **Контракт `validate`:** fail-fast, не модифицирует, никогда не «санирует».
/// **Контракт `expandConfigForTunnel`:** идемпотентно, чисто-функциональное преобразование.
public enum SingBoxConfigLoader {

    /// Inbound types, запрещённые на extension стороне.
    /// **Не** включает `tun` и `direct` — TUN это PacketTunnel inbound на utun*,
    /// direct — pass-through. Запрещены только listen-on-localhost варианты, которые
    /// открывают атаку из [[xray-localhost-vulnerability]] (SOCKS5/HTTP-прокси,
    /// доступный любому приложению на устройстве).
    private static let forbiddenInboundTypes: Set<String> = [
        "socks", "http", "mixed", "redirect", "tproxy",
    ]

    public static func validate(json: String) throws {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SingBoxConfigError.malformedJSON
        }

        // R1 (SEC-01): запретить listen-on-localhost inbound типы.
        if let inbounds = root["inbounds"] as? [[String: Any]] {
            for ib in inbounds {
                let t = (ib["type"] as? String) ?? "<unknown>"
                if forbiddenInboundTypes.contains(t) {
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
        // PROTO-01: должен быть VLESS outbound
        let hasVLESS = outbounds.contains { ($0["type"] as? String) == "vless" }
        guard hasVLESS else { throw SingBoxConfigError.noVLESSOutbound }
    }

    /// Phase 1 W3 expansion: добавить TUN inbound и мигрировать DNS-hijack на sing-box 1.13.
    ///
    /// **Вход:** валидный (после `validate`) sing-box JSON. Hiddify-импорт обычно не несёт
    /// inbounds — это корректное поведение импортёра; клиент (extension) сам отвечает за
    /// PacketTunnel-side inbound.
    ///
    /// **Выход:** JSON с гарантированным `tun` inbound и DNS-hijack route rules
    /// в sing-box 1.13 формате (`action: "hijack-dns"`, без отдельного `{type: dns}` outbound).
    ///
    /// **Идемпотентность:** повторный вызов на уже expanded JSON не дублирует inbound
    /// и не ломает rules.
    ///
    /// **Параметры:**
    /// - `mtu`: 1400 — стандарт PacketTunnel; запас под IPv6 (40б) + Reality (~100б).
    /// - `tunIP`: 198.18.0.1 — RFC 2544 benchmarking range, не пересекается ни с RFC 1918,
    ///   ни с CGNAT. Маска `/30` — минимальная P2P подсеть (4 адреса), достаточно для UTUN.
    ///
    /// **Поля TUN inbound** (см. `Wiki/security-gaps.md` R10):
    /// - `auto_route: false` — routes УЖЕ настроены в `NEPacketTunnelNetworkSettings`
    ///   (`ExtensionPlatformInterface.openTun`). Дать sing-box перетянуть routes =
    ///   нарушение R6 (выставит `IFF_POINTOPOINT` на utun).
    /// - `stack: "system"` — gVisor system stack, наиболее стабильный на iOS.
    /// - `sniff: true` — нужен для domain-based route rules (geosite/.com).
    public static func expandConfigForTunnel(
        json: String,
        mtu: Int = 1400,
        tunIP: String = "198.18.0.1"
    ) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SingBoxConfigError.malformedJSON
        }

        // 1. Inject TUN inbound (idempotent).
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        let hasTun = inbounds.contains { ($0["type"] as? String) == "tun" }
        if !hasTun {
            inbounds.append([
                "type": "tun",
                "tag": "tun-in",
                "address": ["\(tunIP)/30"],
                "mtu": mtu,
                "auto_route": false,
                "stack": "system",
                "sniff": true,
            ])
            root["inbounds"] = inbounds
        }

        // 2. Удалить legacy {type: dns} outbound (sing-box 1.13 removed).
        //    https://sing-box.sagernet.org/migration/#dns-outbound
        if var outbounds = root["outbounds"] as? [[String: Any]] {
            let filtered = outbounds.filter { ($0["type"] as? String) != "dns" }
            if filtered.count != outbounds.count {
                outbounds = filtered
                root["outbounds"] = outbounds
            }
        }

        // 3. Переписать route.rules: правила с outbound:"dns-out" (или protocol:"dns"
        //    + любой outbound) → action:"hijack-dns" (поле outbound удаляется).
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
            // route.final = "dns-out" бессмыслен — fallback на vless-out (PROTO-01 гарантирует).
            if (route["final"] as? String) == "dns-out" {
                route["final"] = "vless-out"
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
    /// Используется W4 ConfigParser'ом перед подстановкой `${...}` placeholder'ов.
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
