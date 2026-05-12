import Foundation

/// D-04 sumtype — результат parsing одной строки/URI/JSON-outbound.
///
/// Phase 2 поддерживает только vless и trojan handlers. Все остальные known schemes
/// (ss, vmess, hy2, wireguard, ssh, socks5, naive+...) парсятся в `.unsupported` для
/// сохранения метаданных и UI feedback пользователю «X конфигов рабочих, Y будут
/// включены в следующих версиях».
///
/// Phase 4 расширяет enum тремя case'ами (D-01, D-05, D-07):
///   - `vlessTLS`     — VLESS+TLS без Reality (с Vision flow или plain TLS).
///   - `shadowsocks`  — SS-2022 (SIP022) и legacy SS (SIP002) AEAD методы.
///   - `hysteria2`    — Hysteria2 (hy2:// и hysteria2:// схемы) с D-08 R1-исключением.
///
/// Relocated from ConfigParser to VPNCore (Phase 5 Wave 6) to eliminate
/// the cyclic dependency: ConfigParser → VPNCore ← Protocols.
public enum AnyParsedConfig: Sendable, Equatable {
    case vlessReality(ParsedVLESS)
    case vlessTLS(ParsedVLESSTLS)
    case trojan(ParsedTrojan)
    case shadowsocks(ParsedShadowsocks)
    case hysteria2(ParsedHysteria2)
}

public enum UnsupportedReason: String, Sendable, Equatable {
    case schemaUnsupportedInPhase2     // ss://, vmess://, hy2://, wireguard://, ssh://, socks5://, naive+...:// (Phase 1/2 legacy reason)
    case transportUnsupported          // type=h2, h2+ws, grpc для известных схем
    case malformedURI                  // не парсится URLComponents-ом
    // Phase 4 additions (04-CONTEXT.md D-04 / D-09 / Clash YAML mixed pool):
    case schemaUnsupportedInPhase4     // vmess (+ любые другие unknown в Clash YAML) после расширения Phase 4 supported set
    case unsupportedSSMethod           // SS-2022/legacy method не в supportedSSMethods (D-04)
    case multiPortNotSupported         // hy2://...:443,8443 — sing-box один порт (D-09)
}

// MARK: - Parsed structs (D-03 / D-05 / D-07)

/// Phase 1 — `vless://...?security=reality` (Reality branch).
///
/// `networkType: String` — тип транспорта для Reality (обычно "tcp").
/// Reality-only поле: VLESS+TLS использует `transport: TransportConfig` вместо этого.
public struct ParsedVLESS: Sendable, Equatable {
    public let uuid: UUID
    public let host: String
    public let port: Int
    public let flow: String
    public let security: String
    public let sni: String
    public let publicKey: String
    public let shortId: String
    public let fingerprint: String
    public let networkType: String
    public let remarks: String?

    public init(uuid: UUID, host: String, port: Int, flow: String, security: String,
                sni: String, publicKey: String, shortId: String, fingerprint: String,
                networkType: String, remarks: String?) {
        self.uuid = uuid; self.host = host; self.port = port; self.flow = flow
        self.security = security; self.sni = sni; self.publicKey = publicKey
        self.shortId = shortId; self.fingerprint = fingerprint
        self.networkType = networkType; self.remarks = remarks
    }
}

/// D-03 — `vless://...?security=tls` без Reality (Vision flow или plain TLS).
///
/// Phase 5 D-05 (миграция типа): `networkType: String` заменено на
/// `transport: TransportConfig` (shared enum в VPNCore). Парсер делегирует
/// извлечение transport-params на `TransportParamParser`. Соответствие:
///   - prev `networkType == "tcp"` / `"raw"` ↔ `transport == .tcp`
///   - prev `networkType == "ws"` (если бы существовал) ↔ `transport == .ws(...)`
///
/// Keychain backward-compat: legacy записи с `payload["networkType"]` ре-парсятся
/// через `TransportParamParser.parse(query: ["type": legacyValue])` в
/// `ConfigImporter.reparseFromKeychain`. Payload-ключ `networkType` НЕ удалён
/// (preserve existing user installs).
public struct ParsedVLESSTLS: Sendable, Equatable {
    public let uuid: UUID
    public let host: String
    public let port: Int
    public let flow: String?                // nil если отсутствует (sing-box примет "")
    public let sni: String                  // mandatory (R1); fallback в parser-е — host
    public let fingerprint: String          // default "chrome"
    public let alpn: [String]               // default ["h2", "http/1.1"]
    public let transport: TransportConfig   // D-05: было `networkType: String`
    public let remarks: String?

    public init(
        uuid: UUID,
        host: String,
        port: Int,
        flow: String?,
        sni: String,
        fingerprint: String,
        alpn: [String],
        transport: TransportConfig,
        remarks: String?
    ) {
        self.uuid = uuid
        self.host = host
        self.port = port
        self.flow = flow
        self.sni = sni
        self.fingerprint = fingerprint
        self.alpn = alpn
        self.transport = transport
        self.remarks = remarks
    }
}

/// PROTO-02 / D-08 — ParsedTrojan struct.
///
/// Phase 5 D-06 (миграция типа): локальный `ParsedTrojan.TransportType` удалён,
/// поле `transport` теперь имеет тип `TransportConfig` из VPNCore (shared enum
/// для всех протоколов). Pattern matches `if case let .ws(path, host) = parsed.transport`
/// сохраняются — case label `.ws(path:host:)` совпадает в обоих enum'ах.
public struct ParsedTrojan: Sendable, Equatable {
    public let password: String
    public let host: String
    public let port: Int
    public let security: String          // always "tls" в supported case
    public let sni: String                // mandatory (R1, D-08)
    public let fingerprint: String        // default "chrome"
    public let alpn: [String]             // default ["h2", "http/1.1"]
    public let transport: TransportConfig // D-06: было `TransportType` (локальный enum, удалён)
    public let remarks: String?

    public init(password: String, host: String, port: Int, security: String, sni: String,
                fingerprint: String, alpn: [String], transport: TransportConfig, remarks: String?) {
        self.password = password; self.host = host; self.port = port
        self.security = security; self.sni = sni; self.fingerprint = fingerprint
        self.alpn = alpn; self.transport = transport; self.remarks = remarks
    }
}

/// D-05 — `ss://...` (SIP002 + SIP022).
/// Метод проверяется на принадлежность к `supportedSSMethods` set'у в `ShadowsocksURIParser`;
/// unknown method → throws `unsupportedMethod`, попадает в `.unsupported` с `unsupportedSSMethod`.
public struct ParsedShadowsocks: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let method: String               // e.g. "2022-blake3-aes-128-gcm", "chacha20-ietf-poly1305"
    public let password: String             // base64 (SS-2022) или plain UTF-8 (legacy)
    public let remarks: String?

    public init(
        host: String,
        port: Int,
        method: String,
        password: String,
        remarks: String?
    ) {
        self.host = host
        self.port = port
        self.method = method
        self.password = password
        self.remarks = remarks
    }
}

/// D-07 — `hy2://...` / `hysteria2://...`.
/// D-08 R1 EXCEPTION: `allowInsecure: true` пропускается в sing-box `tls.insecure` —
/// единственный протокол, обходящий R1 strict-TLS invariant. Multi-port (D-09) НЕ поддерживается:
/// порты вида `443,8443-9000` → throws `multiPortNotSupported`.
public struct ParsedHysteria2: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let auth: String                 // password
    public let sni: String                  // mandatory (R1, кроме `allowInsecure==true`)
    public let fingerprint: String?
    public let obfs: String?                // только "salamander" поддерживается; иначе throws
    public let obfsPassword: String?
    public let allowInsecure: Bool          // D-08 R1 EXCEPTION
    public let pinSHA256: String?           // certificate_public_key_sha256 pinning
    public let remarks: String?

    public init(
        host: String,
        port: Int,
        auth: String,
        sni: String,
        fingerprint: String?,
        obfs: String?,
        obfsPassword: String?,
        allowInsecure: Bool,
        pinSHA256: String?,
        remarks: String?
    ) {
        self.host = host
        self.port = port
        self.auth = auth
        self.sni = sni
        self.fingerprint = fingerprint
        self.obfs = obfs
        self.obfsPassword = obfsPassword
        self.allowInsecure = allowInsecure
        self.pinSHA256 = pinSHA256
        self.remarks = remarks
    }
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
