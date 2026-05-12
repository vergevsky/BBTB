---
phase: 04-protocol-expansion
plan: 03
subsystem: protocols
tags: [shadowsocks, sip002, sip022, outline, parser, pool-builder, sing-box, r1-invariant, tdd]

# Dependency graph
requires:
  - phase: 04-protocol-expansion
    plan: 01
    provides: "AnyParsedConfig.shadowsocks case + ParsedShadowsocks struct (D-05) + UnsupportedReason.unsupportedSSMethod"
  - phase: 04-protocol-expansion
    plan: 02
    provides: "Protocols/VLESSTLS SPM-package шаблон (Package.swift + Sources + Tests + Resources layout)"
  - phase: 02-trojan-import-flow
    provides: "Trojan handler / ConfigBuilder / template — образец structure для SS handler"
provides:
  - "ShadowsocksURIParser.parse(_:) throws -> ParsedShadowsocks с dual-decoder (Pitfall 1 mitigation)"
  - "supportedSSMethods whitelist (8 методов: 3 SS-2022-blake3-* + 5 legacy AEAD)"
  - "ShadowsocksURIError (.malformedURI / .missingHost / .missingPort / .malformedUserinfo / .unsupportedMethod)"
  - "UniversalImportParser case \"ss\" routes → .supported(.shadowsocks) / .unsupported(.unsupportedSSMethod) / .failed.invalid"
  - "Protocols/Shadowsocks SPM package (handler + ConfigBuilder + sing-box JSON template)"
  - "PoolBuilder.buildShadowsocksOutbound + case .shadowsocks (R1 trivial — нет tls block)"
  - "D-11 Outline access keys покрыты тем же handler-ом (SIP002 ss:// — no special branch)"
affects: [04-04, 04-05, 04-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SIP002/SIP022 dual-path decoder: percent-encoded path (SS-2022 + legacy variant) → base64url fallback (Pitfall 1)"
    - "URLComponents.password reassembly: SIP022 URI с literal `:` в userinfo пересобирается обратно в `method:password` перед decoder (необходимо т.к. URLComponents режет по `:`)"
    - "Shadowsocks sing-box outbound БЕЗ tls block — R1 invariant trivial; D-08 R1 exception (insecure=true) применяется ТОЛЬКО к Hysteria2"
    - "PoolBuilder switch case .shadowsocks tag prefix `ss-N` — отличает SS от других протоколов в logs/asserts"

key-files:
  created:
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/ShadowsocksURIParser.swift"
    - "BBTB/Packages/Protocols/Shadowsocks/Package.swift"
    - "BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ShadowsocksHandler.swift"
    - "BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift"
    - "BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/Resources/SingBoxConfigTemplate.shadowsocks.json"
    - "BBTB/Packages/Protocols/Shadowsocks/Tests/ShadowsocksTests/ConfigBuilderTests.swift"
  modified:
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/ShadowsocksURIParserTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/UniversalImportParserTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/DualProtocolSmokeTests.swift"

key-decisions:
  - "ShadowsocksURIError.unsupportedMethod(String) — карри метод в payload (для UI feedback + future telemetry)"
  - "Whitelist в parser-е enforces D-04 на parse уровне — pool builder доверяет (нет дублирующей валидации в ConfigBuilder/PoolBuilder)"
  - "URLComponents.password reassembly — необходимо для SIP022 URI (например `ss://2022-blake3-aes-256-gcm:pwd@host:8388`). URLComponents режет userinfo по literal `:`. Без reassembly path-1 decoder получает только `method`, не `method:password` → throws malformedUserinfo. Это нашлось при first test run: fixture `ss-2022-percent-encoded.txt` failed; добавлен `comps.password` reassembly шаг."
  - "Path-2 (base64url fallback) НЕ применяет whitelist check — это даёт `parse` функции возможность различить malformedUserinfo от unsupportedMethod. Без этого path-2 вместо broadcasting корректного `.unsupportedMethod` ошибался бы `.malformedUserinfo` и потерял payload."
  - "PoolBuilder.buildShadowsocksOutbound — без mutate-port pipeline (degenerate path в `buildSingBoxJSON` уже учитывает port в outbound dictionary). Builder-level mutatePort нужен только для single-server template flow (`ConfigBuilder.swift`), не pool path."
  - "Network=tcp hardcoded в SS outbound — Phase 4 не реализует UDP relay (sing-box поддерживает, но добавить будет отдельным решением — wiki UDP-relay note в Phase 5+ scope)."

requirements-completed: [PROTO-04]

# Metrics
duration: ~25min
completed: 2026-05-12
---

# Phase 4 Plan 03: Shadowsocks Vertical Slice Summary

**PROTO-04 vertical slice — `ShadowsocksURIParser` с SIP002/SIP022 dual-decoder (8-метод whitelist) + Protocols/Shadowsocks SPM package (handler + builder + sing-box JSON template БЕЗ TLS блока) + PoolBuilder.buildShadowsocksOutbound + UniversalImportParser route. Outline access keys (D-11) парсятся тем же handler-ом без отдельной ветки.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-12T20:00:00Z (approx)
- **Completed:** 2026-05-12T20:10:00Z
- **Tasks:** 3 (все автономно, без checkpoints)
- **Files created:** 6 (1 parser + 1 SPM package с 4 файлами + 1 test файл — суммарно)
- **Files modified:** 6

## Accomplishments

- **PROTO-04 vertical slice реализован**: `ss://` URI парсится в `AnyParsedConfig.shadowsocks(ParsedShadowsocks)` через `ShadowsocksURIParser.parse`, проходит через `PoolBuilder.buildShadowsocksOutbound`, генерирует валидный sing-box JSON с `type: "shadowsocks"` outbound (без TLS блока).
- **SIP002 + SIP022 dual-decoder работает**:
  - **SIP022 (SS-2022-blake3-*) percent-encoded** — `ss://2022-blake3-aes-256-gcm:YctP%2BFixt...%3D@vpn.test:8388` парсится в `ParsedShadowsocks(method: "2022-blake3-aes-256-gcm", password: "YctP+FixtUreSecre7P4ssw0rdBaSe64Equ=")`.
  - **SIP002 base64url** — `ss://MjAyMi1ibGFr...=@example.com:8388` парсится так же.
  - **Legacy AEAD** (`chacha20-ietf-poly1305` + 5 других) — base64url + percent-encoded оба пути работают.
  - **Outline access key** (D-11) — `ss://Y2hhY2hh...=@outline.example.com:443` — same parser, no special branch.
- **Whitelist enforcement** (T-04-03-01 mitigation): `aes-128-cfb` / `rc4-md5` / другие stream ciphers → `ShadowsocksURIError.unsupportedMethod("...")` → UniversalImportParser routes в `.unsupported(reason: .unsupportedSSMethod)`. Не передаётся в pool builder.
- **Protocols/Shadowsocks SPM package**:
  - Компилируется на iOS 18 / macOS 15.
  - `swift test --filter ShadowsocksTests` — 10/10 PASS, включая R1 self-test (`SingBoxConfigLoader.validate`) и invariant что `outbound["tls"] == nil`.
- **PoolBuilder integration**: pool с .shadowsocks → urltest selector содержит "ss-N" tag; multi-protocol pool (ss + trojan + vlessTLS) валиден; single SS — degenerate path с route.final="ss-0".
- **R1 invariant trivial**: SS outbound НЕ содержит TLS block (encryption на уровне протокола). D-08 R1 exception (`insecure: true`) применяется ТОЛЬКО к Hysteria2 — для SS такого поля нет вовсе.
- **ShadowsocksURIParserTests RED→GREEN transition**: 6 XCTFail placeholders из Plan 04-01 заменены на 7 полноценных тестов (включая bonus `test_allWhitelistMethods_parse` — coverage всех 8 методов).
- **Regression-free**: 26/26 ConfigParser non-RED тестов PASS. 9 остальных failures — Wave 0 RED placeholders для Plan 04-04 (Hysteria2URIParserTests — 5) и Plan 04-05 (ClashYAMLParserTests — 4), out of scope.

## Task Commits

Each task committed atomically:

1. **Task 1: ShadowsocksURIParser + SIP022 dual-decoder + UIP route** — `3a734eb` (feat)
2. **Task 2: Protocols/Shadowsocks SPM package** — `5b4decc` (feat)
3. **Task 3: PoolBuilder.buildShadowsocksOutbound + tests** — `9b148dc` (feat)

## Files Created/Modified

### Created (Protocols/Shadowsocks package)

- `BBTB/Packages/Protocols/Shadowsocks/Package.swift` — SPM манифест, library name "Shadowsocks", deps на VPNCore и PacketTunnelKit (path-based), test target linker settings (resolv, bsm, SystemConfiguration, AppKit/UIKit), resource process для template JSON.
- `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ShadowsocksHandler.swift` — `VPNProtocolHandler` conformance, `identifier = "shadowsocks"`, `displayName = "Shadowsocks"`, `isAvailable = true`, validate/connect/disconnect/diagnostics stubs (зеркало TrojanHandler / VLESSTLSHandler).
- `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift` — enum с `ShadowsocksInputs` struct (host, port, method, password, remark) + `BuilderError` (templateLoadFailed, invalidPort, missingMethod, missingPassword) + `buildSingBoxJSON` через template + replacingOccurrences + mutatePort (если != 8388).
- `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/Resources/SingBoxConfigTemplate.shadowsocks.json` — sing-box config template: outbound `type: "shadowsocks"`, fields `method`/`password`/`network: "tcp"`, **БЕЗ tls block**. log/dns/route — копия Trojan template; route.final="shadowsocks-out"; DNS секция с `${DNS_DETOUR}`.
- `BBTB/Packages/Protocols/Shadowsocks/Tests/ShadowsocksTests/ConfigBuilderTests.swift` — 10 тестов: placeholders substituted + R1 self-test, method/password substituted, legacy method works, custom port mutated, no TLS block invariant, network=tcp, invalidPort + emptyMethod + emptyPassword throws.

### Created (ConfigParser parser)

- `BBTB/Packages/ConfigParser/Sources/ConfigParser/ShadowsocksURIParser.swift` — `public enum ShadowsocksURIError`, `public enum ShadowsocksURIParser` с `public static let supportedSSMethods: Set<String>` (8 методов) + `public static func parse(_ uri: String) throws -> ParsedShadowsocks` + private `decodeUserinfo` dual-path decoder. URLComponents.password reassembly для SIP022 percent-encoded case.

### Modified

- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — `parseSingleURI` case `"ss":` маршрутизирует через `ShadowsocksURIParser.parse`; `unsupportedMethod` → `.unsupported(reason: .unsupportedSSMethod)` через intermediate catch; прочие ошибки → `.failed.invalid`.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — switch parsed дополнен `case .shadowsocks(let s): tag = "ss-\(index)"; outbound = buildShadowsocksOutbound(parsed: s, tag: tag)`. Новая private static `buildShadowsocksOutbound(parsed:tag:)`: возвращает `["type": "shadowsocks", "tag": tag, "server": parsed.host, "server_port": parsed.port, "method": parsed.method, "password": parsed.password, "network": "tcp"]` — **БЕЗ tls key** by design. `case .hysteria2: continue` остаётся scaffold (Plan 04-04 закроет).
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/ShadowsocksURIParserTests.swift` — 6 XCTFail placeholders → 7 GREEN tests: test_2022_base64_parses, test_2022_percentEncoded_parses, test_legacy_chacha20_parses, test_outlineAccessKey_parses (D-11), test_unknownMethod_unsupported (whitelist rejection), test_malformedURI_throws (4 sub-cases), test_allWhitelistMethods_parse (coverage всех 8 методов).
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift` — `makeShadowsocks(...)` factory + 5 новых SS-тестов: buildsValidOutbound (R1 self-test, NO tls), legacyMethod, inMultiOutboundPool (ss + trojan + vlessTLS), customPort, singleServer_degenerate (route.final="ss-0").
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/UniversalImportParserTests.swift` — `test_singleSS_unsupported` переименован в `test_singleSS_supported` (Phase 4 поведение: aes-256-gcm в whitelist'е → supported); добавлен `test_singleSS_unsupportedMethod_routedToUnsupported` (whitelist routing); `test_multiLine_withGarbageLine_doesNotAbort` обновлён (ss://abc → failed, не unsupported).
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/DualProtocolSmokeTests.swift` — `test_multiline_withUnsupported_isolatesSupportedForPool` переименован в `test_multiline_withSupportedSS_buildsValidPool` (3 supported, 0 unsupported); `test_onlyUnsupported_poolBuilderThrows` → `test_onlyNonSupported_poolBuilderThrows` (1 unsupported + 1 failed; supported=0 → PoolBuilder throws).

## Decisions Made

- **URLComponents.password reassembly для SIP022** — необходимо при первом test run обнаружилось что fixture `ss-2022-percent-encoded.txt` падает с malformedUserinfo. URLComponents разбивает userinfo на user/password по literal `:`, поэтому SIP022 URI `ss://method:pwd@host` приходит с непустым `comps.password`. Решение: если `comps.password != nil` — reassemble `"\(user):\(pwd)"` перед передачей в decoder. Альтернатива (regex по `comps.percentEncodedUser + ":" + comps.percentEncodedPassword`) считалась — отвергнута как менее читаемая. Закреплено тестом `test_2022_percentEncoded_parses`.
- **Path-2 (base64url) пропускает whitelist check** — design decision из 04-RESEARCH.md Example 2. Если base64 decode успешен но method не в whitelist'е, parser возвращает декодированный `(method, password)` и `parse` функция throws `.unsupportedMethod(method)`. Если whitelist применялся бы и в path-2, неподдерживаемый метод приходил бы как `.malformedUserinfo` — пользователь бы не понял, что проблема в выкошенном cipher'е.
- **Network=tcp hardcoded в Shadowsocks outbound** — sing-box поддерживает UDP relay, но Phase 4 фокусируется на TCP (consistent failover поведение). UDP — Phase 5+ scope (wiki note добавлю при необходимости).
- **PoolBuilder.buildShadowsocksOutbound не вызывает mutatePort** — в pool case server_port прокидывается напрямую в outbound dictionary через `parsed.port`. mutatePort нужен только в single-server template flow (`ConfigBuilder.swift`), где template имеет hardcoded "server_port": 8388.
- **Test 4 / Test 6 в UniversalImportParserTests + DualProtocolSmoke tests 2/4 обновлены** — это была обратная совместимость: Phase 2 ставило все `ss://` в unsupported (stub). Phase 4 Plan 03 включает реальный SS handler — `aes-256-gcm:password` теперь supported. Тесты переименованы для отражения нового contract'а (Rule 3 — blocking — auto-fix, документировано в Deviations).
- **R1 invariant invariant trivial для SS** — отсутствие `tls` key в SS outbound — это design constraint протокола, а не наша политика. SS encryption делается на уровне самого протокола (AEAD-2022 в нашем случае). У нас НЕТ возможности случайно включить `insecure: true` для SS — поля нет в outbound dictionary вовсе. Trivial R1 self-test через `outbound["tls"] == nil` assertion.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] URLComponents.password reassembly для SIP022 URI**

- **Found during:** Task 1 verification (`swift test --filter ShadowsocksURIParserTests`).
- **Issue:** Test `test_2022_percentEncoded_parses` failed с `caught error: "malformedUserinfo"`. Fixture `ss://2022-blake3-aes-256-gcm:YctP%2BFixt...%3D@vpn.test:8388` приходит в `URLComponents` с разрезом userinfo по literal `:` — `comps.user = "2022-blake3-aes-256-gcm"`, `comps.password = "YctP%2BFixt...%3D"`. Decoder получал только `user` без password → percent-decoded `"2022-blake3-aes-256-gcm"` без `:` → fall-through → base64url decode `"2022-blake3-aes-256-gcm"` → fail (не valid base64) → throws malformedUserinfo.
- **Fix:** Reassemble `"\(user):\(pwd)"` перед передачей в `decodeUserinfo` если `comps.password` не nil.
- **Files modified:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/ShadowsocksURIParser.swift` (5 строк добавлено в `parse`).
- **Verification:** `test_2022_percentEncoded_parses` теперь PASS; base64url path (без `:` в URLComponents) продолжает работать (SIP002 `comps.password = nil` → reassembly бранч не активен).
- **Committed in:** `3a734eb` (Task 1 commit, fix-in-place до commit).

**2. [Rule 3 — Blocking] Существующие UniversalImportParser / DualProtocolSmoke тесты ожидали старое (Phase 2) поведение ss → unsupported**

- **Found during:** Task 1 verification (regression test pass).
- **Issue:** 4 теста в `UniversalImportParserTests` + `DualProtocolSmokeTests` были написаны под Phase 2 contract — `ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@host:8388` (base64 от `aes-256-gcm:password`) шёл в `.unsupported` через stub parser. После Phase 4 Plan 03 — `aes-256-gcm` в whitelist'е, теперь supported.
- **Affected tests:**
  - `UniversalImportParserTests.test_singleSS_unsupported` (1 supported, 0 unsupported → 0, 1; ожидание сломалось).
  - `UniversalImportParserTests.test_multiLine_withGarbageLine_doesNotAbort` (1 supported, 1 unsupported, >=1 failed → 1, 0, >=2; ss://abc → failed).
  - `DualProtocolSmokeTests.test_multiline_withUnsupported_isolatesSupportedForPool` (2, 1 → 3, 0; SS теперь supported).
  - `DualProtocolSmokeTests.test_onlyUnsupported_poolBuilderThrows` (0, 2 → 0, 1, 1; ss://abc malformed → failed, не unsupported).
- **Fix:** Тесты обновлены под новый contract, переименованы (test_singleSS_supported, test_multiline_withSupportedSS_buildsValidPool, test_onlyNonSupported_poolBuilderThrows) для отражения изменений. Plan 04-03 явно требует «Existing UniversalImportParser tests для ss:// — обновить ожидания: ss:// с supported method теперь → supported (не unsupported)».
- **Files modified:** `UniversalImportParserTests.swift`, `DualProtocolSmokeTests.swift`.
- **Verification:** Все 4 теста + новый `test_singleSS_unsupportedMethod_routedToUnsupported` (whitelist routing) PASS.
- **Committed in:** `3a734eb` (Task 1 commit).

---

**Total deviations:** 2 auto-fixed (оба Rule 3 — blocking). Никаких Rule 1 / Rule 2 / Rule 4 не было.
**Impact on plan:** Фикс №1 был bug в моём первом drafted parser — Rule 1 уровень severity ("code doesn't work as intended"), но катон поскольку нашлось до commit'а. Фикс №2 — explicit ожидание в плане (behavior section Task 1).

## Issues Encountered

- В worktree отсутствовал `BBTB/Vendored/libbox.xcframework` (binary не подтянут в git worktree). Создан локальный симлинк на main repo для верификации `swift build`/`swift test`; **не закоммичен**, удалён до финального состояния. Это известный workflow для worktree-based verification (Plan 04-01 / 04-02 описали тот же workaround).
- `Package.resolved` для ConfigParser создавался при `swift build`; не закоммичен (артефакт SPM, остаётся за пределами repo).

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| (none) | — | No new security surface introduced. T-04-03-01..06 (Plan 04-03 threat register) mitigated через test invariants. |

Threat-register coverage:
- **T-04-03-01** (Tampering — deprecated stream ciphers `rc4-md5`, `aes-256-cfb`): mitigated через `supportedSSMethods` whitelist + `test_unknownMethod_unsupported` test. Whitelist enforce на parse уровне, не передаётся в pool builder.
- **T-04-03-03** (Tampering — base64url userinfo с inject control chars): mitigated через `Data(base64Encoded:)` Foundation API (проверяет base64 alphabet) + `String(data:encoding: .utf8)` cast (non-UTF8 → nil → throws malformedUserinfo).
- **T-04-03-04** (Information disclosure — SS password в outboundJSON): accept — выровнено с Trojan password в Phase 2 (T-02-04 invariant), Keychain integration — Plan 06.
- **T-04-03-02 / 05 / 06**: accept — engine-side validation / Foundation API limits / Outline UX scope.
- **R1 invariant trivial для SS**: outbound dictionary НЕ содержит "tls" key вовсе — невозможно случайно скопировать D-08 Hy2-style exception (Pitfall 2 mitigated by design).

## TDD Gate Compliance

Plan маркирован `type: execute` с всеми 3 задачами `tdd="true"`. RED→GREEN cycle выполнен для каждой задачи:

- **Task 1 RED:** Wave 0 placeholders в `ShadowsocksURIParserTests.swift` (6 XCTFail) — упали ДО реализации parser-а. Тесты `test_singleSS_unsupported` ломались только при добавлении implementation (route в supported) — но это RED для нового contract'а, не для отсутствующего кода.
- **Task 1 GREEN:** `ShadowsocksURIParser.swift` + `UniversalImportParser case "ss"` → 7 ShadowsocksURIParserTests + 12 UniversalImportParserTests + 4 DualProtocolSmokeTests PASS (23/23).
- **Task 2 RED:** `ConfigBuilderTests.swift` с `try ConfigBuilder.buildSingBoxJSON(from: ShadowsocksInputs(...))` — fail на compilation (package ещё не существует).
- **Task 2 GREEN:** Package.swift + handler + builder + template → 10/10 ConfigBuilderTests PASS.
- **Task 3 RED:** PoolBuilderTests с `.shadowsocks(makeShadowsocks())` — runtime skip (`switch case .shadowsocks: continue` в pre-Plan-03 PoolBuilder), assertion на outbound type=="shadowsocks" — fail (нет outbound в результате).
- **Task 3 GREEN:** `case .shadowsocks(let s)` + buildShadowsocksOutbound → 21/21 PoolBuilderTests PASS, 26/26 в combined ConfigParser non-Wave-0 suite.

Каждая task — combined feat-commit (test + impl). Plan не требует строго гранулированных RED/GREEN commits.

## Self-Check: PASSED

- **All 6 created files exist** (verified `[ -f path ]` checks).
- **All 6 modified files reflected** (git diff на каждый файл показывает изменения).
- **All 3 commits in git log** (verified `git log --oneline | grep`):
  - `3a734eb` feat(04-03): ShadowsocksURIParser + SIP022 dual-decoder + UniversalImportParser ss route
  - `5b4decc` feat(04-03): Protocols/Shadowsocks SPM package — handler + builder + template без TLS
  - `9b148dc` feat(04-03): PoolBuilder.buildShadowsocksOutbound + switch case .shadowsocks + tests
- **All acceptance criteria verified** (grep checks все вышли с правильными counts):
  - `supportedSSMethods` присутствует 3× в parser файле (let + 2 references).
  - `case "ss":` присутствует в UniversalImportParser.swift.
  - `ShadowsocksURIParser.parse` называется из UniversalImportParser.
  - `buildShadowsocksOutbound` присутствует 2× в PoolBuilder.swift (1 call + 1 def).
  - `case .shadowsocks(let` присутствует в PoolBuilder switch.
  - `identifier = "shadowsocks"` присутствует в handler.
  - В SS template — **0** литералов `"tls"` (R1 trivial verified).
  - **0** `XCTFail("Pending Plan 04-03"` placeholders остались в test файле.
- **All success criteria из плана выполнены** (ss:// SIP002 + SIP022 + Outline парсятся; 8-method whitelist enforced; PoolBuilder builds valid SS outbound; sing-box JSON passes validate; RED→GREEN transition complete).

## Next Phase Readiness

Готово для следующих параллельных Plan'ов:
- **04-04 (Hysteria2)** — независимый; уже на момент Plan 03 был запланирован параллельно. Phase 4 Plan 03 ничего не блокирует.
- **04-05 (Clash YAML)** — будет использовать `AnyParsedConfig.shadowsocks` case через Yams → ShadowsocksURIParser (или прямой `ParsedShadowsocks` constructor для Clash `ss` proxy entries). Wave 0 fixture `clash-mixed-proxies.yaml` уже содержит `ss-2022-blake3-aes-256-gcm` entry.
- **04-06 (integration / auto-upgrade)** — `ServerConfig.isSupported` auto-upgrade flow будет re-parse'ить старые `ss://` записи через `UniversalImportParser` → теперь они становятся supported.

**Blockers:** None.

---
*Phase: 04-protocol-expansion*
*Plan: 03*
*Completed: 2026-05-12*
