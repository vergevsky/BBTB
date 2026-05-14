import Foundation

/// Server-side signed manifest для Phase 8 rules distribution.
///
/// **Schema source:** v2 prompt §rules_engine + 08-CONTEXT.md D-05/D-07 + Codex thread
/// `019e2841-e382-7cb1-98b4-793307090ae4` (naming convention: snake_case).
///
/// **Trust path:**
/// 1. VPS compiles rules.json → 3 binary `.srs` files + signs каждый Ed25519.
/// 2. VPS публикует `rules-manifest.json` со списком files + signatures hash.
/// 3. VPS подписывает manifest сам → `rules-manifest.json.sig` (detached signature).
/// 4. Client fetches manifest + sig → `RulesSigner.verify(manifest, sig)` gates apply.
/// 5. Client fetches each `.srs` + соответствующий `.srs.sig` → verify gates write.
///
/// **CategoryBodies optional fields:**
/// - В minimal admin manifests категория может быть empty/missing → optional decode.
/// - В rich manifests (W2.3 currentSnapshot → RULES-09 UI viewer) консамируется
///   как display data — UI отрисовывает таблицу доменов/CIDR/стран без вызова sing-box.
/// - `CategoryBodies.{domains,ipCidrs,countries}` все optional — пустая категория
///   может decode-иться как `{}` без всех трёх полей.
///
/// **CodingKeys mapping (snake_case ↔ camelCase):**
/// - top-level: `min_app_version`, `srs_format_version`, `total_size_bytes`,
///   `block_completely`, `never_through_vpn`, `always_through_vpn`
/// - `FileEntry.sigPath` ↔ `sig_path`
/// - `CategoryBodies.ipCidrs` ↔ `ip_cidrs`
public struct RulesManifest: Codable, Sendable, Equatable {

    /// Monotonically-increasing manifest version. Client refuses to roll back
    /// (`received_version > cached_version` invariant — enforced в W2.3 coordinator).
    public let version: Int

    /// Minimum app version required to consume this manifest. Semver string
    /// (e.g. `"0.8.0"`); compared via `String.compare(_:options: .numeric)` (RULES-08).
    public let minAppVersion: String

    /// SRS binary format version. Phase 8 supports v4 (libbox 1.13.11 max).
    /// W2.3 coordinator rejects manifests с `srs_format_version > 4` per Pitfall 1.
    public let srsFormatVersion: Int

    /// Sum of all `.srs` file sizes in bytes. W2.3 coordinator enforces `< 5 MB`
    /// pre-flight check per Pitfall 3 (NE memory ceiling defense).
    public let totalSizeBytes: Int

    /// Index of `.srs` files referenced by category. Used by W2.3 coordinator
    /// to download + verify each file separately.
    public let files: [FileEntry]

    /// Raw rule body для `block_completely` category — populated в baseline/admin manifests
    /// для read-only viewer (RULES-09). `nil` if minimal manifest (только `.srs` references).
    public let blockCompletely: CategoryBodies?

    /// Raw rule body для `never_through_vpn` category — split-tunnel exclude list.
    public let neverThroughVpn: CategoryBodies?

    /// Raw rule body для `always_through_vpn` category — always-VPN pin list.
    public let alwaysThroughVpn: CategoryBodies?

    public init(
        version: Int,
        minAppVersion: String,
        srsFormatVersion: Int,
        totalSizeBytes: Int,
        files: [FileEntry],
        blockCompletely: CategoryBodies?,
        neverThroughVpn: CategoryBodies?,
        alwaysThroughVpn: CategoryBodies?
    ) {
        self.version = version
        self.minAppVersion = minAppVersion
        self.srsFormatVersion = srsFormatVersion
        self.totalSizeBytes = totalSizeBytes
        self.files = files
        self.blockCompletely = blockCompletely
        self.neverThroughVpn = neverThroughVpn
        self.alwaysThroughVpn = alwaysThroughVpn
    }

    enum CodingKeys: String, CodingKey {
        case version
        case minAppVersion = "min_app_version"
        case srsFormatVersion = "srs_format_version"
        case totalSizeBytes = "total_size_bytes"
        case files
        case blockCompletely = "block_completely"
        case neverThroughVpn = "never_through_vpn"
        case alwaysThroughVpn = "always_through_vpn"
    }

    /// Rule-set category enum — server-side ground truth для три route.rules priority slots
    /// (block > never > always > default — D-01).
    ///
    /// Raw values совпадают с manifest JSON's category field names
    /// (NOT camelCase) so decode-able без отдельных CodingKeys.
    public enum Category: String, Codable, Sendable {
        case block = "block_completely"
        case never = "never_through_vpn"
        case always = "always_through_vpn"
    }

    /// Single `.srs` file descriptor inside manifest.
    public struct FileEntry: Codable, Sendable, Equatable {
        /// Bare filename (e.g. `"bbtb-block.srs"`). NO directory components — relative path
        /// constructed via `AppGroupContainer.rulesCacheDirectory.appendingPathComponent(name)`
        /// в W2.3 coordinator.
        public let name: String
        /// Hex-encoded SHA-256 of `.srs` byte content. W2.3 coordinator verifies
        /// hash after fetch + before signature verify (cheap pre-filter).
        public let sha256: String
        /// Relative URL (relative to manifest's base URL) where соответствующий `.srs.sig`
        /// signature file lives.
        public let sigPath: String
        /// Which routing priority this file feeds.
        public let category: Category

        public init(name: String, sha256: String, sigPath: String, category: Category) {
            self.name = name
            self.sha256 = sha256
            self.sigPath = sigPath
            self.category = category
        }

        enum CodingKeys: String, CodingKey {
            case name
            case sha256
            case sigPath = "sig_path"
            case category
        }
    }

    /// Raw rule body для одной category — domains + IP CIDRs + ISO 3166 country codes.
    ///
    /// Server-side this represents pre-resolve admin input (countries resolved to CIDRs
    /// at signing time per D-04). Client просто decode-ит для UI display (RULES-09) —
    /// никакого client-side IP resolution.
    ///
    /// Все три поля optional чтобы decode допускал empty category `{}`.
    public struct CategoryBodies: Codable, Sendable, Equatable {
        /// Domain names + suffix matchers (e.g. `"example.com"`, `"max.ru"`).
        public let domains: [String]?
        /// IPv4/IPv6 CIDR blocks (e.g. `"192.0.2.0/24"`, `"2001:db8::/32"`).
        public let ipCidrs: [String]?
        /// ISO 3166-1 alpha-2 country codes (e.g. `"RU"`, `"US"`) — resolved server-side.
        public let countries: [String]?

        public init(domains: [String]?, ipCidrs: [String]?, countries: [String]?) {
            self.domains = domains
            self.ipCidrs = ipCidrs
            self.countries = countries
        }

        enum CodingKeys: String, CodingKey {
            case domains
            case ipCidrs = "ip_cidrs"
            case countries
        }
    }
}
