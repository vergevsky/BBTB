import Foundation

/// Phase 6 / NET-01..NET-04 — единый value-type, описывающий DNS-стратегию BBTB.
/// (Decisions D-01..D-04 в `.planning/phases/06-network-resilience/06-CONTEXT.md`.)
///
/// **Bootstrap DNS** = pre-tunnel DNS, видимый ТСПУ до поднятия туннеля. Используется
/// sing-box чтобы разрешить hostname в `dns-remote.address` (например `cloudflare-dns.com`).
/// D-01 priority: server IP (zero DNS lookup) → AdGuard `94.140.14.14` → Cloudflare `1.1.1.1`.
/// Резолвинг приоритета — ответственность `SettingsViewModel` / `ConfigImporter` (Wave 3 / Wave 5);
/// в `DNSConfig.bootstrapAddress` приходит уже готовое значение в формате sing-box
/// (`tcp://<ip>` или `https://<host>/dns-query`).
///
/// **Tunnel DNS** = DoH endpoint внутри туннеля. D-02..D-04 priority:
/// `customDNS` > AdGuard (если AdBlock) > Cloudflare (default). Резолвинг приоритета —
/// тоже на стороне `SettingsViewModel`; в `tunnelDNS` уже приходит конкретный enum-case.
///
/// **Сознательно НЕ содержит** валидации (валидация IPv4/RFC1123 hostname для
/// `.custom` — в `SettingsViewModel.validateCustomDNS` и `ConfigImporter.buildDNSConfig`).
/// `DNSConfig` — dumb value carrier, который пересекает actor-границы между UI,
/// `ConfigImporter` и extension-side `PoolBuilder`.
///
/// Codable: используется synthesized conformance (SE-0295, Swift 5.5+) для struct +
/// nested enum с associated values. Никаких custom `CodingKeys` / `init(from:)` /
/// `encode(to:)` — это снижает риск рассинхрона при будущих миграциях.
///
/// **Single source of truth для:**
/// - удалённого DoH endpoint (`cloudflare-dns.com`, `dns.adguard-dns.com`, custom);
/// - формата bootstrap address (sing-box принимает `tcp://`, `udp://`, `https://`, `tls://`).
public struct DNSConfig: Sendable, Equatable, Codable, Hashable {

    /// Адрес bootstrap-сервера в sing-box формате (`tcp://<ip>`, `https://<host>/dns-query`).
    /// D-01: ConfigImporter подставляет server IP или AdGuard/Cloudflare fallback.
    public let bootstrapAddress: String

    /// Туннельный DoH-провайдер. D-02..D-04: SettingsViewModel выбирает один из трёх case.
    public let tunnelDNS: TunnelDNSProvider

    /// DoH-провайдер внутри туннеля. Все три варианта возвращают полноценный DoH URL
    /// через `DNSConfig.dohAddress()`.
    public enum TunnelDNSProvider: Sendable, Equatable, Codable, Hashable {
        /// Cloudflare DoH — `https://cloudflare-dns.com/dns-query` (D-02 default).
        case cloudflare
        /// AdGuard DoH — `https://dns.adguard-dns.com/dns-query` (D-04 — AdBlock toggle).
        case adguard
        /// User-provided DoH URL или `tcp://<ip>` (D-03). Caller обязан pre-formated.
        case custom(address: String)
    }

    public init(bootstrapAddress: String, tunnelDNS: TunnelDNSProvider) {
        self.bootstrapAddress = bootstrapAddress
        self.tunnelDNS = tunnelDNS
    }

    /// Безопасный default для тестов и fallback'ов до того, как `SettingsViewModel`
    /// инициализирован. ConfigImporter (Wave 5) переопределяет bootstrap на server IP
    /// per D-01. `tunnelDNS = .cloudflare` per D-02.
    public static let `default` = DNSConfig(
        bootstrapAddress: "tcp://1.1.1.1",
        tunnelDNS: .cloudflare
    )

    /// Полный DoH URL для записи в `dns.servers[*].address` sing-box JSON.
    public func dohAddress() -> String {
        switch tunnelDNS {
        case .cloudflare:
            return "https://cloudflare-dns.com/dns-query"
        case .adguard:
            return "https://dns.adguard-dns.com/dns-query"
        case .custom(let address):
            return address
        }
    }
}
