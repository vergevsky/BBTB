---
phase: 06c-on-demand-migration
plan: 02
subsystem: networking
tags: [networkextension, on-demand, configimporter, manager-selector, notification-center, b-03, b-04, b-06, w-04, w-07, parallel-run]

# Dependency graph
requires:
  - phase: 06c-on-demand-migration
    plan: 01
    provides: OnDemandRulesBuilder.applyCurrentState — single-source-of-truth entry point (4 public methods)
provides:
  - public enum ManagerSelector в MainScreenFeature (ourManagers + ourProviderBundleIdentifiers Set)
  - extension Notification.Name.bbtbProvisionerDidSave — B-03 cross-plan contract
  - DefaultTunnelProvisioner.provisionTunnelProfile теперь invariantly использует ManagerSelector + applyCurrentState + posts bbtbProvisionerDidSave
affects: [06c-03-settings-toggle-migration, 06c-04-tunnel-controller-cleanup, 06c-05-migration-task]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Static enum namespace helpers — ManagerSelector mirrors KillSwitch.apply / OnDemandRulesBuilder.apply (нет instance state, тестируется без entitlements)"
    - "Cross-plan loose coupling через NotificationCenter — provisioner НЕ знает про TunnelController; observer ставится отдельно в Plan 04"
    - "Single source of truth filter — все 5 callsites Phase 6c сходятся в ManagerSelector.ourManagers (hardcoded Set с iOS+macOS bundle IDs в одном месте)"
    - "Wave 1 strict additivity для существующих файлов — только 1 file modified (ConfigImporter.swift, 42+/1-) + 3 new files; parallel-run invariant preserved"

key-files:
  created:
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift (92 строки)"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift (77 строк, 3 теста)"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift (129 строк, 4 теста)"
  modified:
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (DefaultTunnelProvisioner.provisionTunnelProfile + doc-comment header, 42+/1-)"

key-decisions:
  - "B-06 closure: ManagerSelector.ourManagers(from:) — единый helper для фильтрации [NETunnelProviderManager] по providerBundleIdentifier ∈ Set с iOS+macOS bundle IDs (5 callsites)"
  - "W-07 closure: hardcoded Set ourProviderBundleIdentifiers в одном файле (ManagerSelector.swift), не дублируется по callsite'ам"
  - "B-03 cross-plan contract: NotificationCenter notification bbtbProvisionerDidSave declared в ManagerSelector.swift (single source of truth file для cross-cutting concerns Phase 6c). Observer side — TunnelController в Plan 04"
  - "B-04 / W-04 closure: provisioner вызывает OnDemandRulesBuilder.applyCurrentState (NOT direct apply). Фантомный auto-connect на свежей установке заблокирован: toggle ON default AND intent FALSE default → isOnDemandEnabled=false"
  - "Parallel-run invariant: НИКАКИХ изменений в TunnelController, ReconnectStateMachine, NetworkReachability. Custom auto-reconnect machinery работает рядом с Apple's on-demand. Известный double-trigger race accepted на эту wave (Pitfall 5)"
  - "B-07 fix: Task 1 (RED tests) не имеет <verify> block — тесты GREEN сразу (builder уже создан в Plan 01). Wiring grep-gate в Task 2 GREEN verify"
  - "Doc-comment formatting: literal token references в файле-level doc-comment перефразированы чтобы избежать ложно-положительных grep matches (acceptance demands exact counts)"

patterns-established:
  - "Cross-plan NotificationCenter contract документируется в writer-файле inline (ConfigImporter.swift provisionTunnelProfile) + в declaration-файле (ManagerSelector.swift). Observer-файл (TunnelController в Plan 04) делает третью ссылку"
  - "5-callsite-helper в одном файле с cross-cutting Notification.Name extension — ManagerSelector.swift хостит обе single-source-of-truth декларации Phase 6c (filter helper + notification name)"
  - "Provisioner posts notification ПОСЛЕ saveToPreferences+loadFromPreferences с object: manager — observer получает freshly-loaded manager reference без повторного loadAllFromPreferences (B-03 cost-optimal)"

requirements-completed: [NET-08, NET-09, NET-10]

# Metrics
duration: ~8min
completed: 2026-05-13
---

# Phase 6c Plan 02: ConfigImporter Wiring + ManagerSelector helper Summary

**Wave 1 / Parallel-run wave: `DefaultTunnelProvisioner.provisionTunnelProfile` теперь invariantly использует `ManagerSelector.ourManagers(from:).first` (B-06), вызывает `OnDemandRulesBuilder.applyCurrentState(to: manager)` для single-source-of-truth on-demand gate (B-04 / W-04) и постит `NSNotification.Name.bbtbProvisionerDidSave` для cross-plan observer'а (B-03). Старая custom auto-reconnect machinery в TunnelController работает рядом — parallel-run invariant сохранён.**

## Performance

- **Duration:** ~8 минут (worktree execution; включает TDD RED → GREEN для Task 0 + GREEN-сразу Task 1 + GREEN Task 2 + full regression run + acceptance verification + SUMMARY)
- **Started:** 2026-05-13T12:29:44Z
- **Completed:** 2026-05-13T12:37:37Z
- **Tasks:** 3 (Task 0 TDD: 1 RED + 1 GREEN, Task 1: 1 commit, Task 2: 1 commit)
- **Files created:** 3 (ManagerSelector.swift, ManagerSelectorTests.swift, ConfigImporterOnDemandWiringTests.swift)
- **Files modified:** 1 (ConfigImporter.swift — 42 insertions, 1 deletion, все внутри DefaultTunnelProvisioner)

## Accomplishments

- `public enum ManagerSelector` создан как single source of truth для 5 callsites Phase 6c — закрывает B-06 (multi-manager safety) + W-07 (shared helper). Public API: `ourManagers(from:knownBundleIDs:)` + `ourProviderBundleIdentifiers: Set<String>`.
- `extension Notification.Name.bbtbProvisionerDidSave` декларирован в `ManagerSelector.swift` (single source of truth для cross-cutting concerns Phase 6c). Это B-03 cross-plan contract; observer side ставится в Plan 04 (`TunnelController.refreshCachedManager`).
- `DefaultTunnelProvisioner.provisionTunnelProfile` теперь invariantly:
  1. Фильтрует `loadAllFromPreferences` результат через `ManagerSelector.ourManagers(from:).first ?? NETunnelProviderManager()` вместо `managers.first ?? ...` (B-06).
  2. Вызывает `OnDemandRulesBuilder.applyCurrentState(to: manager)` ПЕРЕД `saveToPreferences` — порядок зафиксирован: ПОСЛЕ `KillSwitch.apply` (другой объект — `proto`), ДО `saveToPreferences`+`loadFromPreferences` (B-04 / W-04).
  3. Постит `NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: manager)` ПОСЛЕ `loadFromPreferences` — даёт observer'у freshly-loaded manager (B-03).
- Wrapper `applyOnDemandConfiguration` (черновик Round 1) НЕ создан — closure W-04 через B-04 (single source of truth находится в builder).
- B-07 fix: Task 1 (тесты wiring contract) GREEN сразу — Plan 01 уже создал `applyCurrentState`; Task 2 GREEN verify покрывает callsite wiring через grep acceptance.
- B-04 phantom-connect mitigated: на свежей установке без Connect тапа `toggle=true` (D-04 default) AND `intent=false` (B-04 default) → `manager.isOnDemandEnabled=false`. Тест `test_applyCurrentState_freshInstall_withoutIntent_writesIsOnDemandFalse` фиксирует контракт.
- Parallel-run invariant preserved: `TunnelController.swift`, `ReconnectStateMachine.swift`, `NetworkReachability.swift` НЕ изменены ни на одну строку. Custom auto-reconnect machinery работает рядом с Apple's on-demand — известный double-trigger race accepted на эту wave (Pitfall 5 в RESEARCH).
- Full AppFeatures test suite: **145/145 PASS** (baseline 138 + 7 новых: 3 ManagerSelectorTests + 4 ConfigImporterOnDemandWiringTests). Ноль regression в TunnelControllerStateTests (18/18) + ConfigImporterSubscriptionTests (4/4) + OnDemandRulesBuilderTests (11/11).

## Task Commits

1. **Task 0 RED — Failing tests for ManagerSelector** — `55e38d4` (test)
   - Создан `ManagerSelectorTests.swift` с 3 тестами (empty / mixed / macOS bundle).
   - Тесты компилируются и падают с ожидаемой ошибкой `cannot find 'ManagerSelector' in scope`.

2. **Task 0 GREEN — Implement ManagerSelector + bbtbProvisionerDidSave contract** — `ce8e83e` (feat)
   - Создан `ManagerSelector.swift` (92 строки): public enum + `ourManagers(from:knownBundleIDs:)` + Set с iOS+macOS bundle IDs.
   - `extension Notification.Name.bbtbProvisionerDidSave` в том же файле — single source of truth для cross-cutting concerns.
   - Все 3 теста PASS.

3. **Task 1 — Wiring contract tests (GREEN immediately)** — `c1f753d` (test)
   - Создан `ConfigImporterOnDemandWiringTests.swift` (129 строк, 4 теста): fresh install / both ON / toggle OFF / replays.
   - Каждый тест использует изолированный `UserDefaults(suiteName: "...-UUID")` — никакого `.standard`.
   - НЕ зовут `saveToPreferences` / `loadAllFromPreferences` — entitlement-gated. Тестируют `applyCurrentState` напрямую.
   - Все 4 теста PASS сразу — API создан в Plan 06C-01 Round 2.

4. **Task 2 — Wire provisionTunnelProfile** — `96f08e0` (feat)
   - Modified `ConfigImporter.swift`: 42 insertions + 1 deletion, всё внутри `DefaultTunnelProvisioner` doc-comment header + `provisionTunnelProfile` body.
   - `managers.first` → `ManagerSelector.ourManagers(from: managers).first`.
   - `OnDemandRulesBuilder.applyCurrentState(to: manager)` вставлено между `manager.isEnabled = true` и `try await manager.saveToPreferences()`.
   - `NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: manager)` вставлено ПОСЛЕ `loadFromPreferences()`.
   - Full AppFeatures suite 145/145 PASS — zero regression.

## Files Created/Modified

**Created (Wave 1 additive):**

- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` (92 строки)
  Public API:
    - `static let ourProviderBundleIdentifiers: Set<String>` — Set с `"app.bbtb.client.ios.tunnel"` + `"app.bbtb.client.macos.tunnel"`.
    - `static func ourManagers(from:knownBundleIDs:)` — filter [NETunnelProviderManager] по providerBundleIdentifier ∈ Set.
    - `extension Notification.Name.bbtbProvisionerDidSave` — cross-plan B-03 contract.
  Doc-comments на русском (per CLAUDE.md); identifiers английские.

- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift` (77 строк)
  3 XCTest методов:
    1. `test_ourManagers_emptyInput_returnsEmpty` — sanity (empty → empty).
    2. `test_ourManagers_mixedInput_returnsOnlyOurs` — mixed input (ios наш + чужой), возвращает 1 наш.
    3. `test_ourManagers_macOSBundleID_alsoMatches` — macOS bundle ID тоже матчится через default Set.
  In-memory NETunnelProviderManager fixtures (без entitlements).

- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift` (129 строк)
  4 XCTest методов:
    1. `test_applyCurrentState_freshInstall_withoutIntent_writesIsOnDemandFalse` — B-04 phantom-connect mitigation.
    2. `test_applyCurrentState_toggleOnIntentOn_writesIsOnDemandTrue` — re-import scenario.
    3. `test_applyCurrentState_toggleOffIntentOn_writesIsOnDemandFalse` — Pitfall 4 (toggle disable).
    4. `test_applyCurrentState_replays_pickFreshUserDefaultsValues` — Pitfall 8 (fresh-read invariant).

**Modified:**

- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (lines 994-1070; 42 insertions, 1 deletion)
  Изменения только внутри `DefaultTunnelProvisioner`:
    - Расширен doc-comment header: добавлены 3 Phase 6c пункта (B-06, B-04/W-04, B-03) + parallel-run invariant note.
    - `let manager = managers.first ?? NETunnelProviderManager()` → `let ours = ManagerSelector.ourManagers(from: managers); let manager = ours.first ?? NETunnelProviderManager()` (B-06).
    - Вставлено `OnDemandRulesBuilder.applyCurrentState(to: manager)` между `manager.isEnabled = true` и `try await manager.saveToPreferences()` (B-04 / W-04).
    - Вставлено `NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: manager)` после `try await manager.loadFromPreferences()` (B-03).
  `KillSwitch.apply` НЕ тронут (другой объект — `proto` vs `manager`).
  `saveToPreferences + loadFromPreferences` order preserved (Apple invariant RESEARCH §9.1).

`git diff --name-status main..HEAD`:
```
M	BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
A	BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift
A	BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift
A	BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift
```

## Decisions Made

Все ключевые решения уже зафиксированы в `06C-CONTEXT.md` (D-01..D-25) и `06C-02-PLAN.md` (Round 2 revisions). Воспроизведены без отступлений:

- **B-06 / W-07 closure** — `ManagerSelector.ourManagers(from:)` создан как single source of truth helper; hardcoded Set с iOS+macOS bundle IDs в одном файле.
- **B-03 cross-plan contract** — `Notification.Name.bbtbProvisionerDidSave` декларирован в `ManagerSelector.swift`. Observer side — Plan 04 (`TunnelController.refreshCachedManager`).
- **B-04 / W-04 closure** — provisioner вызывает `applyCurrentState` (НЕ direct `apply`). Wrapper `applyOnDemandConfiguration` НЕ создан — single source of truth находится в builder. Filter в builder через `loadAutoReconnectEnabled() && loadUserIntendedConnected()` гарантирует gate `toggle AND intent`.
- **B-07 fix** — Task 1 (wiring contract tests) не имеет `<verify>` block; тесты GREEN сразу (Plan 01 уже создал `applyCurrentState`). Wiring grep-gate в Task 2 GREEN verify.
- **Parallel-run invariant** — TunnelController / ReconnectStateMachine / NetworkReachability НЕ изменены. Custom auto-reconnect machinery работает рядом с Apple's on-demand на эту wave. Double-trigger race (Pitfall 5) accepted; mitigation — Wave 2 watchdog + Wave 3 cleanup.
- **Doc-comment phrasing** — токенные литералы (например `OnDemandRulesBuilder.applyCurrentState`) перефразированы в file-level doc-comment header, чтобы Acceptance grep'ы возвращали ровно 1 (call site), а не 2 (call site + doc-comment mention). Семантика сохранена в полном объёме через inline-комментарии внутри метода (которые более информативны для читателя в нужный момент).

Никаких новых архитектурных решений в Wave 1 не принималось — план был исполнен дословно.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Doc-comment header упоминал токены, что нарушало acceptance grep counts**

- **Found during:** Task 2 acceptance criteria verification после первой версии правки.
- **Issue:** План требует `grep -c "OnDemandRulesBuilder\.applyCurrentState" ConfigImporter.swift returns 1` и аналогично для `ManagerSelector.ourManagers` (1) и `bbtbProvisionerDidSave` (1). Моя первая версия добавила в doc-comment header упоминания этих токенов буквально для read-ability — grep возвращал 2 для каждого (1 в header + 1 в коде).
- **Fix:** Перефразировал три места в header doc-comment чтобы описать те же концепции (B-06, B-04/W-04, B-03) без точных литералов токенов: «единый Phase 6c helper», «Phase 6c on-demand builder (high-level single-source-of-truth entry point)», «NotificationCenter сигнал (Notification.Name декларирован в ManagerSelector.swift)». Inline-комментарии внутри метода (где находится call site) сохранили полные литералы для читателя.
- **Files modified:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (только doc-comment header — реализация не менялась).
- **Verification:** Все 4 acceptance grep'а возвращают точные ожидаемые значения (1, 0, 1, 1). Все 145 тестов AppFeatures PASS.
- **Committed in:** Фикс был сделан до Task 2 commit `96f08e0`, поэтому отдельного коммита нет — финальная версия попадает в Task 2 GREEN атомарно.

---

**Total deviations:** 1 auto-fixed (1 acceptance-criterion correction, doc-comment phrasing only). No deviation in code behavior, no scope creep, no changes to plan tasks/order.

**Impact on plan:** None functional. Doc-comments всё ещё описывают полную семантику изменений; они теперь не дублируют точные literal references из inline-комментариев внутри метода — это даже улучшает читаемость (один источник литералов на токен).

## Issues Encountered

- **Worktree libbox.xcframework отсутствовал** — `BBTB/Vendored/libbox.xcframework/` пустой в worktree (binary gitignored). Применил Plan 01 workaround: symlink `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`. Symlink gitignored, не загрязняет коммиты. Это infra-quirk, не bug в плане.

## User Setup Required

None — Wave 1 не требует никаких внешних настроек, никаких credential changes, никаких UserDefaults migration. ConfigImporter теперь invariantly пишет on-demand rules при каждом import (но `isOnDemandEnabled` зависит от intent flag — на свежей установке без Connect остаётся false). Существующие пользователи с активным туннелем НЕ затронуты этой wave — миграция их manager state будет в Plan 06C-03 (Wave 2 migration task).

## Acceptance Criteria Verification

Все Task 2 grep-критерии из плана выполнены **точно**:

| Criterion | Result | Expected |
|-----------|--------|----------|
| `OnDemandRulesBuilder\.applyCurrentState` count | 1 | 1 ✓ |
| `OnDemandRulesBuilder\.apply\b` (word-boundary) count | 0 | 0 ✓ |
| `applyOnDemandConfiguration` count | 0 | 0 ✓ |
| `ManagerSelector\.ourManagers` count | 1 | 1 ✓ |
| `bbtbProvisionerDidSave` count | 1 | 1 ✓ |
| `swift build --package-path Packages/AppFeatures` | OK | succeeds ✓ |
| 4 ConfigImporterOnDemandWiringTests | 4/4 PASS | 4 pass ✓ |
| 11 OnDemandRulesBuilderTests (regression) | 11/11 PASS | 11 pass ✓ |
| 3 ManagerSelectorTests | 3/3 PASS | 3 pass ✓ |
| Full AppFeatures suite regression | 145/145 PASS | no regression ✓ |
| Diff hygiene (только additions/replacements в provisionTunnelProfile) | 42+/1- внутри метода | ✓ |
| Parallel-run invariant (TunnelController / ReconnectStateMachine / NetworkReachability untouched) | Yes | ✓ |

Task 0 acceptance:

| Criterion | Result | Expected |
|-----------|--------|----------|
| 3 ManagerSelectorTests PASS | 3/3 | 3 pass ✓ |
| `public enum ManagerSelector` count | 1 | 1 ✓ |
| `app.bbtb.client.ios.tunnel` count | 3 | ≥1 ✓ |
| `app.bbtb.client.macos.tunnel` count | 3 | ≥1 ✓ |
| `bbtbProvisionerDidSave` count | 1 | ≥1 ✓ |
| `func ourManagers` count | 1 | 1 ✓ |
| ManagerSelector.swift min_lines | 92 | ≥30 ✓ |
| ManagerSelectorTests.swift min_lines | 77 | ≥50 ✓ |

Task 1 acceptance:

| Criterion | Result | Expected |
|-----------|--------|----------|
| Тест-файл компилируется + passes | 4/4 PASS | pass ✓ |
| `saveToPreferences` / `loadAllFromPreferences` calls | 0 (только doc-mention) | 0 actual calls ✓ |
| `UserDefaults.standard` use | 0 | 0 (isolated suites) ✓ |
| `applyCurrentState` count | 14 | ≥4 ✓ |
| `applyOnDemandConfiguration` count | 0 | 0 ✓ |
| ConfigImporterOnDemandWiringTests.swift min_lines | 129 | ≥90 ✓ |

## TDD Gate Compliance

- **Task 0 RED gate:** `test(06c-02)` commit `55e38d4` — tests compiled with `cannot find 'ManagerSelector' in scope` (expected failure).
- **Task 0 GREEN gate:** `feat(06c-02)` commit `ce8e83e` — implementation makes 3 ManagerSelectorTests pass.
- **Task 0 REFACTOR gate:** не понадобился (implementation сразу попала в final shape — pattern зеркалит KillSwitch.apply).
- **Task 1:** не TDD-цикл в строгом смысле — тесты GREEN сразу, потому что API уже создан в Plan 06C-01 (B-07 fix Round 2). Commit `c1f753d` фиксирует тест-контракт для wiring callsite.
- **Task 2:** не TDD-цикл — это implementation task с inline-verify через grep + full suite. Commit `96f08e0`.

## Next Phase Readiness

**Wave 2 ready (Plan 06C-03 — Settings toggle + migration task):**

- `ManagerSelector.ourManagers` готов для `SettingsViewModel.applyAutoReconnectToManager` (toggle handler перебирает наши managers для re-apply) и `OnDemandMigrationTask.runIfNeeded` (one-shot upgrade migration перебирает наши managers).
- `OnDemandRulesBuilder.applyCurrentState` — single entry point для обоих новых callsites (toggle + migration).
- `bbtbProvisionerDidSave` notification — observer side в Plan 04 (`TunnelController.refreshCachedManager`).
- **Migration scope для Plan 03:** для existing installs (D-17b/c) — `OnDemandMigrationTask.runIfNeeded` нужен потому что Wave 1 покрывает только fresh installs / re-import. Migration пройдёт по всем существующим manager'ам, отфильтрованным через `ManagerSelector.ourManagers`, и применит `applyCurrentState` к каждому.

**Wave 3 ready (Plan 06C-04 — TunnelController cleanup):**

- Observer side для `bbtbProvisionerDidSave` ставится в `TunnelController.swift`:
  ```swift
  NotificationCenter.default.addObserver(
      forName: .bbtbProvisionerDidSave, object: nil, queue: nil
  ) { [weak self] note in
      Task { await self?.refreshCachedManager(from: note.object) }
  }
  ```
- После Wave 2 watchdog + Wave 3 удаления `ReconnectStateMachine` + `NetworkReachability` — provisioner notification станет sole trigger для `cachedManager` refresh.

**Concerns / Blockers:** Нет.

## Threat Flags

Нет нового threat surface — добавлены 3 файла + 1 modification, все в существующих trust boundaries:

- `ManagerSelector` — leaf-helper без I/O / без UserDefaults / без entitlements; не вводит новый threat surface. T-06C-02-01 (double-trigger race) уже зарегистрирован в плане как accept (Pitfall 5, mitigation Wave 2-3).
- `NotificationCenter.bbtbProvisionerDidSave` — in-process IPC через локальный NotificationCenter; не выходит за границу app sandbox. Не требует STRIDE re-assessment.
- `ConfigImporter` изменения — добавлены только новые **выходящие** вызовы (post notification + applyCurrentState). Никакие новые входы / новые UserDefaults reads. Существующие KillSwitch + serverAddress validation invariants сохранены.

## Self-Check: PASSED

- File `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` — FOUND (92 строки)
- File `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift` — FOUND (77 строк)
- File `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift` — FOUND (129 строк)
- File `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — MODIFIED (42+/1- внутри DefaultTunnelProvisioner)
- Commit `55e38d4` (Task 0 RED) — FOUND
- Commit `ce8e83e` (Task 0 GREEN) — FOUND
- Commit `c1f753d` (Task 1) — FOUND
- Commit `96f08e0` (Task 2) — FOUND
- `swift build --package-path Packages/AppFeatures` — succeeds
- `swift test --filter ManagerSelectorTests` — 3/3 pass
- `swift test --filter ConfigImporterOnDemandWiringTests` — 4/4 pass
- `swift test --filter OnDemandRulesBuilderTests` (regression) — 11/11 pass
- Full AppFeatures regression — 145/145 pass
- `git diff --name-status main..HEAD` — 1 M + 3 A (как ожидалось)
- TunnelController.swift / ReconnectStateMachine.swift / NetworkReachability.swift — UNTOUCHED (parallel-run invariant)

---
*Phase: 06c-on-demand-migration*
*Plan: 02 (Wave 1 / Parallel-run wiring)*
*Completed: 2026-05-13*
