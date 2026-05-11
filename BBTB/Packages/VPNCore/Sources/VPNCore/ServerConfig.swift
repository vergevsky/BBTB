import Foundation
import SwiftData

/// CORE-10 / SRV-01..03: SwiftData @Model для метаданных сервера.
///
/// **Phase 1:** singleton (один `isActive=true`). Секреты (UUID, publicKey, shortId) хранятся
/// в Keychain — поле `keychainTag` указывает на запись.
///
/// **Phase 2 extensions (D-06 / D-04 / D-07):**
/// - `isSupported: Bool = true` — D-04: false для парсеров stubs (ss, vmess, hy2, wireguard);
///   true для vless/trojan. Default true → существующие Phase 1 rows остаются supported.
/// - `subscriptionURL: String? = nil` — D-07: URL подписки, из которой пришёл pool
///   (для replace-pool детекции при re-import). nil для single-paste import.
/// - `outboundJSON: String = ""` — raw outbound JSON snippet для последующей сборки
///   PoolBuilder'ом. Default empty — Phase 1 rows получат пустую строку.
/// - `protocolDisplayName: String = ""` — человеко-читаемое имя протокола
///   («VLESS + Reality», «Trojan», «Shadowsocks (не поддерживается v0.2)»).
/// - `sni: String? = nil` — для D-06 server identity (host+port+protocolID+sni).
/// - `rawURI: String? = nil` — для D-04 re-parse при handler upgrade.
/// - `keychainTag: String? = nil` — стал optional: для unsupported servers нет Keychain entry.
///   SwiftData lightweight migration: existing rows получат старое значение из Phase 1.
@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var protocolID: String       // "vless-reality" / "trojan" / "ss" / etc.
    public var keychainTag: String?     // ключ в Keychain; nil для unsupported (D-04)
    public var isActive: Bool           // singleton legacy; Phase 3 заменит на "selected"
    public var createdAt: Date
    public var lastLatencyMs: Int?      // Phase 3 заполнит

    // Phase 2 fields (D-04, D-06, D-07)
    public var isSupported: Bool        // D-04: false для stub URI-схем (ss/vmess/...)
    public var subscriptionURL: String? // D-07: метаданная пула для replace-by-URL
    public var outboundJSON: String     // raw outbound dict как JSON-string (для re-emit в pool)
    public var protocolDisplayName: String
    public var sni: String?             // D-06 server identity
    public var rawURI: String?          // D-04 — для re-parse при handler upgrade

    public init(id: UUID = UUID(),
                name: String,
                host: String,
                port: Int,
                protocolID: String,
                keychainTag: String?,
                isSupported: Bool = true,
                subscriptionURL: String? = nil,
                outboundJSON: String = "",
                protocolDisplayName: String = "",
                sni: String? = nil,
                rawURI: String? = nil) {
        self.id = id; self.name = name; self.host = host; self.port = port
        self.protocolID = protocolID; self.keychainTag = keychainTag
        self.isActive = false; self.createdAt = .now
        self.isSupported = isSupported
        self.subscriptionURL = subscriptionURL
        self.outboundJSON = outboundJSON
        self.protocolDisplayName = protocolDisplayName
        self.sni = sni
        self.rawURI = rawURI
    }
}
