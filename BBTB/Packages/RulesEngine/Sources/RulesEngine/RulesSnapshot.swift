import Foundation

/// UI-facing snapshot декодированный из cached `RulesManifest`.
///
/// **Purpose:** materialized view над одним конкретным manifest, для consumption из
/// `SettingsViewModel.rulesSnapshot` (Phase 8 W3 — RULES-09 read-only viewer).
/// Snapshot — Sendable value-type, безопасно переданный между actors / TaskGroup-ами.
///
/// **Decode source:** `RulesEngineCoordinator.currentSnapshot()` берёт `self.cachedManifest`
/// (in-memory copy decoded из last successful refresh) и:
/// 1. Использует `manifest.version`, `manifest.minAppVersion` напрямую.
/// 2. Маппит три `CategoryBodies?` поля manifest'а в три `CategoryEntries` snapshot'а.
///    Если конкретная category отсутствует (nil) — substitutes empty `CategoryEntries()`.
/// 3. `lastFetchedAt` берётся из coordinator state (set после successful refresh
///    или при bootstrap).
///
/// **Equatable** — для SwiftUI `@Published var rulesSnapshot: RulesSnapshot?` diffing.
public struct RulesSnapshot: Sendable, Equatable {

    /// Monotonically-increasing version. 0 = baseline (никогда не fetched с сервера).
    public let version: Int

    /// Когда coordinator последний раз успешно fetched + verified manifest.
    /// nil = baseline только (bootstrap copy, нет network round-trip).
    public let lastFetchedAt: Date?

    /// Категория «block_completely» — список того, что должно быть полностью заблокировано.
    /// Sing-box применит как `block_completely` rule_set (top priority).
    public let block: CategoryEntries

    /// Категория «never_through_vpn» — split-tunnel exclude (доступ только через
    /// прямое подключение, минуя VPN). Sing-box: `never_through_vpn` rule_set.
    public let never: CategoryEntries

    /// Категория «always_through_vpn» — always-VPN pin (доступ только через туннель,
    /// игнорируя split-tunnel hint). Sing-box: `always_through_vpn` rule_set.
    public let always: CategoryEntries

    /// Минимальная версия app для применения этого manifest'а. Phase 8 W4 BG-task
    /// gate'ит через `String.compare(_:options:.numeric)` (RULES-08).
    public let minAppVersion: String

    public init(
        version: Int,
        lastFetchedAt: Date?,
        block: CategoryEntries,
        never: CategoryEntries,
        always: CategoryEntries,
        minAppVersion: String
    ) {
        self.version = version
        self.lastFetchedAt = lastFetchedAt
        self.block = block
        self.never = never
        self.always = always
        self.minAppVersion = minAppVersion
    }
}

/// Domain / CIDR / country triple для одной category.
///
/// Все три поля — value-type arrays, immutable после init. Empty arrays = "category
/// присутствует но пустая" (т.е. ничего не блокируется/не excludes/не pins под этим
/// типом). Чтение из `RulesManifest.CategoryBodies` mapping:
/// `CategoryBodies.domains ?? [] → domains`, etc.
public struct CategoryEntries: Sendable, Equatable {

    /// Domain names + suffix matchers (e.g. `"max.ru"`, `"mssgr.tatar.ru"`,
    /// `"example.com"` — все suffix-matching по sing-box правилам).
    public let domains: [String]

    /// IPv4/IPv6 CIDR блоки (`"192.0.2.0/24"`, `"2001:db8::/32"`). Resolved server-side
    /// из country codes на signing time (D-04) — client никогда не делает GeoIP lookup.
    public let ipCidrs: [String]

    /// ISO 3166-1 alpha-2 country codes — для display only (UI viewer показывает
    /// `"RU"` чтобы admin видел исходный intent). Routing уже работает через ipCidrs.
    public let countries: [String]

    public init(domains: [String] = [], ipCidrs: [String] = [], countries: [String] = []) {
        self.domains = domains
        self.ipCidrs = ipCidrs
        self.countries = countries
    }
}
