---
phase: 05-transports
plan: 05
subsystem: transport-grpc-vertical-slice
tags: [transport, grpc, handler, transportregistry, configparser, tdd, wave4, pitfall-6]
dependency_graph:
  requires:
    - Phase 5 Wave 0 (05-01-SUMMARY.md) — `TransportConfig.grpc(serviceName:)`
      case уже существует; `TransportRegistry` пакет; `TransportParamParser`
      уже понимает `type=grpc` с `serviceName` query-param и default `"TunService"`
      (Open Question 5)
    - Phase 5 Wave 1 (05-02-SUMMARY.md) — `ParsedVLESSTLS.transport: TransportConfig`,
      `ParsedTrojan.transport: TransportConfig`; парсеры делегируют в TransportParamParser
    - Phase 5 Wave 2 (05-03-SUMMARY.md) — установлен паттерн minimal handler +
      URI fixtures + integration parser tests (mirror structure)
    - Phase 5 Wave 3 (05-04-SUMMARY.md) — 4-й handler того же семейства;
      теперь Wave 4 закрывает 5-й (gRPC) — последний overlay handler
  provides:
    - "TransportRegistry.GRPCTransportHandler" — пятый и финальный transport
      handler (TCP/WS/HTTP/HTTPUpgrade + gRPC complete). Emits sing-box
      `{type: \"grpc\", service_name: <value>}` блок ровно с 2 ключами
      (snake_case JSON key per sing-box schema)"
    - "Регрессионное покрытие: URI `vless://...?type=grpc&serviceName=tunsvc` →
      `.vlessTLS` с `.grpc(serviceName: \"tunsvc\")`"
    - "Регрессионное покрытие: URI `vless://...?type=grpc` (без serviceName) →
      `.grpc(serviceName: \"TunService\")` — default per Open Question 5"
    - "Регрессионное покрытие: URI `trojan://...?type=grpc&serviceName=tunsvc&alpn=h2` →
      `.grpc(serviceName: \"tunsvc\")` с `alpn == [\"h2\"]`"
    - "**Pitfall 6 invariant locked**: `test_buildTransportBlock_jsonKeyIsSnakeCase_notCamelCase`
      проверяет ОДНОВРЕМЕННО `block[\"service_name\"] != nil` И `block[\"serviceName\"] == nil`
      — case-transformation invariant URI camelCase → JSON snake_case"
  affects:
    - Wave 5 (PoolBuilder coordinator + per-protocol buildOutbound) — будет
      использовать `GRPCTransportHandler` через
      `TransportRegistry.shared.handler(for: \"grpc\")?.buildTransportBlock(for: config)`.
      Caller protocol packages должны помнить: gRPC over HTTP/2 *требует* h2
      ALPN — НЕ применять Pitfall 1 strip h2 (которое относится только к
      WS transport). Doc-comment handler-а фиксирует invariant.
    - Wave 6 (Transport Picker в ServerDetailView) — добавит `.grpc` опцию
      в Picker через `TransportConfig.displayName` (\"gRPC\").
    - Phase 6+ (любой будущий transport handler) — наследует pattern
      Wave 1-4: minimal handler + 9 unit tests + URI fixture + parser-integration
      test. Pitfall 6 case-transformation документирован как образцовый
      случай (compare с Pitfall 7 host-as-string из Wave 3).
tech_stack:
  added:
    - "GRPCTransportHandler в TransportRegistry/Handlers (Swift enum-namespace,
       идиоматично — пятый и финальный handler по образцу TCPTransportHandler /
       WSTransportHandler / HTTPTransportHandler / HTTPUpgradeTransportHandler)"
  patterns:
    - "TDD plan-level RED→GREEN gate: один test-commit с failing tests
       (GRPCTransportHandler symbol не существовал — `cannot find
       'GRPCTransportHandler' in scope`), один feat-commit с реализацией.
       Parser-integration тесты PASS уже на RED-этапе (TransportParamParser
       умеет grpc с Wave 0 + default `TunService`)."
    - "Minimal handler shape (2 keys всегда): emit'ит `service_name` независимо
       от пустоты значения — отличается от WS/HTTPUpgrade (где empty host
       опускается). Handler прозрачно передаёт associated value наружу;
       sing-box validator решает на этапе outbound init."
    - "Pitfall 6 invariant зафиксирован двумя независимыми механизмами:
       (1) `test_buildTransportBlock_jsonKeyIsSnakeCase_notCamelCase` —
       runtime double-assert (snake_case present + camelCase absent);
       (2) doc-comment GRPCTransportHandler.swift — для будущих авторов
       (таблица сравнения URI / JSON / Swift namespace'ов)"
key_files:
  created:
    - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/GRPCTransportHandler.swift
    - BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/GRPCTransportHandlerTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-grpc.txt
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-grpc.txt
  modified:
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift
decisions:
  - "GRPCTransportHandler emit'ит JSON ключ как **`service_name`** (snake_case)
     — это **Pitfall 6** invariant. sing-box JSON schema strict-by-default;
     если emit'ить `serviceName` (camelCase) — sing-box отвергнет outbound
     с 'unknown field serviceName'. URI query-параметр — `serviceName`
     (camelCase, V2Ray standard). Swift label `.grpc(serviceName:)` —
     camelCase (matches URI). Три namespace'а, два разных написания.
     Тест `test_buildTransportBlock_jsonKeyIsSnakeCase_notCamelCase`
     фиксирует invariant: одновременно `block[\"service_name\"] != nil` И
     `block[\"serviceName\"] == nil`."
  - "Empty serviceName: ключ `service_name` ВСЁ РАВНО emit'ится (с пустой
     строкой) — НЕ опускается. Это отличается от поведения host в
     WS/HTTPUpgrade handlers (где empty → omit). Handler прозрачно передаёт
     associated value наружу. sing-box validator решает на этапе outbound
     init: если сервер настроен на default service — пустота ok; иначе
     error. Тест `test_buildTransportBlock_emptyServiceName_stillEmitted`
     фиксирует invariant (block.count==2, keys.contains(\"service_name\")==true)."
  - "Нулевые модификации парсеров (TransportParamParser, VLESSURIParser,
     TrojanURIParser, UniversalImportParser) — Wave 0 уже полностью закрыл
     grpc URI parsing включая default `serviceName=\"TunService\"` (case
     'grpc' в TransportParamParser.parse: `query[\"serviceName\"] ?? \"TunService\"`).
     Wave 4 — чисто аддитивный handler + integration тесты. Подтверждено:
     `git diff --name-only 646afe5..HEAD -- BBTB/Packages/ConfigParser/Sources/`
     — пусто."
  - "Trojan-gRPC фикстура содержит `alpn=h2` (HTTP/2 — gRPC over HTTP/2
     обязателен). **Важно для Wave 5**: НЕ применять Pitfall 1 strip h2
     для gRPC transport — это правило относится только к WS transport
     (Phase 2 fix). Wave 5 integration должен verify что buildOutbound НЕ
     strip-нет h2 для gRPC."
  - "Identifier 'grpc' — single token lowercase, без дефисов; соответствует
     `TransportConfig.grpc.identifier` и `type=grpc` в URI. Тест
     `test_identifier_isGrpc` также проверяет НЕ-равенство 'GRPC' (uppercase)
     и 'g-rpc' (dashed) — защита от типичной ошибки автора."
  - "displayName = \"gRPC\" (lowercase `g`, uppercase `RPC`) — стандартное
     обозначение в документации gRPC и в UI Transport Picker (Wave 6).
     Тест `test_displayName_isGRPCLiteral` использует case-sensitive
     `XCTAssertEqual` для фиксации точного string literal."
  - "REFACTOR-фаза не понадобилась — handler написан минимально и идиоматично
     по образцу WSTransportHandler / HTTPTransportHandler /
     HTTPUpgradeTransportHandler (которые уже прошли review в Wave 1-3).
     Пятый handler того же семейства — copy-paste с изменением двух
     важных деталей (snake_case JSON key + empty-value emission policy)
     корректно."
metrics:
  duration_min: 5
  completed: 2026-05-12
---

# Phase 05 Plan 05: Wave 4 — gRPC Vertical Slice Summary

**One-liner:** Чисто аддитивный handler `GRPCTransportHandler` (sing-box gRPC
transport блок — JSON ключ **`service_name`** snake_case, что отличается от
URI query-param **`serviceName`** camelCase per Pitfall 6) + URI fixtures +
3 integration-теста парсеров (grpc parse / default serviceName / Trojan+gRPC).
Нулевые модификации Wave 0/1/2/3 кода парсеров.

## Что сделано

Wave 4 фазы 05-transports — один TDD task с RED → GREEN коммитами.
Все артефакты — новые файлы, кроме двух test-файлов парсеров, в которые
добавлены integration-тесты (без изменения существующих).

### Минимальная shape gRPC transport блока

```swift
// Случай 1: c serviceName
GRPCTransportHandler.buildTransportBlock(for: .grpc(serviceName: "tunsvc"))
// → ["type": "grpc", "service_name": "tunsvc"]   ← snake_case JSON key

// Случай 2: c пустой serviceName
GRPCTransportHandler.buildTransportBlock(for: .grpc(serviceName: ""))
// → ["type": "grpc", "service_name": ""]   ← всё равно emit'ится, sing-box валидатор решает
```

**Ровно 2 ключа в обоих случаях.** В отличие от WS/HTTPUpgrade (где empty
host → omit), gRPC всегда emit'ит `service_name` — это прозрачная передача
associated value наружу. sing-box на этапе outbound init подставит default
service-name если сервер так настроен (Open Question 5).

### Pitfall 6 — JSON ключ snake_case `service_name`, URI param camelCase `serviceName`

Это **самая частая ошибка** при добавлении gRPC transport: путаница между
тремя namespace'ами.

| layer              | key            | example                | case      |
| ------------------ | -------------- | ---------------------- | --------- |
| URI query (V2Ray)  | `serviceName`  | `?serviceName=tunsvc`  | camelCase |
| sing-box JSON      | `service_name` | `"service_name":"X"`   | snake_case |
| Swift label        | `serviceName`  | `.grpc(serviceName:)`  | camelCase (matches URI) |

Если emit'ить `"serviceName"` (camelCase) в JSON — sing-box JSON decoder
strict-by-default отвергнет outbound с "unknown field serviceName".
Тест `test_buildTransportBlock_jsonKeyIsSnakeCase_notCamelCase` фиксирует
invariant двумя взаимодополняющими assertions:

```swift
XCTAssertNotNil(block["service_name"],    // MUST be snake_case
                "Pitfall 6: gRPC JSON ключ MUST be 'service_name' (snake_case, sing-box schema)")
XCTAssertNil(block["serviceName"],        // MUST NOT be camelCase
             "Pitfall 6: gRPC JSON ключ MUST NOT be 'serviceName' (camelCase URI param не должен протекать в JSON)")
```

Doc-comment GRPCTransportHandler.swift содержит сравнительную таблицу
для будущих авторов (предотвращение copy-paste ошибки).

### URI парсинг: zero modifications

`TransportParamParser.parse` уже понимает (Wave 0 функционал):
- `type=grpc&serviceName=tunsvc` → `.grpc(serviceName: "tunsvc")`
- `type=grpc` (без serviceName) → `.grpc(serviceName: "TunService")` — default
  (Open Question 5: sing-box-совместимое имя для default tunnel-сервиса)
- `type=grpc&serviceName=` (пустое значение) → `.grpc(serviceName: "")` —
  пустота допустима, sing-box валидатор решает

`VLESSURIParser` и `TrojanURIParser` пропускают `.grpc(serviceName:)` через
`TransportParamParser` без модификации (host fallback не активируется
— gRPC не имеет host-параметра, в отличие от WS/HTTPUpgrade).

## Test counts per package

| Package / Test file | Tests | Result |
|---|---|---|
| `TransportRegistryTests/GRPCTransportHandlerTests.swift` (NEW) | 9 | 9 PASS |
| `ConfigParserTests/VLESSURIParserTLSTests.swift` (+2 new) | 20 total | 20 PASS |
| `ConfigParserTests/TrojanURIParserTests.swift` (+1 new) | 17 total | 17 PASS |
| **TransportRegistry suite** | 41 (32 baseline + 9 new) | **41 PASS** |
| **ConfigParser suite** | 188 (185 baseline + 3 new) | **188 PASS** |

Plan §<verification> ожидал ≥ 40 TransportRegistry (9 above 31 Wave-3-baseline)
и ≥ 164 ConfigParser (3 above 161 Wave-3-baseline) — фактические counts 41
и 188 выше ожиданий (плюс полные регрессии: Wave 3 + Phase 4 без изменений).

## Public API surface (signatures)

### `TransportRegistry.GRPCTransportHandler`

```swift
public enum GRPCTransportHandler: TransportHandler {
    public static let identifier = "grpc"
    public static let displayName = "gRPC"
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
    // ↑ .grpc(serviceName) → ["type": "grpc", "service_name": serviceName]  (2 keys always)
    //   все остальные cases → nil
}
```

### Pitfall 6 note (фиксация для Wave 5+)

```swift
// GRPCTransportHandler.swift doc-comment:
// **Pitfall 6 invariant (CASE TRANSFORMATION URI → JSON)**: gRPC имеет
// два разных namespace'а для одного семантического поля:
//
//   | layer              | key            | example           |
//   | ------------------ | -------------- | ----------------- |
//   | URI query (V2Ray)  | `serviceName`  | `?serviceName=X`  | camelCase
//   | sing-box JSON      | `service_name` | `"service_name":"X"` | snake_case
//   | Swift label        | `serviceName`  | `.grpc(serviceName:)` | camelCase
```

## URI fixtures (новые)

### `vless-tls-grpc.txt`
```
vless://550e8400-e29b-41d4-a716-446655440003@example.com:443?security=tls&encryption=none&type=grpc&serviceName=tunsvc&sni=example.com&fp=chrome#VLESS-TLS-gRPC-Test
```

### `trojan-grpc.txt`
```
trojan://trojan-test-password@example.com:443?security=tls&type=grpc&serviceName=tunsvc&sni=example.com&fp=chrome&alpn=h2#Trojan-gRPC-Test
```

Тестовые UUID/passwords; host `example.com` (generic). ALPN в Trojan-фикстуре
`h2` — обязательно для gRPC over HTTP/2 (НЕ применять Pitfall 1 strip h2
для gRPC transport, это правило только для WS).

## Все 5 transport handlers готовы

После Wave 4 завершён полный набор overlay handlers для phase 5:

| # | Handler | identifier | sing-box `type` | URI `type=` | Wave | Special |
|---|---------|------------|------------------|--------------|------|---------|
| 1 | TCPTransportHandler | "tcp" | (omit transport block) | tcp/raw/absent | Wave 0 | Pitfall 2: no-op |
| 2 | WSTransportHandler | "ws" | ws | ws | Wave 1 | Pitfall 1: strip h2 ALPN |
| 3 | HTTPTransportHandler | "http" | http | http/h2 | Wave 2 | host = [String] array |
| 4 | HTTPUpgradeTransportHandler | "httpupgrade" | httpupgrade | httpupgrade | Wave 3 | Pitfall 7: host = String |
| 5 | **GRPCTransportHandler** | **"grpc"** | **grpc** | **grpc** | **Wave 4 (this)** | **Pitfall 6: service_name snake_case** |

Можно начинать Wave 5 — Integration (PoolBuilder coordinator + per-protocol
`buildOutbound` + App startup registration всех 5 handlers).

## Commits

| # | Hash | Type | Message |
|---|------|------|---------|
| 1 | `646afe5` | test | test(05-05): add failing GRPCTransportHandler tests + URI fixtures |
| 2 | `a3c01c0` | feat | feat(05-05): implement GRPCTransportHandler (service_name snake_case, Pitfall 6) |

**Plan-level TDD gate compliance:** RED commit (`646afe5`) явно предшествует
GREEN commit (`a3c01c0`). RED содержит failing GRPCTransportHandlerTests
(`GRPCTransportHandler` symbol не существовал — `cannot find
'GRPCTransportHandler' in scope` compile error); parser-integration
тесты PASS уже на RED-этапе, потому что Wave 0 (TransportParamParser
case "grpc") полностью покрывает URI-парсинг grpc включая default
`serviceName="TunService"`.

REFACTOR-фаза не понадобилась — handler написан минимально и идиоматично
по образцу WSTransportHandler / HTTPTransportHandler /
HTTPUpgradeTransportHandler. Пятый handler того же семейства —
copy-paste с изменением двух важных деталей корректно:
1. JSON ключ `service_name` (snake_case, Pitfall 6) вместо `path`/`host`.
2. Empty-value policy: emit always (не omit), в отличие от
   WS/HTTPUpgrade host empty → omit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] libbox.xcframework symlink в worktree**

- **Found during:** baseline `swift test` в TransportRegistry перед стартом TDD.
- **Issue:** `BBTB/Vendored/libbox.xcframework/` gitignored (см. `BBTB/.gitignore`
  строки 23/26/27); в свежесозданном worktree папка `Vendored/` присутствует
  но без бинарей. Это блокирует тест-зависимость `PacketTunnelKit` для
  `ConfigParser` (SPM error: `local binary target 'Libbox' does not contain
  a binary artifact`). Та же проблема, что в Wave 0-3 deviations.
- **Fix:** Создан symlink
  `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`.
  Идемпотентная операция; `BBTB/.gitignore` уже игнорирует pattern, symlink
  не появляется в `git status`.
- **Files modified:** none tracked (symlink остался untracked, gitignored).
- **Commit:** N/A.

### Превышение плана

Нет. Plan §2 требовал 9 тестов в GRPCTransportHandlerTests — реализовано
ровно 9 (identity 3 + happy-path 2 [`full` + `jsonKeyIsSnakeCase`] +
empty-value 1 + defensive nil 3 [`tcp`, `ws`, параметризованный для
`http`+`httpUpgrade`]).

### Артефакты не в исходном плане

Нет. Все артефакты соответствуют плану §1 (action items 1-7).

## Acceptance criteria (Plan 05-05)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | File `GRPCTransportHandler.swift` exists with `identifier = "grpc"` and `"service_name": serviceName` exactly (no camelCase leak) | PASS |
| 2 | `grep -c "service_name" GRPCTransportHandler.swift` ≥ 1 | PASS (6) |
| 3 | `grep -c "serviceName" GRPCTransportHandler.swift` ≥ 1 (Swift identifier from associated value) | PASS (13) |
| 4 | JSON output literal `"service_name":` в source ≥ 1 | PASS (3) |
| 5 | JSON output literal `"serviceName":` в source == 0 (no camelCase leak) | PASS (0) |
| 6 | `grep -c "case let .grpc(serviceName)" GRPCTransportHandler.swift` == 1 | PASS (1) |
| 7 | Fixtures `vless-tls-grpc.txt` + `trojan-grpc.txt` exist with `type=grpc&serviceName=tunsvc` | PASS |
| 8 | `swift test --filter GRPCTransportHandlerTests` exits 0 with ≥ 9 tests; специально `test_buildTransportBlock_jsonKeyIsSnakeCase_notCamelCase` PASSes | PASS (9 tests, Pitfall 6 invariant locked) |
| 9 | `swift test --filter VLESSURIParserTLSTests` includes 2 new gRPC tests, all PASS | PASS (20 total, +2 new) |
| 10 | `swift test --filter TrojanURIParserTests` includes 1 new test `test_trojan_grpc_uri_parses`, PASSes | PASS (17 total, +1 new) |
| 11 | Full ConfigParser suite ≥ 164 tests run, 0 failures | PASS (188, 0 failures) |
| 12 | TransportRegistry full suite ≥ 40 tests, 0 failures | PASS (41, 0 failures) |

## Success criteria (Plan 05-05)

- [x] `GRPCTransportHandler.swift` created with `service_name` snake_case JSON key
- [x] `GRPCTransportHandlerTests` — 9 tests PASS including Pitfall 6 invariant test
- [x] 2 URI fixtures (`vless-tls-grpc.txt`, `trojan-grpc.txt`) created with `type=grpc&serviceName=tunsvc`
- [x] 3 new parser tests (2 VLESS+TLS+gRPC + 1 Trojan+gRPC) PASS
- [x] All 4 non-TCP transport handlers (WS, HTTP, HTTPUpgrade, gRPC) complete with tests + 5-й TCP handler
- [x] Wave 0-3 + Phase 4 tests still PASS (no regressions): TransportRegistry 41 (32 baseline + 9 new), ConfigParser 188 (185 baseline + 3 new)
- [x] Zero changes to parsers — Wave 0 delegation already covers grpc + TunService default

## Known Stubs

Нет. `GRPCTransportHandler` — полностью функциональная минимальная
реализация. Поле `service_name` всегда emit'ится (с empty string когда
applicable) — это намеренное прозрачное поведение, sing-box validator
решает на этапе outbound init. Multi-mode (gun/multi/guna) и authority
параметры — out of scope Phase 5 per CONTEXT.md «Не в скоупе»; sing-box
применяет default mode (gun) автоматически.

## Threat Flags

Нет нового threat-surface. `GRPCTransportHandler` — pure data type,
не выполняет сетевых операций. URI fixtures используют тестовые
UUID/passwords и generic `example.com` — не содержат реальных secrets.
ALPN `h2` в trojan-фикстуре — стандартный HTTP/2 ALPN identifier
(обязательно для gRPC over HTTP/2 per RFC 7540).

R1 invariant сохранён: gRPC over TLS — TLS strict (sing-box использует
`tls.server_name` как :authority HTTP/2-запросов, как для HTTP/HTTPUpgrade).
Никаких новых auth paths, file access patterns или schema changes
в trust boundaries не вводится.

## Self-Check: PASSED

### Created files exist

- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/GRPCTransportHandler.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/GRPCTransportHandlerTests.swift` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-grpc.txt` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-grpc.txt` — FOUND

### Modified files contain expected additions

- `VLESSURIParserTLSTests.swift` — +2 new tests (`test_vlessTLS_grpc_uri_parses`,
  `test_vlessTLS_grpc_defaultServiceName`) — FOUND
- `TrojanURIParserTests.swift` — +1 new test (`test_trojan_grpc_uri_parses`) — FOUND

### Commits exist

- `646afe5` (test RED — failing GRPCTransportHandler tests + fixtures) — FOUND
- `a3c01c0` (feat GREEN — GRPCTransportHandler implementation) — FOUND

## Next: Wave 5

Wave 5 (Integration — PoolBuilder coordinator + per-protocol buildOutbound):
- Каждый protocol package (VLESSReality, VLESSTLS, Trojan, Shadowsocks, Hysteria2)
  получает public static `buildOutbound(from:transport:tag:) -> [String: Any]`
  (D-14). Метод использует `TransportRegistry.shared.handler(for:
  config.identifier)?.buildTransportBlock(for: config)` для overlay транспортов.
- `PoolBuilder.buildSingBoxJSON` превращается в тонкого координатора (D-15):
  switch по `AnyParsedConfig` → вызов `ProtocolPackage.buildOutbound(...)` →
  сборка массива → urltest (если > 1) / direct / dns / route.
- App startup регистрирует все 5 transport handlers в `TransportRegistry.shared`
  (TCP, WS, HTTP, HTTPUpgrade, gRPC) — точка по образцу `ProtocolRegistry`
  registration в Phase 1/2.
- `ConfigImporter` применяет `transportOverride` (D-19) ДО `PoolBuilder` —
  если пользователь выбрал транспорт в `ServerDetailView` (Wave 6), он
  переопределяет URI-default.
- **Pitfall 1 reminder для Wave 5**: при сборке Trojan/VLESS+TLS outbound с
  WS transport — strip h2 из ALPN (h2 несовместимо с WS). НО для gRPC —
  ОБРАТНОЕ: h2 ALPN ОБЯЗАТЕЛЬНО (gRPC over HTTP/2). HTTP/HTTPUpgrade —
  H2/HTTP1.1 соответственно. Это transport-specific логика caller-а,
  не handler-а.
