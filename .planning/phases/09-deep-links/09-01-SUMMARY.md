---
phase: 09-deep-links
plan: 01
subsystem: deep-links
tags:
  - deep-links
  - swiftpm-package
  - actor
  - scope-amendment
  - phase-9-wave-1
status: complete
completed: 2026-05-15
requirements:
  - DEEP-01
  - DEEP-02
  - DEEP-05
requirements_deferred:
  - DEEP-03  # v1+ backlog per D-01..D-03 (token endpoint)
  - DEEP-04  # v1+ backlog per D-01..D-03 (landing page)
dependency_graph:
  requires:
    - VPNCore (ImportSource enum host)
    - ConfigParser (Wave 2 dependency, wired now to avoid Package.swift touch later)
  provides:
    - DeepLinks SwiftPM package (Router actor + Handler protocol + Error enum + Logger + TokenFetcher placeholder)
    - ImportSource.deepLink case
    - Phase 9 scope amendment (REQUIREMENTS + ROADMAP)
  affects:
    - Wave 2 (ImportHandler concrete) — consumes DeepLinkHandler + DeepLinkError + ConfigImporting
    - Wave 3 (App-wiring) — instantiates DeepLinkRouter in BBTB_iOSApp + BBTB_macOSApp
    - Wave 4 (AASA + UAT) — exercises full pipeline on device
tech_stack:
  added:
    - swift-tools-version 6.0 (existing; new package adopts)
    - os.signpost (existing pattern; DEC-06d-06 conformance)
  patterns:
    - Actor coordinator + extensible handler registry (mirror RulesEngineCoordinator + ProtocolRegistry)
    - PerfSignposter local enum for Instruments unified-view (DEC-06d-06)
    - Inline RU error strings as Wave 1 fallback (Wave 2 swaps to L10n keys)
key_files:
  created:
    - BBTB/Packages/DeepLinks/Package.swift
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkHandler.swift
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinksLogger.swift
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/TokenFetcher.swift
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift
    - BBTB/Packages/DeepLinks/Tests/DeepLinksTests/DeepLinkRouterTests.swift
  modified:
    - BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift (+2 lines — ImportSource.deepLink case)
    - .planning/REQUIREMENTS.md (DEEP-03/04 strikethrough + new Last-updated footer)
decisions:
  - D-01..D-03 scope amendment formalized (carve-out of DEEP-03/04 to v1+)
  - Linker settings deviation (Rule 3 — added testTarget linkerSettings for Libbox transitive symbols)
metrics:
  duration: ~30 minutes
  task_count: 3
  files_created: 7
  files_modified: 2
  tests_added: 3
  tests_passing: 3
---

# Phase 09 Plan 01: DeepLinks SwiftPM скелет + ImportSource.deepLink + Scope amendment — Summary

**One-liner:** Заложен SwiftPM пакет `DeepLinks` (Router actor + Handler protocol + Error enum + Logger + TokenFetcher placeholder), добавлен `ImportSource.deepLink` case в VPNCore, и зафиксирована Phase 9 scope amendment (DEEP-03/04 → v1+ backlog) в REQUIREMENTS.md.

## Tasks executed

| # | Name | Commit | Status |
|---|------|--------|--------|
| 1.1 | Scope amendment в REQUIREMENTS.md (+ ROADMAP.md already updated by planner) | `2c8c61b` | ✓ done |
| 1.2 | `ImportSource.deepLink` case + Pitfall #3 grep-audit | `bcb5be7` | ✓ done |
| 1.3 | DeepLinks SwiftPM package skeleton + 3 unit tests | `06f5df7` | ✓ done |

## Files

### Created (7)

1. `BBTB/Packages/DeepLinks/Package.swift` — swift-tools 6.0, iOS 18 / macOS 15, deps: VPNCore + ConfigParser; testTarget с linkerSettings (Libbox transitive).
2. `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkHandler.swift` — `public protocol DeepLinkHandler: Sendable` + `static var identifier: String` + `canHandle(_:)` + `handle(_:) async throws`.
3. `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift` — 5-case enum (`.unhandled`, `.missingQueryParameter`, `.invalidParameterValue`, `.importFailed`, `.notImplemented`) с Equatable + LocalizedError + Sendable.
4. `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinksLogger.swift` — OSLog wrapper (router/importer/token categories, `app.bbtb.client` subsystem).
5. `BBTB/Packages/DeepLinks/Sources/DeepLinks/TokenFetcher.swift` — placeholder protocol для v1+ DEEP-03 token-fetch flow (no conformers in v0.9).
6. `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift` — `public actor DeepLinkRouter` + `register` + `handle` с PerfSignposter span (DEC-06d-06).
7. `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/DeepLinkRouterTests.swift` — 3 unit tests + FakeHandler/HandleRecorder fixtures.

### Modified (2)

- `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift` — добавлен `case deepLink` в `ImportSource` (+ doc-comment).
- `.planning/REQUIREMENTS.md` — DEEP-03 + DEEP-04 strikethrough'd как Out of Scope v0.9 с rationale link на 09-CONTEXT.md D-01..D-03; новый `Last updated: 2026-05-15 — Phase 9 W1 scope amendment` footer line; предыдущий Phase 8 footer сохранён как history.

## Tests

3 unit tests (XCTest) — все PASS в 0.003 сек:

| # | Test | Что покрывает |
|---|------|--------------|
| 1 | `test_handle_dispatchesToFirstMatchingHandler` | Register 2 handlers, только second matches → second invoked exactly once |
| 2 | `test_handle_throwsUnhandledWhenNoHandlerMatches` | No handler matches → `DeepLinkError.unhandled(url:)` thrown |
| 3 | `test_handle_registrationOrderMatters_firstMatchWins` | Both handlers match → first registered wins (order semantics) |

```
Executed 3 tests, with 0 failures (0 unexpected) in 0.003 seconds
```

## Scope amendment diff snippet

```diff
- - [ ] **DEEP-03**: Endpoint `https://import.bbtb.app/c/{token}` на VPS отдаёт конфиг
- - [ ] **DEEP-04**: Landing page для тех, у кого приложение не установлено — отправляет на TestFlight invite
+ - [ ] ~~**DEEP-03**: Endpoint `https://import.bbtb.app/c/{token}` на VPS отдаёт конфиг~~ → **Out of Scope v0.9** _(Phase 9 scope amendment 2026-05-15 per D-01..D-03. Архитектурная заглушка `TokenFetcher` protocol реализована в `BBTB/Packages/DeepLinks` для v1+ регенерации. См. `wiki/deep-links.md` после полного обновления в W4.)_
+ - [ ] ~~**DEEP-04**: Landing page для тех, у кого приложение не установлено — отправляет на TestFlight invite~~ → **Out of Scope v0.9** _(Phase 9 scope amendment 2026-05-15 per D-01..D-03. Default browser behavior (Safari 404) accepted; landing page возвращается в v1+ вместе с DEEP-03 token endpoint. См. `wiki/deep-links.md` после полного обновления в W4.)_
```

ROADMAP.md amendment block (`Scope amendment (2026-05-15 in /gsd-discuss-phase 9): ...`) + 4-plan list уже были вставлены planner'ом в /gsd-plan-phase 9, поэтому Task 1.1 не редактировал ROADMAP.md (повторное добавление было бы duplicate). Grep gates это подтверждают:

```
$ grep -c 'Scope amendment.*2026-05-15.*/gsd-discuss-phase 9' .planning/ROADMAP.md
1
$ grep -c '09-01-PLAN.md\|09-02-PLAN.md\|09-03-PLAN.md\|09-04-PLAN.md' .planning/ROADMAP.md
4
```

## Switch-exhaustiveness audit (Pitfall #3)

Three switch-related sites found by grep on `ImportSource` cases:

| Site | Verdict | Reason |
|------|---------|--------|
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:64` | NO CHANGE (false positive) | Switch is over local `InputClass` enum (private к UniversalImportParser), не `ImportSource`. |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:679` | NO CHANGE | `switch source` over `ImportSource` с `default:` branch — `.deepLink` absorbs в `default → importFromPasteboard`. Поведение в Wave 1 acceptable: реальный routing для `.deepLink` будет в Wave 2 через `ImportHandler` → `ConfigImporter.importFromRawInput(_:source: .deepLink)`, минуя `performImport`. |
| `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/UniversalImportParserTests.swift:166` | NO CHANGE | Single-case `if case .subscriptionURL = ...` extraction, не exhaustive switch. |

Final grep gate (must be 0 lines):

```
$ grep -rn 'switch.*ImportSource' BBTB/Packages/ | grep -v '.build/' | grep -v 'default:' | grep -v 'case .deepLink'
(no output — 0 lines)
```

## Plan-level verification gates (all PASS)

| # | Gate | Result |
|---|------|--------|
| 1 | `swift build --package-path Packages/VPNCore` | EXIT 0 (Build complete!) |
| 2 | `swift build --package-path Packages/ConfigParser` | EXIT 0 (Build complete!) |
| 3 | `swift build --package-path Packages/AppFeatures` | EXIT 0 (Build complete!) |
| 4 | `swift test --package-path Packages/DeepLinks` | EXIT 0 — 3/3 tests passed |
| 5 | grep gate: full switch over ImportSource без default/.deepLink | 0 lines |
| 6 | `grep -E "DEEP-03.*Out of Scope.*v0.9" .planning/REQUIREMENTS.md` | 1 match |
| 7 | `grep -E "Plans:.*4 plans" .planning/ROADMAP.md` | 1 match |

## Threat model coverage (Phase 9 W1)

Все 8 STRIDE threats T-09-01..T-09-08 из plan покрыты:

| Threat ID | Disposition | Where mitigated |
|-----------|-------------|-----------------|
| T-09-01 Spoofing — register API | accept | Internal-process surface; no cross-process spoofing в Wave 1. |
| T-09-02 Tampering — handle URL | mitigate | `URL` constructed by Foundation; actor isolation guards `handlers` array. |
| T-09-03 Repudiation | accept | OSLog notice/error levels for audit if needed. |
| T-09-04 Information Disclosure — logger | mitigate | Wave 1 logs только test fake URLs; production URL bodies — Wave 2 ImportHandler с `privacy: .private`. |
| T-09-05 DoS — handlers array | accept | Bounded by static registration count (≤ 2 в v1+). |
| T-09-06 EoP — error enum | mitigate | LocalizedError + Equatable + Sendable; inline RU strings без format-string injection surface. |
| T-09-07 Tampering — ImportSource.deepLink | mitigate | Pitfall #3 grep gate enforces no silent-fallthrough; new case requires recompile. |
| T-09-08 Information Disclosure — TokenFetcher | mitigate | Zero conformers in v0.9; doc-comment explicitly notes "no implementations in Phase 9". |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] testTarget linker symbols missing for Libbox transitive**

- **Found during:** Task 1.3 (`swift test --package-path Packages/DeepLinks`)
- **Issue:** Plan заявил «NO `linkerSettings:` block в testTarget (DeepLinks не тянет libbox через зависимости)». На самом деле DeepLinks target имеет dependency `ConfigParser`, которое транзитивно тянет `PoolBuilder` → `PacketTunnelKit` → `SingBoxBridge` → `libbox.xcframework`. Linker отказывался слинковать `DeepLinksPackageTests` с `_kSCPropNetProxies*` / `_res_9_*` symbols.
- **Fix:** Скопирован linkerSettings block из `BBTB/Packages/RulesEngine/Package.swift` (resolv + bsm + SystemConfiguration + AppKit/UIKit conditionals).
- **Files modified:** `BBTB/Packages/DeepLinks/Package.swift`
- **Commit:** `06f5df7` (same Task 1.3 commit; deviation explained в commit body).

**2. [Infrastructure workaround] libbox.xcframework symlink в worktree**

- **Found during:** Task 1.2 (initial build attempt)
- **Issue:** `BBTB/Vendored/libbox.xcframework/` отсутствует в git worktree (per R8 — local binary target, .gitignored). Worktree spawn'ится с пустым `Vendored/`, поэтому `swift build` падает с «local binary target 'Libbox' does not contain a binary artifact».
- **Fix:** Создан symlink из main repo `libbox.xcframework` в worktree `Vendored/` дирректорию. Symlink **не зафиксирован** в git (защищён `.gitignore` правилом для `libbox.xcframework`).
- **Why this is safe:** Это inherited R8 build-time constraint для всех Phase 1+ work — local binary targets не транслируются между worktrees. Workaround стандартный.

### ROADMAP scope amendment не редактировался Task 1.1

Plan Task 1.1 требовал добавления scope amendment block + Plans list в `.planning/ROADMAP.md`. **Обе вещи уже были вставлены planner'ом** во время `/gsd-plan-phase 9` (см. plan-level frontmatter `last_updated: 2026-05-15`). Грэп gates это подтвердили (line 370 ROADMAP содержит amendment block, lines 381-391 — Plans list). Task 1.1 ограничился REQUIREMENTS.md edit'ами + footer. Это не deviation в смысле functionality — это observation that planner already did half of Task 1.1 work.

## Codex Consultation Gap (carry-forward)

Plan Task 1.3 явно отметил:

> Codex MCP consultation for `protocol DeepLinkHandler` Swift 6 strict-concurrency signature was NOT possible in this planning session (mcp__codex__codex prompt file `~/.claude/prompts/architect.md` not found on this machine).

Я выполнил Task 1.3 with the same gap. Signature follows codebase canonical pattern:
- `Sendable` constraint mirrors `RulesEngineCoordinator` (closed Phase 8 — confirmed working under Swift 6 strict concurrency).
- `static var identifier: String { get }` mirrors `VPNProtocolHandler` (in `BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift`) static identifier pattern.
- `func handle(_:) async throws` стандартный async-throws pattern Phase 1+.

**Follow-up:** если Codex consultation в Wave 2 предложит отличие — открыть Phase 9 backlog issue. Не блокер для Wave 1 closure.

## Self-Check

Files claimed in Summary all exist:

- `BBTB/Packages/DeepLinks/Package.swift` — FOUND
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkHandler.swift` — FOUND
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift` — FOUND
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinksLogger.swift` — FOUND
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/TokenFetcher.swift` — FOUND
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift` — FOUND
- `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/DeepLinkRouterTests.swift` — FOUND

Commits claimed all reachable:

- `2c8c61b` — FOUND (`docs(09-01): Phase 9 scope amendment — DEEP-03/04 carved to v1+ backlog`)
- `bcb5be7` — FOUND (`feat(09-01): add ImportSource.deepLink case (DEEP-01 client routing)`)
- `06f5df7` — FOUND (`feat(09-01): create DeepLinks SwiftPM package skeleton (DEEP-05)`)

## Self-Check: PASSED

---

**Next:** Wave 2 (09-02-PLAN.md) — concrete `ImportHandler` + `RemoteTokenFetchHandler` stub + URL parsing tests + L10n keys.
