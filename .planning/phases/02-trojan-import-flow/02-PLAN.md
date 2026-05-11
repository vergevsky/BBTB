---
phase: 2
slug: trojan-import-flow
type: execute
mode: mvp
created: 2026-05-12
status: ready_for_execute
total_waves: 7
expected_commits: "25-32"
requirements:
  in_phase: [PROTO-02, PROTO-10, IMP-02, KILL-03]
  foundation_partial: [IMP-04, IMP-05, TRANSP-03, SRV-01, SRV-02, SRV-03]
files_modified:
  # Wave 0 — foundation refactor
  - BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift
  - BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift
  - BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusBadge.swift  # → renamed to StatusPill.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  # Wave 1 — ConfigParser foundation + Trojan package
  - BBTB/Packages/Protocols/Trojan/Package.swift
  - BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift
  - BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift
  - BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json
  - BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json
  - BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/JSONEndpointFetcher.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift
  - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/*.swift
  - BBTB/Packages/ConfigParser/Package.swift
  # Wave 2 — registration + integration smoke
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
  # Wave 3 — ConfigImporter rewrite + ViewModel
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
  - BBTB/Packages/AppFeatures/Tests/AppFeaturesTests/MainScreenViewModelTests.swift
  # Wave 4 — UI rewrite + SettingsFeature + QRScanner
  - BBTB/Packages/AppFeatures/Package.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusPill.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/EmptyStateCard.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ServerLineView.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TopBar.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerView.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/CameraPermission.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportProgressOverlay.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift
  - BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift
  - BBTB/Packages/Localization/Sources/Localization/L10n.swift
  - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
  - BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift
  - BBTB/App/iOSApp/Info.plist
  - BBTB/App/macOSApp/Info.plist
  - BBTB/App/macOSApp/BBTB-macOS.entitlements
  - BBTB/Project.swift
  # Wave 5 — integration tests
  - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/IntegrationTests.swift
  - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/*
  - .planning/phases/02-trojan-import-flow/02-UAT.md
autonomous: true

must_haves:
  truths:
    # User-observable behaviors derived from ROADMAP Phase 2 success criteria
    - "User can import a Trojan URI via clipboard → server appears in SwiftData with isSupported=true"
    - "User can import a multi-line URI block (mixed VLESS+Trojan) via clipboard → all parseable URIs are persisted; unparseable lines are skipped without aborting the import"
    - "User can import a subscription URL → app makes HTTPS GET, detects base64/plain-text/JSON, parses, persists all entries"
    - "User can import a JSON endpoint URL → JSON body is validated through SingBoxConfigLoader.validate (R1), servers extracted to SwiftData"
    - "User can scan a QR code containing a vless:// or trojan:// URI → same import pipeline as clipboard"
    - "Camera permission prompt appears on first QR scan attempt; denied → user sees alert with 'Open Settings' link"
    - "When the imported pool contains ≥2 supported servers, sing-box urltest outbound is generated; on probe failure of the active outbound, traffic switches to another within ~1m"
    - "When pool has 1 supported server, route.final points directly to that outbound (degenerate single-outbound config)"
    - "Trojan handler connects on TCP+TLS and WebSocket+TLS — packets flow through trojan-out outbound"
    - "Settings page accessible via menu icon (iOS push, macOS Cmd+,) — contains 'Безопасность' section with Kill Switch toggle"
    - "Kill Switch toggle off → next connect uses includeAllNetworks=false + enforceRoutes=false on NETunnelProviderProtocol"
    - "Toggling Kill Switch while connected shows ReconnectBanner on MainScreen; no forced reconnect"
    - "Empty-state shows centered card with two CTAs (clipboard / QR); top bar remains visible"
    - "Existing Phase 1 single-server import path still works (Phase 1 KillSwitchTests + VLESSRealityTests + SingBoxConfigLoaderTests pass after Wave 0 refactor)"
    - "Unsupported URI schemes (ss://, vmess://, hy2://, wireguard://) are stored with isSupported=false and excluded from urltest pool — no whole-import abort"
  artifacts:
    - path: "BBTB/Packages/Protocols/Trojan/Package.swift"
      provides: "Trojan SwiftPM package manifest"
      min_lines: 30
    - path: "BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift"
      provides: "TrojanHandler conforming to VPNProtocolHandler, identifier='trojan'"
      contains: "identifier"
    - path: "BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift"
      provides: "Trojan ConfigBuilder with TrojanInputs + buildSingBoxJSON(from:)"
      contains: "buildSingBoxJSON"
    - path: "BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json"
      provides: "sing-box template — Trojan over TCP+TLS"
      contains: "${TROJAN_PASSWORD}"
    - path: "BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json"
      provides: "sing-box template — Trojan over WebSocket+TLS"
      contains: "${WS_PATH}"
    - path: "BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift"
      provides: "TrojanURIParser.parse(_:) → ParsedTrojan"
      contains: "ParsedTrojan"
    - path: "BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift"
      provides: "UniversalImportParser actor — single entry point for any raw input"
      contains: "UniversalImportParser"
    - path: "BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift"
      provides: "HTTPS subscription URL fetch with User-Agent BBTB/0.2"
      contains: "SubscriptionURLFetcher"
    - path: "BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift"
      provides: "PoolBuilder.buildSingBoxJSON — assembles N outbounds + urltest selector"
      contains: "urltest"
    - path: "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift"
      provides: "Settings root view with Безопасность section + KillSwitch toggle"
      contains: "KillSwitchToggleSection"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerView.swift"
      provides: "SwiftUI QR scanner (UIViewControllerRepresentable iOS / NSViewRepresentable macOS)"
      contains: "AVCapture"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/EmptyStateCard.swift"
      provides: "Centered empty-state card with two CTAs"
      contains: "onAddFromClipboard"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift"
      provides: "Inline banner shown when Kill Switch flag changed during active tunnel"
      contains: "ReconnectBanner"
    - path: "BBTB/App/iOSApp/Info.plist"
      provides: "iOS Info.plist with NSCameraUsageDescription"
      contains: "NSCameraUsageDescription"
    - path: "BBTB/App/macOSApp/BBTB-macOS.entitlements"
      provides: "macOS entitlements with com.apple.security.device.camera"
      contains: "com.apple.security.device.camera"
    - path: ".planning/phases/02-trojan-import-flow/02-UAT.md"
      provides: "User acceptance test plan for device-side validation"
      min_lines: 60
  key_links:
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      to: "BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift"
      via: "import(rawInput:) entry point"
      pattern: "UniversalImportParser"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      to: "BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift"
      via: "PoolBuilder.buildSingBoxJSON(from: supported)"
      pattern: "PoolBuilder"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      to: "BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift"
      via: "KillSwitch.apply(to: proto, enabled: UserDefaults.bool(forKey: app.bbtb.killSwitchEnabled))"
      pattern: "KillSwitch\\.apply\\(to:.*enabled:"
    - from: "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift"
      to: "UserDefaults app.bbtb.killSwitchEnabled"
      via: "@AppStorage(\"app.bbtb.killSwitchEnabled\")"
      pattern: "@AppStorage.*killSwitchEnabled"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift"
      to: "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift"
      via: "NavigationLink from top-bar menu icon"
      pattern: "NavigationLink|openSettings"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerView.swift"
      to: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      via: "scanned string → ConfigImporter.import(rawInput:)"
      pattern: "onCodeScanned"
    - from: "BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift"
      to: "sing-box urltest outbound"
      via: "JSON assembly with outbounds=[tags], url=https://cp.cloudflare.com/generate_204, interval=1m"
      pattern: "\"type\":\\s*\"urltest\""
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift"
      to: "Phase 2 Trojan + urltest outbound types"
      via: "validate accepts {vless, trojan, urltest, ...} via proxyOutboundTypes set"
      pattern: "noProxyOutbound|proxyOutboundTypes"
    - from: "BBTB/App/iOSApp/BBTB_iOSApp.swift"
      to: "ProtocolRegistry.register(TrojanHandler.self)"
      via: "init() block, immediately after VLESSRealityHandler registration"
      pattern: "register\\(TrojanHandler"
---

# Phase 2 — Trojan + Import flow (v0.2)

## Phase Goal

**As a** BBTB user, **I want to** import any of my three subscription formats (URI list, subscription URL, JSON endpoint) or a single URI via clipboard / QR code and have the app auto-failover between VLESS+Reality and Trojan outbounds, **so that** when one outbound is throttled by TSPU I stay connected without manual intervention.

<objective>
Расширить v0.1 (singleton VLESS+Reality + system kill switch) до v0.2:

1. **Trojan handler (PROTO-02)** — TCP+TLS + WebSocket+TLS транспорт.
2. **Universal import** — клиент принимает single URI / multi-line URI block / subscription URL (base64 / plain-text / JSON response) / JSON endpoint URL. Все три формата раздачи ссылок пользователя парсятся (CONTEXT D-02).
3. **QR-import (IMP-02)** — AVFoundation сканер с camera permission flow iOS+macOS.
4. **Auto-fallback (PROTO-10)** — sing-box `urltest` outbound: один VPN-профиль, один NETunnelProviderManager, sing-box сам пробует HTTP-probe и переключает на failure (CONTEXT D-01, RESEARCH §1).
5. **Kill Switch toggle (KILL-03)** — Settings → Безопасность; применяется на следующем connect (CONTEXT D-12..D-15).
6. **SwiftData массив** — singleton `ServerConfig` мигрирован в multi-row с `isSupported` + `subscriptionURL` (CONTEXT D-06).
7. **MainScreen rewrite** — top bar (≡/+) + idle layout (timer → pill → power → server-line) + empty-state карточка (CONTEXT D-09, D-10, D-11; UI-SPEC §2-§3).

Purpose: пользователь раздаёт друзьям три разные ссылки (subscription URL, multi-line URI block, JSON endpoint). v0.2 должна принимать ВСЕ три без отдельной кнопки «выбери формат» — клиент сам определяет вход. Auto-failover нужен чтобы при тихом ТСПУ-режиме (TLS-handshake пропущен, payload пожёван) не приходилось вручную пересобирать конфиг.

Output: рабочие сборки iOS + macOS, прошедшие unit-test suite + integration tests; готовый 02-UAT.md для device-side проверки на iPhone.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/STATE.md
@.planning/phases/02-trojan-import-flow/02-CONTEXT.md
@.planning/phases/02-trojan-import-flow/02-RESEARCH.md
@.planning/phases/02-trojan-import-flow/02-PATTERNS.md
@.planning/phases/02-trojan-import-flow/02-UI-SPEC.md
@.planning/phases/01-foundation/01-CONTEXT.md
@.planning/phases/01-foundation/01-SECURITY.md

# Phase 1 carry-forward — anchor patterns
@BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift
@BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift
@BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusBadge.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportFromClipboardButton.swift
@BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift
@BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift
@BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift
@BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
@BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift
@BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift
@BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift
@BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift
@BBTB/Packages/Localization/Sources/Localization/L10n.swift
@BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
@BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift
@BBTB/Packages/AppFeatures/Package.swift
@BBTB/Packages/ConfigParser/Package.swift
@BBTB/Packages/Protocols/VLESSReality/Package.swift
@BBTB/App/iOSApp/BBTB_iOSApp.swift
@BBTB/App/macOSApp/BBTB_macOSApp.swift
@BBTB/App/iOSApp/Info.plist
@BBTB/App/macOSApp/Info.plist
@BBTB/App/macOSApp/BBTB-macOS.entitlements
@BBTB/Project.swift

<interfaces>
Key types Phase 2 consumes / extends. Executor should use these directly — no additional codebase exploration needed before W0.

From BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift:
```swift
public protocol VPNProtocolHandler: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    var isAvailable: Bool { get }
    init()
    func validate(config: ProtocolConfig) throws
    func connect(config: ProtocolConfig) async throws -> TunnelHandle
    func disconnect(handle: TunnelHandle) async throws
    func diagnostics() async -> ProtocolDiagnostics
}
```

From BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift (Phase 1 schema):
```swift
@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var protocolID: String
    public var keychainTag: String
    public var isActive: Bool
    public var createdAt: Date
    public var lastLatencyMs: Int?
}
```

From BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift (Phase 1 signature — being changed in W0):
```swift
public enum KillSwitch {
    public static func apply(to proto: NETunnelProviderProtocol)  // ← Phase 1
    // Phase 2 W0 renames to: apply(to: NETunnelProviderProtocol, enabled: Bool)
    public static func platformShouldDisableEnforceRoutes() -> Bool
}
```

From BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift (Phase 1):
```swift
public enum SingBoxConfigError: Error, LocalizedError, Equatable {
    case malformedJSON
    case forbiddenInboundType(String)
    case experimentalApiEnabled(String)
    case missingOutbounds
    case noVLESSOutbound  // ← Phase 2 W0: rename to noProxyOutbound
}
public enum SingBoxConfigLoader {
    public static func validate(json: String) throws
    public static func expandConfigForTunnel(json: String) throws -> String
    public static func loadVLESSRealityTemplate() throws -> String
}
```

From BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift (Phase 1 — exact analog for Trojan):
```swift
public struct ParsedVLESS: Sendable, Equatable {
    public let uuid: String; public let host: String; public let port: Int
    public let publicKey: String; public let shortId: String; public let sni: String
    public let fingerprint: String; public let flow: String; public let remarks: String?
}
public enum VLESSURIError: Error, LocalizedError, Equatable {
    case malformedURI; case notRealitySecurity(String?); case missingPublicKey
}
public enum VLESSURIParser {
    public static func parse(_ uri: String) throws -> ParsedVLESS
}
```

From BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift (Phase 1 — extended in W3):
```swift
public enum ConnectionState: Equatable {
    case empty; case idle; case connecting; case connected(since: Date); case error(message: String)
}
@MainActor public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState
    @Published public var lastError: String?
    public init(importer: ConfigImporting, controller: TunnelControlling)
    public func importFromPasteboard()
    public func performToggle()
}
```

From BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (Phase 1 signature — being widened in W3):
```swift
public protocol ConfigImporting: Sendable {
    func importFromPasteboard() async throws -> ServerConfig  // ← Phase 1
    // Phase 2 W3: widen to importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult
}
```

Phase 2 new contracts (created across waves — referenced by later waves):

```swift
// ConfigParser (W1) — ImportedServer.swift
public enum ImportedServer: Sendable {
    case supported(name: String, parsed: AnyParsedConfig, rawURI: String)
    case unsupported(name: String, scheme: String, host: String, port: Int, rawURI: String, reason: UnsupportedReason)
    case invalid(rawURI: String, error: String)
}
public enum AnyParsedConfig: Sendable {
    case vlessReality(ParsedVLESS)
    case trojan(ParsedTrojan)
}
public enum UnsupportedReason: String, Sendable {
    case schemaUnsupportedInPhase2; case transportUnsupported; case malformedURI
}
public enum ImportSource: Sendable, Equatable {
    case pasteboard; case subscriptionURL(URL); case jsonEndpoint(URL); case qrCode; case multilineText
}
public struct ImportResult: Sendable {
    public let supported: [ImportedServer]; public let unsupported: [ImportedServer]
    public let failed: [ImportedServer]; public let subscriptionURL: String?; public let source: ImportSource
}

// ConfigParser (W1) — TrojanURIParser.swift
public struct ParsedTrojan: Sendable, Equatable {
    public let password: String; public let host: String; public let port: Int
    public let security: String; public let sni: String; public let fingerprint: String
    public let alpn: [String]; public let transport: TransportType; public let remarks: String?
    public enum TransportType: Sendable, Equatable { case tcp; case ws(path: String, host: String) }
}
public enum TrojanURIParser { public static func parse(_ uri: String) throws -> ParsedTrojan }
```
</interfaces>
</context>

<wave_overview>

Phase 2 plan organized as 7 waves. Each wave ends with a clean commit. Total expected: 25–32 commits.

| Wave | Goal | Depends on | Tasks | Commits |
|---|---|---|---|---|
| 0 | Foundation refactor (no behavior change) | — | 6 | 4–5 |
| 1 | ConfigParser foundation + Trojan package | W0 | 9 | 5–7 |
| 2 | Registration + dual-protocol smoke | W1 | 2 | 1–2 |
| 3 | ConfigImporter rewrite + ViewModel | W0, W1, W2 | 3 | 3–4 |
| 4 | UI rewrite + SettingsFeature + QRScanner + Tuist | W0, W3 | 9 | 6–8 |
| 5 | Integration tests + 02-UAT.md | W0–W4 | 3 | 2–3 |
| 6 | Build verification + cleanup | W0–W5 | 2 | 1–2 |

</wave_overview>

---

## Wave 0 — Foundation refactor

**Goal:** Расширить базовые типы и валидатор так, чтобы Phase 1 single-VLESS path продолжал работать **без видимых изменений**, но Phase 2 multi-protocol / multi-outbound сценарии стали возможны. Каждый отдельный коммит W0 не должен ломать ни один Phase 1 test.

**Dependencies:** none — стартовый wave.

**Wave commit count:** 4–5 (lightly clustered — каждый шаг независим, но логически связан).

### Task W0.T1: Extend `ServerConfig` SwiftData @Model with Phase 2 fields

<task type="auto">
  <name>Task W0.T1: Extend ServerConfig with isSupported/subscriptionURL/outboundJSON/protocolDisplayName (D-06)</name>
  <files>BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift</files>
  <action>
Расширяем `@Model public final class ServerConfig` четырьмя новыми properties с default values — это обеспечивает SwiftData lightweight migration без VersionedSchema (RESEARCH §10.3, §10.4):

- `public var isSupported: Bool = true` — D-04: false для парсеров stubs (ss, vmess, hy2, wireguard); true для vless/trojan; defaults to true чтобы существующие Phase 1 rows остались supported.
- `public var subscriptionURL: String? = nil` — D-07: URL подписки, из которой пришёл pool (для replace-pool детекции при re-import). nil для single-paste import.
- `public var outboundJSON: String = ""` — raw outbound JSON snippet для последующей сборки PoolBuilder'ом. Default empty string — Phase 1 rows получат пустую строку, при первом use будет regenerated из protocolID + rawURI.
- `public var protocolDisplayName: String = ""` — человеко-читаемое название протокола ("VLESS + Reality", "Trojan", "Shadowsocks (не поддерживается v0.2)"). Default empty string.

Также добавить опциональные поля для D-06 server identity (host+port+protocolID+sni для дедупликации) и для D-04 re-parse при handler upgrade:

- `public var sni: String? = nil`
- `public var rawURI: String? = nil`

Сделать `keychainTag` optional — для unsupported servers нет Keychain entry: `public var keychainTag: String? = nil` (ВНИМАНИЕ: Phase 1 имел non-optional `keychainTag: String`. Это **breaking schema change** — но SwiftData lightweight migration поддерживает optional-isation: existing rows получат `keychainTag` со старым значением; новые unsupported rows будут иметь nil).

Обновить `public init(...)` сигнатуру: добавить новые параметры с default values чтобы существующие callsites (Phase 1 ConfigImporter) продолжали компилироваться. Порядок параметров: сначала старые (Phase 1 — все same), затем новые с defaults.

Reference: RESEARCH §10.2 для целевой схемы, §10.3 для migration rationale; PATTERNS §2.24 для exact placement.
  </action>
  <verify>
    <automated>cd BBTB/Packages/VPNCore && swift build 2>&1 | grep -E "error|warning: " | head -20</automated>
  </verify>
  <done>VPNCore компилируется; `grep -c "public var isSupported" BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` returns 1; `grep -c "public var subscriptionURL" ...` returns 1; `grep -c "public var outboundJSON" ...` returns 1; `grep -c "public var protocolDisplayName" ...` returns 1.</done>
</task>

### Task W0.T2: Refactor `KillSwitch.apply(to:)` → `apply(to:enabled:)` with default `enabled=true`

<task type="auto" tdd="true">
  <name>Task W0.T2: KillSwitch.apply parameterised by enabled flag (D-15)</name>
  <files>BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift, BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift</files>
  <behavior>
    - Test 1 (existing, updated): `apply(to: proto, enabled: true)` устанавливает `includeAllNetworks=true` + `enforceRoutes=!platformShouldDisableEnforceRoutes()`.
    - Test 2 (existing, updated): `apply(to: proto, enabled: true)` устанавливает `excludeLocalNetworks=false` + `disconnectOnSleep=false` (R4 default).
    - Test 3 (new): `apply(to: proto, enabled: false)` устанавливает `includeAllNetworks=false` + `enforceRoutes=false`.
    - Test 4 (new): `apply(to: proto, enabled: false)` НЕ меняет `excludeLocalNetworks` и `disconnectOnSleep` относительно дефолтов — они остаются `false`.
    - Test 5 (existing, updated): R5 macOS-hook `platformShouldDisableEnforceRoutes()` всё ещё вызывается при `enabled=true` (Phase 1 carry-forward).
  </behavior>
  <action>
Изменить signature `KillSwitch.apply` per D-15 (PATTERNS §2.25):

```swift
public enum KillSwitch {
    public static func apply(to proto: NETunnelProviderProtocol, enabled: Bool) {
        if enabled {
            proto.includeAllNetworks = true
            proto.enforceRoutes = !platformShouldDisableEnforceRoutes()
        } else {
            proto.includeAllNetworks = false
            proto.enforceRoutes = false
        }
        proto.excludeLocalNetworks = false  // R4 default — unchanged
        proto.disconnectOnSleep = false     // R4 default — unchanged
    }

    public static func platformShouldDisableEnforceRoutes() -> Bool {
        return false  // Phase 10 R5 hook unchanged
    }
}
```

Обновить ВСЕ существующие call-sites:
- `BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift` — все 5 тестов меняют `KillSwitch.apply(to: proto)` → `KillSwitch.apply(to: proto, enabled: true)`. Добавить два новых теста для `enabled: false` (Test 3 и Test 4 из <behavior> выше).
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — единственный production call-site Phase 1; временно меняем на `KillSwitch.apply(to: proto, enabled: true)` (hardcoded true). Реальное чтение из UserDefaults будет в W3.T1 (ConfigImporter rewrite). Это **временно** — но позволяет Phase 1 single-server import продолжать работать без изменения поведения.

R5 hook остаётся `public` (Phase 10 переопределит через UserDefaults read).

Reference: PATTERNS §2.25, RESEARCH §9.6 (для context почему enabled=true hardcoded ОК на этом этапе).
  </action>
  <verify>
    <automated>cd BBTB/Packages/KillSwitch && swift test 2>&1 | tail -20</automated>
  </verify>
  <done>`swift test` в KillSwitch package — все 7 тестов зелёные (5 existing + 2 new); `grep -n "KillSwitch.apply(to:" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` показывает single call-site с `enabled: true`.</done>
</task>

### Task W0.T3: Rename `StatusBadge` → `StatusPill` (move only — no visual changes)

<task type="auto">
  <name>Task W0.T3: Rename StatusBadge → StatusPill (file + type) without changing rendering location</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusBadge.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift</files>
  <action>
**Этот таск — pure rename, без визуальных изменений.** Реальное перемещение pill из header под power-кнопку — в W4.T3 при rewrite `MainScreenView`.

1. Переименовать файл `StatusBadge.swift` → `StatusPill.swift` через `git mv`.
2. Переименовать тип внутри: `public struct StatusBadge: View` → `public struct StatusPill: View`. Сохранить тот же `init(state: ConnectionState)` интерфейс и ту же реализацию `body` (PATTERNS §2.18 — restyle к Capsule произойдёт в W4.T3, не сейчас).
3. Обновить call-site в `MainScreenView.swift` (Phase 1 уже использует `StatusBadge(state: viewModel.state)` где-то в header) — поменять на `StatusPill(state:)`.
4. **Не менять** visuals — оставить текущий `Color` / `font` / position. W4.T3 перепишет вёрстку и применит Capsule shape + новые цвета.

Цель: единая чистая операция rename, без перемешивания с visual rewrite. Phase 1 functional behaviour preserved.

Reference: PATTERNS §2.18.
  </action>
  <verify>
    <automated>test ! -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusBadge.swift && test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusPill.swift && grep -rc "StatusBadge" BBTB/Packages/AppFeatures/Sources/ | grep -v ":0$" | wc -l | awk '{exit ($1 == 0 ? 0 : 1)}'</automated>
  </verify>
  <done>File `StatusBadge.swift` не существует; `StatusPill.swift` существует; `grep -r "StatusBadge"` в `BBTB/Packages/AppFeatures/Sources/` возвращает ноль матчей; `cd BBTB/Packages/AppFeatures && swift build` зелёный.</done>
</task>

### Task W0.T4: Relax `SingBoxConfigLoader.validate` to accept Trojan/urltest outbounds

<task type="auto" tdd="true">
  <name>Task W0.T4: Relax validate — replace noVLESSOutbound with noProxyOutbound (R1-preserving) (RESEARCH §7)</name>
  <files>BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift, BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift, BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/</files>
  <behavior>
    - Test 1 (existing, updated): valid VLESS-only config passes validate (Phase 1 carry-forward).
    - Test 2 (new): valid Trojan-only config passes validate.
    - Test 3 (new): valid pool config (vless + trojan + urltest + direct, route.final=urltest-out) passes validate.
    - Test 4 (new): config without ANY proxy outbound (только direct) throws `.noProxyOutbound`.
    - Test 5 (new): config с `experimental.clash_api: enabled: true` всё ещё throws `.experimentalApiEnabled("clash_api")` (R1 unchanged).
    - Test 6 (existing, kept): R1 inbound whitelist still works — config с `{inbounds: [{type: socks}]}` throws `.forbiddenInboundType("socks")`.
    - Test 7 (new): pool config с `urltest.outbounds` ссылающимся на несуществующий tag — throws `.unresolvedOutboundRef(ref, type: "urltest")`.
  </behavior>
  <action>
В `SingBoxConfigLoader.validate(json:)`:

1. **Заменить** error case `noVLESSOutbound` → `noProxyOutbound` в enum `SingBoxConfigError`. Update LocalizedError text.
2. Заменить последнюю проверку:
   ```swift
   // OLD (Phase 1):
   // let hasVLESS = outbounds.contains { ($0["type"] as? String) == "vless" }
   // guard hasVLESS else { throw SingBoxConfigError.noVLESSOutbound }

   // NEW (Phase 2):
   let proxyOutboundTypes: Set<String> = [
       "vless", "trojan",                                  // Phase 2 supported handlers
       "urltest", "selector",                              // group outbounds (содержат proxy outbounds внутри)
       "shadowsocks", "vmess", "hysteria2", "wireguard", "tuic",  // future-supported (доп. для config files которые operator пришлёт)
   ]
   let hasProxyOutbound = outbounds.contains { 
       guard let type = $0["type"] as? String else { return false }
       return proxyOutboundTypes.contains(type)
   }
   guard hasProxyOutbound else { throw SingBoxConfigError.noProxyOutbound }
   ```
3. Добавить новый sanity check для urltest references (RESEARCH §7.3):
   ```swift
   let allTags = Set(outbounds.compactMap { $0["tag"] as? String })
   for outbound in outbounds {
       guard let type = outbound["type"] as? String,
             (type == "urltest" || type == "selector"),
             let refs = outbound["outbounds"] as? [String]
       else { continue }
       for ref in refs where !allTags.contains(ref) {
           throw SingBoxConfigError.unresolvedOutboundRef(ref: ref, in: type)
       }
   }
   ```
   Добавить case `unresolvedOutboundRef(ref: String, in: String)` в `SingBoxConfigError`.

4. **R1 inbound whitelist** не трогать — он уже корректен (RESEARCH §7.1).

5. **Создать fixtures** в `Tests/PacketTunnelKitTests/Fixtures/`:
   - `valid-trojan-only.json` — single Trojan outbound + direct + route.final="trojan-out"
   - `valid-pool-vless-trojan.json` — vless-out + trojan-out + urltest-out (outbounds=[vless-out, trojan-out]) + direct + route.final="urltest-out", dns.detour="urltest-out" (per RESEARCH §1.6)
   - `invalid-no-proxy-outbound.json` — только direct
   - `invalid-urltest-unresolved-ref.json` — urltest.outbounds=["nonexistent-tag"]

6. **Обновить existing tests**: Phase 1 fixtures (`valid-vless-reality.json` и т.п.) должны проходить без изменений — но любой test который ссылается на `SingBoxConfigError.noVLESSOutbound` нужно поменять на `.noProxyOutbound` (имя case'а изменилось).

Reference: RESEARCH §7.1, §7.2, §7.3; PATTERNS §5.2; для R1 inbound rule — Phase 1 SECURITY.md.
  </action>
  <verify>
    <automated>cd BBTB/Packages/PacketTunnelKit && swift test 2>&1 | tail -30</automated>
  </verify>
  <done>`swift test` в PacketTunnelKit зелёный; `grep -c "noProxyOutbound" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` returns ≥1; `grep -c "noVLESSOutbound" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` returns 0; новые 4 фикстуры существуют.</done>
</task>

### Task W0.T5: Update VLESS-Reality template — DNS detour switches to urltest-out placeholder

<task type="auto">
  <name>Task W0.T5: Update SingBoxConfigTemplate.vless-reality.json dns.detour → ${DNS_DETOUR} (RESEARCH §1.6)</name>
  <files>BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json, BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift, BBTB/Packages/Protocols/VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift</files>
  <action>
RESEARCH §1.6 показывает критичный нюанс: если `dns-remote.detour = "vless-out"` (Phase 1 hardcoded), а urltest переключился на `trojan-out` — DoH-запросы DNS всё ещё пойдут через мёртвый vless. Phase 2 W3 PoolBuilder будет вписывать `detour: "urltest-out"`. Чтобы single-server case (Phase 1 path, без urltest) продолжал работать — заменяем hardcoded `"vless-out"` на `${DNS_DETOUR}` placeholder.

1. В `SingBoxConfigTemplate.vless-reality.json` найти DNS `dns.servers[].detour: "vless-out"` (одно вхождение, RESEARCH §1.6 цитирует) — заменить на `"${DNS_DETOUR}"`.
2. В `VLESSReality/ConfigBuilder.swift` добавить substitution `${DNS_DETOUR}` → `"vless-out"` (для single-server Phase 1 case). Сигнатура `buildSingBoxJSON(from:)` не меняется — substitution делается из constant внутри builder.
3. Update `VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift`:
   - Existing test «buildSingBoxJSON_filled_passesValidate» — проверить что после substitution `${DNS_DETOUR}` отсутствует в output И `"vless-out"` присутствует в DNS section.
   - Добавить grep-style check: output не содержит литерал `${DNS_DETOUR}`.

**Почему это важно:** W3 PoolBuilder будет генерировать тот же `${DNS_DETOUR}` placeholder в pool template, но подставлять `"urltest-out"`. Единый pattern.

Reference: RESEARCH §1.6 (mitigation block); PATTERNS §2.4 anti-pattern «hardcoded values in template».
  </action>
  <verify>
    <automated>cd BBTB/Packages/Protocols/VLESSReality && swift test 2>&1 | tail -15</automated>
  </verify>
  <done>`swift test` VLESSReality зелёный; `grep -c '${DNS_DETOUR}' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` returns 1; output ConfigBuilder.buildSingBoxJSON не содержит литерал `${DNS_DETOUR}`.</done>
</task>

### Task W0.T6: Wave 0 regression check — full Phase 1 unit test suite green

<task type="auto">
  <name>Task W0.T6: Regression check — все Phase 1 пакеты компилируются и проходят tests</name>
  <files>(verification only — no file edits)</files>
  <action>
Прогнать full test suite для каждого Phase 1 пакета и подтвердить что W0.T1–T5 не сломали ничего:

```bash
cd BBTB/Packages/VPNCore && swift test 2>&1 | tail -5
cd BBTB/Packages/PacketTunnelKit && swift test 2>&1 | tail -5
cd BBTB/Packages/KillSwitch && swift test 2>&1 | tail -5
cd BBTB/Packages/Protocols/VLESSReality && swift test 2>&1 | tail -5
cd BBTB/Packages/ConfigParser && swift test 2>&1 | tail -5  # Phase 1 VLESSURIParser tests
cd BBTB/Packages/Localization && swift test 2>&1 | tail -5
```

Если любой пакет красный — диагностировать и зафиксировать в commit, **не** двигаться в Wave 1.

Reference: PATTERNS §5.4 «Phase 1 Test Regression Risk» — это явно идентифицировано как риск.

**Commit message templates для Wave 0:**

```
refactor(02/w0): extend ServerConfig schema with isSupported/subscriptionURL/outboundJSON/protocolDisplayName (D-06)

Lightweight SwiftData migration — все новые fields с default values; существующие
Phase 1 rows получают isSupported=true (D-04).

(02-W0.T1)
```

```
refactor(02/w0): parameterise KillSwitch.apply with enabled flag (D-15)

KillSwitch.apply(to:enabled:) — enabled=false → includeAllNetworks=false,
enforceRoutes=false. 5 existing tests updated, 2 new tests added. Phase 1
single-server import path продолжает работать (ConfigImporter передаёт
enabled=true hardcoded; реальное чтение из UserDefaults в W3).

(02-W0.T2)
```

```
refactor(02/w0): rename StatusBadge → StatusPill (file + type, no visual change)

Pure rename ahead of W4 visual rewrite (D-09 — pill переезжает под power-кнопку).

(02-W0.T3)
```

```
refactor(02/w0): relax SingBoxConfigLoader.validate to accept trojan/urltest (RESEARCH §7)

noVLESSOutbound → noProxyOutbound, accepting any of {vless, trojan, urltest, ...}.
R1 inbound whitelist unchanged. Added urltest.outbounds reference resolution check.
4 new fixtures, 6 new tests.

(02-W0.T4)
```

```
refactor(02/w0): parameterise dns.detour in vless-reality template via ${DNS_DETOUR} (RESEARCH §1.6)

Готовит template к Pool case (W3) когда detour=urltest-out. Single-server
Phase 1 case продолжает подставлять "vless-out".

(02-W0.T5)
```
  </action>
  <verify>
    <automated>for pkg in VPNCore PacketTunnelKit KillSwitch Localization ConfigParser; do echo "=== $pkg ==="; (cd "BBTB/Packages/$pkg" && swift test 2>&1 | tail -3); done; for proto in VLESSReality; do echo "=== Protocols/$proto ==="; (cd "BBTB/Packages/Protocols/$proto" && swift test 2>&1 | tail -3); done</automated>
  </verify>
  <done>Все 6 пакетов имеют тот же или больший test pass count чем до Wave 0; ни один тест не упал; output последней строки `swift test` для каждого содержит "Test Suite ... passed" (или эквивалент Swift 6.x runner).</done>
</task>

---

## Wave 1 — ConfigParser universal foundation + Trojan package (no UI)

**Goal:** Создать полную parsing/building pipeline для всех трёх форматов раздачи ссылок + Trojan handler package, **без** интеграции с UI или ConfigImporter. Каждый компонент покрыт unit-тестами с фикстурами, которые включают реальные user URI из CONTEXT.md `<specifics>`.

**Dependencies:** W0 (нужен relaxed validator + ServerConfig extensions + KillSwitch new signature).

**Wave commit count:** 5–7.

**Architecture invariant (PATTERNS §3.6):** ConfigParser НЕ depends on PacketTunnelKit. Если PoolBuilder нужен sing-box-template, template path inject'ится через параметр или загружается в orchestration layer (ConfigImporter — W3) с передачей строки в PoolBuilder. Цикл VPNCore → ConfigParser → PacketTunnelKit недопустим.

### Task W1.T1: Create `Packages/Protocols/Trojan/` SwiftPM package + handler + templates

<task type="auto">
  <name>Task W1.T1: Trojan package skeleton — Package.swift, TrojanHandler, two sing-box templates</name>
  <files>BBTB/Packages/Protocols/Trojan/Package.swift, BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift, BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json, BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json</files>
  <action>
Создать новый под-package `Packages/Protocols/Trojan/` по образцу `Packages/Protocols/VLESSReality/` (PATTERNS §2.1, §2.2).

**Package.swift** — точная копия VLESSReality/Package.swift с двумя resources entries (PATTERNS §2.1 full template). Имя `"Trojan"`, продукт `.library(name: "Trojan", targets: ["Trojan"])`, dependencies `[VPNCore, PacketTunnelKit]`, target resources `[.process("Resources/SingBoxConfigTemplate.trojan-tcp.json"), .process("Resources/SingBoxConfigTemplate.trojan-ws.json")]`, testTarget с same linker settings что VLESSReality.

**Decision per PATTERNS §5.1:** templates живут в Trojan package (Option B — modular). VLESSReality остаётся с template в PacketTunnelKit в этой фазе (миграция в Phase 4).

**TrojanHandler.swift** (PATTERNS §2.2):
```swift
public struct TrojanHandler: VPNProtocolHandler {
    public static let identifier = "trojan"        // lowercase, matches URI scheme
    public static let displayName = "Trojan"
    public var isAvailable: Bool { true }
    public init() {}
    public func validate(config: ProtocolConfig) throws {
        guard config.identifier == Self.identifier else {
            throw HandlerError.identifierMismatch(expected: Self.identifier, got: config.identifier)
        }
    }
    public func connect(config: ProtocolConfig) async throws -> TunnelHandle { TunnelHandle() }
    public func disconnect(handle: TunnelHandle) async throws {}
    public func diagnostics() async -> ProtocolDiagnostics { ProtocolDiagnostics() }

    public enum HandlerError: Error, LocalizedError {
        case identifierMismatch(expected: String, got: String)
        public var errorDescription: String? { /* same shape as VLESSRealityHandler.HandlerError */ }
    }
}
```

**SingBoxConfigTemplate.trojan-tcp.json** (RESEARCH §2.6, PATTERNS §2.4) — JSON со структурой:
```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": { /* identical to vless-reality.json template — same dns-remote/dns-bootstrap/dns-fakeip servers, same rules, same fakeip block, same final/strategy/independent_cache */
           /* dns-remote.detour = "${DNS_DETOUR}" placeholder per W0.T5 */
           /* dns-bootstrap.detour = "direct" */ },
  "outbounds": [
    {
      "type": "trojan",
      "tag": "trojan-out",
      "server": "${SERVER_HOST}",
      "server_port": 443,
      "password": "${TROJAN_PASSWORD}",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "insecure": false,
        "alpn": ["h2", "http/1.1"],
        "utls": { "enabled": true, "fingerprint": "${UTLS_FINGERPRINT}" }
      }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "action": "sniff", "timeout": "1s" },
      { "protocol": "dns", "action": "hijack-dns" }
    ],
    "final": "trojan-out",
    "auto_detect_interface": true
  },
  "experimental": {}
}
```

**SingBoxConfigTemplate.trojan-ws.json** — тот же что trojan-tcp.json + добавлен `"transport"` block в outbound:
```json
"transport": {
    "type": "ws",
    "path": "${WS_PATH}",
    "headers": { "Host": "${WS_HOST}" }
}
```

**Phase 1 W5 learning (PATTERNS §2.4 invariants):** **ВСЕ** server-specific значения параметризованы placeholders — никаких hardcoded password / SNI / fingerprint значений. Hardcoded `server_port: 443` — допустимо, mutatePort() в ConfigBuilder подменит если URI port != 443.

`insecure: false` — hardcoded **намеренно** (R1, D-08): `allowInsecure=1` в URI всегда игнорируется. Параметризовать НЕ нужно.

Reference: RESEARCH §2.1, §2.2, §2.3, §2.6; PATTERNS §2.1, §2.2, §2.4, §5.1.
  </action>
  <verify>
    <automated>cd BBTB/Packages/Protocols/Trojan && swift build 2>&1 | tail -10</automated>
  </verify>
  <done>Trojan package компилируется; `test -f BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift && test -f BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json && test -f BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json` returns success; `grep -c '${TROJAN_PASSWORD}' BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/*.json` returns 2.</done>
</task>

### Task W1.T2: Create `Trojan/ConfigBuilder.swift` + tests

<task type="auto" tdd="true">
  <name>Task W1.T2: Trojan ConfigBuilder + tests — TrojanInputs → sing-box JSON</name>
  <files>BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift, BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift</files>
  <behavior>
    - Test 1: `buildSingBoxJSON` для TCP-inputs (host=example.com, port=443, password=secret, sni=vpn.example.ru, fingerprint=chrome, alpn=[h2,http/1.1], transport=.tcp): output не содержит `${...}` placeholders; содержит `"secret"`; passes `SingBoxConfigLoader.validate(json:)`.
    - Test 2: `buildSingBoxJSON` для WS-inputs (transport=.ws(path:"/path123", host:"vpn.example.ru")): output содержит `"type": "ws"`, `"path": "/path123"`, `"Host": "vpn.example.ru"`; passes validate.
    - Test 3: non-default port (port=2087) → output's `"server_port"` равен 2087 (mutatePort применён).
    - Test 4: empty password → throws `BuilderError.missingPassword`.
    - Test 5: empty sni → throws `BuilderError.missingSNI` (R1 — SNI mandatory for DPI-resistance).
    - Test 6: port=0 → throws `BuilderError.invalidPort(0)`; port=70000 → throws `BuilderError.invalidPort(70000)`.
    - Test 7 (real user URI fixture): TCP+TLS Trojan с password="LN8x95baqueFriHJLnFuDQ", host="185.237.218.81", port=2087, sni="vpn.vergevsky.ru" (sanitized из user fixture в CONTEXT `<specifics>`) → output is valid JSON, passes validate, all placeholders replaced.
  </behavior>
  <action>
Создать `ConfigBuilder.swift` по образцу VLESSReality/ConfigBuilder.swift (PATTERNS §2.3 full template).

```swift
public enum ConfigBuilder {
    public struct TrojanInputs: Sendable, Equatable {
        public let host: String
        public let port: Int
        public let password: String
        public let sni: String
        public let fingerprint: String
        public let alpn: [String]
        public let transport: TransportType
        public let remark: String?
        public init(host: String, port: Int, password: String, sni: String,
                    fingerprint: String, alpn: [String], transport: TransportType, remark: String?) { /* assign */ }
    }
    public enum TransportType: Sendable, Equatable {
        case tcp
        case ws(path: String, host: String)
    }
    public enum BuilderError: Error, LocalizedError {
        case templateLoadFailed(Error)
        case invalidPort(Int)
        case missingPassword
        case missingSNI
        public var errorDescription: String? { /* same shape as VLESSReality.BuilderError */ }
    }

    public static func buildSingBoxJSON(from inputs: TrojanInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        guard !inputs.password.isEmpty else { throw BuilderError.missingPassword }
        guard !inputs.sni.isEmpty else { throw BuilderError.missingSNI }

        let templateName: String
        switch inputs.transport {
        case .tcp: templateName = "SingBoxConfigTemplate.trojan-tcp"
        case .ws:  templateName = "SingBoxConfigTemplate.trojan-ws"
        }
        let template = try loadTemplate(named: templateName)

        var filled = template
            .replacingOccurrences(of: "${SERVER_HOST}",        with: inputs.host)
            .replacingOccurrences(of: "${TROJAN_PASSWORD}",    with: inputs.password)
            .replacingOccurrences(of: "${SNI_DOMAIN}",         with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}",   with: inputs.fingerprint)
            .replacingOccurrences(of: "${DNS_DETOUR}",         with: "trojan-out")  // single-server case; pool case bypasses ConfigBuilder
        if case .ws(let path, let host) = inputs.transport {
            let wsHost = host.isEmpty ? inputs.sni : host
            filled = filled
                .replacingOccurrences(of: "${WS_PATH}", with: path)
                .replacingOccurrences(of: "${WS_HOST}", with: wsHost)
        }
        if inputs.port != 443 {
            return try mutatePort(in: filled, to: inputs.port)
        }
        return filled
    }

    private static func mutatePort(in json: String, to port: Int) throws -> String {
        // identical pattern to VLESSReality/ConfigBuilder.swift mutatePort:
        // JSONSerialization → mutate outbounds[where type==trojan].server_port → reserialise
    }

    private static func loadTemplate(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw BuilderError.templateLoadFailed(NSError(domain: "Trojan.ConfigBuilder", code: -1))
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

Тесты в `Tests/TrojanTests/ConfigBuilderTests.swift` (PATTERNS §2.5):
- import `PacketTunnelKit` для `SingBoxConfigLoader.validate` self-check (R1).
- `@testable import Trojan`.

**Critical invariant:** все 7 тестов должны явно вызвать `try SingBoxConfigLoader.validate(json: built)` — это R1 self-test. После W0.T4 этот validate должен принимать Trojan outbound.

Reference: RESEARCH §2.6, §3.5; PATTERNS §2.3, §2.5; Phase 1 W5 learning (commit 9aa3e93) — все поля параметризованы.
  </action>
  <verify>
    <automated>cd BBTB/Packages/Protocols/Trojan && swift test 2>&1 | tail -15</automated>
  </verify>
  <done>`swift test` Trojan package — все 7 тестов зелёные; output `swift test` содержит "passed"; `grep -c "SingBoxConfigLoader.validate" BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift` returns ≥7.</done>
</task>

### Task W1.T3: Create `ConfigParser/TrojanURIParser.swift` + tests

<task type="auto" tdd="true">
  <name>Task W1.T3: TrojanURIParser + tests (RESEARCH §3, real user URI fixture)</name>
  <files>BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-ws-user-fixture.txt, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-tcp-uri.txt</files>
  <behavior>
    - Test 1 (real user fixture, CONTEXT `<specifics>` line ~266): `trojan://LN8x95baqueFriHJLnFuDQ@185.237.218.81:2087?security=tls&type=ws&path=/ba0ca9ffa1d4&sni=vpn.vergevsky.ru&fp=chrome#Латвия — Trojan` parses to `ParsedTrojan(password:"LN8x95baqueFriHJLnFuDQ", host:"185.237.218.81", port:2087, security:"tls", sni:"vpn.vergevsky.ru", fingerprint:"chrome", alpn:["h2","http/1.1"], transport:.ws(path:"/ba0ca9ffa1d4", host:"vpn.vergevsky.ru"), remarks:"Латвия — Trojan")`.
    - Test 2: TCP+TLS minimal URI `trojan://pwd@host:443?security=tls#TCP` parses, transport=.tcp.
    - Test 3: missing `sni` → fallback to URI authority host (D-08).
    - Test 4: missing `sni` AND missing `peer` → fallback to host.
    - Test 5: `peer=foo.com` без `sni` → fallback на peer (clash-extension).
    - Test 6: `security=none` → throws `.notTLSSecurity("none")` (D-08).
    - Test 7: `security` missing → throws `.notTLSSecurity(nil)` (strict, D-08).
    - Test 8: `type=ws` без `path` → throws `.invalidTransport("ws-missing-path")` или эквивалентная ошибка с понятным message.
    - Test 9: `type=h2` → throws `.invalidTransport("h2")` (trojan-go-only, не поддерживается).
    - Test 10: `allowInsecure=1` параметр — НЕ throws; парсится и **игнорируется** (R1, D-08). Output's `security` остаётся "tls".
    - Test 11: empty password (`trojan://@host:443?security=tls`) → throws `.missingPassword` или `.malformedURI`.
    - Test 12: invalid port → throws `.malformedURI` (URLComponents catches).
    - Test 13: fragment с percent-encoded Cyrillic (`#%D0%9B%D0%B0%D1%82%D0%B2%D0%B8%D1%8F`) → remarks="Латвия" (Phase 1 carry-forward pattern).
  </behavior>
  <action>
Создать `TrojanURIParser.swift` по PATTERNS §2.6 (полный template). Key points:

1. `public struct ParsedTrojan: Sendable, Equatable` со всеми полями из RESEARCH §3.5 (PATTERNS §2.6 — full struct).
2. `public enum TrojanURIError: Error, LocalizedError, Equatable` с case-ами: `.malformedURI`, `.missingPassword`, `.notTLSSecurity(String?)`, `.invalidTransport(String)`.
3. `public enum TrojanURIParser { public static func parse(_ uri: String) throws -> ParsedTrojan }` — pattern из VLESSURIParser:
   - Trim whitespace (поддержка multiline pasteboard).
   - `URLComponents(string:)` для RFC-correct parsing.
   - Scheme проверка (`scheme?.lowercased() == "trojan"`).
   - userinfo → password; host/port required.
   - Query params в dict.
   - `security` defaults to "tls" если absent **OR** explicit reject если present но != "tls" — **CONTEXT D-08 strict reading**: «если security != tls → reject; если missing → reject». Этот таск делает STRICT (Test 7).
   - **R1 принцип**: `allowInsecure` ignored (не throws, парсится и не передаётся дальше).
   - `sni` fallback chain: `q["sni"]` → `q["peer"]` → host.
   - `fingerprint` fallback: `q["fp"]` → `q["fingerprint"]` → "chrome".
   - `alpn` parse CSV → array; default `["h2", "http/1.1"]`.
   - `type` switch: "tcp" → .tcp; "ws" → .ws(path, host) с `path` required (throw если отсутствует или пуст); default "tcp" если absent; "h2", "h2+ws", "grpc" — throws `.invalidTransport(type)`.
   - `remarks` from `comps.fragment?.removingPercentEncoding`.
   - `password.removingPercentEncoding ?? password`.

4. Fixtures:
   - `Fixtures/trojan-ws-user-fixture.txt` — содержит ровно user Trojan URI из CONTEXT (single line).
   - `Fixtures/trojan-tcp-uri.txt` — synthetic TCP Trojan URI.

5. Test loading pattern — PATTERNS §3.5:
   ```swift
   private func loadFixture(_ name: String, ext: String = "txt") -> String { /* same pattern as Phase 1 */ }
   ```

6. Package.swift `ConfigParser` — добавить `resources: [.process("Fixtures")]` в testTarget (если не было).

Reference: RESEARCH §3.1, §3.2, §3.4, §3.5; PATTERNS §2.6; CONTEXT D-08 (strict requirements).
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter TrojanURIParserTests 2>&1 | tail -15</automated>
  </verify>
  <done>13 тестов TrojanURIParserTests зелёные; `grep -c "public struct ParsedTrojan" BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` returns 1; fixture files существуют.</done>
</task>

### Task W1.T4: Create `ImportedServer` / `AnyParsedConfig` shared types + stub URI parsers

<task type="auto">
  <name>Task W1.T4: ImportedServer sumtype + stub parsers (ss/vmess/hy2/wireguard) — D-04</name>
  <files>BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift, BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/StubParsersTests.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/unsupported-ss-uri.txt, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/unsupported-vmess-uri.txt, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/unsupported-hy2-uri.txt, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/unsupported-wireguard-uri.txt</files>
  <action>
**Shared types** в `ImportedServer.swift`:

```swift
import Foundation
import VPNCore  // для ProtocolConfig / ProtocolDiagnostics типов если нужны

public enum AnyParsedConfig: Sendable, Equatable {
    case vlessReality(ParsedVLESS)
    case trojan(ParsedTrojan)
    // Phase 4+ добавит ss, vmess, hy2, wireguard
}

public enum UnsupportedReason: String, Sendable, Equatable {
    case schemaUnsupportedInPhase2  // ss://, vmess://, hy2://, wireguard://, ssh://, socks5://, naive+...://
    case transportUnsupported       // type=h2, h2+ws, grpc для известных схем (vless/trojan)
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
}

public enum ImportSource: Sendable, Equatable {
    case pasteboard
    case subscriptionURL(URL)
    case jsonEndpoint(URL)
    case qrCode
    case multilineText
}
```

**Stub parsers** в `StubParsers.swift` (D-04 — нужны только для извлечения метаданных, чтобы показать пользователю «X конфигов будут включены в следующих версиях»):

```swift
public enum StubParsers {
    /// Parses metadata from any URI scheme that Phase 2 does not handle.
    /// Returns ImportedServer.unsupported with extracted host/port/remark
    /// (or .invalid if URI is malformed beyond URLComponents).
    public static func parseAsUnsupported(_ uri: String) -> ImportedServer {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              let host = comps.host
        else {
            return .invalid(rawURI: trimmed, error: "URLComponents parse failed")
        }
        let port = comps.port ?? defaultPortForScheme(scheme)
        let remark = comps.fragment?.removingPercentEncoding ?? "\(scheme.uppercased()) \(host):\(port)"
        return .unsupported(name: remark, scheme: scheme, host: host, port: port,
                            rawURI: trimmed, reason: .schemaUnsupportedInPhase2)
    }

    private static func defaultPortForScheme(_ s: String) -> Int {
        switch s {
        case "ss": return 8388
        case "vmess": return 443
        case "hy2", "hysteria2": return 443
        case "wireguard": return 51820
        case "ssh": return 22
        case "socks5", "socks": return 1080
        default: return 0
        }
    }

    public static let supportedSchemesInPhase2: Set<String> = ["vless", "trojan"]
    public static let knownSchemes: Set<String> = [
        "vless", "trojan", "ss", "vmess", "hy2", "hysteria2",
        "wireguard", "ssh", "socks5", "socks", "naive+https", "naive+quic"
    ]
}
```

**Тесты** в `StubParsersTests.swift`:
- Test 1: ss URI fixture parses to `.unsupported(scheme: "ss", reason: .schemaUnsupportedInPhase2)`.
- Test 2: vmess URI fixture — same pattern.
- Test 3: hy2 URI fixture — same.
- Test 4: wireguard URI fixture — same.
- Test 5: completely malformed (`"???"` или `"vmess://"` без authority) → `.invalid`.
- Test 6: remark из fragment корректно извлекается с Cyrillic.

**Fixtures** — короткие synthetic URI для каждой схемы (НЕ реальные ключи; для unit-test достаточно `ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.com:8388#Test Server` и т.п.).

Reference: D-04; RESEARCH §6.2 (ImportedServer enum design); PATTERNS §3.5 (fixture organisation).
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter StubParsersTests 2>&1 | tail -15</automated>
  </verify>
  <done>6 тестов StubParsersTests зелёные; types `ImportedServer`, `AnyParsedConfig`, `UnsupportedReason`, `ImportSource` экспортированы (grep `public enum`); 4 fixture файла существуют.</done>
</task>

### Task W1.T5: Create `SubscriptionURLFetcher.swift` + tests (URLSession-mocked)

<task type="auto" tdd="true">
  <name>Task W1.T5: SubscriptionURLFetcher — HTTPS GET with User-Agent BBTB/0.2, format detection (RESEARCH §4.6)</name>
  <files>BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/sub-base64-response.txt, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/sub-plaintext-response.txt, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/sub-json-response.json</files>
  <behavior>
    - Test 1: HTTPS URL → URLSession.shared.data вызывается с User-Agent header `"BBTB/0.2 (iOS / macOS)"` и Accept header `"text/plain, application/json, */*"`. Мокается через URLProtocol subclass.
    - Test 2: `http://` URL → throws `.nonHTTPS("http")` без вызова URLSession.
    - Test 3: HTTP 4xx response → throws `.httpStatusError(404)` или similar; body не возвращается.
    - Test 4: Successful response → `SubscriptionFetchResult(body: Data, metadata: ..., finalURL: url)`.
    - Test 5: Response с `Profile-Title` header → metadata.title = header value.
    - Test 6: Response с base64 body → `detectFormat` returns `.base64URIList`.
    - Test 7: Response с plain-text body `vless://...\ntrojan://...` → `.plainTextURIList`.
    - Test 8: Response с JSON body начинающимся с `{` и `"outbounds":[{"type":"vless"}]` → `.singBoxJSON`.
    - Test 9: Response с V2Ray-style JSON `{"outbounds":[{"protocol":"vless"}]}` → `.v2rayJSON(reason:)`.
    - Test 10: Garbage body → `.unknown(snippet: ...)`.
  </behavior>
  <action>
Создать `SubscriptionURLFetcher.swift` per RESEARCH §4.6 + format detection из §4.2:

```swift
import Foundation

public enum SubscriptionFormat: Sendable, Equatable {
    case base64URIList
    case plainTextURIList
    case singBoxJSON
    case v2rayJSON(reason: String)
    case unknown(snippet: String)
}

public struct SubscriptionMetadata: Sendable, Equatable {
    public let title: String?
    public let updateInterval: Int?  // Phase 3 — на v0.2 nil
    public let userInfo: String?     // Phase 4 — на v0.2 nil
}

public struct SubscriptionFetchResult: Sendable {
    public let body: Data
    public let metadata: SubscriptionMetadata
    public let finalURL: URL
}

public enum SubscriptionURLFetcher {
    public enum FetchError: Error, LocalizedError, Equatable {
        case nonHTTPS(String)
        case notHTTPResponse
        case httpStatusError(Int)
        case malformedURL
        case timeout
        public var errorDescription: String? { /* localized strings via L10n where applicable */ }
    }

    public static func fetch(url: URL, session: URLSession = .shared) async throws -> SubscriptionFetchResult {
        guard url.scheme?.lowercased() == "https" else {
            throw FetchError.nonHTTPS(url.scheme ?? "")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/json, */*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else { throw FetchError.notHTTPResponse }
        guard (200..<300).contains(httpResp.statusCode) else { throw FetchError.httpStatusError(httpResp.statusCode) }

        let title = extractTitle(from: httpResp.allHeaderFields)
        let metadata = SubscriptionMetadata(title: title, updateInterval: nil, userInfo: nil)
        return SubscriptionFetchResult(body: data, metadata: metadata, finalURL: httpResp.url ?? url)
    }

    private static func extractTitle(from headers: [AnyHashable: Any]) -> String? {
        let keys = ["Profile-Title", "profile-title"]
        for k in keys {
            if let v = headers[k] as? String { return decodeMaybeBase64(v) }
        }
        return nil
    }
    private static func decodeMaybeBase64(_ s: String) -> String {
        if s.hasPrefix("base64:"), let data = Data(base64Encoded: String(s.dropFirst(7))),
           let decoded = String(data: data, encoding: .utf8) { return decoded }
        return s
    }

    public static func detectFormat(body: Data) -> SubscriptionFormat {
        /* full algorithm per RESEARCH §4.2:
           1. JSON if starts with `{`
              - check outbounds[].type → singBoxJSON
              - check outbounds[].protocol → v2rayJSON
           2. URI prefix → plainTextURIList
           3. Base64 attempt → base64URIList
           4. else unknown */
    }
}
```

**Test harness:** subclass `URLProtocol` для mocking URLSession без реальной сети:
```swift
final class MockURLProtocol: URLProtocol {
    static var responder: ((URLRequest) -> (Data, HTTPURLResponse))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let responder = Self.responder else { fatalError("MockURLProtocol.responder not set") }
        let (data, response) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
// In tests:
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let session = URLSession(configuration: config)
```

**Fixtures**:
- `Fixtures/sub-base64-response.txt` — base64 от двух URI (vless + trojan).
- `Fixtures/sub-plaintext-response.txt` — 6 строк URI из CONTEXT `<specifics>` (4 VLESS + 2 Trojan).
- `Fixtures/sub-json-response.json` — sing-box config с outbounds=[vless, trojan, selector, direct].

Reference: RESEARCH §4.1, §4.2, §4.3, §4.4, §4.6; CONTEXT D-02; Claude's Discretion (User-Agent format).
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter SubscriptionURLFetcherTests 2>&1 | tail -20</automated>
  </verify>
  <done>10 тестов SubscriptionURLFetcherTests зелёные; реальная сеть не вызывается (все через MockURLProtocol); 3 fixture файла существуют.</done>
</task>

### Task W1.T6: Create `JSONEndpointFetcher.swift` (thin variant of SubscriptionURLFetcher)

<task type="auto" tdd="true">
  <name>Task W1.T6: JSONEndpointFetcher — same as Subscription but Accept: application/json + post-fetch validate</name>
  <files>BBTB/Packages/ConfigParser/Sources/ConfigParser/JSONEndpointFetcher.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/JSONEndpointFetcherTests.swift</files>
  <behavior>
    - Test 1: HTTPS JSON endpoint → fetch returns Data; body parseable as `[String: Any]`.
    - Test 2: Non-JSON response body → throws `.notJSON("got plain text starting with 'vless://...'")`.
    - Test 3: HTTPS URL with self-signed cert (simulated via MockURLProtocol responding with error) → throws `.fetchFailed(...)`.
    - Test 4: HTTP URL → throws `.nonHTTPS("http")`.
  </behavior>
  <action>
Per RESEARCH §5 — JSONEndpointFetcher технически тот же URL fetcher, но header `Accept: application/json` и post-fetch sanity check.

**Architecture note (RESEARCH §5.2):** JSONEndpointFetcher и SubscriptionURLFetcher можно было бы объединить в один тип — но D-02 явно различает три формата, и в UI feedback для пользователя различение полезно. Оставляем отдельным namespace для читаемости; реализация переиспользует MockURLProtocol harness из W1.T5.

```swift
public enum JSONEndpointFetcher {
    public enum FetchError: Error, LocalizedError, Equatable {
        case nonHTTPS(String)
        case notJSON(String)  // snippet
        case httpStatusError(Int)
        case fetchFailed(String)  // underlying error description
    }
    public static func fetch(url: URL, session: URLSession = .shared) async throws -> Data {
        // 1. HTTPS guard
        // 2. URLSession.data with Accept: application/json header + User-Agent BBTB/0.2
        // 3. Status code check
        // 4. Sanity check: trimmed body starts with `{` else throw .notJSON
        // 5. Return Data (caller сделает SingBoxConfigLoader.validate + extractServers)
    }
}
```

**Не делать в этом таске:** валидацию body через `SingBoxConfigLoader.validate` — это происходит в UniversalImportParser (W1.T7) или в ConfigImporter (W3). JSONEndpointFetcher только fetches + проверяет «похоже на JSON».

Reference: RESEARCH §5.1, §5.2.
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter JSONEndpointFetcherTests 2>&1 | tail -10</automated>
  </verify>
  <done>4 теста JSONEndpointFetcherTests зелёные; реальная сеть не вызывается.</done>
</task>

### Task W1.T7: Create `UniversalImportParser.swift` (facade) + tests

<task type="auto" tdd="true">
  <name>Task W1.T7: UniversalImportParser — classify and dispatch to sub-parsers/fetchers (RESEARCH §6)</name>
  <files>BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/UniversalImportParserTests.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/multi-line-mixed.txt</files>
  <behavior>
    - Test 1: Empty input → throws `.empty`.
    - Test 2: Single VLESS URI string → `ImportResult(supported: [.supported(.vlessReality(_))], unsupported: [], failed: [], subscriptionURL: nil, source: .pasteboard)`.
    - Test 3: Single Trojan URI string → same shape with `.trojan(_)`.
    - Test 4: Single ss:// URI → `ImportResult(supported: [], unsupported: [.unsupported(scheme:"ss",...)], failed: [], ...)`.
    - Test 5 (real user fixture): multi-line block из CONTEXT `<specifics>` (4 VLESS + 2 Trojan) → 6 supported entries, 0 unsupported, 0 failed.
    - Test 6: multi-line с 5 valid URI + 1 garbage line `"hello world"` → 5 supported + 0 unsupported + 1 invalid (no whole-import abort, per RESEARCH §6.4).
    - Test 7: HTTPS URL string (mocked subscription returning base64 of 2 URI) → 2 supported entries, `subscriptionURL: .some(url)`, `source: .subscriptionURL(url)`.
    - Test 8: HTTPS URL with JSON response (sing-box config with vless+trojan outbounds + selector) → extracts servers via embedded JSON parser; supported = 2 entries (vless + trojan); selector/direct skipped.
    - Test 9: HTTPS URL responding с V2Ray JSON (outbounds[].protocol field) → throws `.v2rayJSONUnsupported` ИЛИ returns ImportResult с все unsupported (предложение — throws более понятно для UX).
    - Test 10: Single URI с trailing newline и whitespace → trimmed and parsed correctly.
    - Test 11: Base64-encoded URI list (no URL, прямо в pasteboard) → парсится через base64 fallback.
  </behavior>
  <action>
Per RESEARCH §6 (full architecture):

```swift
public struct ImportResult: Sendable {
    public let supported: [ImportedServer]
    public let unsupported: [ImportedServer]
    public let failed: [ImportedServer]  // .invalid cases
    public let subscriptionURL: String?
    public let source: ImportSource
    public let metadata: SubscriptionMetadata?
}

public enum UniversalImportError: Error, LocalizedError, Equatable {
    case empty
    case unknownInputFormat(snippet: String)
    case fetchFailed(String)
    case v2rayJSONUnsupported
    case noValidEntries
    public var errorDescription: String? { /* via L10n */ }
}

public actor UniversalImportParser {
    public init() {}

    public func `import`(rawInput: String, source: ImportSource = .pasteboard) async throws -> ImportResult {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UniversalImportError.empty }

        let classification = classify(trimmed)
        switch classification {
        case .subscriptionURL(let url):
            return try await fetchAndParseSubscription(url: url)
        case .singBoxJSON(let body):
            return try parseSingBoxJSON(body, source: source, subscriptionURL: nil)
        case .v2rayJSON:
            throw UniversalImportError.v2rayJSONUnsupported
        case .singleURI(let uri):
            return parseSingleURI(uri, source: source)
        case .multilineURIList(let lines):
            return parseMultiline(lines, source: source, subscriptionURL: nil)
        case .base64URIList(let decoded):
            let lines = decoded.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            return parseMultiline(lines, source: source, subscriptionURL: nil)
        case .unknown(let snippet):
            throw UniversalImportError.unknownInputFormat(snippet: snippet)
        }
    }

    enum InputClass {
        case singleURI(String); case multilineURIList([String])
        case subscriptionURL(URL); case singBoxJSON(String); case v2rayJSON(reason: String)
        case base64URIList(String); case unknown(snippet: String)
    }

    func classify(_ trimmed: String) -> InputClass {
        // Implement RESEARCH §6.3 algorithm exactly:
        //   1. HTTPS URL?
        //   2. Starts with `{`? → sing-box vs v2ray JSON
        //   3. Starts with known URI scheme? → single vs multi-line
        //   4. base64 attempt
        //   5. unknown
    }

    private func parseSingleURI(_ uri: String, source: ImportSource) -> ImportResult {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = trimmed.split(separator: ":").first.map { String($0).lowercased() } ?? ""

        switch scheme {
        case "vless":
            do {
                let parsed = try VLESSURIParser.parse(trimmed)
                let name = parsed.remarks ?? "\(parsed.host):\(parsed.port)"
                return ImportResult(supported: [.supported(name: name, parsed: .vlessReality(parsed), rawURI: trimmed)],
                                    unsupported: [], failed: [], subscriptionURL: nil, source: source, metadata: nil)
            } catch {
                return ImportResult(supported: [], unsupported: [], failed: [.invalid(rawURI: trimmed, error: error.localizedDescription)],
                                    subscriptionURL: nil, source: source, metadata: nil)
            }
        case "trojan":
            // analogous via TrojanURIParser
        default:
            // unknown known scheme → StubParsers.parseAsUnsupported
            // unknown unknown scheme → .invalid
            let stub = StubParsers.parseAsUnsupported(trimmed)
            if case .unsupported = stub {
                return ImportResult(supported: [], unsupported: [stub], failed: [], subscriptionURL: nil, source: source, metadata: nil)
            } else {
                return ImportResult(supported: [], unsupported: [], failed: [stub], subscriptionURL: nil, source: source, metadata: nil)
            }
        }
    }

    private func parseMultiline(_ lines: [String], source: ImportSource, subscriptionURL: String?) -> ImportResult {
        var sup: [ImportedServer] = []; var unsup: [ImportedServer] = []; var failed: [ImportedServer] = []
        for line in lines {
            let r = parseSingleURI(line, source: source)
            sup.append(contentsOf: r.supported)
            unsup.append(contentsOf: r.unsupported)
            failed.append(contentsOf: r.failed)
        }
        return ImportResult(supported: sup, unsupported: unsup, failed: failed,
                            subscriptionURL: subscriptionURL, source: source, metadata: nil)
    }

    private func fetchAndParseSubscription(url: URL) async throws -> ImportResult {
        let fetchResult = try await SubscriptionURLFetcher.fetch(url: url)
        let format = SubscriptionURLFetcher.detectFormat(body: fetchResult.body)
        let bodyStr = String(data: fetchResult.body, encoding: .utf8) ?? ""
        switch format {
        case .base64URIList:
            // decode base64, split lines, recurse via parseMultiline
        case .plainTextURIList:
            let lines = bodyStr.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            var r = parseMultiline(lines, source: .subscriptionURL(url), subscriptionURL: url.absoluteString)
            return ImportResult(supported: r.supported, unsupported: r.unsupported, failed: r.failed,
                                subscriptionURL: url.absoluteString,
                                source: .subscriptionURL(url),
                                metadata: fetchResult.metadata)
        case .singBoxJSON:
            return try parseSingBoxJSON(bodyStr, source: .subscriptionURL(url), subscriptionURL: url.absoluteString)
        case .v2rayJSON:
            throw UniversalImportError.v2rayJSONUnsupported
        case .unknown(let snippet):
            throw UniversalImportError.unknownInputFormat(snippet: snippet)
        }
    }

    private func parseSingBoxJSON(_ body: String, source: ImportSource, subscriptionURL: String?) throws -> ImportResult {
        // Per RESEARCH §5.3 extractServers:
        // 1. JSONSerialization → root dict.
        // 2. root["outbounds"] as [[String: Any]].
        // 3. For each outbound where type ∈ {vless, trojan}: try to reconstruct ParsedVLESS / ParsedTrojan from fields (or wrap rawOutboundJSON as supported with .vlessReality/.trojan AnyParsedConfig). For unsupported types (ss, vmess, ...): create .unsupported. Skip {direct, block, dns, selector, urltest, ssh}.
        // 4. Return ImportResult.
        //
        // Phase 2 simplification: ImportedServer для sing-box JSON path содержит .vlessReality(ParsedVLESS) ИЛИ .trojan(ParsedTrojan) — придётся выкладывать поля из JSON в Parsed* struct. ИЛИ — добавить третий case в AnyParsedConfig: .rawSingBoxOutbound(json: String, scheme: String) для случая «JSON pre-built operator config». Выбираю **первый вариант** для consistency: парсим vless/trojan outbound block → fields → Parsed*; unsupported outbound types → .unsupported. Это даёт единый pipeline для все 3 форматов.
    }
}
```

**Fixture:** `multi-line-mixed.txt` — exact 6 URI из CONTEXT `<specifics>` lines 261–268 (sanitized public keys / passwords допустимы, real user fixture).

Reference: RESEARCH §6.1–§6.5, §5.3.
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter UniversalImportParserTests 2>&1 | tail -20</automated>
  </verify>
  <done>11 тестов UniversalImportParserTests зелёные; multi-line fixture с 6 user URI парсится как 6 supported entries; subscription URL mock возвращает корректный ImportResult с `subscriptionURL: .some(url)`.</done>
</task>

### Task W1.T8: Create `PoolBuilder.swift` + tests (urltest assembly)

<task type="auto" tdd="true">
  <name>Task W1.T8: PoolBuilder — собирает N outbounds + urltest selector + dns/route → single sing-box JSON (RESEARCH §1, §6.5)</name>
  <files>BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift</files>
  <behavior>
    - Test 1: 2 ParsedVLESS + 1 ParsedTrojan → output JSON содержит 3 outbound objects (vless-0, vless-1, trojan-2) + urltest-out (outbounds=[vless-0, vless-1, trojan-2]) + direct. route.final="urltest-out". dns.servers[detour]="urltest-out".
    - Test 2: 1 supported server (degenerate case, RESEARCH §6.5 single-server special) → output НЕ содержит urltest; route.final = tag первого outbound; dns.detour = тот же tag.
    - Test 3: 0 supported → throws `.noSupportedServers`.
    - Test 4 (validate self-check): output W1.T8 passes `SingBoxConfigLoader.validate(json:)` для multi-server case.
    - Test 5: urltest config keys — `url`="https://cp.cloudflare.com/generate_204", `interval`="1m", `tolerance`=50, `idle_timeout`="30m", `interrupt_exist_connections`=false (RESEARCH §1.4 recommendations).
    - Test 6: tags — детерминированно `vless-{index}`, `trojan-{index}` где index — позиция в input array.
    - Test 7 (>50 servers): если input > 50 supported → берутся первые 50 (RESEARCH §9.5 256KB iOS limit mitigation).
  </behavior>
  <action>
Per RESEARCH §1, §6.5, §9.5:

```swift
public enum PoolBuilder {
    public enum PoolError: Error, LocalizedError, Equatable {
        case noSupportedServers
        case serialisationFailed(String)
    }

    /// Builds a sing-box configuration JSON from N supported servers.
    /// - For ≥2 supported servers: outbounds + urltest selector + direct + dns/route.
    /// - For 1 supported server: degenerate config — no urltest, route.final = single outbound tag.
    /// - For 0 supported: throws .noSupportedServers.
    public static func buildSingBoxJSON(
        from supportedConfigs: [AnyParsedConfig]
    ) throws -> String {
        let truncated = Array(supportedConfigs.prefix(50))  // RESEARCH §9.5 — iOS 256KB limit
        guard !truncated.isEmpty else { throw PoolError.noSupportedServers }

        var outbounds: [[String: Any]] = []
        var tags: [String] = []
        for (index, parsed) in truncated.enumerated() {
            let tag: String
            let outbound: [String: Any]
            switch parsed {
            case .vlessReality(let v):
                tag = "vless-\(index)"
                outbound = buildVLESSOutbound(parsed: v, tag: tag)
            case .trojan(let t):
                tag = "trojan-\(index)"
                outbound = buildTrojanOutbound(parsed: t, tag: tag)
            }
            outbounds.append(outbound)
            tags.append(tag)
        }

        let finalTag: String
        if truncated.count == 1 {
            finalTag = tags[0]  // degenerate case — direct route.final
        } else {
            finalTag = "urltest-out"
            let urltest: [String: Any] = [
                "type": "urltest",
                "tag": "urltest-out",
                "outbounds": tags,
                "url": "https://cp.cloudflare.com/generate_204",  // CONTEXT Claude's Discretion; RESEARCH §1.5
                "interval": "1m",                                  // RESEARCH §1.4 recommendation
                "tolerance": 50,                                   // RESEARCH §1.4
                "idle_timeout": "30m",                             // RESEARCH §1.4
                "interrupt_exist_connections": false                // RESEARCH §1.4 — не дропаем active streams
            ]
            outbounds.append(urltest)
        }
        outbounds.append(["type": "direct", "tag": "direct"])

        let root: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "dns": dnsBlock(detour: finalTag),  // RESEARCH §1.6 — detour goes to urltest или single outbound
            "outbounds": outbounds,
            "route": [
                "rules": [
                    ["action": "sniff", "timeout": "1s"],
                    ["protocol": "dns", "action": "hijack-dns"]
                ],
                "final": finalTag,
                "auto_detect_interface": true
            ],
            "experimental": [:]
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw PoolError.serialisationFailed("UTF-8 encode")
        }
        return json
    }

    private static func buildVLESSOutbound(parsed: ParsedVLESS, tag: String) -> [String: Any] {
        // Construct sing-box vless outbound dict from ParsedVLESS fields.
        // Mirror SingBoxConfigTemplate.vless-reality.json structure for outbound object only.
        // Include: type="vless", tag, server, server_port, uuid, flow,
        //          tls={enabled:true, server_name:sni, utls={enabled:true, fingerprint:fp}, reality={enabled:true, public_key, short_id}}
    }
    private static func buildTrojanOutbound(parsed: ParsedTrojan, tag: String) -> [String: Any] {
        // type="trojan", tag, server, server_port, password, network="tcp",
        // tls={enabled:true, server_name:sni, insecure:false, alpn:[h2, http/1.1], utls={enabled:true, fingerprint}},
        // transport (only if .ws): {type:"ws", path, headers:{Host: wsHost}}
    }

    private static func dnsBlock(detour: String) -> [String: Any] {
        // Identical to PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json dns block,
        // but constructed in code. dns.servers[0].detour = detour parameter.
        // Per RESEARCH §1.6 — dns-remote.detour points to urltest-out (or single outbound tag in degenerate case).
    }
}
```

**Critical R1 invariant:** PoolBuilder generates `experimental: {}` (empty), `insecure: false` for all TLS blocks, no clash_api, no v2ray_api, no cache_file. Output passes `SingBoxConfigLoader.validate(json:)` — Test 4.

**Architecture invariant (PATTERNS §3.6):** PoolBuilder в ConfigParser package — ConfigParser НЕ depends on PacketTunnelKit. Поэтому buildVLESSOutbound / buildTrojanOutbound строят dictionaries in-code, **не** загружают template из bundle. dnsBlock тоже хардкодит структуру (cloudflare DoH + yandex bootstrap + fakeip — matching Phase 1 template). Это дублирование с VLESSReality/ConfigBuilder, но обоснованное: PoolBuilder и ConfigBuilder обслуживают разные шкалы (1 outbound в template vs N outbounds в pool).

**Не делать в этом таске:** call `SingBoxConfigLoader.validate` внутри PoolBuilder — это вернёт circular dependency. validate вызывается в ConfigImporter (W3) ПОСЛЕ PoolBuilder.

Reference: RESEARCH §1.1, §1.4, §1.5, §1.6, §6.5, §9.5; PATTERNS §3.6 (architecture invariant).
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter PoolBuilderTests 2>&1 | tail -20</automated>
  </verify>
  <done>7 тестов PoolBuilderTests зелёные; output для multi-server case проходит external `SingBoxConfigLoader.validate(json:)` (test 4); degenerate single-server case не содержит urltest (test 2); ConfigParser package всё ещё **не depends** on PacketTunnelKit (`grep -c "PacketTunnelKit" BBTB/Packages/ConfigParser/Package.swift` returns 0).</done>
</task>

### Task W1.T9: Update `ConfigParser/Package.swift` + Wave 1 regression check

<task type="auto">
  <name>Task W1.T9: ConfigParser Package.swift update + full Wave 1 regression check</name>
  <files>BBTB/Packages/ConfigParser/Package.swift</files>
  <action>
1. Обновить `ConfigParser/Package.swift`:
   - Если testTarget не имеет `resources: [.process("Fixtures")]` — добавить (для всех новых fixture файлов из W1.T3-T7).
   - Dependency остаётся **только** `VPNCore` (PATTERNS §3.6 invariant). НЕ добавлять `PacketTunnelKit` — validate вызывается в orchestration layer.
   - Если нужен `Trojan` package для re-use Parsed types — НЕ нужен; `ParsedTrojan` живёт в ConfigParser (W1.T3), а `Trojan/ConfigBuilder.swift` импортирует ConfigParser если нужно (в Phase 2 Trojan/ConfigBuilder работает напрямую с TrojanInputs, не с ParsedTrojan — поэтому depends остаётся симметричным VLESSReality).

2. Wave 1 regression check:

```bash
cd BBTB/Packages/ConfigParser && swift test 2>&1 | tail -10
cd BBTB/Packages/Protocols/Trojan && swift test 2>&1 | tail -10
# Phase 1 packages — должны быть зелёные (W0 regression already verified)
cd BBTB/Packages/VPNCore && swift test 2>&1 | tail -3
cd BBTB/Packages/KillSwitch && swift test 2>&1 | tail -3
cd BBTB/Packages/PacketTunnelKit && swift test 2>&1 | tail -3
cd BBTB/Packages/Protocols/VLESSReality && swift test 2>&1 | tail -3
```

**Commit message templates для Wave 1:**

```
feat(02/w1): create Trojan protocol package — handler + 2 sing-box templates (PROTO-02 foundation)

Mirror Packages/Protocols/VLESSReality/ layout. Two templates: trojan-tcp.json,
trojan-ws.json. Все user-specific fields параметризованы placeholders (Phase 1 W5
learning). R1: insecure=false hardcoded, allowInsecure URI param ignored.

(02-W1.T1)
```

```
feat(02/w1): Trojan ConfigBuilder + tests (D-08, RESEARCH §2.6)

ConfigBuilder.TrojanInputs → sing-box JSON via template substitution + mutatePort.
7 tests including real user fixture (LN8x95.../vpn.vergevsky.ru). All call
SingBoxConfigLoader.validate as R1 self-test.

(02-W1.T2)
```

```
feat(02/w1): TrojanURIParser + 13 tests with real user fixture (D-08, RESEARCH §3)

Parse trojan://password@host:port?security=tls&type=ws&path=...&sni=... per
trojan-go spec + Clash extensions. allowInsecure ignored (R1). sni/peer fallback chain.

(02-W1.T3)
```

```
feat(02/w1): ImportedServer sumtype + StubParsers for ss/vmess/hy2/wireguard (D-04)

Unsupported URI schemes parse to ImportedServer.unsupported with extracted
host:port/remark. UI shows "X working, Y will be enabled in future versions".

(02-W1.T4)
```

```
feat(02/w1): SubscriptionURLFetcher — HTTPS GET with BBTB/0.2 UA + format detection (RESEARCH §4)

URLSession.shared.data; HTTPS-only (R1-spirit, http:// reject). Detects body
format: base64 / plain-text / sing-box JSON / V2Ray JSON / unknown.
Profile-Title header parsed for pool display name (Hiddify metadata).
URLProtocol mocking harness for tests — no live network.

(02-W1.T5)
```

```
feat(02/w1): JSONEndpointFetcher + UniversalImportParser facade (D-02, RESEARCH §6)

UniversalImportParser actor classifies any raw input (single URI / multi-line /
HTTPS URL / JSON / base64) and dispatches. Per-URI failures don't abort whole
import (RESEARCH §6.4). 11 tests including 6-URI user fixture.

(02-W1.T6, 02-W1.T7)
```

```
feat(02/w1): PoolBuilder — assemble N outbounds + urltest selector (PROTO-10, RESEARCH §1, §6.5)

urltest with cp.cloudflare.com/generate_204 probe, 1m interval, 50ms tolerance.
Degenerate single-server case skips urltest (route.final = single outbound).
Caps at 50 outbounds for iOS 256KB providerConfiguration limit. R1: insecure=false
on every outbound. ConfigParser package still has no dependency on PacketTunnelKit
(architecture invariant).

(02-W1.T8, 02-W1.T9)
```
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test 2>&1 | tail -5 && cd ../Protocols/Trojan && swift test 2>&1 | tail -5</automated>
  </verify>
  <done>ConfigParser package — все тесты зелёные (включая existing VLESSURIParser + новые Trojan/Stub/Subscription/JSONEndpoint/Universal/Pool тесты); Trojan package — все 7 тестов зелёные; ни один Phase 1 package не упал в regression.</done>
</task>

---

## Wave 2 — Register Trojan handler + dual-protocol smoke

**Goal:** Включить TrojanHandler в ProtocolRegistry на обеих платформах + добавить end-to-end smoke test, что Trojan URI → ParsedTrojan → buildSingBoxJSON → validate → готовый к provision JSON. Реальный device run ещё не делаем (это W5 UAT).

**Dependencies:** W1 (Trojan package + ConfigParser components).

**Wave commit count:** 1–2.

### Task W2.T1: Register `TrojanHandler.self` in both app entry points

<task type="auto">
  <name>Task W2.T1: ProtocolRegistry.register(TrojanHandler.self) in iOS + macOS App.init</name>
  <files>BBTB/App/iOSApp/BBTB_iOSApp.swift, BBTB/App/macOSApp/BBTB_macOSApp.swift</files>
  <action>
В `init()` обоих app entry points добавить регистрацию TrojanHandler сразу после VLESSRealityHandler (PATTERNS §2.28, §2.29):

```swift
// BBTB_iOSApp.swift init():
CrashReporter.shared.install()
// ... existing log export setup ...

// CORE-02: регистрируем протоколы
ProtocolRegistry.shared.register(VLESSRealityHandler.self)
ProtocolRegistry.shared.register(TrojanHandler.self)    // ← NEW Phase 2

// ... rest of init ...
```

Тот же patch в `BBTB_macOSApp.swift`.

`import Trojan` в начало файла обоих апов.

**Не делать в этом таске:** NavigationStack wrapping, Settings Scene, MainScreenView changes — это всё в W4.T9 (App entry refactor).

**Tuist:** добавление Trojan dependency в targets — отложено до W4.T9 (Project.swift extension). Этот таск чисто Swift code change.

**ВАЖНО — этот commit может временно не компилироваться** без Tuist regen. Потому что main app target пока не depends на Trojan package в Project.swift. Опционально: planner/executor может комбинировать этот commit с W4.T9 (Tuist + app entry в одном коммите). **Рекомендую сделать оба изменения в одном коммите** чтобы main app target оставался compilable.

ИЛИ — выполнить W4.T9 (Tuist update Trojan dependency only) ПЕРЕД W2.T1. Executor должен выбрать что удобнее. Зафиксировать выбор в commit message.

Reference: PATTERNS §2.28, §2.29; CONTEXT integration points line 237.
  </action>
  <verify>
    <automated>grep -c "ProtocolRegistry.shared.register(TrojanHandler.self)" BBTB/App/iOSApp/BBTB_iOSApp.swift BBTB/App/macOSApp/BBTB_macOSApp.swift</automated>
  </verify>
  <done>оба App-файла содержат `register(TrojanHandler.self)` ровно 1 раз; `import Trojan` присутствует в обоих.</done>
</task>

### Task W2.T2: Dual-protocol smoke integration test

<task type="auto" tdd="true">
  <name>Task W2.T2: Integration test — multi-line URI block → ImportResult → PoolBuilder → validate green</name>
  <files>BBTB/Packages/ConfigParser/Tests/ConfigParserTests/DualProtocolSmokeTests.swift</files>
  <behavior>
    - Test 1: parse multi-line block (1 VLESS + 1 Trojan-WS URI, synthetic but well-formed) через UniversalImportParser → ImportResult(supported.count = 2). Map supported entries → AnyParsedConfig array → PoolBuilder.buildSingBoxJSON. Output passes `SingBoxConfigLoader.validate(json:)` (R1).
    - Test 2: same, но 1 VLESS + 1 Trojan + 1 ss:// → ImportResult(supported.count=2, unsupported.count=1, failed=0). PoolBuilder вызывается только с supported (2 servers) → valid pool config.
    - Test 3: single Trojan URI → ImportResult(supported.count=1). PoolBuilder с single config → degenerate route.final="trojan-0", no urltest in output. Passes validate.
    - Test 4: только unsupported URI (ss + vmess) → ImportResult(supported.count=0, unsupported.count=2). PoolBuilder throws `.noSupportedServers`.
  </behavior>
  <action>
Integration test в `ConfigParserTests` который соединяет компоненты W1 (Universal parser → PoolBuilder → external validate). Это **smoke test**, **не** unit test — он проверяет что pieces wire вместе.

```swift
import XCTest
import PacketTunnelKit  // для SingBoxConfigLoader.validate в этом тесте — OK для test target
@testable import ConfigParser

final class DualProtocolSmokeTests: XCTestCase {
    func test_multiline_vless_trojan_buildsValidPoolConfig() async throws {
        let input = """
        vless://uuid@host:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=example.com&fp=chrome&pbk=abc&sid=ef#VLESS-1
        trojan://pwd@host2:2087?security=tls&type=ws&path=/p&sni=example.com#Trojan-1
        """
        let parser = UniversalImportParser()
        let result = try await parser.import(rawInput: input, source: .pasteboard)
        XCTAssertEqual(result.supported.count, 2)
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertEqual(result.failed.count, 0)

        let configs = result.supported.compactMap { server -> AnyParsedConfig? in
            if case let .supported(_, parsed, _) = server { return parsed }
            return nil
        }
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
        XCTAssertTrue(json.contains("\"type\":\"urltest\"") || json.contains("\"type\": \"urltest\""))
    }
    // ... + Tests 2/3/4 ...
}
```

**Architecture note:** этот test target — `ConfigParserTests` — может зависеть от `PacketTunnelKit` (через testTarget dependency add). Это **не** нарушает PATTERNS §3.6 (architecture invariant запрещает только **production** ConfigParser→PacketTunnelKit dep). Test target depends на PacketTunnelKit для R1 validation в integration tests — acceptable.

Если testTarget dep на PacketTunnelKit ещё нет — добавить в `ConfigParser/Package.swift`:
```swift
.testTarget(
    name: "ConfigParserTests",
    dependencies: ["ConfigParser", "PacketTunnelKit"],  // ← добавить PacketTunnelKit
    resources: [.process("Fixtures")]
)
```

Reference: PATTERNS §3.6 (test target exception); RESEARCH §6.5 (PoolBuilder usage).
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter DualProtocolSmokeTests 2>&1 | tail -10</automated>
  </verify>
  <done>4 теста DualProtocolSmokeTests зелёные; PoolBuilder output для multi-server case проходит validate; для single-server case route.final = single tag.</done>
</task>

---

## Wave 3 — Universal Import pipeline + ConfigImporter rewrite + ViewModel

**Goal:** Переписать `ConfigImporter` под массив `ServerConfig` + universal parser + kill switch flag из UserDefaults. Переписать `MainScreenViewModel` под новую state semantics (.empty/.idle/.connecting/.connected/.error, активный сервер label, reconnect banner flag). `TunnelController` минимально меняется (load all → update first → save → load — D-01).

**Dependencies:** W0 (KillSwitch new signature, ServerConfig new fields), W1 (UniversalImportParser, PoolBuilder, ImportedServer), W2 (TrojanHandler registered).

**Wave commit count:** 3–4.

### Task W3.T1: Rewrite `ConfigImporter.swift`

<task type="auto" tdd="true">
  <name>Task W3.T1: ConfigImporter rewrite — multi-server pipeline + UniversalImportParser + KILL-03 flag (RESEARCH §9.6, PATTERNS §2.21)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift, BBTB/Packages/AppFeatures/Tests/AppFeaturesTests/ConfigImporterTests.swift</files>
  <behavior>
    - Test 1: importFromRawInput с single VLESS URI string → ImportResult.supported.count=1; в SwiftData появляется 1 ServerConfig с isSupported=true, protocolID="vless-reality", keychainTag != nil.
    - Test 2: importFromRawInput с multi-line VLESS+Trojan + ss URI → 3 ServerConfig rows: 2 с isSupported=true (vless + trojan), 1 с isSupported=false (ss); keychainTag nil для unsupported row; outboundJSON для supported не пустой.
    - Test 3: import с subscription URL (mocked) → ServerConfig rows имеют `subscriptionURL` field set.
    - Test 4: re-import того же subscription URL → existing rows для этого URL УДАЛЯЮТСЯ из SwiftData (replace-pool, D-07); новые rows из ответа сохраняются; Keychain entries для удалённых rows удалены.
    - Test 5: после import, NETunnelProviderManager.protocolConfiguration.providerConfiguration["configJSON"] содержит pool JSON (для multi-supported) или single-outbound JSON (для 1 supported).
    - Test 6: UserDefaults `app.bbtb.killSwitchEnabled = false` (set before import) → KillSwitch.apply вызывается с enabled=false. Mock NETunnelProviderProtocol → includeAllNetworks=false; enforceRoutes=false.
    - Test 7: UserDefaults absent (no key) → defaults to true; KillSwitch.apply called with enabled=true.
    - Test 8: import с 0 supported configs (только ss) → throws `.noSupportedServers` ИЛИ возвращает ImportResult с warning; **не** сохраняет в SwiftData unsupported rows; **не** вызывает provision manager.
    - Test 9 (Phase 1 backwards compat): `importFromPasteboard()` остаётся public, вызывает importFromRawInput(pasteboard.string).
  </behavior>
  <action>
Per RESEARCH §9.6 + PATTERNS §2.21 invariants. Сохранить:
1. Class signature `public final class ConfigImporter: ConfigImporting, @unchecked Sendable`.
2. Pipeline order: parse → keychain save → SwiftData save → NETunnelProviderManager save → loadFromPreferences.
3. `save → loadFromPreferences after save` pattern (Phase 1 RESEARCH §1).
4. `KillSwitch.apply(to: proto, enabled: ...)` (W0.T2 signature) — единственный call site.

Изменения:

```swift
public protocol ConfigImporting: Sendable {
    func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult
    func importFromPasteboard() async throws -> ImportResult  // convenience wrapper, reads pasteboard, calls importFromRawInput
    func importFromQRCode(_ scanned: String) async throws -> ImportResult  // calls importFromRawInput with source: .qrCode
}

public final class ConfigImporter: ConfigImporting, @unchecked Sendable {
    private let modelContext: ModelContext
    private let parser: UniversalImportParser

    public init(modelContext: ModelContext, parser: UniversalImportParser = UniversalImportParser()) {
        self.modelContext = modelContext
        self.parser = parser
    }

    public func importFromRawInput(_ raw: String, source: ImportSource = .pasteboard) async throws -> ImportResult {
        // 1. Parse
        let result = try await parser.import(rawInput: raw, source: source)
        guard !result.supported.isEmpty else {
            throw ImporterError.noSupportedServers
        }

        // 2. Replace-pool semantics (D-07)
        if let subURL = result.subscriptionURL {
            try await deleteExistingPool(subscriptionURL: subURL)
        } else {
            // Single-paste / multi-line / QR — Phase 2: replace entire active pool
            // (Server-list UI Phase 3 will allow merge/append).
            try await deleteAllExistingConfigs()
        }

        // 3. Persist each ImportedServer to SwiftData + Keychain
        var savedConfigs: [ServerConfig] = []
        for server in result.supported {
            let cfg = try await persistSupported(server, subscriptionURL: result.subscriptionURL)
            savedConfigs.append(cfg)
        }
        for server in result.unsupported {
            try await persistUnsupported(server, subscriptionURL: result.subscriptionURL)
            // No Keychain entry — keychainTag remains nil.
        }
        try modelContext.save()

        // 4. Build pool config JSON
        let supportedParsed = result.supported.compactMap { srv -> AnyParsedConfig? in
            if case let .supported(_, parsed, _) = srv { return parsed }; return nil
        }
        let poolJSON = try PoolBuilder.buildSingBoxJSON(from: supportedParsed)

        // 5. R1 self-validate
        try SingBoxConfigLoader.validate(json: poolJSON)

        // 6. Provision NETunnelProviderManager
        try await provisionTunnelProfile(configJSON: poolJSON)

        return result
    }

    public func importFromPasteboard() async throws -> ImportResult {
        let raw = readPasteboard()  // existing #if os(iOS)/macOS pattern from Phase 1
        guard !raw.isEmpty else { throw ImporterError.emptyPasteboard }
        return try await importFromRawInput(raw, source: .pasteboard)
    }

    public func importFromQRCode(_ scanned: String) async throws -> ImportResult {
        return try await importFromRawInput(scanned, source: .qrCode)
    }

    private func provisionTunnelProfile(configJSON: String) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = TunnelBundleIdentifiers.current  // Phase 1 constant
        proto.serverAddress = "BBTB"
        var providerConfig = proto.providerConfiguration ?? [:]
        providerConfig["configJSON"] = configJSON
        proto.providerConfiguration = providerConfig

        // D-14: read UserDefaults flag, default true
        let enabled = UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true
        KillSwitch.apply(to: proto, enabled: enabled)

        manager.protocolConfiguration = proto
        manager.isEnabled = true
        manager.localizedDescription = "BBTB"
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()  // RESEARCH §9.1 critical
    }
}
```

**Keychain payload (PATTERNS §2.21 invariant 5):**
- VLESS: `["uuid": ..., "publicKey": ..., "shortId": ..., "configJSON": singleOutboundOrPool]` — но Phase 2 path подменяется: keychainTag хранит **сам outbound JSON**, потому что pool case требует чтобы каждый ServerConfig мог re-emit свой outbound. Решение: keychain payload содержит `["secrets": <protocol-specific>, "outboundJSON": <one-outbound>]`. **Минимальная альтернатива (Phase 2 simplification):** keychain хранит только secrets (uuid/publicKey/shortId для VLESS; password для Trojan). outbound JSON хранится в `ServerConfig.outboundJSON` (W0.T1 field). При rebuild pool — PoolBuilder получает ParsedX struct from rawURI + secrets из Keychain. ServerConfig.rawURI хранит исходный URI для re-parse. **Использовать этот вариант.**

**Replace-pool helpers:**
```swift
private func deleteExistingPool(subscriptionURL: String) async throws {
    let descriptor = FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.subscriptionURL == subscriptionURL }
    )
    let existing = try modelContext.fetch(descriptor)
    for cfg in existing {
        if let tag = cfg.keychainTag {
            try? KeychainStore.delete(tag: tag)
        }
        modelContext.delete(cfg)
    }
}
private func deleteAllExistingConfigs() async throws {
    let descriptor = FetchDescriptor<ServerConfig>()
    let existing = try modelContext.fetch(descriptor)
    for cfg in existing {
        if let tag = cfg.keychainTag {
            try? KeychainStore.delete(tag: tag)
        }
        modelContext.delete(cfg)
    }
}
```

**Reference:** RESEARCH §9.1, §9.6; PATTERNS §2.21; CONTEXT D-06, D-07, D-14.
  </action>
  <verify>
    <automated>cd BBTB/Packages/AppFeatures && swift test --filter ConfigImporterTests 2>&1 | tail -15</automated>
  </verify>
  <done>9 тестов ConfigImporterTests зелёные; ConfigImporter.swift содержит ровно один callsite `KillSwitch.apply(to:` и он передаёт `enabled: enabled` (читается из UserDefaults); old `importFromPasteboard` остался public.</done>
</task>

### Task W3.T2: Rewrite `MainScreenViewModel.swift`

<task type="auto" tdd="true">
  <name>Task W3.T2: MainScreenViewModel rewrite — empty/idle dispatch, server label, reconnect banner flag (D-09, D-11, D-14)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift, BBTB/Packages/AppFeatures/Tests/AppFeaturesTests/MainScreenViewModelTests.swift</files>
  <behavior>
    - Test 1: ViewModel init с пустой SwiftData → state == `.empty` (не `.idle`).
    - Test 2: после успешного import 1 ServerConfig → state переходит в `.idle` (D-09 — empty стало idle с конфигом).
    - Test 3: после import при ≥2 supported ServerConfig → `currentServerLineText == "Авто"` (computed property из L10n).
    - Test 4: после import при 1 supported ServerConfig → `currentServerLineText == ServerConfig.name` (например, "Латвия — VLESS").
    - Test 5: state в `.empty` → currentServerLineText nil (или пустая строка).
    - Test 6: при изменении UserDefaults `app.bbtb.killSwitchEnabled` И state == `.connected` → `needsReconnectForKillSwitch` flips to true (D-14, наблюдение через NotificationCenter `UserDefaults.didChangeNotification`).
    - Test 7: после disconnect → `needsReconnectForKillSwitch` сбрасывается в false.
    - Test 8: `importFromPasteboard()` (existing Phase 1 method) продолжает работать (вызывает importer.importFromRawInput).
    - Test 9: новый `importFromQRString(_ raw: String)` — вызывает importer.importFromQRCode и обновляет состояние.
  </behavior>
  <action>
Per PATTERNS §2.22:

```swift
@MainActor public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState
    @Published public var lastError: String?
    @Published public private(set) var supportedConfigCount: Int = 0
    @Published public private(set) var unsupportedConfigCount: Int = 0
    @Published public private(set) var needsReconnectForKillSwitch: Bool = false
    @Published public private(set) var importInProgress: Bool = false  // for ImportProgressOverlay W4

    private let importer: ConfigImporting
    private let controller: TunnelControlling
    private let modelContext: ModelContext
    private var killSwitchObserver: NSObjectProtocol?

    public init(importer: ConfigImporting, controller: TunnelControlling, modelContext: ModelContext) {
        self.importer = importer
        self.controller = controller
        self.modelContext = modelContext
        let count = (try? Self.fetchSupportedCount(in: modelContext)) ?? 0
        self.state = (count == 0) ? .empty : .idle
        self.supportedConfigCount = count

        // D-14: observe UserDefaults killSwitchEnabled change
        self.killSwitchObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleKillSwitchFlagChange() }
        }
    }
    deinit { if let o = killSwitchObserver { NotificationCenter.default.removeObserver(o) } }

    public var currentServerLineText: String? {
        guard state != .empty else { return nil }
        if supportedConfigCount > 1 { return L10n.serverAuto }
        // single → fetch first ServerConfig.name
        let cfg = try? modelContext.fetch(FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })).first
        return cfg?.name
    }

    public func importFromPasteboard() {
        Task { @MainActor in await performImport(.pasteboard, raw: nil) }
    }
    public func importFromQRString(_ raw: String) {
        Task { @MainActor in await performImport(.qrCode, raw: raw) }
    }
    public func performToggle() {
        Task { @MainActor in await performToggleImpl() }
    }
    public func openSettings() {
        // No-op for now — NavigationLink in MainScreenView drives the navigation.
        // Reserved для macOS Settings Scene open via Environment.
    }
    public func dismissReconnectBanner() { needsReconnectForKillSwitch = false }

    private func performImport(_ source: ImportSource, raw: String?) async {
        importInProgress = true
        defer { importInProgress = false }
        do {
            let result: ImportResult
            switch source {
            case .qrCode where raw != nil:
                result = try await importer.importFromQRCode(raw!)
            default:
                result = try await importer.importFromPasteboard()
            }
            supportedConfigCount = result.supported.count
            unsupportedConfigCount = result.unsupported.count
            if supportedConfigCount > 0 && state == .empty {
                state = .idle
            }
        } catch { lastError = error.localizedDescription }
    }

    private func performToggleImpl() async {
        switch state {
        case .empty, .connecting:
            return
        case .idle, .error:
            state = .connecting
            do {
                try await controller.connect()
                state = .connected(since: Date())
                needsReconnectForKillSwitch = false  // applied on connect
            } catch { state = .error(message: error.localizedDescription) }
        case .connected:
            do {
                try await controller.disconnect()
                state = .idle
                needsReconnectForKillSwitch = false
            } catch { state = .error(message: error.localizedDescription) }
        }
    }

    private func handleKillSwitchFlagChange() {
        if case .connected = state {
            needsReconnectForKillSwitch = true
        }
    }

    private static func fetchSupportedCount(in ctx: ModelContext) throws -> Int {
        try ctx.fetch(FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })).count
    }
}
```

Phase 1 invariants preserved (PATTERNS §2.22):
- `@MainActor`.
- `Task { await ... }` wrapping в public методах.
- `performImport` / `performToggle` private async.
- ConnectionState switch с no-op для `.empty`/`.connecting`.

**Reference:** PATTERNS §2.22; CONTEXT D-09, D-11, D-14; UI-SPEC §1.3.
  </action>
  <verify>
    <automated>cd BBTB/Packages/AppFeatures && swift test --filter MainScreenViewModelTests 2>&1 | tail -15</automated>
  </verify>
  <done>9 тестов MainScreenViewModelTests зелёные; ViewModel.currentServerLineText возвращает корректные значения для всех 3 кейсов (nil/Auto/remark); needsReconnectForKillSwitch flips при UserDefaults change при state==.connected.</done>
</task>

### Task W3.T3: Minor `TunnelController.swift` update + Wave 3 regression check

<task type="auto">
  <name>Task W3.T3: TunnelController review (no structural change) + Wave 3 regression check</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift</files>
  <action>
Per PATTERNS §2.23: **TunnelController не требует структурных изменений в Phase 2.** D-01 фиксирует «один VPN profile, urltest inside». `TunnelController.connect()` / `disconnect()` оперируют на existing manager (загружают через `loadAllFromPreferences()`, берут first). pool config внутри providerConfiguration — это забота ConfigImporter (W3.T1).

Прочитать TunnelController.swift и подтвердить что:
1. `connect()` использует `NETunnelProviderManager.loadAllFromPreferences()` → first → `connection.startVPNTunnel()`.
2. `disconnect()` — то же, → `connection.stopVPNTunnel()`.
3. `isTunnelActive` computed property работает для new ViewModel.

Если нужно — мелкие refactor'ы: добавить `var isTunnelActive: Bool { manager?.connection.status == .connected }` если ViewModel это использует. Но никакого rewrite.

**Wave 3 regression check:**

```bash
cd BBTB/Packages/AppFeatures && swift test 2>&1 | tail -10
cd BBTB/Packages/ConfigParser && swift test 2>&1 | tail -5
cd BBTB/Packages/VPNCore && swift test 2>&1 | tail -3
cd BBTB/Packages/KillSwitch && swift test 2>&1 | tail -3
cd BBTB/Packages/PacketTunnelKit && swift test 2>&1 | tail -3
cd BBTB/Packages/Protocols/VLESSReality && swift test 2>&1 | tail -3
cd BBTB/Packages/Protocols/Trojan && swift test 2>&1 | tail -3
```

Все пакеты должны быть зелёные.

**Commit message templates для Wave 2 + Wave 3:**

```
feat(02/w2): register TrojanHandler in iOS + macOS app init (PROTO-02)

ProtocolRegistry.shared.register(TrojanHandler.self) right after VLESSReality.
Tuist Project.swift update follows in W4.T9 (combined with main app deps).

(02-W2.T1)
```

```
test(02/w2): dual-protocol smoke — UniversalImportParser → PoolBuilder → validate

4 integration tests verify multi-line VLESS+Trojan parsing produces valid pool config.
Single-server case generates degenerate (no urltest) config. ConfigParser test target
gains PacketTunnelKit dependency for R1 self-test (production code remains untouched —
PATTERNS §3.6 invariant preserved).

(02-W2.T2)
```

```
refactor(02/w3): rewrite ConfigImporter for multi-server pipeline + KILL-03 flag (D-06, D-07, D-14)

importFromRawInput(_:source:) new entry point; importFromPasteboard becomes facade.
Replace-pool semantics: re-import same subscriptionURL deletes existing rows.
KillSwitch.apply reads UserDefaults app.bbtb.killSwitchEnabled (default true).
ServerConfig saved with isSupported flag + outboundJSON + subscriptionURL.

(02-W3.T1)
```

```
refactor(02/w3): rewrite MainScreenViewModel for state.empty + reconnect banner + server label (D-09, D-11, D-14)

state.empty branch added for zero-config case. currentServerLineText computed:
"Авто" for ≥2 supported, ServerConfig.name for single, nil for empty.
needsReconnectForKillSwitch flips via UserDefaults.didChangeNotification observer
when state==.connected. importFromQRString new public method for QR scanner callback.

(02-W3.T2, 02-W3.T3)
```
  </action>
  <verify>
    <automated>for pkg in VPNCore PacketTunnelKit KillSwitch Localization ConfigParser AppFeatures; do echo "=== $pkg ==="; (cd "BBTB/Packages/$pkg" && swift test 2>&1 | tail -3); done; for proto in VLESSReality Trojan; do echo "=== Protocols/$proto ==="; (cd "BBTB/Packages/Protocols/$proto" && swift test 2>&1 | tail -3); done</automated>
  </verify>
  <done>Все 8 пакетов (включая Trojan + ConfigParser с новыми Smoke/Universal/Pool тестами + AppFeatures с новыми ConfigImporter/MainScreenViewModel тестами) зелёные. Ни один Phase 1 тест не упал.</done>
</task>

---

## Wave 4 — UI rewrite + SettingsFeature + QRScanner + Tuist

**Goal:** Visual rewrite главного экрана под UI-SPEC §2-§3, новый SettingsFeature sub-module с Kill Switch toggle, QR scanner SwiftUI обёртка над AVFoundation, localization extension, DesignSystem tokens, Info.plist + entitlements, Tuist Project.swift updates. **Большой wave** — 9 тасков, 6–8 коммитов.

**Dependencies:** W0 (StatusBadge rename), W3 (ViewModel new shape + Settings flag integration).

**Wave commit count:** 6–8.

### Task W4.T1: Extend `DesignSystem` package with tokens (UI-SPEC §8)

<task type="auto">
  <name>Task W4.T1: DesignSystem extension — Spacing, Radius, Typography tokens (UI-SPEC §8)</name>
  <files>BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift</files>
  <action>
Расширить существующий DesignSystem (Phase 1: только `DS.accent` + `DS.titleFont`) до полной шкалы per UI-SPEC §8.

```swift
import SwiftUI

public enum DS {
    public static let accent: Color = .accentColor  // Phase 1 carry-forward
    public static let titleFont: Font = .system(.title, design: .rounded).weight(.semibold)

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }
    public enum Radius {
        public static let small: CGFloat = 8
        public static let card: CGFloat = 12
        public static let cardLarge: CGFloat = 16
        public static let button: CGFloat = 12
    }
    public enum Typography {
        public static let display: Font = .system(.largeTitle, design: .monospaced).monospacedDigit()
        public static let title: Font = .system(.title3, design: .rounded).weight(.bold)
        public static let body: Font = .body
        public static let callout: Font = .system(.callout, design: .rounded)
        public static let subheadline: Font = .system(.subheadline, design: .rounded).weight(.medium)
        public static let caption: Font = .caption
    }
    public enum ConnectionButtonSize {
        public static let compactDiameter: CGFloat = 140
        public static let regularDiameter: CGFloat = 160
        public static let compactIcon: CGFloat = 56
        public static let regularIcon: CGFloat = 64
    }
}
```

Phase 11 переопределит значения но сохранит names (UI-SPEC §12 forward-compat).

Reference: UI-SPEC §8.1, §8.2, §8.4, §8.5.
  </action>
  <verify>
    <automated>cd BBTB/Packages/DesignSystem && swift build 2>&1 | tail -5</automated>
  </verify>
  <done>DesignSystem собирается; `grep -c "public enum Spacing" BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift` returns 1; same для Radius/Typography.</done>
</task>

### Task W4.T2: Extend `Localization` package with 32 new keys (UI-SPEC §9.1)

<task type="auto">
  <name>Task W4.T2: Localization extension — 32 new keys for empty/menu/server/settings/qr/banner/import (UI-SPEC §9)</name>
  <files>BBTB/Packages/Localization/Sources/Localization/L10n.swift, BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings</files>
  <action>
**Расширить `L10n.swift`** — добавить static let для каждого ключа из UI-SPEC §9.1 (~32 ключа). Naming convention из Phase 1 (lines 10-31): camelCase для Swift property name, dotted lowercase для xcstrings key.

Конкретные keys из UI-SPEC §9.1 (полный список):
- `empty.title`, `empty.subtitle`
- `action.scan_qr`, `action.cancel`, `action.ok`, `action.import_from_clipboard` (carry-forward)
- `menu.add_config`, `menu.scan_qr`, `menu.import_from_clipboard`
- `server.label`, `server.auto`
- `status.disconnected`, `status.connecting`, `status.connected`, `status.error` (replaces Phase 1 `status.idle` etc.)
- `timer.label`
- `settings.title`, `settings.security.section`, `settings.kill_switch.label`, `settings.kill_switch.footer`
- `banner.reconnect_needed`, `banner.dismiss`
- `qr.title`, `qr.cancel`, `qr.hint`, `qr.permission_denied.title`, `qr.permission_denied.message`, `qr.permission_denied.open_settings`
- `import.error.no_supported_configs`, `import.error.network` (с `%@` placeholder), `import.error.validation`, `import.error.v2ray_unsupported`
- `import.progress`, `import.success.title`, `import.success.message` (с `%lld %lld` placeholders)

**Phase 1 keys fate** (UI-SPEC §9.2):
- `status.empty` — удалить (state empty не показывает StatusPill).
- `status.idle` — заменить на `status.disconnected` (более ясно).
- existing `import.success` → renamed to `import.success.message`.
- остальные `menubar.*`, `alert.*`, `action.*` — без изменений.

**Localizable.xcstrings:** для каждого нового key добавить JSON entry с en + ru, каждый со `"state": "translated"`:
```json
"empty.title" : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "No configuration" } },
    "ru" : { "stringUnit" : { "state" : "translated", "value" : "Нет конфигурации" } }
  }
}
```
Тексты строго из UI-SPEC §9.1 таблицы (там полный ru + en список).

Удалить устаревшие keys (`status.empty`, `status.idle`) если они есть в xcstrings.

Reference: UI-SPEC §9.1, §9.2; PATTERNS §2.26, §2.27.
  </action>
  <verify>
    <automated>cd BBTB/Packages/Localization && swift build 2>&1 | tail -5 && grep -c "tr(" BBTB/Packages/Localization/Sources/Localization/L10n.swift</automated>
  </verify>
  <done>Localization собирается; L10n.swift имеет ≥30 `tr(...)` calls (старые ~22 + новые ~28+); Localizable.xcstrings содержит все новые keys с обоими ru+en entries; JSON в xcstrings валиден (`python3 -c "import json; json.load(open('BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings'))"`).</done>
</task>

### Task W4.T3: Visual rewrite of MainScreen components (StatusPill / ConnectionTimer / ConnectionButton)

<task type="auto">
  <name>Task W4.T3: Restyle StatusPill (Capsule), ConnectionTimer (optional Date?), ConnectionButton (140pt) per UI-SPEC §2.4-§2.6</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusPill.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift</files>
  <action>
**StatusPill.swift** (UI-SPEC §2.5, PATTERNS §2.18) — финальный rewrite после W0.T3 rename:
- Capsule shape вместо Phase 1 rounded rect.
- Padding: 16pt horizontal, 8pt vertical.
- Font: `DS.Typography.subheadline`.
- Background colors per UI-SPEC §2.5 table: idle = `.tertiarySystemFill`+`.secondary`; connecting = `.orange.opacity(0.18)`+`.orange`; connected = `.green.opacity(0.18)`+`.green`; error = `.red.opacity(0.18)`+`.red`.
- `.empty` state — компонент не рендерится (return EmptyView()).
- Без disclosure arrow (D-09 Q2.4).
- Tap **не реагирует** (Information element).
- Localization keys: `L10n.statusDisconnected`, `L10n.statusConnecting`, `L10n.statusConnected`, `L10n.statusError`.

**ConnectionTimer.swift** (UI-SPEC §2.4):
- Signature `init(since: Date?)` (Phase 1 был non-optional).
- При `since == nil` → рендерится `"00:00:00"` без подписки на `Timer.publish` (избегаем unnecessary work).
- Font: `DS.Typography.display` (largeTitle + monospaced + monospacedDigit).
- Опциональный label сверху `.caption2` foreground `.secondary` с текстом `L10n.timerLabel` ("Время подключения"). Показывается всегда когда таймер показан.
- Format `HH:MM:SS`.

**ConnectionButton.swift** (UI-SPEC §2.6):
- Diameter: `DS.ConnectionButtonSize.compactDiameter` / `regularDiameter` через `@Environment(\.horizontalSizeClass)`.
- Icon size: `DS.ConnectionButtonSize.compactIcon` / `regularIcon`.
- Shape: `Circle()`.
- Inner SF Symbol: `"power"`, weight `.medium`, foreground `Color.white`.
- Fill colors per UI-SPEC §2.6 table:
  - `.idle` → `Color(.systemGray)`
  - `.connecting` → `Color.orange` (анимация вращения — Phase 11 UX-08, на v0.2 оставляем `symbolEffect(.bounce, value: state)` Phase 1)
  - `.connected` → `Color.accentColor`
  - `.error` → `Color.red.opacity(0.85)`
  - `.empty` → not rendered
- Tap actions:
  - `.idle`/`.error` → `connect()`
  - `.connected` → `disconnect()`
  - `.connecting` → disabled
- `accessibilityIdentifier` = `"BBTB.ConnectionButton"` (Phase 1 carry-forward).

**Note:** SwiftUI snapshot tests на этом этапе **не делаем** — Phase 11 финал дизайна определит когда snapshots имеют ценность. На v0.2 — компиляция + manual visual check на симуляторе (W6 task).

Reference: UI-SPEC §2.4, §2.5, §2.6; PATTERNS §2.18; CONTEXT D-09.
  </action>
  <verify>
    <automated>cd BBTB/Packages/AppFeatures && swift build 2>&1 | tail -10</automated>
  </verify>
  <done>AppFeatures собирается; StatusPill использует Capsule; ConnectionTimer.init принимает Date?; ConnectionButton использует `DS.ConnectionButtonSize.compactDiameter`.</done>
</task>

### Task W4.T4: Create new MainScreen sub-components (EmptyStateCard, TopBar, ServerLineView, ReconnectBanner)

<task type="auto">
  <name>Task W4.T4: 4 new SwiftUI components for MainScreen (UI-SPEC §3, §2.7, §2.2, §2.3, PATTERNS §2.15-§2.19)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/EmptyStateCard.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TopBar.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ServerLineView.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportProgressOverlay.swift</files>
  <action>
**EmptyStateCard.swift** (UI-SPEC §3.2, PATTERNS §2.15):
- `public struct EmptyStateCard: View` с `init(onAddFromClipboard: @escaping () -> Void, onScanQR: @escaping () -> Void)`.
- VStack(spacing: DS.Spacing.lg) layout:
  - Image(systemName: "tray") — UI-SPEC §3.2 — size 56pt, `.secondary` foreground.
  - Text(L10n.emptyTitle) — DS.Typography.title.
  - Text(L10n.emptySubtitle) — DS.Typography.subheadline + `.secondary` + `.multilineTextAlignment(.center)`.
  - Button(L10n.actionImportFromClipboard) primary `.borderedProminent` `.controlSize(.large)`.
  - Button(L10n.actionScanQR) secondary `.bordered` `.controlSize(.large)`.
- Card: padding 24pt all, background `Color.secondary.opacity(0.1)` с corner radius `DS.Radius.cardLarge`.
- Max-width 360pt centered (на iPad/macOS).
- A11y labels per UI-SPEC §10 §10.3.

**TopBar.swift** (UI-SPEC §2.2, PATTERNS §2.16):
- `public struct TopBar: View` с `init(onMenuTap: () -> Void, onAddFromClipboard: () -> Void, onScanQR: () -> Void)`.
- HStack: leading menu button + Spacer + trailing `+` Menu.
- Menu icon: `Image(systemName: "line.3.horizontal")`, font `.title3` (CONTEXT D-09 Claude-default).
- `+` Menu (SwiftUI `Menu` native popup) с двумя пунктами:
  1. `Button(L10n.menuScanQR, systemImage: "qrcode.viewfinder", action: onScanQR)`.
  2. `Button(L10n.menuImportFromClipboard, systemImage: "doc.on.clipboard", action: onAddFromClipboard)`.
- accessibilityIdentifiers: `"BBTB.MenuButton"`, `"BBTB.AddButton"`.
- A11y labels per UI-SPEC §10.1.
- Padding: `.padding(.horizontal)` + `.padding(.top, 24)`.

**ServerLineView.swift** (UI-SPEC §2.7, PATTERNS §2.17):
- `public struct ServerLineView: View` с `init(name: String?)` (если nil — не рендерится).
- HStack: Text(L10n.serverLabel) + Text(name) bold + Spacer.
- Font: DS.Typography.callout, foreground `.secondary`.
- **Tap disabled на v0.2** — D-11 (Phase 3 enables).
- A11y label per UI-SPEC §10.1.

**ReconnectBanner.swift** (UI-SPEC §2.3, PATTERNS §2.19):
- `public struct ReconnectBanner: View` с `init(onDismiss: () -> Void)`.
- HStack: Image("arrow.triangle.2.circlepath") + Text(L10n.bannerReconnectNeeded) + Spacer + Button("xmark", action: onDismiss).
- Background: `Color.orange.opacity(0.15)`, corner radius `DS.Radius.card`.
- A11y label per UI-SPEC §10.1.

**ImportProgressOverlay.swift** (UI-SPEC §6.2):
- `public struct ImportProgressOverlay: View` с `init(message: String = L10n.importProgress)`.
- Center `ProgressView()` (.circular, scaleEffect 1.5) + Text(message).
- Background: `.regularMaterial` blur full-screen overlay.
- No cancel button on v0.2 (30s URLSession default timeout).

Reference: UI-SPEC §2.2, §2.3, §2.7, §3, §6.2, §10; PATTERNS §2.15, §2.16, §2.17, §2.19.
  </action>
  <verify>
    <automated>cd BBTB/Packages/AppFeatures && swift build 2>&1 | tail -5</automated>
  </verify>
  <done>Все 5 файлов существуют и AppFeatures компилируется; каждый компонент имеет `public init` и тип `View`.</done>
</task>

### Task W4.T5: Rewrite `MainScreenView.swift` — compose new layout

<task type="auto">
  <name>Task W4.T5: MainScreenView rewrite — TopBar + ReconnectBanner + content branch (empty/idle) per UI-SPEC §2-§3 (PATTERNS §2.14)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportFromClipboardButton.swift</files>
  <action>
**Rewrite `MainScreenView.body`** (PATTERNS §2.14):

```swift
public struct MainScreenView: View {
    @ObservedObject public var viewModel: MainScreenViewModel
    @State private var showQRScanner = false

    public init(viewModel: MainScreenViewModel) { self.viewModel = viewModel }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(
                    onMenuTap: { /* NavigationLink handles via toolbar — see below */ },
                    onAddFromClipboard: viewModel.importFromPasteboard,
                    onScanQR: { showQRScanner = true }
                )
                if viewModel.needsReconnectForKillSwitch {
                    ReconnectBanner(onDismiss: viewModel.dismissReconnectBanner)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                }
                Spacer()
                content
                Spacer()
            }
            if viewModel.importInProgress {
                ImportProgressOverlay()
            }
        }
        .toolbar { /* NavigationLink → SettingsView */ }
        .alert(isPresented: errorBinding) {
            Alert(title: Text(L10n.alertImportFailed), message: Text(viewModel.lastError ?? ""),
                  dismissButton: .default(Text(L10n.actionOK)))
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showQRScanner) {
            QRScannerView(
                onCodeScanned: { uri in
                    viewModel.importFromQRString(uri)
                    showQRScanner = false
                },
                onCancel: { showQRScanner = false }
            )
        }
        #elseif os(macOS)
        .sheet(isPresented: $showQRScanner) {
            QRScannerView(
                onCodeScanned: { uri in
                    viewModel.importFromQRString(uri)
                    showQRScanner = false
                },
                onCancel: { showQRScanner = false }
            )
            .frame(width: 480, height: 640)
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            EmptyStateCard(
                onAddFromClipboard: viewModel.importFromPasteboard,
                onScanQR: { showQRScanner = true }
            )
        case .idle, .connecting, .connected, .error:
            VStack(spacing: DS.Spacing.xxl) {
                ConnectionTimer(since: connectionStartDate)
                StatusPill(state: viewModel.state)
                ConnectionButton(state: viewModel.state, action: viewModel.performToggle)
                if let name = viewModel.currentServerLineText {
                    ServerLineView(name: name)
                }
            }
        }
    }

    private var connectionStartDate: Date? {
        if case let .connected(since) = viewModel.state { return since }
        return nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.lastError != nil },
                set: { if !$0 { viewModel.lastError = nil } })
    }
}
```

**Удалить файл `ImportFromClipboardButton.swift`** (`git rm`) — Phase 1 кнопку заменяет `EmptyStateCard`. Если есть call-sites — должны быть только в `MainScreenView.swift` (header или footer) — они заменены rewrite'ом.

NavigationLink to SettingsView через `.toolbar` ToolbarItem с placement `.topBarLeading`:
```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        NavigationLink(destination: SettingsView(viewModel: SettingsViewModel())) {
            Image(systemName: "line.3.horizontal").font(.title3)
        }
    }
}
```

Это **дополняет** существующий TopBar в body — toolbar item остаётся видимым в NavigationStack. Если выглядит как дубль с TopBar.swift — **выбрать одно из двух**:
- Вариант A: TopBar.swift содержит menu icon + `+` Menu, не используем NavigationStack toolbar. NavigationLink wrapping делается **в TopBar.swift** (TopBar получает `destination` parameter).
- Вариант B: TopBar.swift только для `+` Menu, leading menu icon идёт через `.toolbar`.

Рекомендую **Вариант A** (PATTERNS §2.16) — TopBar.swift cleaner и тестируемее. Executor должен выбрать и зафиксировать в commit message.

Reference: UI-SPEC §2.1, §2.3, §3.1, §6.2; PATTERNS §2.14.
  </action>
  <verify>
    <automated>cd BBTB/Packages/AppFeatures && swift build 2>&1 | tail -10 && test ! -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportFromClipboardButton.swift</automated>
  </verify>
  <done>AppFeatures собирается; `ImportFromClipboardButton.swift` удалён; `MainScreenView.swift` содержит `case .empty: EmptyStateCard(...)` ветку (grep `case .empty`).</done>
</task>

### Task W4.T6: Create `SettingsFeature` sub-module (AppFeatures package update)

<task type="auto" tdd="true">
  <name>Task W4.T6: SettingsFeature sub-module — SettingsView + SettingsViewModel + KillSwitchToggleSection (D-12, D-13, D-14, PATTERNS §2.11-§2.13)</name>
  <files>BBTB/Packages/AppFeatures/Package.swift, BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift, BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift, BBTB/Packages/AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift, BBTB/Packages/AppFeatures/Tests/AppFeaturesTests/SettingsViewModelTests.swift</files>
  <behavior>
    - Test 1: SettingsViewModel.killSwitchEnabled default = true (если UserDefaults key отсутствует).
    - Test 2: установка ViewModel.killSwitchEnabled = false → UserDefaults.standard.bool(forKey: "app.bbtb.killSwitchEnabled") == false.
    - Test 3: чтение UserDefaults = false → ViewModel.killSwitchEnabled == false.
  </behavior>
  <action>
1. **AppFeatures/Package.swift** (PATTERNS §2.30) — добавить новый library product + new target + dependencies:

```swift
products: [
    .library(name: "MainScreenFeature", targets: ["MainScreenFeature"]),
    .library(name: "MenuBarFeature", targets: ["MenuBarFeature"]),
    .library(name: "SettingsFeature", targets: ["SettingsFeature"]),  // NEW
],
dependencies: [
    .package(path: "../VPNCore"),
    .package(path: "../DesignSystem"),
    .package(path: "../Localization"),
    .package(path: "../ConfigParser"),
    .package(path: "../KillSwitch"),
    .package(path: "../Protocols/VLESSReality"),
    .package(path: "../Protocols/Trojan"),  // NEW (W2)
],
targets: [
    .target(name: "MainScreenFeature", dependencies: ["VPNCore", "DesignSystem", "Localization", "ConfigParser", "KillSwitch", "VLESSReality", "Trojan"]),  // Trojan added
    .target(name: "MenuBarFeature", dependencies: ["MainScreenFeature", "Localization", "VPNCore"]),
    .target(name: "SettingsFeature", dependencies: ["VPNCore", "DesignSystem", "Localization", "KillSwitch"]),  // NEW
    .testTarget(name: "AppFeaturesTests", dependencies: ["MainScreenFeature", "MenuBarFeature", "SettingsFeature"]),
]
```

2. **SettingsView.swift** (UI-SPEC §4, PATTERNS §2.11):
```swift
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel
    public init(viewModel: SettingsViewModel) { self.viewModel = viewModel }
    public var body: some View {
        Form {
            Section {
                KillSwitchToggleSection(
                    isOn: $viewModel.killSwitchEnabled,
                    footerText: L10n.settingsKillSwitchFooter
                )
            } header: {
                Text(L10n.settingsSecuritySection)
            } footer: {
                Text(L10n.settingsKillSwitchFooter)
            }
        }
        .navigationTitle(L10n.settingsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
```

3. **SettingsViewModel.swift** (PATTERNS §2.12):
```swift
@MainActor public final class SettingsViewModel: ObservableObject {
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = true
    public init() {}
}
```

4. **KillSwitchToggleSection.swift** (PATTERNS §2.13):
```swift
public struct KillSwitchToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String
    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn; self.footerText = footerText
    }
    public var body: some View {
        Toggle(L10n.settingsKillSwitchLabel, isOn: $isOn)
            .accessibilityHint(footerText)
    }
}
```

5. **SettingsViewModelTests.swift** — 3 теста за UserDefaults round-trip.

Reference: UI-SPEC §4; PATTERNS §2.11-§2.13, §2.30 (Package.swift extension); CONTEXT D-12, D-13, D-14.
  </action>
  <verify>
    <automated>cd BBTB/Packages/AppFeatures && swift test --filter SettingsViewModelTests 2>&1 | tail -10</automated>
  </verify>
  <done>3 теста SettingsViewModelTests зелёные; SettingsFeature target собирается; AppFeatures/Package.swift содержит `.library(name: "SettingsFeature"`.</done>
</task>

### Task W4.T7: Create `QRScannerView` + `CameraPermission` (AVFoundation)

<task type="auto">
  <name>Task W4.T7: QRScannerView SwiftUI wrapper + CameraPermission actor (IMP-02, RESEARCH §8, PATTERNS §2.20)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerView.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/CameraPermission.swift</files>
  <action>
**CameraPermission.swift** (RESEARCH §8.2):
```swift
import AVFoundation

public actor CameraPermission {
    public enum Status { case authorized, denied, restricted, notDetermined }
    public enum CameraError: Error, LocalizedError {
        case userDenied, restricted, noCamera
        public var errorDescription: String? { /* via L10n */ }
    }
    public static func currentStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
    /// Returns true when access granted; throws if denied or restricted.
    public static func request() async throws -> Bool {
        switch currentStatus() {
        case .authorized: return true
        case .denied: throw CameraError.userDenied
        case .restricted: throw CameraError.restricted
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        }
    }
}
```

**QRScannerViewController.swift** (iOS only) per RESEARCH §8.4:
```swift
#if os(iOS)
import UIKit; import AVFoundation
final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var onScan: ((String) -> Void)?
    convenience init(onScan: @escaping (String) -> Void) {
        self.init(); self.onScan = onScan
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
        else { return }
        if session.canAddInput(videoInput) { session.addInput(videoInput) }
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]
        }
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !metadataObjects.isEmpty,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = readable.stringValue
        else { return }
        session.stopRunning()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        DispatchQueue.main.async { [weak self] in self?.onScan?(value) }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }
}
#endif
```

**QRScannerView.swift** — SwiftUI wrapper:
```swift
public struct QRScannerView: View {
    public let onCodeScanned: (String) -> Void
    public let onCancel: () -> Void
    @State private var permissionState: CameraPermission.Status = CameraPermission.currentStatus()
    @State private var permissionError: Error?

    public init(onCodeScanned: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCodeScanned = onCodeScanned; self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L10n.qrCancel, action: onCancel)
                Spacer()
                Text(L10n.qrTitle).bold()
                Spacer()
                Button("") {}.hidden()  // symmetric layout
            }.padding()

            if permissionState == .denied || permissionState == .restricted {
                permissionDeniedView
            } else {
                cameraView
            }
        }
        .task {
            do {
                _ = try await CameraPermission.request()
                permissionState = CameraPermission.currentStatus()
            } catch {
                permissionError = error
                permissionState = CameraPermission.currentStatus()
            }
        }
    }

    @ViewBuilder
    private var cameraView: some View {
        #if os(iOS)
        QRScannerRepresentable(onScan: onCodeScanned).edgesIgnoringSafeArea(.all)
        Text(L10n.qrHint).foregroundColor(.white).font(DS.Typography.callout).padding()
        #elseif os(macOS)
        QRScannerNSRepresentable(onScan: onCodeScanned).frame(maxWidth: .infinity, maxHeight: .infinity)
        Text(L10n.qrHint).font(DS.Typography.callout).padding()
        #endif
    }

    @ViewBuilder
    private var permissionDeniedView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "video.slash").font(.system(size: 56)).foregroundColor(.secondary)
            Text(L10n.qrPermissionDeniedTitle).font(DS.Typography.title)
            Text(L10n.qrPermissionDeniedMessage).font(DS.Typography.body).multilineTextAlignment(.center)
            Button(L10n.qrPermissionDeniedOpenSettings) {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #elseif os(macOS)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
                #endif
            }.buttonStyle(.borderedProminent)
            Button(L10n.actionCancel, action: onCancel).buttonStyle(.bordered)
        }.padding()
    }
}

#if os(iOS)
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(onScan: onScan)
    }
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}
#elseif os(macOS)
private struct QRScannerNSRepresentable: NSViewRepresentable {
    let onScan: (String) -> Void
    func makeNSView(context: Context) -> QRScannerNSView { QRScannerNSView(onScan: onScan) }
    func updateNSView(_ nsView: QRScannerNSView, context: Context) {}
}
final class QRScannerNSView: NSView, AVCaptureMetadataOutputObjectsDelegate {
    // Аналогично QRScannerViewController но для macOS NSView с AVCaptureSession.
    // Implementation per RESEARCH §8.5 macOS variant.
}
#endif
```

**Test note:** AVFoundation requires real camera or Simulator не подходит для unit tests. На v0.2 — **build test only** (компиляция должна проходить). Real test — W5 UAT (user scans real QR code).

Reference: RESEARCH §8.1-§8.6, §8.7; PATTERNS §2.20.
  </action>
  <verify>
    <automated>cd BBTB/Packages/AppFeatures && swift build 2>&1 | tail -10</automated>
  </verify>
  <done>AppFeatures собирается на macOS (host для test); три файла существуют; QRScannerView имеет init с `onCodeScanned` + `onCancel` callbacks.</done>
</task>

### Task W4.T8: Update Info.plist (iOS + macOS) + macOS entitlements

<task type="auto">
  <name>Task W4.T8: NSCameraUsageDescription in both Info.plists + camera entitlement in macOS entitlements</name>
  <files>BBTB/App/iOSApp/Info.plist, BBTB/App/macOSApp/Info.plist, BBTB/App/macOSApp/BBTB-macOS.entitlements</files>
  <action>
**BBTB/App/iOSApp/Info.plist** — добавить ключ перед закрывающим `</dict>` (PATTERNS §2.31):
```xml
<key>NSCameraUsageDescription</key>
<string>BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов.</string>
```

**BBTB/App/macOSApp/Info.plist** — same key (PATTERNS §2.32):
```xml
<key>NSCameraUsageDescription</key>
<string>BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов.</string>
```

**BBTB/App/macOSApp/BBTB-macOS.entitlements** — добавить camera entitlement (PATTERNS §2.33; RESEARCH §8.3):
```xml
<key>com.apple.security.device.camera</key>
<true/>
```

iOS entitlements file не меняем — iOS gates через TCC + Info.plist key (RESEARCH §8.3).

Локализованные тексты NSCameraUsageDescription (en + ru) опционально через InfoPlist.strings — отложим до Phase 11. На v0.2 default Russian текст приемлем (CLAUDE.md primary language).

Reference: RESEARCH §8.3; PATTERNS §2.31-§2.33; CONTEXT Claude's Discretion (Camera permissions copy).
  </action>
  <verify>
    <automated>grep -c "NSCameraUsageDescription" BBTB/App/iOSApp/Info.plist BBTB/App/macOSApp/Info.plist && grep -c "com.apple.security.device.camera" BBTB/App/macOSApp/BBTB-macOS.entitlements</automated>
  </verify>
  <done>NSCameraUsageDescription присутствует в обоих Info.plist; com.apple.security.device.camera в macOS entitlements; XML файлы валидны (`plutil -lint BBTB/App/iOSApp/Info.plist && plutil -lint BBTB/App/macOSApp/Info.plist && plutil -lint BBTB/App/macOSApp/BBTB-macOS.entitlements`).</done>
</task>

### Task W4.T9: Update Tuist `Project.swift` + App entry points + MenuBarFeature

<task type="auto">
  <name>Task W4.T9: Tuist Project.swift — add Trojan + SettingsFeature packages + NavigationStack + Settings Scene</name>
  <files>BBTB/Project.swift, BBTB/App/iOSApp/BBTB_iOSApp.swift, BBTB/App/macOSApp/BBTB_macOSApp.swift, BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift</files>
  <action>
1. **BBTB/Project.swift** (PATTERNS §2.30):
   - В `localPackages` array — добавить `.package(path: .relativeToManifest("Packages/Protocols/Trojan"))`.
   - В iOS app target dependencies — добавить `.package(product: "Trojan")` и `.package(product: "SettingsFeature")`.
   - В macOS app target dependencies — то же два .package.

2. **BBTB_iOSApp.swift** (PATTERNS §2.28):
   ```swift
   import SettingsFeature  // NEW

   var body: some Scene {
       WindowGroup {
           NavigationStack {  // ← NEW
               MainScreenView(viewModel: viewModel)
           }
       }
       .modelContainer(modelContainer)
   }
   ```

3. **BBTB_macOSApp.swift** (PATTERNS §2.29):
   ```swift
   import SettingsFeature  // NEW

   var body: some Scene {
       Window(L10n.appShortName, id: "main") {
           NavigationStack {  // ← NEW
               MainScreenView(viewModel: viewModel)
                   .frame(minWidth: 380, minHeight: 520)
           }
       }
       .windowResizability(.contentSize)
       .modelContainer(modelContainer)

       Settings {  // ← NEW Cmd+, scene
           SettingsView(viewModel: SettingsViewModel())
               .frame(width: 480, height: 360)
       }

       MenuBarExtra(L10n.appShortName, systemImage: viewModel.state.menuBarSymbol) {
           MenuBarContent(viewModel: viewModel)
       }
       .menuBarExtraStyle(.window)
   }
   ```

4. **MenuBarContent.swift** (macOS) — добавить «Настройки…» пункт через `SettingsLink` (iOS17+/macOS14+):
   ```swift
   // Existing items + new:
   #if os(macOS)
   SettingsLink {
       Text(L10n.settingsTitle)
   } prefix: {
       Image(systemName: "gear")
   }
   #endif
   ```

5. После всех изменений — regenerate Xcode project через Tuist:
   ```bash
   cd BBTB && tuist generate
   ```
   (Этот step выполняется как часть verify automated check.)

Reference: PATTERNS §2.28, §2.29, §2.30; CONTEXT D-09 macOS Settings + Cmd+,.
  </action>
  <verify>
    <automated>cd BBTB && tuist generate 2>&1 | tail -5 && xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20</automated>
  </verify>
  <done>Tuist generate succeeds; iOS simulator build succeeds (xcodebuild last line = `BUILD SUCCEEDED`); macOS build separate check in W6.</done>
</task>

**Commit message templates для Wave 4:**

```
feat(02/w4): extend DesignSystem with Spacing/Radius/Typography tokens (UI-SPEC §8)

Token names match Phase 11 forward-compat (values will change, names stable).

(02-W4.T1)
```

```
feat(02/w4): localization — 32 new keys for empty/menu/server/settings/qr/banner/import (UI-SPEC §9)

ru + en for each key, "state": "translated". Phase 1 status.idle → status.disconnected
rename. Phase 1 empty.title/empty.subtitle rewritten with v2raytune-reference text.

(02-W4.T2)
```

```
refactor(02/w4): visual rewrite — StatusPill (Capsule), ConnectionTimer (optional Date?), ConnectionButton (140pt, accent on connected) (UI-SPEC §2.4-§2.6)

(02-W4.T3)
```

```
feat(02/w4): new SwiftUI components — EmptyStateCard, TopBar, ServerLineView, ReconnectBanner, ImportProgressOverlay (UI-SPEC §2-§3, §6)

(02-W4.T4)
```

```
refactor(02/w4): MainScreen layout rewrite — TopBar + content branch (empty/idle) + QR sheet + import overlay (D-09, D-10, UI-SPEC §2-§3)

ImportFromClipboardButton.swift deleted (replaced by EmptyStateCard).

(02-W4.T5)
```

```
feat(02/w4): SettingsFeature sub-module — Kill Switch toggle + Безопасность section (KILL-03, D-12, D-13, D-14)

AppFeatures/Package.swift gains SettingsFeature product + Trojan dependency for
MainScreenFeature. @AppStorage("app.bbtb.killSwitchEnabled") drives the toggle.

(02-W4.T6)
```

```
feat(02/w4): QR scanner — AVFoundation + CameraPermission flow (IMP-02, RESEARCH §8)

UIViewControllerRepresentable (iOS) + NSViewRepresentable (macOS). Permission denied
state shows "Open Settings" deep link. NSCameraUsageDescription + camera entitlement
for macOS hardened runtime.

(02-W4.T7, 02-W4.T8)
```

```
build(02/w4): Tuist update — register Trojan + SettingsFeature in app targets; wrap MainScreen in NavigationStack; macOS Settings Scene (D-09, D-12)

(02-W4.T9)
```

---

## Wave 5 — Integration tests + Device UAT prep

**Goal:** End-to-end integration tests с моки URLSession для всех 3 форматов раздачи + Kill Switch toggle round-trip + создание `02-UAT.md` для пользователя проверить на iPhone.

**Dependencies:** W0–W4.

**Wave commit count:** 2–3.

### Task W5.T1: Integration tests — 3 import formats + Kill Switch round-trip

<task type="auto" tdd="true">
  <name>Task W5.T1: Integration tests — subscription URL / multi-line / JSON endpoint / Kill Switch round-trip</name>
  <files>BBTB/Packages/ConfigParser/Tests/ConfigParserTests/IntegrationTests.swift, BBTB/Packages/AppFeatures/Tests/AppFeaturesTests/ImportFlowIntegrationTests.swift</files>
  <behavior>
    - Test 1 (Variant 1 — subscription URL): mocked URLSession возвращает base64 от 6 user URI (CONTEXT `<specifics>`, sanitized) → `UniversalImportParser.import(rawInput: subscriptionURL)` → ImportResult.supported.count=6 (4 VLESS + 2 Trojan). Все имеют subscriptionURL field set.
    - Test 2 (Variant 1 with unsupported): mocked response с 6 supported + 1 ss URI → 6 supported + 1 unsupported. ImportResult.failed.count=0.
    - Test 3 (Variant 2 — multi-line plain-text): direct paste 6 user URI → 6 supported. subscriptionURL=nil.
    - Test 4 (Variant 3 — JSON endpoint): mocked response с sing-box config (vless+trojan+selector+direct) → extract → 2 supported. Passes `SingBoxConfigLoader.validate(json: poolJSON)`.
    - Test 5 (Variant 3 invalid): mocked JSON с `inbounds: [{type: socks}]` → validate throws `.forbiddenInboundType("socks")` (R1).
    - Test 6 (Kill Switch round-trip): UserDefaults `app.bbtb.killSwitchEnabled = false` → ConfigImporter.importFromRawInput → mock NETunnelProviderProtocol → includeAllNetworks==false; enforceRoutes==false. Затем UserDefaults = true, re-import → includeAllNetworks==true, enforceRoutes==!platformShouldDisableEnforceRoutes().
    - Test 7 (Replace-pool D-07): import subscription URL #1 (3 servers) → 3 rows in SwiftData. Re-import same URL (4 servers) → 4 rows (old 3 deleted, new 4 inserted). Re-import different URL #2 (2 servers) → 4+2=6 rows total (URL #1 rows preserved since matched by URL field, not "all").

NOTE: Test 7 contradicts ConfigImporter.deleteAllExistingConfigs (W3.T1 logic for non-subscription path). Решение: для subscription URL path — replace-by-URL (per D-07). Для non-subscription path (single paste / multi-line / QR) — replace-all (more conservative, single VPN profile concept). Test 7 specifically tests **subscription path with D-07 replace-by-URL semantics**.
  </behavior>
  <action>
**File 1: `ConfigParser/Tests/ConfigParserTests/IntegrationTests.swift`** — Variant 1/2/3 integration через mocked URLSession (MockURLProtocol harness W1.T5).

**File 2: `AppFeatures/Tests/AppFeaturesTests/ImportFlowIntegrationTests.swift`** — ConfigImporter end-to-end с mock NETunnelProviderProtocol класса (test util):
```swift
final class MockNETunnelProviderProtocol: NETunnelProviderProtocol {
    var capturedIncludeAllNetworks: Bool?
    var capturedEnforceRoutes: Bool?
    override var includeAllNetworks: Bool { didSet { capturedIncludeAllNetworks = includeAllNetworks } }
    override var enforceRoutes: Bool { didSet { capturedEnforceRoutes = enforceRoutes } }
}
```

Тесты используют in-memory ModelContainer (existing `SwiftDataContainer.makeInMemory` или эквивалент). Для NETunnelProviderManager — **stub** (Phase 1 tests делают похожий pattern; см. как Phase 1 проверял KillSwitch.apply без real manager).

**Fixtures (shared с W1):**
- `sub-base64-response.txt` (W1.T5) — для Test 1.
- `sub-plaintext-response.txt` (W1.T5) — для Test 3.
- `sub-json-response.json` (W1.T5) — для Test 4.

Reference: CONTEXT `<specifics>`; RESEARCH §4 (subscription formats); §9.6 (ConfigImporter pipeline).
  </action>
  <verify>
    <automated>cd BBTB/Packages/ConfigParser && swift test --filter IntegrationTests 2>&1 | tail -10 && cd ../AppFeatures && swift test --filter ImportFlowIntegrationTests 2>&1 | tail -10</automated>
  </verify>
  <done>7 integration тестов зелёные; все 3 формата (subscription URL / multi-line / JSON endpoint) парсятся в правильный ImportResult shape; Kill Switch UserDefaults flag round-trip через ConfigImporter работает.</done>
</task>

### Task W5.T2: Generate `02-UAT.md` (device acceptance test plan)

<task type="auto">
  <name>Task W5.T2: Generate 02-UAT.md — 9 device-side tests for user to run on real iPhone (T1-T9)</name>
  <files>.planning/phases/02-trojan-import-flow/02-UAT.md</files>
  <action>
Создать `02-UAT.md` (Phase 1 UAT pattern — см. `.planning/phases/01-foundation/01-UAT.md` если есть, или создать с нуля). Структура — каждый test имеет: ID / Цель / Шаги / Ожидаемое поведение / Pass/Fail отметка.

**Тесты (per task prompt):**

```markdown
# Phase 2 — UAT (User Acceptance Test) Plan

**Target device:** iPhone (iOS 18+) с активной TestFlight сборкой v0.2.
**Prerequisite:** Phase 1 build установлен и работает (Phase 1 UAT closed 2026-05-11).
**Estimated duration:** ~60 минут включая ожидание urltest switching window.

## T1 — Variant 1: Subscription URL import
**Цель:** Подтвердить D-02 / IMP-02 — клиент принимает subscription URL и парсит весь pool.
**Шаги:**
1. Открыть BBTB на iPhone.
2. Скопировать `https://vpn.vergevsky.ru/sub/VGVzdCwxNzc4NTIzNzExdXbmcsiR_Y` в буфер обмена.
3. Tap `+` → «Добавить из буфера».
4. Дождаться завершения progress overlay (~5-15s).
**Ожидаемое:**
- Alert «Импорт завершён. Добавлено: X. Будут включены в следующих версиях: Y.»
- iOS Settings → VPN — появилась запись «BBTB» (если ещё не было).
- В SwiftData rows должно быть ~6-7 (зависит от состава подписки).

## T2 — Variant 2: Multi-line URI block import
**Цель:** Подтвердить D-02 multi-line поддержку.
**Шаги:**
1. Скопировать в буфер обмена 6-строчный блок URI из `.planning/phases/02-trojan-import-flow/02-CONTEXT.md` `<specifics>` Вариант 2.
2. Tap `+` → «Добавить из буфера».
**Ожидаемое:** Alert «Импорт завершён. Добавлено: 6.».

## T3 — Variant 3: JSON endpoint import
**Цель:** Подтвердить D-02 JSON endpoint path.
**Шаги:**
1. Скопировать `https://185.237.218.81:24527/json/v3ry-53cur3-p4th-98231/g8ogx6367znwvy95` в буфер обмена.
2. Tap `+` → «Добавить из буфера».
**Ожидаемое:** Alert «Импорт завершён. Добавлено: N.» (N зависит от содержимого operator JSON).

## T4 — QR-code import
**Цель:** Подтвердить IMP-02 + camera permission flow.
**Шаги:**
1. Сгенерировать QR-код с одним vless:// URI (например через `qrencode` на ноутбуке).
2. На iPhone: tap `+` → «Сканировать QR».
3. (Первый запуск) — iOS показывает permission prompt — нажать «Разрешить».
4. Навести камеру на QR.
**Ожидаемое:**
- Виден preview камеры с hint «Наведите камеру на QR-код».
- При сканировании — haptic feedback (buzz), sheet закрывается.
- Alert «Импорт завершён. Добавлено: 1.».

## T5 — Connect & IP change verification
**Цель:** Подтвердить что после import → connect туннель работает.
**Шаги:**
1. После T1/T2/T3, перейти на главный экран.
2. Tap power button — state переходит .connecting → .connected.
3. Открыть Safari → `https://api.ipify.org`.
**Ожидаемое:**
- Status pill «Подключено».
- Timer считает с 00:00:00 вверх.
- IP на api.ipify.org — IP одного из серверов из импортированного пула (НЕ домашний IP).
- ServerLine показывает «Авто» (т.к. в пуле > 1 сервера).

## T6 — urltest failover (manual or natural)
**Цель:** Подтвердить PROTO-10 / D-01 — при failure активного outbound, urltest переключается.
**Шаги:**
1. После T5 (connected).
2. **Manual scenario:** на сервере остановить процесс sing-box на VLESS-сервере (через SSH).
3. **OR Natural scenario:** дождаться ТСПУ-блокировки VLESS (может занять часы — выполнить тест на нескольких сетях).
4. Подождать ~1-2 минуты (urltest interval=1m).
5. Проверить IP на api.ipify.org.
**Ожидаемое:**
- IP меняется на Trojan-сервер (или другой выживший outbound из пула).
- Touch-Connection продолжает работать без полного reconnect.

## T7 — Kill Switch OFF round-trip
**Цель:** Подтвердить D-14, D-15.
**Шаги:**
1. Перейти в Settings (≡ → Настройки).
2. Toggle «Kill Switch» — выключить.
3. Возврат на MainScreen — ReconnectBanner НЕ показывается (т.к. tunnel был disconnected или ещё не connected).
4. Connect.
5. Открыть iOS Settings → VPN → BBTB → проверить «Include All Networks» = OFF (если iOS показывает этот toggle) или диагностировать через `ifconfig utun*` flags.
**Ожидаемое:**
- VPN profile: includeAllNetworks=false, enforceRoutes=false.
- Tunnel работает в обычном split-VPN режиме.

## T8 — Kill Switch ON round-trip (return to default)
**Цель:** Подтвердить D-15 reverse.
**Шаги:**
1. Settings → Kill Switch — включить.
2. Connect → IP change verified.
**Ожидаемое:**
- VPN profile: includeAllNetworks=true.
- При искусственном disconnect (закрыть VPN profile через iOS Settings) — внешний трафик блокируется до restart.

## T9 — Toggle Kill Switch during active tunnel — banner appears
**Цель:** D-14 баннер «Переподключитесь».
**Шаги:**
1. Connect (state == .connected).
2. Settings → Kill Switch — toggle (любое направление).
3. Возврат на MainScreen.
**Ожидаемое:**
- ReconnectBanner показывается сверху со словами «Переподключитесь для применения изменений».
- Tap `✕` — banner закрывается.
- Disconnect → connect — изменения applied; banner не возвращается.

---

## Sign-off

После завершения всех 9 тестов:
- [ ] T1 — PASS / FAIL / N/A (с описанием)
- [ ] T2 — PASS / FAIL / N/A
- [ ] T3 — PASS / FAIL / N/A
- [ ] T4 — PASS / FAIL / N/A
- [ ] T5 — PASS / FAIL / N/A
- [ ] T6 — PASS / FAIL / N/A (failover может потребовать manual ТСПУ simulation)
- [ ] T7 — PASS / FAIL / N/A
- [ ] T8 — PASS / FAIL / N/A
- [ ] T9 — PASS / FAIL / N/A

**Carry-forward Phase 1 invariants** (re-verified на v0.2 build):
- [ ] R1 — SocksProbe не находит SOCKS listeners на 127.0.0.1 нашего PacketTunnelProvider.
- [ ] R6 — `ifconfig utun*` shows `P2P` flag NOT present (Phase 1 verified, regression check).
- [ ] No debug logs in Release config.

**UAT date:** _____________
**Tester:** Nv (project owner)
**Sign-off:** _____________
```

Reference: Phase 1 UAT pattern (`.planning/phases/01-foundation/01-UAT.md`); CONTEXT `<specifics>`; tasks T1-T9 из task prompt.
  </action>
  <verify>
    <automated>test -f .planning/phases/02-trojan-import-flow/02-UAT.md && wc -l .planning/phases/02-trojan-import-flow/02-UAT.md | awk '{exit ($1 >= 60 ? 0 : 1)}'</automated>
  </verify>
  <done>02-UAT.md существует и содержит ≥60 строк; 9 тестов (T1-T9) с шагами; sign-off section.</done>
</task>

### Task W5.T3: Wave 5 regression check + commit

<task type="auto">
  <name>Task W5.T3: Final regression check before Wave 6 build verification</name>
  <files>(verification only)</files>
  <action>
Прогнать full unit + integration suite:
```bash
for pkg in VPNCore PacketTunnelKit KillSwitch Localization DesignSystem ConfigParser AppFeatures; do
    echo "=== $pkg ==="
    (cd "BBTB/Packages/$pkg" && swift test 2>&1 | tail -3)
done
for proto in VLESSReality Trojan; do
    echo "=== Protocols/$proto ==="
    (cd "BBTB/Packages/Protocols/$proto" && swift test 2>&1 | tail -3)
done
```

Все пакеты должны быть зелёные. Если any красный — диагностика и фикс **в этом** wave, **не** двигаться в W6.

**Commit message templates для Wave 5:**

```
test(02/w5): integration tests — 3 import formats + Kill Switch round-trip + replace-pool

7 integration tests covering Variant 1 (subscription URL with base64 / plain-text / JSON
response), Variant 2 (multi-line paste), Variant 3 (JSON endpoint), R1 reject of operator
JSON with forbidden inbounds, Kill Switch UserDefaults round-trip through ConfigImporter,
D-07 replace-pool semantics (same subscriptionURL replaces; different URL appends).

(02-W5.T1)
```

```
docs(02/w5): generate device UAT plan — 9 acceptance tests (T1-T9, ROADMAP SC1-SC8)

T1-T3: 3 import variants. T4: QR scan. T5: connect + IP change. T6: urltest failover.
T7-T9: Kill Switch toggle round-trip + reconnect banner. Phase 1 R1/R6 carry-forward
re-verified.

(02-W5.T2, 02-W5.T3)
```
  </action>
  <verify>
    <automated>for pkg in VPNCore PacketTunnelKit KillSwitch Localization DesignSystem ConfigParser AppFeatures; do (cd "BBTB/Packages/$pkg" && swift test 2>&1 | tail -3 | head -1); done; for proto in VLESSReality Trojan; do (cd "BBTB/Packages/Protocols/$proto" && swift test 2>&1 | tail -3 | head -1); done</automated>
  </verify>
  <done>Все 9 пакетов имеют "passed" последний test result; никаких regressions относительно Phase 1.</done>
</task>

---

## Wave 6 — Build verification + cleanup

**Goal:** Финальная сборка iOS + macOS targets через Tuist + xcodebuild. Подтвердить что Release config не содержит debug-логов (Phase 1 carry-forward SEC). Cleanup.

**Dependencies:** W0–W5.

**Wave commit count:** 1–2.

### Task W6.T1: Full Tuist + xcodebuild verification (iOS + macOS, Debug + Release)

<task type="auto">
  <name>Task W6.T1: tuist generate + xcodebuild for iOS Simulator (Debug) + macOS (Debug) + iOS Release linting</name>
  <files>(verification only — may regenerate Xcode project)</files>
  <action>
```bash
cd BBTB && tuist generate 2>&1 | tail -5

# iOS Simulator Debug
xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20

# macOS Debug
xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination 'generic/platform=macOS' -configuration Debug build 2>&1 | tail -20

# Release config lint — Phase 1 SEC carry-forward: нет `print(`, `os_log(.debug` в release-built sources
grep -rn "print(" BBTB/Packages/*/Sources/ BBTB/App/ 2>/dev/null | grep -v "//" | head -20
grep -rn "os_log(.debug" BBTB/Packages/*/Sources/ BBTB/App/ 2>/dev/null | head -10
```

Failed builds → диагностика, фикс, re-build.

Если `print(` найден в production sources — заменить на `Logger.notice` / удалить (Phase 1 SEC carry-forward — Release builds не должны иметь debug-логи).

Reference: Phase 1 W5 — нет debug-логов в release config.
  </action>
  <verify>
    <automated>cd BBTB && tuist generate 2>&1 | tail -2 && xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -5 | grep -E "BUILD SUCCEEDED|BUILD FAILED"</automated>
  </verify>
  <done>iOS Simulator Debug build: BUILD SUCCEEDED; macOS Debug build: BUILD SUCCEEDED; `grep "print(" BBTB/Packages/*/Sources/**/*.swift | grep -v "//"` returns no production debug-prints (existing test prints допустимы).</done>
</task>

### Task W6.T2: Final commit + phase wrap-up

<task type="auto">
  <name>Task W6.T2: Phase 2 wrap-up — single final commit summarising W0-W6</name>
  <files>(commit only)</files>
  <action>
Final summary commit для wave 6:

```
chore(02/w6): Phase 2 build verification — iOS + macOS Debug builds green

Full Tuist regen + xcodebuild verified on both platforms.
No debug logs in Release config (Phase 1 SEC carry-forward).
All 9 packages unit + integration tests green.

UAT plan ready (.planning/phases/02-trojan-import-flow/02-UAT.md) — user to run
on real iPhone before /gsd-verify-work 2.

Ready for /gsd-execute-phase verification.

(02-W6.T1, 02-W6.T2)
```

После этого коммита — Phase 2 готова для:
- `/gsd-execute-phase 2` verification on real device (UAT)
- `/gsd-verify-work 2` (gap detection)
- Update STATE.md, ROADMAP, wiki (R11-pattern decisions from Phase 2 logged)
  </action>
  <verify>
    <automated>git log --oneline -1 | grep -E "Phase 2|02/w6"</automated>
  </verify>
  <done>Last commit message references Phase 2 build verification; working tree clean (`git status --short` empty).</done>
</task>

---

## Threat Model (Phase 2 STRIDE)

`security_enforcement = enabled` (Phase 1 carry-forward).

### Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Client app → Subscription URL provider | Untrusted: provider может вернуть malicious config (clash_api enabled, SOCKS inbound). |
| Client app → JSON endpoint provider | Untrusted: same as Subscription URL. |
| Pasteboard / QR camera → Universal parser | Untrusted: user может вставить malformed URI или scan random QR. |
| UserDefaults `app.bbtb.killSwitchEnabled` | Trusted (local), но изменения должны applied **на следующем connect** (D-14). |
| ConfigImporter → NETunnelProviderManager | Trusted boundary: всё что сюда попадает уже прошло `SingBoxConfigLoader.validate` (R1). |

### STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-02-01 | Spoofing | Subscription URL response (malicious operator) | mitigate | `SingBoxConfigLoader.validate` rejects clash_api/v2ray_api/cache_file/socks-inbound (R1 carry-forward) — applied after every fetch (RESEARCH §5.3 recommendation). |
| T-02-02 | Tampering | Subscription URL response in-flight | mitigate | HTTPS-only enforcement в `SubscriptionURLFetcher` (W1.T5) — `http://` rejected before fetch. URLSession использует system cert store. (Cert pinning DPI-08 → Phase 7.) |
| T-02-03 | Repudiation | n/a | accept | No audit log in Phase 2 — operator не attestable. Phase 12 TELEM-04 опционально логирует import events. |
| T-02-04 | Information Disclosure | Trojan password / VLESS uuid stored in Keychain | mitigate | KeychainStore с `kSecAttrAccessibleWhenUnlocked` (Phase 1 carry-forward). Unsupported configs (ss/vmess/...) **не имеют** keychainTag — secrets из их URI хранятся в `rawURI` ServerConfig field (raw URI содержит password в userinfo — это **acceptable**: user сам вставил URI plain-text в clipboard; SwiftData encrypts at-rest на iOS via Data Protection class). |
| T-02-05 | Information Disclosure | Camera permission scope | mitigate | NSCameraUsageDescription explicit: "QR-коды с конфигурациями VPN-серверов" — не general camera usage; AVCaptureMetadataOutput с types=[.qr] **только** — не сохраняем raw frames. |
| T-02-06 | Denial of Service | Subscription URL fetch timeout | mitigate | `URLSession.timeoutInterval = 30s` (RESEARCH §4.6); progress overlay UI отзывается. |
| T-02-07 | Denial of Service | Pool size > 50 servers (256KB iOS limit) | mitigate | `PoolBuilder.buildSingBoxJSON` truncates input to first 50 supported (RESEARCH §9.5). |
| T-02-08 | Elevation of Privilege | Kill Switch toggle bypass | mitigate | `KillSwitch.apply(to:enabled:)` is **only** mutator of `includeAllNetworks` / `enforceRoutes` (PATTERNS §2.25 invariant; Phase 1 W3 carry-forward). User toggle changes UserDefaults only — actual NEVPNProtocol mutation happens through `ConfigImporter.provisionTunnelProfile` (single call site). |
| T-02-09 | Spoofing | QR-code containing malicious URL (phishing) | mitigate | QR string → UniversalImportParser → only known schemes accepted; unknown URIs go to `.invalid` and don't reach NETunnelProviderManager. User sees alert «Не удалось распознать конфигурацию» (UI-SPEC §6.3). |
| T-02-10 | Tampering | Multi-protocol pool config injection | mitigate | `SingBoxConfigLoader.validate` (W0.T4 extended) now checks `urltest.outbounds` references — operator JSON с typo'ом или injection attempt будет rejected. |
| T-02-11 | Information Disclosure | `allowInsecure=1` URI param bypass (TLS validation skip) | mitigate | **Ignored** in `TrojanURIParser` (D-08, W1.T3 Test 10); `insecure: false` hardcoded in template (W1.T1); no code path can produce `insecure: true` outbound. |
| T-02-12 | Denial of Service | DNS resolves through dead outbound (RESEARCH §1.6) | mitigate | `dns.servers[].detour = urltest-out` in PoolBuilder (W1.T8) — DoH через тот же urltest pool; automatic failover same как traffic. |
| T-02-13 | Spoofing | V2Ray-style JSON config (`outbounds[].protocol`) operator confuses with sing-box | mitigate | `SubscriptionURLFetcher.detectFormat` returns `.v2rayJSON(reason:)` distinct case; `UniversalImportParser` throws `.v2rayJSONUnsupported`; user sees error «Формат V2Ray не поддерживается» (W4.T2). |

**R11 carry-forward (Phase 1 closed decisions):** все Phase 1 mitigations (R1 inbound whitelist, R4 default `excludeLocalNetworks=false/disconnectOnSleep=false`, R5 macOS enforceRoutes hook, R6 P2P=false, R10 TUN inbound runtime expansion) — **не откатываются** в Phase 2. Если W0.T4 (validate extension) или W1.T8 (PoolBuilder) сгенерируют config, нарушающий R1 — это **должно быть пойдено в unit-test** (Test 4 W0.T4: forbiddenInboundType; Test 4 W1.T8: validate passes).

---

## Verification (phase-level)

### Goal-Backward Coverage Matrix

Map каждого из **8 ROADMAP success criteria** на конкретные wave/task(s):

| ROADMAP SC | Description | Covered by |
|------------|-------------|------------|
| **SC-1** | Импорт через все три формата (URI / multi-line / subscription / JSON endpoint) + QR; unsupported протоколы парсятся с isSupported=false без отказа | W1.T3-T8 (parsers), W1.T9 (Pool), W3.T1 (ConfigImporter), W4.T7 (QR), W5.T1 Test 1-5 (integration), W5.T2 T1-T4 (UAT) |
| **SC-2** | Auto-fallback через urltest при блокировке активного outbound | W1.T8 (PoolBuilder.urltest), W0.T4 (validate accepts urltest), W0.T5 (DNS detour), W5.T2 T6 (UAT failover test) |
| **SC-3** | Trojan handler работает на TCP+TLS и WS+TLS | W1.T1 (templates), W1.T2 (ConfigBuilder), W1.T3 (parser), W2.T1 (registration), W2.T2 (smoke), W5.T1 Tests 3+4, W5.T2 T5 (UAT IP change) |
| **SC-4** | Kill Switch toggle в Settings → Безопасность; применяется на след. connect; reconnect banner если active | W0.T2 (KillSwitch.apply parameterised), W3.T1 (UserDefaults read), W3.T2 (banner state), W4.T6 (SettingsView), W5.T1 Test 6 (round-trip), W5.T2 T7+T8+T9 (UAT) |
| **SC-5** | Камера запрашивает permission корректно iOS + macOS | W4.T7 (CameraPermission, QRScannerView), W4.T8 (Info.plist + macOS entitlement), W5.T2 T4 (UAT first-run permission) |
| **SC-6** | MainScreen rewritten: top bar (≡/+), idle layout, empty-state card | W0.T3 (StatusBadge rename), W4.T3 (visual rewrite), W4.T4 (new components), W4.T5 (MainScreenView rewrite), W4.T9 (NavigationStack + Settings Scene), W5.T2 T5+T9 (UAT visual check) |
| **SC-7** | SwiftData массив ServerConfig — Phase 1 singleton мигрирован | W0.T1 (schema extension), W3.T1 (ConfigImporter multi-row save), W5.T1 Test 7 (replace-pool D-07) |
| **SC-8** | Unit-test suite зелёный (parsers, Trojan, urltest, kill switch parameterisation) | W0.T6 (Phase 1 regression), W1.T9 (Wave 1 regression), W3.T3 (Wave 3 regression), W5.T3 (final), W6.T1 (build verify) |

✅ **Все 8 success criteria covered.**

### Claude's Discretion Items Coverage (CONTEXT)

| Discretion Item | Disposition |
|-----------------|-------------|
| Menu icon top bar left (`line.3.horizontal`) | W4.T4 TopBar.swift — `line.3.horizontal` SF Symbol (no implementation difference from default). |
| Empty-state card icon (`tray` SF Symbol) | W4.T4 EmptyStateCard.swift — `Image(systemName: "tray")` (UI-SPEC §3.2). |
| HTTP-probe URL (`cp.cloudflare.com/generate_204`) | W1.T8 PoolBuilder.swift — hardcoded в urltest dict. |
| urltest interval=1m, tolerance=50ms, idle_timeout=30m | W1.T8 — hardcoded per RESEARCH §1.4 recommendation. |
| Subscription parser fallback chain (JSON → URI prefix → base64) | W1.T7 UniversalImportParser.classify per RESEARCH §6.3 order. |
| Subscription User-Agent `BBTB/0.2` | W1.T5 SubscriptionURLFetcher.fetch HTTP header. |
| macOS Settings via `Settings { }` Scene + Cmd+, | W4.T9 BBTB_macOSApp.swift. |
| Camera permissions copy (NSCameraUsageDescription text) | W4.T8 Info.plist strings — RU text per CONTEXT Claude's Discretion. |
| Trojan template files (`SingBoxConfigTemplate.trojan-tcp.json`, `.trojan-ws.json`) | W1.T1 two separate files (Option A from RESEARCH §2.6 — recommended). |
| ConfigBuilder refactor scope (per-protocol + Pool separate, not unified Codable) | W1.T2 + W1.T8 — per-protocol ConfigBuilder + separate PoolBuilder; Codable migration deferred to Phase 4. |

✅ **Все Claude's Discretion items covered.**

### Multi-Source Coverage Audit (planner self-check)

**GOAL** (ROADMAP Phase 2): mapped to waves as above.

**REQ** (REQUIREMENTS.md):
- **PROTO-02** Trojan — W1.T1-T3, W2.T1.
- **PROTO-10** Auto-fallback — W1.T8 (PoolBuilder urltest).
- **IMP-02** QR import — W4.T7, W4.T8.
- **KILL-03** Kill Switch toggle — W0.T2, W3.T1, W4.T6.
- **IMP-04 foundation** universal URI parser + subscription URL fetch — W1.T5, W1.T7.
- **IMP-05 foundation** все URI-схемы распознаются — W1.T4 (StubParsers).
- **TRANSP-03 foundation** WebSocket transport для Trojan — W1.T1 (trojan-ws template).
- **SRV-01/02/03 foundation** SwiftData массив + isSupported + subscriptionURL — W0.T1, W3.T1.

**RESEARCH** (12 sections):
- §1 urltest — W1.T8.
- §2 Trojan outbound schema — W1.T1.
- §3 Trojan URI scheme — W1.T3.
- §4 Subscription URL formats — W1.T5, W1.T7.
- §5 JSON endpoint — W1.T6, W1.T7.
- §6 Universal parser architecture — W1.T7.
- §7 validate extension — W0.T4.
- §8 AVFoundation QR — W4.T7.
- §9 NETunnelProviderManager — W3.T1.
- §10 SwiftData migration — W0.T1.

**CONTEXT** (15 decisions D-01..D-15):
- D-01 Auto-fallback inside sing-box — W1.T8 + W3.T1.
- D-02 Three import formats — W1.T5-T7.
- D-03 Leadaxe as spec only — embedded in W1.T7 design.
- D-04 Universal parser, all schemes recognised — W1.T4.
- D-05 Trojan TCP+TLS + WS+TLS — W1.T1-T3.
- D-06 SwiftData array — W0.T1, W3.T1.
- D-07 subscriptionURL metadata + replace-pool — W3.T1 + W5.T1 Test 7.
- D-08 Trojan URI strict TLS — W1.T3.
- D-09 MainScreen layout — W4.T3-T5.
- D-10 Empty-state card — W4.T4.
- D-11 ServerLineView — W4.T4.
- D-12 Settings page Безопасность section — W4.T6.
- D-13 Toggle без confirmation — W4.T6.
- D-14 Apply on next connect + banner — W3.T1, W3.T2, W4.T5.
- D-15 KillSwitch.apply enabled parameter — W0.T2.

✅ **All 15 decisions mapped.**

✅ **No unplanned items detected.**

### Phase 2 Out of Scope (mentioned briefly)

Per CONTEXT + task prompt — Phase 2 explicitly NOT implementing:

- **IMP-03 file picker** — Phase 11 (UX-01 onboarding) как угловая ссылка «У меня уже есть конфиг файл».
- **Server-list UI** (UX-04, SRV-* full) — Phase 3.
- **Multi-subscription URLs UI** (SRV-02 finish) — Phase 3.
- **Full Settings sections** (Подписки UI, Уведомления, Внешний вид, Помощь, О приложении, Расширенные beyond Безопасность) — Phase 4 / 10 / 11.
- **Final Figma design** (UX-08, UX-09) — Phase 11. На v0.2 — placeholder с DesignSystem tokens.
- **Anti-DPI suite** (DPI-01..09) — Phase 7.
- **macOS R5 enforceRoutes toggle** (KILL-04) — Phase 10. Hook уже зарезервирован в `KillSwitch.platformShouldDisableEnforceRoutes()`.

---

## Success Criteria (PLAN-level, executor's checklist)

При завершении Phase 2:

- [ ] Все 6 waves имеют ≥1 commit.
- [ ] Total commits: 25–32.
- [ ] All 9 packages (VPNCore, PacketTunnelKit, KillSwitch, Localization, DesignSystem, ConfigParser, AppFeatures, VLESSReality, Trojan) — `swift test` зелёный.
- [ ] iOS Simulator Debug build — `BUILD SUCCEEDED`.
- [ ] macOS Debug build — `BUILD SUCCEEDED`.
- [ ] No `print(` или `os_log(.debug` в production sources (Phase 1 SEC carry-forward).
- [ ] `02-UAT.md` создан и содержит T1-T9.
- [ ] Все 15 CONTEXT D-xx decisions реализованы (см. Goal-Backward Coverage Matrix).
- [ ] R1 / R6 / R10 / R11 Phase 1 invariants не нарушены (validated через integration tests W5.T1).

После /gsd-execute-phase 2 завершения — пользователь запускает `02-UAT.md` тесты на iPhone, и при ≥7/9 PASS → `/gsd-verify-work 2` → Phase 2 closeout.

<output>
After Wave 6 completion (or per-wave summaries), создать `.planning/phases/02-trojan-import-flow/02-W{N}-{name}-SUMMARY.md` для каждого wave с фактически реализованным шагом, найденными отклонениями от плана, и any deferred items (если pop'нулись).
</output>

---

*Phase 2 plan v1.0 — 2026-05-12.*
*Authored by `gsd-planner` agent.*
*Total waves: 7 (W0-W6). Total tasks: 34. Expected commits: 25-32.*
*Source: 02-CONTEXT.md (15 decisions D-01..D-15), 02-RESEARCH.md (12 deep-dive sections), 02-PATTERNS.md (33 component mappings), 02-UI-SPEC.md (13 sections), ROADMAP.md Phase 2 (8 success criteria), REQUIREMENTS.md (4 in-phase + 6 foundation REQ IDs).*
*Downstream: `gsd-plan-checker` (validation), `gsd-execute-phase 2` (executor agent).*
