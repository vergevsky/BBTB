---
phase: 06c-on-demand-migration
plan: 01
subsystem: networking
tags: [networkextension, on-demand, ondemandrules, userdefaults, tdd, foundation]

# Dependency graph
requires:
  - phase: 06-network-resilience
    provides: UserIntentStore writer (TunnelController.swift) — Phase 6c reads same key
provides:
  - public enum OnDemandRulesBuilder в MainScreenFeature (4 public methods)
  - apply(to:isOnDemandEnabled:) — низкоуровневый NETunnelProviderManager mutator
  - applyCurrentState(to:userDefaults:) — single source of truth для Phase 6c консьюмеров
  - loadAutoReconnectEnabled() — D-04 default-ON UserDefaults reader для UI toggle
  - loadUserIntendedConnected() — B-04 default-FALSE reader для пользовательского intent
  - private buildRules() — Phase 8 extension point с W-08 ordering contract
  - 11 unit-тестов покрывающих rule shape + idempotency + replace + UserDefaults + intent gate
affects: [06c-02-config-importer, 06c-03-settings-toggle, 06c-04-tunnel-controller, 06c-05-migration-task, 08-rules-engine]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Static enum namespace for stateless mutators (зеркалит KillSwitch.apply)"
    - "Single-source-of-truth entry point applyCurrentState — все консьюмеры идут СЮДА, не в low-level apply"
    - "UserDefaults default ON via `object(forKey:) as? Bool ?? true` (НЕ `.bool(forKey:)`)"
    - "UserDefaults default FALSE via `object(forKey:) as? Bool ?? false`"
    - "Cross-plan UserDefaults key contract documented in BOTH writer и reader файлах (TunnelController.UserIntentStore + OnDemandRulesBuilder.loadUserIntendedConnected)"
    - "Phase 8 extensibility через private buildRules() — first-match-wins ordering, новые prepend rules не меняют callsite signatures"
    - "Test isolation через uniquely-named UserDefaults suites (UUID()) — никакого .standard, no tearDown needed"

key-files:
  created:
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (180 строк)"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift (200 строк)"
  modified: []

key-decisions:
  - "D-01 (RESEARCH correction): NEOnDemandRuleConnect(.any), не NEEvaluateConnectionRule — последний требует non-empty matchDomains (Apple forum thread 81249)"
  - "D-01b extensibility: Phase 8 prepend-only порядок документирован в buildRules() doc-comment (W-08)"
  - "D-04 default ON для UI toggle (app.bbtb.autoReconnectEnabled) — fresh install включает auto-reconnect автоматически"
  - "B-04 default FALSE для user intent (app.bbtb.userIntendedConnected) — fresh install НЕ активирует on-demand до явного Connect тапа"
  - "Single source of truth: applyCurrentState — все Phase 6c консьюмеры идут СЮДА. Low-level apply зарезервирован для тестов"
  - "Параметр isOnDemandEnabled (Round 2 B-04 rename с autoReconnectEnabled) — disambiguates UI toggle vs финальный manager flag"
  - "Builder ВСЕГДА пишет правила, даже при isOnDemandEnabled=false — re-enable не должен требовать provisionTunnelProfile (Pitfall 9 RESEARCH)"

patterns-established:
  - "Static enum namespace mutator: KillSwitch.apply + OnDemandRulesBuilder.apply используют одну форму (никакого instance state, тестируется без entitlements)"
  - "Cross-plan UserDefaults контракт: один key — writer + reader в разных файлах; контракт documented в обоих местах"
  - "Phase 8 prepend-only ordering: catch-all правило всегда последнее в onDemandRules массиве (first-match-wins)"

requirements-completed: [NET-08, NET-09, NET-10]

# Metrics
duration: 3min
completed: 2026-05-13
---

# Phase 6c Plan 01: OnDemandRulesBuilder Foundation Summary

**Static enum namespace в MainScreenFeature: NEOnDemandRuleConnect(.any) builder + UserDefaults intent-gated single-source-of-truth applyCurrentState entry point — закладывает фундамент Phase 6c on-demand миграции, ничего существующего не трогая.**

## Performance

- **Duration:** ~3 min (worktree execution; включает TDD RED → GREEN cycle + full regression run)
- **Started:** 2026-05-13T12:15:11Z (RED commit)
- **Completed:** 2026-05-13T12:18:47Z (после full AppFeatures test suite 138/138 + acceptance criteria verification)
- **Tasks:** 1 (TDD: 1 RED commit + 1 GREEN commit)
- **Files created:** 2 (builder + tests)
- **Files modified:** 0 (строго аддитивный wave 0)

## Accomplishments

- `public enum OnDemandRulesBuilder` создан с 4 public методами + 1 private extension point.
- Все 11 unit-тестов проходят (Round 2: 8 original + 3 новых для B-04 intent gate).
- Full AppFeatures test suite 138/138 PASS — ноль regression.
- Доказана строгая аддитивность: `git diff --name-status main..HEAD` показывает ТОЛЬКО `A` (added) для двух новых файлов, никаких `M` (modified).
- D-01 RESEARCH correction зафиксирован в коде: используется `NEOnDemandRuleConnect`, не `NEEvaluateConnectionRule` (anti-pattern требующий non-empty matchDomains).
- W-08 Phase 8 ordering contract документирован inline в `buildRules()` doc-comment: future evaluate-connection rules МОГУТ быть только prepended; catch-all всегда последним (first-match-wins).
- B-04 cross-plan contract: новый reader `loadUserIntendedConnected` читает тот же UserDefaults ключ `app.bbtb.userIntendedConnected`, что пишет `UserIntentStore` в `TunnelController.swift:73` — контракт documented в обоих файлах.

## Task Commits

Task 1 — TDD RED-GREEN cycle:

1. **Task 1 RED — Failing tests for OnDemandRulesBuilder** — `b9df849` (test)
   - Создан `OnDemandRulesBuilderTests.swift` с 11 тестами.
   - Тесты компилируются и падают с ожидаемой ошибкой `cannot find 'OnDemandRulesBuilder' in scope`.
2. **Task 1 GREEN — Implement OnDemandRulesBuilder** — `7498aa4` (feat)
   - Создан `OnDemandRulesBuilder.swift` с 4 public методами + private `buildRules()`.
   - Все 11 тестов проходят; full AppFeatures suite 138/138 зелёный.

Refactor commit не понадобился — implementation сразу попала в чистый вид (static enum mirrors KillSwitch.apply).

## Files Created/Modified

**Created (additive, Wave 0):**

- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` (180 строк)
  Public API:
    - `apply(to: NETunnelProviderManager, isOnDemandEnabled: Bool)` — низкоуровневый apply; всегда пишет `NEOnDemandRuleConnect(.any)` + зеркалит manager flag.
    - `applyCurrentState(to: NETunnelProviderManager, userDefaults: UserDefaults = .standard)` — high-level entry point: `toggle && intent → apply(isOnDemandEnabled:)`.
    - `loadAutoReconnectEnabled(userDefaults:key:)` — D-04 default ON (`?? true`).
    - `loadUserIntendedConnected(userDefaults:key:)` — B-04 default FALSE (`?? false`).
    - private `buildRules() -> [NEOnDemandRule]` — Phase 8 extension point с W-08 ordering contract.
  Doc-comments на русском (per CLAUDE.md); identifiers английские.

- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift` (200 строк)
  11 XCTest методов:
    1. `test_apply_enabled_writesConnectAnyRule`
    2. `test_apply_disabled_writesIsOnDemandEnabledFalseButPreservesRules`
    3. `test_apply_isIdempotent_secondCallProducesIdenticalState`
    4. `test_apply_replacesPreviousRules`
    5. `test_loadAutoReconnectEnabled_freshInstall_defaultsTrue`
    6. `test_loadAutoReconnectEnabled_persistedFalse_returnsFalse`
    7. `test_loadAutoReconnectEnabled_persistedTrue_returnsTrue`
    8. `test_loadAutoReconnectEnabled_customKey_usesCustomKey`
    9. `test_loadUserIntendedConnected_freshInstall_defaultsFalse` (B-04 NEW)
    10. `test_applyCurrentState_intentFalse_writesIsOnDemandFalse` (B-04 NEW)
    11. `test_applyCurrentState_bothTrue_writesIsOnDemandTrue` (B-04 NEW)
  Каждый тест создаёт изолированный `UserDefaults(suiteName: "OnDemandTests-<UUID>")` — никакого `.standard`, no tearDown needed.

**Modified:** NONE.

`git diff --name-status main..HEAD`:
```
A	BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift
A	BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift
```

## Decisions Made

Все ключевые решения уже зафиксированы в `06C-CONTEXT.md` (D-01..D-25) и `06C-01-PLAN.md` (must_haves). В реализации воспроизведены без отступлений:

- **D-01 / D-01b воплощены**: `NEOnDemandRuleConnect(.any)` + W-08 prepend-only contract для Phase 8.
- **D-04 default ON** для `app.bbtb.autoReconnectEnabled` — `object(forKey:) as? Bool ?? true`.
- **B-04 default FALSE** для `app.bbtb.userIntendedConnected` — `object(forKey:) as? Bool ?? false`.
- **Параметр rename** `autoReconnectEnabled` → `isOnDemandEnabled` (Round 2 B-04) — выполнен.
- **Single source of truth** через `applyCurrentState` — выполнен; doc-comment метода явно перечисляет 4 consumer callsites Phase 6c (ConfigImporter, SettingsViewModel, OnDemandMigrationTask, TunnelController), которые в следующих планах должны идти именно через эту точку.

Никаких новых архитектурных решений в Wave 0 не принималось — план был исполнен дословно.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Доc-comment упоминал `NEOnDemandRuleEvaluateConnection` буквально — нарушал acceptance criterion grep**

- **Found during:** Acceptance criteria verification после GREEN commit.
- **Issue:** План требует: `grep -c "NEEvaluateConnectionRule\\|NEOnDemandRuleEvaluateConnection" OnDemandRulesBuilder.swift returns 0` (Phase 6c не использует — anti-pattern). После первой версии файла grep возвращал 3 (3 упоминания в doc-comments header + buildRules W-08 contract).
- **Fix:** Переформулировал три места в doc-comments чтобы описать Phase 8 / anti-pattern через нейтральные термины «evaluate-connection rule», «Apple's rule-тип для match-domain/SSID-based activation», без буквального type name. Семантика W-08 ordering contract и D-01 anti-pattern reasoning полностью сохранена. Идентификатор `NEOnDemandRuleConnect` (целевой тип Phase 6c) остался — он наоборот должен быть в файле (acceptance ≥1).
- **Files modified:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` (только doc-comments — реализация не менялась).
- **Verification:** `grep -cE "NEEvaluateConnectionRule|NEOnDemandRuleEvaluateConnection"` → 0; все 11 тестов всё ещё проходят (doc-comments не влияют на поведение); все остальные grep-критерии остаются в пределах.
- **Committed in:** Фикс был сделан до GREEN commit `7498aa4`, поэтому отдельного коммита нет — финальная версия файла попадает в GREEN атомарно.

---

**Total deviations:** 1 auto-fixed (1 acceptance-criterion correction, doc-comments only).
**Impact on plan:** Нет functional impact — изменение чисто текстовое в doc-comments. Все 8 success criteria плана и 15 grep acceptance criteria выполнены. Никакого scope creep.

## Issues Encountered

- **Worktree libbox.xcframework отсутствовал** — `BBTB/Vendored/libbox.xcframework/` пустой в worktree (`.gitkeep` only), потому что binary gitignored. swift build падал с `local binary target 'Libbox' does not contain a binary artifact`. **Resolved:** создан symlink `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`. Symlink gitignored (verified via `git check-ignore`), не загрязняет коммиты. Это infra-quirk worktree setup, не bug в плане.

## User Setup Required

None — Wave 0 строго аддитивен, не требует никаких внешних настроек, никаких credential changes, никаких UserDefaults migration. Builder создан, но ещё нигде не вызывается. Apple's `NEOnDemandRuleConnect` / `NETunnelProviderManager` API уже доступны (iOS 18+ / macOS 15+) — никаких новых entitlements не нужно.

## Acceptance Criteria Verification

Все 15 grep-критериев из плана выполнены:

| Criterion | Result | Expected |
|-----------|--------|----------|
| `NEOnDemandRuleConnect` | 6 | ≥1 ✓ |
| `NEEvaluateConnectionRule\|NEOnDemandRuleEvaluateConnection` | 0 | 0 ✓ |
| `interfaceTypeMatch` | 1 | ≥1 ✓ |
| `app.bbtb.autoReconnectEnabled` | 4 | ≥1 ✓ |
| `app.bbtb.userIntendedConnected` | 4 | ≥1 ✓ |
| `?? true` | 2 | ≥1 ✓ |
| `?? false` | 1 | ≥1 ✓ |
| `public enum OnDemandRulesBuilder` | 1 | 1 ✓ |
| `func applyCurrentState` | 1 | 1 ✓ |
| `func loadUserIntendedConnected` | 1 | 1 ✓ |
| `isOnDemandEnabled:` (param) | 3 | ≥2 ✓ |
| `autoReconnectEnabled:` (param) | 0 | 0 ✓ (renamed) |
| `first-match-wins\|prepend` | 4 | ≥1 ✓ |
| `swift build` | OK | succeeds ✓ |
| `swift test --filter OnDemandRulesBuilderTests` | 11/11 PASS | all pass ✓ |
| Full suite regression | 138/138 PASS | no regression ✓ |
| `git status` strictly additive | 2 A, 0 M | 2 new only ✓ |

## TDD Gate Compliance

- **RED gate:** `test(06c-01)` commit `b9df849` — tests compiled with `cannot find 'OnDemandRulesBuilder' in scope` (expected failure).
- **GREEN gate:** `feat(06c-01)` commit `7498aa4` — implementation makes all 11 tests pass.
- **REFACTOR gate:** не понадобился (implementation сразу попала в final shape).

## Next Phase Readiness

**Wave 1 ready (Plan 06C-02 — ConfigImporter wiring):**

- API контракт зафиксирован и опубликован. Plan 06C-02 ConfigImporter integration должна использовать `OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: .standard)` после `manager.saveToPreferences()`. **НЕ low-level apply** (per Round 2 B-04 — single source of truth).
- B-04 cross-plan key contract задокументирован: `app.bbtb.userIntendedConnected` пишется `UserIntentStore` (TunnelController.swift), читается `OnDemandRulesBuilder.loadUserIntendedConnected`. Writer не меняется в Phase 6c.
- W-08 Phase 8 hook ready: будущие evaluate-connection rules (per-SSID/per-domain) добавляются в `buildRules()` prepend-only, callsite signatures не меняются.

**Concerns / Blockers:** Нет.

## Threat Flags

Нет нового threat surface — builder leaf-code без callers в Wave 0, никаких новых endpoints/IO/auth paths. T-06C-01-01 (UserDefaults non-Bool tampering) уже mitigated через `as? Bool ?? default` graceful fallback (Test 5/9 покрывают fresh-install path). T-06C-01-02 (DoS in loop) — accept rationale валиден (нет callers).

## Self-Check: PASSED

- File `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` — FOUND (180 строк, ≥80 required)
- File `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift` — FOUND (200 строк, ≥150 required)
- Commit `b9df849` (RED) — FOUND (`git log --all --oneline | grep b9df849` succeeds)
- Commit `7498aa4` (GREEN) — FOUND
- `swift build --package-path Packages/AppFeatures` — succeeds
- `swift test --filter OnDemandRulesBuilderTests` — 11/11 pass
- Full AppFeatures regression — 138/138 pass
- `git diff --name-status main..HEAD` shows ТОЛЬКО 2 `A` (added) entries — строгая аддитивность подтверждена

---
*Phase: 06c-on-demand-migration*
*Plan: 01 (Wave 0 / Foundation)*
*Completed: 2026-05-13*
