# Phase 10: Advanced Settings + Security Polish — Pattern Map

**Mapped:** 2026-05-15
**Files analyzed:** 13 new/modified files
**Analogs found:** 12 / 13

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `AdvancedSettingsView.swift` | component | request-response | `AdvancedSettingsView.swift` (self — extend) | exact |
| `SettingsViewModel.swift` | store/viewmodel | request-response | `SettingsViewModel.swift` (self — extend) | exact |
| `KillSwitch.swift` | utility | request-response | `KillSwitch.swift` (self — extend hook) | exact |
| `AppGroupContainer.swift` | utility | file-I/O | `AppGroupContainer.swift` (self — add paths) | exact |
| `SingBoxConfigLoader.swift` | service | transform | `SingBoxConfigLoader.swift` (self — extend expand) | exact |
| `FrontingProfile.swift` + `CDNProviderAdapter` protocol | model/protocol | transform | `TransportHandler.swift` + `TransportConfig.swift` | role-match |
| `FrontingEngine/` package | service | transform | `RulesEngine/` package structure | role-match |
| `FrontingConfigApplier.swift` | service | transform | `SingBoxConfigLoader.expandConfigForTunnel` (step 5) | role-match |
| `PinnedSessionDelegate.swift` | middleware | request-response | `RulesFetcher.fetch` (URLSession pattern) | partial |
| `SubscriptionPinManager.swift` actor | service | request-response | `RulesEngineCoordinator.swift` | role-match |
| `PinStore.swift` / `PinManifest.swift` | model | file-I/O | `RulesManifest.swift` + `PublicKey.swift` | role-match |
| toggle UI components (CDN/Mux/STUN/Cert/enforceRoutes) | component | request-response | `AdBlockToggleSection.swift` / `KillSwitchToggleSection.swift` | exact |
| `SubscriptionURLFetcher.swift` (modify) | service | request-response | `SubscriptionURLFetcher.swift` (self — wrap session) | exact |

---

## Pattern Assignments

### `AdvancedSettingsView.swift` (component, request-response)

**Analog:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` (current file — extend)

**Imports pattern** (lines 1-2):
```swift
import SwiftUI
import Localization
```

**Current Form structure to extend** (lines 22-77 — full current body):
```swift
public var body: some View {
    Form {
        // Section 1: MinAppVersionBanner (conditional) — KEEP AS IS (lines 27-35)
        if viewModel.showMinAppVersionBanner {
            Section {
                MinAppVersionBanner(
                    currentVersion: viewModel.currentAppVersion,
                    onTap: viewModel.openTestFlight
                )
            }
            .listRowBackground(Color.orange.opacity(0.15))
        }

        // Section 2: DNS (Phase 6, existing) — KEEP AS IS (lines 38-48)
        Section {
            AdBlockToggleSection(isOn: $viewModel.adBlockEnabled, footerText: ...)
            CustomDNSField(text: $viewModel.customDNS)
        } header: { Text(L10n.settingsDnsSection) }
        footer: { Text(L10n.settingsDnsCustomFooter) }

        // NEW Section 3: Anti-DPI — INSERT HERE (between DNS and Rules)
        // NEW Section 4: Безопасность — INSERT HERE (after Anti-DPI)

        // Section 3 (was 3): Rules viewer — KEEP, renumber (lines 51-53)
        // Section 4 (was 4): Force-update — KEEP, renumber (lines 55-70)
    }
    .navigationTitle(L10n.settingsAdvancedTitle)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
}
```

**New Anti-DPI section pattern** (copy Section structure from DNS section, lines 38-48):
```swift
// ─── Section 3: Anti-DPI (Phase 10, NEW) ──────────────────────────────
Section {
    Toggle(L10n.settingsAntiDpiCdnLabel, isOn: $viewModel.cdnFrontingEnabled)
        .accessibilityHint(Text(L10n.settingsAntiDpiCdnFooter))
    Toggle(L10n.settingsAntiDpiMuxLabel, isOn: $viewModel.muxEnabled)
    Picker(L10n.settingsAntiDpiUtlsLabel, selection: $viewModel.utlsFingerprint) {
        ForEach(SettingsViewModel.utlsOptions, id: \.self) { opt in
            Text(opt).tag(opt)
        }
    }
    Toggle(L10n.settingsAntiDpiStunLabel, isOn: $viewModel.stunBlockEnabled)
        .accessibilityHint(Text(L10n.settingsAntiDpiStunFooter))
} header: {
    Text(L10n.settingsAntiDpiSection)
} footer: {
    Text(L10n.settingsAntiDpiStunFooter)  // STUN warning footer
}

// ─── Section 4: Безопасность (Phase 10, NEW) ──────────────────────────
Section {
    Toggle(L10n.settingsSecurityCertPinningLabel, isOn: $viewModel.certPinningEnabled)
    #if os(macOS)
    Toggle(L10n.settingsSecurityEnforceRoutesLabel, isOn: $viewModel.enforceRoutesMacOS)
        .accessibilityHint(Text(L10n.settingsSecurityEnforceRoutesFooter))
    #endif
} header: {
    Text(L10n.settingsSecuritySection)
} footer: {
    Text(L10n.settingsSecurityCertPinningFooter)
}
```

---

### `SettingsViewModel.swift` — new @AppStorage properties (store, request-response)

**Analog:** `SettingsViewModel.swift` lines 27-49 — existing @AppStorage toggle pattern

**Existing @AppStorage pattern to copy** (lines 27-49):
```swift
/// KILL-03 — kill switch toggle.
@AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false

/// Phase 6 / NET-02 — custom DNS.
@AppStorage("app.bbtb.customDNS") public var customDNS: String = ""

/// Phase 6 / NET-03 — adblock.
@AppStorage("app.bbtb.adBlockEnabled") public var adBlockEnabled: Bool = false

/// Phase 6c — auto-reconnect.
@AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true
```

**New properties to add** (follow exact same pattern, place after `autoReconnectEnabled`):
```swift
// MARK: - Phase 10 — Anti-DPI + Security toggles

/// DPI-06 — CDN-fronting global toggle.
@AppStorage("app.bbtb.cdnFrontingEnabled") public var cdnFrontingEnabled: Bool = false

/// DPI-05 — Mux global toggle (smux, max_connections=4, padding=true).
@AppStorage("app.bbtb.muxEnabled") public var muxEnabled: Bool = false

/// DPI-09 — uTLS fingerprint picker. Default: "random" (sing-box 1.13 supported).
@AppStorage("app.bbtb.utlsFingerprint") public var utlsFingerprint: String = "random"

/// BIO-04 — STUN block toggle. Default off (breaks browser video calls).
@AppStorage("app.bbtb.stunBlockEnabled") public var stunBlockEnabled: Bool = false

/// DPI-08 — cert pinning toggle. Default on.
@AppStorage("app.bbtb.certPinningEnabled") public var certPinningEnabled: Bool = true

#if os(macOS)
/// KILL-04 — macOS enforceRoutes toggle. Default on (current hardcoded behavior).
@AppStorage("app.bbtb.enforceRoutesMacOS") public var enforceRoutesMacOS: Bool = true
#endif

/// DPI-09 picker options — sing-box 1.13.11 supported fingerprints.
public static let utlsOptions: [String] = [
    "random", "chrome", "firefox", "safari", "ios", "android", "edge"
]
```

---

### `KillSwitch.swift` — implement `platformShouldDisableEnforceRoutes()` (utility, request-response)

**Analog:** `KillSwitch.swift` lines 50-55 — existing Phase 1 stub

**Current stub to replace** (lines 50-55):
```swift
public static func platformShouldDisableEnforceRoutes() -> Bool {
    // Phase 10 заменит на чтение @AppStorage/UserDefaults флага.
    return false
}
```

**Pattern for reading UserDefaults** (copy key-string convention from SettingsViewModel `@AppStorage`):
```swift
public static func platformShouldDisableEnforceRoutes() -> Bool {
    #if os(macOS)
    // Read same UserDefaults key as SettingsViewModel @AppStorage("app.bbtb.enforceRoutesMacOS")
    // Default true = enforceRoutes=true (current behavior, hardcoded was false meaning no disable).
    let enforceRoutes = UserDefaults.standard.object(forKey: "app.bbtb.enforceRoutesMacOS")
        .flatMap { $0 as? Bool } ?? true
    return !enforceRoutes   // disable = !enforceRoutes
    #else
    return false            // iOS 26: includeAllNetworks overrides enforceRoutes
    #endif
}
```

---

### `AppGroupContainer.swift` — add CDN failure cache + cert pin manifest paths (utility, file-I/O)

**Analog:** `AppGroupContainer.swift` lines 55-58 — `rulesCacheDirectory` pattern

**Exact pattern to copy** (lines 55-58 — idempotent createDirectory subdirectory):
```swift
public static var rulesCacheDirectory: URL {
    let dir = url.appendingPathComponent("Library/Caches/rules", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

**New paths to add** (copy pattern exactly):
```swift
/// Phase 10 — CDN failure score cache: {(provider, ip, networkType) → failureScore + cooldown}.
/// Main app writer (FrontingEngine). Extension read-only (optional, Phase 10 v0.10 skipped).
public static var cdnFailureCacheURL: URL {
    let dir = url.appendingPathComponent("Library/Caches/cdn", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("cdn-failure-cache.json")
}

/// Phase 10 — cert pin manifest cache: subscription-pins.json + .sig (Ed25519-signed).
/// Main app writer (SubscriptionPinManager). Extension does NOT use (pinning = main app only).
public static var certPinManifestDirectory: URL {
    let dir = url.appendingPathComponent("Library/Caches/pins", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

---

### `SingBoxConfigLoader.swift` — Mux injection + STUN block (service, transform)

**Analog:** `SingBoxConfigLoader.swift` — `expandConfigForTunnel(_:)` method (lines 144-330)

**Existing injection pattern to copy** — Phase 8 rule_set injection (lines 270-323):

The pattern: read UserDefaults bool → conditionally inject into `root["route"]` mutated dict → set back.

**STUN block injection** (insert after step 5b, before final serialization — lines 319-323):
```swift
// 6. Phase 10 — STUN block route.rule [if stunBlockEnabled in UserDefaults].
// sing-box 1.13.11 does NOT have protocol:"stun" matcher — use port+network instead.
let stunBlockEnabled = UserDefaults(suiteName: AppGroupContainer.identifier)?
    .bool(forKey: "app.bbtb.stunBlockEnabled") ?? false
if stunBlockEnabled {
    if var route = root["route"] as? [String: Any] {
        var rules = (route["rules"] as? [[String: Any]]) ?? []
        let hasSTUN = rules.contains { ($0["network"] as? String) == "udp"
                                    && ($0["port"] as? [Int]) == [3478, 5349] }
        if !hasSTUN {
            // Insert after sniff+hijack-dns (before rule_set priority rules).
            let insertIdx = rules.firstIndex {
                ($0["action"] as? String) == "hijack-dns"
            }.map { $0 + 1 } ?? 2
            rules.insert(["port": [3478, 5349], "network": "udp", "action": "reject"], at: insertIdx)
            route["rules"] = rules
            root["route"] = route
        }
    }
}
```

**Mux injection** (insert after STUN block — iterate outbounds, whitelist-gate):
```swift
// 7. Phase 10 — Mux injection [if muxEnabled in UserDefaults]. D-09 whitelist.
// Allowed protocols: vless (TLS, not Reality/Vision), trojan, shadowsocks.
// Forbidden: reality (XTLS), tuic, hysteria2 (QUIC multiplexed already).
let muxEnabled = UserDefaults(suiteName: AppGroupContainer.identifier)?
    .bool(forKey: "app.bbtb.muxEnabled") ?? false
if muxEnabled, var outbounds = root["outbounds"] as? [[String: Any]] {
    let muxWhitelist: Set<String> = ["vless", "trojan", "shadowsocks"]
    for i in outbounds.indices {
        guard let type = outbounds[i]["type"] as? String,
              muxWhitelist.contains(type) else { continue }

        // Exclude Reality/Vision: vless with tls.reality
        if type == "vless",
           let tls = outbounds[i]["tls"] as? [String: Any],
           tls["reality"] != nil { continue }
        // Exclude Vision flow (XTLS)
        if type == "vless",
           let flow = outbounds[i]["flow"] as? String,
           flow.contains("vision") { continue }

        // Inject multiplex block (idempotent — skip if already present)
        if outbounds[i]["multiplex"] == nil {
            outbounds[i]["multiplex"] = [
                "enabled": true,
                "protocol": "smux",
                "max_connections": 4,
                "padding": true,   // DPI-03 per-packet padding side-effect
            ] as [String: Any]
        }
    }
    root["outbounds"] = outbounds
}
```

**Function signature — add new parameters** (extend existing signature at line 144):
```swift
public static func expandConfigForTunnel(
    json: String,
    mtu: Int = 1500,
    tunIP: String = "198.18.0.1",
    logPath: String? = nil,
    logLevel: String = "debug"
) throws -> String {
    // UserDefaults suite reads from App Group container — same suite used by main app
    // @AppStorage. This is the established pattern in SingBoxConfigLoader (AppGroupContainer
    // identifer reuse, see lines 274-286 for rulesCacheDirectory usage).
```

---

### `FrontingProfile.swift` + `CDNProviderAdapter` protocol (model + protocol, transform)

**Analog:** `TransportConfig.swift` (lines 1-49) + `TransportHandler.swift` (lines 1-31)

**TransportConfig pattern to copy** (lines 19-49 — enum with associated values + Codable + Sendable):
```swift
// TransportConfig.swift lines 19-49: Codable Sendable enum with identifier + displayName
public enum TransportConfig: Sendable, Equatable, Codable, Hashable {
    case tcp
    case ws(path: String, host: String)
    // ...
    public var identifier: String { ... }
    public var displayName: String { ... }
}
```

**FrontingProfile** (struct, not enum — Codable + Sendable, D-03):
```swift
// FrontingEngine/Sources/FrontingEngine/FrontingProfile.swift
import Foundation

public struct FrontingProfile: Codable, Sendable, Equatable {
    public let provider: CDNProvider        // .cloudflare, .fastly, .custom
    public let connectHost: String          // CDN IP or domain (dial target)
    public let connectPort: Int             // usually 443
    public let sniHost: String              // fronted hostname (TLS server_name)
    public let httpHost: String             // Host/:authority header value
    public let mode: FrontingMode           // .domain, .ipPool, .remoteSigned
}

public enum CDNProvider: String, Codable, Sendable { case cloudflare, fastly, custom }
public enum FrontingMode: String, Codable, Sendable { case domain, ipPool, remoteSigned }
```

**TransportHandler protocol pattern to copy** (lines 13-31 — protocol contract):
```swift
// TransportHandler.swift lines 13-31
public protocol TransportHandler: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    static var supportedProtocols: [String] { get }
    static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
}
```

**CDNProviderAdapter protocol** (mirror TransportHandler structure):
```swift
// FrontingEngine/Sources/FrontingEngine/CDNProviderAdapter.swift
public protocol CDNProviderAdapter: Sendable {
    static var provider: CDNProvider { get }
    static var displayName: String { get }
    /// Apply FrontingProfile overlay to a sing-box outbound JSON dict.
    /// Mutates server, tls.server_name, transport.headers.Host or equivalent.
    /// Returns nil if this outbound type is incompatible (Reality/TUIC/Hysteria2).
    static func applyFronting(
        to outbound: inout [String: Any],
        profile: FrontingProfile
    ) -> Bool
}
```

---

### `FrontingEngine/` package (SwiftPM package, transform)

**Analog:** `BBTB/Packages/RulesEngine/Package.swift` (full file) — package structure

**RulesEngine package structure to mirror:**
- `swift-tools-version: 6.0`
- `platforms: [.iOS(.v18), .macOS(.v15)]`
- `products: [.library(name: "FrontingEngine", targets: ["FrontingEngine"])]`
- `dependencies`: local `VPNCore`, `PacketTunnelKit` (for `AppGroupContainer`)
- `resources: [.process("Resources")]` — for bootstrap CDN IP pool JSON
- linkerSettings pattern from RulesEngine/Package.swift lines 64-75

**Directory structure** (mirror RulesEngine layout):
```
FrontingEngine/
  Sources/FrontingEngine/
    FrontingProfile.swift          ← Codable model (D-03)
    CDNProviderAdapter.swift       ← protocol (D-04)
    CloudflareAdapter.swift        ← protocol impl
    FastlyAdapter.swift            ← protocol impl
    CustomCDNAdapter.swift         ← protocol impl
    FrontingConfigApplier.swift    ← JSON overlay applier
    CDNFailureCache.swift          ← score cache (App Group JSON, D-06)
  Tests/FrontingEngineTests/
```

---

### `FrontingConfigApplier.swift` (service, transform)

**Analog:** `SingBoxConfigLoader.swift` step 5b (lines 294-323) — inject into JSON dict pattern

**Step 5b pattern to copy** (lines 294-323 — loop + mutate outbounds):
```swift
// SingBoxConfigLoader.swift lines 294-320 — mutable dict mutation + JSON re-serialization
var outbounds = (root["outbounds"] as? [[String: Any]]) ?? []
// ... loop: check type, mutate dict, set back
root["outbounds"] = outbounds
let modifiedData = try JSONSerialization.data(withJSONObject: root, options: [])
guard let modifiedString = String(data: modifiedData, encoding: .utf8) else {
    throw SingBoxConfigError.malformedJSON
}
return modifiedString
```

**FrontingConfigApplier** applies profile after `expandConfigForTunnel`:
```swift
// FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift
public enum FrontingConfigApplier {
    /// Apply CDN fronting overlay to already-expanded sing-box JSON.
    /// Called from ConfigImporter after SingBoxConfigLoader.expandConfigForTunnel.
    /// Returns modified JSON string.
    /// Skips Reality/TUIC/Hysteria2 outbounds per D-05.
    public static func apply(
        json: String,
        profile: FrontingProfile,
        adapter: any CDNProviderAdapter.Type
    ) throws -> String {
        // Same JSONSerialization pattern as SingBoxConfigLoader.expandConfigForTunnel
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw FrontingError.malformedJSON }
        // ... mutate outbounds ...
        let modified = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let result = String(data: modified, encoding: .utf8) else {
            throw FrontingError.malformedJSON
        }
        return result
    }
}
```

---

### `PinnedSessionDelegate.swift` (middleware, request-response)

**Analog:** `SubscriptionURLFetcher.fetch` (lines 80-106) — URLSession + URLRequest pattern; `RulesFetcher.fetch` (lines 86-159) for error handling style

**URLSession request pattern from SubscriptionURLFetcher** (lines 94-106):
```swift
// SubscriptionURLFetcher.swift lines 94-106
var request = URLRequest(url: url)
request.timeoutInterval = 10
request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
request.setValue("text/plain, application/json, */*", forHTTPHeaderField: "Accept")
request.cachePolicy = .reloadIgnoringLocalCacheData

let (data, response) = try await session.data(for: request)
guard let httpResp = response as? HTTPURLResponse else { throw FetchError.notHTTPResponse }
guard (200..<300).contains(httpResp.statusCode) else { throw FetchError.httpStatusError(httpResp.statusCode) }
```

**PinnedSessionDelegate** — NSObject + URLSessionDelegate pattern (D-11):
```swift
// ConfigParser/Sources/ConfigParser/PinnedSessionDelegate.swift
import Foundation
import CryptoKit    // SHA256 — system framework, no additional dep on Apple platforms

/// DPI-08 — SPKI SHA-256 certificate pinning delegate for SubscriptionURLFetcher.
/// NSObject required for URLSessionDelegate protocol conformance (ObjC bridging).
public final class PinnedSessionDelegate: NSObject, URLSessionDelegate {
    private let pinStore: PinStore

    public init(pinStore: PinStore) {
        self.pinStore = pinStore
    }

    // The core hook — called by URLSession for server trust challenges.
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod ==
              NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Extract server public key (SPKI).
        // SecTrustCopyKey is iOS 14+ / macOS 11+ — our deployment target is iOS 18+/macOS 15+.
        guard let serverKey = SecTrustCopyKey(serverTrust),
              let keyData = SecKeyCopyExternalRepresentation(serverKey, nil) as Data?
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Hash SPKI bytes (SHA-256) — survives cert renewal on same key (D-11).
        let spkiHash = SHA256.hash(data: keyData)
        let spkiHashData = Data(spkiHash)

        if pinStore.isValid(spkiHash: spkiHashData, for: challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

---

### `SubscriptionPinManager.swift` actor (service, request-response)

**Analog:** `RulesEngineCoordinator.swift` (lines 109-529) — actor + bootstrap + performBackgroundRefresh + currentSnapshot pattern

**Actor declaration + init pattern** (lines 109-183 — injected dependencies, actor-isolated state):
```swift
// RulesEngineCoordinator.swift lines 109-183
public actor RulesEngineCoordinator {
    private let fetcher: RulesFetcherProtocol
    private let cache: SRSCacheStore
    private let clock: ClockProtocol
    private let mirrorURLs: [URL]
    private let signer: SignatureVerifierProtocol

    private var cachedManifest: RulesManifest?
    private var lastFetchedAt: Date?
    private var isInFlight: Bool = false

    public init(
        fetcher: RulesFetcherProtocol = DefaultRulesFetcher(),
        cache: SRSCacheStore = SRSCacheStore(),
        clock: ClockProtocol = SystemClock(),
        mirrorURLs: [URL] = RulesEngineCoordinator.productionMirrors,
        signer: SignatureVerifierProtocol = DefaultRulesSigner()
    ) { ... }
}
```

**Bootstrap pattern** (lines 199-251 — idempotent cache check + bundle copy):
```swift
// RulesEngineCoordinator.swift lines 199-251
public func bootstrap() async {
    let alreadyBootstrapped = await cache.exists(filename: "baseline-rules-manifest.json")
    if alreadyBootstrapped {
        // restore cachedManifest from disk on cold-start
        if cachedManifest == nil, let data = await cache.read(filename: "...") {
            cachedManifest = try JSONDecoder().decode(RulesManifest.self, from: data)
        }
        return
    }
    // copy from Bundle.module → App Group cache
    let (manifestData, manifestSig) = try BaselineRulesLoader.loadManifest()
    try await cache.write(manifestData, filename: "baseline-rules-manifest.json")
    cachedManifest = try JSONDecoder().decode(RulesManifest.self, from: manifestData)
}
```

**SubscriptionPinManager** (mirror coordinator, simplified):
```swift
// ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift
// OR new FrontingEngine/ if CDN package absorbs pin management
public actor SubscriptionPinManager {
    // Mirror RulesEngineCoordinator fields but for pin manifest
    private var cachedPins: PinManifest?
    private var isInFlight: Bool = false
    private let cache: SRSCacheStore   // reuse SRSCacheStore(directory: AppGroupContainer.certPinManifestDirectory)
    private let signer: SignatureVerifierProtocol = DefaultRulesSigner()  // same Ed25519 key
    private let mirrorURLs: [URL]      // subscription-pins.json mirror URLs

    // bootstrap(): load hardcoded PinStore from bundle → write to App Group
    // performBackgroundRefresh(): fetch subscription-pins.json + .sig → Ed25519 verify → cache
    // currentPins(): merged (hardcoded bootstrap ∪ remote, dedupe by SPKI hash)
}
```

---

### `PinManifest.swift` + `PinStore.swift` (models, file-I/O)

**Analog:** `RulesManifest.swift` (lines 27-158) — Codable schema with CodingKeys + `PublicKey.swift` (lines 37-60) — hardcoded bootstrap bytes

**RulesManifest Codable pattern** (lines 27-88 — struct + CodingKeys snake_case mapping):
```swift
// RulesManifest.swift lines 27-88
public struct RulesManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let minAppVersion: String
    // ...
    enum CodingKeys: String, CodingKey {
        case version
        case minAppVersion = "min_app_version"
        case srsFormatVersion = "srs_format_version"
        // snake_case mapping for all fields
    }
}
```

**PinManifest** (D-12 schema — copy Codable pattern):
```swift
// FrontingEngine or ConfigParser: PinManifest.swift
public struct PinManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let validFrom: Date
    public let validUntil: Date           // hard reject if expired (D-12 policy)
    public let host: String               // subscription endpoint hostname
    public let spkiSha256Pins: [String]   // primary pins (hex-encoded SHA-256)
    public let backupPins: [String]       // backup pins for key rotation
    // CodingKeys: snake_case → camelCase (same pattern as RulesManifest)
    enum CodingKeys: String, CodingKey {
        case version
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case host
        case spkiSha256Pins = "spki_sha256_pins"
        case backupPins = "backup_pins"
    }
}
```

**Bootstrap hardcoded pins** (copy PublicKey.swift pattern — lines 37-60):
```swift
// PublicKey.swift lines 37-60 — hardcoded byte array pattern
enum PublicKey {
    private static let publicKeyBytes: [UInt8] = [
        0xB5, 0x3F, 0xCF, 0xC3, ...  // 32 bytes
    ]
    static let publicKey: Curve25519.Signing.PublicKey = {
        try! Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKeyBytes))
    }()
}
```

**PinStore** (adapt pattern — hex strings instead of raw bytes):
```swift
// ConfigParser/Sources/ConfigParser/PinStore.swift
public struct PinStore: Sendable {
    /// Hardcoded SPKI SHA-256 pins (bootstrap, D-12). Replace with real values before production.
    /// Format: lowercase hex-encoded SHA-256 of DER-encoded SubjectPublicKeyInfo.
    public static let bootstrapPins: [String] = [
        "PLACEHOLDER_PIN_1_sha256_hex_64chars",  // current key
        "PLACEHOLDER_PIN_2_sha256_hex_64chars",  // backup key
    ]

    private let pins: Set<String>  // merged bootstrap + remote (lowercased)

    public func isValid(spkiHash: Data, for host: String) -> Bool {
        let hex = spkiHash.map { String(format: "%02x", $0) }.joined()
        return pins.contains(hex)
    }
}
```

---

### Toggle UI components: CDN/Mux/STUN/Cert pinning/enforceRoutes (component, request-response)

**Analog:** `AdBlockToggleSection.swift` (lines 1-19) + `KillSwitchToggleSection.swift` (lines 1-18)

**Exact pattern to copy** (AdBlockToggleSection.swift lines 1-19):
```swift
import SwiftUI
import Localization

public struct AdBlockToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String

    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn
        self.footerText = footerText
    }

    public var body: some View {
        Toggle(L10n.settingsDnsAdblockLabel, isOn: $isOn)
            .accessibilityHint(Text(footerText))
    }
}
```

Phase 10 does NOT need separate toggle component files. The pattern for Phase 10 is:
- Use `Toggle(L10n.xyz, isOn: $viewModel.property)` inline in `AdvancedSettingsView` Section (D-15 layout)
- No separate `XyzToggleSection.swift` files — existing DNS section uses `AdBlockToggleSection` for historical reasons but D-15 specifies inline toggles for Anti-DPI/Security sections
- `Picker` for uTLS follows SwiftUI `Picker(label, selection: $binding)` standard form

---

### `SubscriptionURLFetcher.swift` — wrap with `PinnedSessionDelegate` (service, request-response)

**Analog:** `SubscriptionURLFetcher.swift` lines 80-106 — `fetch(url:session:)` static function with injectable session

**Injectable session pattern** (lines 80-82 + line 100):
```swift
// SubscriptionURLFetcher.swift lines 80-82
public static func fetch(url: URL, session: URLSession = .shared) async throws -> SubscriptionFetchResult {
    // ...
    let (data, response) = try await session.data(for: request)
```

**DefaultSubscriptionURLFetcher pattern** (lines 41-45 — protocol impl wraps static func):
```swift
// SubscriptionURLFetcher.swift lines 41-45
public struct DefaultSubscriptionURLFetcher: SubscriptionURLFetching, Sendable {
    public init() {}
    public func fetch(url: URL) async throws -> SubscriptionFetchResult {
        try await SubscriptionURLFetcher.fetch(url: url, session: .shared)
    }
}
```

**Pinned variant** (add alongside existing — D-13: only main app, not extension):
```swift
/// DPI-08 pinned variant — wraps SubscriptionURLFetcher.fetch with PinnedSessionDelegate.
/// Used when certPinningEnabled == true (D-14). Falls back to .shared when disabled.
public struct PinnedSubscriptionURLFetcher: SubscriptionURLFetching, Sendable {
    private let pinStore: PinStore

    public init(pinStore: PinStore) {
        self.pinStore = pinStore
    }

    public func fetch(url: URL) async throws -> SubscriptionFetchResult {
        let delegate = PinnedSessionDelegate(pinStore: pinStore)
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )
        return try await SubscriptionURLFetcher.fetch(url: url, session: session)
    }
}
```

---

## Shared Patterns

### @AppStorage Toggle State
**Source:** `SettingsViewModel.swift` lines 27-49
**Apply to:** All new toggle additions in Phase 10 (`cdnFrontingEnabled`, `muxEnabled`, `stunBlockEnabled`, `certPinningEnabled`, `enforceRoutesMacOS`, `utlsFingerprint`)
```swift
@AppStorage("app.bbtb.<key>") public var <property>: <Type> = <default>
```
Key convention: always `app.bbtb.<camelCase>`. Booleans default off unless explicitly security-default-on (certPinningEnabled=true, enforceRoutesMacOS=true).

### Ed25519 Signature Verify
**Source:** `RulesSigner.swift` (lines 41-80) + `PublicKey.swift` (lines 37-60)
**Apply to:** `SubscriptionPinManager.performBackgroundRefresh()` pin manifest verify
```swift
// Reuse DefaultRulesSigner — same Ed25519 key signs both rules.json and subscription-pins.json
let isValid = signer.verify(message: manifestData, signature: manifestSig)
guard isValid else { /* reject */ }
```

### Actor + Bootstrap Pattern
**Source:** `RulesEngineCoordinator.swift` lines 199-251 (bootstrap) + 267-277 (re-entry guard)
**Apply to:** `SubscriptionPinManager` actor
```swift
// Re-entry guard pattern (lines 267-277):
guard !isInFlight else { return false }
isInFlight = true
defer { isInFlight = false }
```

### App Group Subdirectory Path
**Source:** `AppGroupContainer.swift` lines 55-58 (`rulesCacheDirectory`)
**Apply to:** `cdnFailureCacheURL`, `certPinManifestDirectory`, `SRSCacheStore(directory: AppGroupContainer.certPinManifestDirectory)` in SubscriptionPinManager
```swift
let dir = url.appendingPathComponent("Library/Caches/<name>", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
return dir
```

### JSON Dict Mutation in expandConfigForTunnel
**Source:** `SingBoxConfigLoader.swift` lines 270-323 (Phase 8 rule_set injection)
**Apply to:** Mux injection (step 7) + STUN block injection (step 6) in `expandConfigForTunnel`
Pattern: `var root = ...`, mutate subdicts, `root["route"] = route`, then `JSONSerialization.data(withJSONObject: root)`.

### Sequential Mirror Failover
**Source:** `RulesFetcher.fetchWithFailover` (lines 174-217)
**Apply to:** `SubscriptionPinManager.performBackgroundRefresh()` — fetch subscription-pins.json from mirror URLs
```swift
// DEC-06d-04 bounded concurrency=1 — sequential, not parallel
for (idx, url) in urls.enumerated() {
    do { return try await fetch(url: url, ...) }
    catch { collectedErrors.append(...); continue }
}
throw FetchError.allMirrorsFailed(collectedErrors)
```

### SwiftUI Section with header + footer
**Source:** `AdvancedSettingsView.swift` lines 38-48 (DNS section)
**Apply to:** New Anti-DPI section + Безопасность section
```swift
Section {
    // Toggle rows
} header: {
    Text(L10n.sectionHeaderKey)
} footer: {
    Text(L10n.sectionFooterKey)
}
```

### Platform conditional (#if os(macOS))
**Source:** `AdvancedSettingsView.swift` lines 73-75 + `SettingsViewModel.swift` lines 486-492
**Apply to:** `enforceRoutesMacOS` toggle (D-17 — macOS only)
```swift
#if os(macOS)
// enforceRoutes toggle
#endif
```

### OSLog Logging
**Source:** `SettingsViewModel.swift` line 272: `Logger(subsystem: "app.bbtb.client", category: "...")`
**Apply to:** `SubscriptionPinManager`, `FrontingConfigApplier`, `PinnedSessionDelegate`
```swift
let log = Logger(subsystem: "app.bbtb.client", category: "cert-pinning")
// or use RulesEngineLogger pattern (OSSignposter) for FrontingEngine actor
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| SecTrust SPKI extraction (inside `PinnedSessionDelegate`) | utility | request-response | No existing cert-pinning or Security.framework usage in codebase. Planner must use RESEARCH.md §State of the Art: `SecTrustCopyKey` + `SecKeyCopyExternalRepresentation` + `CryptoKit.SHA256.hash(data:)` |

---

## Metadata

**Analog search scope:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/`, `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/`, `BBTB/Packages/RulesEngine/Sources/RulesEngine/`, `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/`, `BBTB/Packages/ConfigParser/Sources/ConfigParser/`, `BBTB/Packages/KillSwitch/Sources/KillSwitch/`, `BBTB/Packages/VPNCore/Sources/VPNCore/`
**Files scanned:** 32 source files
**Pattern extraction date:** 2026-05-15
