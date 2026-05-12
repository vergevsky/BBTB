# Phase 5: Transports — Pattern Map

**Mapped:** 2026-05-12
**Files analyzed:** 14 (7 new, 7 modified)
**Analogs found:** 14 / 14

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `VPNCore/TransportConfig.swift` (NEW) | model | transform | `VPNCore/VPNProtocolHandler.swift` (protocol defs) | role-match |
| `TransportRegistry/TransportRegistry.swift` (NEW) | registry/service | request-response | `ProtocolRegistry/ProtocolRegistry.swift` | exact |
| `TransportRegistry/TransportHandler.swift` (NEW) | protocol/utility | transform | `VPNCore/VPNProtocolHandler.swift` | exact |
| `TransportRegistry/Handlers/WSHandler.swift` (NEW) | handler | transform | `Protocols/Trojan/TrojanHandler.swift` | role-match |
| `TransportRegistry/Handlers/GRPCHandler.swift` (NEW) | handler | transform | `Protocols/Trojan/TrojanHandler.swift` | role-match |
| `TransportRegistry/Handlers/HTTPHandler.swift` (NEW) | handler | transform | `Protocols/Trojan/TrojanHandler.swift` | role-match |
| `TransportRegistry/Handlers/HTTPUpgradeHandler.swift` (NEW) | handler | transform | `Protocols/Trojan/TrojanHandler.swift` | role-match |
| `ConfigParser/TransportParamParser.swift` (NEW) | utility | transform | `ConfigParser/TrojanURIParser.swift` | role-match |
| `ServerListFeature/ServerDetailView.swift` (NEW) | component | request-response | `AppFeatures/ServerListFeature/ServerListSheet.swift` | role-match |
| `ConfigParser/ImportedServer.swift` (MODIFIED) | model | transform | itself (ParsedVLESSTLS struct migration) | exact |
| `ConfigParser/TrojanURIParser.swift` (MODIFIED) | utility | transform | itself (D-06 migration + D-09 delegation) | exact |
| `ConfigParser/VLESSURIParser.swift` (MODIFIED) | utility | transform | itself (D-09 delegation) | exact |
| `ConfigParser/PoolBuilder.swift` (MODIFIED) | service | CRUD | itself (D-14/D-15 coordinator refactor) | exact |
| `VPNCore/ServerConfig.swift` (MODIFIED) | model | CRUD | itself (SwiftData lightweight migration pattern) | exact |

---

## Pattern Assignments

---

### `VPNCore/TransportConfig.swift` (NEW — model, transform)

**Analog:** `BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift`

**Imports pattern** (lines 1-2 of VPNProtocolHandler.swift):
```swift
import Foundation
```

**Core enum pattern — derive from `ParsedTrojan.TransportType`** (`TrojanURIParser.swift` lines 15-18):
```swift
// MIGRATE from ParsedTrojan.TransportType — exact case names carry forward:
public enum TransportConfig: Sendable, Equatable, Codable {
    case tcp
    case ws(path: String, host: String)
    case grpc(serviceName: String)
    case http(path: String)
    case httpUpgrade(path: String, host: String)
}
```

**Codable requirement** (RESEARCH §Standard Stack — SwiftData cannot store non-Codable enums):
- Add `Codable` conformance directly on the enum.
- Associated values require explicit `CodingKeys` enum and `init(from:)` / `encode(to:)` or use synthesized coding if all labels are unique.

**`identifier` computed property** (needed by PoolBuilder → TransportRegistry lookup):
```swift
public var identifier: String {
    switch self {
    case .tcp:              return "tcp"
    case .ws:               return "ws"
    case .grpc:             return "grpc"
    case .http:             return "http"
    case .httpUpgrade:      return "httpupgrade"
    }
}
```

---

### `TransportRegistry/TransportRegistry.swift` (NEW — registry, request-response)

**Analog:** `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` lines 1-26

**Imports pattern** (lines 1-2):
```swift
import Foundation
import VPNCore
```

**Exact singleton + NSLock + dict pattern** (lines 4-26):
```swift
public final class ProtocolRegistry: @unchecked Sendable {
    public static let shared = ProtocolRegistry()

    private let lock = NSLock()
    private var handlers: [String: any VPNProtocolHandler.Type] = [:]

    public func register<H: VPNProtocolHandler>(_ handlerType: H.Type) {
        lock.lock(); defer { lock.unlock() }
        handlers[H.identifier] = handlerType
    }

    public func handler(for identifier: String) -> (any VPNProtocolHandler.Type)? {
        lock.lock(); defer { lock.unlock() }
        return handlers[identifier]
    }

    public var registeredIdentifiers: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(handlers.keys).sorted()
    }
}
```

**Adaptation for TransportRegistry:** Replace `VPNProtocolHandler.Type` with `any TransportHandler.Type`; replace `H.identifier` with `H.identifier` (same); rename class to `TransportRegistry`. Structure is byte-for-byte identical.

**Package manifest pattern** (from `ProtocolRegistry/Package.swift` lines 1-12):
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TransportRegistry",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "TransportRegistry", targets: ["TransportRegistry"])],
    dependencies: [.package(path: "../VPNCore")],
    targets: [
        .target(name: "TransportRegistry", dependencies: ["VPNCore"]),
    ]
)
```

---

### `TransportRegistry/TransportHandler.swift` (NEW — protocol, transform)

**Analog:** `BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift` lines 4-14

**Exact protocol shape from CONTEXT.md D-11:**
```swift
import Foundation
import VPNCore

public protocol TransportHandler: Sendable {
    static var identifier: String { get }        // "ws", "grpc", "http", "httpupgrade", "tcp"
    static var displayName: String { get }        // "WebSocket", "gRPC", …
    static var supportedProtocols: [String] { get } // ["vless-tls", "trojan", …]
    static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
}
```

Note: `static` methods (not instance) — differs from `VPNProtocolHandler` which uses instance methods. `VPNProtocolHandler` is the structural template; the method signatures here are per D-11.

---

### `TransportRegistry/Handlers/WSHandler.swift` (NEW — handler, transform)

**Analog:** `BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift` lines 1-49 (struct with static members)

**WS transport block source:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` lines 263-270:
```swift
if case let .ws(path, host) = parsed.transport {
    let wsHost = host.isEmpty ? parsed.sni : host
    outbound["transport"] = [
        "type": "ws",
        "path": path,
        "headers": ["Host": wsHost],
    ] as [String: Any]
}
```

**Handler struct pattern** (from TrojanHandler.swift lines 11-49):
```swift
import Foundation
import VPNCore

public struct WSHandler: TransportHandler {
    public static let identifier = "ws"
    public static let displayName = "WebSocket"
    public static let supportedProtocols = ["vless-tls", "trojan"]

    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
        guard case let .ws(path, host) = config else { return nil }
        return [
            "type": "ws",
            "path": path,
            "headers": ["Host": host],
        ]
    }
}
```

**ALPN h2 strip invariant** (PoolBuilder.swift lines 238-246 — WS+h2 incompatibility from Phase 2 W4):
```swift
// WS upgrade is HTTP/1.1 — if ALPN includes h2, server negotiates h2 and
// rejects the upgrade (framing mismatch → i/o timeout). Strip h2 for WS.
let isWS: Bool
if case .ws = parsed.transport { isWS = true } else { isWS = false }
let alpn: [String]
if isWS {
    let filtered = parsed.alpn.filter { $0 != "h2" }
    alpn = filtered.isEmpty ? ["http/1.1"] : filtered
} else {
    alpn = parsed.alpn
}
```
This strip logic must be preserved in `VLESSTLS.buildOutbound` and `Trojan.buildOutbound` (D-14) — not inside WSHandler itself, since WSHandler only produces the transport block dict.

---

### `TransportRegistry/Handlers/GRPCHandler.swift` (NEW — handler, transform)

**Analog:** same struct pattern as WSHandler above.

**sing-box gRPC transport block** (from RESEARCH.md §«sing-box transport JSON / gRPC»):
```swift
public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
    guard case let .grpc(serviceName) = config else { return nil }
    return [
        "type": "grpc",
        "service_name": serviceName,
    ]
}
```
URI query param: `serviceName` → `service_name` in JSON. `mode` and `authority` are omitted (sing-box defaults per RESEARCH.md).

---

### `TransportRegistry/Handlers/HTTPHandler.swift` (NEW — handler, transform)

**Analog:** same struct pattern as WSHandler above.

**sing-box HTTP/2 transport block** (from RESEARCH.md §«sing-box transport JSON / HTTP»):
```swift
public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
    guard case let .http(path) = config else { return nil }
    return [
        "type": "http",
        "path": path,
    ]
}
```
Note: `TransportConfig.http` carries only `path`; host is not stored (sing-box uses TLS SNI for h2 authority). ALPN for HTTP transport should include `"h2"` — this is set in the protocol package's `buildOutbound`, not in HTTPHandler.

---

### `TransportRegistry/Handlers/HTTPUpgradeHandler.swift` (NEW — handler, transform)

**Analog:** same struct pattern as WSHandler above.

**sing-box HTTPUpgrade transport block** (from RESEARCH.md §«sing-box transport JSON / HTTPUpgrade»):
```swift
public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
    guard case let .httpUpgrade(path, host) = config else { return nil }
    return [
        "type": "httpupgrade",
        "path": path,
        "host": host,
    ]
}
```

---

### `ConfigParser/TransportParamParser.swift` (NEW — utility, transform)

**Analog:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` lines 99-113 (transport switch dispatch block)

**Imports pattern:**
```swift
import Foundation
import VPNCore
```

**Core dispatch pattern — copy TrojanURIParser transport switch, extend to 5 cases** (TrojanURIParser.swift lines 99-113):
```swift
// EXISTING pattern (Trojan, 2 cases):
let typeRaw = (q["type"] ?? "tcp").lowercased()
switch typeRaw {
case "tcp":
    transport = .tcp
case "ws":
    guard let path = q["path"], !path.isEmpty else {
        throw TrojanURIError.invalidTransport("ws-missing-path")
    }
    let wsHost = q["host"] ?? sni
    transport = .ws(path: path, host: wsHost)
default:
    throw TrojanURIError.invalidTransport(typeRaw)
}
```

**Extended for Phase 5 (5 cases):**
```swift
public enum TransportParamParser {
    /// Throws `UnsupportedReason.transportUnsupported` for unknown types (D-10).
    public static func parse(queryItems: [URLQueryItem]) throws -> TransportConfig {
        var q: [String: String] = [:]
        for item in queryItems {
            if let v = item.value { q[item.name] = v }
        }
        let typeRaw = (q["type"] ?? "tcp").lowercased()
        switch typeRaw {
        case "tcp", "raw":
            return .tcp
        case "ws":
            let path = q["path"] ?? "/"
            let host = q["host"] ?? ""
            return .ws(path: path, host: host)
        case "grpc":
            let svcName = q["serviceName"] ?? q["service-name"] ?? ""
            return .grpc(serviceName: svcName)
        case "http", "h2":
            let path = q["path"] ?? "/"
            return .http(path: path)
        case "httpupgrade":
            let path = q["path"] ?? "/"
            let host = q["host"] ?? ""
            return .httpUpgrade(path: path, host: host)
        default:
            throw UnsupportedReason.transportUnsupported
        }
    }
}
```

**Error type** — use existing `UnsupportedReason.transportUnsupported` from `ImportedServer.swift` line 24 (already defined, no new error type needed).

---

### `ServerListFeature/ServerDetailView.swift` (NEW — component, request-response)

**Analog:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` (SwiftUI View + @ObservedObject ViewModel pattern)

**Imports pattern** (ServerListSheet.swift lines 22-26):
```swift
import SwiftUI
import VPNCore
import DesignSystem
import Localization
```
Add `import ConfigParser` for re-parse rawURI.

**View + ViewModel structure** (ServerListSheet.swift lines 27-33):
```swift
public struct ServerDetailView: View {
    @ObservedObject public var viewModel: ServerDetailViewModel
    // (no static height constants needed — single-scroll detail page)
    public init(viewModel: ServerDetailViewModel) {
        self.viewModel = viewModel
    }
    public var body: some View { ... }
}
```

**ViewModel pattern** (ServerListViewModel.swift lines 44-84):
```swift
@MainActor
public final class ServerDetailViewModel: ObservableObject {
    private static let log = Logger(subsystem: "app.bbtb.server-list", category: "detail")

    @Published public private(set) var parsedDetails: SomeDetailStruct? = nil
    @Published public var selectedTransport: TransportConfig? = nil  // nil = Auto

    private let server: ServerConfig
    private let modelContainer: ModelContainer

    public init(server: ServerConfig, modelContainer: ModelContainer) {
        self.server = server
        self.modelContainer = modelContainer
        self.selectedTransport = server.transportOverride
    }

    public func onAppear() async {
        // Re-parse rawURI on demand (D-18, CONTEXT.md §Code Context "Re-parse rawURI on demand")
        guard let rawURI = server.rawURI else { return }
        // ... parse and populate parsedDetails
    }

    public func saveTransportOverride(_ value: TransportConfig?) {
        let context = ModelContext(modelContainer)
        // fetch-all + Swift filter (SwiftData UUID? predicate pitfall — memory feedback)
        // ...
        server.transportOverride = value
        try? context.save()
    }
}
```

**DesignSystem tokens** used in ServerListSheet/ServerRow — exact same tokens for ServerDetailView:
- `DS.Spacing.lg` / `DS.Spacing.md` / `DS.Spacing.xl` for padding
- `DS.Typography.title` / `DS.Typography.body` / `DS.Typography.caption` for text styles
- `DS.Radius.card` / `DS.Radius.cardLarge` for rounded corners

**NavigationLink trigger pattern** — add to `ServerRow.swift` body (lines 38-87). Existing row is a `Button`. Phase 5 replaces or augments it with a chevron `›` NavigationLink:
```swift
// Add trailing chevron inside existing HStack (after LatencyBadge/checkmark):
NavigationLink(destination: ServerDetailView(viewModel: detailVM)) {
    Image(systemName: "chevron.right")
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
}
.buttonStyle(.plain)
```

---

### `ConfigParser/ImportedServer.swift` — `ParsedVLESSTLS` migration (MODIFIED)

**Current state** (lines 36-68): has `networkType: String` field.

**Migration pattern (D-05):** Replace `networkType: String` with `transport: TransportConfig`:
```swift
// BEFORE (line 44):
public let networkType: String          // "tcp" / "raw" в Phase 4

// AFTER:
public let transport: TransportConfig   // D-05: replaces networkType: String
```
Update `init` signature and body accordingly. All callers (VLESSURIParser.swift line 129-140) must be updated simultaneously.

**No new Codable/Sendable conformance needed** — `ParsedVLESSTLS` is already `Sendable, Equatable`. `TransportConfig` must be `Equatable` (already required by D-04).

---

### `ConfigParser/TrojanURIParser.swift` (MODIFIED)

**Two changes:**

1. **D-06 — `ParsedTrojan.TransportType` migration**: Remove the nested `TransportType` enum (lines 15-18) and change field `transport: TransportType` to `transport: TransportConfig` (line 12). Update `init` (lines 20-25).

2. **D-09 — delegate to TransportParamParser**: Replace lines 99-113 (manual switch on `typeRaw`) with a single call:
```swift
// REPLACE lines 99-113 with:
let transport: TransportConfig
do {
    transport = try TransportParamParser.parse(queryItems: comps.queryItems ?? [])
} catch {
    throw TrojanURIError.invalidTransport(q["type"] ?? "unknown")
}
```
Remove `TrojanURIError.invalidTransport` if no longer needed, or keep it as a wrapper for re-throw.

---

### `ConfigParser/VLESSURIParser.swift` (MODIFIED)

**D-09 — delegate to TransportParamParser**: Replace `networkType: q["type"] ?? "tcp"` (line 103 in Reality branch, line 139 in TLS branch) with:
```swift
// In TLS branch (lines 129-140) — replace networkType assignment:
let transport: TransportConfig
do {
    transport = try TransportParamParser.parse(queryItems: comps.queryItems ?? [])
} catch {
    // Unknown transport for VLESS+TLS — route to unsupported (D-10)
    return .unsupported(name: ..., scheme: "vless", host: host, port: port,
                        rawURI: trimmed, reason: .transportUnsupported)
}

// In ParsedVLESSTLS init call — replace `networkType:` with `transport:`:
let parsed = ParsedVLESSTLS(
    uuid: uuid, host: host, port: port, flow: flow,
    sni: q["sni"] ?? host, fingerprint: q["fp"] ?? "chrome",
    alpn: alpn, transport: transport, remarks: ...
)
```
Reality branch (`ParsedVLESS`) keeps `networkType: String` unchanged (D-03 — Reality only TCP).

---

### `ConfigParser/PoolBuilder.swift` (MODIFIED — coordinator refactor D-14/D-15)

**Current state:** 5 private `buildXxxOutbound` methods inline (lines 114-272). Switch in `buildSingBoxJSON` lines 43-61 calls them.

**After D-15:** Each case becomes a one-liner calling the protocol package's public `buildOutbound`:
```swift
// REPLACE lines 43-61 with:
switch parsed {
case .vlessReality(let v):
    tag = "vless-\(index)"
    outbound = VLESSReality.buildOutbound(from: v, transport: .tcp, tag: tag)
case .vlessTLS(let v):
    tag = "vless-tls-\(index)"
    outbound = VLESSTLS.buildOutbound(from: v, transport: v.transport, tag: tag)
case .trojan(let t):
    tag = "trojan-\(index)"
    outbound = TrojanModule.buildOutbound(from: t, transport: t.transport, tag: tag)
case .shadowsocks(let s):
    tag = "ss-\(index)"
    outbound = ShadowsocksModule.buildOutbound(from: s, transport: .tcp, tag: tag)
case .hysteria2(let h):
    tag = "hy2-\(index)"
    outbound = Hysteria2Module.buildOutbound(from: h, transport: .tcp, tag: tag)
}
```
The 5 private builder functions (lines 114-272) move to their respective protocol packages as `public static func buildOutbound(from:transport:tag:) -> [String: Any]`.

**R1 invariant comment block** (lines 185-200) moves verbatim into `Hysteria2Module.buildOutbound` as the authoritative location.

**Existing `dnsBlock`, `buildSingleOutboundJSON`, `buildSingBoxJSON` outer structure** (lines 66-110, 276-326) — unchanged.

---

### `VPNCore/ServerConfig.swift` (MODIFIED — SwiftData lightweight migration D-19)

**Current migration pattern** (lines 34-58 show prior optional/default additions). Add one new optional field:
```swift
// ADD after line 58 (missingFromLastFetch):
/// D-19 — Transport override (Phase 5). nil = use transport from URI (Auto mode).
/// SwiftData lightweight migration: optional field, no default value needed → auto-migrated.
public var transportOverride: TransportConfig? = nil
```

**Init update** (lines 60-91): Add `transportOverride: TransportConfig? = nil` parameter and `self.transportOverride = transportOverride` in body.

**Migration safety:** `TransportConfig` must be `Codable` (required by SwiftData for non-primitive types). SwiftData stores Codable values as JSON blob. Existing rows will have `nil` = Auto behavior.

---

## Shared Patterns

### Registry Singleton (NSLock + dict)
**Source:** `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` lines 4-26
**Apply to:** `TransportRegistry.swift` — exact structural copy, swap type parameters.

### App Bootstrap Registration
**Source:** `BBTB/App/iOSApp/BBTB_iOSApp.swift` lines 37-41
```swift
// EXISTING (lines 37-41):
ProtocolRegistry.shared.register(VLESSRealityHandler.self)
ProtocolRegistry.shared.register(TrojanHandler.self)
ProtocolRegistry.shared.register(VLESSTLSHandler.self)
ProtocolRegistry.shared.register(ShadowsocksHandler.self)
ProtocolRegistry.shared.register(Hysteria2Handler.self)
```
**Apply to:** Add 5 analogous lines immediately after the ProtocolRegistry block:
```swift
TransportRegistry.shared.register(TCPHandler.self)   // no-op handler (tcp = no transport block)
TransportRegistry.shared.register(WSHandler.self)
TransportRegistry.shared.register(GRPCHandler.self)
TransportRegistry.shared.register(HTTPHandler.self)
TransportRegistry.shared.register(HTTPUpgradeHandler.self)
```
Same pattern in `macOSApp/BBTB_macOSApp.swift`.

### R1 TLS Strict — `insecure: false` hardcoded
**Source:** `PoolBuilder.swift` lines 148-152 (VLESS+TLS builder) and lines 185-200 (R1 exception comment for Hysteria2)
**Apply to:** Every `buildOutbound` in VLESSTLS, Trojan, VLESSReality packages — `insecure: false` must be hardcoded. Only `Hysteria2.buildOutbound` may set `insecure: parsed.allowInsecure` (D-08 exception).

### ALPN h2 Strip for WebSocket
**Source:** `PoolBuilder.swift` lines 238-246
**Apply to:** `VLESSTLS.buildOutbound` and `Trojan.buildOutbound` — preserve h2-strip when `transport == .ws(...)`.

### SwiftData fetch-all + Swift filter (UUID? predicate pitfall)
**Source:** `ServerListViewModel.swift` lines 231-240 (confirmDeleteSubscription uses all-fetch + filter)
**Apply to:** `ServerDetailViewModel.saveTransportOverride` — do NOT use `#Predicate { $0.id == serverID }` with UUID; use fetch-all + `.first(where:)`.

### DesignSystem Tokens
**Source:** `DesignSystem/DesignSystem.swift` lines 11-38
**Apply to:** `ServerDetailView.swift` — use `DS.Spacing.*`, `DS.Typography.*`, `DS.Radius.*` for all layout values. No hardcoded CGFloat literals.

### `@MainActor ObservableObject` ViewModel
**Source:** `ServerListViewModel.swift` lines 44-47
```swift
@MainActor
public final class ServerListViewModel: ObservableObject {
    private static let log = Logger(subsystem: "app.bbtb.server-list", category: "viewmodel")
```
**Apply to:** `ServerDetailViewModel` — same `@MainActor`, same `OSLog` subsystem `"app.bbtb.server-list"`, category `"detail"`.

---

## No Analog Found

All files have close analogs in the existing codebase. No novel patterns required.

---

## Metadata

**Analog search scope:** `BBTB/Packages/` (all packages), `BBTB/App/iOSApp/`
**Files scanned:** 18 source files read directly
**Pattern extraction date:** 2026-05-12
