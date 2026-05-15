# Phase 9: Deep Links — Pattern Map

**Mapped:** 2026-05-15
**Files analyzed:** 16 (8 NEW в новом SwiftPM пакете `DeepLinks` + 8 MODIFY в App / VPNCore / AppFeatures / Tuist Project)
**Analogs found:** 16 / 16 (все exact или role-match)

> Carved-out scope per CONTEXT.md scope-amendment: DEEP-03 (`/c/{token}`) и DEEP-04 (landing) — v1+ backlog. Phase 9 — только клиент + AASA. Архитектурная заглушка `TokenFetcher` остаётся в пакете для v1+.

> **Каноничный source-of-truth для архитектуры пакета** — `BBTB/Packages/RulesEngine/` (Phase 8). Каждый NEW file имеет exact pattern match к одному из RulesEngine файлов. Каждый MODIFY на App-layer ссылается на existing Phase 8 W4 wiring code в `BBTB_iOSApp.swift` / `BBTB_macOSApp.swift`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| **NEW** `BBTB/Packages/DeepLinks/Package.swift` | config (SwiftPM manifest) | build-time | `BBTB/Packages/RulesEngine/Package.swift` | exact (same Phase-8 pattern, fewer deps) |
| **NEW** `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift` | actor coordinator | request-response (async) | `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift` | exact (actor + ordered registry iteration + PerfSignposter + late-binding handlers) |
| **NEW** `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkHandler.swift` | protocol (Sendable) | request-response | `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` (lookup pattern) + `VPNProtocolHandler` (registered-type pattern) | exact (Sendable protocol + canHandle/handle) |
| **NEW** `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift` | service (handler impl) | transform (URL → raw → ConfigImporter) | `RulesEngineCoordinator.performBackgroundRefresh` body (sequential parse/validate/dispatch) | role-match (single-purpose service) |
| **NEW** `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/RemoteTokenFetchHandler.swift` | service (stub for v1+) | request-response (stubbed) | `RulesEngineCoordinator.performBackgroundRefresh` shape | role-match (placeholder per D-03) |
| **NEW** `BBTB/Packages/DeepLinks/Sources/DeepLinks/TokenFetcher.swift` | protocol placeholder | n/a (no impl in v0.9) | `FailoverProvider` protocol placeholder pattern | role-match (Sendable protocol stub) |
| **NEW** `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift` | error enum (LocalizedError) | n/a | `ImporterError` (ConfigImporter.swift:27-49) + `RulesFetcher.FetchError` | exact |
| **NEW** `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinksLogger.swift` | logger wrapper | logging | `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift` | exact |
| **NEW** `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/DeepLinkRouterTests.swift` | test | test-execution | `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift` | exact |
| **NEW** `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/ImportHandlerTests.swift` | test | test-execution | `RulesEngineCoordinatorTests` | exact |
| **NEW** `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/URLParsingTests.swift` | test | test-execution | `RulesFetcherTests` (URL parsing) | role-match |
| **MODIFY** `BBTB/App/iOSApp/BBTB_iOSApp.swift` | App entry point | event-driven (lifecycle) | itself (Phase 8 W4 `rulesCoordinator` wiring at lines 36-37, 170-213, 231-243 + Cold-start defer pattern) | exact (self-pattern) |
| **MODIFY** `BBTB/App/macOSApp/BBTB_macOSApp.swift` | App entry point | event-driven (lifecycle) | itself (Phase 8 W4 mirror) | exact (self-pattern) |
| **MODIFY** `BBTB/App/iOSApp/BBTB-iOS.entitlements` | entitlements (XML) | build-time | itself (existing keys 5-20) | exact (add associated-domains key) |
| **MODIFY** `BBTB/App/macOSApp/BBTB-macOS.entitlements` | entitlements (XML) | build-time | itself | exact |
| **MODIFY** `BBTB/App/iOSApp/Info.plist` | config (plist) | build-time | itself (Phase 8 W4 added `BGTaskSchedulerPermittedIdentifiers` lines 62-74) | exact (add CFBundleURLTypes) |
| **MODIFY** `BBTB/App/macOSApp/Info.plist` | config (plist) | build-time | iOS Info.plist (mirror) | exact |
| **MODIFY** `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift` (line 289-295 `ImportSource` enum) | model (enum) | n/a | itself (existing cases 290-294) | exact (add `.deepLink` case) |
| **MODIFY** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | view-model (MainActor) | request-response | itself (existing `performImport(_:raw:)` lines 672-696 + `wireRulesCoordinator` late-binding 102-103) | exact (self-pattern) |
| **MODIFY** `BBTB/Project.swift` (Tuist root) | config | build-time | itself (Phase 8 W1 `RulesEngine` addition lines 46, 95, 136) | exact |

---

## Pattern Assignments

### 1) `BBTB/Packages/DeepLinks/Package.swift` (config, build-time)

**Analog:** `BBTB/Packages/RulesEngine/Package.swift`

**Why this analog:** Phase 8 newest SwiftPM package в проекте. Те же platforms (`iOS 18 / macOS 15`), swift-tools-version 6.0, structure `Sources/<Name>/` + `Tests/<Name>Tests/`. Простее, потому что DeepLinks **не имеет внешних SwiftPM deps** (per RESEARCH.md § Standard Stack: только Foundation + OSLog).

**Header / tools-version pattern** (RulesEngine/Package.swift:1-3):
```swift
// swift-tools-version: 6.0
import PackageDescription
```

**Domain doc-comment pattern** (RulesEngine/Package.swift:4-18) — DeepLinks Package.swift должен в верхнем doc-block описать: Domain, Architecture (DeepLinkRouter actor + DeepLinkHandler protocol + ImportHandler concrete + RemoteTokenFetchHandler stub), и явно отметить — `// External dep: NONE — pure Foundation/OSLog. SSRF/HTTPS уже выполняется внутри ConfigImporter.importFromRawInput → SubscriptionURLFetcher.`

**Package declaration pattern** (RulesEngine/Package.swift:20-25):
```swift
let package = Package(
    name: "DeepLinks",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DeepLinks", targets: ["DeepLinks"]),
    ],
```

**Local sibling packages** (RulesEngine/Package.swift:26-38) — для DeepLinks нужны минимум **2 local deps**:
- `VPNCore` — для `ImportSource` enum (после добавления `.deepLink` case) + `ImportResult` тип, который возвращает `ConfigImporter.importFromRawInput`.
- `ConfigParser` — для public protocol `ConfigImporting` (PHASE 3 / Plan 04 переехал в ConfigParser per ConfigImporter.swift:22-24). DeepLinkRouter принимает `ConfigImporting` через DI, не concrete `ConfigImporter` (избегает reverse-dep AppFeatures → DeepLinks → AppFeatures).

```swift
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../ConfigParser"),
    ],
```

**Target + testTarget** (RulesEngine/Package.swift:39-73) — testTarget наследует те же linkerSettings что и main app **только если** транзитивно тянет libbox. DeepLinks **не тянет libbox** (не зависит от PacketTunnelKit). Поэтому linkerSettings блок убирается полностью; testTarget остаётся минимальным:
```swift
        .target(
            name: "DeepLinks",
            dependencies: ["VPNCore", "ConfigParser"]
        ),
        .testTarget(
            name: "DeepLinksTests",
            dependencies: ["DeepLinks"]
        ),
```

**No `resources:` section** — в отличие от RulesEngine (baseline manifest + .srs) у DeepLinks нет bundled resources в v0.9.

---

### 2) `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift` (actor coordinator)

**Analog:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift`

**Why this analog:** **самая близкая** пара. Тот же архетип: public actor + late-binding handlers + Sendable contract + PerfSignposter span + Logger logging + idempotent register/iterate API. Phase 8 verified working.

**Imports** (RulesEngineCoordinator.swift:1-2):
```swift
import Foundation
import os.signpost
```

**Notification name extension** (RulesEngineCoordinator.swift:6-20) — DeepLinks НЕ нужна notification (router сам await'ит результат и пробрасывает ошибку наверх). Это **исключение** из паттерна. Не копировать `Notification.Name` extension.

**PerfSignposter local subsystem** (RulesEngineCoordinator.swift:53-67) — копировать дословно с переименованием категории на `"deep-link"`:
```swift
enum PerfSignposter {
    static let client = OSSignposter(
        subsystem: "app.bbtb.client",
        category: "performance"
    )
}
```

**Actor declaration + Swift 6 visibility** (RulesEngineCoordinator.swift:109):
```swift
public actor DeepLinkRouter {
```

**Mutable state — ordered handler list** (analog к `cachedManifest` field RulesEngineCoordinator.swift:145):
```swift
private var handlers: [DeepLinkHandler] = []
```

**Re-entry guard / in-flight pattern** (RulesEngineCoordinator.swift:155-157) — **рекомендуется применить** для `handle(_:)`, потому что cold-start defer (D-09) может дублировать вызов если pendingURL flush race'ит с manual handleDeepLink:
```swift
private var isInFlight: Bool = false
```

**Public init с DI defaults** (RulesEngineCoordinator.swift:171-183) — копировать паттерн `init` с injectable dep:
```swift
public init(handlers: [DeepLinkHandler] = []) {
    self.handlers = handlers
}
```

**Public `register(_:)` API** (паттерн ProtocolRegistry.swift:12-15 + actor-isolation RulesEngineCoordinator.swift:109):
```swift
public func register(_ handler: DeepLinkHandler) {
    handlers.append(handler)
}
```

**Public `handle(_:)` body — ordered iterate + first canHandle wins** — собран из двух источников:
- iteration pattern: ProtocolRegistry.swift:17-20 (lookup by predicate)
- async/await + structured error: RulesEngineCoordinator.performBackgroundRefresh skeleton lines 267-281

```swift
public func handle(_ url: URL) async throws {
    guard !isInFlight else {
        DeepLinksLogger.router.notice("DeepLinkRouter.handle: rejected (in-flight)")
        return
    }
    isInFlight = true
    defer { isInFlight = false }

    // PerfSignposter span (DEC-06d-06).
    let signpostID = PerfSignposter.client.makeSignpostID()
    let state = PerfSignposter.client.beginInterval("DeepLinkHandle", id: signpostID)
    defer { PerfSignposter.client.endInterval("DeepLinkHandle", state) }

    DeepLinksLogger.router.notice("DeepLinkRouter.handle: url=\(url.absoluteString, privacy: .public)")

    for handler in handlers {
        if handler.canHandle(url) {
            try await handler.handle(url)
            return
        }
    }
    DeepLinksLogger.router.warning("DeepLinkRouter.handle: no handler matched url=\(url.absoluteString, privacy: .public)")
    throw DeepLinkError.unhandled(url: url)
}
```

**Logging with `privacy: .public`** (RulesEngineCoordinator.swift:203-205, 242-243, 416-419) — application всегда использует `privacy: .public` для **URL strings** (не secret) и `privacy: .public` для error.localizedDescription. Email/token query params — если когда-то добавятся — должны быть `privacy: .private`. В v0.9 нет таких полей.

---

### 3) `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkHandler.swift` (protocol)

**Analog:** ProtocolRegistry pattern (`ProtocolRegistry.swift:6-26`) + VPNProtocolHandler-like Sendable protocol.

**Why this analog:** ProtocolRegistry — каноничный extensible-protocol паттерн в codebase (registered-by-identifier). Для DeepLinks упрощается: нет identifier-key lookup, только ordered iteration с `canHandle(_:) -> Bool`.

**Full file pattern** (composed):
```swift
import Foundation

/// Phase 9 / DEEP-05 — protocol that конкретные deep-link handlers conform к.
///
/// Каждый handler отвечает за единственный URL pattern. `DeepLinkRouter`
/// итерирует ordered list and dispatches на первый matching handler.
///
/// **Sendable:** требуется для actor-isolated `DeepLinkRouter.handlers` array.
///
/// **Phase 9 conformers:**
///   * `ImportHandler` — `bbtb://import?url=…` и `https://import.bbtb.app/import?…`.
///   * `RemoteTokenFetchHandler` — **stub** (D-03) для v1+ token-endpoint.
public protocol DeepLinkHandler: Sendable {
    /// Synchronous predicate. Должен быть pure — никаких side-effects, никаких
    /// network IO. Router вызывает на каждом URL для всех handlers до первого `true`.
    func canHandle(_ url: URL) -> Bool

    /// Asynchronous handler. Вызывается **только если** `canHandle(url) == true`.
    /// Throws DeepLinkError при невозможности выполнить (или прокидывает ниже —
    /// например ImporterError из ConfigImporter).
    func handle(_ url: URL) async throws
}
```

---

### 4) `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift` (concrete handler)

**Analog (structural):** `RulesEngineCoordinator.performBackgroundRefresh` body (sequence: validate → parse → dispatch).
**Analog (functional):** `MainScreenViewModel.performImport(_:raw:)` (MainScreenViewModel.swift:672-696) — вызывает `importer.importFromRawInput` + `lastError = error.localizedDescription` pattern.

**Imports**:
```swift
import Foundation
import VPNCore       // ImportSource (после добавления `.deepLink` case)
import ConfigParser  // ConfigImporting public protocol
```

**Struct declaration + DI injectable** (RulesEngineCoordinator.swift:171-183 DI pattern):
```swift
public struct ImportHandler: DeepLinkHandler {
    private let importer: ConfigImporting

    public init(importer: ConfigImporting) {
        self.importer = importer
    }
```

**`canHandle(_:)` — accept BOTH** `bbtb://import…` AND `https://import.bbtb.app/import…` (per RESEARCH.md § Pattern 1 + Pattern 2 диаграмма — оба пути сходятся к одной handler):
```swift
public func canHandle(_ url: URL) -> Bool {
    // Custom scheme path: bbtb://import?url=…
    if url.scheme?.lowercased() == "bbtb", url.host?.lowercased() == "import" {
        return true
    }
    // Universal Link path: https://import.bbtb.app/import?…  (Apple lowercases host)
    if url.scheme?.lowercased() == "https",
       url.host?.lowercased() == "import.bbtb.app",
       url.path.hasPrefix("/import") {
        return true
    }
    return false
}
```

**`handle(_:)` body** — pattern из MainScreenViewModel.performImport (lines 672-696, do-try-await-import-then-state):
```swift
public func handle(_ url: URL) async throws {
    // 1. Parse query items
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw DeepLinkError.malformedURL(url)
    }
    // 2. Extract `url` parameter (auto-percent-decoded by URLQueryItem.value)
    guard let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value,
          !urlParam.isEmpty else {
        throw DeepLinkError.missingURLParameter
    }
    // 3. Sanity check — looks like URL (но НЕ переcompile'им — ConfigImporter сам parse'ит)
    guard URL(string: urlParam) != nil else {
        throw DeepLinkError.invalidSubscriptionURL(urlParam)
    }
    // 4. Delegate to ConfigImporter — same pipeline as `Paste` button.
    DeepLinksLogger.importer.notice("ImportHandler.handle: forwarding to ConfigImporter, urlParam=\(urlParam, privacy: .public)")
    _ = try await importer.importFromRawInput(urlParam, source: .deepLink)
}
```

**Note:** `ConfigImporting.importFromRawInput` уже **public** в `ConfigParser/Sources/ConfigParser/ConfigImporting.swift` (per comment ConfigImporter.swift:22-24). Verify-task для planner: убедиться что protocol exposes `importFromRawInput(_:source:)` или добавить, если не expose'но.

**Error handling pattern** (ImporterError ConfigImporter.swift:27-49) — НЕ wrapping, **rethrow as-is**: `ConfigImporter` уже бросает `ImporterError: LocalizedError`, у которого готовые русские локализованные `errorDescription` (line 38-47). DeepLinkRouter поднимет это до MainScreenViewModel, который сделает `lastError = error.localizedDescription` (MainScreenViewModel.swift:691). Existing `.alert(L10n.alertImportFailed, isPresented: errorBinding)` (MainScreenView.swift:72-76) покажет сразу пользователю.

---

### 5) `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/RemoteTokenFetchHandler.swift` (stub for v1+)

**Analog:** ImportHandler shape (sibling), с unimplemented body.

**Imports + struct skeleton** (mirror ImportHandler):
```swift
import Foundation
import ConfigParser

/// Phase 9 / D-03 — **STUB** for v1+ DEEP-03 token endpoint.
///
/// **NOT** registered с DeepLinkRouter в v0.9. Хранится в пакете как
/// архитектурная подготовка: когда в v1+ появится `GET /c/{token}` —
/// planner реализует body через `TokenFetcher` protocol и регистрирует
/// в App.init(). Тогда `canHandle` будет matching `https://import.bbtb.app/c/…`.
public struct RemoteTokenFetchHandler: DeepLinkHandler {
    private let tokenFetcher: TokenFetcher
    private let importer: ConfigImporting

    public init(tokenFetcher: TokenFetcher, importer: ConfigImporting) {
        self.tokenFetcher = tokenFetcher
        self.importer = importer
    }

    public func canHandle(_ url: URL) -> Bool {
        // v0.9 stub — НИКОГДА не matching (DEEP-03 deferred к v1+).
        return false
    }

    public func handle(_ url: URL) async throws {
        // TODO(v1+ DEEP-03): extract token from path, call tokenFetcher.fetchConfig,
        // forward raw config to importer.importFromRawInput(_, source: .deepLink).
        throw DeepLinkError.notImplemented
    }
}
```

---

### 6) `BBTB/Packages/DeepLinks/Sources/DeepLinks/TokenFetcher.swift` (protocol placeholder)

**Analog:** **`FailoverProvider` protocol placeholder** in `MainScreenFeature/FailoverProvider.swift`, и `TunnelProvisioning` protocol in `ConfigImporter.swift:53-56`:
```swift
public protocol TunnelProvisioning: Sendable {
    func provisionTunnelProfile(configJSON: String, serverHost: String) async throws
}
```

**Full file** — Sendable protocol-placeholder без implementations:
```swift
import Foundation

/// Phase 9 / D-03 — **PROTOCOL PLACEHOLDER** for v1+ DEEP-03 token endpoint resolution.
///
/// **Не имеет конкретных conformers в Phase 9.** В v1+ planner реализует:
///   * `MarzbanDirectTokenFetcher` — прямой прокси к Marzban `/sub/{token}`.
///   * `ShlinkTokenFetcher` — Shlink-backed alias resolution (Codex рекомендация).
///
/// **Sendable** required для cross-actor использования из DeepLinkRouter.
public protocol TokenFetcher: Sendable {
    /// Возвращает raw subscription config string (то что `ConfigImporter.importFromRawInput`
    /// принимает). Должен throw'ить при network/auth/token-not-found.
    func fetchConfig(forToken token: String) async throws -> String
}
```

---

### 7) `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift` (error enum)

**Analog (primary):** `ImporterError` (ConfigImporter.swift:27-49) — LocalizedError + Russian errorDescription strings (используется напрямую в MainScreenViewModel.lastError = error.localizedDescription).
**Analog (secondary):** `RulesFetcher.FetchError` (RulesFetcher.swift partial, Equatable + LocalizedError pattern).

**ImporterError reference pattern** (ConfigImporter.swift:27-49):
```swift
public enum ImporterError: Error, LocalizedError {
    case emptyPasteboard
    case malformedURI(Error)
    case noSupportedServers
    ...
    public var errorDescription: String? {
        switch self {
        case .emptyPasteboard: return L10n.importErrorNoPasteboard
        case .malformedURI: return L10n.importErrorMalformed
        case .noSupportedServers: return "В источнике нет поддерживаемых конфигураций."
        ...
        }
    }
}
```

**DeepLinkError full file** (compose ImporterError shape + RulesFetcher.FetchError sendability):
```swift
import Foundation

public enum DeepLinkError: Error, LocalizedError, Equatable, Sendable {
    /// URL не парсится как URLComponents.
    case malformedURL(URL)
    /// URL валидный но не несёт обязательный `url` query parameter.
    case missingURLParameter
    /// `url` parameter не URL по форме.
    case invalidSubscriptionURL(String)
    /// Router исчерпал все registered handlers — ни один не canHandle.
    case unhandled(url: URL)
    /// Stub handler (RemoteTokenFetchHandler) бросает в v0.9.
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .malformedURL: return "Невалидный URL ссылки."
        case .missingURLParameter: return "В ссылке отсутствует параметр url."
        case .invalidSubscriptionURL: return "Ссылка содержит невалидный subscription URL."
        case .unhandled: return "Этот тип deep-link ссылок пока не поддерживается."
        case .notImplemented: return "Эта функция станет доступна в следующей версии."
        }
    }
}
```

**Localization note:** строки выше — placeholder. Planner должен **либо** оставить inline (как ImporterError.noSupportedServers line 41) **либо** добавить в `Localization` пакет (`L10n.deepLinkErrorMalformed` и т.д.). Решение — на усмотрение per CONTEXT.md Claude's Discretion. Существующий `L10n.importErrorMalformed` (line 39) можно reuse для `.malformedURL`/`.invalidSubscriptionURL`.

---

### 8) `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinksLogger.swift` (logger wrapper)

**Analog:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift` (full file, 17 lines).

**Full pattern** (copy-paste + rename):
```swift
import Foundation
import OSLog

/// Subsystem-scoped Logger для DeepLinks модуля.
///
/// Three categories track three architectural layers:
///   * **router** — DeepLinkRouter actor: incoming URLs, dispatch outcomes.
///   * **importer** — ImportHandler: query parsing, forward to ConfigImporter.
///   * **token** — RemoteTokenFetchHandler stub (v1+).
///
/// Subsystem `app.bbtb.client` mirrors AppFeatures / RulesEngine conventions.
enum DeepLinksLogger {
    static let router = Logger(subsystem: "app.bbtb.client", category: "deep-links.router")
    static let importer = Logger(subsystem: "app.bbtb.client", category: "deep-links.importer")
    static let token = Logger(subsystem: "app.bbtb.client", category: "deep-links.token")
}
```

---

### 9) Tests: `DeepLinkRouterTests.swift`, `ImportHandlerTests.swift`, `URLParsingTests.swift`

**Analog:** `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift`

**XCTestCase setUp / tearDown pattern** (RulesEngineCoordinatorTests.swift:13-30):
```swift
import XCTest
@testable import DeepLinks

final class DeepLinkRouterTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
    }
    override func tearDown() async throws {
        try await super.tearDown()
    }
```

**Fake handler pattern** (analog к `FakeFetcher` mentioned in RulesEngineCoordinatorTests.swift:6) — XCTest конструирует stub-conforming-to-protocol:
```swift
struct FakeHandler: DeepLinkHandler {
    let matches: (URL) -> Bool
    let onHandle: @Sendable (URL) async throws -> Void
    func canHandle(_ url: URL) -> Bool { matches(url) }
    func handle(_ url: URL) async throws { try await onHandle(url) }
}
```

**Test method naming convention** (RulesEngineCoordinatorTests.swift:34, 65):
```swift
func test_handle_dispatchesToFirstMatchingHandler() async throws { … }
func test_handle_throwsUnhandledWhenNoHandlerMatches() async throws { … }
func test_handle_returnsImporterErrorTransparently() async throws { … }
```

**Required ImportHandler tests** (per RESEARCH.md acceptance criteria):
- `bbtb://import?url=https%3A%2F%2Fexample.com%2Fsub` → ConfigImporter получает auto-decoded `"https://example.com/sub"`.
- `https://import.bbtb.app/import?url=…` → same path.
- `bbtb://import` без `url=` → throws `.missingURLParameter`.
- `bbtb://connect` → `canHandle == false` (D-06 deferred).

---

### 10) `BBTB/App/iOSApp/BBTB_iOSApp.swift` (MODIFY)

**Analog:** **itself** — Phase 8 W4 RulesEngineCoordinator wiring уже служит каноничным образцом для Phase 9 wiring DeepLinkRouter.

**Import additions** (between line 16 `import RulesEngine` и line 17):
```swift
import DeepLinks  // Phase 9 W3 — DEEP-01/02/05
```

**Stored property pattern** (BBTB_iOSApp.swift:37 — rulesCoordinator declaration):
```swift
/// Phase 9 / W3 — DeepLink router (DEEP-05).
/// **D-09 cold-start defer:** init cheap, register-handler выполняется
/// до завершения init; routing запускается **только после**
/// `applyInitialStatusSnapshot` через `pendingURL` buffer (Pattern 4 в 09-RESEARCH).
private let deepLinkRouter: DeepLinkRouter
```

**Init-body construction pattern** (BBTB_iOSApp.swift:170-171 + handler register pattern — DOUBLE step):
```swift
// Phase 9 / W3 — DEEP-05 DeepLinkRouter (mirror Phase 8 rulesCoordinator init).
let deepLinkRouter = DeepLinkRouter()
self.deepLinkRouter = deepLinkRouter

// Register handlers — ordered (first matching wins).
// Phase 9: только ImportHandler. v1+: добавится RemoteTokenFetchHandler.
let importHandler = ImportHandler(importer: importer)
Task.detached(priority: .utility) { [deepLinkRouter] in
    await deepLinkRouter.register(importHandler)
}
```

> **NB для planner:** `importer` уже сконструирован в существующем code line 89-92. Использовать тот же объект (без второго ConfigImporter — он SwiftData-stateful).

**Late-binding via wireDeepLinkRouter (mirror wireRulesCoordinator line 102-103 + 272-273)** — добавить **новый метод** в MainScreenViewModel `public func wireDeepLinkRouter(_ router: DeepLinkRouter) async` + `.task` call в BBTBRootView body:

Pattern source (BBTB_iOSApp.swift:271-274):
```swift
.task {
    await settingsVM.wireRulesCoordinator(rulesCoordinator)
    await viewModel.wireRulesCoordinator(rulesCoordinator)
}
```

DeepLinks addition (Phase 9):
```swift
.task {
    await settingsVM.wireRulesCoordinator(rulesCoordinator)
    await viewModel.wireRulesCoordinator(rulesCoordinator)
    await viewModel.wireDeepLinkRouter(deepLinkRouter)  // Phase 9
}
```

**`.onOpenURL` + `.onContinueUserActivity` modifiers** — добавить **внутри** `body var Scene` (BBTB_iOSApp.swift:231-243). Pattern from RESEARCH.md § Pattern 1 + § Pattern 2:

```swift
var body: some Scene {
    WindowGroup {
        BBTBRootView(viewModel: viewModel, rulesCoordinator: rulesCoordinator)
            .onAppear {
                PerfSignposter.app.endInterval("ColdLaunch", coldLaunchState)
            }
            // Phase 9 / DEEP-01 — bbtb:// custom scheme (iOS + macOS).
            .onOpenURL { url in
                viewModel.handleDeepLink(url)
            }
            // Phase 9 / DEEP-02 — Universal Links HTTPS path (на iOS дублирует,
            // на macOS — ЕДИНСТВЕННЫЙ канал per RESEARCH § Pitfall).
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                viewModel.handleDeepLink(url)
            }
    }
    .modelContainer(modelContainer)
}
```

**Cold-start `pendingURL` (D-09)** — РЕКОМЕНДОВАННЫЙ design pattern: `viewModel.handleDeepLink(_:)` сам должен gate'ить по `initialManagersApplied` (MainScreenViewModel.swift:548-551). Внутри ViewModel хранится `private var pendingDeepLink: URL?` и `applyInitialStatusSnapshot` после `initialManagersApplied = true` flush'ит pending. Это упрощает modify в App.swift (один modifier — одна строка вызова). См. секцию 11 ниже.

---

### 11) `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (MODIFY)

**Analog:** **itself** — три существующих self-patterns:
1. `wireRulesCoordinator` late-binding (line 102-103: `public weak var rulesEngineCoordinator: RulesEngineCoordinator?`).
2. `applyInitialStatusSnapshot` cold-start gate (lines 547-551).
3. `performImport(_:raw:)` error handling (lines 672-696).

**Add stored properties** (после line 103 `public weak var rulesEngineCoordinator`):
```swift
/// Phase 9 / DEEP-05 — late-bound router (App.init wires через `wireDeepLinkRouter`).
public weak var deepLinkRouter: DeepLinkRouter?

/// Phase 9 / D-09 — cold-start pending URL. Если `.onOpenURL` fires до
/// `applyInitialStatusSnapshot`, URL буферизуется здесь; flush в snapshot
/// applier. Идемпотентно: nil после flush.
private var pendingDeepLink: URL?
```

**Add `wireDeepLinkRouter` method** (analog of `wireRulesCoordinator` — copy structure, no Notification observer needed):
```swift
public func wireDeepLinkRouter(_ router: DeepLinkRouter) async {
    deepLinkRouter = router
}
```

**Add `handleDeepLink(_:)` method** — combine MainScreenViewModel.performImport pattern (lines 672-696) + cold-start gate (lines 547-551):
```swift
/// Phase 9 / DEEP-01/02/05 — entrypoint from App.body `.onOpenURL` /
/// `.onContinueUserActivity`. Handles cold-start race per D-09: если VM
/// ещё не получил `applyInitialStatusSnapshot`, URL буферизуется в
/// `pendingDeepLink` и обрабатывается после flush.
public func handleDeepLink(_ url: URL) {
    guard initialManagersApplied else {
        pendingDeepLink = url
        return
    }
    Task { @MainActor in
        await performDeepLink(url)
    }
}

private func performDeepLink(_ url: URL) async {
    guard let router = deepLinkRouter else {
        lastError = "DeepLinkRouter not wired"
        return
    }
    importInProgress = true
    defer { importInProgress = false }
    lastError = nil
    do {
        try await router.handle(url)
        await refresh()
    } catch {
        lastError = error.localizedDescription
    }
}
```

**Modify `applyInitialStatusSnapshot` to flush pendingDeepLink** (MainScreenViewModel.swift:547-551):
```swift
public func applyInitialStatusSnapshot(_ snapshot: InitialStatusSnapshot) {
    guard !initialManagersApplied else { return }
    initialManagersApplied = true
    applyVPNStatus(snapshot.status, connectedDate: snapshot.connectedDate)
    // Phase 9 / D-09 — flush cold-start pending deep link AFTER VM ready.
    if let url = pendingDeepLink {
        pendingDeepLink = nil
        Task { @MainActor in
            await performDeepLink(url)
        }
    }
}
```

---

### 12) `BBTB/App/macOSApp/BBTB_macOSApp.swift` (MODIFY)

**Analog:** **iOS app** (BBTB_iOSApp.swift) + **itself** (Phase 8 W4 rulesCoordinator mirror lines 17, 34, 129-130, 167-194).

Все правила из секции 10 повторяются буква-в-букву с двумя поправками:

1. **`Window` вместо `WindowGroup`** (BBTB_macOSApp.swift:168-176) — modifier chain прикрепляется к `BBTBMacOSRootView`, не к `WindowGroup{}`. Pattern уже устоявшийся.

2. **`.onContinueUserActivity` КРИТИЧЕН на macOS** (RESEARCH.md § Pattern 2): `.onOpenURL` НЕ доставляет Universal Links на macOS. Без `.onContinueUserActivity` https://import.bbtb.app/import просто откроется в Safari вместо приложения.

```swift
Window(L10n.appShortName, id: "main") {
    BBTBMacOSRootView(viewModel: viewModel, rulesCoordinator: rulesCoordinator)
        .frame(minWidth: 380, minHeight: 520)
        .onAppear { PerfSignposter.appMac.endInterval("ColdLaunch", coldLaunchState) }
        // Phase 9 / DEEP-01
        .onOpenURL { url in
            viewModel.handleDeepLink(url)
        }
        // Phase 9 / DEEP-02 — REQUIRED for macOS (см. § Pattern 2 pitfall)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            viewModel.handleDeepLink(url)
        }
}
```

---

### 13) `BBTB/App/iOSApp/BBTB-iOS.entitlements` (MODIFY)

**Analog:** itself (existing keys 5-20).

**Insert before `</dict>` closing tag** (after line 20):
```xml
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:import.bbtb.app</string>
  </array>
```

**Production vs developer mode:** RESEARCH.md § Pattern 2 mentions `applinks:import.bbtb.app?mode=developer` для testing — НЕ включать в production entitlements. В Phase 9 production-only.

---

### 14) `BBTB/App/macOSApp/BBTB-macOS.entitlements` (MODIFY)

**Analog:** iOS entitlements file (same pattern).

**Insert before `</dict>` closing tag** (after line 28):
```xml
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:import.bbtb.app</string>
  </array>
```

> **NB:** macOS entitlements уже содержат `com.apple.security.app-sandbox = true` (line 17-18). Associated Domains совместим с sandbox — без дополнительных entitlement требований.

---

### 15) `BBTB/App/iOSApp/Info.plist` (MODIFY)

**Analog:** **itself** — Phase 8 W4 уже добавил `BGTaskSchedulerPermittedIdentifiers` (lines 62-74). DeepLinks следует тому же шаблону: insert before `</dict>`.

**Pattern source** (Info.plist:62-74 — Phase 8 W4):
```xml
<!-- Phase 8 / W4 — RULES-04 ... -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>app.bbtb.client.ios.rules-refresh</string>
</array>
```

**Insert after line 74** (before `</dict>`):
```xml
  <!-- Phase 9 / DEEP-01 — Custom URL scheme `bbtb://`.
       Доставка в SwiftUI `.onOpenURL` на iOS + macOS.
       CFBundleURLName — reverse-DNS уникальный идентификатор (apple convention). -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>app.bbtb.client.ios.url</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>bbtb</string>
      </array>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
    </dict>
  </array>
```

---

### 16) `BBTB/App/macOSApp/Info.plist` (MODIFY)

**Analog:** iOS Info.plist Phase 9 addition (mirror).

**Insert before `</dict>` (after line 33)**:
```xml
  <!-- Phase 9 / DEEP-01 — Custom URL scheme `bbtb://` (macOS counterpart). -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>app.bbtb.client.macos.url</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>bbtb</string>
      </array>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
    </dict>
  </array>
```

---

### 17) `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift` (MODIFY line 289-295)

**Analog:** **itself** — existing enum cases lines 290-294.

**Current state** (ParsedConfigs.swift:289-295):
```swift
public enum ImportSource: Sendable, Equatable {
    case pasteboard
    case subscriptionURL(URL)
    case jsonEndpoint(URL)
    case qrCode
    case multilineText
}
```

**After Phase 9** — добавить **новый case без payload** (deep link не несёт самостоятельных metadata — URL обрабатывается ImportHandler ДО вызова importFromRawInput; для attribution достаточно tag'а):
```swift
public enum ImportSource: Sendable, Equatable {
    case pasteboard
    case subscriptionURL(URL)
    case jsonEndpoint(URL)
    case qrCode
    case multilineText
    case deepLink  // Phase 9 / DEEP-01 — used by ImportHandler.handle
}
```

> **NB для planner:** свич'и над `ImportSource` могут существовать в codebase (search `case .pasteboard` / `switch source`). После добавления `.deepLink` все `switch` без `default:` дадут compile-time exhaustiveness error — это **желаемое поведение**, чтобы найти forgotten branches. Pattern verified в codebase: `MainScreenViewModel.performImport(_:raw:)` (line 678-682) уже использует `switch source { case .qrCode where raw != nil: ... default: ... }` — `default:` поглотит `.deepLink` без изменений.

---

### 18) `BBTB/Project.swift` (Tuist root — MODIFY)

**Analog:** **itself** — Phase 8 W1 RulesEngine addition pattern (lines 46, 95, 136).

**Three insertion points** (mirror Phase 8 RulesEngine):

**A) Local packages list** (Project.swift:35-53 — после line 46 RulesEngine):
```swift
    .package(path: .relativeToManifest("Packages/RulesEngine")),  // Phase 8 W1 — RULES-01/02
    .package(path: .relativeToManifest("Packages/DeepLinks")),    // Phase 9 W1 — DEEP-05
```

**B) iOS app target dependencies** (Project.swift:85-103 — после line 95):
```swift
                .package(product: "RulesEngine"),  // Phase 8 W1 — RULES-01/02
                .package(product: "DeepLinks"),    // Phase 9 W1 — DEEP-05
```

**C) macOS app target dependencies** (Project.swift:126-145 — после line 136):
```swift
                .package(product: "RulesEngine"),  // Phase 8 W1 — RULES-01/02
                .package(product: "DeepLinks"),    // Phase 9 W1 — DEEP-05
```

> **NB:** `tuist generate` после изменения Project.swift обязателен. Pattern из Phase 8 (commits 60b02ee / 4245980 timeline) — `tuist generate` всегда первый шаг после Project.swift modify.

---

## Shared Patterns

### Cold-start defer (DEC-06d-01)
**Source:** `BBTB_iOSApp.swift:209-213` (rulesCoordinator.bootstrap deferred) + `MainScreenViewModel.swift:547-551` (applyInitialStatusSnapshot gate).
**Apply to:** Все вызовы DeepLinkRouter.handle() в App layer **должны** проходить через `MainScreenViewModel.handleDeepLink(_:)` который сам gate'ит по `initialManagersApplied`.
**Why:** Холодный старт через deep link race'ит с TunnelController bootstrap → 1 XPC trip к NEVPN. Buffer URL до flush snapshot.

```swift
// In App.init — НЕ запускать router operations:
let deepLinkRouter = DeepLinkRouter()  // cheap init OK
// ❌ await deepLinkRouter.handle(url)  ← NEVER в App.init

// Defer registration to detached Task:
Task.detached(priority: .utility) { [deepLinkRouter] in
    await deepLinkRouter.register(importHandler)
}
```

### Two-phase init with late-binding weak reference
**Source:** `MainScreenViewModel.swift:102-103` (`public weak var rulesEngineCoordinator`) + feedback memory `feedback_failover_two_phase_init.md`.
**Apply to:** `MainScreenViewModel.deepLinkRouter` field declaration + `wireDeepLinkRouter` setter method.
**Why:** App owns lifecycle; VM-side weak reference избегает retain cycle.

```swift
public weak var deepLinkRouter: DeepLinkRouter?

public func wireDeepLinkRouter(_ router: DeepLinkRouter) async {
    deepLinkRouter = router
}
```

### Logging subsystem unification
**Source:** `RulesEngineLogger.swift` (RulesEngine) + `feedback_nevpn_xpc_mach_port.md` (`privacy: .public` для статусов, не для секретов).
**Apply to:** Все DeepLinks log calls.
**Rules:**
- subsystem = `"app.bbtb.client"` (mirror RulesEngine).
- category = `"deep-links.{router|importer|token}"` (3 categories per arch layer).
- URL strings → `privacy: .public` (Marzban subscription URL — sensitive token, но Logger логирует только для debug; production builds редактируют по privacy automatically).

### Error UX через existing `MainScreenViewModel.lastError` alert
**Source:** `MainScreenView.swift:72-76` (`.alert(L10n.alertImportFailed, isPresented: errorBinding)`) + `MainScreenView.swift:195-200` (`errorBinding`).
**Apply to:** ВСЕ DeepLink error paths.
**Why (per D-08):** не вводить новый alert-механизм. Уже работает русская локализация + кнопка OK + auto-dismiss.

```swift
// In MainScreenViewModel.performDeepLink:
catch {
    lastError = error.localizedDescription  // existing alert auto-triggers
}
```

### Tuist regeneration after Project.swift modify
**Source:** Phase 8 commit history (`tuist generate` обязателен после `Packages/RulesEngine` add).
**Apply to:** Project.swift modify (раздел 18 выше).
**Sequence:** save Project.swift → `tuist generate` from `BBTB/` → BBTB.xcodeproj обновлён → build.

### Test directory structure
**Source:** `BBTB/Packages/RulesEngine/Tests/RulesEngineTests/` (6 test files + Fixtures/).
**Apply to:** `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/`.
**Pattern:** `final class XxxTests: XCTestCase` + `setUp async throws` + `tearDown async throws` + `test_methodName_describesBehavior()` naming.

---

## No Analog Found

Все 16 файлов имеют либо exact либо role-match аналог в codebase. **Особых "первопроходцев"** в Phase 9 нет:

| File | Why no concerns | Pattern source |
|------|-----------------|----------------|
| AASA file (`/.well-known/apple-app-site-association`) | **Off-repo** — hosted on `import.bbtb.app`, не файл в репозитории. Содержимое экзектно описано в CONTEXT.md D-02. | (server admin, не code) |

Серверные изменения (AASA hosting на nginx/Cloudflare Pages) — **вне scope codebase** и не требуют PATTERNS.md мapping. Plan может описать как separate runbook task.

---

## Metadata

**Analog search scope:**
- `BBTB/Packages/RulesEngine/` (Phase 8 — primary template for new SwiftPM package)
- `BBTB/Packages/ProtocolRegistry/` (extensible registry pattern)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` (ViewModel + ConfigImporter integration)
- `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift` (ImportSource enum)
- `BBTB/App/iOSApp/` + `BBTB/App/macOSApp/` (App entry points + Info.plist + entitlements)
- `BBTB/Project.swift` (Tuist root)

**Files scanned:** ~25 files across 5 packages + 6 App-layer files.

**Strongest single pattern source:** `RulesEngine` Phase 8 — 5 NEW DeepLinks files are direct structural copies (Package.swift, DeepLinkRouter actor, DeepLinksLogger, DeepLinkError, tests).

**Pattern extraction date:** 2026-05-15
