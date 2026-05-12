# Phase 3: Server Management — Pattern Map

**Mapped:** 2026-05-12
**Files analyzed:** 16 (10 NEW + 6 MODIFIED)
**Analogs found:** 16/16

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `VPNCore/Sources/VPNCore/Subscription.swift` | model | CRUD | `VPNCore/Sources/VPNCore/ServerConfig.swift` | exact (same package, same @Model paradigm) |
| `VPNCore/Sources/VPNCore/ServerConfig.swift` (MOD) | model | CRUD | self (Phase 2 schema) | self-extend |
| `VPNCore/Sources/VPNCore/SwiftDataContainer.swift` (MOD) | service (container factory) | file-I/O | self (Phase 1 baseline) | self-extend |
| `VPNCore/Sources/VPNCore/ProbeResult.swift` | model (value-types) | transform | `ConfigParser/.../ImportedServer.swift` (Sendable enum/struct) | role-match |
| `VPNCore/Sources/VPNCore/ServerScore.swift` | utility (pure-data) | transform | `ConfigParser/.../PoolBuilder.swift` (pure-static utility) | role-match |
| `VPNCore/Sources/VPNCore/ServerProbeService.swift` | service (actor) | streaming (AsyncStream) | `ConfigParser/.../UniversalImportParser.swift` (actor) + `TunnelController.swift` (async API) | role-match (actor + async iteration) |
| `ConfigParser/.../PoolBuilder.swift` (MOD) | utility | transform | self (Phase 2 baseline) | self-extend |
| `ConfigParser/.../SubscriptionMergeService.swift` | service | transform/CRUD | `ConfigParser/.../UniversalImportParser.swift` + `ConfigImporter.deleteExistingPool` | role-match |
| `ConfigParser/.../UniversalImportParser.swift` (MOD) | service (parser actor) | transform | self (Phase 2 baseline) | self-extend |
| `MainScreenFeature/MainScreenViewModel.swift` (MOD) | view-model | event-driven | self (Phase 2 baseline) | self-extend |
| `MainScreenFeature/MainScreenView.swift` (MOD) | view (SwiftUI) | request-response | self (Phase 2 — `.fullScreenCover`/`.sheet` modifier already used) | self-extend |
| `MainScreenFeature/ConfigImporter.swift` (MOD) | service | CRUD (SwiftData + Keychain) | self (Phase 2 baseline) | self-extend |
| `MainScreenFeature/ServerLineView.swift` (MOD) | view (component) | request-response | self + `ConnectionButton.swift` (button-with-tap) | self-extend |
| `ServerListFeature/ServerListSheet.swift` | view (SwiftUI root) | request-response | `SettingsFeature/SettingsView.swift` + `MainScreenView.swift` (sheet+toolbar) | role-match |
| `ServerListFeature/ServerListViewModel.swift` | view-model | streaming (AsyncStream consume) | `MainScreenFeature/MainScreenViewModel.swift` | exact (@MainActor ObservableObject) |
| `ServerListFeature/ServerListState.swift` | model (enum FSM) | transform | `MainScreenFeature/ConnectionState.swift` | exact (same enum-state-machine paradigm) |
| `ServerListFeature/AutoCell.swift` | view (component) | request-response | `MainScreenFeature/ServerLineView.swift` + `EmptyStateCard.swift` | role-match |
| `ServerListFeature/SubscriptionHeader.swift` | view (component) | request-response | `MainScreenFeature/ReconnectBanner.swift` (HStack + action) | role-match |
| `ServerListFeature/ServerRow.swift` | view (component) | request-response | `MainScreenFeature/ServerLineView.swift` | role-match (same package paradigm) |
| `ServerListFeature/LatencyBadge.swift` | view (component) | request-response | `MainScreenFeature/StatusPill.swift` (capsule + state-driven colors) | exact (Capsule + state→colour) |
| `ServerListFeature/PingState.swift` | model (enum) | transform | `MainScreenFeature/ConnectionState.swift` | exact |

**Tally:** 7 exact, 11 role-match, 0 partial, 0 none.

---

## Pattern Assignments

### `VPNCore/Sources/VPNCore/Subscription.swift` (model, CRUD) — NEW

**Analog:** `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift`

**Imports pattern** (`ServerConfig.swift:1-2`):
```swift
import Foundation
import SwiftData
```

**@Model class pattern** (`ServerConfig.swift:22-64`):
```swift
@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    // ... typed mutable stored properties ...
    public var createdAt: Date

    public init(id: UUID = UUID(),
                name: String,
                /* ... defaults ... */) {
        self.id = id; self.name = name
        // ... assign every property ...
    }
}
```

**Why this analog:** Same package, same SwiftData paradigm, same `@Attribute(.unique) public var id: UUID` invariant, same `public final class`+`public init(... = defaults)`. Subscription тоже сидит в App Group store рядом с ServerConfig (см. SwiftDataContainer).

**Do NOT use `@Relationship`** — RESEARCH §«SwiftData @Model Subscription с manual FK» (Pattern 3) фиксирует rationale: lightweight migration требует manual FK (`subscriptionID: UUID?` на ServerConfig), не `@Relationship`.

---

### `VPNCore/Sources/VPNCore/ServerConfig.swift` (model, CRUD) — MODIFIED

**Analog:** self.

**Existing init signature** (`ServerConfig.swift:42-63`):
```swift
public init(id: UUID = UUID(),
            name: String,
            host: String,
            port: Int,
            protocolID: String,
            keychainTag: String?,
            isSupported: Bool = true,
            subscriptionURL: String? = nil,
            outboundJSON: String = "",
            protocolDisplayName: String = "",
            sni: String? = nil,
            rawURI: String? = nil) {
    self.id = id; self.name = name; self.host = host; self.port = port
    self.protocolID = protocolID; self.keychainTag = keychainTag
    self.isActive = false; self.createdAt = .now
    self.isSupported = isSupported
    self.subscriptionURL = subscriptionURL
    /* ... */
}
```

**Phase 3 new fields — все optional с defaults (lightweight migration)** (per RESEARCH §«Pitfall 2» + Example 4 строки 880-923):
```swift
// NEW Phase 3 (all optional → lightweight migration):
public var subscriptionID: UUID?
public var countryCode: String?
public var lastPingedAt: Date?
public var failedProbeCount: Int?
public var missingFromLastFetch: Bool   // default false (D-14)
```

**Computed properties pattern (no migration impact)** — добавить после init:
```swift
public var countryFlag: String {
    guard let code = countryCode, code.count == 2 else { return "🌐" }
    return code.uppercased().unicodeScalars
        .compactMap { Unicode.Scalar(127397 + $0.value) }
        .map(String.init).joined()
}
public var isUnreachable: Bool { (failedProbeCount ?? 0) >= 3 }
```

**Critical:** НЕ удалять `subscriptionURL: String?` — он остаётся deprecated для data-migration. Удалить в Phase 4 via VersionedSchema.

---

### `VPNCore/Sources/VPNCore/SwiftDataContainer.swift` (service, file-I/O) — MODIFIED

**Analog:** self (Phase 1 baseline).

**Existing pattern** (`SwiftDataContainer.swift:6-23`):
```swift
public enum SwiftDataContainer {
    public static let appGroupIdentifier = "group.app.bbtb.shared"

    public static func makeShared() throws -> ModelContainer {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            return try ModelContainer(
                for: ServerConfig.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let storeURL = containerURL.appendingPathComponent("ServerConfigStore.sqlite")
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: ServerConfig.self, configurations: config)
    }
}
```

**Phase 3 changes** (per RESEARCH Example 3, строки 806-874):
1. Register `Subscription.self` в schema (оба места — App-Group path **и** in-memory fallback).
2. Добавить `private static let migrationDoneKey = "app.bbtb.phase3.migrationDone"` (UserDefaults idempotency flag).
3. Добавить `private static func migratePhase2ToPhase3(in: ModelContainer) throws` который:
   - Fetch'ит `ServerConfig where subscriptionURL != nil`.
   - Группирует по `subscriptionURL`, для каждой уникальной URL создаёт `Subscription` (FetchDescriptor check на дубль перед insert).
   - Проставляет `srv.subscriptionID = sub.id`.
   - `context.save()`.
4. После создания контейнера — `if !UserDefaults.standard.bool(forKey: migrationDoneKey) { try migrate...; UserDefaults.standard.set(true, forKey: migrationDoneKey) }`.

**Pitfall warning (RESEARCH §«Pitfall 9»):** идемпотентность обязательна — без UserDefaults flag будут дубли Subscription rows при каждом launch.

---

### `VPNCore/Sources/VPNCore/ProbeResult.swift` + `ServerScore.swift` (value-types + utility) — NEW

**Analog:** `ConfigParser/Sources/ConfigParser/ImportedServer.swift` (Sendable enums) + `ConfigParser/Sources/ConfigParser/PoolBuilder.swift` (pure-data utility).

**Sendable enum pattern** (взят из RESEARCH Example 1, строки 647-662):
```swift
import Foundation

public enum ProbeResult: Sendable, Equatable {
    case ok(latencyMs: Int)
    case timeout
    case error(String)
}

public struct ProbeAggregate: Sendable {
    public let avgLatencyMs: Int?
    public let lossRate: Double
    public let probedAt: Date
    public var score: Double? {
        guard let ms = avgLatencyMs else { return nil }
        return Double(ms) * (1.0 + lossRate)   // D-03 formula
    }
    public var isUnreachable: Bool { avgLatencyMs == nil }
}
```

**Reasoning:** ProbeResult/ProbeAggregate — **Sendable value types**, пересекают actor boundary между `ServerProbeService` (actor) и `@MainActor ServerListViewModel`. **НЕ** передавать `[ServerConfig]` через actor — это nonsendable @Model (RESEARCH §«Pitfall 4»).

---

### `VPNCore/Sources/VPNCore/ServerProbeService.swift` (actor service, streaming) — NEW

**Analog:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` (actor с async API) + `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` (async-throws pattern).

**Actor declaration pattern** (`UniversalImportParser.swift:43-49`):
```swift
public actor UniversalImportParser {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }
    // ... public async functions ...
}
```

**Apply to ServerProbeService** (RESEARCH Example 1, строки 664-727 + Example 2, строки 736-781):
```swift
import Foundation
import Network
import OSLog

public actor ServerProbeService {
    private let log = Logger(subsystem: "app.bbtb.server-probe", category: "probe")
    private let queue = DispatchQueue(label: "app.bbtb.probe", qos: .userInitiated)

    public init() {}

    public func probeOnce(host: String, port: Int, timeoutMs: Int = 500) async -> ProbeResult {
        // NWConnection + withTaskCancellationHandler + withCheckedContinuation + LockedBool
        // — точная копия RESEARCH Example 1 строки 670-727.
    }

    public nonisolated func probeAll(
        _ servers: [(id: UUID, host: String, port: Int)]
    ) -> AsyncStream<(UUID, ProbeAggregate)> {
        // AsyncStream + TaskGroup + continuation.onTermination — точная копия
        // RESEARCH Example 2 строки 738-780.
    }
}
```

**OSLog subsystem pattern** — `subsystem: "app.bbtb.server-probe"`, category `"probe"` (matches tech-stack obligation).

**Pitfall-1 mitigation** — strong-reference на NWConnection через capturing inside `withCheckedContinuation` (RESEARCH §«Pitfall 1»). LockedBool helper (RESEARCH строки 716-726) гарантирует single-resume.

**Pitfall-3 mitigation** — `withTaskCancellationHandler { ... } onCancel: { connection.cancel() }` для propagation cancellation (RESEARCH §«Pitfall 3»).

**Pitfall-4 mitigation** — API принимает `[(id: UUID, host: String, port: Int)]` tuple (Sendable), не `[ServerConfig]` (RESEARCH §«Pitfall 4»).

---

### `ConfigParser/.../PoolBuilder.swift` (utility, transform) — MODIFIED

**Analog:** self.

**Existing degenerate-case pattern** (`PoolBuilder.swift:54-56`):
```swift
let finalTag: String
if truncated.count == 1 {
    finalTag = tags[0]  // degenerate case — direct route.final
} else {
    finalTag = "urltest-out"
    // ... urltest selector ...
}
```

**Phase 3 addition** (per RESEARCH Example 6, строки 1031-1034) — `buildSingleOutboundJSON` просто вызывает existing degenerate path:
```swift
extension PoolBuilder {
    /// Phase 3: pool с одним конкретным outbound (manual selection или auto-select winner).
    public static func buildSingleOutboundJSON(from parsed: AnyParsedConfig) throws -> String {
        return try buildSingBoxJSON(from: [parsed])  // existing degenerate path
    }
}
```

**Why:** избегаем дублирования логики — degenerate case в `buildSingBoxJSON` уже корректно работает для 1 outbound (без urltest, `route.final = tags[0]`).

---

### `ConfigParser/.../SubscriptionMergeService.swift` (service, transform/CRUD) — NEW

**Analog:** `ConfigParser/.../UniversalImportParser.swift` (actor с parse method) + `MainScreenFeature/ConfigImporter.swift` lines 315-326 (existing `deleteExistingPool` SwiftData fetch+delete pattern).

**Identity dedup pattern** (D-14 — same host+port+protocolID+sni = same server):

**Imports** (mirror `UniversalImportParser.swift:1-2`):
```swift
import Foundation
import SwiftData
import VPNCore
```

**Existing SwiftData mutation pattern** (`ConfigImporter.swift:315-326`):
```swift
private func deleteExistingPool(subscriptionURL: String, in context: ModelContext) throws {
    let descriptor = FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.subscriptionURL == subscriptionURL }
    )
    let existing = try context.fetch(descriptor)
    for cfg in existing {
        if let tag = cfg.keychainTag {
            try? KeychainStore.delete(tag: tag)
        }
        context.delete(cfg)
    }
}
```

**Apply for merge** (Phase 3 — D-14 merge semantics):
```swift
public enum SubscriptionMergeService {
    /// Merge fetched URIs into existing ServerConfig pool for one subscription.
    /// - existing (same host+port+protocolID+sni) → keep id, update name/metadata, preserve lastLatencyMs
    /// - new URI → insert new ServerConfig with subscriptionID
    /// - existing but absent in fresh fetch → set missingFromLastFetch = true (NOT delete — D-14)
    public static func merge(
        fetched: [ImportedServer],
        into subscription: Subscription,
        context: ModelContext
    ) throws {
        // 1. Fetch existing ServerConfig where subscriptionID == subscription.id
        // 2. Build identity key (host+port+protocolID+sni)
        // 3. For each fetched → upsert by identity
        // 4. Mark unseen as missingFromLastFetch = true
        // 5. subscription.lastFetched = .now
    }
}
```

---

### `ConfigParser/.../UniversalImportParser.swift` (parser actor) — MODIFIED

**Analog:** self.

**Existing subscription URL flow** (`UniversalImportParser.swift:221-256`):
```swift
private func fetchAndParseSubscription(url: URL) async throws -> ImportResult {
    let fetchResult: SubscriptionFetchResult
    do {
        fetchResult = try await SubscriptionURLFetcher.fetch(url: url, session: session)
    } catch {
        throw UniversalImportError.fetchFailed(error.localizedDescription)
    }
    let format = SubscriptionURLFetcher.detectFormat(body: fetchResult.body)
    /* ... dispatch by format ... */
}
```

**Phase 3 changes:**
- Emit `SubscriptionMetadata.title` (already extracted, строки 73-74) **наверх** в ImportResult — для derivation `Subscription.name` (RESEARCH «User Constraints / Claude's Discretion»: Profile-Title → URL host → fallback «Подписка #N»).
- ImportResult already has `metadata: SubscriptionMetadata?` field (`UniversalImportParser.swift:10-15`) — ничего менять не нужно, просто читать в caller.

---

### `MainScreenFeature/MainScreenViewModel.swift` (view-model, event-driven) — MODIFIED

**Analog:** self.

**Existing @MainActor ObservableObject pattern** (`MainScreenViewModel.swift:7-38`):
```swift
@MainActor
public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState = .empty
    @Published public private(set) var activeServerName: String?
    @Published public private(set) var supportedConfigCount: Int = 0
    @Published public var lastError: String?

    public let importer: ConfigImporting
    public let tunnel: TunnelControlling

    public init(importer: ConfigImporting, tunnel: TunnelControlling) {
        self.importer = importer
        self.tunnel = tunnel
        Task { @MainActor in await refresh() }
        // NotificationCenter observer for UserDefaults changes
    }
}
```

**Existing toggle implementation** (`MainScreenViewModel.swift:120-142`):
```swift
private func performToggleImpl() async {
    switch state {
    case .empty, .connecting: return
    case .idle, .error:
        state = .connecting
        do {
            let since = try await tunnel.connect()
            state = .connected(since: since)
        } catch {
            state = .error(message: error.localizedDescription)
        }
    case .connected:
        do {
            try await tunnel.disconnect()
            state = .idle
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }
}
```

**Phase 3 additions:**
- `@Published public var selectedServerID: UUID? = nil` (nil = Авто) — persisted в UserDefaults через `@AppStorage` или manual mirror (`SettingsViewModel.swift:7` показывает `@AppStorage` pattern).
- `@Published public var isPresentingServerList: Bool = false` — driver для `.sheet` modifier.
- `private let probeService: ServerProbeService` injection через init.
- Pre-connect auto-select: при `state == .idle && selectedServerID == nil` → перед `tunnel.connect()` вызвать `await pingAllSupportedServers()` → выбрать min score → пересобрать pool через `PoolBuilder.buildSingleOutboundJSON` → переapply `provisionTunnelProfile` (delegate to ConfigImporter helper) → `tunnel.connect()`.
- Auto-reconnect при `selectServer(id:)` если `case .connected = state` — паттерн идентичен Phase 2 reconnect (см. ReconnectBanner).

**Pitfall-8 mitigation** (RESEARCH §«Pitfall 8») — если 0 reachable servers → state = `.error("Все серверы недоступны")` (новый L10n key).

---

### `MainScreenFeature/MainScreenView.swift` (view) — MODIFIED

**Analog:** self.

**Existing `.fullScreenCover` / `.sheet` pattern** (`MainScreenView.swift:62-83`):
```swift
#if os(iOS)
.fullScreenCover(isPresented: $showQRScanner) {
    QRScannerView(/*...*/)
}
#elseif os(macOS)
.sheet(isPresented: $showQRScanner) {
    QRScannerView(/*...*/)
        .frame(width: 480, height: 640)
}
#endif
```

**Phase 3 server-list sheet** — D-08 фиксирует `.sheet` + `.presentationDetents([.large])`:
```swift
.sheet(isPresented: $viewModel.isPresentingServerList) {
    ServerListSheet(viewModel: serverListVM)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)  // RESEARCH §«Sheet с pull-to-refresh» — macOS ignores detents
        #endif
}
```

**ServerLineView tap binding** (`MainScreenView.swift:131-133`):
```swift
if let name = viewModel.activeServerName {
    ServerLineView(name: name)
}
```
→ Wrap в `Button { viewModel.isPresentingServerList = true } label: { ServerLineView(name: name) }` либо передать onTap closure в ServerLineView (предпочтительно — keep View focused, pull tap up).

---

### `MainScreenFeature/ConfigImporter.swift` (service) — MODIFIED

**Analog:** self.

**Existing replace-pool branch** (`ConfigImporter.swift:122-134`):
```swift
let context = ModelContext(modelContainer)
do {
    if let subURL = result.subscriptionURL {
        try deleteExistingPool(subscriptionURL: subURL, in: context)
    } else {
        try deleteAllExistingConfigs(in: context)
    }
} catch {
    throw ImporterError.swiftDataSaveFailed(error)
}
```

**Phase 3 rewire** (CONTEXT D-06, RESEARCH Example 7 строки 1046-1049):
- При `result.subscriptionURL != nil` → fetch existing `Subscription where url == subURL`. Если existing → call `SubscriptionMergeService.merge(...)` (НЕ delete). Если новая → `context.insert(Subscription(url: ..., name: derive(title || host)))`.
- При `result.subscriptionURL == nil` (single paste) → НЕ удалять весь pool (Phase 2 behavior) — добавить ServerConfig с `subscriptionID = nil` в «Manual» section. Это **breaking change** относительно Phase 2 `deleteAllExistingConfigs` — фиксируется как Phase 3 transition: «manual paste accumulates, не заменяет».
- `ServerConfig.subscriptionID = sub.id` устанавливается в `persistSupported` (extend signature: добавить `subscriptionID: UUID?` параметр) — параллельно с `subscriptionURL` (deprecated, оба заполняются для compat в Phase 3).

**provisionTunnelProfile sub-selection** (RESEARCH Example 6 строки 1036-1038) — extract helper:
```swift
public func provisionTunnelProfile(for selectedID: UUID?) async throws {
    let context = ModelContext(modelContainer)
    let supportedDesc = FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.isSupported == true }
    )
    let supported = try context.fetch(supportedDesc)
    let parsed: [AnyParsedConfig]
    if let id = selectedID, let one = supported.first(where: { $0.id == id }) {
        parsed = [reparseFromKeychain(one)]   // 1 outbound — degenerate
    } else {
        parsed = supported.map(reparseFromKeychain)
    }
    let json = try PoolBuilder.buildSingBoxJSON(from: parsed)
    // ... existing NETunnelProviderManager save flow ...
}
```

**Pitfall-10 mitigation** (RESEARCH «Pitfall 10») — deleteServer flow: если deleted server == `selectedServerID` → reset to nil (Auto); если tunnel active → reconnect через provisionTunnelProfile с обновлённым массивом.

---

### `MainScreenFeature/ServerLineView.swift` (view component) — MODIFIED

**Analog:** self + `ConnectionButton.swift` (tap-enabled component).

**Existing implementation** (`ServerLineView.swift:6-23`):
```swift
public struct ServerLineView: View {
    public let name: String?

    public init(name: String?) { self.name = name }

    public var body: some View {
        if let name = name {
            HStack(spacing: DS.Spacing.xs) {
                Text(L10n.serverLabel)
                Text(name).fontWeight(.medium)
            }
            // ...
        }
    }
}
```

**Phase 3 changes:**
1. Добавить `onTap: () -> Void` параметр (D-08 — tap on server-line opens sheet).
2. Завернуть HStack в `Button(action: onTap) { ... }` + `.buttonStyle(.plain)` (как `TopBar.swift:26-30`).
3. Добавить chevron: `Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)` (per RESEARCH «code_context» note).
4. Accessibility trait `.isButton`.

Reference closure-style: `EmptyStateCard.swift:6-13` (init с `onAddFromClipboard: () -> Void` closures).

---

### `ServerListFeature/ServerListSheet.swift` (view root) — NEW

**Analog:** `SettingsFeature/SettingsView.swift` (Form-style root) + `MainScreenFeature/MainScreenView.swift` (toolbar + sheet container).

**Imports pattern** (`SettingsView.swift:1-2`):
```swift
import SwiftUI
import Localization
```
+ `import VPNCore` + `import DesignSystem` (per `MainScreenView.swift:1-3`).

**ObservedObject + body pattern** (`SettingsView.swift:5-30`):
```swift
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form { /* ... */ }
        .navigationTitle(L10n.settingsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
```

**Apply for ServerListSheet** (RESEARCH Example 4 строки 463-509):
```swift
public struct ServerListSheet: View {
    @ObservedObject public var viewModel: ServerListViewModel

    public init(viewModel: ServerListViewModel) { self.viewModel = viewModel }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                AutoCell(isSelected: viewModel.isAutoSelected, onTap: viewModel.selectAuto)
                ForEach(viewModel.sections) { section in
                    Section {
                        ForEach(section.servers) { server in
                            ServerRow(/* ... */)
                        }
                    } header: {
                        if let sub = section.subscription {
                            SubscriptionHeader(subscription: sub,
                                onDelete: { viewModel.requestDeleteSubscription(sub) })
                        } else {
                            Text(L10n.serverListManualSection)
                                .font(DS.Typography.caption)
                                .textCase(.uppercase)
                        }
                    }
                }
            }
        }
        .refreshable { await viewModel.pullToRefresh() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert(/* refresh error */)
        .confirmationDialog(/* delete subscription confirm */, isPresented: ...)
        .task { await viewModel.onAppear() }
    }
}
```

**Pitfall-5 mitigation** (RESEARCH «Pitfall 5») — внутри `pullToRefresh()` использовать только structured concurrency (`async let` или `withTaskGroup`), не `Task { ... }` detached, иначе leak'и при swipe-dismiss.

**Anti-pattern reminder** (RESEARCH §«Anti-patterns»): **НЕ** использовать `List` — используем `ScrollView + LazyVStack + Section` (UI-SPEC §2.2).

---

### `ServerListFeature/ServerListViewModel.swift` (view-model, streaming) — NEW

**Analog:** `MainScreenFeature/MainScreenViewModel.swift`.

**Imports** (mirror `MainScreenViewModel.swift:1-5`):
```swift
import Foundation
import SwiftUI
import SwiftData
import VPNCore
import ConfigParser
```

**Class declaration pattern** (`MainScreenViewModel.swift:7-23`):
```swift
@MainActor
public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState = .empty
    @Published public var lastError: String?

    public let importer: ConfigImporting
    public let tunnel: TunnelControlling

    public init(importer: ConfigImporting, tunnel: TunnelControlling) {
        self.importer = importer
        self.tunnel = tunnel
        Task { @MainActor in await refresh() }
    }
}
```

**Apply** (RESEARCH Example 5 строки 936-1001):
```swift
@MainActor
public final class ServerListViewModel: ObservableObject {
    @Published public private(set) var state: ServerListState = .loading
    @Published public private(set) var sections: [ServerListSection] = []
    @Published public private(set) var pingStates: [UUID: PingState] = [:]
    @Published public var refreshError: String?
    @Published public var pendingDeleteSubscription: Subscription?

    public weak var mainViewModel: MainScreenViewModel?  // for selectedServerID + reconnect

    private let modelContainer: ModelContainer
    private let probeService: ServerProbeService
    private let importer: ConfigImporting

    public init(modelContainer: ModelContainer,
                probeService: ServerProbeService,
                importer: ConfigImporting) {
        self.modelContainer = modelContainer
        self.probeService = probeService
        self.importer = importer
    }

    public func onAppear() async { /* loadFromStore + pingAllServers */ }
    public func pullToRefresh() async { /* D-13 sequential 2 phases */ }
    public func selectServer(id: UUID) { /* set mainViewModel.selectedServerID + dismiss + reconnect */ }
    public func selectAuto() { /* nil + dismiss + reconnect */ }
    public func deleteServer(id: UUID) { /* cascade + reconcile tunnel */ }
    public func confirmDeleteSubscription(_ sub: Subscription) { /* cascade delete */ }
}
```

**AsyncStream consumer pattern** (RESEARCH Example 5 строки 974-995):
```swift
private func pingAllServers() async {
    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })
    guard let supported = try? context.fetch(descriptor) else { return }
    let payload = supported.map { (id: $0.id, host: $0.host, port: $0.port) }
    for s in supported { pingStates[s.id] = .pinging }
    for await (id, agg) in probeService.probeAll(payload) {
        if Task.isCancelled { break }
        if let row = supported.first(where: { $0.id == id }) {
            row.lastLatencyMs = agg.avgLatencyMs
            row.lastPingedAt = agg.probedAt
            row.failedProbeCount = Int(agg.lossRate * 3)
        }
        pingStates[id] = .completed(agg)
    }
    try? context.save()
}
```

**Critical:** consumer запускается на `@MainActor`, потому что обновляет `@Published pingStates` и `ServerConfig` (нужен main-actor ModelContext per Phase 2 baseline). `ServerProbeService.probeAll` — `nonisolated` (см. RESEARCH строка 354), возвращает AsyncStream который безопасно потребляется на main-actor.

---

### `ServerListFeature/ServerListState.swift` + `PingState.swift` (model enums) — NEW

**Analog:** `MainScreenFeature/ConnectionState.swift` (см. `MainScreenView.swift:118-126` usage в switch).

**Enum-state-machine pattern** — apply to ServerListState (RESEARCH Example 5 строки 1003-1013):
```swift
public enum ServerListState: Equatable {
    case loading
    case loaded
    case pinging
    case refreshing
    case refreshError(String)
    case empty
}

public enum PingState: Equatable {
    case idle
    case pinging
    case completed(ProbeAggregate)
}
```

**Why enum (not Bool flags):** RESEARCH §«Don't Hand-Roll» — Sheet state machine: «Boolean flags `isLoading`, `isRefreshing`, `hasError` → Single enum `ServerListState` — pattern предотвращает invalid states».

---

### `ServerListFeature/AutoCell.swift` (view component) — NEW

**Analog:** `MainScreenFeature/EmptyStateCard.swift` (closure-init component) + `MainScreenFeature/ServerLineView.swift` (HStack row).

**Closure-init pattern** (`EmptyStateCard.swift:6-13`):
```swift
public struct EmptyStateCard: View {
    public let onAddFromClipboard: () -> Void
    public let onScanQR: () -> Void

    public init(onAddFromClipboard: @escaping () -> Void, onScanQR: @escaping () -> Void) {
        self.onAddFromClipboard = onAddFromClipboard
        self.onScanQR = onScanQR
    }
}
```

**Apply for AutoCell** — top-pinned «Авто» row с checkmark:
```swift
public struct AutoCell: View {
    public let isSelected: Bool
    public let onTap: () -> Void

    public init(isSelected: Bool, onTap: @escaping () -> Void) {
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "wand.and.stars")  // или похожее
                Text(L10n.serverAuto)
                    .font(DS.Typography.subheadline)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
        .buttonStyle(.plain)
    }
}
```

Reference for L10n: `L10n.serverAuto` уже есть (см. `L10n.swift:52`).

---

### `ServerListFeature/SubscriptionHeader.swift` (view component) — NEW

**Analog:** `MainScreenFeature/ReconnectBanner.swift` (HStack + iconography + action button).

**Pattern** (`ReconnectBanner.swift:14-35`):
```swift
public var body: some View {
    HStack(spacing: DS.Spacing.sm) {
        Image(systemName: "arrow.triangle.2.circlepath")
        Text(L10n.bannerReconnectNeeded).font(DS.Typography.subheadline)
        Spacer()
        Button(action: onDismiss) {
            Image(systemName: "xmark").font(.caption.bold())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.bannerDismiss))
    }
    .padding(DS.Spacing.md)
    .background(
        RoundedRectangle(cornerRadius: DS.Radius.card)
            .fill(Color.orange.opacity(0.15))
    )
    // ...
}
```

**Apply for SubscriptionHeader** — section header c subscription name + last-fetched + delete button:
```swift
public struct SubscriptionHeader: View {
    public let subscription: Subscription
    public let onDelete: () -> Void

    public init(subscription: Subscription, onDelete: @escaping () -> Void) {
        self.subscription = subscription
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(subscription.name)
                .font(DS.Typography.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if let fetched = subscription.lastFetched {
                Text(RelativeDateTimeFormatter().localizedString(for: fetched, relativeTo: .now))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}
```

Per D-07: swipe по заголовку секции → confirmation dialog (alert/confirmationDialog handled в ServerListViewModel + ServerListSheet).

---

### `ServerListFeature/ServerRow.swift` (view component) — NEW

**Analog:** `MainScreenFeature/ServerLineView.swift` (HStack server-row).

**Existing HStack server pattern** (`ServerLineView.swift:13-22`):
```swift
HStack(spacing: DS.Spacing.xs) {
    Text(L10n.serverLabel)
    Text(name).fontWeight(.medium)
}
.font(DS.Typography.callout)
.foregroundStyle(.secondary)
```

**Apply for ServerRow** (per D-11 — флаг + имя + LatencyBadge + unsupported plate):
```swift
public struct ServerRow: View {
    public let server: ServerConfig
    public let isSelected: Bool
    public let pingState: PingState
    public let onTap: () -> Void
    public let onDelete: () -> Void

    public init(server: ServerConfig, isSelected: Bool, pingState: PingState,
                onTap: @escaping () -> Void, onDelete: @escaping () -> Void) {
        // ... assign all ...
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                Text(server.countryFlag).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(DS.Typography.body)
                    if !server.isSupported {
                        Text("Не поддерживается").font(DS.Typography.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                LatencyBadge(pingState: pingState, isSupported: server.isSupported,
                             isUnreachable: server.isUnreachable)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .opacity(server.isSupported ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}
```

**iOS haptic** (RESEARCH §«Standard Stack» Supporting table) — добавить `UIImpactFeedbackGenerator(style: .light).impactOccurred()` в `onTap` для iOS.

---

### `ServerListFeature/LatencyBadge.swift` (view component) — NEW

**Analog:** `MainScreenFeature/StatusPill.swift` (state-driven capsule).

**Pattern** (`StatusPill.swift:10-23`):
```swift
public var body: some View {
    Text(label)
        .font(DS.Typography.subheadline)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(Capsule())
}
```

**Apply for LatencyBadge** — state-driven label/color (D-11 — `lastLatencyMs` ms, «недоступен», «не поддерживается», pinging):
```swift
public struct LatencyBadge: View {
    public let pingState: PingState
    public let isSupported: Bool
    public let isUnreachable: Bool

    public var body: some View {
        Group {
            switch (isSupported, isUnreachable, pingState) {
            case (false, _, _):
                Text("не поддерживается").foregroundStyle(.tertiary)
            case (_, true, _):
                Text("недоступен").foregroundStyle(.red)
            case (_, _, .pinging):
                ProgressView().controlSize(.mini)
            case (_, _, .completed(let agg)):
                if let ms = agg.avgLatencyMs {
                    Text("\(ms) ms").foregroundStyle(colorForLatency(ms))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            case (_, _, .idle):
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .font(DS.Typography.caption)
    }

    private func colorForLatency(_ ms: Int) -> Color {
        switch ms {
        case ..<100: return .green
        case ..<300: return .orange
        default: return .red
        }
    }
}
```

---

## Shared Patterns

### Logging (OSLog)
**Source:** RESEARCH §«Standard Stack» Supporting + RESEARCH Example 1 строка 665.
**Apply to:** `ServerProbeService.swift`, `SubscriptionMergeService.swift`, и любые новые actor/services.
```swift
import OSLog
private let log = Logger(subsystem: "app.bbtb.server-probe", category: "probe")
log.info("probeOnce host=\(host) port=\(port) result=\(String(describing: result))")
```
**Subsystems:** `app.bbtb.server-probe` (ServerProbeService), `app.bbtb.server-list` (ViewModel/sheet), `app.bbtb.subscription-merge` (SubscriptionMergeService).

---

### Error Handling — Localized Enum
**Source:** `MainScreenFeature/ConfigImporter.swift:39-61` + `ConfigParser/.../PoolBuilder.swift:17-27`.
**Apply to:** Все новые services (SubscriptionMergeService, ServerProbeService — для public throwing API).
```swift
public enum ServerProbeError: Error, LocalizedError, Equatable {
    case invalidPort(Int)
    case cancelled
    public var errorDescription: String? {
        switch self {
        case .invalidPort(let p): return "Invalid port \(p)"
        case .cancelled: return "Probe cancelled"
        }
    }
}
```

---

### SwiftData ModelContext patterns
**Source:** `MainScreenFeature/ConfigImporter.swift:78-90, 315-326`.
**Apply to:** `ServerListViewModel`, `SubscriptionMergeService`, `SwiftDataContainer.migratePhase2ToPhase3`.
```swift
let context = ModelContext(modelContainer)
let descriptor = FetchDescriptor<ServerConfig>(
    predicate: #Predicate { $0.isSupported == true && $0.subscriptionID == subscriptionID }
)
let rows = try context.fetch(descriptor)
for row in rows { /* mutate */ }
try context.save()
```

---

### @Published + @MainActor ObservableObject
**Source:** `MainScreenFeature/MainScreenViewModel.swift:7-38`.
**Apply to:** `ServerListViewModel`.
```swift
@MainActor
public final class XxxViewModel: ObservableObject {
    @Published public private(set) var state: XxxState = .loading
    @Published public var lastError: String?
    public init(/* deps */) { Task { @MainActor in await initialLoad() } }
}
```

---

### Localization — L10n.swift
**Source:** `Localization/Sources/Localization/L10n.swift:5-13` (`tr()` helper + `static let` accessor).
**Apply to:** All new user-facing strings (Phase 3 will add ≈15 new keys per UI-SPEC §9 extension).
**Existing keys reusable:** `L10n.serverAuto`, `L10n.serverLabel`, `L10n.actionOK`, `L10n.actionCancel`, `L10n.bannerDismiss`, `L10n.alertImportFailed`.
**New keys (рекомендуемые):** `server.list.title`, `server.list.manual.section`, `server.list.unreachable`, `server.list.unsupported`, `server.list.delete.confirm.title`, `server.list.delete.confirm.message`, `server.list.refresh.error`, `server.list.no_reachable_servers`.

---

### Accessibility
**Source:** `ReconnectBanner.swift:33-35`, `EmptyStateCard.swift:34, 39`, `ServerLineView.swift:19-21`.
**Apply to:** All ServerListFeature components.
```swift
.accessibilityIdentifier("BBTB.ServerListSheet.AutoCell")
.accessibilityLabel(Text(L10n.serverAuto))
.accessibilityHint(Text("Включает автоматический выбор сервера"))
```

---

### Cross-platform `#if os(iOS)` / `#if os(macOS)`
**Source:** `MainScreenView.swift:41-55, 62-83`, `ConfigImporter.swift:11-15, 207-213`.
**Apply to:** ServerListSheet (presentationDetents ignored on macOS — use `.frame(minWidth:minHeight:)`); ServerRow (UIImpactFeedbackGenerator iOS-only).

---

### Sendable cross-actor boundary
**Source:** RESEARCH §«Pitfall 4» + `ConfigParser/.../UniversalImportParser.swift:43` (`public actor`).
**Apply to:** `ServerProbeService.probeAll(_: [(UUID, String, Int)])` — Sendable tuple, **NOT** `[ServerConfig]`. AsyncStream `(UUID, ProbeAggregate)` — оба Sendable.

---

## Package Wiring (Package.swift modifications)

### `AppFeatures/Package.swift` (MODIFIED)

**Existing pattern** (`AppFeatures/Package.swift:7-50`):
```swift
products: [
    .library(name: "MainScreenFeature", targets: ["MainScreenFeature"]),
    .library(name: "MenuBarFeature", targets: ["MenuBarFeature"]),
    .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
],
dependencies: [
    .package(path: "../VPNCore"),
    /* ... */
],
targets: [
    .target(name: "MainScreenFeature", dependencies: [/* ... */]),
    /* ... */
]
```

**Phase 3 additions:**
```swift
.library(name: "ServerListFeature", targets: ["ServerListFeature"]),

.target(
    name: "ServerListFeature",
    dependencies: ["VPNCore", "DesignSystem", "Localization", "ConfigParser", "MainScreenFeature"]
)
```

`MainScreenFeature` (existing) — добавить `"ServerListFeature"` в dependencies (для presentation из `MainScreenView.swift`). **Reverse-dep check:** ServerListFeature не должен depend'ить на MainScreenFeature напрямую — соединение через `weak var mainViewModel: MainScreenViewModel?` на ServerListViewModel; либо вынести MainScreenViewModel в отдельный target. **Рекомендация:** оставить one-way `MainScreenFeature → ServerListFeature`, и mainViewModel передавать в `ServerListViewModel.init` как opaque protocol (`ServerSelectionCoordinating`) объявленный в ServerListFeature, который реализует MainScreenViewModel в MainScreenFeature.

### `VPNCore/Package.swift` — NO CHANGES (новые .swift файлы автоматически подхватываются target'ом).

### `ConfigParser/Package.swift` — NO CHANGES.

---

## No Analog Found

Все 16 файлов имеют analogs в проекте (exact или role-match). Никаких файлов без analog — Phase 3 = orchestration существующих паттернов (SwiftData @Model, actor + AsyncStream, @MainActor ObservableObject, SwiftUI sheet+toolbar).

---

## Metadata

**Analog search scope:**
- `BBTB/Packages/VPNCore/Sources/VPNCore/*.swift` (5 файлов прочитано)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/*.swift` (3 файла прочитано: PoolBuilder, SubscriptionURLFetcher, UniversalImportParser, VLESSURIParser)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/*.swift` (9 файлов прочитано)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/*.swift` (3 файла прочитано)
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift`
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` (первые 80 строк)
- `BBTB/Packages/ConfigParser/Tests/.../PoolBuilderTests.swift`

**Files scanned:** 22 Swift файла.
**Pattern extraction date:** 2026-05-12.

**Cross-references for planner:**
- RESEARCH.md §«Architecture Patterns» → Pattern 1-4 (NWConnection, AsyncStream, @Model, sheet)
- RESEARCH.md §«Code Examples» Example 1-7 (verified code snippets)
- RESEARCH.md §«Common Pitfalls» Pitfall 1-10 (mitigation references)
- CONTEXT.md §«decisions» D-01..D-14 (locked decisions reflected in pattern assignments)
