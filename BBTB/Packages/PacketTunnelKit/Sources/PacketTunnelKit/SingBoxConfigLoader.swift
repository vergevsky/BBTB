import Foundation

/// Errors thrown by SingBoxConfigLoader.validate.
/// R1 (SEC-01, SEC-02): отказ при попытке передать конфиг с локальными inbound'ами или включёнными gRPC-API.
/// SEC-06: отказ при malformed JSON / отсутствии VLESS outbound.
public enum SingBoxConfigError: Error, LocalizedError, Equatable {
    case malformedJSON
    case forbiddenInboundType(String)
    case forbiddenInboundExists
    case experimentalApiEnabled(String)
    case missingOutbounds
    case noVLESSOutbound

    public var errorDescription: String? {
        switch self {
        case .malformedJSON:
            return "sing-box config is not valid JSON"
        case .forbiddenInboundType(let t):
            return "sing-box config contains forbidden inbound type: \(t) (R1: SEC-01)"
        case .forbiddenInboundExists:
            return "sing-box config must not contain inbounds[] (R1: SEC-01)"
        case .experimentalApiEnabled(let api):
            return "sing-box experimental API enabled: \(api) (R1: SEC-02)"
        case .missingOutbounds:
            return "sing-box config has no outbounds (SEC-06)"
        case .noVLESSOutbound:
            return "sing-box config has no vless outbound (SEC-06 / PROTO-01)"
        }
    }
}

/// R1 + SEC-06 validation. Phase 1 — single source of truth для проверки безопасности sing-box конфига.
///
/// Используется:
/// - Wave 3 `BaseSingBoxTunnel.startTunnel` ПЕРЕД `LibboxNewService(configJSON, ...)`
/// - Wave 4 при `ConfigParser.buildSingBoxJSON(from: parsed)` после подстановки значений в template
///
/// Контракт:
/// - Бросает при первом нарушении (fail-fast)
/// - НЕ модифицирует конфиг
/// - Никогда не "санирует" — это runtime guard, не fixer
public enum SingBoxConfigLoader {
    public static func validate(json: String) throws {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SingBoxConfigError.malformedJSON
        }

        // R1 (SEC-01): запретить inbounds[]
        if let inbounds = root["inbounds"] as? [[String: Any]], !inbounds.isEmpty {
            let firstType = inbounds.first?["type"] as? String ?? "<unknown>"
            throw SingBoxConfigError.forbiddenInboundType(firstType)
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

    /// Загрузить шаблон VLESS+Vision+Reality из bundle.
    /// Используется Wave 4 ConfigParser'ом перед подстановкой ${...} placeholder'ов.
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
