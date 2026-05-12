---
phase: 04-protocol-expansion
plan: 01
subsystem: testing
tags: [swift-package-manager, yams, xctest, scaffold, vless-tls, shadowsocks, hysteria2, clash-yaml, red-gate]

# Dependency graph
requires:
  - phase: 02-trojan-import-flow
    provides: "ParsedTrojan + AnyParsedConfig pattern (vlessReality, trojan cases)"
  - phase: 01-foundation
    provides: "ParsedVLESS + VLESSURIParser (Reality branch) + ImportedServer enum"
provides:
  - "AnyParsedConfig enum расширен на 5 case'ов (+ vlessTLS, shadowsocks, hysteria2)"
  - "ParsedVLESSTLS, ParsedShadowsocks, ParsedHysteria2 structs (D-03/D-05/D-07)"
  - "UnsupportedReason расширен: schemaUnsupportedInPhase4, unsupportedSSMethod, multiPortNotSupported"
  - "Yams 6.2.1 SPM dependency для Clash YAML (Plan 04-05)"
  - "StubParsers.supportedSchemesInPhase4 = {vless, trojan, ss, hy2, hysteria2}"
  - "4 test scaffold классов с XCTFail placeholders (RED gate для Wave 1+)"
  - "10 test fixture файлов (SS-2022/legacy/Outline, Hy2 obfs/insecure/multi-port, VLESS-TLS no-flow/vision, Clash mixed)"
affects: [04-02, 04-03, 04-04, 04-05, 04-06]

# Tech tracking
tech-stack:
  added: [Yams 6.2.1 (jpsim/Yams, MIT)]
  patterns:
    - "Wave 0 Nyquist gate: создать failing-test scaffolds ДО implementation чтобы RED→GREEN cycle работал"
    - "Sum-type расширение enum'ов с downstream skip-pattern (PoolBuilder.continue) и exhaustive identity-string"
    - "Fictional fixture credentials (T-04-W0-03 mitigation) — example.com/vpn.test/selfsigned.test hosts"

key-files:
  created:
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/ShadowsocksURIParserTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Hysteria2URIParserTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/ClashYAMLParserTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/ss-2022-aes-128-gcm.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/ss-2022-percent-encoded.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/ss-legacy-chacha20.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/outline-access-key.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/hy2-with-obfs.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/hy2-insecure.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/hy2-multi-port.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-no-flow.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-vision.txt"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/clash-mixed-proxies.yaml"
  modified:
    - "BBTB/Packages/ConfigParser/Package.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift"

key-decisions:
  - "Yams pinned to from: \"6.2.1\" (semver-major lock; jpsim/Yams MIT — T-04-W0-01 mitigation)"
  - "AnyParsedConfig — public Swift enum БЕЗ @unknown default; добавление case'ов триггерит compile-error в downstream switches (intentional Pitfall 7 enforcement)"
  - "PoolBuilder.swift скипает (continue) vlessTLS/shadowsocks/hysteria2 в Wave 0 — builders реализуются в Plan 04-02/03/04"
  - "SubscriptionMergeService.identity() — exhaustive switch по всем 5 case'ам уже в Wave 0 (identity string нужен для merge даже до builder реализации)"
  - "ParsedVLESSTLS.flow: String? (nil != \"\") — отличает 'flow отсутствует в URI' от 'flow=\"\"' (per Phase 1 W5 lesson)"
  - "supportedSchemesInPhase2 НЕ удалена — backward compat для StubParsersTests (per acceptance criteria)"

patterns-established:
  - "Pattern: Wave 0 RED scaffold — каждый test файл копирует loadFixture helper из TrojanURIParserTests + XCTFail placeholder с указанием в каком Plan становится GREEN. Тест файл компилируется без ссылок на несуществующие parser типы."
  - "Pattern: fictional fixture credentials — все hostnames/UUID/passwords синтетические (example.com, vpn.test, *.example.com), credentials длинной b64-style для реалистичности но не настоящие. Защита от T-04-W0-03."
  - "Pattern: enum exhaustivity downstream — все existing switches на AnyParsedConfig обновляются в Wave 0 (хотя бы как skip/continue), чтобы build не падал и Wave 1+ могли стартовать."

requirements-completed: [PROTO-03, PROTO-04, PROTO-05, IMP-04, IMP-05]

# Metrics
duration: ~17min
completed: 2026-05-12
---

# Phase 4 Plan 01: Foundation Scaffold (Wave 0) Summary

**Wave 0 Nyquist gate для Phase 4 — расширение `AnyParsedConfig` enum на 5 case'ов, добавление Yams 6.2.1 SPM dependency, создание 4 RED-test scaffold классов с 19 failing placeholders и 10 test fixture файлов для всех Wave 1+ scenarios (SS-2022/legacy, Hysteria2 D-08/D-09, VLESS+TLS, Clash YAML mixed pool).**

## Performance

- **Duration:** ~17 min
- **Started:** 2026-05-12T16:26:00Z (approx)
- **Completed:** 2026-05-12T16:43:32Z
- **Tasks:** 3
- **Files modified:** 5
- **Files created:** 14 (4 test файла + 10 fixture)

## Accomplishments

- **AnyParsedConfig** теперь 5 case'ов (добавлены `vlessTLS`, `shadowsocks`, `hysteria2`) с тремя новыми `Parsed*` structs (D-03 / D-05 / D-07).
- **Yams 6.2.1** SPM dependency добавлена и резолвится (`swift package resolve` + `swift build` зелёные на ConfigParser package).
- **4 test scaffold класса** созданы (`ShadowsocksURIParserTests`, `Hysteria2URIParserTests`, `ClashYAMLParserTests`, `VLESSURIParserTLSTests`) с 19 XCTFail-placeholders — `swift test --filter` даёт **19 failures, 0 unexpected** (RED gate работает).
- **30/30 существующих тестов** (TrojanURIParserTests, VLESSURIParserTests, StubParsersTests) проходят без регрессий после расширения enum.
- **10 fixture файлов** покрывают все Wave 0 scenarios: SS-2022 base64/percent, SS legacy, Outline access key, Hy2 obfs/insecure/multi-port, VLESS+TLS no-flow/vision, Clash YAML с 6 proxy типами.
- **StubParsers.supportedSchemesInPhase4** определена; `supportedSchemesInPhase2` сохранена для backward compat.

## Task Commits

Each task was committed atomically:

1. **Task 1: Yams 6.2.1 + AnyParsedConfig + Parsed* structs + UnsupportedReason** — `0ffa7ac` (feat)
2. **Task 2: 10 Wave 0 test fixtures** — `5a22e43` (test)
3. **Task 3: 4 Wave 0 test scaffolds (RED stubs)** — `8bd91c4` (test)

## Files Created/Modified

### Modified

- `BBTB/Packages/ConfigParser/Package.swift` — Yams 6.2.1 dependency + product wiring в ConfigParser target.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift` — `AnyParsedConfig` 5 case'ов, `ParsedVLESSTLS` / `ParsedShadowsocks` / `ParsedHysteria2` structs, `UnsupportedReason` +3 case'а.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift` — `supportedSchemesInPhase4` константа.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — добавлен `case .vlessTLS, .shadowsocks, .hysteria2: continue` для exhaustivity (builder'ы — Plan 04-02/03/04).
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift` — exhaustive switch для SNI update + identity-string (включая `vless-tls`, `shadowsocks`, `hysteria2` ids).

### Created (tests)

- `Tests/ConfigParserTests/ShadowsocksURIParserTests.swift` — 6 XCTFail stubs (Plan 04-03 GREEN).
- `Tests/ConfigParserTests/Hysteria2URIParserTests.swift` — 5 XCTFail stubs (Plan 04-04 GREEN).
- `Tests/ConfigParserTests/ClashYAMLParserTests.swift` — 4 XCTFail stubs (Plan 04-05 GREEN).
- `Tests/ConfigParserTests/VLESSURIParserTLSTests.swift` — 4 XCTFail stubs (Plan 04-02 GREEN).

### Created (fixtures)

10 files в `Tests/ConfigParserTests/Fixtures/`:
- `ss-2022-aes-128-gcm.txt`, `ss-2022-percent-encoded.txt`, `ss-legacy-chacha20.txt`, `outline-access-key.txt` (SIP002 + SIP022)
- `hy2-with-obfs.txt`, `hy2-insecure.txt`, `hy2-multi-port.txt`
- `vless-tls-no-flow.txt`, `vless-tls-vision.txt`
- `clash-mixed-proxies.yaml` — 6 proxies (ss-2022, trojan, hysteria2 skip-cert-verify, vmess unsupported, vless+reality-opts, vless+TLS)

## Decisions Made

- **Yams `from: "6.2.1"`** — semver-major lock per 04-RESEARCH.md Security Domain (jpsim 1.2k stars, MIT, 5+ лет).
- **`ParsedVLESSTLS.flow: String?`** (а не `String`) — nil отличает «flow отсутствует в URI» от пустой строки. Соответствует Phase 1 W5 lesson о `flow` placeholder в template.
- **Symbolic links в worktree для libbox.xcframework** — не закоммичены; были созданы только для локальной верификации `swift build` (xcframework binary живёт только в main repo). Plan не вписан в workflow — это инфраструктурный workaround для validation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Exhaustive switch errors в существующих downstream'ах после расширения AnyParsedConfig**

- **Found during:** Task 1 (`swift build` verification step).
- **Issue:** Добавление трёх новых case'ов в `AnyParsedConfig` сломало compilation в двух файлах (Pitfall 7 enforcement — Swift compiler требует exhaustive switch для public enum'а нашего пакета):
  - `PoolBuilder.swift:42` — switch только `vlessReality` / `trojan`.
  - `SubscriptionMergeService.swift:94, 137` — два switches по `parsed`.
- **Fix:**
  - `PoolBuilder.swift` — добавлен `case .vlessTLS, .shadowsocks, .hysteria2: continue` (builder'ы будут реализованы в Plan 04-02/03/04; Wave 0 PoolBuilder продолжает работать с Phase 1/2 типами).
  - `SubscriptionMergeService.swift` — exhaustive switch для SNI update (`vlessTLS`/`hysteria2` ставят `row.sni`; `shadowsocks` — `break`, нет SNI) и для identity-string (`vless-tls`, `shadowsocks`, `hysteria2` идентификаторы).
- **Files modified:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift`, `SubscriptionMergeService.swift`.
- **Verification:** `swift build` (ConfigParser package) exits 0 после fix; `swift test --filter "TrojanURIParserTests|VLESSURIParserTests|StubParsersTests"` — 30/30 pass.
- **Committed in:** `0ffa7ac` (часть Task 1 commit).

**2. [Rule 3 — Blocking] Libbox xcframework отсутствует в worktree (verification-only workaround)**

- **Found during:** Task 1 (`swift package resolve`).
- **Issue:** `BBTB/Vendored/libbox.xcframework` — local binary target Package.swift'а PacketTunnelKit'а, который ConfigParser test target использует. В git worktree binary артефакт не подтянут (только в main repo).
- **Fix:** Локально создан симлинк `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework` ТОЛЬКО на время `swift build`/`swift test` verification. Симлинк удалён до коммита.
- **Files modified:** None (symlink ephemeral, не закоммичен).
- **Verification:** `swift test` (с симлинком) — Wave 0 19 failures + 30 existing pass; коммиты выполнены БЕЗ симлинка.
- **Committed in:** N/A — симлинк намеренно не в репо.

---

**Total deviations:** 2 auto-fixed (оба Rule 3 — blocking).
**Impact on plan:** Обе автокоррекции необходимы для прохождения Wave 0 build/test verification. Скоупа не было нарушено — downstream switches в PoolBuilder/SubscriptionMergeService будут полноценно реализованы в Plan 04-02/03/04 (builders) и Plan 04-06 (integration).

## Issues Encountered

- None в рамках planned work. Compile-errors из-за exhaustive switch'ей — это ожидаемое поведение Swift (Pitfall 7 mitigation), правка тривиальна.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| (none) | — | No new security surface introduced — Wave 0 — scaffold-only. Yams 6.2.1 dependency mitigation tracked в threat register (T-04-W0-01). |

## TDD Gate Compliance

План маркирован `type: execute` (не `tdd`) — RED→GREEN цикл будет применён в Plan 04-02/03/04/05 (Wave 1+). Этот план КАК ЦЕЛОЕ — Wave 0 RED-фаза для Phase 4: создан failing scaffold, который Wave 1+ заполнит реальными assertions. RED gate verified: `swift test --filter "Shadowsocks|Hysteria2|ClashYAML|VLESSURIParserTLS"` → 19 failures, 0 unexpected.

## Next Phase Readiness

Готово для следующего wave (параллельных Plan'ов 04-02 / 04-03 / 04-04 / 04-05):
- `AnyParsedConfig` enum расширен — последующие planы могут сразу строить `case .vlessTLS(...)` / `.shadowsocks(...)` / `.hysteria2(...)` без дополнительной enum-модификации.
- Yams 6.2.1 уже доступен в ConfigParser target (Plan 04-05 импортирует `import Yams` сразу).
- Все fixtures на месте — Plan 04-02..05 GREEN-фазы используют `loadFixture(...)` напрямую.
- 19 failing tests — RED gate для Wave 1+ выполнен.

**Blockers:** None.

## Self-Check: PASSED

- All 14 created files exist (verified via `git log --stat HEAD~3..HEAD`).
- 5 modified files reflected (git log).
- 3 commits exist on worktree branch: `0ffa7ac`, `5a22e43`, `8bd91c4`.
- Acceptance criteria verified for each task (Yams resolved, ImportedServer literals present, fixtures non-empty + YAML parses + ≥6 proxies, test classes compile + RED gate produces 19 failures with 0 unexpected, 30 existing pass).

---
*Phase: 04-protocol-expansion*
*Plan: 01*
*Completed: 2026-05-12*
