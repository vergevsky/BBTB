import Foundation

/// PROTO-05 / D-07 / D-08 / D-09 — parser для `hy2://auth@host:port?sni=...&obfs=salamander
/// &obfs-password=...&insecure=1&pinSHA256=...&fp=...#name` и `hysteria2://...` (D-09 dual scheme).
///
/// Покрывает:
/// - **D-09 dual scheme:** `hy2` и `hysteria2` — оба валидные scheme aliases (Hysteria 2 official docs).
/// - **D-09 multi-port reject:** `host:443,8443` или `host:443-8443` → throws `multiPortNotSupported`.
///   `URLComponents(string:)` возвращает `nil` для таких URI (валидатор парсера), но нам нужен
///   ТОЧНЫЙ error (а не `.malformedURI`) — поэтому pre-URLComponents string scan port-части.
/// - **D-08 R1 EXCEPTION (три синонима):** query params `insecure` / `allowInsecure` /
///   `skip-cert-verify` со значением `1`/`true`/`yes` → `allowInsecure: true`. Hysteria2 — ЕДИНСТВЕННЫЙ
///   протокол в проекте, где `tls.insecure: true` legitimate (обусловлено реальностью self-hosted
///   Hy2 серверов с self-signed certs). См. PoolBuilder.buildHysteria2Outbound и wiki R17.
/// - **obfs whitelist:** только `salamander` поддерживается sing-box-ом; другие значения → throws
///   `unsupportedObfs` (T-04-04-04 mitigation).
public enum Hysteria2URIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingAuth
    case multiPortNotSupported(String)
    case unsupportedObfs(String)

    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed hy2:// / hysteria2:// URI"
        case .missingAuth: return "Hysteria2 URI missing auth (password)"
        case .multiPortNotSupported(let p):
            return "Hysteria2 multi-port port spec \"\(p)\" не поддерживается (sing-box один порт; D-09)"
        case .unsupportedObfs(let o):
            return "Hysteria2 obfs \"\(o)\" не поддерживается (только \"salamander\")"
        }
    }
}

/// D-09 dual-scheme + D-08 three-synonym + Pitfall 6 multi-port reject.
public enum Hysteria2URIParser {
    public static func parse(_ uri: String) throws -> ParsedHysteria2 {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)

        // D-09 / Pitfall 6 — multi-port reject ДО URLComponents parse.
        //
        // `URLComponents(string:)` возвращает `nil` для URI с `host:443,8443` и
        // `host:443-8443` (нелегальный port). Без pre-scan parser бы вернул
        // `.malformedURI`, теряя точную причину. Здесь делаем substring анализ
        // port-части (после `@`, до `/`, `?` или `#`).
        let afterAt = String(trimmed.split(separator: "@", maxSplits: 1).last ?? "")
        let portCandidate = afterAt
            .split(maxSplits: 1, whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
            .first
            .map(String.init) ?? ""
        let portParts = portCandidate.split(separator: ":", maxSplits: 1).map(String.init)
        // Port присутствует ТОЛЬКО если в host-части был `:` → parts.count == 2.
        // Иначе portParts == [hostname], где `-` в hostname (`my-host.example.com`) НЕ
        // должен триггерить multi-port.
        if portParts.count == 2 {
            let portPart = portParts[1]
            if portPart.contains(",") || portPart.contains("-") {
                throw Hysteria2URIError.multiPortNotSupported(portPart)
            }
        }

        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              scheme == "hy2" || scheme == "hysteria2",
              let host = comps.host, !host.isEmpty,
              let user = comps.user
        else { throw Hysteria2URIError.malformedURI }

        // D-09 default port (RESEARCH §pattern-E): 443 если отсутствует в URI.
        let port = comps.port ?? 443

        let auth = user.removingPercentEncoding ?? user
        guard !auth.isEmpty else { throw Hysteria2URIError.missingAuth }

        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }

        // D-08 — три URI synonym'a collapse в один Bool. `insecure=1` (Hysteria2 native),
        // `allowInsecure=1` (некоторые subscription панели), `skip-cert-verify=1` (Clash YAML
        // соглашение, пробрасывается и в URI варианты). ВСЕ ТРИ → allowInsecure=true.
        let allowInsecure = ["1", "true", "yes"].contains(
            (q["insecure"] ?? q["allowInsecure"] ?? q["skip-cert-verify"] ?? "0").lowercased()
        )

        // obfs whitelist — только "salamander" поддерживается sing-box-ом.
        if let obfs = q["obfs"], !obfs.isEmpty, obfs != "salamander" {
            throw Hysteria2URIError.unsupportedObfs(obfs)
        }

        return ParsedHysteria2(
            host: host,
            port: port,
            auth: auth,
            sni: q["sni"] ?? host,
            fingerprint: q["fingerprint"] ?? q["fp"],
            obfs: (q["obfs"]?.isEmpty == false) ? q["obfs"] : nil,
            obfsPassword: q["obfs-password"],
            allowInsecure: allowInsecure,
            pinSHA256: q["pinSHA256"],
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
