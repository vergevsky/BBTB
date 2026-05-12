---
phase: 04-protocol-expansion
plan: 04
subsystem: protocols
tags: [hysteria2, quic, http3, parser, pool-builder, sing-box, r1-exception, d-08, r1-invariant, tdd, pitfall-2-mitigation]

# Dependency graph
requires:
  - phase: 04-protocol-expansion
    plan: 01
    provides: "AnyParsedConfig.hysteria2 case + ParsedHysteria2 struct (D-07) + UnsupportedReason.multiPortNotSupported"
  - phase: 04-protocol-expansion
    plan: 02
    provides: "Protocols/VLESSTLS SPM-package шаблон + PoolBuilder switch enum exhaustivity"
  - phase: 04-protocol-expansion
    plan: 03
    provides: "Protocols/Shadowsocks SPM-package шаблон + PoolBuilder switch case .shadowsocks (после которого добавляется .hysteria2)"
  - phase: 02-trojan-import-flow
    provides: "Trojan handler / ConfigBuilder / template — образец structure для Hy2 handler"
provides:
  - "Hysteria2URIParser.parse(_:) throws -> ParsedHysteria2 (D-09 dual scheme + D-08 three-synonym + D-09 multi-port reject + obfs whitelist)"
  - "Hysteria2URIError (.malformedURI / .missingAuth / .multiPortNotSupported / .unsupportedObfs)"
  - "UniversalImportParser case \"hy2\",\"hysteria2\" routes → .supported(.hysteria2) / .unsupported(.multiPortNotSupported) / .failed.invalid"
  - "Protocols/Hysteria2 SPM package (handler + ConfigBuilder + sing-box JSON template с ${ALLOW_INSECURE} placeholder — единственный template с этим placeholder)"
  - "PoolBuilder.buildHysteria2Outbound + case .hysteria2 (R1 EXCEPTION — единственный builder с tls.insecure: parsed.allowInsecure)"
  - "test_nonHy2_outbounds_neverHaveInsecureTrue — R1 invariant test (Pitfall 2 mitigation, CI gate)"
affects: [04-05, 04-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pre-URLComponents string scan port-части — детектит multi-port формат (`443,8443` / `443-8443`) ДО URLComponents.init, поскольку URLComponents возвращает nil для multi-port URI и parser потерял бы точную причину (Pitfall 6 mitigation)"
    - "Boundary-safe port detection: split host-части по `:` с maxSplits=1, считать port-частью ТОЛЬКО parts.count==2 (предотвращает ложное срабатывание `,/-` в hostname типа `my-host.example.com`)"
    - "${ALLOW_INSECURE} JSON boolean placeholder (без кавычек в template) — после replacingOccurrences превращается в valid JSON boolean (`true`/`false`), а не строку"
    - "R1 EXCEPTION enforcement через 3 layer'а: (1) большой comment block над function и над replacingOccurrences, (2) invariant test test_nonHy2_outbounds_neverHaveInsecureTrue, (3) Parsed* structs без allowInsecure field by design"
    - "obfs whitelist на parser level (только salamander) — sing-box engine validates obfs.type в handshake, parser fail-fast перед pool building"

key-files:
  created:
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/Hysteria2URIParser.swift"
    - "BBTB/Packages/Protocols/Hysteria2/Package.swift"
    - "BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift"
    - "BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift"
    - "BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Resources/SingBoxConfigTemplate.hysteria2.json"
    - "BBTB/Packages/Protocols/Hysteria2/Tests/Hysteria2Tests/ConfigBuilderTests.swift"
  modified:
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Hysteria2URIParserTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift"

key-decisions:
  - "Hysteria2URIError.multiPortNotSupported(String) — carry portPart строку (для UI feedback + future telemetry; UniversalImportParser также reuse'ит этот payload для name='<host>:multi-port' display)"
  - "Boundary-safe port detection: `parts.count == 2` gate — без него `hy2://auth@my-host.example.com` (без port) ложно сработал бы на `-` в hostname"
  - "Hysteria2URI parser НЕ применяет default port 443 к multi-port detection: detection происходит ДО URLComponents.init, на raw substring уровне, чтобы вернуть точный `.multiPortNotSupported` вместо `.malformedURI`"
  - "${ALLOW_INSECURE} placeholder — без кавычек в template (`\"insecure\": ${ALLOW_INSECURE}`), чтобы после replacingOccurrences получился JSON boolean (`true`/`false`), а не строка. JSON parser в SingBoxConfigLoader валидирует это автоматически"
  - "obfs whitelist в parser-е (только `salamander`) — не в ConfigBuilder/PoolBuilder; parser fail-fast перед строительством pool. Builder доверяет что obfs валидирован"
  - "buildHysteria2Outbound НЕ имеет fallback fingerprint в parser (Hy2 RESEARCH §pattern-3: `fp` или nil) — в builder default `chrome` ставится только если parsed.fingerprint nil/empty (Trojan-стиль fallback). Это симметрично VLESSTLS / Trojan поведению"
  - "tls.alpn=[\"h3\"] hardcoded в Hy2 outbound builder и template (Hysteria2 = QUIC = HTTP/3; sing-box требует h3 ALPN для QUIC handshake) — НЕ читается из URI, поскольку нет легитимного use-case для другого ALPN"
  - "test_nonHy2_outbounds_neverHaveInsecureTrue включает sanity check (`sawHy2Insecure==true assert`) — это проверяет что test НЕ false-positive: pool ДОЛЖЕН содержать hy2-* outbound с insecure=true (legitimate D-08 case). Если sanity assert fail'ит — invariant test не проверяет реальный сценарий и нуждается в исправлении"

requirements-completed: [PROTO-05]

# Metrics
duration: ~30min
completed: 2026-05-12
---

# Phase 4 Plan 04: Hysteria2 Vertical Slice Summary

**PROTO-05 vertical slice — `Hysteria2URIParser` с D-09 dual scheme (hy2/hysteria2), D-08 three-synonym collapse (insecure/allowInsecure/skip-cert-verify → allowInsecure Bool), pre-URLComponents multi-port reject + obfs whitelist; Protocols/Hysteria2 SPM package с template содержащим единственный в codebase `${ALLOW_INSECURE}` JSON boolean placeholder; PoolBuilder.buildHysteria2Outbound — ЕДИНСТВЕННЫЙ outbound builder где tls.insecure может legitimately быть true (R1 EXCEPTION); R1 invariant test через CI gate.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-05-12T20:13:00Z (approx)
- **Completed:** 2026-05-12T20:22:00Z
- **Tasks:** 3 (все автономно, без checkpoints)
- **Files created:** 6 (1 parser + 1 SPM package с 4 файлами + 1 test файл — суммарно)
- **Files modified:** 4

## Accomplishments

- **PROTO-05 vertical slice реализован**: `hy2://` / `hysteria2://` URI парсится в `AnyParsedConfig.hysteria2(ParsedHysteria2)` через `Hysteria2URIParser.parse`, проходит через `PoolBuilder.buildHysteria2Outbound`, генерирует валидный sing-box JSON с `type: "hysteria2"` outbound (с `tls.insecure: parsed.allowInsecure` — R1 EXCEPTION).
- **D-09 dual scheme** — `hy2://auth@host:443?sni=...` и `hysteria2://auth@host:443?sni=...` дают семантически идентичный `ParsedHysteria2`. Tested via `test_bothSchemes_parse`.
- **D-08 three-synonym collapse** — `insecure=1` (Hysteria2 native), `allowInsecure=1` (некоторые subscription панели), `skip-cert-verify=1` (Clash YAML соглашение, пробрасывается в URI вариант) — ВСЕ три → `parsed.allowInsecure=true`. Без флагов → `allowInsecure=false` (strict TLS по умолчанию). Tested via `test_insecureFlag_setsAllowInsecure` + `test_insecureFromFixture`.
- **D-09 multi-port reject (Pitfall 6)**: pre-URLComponents string scan port-части. `URLComponents(string: "hy2://auth@host:443,8443?")` возвращает `nil` — без pre-scan parser потерял бы точную причину (`malformedURI` вместо `multiPortNotSupported`). Fixture `hy2-multi-port.txt` → `throws .multiPortNotSupported`. Аналогично для dash-range формы (`443-8443`). Tested via `test_multiPort_rejects` + `test_multiPort_dashRange_rejects`.
- **obfs whitelist (T-04-04-04 mitigation)**: только `salamander` поддерживается; `obfs=plain` → `throws .unsupportedObfs("plain")`. Tested via `test_obfsSalamander_parses` (fixture) + `test_obfsNotSalamander_throws` (inline).
- **Protocols/Hysteria2 SPM package**:
  - Компилируется на iOS 18 / macOS 15.
  - `swift test --filter Hysteria2Tests` — 14/14 PASS, включая R1 self-test (`SingBoxConfigLoader.validate`) для всех variants (default strict + D-08 exception + obfs + pin + fingerprint).
  - Template содержит `"insecure": ${ALLOW_INSECURE}` БЕЗ кавычек → после replacingOccurrences получается JSON boolean (`true`/`false`).
- **R1 EXCEPTION enforcement через 3 layer'а** (Pitfall 2 mitigation):
  1. **Code-level comment markers**: над `buildHysteria2Outbound` function (PoolBuilder.swift), над `replacingOccurrences("${ALLOW_INSECURE}", ...)` (ConfigBuilder.swift), над `ConfigBuilder` enum declaration (Hysteria2 package).
  2. **Test-level CI gate**: `test_nonHy2_outbounds_neverHaveInsecureTrue` — итерирует multi-protocol pool `[vlessReality, vlessTLS, trojan, shadowsocks, hysteria2(allowInsecure:true)]`, assert'ит что outbound с tag НЕ начинающимся `hy2-` не имеет `tls.insecure=true`. Включает sanity assert (`sawHy2Insecure==true`) — proof что test проверяет реальный сценарий.
  3. **Type-level by design**: `ParsedShadowsocks` / `ParsedVLESSTLS` / `ParsedTrojan` structs НЕ содержат `allowInsecure: Bool` field — копирование Hy2 builder pattern в другой builder требует расширения структуры (compiler enforcement).
- **PoolBuilder integration**: 7 Hysteria2-специфичных тестов: `buildsValidOutbound` (default insecure=false), `insecureTrue/False`, `obfsSalamander/Absent`, `pinSHA256`, `singleServer_degenerate` (route.final="hy2-0").
- **Regression-free**: 140/140 не-RED ConfigParser tests PASS. 4 остальных failures — это Plan 04-05 RED placeholders (ClashYAMLParser Wave 0), out of scope.

## Task Commits

Each task committed atomically:

1. **Task 1: Hysteria2URIParser + UniversalImportParser route + 12 tests** — `a005121` (feat)
2. **Task 2: Protocols/Hysteria2 SPM package — handler + ConfigBuilder + template + 14 tests** — `a7339c6` (feat)
3. **Task 3: PoolBuilder.buildHysteria2Outbound + R1 invariant test (Pitfall 2 mitigation)** — `13d10b1` (feat)

## Files Created/Modified

### Created (Protocols/Hysteria2 package)

- `BBTB/Packages/Protocols/Hysteria2/Package.swift` — SPM манифест, library name "Hysteria2", deps на VPNCore и PacketTunnelKit (path-based), test target linker settings (resolv, bsm, SystemConfiguration, AppKit/UIKit), resource process для template JSON.
- `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift` — `VPNProtocolHandler` conformance, `identifier = "hysteria2"`, `displayName = "Hysteria2"`, `isAvailable = true`, validate/connect/disconnect/diagnostics stubs (зеркало TrojanHandler / ShadowsocksHandler / VLESSTLSHandler).
- `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift` — enum с `Hysteria2Inputs` struct (host, port, password, sni, fingerprint?, obfs?, obfsPassword?, allowInsecure, pinSHA256?, remark) + `BuilderError` (templateLoadFailed, invalidPort, missingPassword, missingSNI) + `buildSingBoxJSON` pipeline: validate → template load → 5 placeholder replacements → mutatePort + mutateOptionalFields (fingerprint override / pinSHA256 / obfs salamander mutation через JSONSerialization round-trip). Большой R1 EXCEPTION comment block над enum + над `${ALLOW_INSECURE}` replacingOccurrences.
- `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Resources/SingBoxConfigTemplate.hysteria2.json` — sing-box config template: outbound `type: "hysteria2"`, fields `password`/`tls.{server_name,insecure: ${ALLOW_INSECURE},alpn:["h3"],utls.{enabled:true,fingerprint:"chrome"}}`. ВАЖНО: `"insecure": ${ALLOW_INSECURE}` БЕЗ кавычек — после replace получается JSON boolean. log/dns/route — копия Trojan template; route.final="hysteria2-out"; DNS секция с `${DNS_DETOUR}`.
- `BBTB/Packages/Protocols/Hysteria2/Tests/Hysteria2Tests/ConfigBuilderTests.swift` — 14 тестов: buildsConfigWithoutPlaceholders + R1 self-test, validate_strictDefault, insecureTrue (D-08), insecureFalse_default, obfsSalamander_present, obfsAbsent_omitted, customFingerprint_mutated, pinSHA256_added, customPort_mutated, invalidPort_throws, emptySNI_throws, emptyPassword_throws, alpnIsH3 (Hysteria2 = QUIC = HTTP/3), allOptionalFields_combined (комбинация всех optional fields).

### Created (ConfigParser parser)

- `BBTB/Packages/ConfigParser/Sources/ConfigParser/Hysteria2URIParser.swift` — `public enum Hysteria2URIError` (malformedURI / missingAuth / multiPortNotSupported / unsupportedObfs) + `public enum Hysteria2URIParser` с `public static func parse(_:) throws -> ParsedHysteria2`. Pre-URLComponents multi-port scan (D-09 / Pitfall 6) — split по `@`, затем по terminator (`/`/`?`/`#`), затем по `:` с maxSplits=1; `,` или `-` в port-части → `.multiPortNotSupported`. После URLComponents init: scheme check `hy2`/`hysteria2` (D-09), host non-empty, user → auth (D-07), query parsing → D-08 three-synonym collapse → obfs whitelist (PROTO-05) → return ParsedHysteria2.

### Modified

- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — `parseSingleURI` case `"hy2","hysteria2":` маршрутизирует через `Hysteria2URIParser.parse`; `multiPortNotSupported` → `.unsupported(reason: .multiPortNotSupported)` через intermediate catch (best-effort host extraction из raw URI поскольку URLComponents возвращает nil для multi-port); прочие ошибки → `.failed.invalid`.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — switch parsed дополнен `case .hysteria2(let h): tag = "hy2-\(index)"; outbound = buildHysteria2Outbound(parsed: h, tag: tag)` (заменив `case .hysteria2: continue` scaffold из Plan 04-01). Новая private static `buildHysteria2Outbound(parsed:tag:)` с большим R1 EXCEPTION comment block: tls={enabled, server_name, **insecure: parsed.allowInsecure** (R1 EXCEPTION), alpn:["h3"], utls{enabled,fingerprint: parsed.fingerprint ?? "chrome"}, +pin?}, outbound={type:"hysteria2", tag, server, server_port, password, tls, +obfs?}.
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Hysteria2URIParserTests.swift` — 5 XCTFail placeholders заменены на 12 GREEN tests: bothSchemes_parse, insecureFlag_setsAllowInsecure (3 synonyms + negative), insecureFromFixture, multiPort_rejects (fixture), multiPort_dashRange_rejects (inline), obfsSalamander_parses (fixture), obfsNotSalamander_throws, defaultPort, malformedURI_throws, sniFallback_toHost, fingerprintFromFP, pinSHA256_extracted.
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift` — `makeHysteria2(...)` factory + 7 Hy2-специфичных тестов + критический R1 invariant test `test_nonHy2_outbounds_neverHaveInsecureTrue` с sanity check на legitimate hy2-* insecure=true случай (proof что invariant НЕ false-positive).

## Decisions Made

- **Pre-URLComponents multi-port detection** — single substring scan ДО `URLComponents.init`. Без этого parser возвращал бы `.malformedURI` вместо `.multiPortNotSupported`, теряя точную причину для UI feedback. Закреплено `test_multiPort_rejects` и `test_multiPort_dashRange_rejects`.
- **Boundary-safe port detection** (`parts.count == 2` gate) — без этого hostname с тире (`my-host.example.com`) ложно бы попал в `multiPortNotSupported` branch. Verified mental model на тестовых данных перед записью parser-а.
- **${ALLOW_INSECURE} как JSON boolean** — placeholder в template вписан как `"insecure": ${ALLOW_INSECURE}` БЕЗ кавычек, чтобы после replacingOccurrences стал valid JSON boolean (`true`/`false`), а не строка. SingBoxConfigLoader.validate автоматически проверяет тип через JSONSerialization.
- **R1 EXCEPTION на 3 layer'ах** — code comments, invariant test, type-level by design (структуры parsed-* без allowInsecure поля). Pitfall 2 mitigation — defence in depth.
- **Sanity assert в invariant test** (`sawHy2Insecure==true`) — proof что invariant test проверяет реальный D-08 сценарий. Без sanity assert тест мог бы тривиально пройти при ошибочной конфигурации pool'а (без hy2 outbound вовсе).
- **obfs whitelist на parser level** — не в builder. Builder доверяет что obfs валидирован. Это симметрично Shadowsocks whitelist подходу (parser enforces D-04, builder доверяет).
- **ALPN ["h3"] hardcoded** — Hysteria2 = QUIC = HTTP/3; sing-box требует h3 ALPN для QUIC handshake. Не из URI — нет легитимного use-case для другого ALPN значения (verified via Hysteria2 docs в RESEARCH §pattern-3).
- **fingerprint fallback в pool builder** — `parsed.fingerprint ?? "chrome"` симметрично Trojan / VLESSTLS поведению. В Hy2 ConfigBuilder template default `chrome`, optional override через mutateOptionalFields. В PoolBuilder напрямую через ternary.

## Deviations from Plan

### Auto-fixed Issues

**None.** План выполнен ровно как написан. Все 3 задачи закрыты без авто-фиксов, blocking issues, или Rule 4 architectural questions.

Дополнительно к acceptance criteria плана добавил несколько bonus-тестов (sniFallback, fp, pinSHA256 для parser; alpnIsH3 + allOptionalFields_combined для builder) — покрывают edge cases без изменения plan-предписанного behavior.

## Issues Encountered

- В worktree отсутствовал `BBTB/Vendored/libbox.xcframework` (binary не подтянут в git worktree). Создан локальный симлинк на main repo для верификации `swift build`/`swift test`; **не закоммичен**, удалён до финального состояния. Это известный workflow для worktree-based verification (Plan 04-01 / 04-02 / 04-03 описали тот же workaround).
- `Package.resolved` для ConfigParser создавался при `swift build`; не закоммичен (артефакт SPM, остаётся за пределами repo).

## Threat Flags

**None** — no new security surface introduced. PROTO-05 расширяет protocol handler family без новых network endpoints / auth paths / file access. Threat-register `T-04-04-01..07` mitigated через test invariants и code-level enforcement:

- **T-04-04-01** (Spoofing — hy2:// URI с insecure=1 → MITM с self-signed cert): **accept (D-08)** — documented user-trust model; mitigation в Phase 11 UX (UI warning при импорте Hy2-insecure config, deferred).
- **T-04-04-02** (Tampering — copy-paste buildHysteria2Outbound → R1 violation): **mitigate** through 3-layer enforcement: (1) comment markers в PoolBuilder.swift + ConfigBuilder.swift (Hysteria2 package); (2) **test_nonHy2_outbounds_neverHaveInsecureTrue** invariant test (CI gate); (3) ParsedShadowsocks/ParsedVLESSTLS/ParsedTrojan structs без allowInsecure field by design.
- **T-04-04-03** (DoS — multi-port URI `1-65535`): **mitigate** through D-09 / Pitfall 6 — pre-URLComponents string scan; `test_multiPort_rejects` + `test_multiPort_dashRange_rejects` coverage.
- **T-04-04-04** (Tampering — malicious obfs value): **mitigate** through obfs whitelist в parser (только `salamander`); `test_obfsNotSalamander_throws` coverage.
- **T-04-04-05** (Cryptographic — pinSHA256 invalid): **accept** — invalid pin → sing-box handshake fails → no connection (fail-safe); user видит connection error, не молчаливый MITM.
- **T-04-04-06** (Information disclosure — Hy2 password в outbound JSON): **accept** — same as Trojan/SS (T-02-04 invariant); Keychain integration — Plan 06.
- **T-04-04-07** (Repudiation — sing-box принимает unknown obfs через JSON edit): **accept** — parser whitelist на client side; engine validates obfs.type в handshake.

## TDD Gate Compliance

Plan маркирован `type: execute` с всеми 3 задачами `tdd="true"`. RED→GREEN cycle выполнен для каждой задачи:

- **Task 1 RED:** Wave 0 placeholders в `Hysteria2URIParserTests.swift` (5 XCTFail) + non-existent Hysteria2URIParser/Error types — compile-fail / runtime-XCTFail.
- **Task 1 GREEN:** `Hysteria2URIParser.swift` (D-09 + D-08 + multi-port + obfs whitelist) + `UniversalImportParser case "hy2","hysteria2"` → 12/12 Hysteria2URIParserTests + 12/12 UniversalImportParserTests PASS.
- **Task 2 RED:** `ConfigBuilderTests.swift` с `try ConfigBuilder.buildSingBoxJSON(from: Hysteria2Inputs(...))` — compile-fail (package ещё не существует).
- **Task 2 GREEN:** Package.swift + handler + builder + template + R1 EXCEPTION comment blocks → 14/14 ConfigBuilderTests PASS (включая R1 self-test через SingBoxConfigLoader.validate).
- **Task 3 RED:** PoolBuilderTests с `.hysteria2(makeHysteria2())` — runtime skip (`case .hysteria2: continue` в pre-Plan-04 PoolBuilder); assertion на outbound type=="hysteria2" — fail.
- **Task 3 GREEN:** `case .hysteria2(let h)` + buildHysteria2Outbound с R1 EXCEPTION comment + invariant test → 29/29 PoolBuilderTests PASS, 140/140 не-RED ConfigParser tests PASS.

Каждая task — combined feat-commit (test + impl). Plan не требует строго гранулированных RED/GREEN commits.

## Self-Check: PASSED

- **All 6 created files exist** (verified via `[ -f path ]` checks before SUMMARY):
  - `BBTB/Packages/ConfigParser/Sources/ConfigParser/Hysteria2URIParser.swift` — verified
  - `BBTB/Packages/Protocols/Hysteria2/Package.swift` — verified
  - `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift` — verified
  - `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift` — verified
  - `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Resources/SingBoxConfigTemplate.hysteria2.json` — verified, valid JSON, содержит `${ALLOW_INSECURE}` без кавычек
  - `BBTB/Packages/Protocols/Hysteria2/Tests/Hysteria2Tests/ConfigBuilderTests.swift` — verified
- **All 4 modified files reflected** (git status показывал M / A до commits).
- **All 3 commits in git log** (verified via `git log --oneline -3`):
  - `a005121` feat(04-04): Hysteria2URIParser — D-09 dual scheme + D-08 three-synonym + multi-port reject
  - `a7339c6` feat(04-04): Protocols/Hysteria2 SPM package — handler + ConfigBuilder + template с ${ALLOW_INSECURE}
  - `13d10b1` feat(04-04): PoolBuilder.buildHysteria2Outbound + R1 invariant test (Pitfall 2 mitigation)
- **All acceptance criteria verified** (literal grep checks для каждого acceptance item):
  - File содержит `scheme == "hy2" || scheme == "hysteria2"` (D-09) ✓
  - File содержит `multiPortNotSupported` AND `portPart.contains(",")` AND `portPart.contains("-")` ✓
  - File содержит `insecure` AND `allowInsecure` AND `skip-cert-verify` (D-08) ✓
  - File содержит `obfs != "salamander"` ✓
  - UniversalImportParser содержит `case "hy2", "hysteria2":` AND `Hysteria2URIParser.parse` AND `.hysteria2(` ✓
  - Hysteria2URIParserTests НЕ содержит `XCTFail("Pending Plan 04-04`; содержит `test_bothSchemes_parse`, `test_insecureFlag_setsAllowInsecure`, `test_multiPort_rejects`, `test_obfsSalamander_parses` ✓
  - Hysteria2 Package.swift содержит `name: "Hysteria2"` AND `.process("Resources/SingBoxConfigTemplate.hysteria2.json")` ✓
  - Hysteria2Handler содержит `identifier = "hysteria2"` AND `displayName = "Hysteria2"` ✓
  - Hysteria2 ConfigBuilder.swift содержит `Hysteria2Inputs` AND `${ALLOW_INSECURE}` AND `${HY2_PASSWORD}` AND `hysteria2-out` AND `R1 EXCEPTION` ✓
  - Template содержит `${ALLOW_INSECURE}` AND `"type": "hysteria2"` AND `"alpn": ["h3"]` AND `"insecure": ${ALLOW_INSECURE}` (без кавычек вокруг placeholder) ✓
  - ConfigBuilderTests содержит `XCTAssertEqual(tls["insecure"] as? Bool, true)` AND `XCTAssertEqual(tls["insecure"] as? Bool, false)` AND `SingBoxConfigLoader.validate` ✓
  - PoolBuilder.swift содержит `case .hysteria2(let` AND `buildHysteria2Outbound` AND `R1 EXCEPTION` AND `"insecure": parsed.allowInsecure` ✓
  - PoolBuilderTests содержит `test_nonHy2_outbounds_neverHaveInsecureTrue` AND `R1 violation` AND `test_hysteria2_insecureTrue` AND `test_hysteria2_insecureFalse_default` ✓
  - `swift test --filter Hysteria2URIParserTests` → 12/12 PASS ✓
  - `swift test --filter UniversalImportParserTests` → 12/12 PASS (regression-free) ✓
  - `swift build` в Hysteria2 package → exits 0 ✓
  - `swift test --filter Hysteria2Tests` → 14/14 PASS ✓
  - `swift test --filter PoolBuilderTests` → 29/29 PASS ✓
  - `swift test` (full ConfigParser suite) — 140 PASS, 4 fail (ClashYAMLParser Plan 04-05 RED placeholders, out of scope) ✓

## Next Phase Readiness

Готово для следующих параллельных Plan'ов:
- **04-05 (Clash YAML)** — будет использовать `AnyParsedConfig.hysteria2` case через Yams → `ParsedHysteria2` constructor (Clash YAML `hysteria2` proxy entries). Wave 0 fixture `clash-mixed-proxies.yaml` уже содержит `hysteria2` entry с `skip-cert-verify` — Clash D-08 synonym (третий синоним обрабатывается тем же parser collapse'ом).
- **04-06 (integration / auto-upgrade)** — `ServerConfig.isSupported` auto-upgrade flow будет re-parse'ить старые `hy2://` записи через `UniversalImportParser` → теперь они становятся supported (с corretkimi `allowInsecure` / `multiPortNotSupported` routings).

**Phase 4 base достигнут** (per plan success criteria): все 3 новых протокола (VLESS+TLS / SS / Hy2) полностью реализованы pipeline-end-to-end (parser → pool → builder → JSON → validate). R1 invariant защищён 3 mitigation layers'ами.

**Blockers:** None.

---
*Phase: 04-protocol-expansion*
*Plan: 04*
*Completed: 2026-05-12*
