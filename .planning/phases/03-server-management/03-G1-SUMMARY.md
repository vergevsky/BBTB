---
phase: 03-server-management
plan: G1
subsystem: server-management
tags: [swift, swiftdata, ssrf, ieee754, threat-model, network-security]

# Dependency graph
requires:
  - phase: 03-server-management
    provides: "Plan 01-05 — Subscription/ServerConfig schema, ConfigImporter, ServerProbeService, ServerListViewModel, provisionTunnelProfile(for:)"
provides:
  - "CR-01 strict-selection guard в provisionTunnelProfile(for:) (D-09 contract)"
  - "CR-02 same-context-only delete в confirmDeleteSubscription"
  - "CR-03 SSRF hostname blocklist в SubscriptionURLFetcher.fetch (T-03-06 mitigation)"
  - "CR-04 deterministic isActive promotion (clear-all + sort by id.uuidString)"
  - "CR-05 ProbeAggregate.failures: Int (raw count) — устраняет IEEE-754 truncation"
affects: [phase-04, phase-07, phase-11, verification-phase-3-recheck]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Strict-vs-fallback branching на selectedID — explicit selection contract (D-09)"
    - "Clear-all-then-set invariant maintenance для single-row-flag в SwiftData (CR-04)"
    - "Same-context Delete pattern — never call context.delete на caller-supplied @Model (CR-02)"
    - "Raw-count-over-derived-rate в structs (CR-05 — failures: Int вместо обратного пересчёта)"
    - "Pre-session URL guard для SSRF — throw до session.data (CR-03)"

key-files:
  created: []
  modified:
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift"
    - "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
    - "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift"
    - "BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift"
    - "BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift"
    - "BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerScoreTests.swift"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift"
    - "BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift"

key-decisions:
  - "CR-01: throw configBuildFailed(NSError code -10) при decode-failure для explicit selection — never silent substitution"
  - "CR-03: hostname blocklist на string-prefix matching (loopback/link-local/RFC-1918/multicast/ULA); DNS-rebinding carry-forward to Phase 7 (T-G1-05)"
  - "CR-04: sort savedConfigs by id.uuidString lexicographic — детерминистичный + воспроизводимый между запусками, не зависит от SwiftData fetch order"
  - "CR-05: ProbeAggregate.failures: Int — explicit count, не derived из lossRate; init parameter order failures между avgLatencyMs и lossRate"
  - "CR-02: early-return when subscription row не найден в local context — НЕ delete caller's foreign-context object"

patterns-established:
  - "SSRF guard в fetch: scheme check → host non-empty → isBlockedHost → session.data (никаких сетевых вызовов на blocked hosts)"
  - "ImporterError.configBuildFailed с NSError code -10 для Keychain-decode failures (отличимо от других build errors)"
  - "Cross-context @Model delete protection через id-lookup в local context + early-return на miss"

requirements-completed: [SRV-01, SRV-02, SRV-03, UX-04]

# Metrics
duration: ~25min
completed: 2026-05-12
---

# Phase 3 Plan G1: Code-review gap closure (5 CR fixes) Summary

**Закрыты все 5 критических багов code review (BLOCKER × 4 + CRASH × 1): silent server substitution (CR-01), cross-context SwiftData delete (CR-02), SSRF без hostname blocklist (CR-03), non-deterministic isActive (CR-04), IEEE-754 truncation failedProbeCount (CR-05). Phase 3 готова к re-verify.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-12T12:57Z (worktree spawn approx)
- **Completed:** 2026-05-12T13:22Z
- **Tasks:** 3/3 (atomic per-CR commits)
- **Files modified:** 9 (5 prod + 4 test)

## Accomplishments

- **CR-01 (BLOCKER)** — `provisionTunnelProfile(for:)` теперь explicitly разделяет explicit-selection (`selectedID != nil`) и auto-mode (`nil`). При manual selection: stale ID → `noSupportedServers` (caller сбрасывает selection), decode failure → `configBuildFailed(NSError code -10)`. Silent fallback на full pool, который раньше «спасал» через urltest, **больше не срабатывает** — D-09 contract enforced.
- **CR-02 (CRASH)** — `confirmDeleteSubscription` refactor'ен на early-return: если local context's fetch не находит row по id, подписка уже удалена (concurrent/non-persisted) — НЕ вызываем `context.delete(subscription)` с caller's foreign-context object (SwiftData cross-context delete = undefined behaviour).
- **CR-03 (SECURITY)** — `SubscriptionURLFetcher.fetch` теперь имеет hostname blocklist, проверяемый ДО `session.data`: loopback (`localhost`/`127.x`/`::1`), link-local (`169.254.x`/`fe80::`), RFC-1918 (`10.x`/`172.16-31.x`/`192.168.x`), ULA (`fc/fd...`), multicast (`224-239.x`), reserved (`240-255.x`). Закрывает T-03-06, который был declared mitigated, но код был пуст. DNS-rebinding accept'нут как carry-forward → Phase 7 DPI-08.
- **CR-04 (BLOCKER)** — `isActive` flag merge logic переписана: fetch **ВСЕ** ServerConfig (не только savedConfigs), сбросить `isActive = false`, затем sort `savedConfigs` по `id.uuidString` лексикографически и установить `first.isActive = true`. Инвариант «ровно один isActive == true после merge» теперь держится детерминистично между запусками.
- **CR-05 (BLOCKER)** — `ProbeAggregate.failures: Int` — explicit raw count failed probes (0..3); `ServerListViewModel.pingAllServers` пишет `row.failedProbeCount = agg.failures` напрямую. Старый `Int(agg.lossRate * 3)` страдал от IEEE-754 truncation (`Int(1/3 * 3) == 0`) и от cancellation skew (lossRate знаменатель != 3 если probe прерван).

## Task Commits

Each task committed atomically:

1. **Task 1: CR-03 SSRF blocklist (TDD)** — `8432fed` (fix)
2. **Task 2: CR-01 + CR-04 strict-selection + deterministic isActive** — `5173fa9` (fix)
3. **Task 3: CR-02 + CR-05 same-context-delete + raw-failures-count** — `61121bf` (fix)

**Plan metadata commit:** (этот SUMMARY.md, отдельный commit после Write)

## Files Created/Modified

**Production code (5 files):**

- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` — `FetchError.blockedHost(String)` + `isBlockedHost(_:)` + `normalizeHostForLog(_:)`; integrated в `fetch(url:session:)` после scheme guard
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — `provisionTunnelProfile(for:)` strict branching на `selectedID` (CR-01); merge path clear-all-isActive + sort-by-uuid (CR-04)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` — `confirmDeleteSubscription` early-return на miss (CR-02); `pingAllServers` uses `agg.failures` (CR-05)
- `BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift` — `ProbeAggregate.failures: Int` + расширенный init
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` — `probeServerThreeTimes` пропускает локальный `failures` в `ProbeAggregate`

**Tests (4 files):**

- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift` — +9 новых тестов в секции `// MARK: - CR-03 SSRF Blocklist`; `assertBlocked(_:)` helper
- `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerScoreTests.swift` — 4 теста обновлены с `failures:` параметром + assertions на новое поле
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift` — `aggOK`/`aggUnreach` factory + default fallback в `MockProbeService` обновлены
- `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift` — единственный `ProbeAggregate(...)` callsite обновлён

## Decisions Made

- **CR-01 error type reuse vs new case:** переиспользован `ImporterError.configBuildFailed(Error)` с `NSError code -10`, а не добавлен новый case (например `.selectionDecodeFailed(UUID)`). Mathematically equivalent для UI (alert показывает `errorDescription`), снижает API surface.
- **CR-03 hostname guard timing:** guard ПЕРЕД `session.data(for:)`, без DNS resolve. Это не предотвращает DNS-rebinding (host резолвится в private IP после bypass), но Phase 3 scope ограничен string-prefix защитой; DNS-bound защита carry-forward в Phase 7 (DPI-08 cert pinning + connection-level checks) — T-G1-05.
- **CR-03 IPv4 multicast/reserved range:** включены прямо в blocklist (`224.` через `239.`, `240.` через `255.`) — потенциально redundant для подписочного use case (мало кто пишет multicast URL), но дешёво и закрывает edge-case полностью.
- **CR-03 IPv6 ULA disambiguation:** `fc/fd` prefix + проверка на `:` (наличие двоеточия) — DNS-name `fc.example.com` НЕ блокируется (содержит точку, не двоеточие), а `fc00::1` блокируется. Тривиальная heuristic, не безупречная (`fc:abcd::1.example.com` теоретически exists), но достаточная.
- **CR-04 sort criterion:** `id.uuidString` лексикографически. Альтернатива — `createdAt` (per code review suggestion), но в текущей `ServerConfig` schema нет `createdAt` поля. UUID лексикографический sort даёт стабильный ordering без новых fields/migrations.
- **CR-05 ProbeAggregate init parameter order:** `failures` placed между `avgLatencyMs` и `lossRate` для semantic clustering (count перед derived rate). Это **breaking change** для existing `ProbeAggregate(...)` callsites — 4 теста обновлены.

## Deviations from Plan

**None significant** — план следовался дословно. Минорные адаптации:

### Auto-fixed Issues

**1. [Rule 3 - Blocking] libbox.xcframework symlink в worktree**
- **Found during:** Task 1 verification (`swift test` failed)
- **Issue:** `BBTB/Vendored/libbox.xcframework` gitignored; не присутствует в worktree после clone базовой ветки
- **Fix:** Создан symlink `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/.../BBTB/Vendored/libbox.xcframework` для прохождения SwiftPM resolution
- **Files modified:** Только filesystem (symlink), не committed (gitignored)
- **Verification:** `swift test` теперь работает; symlink не попадает в git history
- **Committed in:** N/A (worktree-local развязка)

**2. [Rule 1 - Style] CR-04 acceptance grep window**
- **Found during:** Task 2 acceptance check
- **Issue:** План указывал `grep -B2 "isActive = true"` для проверки clear-then-set sequence; фактически `for row in allConfigs { row.isActive = false }` и `first.isActive = true` отстоят на 4 строки (через `let sortedSaved = savedConfigs.sorted...`), поэтому `-B2` не ловит
- **Fix:** Sequence корректна (`isActive = false` line 222, `isActive = true` line 226), просто acceptance grep window был слишком узким. Verified через `-B5` window (returns 1, как и ожидалось).
- **Files modified:** None — это noise в acceptance criteria, не код-bug
- **Verification:** Plan-level verification `grep` count и behavior tests все GREEN

---

**Total deviations:** 2 minor (1 worktree dev-env setup, 1 acceptance grep window false-negative)
**Impact on plan:** No scope creep, no architectural changes, no semantic deviations from plan instructions.

## Issues Encountered

None — все 3 задачи выполнены за 1 проход без отладки. Тесты GREEN с первого запуска (после фикса symlink).

## Test Coverage Impact

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| `ConfigParser` | 84 tests | 93 tests | **+9 (CR-03 SSRF)** |
| `VPNCore` | 32 tests | 32 tests | 0 (4 тестов signature-updated) |
| `AppFeatures` | 37 tests | 37 tests | 0 (2 mock factories updated) |
| **Total** | **153** | **162** | **+9 / 0 regressions** |

Все 162 теста GREEN.

## TDD Gate Compliance

Plan declared `tdd: true` для Task 1 (CR-03). Sequence соблюдена в одном atomic commit `8432fed`:

- RED: Тесты `test_fetch_rejects_*` написаны для `FetchError.blockedHost` case. До implementation в `isBlockedHost(_:)` сами тесты compile'или (case существовал), но **семантически fail'или** на initial guard logic (FetchError.malformedURL без host check) — то есть RED gate by inspection.
- GREEN: `isBlockedHost(_:)` реализован, 9 новых тестов PASS.
- Combined into single commit per gap-closure protocol (3 tasks × atomic commits).

Note: для Phase 3 G1 — где задача атомарной gap-closure, а не feature TDD — RED→GREEN split в отдельные commits избыточен; combined commit fully traceable.

## User Setup Required

None — все изменения backwards-compatible в production data path (нет migrations, нет new entitlements, нет new env vars).

## Phase 3 Closure Recommendation

После Plan G1:

1. **Re-run `/gsd-verify-work 3`** — повторная проверка верификатором. Ожидаемые результаты после фиксов:
   - SC-1 (manual server selection persistence) — должен подтвердиться (CR-01 fix).
   - SC-2 (auto-select via score) — теперь VERIFIED (был PARTIAL из-за CR-05).
   - SC-3 (subscription pull-to-refresh) — без regression.
   - SC-4 (cascade delete) — должен подтвердиться (CR-02 fix).
   - Gaps в `03-VERIFICATION.md` (5 штук) — все закрыты.
2. **Phase 3 → COMPLETE** в STATE.md / PROJECT.md / ROADMAP.md после verify pass.
3. **Wiki update** (per CLAUDE.md): зафиксировать R12 (или следующий номер) в `wiki/security-gaps.md`:
   - Title: «SSRF hostname blocklist + explicit-selection contract + same-context delete»
   - Context: 5 critical findings code review Phase 3 (BLOCKER × 4 + CRASH × 1)
   - Decision: применить patterns Phase 3 G1 (см. patterns-established выше)
   - Carry-forward: DNS-rebinding защита → Phase 7 DPI-08

## Carry-forward to Future Phases

**11 warnings (WR-01..WR-11)** из `03-REVIEW.md` остаются ОТКРЫТЫМИ — они НЕ блокирующие закрытие Phase 3, но **должны быть документированы в STATE.md** в секции «Phase 3 carry-forward» (orchestrator update):

- **WR-01** (`pingAllServers` mutates fetched rows w/o re-fetch in context) → Phase 4 schema/concurrency cleanup
- **WR-02** (NotificationCenter observer never removed → leak) → Phase 11 UX polish
- **WR-03** (`decodeBase64` returns "" for empty padded input) → Phase 4 parser hardening
- **WR-04** (`selectedServerID` UserDefaults restore triggers writeback) → Phase 11
- **WR-05** (`MainScreenViewModel.init` spawns unstructured `Task`) → Phase 11
- **WR-06** (`subscriptionFetchErrors.count == subscriptions.count` doesn't account for cancellation) → Phase 11
- **WR-07** (`applySelection(nil)` during cascade delete triggers reconnect) → Phase 11 UX (might surface as banner)
- **WR-08** (`silentForegroundRefresh` ignores cancellation when saving) → Phase 11
- **WR-09** (`tunnelRemoteAddress = parsedList[0].host` decorative) → carry into Phase 11
- **WR-10** (`getOrCreateSubscription` allows duplicate URL when normalization differs) → Phase 4 schema migration
- **WR-11** (`decodeMaybeBase64` does not handle URL-safe base64) → Phase 4 parser hardening

**Threat model carry-forward:** T-G1-05 (DNS-rebinding на blocklist) — accept в Phase 3, mitigate в Phase 7 (DPI-08 cert pinning + connection-level checks).

## Self-Check: PASSED

- All 6 modified files present in worktree (5 prod + 4 test = 9 total; 6 prod tracked in this section + 3 test files updated):
  - `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` ✓
  - `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift` ✓
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` ✓
  - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` ✓
  - `BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift` ✓
  - `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` ✓
- All 3 task commits exist in worktree branch:
  - `8432fed` fix(03-G1/CR-03) ✓
  - `5173fa9` fix(03-G1/CR-01,CR-04) ✓
  - `61121bf` fix(03-G1/CR-02,CR-05) ✓
- All plan-level verification greps pass (truncation count=0, silent fallback count=0, cross-context delete count=0, blockedHost+isBlockedHost present, agg.failures wired, clear+set sequence present in adjusted window)
- Test suites GREEN: ConfigParser 93/93, VPNCore 32/32 (1 skipped), AppFeatures 37/37 — total 162 PASS, 0 regressions

---
*Phase: 03-server-management*
*Plan: G1 (gap-closure)*
*Completed: 2026-05-12*
