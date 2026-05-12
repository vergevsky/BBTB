---
phase: 05-transports
plan: 08
wave: 8
status: complete
commit: 44dd8fe
date: 2026-05-13
---

# Wave 8 SUMMARY — ServerDetailView + transportOverride + TransportPicker

## What Was Built

### 1. ServerConfig.transportOverride (SwiftData lightweight migration)

**File:** `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift`

Added `public var transportOverride: TransportConfig?` field + `transportOverride: TransportConfig? = nil` init parameter. Optional field with nil default — SwiftData auto-migrates existing rows (Pitfall 3 mitigation). Pre-Phase-5 devices that upgrade will see all servers with `transportOverride == nil` (Auto) on first launch without crash.

### 2. SwiftData Round-Trip Tests (4 new tests)

**File:** `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerConfigTransportOverrideTests.swift`

- `test_serverConfig_init_transportOverride_defaultsNil` — PASS
- `test_serverConfig_init_transportOverride_storesValue` — PASS
- `test_serverConfig_swiftData_roundtrip` — PASS (verifies `.ws(path:"/x", host:"h")` roundtrips via in-memory ModelContainer)
- `test_serverConfig_swiftData_nilOverride_roundtrip` — PASS (simulates pre-Phase-5 migration)

### 3. TransportPicker.swift

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift`

- `TransportSelection` enum: `.auto, .tcp, .ws, .grpc, .http, .httpUpgrade`
- `TransportSelection.from(_:TransportConfig?)` — maps nil → .auto, TransportConfig cases → Selection cases
- `TransportSelection.toOverride()` — .auto → nil, others → TransportConfig with Phase 5 defaults
- `TransportPicker` view with `.pickerStyle(.menu)` using DesignSystem + L10n strings

**Phase 5 note:** Picker provides COARSE override — user selects transport type, path/host/serviceName use defaults. Wave 10 (Advanced settings) will expose per-field editing.

### 4. ServerDetailViewModel.swift

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailViewModel.swift`

- `ParsedDetails` struct: uuid, flow, fingerprint, alpn, publicKey, shortId, currentTransport
- `@MainActor ServerDetailViewModel: ObservableObject`
- `onAppear()` — calls `configImporter.reparseAnyParsedConfig(from:)` to populate parsedDetails
- `applyTransportSelection(_:)` — **Pitfall 4 compliance**: fetch-all + Swift filter (NOT #Predicate) to persist transport override to SwiftData
- `extractDetails(from:)` — maps all 5 AnyParsedConfig cases to ParsedDetails

### 5. ServerDetailView.swift

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift`

Form-based screen with 3 sections:
1. **General** — name, host, port, protocol, sni?, latency?, countryCode?
2. **Protocol parameters** (optional, when parsedDetails available) — uuid, flow, fingerprint, alpn, publicKey, shortId
3. **Transport** — TransportPicker + footer text; onChange → applyTransportSelection

Uses `.navigationTitle(server.name)` + `.navigationBarTitleDisplayMode(.inline)` on iOS.

### 6. ServerRow.swift — Chevron Button

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift`

Added `onDetailTap: () -> Void` parameter (default `{}` for backward compat). Chevron `›` button on the right side of each row calls `onDetailTap`. Button has dedicated accessibility label (`serverDetailAccessibilityHint`) and identifier `BBTB.ServerListSheet.ServerRow.Detail.<uuid>`.

### 7. ServerListSheet.swift — NavigationStack + navigationDestination

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift`

Wrapped `sheetContent` in `NavigationStack`. Added `.navigationDestination(item: $viewModel.openServerDetail)` that pushes `ServerDetailView`. Passes `onDetailTap: { viewModel.openDetail(for: server) }` to each `ServerRow`.

**Open Q3 note:** Sheet detent collapse on navigation push not forced to `.large` — UAT will determine if Phase 11 follow-up is needed.

### 8. ServerListViewModel.swift — Navigation State

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift`

- `@Published public var openServerDetail: ServerConfig? = nil`
- `public func openDetail(for server: ServerConfig)` — sets openServerDetail
- `public func makeDetailViewModel(for server: ServerConfig) -> ServerDetailViewModel` — factory used by .navigationDestination

### 9. ConfigImporter.swift — Wire-up + reparseAnyParsedConfig

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`

- `transportOverride(for:)`: stub `return nil` → **real** `return cfg.transportOverride`
- `reparseAnyParsedConfig(from:)`: new `@MainActor` public method; prefers Keychain, returns nil if unavailable

### 10. ConfigImporting.swift — Protocol Extension

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift`

Added `@MainActor func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig?` to the protocol. Annotated `@MainActor` to satisfy Swift 6 strict concurrency when passing `@Model` objects.

All existing ConfigImporting stubs in tests updated with no-op implementations.

### 11. Localization — 15 New Keys

**Files:** `Localizable.xcstrings` + `L10n.swift`

Keys added (ru + en):
- `serverDetailGeneralSection`, `serverDetailParsedSection`, `serverDetailTransportSection`
- `serverDetailTransport`, `serverDetailTransportAuto`, `serverDetailTransportFooter`
- `serverDetailName`, `serverDetailHost`, `serverDetailPort`, `serverDetailProtocol`
- `serverDetailLatency`, `serverDetailFlow`, `serverDetailFingerprint`
- `serverDetailPublicKey`, `serverDetailShortId`, `serverDetailAccessibilityHint`

## Test Results

| Suite | Tests | New | Status |
|-------|-------|-----|--------|
| VPNCore | 45 | +4 | PASS |
| AppFeatures (all suites) | 54 | +5 | PASS |

No regressions. ConfigParser builds clean.

## Critical Implementation Notes

### Pitfall 4 Compliance (SwiftData #Predicate with Codable enum)
`ServerDetailViewModel.applyTransportSelection` uses:
```swift
let allServers = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
guard let cfg = allServers.first(where: { $0.id == server.id }) else { ... }
```
Never `#Predicate` for `transportOverride` filter.

### Swift 6 Strict Concurrency
`reparseAnyParsedConfig` is `@MainActor` in protocol and implementation — `ServerConfig` is a `@Model` class whose properties can only be safely accessed on MainActor.

## Manual UAT Required (Device)

**Task 5 — Human verification checkpoint (not automated):**

1. **SwiftData migration safety** — install Phase 4 build → import server → install Phase 5 over it → verify no crash + transportOverride == nil for all servers
2. **Chevron → push navigation** — tap `›` on any server row → ServerDetailView pushes; back button works; sheet doesn't collapse
3. **Picker persistence** — select WebSocket for a server → close detail → reopen → Picker shows WebSocket
4. **End-to-end connect with override** — WebSocket override on a WS-capable VLESS+TLS server → connect → verify transport block in sing-box logs
5. **Phase 2 Trojan-WS regression** — re-import Trojan-WS subscription → connect → works as before

## Phase 11 Follow-ups

- **Open Q3** (NavigationStack-in-sheet detent collapse) — if sheet collapses when pushing to detail on iOS 18, force `.large` detent reactively when `openServerDetail != nil`
- **ServerDetailView per-field editing** (SNI, publicKey override) — Phase 10 Advanced Settings
- **TransportPicker path/host editing** (coarse → fine override) — Wave 10
- **reparseAnyParsedConfig rawURI path** (for unsupported servers without Keychain) — Wave 11

## Phase 5 Architecture Summary (for wiki/transports.md)

Phase 5 completes the transport overlay architecture:
- `TransportConfig` enum in VPNCore — shared across all protocol packages (D-04)
- `TransportRegistry` — registry pattern matching `ProtocolRegistry.shared` (CORE-03)
- `PoolBuilder` — thin coordinator; delegates `buildOutbound` to per-protocol packages (D-14/D-15)
- `ServerConfig.transportOverride` — per-server Picker state in SwiftData (D-19)
- `ConfigImporter.applyTransportOverride` + `transportOverride(for:)` — wire-up from D-19 to PoolBuilder
- All invariants preserved: R1 strict-TLS, D-08 Hysteria2 exception, ALPN h2-strip

**Next phase:** Phase 6 — Network resilience.
