import Foundation

/// Phase 10 / DPI-06 / D-03 — CDN dial target overlay.
///
/// **Critical architectural decision D-03:** FrontingProfile НЕ часть TransportConfig.
/// Иначе каждый из 50+ транспортов должен был бы дублировать CDN логику или нести
/// optional поля CDN, которые не используются в 99% случаев.
/// Отдельный struct — CDN config orthogonal к transport config (separation of concerns).
///
/// **Usage:** ConfigImporter (Plan 06 Wave 3) создаёт FrontingProfile из admin subscription JSON
/// и передаёт в FrontingConfigApplier.apply(json:profile:adapter:) как JSON overlay
/// поверх expandConfigForTunnel output. Туннельный extension эту структуру НЕ использует.
///
/// **Schema соответствует D-03 table:**
/// | Field       | Sing-box target      |
/// |-------------|----------------------|
/// | connectHost | outbound.server      |
/// | connectPort | outbound.server_port |
/// | sniHost     | outbound.tls.server_name |
/// | httpHost    | transport.headers.Host (WS) / transport.host (HTTPUpgrade) |

// MARK: - CDNProvider

/// Перечень поддерживаемых CDN-провайдеров.
/// Расширяемо (добавить case + реализовать CDNProviderAdapter) без изменений TransportRegistry.
public enum CDNProvider: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    /// Cloudflare anycast edge (1.1.1.1/CF-Ray header). Frontable через HTTPS proxy workers.
    case cloudflare
    /// Fastly CDN edge. Similar fronting mechanics к Cloudflare.
    case fastly
    /// Admin's own CDN / private reverse proxy. Generic SNI+Host swap.
    case custom
}

// MARK: - FrontingMode

/// Режим получения CDN target endpoint.
///
/// `.domain` — использовать connectHost как hostname напрямую.
/// `.ipPool` — FrontingFallbackChain итерирует IP-пул (admin-provisioned).
/// `.remoteSigned` — CDN config доставляется из subscription JSON (Phase 10 Plan 06).
public enum FrontingMode: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case domain
    case ipPool
    case remoteSigned
}

// MARK: - FrontingProfile

/// Overlay параметры для CDN-фронтинга одного VPN-сервера.
///
/// Создаётся admin через subscription JSON; хранится как `[FrontingProfile]` (пул).
/// FrontingFallbackChain отдаёт следующий profile из пула когда текущий блокируется.
public struct FrontingProfile: Codable, Sendable, Equatable, Hashable {

    /// CDN-провайдер. Определяет конкретный adapter для `applyFronting`.
    public let provider: CDNProvider

    /// Dial target для TCP-соединения: IP или hostname CDN edge.
    /// Примеры: "1.1.1.1", "104.19.208.0", "cdn.example.com".
    public let connectHost: String

    /// TCP порт CDN (обычно 443).
    public let connectPort: Int

    /// TLS server_name (SNI): fronted hostname, который CDN принимает и проксирует к origin.
    /// Пример: "legit-customer.cdn-provider.com" (для Cloudflare SaaS) или "api.example.com".
    public let sniHost: String

    /// HTTP Host header / :authority значение.
    /// Для WS: transport.headers.Host. Для HTTPUpgrade: transport.host.
    /// Обычно совпадает с sniHost, но может отличаться для multi-tenant CDN deployments.
    public let httpHost: String

    /// Режим получения CDN endpoint (см. FrontingMode).
    public let mode: FrontingMode

    public init(
        provider: CDNProvider,
        connectHost: String,
        connectPort: Int,
        sniHost: String,
        httpHost: String,
        mode: FrontingMode
    ) {
        self.provider = provider
        self.connectHost = connectHost
        self.connectPort = connectPort
        self.sniHost = sniHost
        self.httpHost = httpHost
        self.mode = mode
    }
}
