---
phase: 05-transports
plan: 02
subsystem: transport-ws-vertical-slice
tags: [transport, websocket, parser, configparser, transportregistry, vpncore, tdd, wave1]
dependency_graph:
  requires:
    - Phase 5 Wave 0 (05-01-SUMMARY.md) — `TransportConfig` enum в VPNCore,
      `TransportRegistry` пакет, `TransportParamParser` utility
    - BBTB/Packages/ConfigParser — модели `ParsedVLESSTLS`, `ParsedTrojan`, парсеры
    - BBTB/Packages/AppFeatures — `ConfigImporter` (re-parse from Keychain)
  provides:
    - "ParsedVLESSTLS.transport: TransportConfig" (D-05 — заменяет `networkType: String`)
    - "ParsedTrojan.transport: TransportConfig" (D-06 — заменяет локальный `TransportType` enum)
    - "VLESSURIError.unsupportedTransport(String)" — типизированная transport-ошибка
    - "TransportRegistry.WSTransportHandler" — первый "настоящий" overlay handler
    - "UniversalImportParser маршрутизирует unknown VLESS+TLS transport в `.unsupported(.transportUnsupported)`"
  affects:
    - Wave 2 (HTTP/2 transport) — добавит `HTTPTransportHandler` по образцу WSTransportHandler
    - Wave 3 (gRPC) — добавит `GRPCTransportHandler`
    - Wave 4 (HTTPUpgrade) — добавит `HTTPUpgradeTransportHandler`
    - Wave 5 (PoolBuilder coordinator + per-protocol `buildOutbound`) — будет
      использовать `parsed.transport: TransportConfig` через `TransportRegistry`
tech_stack:
  added:
    - "WSTransportHandler в TransportRegistry/Handlers (Swift enum-namespace, идиоматично)"
  patterns:
    - "TDD plan-level RED→GREEN gate: один test-commit с failing тестами, один feat-commit с миграцией"
    - "case label preservation — `.ws(path:host:)` совпадает между удалённым ParsedTrojan.TransportType и новым TransportConfig, поэтому pattern matches `if case .ws(...)` в downstream-коде работают без изменений"
    - "Trojan reviewer-choice SNI fallback в URI парсере (Phase 2 backward-compat); VLESS+TLS — без fallback (Wave 5 buildOutbound решит substitution)"
    - "Typed error case `VLESSURIError.unsupportedTransport` + UniversalImportParser routing → `.unsupported(reason: .transportUnsupported)` — сохраняет URI для UI feedback"
    - "Backward-compat Keychain payload — ключи `networkType` / `transportType` / `wsPath` / `wsHost` СОХРАНЕНЫ для существующих installs; конвертация legacy строк → TransportConfig через TransportParamParser"
key_files:
  created:
    - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/WSTransportHandler.swift
    - BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/WSTransportHandlerTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-ws.txt
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-ws-vless-tls-ws-roundtrip.txt
  modified:
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/IsSupportedUpgradeTests.swift
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterAnyParsedConfigTests.swift
decisions:
  - "Trojan URI парсер ПРИМЕНЯЕТ SNI fallback при `?type=ws` без `&host=` (reviewer-choice §2 alternative). Причина: Phase 2 backward-compat invariant (фикстура trojan-ws-user-fixture полагается на host=sni); plan must_have #9 явно требует preserve существующее поведение."
  - "VLESS+TLS URI парсер НЕ применяет SNI fallback (рекомендация §2): empty host остаётся в `transport: .ws(path, \"\")` — substitution произойдёт в Wave 5 `VLESSTLS.buildOutbound`. WSTransportHandler уже опускает `headers` ключ при empty host (Example 4), поэтому отсутствие fallback в парсере безопасно."
  - "Новый `VLESSURIError.unsupportedTransport(String)` (а не `return .unsupported(...)` внутри парсера) — сигнатура `parse(_:) throws -> AnyParsedConfig` сохранена; UniversalImportParser ловит специфичный case и маршрутизирует в `.unsupported(reason: .transportUnsupported)`. Соответствует существующему паттерну (ShadowsocksURIError.unsupportedMethod → `.unsupported`)."
  - "Trojan URI: при неизвестном/полу-разобранном transport (например `?type=h2&path=...` или missing path) — `TrojanURIError.invalidTransport` (failed, не `.unsupported`). Сохраняет существующую strict семантику Phase 2."
  - "Wave 1 НЕ регистрирует WSTransportHandler в App startup и НЕ подключает TransportRegistry lookup в PoolBuilder. PoolBuilder.buildVLESSTLSOutbound теперь использует `network: \"tcp\"` хардкодом (transport overlay блок придёт в Wave 5)."
  - "ConfigImporter.buildKeychainPayload для vless-tls персистит `v.transport.identifier` (single-token string) под legacy ключом `networkType`. Это обеспечивает backward/forward-compat: old installs продолжат работать; new installs могут persist ws/grpc identifiers, которые будут корректно re-парситься через TransportParamParser."
metrics:
  duration_min: 11
  completed: 2026-05-12
---

# Phase 05 Plan 02: Wave 1 — WebSocket Vertical Slice Summary

**One-liner:** Миграция `ParsedVLESSTLS.networkType` / `ParsedTrojan.TransportType`
на shared `TransportConfig` enum + парсеры делегируют в `TransportParamParser` +
первый "настоящий" overlay handler `WSTransportHandler` производит sing-box
WebSocket transport блок.

## Что сделано

Wave 1 фазы 05-transports — один TDD task с RED → GREEN коммитами. Меняет
**публичный API** парсеров и моделей; backward-compat preservation для:
- Phase 2 Trojan fixture (`trojan-ws-user-fixture.txt`) — SNI fallback сохранён в `TrojanURIParser`
- Существующих Keychain записей — payload-ключи `networkType` / `transportType` / `wsPath` / `wsHost` сохранены

### Migration summary

**`ParsedVLESSTLS` (D-05):** `networkType: String` → `transport: TransportConfig`.
Init параметр и storage поле обновлены; consumers обновлены автоматически через
переименование case label `.tcp` (`String == "tcp"` → `TransportConfig.tcp`).

**`ParsedTrojan` (D-06):** локальный `enum TransportType: Sendable, Equatable { case tcp;
case ws(path:host:) }` УДАЛЁН целиком; поле `transport` теперь `TransportConfig` из
VPNCore. Pattern matches `if case let .ws(path, host) = parsed.transport` работают
без изменений (case labels совпадают).

**Парсер delegation (D-09):**
- `VLESSURIParser` TLS branch и `TrojanURIParser` теперь вызывают
  `TransportParamParser.parse(query:)` вместо собственного switch по `typeRaw`.
- `VLESSURIError.unsupportedTransport(String)` — новый typed error case для
  unknown VLESS+TLS transport (`type=quic` и т.д.).
- `UniversalImportParser` ловит `.unsupportedTransport` и маршрутизирует в
  `ImportedServer.unsupported(reason: .transportUnsupported)` с сохранением
  `rawURI` для UI feedback.

**`WSTransportHandler` (CORE-03 Wave 1):**
- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/WSTransportHandler.swift`.
- Идиоматичный `public enum WSTransportHandler: TransportHandler` namespace
  (по образцу `TCPTransportHandler`).
- `supportedProtocols = ["vless-tls", "trojan"]` — D-03 Reality намеренно исключён.
- `buildTransportBlock(for: .ws(path, host))`:
  - `host` непустой → `["type": "ws", "path": path, "headers": ["Host": host]]`
  - `host == ""` → `["type": "ws", "path": path]` (ключ `headers` ОПУЩЕН целиком)
  - Все non-ws cases → `nil` (defensive).

### Test counts per package

| Package / Test file | Tests | Result |
|---|---|---|
| `TransportRegistryTests/WSTransportHandlerTests.swift` | 6 new | 6 PASS |
| `ConfigParserTests/VLESSURIParserTLSTests.swift` | +4 new (3 happy + 1 unsupported integration); existing tests adapted | 12 total, 12 PASS |
| `ConfigParserTests/TrojanURIParserTests.swift` | +1 new (ws minimal); existing tests preserved | 14 total, 14 PASS |
| **TransportRegistry suite** | 15 (9 baseline + 6 new) | **15 PASS** |
| **ConfigParser suite** | 178 (173 baseline + 5 new) | **178 PASS** |
| **AppFeatures suite (regression check)** | 49 | **49 PASS** |

## Public API changes

### `ConfigParser.ParsedVLESSTLS`
```swift
public struct ParsedVLESSTLS: Sendable, Equatable {
    public let uuid: UUID
    public let host: String
    public let port: Int
    public let flow: String?
    public let sni: String
    public let fingerprint: String
    public let alpn: [String]
    public let transport: TransportConfig   // BEFORE: `networkType: String` (D-05)
    public let remarks: String?
    // init signature: ...alpn:transport:remarks:  (BEFORE: ...alpn:networkType:remarks:)
}
```

### `ConfigParser.ParsedTrojan`
```swift
public struct ParsedTrojan: Sendable, Equatable {
    // …existing fields…
    public let transport: TransportConfig   // BEFORE: `transport: TransportType` (D-06)
    // public enum TransportType { case tcp; case ws(...) }   ← REMOVED
}
```

### `ConfigParser.VLESSURIError`
```swift
public enum VLESSURIError: Error, LocalizedError, Equatable {
    // …existing cases…
    case unsupportedTransport(String)        // NEW (D-10 + Pitfall 10)
}
```

### `TransportRegistry.WSTransportHandler`
```swift
public enum WSTransportHandler: TransportHandler {
    public static let identifier = "ws"
    public static let displayName = "WebSocket"
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
}
```

## Commits

| # | Hash | Type | Message |
|---|------|------|---------|
| 1 | `29bf8ec` | test | test(05-02): add failing WS handler + VLESS+TLS/Trojan WS migration tests |
| 2 | `4dd5d29` | feat | feat(05-02): migrate ParsedVLESSTLS/ParsedTrojan to TransportConfig + WSTransportHandler |

Plan-level TDD gate compliance: RED commit (`29bf8ec`) явно предшествует
GREEN commit (`4dd5d29`).

## Deviations from Plan

### Reviewer choice — Trojan SNI fallback

Plan §2 предоставлял choice между:
- (A) keep SNI fallback в `TrojanURIParser` для `.ws(path, "")` (Phase 2
  backward-compat)
- (B) drop fallback (recommendation; Wave 5 buildOutbound подставит)

**Выбор: (A) для Trojan, (B) для VLESS+TLS.**

Обоснование:
- Trojan must_have #9 (фикстура `trojan-ws-user-fixture.txt` должна
  продолжать парситься "с правильным transport") + §6 "обновить только тип, не
  logic" — это сильнее, чем §2 рекомендация. Существующий test
  `test_realUserFixture_WSparsedCorrectly` ожидает `host == "vpn.vergevsky.ru"`
  (SNI), не `""`. Дроп fallback сломал бы инвариант.
- VLESS+TLS не имел существующих WS-фикстур, поэтому применяется чистая
  recommendation: `.ws(path, "")` сохраняется, substitution в Wave 5.

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] libbox.xcframework symlink в worktree**
- **Found during:** первая попытка `swift build` в ConfigParser.
- **Issue:** `Package.swift` ConfigParser ссылается на `PacketTunnelKit`, который
  использует `BBTB/Vendored/libbox.xcframework` (gitignored). В свежесозданном
  worktree фреймворка нет — build fails с "does not contain a binary artifact".
- **Fix:** Создан symlink `BBTB/Vendored/libbox.xcframework` на main repo'шный
  `libbox.xcframework`. Idempotent / неинтерактивная операция; `.gitignore`
  уже игнорирует символический линк (Wave 0 расширил pattern).
- **Files modified:** none tracked (symlink остался untracked, gitignored).
- **Commit:** N/A.

**2. [Rule 1 — Bug, тоже автоматический Rule 3 — Blocking] Multiple downstream
call-sites не были в файле списке Plan**

- **Found during:** RED→GREEN compile pass.
- **Issue:** Plan §4 указывал `ConfigImporter.swift` и `PoolBuilder.swift` как
  downstream callers. Реальный поиск через `grep -rn "ParsedVLESSTLS|ParsedTrojan|TransportType|networkType"`
  выявил ещё 4 файла:
  - `ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` (extractParsedTrojan)
  - `ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift` (mapTrojan + mapVLESS TLS branch)
  - `ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift` (helpers makeVLESSTLS / makeTrojan)
  - `AppFeatures/Tests/MainScreenFeatureTests/IsSupportedUpgradeTests.swift` и
    `ConfigImporterAnyParsedConfigTests.swift` (fixture helpers)
- **Fix:** Все sites обновлены по тому же паттерну (либо init параметр
  `networkType:` → `transport:`, либо переменная `let transport: ParsedTrojan.TransportType`
  → `let transport: TransportConfig`). Семантика сохранена.
- **Files modified:** все перечисленные выше.
- **Commit:** `4dd5d29` (часть единого GREEN коммита).

### Артефакты не в исходном плане

- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-ws-vless-tls-ws-roundtrip.txt`
  создан per Plan §6, но в Wave 1 ни один тест его не загружает (планируется как
  integration smoke в Wave 5). Это intended deferred-test fixture.

## Acceptance criteria (Plan 05-02)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `grep -c "let networkType: String" ImportedServer.swift` == 0 | PASS (0) |
| 2 | `grep -c "let transport: TransportConfig"` в ImportedServer.swift (≥ 1) | PASS (1) |
| 3 | `grep -c "public enum TransportType" TrojanURIParser.swift` == 0 | PASS (0) |
| 4 | `grep -c "TransportParamParser.parse"` в TrojanURIParser.swift (≥ 1) | PASS (1) |
| 5 | `grep -c "TransportParamParser.parse"` в VLESSURIParser.swift (≥ 1) | PASS (1) |
| 6 | WSTransportHandler.swift с `case let .ws(path, host)` + conditional headers | PASS |
| 7 | `vless-tls-ws.txt` exists + содержит `vless://` + `type=ws` | PASS |
| 8 | `swift test` в ConfigParser ≥ 154 tests, exit 0 | PASS (178) |
| 9 | `swift test --filter WSTransportHandlerTests` ≥ 6 tests | PASS (6) |
| 10 | `swift build` в AppFeatures exit 0 | PASS |
| 11 | Никаких регрессий — Phase 4 tests still PASS | PASS (test_realUserFixture_WSparsedCorrectly + все остальные prior tests зелёные) |

## Success criteria (Plan 05-02)

- [x] `ParsedVLESSTLS.networkType: String` removed; `transport: TransportConfig` added
- [x] `ParsedTrojan.TransportType` enum removed; `transport: TransportConfig` field updated
- [x] `VLESSURIParser` TLS branch + `TrojanURIParser` delegate to `TransportParamParser.parse(query:)`
- [x] `WSTransportHandler.swift` created with correct ws block JSON (headers omitted when host empty)
- [x] `WSTransportHandlerTests` — 6 tests PASS
- [x] New tests: `test_vlessTLS_ws_uri_parsesToWsTransport`, `test_vlessTLS_unknown_transport_*` (×2), `test_vlessTLS_tcp_default_when_type_absent` PASS
- [x] `trojan-ws-user-fixture.txt` still parses correctly (backward-compat invariant)
- [x] All Phase 4 ConfigParser tests still PASS (178 ≥ 151)
- [x] `AppFeatures` package builds (ConfigImporter call sites updated)
- [x] No new modifications to Keychain payload key names (`networkType`, `transportType`, `wsPath`, `wsHost`) — backward-compat preserved

## Known Stubs

Нет. Все артефакты Wave 1 — полностью функциональные минимальные реализации,
готовые к использованию в Wave 5 (когда WSTransportHandler будет
зарегистрирован в App startup и `PoolBuilder` начнёт строить outbound через
`TransportRegistry` lookup).

## Threat Flags

Нет нового threat-surface. `WSTransportHandler` — pure data type без сетевых
операций. Миграция типов в `Parsed*` структурах не вводит новых полей с
secrets / privileges (password / sni / fingerprint уже существовали и не
изменялись). UniversalImportParser routing нового VLESSURIError —
classification-only, не изменяет flow данных.

## Self-Check: PASSED

### Created files exist

- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/WSTransportHandler.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/WSTransportHandlerTests.swift` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-ws.txt` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-ws-vless-tls-ws-roundtrip.txt` — FOUND

### Modified files contain expected migration

- `ImportedServer.swift` — `import VPNCore` + `transport: TransportConfig` поле — FOUND
- `TrojanURIParser.swift` — `import VPNCore` + `TransportParamParser.parse` + удалённый `TransportType` enum — FOUND
- `VLESSURIParser.swift` — `TransportParamParser.parse` + `VLESSURIError.unsupportedTransport` — FOUND
- `UniversalImportParser.swift` — `catch VLESSURIError.unsupportedTransport` routing к `.unsupported(reason: .transportUnsupported)` — FOUND
- `ClashYAMLParser.swift` — `import VPNCore` + `transport: TransportConfig` в `mapTrojan` / `mapVLESS` — FOUND
- `PoolBuilder.swift` — `buildVLESSTLSOutbound` использует `network: "tcp"` хардкодом — FOUND
- `ConfigImporter.swift` — `TransportParamParser.parse` для legacy `networkType` payload — FOUND

### Commits exist

- `29bf8ec` (test RED) — FOUND
- `4dd5d29` (feat GREEN) — FOUND

## Next: Wave 2

Wave 2 (HTTP/2 transport vertical slice):
- `HTTPTransportHandler` в `TransportRegistry/Handlers/` — `.http(path:)` →
  `["type": "http", "path": path]` (см. Example 5 в 05-RESEARCH.md)
- URI парсеры (`VLESSURIParser`, `TrojanURIParser`): `?type=http&path=/api` →
  `.http(path: "/api")` (через тот же `TransportParamParser` — уже работает)
- Test fixtures: `vless-tls-http.txt` (single URI)
- Backward-compat: Trojan `?type=h2` всё ещё throws `TrojanURIError.invalidTransport("h2")`
  (Phase 2 strict-spec), но `?type=http` теперь успешно парсится → `.http(path:)`
  (плюс через `TransportParamParser` alias `h2 → http`, но в Trojan ветке этот
  alias bypass'нут через invalidTransport)
- Никаких изменений в data models (`TransportConfig.http` уже существует в
  VPNCore с Wave 0).
