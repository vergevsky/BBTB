---
phase: 06c-on-demand-migration
plan: 03
subsystem: MainScreenFeature + SettingsFeature
tags: [on-demand, migration, watchdog, settings-ui, parallel-run]
requires:
  - "06c-on-demand-migration:01"
  - "06c-on-demand-migration:02"
provides:
  - "TunnelWatchdog actor (mid-session failover with stable-session gate + adaptive debounce)"
  - "OnDemandMigrationTask (idempotent existing-install migration with transient-failure guard)"
  - "Settings → раздел «Подключение» → переключатель «Автоматическое переподключение»"
  - "ReconnectClock + SystemReconnectClock extracted в standalone-файл (Plan 04 cleanup safety)"
  - "InstantReconnectClock extracted в TestClocks.swift (shared test seam)"
affects:
  - "BBTB/Packages/AppFeatures (5 new source files, 3 modified, 4 new test files)"
  - "BBTB/Packages/Localization (3 new keys × 2 locales)"
tech_stack:
  added:
    - "NEOnDemandRuleConnect.applyCurrentState consumer pattern в migration + Settings toggle"
    - "actor-based debounce + stable-session task pattern для watchdog"
  patterns:
    - "test seam через @Sendable closure parameter (loader: ... throws -> [NETunnelProviderManager])"
    - "internal test helpers в отдельном TestClocks.swift файле (B-02 extraction)"
key_files:
  created:
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift (39 строк)"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift (115 строк)"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift (245 строк)"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift (Task 1, в Task 1 коммите)"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift (22 строки)"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift (133 строки)"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift (303 строки)"
    - "BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift (Task 1)"
  modified:
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift (Task 2.5 — protocol + struct extracted; class остаётся)"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift (Task 2.5 — InstantReconnectClock extracted)"
    - "BBTB/Packages/AppFeatures/Package.swift (Task 1 B-09 — SettingsFeature → MainScreenFeature dep)"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift (Task 1)"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift (Task 1)"
    - "BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings (Task 1 — 3 новых key)"
decisions:
  - "D-04/D-05/D-06/D-07 (UI toggle): Settings → раздел «Подключение» → переключатель default ON; live-apply через OnDemandRulesBuilder.applyCurrentState"
  - "D-08 (4 gate'а watchdog): stable session ≥ 30s + .disconnected + managerEnabled + userIntent"
  - "D-09 (failover bridge): watchdog вызывает FailoverProviding.nextServerAttempt + исполняет returned closure"
  - "D-10 (debounce): 3 секунды после .disconnected; cancellation на .connecting / .reasserting / .connected"
  - "D-17b/c (migration): one-shot UserDefaults flag `app.bbtb.autoReconnectMigratedV6c`"
  - "B-01 (Round 2): ReconnectClock + SystemReconnectClock extracted в ReconnectClock.swift — переживут Plan 04 Task 3c удаления ReconnectStateMachine.swift"
  - "B-02 (Round 2): InstantReconnectClock extracted в TestClocks.swift с visibility internal (было private)"
  - "B-05 (Round 2): explicit do/catch вокруг каждого XPC вызова в migration; на throw флаг НЕ ставится → retry next launch"
  - "B-06: ManagerSelector.ourManagers применяется в toggle + migration — multi-manager safe"
  - "W-04: OnDemandRulesBuilder.applyCurrentState — single source of truth для всех 4 consumer-callsites"
  - "W-05 (Round 2): debounce cancellation расширена с .connecting + .connected до .connecting + .reasserting + .connected (iOS 26+ путь)"
metrics:
  start_time: "2026-05-13T15:58:00Z (resumption start)"
  duration: "~10 minutes (Task 2.5 + Task 2 + Task 3 + SUMMARY)"
  completed: "2026-05-13"
  tests_added: 14  # Task 1 уже добавил 4 → этот resumption: 5 (Migration) + 9 (Watchdog) = 14
  tests_total_appfeatures: 163  # 145 baseline + 4 (Task 1, уже в main) + 5 + 9
  commits_this_resumption: 5  # Task 2.5 + Task 2 RED + Task 2 GREEN + Task 3 RED + Task 3 GREEN
---

# Phase 6c Plan 03: On-Demand Migration / UI Toggle / Watchdog Summary

**One-liner:** Wave 2 закрывает parallel-run state — Settings UI toggle + idempotent migration для existing-install + TunnelWatchdog actor для mid-session failover; всё параллельно действующей custom-reconnect machinery (Plan 04 Wave 3 удалит старое).

## Что было сделано в этой resumption

Task 1 (Settings toggle + Package.swift edit + AutoReconnectToggleSection + Localization + 4 тестa) уже был закоммичен предыдущим агентом как `58ad4a7` до stream timeout. Этот resumption доделал Task 2.5, Task 2, Task 3, SUMMARY.

### Task 2.5 — Extract ReconnectClock + InstantReconnectClock (commit `6c8f841`)

**Round 2 B-01 + B-02 pre-condition extraction.** Перемещено `protocol ReconnectClock` + `struct SystemReconnectClock` из `ReconnectStateMachine.swift` в новый `ReconnectClock.swift` (verbatim signature — semantic no-op shift, тот же module). Перемещён `actor InstantReconnectClock` из вложенного private declaration в `TunnelControllerStateTests.swift` в `TestClocks.swift` с visibility `internal` (теперь shared seam для `TunnelWatchdogTests`).

**Цель:** survive Plan 04 Task 3c удаления `ReconnectStateMachine.swift` + `TunnelControllerStateTests.swift`. Watchdog зависит от `ReconnectClock` — без extraction он сломался бы после Plan 04 cleanup.

**Verification:**
- `grep -c "protocol ReconnectClock"` в `ReconnectClock.swift` == 1, в `ReconnectStateMachine.swift` == 0.
- `grep -c "actor InstantReconnectClock"` в `TestClocks.swift` == 1, в `TunnelControllerStateTests.swift` == 0.
- `ReconnectStateMachine` class остаётся в `ReconnectStateMachine.swift` (parallel-run invariant).
- Full AppFeatures test suite green после extract (109 tests).

### Task 2 — OnDemandMigrationTask (RED commit `8a2ff2a` → GREEN commit `9846981`)

Idempotent one-shot task для existing-install upgrade path. Six-branch decision tree:

1. Флаг уже true → no-op.
2. `loadAllFromPreferences` throws → **флаг НЕ ставится** (B-05 transient-failure safety), retry next launch.
3. Empty managers → флаг = true (fresh install).
4. `ManagerSelector.ourManagers` пусто (есть чужие, нет наших) → флаг = true.
5. Для каждого нашего: `applyCurrentState` + save + reload; на любой throw — флаг НЕ ставится.
6. Все succeeded → флаг = true, post `.bbtbProvisionerDidSave`.

**Round 2 invariants:**
- **B-05:** замена Round 1 паттерна (try-question-mark) на явные do/catch — transient XPC failure НЕ маскирует под confirmed-empty.
- **B-06:** через `ManagerSelector.ourManagers` фильтруем только наши NEMs.
- **W-04:** используем `applyCurrentState` (single source of truth), НЕ низкоуровневый apply.
- **B-03:** на successful batch постим `.bbtbProvisionerDidSave` для TunnelController cache refresh.

**Test seam:** API параметр `loader: @Sendable () async throws -> [NETunnelProviderManager]` с default = real `loadAllFromPreferences` позволяет тестам подменить на closure, который throws.

**5 тестов:**
1. `test_runIfNeeded_alreadyMigrated_isNoOp` — флаг true → no-op (loader не вызывается).
2. `test_runIfNeeded_loadAllThrows_doesNotSetFlag` — **NEW Round 2 B-05** — на throw флаг остаётся false.
3. `test_runIfNeeded_emptyManagers_setsFlag` — confirmed-empty → флаг ставится.
4. `test_runIfNeeded_isIdempotent_twoCallsSafe` — два вызова, loader дёргается ровно 1 раз.
5. `test_runIfNeeded_respectsTogglePersisted` — migration не трогает toggle.

### Task 3 — TunnelWatchdog actor (RED commit `6fc6427` → GREEN commit `f50a868`)

Узко-целевой actor для mid-session failover. Параллелен Apple's on-demand reconnect: Apple retry'ит тот же мёртвый сервер, watchdog знает о пуле и swap'ит на следующий через `SwiftDataFailoverProvider.nextServerAttempt`.

**Public API:**
```swift
public actor TunnelWatchdog {
    public init(failoverProvider: any FailoverProviding,
                stableSessionThreshold: TimeInterval = 30,
                disconnectDebounce: TimeInterval = 3,
                clock: ReconnectClock = SystemReconnectClock())
    public func handleStatusChange(_ status: NEVPNStatus, managerEnabled: Bool) async
    public func setUserIntent(_ intent: Bool) async
    // 3 internal test seams: getStableSessionForTest, getUserIntentForTest, getDebounceActiveForTest.
}
```

**State machine:**
- `.connected` → cancel debounce, arm stable-session task (через `clock.sleep(threshold)`); по истечении — `stableSession = true`.
- `.disconnected` → если все 4 gate'а (userIntent + managerEnabled + stableSession + нет pending debounce) → arm debounce task (через `clock.sleep(debounce)`); по истечении — call `failoverProvider.nextServerAttempt`, execute attempt closure.
- `.connecting` / `.reasserting` → cancel debounce (Apple's on-demand выиграл race; не fire failover).
- `setUserIntent(false)` → cancel everything, reset stableSession.

**Round 2 W-05:** `.reasserting` теперь тоже отменяет debounce (Round 1 отменял только `.connecting`). iOS 26+ путь — Apple's on-demand попадает в reasserting state до full reconnect, без W-05 watchdog ошибочно бы продолжил debounce и вызвал double-failover.

**XPC-free invariant:** все статусы (`NEVPNStatus`, `managerEnabled`) приходят как arguments. Никаких `loadAllFromPreferences` или чтения `connection.status` внутри watchdog'а.

**Cycle prevention:** `failoverProvider` хранится strong; внутри `SwiftDataFailoverProvider` есть `[weak tunnelController]` в `connect` closure — нет cycle.

**9 тестов:**
1. `test_disconnectedBeforeStableSession_noFailover` — без stable session failover не fires.
2. `test_stableSession_disconnected_firesFailoverAfterDebounce` — happy path.
3. `test_disconnectButManagerDisabled_noFailover` — managerEnabled=false блокирует.
4. `test_disconnectButNoUserIntent_noFailover` — userIntent=false блокирует.
5. `test_debounceCancelledByReconnect` — `.connecting` отменяет debounce.
6. `test_debounceCancelledByReasserting` — **NEW Round 2 W-05** — `.reasserting` тоже отменяет.
7. `test_userIntentFalseResetsState` — `setUserIntent(false)` сбрасывает stableSession.
8. `test_failoverNextNil_noAttemptExecuted` — пул исчерпан → nil safe.
9. `test_failoverNextNonNil_attemptInvoked` — attempt closure выполняется ровно 1 раз.

## Confirmations

- **Полный AppFeatures suite green:** **163 тестов** (145 baseline + 4 Settings от Task 1 + 5 Migration + 9 Watchdog). 0 failures.
- **`TunnelControllerStateTests` все ещё проходит** после extract Task 2.5 (18 тестов, 0 regressions).
- **TunnelController.swift НЕ изменён** в этой wave (parallel-run invariant strict). `grep -c "TunnelWatchdog\|OnDemandMigrationTask"` в TunnelController.swift == 0.
- **NetworkReachability.swift НЕ изменён** в этой wave.
- **ReconnectStateMachine class body НЕ изменён** — Task 2.5 только удалил extracted protocol + struct declarations; класс сам нетронут до Plan 04 Task 3c.

## Round 2 fixes — landed status

| Code | Что | Где |
|------|-----|-----|
| B-01 | ReconnectClock + SystemReconnectClock extracted | `ReconnectClock.swift` (commit `6c8f841`) |
| B-02 | InstantReconnectClock extracted, internal | `TestClocks.swift` (commit `6c8f841`) |
| B-03 | bbtbProvisionerDidSave posted после batch migration | `OnDemandMigrationTask.swift` (commit `9846981`) |
| B-04 | applyCurrentState единая точка (cross-plan contract) | `OnDemandMigrationTask.swift` (commit `9846981`) + Task 1 (Settings) commit `58ad4a7` |
| B-05 | explicit do/catch + flag NOT set on transient throw | `OnDemandMigrationTask.swift` (commit `9846981`) |
| B-06 | ManagerSelector.ourManagers применяется | `OnDemandMigrationTask.swift` (commit `9846981`) + Task 1 commit `58ad4a7` |
| B-09 | Package.swift SettingsFeature → MainScreenFeature dep | Task 1 commit `58ad4a7` |
| W-03 | applyAutoReconnectToManager nonisolated | Task 1 commit `58ad4a7` |
| W-04 | applyCurrentState единая точка (no wrapper) | Task 1 commit `58ad4a7` + Task 2 commit `9846981` |
| W-05 | debounce cancellation расширена на .reasserting | `TunnelWatchdog.swift` (commit `f50a868`) |

## Commit log этой resumption

```
f50a868  feat(06c-03): TunnelWatchdog actor — mid-session failover with .reasserting cancellation (Task 3 — D-08/09/10 + W-05)
6fc6427  test(06c-03): add failing tests for TunnelWatchdog (Task 3 RED)
9846981  feat(06c-03): OnDemandMigrationTask — idempotent existing-install migration with transient-failure guard (Task 2 — D-17b/c + B-05)
8a2ff2a  test(06c-03): add failing tests for OnDemandMigrationTask (Task 2 RED)
6c8f841  refactor(06c-03): extract ReconnectClock + InstantReconnectClock to standalone files (Task 2.5 — B-01/B-02 pre-condition for Plan 04 cleanup)
```

Plus Task 1 commit `58ad4a7` (предыдущий агент, уже на main).

## Что НЕ сделано в этой wave (по плану)

Эти пункты — Wave 3 / Plan 06C-04:

1. **Wiring `OnDemandMigrationTask.runIfNeeded()` в App init** (BBTB_iOSApp + BBTB_macOSApp).
2. **Wiring `TunnelWatchdog` в TunnelController** — cachedManager + bbtbProvisionerDidSave observer для B-03 fix.
3. **Удаление старой machinery:**
   - `ReconnectStateMachine.swift` (но `ReconnectClock.swift` SURVIVES — Round 2 B-01 contract).
   - `NetworkReachability.swift`.
   - `TunnelControllerStateTests.swift` (но `TestClocks.swift` SURVIVES — Round 2 B-02 contract).
   - Related tests (`ReconnectStateMachineTests.swift`).
   - Custom-reconnect branches в TunnelController.
4. **Preserve:** macOS `NSWorkspace.didWakeNotification` observer (D-11/12/13) с 3 guards (W-06).
5. **Banner enum trim + audit** (W-02).
6. **Task 3 split into 3a/3b/3c** per W-01.

## UAT notes для Plan 06C-04

**Pitfall 5 race (watchdog vs Apple's on-demand)** requires explicit device test — UAT-Task E.
Hard-blocker UAT set per B-10: {A, C, E, F, G, I}.

## References

**Decisions:** D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11, D-12, D-13, D-17b, D-17c.
**Round 2 fixes:** B-01, B-02, B-03, B-04, B-05, B-06, B-09, W-03, W-04, W-05.
**Pitfalls mitigated (RESEARCH.md):** Pitfall 1 (existing-install migration), Pitfall 4 (toggle OFF не tear-down), Pitfall 5 (parallel-run accepted), Pitfall 10 (Apple's on-demand race window).

## Self-Check: PASSED

- ReconnectClock.swift FOUND
- TestClocks.swift FOUND
- OnDemandMigrationTask.swift FOUND
- OnDemandMigrationTaskTests.swift FOUND (5 tests pass)
- TunnelWatchdog.swift FOUND
- TunnelWatchdogTests.swift FOUND (9 tests pass)
- Commit 6c8f841 FOUND (Task 2.5)
- Commit 8a2ff2a FOUND (Task 2 RED)
- Commit 9846981 FOUND (Task 2 GREEN)
- Commit 6fc6427 FOUND (Task 3 RED)
- Commit f50a868 FOUND (Task 3 GREEN)
- Commit 58ad4a7 FOUND (Task 1, предыдущий агент)
- Full AppFeatures test suite: 163/163 PASS
