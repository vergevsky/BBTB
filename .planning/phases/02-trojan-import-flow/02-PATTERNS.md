# Phase 2: Trojan + Import flow — Pattern Map

**Mapped:** 2026-05-11
**Files analyzed (Phase 1 codebase):** 38 source files across 11 packages
**New/changed components in Phase 2:** 30+
**Analogs found:** 18 / 30 strong matches; 12 NEW patterns flagged

---

## 1. File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|-------------------|------|-----------|----------------|-------|
| `Packages/Protocols/Trojan/Package.swift` | package manifest | n/a | `Packages/Protocols/VLESSReality/Package.swift` | exact |
| `Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift` | protocol handler | request-response (stub) | `VLESSRealityHandler.swift` | exact |
| `Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` | template-substitution | transform | `VLESSReality/ConfigBuilder.swift` | exact |
| `Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json` | sing-box template | n/a | `SingBoxConfigTemplate.vless-reality.json` | exact |
| `Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json` | sing-box template | n/a | `SingBoxConfigTemplate.vless-reality.json` (transport-extension) | role-match |
| `Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift` | test | n/a | `VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift` | exact |
| `Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` | URI parser | transform | `VLESSURIParser.swift` | exact |
| `Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` | facade/router | transform | n/a — **NEW** | none |
| `Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` | HTTP fetcher | request-response | n/a — **NEW** | none |
| `Packages/ConfigParser/Sources/ConfigParser/JSONEndpointFetcher.swift` | HTTP fetcher | request-response | `SubscriptionURLFetcher.swift` (sibling, also NEW) | none |
| `Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` | assembler | transform | `VLESSReality/ConfigBuilder.swift` (JSON mutation idea) | role-match |
| `Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift` | test | n/a | `VLESSURIParserTests.swift` | exact |
| `Packages/ConfigParser/Tests/ConfigParserTests/UniversalImportParserTests.swift` | test | n/a | `VLESSURIParserTests.swift` (style only) | role-match |
| `Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` | SwiftUI screen | event-driven | `MainScreenView.swift` (SwiftUI layout) | role-match |
| `Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` | view-model | event-driven | `MainScreenViewModel.swift` | exact |
| `Packages/AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift` | SwiftUI subview | event-driven | `StatusBadge.swift` (small subview component) | role-match |
| `Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` (rewrite) | SwiftUI screen | event-driven | self (current `MainScreenView.swift`) | exact |
| `Packages/AppFeatures/Sources/MainScreenFeature/EmptyStateCard.swift` | SwiftUI subview | event-driven | `ImportFromClipboardButton.swift` | exact |
| `Packages/AppFeatures/Sources/MainScreenFeature/TopBar.swift` | SwiftUI subview | event-driven | `MainScreenView.swift` `private var header` | role-match |
| `Packages/AppFeatures/Sources/MainScreenFeature/ServerLineView.swift` | SwiftUI subview | event-driven | `MainScreenView.swift` `private var footer` | role-match |
| `Packages/AppFeatures/Sources/MainScreenFeature/StatusPill.swift` | SwiftUI subview | event-driven | `StatusBadge.swift` | exact |
| `Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift` | SwiftUI subview | event-driven | n/a — **NEW** | none |
| `Packages/AppFeatures/Sources/MainScreenFeature/QRScannerView.swift` | UIView/NSView representable | event-driven | n/a — **NEW** | none |
| `Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (rewrite) | importer/orchestrator | event-driven | self (current `ConfigImporter.swift`) | exact |
| `Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (rewrite) | view-model | event-driven | self (current) | exact |
| `Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` (minor) | tunnel API wrapper | request-response | self (current) | exact |
| `Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` (extend) | SwiftData @Model | CRUD | self (current) | exact |
| `Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` (signature change) | utility | transform | self (current) | exact |
| `Packages/Localization/Resources/Localizable.xcstrings` (extend) | i18n catalog | n/a | self (current keys) | exact |
| `Packages/Localization/Sources/Localization/L10n.swift` (extend) | i18n accessor | n/a | self (current `L10n` enum) | exact |
| `App/iOSApp/BBTB_iOSApp.swift` (modify) | app composition root | event-driven | self (current) | exact |
| `App/macOSApp/BBTB_macOSApp.swift` (modify) | app composition root | event-driven | self (current) | exact |
| `BBTB/Project.swift` (extend) | Tuist manifest | n/a | self (current — VLESSReality registration block) | exact |
| `App/iOSApp/Info.plist` (extend) | plist | n/a | self (current) | exact |
| `App/macOSApp/Info.plist` (extend) | plist | n/a | self (current) | exact |
| `App/iOSApp/BBTB-iOS.entitlements` (extend) | entitlements | n/a | self (current) | exact |
| `App/macOSApp/BBTB-macOS.entitlements` (extend) | entitlements | n/a | self (current) | exact |

---

## 2. Pattern Assignments

### 2.1 `Packages/Protocols/Trojan/Package.swift` (package manifest)

**Analog:** `Packages/Protocols/VLESSReality/Package.swift` (lines 1–33, exact copy with name swap)

**Pattern to reuse — full file template:**
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trojan",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Trojan", targets: ["Trojan"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "Trojan",
            dependencies: ["VPNCore", "PacketTunnelKit"],
            path: "Sources/Trojan",
            resources: [
                .process("Resources/SingBoxConfigTemplate.trojan-tcp.json"),
                .process("Resources/SingBoxConfigTemplate.trojan-ws.json"),
            ]
        ),
        .testTarget(
            name: "TrojanTests",
            dependencies: ["Trojan"],
            path: "Tests/TrojanTests",
            linkerSettings: [
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
```

**Key changes vs. VLESSReality `Package.swift`:**
- Two resource entries instead of one (Trojan has tcp + ws templates).
- VLESSReality `Package.swift` does NOT declare resources because the template lives in `PacketTunnelKit/Resources/`. **Decision point for planner:** Phase 1 placed VLESS-Reality template in `PacketTunnelKit/Resources/` and loads via `SingBoxConfigLoader.loadVLESSRealityTemplate()`. For Trojan, either (a) keep the same pattern (templates in `PacketTunnelKit/Resources/`) for consistency, or (b) move templates into the protocol package itself (more modular but breaks the existing loader pattern). **Recommended (b)** — templates live with the protocol; loader function is added to `Trojan/ConfigBuilder.swift` using `Bundle.module.url(forResource:withExtension:)`.

---

### 2.2 `Trojan/Sources/Trojan/TrojanHandler.swift`

**Analog:** `Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift` (lines 1–46, full file)

**Pattern to reuse:**
```swift
import Foundation
import VPNCore

public struct TrojanHandler: VPNProtocolHandler {
    public static let identifier = "trojan"
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
        public var errorDescription: String? {
            switch self {
            case .identifierMismatch(let e, let g): return "Handler ID mismatch: expected \(e), got \(g)"
            }
        }
    }
}
```

**Key invariants to preserve from analog:**
- `struct VPNProtocolHandler` (not `class`) — Sendable by value.
- `static let identifier` — used as key in `ProtocolRegistry`; choose `"trojan"` (lowercase, matches URI scheme).
- `connect`/`disconnect` remain no-ops in v0.2 (same as VLESSReality). Real start goes through `NETunnelProviderManager.connection.startVPNTunnel()` per `TunnelController.swift` lines 12–37.
- `HandlerError.identifierMismatch` is the only error case Phase 1 needed; Phase 2 can reuse same minimal surface.

---

### 2.3 `Trojan/Sources/Trojan/ConfigBuilder.swift`

**Analog:** `Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift` (lines 1–88)

**Pattern to reuse — input struct + builder enum + template loader:**
```swift
public enum ConfigBuilder {
    public struct TrojanInputs {
        public let host: String
        public let port: Int
        public let password: String
        public let sni: String
        public let fingerprint: String        // uTLS, default "chrome"
        public let alpn: [String]             // default ["h2", "http/1.1"]
        public let transport: TransportType   // .tcp or .ws(path, host)
        public let remark: String?
    }
    public enum TransportType: Equatable {
        case tcp
        case ws(path: String, host: String)
    }

    public enum BuilderError: Error, LocalizedError {
        case templateLoadFailed(Error)
        case invalidPort(Int)
        case missingPassword
        case missingSNI
        // errorDescription cases — same pattern as VLESSReality.BuilderError
    }

    public static func buildSingBoxJSON(from inputs: TrojanInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        guard !inputs.password.isEmpty else { throw BuilderError.missingPassword }
        guard !inputs.sni.isEmpty else { throw BuilderError.missingSNI }  // R1: SNI mandatory for DPI-resistance

        let templateName: String
        switch inputs.transport {
        case .tcp:        templateName = "SingBoxConfigTemplate.trojan-tcp"
        case .ws:         templateName = "SingBoxConfigTemplate.trojan-ws"
        }
        let template = try loadTemplate(named: templateName)

        var filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: inputs.host)
            .replacingOccurrences(of: "${TROJAN_PASSWORD}", with: inputs.password)
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: inputs.fingerprint)
        if case .ws(let path, let host) = inputs.transport {
            filled = filled
                .replacingOccurrences(of: "${WS_PATH}", with: path)
                .replacingOccurrences(of: "${WS_HOST}", with: host.isEmpty ? inputs.sni : host)
        }
        if inputs.port != 443 { return try mutatePort(in: filled, to: inputs.port) }
        return filled
    }

    private static func mutatePort(in json: String, to port: Int) throws -> String {
        // identical to VLESSReality/ConfigBuilder.swift lines 73–87
    }

    private static func loadTemplate(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw BuilderError.templateLoadFailed(NSError(domain: "Trojan.ConfigBuilder", code: -1))
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

**Key invariants to preserve (Phase 1 W5 learnings, see VLESSReality `ConfigBuilder` line 56–63):**
- **Hard-coded** placeholders ONLY — never embed user data outside `${...}`. Phase 1 W5 root cause was `${VLESS_FLOW}` hardcoded as `xtls-rprx-vision` in template; same trap exists for Trojan transport, password, SNI.
- `mutatePort` reused verbatim — same JSON shape, same approach.
- `Bundle.module` access requires SwiftPM `resources: [.process(...)]` declaration (see `Localization/Package.swift` lines 9–14 and `PacketTunnelKit/Package.swift` lines 19–22).

---

### 2.4 `Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json`

**Analog:** `PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` (lines 1–77)

**Pattern to reuse — same outer shape (log/dns/outbounds/route/experimental), Trojan-specific outbound block:**
```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "dns-remote", "address": "https://cloudflare-dns.com/dns-query",
        "address_resolver": "dns-bootstrap", "address_strategy": "ipv4_only",
        "detour": "trojan-out" },
      { "tag": "dns-bootstrap", "address": "tcp://77.88.8.8",
        "detour": "direct", "strategy": "ipv4_only" },
      { "tag": "dns-fakeip", "address": "fakeip" }
    ],
    "rules": [ /* identical to vless-reality template */ ],
    "fakeip": { /* identical */ },
    "final": "dns-remote", "strategy": "ipv4_only", "independent_cache": true
  },
  "outbounds": [
    {
      "type": "trojan",
      "tag": "trojan-out",
      "server": "${SERVER_HOST}",
      "server_port": 443,
      "password": "${TROJAN_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
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

**Trojan-WS template** (`.trojan-ws.json`) adds `"transport"` block to outbound:
```json
"transport": {
  "type": "ws",
  "path": "${WS_PATH}",
  "headers": { "Host": "${WS_HOST}" }
}
```

**Pattern invariants from `vless-reality.json` template (lines 40–67):**
- Outbound `tag` matches `route.final` and DNS `detour` (here `"trojan-out"` instead of `"vless-out"`).
- Always include `"direct"` outbound — used by `dns-bootstrap` (template line 19 references it).
- `experimental: {}` — empty object, not absent — R1 validate at `SingBoxConfigLoader.swift` line 75 expects key presence is OK but no enabled `clash_api`/`v2ray_api`/`cache_file`.
- Hard-coded `server_port: 443` is mutated post-substitution if user URI port differs (see `mutatePort`, ConfigBuilder lines 73–87).

---

### 2.5 `Trojan/Tests/TrojanTests/ConfigBuilderTests.swift`

**Analog:** `VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift` (lines 1–88, 4 test methods)

**Pattern to reuse — XCTest layout + R1 self-check via `SingBoxConfigLoader.validate`:**
```swift
import XCTest
import PacketTunnelKit
@testable import Trojan

final class ConfigBuilderTests: XCTestCase {
    func test_buildSingBoxJSON_tcp_filled_passesValidate() throws {
        let inputs = ConfigBuilder.TrojanInputs(
            host: "example.com", port: 443, password: "secret",
            sni: "vpn.example.ru", fingerprint: "chrome",
            alpn: ["h2", "http/1.1"], transport: .tcp, remark: nil
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        XCTAssertFalse(json.contains("${TROJAN_PASSWORD}"))
        XCTAssertTrue(json.contains("\"secret\""))
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }
    func test_buildSingBoxJSON_ws_includesTransportBlock() throws { /* ... */ }
    func test_buildSingBoxJSON_nonDefaultPort_mutatesPort() throws { /* same pattern as VLESSReality */ }
    func test_buildSingBoxJSON_missingPassword_throws() { /* ... */ }
    func test_buildSingBoxJSON_missingSNI_throws() { /* R1 invariant */ }
}
```

**WARNING for planner:** `SingBoxConfigLoader.validate` (PacketTunnelKit/SingBoxConfigLoader.swift line 92–94) currently has `hasVLESS` check — Trojan configs WILL FAIL this check. **This is a required Phase 2 modification** to `SingBoxConfigLoader.validate`: either relax `noVLESSOutbound` to `noKnownOutbound` (accept vless OR trojan OR urltest), or remove the protocol-specific check entirely (relies on outbounds being non-empty + `route.final` referencing a valid tag). Researcher should consult.

---

### 2.6 `ConfigParser/Sources/ConfigParser/TrojanURIParser.swift`

**Analog:** `Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` (lines 1–88)

**Pattern to reuse — `ParsedX` struct (Sendable, Equatable) + error enum + static `parse(_:)`:**
```swift
import Foundation
import VPNCore

public struct ParsedTrojan: Sendable, Equatable {
    public let password: String
    public let host: String
    public let port: Int
    public let security: String          // must be "tls"
    public let sni: String
    public let fingerprint: String       // default "chrome"
    public let alpn: [String]            // default ["h2", "http/1.1"]
    public let transport: TransportType  // .tcp or .ws(path, host)
    public let remarks: String?

    public enum TransportType: Sendable, Equatable {
        case tcp
        case ws(path: String, host: String)
    }
    // init( ... ) — all-args; same style as ParsedVLESS lines 17-24
}

public enum TrojanURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingPassword
    case notTLSSecurity(String?)
    case invalidTransport(String)
    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed trojan:// URI"
        case .missingPassword: return "Trojan password missing in userinfo"
        case .notTLSSecurity(let s): return "Trojan requires security=tls (got: \(s ?? "missing"))"
        case .invalidTransport(let t): return "Unsupported transport: \(t)"
        }
    }
}

public enum TrojanURIParser {
    public static func parse(_ uri: String) throws -> ParsedTrojan {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "trojan",
              let host = comps.host, !host.isEmpty,
              let port = comps.port,
              let password = comps.user, !password.isEmpty
        else { throw TrojanURIError.malformedURI }

        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }

        let security = q["security"] ?? "tls"  // some clients omit; default tls
        guard security == "tls" else { throw TrojanURIError.notTLSSecurity(security) }

        // R1 principle: `allowInsecure=1` is IGNORED (not failed) — see D-08 in CONTEXT.md
        // sni — fallback to host (D-08)
        let sni = q["sni"]?.isEmpty == false ? q["sni"]! : host
        let fingerprint = (q["fp"] ?? q["fingerprint"])?.isEmpty == false
            ? (q["fp"] ?? q["fingerprint"])! : "chrome"
        let alpn = (q["alpn"]?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }) ?? ["h2", "http/1.1"]

        let type = q["type"] ?? "tcp"
        let transport: ParsedTrojan.TransportType
        switch type {
        case "tcp": transport = .tcp
        case "ws":
            let path = q["path"] ?? "/"
            let wsHost = q["host"]?.isEmpty == false ? q["host"]! : sni
            transport = .ws(path: path, host: wsHost)
        default: throw TrojanURIError.invalidTransport(type)
        }

        return ParsedTrojan(
            password: password.removingPercentEncoding ?? password,
            host: host, port: port, security: "tls",
            sni: sni, fingerprint: fingerprint, alpn: alpn,
            transport: transport,
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
```

**Pattern invariants from `VLESSURIParser.swift` (lines 44–87):**
- `URLComponents(string:)` for RFC-correct parsing — NOT manual regex.
- Trim whitespace first (line 45) — supports `"  vless://...\n"` (multi-line pasteboard).
- Query params into `[String: String]` dict (lines 56–60).
- Defaults for optional fields are explicit string literals, NOT `nil` — so downstream `ConfigBuilder` always has a value (see VLESSURIParser lines 78–84).
- Remarks via `comps.fragment?.removingPercentEncoding` — supports URL-encoded names like `#%D0%9B%D0%B0%D1%82%D0%B2%D0%B8%D1%8F` → `"Латвия"`.

---

### 2.7 `ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — **NEW PATTERN**

**Analog:** No direct match in Phase 1. Closest stylistic referent is `ConfigImporter.swift` (lines 58–141) which orchestrates parse→build→persist; UniversalImportParser does the parse+classify front-half only.

**Recommended structure (Claude-derived, planner to refine):**
```swift
public struct ParsedImport: Sendable, Equatable {
    public let outbounds: [SupportedOutbound]   // for urltest pool
    public let unsupported: [UnsupportedOutbound]  // SwiftData with isSupported=false
    public let subscriptionURL: String?         // if input was sub:// or HTTPS subscription
}

public enum SupportedOutbound: Sendable, Equatable {
    case vlessReality(ParsedVLESS)
    case trojan(ParsedTrojan)
    // Phase 4+: shadowsocks, vmess, hysteria2, wireguard, etc.
}

public struct UnsupportedOutbound: Sendable, Equatable {
    public let scheme: String     // "ss", "vmess", "hy2", "wireguard", etc.
    public let rawURI: String     // store as-is so future phases can re-activate
    public let remarks: String?
}

public enum UniversalImportError: Error, LocalizedError {
    case empty
    case noValidEntries
    case subscriptionFetchFailed(Error)
    case jsonEndpointFetchFailed(Error)
    case unsupportedScheme(String)
}

public actor UniversalImportParser {
    public init() {}

    /// Main entry — classifies raw input and routes to sub-parsers/fetchers.
    public func parse(rawInput: String) async throws -> ParsedImport {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UniversalImportError.empty }

        // Detection chain (per D-02 + Claude's Discretion):
        // 1. Single HTTPS URL → SubscriptionURLFetcher OR JSONEndpointFetcher
        // 2. Single URI scheme line (vless://, trojan://) → per-protocol parser
        // 3. Multi-line text → parse each line, aggregate
        if isSingleHTTPSURL(trimmed) {
            // Fetch body, detect content-type
            let body = try await SubscriptionURLFetcher.fetch(url: trimmed)
            return try await parse(rawInput: body)  // recurse on body
                .withSubscriptionURL(trimmed)
        }
        return try parseMultiLine(trimmed)
    }

    private func parseMultiLine(_ text: String) throws -> ParsedImport { /* ... */ }
    private func isSingleHTTPSURL(_ s: String) -> Bool { /* URL(string:) + scheme check */ }
}
```

**Key patterns to inherit from Phase 1:**
- `Sendable` + `Equatable` for all data carriers (`ParsedVLESS` pattern, VLESSURIParser line 4).
- `LocalizedError` for user-facing errors (`ImporterError` pattern, `ConfigImporter.swift` lines 21–39).
- `actor` for stateful coordinators OR `public enum` for pure-function parsers (VLESSURIParser uses `enum` namespace; UniversalImportParser has async work → use `actor`).
- Errors expose enough info for the UI: see `ImporterError.malformedURI(Error)` wrapping the underlying parser error (line 22).

**Subscription URL fallback chain** (per CONTEXT.md "Claude's Discretion"):
1. If body starts with `{` → JSON endpoint.
2. Else try base64-decode → if ASCII-printable URI list → split `\n`.
3. Else plain-text → split `\n`.

---

### 2.8 `ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` — **NEW PATTERN**

**Analog:** None in Phase 1 (Phase 1 had no HTTP fetching — only sing-box outbound traffic).

**Pattern to establish (planner + researcher to validate via Codex):**
```swift
public enum SubscriptionURLFetcher {
    public enum FetchError: Error, LocalizedError {
        case invalidURL(String)
        case insecureScheme           // R1-spirit: HTTPS-only for subscription URLs
        case httpError(Int)
        case decodingFailed
        case timeout

        public var errorDescription: String? { /* user-facing strings */ }
    }

    public static func fetch(url urlString: String, timeout: TimeInterval = 15) async throws -> String {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            throw FetchError.invalidURL(urlString)
        }
        guard scheme == "https" else { throw FetchError.insecureScheme }  // R1-spirit

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("BBTB/0.2", forHTTPHeaderField: "User-Agent")  // CONTEXT.md "Subscription User-Agent"
        request.setValue("text/plain, application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.httpError(0) }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.httpError(http.statusCode) }

        guard let body = String(data: data, encoding: .utf8) else { throw FetchError.decodingFailed }
        return body
    }
}
```

**Key invariants (Claude-derived from CONTEXT.md decisions D-02 + Claude's Discretion):**
- HTTPS-only — `http://` reject. R1-spirit (subscription URL is a credential — should not travel in clear-text).
- User-Agent `"BBTB/0.2"` — protocol-compatibility with subscription panels (Marzban, X-UI).
- No certificate pinning in v0.2 (DPI-08 deferred to Phase 7).
- Returns raw body string — caller (UniversalImportParser) decides base64 vs JSON vs plaintext.

---

### 2.9 `ConfigParser/Sources/ConfigParser/JSONEndpointFetcher.swift` — **NEW PATTERN**

**Analog:** `SubscriptionURLFetcher.swift` (sibling — also NEW; minor variant).

**Pattern:**
```swift
public enum JSONEndpointFetcher {
    public static func fetch(url urlString: String, timeout: TimeInterval = 15) async throws -> String {
        // Same HTTPS check + User-Agent as SubscriptionURLFetcher.
        // Sets Accept: application/json explicitly.
        // Body must pass JSONSerialization.jsonObject(with:) sanity check before return.
        // Caller then passes through SingBoxConfigLoader.validate (see ConfigImporter pipeline).
    }
}
```

**Key invariant:** After fetch, the body MUST be passed through `SingBoxConfigLoader.validate(json:)` (PacketTunnelKit/SingBoxConfigLoader.swift line 57) BEFORE persisting — R1 guarantee that no SOCKS/clash_api gets through via JSON endpoint trust.

---

### 2.10 `ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — **NEW PATTERN** (extends ConfigBuilder idea)

**Analog:** `VLESSReality/ConfigBuilder.swift` lines 73–87 — `mutatePort` shows the JSON-mutation pattern that PoolBuilder generalizes.

**Pattern to establish:**
```swift
public enum PoolBuilder {
    public struct PoolInputs: Sendable {
        public let outbounds: [String]   // each is a sing-box outbound JSON (single object, not full config)
        public let probeURL: String      // e.g., "https://cp.cloudflare.com/generate_204"
        public let interval: String      // sing-box duration string, e.g. "1m"
        public let tolerance: String     // e.g., "50ms"
        public let idleTimeout: String   // e.g., "30m"
    }

    public enum BuilderError: Error, LocalizedError {
        case noOutbounds
        case malformedOutbound(Int, Error)  // index + underlying
    }

    /// Build full sing-box config with N protocol outbounds + urltest selector + direct.
    /// Pool builder loads the "pool" template (with log/dns/route blocks) and injects
    /// outbounds array. Uses the same template-substitution pattern as per-protocol builders.
    public static func build(_ inputs: PoolInputs) throws -> String {
        // 1. Load Resources/SingBoxConfigTemplate.pool.json (NEW template — same shape
        //    as vless-reality.json but with `urltest` outbound placeholder).
        // 2. JSON-mutation: replace outbounds array with parsed inputs.outbounds + urltest + direct.
        // 3. Set route.final = "urltest-out".
        // 4. Validate via SingBoxConfigLoader.validate before return.
    }
}
```

**Pool template** (`Resources/SingBoxConfigTemplate.pool.json`) — recommended location: `PacketTunnelKit/Sources/PacketTunnelKit/Resources/` (consistent with vless-reality.json) OR new `ConfigParser/Sources/ConfigParser/Resources/`. **Recommended: `PacketTunnelKit/Resources/`** for two reasons: (1) `SingBoxConfigLoader` already has a `loadVLESSRealityTemplate()` symmetric API to add `loadPoolTemplate()`; (2) avoids ConfigParser depending on PacketTunnelKit (currently it only depends on VPNCore — see `ConfigParser/Package.swift` line 7).

**Key invariants from `ConfigBuilder.mutatePort` (lines 73–87):**
- `JSONSerialization.jsonObject(with:)` → `[String: Any]` mutation → `JSONSerialization.data(withJSONObject:options:)`.
- Always re-encode to UTF-8 string before return.
- Empty/malformed input returns original JSON unchanged (defensive).

---

### 2.11 `AppFeatures/Sources/SettingsFeature/SettingsView.swift`

**Analog:** `MainScreenView.swift` (lines 1–63) — overall SwiftUI structure (`View` protocol, `@ObservedObject` viewModel, body composing subviews).

**Pattern to reuse:**
```swift
import SwiftUI
import Localization

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
                Text(L10n.settingsSecurityHeader)
            }
        }
        .navigationTitle(L10n.settingsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
```

**Pattern invariants from `MainScreenView.swift`:**
- `public struct` + `public var body: some View` (line 4 + line 8).
- `@ObservedObject public var viewModel:` — NOT `@StateObject`; ownership lives in the app composition root (`BBTB_iOSApp.swift` line 14 + 45).
- `public init` — explicit, accepts dependencies (line 6).
- All UI strings come through `L10n` namespace — never literal Russian or English strings in View bodies (see every `L10n.xxx` access in `MainScreenView.swift` and `StatusBadge.swift`).

---

### 2.12 `AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift`

**Analog:** `MainScreenViewModel.swift` (lines 1–72)

**Pattern to reuse:**
```swift
import Foundation
import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = true

    public init() {}
    // Phase 2: simple binding to UserDefaults — no async work, no orchestration.
    // Phase 4+: this VM will grow (subscriptions, advanced settings, etc.).
}
```

**Pattern invariants from `MainScreenViewModel.swift`:**
- `@MainActor` annotation on the class (line 5) — UI updates must be on main.
- `public final class ... : ObservableObject` (line 6).
- `@Published public private(set) var` for read-only state (line 7); `@Published public var` for two-way (line 9, `lastError`).
- Constructor takes dependencies as protocol-typed parameters (line 14 — `importer: ConfigImporting`). For SettingsViewModel in v0.2 there are no dependencies — the kill switch flag is just `@AppStorage`.

**`@AppStorage` justification (per D-14):** Flag is NOT per-`ServerConfig`, it's app-global → `UserDefaults` is correct. Key `"app.bbtb.killSwitchEnabled"` matches the integration point in CONTEXT.md line 241.

---

### 2.13 `AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift`

**Analog:** `StatusBadge.swift` (lines 1–33) — small, focused, self-contained subview component.

**Pattern to reuse:**
```swift
import SwiftUI
import Localization

public struct KillSwitchToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String
    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn; self.footerText = footerText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L10n.settingsKillSwitchTitle, isOn: $isOn)
            Text(footerText).font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

**Pattern invariants from `StatusBadge.swift`:**
- `public struct ... : View` with explicit `public init` (lines 4–6).
- Stateless component — state flows in via `@Binding`, never owned.
- Localization via `L10n` namespace.

---

### 2.14 `MainScreenFeature/MainScreenView.swift` (rewrite per D-09)

**Analog:** self (current `MainScreenView.swift` lines 1–63) — keep `@ObservedObject` + state-switch dispatch idiom, replace `header`/`content`/`footer` layout.

**Pattern to apply (Phase 1 idioms preserved):**
```swift
public var body: some View {
    VStack(spacing: 0) {
        TopBar(
            onMenuTap: viewModel.openSettings,
            onAddTap: viewModel.showAddMenu,
            isReconnectBannerVisible: viewModel.needsReconnectForKillSwitch
        )
        if viewModel.needsReconnectForKillSwitch {
            ReconnectBanner(message: L10n.bannerReconnectForKillSwitch)
        }
        Spacer()
        content   // .empty → EmptyStateCard; otherwise → timer+pill+button+serverline
        Spacer()
    }
    .alert(/* same pattern as current line 16-24 */)
}

@ViewBuilder
private var content: some View {
    switch viewModel.state {
    case .empty:
        EmptyStateCard(
            onAddFromClipboard: viewModel.importFromPasteboard,
            onScanQR: viewModel.startQRScan
        )
    case .idle, .connecting, .connected, .error:
        VStack(spacing: 20) {
            ConnectionTimer(since: viewModel.timerSince ?? Date.distantPast)
            StatusPill(state: viewModel.state)
            ConnectionButton(state: viewModel.state, action: viewModel.toggleConnection)
            ServerLineView(name: viewModel.activeServerLineText)
        }
    }
}
```

**Pattern invariants preserved from Phase 1:**
- `@ViewBuilder` on private computed property for switch-dispatch (current line 38).
- `if case .error(let msg) = viewModel.state` for state-pattern-matching destructuring (current line 49).
- `.alert(...)` with two-way binding to `lastError` (current lines 16–25).
- Idle/empty state distinction comes from `ConnectionState` enum (`ConnectionState.swift` lines 4–8) — preserved unchanged.

---

### 2.15 `MainScreenFeature/EmptyStateCard.swift`

**Analog:** `ImportFromClipboardButton.swift` (lines 1–25) — directly replaces it.

**Pattern to reuse (card layout from D-10):**
```swift
public struct EmptyStateCard: View {
    public let onAddFromClipboard: () -> Void
    public let onScanQR: () -> Void
    public init(onAddFromClipboard: @escaping () -> Void, onScanQR: @escaping () -> Void) { ... }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox").font(.system(size: 56)).foregroundStyle(.secondary)
            Text(L10n.emptyTitle).font(.headline)
            Text(L10n.emptySubtitle).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.actionImportFromClipboard, action: onAddFromClipboard)
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button(L10n.actionScanQR, action: onScanQR)
                .buttonStyle(.bordered).controlSize(.large)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.1)))
        .padding()
    }
}
```

**Pattern invariants from `ImportFromClipboardButton.swift`:**
- VStack + Image(systemName:) + Text headline + Text caption + Button(s) layout (lines 9–22).
- `L10n` keys for every string.
- `buttonStyle(.borderedProminent)` for primary, `.bordered` for secondary (D-10 spec).

---

### 2.16 `MainScreenFeature/TopBar.swift`

**Analog:** `MainScreenView.swift` `private var header` (lines 28–36) — current header has app name + StatusBadge; Phase 2 replaces with menu/add icons.

**Pattern to apply:**
```swift
public struct TopBar: View {
    public let onMenuTap: () -> Void
    public let onAddTap: () -> Void
    public let isReconnectBannerVisible: Bool

    public var body: some View {
        HStack {
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal").font(.title3)
            }
            .accessibilityIdentifier("BBTB.MenuButton")
            Spacer()
            Menu {
                Button(L10n.menuScanQR, action: onAddTap)
                Button(L10n.menuAddFromClipboard, action: onAddTap)
            } label: {
                Image(systemName: "plus").font(.title3)
            }
            .accessibilityIdentifier("BBTB.AddButton")
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }
}
```

**Pattern invariants:**
- HStack with `Spacer()` between left and right items (header pattern lines 29–32).
- `padding(.horizontal)` + `padding(.top, 24)` for top-bar inset (lines 34–35).
- `accessibilityIdentifier` strings prefixed `"BBTB."` (see `ConnectionButton.swift` line 25 — `"BBTB.ConnectionButton"`).

---

### 2.17 `MainScreenFeature/ServerLineView.swift`

**Analog:** `MainScreenView.swift` `private var footer` (lines 57–62) — current footer is just `Text(name)`.

**Pattern to apply (D-11 — disabled tap in v0.2, no disclosure arrow):**
```swift
public struct ServerLineView: View {
    public let name: String  // "Auto" or specific remark

    public var body: some View {
        HStack {
            Text(L10n.serverLineLabel)  // "Сервер:"
            Text(name).fontWeight(.medium)
            Spacer()
            // No disclosure arrow on v0.2 (D-09)
        }
        .padding()
        .contentShape(Rectangle())
        // .onTapGesture disabled — Phase 3 enables server-list navigation
    }
}
```

**Pattern invariants from footer (lines 57–62):**
- `font(.caption)` + `foregroundStyle(.secondary)` for de-emphasized text — Phase 2 can opt for `.body` + medium weight since this is now primary content.
- `padding(.bottom, 24)` for bottom-screen edge.

---

### 2.18 `MainScreenFeature/StatusPill.swift`

**Analog:** `StatusBadge.swift` (lines 1–33) — full file, rename + visual restyle.

**Pattern to reuse (same state-driven color/label, capsule shape per D-09):**
```swift
public struct StatusPill: View {
    public let state: ConnectionState
    public var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
    private var color: Color { /* identical to StatusBadge lines 15-23 */ }
    private var label: String { /* identical to StatusBadge lines 24-32 */ }
}
```

**Pattern invariants from `StatusBadge.swift`:**
- `private var color: Color` switch on state (lines 15–23).
- `private var label: String` returns `L10n.statusXxx` (lines 24–32).
- ConnectionState match-arms cover all 5 cases exhaustively.

---

### 2.19 `MainScreenFeature/ReconnectBanner.swift` — **NEW**

**Analog:** None. Closest is alert pattern in `MainScreenView.swift` lines 16–24, but that's an OS alert, not an inline banner.

**Pattern to establish:**
```swift
public struct ReconnectBanner: View {
    public let message: String  // L10n.bannerReconnectForKillSwitch
    public var body: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(message).font(.caption)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color.yellow.opacity(0.2))
    }
}
```

**Integration point** (per CONTEXT.md line 242): `MainScreenViewModel` exposes `@Published var needsReconnectForKillSwitch: Bool` that flips on when (a) UserDefaults `killSwitchEnabled` changes AND (b) tunnel is currently active. Reset on next disconnect→connect cycle.

---

### 2.20 `MainScreenFeature/QRScannerView.swift` — **NEW**

**Analog:** None in Phase 1.

**Pattern to establish (UIViewControllerRepresentable for iOS, NSViewRepresentable for macOS):**
```swift
#if os(iOS)
import UIKit
import AVFoundation

public struct QRScannerView: UIViewControllerRepresentable {
    public let onCodeScanned: (String) -> Void
    public let onError: (Error) -> Void

    public init(onCodeScanned: @escaping (String) -> Void, onError: @escaping (Error) -> Void) { ... }

    public func makeUIViewController(context: Context) -> QRScannerViewController { ... }
    public func updateUIViewController(_ vc: QRScannerViewController, context: Context) {}

    // QRScannerViewController: AVCaptureSession + AVCaptureMetadataOutput + delegate.
    // Camera permission flow via AVCaptureDevice.requestAccess(for:.video).
}
#elseif os(macOS)
import AppKit
import AVFoundation
public struct QRScannerView: NSViewRepresentable { /* AVCaptureSession + NSView preview layer */ }
#endif
```

**Pattern invariant — platform-specific compile guards:**
See `ConfigImporter.swift` lines 10–14 + lines 145–151 for the `#if os(iOS) … #elseif os(macOS) … #endif` pasteboard pattern. QRScannerView follows the same shape but for camera capture.

**Camera permission strings** (per CONTEXT.md "Claude's Discretion"):
- `Info.plist` key: `NSCameraUsageDescription`
- Russian: "BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов"
- English: same translated.

---

### 2.21 `MainScreenFeature/ConfigImporter.swift` (rewrite per CONTEXT.md line 202)

**Analog:** self (current `ConfigImporter.swift` lines 1–174) — preserve pipeline shape, generalize for array storage and universal parser.

**Patterns to PRESERVE (Phase 1 invariants from current file):**
1. **Class signature** (line 41): `public final class ConfigImporter: ConfigImporting, @unchecked Sendable`. Keep `@unchecked Sendable` because `ModelContainer` is not Sendable-checked.
2. **ConfigImporting protocol** (lines 16–19): widen to accept `rawInput: String` instead of pasteboard read; rename method to `importFromRawInput(_:)` and keep `importFromPasteboard()` as convenience wrapper.
3. **Pipeline order** (lines 58–141): `parse → build → keychain save → SwiftData save → NETunnelProviderManager save`. Order is load-bearing — keychain BEFORE SwiftData ensures secrets are persisted before metadata references them.
4. **`save → loadFromPreferences after save`** (lines 171–172): the comment `// RESEARCH §1 — обязательно после save` is a hard requirement from Phase 1 RESEARCH; preserve this two-step ALWAYS.
5. **Keychain payload structure** (lines 88–95): `[String: String]` dict serialized to Data via JSONSerialization. For Trojan, store `password` field instead of `uuid`/`publicKey`/`shortId`; keep `configJSON` always.
6. **`KillSwitch.apply(to:)` call site** (line 165): single call before assigning `manager.protocolConfiguration = proto`. Phase 2 changes signature to `apply(to:enabled:)`.

**Patterns to MODIFY in Phase 2:**
- **Array storage** (line 50–56 + 108–115): no more singleton `isActive=true`. Instead, on import:
  - For multi-line / subscription / JSON-endpoint input: REPLACE entire pool (delete all existing ServerConfigs in scope, insert new).
  - Track replacement scope by `subscriptionURL` field if present (D-07).
- **Universal parser invocation** (line 64–69): call `UniversalImportParser.parse(rawInput:)` instead of `VLESSURIParser.parse(_:)`.
- **Pool building** (line 71–83): if multiple outbounds → `PoolBuilder.build(_:)`; if single → use per-protocol `ConfigBuilder.buildSingBoxJSON(from:)` as before.
- **Kill switch flag read** (per D-14 + CONTEXT.md line 241): `let enabled = UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true` — read BEFORE calling `KillSwitch.apply(to: proto, enabled: enabled)`.

---

### 2.22 `MainScreenFeature/MainScreenViewModel.swift` (rewrite)

**Analog:** self (current `MainScreenViewModel.swift` lines 1–72) — preserve `@MainActor` + state machine shape; expand published surface.

**New published properties (Phase 2):**
```swift
@Published public private(set) var activeServerLineText: String   // "Авто" or remark from D-11
@Published public private(set) var timerSince: Date?
@Published public private(set) var needsReconnectForKillSwitch: Bool = false
@Published public private(set) var supportedConfigCount: Int = 0
@Published public private(set) var unsupportedConfigCount: Int = 0  // for "X working, Y will be enabled later" message (D-04)
```

**Pattern invariants to preserve:**
- `@MainActor` (line 5).
- `Task { await ... }` wrapping in public sync methods (lines 31–37) — never expose async from view callbacks directly.
- `performImport()` / `performToggle()` private async methods (lines 39–71).
- `ConnectionState` switch in `performToggle` (lines 52–69) — keep `.empty` and `.connecting` no-op fallthrough.

---

### 2.23 `MainScreenFeature/TunnelController.swift` (minor changes)

**Analog:** self (current lines 1–43).

**Minor change:** No longer assumes singleton profile. Loading still uses `NETunnelProviderManager.loadAllFromPreferences()` (line 13) — Phase 2 keeps SAME one VPN profile (D-01: one NETunnelProviderManager, one profile, urltest inside). Only `ConfigImporter.provisionTunnelProfile` orchestrates the single profile content. **No structural change to `TunnelController` needed.**

---

### 2.24 `VPNCore/Sources/VPNCore/ServerConfig.swift` (extend)

**Analog:** self (current lines 1–25).

**Pattern to extend (SwiftData lightweight migration):**
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

    // Phase 2 additions:
    public var isSupported: Bool = true              // D-04 — unsupported protocols stored but not in urltest pool
    public var subscriptionURL: String? = nil         // D-07 — for re-import replace-pool detection
    public var outboundJSON: String = ""              // raw outbound JSON snippet (for urltest assembly)
    public var protocolDisplayName: String = ""       // human-readable, e.g. "VLESS + Reality" or "Trojan"

    public init(/* extended init with defaults for new fields */) { ... }
}
```

**Migration pattern** (SwiftData lightweight):
- New fields with default values → lightweight migration is automatic (no schema version bump needed in v0.2 for SwiftData ≥ macOS 14).
- However, for explicit safety, planner should consider declaring a `VersionedSchema` per Apple docs. **Researcher should verify** whether silent default-value migration works for `@Model` classes added with new properties in v0.2 vs requires explicit schema versioning.

---

### 2.25 `KillSwitch/Sources/KillSwitch/KillSwitch.swift` (signature change per D-15)

**Analog:** self (current lines 1–43).

**Pattern to apply:**
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
        // Unchanged from Phase 1:
        proto.excludeLocalNetworks = false
        proto.disconnectOnSleep = false
    }

    public static func platformShouldDisableEnforceRoutes() -> Bool {
        return false  // Phase 10 R5 hook unchanged
    }
}
```

**Pattern invariants preserved from Phase 1:**
- `public enum KillSwitch` namespace (line 16).
- `apply` is the ONLY mutator of `includeAllNetworks` / `enforceRoutes` (per Phase 1 line 9).
- `excludeLocalNetworks = false` and `disconnectOnSleep = false` REGARDLESS of enabled flag (line 27 + 30).
- `platformShouldDisableEnforceRoutes()` R5 hook preserved (line 37 — made `public` so Phase 10 can override via UserDefaults read).

**Test update:** All 5 tests in `KillSwitchTests.swift` (lines 6–48) require updates — `KillSwitch.apply(to: proto)` calls must become `KillSwitch.apply(to: proto, enabled: true)`. Add new tests for `enabled: false` case.

---

### 2.26 `Localization/Sources/Localization/L10n.swift` (extend)

**Analog:** self (current lines 1–32, 22 keys).

**Pattern to extend:** Add new `static let` per UI string. Naming convention (current keys lines 10–31): dotted lowercase with category prefix.

**New keys for Phase 2** (Claude-derived, planner to refine wording):
```swift
// Top bar / menu
public static let menuScanQR = tr("menu.scan_qr")
public static let menuAddFromClipboard = tr("menu.add_from_clipboard")

// Empty state (rewrites empty.title + empty.subtitle)
public static let emptyTitle = tr("empty.title")           // "Нет конфигурации"
public static let emptySubtitle = tr("empty.subtitle")     // "Добавьте первую конфигурацию с помощью кнопок ниже"
public static let actionScanQR = tr("action.scan_qr")

// Server line
public static let serverLineLabel = tr("server.line.label")  // "Сервер:"
public static let serverAuto = tr("server.auto")             // "Авто"

// Reconnect banner
public static let bannerReconnectForKillSwitch = tr("banner.reconnect_for_kill_switch")

// Settings
public static let settingsTitle = tr("settings.title")                       // "Настройки"
public static let settingsSecurityHeader = tr("settings.security.header")    // "Безопасность"
public static let settingsKillSwitchTitle = tr("settings.kill_switch.title") // "Kill Switch"
public static let settingsKillSwitchFooter = tr("settings.kill_switch.footer")

// QR camera
public static let qrPermissionDeniedTitle = tr("qr.permission_denied.title")
public static let qrPermissionDeniedMessage = tr("qr.permission_denied.message")

// Import: subscription / multi-line / unsupported
public static let importSuccessMessage = tr("import.success.message")            // "%d working, %d will be enabled later"
public static let importErrorSubscriptionFetch = tr("import.error.subscription_fetch")
public static let importErrorNoValidEntries = tr("import.error.no_valid_entries")
public static let importErrorInsecureScheme = tr("import.error.insecure_scheme")
```

**Pattern invariant from `L10n.swift`:**
- `private static func tr(_ key: String) -> String` (line 6) — single point for `NSLocalizedString(_:bundle:comment:)` with `Bundle.module`.
- Every new key needs corresponding entries in `Resources/Localizable.xcstrings` (ru + en).

---

### 2.27 `Localization/Sources/Localization/Resources/Localizable.xcstrings` (extend)

**Analog:** self (current file — 22 keys, each with `en` + `ru` localization).

**Pattern to apply (per-key JSON shape):**
```json
"menu.scan_qr" : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Scan QR code" } },
    "ru" : { "stringUnit" : { "state" : "translated", "value" : "Сканировать QR" } }
  }
}
```

**Pattern invariant:** Every key has `"state": "translated"` for both `en` and `ru` (never `"new"` — those would flag as untranslated in Xcode).

---

### 2.28 `App/iOSApp/BBTB_iOSApp.swift` (modify)

**Analog:** self (current lines 1–54).

**Patterns to apply:**
```swift
@main
struct BBTB_iOSApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: MainScreenViewModel

    init() {
        CrashReporter.shared.install()
        // Phase 1 log export — unchanged (lines 22–29)

        // CORE-02: регистрируем протоколы
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)
        ProtocolRegistry.shared.register(TrojanHandler.self)    // ← NEW Phase 2

        // SwiftData container — unchanged (lines 35–39)
        // ConfigImporter init — extended signature (universal parser dependency)
        // ...
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {                                    // ← NEW Phase 2 (D-09 menu icon → SettingsView push)
                MainScreenView(viewModel: viewModel)
            }
        }
        .modelContainer(modelContainer)
    }
}
```

**Pattern invariants preserved:**
- `CrashReporter.shared.install()` FIRST in init (line 18).
- `ProtocolRegistry.shared.register(...)` block (line 32) — Phase 2 appends Trojan after VLESSReality.
- `fatalError("SwiftData container init failed: \(error)")` for init failures (line 38).
- `init()` constructs viewModel synchronously; passes it to `WindowGroup` body — no `@StateObject` because viewModel lives at app scope.

---

### 2.29 `App/macOSApp/BBTB_macOSApp.swift` (modify)

**Analog:** self (current lines 1–51).

**Patterns to apply:**
```swift
@main
struct BBTB_macOSApp: App {
    // ... existing fields unchanged ...

    init() {
        CrashReporter.shared.install()
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)
        ProtocolRegistry.shared.register(TrojanHandler.self)    // ← NEW Phase 2
        // ... rest unchanged
    }

    var body: some Scene {
        Window(L10n.appShortName, id: "main") {
            NavigationStack {                                   // ← NEW Phase 2 (menu icon entry point also on macOS)
                MainScreenView(viewModel: viewModel)
                    .frame(minWidth: 380, minHeight: 520)
            }
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)

        // ← NEW Phase 2: Cmd+, opens Settings
        Settings {
            SettingsView(viewModel: SettingsViewModel())
                .frame(width: 480, height: 360)
        }

        MenuBarExtra(L10n.appShortName, systemImage: viewModel.state.menuBarSymbol) {
            MenuBarContent(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
```

**Pattern invariants:**
- macOS uses `Window(_:id:)` scene (line 38) — not `WindowGroup` (which is iOS-specific style for multi-window).
- `MenuBarExtra` block (lines 45–48) unchanged in Phase 2; Phase 2 can add a "Settings…" menu item but its inclusion is optional.
- `Settings` SwiftUI scene opens via Cmd+, automatically (no extra wiring needed).

---

### 2.30 `BBTB/Project.swift` (extend Tuist manifest)

**Analog:** self (current lines 1–205). Pattern for adding a new Package is to extend `localPackages` array and add it to dependencies of relevant targets.

**Patterns to apply:**
```swift
let localPackages: [Package] = [
    .package(path: .relativeToManifest("Packages/VPNCore")),
    .package(path: .relativeToManifest("Packages/ProtocolRegistry")),
    .package(path: .relativeToManifest("Packages/ProtocolEngine")),
    .package(path: .relativeToManifest("Packages/Protocols/VLESSReality")),
    .package(path: .relativeToManifest("Packages/Protocols/Trojan")),   // ← NEW
    .package(path: .relativeToManifest("Packages/ConfigParser")),
    // ... rest unchanged
]

// iOS app target dependencies:
dependencies: [
    .package(product: "VPNCore"),
    .package(product: "ProtocolRegistry"),
    .package(product: "VLESSReality"),
    .package(product: "Trojan"),                                          // ← NEW
    .package(product: "ConfigParser"),
    .package(product: "KillSwitch"),
    .package(product: "DesignSystem"),
    .package(product: "Localization"),
    .package(product: "MainScreenFeature"),
    .package(product: "SettingsFeature"),                                 // ← NEW (sub-module in AppFeatures)
    .package(product: "CrashReporter"),
    .target(name: "BBTB-Tunnel-iOS"),
],
```

**Pattern invariant** (current Project.swift lines 79–90 for iOS, lines 113–126 for macOS):
- `.package(product: "X")` for every SwiftPM product the target consumes.
- The `Trojan` package is consumed by the app target (for `TrojanHandler.self` registration) but NOT by the PacketTunnelExtension target (extension only needs `PacketTunnelKit` + `SingBoxBridge`).
- `SettingsFeature` is a new product of the existing `AppFeatures` package (no new Tuist `.package(path:)` needed — just add `.library(name: "SettingsFeature", targets: ["SettingsFeature"])` in `AppFeatures/Package.swift`).

**`AppFeatures/Package.swift` extension pattern (analog: current lines 1–44):**
```swift
products: [
    .library(name: "MainScreenFeature", targets: ["MainScreenFeature"]),
    .library(name: "MenuBarFeature", targets: ["MenuBarFeature"]),
    .library(name: "SettingsFeature", targets: ["SettingsFeature"]),   // ← NEW
],
dependencies: [
    .package(path: "../VPNCore"),
    .package(path: "../DesignSystem"),
    .package(path: "../Localization"),
    .package(path: "../ConfigParser"),
    .package(path: "../KillSwitch"),
    .package(path: "../Protocols/VLESSReality"),
    .package(path: "../Protocols/Trojan"),                              // ← NEW
],
targets: [
    .target(
        name: "MainScreenFeature",
        dependencies: [
            "VPNCore", "DesignSystem", "Localization",
            "ConfigParser", "KillSwitch", "VLESSReality", "Trojan",     // ← Trojan added
        ]
    ),
    .target(name: "MenuBarFeature", dependencies: ["MainScreenFeature", "Localization", "VPNCore"]),
    .target(
        name: "SettingsFeature",                                         // ← NEW
        dependencies: ["VPNCore", "DesignSystem", "Localization", "KillSwitch"]
    ),
    // testTarget unchanged
],
```

---

### 2.31 `App/iOSApp/Info.plist` (extend)

**Analog:** self (current lines 1–53).

**Pattern to add:**
```xml
<key>NSCameraUsageDescription</key>
<string>BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов</string>
```

Add as new `<key>`/`<string>` pair inside the existing `<dict>` (insertion point: after `CFBundleLocalizations` block, line 47–51).

---

### 2.32 `App/macOSApp/Info.plist` (extend)

**Analog:** self (current lines 1–33).

**Pattern to add:**
```xml
<key>NSCameraUsageDescription</key>
<string>BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов</string>
```

---

### 2.33 `App/macOSApp/BBTB-macOS.entitlements` (extend)

**Analog:** self (current lines 1–29).

**Pattern to add (hardened runtime camera access):**
```xml
<key>com.apple.security.device.camera</key>
<true/>
```

iOS entitlements file does NOT need this — iOS uses `NSCameraUsageDescription` only.

---

## 3. Shared Patterns (Cross-Cutting)

### 3.1 Authentication / Security — R1 Validate Pipeline

**Source:** `PacketTunnelKit/SingBoxConfigLoader.swift` lines 57–95
**Apply to:** Every code path that produces sing-box JSON before persisting or starting tunnel
**Pattern:**
```swift
try SingBoxConfigLoader.validate(json: configJSON)
```
**Must-call sites in Phase 2:**
1. After `ConfigBuilder.buildSingBoxJSON(from:)` for VLESS or Trojan (already done in `VLESSReality/ConfigBuilder.swift` tests; replicate in Trojan tests).
2. After `PoolBuilder.build(_:)` — pool JSON must validate.
3. After `JSONEndpointFetcher.fetch(...)` — body must validate before persist (R1 trust boundary).
4. `BaseSingBoxTunnel.startTunnel` already calls it (Phase 1 contract) — no change needed.

**Required SingBoxConfigLoader change:** Current line 92–94 requires `vless` outbound. Phase 2 must relax to: at least one of `[vless, trojan, urltest]`. Add corresponding tests.

### 3.2 Error Handling — `LocalizedError` Wrap

**Source:** `ConfigImporter.swift` lines 21–39 (`ImporterError` enum)
**Apply to:** All new error types in Phase 2 (`UniversalImportError`, `SubscriptionURLFetcher.FetchError`, `TrojanURIError`, `Trojan.ConfigBuilder.BuilderError`, etc.)
**Pattern:**
```swift
public enum FooError: Error, LocalizedError {
    case caseA
    case caseB(Error)                  // wraps lower-level errors
    case caseC(String)                 // includes context

    public var errorDescription: String? {
        switch self {
        case .caseA: return L10n.fooErrorA              // user-facing string
        case .caseB(let e): return "Foo: \(e.localizedDescription)"
        case .caseC(let s): return "Foo with \(s)"
        }
    }
}
```
**Invariants:**
- Public errors are always `LocalizedError`.
- `errorDescription` for user-facing cases reads from `L10n`.
- `errorDescription` for developer-facing cases (wrapping lower errors) just concatenates `localizedDescription`.

### 3.3 Sendable / Concurrency

**Source:** Several files:
- `ParsedVLESS` struct: `Sendable, Equatable` (VLESSURIParser.swift line 4)
- `ConfigImporter` class: `@unchecked Sendable` (ConfigImporter.swift line 41) — because of non-Sendable `ModelContainer`
- `MainScreenViewModel`: `@MainActor` class (MainScreenViewModel.swift line 5)
- `ProtocolRegistry`: `@unchecked Sendable` with `NSLock` (ProtocolRegistry.swift line 6)

**Apply to:**
- All `Parsed*` data carriers → `Sendable, Equatable` value types.
- All `*Importer`, `*Fetcher` orchestrators with mutable state → `@unchecked Sendable` final class OR `actor`.
- All `*ViewModel` → `@MainActor public final class ... : ObservableObject`.
- All `*Handler` → `Sendable` struct (per `VPNProtocolHandler` protocol contract — `VPNCore/VPNProtocolHandler.swift` line 5).

### 3.4 SwiftPM Resource Bundling

**Source:**
- `Localization/Package.swift` lines 9–14 — `.process("Resources/Localizable.xcstrings")`
- `PacketTunnelKit/Package.swift` lines 19–22 — `.process("Resources/SingBoxConfigTemplate.vless-reality.json")`

**Access pattern:**
```swift
guard let url = Bundle.module.url(forResource: "X", withExtension: "json") else { /* throw */ }
return try String(contentsOf: url, encoding: .utf8)
```
(see `SingBoxConfigLoader.swift` lines 280–286)

**Apply to:** Trojan templates, optional Pool template, any future protocol templates.

### 3.5 Test Fixture Organization

**Source:** `PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/*.json` — 9 fixtures (valid + invalid cases).
**Pattern (Package.swift `.testTarget` lines 23–28):**
```swift
.testTarget(
    name: "PackageNameTests",
    dependencies: ["PackageName"],
    resources: [.process("Fixtures")]
)
```
**Access pattern (`SingBoxConfigLoaderTests.swift` lines 8–17):**
```swift
private func loadFixture(_ name: String) throws -> String {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: nil)
        ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    else { XCTFail("Fixture not found: \(name).json"); throw SingBoxConfigError.malformedJSON }
    return try String(contentsOf: url, encoding: .utf8)
}
```
**Apply to:** ConfigParser tests for Phase 2 — fixtures should include real user URIs (sanitized) from CONTEXT.md `<specifics>` lines 261–268. Recommended fixtures:
- `Fixtures/sub-base64-response.txt`
- `Fixtures/sub-plaintext-response.txt`
- `Fixtures/sub-json-response.json`
- `Fixtures/multi-line-mixed.txt`
- `Fixtures/trojan-tcp-uri.txt`
- `Fixtures/trojan-ws-uri.txt`
- `Fixtures/unsupported-ss-uri.txt` (for `isSupported=false` test)

### 3.6 Module Dependency Graph (Phase 2 preserves Phase 1 acyclic graph)

Current graph (no cycles):
```
VPNCore  ←  ProtocolRegistry, ProtocolEngine, ConfigParser, KillSwitch,
            PacketTunnelKit, Localization (no deps), DesignSystem (no deps),
            CrashReporter, all Protocols/*, AppFeatures
PacketTunnelKit  ←  Protocols/VLESSReality, BBTB-Tunnel-{iOS,macOS}
SingBoxBridge (from ProtocolEngine)  ←  PacketTunnelKit
AppFeatures/MainScreenFeature  ←  BBTB iOS+macOS apps
AppFeatures/MenuBarFeature  ←  BBTB macOS app
```

**Phase 2 additions:**
```
Protocols/Trojan  →  VPNCore, PacketTunnelKit
ConfigParser     →  VPNCore (UNCHANGED — Universal/Subscription/JSON/PoolBuilder all live inside ConfigParser)
AppFeatures/SettingsFeature  →  VPNCore, DesignSystem, Localization, KillSwitch
AppFeatures/MainScreenFeature  →  + Trojan (handler registration not needed here, but PoolBuilder + ParsedTrojan are consumed)
```

**Critical invariant: ConfigParser MUST NOT depend on PacketTunnelKit.** Current `ConfigParser/Package.swift` line 7 shows only VPNCore dependency. Phase 2's `PoolBuilder` should NOT trigger a new dependency on PacketTunnelKit — instead, validation calls happen at `ConfigImporter` orchestration layer (which already depends on both).

If `PoolBuilder.build()` needs the pool template, the template file lives in `PacketTunnelKit/Resources/` and is loaded via a new `SingBoxConfigLoader.loadPoolTemplate()` method called from `ConfigImporter`, passing the loaded template string into `PoolBuilder.build(template:inputs:)`. **This avoids the ConfigParser→PacketTunnelKit dependency.**

---

## 4. No Analog Found — NEW Patterns (Planner Must Design)

| File | Why no analog | Recommendation |
|------|---------------|----------------|
| `ConfigParser/UniversalImportParser.swift` | First multi-format input router | Use Sendable struct for output + actor for parser (async work). Follow `ConfigImporter` error-wrapping idiom. |
| `ConfigParser/SubscriptionURLFetcher.swift` | First HTTP fetcher in codebase | `enum` namespace with static async functions. URLSession.shared. HTTPS-only check + User-Agent header. **Codex consult recommended.** |
| `ConfigParser/JSONEndpointFetcher.swift` | First JSON-endpoint fetcher | Sibling to SubscriptionURLFetcher; add `Accept: application/json` header + post-fetch validate. |
| `ConfigParser/PoolBuilder.swift` | First multi-outbound assembler | Reuse `ConfigBuilder.mutatePort` JSON-mutation idiom; new pool template file. |
| `MainScreenFeature/QRScannerView.swift` | First camera/AVFoundation code | UIViewControllerRepresentable (iOS) + NSViewRepresentable (macOS) with `AVCaptureSession` + `AVCaptureMetadataOutput`. Handle camera permission flow. **Researcher should verify** macOS approach (AVFoundation works on macOS but NSCameraUsageDescription handling differs). |
| `MainScreenFeature/ReconnectBanner.swift` | First inline banner UI | Simple HStack + background fill — minimal pattern needed. |
| `MainScreenFeature/TopBar.swift` | Header replaces previous app-name+badge | Reuse HStack+padding pattern from current `header` computed property. |
| `Resources/SingBoxConfigTemplate.pool.json` | First urltest pool template | Plan with researcher — sing-box `urltest` outbound shape + probe URL + interval/tolerance/idle_timeout. |
| `SettingsFeature/SettingsView.swift` | First non-MainScreen scene | Use SwiftUI `Form` + `Section { ... } header:` idiom (iOS/macOS portable). |

---

## 5. Critical Cross-Cutting Decisions (For Planner Attention)

### 5.1 Where do Trojan templates live?

**Option A** (consistent with VLESS-Reality): `PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.trojan-{tcp,ws}.json`.
**Option B** (modular per protocol): `Packages/Protocols/Trojan/Sources/Trojan/Resources/`.

**Recommendation: Option B.** Reasons:
- Trojan package is self-contained — no transitive Bundle traversal needed.
- Sets the pattern for Phase 4+ protocols (each protocol carries its own template).
- Avoids growing `PacketTunnelKit` with N-protocol resources.

Phase 1 placed the VLESS-Reality template in PacketTunnelKit because there was no separate VLESSReality protocol package needing resources at that moment. Migration plan (optional): in Phase 4 (when VMess/Shadowsocks join), move `SingBoxConfigTemplate.vless-reality.json` into `Packages/Protocols/VLESSReality/Sources/VLESSReality/Resources/` for consistency. NOT required in Phase 2.

### 5.2 `SingBoxConfigLoader.validate` Trojan acceptance

**Current code** (line 92–94) hard-requires `vless` outbound. Phase 2 MUST modify:
```swift
// Phase 2: accept any registered protocol's outbound OR urltest
private static let allowedOutboundTypes: Set<String> = ["vless", "trojan", "urltest", "direct"]
let hasUserOutbound = outbounds.contains {
    let t = $0["type"] as? String
    return t == "vless" || t == "trojan" || t == "urltest"
}
guard hasUserOutbound else { throw SingBoxConfigError.noUserOutbound }
```
Rename error case `noVLESSOutbound` → `noUserOutbound` (breaking change in error enum — update tests). Alternatively, keep `noVLESSOutbound` for backwards compat in tests but flip the check.

### 5.3 ConfigImporter signature evolution

**Phase 1:** `func importFromPasteboard() async throws -> ServerConfig`
**Phase 2 needs:**
- `func importFromRawInput(_ raw: String) async throws -> ImportResult` (multi-server result)
- `func importFromPasteboard() async throws -> ImportResult` (reads pasteboard, calls above)
- `func importFromQRCode(_ scanned: String) async throws -> ImportResult` (calls above)
- `func importFromSubscriptionURL(_ url: String) async throws -> ImportResult` (specialized; ImportResult includes `subscriptionURL` for D-07 replace-pool)

Where `ImportResult` = `{ supportedConfigs: [ServerConfig], unsupportedCount: Int, subscriptionURL: String? }`.

### 5.4 Phase 1 Test Regression Risk

Phase 2 changes that WILL break existing tests:
- `KillSwitch.apply(to:)` → `apply(to:enabled:)` — **all 5 KillSwitchTests need updates** (`KillSwitchTests.swift` lines 7, 13, 21, 28, 36).
- `SingBoxConfigLoader.validate` accepts Trojan/urltest → **add tests** but EXISTING tests should still pass.
- `ServerConfig` new fields with defaults → `KeychainStoreTests` + `VPNCoreTests` should still pass (lightweight migration covers new defaults).
- `ConfigImporter` rewrite — current path `importFromPasteboard()` still works as facade; no test regression expected if facade preserved.

Phase 2 plan should include a "regression check" wave that runs all Phase 1 tests before merging.

---

## 6. Metadata

**Analog search scope:**
- `BBTB/Packages/**/Sources/*.swift` (38 files)
- `BBTB/Packages/**/Tests/*.swift` (~7 files)
- `BBTB/App/**/*.swift` (~6 files)
- `BBTB/Project.swift` + `BBTB/Workspace.swift`
- `BBTB/Packages/*/Package.swift` (11 files)
- `BBTB/App/**/Info.plist` + `*.entitlements` (4 files)

**Files NOT analyzed but relevant** (researcher may consult if needed for deeper context):
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` — tunnel lifecycle (no Phase 2 change expected).
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift` — R6 P2P=false (no Phase 2 change).
- `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/*.swift` — libbox wiring (no Phase 2 change).
- `BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift` — no Phase 2 change.
- `BBTB/Tools/SocksProbe/**` — security validation tool, no Phase 2 change.

**Pattern extraction date:** 2026-05-11

---

*Created via `/gsd-plan-phase 2` pattern-mapper agent.*
*Downstream consumer: `gsd-planner` for PLAN.md generation.*
*Patterns extracted: 33 component mappings, 6 cross-cutting patterns, 4 critical decision points for planner.*
