import Foundation

/// PROTO-04 / D-04 / D-05 / D-11 — parser для `ss://userinfo@host:port#tag` (SIP002 + SIP022).
///
/// Покрывает:
/// - **SIP002 legacy** — userinfo = base64url(`method:password`). Используется большинством
///   панелей / Outline access keys (D-11: Outline = чистый SIP002, отдельного парсера не нужно).
/// - **SIP022 (AEAD-2022)** — userinfo = percent-encoded `method:password` напрямую (SS-2022
///   spec обязывает НЕ использовать base64url).
///
/// Decoder dual-path (Pitfall 1 mitigation, см. `.planning/phases/04-protocol-expansion/04-RESEARCH.md`
/// раздел «Common Pitfalls» / Example 2): сначала percent-encoded путь (валидный для SS-2022
/// и legacy с percent-encoded userinfo), затем base64url fallback (типичный legacy формат).
///
/// **Whitelist методов** (D-04): только AEAD-семейство — stream ciphers (rc4-md5, aes-*-cfb,
/// aes-*-ctr) НЕ включены, поскольку выкошены SS-сообществом в 2017 как небезопасные. Неизвестный
/// метод → `ShadowsocksURIError.unsupportedMethod(String)` → `UniversalImportParser` сворачивает
/// в `.unsupported(reason: .unsupportedSSMethod)`.
public enum ShadowsocksURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingHost
    case missingPort
    case malformedUserinfo
    case unsupportedMethod(String)

    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed ss:// URI"
        case .missingHost: return "Shadowsocks URI missing host"
        case .missingPort: return "Shadowsocks URI missing port"
        case .malformedUserinfo:
            return "Shadowsocks URI userinfo не парсится ни как percent-encoded, ни как base64url"
        case .unsupportedMethod(let m):
            return "Shadowsocks method \"\(m)\" не поддерживается (Phase 4 whitelist: SS-2022 + legacy AEAD)"
        }
    }
}

/// SIP002 / SIP022 URI parser.
public enum ShadowsocksURIParser {

    /// D-04 — whitelist поддерживаемых методов (AEAD only).
    /// - 3 × SS-2022-blake3-* (SIP022).
    /// - 5 × legacy AEAD (SIP002 / SIP004).
    /// Stream ciphers (rc4-md5, aes-*-cfb, aes-*-ctr) **намеренно** исключены (T-04-03-01).
    public static let supportedSSMethods: Set<String> = [
        // 2022-blake3 (AEAD-2022, SIP022)
        "2022-blake3-aes-128-gcm",
        "2022-blake3-aes-256-gcm",
        "2022-blake3-chacha20-poly1305",
        // Legacy AEAD
        "aes-128-gcm",
        "aes-192-gcm",
        "aes-256-gcm",
        "chacha20-ietf-poly1305",
        "xchacha20-ietf-poly1305",
    ]

    public static func parse(_ uri: String) throws -> ParsedShadowsocks {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "ss"
        else {
            throw ShadowsocksURIError.malformedURI
        }
        guard let host = comps.host, !host.isEmpty else {
            throw ShadowsocksURIError.missingHost
        }
        guard let port = comps.port else {
            throw ShadowsocksURIError.missingPort
        }
        guard let user = comps.user, !user.isEmpty else {
            throw ShadowsocksURIError.malformedURI
        }

        // SIP022 nuance: percent-encoded `method:password` userinfo. `URLComponents` splits
        // on the literal `:` between user/password — поэтому SIP022 URI приходят с
        // непустым `comps.password`. Reassemble `method:password` ДО передачи в decoder
        // (для SIP002 base64url userinfo `comps.password` is nil — single string остаётся).
        let userinfo: String
        if let pwd = comps.password, !pwd.isEmpty {
            userinfo = "\(user):\(pwd)"
        } else {
            userinfo = user
        }

        let (method, password) = try decodeUserinfo(userinfo)

        guard supportedSSMethods.contains(method) else {
            throw ShadowsocksURIError.unsupportedMethod(method)
        }

        return ParsedShadowsocks(
            host: host,
            port: port,
            method: method,
            password: password,
            remarks: comps.fragment?.removingPercentEncoding
        )
    }

    /// SIP002 + SIP022 dual-path decoder (Pitfall 1 mitigation).
    /// - **Path 1 — percent-encoded:** SS-2022 (SIP022) **MUST** использовать этот формат;
    ///   некоторые legacy серверы тоже встречаются с percent-encoded userinfo.
    ///   Принимаем only-if первая часть в whitelist'е (чтобы случайный base64-чанк не
    ///   проскочил с мусорным "method" впереди).
    /// - **Path 2 — base64url:** Legacy SIP002. Padding tolerance ('=' до length%4==0),
    ///   '-' → '+', '_' → '/' (стандартная base64url → base64). На этом пути whitelist
    ///   НЕ применяется — чтобы `parse` мог различить `malformedUserinfo` (decode не получился)
    ///   от `unsupportedMethod` (decode успешен, но метод не в whitelist'е).
    /// - Если оба пути не дают валидного `method:password` → `malformedUserinfo`.
    private static func decodeUserinfo(_ user: String) throws -> (method: String, password: String) {
        // Path 1: percent-encoded.
        let decoded = user.removingPercentEncoding ?? user
        if let colonIdx = decoded.firstIndex(of: ":") {
            let method = String(decoded[..<colonIdx])
            let password = String(decoded[decoded.index(after: colonIdx)...])
            if supportedSSMethods.contains(method) {
                return (method, password)
            }
        }

        // Path 2: base64url fallback.
        var padded = user
        while padded.count % 4 != 0 { padded.append("=") }
        let base64Std = padded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if let data = Data(base64Encoded: base64Std),
           let s = String(data: data, encoding: .utf8),
           let colonIdx = s.firstIndex(of: ":") {
            let method = String(s[..<colonIdx])
            let password = String(s[s.index(after: colonIdx)...])
            return (method, password)
        }

        throw ShadowsocksURIError.malformedUserinfo
    }
}
