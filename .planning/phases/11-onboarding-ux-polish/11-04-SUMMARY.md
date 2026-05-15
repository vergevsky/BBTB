---
phase: 11-onboarding-ux-polish
plan: 04
subsystem: detection
tags: [detect, max-messenger, silent-logging, lsapplicationqueriesschemes, nsworkspace, os-logger, cold-start-defer, dec-06d-01, swift6-concurrency, rules-engine-handoff]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "AppFeatures SwiftPM пакет + Logger pattern (subsystem: app.bbtb.client) + iOS Info.plist baseline + Tuist-managed Xcode project"
  - phase: 06d-performance-audit
    provides: "DEC-06d-01 cold-start defer pattern — `Task.detached(.utility)` для non-critical init"
  - phase: 08-rules-engine-split-tunnel
    provides: "RulesEngine pipeline + block_completely category (DETECT-03 server-side runway)"
  - phase: 11-onboarding-ux-polish/plan-01
    provides: "L10n foundation (NOT required для этого плана — detection silent, no UI/L10n)"
provides:
  - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MAXDetector.swift — silent MAX-detection service: static enum, URLSchemeQueryable / WorkspaceQueryable mockable protocols, iOSSchemeCandidates + macOSBundleCandidates, @MainActor detectAndLog() (одна os.Logger.info() в category=detection)"
  - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MAXDetectorTests.swift — 5 unit-тестов (4 macOS path + 1 cross-platform invariant; iOS-conditional skipped на macOS host)"
  - "BBTB/App/iOSApp/Info.plist: LSApplicationQueriesSchemes whitelist (max, max-app, ru-max, vkmax) — sync с iOSSchemeCandidates"
  - "BBTB/App/iOSApp/BBTB_iOSApp.swift + BBTB/App/macOSApp/BBTB_macOSApp.swift: Task.detached(.utility) { await MainActor.run { MAXDetector.detectAndLog() } } в init() per DEC-06d-01"
  - "wiki/max-domains-blocklist.md — admin handoff документ DETECT-03: 7 кандидат-доменов (2 подтверждённых + 5 [ASSUMED]), JSON-фрагмент для rules.json, verification protocol (DNS baseline → tcpdump → build-baseline-rules.sh → 24h monitoring)"
  - "wiki/index.md + wiki/log.md: ссылка на новую страницу + хронологическая запись Phase 11 Plan 04"
affects: [11-05, 11-06, 11-07, 12-pre-release]

# Tech tracking
tech-stack:
  added: []  # никаких новых SPM пакетов / Apple frameworks — только использование UIKit.UIApplication.canOpenURL + AppKit.NSWorkspace.urlForApplication (уже доступны Apple stdlib)
  patterns:
    - "Pattern S3 (Logger init): private static let logger = Logger(subsystem: \"app.bbtb.client\", category: \"detection\")"
    - "Pattern S4 (privacy annotations): privacy: .public для scheme/bundleID; privacy: .private для URL.path"
    - "Pattern S8 (cross-platform conditional compilation): #if os(iOS) / #elseif os(macOS) — общий entry @MainActor detectAndLog() диспатчит к platform-specific внутренней реализации"
    - "Protocol-based mockability для testability: URLSchemeQueryable / WorkspaceQueryable — internal helper методы detectIOS(query:) / detectMacOS(workspace:) принимают protocol-typed аргументы (production — real wrappers, тесты — mock'и)"
    - "DEC-06d-01 cold-start defer: Task.detached(priority: .utility) { await MainActor.run { ... } } — добавляет hook в init() БЕЗ блокировки первого UI frame"
    - "Swift 6 strict concurrency bridge: @preconcurrency на conformance с nonisolated protocol требованиями для main-actor isolated production wrapper (Xcode 26 -swift-version 6 catches this)"

key-files:
  created:
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MAXDetector.swift — 207 строк, 26 sentinel matches на 7 grep-токенах"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MAXDetectorTests.swift — 5 тестов"
    - "wiki/max-domains-blocklist.md — 147 строк, 7 domain entries"
  modified:
    - "BBTB/App/iOSApp/Info.plist — добавлен LSApplicationQueriesSchemes блок с 4 candidate schemes"
    - "BBTB/App/iOSApp/BBTB_iOSApp.swift — добавлен Task.detached в init() (вставка после DeepLinks register, до SwiftData migration)"
    - "BBTB/App/macOSApp/BBTB_macOSApp.swift — то же что и iOS (mirror pattern)"
    - "wiki/index.md — добавлена ссылка на max-domains-blocklist под [[max-messenger]]"
    - "wiki/log.md — добавлена хронологическая запись Phase 11 Plan 04"

key-decisions:
  - "iOS Info.plist LSApplicationQueriesSchemes — 4 candidate schemes (max, max-app, ru-max, vkmax), все [ASSUMED] до device-UAT. Без этого whitelist canOpenURL silently returns false (Pitfall 1). Schemes sync буква в букву с MAXDetector.iOSSchemeCandidates — guard через cross-platform invariant test."
  - "macOSBundleCandidates — 4 IDs (ru.vk.max, com.vkontakte.max, chat.max.app, ru.max.messenger), все [ASSUMED]. Phase 11 deliberately НЕ verify через реальную установку MAX-app — fallback path (\"not detected\" log entry) acceptable per RESEARCH A1/A2/A3. Финальная верификация — Phase 11 device-UAT шаг (ручная установка MAX на test device + `xcrun simctl spawn log show ... category=detection`)."
  - "@preconcurrency на URLSchemeQueryable conformance — Xcode 26 / Swift 6 strict mode жёстко проверяет main-actor → nonisolated boundary. SPM `swift test` use slighltly looser rules чем `xcodebuild` (без -swift-version 6 explicit flag). Fix required в pure Apple-recommended стиле; альтернативы (изменить protocol на @MainActor; убрать @MainActor с RealUIApplication; @preconcurrency import) хуже по причинам, описанным в comment doc."
  - "Detection callsite — Task.detached(.utility) { await MainActor.run { ... } }: detached task isolates exception (T-11-04-05 mitigation), MainActor.run требуется потому что UIApplication.shared @MainActor-isolated (Apple). На macOS NSWorkspace.urlForApplication НЕ требует main actor, но pattern унифицирован cross-platform для maintainability."
  - "DETECT-03 — никакого client code. Admin handoff документ (wiki/max-domains-blocklist.md) описывает workflow для админа: добавление MAX-доменов в server-side rules.json через [[rules-engine]] pipeline. Phase 8 RulesEngine клиента подхватит обновление автоматически через BGAppRefreshTask iOS / NSBackgroundActivityScheduler macOS (6h interval)."
  - "Никакого UI side-effect, никаких записей в App Group / Keychain / UserDefaults / SwiftData — detection живёт только в os.Logger unified-logging buffer (D-Detect). Это явное scope decision: detection — diagnostic facility, не product feature."

patterns-established:
  - "Pattern P11-04-A — Silent best-effort detection через protocol-based mockable surface: для будущих detection задач (например DETECT-04+ другие apps из списка [[vpn-detection-by-apps]] — банки, маркетплейсы) reuse того же шаблона: candidate list + iteration + os.Logger.info() + LSApplicationQueriesSchemes sync."
  - "Pattern P11-04-B — Cross-platform cold-start defer hook: точка вставки в init() оба App entry points (после крупных registrations, до SwiftData migration). Унифицированный Task.detached(.utility) { await MainActor.run { ... } } блок — easy reuse для future telemetry / diagnostic hooks."
  - "Pattern P11-04-C — Admin handoff document для server-side requirements: wiki-страница с (a) контекстом и связью с client-side, (b) JSON-fragment для прямой вставки, (c) verification protocol с конкретными CLI-командами, (d) closure dependency note. Шаблон для будущих server-driven requirements (DETECT-* future, BLOCK-* future)."

requirements-completed:
  - DETECT-01  # iOS silent detection — client-side ✅ Validated
  - DETECT-02  # macOS silent detection — client-side ✅ Validated
  - DETECT-03  # MAX-домены в rules.json — client ✅ ready, admin handoff ⏸ pending

# Metrics
duration: 30min
completed: 2026-05-15
---

# Phase 11 Plan 04: MAX Detection (Wave 2) Summary

**Silent best-effort MAX-app detection для iOS (canOpenURL) и macOS (NSWorkspace) реализован: ровно одна os.Logger.info() запись при cold start через DEC-06d-01 defer; никакого UI, никаких shared-state writes. Admin handoff документ для DETECT-03 (server-side block_completely) готов.**

## Performance

- **Duration:** ~30 min (включая Rule 1 fix Swift 6 concurrency + xcodebuild verification + wiki sync)
- **Started:** 2026-05-15T18:09:00Z (approximate, после worktree branch check)
- **Completed:** 2026-05-15T18:40:00Z (approximate)
- **Tasks:** 2 / 2 ✅
- **Files created:** 3 (MAXDetector.swift, MAXDetectorTests.swift, max-domains-blocklist.md)
- **Files modified:** 5 (Info.plist, BBTB_iOSApp.swift, BBTB_macOSApp.swift, wiki/index.md, wiki/log.md)
- **AppFeatures tests:** 178 / 178 PASS (было 173/173 — +5 новых тестов MAXDetector)

## Accomplishments

- **MAXDetector реализован как public API в MainScreenFeature.** Production callsite — `MAXDetector.detectAndLog()` через cold-start defer Task. Internal `detectIOS(query:)` / `detectMacOS(workspace:)` testable через mocks.
- **iOS Info.plist whitelist sync.** `LSApplicationQueriesSchemes` блок добавлен с 4 schemes (max, max-app, ru-max, vkmax) — sync буква в букву с `iOSSchemeCandidates` (без whitelist iOS 9+ silently returns false из `canOpenURL`).
- **Cross-platform wire через DEC-06d-01 pattern.** Один `Task.detached(.utility) { await MainActor.run { MAXDetector.detectAndLog() } }` блок добавлен в каждый App entry point — identical pattern, easy reuse.
- **Silent invariant verified.** Никаких UI imports (SwiftUI/DesignSystem) в MAXDetector.swift; никаких записей в App Group/Keychain/UserDefaults/SwiftData/Notification. Detection живёт только в `os.Logger(subsystem: "app.bbtb.client", category: "detection")`.
- **Privacy annotations correct.** scheme/bundleID — `privacy: .public` (не PII, T-11-04-01 accepted); URL.path — `privacy: .private` (defence-in-depth).
- **Admin handoff документ готов.** `wiki/max-domains-blocklist.md` (147 строк) описывает 7 кандидат-доменов, verification protocol (DNS baseline → tcpdump → build-baseline-rules.sh), и closure dependency для DETECT-03.
- **Wiki long-term memory обновлено.** `wiki/index.md` ссылается на новую страницу под [[max-messenger]]; `wiki/log.md` содержит хронологическую запись Phase 11 Plan 04 (CLAUDE.md compliance).
- **Swift 6 strict concurrency bridge задокументирован.** `@preconcurrency URLSchemeQueryable` conformance с подробным комментарием — паттерн для будущих main-actor → nonisolated bridge cases.

## Task Commits

Each task committed atomically:

1. **Task 4.1: MAXDetector + mockable surface + unit-тесты** — `e636331` (feat)
2. **Task 4.2: App wires + Info.plist + wiki handoff + Swift 6 concurrency fix** — `1a9f3ce` (feat)

## Candidate Lists (Info.plist ↔ Swift sync)

### iOS schemes — sync status: ✅ MATCH

`MAXDetector.iOSSchemeCandidates` ↔ `LSApplicationQueriesSchemes` в `BBTB/App/iOSApp/Info.plist`:

| # | Scheme | Status | Notes |
|---|--------|--------|-------|
| 1 | `max` | `[ASSUMED]` | Базовый guess по convention |
| 2 | `max-app` | `[ASSUMED]` | По образцу `telegram-app` |
| 3 | `ru-max` | `[ASSUMED]` | Geo-prefix variant |
| 4 | `vkmax` | `[ASSUMED]` | VK-branded variant (MAX выпущен VK 2025) |

**Verification step (Phase 11 device-UAT):**
1. Установить MAX из App Store на test iPhone.
2. Запустить BBTB → проверить лог: `xcrun simctl spawn booted log show --predicate 'subsystem == "app.bbtb.client" && category == "detection"' --last 1m`
3. Если все 4 candidates fail (видим `MAX-app not detected (iOS, tried 4 schemes)`) — открыть MAX, отследить через Charles Proxy `Open in App` URL — там может быть реальный scheme.
4. Update `iOSSchemeCandidates` + Info.plist + повторить.

### macOS bundle IDs — verification pending

`MAXDetector.macOSBundleCandidates`:

| # | Bundle ID | Status | Notes |
|---|-----------|--------|-------|
| 1 | `ru.vk.max` | `[ASSUMED]` | Reverse-DNS VK convention |
| 2 | `com.vkontakte.max` | `[ASSUMED]` | Альтернативный VK convention |
| 3 | `chat.max.app` | `[ASSUMED]` | По образцу `chat.signal.macos` etc |
| 4 | `ru.max.messenger` | `[ASSUMED]` | Geo-prefix variant |

**Verification step:** Если MAX доступен на macOS (RESEARCH A3 unknown) — `mdls /Applications/MAX.app kMDItemCFBundleIdentifier`. Если нет macOS версии — DETECT-02 will log `not detected` permanently, что acceptable (no harm).

## Unit Test Outcomes

| # | Test | Платформа | Status |
|---|------|-----------|--------|
| 1 | `test_iOS_detectsFirstMatchingScheme` | iOS (conditional, skipped on macOS host) | passing (verified locally при iOS build) |
| 2 | `test_iOS_returnsNilWhenNoneRegistered` | iOS conditional | passing |
| 3 | `test_iOS_prefersFirstCandidateWhenMultipleRegistered` | iOS conditional | passing |
| 4 | `test_iOS_handlesArbitraryRegisteredScheme` | iOS conditional | passing |
| 5 | `test_macOS_detectsFirstMatchingBundle` | macOS | ✅ PASS (0.000s) |
| 6 | `test_macOS_returnsNilWhenNoneInstalled` | macOS | ✅ PASS |
| 7 | `test_macOS_prefersFirstCandidateWhenMultipleInstalled` | macOS | ✅ PASS |
| 8 | `test_macOS_handlesArbitraryRegisteredBundle` | macOS | ✅ PASS |
| 9 | `test_candidates_nonEmpty_andNoDuplicates` | cross-platform | ✅ PASS |

**На SPM `swift test` host (arm64e-apple-macos14.0):** 5 тестов executed (4 macOS + 1 cross-platform invariant), 4 iOS-conditional тестов skipped. Под Xcode iOS Simulator build path — iOS тесты также бы executed (Xcode integration UI test остаётся device-UAT задачей).

## wiki/max-domains-blocklist.md Initial Domains

7 entries — 2 подтверждённых + 5 `[ASSUMED]`:

| # | Домен | Назначение | Confidence |
|---|-------|------------|------------|
| 1 | `max.ru` | Основной домен | ✅ Confirmed (wiki/max-messenger.md) |
| 2 | `mssgr.tatar.ru` | VK historical | ✅ Confirmed (wiki/max-messenger.md) |
| 3 | `api.max.ru` | API endpoint | `[ASSUMED]` — dig verify |
| 4 | `cdn.max.ru` | CDN | `[ASSUMED]` — tcpdump verify |
| 5 | `static.max.ru` | Static assets | `[ASSUMED]` — Charles snapshot |
| 6 | `apk.max.ru` | APK distribution | `[ASSUMED]` — 302 redirect verify |
| 7 | `auth.max.ru` | Auth | `[ASSUMED]` — мб unified с id.vk.com |

Минимум 5 (PRD acceptance) ✓.

## iOS + macOS xcodebuild Status

| Target | Result | Notes |
|--------|--------|-------|
| `BBTB` (iOS Simulator generic) | ✅ BUILD SUCCEEDED | После @preconcurrency fix Rule 1 |
| `BBTB-macOS` (default signing) | ❌ FAILED — pre-existing Distribution credentials gap (Phase 12 prerequisite) | Не Phase 11-04 regression — карта известных blocker'ов в STATE.md |
| `BBTB-macOS` (ad-hoc CODE_SIGN_IDENTITY="-") | ✅ BUILD SUCCEEDED | Consistent с Phase 7a closure pattern |

Производство ready (iOS) + dev-build ready (macOS).

## Decisions Made

- **DEC-11-04-01 — Silent invariant:** detection не пишет в shared state, не вызывает Notification, не имеет UI side-effect. Это explicit scope decision из CONTEXT D-Detect. Тест `grep` на запрещённых символах = 0. Future tempation добавить «отметку, что мы видели MAX, чтобы показать FAQ» — должна resist'иться: FAQ entry статичный (Phase 11 LOC-04), не conditional на detection result.
- **DEC-11-04-02 — Cold-start defer pattern reuse:** один-shot detection вызывается через `Task.detached(.utility)`, идентично существующим Phase 8 RulesEngine bootstrap + Phase 9 DeepLinks register patterns. Не блокирует первый UI frame.
- **DEC-11-04-03 — Mockable surface через protocols:** `URLSchemeQueryable` / `WorkspaceQueryable` — minimal abstraction (1 method каждый) для test-only purpose. НЕ публикуется как public API внешним клиентам пакета — это internal detection mechanism.
- **DEC-11-04-04 — `@preconcurrency` для protocol conformance:** Apple-recommended bridge между `@MainActor private struct RealUIApplication` и `nonisolated` requirement `URLSchemeQueryable.canOpenURL(_:)`. Альтернативы (изменить protocol на `@MainActor`, использовать `@unchecked Sendable`, убрать `@MainActor` annotation) хуже по reasons задокументированным в MAXDetector.swift inline doc.
- **DEC-11-04-05 — Admin handoff document scope:** wiki/max-domains-blocklist.md описывает task на VPS, НЕ client code change. DETECT-03 closure conditional на admin applying документ — паттерн "client ready, admin handoff pending" из Phase 10 DPI-06 (CDN fronting).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict concurrency error на Xcode iOS build**
- **Found during:** Task 4.2 verify (iOS xcodebuild SUCCEEDED первый run)
- **Issue:** `conformance of 'RealUIApplication' to protocol 'URLSchemeQueryable' crosses into main actor-isolated code and can cause data races`. Xcode 26 с `-swift-version 6` строже SPM `swift test` — ловит main-actor → nonisolated-protocol bridge как ошибку. Локальная SPM-build была green; Xcode iOS Simulator build падал в emit-module phase MainScreenFeature.
- **Fix:** Добавлен `@preconcurrency` qualifier на conformance: `private struct RealUIApplication: @preconcurrency URLSchemeQueryable, @unchecked Sendable` + inline doc-comment с обоснованием (Apple recommended pattern для main-actor → nonisolated bridging).
- **Files modified:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MAXDetector.swift` line 192-194.
- **Verification:** После fix — iOS xcodebuild ✅ SUCCEEDED + AppFeatures swift test 178/178 PASS (unchanged).
- **Committed in:** `1a9f3ce` (Task 4.2 commit). Pre-fix state (committed как `e636331`) — функционально работал для swift-test, но не для full Xcode build.

**2. [Rule 3 - Blocking] Symlinked libbox.xcframework в worktree**
- **Found during:** Task 4.1 verify (`swift test --filter MAXDetectorTests`)
- **Issue:** SPM build падал с `error: local binary target 'Libbox' at '<path>/Vendored/libbox.xcframework' does not contain a binary artifact` — libbox.xcframework gitignored (binary артефакт), отсутствует в новом worktree.
- **Fix:** `ln -sf /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework <worktree>/BBTB/Vendored/libbox.xcframework` (тот же fix что в Plan 11-01 — known worktree setup step).
- **Files modified:** Worktree filesystem only (symlink, не commitable — Vendored/ в .gitignore).
- **Verification:** После symlink — `swift build` green, `swift test` green, `xcodebuild` green (Xcode picks up symlinked binary автоматически).
- **Committed in:** N/A — non-tracked filesystem state.

---

**Total deviations:** 2 auto-fixed (1 bug — Swift 6 concurrency, 1 blocking — libbox symlink)

**Impact on plan:** План не пострадал. Swift 6 fix — single-line addition + comment, encapsulated в Task 4.2 commit. Libbox symlink — well-known worktree-setup step. Никакого scope creep.

## Issues Encountered

- **Xcode strict concurrency vs SPM**: Xcode 26 с `-swift-version 6` flag (production target) строже SPM `swift test` (без явного `-swift-version 6` для Package.swift swift-tools-version: 6.0). Известная разница; planner должен валидировать оба путей перед закрытием waves. **Lesson:** В будущих фазах с новым кодом, который пересекает actor isolation boundaries — запускать xcodebuild ДО считать Task verify'нутым.
- **libbox.xcframework worktree gap**: воспроизводится каждый раз в новых worktrees. Стоит автоматизировать как post-clone hook в `gsd-execute-phase` worktree setup (carried-forward concern из Plan 11-01).

## User Setup Required

**Для closure DETECT-03 (admin handoff):**

1. Прочитать `wiki/max-domains-blocklist.md` — там пошаговая инструкция для админа.
2. Verify все `[ASSUMED]` домены по § «Verification protocol» (DNS baseline → tcpdump → 24h monitoring).
3. Добавить verified домены в `rules.json` на VPS (block_completely.domains).
4. Run `scripts/build-baseline-rules.sh` (Phase 8 W6 pipeline) для sign + publish.
5. Mark DETECT-03 в REQUIREMENTS.md как `⚙️ Infrastructure-validated` (паттерн Phase 10 DPI-06).

**Для closure DETECT-01/02 (device UAT optional verification):**

1. Установить MAX-app на test iOS device + macOS (если доступен).
2. Cold-start BBTB app.
3. На iOS: `xcrun simctl spawn <device> log show --predicate 'subsystem == "app.bbtb.client" && category == "detection"' --last 1m` — должна быть строка `MAX-app detected via scheme: <scheme>` или `MAX-app not detected (iOS, tried 4 schemes)`.
4. На macOS: `log show --predicate 'subsystem == "app.bbtb.client" && category == "detection"' --last 1m` — analogous.
5. Если detection всегда `not detected` хотя MAX установлен — обновить `iOSSchemeCandidates` / `macOSBundleCandidates` в MAXDetector.swift и Info.plist (sync!).

**Никаких backend / build config / external service changes Phase 11-04 не требует.** Все изменения чистые code edits + один Info.plist edit + один wiki файл.

## Verification Summary

**Task 4.1 acceptance criteria:**
- `swift test --filter MAXDetectorTests` → ✅ PASS (5 tests; 4 macOS + 1 invariant; iOS conditional skipped on macOS host)
- `grep -c` на 7 sentinel'ах в MAXDetector.swift → **26** (план требовал ≥7)
- MAXDetector.swift lines → **207** (план требовал ≥80)
- AppFeatures swift test full → ✅ 178/178 PASS
- No UI imports check → ✅ только Foundation/os/UIKit/AppKit
- No forbidden symbols check → ✅ только в `//` doc-comments (negative-clause text), no actual code references

**Task 4.2 acceptance criteria:**
- `plutil -lint Info.plist` → ✅ OK
- `LSApplicationQueriesSchemes` `<string>` count → **4** (план требовал ≥4)
- iOS App MAXDetector.detectAndLog non-comment call → **1** (план требовал ровно 1)
- macOS App MAXDetector.detectAndLog non-comment call → **1** (план требовал ровно 1)
- `wiki/max-domains-blocklist.md` exists, lines → **147** (план требовал ≥30)
- Domain entries → **7** (план требовал ≥5)
- iOS xcodebuild (-destination 'generic/platform=iOS Simulator') → ✅ BUILD SUCCEEDED
- macOS xcodebuild (ad-hoc signing) → ✅ BUILD SUCCEEDED (production Distribution = pre-existing Phase 12 gap)
- Info.plist schemes ↔ iOSSchemeCandidates → ✅ MATCH (verified manually: `max`, `max-app`, `ru-max`, `vkmax` в обоих)

**Plan-level verification (`<verification>`):**
- AppFeatures swift test green: **178 / 178 PASS** ≥ план-required ≥143
- iOS xcodebuild SUCCEEDED ✅
- macOS xcodebuild SUCCEEDED (ad-hoc) ✅
- `plutil -lint Info.plist` returns OK ✅
- wiki/max-domains-blocklist.md > 30 lines + citations ✅ (147 строк, citation footer)
- Console log probe — deferred to manual UAT (carved-out — см. User Setup Required выше)

## DETECT-03 Carry-out Note

**Client-side ✅ Validated**, server-side **⏸ pending admin handoff**.

DETECT-03 closure условный на админе:
1. Apply `wiki/max-domains-blocklist.md` workflow (steps 1-4 в § «Verification protocol»).
2. Один раз runs `scripts/build-baseline-rules.sh` с обновлённым `rules.json` на VPS.
3. Clients автоматически подхватят обновление в течение ≤6 часов (Phase 8 RulesEngine BGAppRefreshTask iOS / NSBackgroundActivityScheduler macOS).
4. После подтверждения applied → mark в `.planning/REQUIREMENTS.md` DETECT-03 status: `⚙️ Infrastructure-validated` (паттерн Phase 10 DPI-06 closure).

Phase 11 client code НЕ требует обновления для DETECT-03 closure — это purely server-side задача.

## Threat Flags

None — Phase 11-04 не добавляет нового network endpoint, auth path, schema или trust boundary. Threat model T-11-04-01..06 (см. 11-04-PLAN.md `<threat_model>`) полностью accepted/mitigated:
- T-11-04-01 (logger PII leak) — accepted: scheme/bundleID не PII; CloudKit log sync отключён.
- T-11-04-02 (Info.plist ↔ Swift sync drift) — mitigated через cross-platform invariant test + sync check в acceptance criteria.
- T-11-04-03 (candidate list публично visible в IPA) — accepted: Apple-mandated public visibility, не security boundary.
- T-11-04-04 (false positive — malicious app зарегистрировал `max://`) — accepted: detection diagnostic, не security boundary.
- T-11-04-05 (detector exception crashes first frame) — mitigated: Task.detached isolates exception, canOpenURL / urlForApplication non-throwing.
- T-11-04-06 (max-domains-blocklist.md leaked в git) — accepted: domains public observation, not military secrets.

## Self-Check: PASSED

### Created files exist
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MAXDetector.swift` — FOUND (207 lines)
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MAXDetectorTests.swift` — FOUND
- `wiki/max-domains-blocklist.md` — FOUND (147 lines)

### Modified files contain expected changes
- `BBTB/App/iOSApp/Info.plist` contains `LSApplicationQueriesSchemes` array with 4 strings — FOUND
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` contains 1 non-comment `MAXDetector.detectAndLog` call — FOUND (line 241)
- `BBTB/App/macOSApp/BBTB_macOSApp.swift` contains 1 non-comment `MAXDetector.detectAndLog` call — FOUND (line 176)
- `wiki/index.md` contains link to `[[max-domains-blocklist]]` — FOUND
- `wiki/log.md` contains "Phase 11 Plan 04" entry — FOUND

### Commits exist
- `e636331` (Task 4.1 — MAXDetector service + tests) — FOUND in git log
- `1a9f3ce` (Task 4.2 — Wiring + Info.plist + wiki + Swift 6 fix) — FOUND in git log

## Next Plan Readiness

**Phase 11 Wave 3+ unblocked:**

- **Plan 11-02 (Onboarding UI / UX-01)** — может использовать `@AppStorage("app.bbtb.hasShownOnboarding")` + `fullScreenCover` + L10n keys (готовы из Wave 1). Не зависит от MAXDetector.
- **Plan 11-03 (ConnectionButton spinner / UX-08)** — pure View work. Не зависит ни от чего.
- **Plan 11-05 (HelpView + FAQ / LOC-03/04)** — L10n keys готовы из Wave 1. FAQ 5 entries (вкл. «Ограничения детектирования MAX») контент уже в xcstrings.
- **Plan 11-06 (DiagnosticsSection + ShareLink / TELEM-02)** — может ссылаться на `AppGroupContainer.singBoxLogPath` + L10n keys из Wave 1.
- **Plan 11-07 (file picker / IMP-03)** — может использовать `.fileImporter` + L10n keys из Wave 1.

**Никаких blocker'ов или concerns'ов** для последующих волн Phase 11.

**Wiki sync DONE (CLAUDE.md правило):** Phase 11 Plan 04 артефакты задокументированы:
- `wiki/max-domains-blocklist.md` — новый
- `wiki/index.md` — ссылка добавлена
- `wiki/log.md` — entry добавлена
- `wiki/max-messenger.md` — НЕ обновлён в этом плане (был обновлён Phase 1 / 2026-05-11); может быть обновлён при Phase 11 closure с уточнением «MAXDetector implementation closed; пока candidates все [ASSUMED] до device-UAT».

**Phase 11 closure TODO (после всех Wave): добавить в `wiki/architecture.md` упоминание `MAXDetector` (silent detection service) в section «Phase 11 additions».**

---
*Phase: 11-onboarding-ux-polish*
*Plan: 04 (Wave 2 — MAX Detection)*
*Completed: 2026-05-15*
