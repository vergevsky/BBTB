---
phase: 05-transports
plan: 03
subsystem: transport-http-vertical-slice
tags: [transport, http, http2, handler, transportregistry, configparser, tdd, wave2]
dependency_graph:
  requires:
    - Phase 5 Wave 0 (05-01-SUMMARY.md) — `TransportConfig.http(path:)` case,
      `TransportRegistry` пакет, `TransportParamParser` уже понимает http/h2
    - Phase 5 Wave 1 (05-02-SUMMARY.md) — `ParsedVLESSTLS.transport: TransportConfig`,
      `ParsedTrojan.transport: TransportConfig`, парсеры делегируют в TransportParamParser,
      VLESSURIError.unsupportedTransport уже существует
  provides:
    - "TransportRegistry.HTTPTransportHandler" — второй overlay handler, emits
      минимальный sing-box `{type, path}` блок (host ОПУЩЕН — Pitfall 7 invariant)
    - "Регрессионное покрытие: URI `vless://...?type=http&path=/api` → `.vlessTLS` с `.http(path:)`"
    - "Регрессионное покрытие: URI `vless://...?type=h2&path=/api` → `.http(path:)` (Pitfall 10 alias)"
    - "Регрессионное покрытие: URI `vless://...?type=http` без `&path=` → `.unsupportedTransport`"
    - "Регрессионное покрытие: URI `trojan://...?type=http&path=/api` → `.http(path:)`"
  affects:
    - Wave 3 (HTTPUpgrade) — добавит `HTTPUpgradeTransportHandler`; критично:
      HTTPUpgrade host — **string** (не array), в отличие от HTTP. Wave 3 plan
      должен явно проверить opposite shape.
    - Wave 4 (gRPC) — добавит `GRPCTransportHandler`.
    - Wave 5 (PoolBuilder coordinator + per-protocol buildOutbound) — будет
      использовать `HTTPTransportHandler` через `TransportRegistry` lookup
      по identifier "http". Если когда-нибудь protocol package решит emit'ить
      host explicit — он обязан использовать `[String]` array (Pitfall 7),
      не string; comment в HTTPTransportHandler.swift это документирует.
tech_stack:
  added:
    - "HTTPTransportHandler в TransportRegistry/Handlers (Swift enum-namespace, идиоматично)"
  patterns:
    - "TDD plan-level RED→GREEN gate: один test-commit с failing tests (handler не существует),
       один feat-commit с реализацией"
    - "Минимальный JSON-блок: handler emit'ит ровно {type, path}; host решение
       делегировано caller-у protocol package (Wave 5)"
    - "Pitfall 7 invariant зафиксирован в doc-comment handler-а (host — array,
       не string), даже когда сам ключ не emit'ится сейчас — для будущих авторов"
key_files:
  created:
    - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/HTTPTransportHandler.swift
    - BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/HTTPTransportHandlerTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-http.txt
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-http.txt
  modified:
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift
decisions:
  - "HTTPTransportHandler emit'ит ровно 2 ключа: type='http' и path. Поле host
     намеренно опущено — sing-box использует tls.server_name (SNI) как
     :authority HTTP/2-запросов когда host отсутствует. Это безопасный default
     для R1 invariant (всегда SNI = honest server name)."
  - "Pitfall 7 (HOST is ARRAY, not STRING) — зафиксирован в doc-comment с явным
     указанием: если когда-нибудь TransportConfig.http расширится hosts: [String]
     ассоциированным значением, handler обязан emit'ить блок как [String], не
     string. Это критичный invariant для будущих изменений."
  - "Нулевые модификации парсеров (TransportParamParser, VLESSURIParser,
     TrojanURIParser, UniversalImportParser) — Wave 0 и Wave 1 уже полностью
     закрыли http/h2 поддержку на уровне URI. Wave 2 — чисто аддитивный
     handler + integration тесты."
  - "В Trojan branch httpMissingPath сворачивается в TrojanURIError.invalidTransport
     (Phase 2 strict семантика). VLESS+TLS branch сворачивает httpMissingPath в
     VLESSURIError.unsupportedTransport (D-10 — preserve URI для UI feedback).
     Эта asymmetry унаследована из Wave 1 и не модифицируется в Wave 2."
  - "В тесте на missing-path для VLESS+TLS rawType сохраняется как 'http'
     (q['type']?.lowercased() — actually 'http'), не как 'http-missing-path' —
     соответствует существующему VLESSURIParser.swift fallback в catch."
  - "h2 alias тестируется на inline URI (не fixture), потому что h2 — это не
     transport-тип в нашей TransportConfig, а alias-наклейка на уровне
     TransportParamParser; фикстуры показывают целевой стандарт type=http."
  - "Trojan HTTP-фикстура содержит alpn=h2 (single-value CSV) — это тестирует
     ALPN-парсинг при одиночном значении (regression-coverage для Phase 2 Trojan parser)."
metrics:
  duration_min: 6
  completed: 2026-05-12
---

# Phase 05 Plan 03: Wave 2 — HTTP/2 Vertical Slice Summary

**One-liner:** Чисто аддитивный handler `HTTPTransportHandler` (sing-box
HTTP transport блок с минимальной `{type, path}` shape — host опущен,
делегирован sing-box `tls.server_name` fallback per Pitfall 7) + URI fixtures
+ 4 integration-теста парсеров, охватывающие http parse / h2 alias /
missing-path / Trojan+HTTP. Нулевые модификации Wave 0/1 кода парсеров.

## Что сделано

Wave 2 фазы 05-transports — один TDD task с RED → GREEN коммитами.
Все артефакты — новые файлы, кроме двух test-файлов парсеров, в которые
добавлены integration-тесты (без изменения существующих).

### Минимальная shape HTTP transport блока

```swift
HTTPTransportHandler.buildTransportBlock(for: .http(path: "/api"))
// → ["type": "http", "path": "/api"]
```

**Ровно 2 ключа.** Host намеренно опущен — sing-box использует
`tls.server_name` (SNI) как `:authority` HTTP/2-запросов. Это упрощает
handler, сохраняет R1 invariant и оставляет multi-host расширение
backlog-ом (Phase 7+, при необходимости расширим `TransportConfig.http`
ассоциированным значением `hosts: [String]`).

### Pitfall 7 — HOST is ARRAY (зафиксировано в doc-comment)

Sing-box HTTP transport имеет уникальное поведение: поле `host`
объявлено как `[]string` (массив для random-selection по серверам).
Если в WS/HTTPUpgrade host передаётся как **строка**, то в HTTP — это
**массив строк**. В Wave 2 этот ключ не emit'ится, но doc-comment
HTTPTransportHandler.swift явно фиксирует invariant для будущих
авторов (и для Wave 3 — где будет противоположная shape для HTTPUpgrade).

### URI парсинг: zero modifications

`TransportParamParser.parse` уже понимает:
- `type=http` + `path` → `.http(path:)`
- `type=h2` + `path` → `.http(path:)` (alias, Pitfall 10)
- `type=http` без `path` → throws `.httpMissingPath`

`VLESSURIParser` (Wave 1) уже сворачивает все TransportParamParser
ошибки в `VLESSURIError.unsupportedTransport(typeRaw)`, а
`UniversalImportParser` маршрутизирует это в
`.unsupported(reason: .transportUnsupported)`. `TrojanURIParser` для
HTTP с валидным `path` пропускает через `TransportParamParser`
без модификации (HTTP transport не имеет SNI-fallback по host —
ключ host отсутствует в `.http(path:)` enum case).

## Test counts per package

| Package / Test file | Tests | Result |
|---|---|---|
| `TransportRegistryTests/HTTPTransportHandlerTests.swift` (NEW) | 9 | 9 PASS |
| `ConfigParserTests/VLESSURIParserTLSTests.swift` (+3 new) | 16 total | 16 PASS |
| `ConfigParserTests/TrojanURIParserTests.swift` (+1 new) | 15 total | 15 PASS |
| **TransportRegistry suite** | 24 (15 baseline + 9 new) | **24 PASS** |
| **ConfigParser suite** | 182 (178 baseline + 4 new) | **182 PASS** |
| **AppFeatures suite (regression check)** | 49 | **49 PASS** |

**Note про test count:** Plan §2 указывал 8 тестов для HTTPTransportHandlerTests.
Фактически — 9: 8 указанных в плане + дополнительный
`test_buildTransportBlock_httpUpgradeReturnsNil` для полного defensive coverage
(HTTPUpgrade — соседний non-http case, который имеет смысл явно покрыть, чтобы
случайная путаница `.http` / `.httpUpgrade` не прошла незамеченной — обе цели
эволюционируют независимо в Wave 3). Это превышает план, не нарушая его.

## Public API surface (signatures)

### `TransportRegistry.HTTPTransportHandler`

```swift
public enum HTTPTransportHandler: TransportHandler {
    public static let identifier = "http"
    public static let displayName = "HTTP/2"
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
    // ↑ .http(path) → ["type": "http", "path": path]
    //   все остальные cases → nil
}
```

### Pitfall 7 note для будущих авторов (Wave 5+)

```swift
// HTTPTransportHandler.swift doc-comment:
// **Pitfall 7 (HOST как ARRAY, не STRING)**: sing-box HTTP transport
// принимает `host` как `[]string` (массив строк для random-host selection).
// **В Wave 2 этот ключ НЕ emit'ится**: sing-box использует `tls.server_name`
// (SNI) в качестве `:authority` HTTP/2-запросов когда поле `host` отсутствует.
//
// **Внимание (для Wave 5 protocol packages)**: если конкретный protocol
// package решит подставить host explicit-ом, ОН должен emit'ить массив
// `[String]`, а не строку — в противном случае sing-box отвергнет outbound
// JSON. Эта ответственность лежит на каллере, не на handler-е.
```

## URI fixtures (новые)

### `vless-tls-http.txt`
```
vless://550e8400-e29b-41d4-a716-446655440001@example.com:443?security=tls&encryption=none&type=http&path=/api&sni=example.com&fp=chrome#VLESS-TLS-HTTP-Test
```

### `trojan-http.txt`
```
trojan://trojan-test-password@example.com:443?security=tls&type=http&path=/api&sni=example.com&fp=chrome&alpn=h2#Trojan-HTTP-Test
```

Тестовые UUID/passwords; host `example.com` (generic). ALPN в Trojan-фикстуре
single-value `h2` — также тестирует CSV-парсинг при одиночном значении.

## Commits

| # | Hash | Type | Message |
|---|------|------|---------|
| 1 | `603fcb3` | test | test(05-03): add failing HTTP handler tests + HTTP URI fixtures |
| 2 | `628283f` | feat | feat(05-03): implement HTTPTransportHandler with minimal {type, path} block |

**Plan-level TDD gate compliance:** RED commit (`603fcb3`) явно предшествует
GREEN commit (`628283f`). RED содержит failing HTTPTransportHandlerTests
(handler symbol не существовал — compile fail); parser-integration tests
проходили уже на RED-этапе, потому что Wave 0 (TransportParamParser) +
Wave 1 (VLESSURIError.unsupportedTransport routing) полностью покрывают
URI-парсинг http/h2.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] libbox.xcframework symlink в worktree**

- **Found during:** первая попытка `swift test` в ConfigParser.
- **Issue:** `BBTB/Vendored/libbox.xcframework/` gitignored; в свежесозданном
  worktree фреймворка нет, что блокирует тест-зависимость
  `PacketTunnelKit` для `ConfigParser` (см. Wave 0/1 deviations).
- **Fix:** Создан symlink `BBTB/Vendored/libbox.xcframework` →
  `/Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`.
  Идемпотентная операция; `.gitignore` уже игнорирует symlink (Wave 0
  расширил pattern).
- **Files modified:** none tracked (symlink остался untracked, gitignored).
- **Commit:** N/A.

### Превышение плана

- **+1 test:** `test_buildTransportBlock_httpUpgradeReturnsNil` добавлен
  поверх 8 запланированных handler-тестов (defensive coverage для
  соседнего non-http case `.httpUpgrade(path:host:)`). Итого 9 handler-тестов
  вместо 8. Не нарушает план, повышает confidence на стыке Wave 2 / Wave 3.

### Артефакты не в исходном плане

Нет. Все артефакты соответствуют плану §1 (action items 1-5).

## Acceptance criteria (Plan 05-03)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | File `HTTPTransportHandler.swift` exists with `public enum HTTPTransportHandler: TransportHandler` and `return ["type": "http", "path": path]` | PASS |
| 2 | `grep -c "case let .http(path)" HTTPTransportHandler.swift` == 1 | PASS (1) |
| 3 | `grep -c "displayName = \"HTTP/2\"" HTTPTransportHandler.swift` == 1 | PASS (1) |
| 4 | Fixture `vless-tls-http.txt` exists + содержит `type=http` | PASS |
| 5 | Fixture `trojan-http.txt` exists + содержит `type=http` | PASS |
| 6 | `swift test --filter HTTPTransportHandlerTests` exits 0 with ≥ 8 tests | PASS (9 tests) |
| 7 | `swift test --filter VLESSURIParserTLSTests` ≥ 3 new HTTP-related tests PASS | PASS (3 new, 16 total) |
| 8 | `swift test --filter TrojanURIParserTests` включает `test_trojan_http_uri_parses` PASS | PASS (15 total) |
| 9 | Full ConfigParser suite ≥ 158 tests, 0 failures | PASS (182, 0 failures) |
| 10 | Zero modifications to `TransportParamParser.swift`, `TrojanURIParser.swift`, `VLESSURIParser.swift` | PASS (verified `git diff --name-only 81cf898..HEAD -- BBTB/Packages/ConfigParser/Sources/` — empty) |

## Success criteria (Plan 05-03)

- [x] `HTTPTransportHandler.swift` created with correct minimal `{type, path}` block
- [x] `HTTPTransportHandlerTests` — 9 tests PASS (≥ 8 required)
- [x] 2 URI fixtures (`vless-tls-http.txt`, `trojan-http.txt`) created
- [x] 4 new parser tests (3 VLESS+TLS+HTTP + 1 Trojan+HTTP) PASS
- [x] All Wave 1 + Phase 4 tests still PASS (no regressions): TransportRegistry 24 (15 baseline + 9 new), ConfigParser 182 (178 baseline + 4 new), AppFeatures 49 (unchanged)
- [x] Zero changes to parsers — Wave 0/1 delegation already covers http/h2

## Known Stubs

Нет. `HTTPTransportHandler` — полностью функциональная минимальная
реализация. Поле `host` намеренно опущено (sing-box `tls.server_name`
fallback — задокументированное поведение sing-box, не stub). Multi-host
расширение — future work, документировано как backlog в doc-comment.

## Threat Flags

Нет нового threat-surface. `HTTPTransportHandler` — pure data type,
не выполняет сетевых операций. URI fixtures используют тестовые
UUID/passwords и generic `example.com` — не содержат реальных secrets.
ALPN `h2` в trojan-фикстуре — стандартный HTTP/2 ALPN identifier, не
sensitive значение.

## Self-Check: PASSED

### Created files exist

- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/HTTPTransportHandler.swift` — FOUND
- `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/HTTPTransportHandlerTests.swift` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-http.txt` — FOUND
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-http.txt` — FOUND

### Modified files contain expected additions

- `VLESSURIParserTLSTests.swift` — +3 new tests (`test_vlessTLS_http_uri_parses`,
  `test_vlessTLS_h2_alias_parses_as_http`, `test_vlessTLS_http_missingPath_returnsUnsupported`) — FOUND
- `TrojanURIParserTests.swift` — +1 new test (`test_trojan_http_uri_parses`) — FOUND

### Commits exist

- `603fcb3` (test RED — failing HTTP handler tests + fixtures) — FOUND
- `628283f` (feat GREEN — HTTPTransportHandler implementation) — FOUND

## Next: Wave 3

Wave 3 (HTTPUpgrade transport vertical slice):
- `HTTPUpgradeTransportHandler` в `TransportRegistry/Handlers/` —
  `.httpUpgrade(path:host:)` → `["type": "httpupgrade", "path": path, "host": host]`.
  **Критично:** в отличие от HTTP (Wave 2), HTTPUpgrade host — **string**, не array.
  Это противоположная shape; Wave 3 plan должен явно проверить invariant
  через handler-test `block["host"] as? String`, не `[String]`.
- URI парсеры уже умеют `?type=httpupgrade&path=/p&host=h` (Wave 0
  TransportParamParser); зеркально к HTTP тестам — `?type=httpupgrade`
  без `path` → throws → unsupportedTransport.
- Test fixtures: `vless-tls-httpupgrade.txt`, `trojan-httpupgrade.txt`.
- Никаких изменений в data models (`TransportConfig.httpUpgrade` уже существует
  в VPNCore с Wave 0).
- Никаких изменений в парсерах (Wave 0/1 уже полностью покрыли httpupgrade
  на уровне URI).
