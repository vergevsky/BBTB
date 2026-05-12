---
phase: 03-server-management
plan: 04
subsystem: ui
tags: [swiftdata, swiftui, async-await, structured-concurrency, keychain, refreshable, subscription, merge-strategy, scenephase]

# Dependency graph
requires:
  - phase: 03-server-management
    provides: "Plan 01 — Subscription @Model + ServerConfig Phase 3 fields + ConfigImporter Subscription branch foundation"
  - phase: 03-server-management
    provides: "Plan 02 — ServerProbeService actor + AsyncStream probeAll + ProbeAggregate score"
  - phase: 03-server-management
    provides: "Plan 03 — ServerListViewModel skeleton, ServerListSheet UI scaffolding, ServerSelectionCoordinating protocol, ServerListSection, PingState, ServerListState"
provides:
  - "SubscriptionMergeService.merge — D-14 identity-based dedup with latency preservation and missing-from-fetch marking"
  - "ConfigImporting protocol expansion (persistKeychainSecret + buildServerConfig); protocol relocated from MainScreenFeature → ConfigParser to unblock ServerListFeature consumption"
  - "KeychainPersistResult struct — bridges UUID + tag across the persistKeychain / buildServerConfig closure pair"
  - "ServerProbing / SubscriptionURLFetching / DefaultSubscriptionURLFetcher — DI protocols for actor mocking"
  - "ServerListViewModel.pullToRefresh — 2-phase sequential (D-13: fetch all → ping all), structured concurrency only"
  - "ServerListViewModel.silentForegroundRefresh — silent variant for scenePhase .active (D-12)"
  - "ServerListViewModel.deleteServer / confirmDeleteSubscription — cascade delete + Keychain cleanup + selection reset (D-07, Pitfall 10)"
  - "ServerListSheet .refreshable + .confirmationDialog wiring"
  - "SubscriptionHeader fetchError inline indicator (UI-SPEC §3.4)"
  - "MainScreenView .onChange(of: scenePhase) → silentForegroundRefresh on .active"
  - "ServerConfig.identity computed property — composite key host:port:protocolID:sni"
affects:
  - 03-05 — pre-connect auto-select + reconnect-on-active-tunnel will reuse pullToRefresh pattern and SubscriptionMergeService for fetched state.
  - "Phase 4 — Protocol expansion: new handler additions only need to extend persistKeychainSecret / buildServerConfig switch arms; SubscriptionMergeService picks them up automatically through identity contract."
  - "Phase 6 — Network resilience: BGAppRefreshTask will reuse silentForegroundRefresh as backend for scheduled refresh."

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Closure-injection через protocol — SubscriptionMergeService.merge(persistKeychain:buildServerConfig:) делает merge testable без monkey-patching."
    - "Actor protocol abstraction — ServerProbing protocol covers nonisolated probeAll signature, mocked by plain class в тестах (actor inheritance невозможно в Swift)."
    - "Sendable bridge struct — KeychainPersistResult несёт (UUID, tag) пару между двумя closure-вызовами, избегая mutable shared state."
    - "scenePhase-driven silent refresh — Environment(\\.scenePhase) + onChange → Task для foreground refresh без UI spinner."

key-files:
  created:
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift — relocated from MainScreenFeature"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift — D-14 merge logic"
    - "BBTB/Packages/VPNCore/Sources/VPNCore/KeychainPersistResult.swift — closure-pair payload struct"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MergeStrategyTests.swift — 6 cases"
    - "BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift — 5 cases"
    - "BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/CascadeDeleteTests.swift — 5 cases"
  modified:
    - "BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift — identity computed property"
    - "BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift — ServerProbing protocol + conformance"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift — SubscriptionURLFetching protocol + DefaultSubscriptionURLFetcher"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift — persistKeychainSecret/buildServerConfig public helpers, subscription URL branch → merge, deleteExistingPool removed"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift — scenePhase observer"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift — pass importer to ServerListViewModel"
    - "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift — pullToRefresh / silentForegroundRefresh / deleteServer / confirmDeleteSubscription, importer + fetcher + parser DI"
    - "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift — .refreshable + .confirmationDialog"
    - "BBTB/Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift — fetchError parameter"
    - "BBTB/Packages/AppFeatures/Package.swift — ServerListFeature + ServerListFeatureTests dep on ConfigParser"

key-decisions:
  - "ConfigImporting protocol relocated from MainScreenFeature → ConfigParser. Rationale: ServerListFeature нужно вызывать ConfigImporting.persistKeychainSecret / buildServerConfig через protocol reference; обратная зависимость MainScreenFeature → ServerListFeature уже существует через .sheet(ServerListSheet) — добавлять обратную грань ServerListFeature → MainScreenFeature невозможно. Перенос в ConfigParser нейтрален (концепт importer обслуживает ImportedServer/ImportResult, которые там же)."
  - "KeychainPersistResult struct (вместо tuple `(UUID, String?)?` или out-of-band shared state) — bridge между persistKeychain closure return и buildServerConfig invocation. Гарантирует consistency UUID/tag в multi-server batch без mutable storage."
  - "ServerProbing protocol добавлен — actor type cannot be inherited (Swift constraint), а DI требует mock в тестах. Protocol-level nonisolated declaration соответствует existing ServerProbeService.probeAll signature."
  - "Server-identity при изменённом password (Open Question 2 — RESEARCH §«Open Questions»): merge сохраняет existing row + только обновляет `name`. Keychain entry остаётся старый (D-14 + Pitfall 10 mitigation — менять Keychain в фоновом refresh опасно). Если password действительно изменился, user replays import вручную."
  - "Phase 1 fetch + Phase 2 ping всегда выполняются последовательно (D-13), даже если все fetch failed — existing servers всё равно нужно перепиновать. Только финальный state (.refreshError) фиксируется."

patterns-established:
  - "Pattern 1: SubscriptionMergeService.merge принимает closures persistKeychain + buildServerConfig — caller (ConfigImporter, ServerListViewModel) injectит конкретную ConfigImporting реализацию без shared mutable state."
  - "Pattern 2: ServerProbing/SubscriptionURLFetching protocols + Default impl + Mock в тестах — стандартный DI для actor / static fetcher."
  - "Pattern 3: state preservation в silentForegroundRefresh — save current state, выполнить ту же логику, restore state. Используется как universal паттерн для background-style операций."
  - "Pattern 4: SwiftData #Predicate с UUID? сравнением требует явный `let opt: UUID? = nonOptional` перед предикатом — иначе macro reject'ит KeyPath<Subscription, UUID> vs KeyPath<ServerConfig, UUID?>."

requirements-completed: [SRV-02, SRV-03, UX-04]

# Metrics
duration: 15min
completed: 2026-05-12
---

# Phase 3 Plan 04: Pull-to-refresh + Cascade delete + Foreground refresh Summary

**SubscriptionMergeService with identity-based dedup + ConfigImporting protocol expansion + 2-phase pull-to-refresh + cascade delete with Keychain cleanup + scenePhase-driven silent refresh.**

## Performance

- **Duration:** ~15 min (2026-05-12T12:17:15Z → 12:32:41Z)
- **Started:** 2026-05-12T12:17:15Z
- **Completed:** 2026-05-12T12:32:41Z
- **Tasks:** 2/2 (TDD RED + GREEN)
- **Files modified:** 17 (3 created tests, 3 created sources, 8 modified sources, 1 modified package, 1 modified plan, 1 created summary)

## Accomplishments

- **D-14 merge-by-identity** (`SubscriptionMergeService.merge`): composite key `host:port:protocolID:sni`; existing identity → preserve lastLatencyMs/lastPingedAt/failedProbeCount, refresh name (sanitized); new identity → insert через injected closures; disappeared identities → `missingFromLastFetch = true` (НЕ удаляются — пользователь решает swipe-delete); per-subscription isolation; `subscription.lastFetched = .now`.
- **ConfigImporting protocol expansion** (Plan-check BLOCKER fix): добавлены `persistKeychainSecret(for:)` и `buildServerConfig(from:id:subscriptionID:keychainTag:)`. `ServerListViewModel.fetchAndMerge` вызывает их через **protocol reference** без cast'ов к concrete ConfigImporter (verified `grep -E "as[!?] ConfigImporter" → 0`).
- **D-13 pull-to-refresh 2-phase sequential** (`pullToRefresh`): Phase 1 — fetch all subscription URLs + merge; Phase 2 — ping all supported. Structured concurrency only (Pitfall 5). Partial failure → `subscriptionFetchErrors[sub.id]` set; all-fail → `refreshError != nil` + `state == .refreshError(...)`.
- **D-12 foreground refresh** (`silentForegroundRefresh`): identical to pullToRefresh logic, но state preserved (.loaded → .loaded), errors silent (нет UI alert). Wired через `MainScreenView .onChange(of: scenePhase)`.
- **D-07 cascade delete** (`deleteServer` + `confirmDeleteSubscription`): single server — Keychain cleanup + delete row + selection reset if was selected (Pitfall 10); subscription — delete all linked ServerConfig + cascade Keychain delete + delete Subscription + selection reset if selected was in linked set. Orphans (subscriptionID == nil) не затрагиваются.
- **UI wiring**: `ServerListSheet.refreshable { await viewModel.pullToRefresh() }`; `.confirmationDialog` с `L10n.serverListDeleteSubscriptionConfirm(name, count)`. `SubscriptionHeader` имеет `fetchError: String?` параметр → exclamationmark.triangle.fill с .help(error).
- **T-03-17 mitigation**: `SubscriptionMergeService.sanitizeRowName` strips `\n\r\t` + clamp 100 chars при merge fetched.displayName в existing row.name.

## Task Commits

1. **Task 1 (RED): failing tests** — `7a3281b` (test) — 3 файла теста, все RED (compile-fail).
2. **Task 2 (GREEN): implementation** — `2d2332e` (feat) — 16 новых tests pass, 0 regressions.

**Plan metadata:** This SUMMARY commit will be added.

_Note: Plan 04 — 2-task TDD plan (RED → GREEN), без отдельных refactor commits._

## Test Results

| Package | Before | After | Δ |
|---------|--------|-------|----|
| AppFeatures | 15 pass | 31 pass | +16 (Plan 04 new) |
| ConfigParser | 78 pass | 78 pass | 0 |
| VPNCore | 32 pass / 1 skip | 32 pass / 1 skip | 0 |
| PacketTunnelKit | 44 pass | 44 pass | 0 |
| **Total** | **169 pass** | **185 pass** | **+16, 0 regressions** |

All Plan 04 specific tests (`swift test --filter "MergeStrategyTests|PullToRefreshTests|CascadeDeleteTests"`) → 16/16 pass.

## Files Created/Modified

**Sources (created):**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift` — protocol declaration (moved from MainScreenFeature)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift` — D-14 merge logic + identity helper + sanitization
- `BBTB/Packages/VPNCore/Sources/VPNCore/KeychainPersistResult.swift` — Sendable struct

**Sources (modified):**
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` — `var identity: String` extension
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` — `ServerProbing` protocol + conformance
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` — `SubscriptionURLFetching` protocol + `DefaultSubscriptionURLFetcher`
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — `persistKeychainSecret`/`buildServerConfig` public helpers; subscription URL branch → `SubscriptionMergeService.merge`; `deleteExistingPool` removed; protocol declaration moved to ConfigParser (comment placeholder remains)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` — `@Environment(\.scenePhase)` + `.onChange(of: scenePhase)` → silentForegroundRefresh
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` — pass `importer: importer` to ServerListViewModel init
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` — implementation of pullToRefresh / silentForegroundRefresh / deleteServer / confirmDeleteSubscription + DI of importer/fetcher/parser
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` — `.refreshable { await viewModel.pullToRefresh() }` + `.confirmationDialog`
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift` — `fetchError: String?` parameter + warning triangle UI

**Packages:**
- `BBTB/Packages/AppFeatures/Package.swift` — ServerListFeature target gains ConfigParser dep; ServerListFeatureTests gains ConfigParser dep

**Tests (created):**
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MergeStrategyTests.swift` — 6 cases for D-14
- `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift` — 5 cases for D-12/D-13
- `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/CascadeDeleteTests.swift` — 5 cases for D-07

## Decisions Made

- **ConfigImporting protocol — relocated to ConfigParser.** Plan placed protocol в MainScreenFeature; при попытке `ServerListFeature` импортировать его обнаружилась reverse-dep cycle (MainScreen depends on ServerList through .sheet). Перенесли в ConfigParser — нейтрально по смыслу, протокол оперирует ImportedServer/ImportResult, которые уже там. Comment placeholder в `MainScreenFeature/ConfigImporter.swift` указывает на новое место.
- **KeychainPersistResult struct (вместо tuple)** — bridges (UUID, tag) между двумя closure-вызовами в merge. Tuple был отброшен как менее читаемый; out-of-band mutable state (ConfigImporter property) был отброшен как небезопасный для concurrent batch.
- **ServerProbing protocol добавлен в VPNCore** — actor inheritance невозможно в Swift, поэтому DI через protocol — единственный путь. Default impl — сам actor (conforms через `public actor ServerProbeService: ServerProbing`).
- **`silentForegroundRefresh` сохраняет savedState** — копируем state в локальную переменную в начале, выполняем fetch+ping (могут пройти быстро если servers свежие или fail silently), потом restore. Не используем `.refreshing` state ни в какой момент. Test `test_silent_foreground_refresh_does_not_set_refreshing_state` подтверждает.
- **scenePhase observer в MainScreenView**, не в ServerListSheet — sheet может быть закрыт когда пользователь возвращается из background. MainScreenView живёт весь app lifecycle, поэтому observer там более consistent.
- **`deleteExistingPool` удалён полностью** (а не оставлен как unused helper) — обнаружение через grep acceptance check; чище без orphan dead code. Single-paste branch использует `deleteAllExistingConfigs` (Phase 2 behavior unchanged).

## Open Question Resolutions

- **OQ-2 (server-identity при изменённом password):** merge сохраняет existing row, обновляется только `name`. Keychain entry — не трогается (D-14 + Pitfall 10 — менять секрет в фоне небезопасно). Если password действительно изменился, user должен повторить import вручную. Документировано в SubscriptionMergeService.swift.
- **OQ-4 (pre-connect timeout):** out-of-scope для Plan 04. Отложено в Plan 05 (auto-select + reconnect-on-active).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] ConfigImporting protocol relocation**
- **Found during:** Task 2 (build sweep — `cannot find type 'ConfigImporting' in scope` в ServerListViewModel.swift).
- **Issue:** Plan instructed добавить `persistKeychainSecret` + `buildServerConfig` в protocol, declared в `MainScreenFeature/ConfigImporter.swift`. ServerListFeature не может импортировать MainScreenFeature (создаётся reverse-dep cycle: MainScreen уже depends on ServerList через .sheet ServerListSheet).
- **Fix:** Перенесли `protocol ConfigImporting` в новый файл `BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift`. Существующий блок объявления в `ConfigImporter.swift` заменён на comment-placeholder. ConfigImporter conforms по-прежнему. AppFeatures.Package.swift получил `"ConfigParser"` dependency в ServerListFeature target.
- **Files modified:** `ConfigParser/Sources/ConfigParser/ConfigImporting.swift` (new), `AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (protocol block → comment), `AppFeatures/Package.swift` (dep added).
- **Verification:** Build passes, все 31 AppFeatures + 78 ConfigParser tests green.
- **Committed in:** `2d2332e` (Task 2 commit).

**2. [Rule 3 — Blocking] ServerProbing protocol added (actor inheritance impossible)**
- **Found during:** Task 1 (RED — `cannot inherit from non-open class 'ServerProbeService' outside of its defining module`; actor types do not support inheritance).
- **Issue:** Plan не указал, как тестам мокать actor `ServerProbeService`. Тесты падали на compile с попыткой `class MockProbe: ServerProbeService`.
- **Fix:** Добавили `public protocol ServerProbing` в `ServerProbeService.swift` с nonisolated `probeAll` declaration. Actor `ServerProbeService` conforms. ViewModel принимает `probeService: ServerProbing` через init.
- **Files modified:** `VPNCore/Sources/VPNCore/ServerProbeService.swift`.
- **Verification:** Tests compile, 31 AppFeatures pass.
- **Committed in:** `2d2332e`.

**3. [Rule 3 — Blocking] SubscriptionURLFetching protocol + DefaultSubscriptionURLFetcher**
- **Found during:** Task 1 (тесты требуют mock без сетевых вызовов).
- **Issue:** `SubscriptionURLFetcher.fetch` — static func, нельзя injectить без protocol abstraction.
- **Fix:** Добавлен `public protocol SubscriptionURLFetching` + `DefaultSubscriptionURLFetcher` struct в `SubscriptionURLFetcher.swift`. ViewModel принимает fetcher через init (default — DefaultSubscriptionURLFetcher).
- **Files modified:** `ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift`.
- **Verification:** PullToRefreshTests/CascadeDeleteTests используют MockFetcher без сети — 10 tests pass.
- **Committed in:** `2d2332e`.

**4. [Rule 1 — Bug] SwiftData #Predicate strict typing fixes**
- **Found during:** Task 2 (build error — `cannot convert value of type 'KeyPath<Subscription, UUID>' to expected argument type 'KeyPath<Subscription, UUID?>'`).
- **Issue:** `#Predicate { $0.subscriptionID == sub.id }` — `subscriptionID` на ServerConfig — `UUID?`, а `sub.id` — `UUID`. Macro reject'ит mismatch.
- **Fix:** Перед каждым предикатом — `let subID: UUID? = sub.id` (или `let subscriptionID: UUID? = subscription.id`), используем optional binding в predicate. Применено в 3 местах: `SubscriptionMergeService.merge`, `ServerListViewModel.pendingDeleteSubscriptionServerCount`, `ServerListViewModel.confirmDeleteSubscription`. И обратно — `confirmDeleteSubscription` re-fetch'ит Subscription по `id` (non-optional UUID) — там понадобился `let lookupID: UUID = subscription.id`.
- **Files modified:** `ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift`, `AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift`, `AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`.
- **Verification:** Build passes, все tests green.
- **Committed in:** `2d2332e`.

---

**Total deviations:** 4 auto-fixed (3 Rule 3 blocking, 1 Rule 1 bug).
**Impact on plan:** All deviations are correctness-required compile-fixes — ConfigImporting placement was a planner oversight (reverse-dep), actor mocking needs protocol abstraction (Swift constraint), SwiftData #Predicate typing is strict. No scope creep. All deviations covered by tests.

## Issues Encountered

- **libbox.xcframework missing в worktree** — gitignored binary. Решено symlink'ом на `/Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework` (один раз в начале сессии). Не закоммичено (symlink, gitignored). Документировано в `BBTB/Vendored/README.md` — стандартный workflow.

## Threat Flags

Нет нового threat surface за пределами того, что указано в `<threat_model>` плана. Все mitigations (T-03-17 sanitization, T-03-23 acceptable surface) реализованы. T-03-18 (Keychain cleanup silent failure) — accept'ed risk (Phase 2 baseline, документировано в SECURITY.md Phase 2).

## Known Stubs

Нет. Все методы имеют non-stub bodies и покрыты тестами. UI-wired в ServerListSheet и MainScreenView.

## Next Phase Readiness

Plan 04 закрывает «обновлять список одним жестом» из user-story Phase 3. Остаётся **Plan 05** (auto-select + reconnect-on-active + pre-connect timeout — OQ-4), который:
- использует `SubscriptionMergeService` через тот же closure-pair pattern для refresh при reconnect;
- реализует pre-connect TCP-probes (Plan 02 carry-forward) с timeout fallback к "any" сервер (Pitfall 8 mitigation);
- расширит `ServerSelectionCoordinating.applySelection` чтобы trigger reconnect при tunnel active.

Никаких blocker'ов для Plan 05 нет. Phase 1/2/3 regression tests все зелёные.

---
*Phase: 03-server-management*
*Completed: 2026-05-12*

## Self-Check: PASSED

Verified after writing:
- File `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift` — exists.
- File `BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift` — exists.
- File `BBTB/Packages/VPNCore/Sources/VPNCore/KeychainPersistResult.swift` — exists.
- File `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MergeStrategyTests.swift` — exists.
- File `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift` — exists.
- File `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/CascadeDeleteTests.swift` — exists.
- Commit `7a3281b` (RED) and `2d2332e` (GREEN) present in git log.
- 31 AppFeatures + 78 ConfigParser + 32 VPNCore tests pass (verified `swift test`).
- ServerListViewModel `grep -E "as[!?] ConfigImporter"` → 0 (no casts).
- 16 new tests added in Plan 04 (MergeStrategyTests 6 + PullToRefreshTests 5 + CascadeDeleteTests 5).
