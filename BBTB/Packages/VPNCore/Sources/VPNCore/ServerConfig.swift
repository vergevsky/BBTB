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
    /// Phase 2 carry-forward. **DEPRECATED в Phase 3** (D-05) — заменён на manual FK
    /// `subscriptionID`. Поле остаётся live для lightweight-migration (Pitfall 2);
    /// удаляется в Phase 4 через VersionedSchema. Новый код пишет ОБА поля для
    /// backward-compat (T-03-06 mitigation).
    public var subscriptionURL: String?
    public var outboundJSON: String     // raw outbound dict как JSON-string (для re-emit в pool)
    public var protocolDisplayName: String
    public var sni: String?             // D-06 server identity
    public var rawURI: String?          // D-04 — для re-parse при handler upgrade

    // Phase 3 fields (D-05, D-11) — все optional / с дефолтом → SwiftData lightweight migration.
    /// FK на Subscription.id. nil = «добавлен вручную» (single paste, Phase 3 Plan 03 секция «Manual»).
    public var subscriptionID: UUID?
    /// ISO 3166-1 alpha-2 (например «DE»). Получается из URI fragment `cc=XX` или regex; UI рендерит
    /// в emoji-флаг через computed `countryFlag` (Phase 3 Plan 03). nil = глобус-fallback.
    public var countryCode: String?
    /// Время последнего успешного TCP-probe (Phase 3 Plan 02). nil = ещё не пинговали.
    public var lastPingedAt: Date?
    /// 0..3 — число failed TCP-probe из последнего раунда (D-03). 3 = недоступен.
    public var failedProbeCount: Int?
    /// D-14: true если сервер отсутствовал в последнем re-fetch подписки (Plan 04 merge).
    /// Не удаляется автоматически — пользователь решает swipe-delete.
    public var missingFromLastFetch: Bool = false

    // Phase 5 D-19 — TRANSP-05 manual transport override.
    /// nil = use URI-derived transport (Auto in Picker).
    /// non-nil = user-selected transport in ServerDetailView.
    /// SwiftData lightweight migration: optional Codable enum auto-migrated (Pitfall 3 RESEARCH).
    public var transportOverride: TransportConfig?

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
                rawURI: String? = nil,
                subscriptionID: UUID? = nil,
                countryCode: String? = nil,
                lastPingedAt: Date? = nil,
                failedProbeCount: Int? = nil,
                missingFromLastFetch: Bool = false,
                transportOverride: TransportConfig? = nil) {
        self.id = id; self.name = name; self.host = host; self.port = port
        self.protocolID = protocolID; self.keychainTag = keychainTag
        self.isActive = false; self.createdAt = .now
        self.isSupported = isSupported
        self.subscriptionURL = subscriptionURL
        self.outboundJSON = outboundJSON
        self.protocolDisplayName = protocolDisplayName
        self.sni = sni
        self.rawURI = rawURI
        self.subscriptionID = subscriptionID
        self.countryCode = countryCode
        self.lastPingedAt = lastPingedAt
        self.failedProbeCount = failedProbeCount
        self.missingFromLastFetch = missingFromLastFetch
        self.transportOverride = transportOverride
    }
}

// MARK: - Phase 3 / Plan 03 — display helpers

extension ServerConfig {

    /// UI-SPEC §7.3 — derive emoji-флаг из `countryCode`.
    ///
    /// Regex `^[A-Za-z]{2}$` enforced (T-03-13 mitigation: malicious cc="12" / "!@"
    /// → fallback "🌐"). При корректном 2-letter ISO 3166-1 alpha-2 коде возвращает
    /// emoji через пару Unicode regional indicator symbols (0x1F1E6 + letterIndex).
    public var countryFlag: String {
        guard let code = countryCode,
              code.count == 2,
              code.range(of: "^[A-Za-z]{2}$", options: .regularExpression) != nil
        else {
            return "🌐"
        }
        return code.uppercased().unicodeScalars
            .compactMap { Unicode.Scalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }

    /// True если все 3 probes последнего цикла failed.
    /// Использует ProbeResult (`failedProbeCount >= 3`).
    public var isUnreachable: Bool { (failedProbeCount ?? 0) >= 3 }

    /// Phase 3 / Plan 04 / D-14 — composite key для merge-by-identity при pull-to-refresh.
    ///
    /// Два ServerConfig считаются «тем же сервером» если совпадают `host:port:protocolID`.
    /// SNI намеренно исключён: subscription-серверы ротируют SNI между fetch'ами
    /// (domain-fronting / Reality anti-fingerprint). При re-fetch с тем же identity —
    /// preserve latency fields; обновляются `name` и `sni`.
    public var identity: String {
        "\(host):\(port):\(protocolID)"
    }
}
