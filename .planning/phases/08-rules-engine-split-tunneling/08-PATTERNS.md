# Phase 8: Rules Engine + Split tunneling — Pattern Map

**Mapped:** 2026-05-15
**Files analyzed:** 27 new + 11 modified + 1 delete
**Analogs found:** 38 / 38 (exact or role-match in BBTB codebase)

> **Scope summary (from CONTEXT/RESEARCH/UI-SPEC):** Phase 8 добавляет SwiftPM-пакет `RulesEngine` (fetch + Ed25519 verify + atomic App Group write), расширяет `SingBoxConfigLoader.expandConfigForTunnel` injection'ом 3 `route.rule_set` entries + priority rules, добавляет 5 SwiftUI компонентов в Settings/Main, регистрирует `BGAppRefreshTask` (iOS) + `NSBackgroundActivityScheduler` (macOS), удаляет `BBTB-AppProxy-macOS` target из Tuist, и расширяет `validate-r1-r6.sh` Phase 8 invariants. Все эти изменения находят прямые аналоги в существующих Phase 1-7 паттернах.

> **Match quality legend:**
> - **exact** — same role + same data flow + same package layout.
> - **role-match** — same role (e.g. SwiftUI section, actor coordinator), data flow или layer слегка отличается.
> - **partial** — есть analog, но pattern частично новый (e.g. `RulesEngineCoordinator` есть structurally похожий `TunnelController`, но domain-уникальный).

---

## File Classification

### NEW FILES (24)

| File | Role | Data Flow | Closest Analog | Match |
|------|------|-----------|----------------|-------|
| `BBTB/Packages/RulesEngine/Package.swift` | package-manifest | n/a | `BBTB/Packages/ConfigParser/Package.swift` | exact |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift` | service (HTTPS fetcher) | request-response | `Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` | exact |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift` | utility (crypto verify) | transform | `Packages/VPNCore/Sources/VPNCore/KeychainStore.swift` (Apple-API wrapper enum) | role-match |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` | config-constant | n/a | `Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` (enum singleton with `static let`) | exact |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesManifest.swift` | model (Codable) | transform | `Packages/VPNCore/Sources/VPNCore/Subscription.swift` (Codable struct) | role-match |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSnapshot.swift` | model (value-type) | transform | `Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` → `SupportedServerSnapshot` (Sendable value snapshot) | exact |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift` | store (App Group FS) | file-I/O | `Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` + Phase 6 `ExternalVPNStopMarker.swift` (App Group marker write/read) | exact |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/BaselineRulesLoader.swift` | utility (bundle Resources) | file-I/O | `Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift::loadVLESSRealityTemplate()` | exact |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift` | coordinator (actor) | event-driven (fetch → verify → write → notify) | `Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` + `FailoverProvider.swift` (two-phase init actor) | role-match |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift` | utility (OSLog) | logging | `Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift` | exact |
| `BBTB/Packages/RulesEngine/Resources/baseline-rules-manifest.json` | resource (signed asset) | file-I/O | `Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json` | exact |
| `BBTB/Packages/RulesEngine/Resources/baseline-rules-manifest.json.sig` | resource (binary asset) | file-I/O | (none — new pattern; binary sidecar) | partial |
| `BBTB/Packages/RulesEngine/Resources/bbtb-baseline-block.srs` | resource (binary) | file-I/O | (none; SRS binary v4 — new) | partial |
| `BBTB/Packages/RulesEngine/Resources/bbtb-baseline-block.srs.sig` | resource (binary sidecar) | file-I/O | (none; partner of above) | partial |
| `BBTB/Packages/RulesEngine/Resources/bbtb-baseline-never.srs` (+`.sig`) | resource (binary) | file-I/O | same as block.srs | partial |
| `BBTB/Packages/RulesEngine/Resources/bbtb-baseline-always.srs` (+`.sig`) | resource (binary) | file-I/O | same as block.srs | partial |
| `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesFetcherTests.swift` | test | request-response | `Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift` (existing pattern in same package) | exact |
| `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesSignerTests.swift` | test | transform | `Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` (pure-function validate tests) | exact |
| `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift` | test (actor integration) | event-driven | `Packages/AppFeatures/Tests/MainScreenFeatureTests/*` (TunnelController DI mock pattern) | role-match |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift` | component (SwiftUI Section) | display | `Packages/AppFeatures/Sources/SettingsFeature/AdBlockToggleSection.swift` + `Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift` | exact |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift` | component (SwiftUI) | request-response | `Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` (state machine button) + `Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift` | exact |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/MinAppVersionBanner.swift` | component (SwiftUI) | display | `Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift` | exact |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MinAppVersionSheet.swift` | component (modal) | display | `Packages/AppFeatures/Sources/MainScreenFeature/EmptyStateCard.swift` (icon + title + 2 buttons) | exact |
| `BBTB/scripts/build-baseline-rules.sh` | build-script | batch (CLI tool invocation) | `BBTB/scripts/validate-r1-r6.sh` (set -uo pipefail + check function) | role-match |

### MODIFIED FILES (11)

| File | Modification | Role | Closest Analog Pattern |
|------|--------------|------|-------------------------|
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` | extend `expandConfigForTunnel` → inject `route.rule_set` + 3 priority rules | utility (transform) | self (`expandConfigForTunnel` Phase 1 W3.2 sniff insertion @ line 228-237) — extend that same fall-through chain |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json` | (no inline edit — must stay R1-clean per validate-r1-r6.sh) | resource | template stays bare; `expandConfigForTunnel` is single injection point |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` | add `rulesCacheDirectory` computed URL | utility (path resolver) | self (`crashReportsURL` @ line 32-36) |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` | add 3 new Sections: `MinAppVersionBanner` (conditional) + Rules viewer + Force-update | view | self (Phase 6 Form Section pattern @ line 21-32) |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` | add `@Published rulesSnapshot/version/lastFetchedAt`, `forceUpdateButtonState`, `forceUpdateStatusOutcome`, `showMinAppVersionBanner` + bind to RulesEngineCoordinator | view-model | self (`applyAutoReconnectToManager` Phase 6c late-bind pattern @ line 181) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | add `@Published showMinAppVersionSheet`, `handleMinAppVersionCheck()`, observer for `bbtbRulesEngineDidUpdate` | view-model | self (`nevpnStatusObserver` queue=nil pattern @ line 205) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` | add `.sheet(isPresented: $vm.showMinAppVersionSheet)` modifier | view | self (existing `.sheet(isPresented: $viewModel.isPresentingServerList)` @ line 77) |
| `BBTB/Packages/AppFeatures/Package.swift` | add `RulesEngine` package dep + product wiring | manifest | self (existing local `.package(path: "../VPNCore")` pattern @ line 14-24) |
| `BBTB/App/iOSApp/BBTB_iOSApp.swift` | register `BGAppRefreshTask` + construct `RulesEngineCoordinator` + inject into `SettingsViewModel` | host bootstrap | self (Phase 6d Wave 03f ordered launch Task chain @ line 133-146) |
| `BBTB/App/macOSApp/BBTB_macOSApp.swift` | register `NSBackgroundActivityScheduler` + same coordinator | host bootstrap | self (Phase 6d mirror @ line 83+) |
| `BBTB/App/iOSApp/Info.plist` | add `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes` (fetch) | infrastructure | (none in repo; Apple-canonical addition) |
| `BBTB/Project.swift` | **DELETE** `BBTB-AppProxy-macOS` target block (lines 207-220) + dependency reference (line 142) | manifest | self (existing Phase 2 W4.T6 target add pattern; reverse direction) |
| `BBTB/scripts/validate-r1-r6.sh` | extend with 4 Phase 8 grep checks (template bare, AppGroup path usage, 32-byte pubkey, no NEAppProxyProvider) | invariant script | self (existing `check ...` pattern @ line 16-24, 31-69) |
| `BBTB/App/macOSApp/BBTB-macOS.entitlements` | remove `app-proxy-provider` value from NE array | entitlement | (Phase 1 entitlement audit pattern) |

### DELETED FILES (3)

| File | Reason |
|------|--------|
| `BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift` | D-09 — RULES-11 carve-out |
| `BBTB/App/AppProxyExtension-macOS/Info.plist` | same |
| `BBTB/App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements` | same |

---

## Pattern Assignments

### 1. `BBTB/Packages/RulesEngine/Package.swift` (package-manifest)

**Analog:** `BBTB/Packages/ConfigParser/Package.swift` (lines 1-54)

**Manifest skeleton pattern** (Package.swift lines 1-25):
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ConfigParser",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ConfigParser", targets: ["ConfigParser"])],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        // ...
    ],
    targets: [
        .target(name: "ConfigParser", dependencies: ["VPNCore", ...]),
        .testTarget(name: "ConfigParserTests", dependencies: ["ConfigParser", ...], resources: [.process("Fixtures")]),
    ]
)
```

**Apply to RulesEngine:** swap `Yams` external dep → `swift-crypto` 4.0.0..<5.0.0; add `.product(name: "Crypto", package: "swift-crypto")` in target deps; resources `[.process("Resources")]` for baseline SRS files and manifest JSON.

**Rationale:** ConfigParser — ровно same platform set (iOS 18 / macOS 15), same Swift 6 toolchain, и единственный пакет где уже подключён внешний Git-dependency (Yams) — паттерн копируется напрямую.

---

### 2. `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift` (service, request-response)

**Analog:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` (lines 80-107, 187-249)

**HTTPS guard + SSRF blocklist** (SubscriptionURLFetcher.swift lines 80-107):
```swift
public static func fetch(url: URL, session: URLSession = .shared) async throws -> SubscriptionFetchResult {
    guard url.scheme?.lowercased() == "https" else {
        throw FetchError.nonHTTPS(url.scheme ?? "")
    }
    guard let rawHost = url.host, !rawHost.isEmpty else {
        throw FetchError.malformedURL
    }
    if isBlockedHost(rawHost) {
        throw FetchError.blockedHost(normalizeHostForLog(rawHost))
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
    request.setValue("text/plain, application/json, */*", forHTTPHeaderField: "Accept")
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await session.data(for: request)
    guard let httpResp = response as? HTTPURLResponse else { throw FetchError.notHTTPResponse }
    guard (200..<300).contains(httpResp.statusCode) else { throw FetchError.httpStatusError(httpResp.statusCode) }
    // ...
}
```

**Error enum pattern** (lines 54-74) — copy `FetchError.nonHTTPS/notHTTPResponse/httpStatusError/malformedURL/timeout/blockedHost`; add `RulesFetcher.FetchError` cases для signature/size budget violations.

**Apply to RulesFetcher:** заменить `SubscriptionFetchResult` на простой `(body: Data, etag: String?)`; User-Agent = `"BBTB-Rules/0.8 (iOS / macOS)"`; reuse `SubscriptionURLFetcher.isBlockedHost(_:)` (W0 task: повысить с `internal` на `public` либо extract в shared utility).

**Mirror failover pattern (new — но bounded concurrency=1 per DEC-06d-04):**
```swift
public static func fetchWithFailover(urls: [URL]) async throws -> FetchResult {
    var lastError: Error?
    for url in urls {
        do { return try await fetch(url: url) }
        catch { lastError = error; continue }
    }
    throw lastError ?? FetchError.allMirrorsFailed
}
```
**Rationale:** sequential (concurrency=1) — DEC-06d-04 bounded concurrency principle (см. wiki/performance-baseline.md).

---

### 3. `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift` (utility, transform)

**Analog:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` (lines 50-131 — `public enum` static helper pattern)

**Enum-namespace + static func pattern** (SingBoxConfigLoader.swift lines 50-75):
```swift
public enum SingBoxConfigLoader {
    private static let allowedInboundTypes: Set<String> = ["tun", "direct"]
    private static let proxyOutboundTypes: Set<String> = [
        "vless", "trojan", "urltest", "selector", ...
    ]
    public static func validate(json: String) throws {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SingBoxConfigError.malformedJSON }
        // ...
    }
}
```

**Apply to RulesSigner** (per RESEARCH.md §Code Examples lines 254-275):
```swift
import Crypto

public enum RulesSigner {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidPublicKey
        case signatureMismatch
        case invalidSignatureLength
    }
    static func verify(message: Data, signature: Data) -> Bool {
        return PublicKey.publicKey.isValidSignature(signature, for: message)
    }
}
```

**Rationale:** Same `public enum` namespace pattern, same `LocalizedError` Equatable error enum. Single static API. No state.

---

### 4. `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` (config-constant)

**Analog:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` (lines 5-18 — `public enum` + `public static let identifier`)

**Constant-as-enum pattern** (AppGroupContainer.swift lines 5-18):
```swift
public enum AppGroupContainer {
    public static let identifier = "group.app.bbtb.shared"
    public static var url: URL {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else {
            fatalError("App Group \(identifier) not configured in entitlements")
        }
        return url
    }
}
```

**Apply to PublicKey.swift:**
```swift
import Crypto

enum PublicKey {
    /// Generated server-side, never rotated in v0.8 (см. Pitfall 5 в 08-RESEARCH.md).
    /// Хранится здесь как 32-byte Swift literal — публичный по design, не secret.
    private static let publicKeyBytes: [UInt8] = [
        0x00, 0x01, 0x02, /* ... 32 bytes total — populated by W1 task ... */ 0x1F
    ]

    static let publicKey: Curve25519.Signing.PublicKey = {
        // try! is justified — constant bytes baked at compile time; failure = build bug.
        try! Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKeyBytes))
    }()
}
```

**R8 invariant** (validate-r1-r6.sh check #3 — Phase 8 extension): grep must find exactly 32 `0x..` hex literals in this file.

---

### 5. `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesManifest.swift` (model, Codable)

**Analog:** `BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift` (Codable struct pattern)

**Decodable struct pattern (similar):**
```swift
public struct RulesManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let minAppVersion: String
    public let srsFormatVersion: Int  // Pitfall 1 guard
    public let totalSizeBytes: Int    // Pitfall 3 guard
    public let files: [FileEntry]
    public let signatureBase64: String  // detached sig of this struct's canonical JSON; verified separately

    public struct FileEntry: Codable, Sendable, Equatable {
        public let name: String
        public let sha256: String
        public let sigPath: String
        public let category: Category  // "block" | "never" | "always"
    }

    public enum Category: String, Codable, Sendable {
        case block = "block_completely"
        case never = "never_through_vpn"
        case always = "always_through_vpn"
    }
}
```

---

### 6. `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSnapshot.swift` (model, value-type)

**Analog:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` lines 49-61 — `SupportedServerSnapshot`

**Sendable value-type snapshot pattern** (MainScreenViewModel.swift lines 49-61):
```swift
public struct SupportedServerSnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let lastLatencyMs: Int?
    public let failedProbeCount: Int
    public init(id: UUID, name: String, lastLatencyMs: Int?, failedProbeCount: Int) {
        self.id = id; self.name = name
        self.lastLatencyMs = lastLatencyMs
        self.failedProbeCount = failedProbeCount
    }
}
```

**Apply to RulesSnapshot:**
```swift
public struct RulesSnapshot: Sendable, Equatable {
    public let version: Int
    public let lastFetchedAt: Date?
    public let block: CategoryEntries
    public let never: CategoryEntries
    public let always: CategoryEntries
}
public struct CategoryEntries: Sendable, Equatable {
    public let domains: [String]
    public let ipCidrs: [String]
    public let countries: [String]
}
```

**Rationale:** UI-SPEC §Component Inventory табл. specифицирует именно эти поля. SwiftData/actor-safe Sendable per Phase 6d patterns.

---

### 7. `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift` (store, file-I/O)

**Analog A:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` (path resolver pattern)
**Analog B:** Phase 6 `ExternalVPNStopMarker.swift` (App Group sticky marker write/read — RESEARCH-cited)

**Subdirectory-under-App-Group pattern** (AppGroupContainer.swift lines 32-36):
```swift
public static var crashReportsURL: URL {
    let dir = url.appendingPathComponent("crash-reports", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

**Apply: add `rulesCacheDirectory` in AppGroupContainer.swift (MODIFY)** + new `SRSCacheStore` actor uses it:
```swift
// AppGroupContainer.swift — ADD:
public static var rulesCacheDirectory: URL {
    let dir = url.appendingPathComponent("Library/Caches/rules", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

**Atomic write pattern (RESEARCH §Pattern 5 — Approach A):**
```swift
public actor SRSCacheStore {
    private let directory: URL = AppGroupContainer.rulesCacheDirectory

    public func write(_ data: Data, filename: String) throws {
        let target = directory.appendingPathComponent(filename)
        try data.write(to: target, options: .atomic)  // POSIX rename(2) under the hood
    }

    public func read(filename: String) -> Data? {
        let target = directory.appendingPathComponent(filename)
        return try? Data(contentsOf: target)
    }
}
```

**Rationale:** Same `Library/Caches/...` subdir convention. `.atomic` = тmp+rename, same-volume guaranteed (App Group container). Phase 6 уже doctrine'ит этот approach (см. ExternalVPNStopMarker.swift).

---

### 8. `BBTB/Packages/RulesEngine/Sources/RulesEngine/BaselineRulesLoader.swift` (utility, bundle Resources)

**Analog:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` lines 247-256

**Bundle.module resource load pattern** (SingBoxConfigLoader.swift lines 246-256):
```swift
public static func loadVLESSRealityTemplate() throws -> String {
    guard let url = Bundle.module.url(
        forResource: "SingBoxConfigTemplate.vless-reality",
        withExtension: "json"
    ) else {
        throw SingBoxConfigError.malformedJSON
    }
    return try String(contentsOf: url, encoding: .utf8)
}
```

**Apply to BaselineRulesLoader:**
```swift
public enum BaselineRulesLoader {
    public enum Error: Swift.Error { case resourceMissing(String) }

    /// Read raw bytes of baseline .srs (e.g. "bbtb-baseline-block.srs") from package resources.
    public static func loadSRS(category: RulesManifest.Category) throws -> Data {
        let basename: String
        switch category {
        case .block: basename = "bbtb-baseline-block"
        case .never: basename = "bbtb-baseline-never"
        case .always: basename = "bbtb-baseline-always"
        }
        guard let url = Bundle.module.url(forResource: basename, withExtension: "srs") else {
            throw Error.resourceMissing("\(basename).srs")
        }
        return try Data(contentsOf: url)
    }

    public static func loadManifest() throws -> (manifest: Data, signature: Data) { /* same pattern */ }
}
```

**Rationale:** Same `Bundle.module` Swift Package idiom, same error-on-missing-resource. Phase 8 W6 add baseline files to `Package.swift` `resources: [.process("Resources")]`.

---

### 9. `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift` (coordinator, actor)

**Analog A:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` (actor coordinator pattern — Phase 6c)
**Analog B:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift` + Phase 6 two-phase init (per memory `feedback_failover_two_phase_init.md`)
**Analog C:** `BBTB/App/iOSApp/BBTB_iOSApp.swift` lines 88-103 — `SwiftDataFailoverProvider` weak-capture pattern

**Two-phase init pattern (BBTB_iOSApp.swift lines 92-103):**
```swift
let tunnel = TunnelController()
let failoverProvider = SwiftDataFailoverProvider(
    modelContainer: modelContainer,
    provisioner: importer,
    connect: { [weak tunnel] in
        guard let tunnel else { throw CancellationError() }
        return try await tunnel.connect()
    },
    currentServerID: {
        userDefaults.string(forKey: "app.bbtb.selectedServerID").flatMap(UUID.init(uuidString:))
    }
)
// Later: await tunnel.setFailoverProvider(failoverProvider)  // late-bind setter
```

**Apply to RulesEngineCoordinator** (per memory `feedback_failover_two_phase_init.md`):
```swift
public actor RulesEngineCoordinator {
    private let fetcher: RulesFetching
    private let cache: SRSCacheStore
    private let baseline: BaselineRulesLoader.Type
    private weak var settingsVM: SettingsViewModel?  // late-bound to avoid retain cycle

    public init(fetcher: RulesFetching = DefaultRulesFetcher(), cache: SRSCacheStore = SRSCacheStore()) {
        self.fetcher = fetcher
        self.cache = cache
        self.baseline = BaselineRulesLoader.self
    }

    /// Two-phase: SettingsViewModel создаётся отдельно, late-bind через setter.
    public func setSettingsViewModel(_ vm: SettingsViewModel) { self.settingsVM = vm }

    /// W0 boot: copy baseline to cache if missing (D-05).
    public func bootstrap() async { /* ... */ }

    /// Triggered by BGAppRefreshTask / NSBackgroundActivityScheduler / force-update tap.
    public func performBackgroundRefresh() async -> Bool { /* fetch → verify → write → notify */ }

    public func forceUpdate() async -> ForceUpdateOutcome { /* with cooldown */ }
}
```

**OSLog subsystem pattern** (TunnelController.swift): `Logger(subsystem: "app.bbtb.client", category: "rules-engine")`.

**NotificationCenter pattern** (per MainScreenViewModel.swift line 205 — `queue: nil` + Task @MainActor hop): post `Notification.Name.bbtbRulesEngineDidUpdate` after successful write.

---

### 10. `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift` (utility, OSLog)

**Analog:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift` + `Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift` (lines 22-49 — subsystem/category enum)

**Subsystem/category enum pattern** (PerfSignposter.swift lines 22-49):
```swift
public enum PerfSignposter {
    public static let app = OSSignposter(subsystem: "app.bbtb.client.ios", category: "performance")
    public static let client = OSSignposter(subsystem: "app.bbtb.client", category: "performance")
    public static let tunnel = OSSignposter(subsystem: "app.bbtb.tunnel", category: "performance")
}
```

**Apply to RulesEngineLogger:**
```swift
import OSLog
enum RulesEngineLogger {
    static let coordinator = Logger(subsystem: "app.bbtb.client", category: "rules-engine.coordinator")
    static let fetcher = Logger(subsystem: "app.bbtb.client", category: "rules-engine.fetcher")
    static let signer = Logger(subsystem: "app.bbtb.client", category: "rules-engine.signer")
}
```

**PerfSignposter integration (DEC-06d-06):**
```swift
let id = PerfSignposter.client.makeSignpostID()
let state = PerfSignposter.client.beginInterval("RulesRefresh", id: id)
// ... fetch + verify + write ...
PerfSignposter.client.endInterval("RulesRefresh", state)
```

---

### 11. `BBTB/Packages/RulesEngine/Resources/baseline-rules-manifest.json` (resource)

**Analog:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json` (lines 1-77 — JSON resource в Swift Package)

**JSON resource location pattern:** lives in `Sources/RulesEngine/Resources/`, declared в Package.swift's target via `resources: [.process("Resources")]`. Accessed runtime через `Bundle.module.url(forResource:withExtension:)`.

**Content structure** (per v2 prompt §rules_engine + 08-CONTEXT D-05/D-07):
```json
{
  "version": 0,
  "min_app_version": "0.8.0",
  "srs_format_version": 4,
  "total_size_bytes": 0,
  "files": [
    {"name": "bbtb-baseline-block.srs",  "category": "block_completely",   "sha256": "..."},
    {"name": "bbtb-baseline-never.srs",  "category": "never_through_vpn",  "sha256": "..."},
    {"name": "bbtb-baseline-always.srs", "category": "always_through_vpn", "sha256": "..."}
  ],
  "block_completely":   { "domains": ["max.ru", "mssgr.tatar.ru"], "ip_cidrs": [], "countries": [] },
  "never_through_vpn":  { "domains": [], "ip_cidrs": [], "countries": [] },
  "always_through_vpn": { "domains": [], "ip_cidrs": [], "countries": [] }
}
```

---

### 12. `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift` (component, SwiftUI Section)

**Analog A:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdBlockToggleSection.swift` (lines 1-20 — public Section component pattern)
**Analog B:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift` (lines 31-50 — section header with timestamp + uppercase caption)

**Public View component pattern** (AdBlockToggleSection.swift lines 6-20):
```swift
public struct AdBlockToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String
    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn; self.footerText = footerText
    }
    public var body: some View {
        Toggle(L10n.settingsDnsAdblockLabel, isOn: $isOn)
            .accessibilityHint(Text(footerText))
    }
}
```

**Header-with-timestamp pattern** (SubscriptionHeader.swift lines 31-50):
```swift
public var body: some View {
    HStack(spacing: DS.Spacing.sm) {
        Text(subscription.name)
            .font(DS.Typography.caption)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
        Spacer()
        if let fetched = subscription.lastFetched {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
                Text(RelativeDateTimeFormatter().localizedString(for: fetched, relativeTo: .now))
                    .font(DS.Typography.caption)
            }
        }
    }
}
```

**Apply to RulesViewerSection** (pure data view per UI-SPEC §Component Inventory):
```swift
public struct RulesViewerSection: View {
    public let snapshot: RulesSnapshot?
    public init(snapshot: RulesSnapshot?) { self.snapshot = snapshot }

    public var body: some View {
        Group {
            if let snapshot {
                // 3 category Sections + DisclosureGroups
                RuleCategoryGroup(category: .block,  entries: snapshot.block)
                RuleCategoryGroup(category: .never,  entries: snapshot.never)
                RuleCategoryGroup(category: .always, entries: snapshot.always)
            } else {
                emptyCard
            }
        }
    }
}
```

**`textSelection(.enabled)` invariant per UI-SPEC A-07** — все domain/IP/country entries должны быть `.textSelection(.enabled)` для copy support tickets.

---

### 13. `BBTB/Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift` (component, state machine)

**Analog A:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` (state-machine button)
**Analog B:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift` (Settings-section component)
**Analog C:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift` (Timer.publish + monospacedDigit pattern — Phase 2)

**Component pattern + state-machine driver (per UI-SPEC §Interaction Patterns §3):**
```swift
public enum ForceUpdateButtonState: Equatable, Sendable {
    case idle
    case inProgress
    case cooldown(secondsRemaining: Int)
}

public enum ForceUpdateOutcome: Equatable, Sendable {
    case success(version: Int)
    case alreadyLatest(version: Int)
    case networkFailure
    case signatureFailure
}

public struct ForceUpdateRulesButton: View {
    public let buttonState: ForceUpdateButtonState
    public let statusOutcome: ForceUpdateOutcome?
    public let onTap: () -> Void

    public init(buttonState: ForceUpdateButtonState, statusOutcome: ForceUpdateOutcome?, onTap: @escaping () -> Void) {
        self.buttonState = buttonState
        self.statusOutcome = statusOutcome
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 8) {
            Button(action: onTap) {
                if buttonState == .inProgress {
                    HStack { ProgressView(); Text(L10n.rulesForceUpdateInProgress) }
                } else {
                    Text(buttonLabel).font(DS.Typography.subheadline)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(buttonState != .idle)
            .frame(maxWidth: .infinity)

            if let outcome = statusOutcome {
                statusRow(outcome)
                    .transition(.opacity)
            }
        }
    }
}
```

**Haptic + cooldown tick** (UI-SPEC A-11, A-13) — VM owns `cooldownExpiresAt: Date` + `Timer.publish(every: 1.0)` (background-foreground safe via wallclock comparison per UI-SPEC §3 trigger table).

---

### 14. `BBTB/Packages/AppFeatures/Sources/SettingsFeature/MinAppVersionBanner.swift` (component, banner)

**Analog:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift` (lines 1-53 — exact same orange-tint banner pattern)

**Full ReconnectBanner pattern** (ReconnectBanner.swift lines 13-53):
```swift
public struct ReconnectBanner: View {
    public let message: String
    public let onDismiss: (() -> Void)?
    public init(message: String = L10n.bannerReconnectNeeded,
                onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(message).font(DS.Typography.subheadline)
            Spacer()
            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.caption.bold())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.bannerDismiss))
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .fill(Color.orange.opacity(0.15))
        )
        .foregroundColor(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(message))
    }
}
```

**Apply to MinAppVersionBanner:** structurally identical — заменить icon на `arrow.up.circle.fill`, заменить message на `L10n.minAppVersionBannerText`, `onTap` вместо `onDismiss` (per UI-SPEC §A-20). Cornering + orange.opacity(0.15) сохранить идентично.

---

### 15. `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MinAppVersionSheet.swift` (component, modal)

**Analog:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/EmptyStateCard.swift` (lines 6-49 — icon + title + 2 buttons)

**Full EmptyStateCard pattern** (EmptyStateCard.swift lines 15-49):
```swift
public var body: some View {
    VStack(spacing: DS.Spacing.lg) {
        Image(systemName: "tray")
            .font(.system(size: 56))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

        Text(L10n.emptyTitle).font(DS.Typography.title)

        Text(L10n.emptySubtitle)
            .font(DS.Typography.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        VStack(spacing: DS.Spacing.md) {
            Button(L10n.actionImportFromClipboard, action: onAddFromClipboard)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button(L10n.actionScanQR, action: onScanQR)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
    .padding(DS.Spacing.xl)
    .background(
        RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
            .fill(Color.secondary.opacity(0.1))
    )
    .frame(maxWidth: 360)
}
```

**Apply to MinAppVersionSheet** (per UI-SPEC §Layout Specifications):
```swift
public struct MinAppVersionSheet: View {
    public let currentVersion: String
    public let onOpenTestFlight: () -> Void
    public let onDismiss: () -> Void

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.up.app.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)

            Text(L10n.minAppVersionSheetTitle)
                .font(DS.Typography.title)
                .multilineTextAlignment(.center)

            Text(L10n.minAppVersionSheetBody(currentVersion))
                .font(DS.Typography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(L10n.minAppVersionSheetPrimary, action: onOpenTestFlight)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                    .frame(maxWidth: .infinity)
                Button(L10n.minAppVersionSheetSecondary, action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        #if os(macOS)
        .frame(width: 440, height: 320)
        #endif
    }
}
```

**Presentation modifier (on parent MainScreenView):** `.sheet(isPresented: $vm.showMinAppVersionSheet) { ... }` + `.presentationDetents([.medium])` + `.presentationDragIndicator(.visible)` per UI-SPEC §4.

---

### 16. `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` (MODIFY)

**Self-analog:** lines 136-243 — existing `expandConfigForTunnel(_:)` chain (TUN inbound → DNS-hijack migration → sniff insertion). Phase 8 extends this same idempotent chain.

**Idempotent injection pattern** (SingBoxConfigLoader.swift lines 172-185 — TUN inbound):
```swift
var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
let hasTun = inbounds.contains { ($0["type"] as? String) == "tun" }
if !hasTun {
    inbounds.append([
        "type": "tun",
        "tag": "tun-in",
        // ...
    ])
    root["inbounds"] = inbounds
}
```

**Sniff insertion pattern** (lines 228-237):
```swift
if var route = root["route"] as? [String: Any] {
    var rules = (route["rules"] as? [[String: Any]]) ?? []
    let hasSniff = rules.contains { ($0["action"] as? String) == "sniff" }
    if !hasSniff {
        rules.insert(["action": "sniff"], at: 0)
        route["rules"] = rules
        root["route"] = route
    }
}
```

**Apply Phase 8 extension (insert AFTER sniff step ~line 237, BEFORE final serialization line 239):**
```swift
// 5. Phase 8 D-01 — inject 3 route.rule_set entries + 3 priority rules.
// Idempotent: проверяет наличие tag-ов прежде чем добавлять.
if var route = root["route"] as? [String: Any] {
    var ruleSets = (route["rule_set"] as? [[String: Any]]) ?? []
    let existingTags: Set<String> = Set(ruleSets.compactMap { $0["tag"] as? String })
    let rulesDir = AppGroupContainer.rulesCacheDirectory.path
    let categories: [(tag: String, file: String)] = [
        ("bbtb-block",  "bbtb-block.srs"),
        ("bbtb-never",  "bbtb-never.srs"),
        ("bbtb-always", "bbtb-always.srs"),
    ]
    for (tag, file) in categories where !existingTags.contains(tag) {
        ruleSets.append([
            "tag": tag,
            "type": "local",
            "format": "binary",
            "path": "\(rulesDir)/\(file)"
        ])
    }
    route["rule_set"] = ruleSets

    // Priority rules — insert AFTER existing sniff + hijack-dns, BEFORE everything else.
    var rules = (route["rules"] as? [[String: Any]]) ?? []
    let existingRuleSetRefs: Set<String> = Set(rules.compactMap { $0["rule_set"] as? String })
    // Determine first proxy outbound for "always" — reuse existing logic at line 219-223.
    let outbounds = (root["outbounds"] as? [[String: Any]]) ?? []
    let firstProxyTag = outbounds.first { o in
        guard let t = o["type"] as? String else { return false }
        return proxyOutboundTypes.contains(t)
    }?["tag"] as? String ?? "vless-out"
    // Find insertion index — after sniff + hijack-dns (typically index 2).
    let insertIdx = rules.firstIndex { ($0["action"] as? String) == "hijack-dns" }.map { $0 + 1 } ?? 0
    var newRules: [[String: Any]] = []
    if !existingRuleSetRefs.contains("bbtb-block")  { newRules.append(["rule_set": "bbtb-block",  "action": "reject"]) }
    if !existingRuleSetRefs.contains("bbtb-never")  { newRules.append(["rule_set": "bbtb-never",  "outbound": "direct"]) }
    if !existingRuleSetRefs.contains("bbtb-always") { newRules.append(["rule_set": "bbtb-always", "outbound": firstProxyTag]) }
    rules.insert(contentsOf: newRules, at: insertIdx)
    route["rules"] = rules
    root["route"] = route
}
```

**R1/R10 invariant preservation:** post-expand `validate(json:)` (called from BaseSingBoxTunnel.startTunnel after expand per line 42-43 of SingBoxConfigLoader doc-comment) уже не пропускает forbidden inbounds. `action: "reject"` это **action**, не inbound — pass. AppGroupContainer path — extension-side resolvable.

---

### 17. `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` (MODIFY)

**Self-analog:** lines 32-36 (`crashReportsURL` subdirectory pattern).

**Apply addition:**
```swift
/// Phase 8 / RULES-01..07 — directory для signed SRS rule_set cache.
/// Used by RulesEngine.SRSCacheStore (writer = main app) and
/// SingBoxConfigLoader.expandConfigForTunnel (reader = extension).
public static var rulesCacheDirectory: URL {
    let dir = url.appendingPathComponent("Library/Caches/rules", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

**Same pattern as crashReportsURL** — public, idempotent createDirectory.

---

### 18. `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` (MODIFY)

**Self-analog:** lines 19-37 — existing Form + Section pattern (DNS section).

**Existing Form pattern** (AdvancedSettingsView.swift lines 19-37):
```swift
public var body: some View {
    Form {
        Section {
            AdBlockToggleSection(
                isOn: $viewModel.adBlockEnabled,
                footerText: L10n.settingsDnsAdblockFooter
            )
            CustomDNSField(text: $viewModel.customDNS)
        } header: {
            Text(L10n.settingsDnsSection)
        } footer: {
            Text(L10n.settingsDnsCustomFooter)
        }
    }
    .navigationTitle(L10n.settingsAdvancedTitle)
}
```

**Apply Phase 8 extension** (per UI-SPEC §Layout Specifications):
```swift
public var body: some View {
    Form {
        // 1. min_app_version banner (conditional — UI-SPEC §A-20)
        if viewModel.showMinAppVersionBanner {
            Section {
                MinAppVersionBanner(currentVersion: viewModel.currentAppVersion,
                                    onTap: viewModel.openTestFlight)
            }
            .listRowBackground(Color.orange.opacity(0.15))
        }

        // 2. Existing DNS section (unchanged)
        Section {
            AdBlockToggleSection(...)
            CustomDNSField(text: $viewModel.customDNS)
        } header: { Text(L10n.settingsDnsSection) } footer: { Text(L10n.settingsDnsCustomFooter) }

        // 3. Phase 8 — Rules viewer (RULES-09)
        Section {
            RulesViewerSection(snapshot: viewModel.rulesSnapshot)
        } header: {
            Text(viewModel.rulesHeaderText)
                .textCase(.uppercase)
        }

        // 4. Phase 8 — Force-update button (RULES-10)
        Section {
            ForceUpdateRulesButton(
                buttonState: viewModel.forceUpdateButtonState,
                statusOutcome: viewModel.forceUpdateStatusOutcome,
                onTap: { Task { await viewModel.triggerForceUpdate() } }
            )
        } header: {
            Text(L10n.rulesForceUpdateSection).textCase(.uppercase)
        } footer: {
            Text(L10n.rulesForceUpdateFooter)
        }
    }
    .navigationTitle(L10n.settingsAdvancedTitle)
}
```

---

### 19. `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` (MODIFY)

**Self-analog A:** lines 14-43 — `@AppStorage` + `@MainActor` ObservableObject pattern
**Self-analog B:** lines 181-214 — `applyAutoReconnectToManager()` Phase 6c live-apply pattern (nonisolated async + Logger + NotificationCenter.post)

**`@AppStorage` extension pattern** (SettingsViewModel.swift lines 16-43):
```swift
@AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false
@AppStorage("app.bbtb.customDNS") public var customDNS: String = ""
@AppStorage("app.bbtb.adBlockEnabled") public var adBlockEnabled: Bool = false
@AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true
```

**Apply Phase 8 additions:**
```swift
// MARK: - Phase 8 — Rules Engine state (bound from RulesEngineCoordinator)
@Published public private(set) var rulesSnapshot: RulesSnapshot?
@Published public private(set) var rulesVersion: Int = 0
@Published public private(set) var rulesLastFetchedAt: Date?
@Published public private(set) var forceUpdateButtonState: ForceUpdateButtonState = .idle
@Published public private(set) var forceUpdateStatusOutcome: ForceUpdateOutcome?
@Published public private(set) var showMinAppVersionBanner: Bool = false

/// D-10 cooldown bookkeeping (UI-SPEC §3 trigger table)
private var cooldownExpiresAt: Date?
private var cooldownTimer: Timer?

/// **Phase 8 / D-11 dismissed flag** — per-version persistent storage.
@AppStorage("app.bbtb.minAppVersion.dismissed") private var dismissedMinAppVersion: String = ""

/// Late-bound coordinator (two-phase init per `feedback_failover_two_phase_init.md`).
public weak var rulesEngineCoordinator: RulesEngineCoordinator?

/// Trigger force-update tap; respects cooldown gate.
public func triggerForceUpdate() async {
    guard forceUpdateButtonState == .idle else { return }  // race guard (UI-SPEC Edge Cases)
    #if os(iOS)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
    forceUpdateButtonState = .inProgress
    let outcome = await rulesEngineCoordinator?.forceUpdate() ?? .networkFailure
    await applyForceUpdateOutcome(outcome)
}
```

**Bind-from-coordinator pattern** (mirror Phase 6c late-bind in SwiftDataFailoverProvider).

---

### 20. `BBTB/App/iOSApp/BBTB_iOSApp.swift` (MODIFY) — `BGAppRefreshTask` registration

**Self-analog:** lines 27-162 — `init()` bootstrap + Phase 6d Wave 03f ordered launch Task chain.

**Existing ordered Task chain** (BBTB_iOSApp.swift lines 133-146):
```swift
Task { [vm] in
    await OnDemandMigrationTask.runIfNeeded()
    let watchdog = TunnelWatchdog(failoverProvider: failoverProvider)
    await watchdog.setFailoverObserver { [weak vm] serverName in
        await MainActor.run { [weak vm] in
            vm?.showFailoverBanner(toServerName: serverName)
        }
    }
    let snapshot = await tunnel.bootstrap(failoverProvider: failoverProvider, watchdog: watchdog)
    await MainActor.run { [weak vm] in
        vm?.applyInitialStatusSnapshot(snapshot)
    }
}
```

**Apply Phase 8 extension (per RESEARCH §Pattern 3, in same `init()`):**
```swift
// Phase 8 / RULES-04 — register BGAppRefreshTask BEFORE first scene render.
// Apple requires registration during app launch BEFORE app finishes launching.
let rulesCoordinator = RulesEngineCoordinator()
// Bind to SettingsVM later (in BBTBRootView via late-bind setter — Phase 8 W3 wiring).
Task { await rulesCoordinator.bootstrap() }  // copy baseline → cache if first launch

BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "app.bbtb.client.ios.rules-refresh",
    using: nil
) { task in
    guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false); return
    }
    refresh.expirationHandler = { /* cancellation hook */ }
    Task {
        let success = await rulesCoordinator.performBackgroundRefresh()
        // Schedule next regardless of outcome
        let request = BGAppRefreshTaskRequest(identifier: "app.bbtb.client.ios.rules-refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
        refresh.setTaskCompleted(success: success)
    }
}
```

---

### 21. `BBTB/App/macOSApp/BBTB_macOSApp.swift` (MODIFY) — `NSBackgroundActivityScheduler`

**Self-analog:** BBTB_macOSApp.swift lines 27-end — `init()` mirror of iOS pattern.

**Apply (per RESEARCH §Pattern 4):**
```swift
let rulesScheduler: NSBackgroundActivityScheduler = {
    let s = NSBackgroundActivityScheduler(identifier: "app.bbtb.client.macos.rules-refresh")
    s.repeats = true
    s.interval = 6 * 3600
    s.tolerance = 10 * 60
    s.qualityOfService = .utility
    return s
}()
rulesScheduler.schedule { [weak rulesCoordinator = self.rulesCoordinator] completion in
    Task {
        _ = await rulesCoordinator?.performBackgroundRefresh()
        completion(.finished)
    }
}
```

---

### 22. `BBTB/App/iOSApp/Info.plist` (MODIFY)

**Self-analog:** lines 23-26 (`UILaunchScreen`, `LSRequiresIPhoneOS` pattern — well-formed plist).

**Apply additions** (per RESEARCH §Pattern 3 Info.plist requirements):
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>app.bbtb.client.ios.rules-refresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

---

### 23. `BBTB/Project.swift` (MODIFY — D-09 deletion)

**Self-analog:** lines 153-204 — existing `BBTB-Tunnel-iOS` and `BBTB-Tunnel-macOS` target definitions (kept).

**Existing target block to DELETE** (Project.swift lines 206-220):
```swift
// MARK: macOS AppProxy Extension (placeholder под Phase 8)

.target(
    name: "BBTB-AppProxy-macOS",
    destinations: [.mac],
    product: .appExtension,
    bundleId: "\(bundlePrefix).macos.appproxy",
    deploymentTargets: .macOS("15.0"),
    infoPlist: .file(path: "App/AppProxyExtension-macOS/Info.plist"),
    sources: ["App/AppProxyExtension-macOS/**/*.swift"],
    entitlements: .file(path: "App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements"),
    dependencies: [
        .package(product: "VPNCore"),
    ]
),
```

**Also DELETE** line 142 (in `BBTB-macOS` target dependencies):
```swift
.target(name: "BBTB-AppProxy-macOS"),
```

**Apply:** удалить блок + dependency reference + физические файлы под `BBTB/App/AppProxyExtension-macOS/`. Затем `tuist generate` (см. RESEARCH §Runtime State Inventory step 1-7).

---

### 24. `BBTB/scripts/validate-r1-r6.sh` (MODIFY — Phase 8 extensions)

**Self-analog:** validate-r1-r6.sh lines 16-69 — `check` function + bash `grep -q` invariants.

**Existing `check` framework** (validate-r1-r6.sh lines 16-24, 31-69):
```bash
function check() {
    local label="$1"; shift
    if "$@" > /dev/null 2>&1; then
        echo "PASS: $label"
    else
        echo "FAIL: $label  (cmd: $*)"
        FAIL=$((FAIL+1))
    fi
}

# R1: SingBoxConfigTemplate не содержит inbounds
check "R1: template has no 'inbounds' key" \
    bash -c '! grep -q "\"inbounds\"" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json'
```

**Apply Phase 8 invariants** (after existing R1-R6 checks, before unit-test block at line 71):
```bash
# Phase 8 — rule_set integrity

check "R8: vless-reality template has no inline rule_set block" \
    bash -c '! grep -q "rule_set" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json'

check "R8: SingBoxConfigLoader uses AppGroupContainer for rule_set paths" \
    grep -q "AppGroupContainer.rulesCacheDirectory" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift

check "RULES-02: PublicKey.swift has 32-byte pubkey constant" \
    bash -c 'grep -E "publicKeyBytes:\s*\[UInt8\]" BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift | grep -oE "0x[0-9a-fA-F]+" | wc -l | xargs test 32 -eq'

check "D-08: No NEAppProxyProvider import in main app sources" \
    bash -c '! grep -rE "NEAppProxyProvider|app-proxy-provider" BBTB/App/macOSApp/ BBTB/Packages/AppFeatures/Sources/'
```

Also add `run_pkg_tests "RulesEngine" "BBTB/Packages/RulesEngine"` to the unit-test loop at line 89-96.

---

### 25. `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesFetcherTests.swift` (test)

**Analog:** `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift` (existing pattern in same package as analog #2)

**Mocking pattern** (referenced in `SubscriptionURLFetcher.swift` line 78 doc comment): `URLSessionConfiguration.ephemeral` with `MockURLProtocol` in `protocolClasses`. Reuse exact mocking framework.

**Apply:**
```swift
import XCTest
@testable import RulesEngine

final class RulesFetcherTests: XCTestCase {
    // Mirror SubscriptionURLFetcherTests test set:
    // - test_acceptsValidHTTPSURL
    // - test_rejectsNonHTTPSScheme
    // - test_rejectsLocalhostHost (SSRF blocklist)
    // - test_failoverFallsBackToSecondMirrorOn500
    // - test_failoverFallsBackToThirdMirrorOnConnectionFailure
    // - test_allMirrorsFailureThrowsFinalError
}
```

---

### 26. `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesSignerTests.swift` (test)

**Analog:** `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` (lines 1-80 — pure-function validate tests)

**XCTest enum-tested pattern** (SingBoxConfigLoaderTests.swift lines 21-50):
```swift
final class SingBoxConfigLoaderTests: XCTestCase {
    func test_acceptsValidVLESSRealityConfig() throws {
        let json = try loadFixture("valid-vless-reality")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }
    func test_rejectsSocksInbound() throws {
        let json = try loadFixture("invalid-socks-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("socks"))
        }
    }
}
```

**Apply:**
```swift
final class RulesSignerTests: XCTestCase {
    func test_verify_acceptsValidSignature() throws {
        let msg = Data("hello".utf8)
        let sig = /* fixture signed with test private key */
        XCTAssertTrue(RulesSigner.verify(message: msg, signature: sig))
    }
    func test_verify_rejectsTamperedSignature() { /* flip 1 bit, assert false */ }
    func test_verify_rejectsWrongLengthSignature() { /* 63-byte sig → false */ }
}
```

---

### 27. `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift` (test, actor integration)

**Analog:** `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/*` — TunnelController DI-based mock tests (existing in SettingsViewModelDNSTests.swift @MainActor pattern).

**Mock-injected actor test pattern (SettingsViewModelDNSTests.swift lines 10-22):**
```swift
@MainActor
final class SettingsViewModelDNSTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "app.bbtb.customDNS")
        // ...
    }
}
```

**Apply:**
```swift
final class RulesEngineCoordinatorTests: XCTestCase {
    func test_bootstrap_copiesBaselineWhenCacheEmpty() async throws { /* ... */ }
    func test_performBackgroundRefresh_keepsCacheOnSignatureFailure() async throws { /* RULES-03 */ }
    func test_performBackgroundRefresh_keepsCacheOnNetworkFailure() async throws { /* RULES-03 */ }
    func test_forceUpdate_postsNotificationOnSuccess() async throws { /* RULES-10 */ }
}
```

---

### 28. `BBTB/scripts/build-baseline-rules.sh` (NEW)

**Analog:** `BBTB/scripts/validate-r1-r6.sh` lines 1-15 (`set -uo pipefail` + cd to REPO_ROOT pattern).

**Apply (per RESEARCH §Pattern 6):**
```bash
#!/usr/bin/env bash
# Phase 8 / RULES-05/06 — compile baseline-rules.json into 3 .srs files + sign.
# Invoked manually by developer when baseline-rules.json changes (per Pitfall 6 Option A).
# Output: BBTB/Packages/RulesEngine/Resources/bbtb-baseline-*.srs(+sig)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="${REPO_ROOT}/Packages/RulesEngine/Resources"
BASELINE_JSON="${RESOURCES}/baseline-rules.json"
SIGNING_KEY="${BBTB_BASELINE_SIGNING_KEY:?BBTB_BASELINE_SIGNING_KEY env required}"

for category in block never always; do
    jq ".${category}_completely // .${category}_through_vpn" "$BASELINE_JSON" > "/tmp/${category}.json"
    sing-box rule-set compile --output "/tmp/bbtb-baseline-${category}.srs" "/tmp/${category}.json"
    openssl pkeyutl -sign -rawin -inkey "$SIGNING_KEY" \
        -in "/tmp/bbtb-baseline-${category}.srs" \
        -out "/tmp/bbtb-baseline-${category}.srs.sig"
    cp "/tmp/bbtb-baseline-${category}.srs"     "${RESOURCES}/"
    cp "/tmp/bbtb-baseline-${category}.srs.sig" "${RESOURCES}/"
done
```

---

## Shared Patterns

### S-1: NotificationCenter observer with queue=nil

**Source:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` lines 205-221

**Apply to:** `RulesEngineCoordinator` post-notification; `MainScreenViewModel.handleMinAppVersionCheck()` observer

**Pattern (memory `feedback_nevpn_observer_queue_main.md`):**
```swift
self.observer = NotificationCenter.default.addObserver(
    forName: .bbtbRulesEngineDidUpdate,
    object: nil,
    queue: nil  // critical: NOT .main — main queue suspends during background app state
) { [weak self] notification in
    // Read sync properties from notification.object (NO XPC trips)
    Task { @MainActor [weak self] in
        self?.handleRulesUpdate()  // mutate @Published on MainActor
    }
}
```

---

### S-2: Two-phase init for actor-actor cycles (late-bind setter)

**Source:** memory `feedback_failover_two_phase_init.md` + `BBTB/App/iOSApp/BBTB_iOSApp.swift` lines 88-103 + Phase 6 `SwiftDataFailoverProvider`

**Apply to:** `RulesEngineCoordinator` ↔ `SettingsViewModel` cycle (coordinator needs VM for status outcome publishing; VM needs coordinator for force-update tap).

**Pattern:**
```swift
let coordinator = RulesEngineCoordinator()  // phase 1: stub
let settingsVM = SettingsViewModel()         // phase 1: independent
settingsVM.rulesEngineCoordinator = coordinator  // late-bind weak
await coordinator.setSettingsViewModelSink(settingsVM)  // late-bind weak callback
```

---

### S-3: `public enum X` static-namespace helper (no instance state)

**Source:** `SingBoxConfigLoader` (PacketTunnelKit) + `AppGroupContainer` (PacketTunnelKit) + `PerfSignposter` (AppFeatures)

**Apply to:** `RulesSigner`, `PublicKey`, `BaselineRulesLoader`, `RulesEngineLogger`

**Pattern:**
```swift
public enum X {
    private static let constantField: ... = ...
    public static func operation(...) -> ... { ... }
}
```
**Rationale:** Phase 1-7 throughout — enum-namespace pattern для stateless utilities. Не возможно instantiate, не нужны instance properties, thread-safe by default.

---

### S-4: `Bundle.module` resource access from Swift Package

**Source:** `SingBoxConfigLoader.loadVLESSRealityTemplate()` (lines 246-256) + every L10n.tr call (Localization package)

**Apply to:** `BaselineRulesLoader` (load baseline SRS files and manifest from `Sources/RulesEngine/Resources/`)

**Pattern (SingBoxConfigLoader.swift):**
```swift
public static func loadVLESSRealityTemplate() throws -> String {
    guard let url = Bundle.module.url(
        forResource: "SingBoxConfigTemplate.vless-reality",
        withExtension: "json"
    ) else { throw SingBoxConfigError.malformedJSON }
    return try String(contentsOf: url, encoding: .utf8)
}
```

**Critical:** Package.swift target declaration must specify `resources: [.process("Resources")]`.

---

### S-5: PerfSignposter spans для production code (DEC-06d-06)

**Source:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift` + `BBTB_iOSApp.swift` lines 30-32

**Apply to:** `RulesEngineCoordinator.performBackgroundRefresh()` + `forceUpdate()` + bootstrap

**Pattern (BBTB_iOSApp.swift lines 30-32):**
```swift
let coldID = PerfSignposter.app.makeSignpostID()
self.coldLaunchState = PerfSignposter.app.beginInterval("ColdLaunch", id: coldID)
// ... work ...
PerfSignposter.app.endInterval("ColdLaunch", coldLaunchState)
```

**Apply to RulesRefresh:**
```swift
public func performBackgroundRefresh() async -> Bool {
    let id = PerfSignposter.client.makeSignpostID()
    let state = PerfSignposter.client.beginInterval("RulesRefresh", id: id)
    defer { PerfSignposter.client.endInterval("RulesRefresh", state) }
    // ... fetch + verify + write ...
}
```

---

### S-6: Bounded concurrency = 1 (sequential) for failover paths (DEC-06d-04)

**Source:** memory `wiki/performance-baseline.md` § DEC-06d-04 + Phase 6c reachability handling

**Apply to:** `RulesFetcher.fetchWithFailover` (mirrors sequential), `RulesEngineCoordinator.forceUpdate` (cooldown gate single in-flight).

**Pattern:**
```swift
public func performBackgroundRefresh() async -> Bool {
    guard !isInFlight else { return false }  // guard re-entry
    isInFlight = true
    defer { isInFlight = false }
    // sequential mirror iteration; no TaskGroup; no concurrent fan-out
}
```

---

### S-7: Cold-start init defer pattern (DEC-06d-01)

**Source:** memory `feedback_phase6d_architectural_patterns.md` DEC-06d-01 + BBTB_iOSApp.swift Wave 03f comments

**Apply to:** `RulesEngineCoordinator` — **bootstrap baseline applies synchronously** (in-process baseline copy is fast, ~ms); **server fetch is deferred** to BGAppRefreshTask + foreground sanity Task (per Pitfall 2).

**Pattern (per D-12 in CONTEXT.md):**
```swift
// In App.init — DO NOT block on server fetch:
Task { await rulesCoordinator.bootstrap() }  // synchronous baseline copy only

// Server fetch happens via:
// 1. BGAppRefreshTask handler
// 2. SceneActive foreground sanity Task (if lastFetchedAt > 12h)
// 3. User tap on force-update button
```

---

### S-8: SwiftUI banner row inside Form Section with .listRowBackground

**Source:** `ReconnectBanner.swift` + Phase 6e MainScreenView line 32-44 + UI-SPEC §Layout «Persistent banner row»

**Apply to:** `MinAppVersionBanner` integration in `AdvancedSettingsView` (top of Form).

**Pattern (UI-SPEC §A-20):**
```swift
Section {
    Button(action: viewModel.openTestFlight) {
        HStack {
            Image(systemName: "arrow.up.circle.fill").foregroundColor(.orange)
            VStack(alignment: .leading) {
                Text(L10n.minAppVersionBannerText)
                Text(L10n.minAppVersionBannerCta).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
        }
    }
}
.listRowBackground(Color.orange.opacity(0.15))
```

---

## No Analog Found (use RESEARCH.md patterns)

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `Resources/*.srs` (3 baseline files) | binary asset | file-I/O | SRS v4 binary format — generated by `sing-box rule-set compile`; нет precedent в repo |
| `Resources/*.srs.sig` (3 sig sidecars) | binary asset | file-I/O | Ed25519 raw signature byte sidecar — new pattern (cryptographic asset rather than code/config) |
| `Resources/baseline-rules-manifest.json.sig` | binary asset | file-I/O | similar — new sidecar pattern |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift::publicKeyBytes` constant | crypto literal | n/a | 32-byte Ed25519 public key as Swift `[UInt8]` literal — нет precedent; **planner action:** generate via `openssl genpkey -algorithm ed25519 ... && openssl pkey -in privkey -pubout` then convert to Swift byte array via `xxd`/`hex` script in W1 |

For binary resource files — planner pulls patterns from RESEARCH.md §Architecture Patterns (build-script approach §Pattern 6) + §Don't Hand-Roll table (use `sing-box rule-set compile` CLI).

---

## Risks Surfaced

| # | Risk | Where | Mitigation |
|---|------|-------|------------|
| 1 | **`SubscriptionURLFetcher.isBlockedHost` is `internal`** — `RulesFetcher` in new package cannot reuse without copying code. | RulesFetcher.swift | **W0 task:** promote `isBlockedHost(_:)` + `normalizeHostForLog(_:)` to `public` (or extract to shared `Packages/VPNCore/Sources/VPNCore/Net/HostBlocklist.swift`). RESEARCH §Code Examples lines 653-654 already flags this. |
| 2 | **`AppGroupContainer.rulesCacheDirectory` creation race** between extension's `SingBoxConfigLoader.expandConfigForTunnel` (reads path) and main app's `SRSCacheStore.bootstrap` (creates dir + writes baseline). If extension starts BEFORE main app ever ran (first-launch impossible, but reactor in tests) → empty dir → sing-box rule_set load fails silently → cache stays empty forever. | AppGroupContainer.swift MODIFY | `createDirectory(withIntermediateDirectories: true)` is idempotent — calling from BOTH sides is safe. Add it to `expandConfigForTunnel` as defensive call. Pattern self-analog: `crashReportsURL` does the same (line 32-36). |
| 3 | **DesignSystem `DS.Spacing.md = 12`** in code but UI-SPEC A-14 dictates `md = 16` for Phase 8. | RulesViewerSection.swift, ForceUpdateRulesButton.swift, MinAppVersionSheet.swift | **Planner decision per A-14:** Phase 8 uses **literal `16`** in code (not `DS.Spacing.md`), defer global DS migration to Phase 11. Document in Wave 3 task. |
| 4 | **Existing `SingBoxConfigLoader.expandConfigForTunnel` produces config without `final` outbound clarity** when D-01 routes always-rule to `firstProxyTag` — но если template уже had `final: "vless-out"`, новое `outbound: "<firstProxyTag>"` для always category should match. Misalignment может направить always-через-VPN траффик в `direct` outbound. | SingBoxConfigLoader.swift MODIFY | Single source of truth — reuse same `firstProxyTag` resolution logic at line 219-223. Add unit test (`testRulesetInjection_alwaysCategoryUsesSameProxyTagAsFinal`). |
| 5 | **`SubscriptionURLFetcher` mock framework** uses ephemeral session + protocolClasses pattern documented in line 78 comment but not extracted as reusable helper. RulesFetcher tests need to either re-implement MockURLProtocol or import test-target helper. | RulesFetcherTests.swift | **W0 task:** decide — copy MockURLProtocol into RulesEngineTests target (simpler) OR extract to `Packages/VPNCore/Tests/TestHelpers/` shared test target (cleaner but new structure). Recommend copy-paste for v0.8 simplicity. |
| 6 | **Tuist target deletion breaks BBTB-macOS build** until tuist generate runs + Xcode reopen. | Project.swift MODIFY | Sequenced steps in RESEARCH §Runtime State Inventory step 1-5. Wave 0 must complete fully (delete files + tuist generate + Xcode reopen) before next wave starts. |
| 7 | **PublicKey rotation never planned** в v0.8 (Pitfall 5). Если key compromised до v1.x rotation infrastructure — пользователи навсегда заблокированы на cached version. | PublicKey.swift | Document TODO in PublicKey.swift docstring per RESEARCH §Pitfall 5 strategy. Wave 7 wiki update. |
| 8 | **fswatch.Watcher inside iOS NE sandbox** unverified (RESEARCH Open Question A4). Если не работает — атомарная замена SRS не приведёт к auto-reload в extension → требуется fallback (tunnel restart on rules update via PTP `wakeApp` or manifest `force_reload_token`). | SingBoxConfigLoader.swift MODIFY | **Wave 1 empirical validation task:** physical-device smoke test. If fails — add `force_reload_token` field to manifest + extension polls every 60s via lightweight `fileModificationDate` check. |
| 9 | **AppGroup write from main app + concurrent read from extension** during sing-box rule_set parse race condition. RESEARCH §Pattern 5 + §Pitfall 7 cover atomic write + sing-box's fswatch handling. | SRSCacheStore.swift | `Data.write(.atomic)` uses POSIX rename(2); sing-box's open fd remains valid on old inode. Verified `[ASSUMED]` per RESEARCH A2 — empirical W1 validation prescribed. |
| 10 | **Test depends on Yams + protocol stubs (existing ConfigParser Package.swift)** — RulesEngine package will be **leaner**: only swift-crypto + VPNCore. Cross-package test reuse не возможен (RulesEngineTests cannot depend on ConfigParser test helpers). | Package.swift | Self-contained MockURLProtocol per Risk #5. |

---

## Metadata

**Analog search scope:**
- `BBTB/Packages/PacketTunnelKit/Sources/` (8 files, focused: SingBoxConfigLoader, AppGroupContainer, TunnelLogger)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/` (5 files: SettingsView, AdvancedSettingsView, SettingsViewModel, AutoReconnectToggleSection, AdBlockToggleSection)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` (key files: MainScreenView, MainScreenViewModel, ReconnectBanner, EmptyStateCard, PerfSignposter, ConnectionTimer)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/` (SubscriptionHeader for timestamp header pattern)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/` (SubscriptionURLFetcher — primary HTTPS+SSRF pattern)
- `BBTB/Packages/VPNCore/Sources/VPNCore/` (Subscription, ServerConfig for Codable model pattern)
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift` (Spacing/Radius/Typography tokens)
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` (L10n key pattern)
- `BBTB/scripts/validate-r1-r6.sh` (shell invariant gate pattern)
- `BBTB/Project.swift` (Tuist target manifest)
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` + `BBTB/App/macOSApp/BBTB_macOSApp.swift` (host bootstrap)
- Memory references: `feedback_failover_two_phase_init.md`, `feedback_nevpn_observer_queue_main.md`, `feedback_phase6d_architectural_patterns.md`

**Files scanned:** ~28 files Read; ~10 directories Bash-listed.

**Pattern extraction date:** 2026-05-15

**Downstream:** `gsd-planner` will reference this PATTERNS.md when constructing per-wave PLAN.md actions. Each wave (W0..W7) maps to ≥3 patterns from this document.

---

*Phase: 8-rules-engine-split-tunneling*
*Pattern mapping complete (autonomous mode)*
*Ready for `gsd-planner` consumption*
