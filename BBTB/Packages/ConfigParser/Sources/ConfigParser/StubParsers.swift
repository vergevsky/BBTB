import Foundation
import VPNCore

/// D-04 — stub-parsers для URI-схем, которые Phase 2 распознаёт но не поддерживает.
///
/// Извлекают метаданные (host/port/remark) чтобы:
/// 1. UI мог показать пользователю «X конфигов будут включены в следующих версиях».
/// 2. SwiftData мог сохранить row с `isSupported=false` и `rawURI` для re-parse
///    при handler upgrade (Phase 4/7).
public enum StubParsers {

    /// Phase 2 — vless и trojan handlers активны.
    public static let supportedSchemesInPhase2: Set<String> = ["vless", "trojan"]

    /// Phase 4 — добавлены `ss`, `hy2`, `hysteria2` (SS-2022/legacy, Hysteria2 обе схемы).
    /// `vless` тот же handler покрывает оба case'а (Reality + TLS, выбор по query params).
    /// supportedSchemesInPhase2 НЕ удаляется — backward compat для StubParsersTests.
    public static let supportedSchemesInPhase4: Set<String> = [
        "vless", "trojan", "ss", "hy2", "hysteria2"
    ]

    /// Все URI-схемы, которые мы распознаём как «valid VPN protocol» (для распарсивания).
    /// Unknown schemes (http, https, ftp, mailto, ...) обрабатываются отдельно.
    public static let knownSchemes: Set<String> = [
        "vless", "trojan", "ss", "vmess", "hy2", "hysteria2",
        "wireguard", "ssh", "socks5", "socks", "naive+https", "naive+quic"
    ]

    /// Parses metadata from any URI scheme that Phase 2 does not handle.
    /// Returns ImportedServer.unsupported with extracted host/port/remark
    /// (or .invalid if URI is malformed beyond URLComponents).
    public static func parseAsUnsupported(_ uri: String) -> ImportedServer {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              let host = comps.host, !host.isEmpty
        else {
            return .invalid(rawURI: trimmed, error: "URLComponents parse failed (missing scheme or host)")
        }
        let port = comps.port ?? defaultPortForScheme(scheme)
        let remark = comps.fragment?.removingPercentEncoding ?? "\(scheme.uppercased()) \(host):\(port)"
        return .unsupported(
            name: remark,
            scheme: scheme,
            host: host,
            port: port,
            rawURI: trimmed,
            reason: .schemaUnsupportedInPhase2
        )
    }

    private static func defaultPortForScheme(_ s: String) -> Int {
        switch s {
        case "ss": return 8388
        case "vmess": return 443
        case "hy2", "hysteria2": return 443
        case "wireguard": return 51820
        case "ssh": return 22
        case "socks5", "socks": return 1080
        default: return 0
        }
    }
}
