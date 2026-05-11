import Foundation

/// D-04 sumtype — результат parsing одной строки/URI/JSON-outbound.
///
/// Phase 2 поддерживает только vless и trojan handlers. Все остальные known schemes
/// (ss, vmess, hy2, wireguard, ssh, socks5, naive+...) парсятся в `.unsupported` для
/// сохранения метаданных и UI feedback пользователю «X конфигов рабочих, Y будут
/// включены в следующих версиях».
public enum AnyParsedConfig: Sendable, Equatable {
    case vlessReality(ParsedVLESS)
    case trojan(ParsedTrojan)
    // Phase 4+ добавит ss, vmess, hy2, wireguard
}

public enum UnsupportedReason: String, Sendable, Equatable {
    case schemaUnsupportedInPhase2  // ss://, vmess://, hy2://, wireguard://, ssh://, socks5://, naive+...://
    case transportUnsupported       // type=h2, h2+ws, grpc для известных схем
    case malformedURI               // не парсится URLComponents-ом
}

public enum ImportedServer: Sendable {
    case supported(name: String, parsed: AnyParsedConfig, rawURI: String)
    case unsupported(name: String, scheme: String, host: String, port: Int, rawURI: String, reason: UnsupportedReason)
    case invalid(rawURI: String, error: String)  // String для Sendable; full Error wrapped in description

    public var displayName: String {
        switch self {
        case .supported(let n, _, _): return n
        case .unsupported(let n, _, _, _, _, _): return n
        case .invalid(let uri, _): return String(uri.prefix(60))
        }
    }
    public var isSupportedFlag: Bool {
        if case .supported = self { return true } else { return false }
    }
    public var rawURI: String {
        switch self {
        case .supported(_, _, let r): return r
        case .unsupported(_, _, _, _, let r, _): return r
        case .invalid(let r, _): return r
        }
    }
}

public enum ImportSource: Sendable, Equatable {
    case pasteboard
    case subscriptionURL(URL)
    case jsonEndpoint(URL)
    case qrCode
    case multilineText
}
