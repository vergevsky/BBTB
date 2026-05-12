---
phase: 04-protocol-expansion
plan: 02
subsystem: protocols
tags: [vless-tls, parser, pool-builder, sing-box, r1-invariant, breaking-change, tdd]

# Dependency graph
requires:
  - phase: 04-protocol-expansion
    plan: 01
    provides: "AnyParsedConfig.vlessTLS case + ParsedVLESSTLS struct (D-03)"
  - phase: 01-foundation
    provides: "ParsedVLESS + VLESSURIParser (Reality branch) + VLESSURIError"
provides:
  - "VLESSURIParser.parse(_:) throws -> AnyParsedConfig (BREAKING CHANGE сигнатуры)"
  - "VLESSURIError.unsupportedSecurity(String) — новый error case для security=none/missing/other"
  - "Protocols/VLESSTLS SPM package (handler + ConfigBuilder + sing-box JSON template)"
  - "PoolBuilder.buildVLESSTLSOutbound с R1 invariant (insecure: false hardcoded)"
  - "D-02 двойная ветка Reality precedence (Pitfall 3) → TLS branch → throw"
affects: [04-03, 04-04, 04-05, 04-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "VLESS+TLS sing-box JSON template — копия vless-reality template минус reality block с insecure: false hardcoded (R1)"
    - "ParsedVLESSTLS.flow: String? — nil ≠ \"\" (Phase 1 W5 lesson); template получает \"\" если nil"
    - "VLESSTLSHandler паттерн зеркалит TrojanHandler — identifier vless-tls + displayName \"VLESS + TLS\""

key-files:
  created:
    - "BBTB/Packages/Protocols/VLESSTLS/Package.swift"
    - "BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift"
    - "BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift"
    - "BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/Resources/SingBoxConfigTemplate.vless-tls.json"
    - "BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/ConfigBuilderTests.swift"
  modified:
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift"

key-decisions:
  - "VLESSURIParser.parse сигнатура: throws -> AnyParsedConfig (breaking change со старой ParsedVLESS — callers распаковывают через guard case let)"
  - "Reality precedence — pbk OR security=reality проверяется ДО security=tls (Pitfall 3 mitigation)"
  - "Empty pbk (`pbk=`) НЕ считается Reality маркером (только non-empty value триггерит Reality branch)"
  - "VLESS+TLS НЕ имеет D-08 exception — insecure: false hardcoded в template + PoolBuilder + не читается из ParsedVLESSTLS"
  - "VLESSTLSHandler identifier = \"vless-tls\" (matches AnyParsedConfig.vlessTLS case, lowercase консистентно с trojan/vless-reality)"

requirements-completed: [PROTO-03]

# Metrics
duration: ~8min
completed: 2026-05-12
---

# Phase 4 Plan 02: VLESS+TLS Vertical Slice Summary

**VLESS+TLS (без Reality) vertical slice — `VLESSURIParser.parse` теперь возвращает `AnyParsedConfig` с двойной веткой Reality precedence (Pitfall 3) → TLS branch (vlessTLS) → throw `.unsupportedSecurity`; новый SPM package `Protocols/VLESSTLS` с handler + ConfigBuilder + sing-box JSON template (без Reality block, R1 invariant `insecure: false` hardcoded); `PoolBuilder.buildVLESSTLSOutbound` интегрирован в pool с R1 strict TLS.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-12T16:47:04Z
- **Completed:** 2026-05-12T16:55:49Z
- **Tasks:** 3 (все автономно, без checkpoints)
- **Files modified:** 6
- **Files created:** 5

## Accomplishments

- **PROTO-03 (VLESS+TLS без Reality)** — vertical slice реализован: URI с `?security=tls` без Reality маркеров парсится в `.vlessTLS(ParsedVLESSTLS)`, проходит через `PoolBuilder.buildVLESSTLSOutbound`, генерирует валидный sing-box JSON с `type: "vless"` outbound (без reality block) и `tls.insecure: false` (R1).
- **D-02 двойная ветка реализована**: Reality precedence (Pitfall 3) → TLS branch → throw `.unsupportedSecurity`. Reality URI с дополнительным `&security=tls` корректно классифицируется как `.vlessReality` (invariant подтверждён тестом `test_realityWithExtraTLS_returnsReality`).
- **`VLESSURIError.unsupportedSecurity(String)`** — новый error case для `security=none` / missing / other (R1 enforcement в parser-е).
- **`Protocols/VLESSTLS` SPM package** компилируется на iOS 18 / macOS 15; `swift test` PASS (7/7 ConfigBuilderTests, включая R1 self-test через `SingBoxConfigLoader.validate`).
- **Reality regression-free**: все Phase 1 VLESSURIParserTests обновлены на новую сигнатуру (`guard case let .vlessReality(p) = ...`) и проходят (10/10 PASS).
- **9/9 VLESSURIParserTLSTests PASS** (RED→GREEN transition complete — 4 placeholders из Plan 04-01 заменены на 9 полноценных тестов).
- **5 новых PoolBuilderTests PASS** для VLESS+TLS pool path + integration с `SingBoxConfigLoader.validate` (R1 self-test): build valid outbound, Vision flow preserved, nil flow handled, mixed pool с Trojan, custom ALPN preserved.

## Task Commits

Each task committed atomically:

1. **Task 1: VLESSURIParser breaking change + D-02 двойная ветка** — `aee566e` (feat)
2. **Task 2: Protocols/VLESSTLS SPM package** — `19ab4e3` (feat)
3. **Task 3: PoolBuilder.buildVLESSTLSOutbound + case .vlessTLS** — `5a2bebd` (feat)

## Files Created/Modified

### Created (Protocols/VLESSTLS package)

- `BBTB/Packages/Protocols/VLESSTLS/Package.swift` — SPM манифест, library name "VLESSTLS", deps на VPNCore и PacketTunnelKit (path-based), test target linkerSettings (resolv, bsm, SystemConfiguration, AppKit/UIKit), resource process для template JSON.
- `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift` — `VPNProtocolHandler` conformance, `identifier = "vless-tls"`, `displayName = "VLESS + TLS"`, `isAvailable = true`, validate/connect/disconnect/diagnostics stubs (зеркало TrojanHandler).
- `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` — enum с `VLESSTLSInputs` struct (uuid, host, port, flow: String?, sni, fingerprint, alpn, remark) + `BuilderError` (templateLoadFailed, invalidPort, missingUUID, missingSNI) + `buildSingBoxJSON` через template + replacingOccurrences + mutatePort если port != 443.
- `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/Resources/SingBoxConfigTemplate.vless-tls.json` — sing-box config template на основе `vless-reality.json`: outbound type=vless с TLS блоком, БЕЗ reality, `"insecure": false`, ALPN ["h2","http/1.1"], utls fingerprint placeholder, DNS секция с `${DNS_DETOUR}`, route.final="vless-out".
- `BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/ConfigBuilderTests.swift` — 7 тестов: placeholders substituted + R1 self-test, Vision flow set, nil flow handled, custom port mutated, R1 insecure=false invariant, invalid port throws, empty SNI throws.

### Modified

- `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` — сигнатура `parse(_:) throws -> AnyParsedConfig` (breaking change); D-02 двойная ветка: `hasReality = !pbk.isEmpty || security == "reality"` → vlessReality; `security == "tls"` → vlessTLS; иначе throw `.unsupportedSecurity`. Новый case `unsupportedSecurity(String)` в `VLESSURIError`.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — `parseSingleURI` case "vless": результат `VLESSURIParser.parse(trimmed)` используется напрямую в `.supported(... parsed: parsedConfig)` (не оборачивается в `.vlessReality`). Helper `vlessName(from: AnyParsedConfig) -> String` для extraction display name.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — switch parsed дополнен `case .vlessTLS(let v): tag = "vless-tls-\(index)"; outbound = buildVLESSTLSOutbound(parsed: v, tag: tag)`. Новая private static `buildVLESSTLSOutbound(parsed:tag:)` с R1 hardcoded `insecure: false` (комментарий-маркер `R1 invariant — VLESS+TLS strict TLS (no Hy2-style exception)`).
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTests.swift` — все existing Reality tests обновлены: helper `unwrapReality(_:)` через `guard case let .vlessReality(p) = ...`; старый `test_parse_withoutReality_throws` переименован в `test_parse_withoutReality_routesToTLSBranch` (поведение изменилось: throw → vlessTLS); добавлены `&pbk=abc` в Reality URI без Reality маркеров (для backward compat в тестах).
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift` — 4 XCTFail placeholders → 9 GREEN tests (securityTLS_returnsVlessTLS, visionFlow_preserved, noFlow_nilField, realityWithExtraTLS_returnsReality [Pitfall 3], securityReality_returnsReality, securityNone_throws, securityMissing_throws, alpnDefault_whenMissing, emptyPbk_notReality_treatedAsTLS).
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift` — `makeVLESSTLS(...)` factory + 5 новых VLESS+TLS тестов (buildsValidOutbound с R1 self-test, visionFlow_preserved, nilFlow_handled, inPool_withTrojan, customALPN_preserved).

## Decisions Made

- **VLESSURIParser.parse — breaking change сигнатуры** — `throws -> ParsedVLESS` → `throws -> AnyParsedConfig`. Все callers (UniversalImportParser + 10 Phase 1 тестов) обновлены распаковкой через `guard case let .vlessReality(p) = ...`. Не делал deprecation wrapper — внутренний parser, минимум 2 known callers, чисто Swift compile-time enforcement.
- **Empty pbk (`pbk=`) НЕ Reality** — добавил `let pbk = q["pbk"] ?? ""; hasReality = !pbk.isEmpty || ...`. Это решает edge case в subscription данных где провайдеры ставят `pbk=` как placeholder. Закреплено тестом `test_emptyPbk_notReality_treatedAsTLS`.
- **VLESSURIError.unsupportedSecurity(String)** — отдельный case вместо повторного использования `.notRealityProtocol` — семантически точнее для Phase 4 (теперь два non-throw security values: reality + tls; throw случай — всё остальное).
- **`VLESSTLSInputs` не содержит `allowInsecure`** — design-time enforcement R1 invariant. D-08 exception (allowInsecure=true) применяется **только** к Hysteria2; добавление поля в VLESS+TLS Inputs создало бы copy-paste риск (Pitfall 2). Если в будущем понадобится — отдельный решение требует пересмотра R1.
- **PoolBuilder tag prefix `vless-tls-`** (а не `vless-`) — отличает VLESS+TLS от VLESS+Reality outbound в pool. Хорошо читается в логах sing-box и в test assertions.

## Deviations from Plan

### Auto-fixed Issues

**None.** План выполнен ровно как написан. Все 3 задачи закрыты без авто-фиксов или blocking issues.

## Issues Encountered

- В worktree отсутствовал `BBTB/Vendored/libbox.xcframework` (binary не подтянут в git worktree). Создан локальный симлинк на main repo для верификации `swift build`/`swift test`; **не закоммичен** (Plan 04-01 ровно та же ситуация — известный workflow для worktree-based verification).

## Threat Flags

**None** — no new security surface introduced. PROTO-03 расширяет VLESS handler family без новых network endpoints / auth paths / file access. Threat-register `T-04-02-01..06` mitigated через test invariants:

- T-04-02-01 (Spoofing — Reality URI with security=tls): mitigated тестом `test_realityWithExtraTLS_returnsReality` (Pitfall 3 invariant).
- T-04-02-02 (Tampering — security=none downgrade): mitigated через throw `.unsupportedSecurity`, тесты `test_securityNone_throws` + `test_securityMissing_throws`.
- T-04-02-04 (Tampering — insecure=true injection): mitigated R1 invariant hardcoded в template + PoolBuilder; `ParsedVLESSTLS` не содержит `allowInsecure` поля (design-time enforcement); тест `test_insecureIsFalse_R1`.
- T-04-02-03/05/06 (accept): unchanged from threat register.

## TDD Gate Compliance

Plan маркирован `type: execute`, но все 3 задачи имеют `tdd="true"`. RED→GREEN cycle выполнен для каждой задачи:

- **Task 1 RED:** новые тесты VLESSURIParserTLSTests.swift с `case let .vlessTLS(...)` и `VLESSURIError.unsupportedSecurity` — fail на compilation (типы ещё не существуют).
- **Task 1 GREEN:** VLESSURIParser.swift с новой сигнатурой → tests PASS (10 VLESSURIParserTests + 9 VLESSURIParserTLSTests + 11 UniversalImportParserTests, итого 30/30).
- **Task 2 RED:** ConfigBuilderTests.swift с `try ConfigBuilder.buildSingBoxJSON(from: VLESSTLSInputs(...))` — fail на compilation (package ещё не существует).
- **Task 2 GREEN:** Package.swift + handler + builder + template → 7/7 ConfigBuilderTests PASS.
- **Task 3 RED:** PoolBuilderTests.swift с `.vlessTLS(makeVLESSTLS())` — fatal runtime error (PoolBuilder.switch.continue skips vlessTLS, нет outbound для assertion).
- **Task 3 GREEN:** PoolBuilder.swift с case + buildVLESSTLSOutbound → 16/16 PoolBuilderTests PASS, 64/64 в смежных модулях.

Каждая commit пара (test → impl) могла бы быть отдельными commits, но 04-02 PLAN не требует строго гранулированных RED/GREEN commits — combined feat-commits соответствуют success criteria плана.

## Self-Check: PASSED

- All 5 created files exist:
  - `BBTB/Packages/Protocols/VLESSTLS/Package.swift` — verified `git show 19ab4e3:BBTB/Packages/Protocols/VLESSTLS/Package.swift`
  - `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift` — verified
  - `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` — verified
  - `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/Resources/SingBoxConfigTemplate.vless-tls.json` — verified, JSON valid, no `reality` substring, `insecure: false` present
  - `BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/ConfigBuilderTests.swift` — verified
- All 3 commits in git log: `aee566e`, `19ab4e3`, `5a2bebd` (verified via `git log --oneline -3`)
- All success criteria verified:
  - [x] VLESS+TLS URI (vision и без vision) парсится в .vlessTLS — `test_securityTLS_returnsVlessTLS` + `test_visionFlow_preserved` PASS
  - [x] Reality URI продолжает парситься в .vlessReality (Pitfall 3) — `test_realityWithExtraTLS_returnsReality` PASS
  - [x] VLESS-TLS sing-box JSON content проходит SingBoxConfigLoader.validate (R1) — `XCTAssertNoThrow(try SingBoxConfigLoader.validate(...))` в 7 тестах
  - [x] Protocols/VLESSTLS package компилируется и тесты PASS — `swift test --filter VLESSTLSTests` exits 0 (7/7)
  - [x] VLESSURIParserTLSTests все PASS (RED→GREEN transition complete) — 9/9 PASS

---
*Phase: 04-protocol-expansion*
*Plan: 02*
*Completed: 2026-05-12*
