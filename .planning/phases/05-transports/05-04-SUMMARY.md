---
phase: 05-transports
plan: 04
subsystem: transport-httpupgrade-vertical-slice
tags: [transport, httpupgrade, handler, transportregistry, configparser, tdd, wave3, pitfall-7]
dependency_graph:
  requires:
    - Phase 5 Wave 0 (05-01-SUMMARY.md) — `TransportConfig.httpUpgrade(path:host:)` case
      уже существует; `TransportRegistry` пакет; `TransportParamParser` уже понимает
      `type=httpupgrade` с обязательным `path` и опциональным `host`
    - Phase 5 Wave 1 (05-02-SUMMARY.md) — `ParsedVLESSTLS.transport: TransportConfig`,
      `ParsedTrojan.transport: TransportConfig`; парсеры делегируют в TransportParamParser
    - Phase 5 Wave 2 (05-03-SUMMARY.md) — установлен паттерн minimal handler +
      URI fixtures + integration parser tests (mirror structure)
  provides:
    - "TransportRegistry.HTTPUpgradeTransportHandler" — третий overlay handler, emits
      sing-box `{type, path[, host]}` блок (host — **STRING**, не array; Pitfall 7 invariant)
    - "Регрессионное покрытие: URI `vless://...?type=httpupgrade&path=/upgrade&host=h` →
      `.vlessTLS` с `.httpUpgrade(path: \"/upgrade\", host: \"h\")`"
    - "Регрессионное покрытие: URI `vless://...?type=httpupgrade` без `&path=` →
      `VLESSURIError.unsupportedTransport(\"httpupgrade\")` (UI feedback preserved)"
    - "Регрессионное покрытие: URI `trojan://...?type=httpupgrade&path=/upgrade&host=h` →
      `.httpUpgrade(path:host:)`"
    - "**Pitfall 7 invariant locked**: `test_buildTransportBlock_hostIsString_notArray`
      проверяет что `block[\"host\"] as? String != nil` И `as? [String] == nil`"
  affects:
    - Wave 4 (gRPC) — добавит `GRPCTransportHandler`. URI param `serviceName`
      camelCase → JSON `service_name` snake_case (Pitfall 6 — другая
      transformation, не путать с Pitfall 7).
    - Wave 5 (PoolBuilder coordinator + per-protocol buildOutbound) — будет
      использовать `HTTPUpgradeTransportHandler` через `TransportRegistry.shared
      .handler(for: "httpupgrade")?.buildTransportBlock(for: config)`. Caller
      protocol packages должны помнить: HTTPUpgrade host=String (не array),
      это противоположно HTTP transport. Doc-comment handler-а фиксирует
      invariant для будущих авторов.
    - Wave 6 (Transport Picker в ServerDetailView) — добавит `.httpUpgrade`
      опцию в Picker через `TransportConfig.displayName` ("HTTPUpgrade").
tech_stack:
  added:
    - "HTTPUpgradeTransportHandler в TransportRegistry/Handlers (Swift enum-namespace,
       идиоматично — третий handler по образцу TCPTransportHandler / WSTransportHandler /
       HTTPTransportHandler)"
  patterns:
    - "TDD plan-level RED→GREEN gate: один test-commit с failing tests
       (HTTPUpgradeTransportHandler symbol не существовал), один feat-commit
       с реализацией. Parser-integration тесты PASS уже на RED-этапе
       (TransportParamParser umеет httpupgrade с Wave 0)."
    - "Minimal handler shape (3-key full / 2-key empty-host) — caller protocol
       package решает host substitution в Wave 5 (если потребуется)"
    - "Pitfall 7 invariant зафиксирован двумя независимыми механизмами:
       (1) `test_buildTransportBlock_hostIsString_notArray` — runtime assertion;
       (2) doc-comment HTTPUpgradeTransportHandler.swift — для будущих авторов
       (таблица сравнения ws/http/httpupgrade host shapes)"
key_files:
  created:
    - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/HTTPUpgradeTransportHandler.swift
    - BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/HTTPUpgradeTransportHandlerTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-httpupgrade.txt
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-httpupgrade.txt
  modified:
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift
decisions:
  - "HTTPUpgradeTransportHandler emit'ит `host` как **STRING** (не array) — это
     Pitfall 7 invariant. sing-box HTTPUpgrade transport schema требует
     `host: string` в отличие от HTTP transport (Wave 2), где `host: []string`.
     Если emit'ить array — sing-box отвергнет outbound init с 'expected string
     for host'. Тест `test_buildTransportBlock_hostIsString_notArray` фиксирует
     invariant: одновременно `block[\"host\"] as? String != nil` И `as? [String] == nil`."
  - "Empty host (URI без `&host=` query-параметра — TransportParamParser fallback
     `host: \"\"`): ключ `host` ОПУЩЕН из выходного блока (не emit'ится с пустой
     строкой). sing-box подставит `tls.server_name` (SNI) как :authority
     HTTP/1.1 Upgrade-запроса — безопасный default для R1 invariant. Тест
     `test_buildTransportBlock_emptyHost_omitsHostKey` фиксирует invariant
     (block.count==2, keys.contains(\"host\")==false)."
  - "Нулевые модификации парсеров (TransportParamParser, VLESSURIParser,
     TrojanURIParser, UniversalImportParser) — Wave 0/1 уже полностью закрыли
     httpupgrade поддержку на уровне URI. Wave 3 — чисто аддитивный handler +
     integration тесты. Подтверждено: `git diff --name-only 853d5e4..HEAD --
     BBTB/Packages/ConfigParser/Sources/` — пусто."
  - "В тесте на missing-path для VLESS+TLS rawType сохраняется как 'httpupgrade'
     (q['type']?.lowercased() — 'httpupgrade'). VLESSURIParser catch-блок
     сворачивает TransportParamParser.ParserError.httpUpgradeMissingPath в
     VLESSURIError.unsupportedTransport(typeRaw='httpupgrade'). Это симметрично
     обработке http в Wave 2 — preserve URI raw type для UI feedback (D-10)."
  - "Trojan HTTPUpgrade-фикстура содержит `alpn=http%2F1.1` (URL-encoded
     `http/1.1`) — single-value CSV regression-coverage для Phase 2 Trojan
     parser (мирьерно с Wave 2 trojan-http.txt `alpn=h2`)."
  - "Identifier 'httpupgrade' — single token, lowercase, без дефисов и
     подчёркиваний; соответствует `TransportConfig.httpUpgrade.identifier`
     и `type=httpupgrade` в URI (Pitfall 6 mapping conv). Тест
     `test_identifier_isHttpupgrade` также проверяет НЕ-равенство 'http-upgrade'
     и 'httpUpgrade' (camelCase) для защиты от типичной ошибки автора."
metrics:
  duration_min: 4
  completed: 2026-05-12
---

# Phase 05 Plan 04: Wave 3 — HTTPUpgrade Vertical Slice Summary

**One-liner:** Чисто аддитивный handler `HTTPUpgradeTransportHandler` (sing-box
HTTPUpgrade transport блок — host как **STRING**, не array, что отличает его
от HTTP transport per Pitfall 7) + URI fixtures + 3 integration-теста парсеров,
охватывающие httpupgrade parse / missing-path / Trojan+HTTPUpgrade. Нулевые
модификации Wave 0/1/2 кода парсеров.

## Что сделано

Wave 3 фазы 05-transports — один TDD task с RED → GREEN коммитами.
Все артефакты — новые файлы, кроме двух test-файлов парсеров, в которые
добавлены integration-тесты (без изменения существующих).

### Минимальная shape HTTPUpgrade transport блока

```swift
// Случай 1: с host
HTTPUpgradeTransportHandler.buildTransportBlock(for: .httpUpgrade(path: "/upgrade", host: "h.example.com"))
// → ["type": "httpupgrade", "path": "/upgrade", "host": "h.example.com"]  ← host STRING

// Случай 2: без host (empty)
HTTPUpgradeTransportHandler.buildTransportBlock(for: .httpUpgrade(path: "/x", host: ""))
// → ["type": "httpupgrade", "path": "/x"]  ← host ключ ОПУЩЕН
```

**Ровно 2 ключа при empty host, ровно 3 ключа при non-empty host.** sing-box
подставляет `tls.server_name` (SNI) как :authority HTTP/1.1 Upgrade-запроса
когда `host` отсутствует — это R1-safe default.

### Pitfall 7 — HOST is STRING (не ARRAY!)

Sing-box HTTPUpgrade transport имеет уникальное поведение по сравнению с HTTP:

| transport    | sing-box `host` shape    | URI param | Wave |
| ------------ | ------------------------ | --------- | ---- |
| ws           | `headers.Host` (string)  | `?host=X` | 1    |
| http         | `host: [String]` (array) | `?host=X` | 2    |
| **httpupgrade** | **`host: String`** (string) | `?host=X` | **3 (this)** |

**Три разные schema** для трёх соседних транспортов одного семейства V2Ray.
Если emit'ить `[host]` (array) для HTTPUpgrade — sing-box отвергнет outbound
с "expected string for host". Тест
`test_buildTransportBlock_hostIsString_notArray` фиксирует invariant двумя
взаимодополняющими assertions:

```swift
XCTAssertNotNil(block["host"] as? String,   // MUST be String
                "Pitfall 7: HTTPUpgrade host MUST be String (sing-box schema)")
XCTAssertNil(block["host"] as? [String],     // MUST NOT be [String]
             "Pitfall 7: HTTPUpgrade host MUST NOT be [String] (отличается от HTTP transport)")
```

Doc-comment HTTPUpgradeTransportHandler.swift содержит сравнительную таблицу
для будущих авторов (предотвращение copy-paste ошибки из HTTPTransportHandler).

### URI парсинг: zero modifications

`TransportParamParser.parse` уже понимает:
- `type=httpupgrade` + `path` + `host` → `.httpUpgrade(path:host:)`
- `type=httpupgrade` + `path` (без host) → `.httpUpgrade(path: path, host: "")`
- `type=httpupgrade` без `path` → throws `.httpUpgradeMissingPath`

`VLESSURIParser` сворачивает `.httpUpgradeMissingPath` в
`VLESSURIError.unsupportedTransport("httpupgrade")` (catch-all в строке 148-153
VLESSURIParser.swift); `TrojanURIParser` пропускает `.httpUpgrade(path:host:)`
через `TransportParamParser` без модификации (host не пустой в фикстуре, SNI
fallback не активируется).

## Test counts per package

| Package / Test file | Tests | Result |
|---|---|---|
| `TransportRegistryTests/HTTPUpgradeTransportHandlerTests.swift` (NEW) | 8 | 8 PASS |
| `ConfigParserTests/VLESSURIParserTLSTests.swift` (+2 new) | 18 total | 18 PASS |
| `ConfigParserTests/TrojanURIParserTests.swift` (+1 new) | 16 total | 16 PASS |
| **TransportRegistry suite** | 32 (24 baseline + 8 new) | **32 PASS** |
| **ConfigParser suite** | 185 (182 baseline + 3 new) | **185 PASS** |
| **AppFeatures suite (regression check)** | 49 | **49 PASS** |

Plan §<verification> ожидал ≥ 31 TransportRegistry (8 above 23 Wave-2-baseline) и
≥ 161 ConfigParser (3 above 158 Wave-2-baseline) — фактические counts 32 и 185
выше ожиданий (плюс полные регрессии: Wave 2 + Phase 4 без изменений).

## Public API surface (signatures)

### `TransportRegistry.HTTPUpgradeTransportHandler`

```swift
public enum HTTPUpgradeTransportHandler: TransportHandler {
    public static let identifier = "httpupgrade"
    public static let displayName = "HTTPUpgrade"
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
    // ↑ .httpUpgrade(path, "")    → ["type": "httpupgrade", "path": path]               (2 keys)
    //   .httpUpgrade(path, host)  → ["type": "httpupgrade", "path": path, "host": host] (3 keys; host STRING)
    //   все остальные cases       → nil
}
```

### Pitfall 7 note (фиксация для Wave 5+)

```swift
// HTTPUpgradeTransportHandler.swift doc-comment:
// **Pitfall 7 invariant (HOST как STRING, не ARRAY)**: sing-box HTTPUpgrade
// transport принимает `host` как **string** — это отличается от HTTP transport
// (Wave 2), где `host` объявлено как `[]string` (массив для random-host
// selection). Три разные schema по семейству V2Ray-транспортов:
//
//   | transport    | host shape              | URI param |
//   | ------------ | ----------------------- | --------- |
//   | ws           | headers.Host (string)   | ?host=X   |
//   | http         | host: [String] (array)  | ?host=X   |
//   | httpupgrade  | host: String (string)   | ?host=X   |
```

## URI fixtures (новые)

### `vless-tls-httpupgrade.txt`
```
vless://550e8400-e29b-41d4-a716-446655440002@example.com:443?security=tls&encryption=none&type=httpupgrade&path=/upgrade&host=h.example.com&sni=example.com&fp=chrome#VLESS-TLS-HTTPUpgrade-Test
```

### `trojan-httpupgrade.txt`
```
trojan://trojan-test-password@example.com:443?security=tls&type=httpupgrade&path=/upgrade&host=h.example.com&sni=example.com&fp=chrome&alpn=http%2F1.1#Trojan-HTTPUpgrade-Test
```

Тестовые UUID/passwords; host `example.com` (generic). ALPN в Trojan-фикстуре
single-value `http/1.1` (URL-encoded как `http%2F1.1`) — также тестирует
percent-decoding для CSV-парсинга при одиночном значении (regression coverage
поверх Wave 2 trojan-http.txt где `alpn=h2`).

## Commits

| # | Hash | Type | Message |
|---|------|------|---------|
| 1 | `1c23333` | test | test(05-04): add failing HTTPUpgrade handler tests + URI fixtures |
| 2 | `e63a600` | feat | feat(05-04): implement HTTPUpgradeTransportHandler (host=String, Pitfall 7) |

**Plan-level TDD gate compliance:** RED commit (`1c23333`) явно предшествует
GREEN commit (`e63a600`). RED содержит failing HTTPUpgradeTransportHandlerTests
(`HTTPUpgradeTransportHandler` symbol не существовал — `cannot find
'HTTPUpgradeTransportHandler' in scope` compile error); parser-integration
тесты PASS уже на RED-этапе, потому что Wave 0 (TransportParamParser) +
Wave 1 (VLESSURIError.unsupportedTransport routing) полностью покрывают
URI-парсинг httpupgrade.

REFACTOR-фаза не понадобилась — handler написан минимально и идиоматично
по образцу WSTransportHandler / HTTPTransportHandler (которые уже прошли
review в Wave 1/2). Третий handler того же семейства — copy-paste с
изменением одной важной детали (host shape) корректно.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] libbox.xcframework symlink в worktree**

- **Found during:** baseline `swift test` в ConfigParser перед стартом TDD.
- **Issue:** `BBTB/Vendored/libbox.xcframework/` gitignored (см. `BBTB/.gitignore`);
  в свежесозданном worktree папка `Vendored/` присутствует но без бинарей.
  Это блокирует тест-зависимость `PacketTunnelKit` для `ConfigParser`
  (SPM error: `local binary target 'Libbox' does not contain a binary
  artifact`). Та же проблема, что в Wave 0/1/2/3 deviations.
- **Fix:** Создан symlink
  `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`.
  Идемпотентная операция; `BBTB/.gitignore` уже игнорирует pattern, symlink
  не появляется в `git status`.
- **Files modified:** none tracked (symlink остался untracked, gitignored).
- **Commit:** N/A.

### Превышение плана

Нет. Plan §2 требовал 8 тестов в HTTPUpgradeTransportHandlerTests —
реализовано ровно 8 (не дополнено как в Wave 2 9-м defensive test, потому
что 8-й тест `test_buildTransportBlock_wsHttpGrpcReturnNil` параметризованный
и уже покрывает все 3 non-httpUpgrade non-tcp case'а).

### Артефакты не в исходном плане

Нет. Все артефакты соответствуют плану §1 (action items 1-7).

## Acceptance criteria (Plan 05-04)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | File `HTTPUpgradeTransportHandler.swift` exists with `identifier = "httpupgrade"` (single token, no `-`, no `_`); `grep -c 'identifier = "httpupgrade"' …` == 1 | PASS (1) |
| 2 | `grep -c "case let .httpUpgrade(path, host)" …` == 1 | PASS (1) |
| 3 | `grep -c 'block\["host"\] = host' …` == 1 (string, not array literal) | PASS (1) |
| 4 | Fixture `vless-tls-httpupgrade.txt` exists + содержит `type=httpupgrade` | PASS |
| 5 | Fixture `trojan-httpupgrade.txt` exists + содержит `type=httpupgrade` | PASS |
| 6 | `swift test --filter HTTPUpgradeTransportHandlerTests` exits 0 with ≥ 8 tests; specifically `test_buildTransportBlock_hostIsString_notArray` PASSes | PASS (8 tests, including Pitfall 7 invariant) |
| 7 | `swift test --filter VLESSURIParserTLSTests` includes 2 new HTTPUpgrade tests, all PASS | PASS (18 total, +2 new) |
| 8 | `swift test --filter TrojanURIParserTests` includes 1 new test `test_trojan_httpUpgrade_uri_parses`, PASSes | PASS (16 total, +1 new) |
| 9 | Full ConfigParser suite ≥ 161 tests run, 0 failures | PASS (185, 0 failures) |
| 10 | TransportRegistry full suite ≥ 31 tests, 0 failures | PASS (32, 0 failures) |

## Success criteria (Plan 05-04)

- [x] `HTTPUpgradeTransportHandler.swift` created with host as String + omit-when-empty
- [x] `HTTPUpgradeTransportHandlerTests` — 8 tests PASS including Pitfall 7 invariant test
- [x] 2 URI fixtures (`vless-tls-httpupgrade.txt`, `trojan-httpupgrade.txt`) created
- [x] 3 new parser tests (2 VLESS+TLS+HTTPUpgrade + 1 Trojan+HTTPUpgrade) PASS
- [x] Wave 2 + Phase 4 tests still PASS (no regressions): TransportRegistry 32 (24 baseline + 8 new), ConfigParser 185 (182 baseline + 3 new), AppFeatures 49 (unchanged)
- [x] Zero changes to parsers — Wave 0/1 delegation already covers httpupgrade

## Known Stubs

Нет. `HTTPUpgradeTransportHandler` — полностью функциональная минимальная
реализация. Поле `host` намеренно опущено при empty (sing-box `tls.server_name`
fallback — задокументированное поведение sing-box, не stub). Multi-host
расширение не применимо к HTTPUpgrade (single Upgrade-request на конкретный
host; в отличие от HTTP transport который поддерживает random-host array).

## Threat Flags

Нет нового threat-surface. `HTTPUpgradeTransportHandler` — pure data type,
не выполняет сетевых операций. URI fixtures используют тестовые
UUID/passwords и generic `example.com` — не содержат реальных secrets.
ALPN `http/1.1` в trojan-фикстуре — стандартный HTTP/1.1 ALPN identifier
(требуется sing-box для HTTPUpgrade Upgrade-request).

## Self-Check: PASSED

### Created files exist

- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/HTTPUpgradeTransportHandler.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/HTTPUpgradeTransportHandlerTests.swift` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-httpupgrade.txt` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-httpupgrade.txt` — FOUND

### Modified files contain expected additions

- `VLESSURIParserTLSTests.swift` — +2 new tests (`test_vlessTLS_httpUpgrade_uri_parses`,
  `test_vlessTLS_httpUpgrade_missingPath_returnsUnsupported`) — FOUND
- `TrojanURIParserTests.swift` — +1 new test (`test_trojan_httpUpgrade_uri_parses`) — FOUND

### Commits exist

- `1c23333` (test RED — failing HTTPUpgrade handler tests + fixtures) — FOUND
- `e63a600` (feat GREEN — HTTPUpgradeTransportHandler implementation) — FOUND

## Next: Wave 4

Wave 4 (gRPC transport vertical slice):
- `GRPCTransportHandler` в `TransportRegistry/Handlers/` —
  `.grpc(serviceName:)` → `["type": "grpc", "service_name": serviceName]`.
  **Критично:** URI query-параметр `serviceName` (**camelCase** per V2Ray URI
  convention) → JSON ключ `service_name` (**snake_case** per sing-box schema).
  Это **Pitfall 6** (case-transformation), не путать с Pitfall 7
  (HTTP host array vs HTTPUpgrade host string — закрыт в Wave 3).
  Wave 4 plan должен явно проверить mapping через handler-test
  `block["service_name"] as? String == "TunService"` (с underscore).
- TransportParamParser уже умеет `?serviceName=X` (Wave 0); default
  `"TunService"` при отсутствии параметра — D-10 fallback.
- Test fixtures: `vless-tls-grpc.txt`, `trojan-grpc.txt`.
- Никаких изменений в data models (`TransportConfig.grpc` уже существует
  в VPNCore с Wave 0).
- Никаких изменений в парсерах (Wave 0/1 уже полностью покрыли grpc
  на уровне URI).
