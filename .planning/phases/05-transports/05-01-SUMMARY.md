---
phase: 05-transports
plan: 01
subsystem: transport-foundation
tags: [foundation, transport, registry, parser, vpncore, configparser, tdd]
dependency_graph:
  requires:
    - phase 04 (VPNCore, ConfigParser, ProtocolRegistry готовы как образцы и зависимости)
    - BBTB/Packages/VPNCore — TransportConfig.swift живёт здесь
    - BBTB/Packages/ProtocolRegistry — структурный образец для TransportRegistry
  provides:
    - VPNCore.TransportConfig — shared enum для всех protocol packages (Wave 1-5)
    - TransportRegistry (новый SwiftPM target) — реестр + protocol для transport handlers
    - TransportRegistry.TCPTransportHandler — no-overlay handler (Pitfall 2)
    - ConfigParser.TransportParamParser — общая утилита для URI query-парсинга
  affects:
    - Wave 1 (WebSocket vertical slice) — будет регистрировать WSTransportHandler
      и переводит ParsedVLESSTLS.networkType / ParsedTrojan.TransportType на TransportConfig
    - Wave 2-4 (gRPC, HTTP, HTTPUpgrade) — будут регистрировать свои handlers
    - Wave 5 (App registration + per-protocol buildOutbound) — заменит switch в PoolBuilder
      на TransportRegistry lookup
tech_stack:
  added:
    - TransportRegistry (новый локальный SwiftPM пакет, swift-tools 6.0, iOS18+/macOS15+)
  patterns:
    - synthesized Codable conformance для enum с associated values (SE-0295)
    - enum-namespace как идиоматичный Swift способ объявить static-only contract
    - NSLock-protected singleton dict (byte-for-byte копия ProtocolRegistry)
    - case-insensitive type dispatch с aliases (raw→tcp, h2→http) — Pitfall 10
key_files:
  created:
    - BBTB/Packages/VPNCore/Sources/VPNCore/TransportConfig.swift
    - BBTB/Packages/VPNCore/Tests/VPNCoreTests/TransportConfigTests.swift
    - BBTB/Packages/TransportRegistry/Package.swift
    - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/TransportHandler.swift
    - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/TransportRegistry.swift
    - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/TCPTransportHandler.swift
    - BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/TransportRegistryTests.swift
    - BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/TCPTransportHandlerTests.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/TransportParamParser.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TransportParamParserTests.swift
  modified:
    - BBTB/.gitignore  # ignore libbox symlink (без слэша) + per-package Package.resolved
decisions:
  - "TransportConfig живёт в VPNCore (не в TransportRegistry) — protocol packages импортируют только VPNCore, нет циклической зависимости (D-04, подтверждено в Plan 05-01)."
  - "TCPTransportHandler.supportedProtocols включает все 5 текущих протоколов — TCP применим ко всем (semantic 'no transport overlay', Pitfall 2)."
  - "buildTransportBlock для TCP возвращает nil — sing-box trim'ит pure-nil-overlay в JSON (Pitfall 2 invariant)."
  - "Synthesized Codable conformance для enum-with-associated-values (SE-0295) — отказ от custom CodingKeys снижает риск рассинхрона при SwiftData миграциях."
  - "Test isolation для TransportRegistry singleton: используем `.contains('tcp')` вместо равенства массиву, чтобы не добавлять test-only API в production singleton."
  - "type='raw' и type='h2' (aliases в URI v2rayNG/v2ray-core) дешифруются на уровне TransportParamParser в .tcp и .http соответственно — Pitfall 10."
  - "VLESSURIParser/TrojanURIParser НЕ модифицируются в этой задаче — их делегирование на TransportParamParser происходит в Wave 1 после миграции ParsedVLESSTLS/ParsedTrojan на TransportConfig."
  - "TCPTransportHandler не регистрируется в App-startup в Wave 0 — registration wiring переезжает в Wave 5 совместно с регистрацией остальных handler-ов."
metrics:
  duration_min: 8
  completed: 2026-05-12
---

# Phase 05 Plan 01: Transport Foundation Summary

**One-liner:** Заложен shared `TransportConfig` enum + новый пакет `TransportRegistry`
(singleton + protocol + TCPTransportHandler) + `TransportParamParser` в ConfigParser
как чисто аддитивный фундамент Phase 5; нулевые модификации Phase 4 кода.

## Что сделано

Wave 0 фазы 05-transports — три параллельных TDD-задачи, каждая с RED → GREEN
коммитами. Все артефакты — новые файлы; ни одна строка Phase 4 не изменена в
исходниках (модифицирован только `BBTB/.gitignore` — build-time gitignore-чистка).

### Task 1: TransportConfig enum в VPNCore
- `public enum TransportConfig: Sendable, Equatable, Codable, Hashable` с 5 cases:
  `.tcp`, `.ws(path:host:)`, `.grpc(serviceName:)`, `.http(path:)`,
  `.httpUpgrade(path:host:)`.
- `identifier` → lowercase single-token строки `"tcp"`, `"ws"`, `"grpc"`, `"http"`,
  `"httpupgrade"` (sing-box JSON `type` поле + URI `?type=` query param).
- `displayName` → UI-строки `"TCP"`, `"WebSocket"`, `"gRPC"`, `"HTTP/2"`, `"HTTPUpgrade"`.
- Synthesized Codable conformance (SE-0295) — никаких custom CodingKeys.

### Task 2: TransportRegistry package skeleton + TCPTransportHandler
- Новый SwiftPM пакет `BBTB/Packages/TransportRegistry/` (swift-tools 6.0,
  iOS18+/macOS15+, deps: `../VPNCore`).
- `public protocol TransportHandler: Sendable` с 4 static members
  (`identifier`, `displayName`, `supportedProtocols`, `buildTransportBlock(for:)`).
- `public final class TransportRegistry: @unchecked Sendable` — NSLock-protected
  `[String: any TransportHandler.Type]`, структурная копия `ProtocolRegistry`.
- `public enum TCPTransportHandler: TransportHandler` — enum-namespace, identifier
  `"tcp"`, supportedProtocols = все 5 текущих протоколов, `buildTransportBlock`
  возвращает `nil` для всех 5 cases (Pitfall 2: sing-box не имеет transport `tcp`,
  отсутствие поля = TCP).

### Task 3: TransportParamParser в ConfigParser
- `public enum TransportParamParser` с nested `ParserError: Error, LocalizedError, Equatable`
  (4 cases: `wsMissingPath`, `httpMissingPath`, `httpUpgradeMissingPath`,
  `unsupportedType(String)`).
- `public static func parse(query: [String: String]) throws -> TransportConfig`
  с case-insensitive dispatch: tcp/raw/empty → `.tcp`, ws (path required),
  grpc (default `"TunService"`), http/h2 (path required), httpupgrade
  (path required); неизвестные типы → `.unsupportedType(typeRaw)`. Неизвестные
  query-params тихо игнорируются.

## Test counts per package

| Test file | Tests | Result |
|----|----|----|
| `VPNCoreTests/TransportConfigTests.swift` | 6 | 6 PASS |
| `TransportRegistryTests/TransportRegistryTests.swift` | 5 | 5 PASS |
| `TransportRegistryTests/TCPTransportHandlerTests.swift` | 4 | 4 PASS |
| `ConfigParserTests/TransportParamParserTests.swift` | 22 | 22 PASS |
| **Итого новых** | **37** | **37 PASS** |

Регрессия:
- `swift test` для `VPNCore` — 38 tests, 0 failures (1 pre-existing skipped).
- `swift test` для `ConfigParser` — 173 tests, 0 failures (151 pre-existing + 22 новых).
- `swift test` для `TransportRegistry` — 9 tests, 0 failures.

## Public API surface (signatures)

### `VPNCore.TransportConfig`
```swift
public enum TransportConfig: Sendable, Equatable, Codable, Hashable {
    case tcp
    case ws(path: String, host: String)
    case grpc(serviceName: String)
    case http(path: String)
    case httpUpgrade(path: String, host: String)

    public var identifier: String   // "tcp" | "ws" | "grpc" | "http" | "httpupgrade"
    public var displayName: String  // "TCP" | "WebSocket" | "gRPC" | "HTTP/2" | "HTTPUpgrade"
}
```

### `TransportRegistry.TransportHandler`
```swift
public protocol TransportHandler: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    static var supportedProtocols: [String] { get }
    static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
}
```

### `TransportRegistry.TransportRegistry`
```swift
public final class TransportRegistry: @unchecked Sendable {
    public static let shared: TransportRegistry
    public func register<H: TransportHandler>(_ handlerType: H.Type)
    public func handler(for identifier: String) -> (any TransportHandler.Type)?
    public var registeredIdentifiers: [String] { get }  // sorted
}
```

### `TransportRegistry.TCPTransportHandler`
```swift
public enum TCPTransportHandler: TransportHandler {
    public static let identifier = "tcp"
    public static let displayName = "TCP"
    public static let supportedProtocols: [String] =
        ["vless-tls", "trojan", "vless-reality", "shadowsocks", "hysteria2"]
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
        // Always returns nil (Pitfall 2)
}
```

### `ConfigParser.TransportParamParser`
```swift
public enum TransportParamParser {
    public enum ParserError: Error, LocalizedError, Equatable {
        case wsMissingPath
        case httpMissingPath
        case httpUpgradeMissingPath
        case unsupportedType(String)
        public var errorDescription: String? { get }
    }
    public static func parse(query: [String: String]) throws -> TransportConfig
}
```

## Pre-Phase-5 files: zero modifications

Подтверждено `git diff cf766c65 HEAD --stat` (база — head main): затронуты только
новые файлы плюс `BBTB/.gitignore`. Никаких изменений в `VLESSURIParser.swift`,
`TrojanURIParser.swift`, `ImportedServer.swift`, `PoolBuilder.swift`, или любом
другом существующем источнике Phase 1-4.

## Commits

| # | Hash | Type | Message |
|---|------|------|---------|
| 1 | `eb36f74` | test | test(05-01): add failing tests for TransportConfig enum |
| 2 | `37ade76` | feat | feat(05-01): add shared TransportConfig enum in VPNCore |
| 3 | `9b5d3e2` | test | test(05-01): add TransportRegistry package skeleton + failing tests |
| 4 | `78b3d0c` | feat | feat(05-01): implement TransportRegistry singleton + TCPTransportHandler |
| 5 | `04d6229` | test | test(05-01): add failing tests for TransportParamParser |
| 6 | `1a0e536` | feat | feat(05-01): implement TransportParamParser in ConfigParser |
| 7 | `da2ac7b` | chore | chore(05-01): ignore build-time artifacts (libbox symlink + per-package Package.resolved) |

Каждая Task следует RED → GREEN sequence (Plan-level TDD gate compliance — все три
feat-коммиты явно следуют за test-коммитом для того же артефакта).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Symlink vendored libbox.xcframework для swift test**
- **Найдено при:** Task 3 (RED run для TransportParamParserTests)
- **Issue:** `ConfigParser/Package.swift` объявляет `.package(path: "../PacketTunnelKit")`
  как тест-зависимость. PacketTunnelKit, в свою очередь, ссылается на
  `BBTB/Vendored/libbox.xcframework`, который gitignored (`Vendored/libbox.xcframework/`
  в `BBTB/.gitignore`). В свежесозданном worktree фреймворка нет (только в main
  репозитории), что блокирует `swift test` для ConfigParser.
- **Fix:** Создан symlink `BBTB/Vendored/libbox.xcframework` →
  `/Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`, плюс
  расширен `BBTB/.gitignore` (добавлен паттерн без trailing slash, чтобы symlink
  тоже игнорировался). Никаких изменений в Package.swift и в production коде.
- **Files modified:** symlink в `BBTB/Vendored/libbox.xcframework` (untracked,
  gitignored); `BBTB/.gitignore` (+8 строк).
- **Commit:** `da2ac7b`

### Артефакты не в исходном плане

Помимо одного chore-коммита выше, выполнение строго следует плану: 6 новых
исходных файлов + 4 новых test-файла + добавочные RED test-файлы созданы согласно
TDD-протоколу плана.

## Acceptance criteria (Plan 05-01)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | TransportConfig.swift создан с 5 cases + Codable + Sendable + Equatable + Hashable + identifier + displayName | PASS |
| 2 | TransportConfigTests — 5 тестов PASS | PASS (6 тестов, equatable разнесён на 2 метода) |
| 3 | TransportRegistry package directory создан с Package.swift + 3 source + 2 test файлами | PASS |
| 4 | `swift build` в TransportRegistry succeeds | PASS (0.34s, no warnings) |
| 5 | `swift test` в TransportRegistry — ≥ 9 PASS | PASS (9/9) |
| 6 | TransportParamParser.swift создан в ConfigParser с parse(query:) (5 transports + 2 aliases + 3 unsupported throws) | PASS |
| 7 | TransportParamParserTests — ≥ 21 PASS | PASS (22/22) |
| 8 | Существующие Phase 4 тесты ConfigParser + VPNCore зелёные | PASS (173 + 38, нулевые регрессии) |
| 9 | Нулевые модификации источников вне 6 новых файлов | PASS (только `BBTB/.gitignore` modified) |

## Known Stubs

Нет. Все артефакты Wave 0 — полностью функциональные минимальные реализации,
готовые к использованию волнами 1-5. Никаких placeholder-значений, hardcoded mock
data или "TODO" в коде.

## Threat Flags

Нет нового threat-surface. `TransportConfig` — pure data type без сетевых операций.
`TransportParamParser` принимает уже распарсенные `[String: String]`, не выполняет
сетевых запросов, не загружает файлы. `TransportRegistry` — in-process singleton.
TCPTransportHandler не строит сетевых соединений (только метаданные).

## Self-Check: PASSED

### Created files exist
- `BBTB/Packages/VPNCore/Sources/VPNCore/TransportConfig.swift` — FOUND
- `BBTB/Packages/VPNCore/Tests/VPNCoreTests/TransportConfigTests.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Package.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/TransportHandler.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/TransportRegistry.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/TCPTransportHandler.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/TransportRegistryTests.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/TCPTransportHandlerTests.swift` — FOUND
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/TransportParamParser.swift` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TransportParamParserTests.swift` — FOUND

### Commits exist
- `eb36f74` (test TransportConfig RED) — FOUND
- `37ade76` (feat TransportConfig GREEN) — FOUND
- `9b5d3e2` (test TransportRegistry RED) — FOUND
- `78b3d0c` (feat TransportRegistry GREEN) — FOUND
- `04d6229` (test TransportParamParser RED) — FOUND
- `1a0e536` (feat TransportParamParser GREEN) — FOUND
- `da2ac7b` (chore .gitignore) — FOUND

## Next: Wave 1

Wave 1 (WebSocket vertical slice):
- `ParsedVLESSTLS.networkType: String` → `transport: TransportConfig`
- `ParsedTrojan.TransportType` (локальный enum) удалить, заменить на `TransportConfig`
- Делегировать `VLESSURIParser.parseTLS` и `TrojanURIParser` на `TransportParamParser`
- `WSTransportHandler` в `TransportRegistry/Handlers/`
- `VLESSTLS.buildOutbound(...)` и `Trojan.buildOutbound(...)` per-protocol с WS-блоком
- Full WS happy-path integration test (фикстура trojan-ws-user-fixture)
