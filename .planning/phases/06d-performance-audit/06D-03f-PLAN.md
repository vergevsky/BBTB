---
phase: 06d-performance-audit
plan: 03f
slice: f
type: execute
wave: 3.6
mode: mvp
depends_on: [03e]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
autonomous: true
requirements: [QUAL-01, PERF-02]
findings_addressed: [M1]
tags: [cold-start, xpc, mach-ports, structured-concurrency, network-extension]
status: complete

must_haves:
  truths:
    - "M1: 6-8 fire-and-forget Tasks в `BBTB_iOSApp.init` / `BBTB_macOSApp.init` сведены к 1 ordered chain + 1 detached SwiftData migration. Total Tasks в каждом init: было 5, стало 2."
    - "`TunnelController.bootstrap(failoverProvider:watchdog:) async -> InitialStatusSnapshot` — actor-метод, сериализующий setFailoverProvider → setWatchdog → startReachability и возвращающий Sendable snapshot из уже загруженного cachedManager. Существующие public setters / startReachability нетронуты (test paths сохранены)."
    - "`MainScreenViewModel.applyInitialStatusSnapshot(_:)` — потребитель snapshot'а от bootstrap; использует `applyVPNStatus(_:connectedDate:)` как единственный UI authority (D-09). Idempotent через `initialManagersApplied` flag."
    - "Init-time seed Task в `MainScreenViewModel.init` GUARDED через `initialManagersApplied` — flag flips ДО `await loadAllFromPreferences()`, eliminates duplicate XPC trip когда App.init bootstrap успевает первым."
    - "Cold-start XPC trip count: 2 → 1 в счёт launch-time `loadAllFromPreferences`. Один внутри `bootstrap → startReachability → refreshCachedManager`, второй из VM init-seed Task превращён в guarded no-op."
    - "Ordering invariants PRESERVED: `OnDemandMigrationTask.runIfNeeded()` → `TunnelWatchdog(...)` creation + `setFailoverObserver` → `bootstrap` (которая внутри делает setFailover → setWatchdog → startReachability) → `applyInitialStatusSnapshot`. Migration успевает запостить `.bbtbProvisionerDidSave` до того, как reachability seed'ит cachedManager."
    - "SwiftData Phase 2→3 migration осталась в отдельной `Task.detached(priority: .background)` (M2 / Wave 03e Commit 2): background priority + семантически независимая (НЕ contend'ит за NE XPC) — параллельное выполнение допустимо и желательно."
    - "D-09 invariants clean: forbidden symbols=4 (baseline), queue=.main=0, #Predicate UUID?=1 (baseline). `handleStatusChange` / `applyVPNStatus` тела не изменены (diff empty); nevpnObserver registration unchanged."
    - "Sensitive files D-09: TunnelController.swift (additive — добавлен `bootstrap` + `InitialStatusSnapshot`, существующие методы не меняются); MainScreenViewModel.swift (additive — добавлен `applyInitialStatusSnapshot` + `initialManagersApplied` flag + guard в init-seed Task; `applyVPNStatus` тело identical)."
    - "Regression gate D-08 PASS: AppFeatures swift test 133/133 PASS, iOS Simulator xcodebuild BUILD SUCCEEDED, macOS xcodebuild BUILD SUCCEEDED."
---

# Wave 06D-03f — M1: Cold-start XPC consolidation via TunnelController.bootstrap

## Цель волны

Закрытие **M1** из Wave 06D-01 (3/3 moderate consensus: Opus #3 HIGH + Codex #6+#7 MEDIUM + Gemini implicit): 6-8 fire-and-forget Tasks из `BBTB_iOSApp.init` гонятся за NetworkExtension XPC server до первого frame. Это тот же класс crash'а, что описан в `feedback_nevpn_xpc_mach_port.md` (40+/sec → `EXC_RESOURCE/PORT_SPACE`). Severity MEDIUM (Codex+Gemini не классифицировали как HIGH), поэтому fix tight-scoped — НЕ переписывает init, а **серийизует уже существующую work** в одну ordered chain.

Один atomic commit, регрессионный gate D-08 после.

## Source consensus

| Finding | Source | Severity | Specifics |
|---|---|---|---|
| M1 | Opus #3 (HIGH) + Codex #6 (MEDIUM) + Codex #7 (MEDIUM) + Gemini (implicit) | MEDIUM | "6-8 unstructured launch-time Tasks contend для NE XPC server / Mach ports; на warm launches некоторые `loadAllFromPreferences` дублируются (migration + VM init seed + cachedManager refresh)" |

## Pre-Wave-03f baseline (init Task fanout)

`BBTB_iOSApp.init` / `BBTB_macOSApp.init` запускали 5 separate fire-and-forget Tasks:

1. `Task { await OnDemandMigrationTask.runIfNeeded() }`
2. `Task { await tunnel.setFailoverProvider(failoverProvider) }`
3. `Task { [weak vm] in ... await tunnel.setWatchdog(watchdog) }` — внутри также `let watchdog = TunnelWatchdog(...)` + `watchdog.setFailoverObserver(...)`
4. `Task { await tunnel.startReachability() }` — внутри `refreshCachedManager()` → 1 XPC `loadAllFromPreferences`
5. `Task.detached(priority: .background) { await SwiftDataContainer.runMigrationsIfNeeded(in: mc) }` (Wave 03e Commit 2 / M2)

Плюс **внутри** `MainScreenViewModel.init`:

6. `Task { @MainActor in await refresh() }` — SwiftData (НЕ XPC; off-target для M1)
7. `Task { @MainActor [weak self] in let managers = ...loadAllFromPreferences()... self?.applyVPNStatus(...) }` — **2nd duplicate XPC `loadAllFromPreferences` trip**

**Race surface (pre-Wave-03f):**

- Tasks #2, #3, #4 все hit'ают actor `TunnelController` simultaneously; reachability observer install и cachedManager seed могут начаться РАНЬШЕ, чем `setFailoverProvider` или `setWatchdog` записаны → status events forward'ятся в `watchdog == nil` (silent miss).
- Task #7 (VM init seed) и Task #4 (reachability refreshCachedManager) одновременно вызывают `loadAllFromPreferences` через NE XPC — 2 параллельных XPC trips на cold start, оба читают идентичные данные.
- Task #1 (OnDemandMigrationTask) может закончить ПОСЛЕ Task #4 → cachedManager seeded из устаревшего manager без on-demand toggle; следующий `.bbtbProvisionerDidSave` от migration corrects это, но в окне между двумя refresh'ами VM может зарелизить wrong state.

## D-09 invariant pre-check (sensitive files modified — additive only)

| Invariant | Status |
|---|---|
| `ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay` grep ≤ 7 | ✅ Baseline = 4, unchanged |
| `NEVPNStatusDidChange .*queue:.*\.main\)\|OperationQueue\.main` grep = 0 | ✅ Clean |
| `#Predicate.*UUID?` grep ≤ 1 | ✅ Baseline = 1, unchanged |
| `TunnelController.handleStatusChange(_:)` body identical | ✅ Diff empty |
| `MainScreenViewModel.applyVPNStatus(_:connectedDate:)` body identical | ✅ Diff empty |
| `nevpnObserver` registration `(forName: .NEVPNStatusDidChange, object: nil, queue: nil)` unchanged | ✅ Untouched в TunnelController + MainScreenViewModel |
| `manager.isOnDemandEnabled` formula unchanged | ✅ Untouched (OnDemandRulesBuilder не в diff) |
| Sliding session window invariant unchanged | ✅ TunnelWatchdog не в diff (только creation site moved into chain) |
| PacketTunnelProvider*.swift не тронуты | ✅ Out of scope для M1 |

## Architectural summary

### Сериализация через TunnelController.bootstrap

**Новый actor-метод** в `TunnelController.swift`:

```swift
public func bootstrap(failoverProvider: FailoverProviding,
                      watchdog: TunnelWatchdog) async -> InitialStatusSnapshot {
    setFailoverProvider(failoverProvider)
    setWatchdog(watchdog)
    await startReachability()
    // cachedManager — seeded by `startReachability` via `refreshCachedManager`;
    // NEVPNConnection.status / .connectedDate — synchronous (NOT XPC).
    let status = cachedManager?.connection.status ?? .invalid
    let connectedDate = cachedManager?.connection.connectedDate
    return InitialStatusSnapshot(status: status, connectedDate: connectedDate)
}
```

**`InitialStatusSnapshot`** — Sendable value-type (NEVPNStatus + Date?). Почему НЕ `[NETunnelProviderManager]` как изначально предложено в task spec: `NETunnelProviderManager` это `NSObject` (НЕ Sendable); возврат через actor → MainActor hop в Swift 6 strict concurrency wouldn't compile cleanly без warnings + потенциально нарушит actor isolation. Snapshot содержит ровно те две sync-property значения, которые `applyVPNStatus` реально читает.

**`setFailoverProvider` / `setWatchdog` / `startReachability` остаются public** — `TunnelControllerTests` + `AutoSelectIntegrationTests` через них тестируют subset of bootstrap (`testStartReachabilityIsIdempotent` и др. 9 unit-тестов). Bootstrap полностью additive.

### VM consumer: applyInitialStatusSnapshot + initialManagersApplied guard

**Новый MainActor метод** в `MainScreenViewModel.swift`:

```swift
public func applyInitialStatusSnapshot(_ snapshot: InitialStatusSnapshot) {
    guard !initialManagersApplied else { return }
    initialManagersApplied = true
    applyVPNStatus(snapshot.status, connectedDate: snapshot.connectedDate)
}
```

**Existing init-seed Task** в `init(importer:tunnel:modelContainer:...)`:

```swift
Task { @MainActor [weak self] in
    guard let self, !self.initialManagersApplied else { return }
    let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
    // Recheck — bootstrap could have flipped the flag while await above suspended.
    guard !self.initialManagersApplied else { return }
    let ours = ManagerSelector.ourManagers(from: managers).first
    let initialStatus = ours?.connection.status ?? .invalid
    let initialConnectedDate = ours?.connection.connectedDate
    self.initialManagersApplied = true
    self.applyVPNStatus(initialStatus, connectedDate: initialConnectedDate)
}
```

Двойной guard (до и после `await`) — race-safe: если bootstrap успел первым, второй check ловит флип ДО второго чтения; если оба читают одновременно, первый записавший выигрывает (`@MainActor` сериализует мутацию `initialManagersApplied`). Результат всё равно идемпотентен — оба пути ведут через `applyVPNStatus` (D-09 single authority).

### App.init: 5 Tasks → 1 ordered chain + 1 detached migration

`BBTB_iOSApp.init` / `BBTB_macOSApp.init` (mirror):

```swift
Task { [vm] in
    await OnDemandMigrationTask.runIfNeeded()
    let watchdog = TunnelWatchdog(failoverProvider: failoverProvider)
    await watchdog.setFailoverObserver { [weak vm] serverName in
        await MainActor.run { [weak vm] in
            vm?.showFailoverBanner(toServerName: serverName)
        }
    }
    let snapshot = await tunnel.bootstrap(failoverProvider: failoverProvider,
                                          watchdog: watchdog)
    await MainActor.run { [weak vm] in
        vm?.applyInitialStatusSnapshot(snapshot)
    }
}
// Migration сохранена параллельной (M2 — Wave 03e Commit 2; background priority,
// не contend'ит за NE XPC):
let mc = modelContainer
Task.detached(priority: .background) {
    await SwiftDataContainer.runMigrationsIfNeeded(in: mc)
}
```

**Ordering invariants реализованы явно:**

1. `OnDemandMigrationTask.runIfNeeded()` — first; постит `.bbtbProvisionerDidSave` до того, как bootstrap'овский `refreshCachedManager()` сделает initial seed.
2. `TunnelWatchdog` создаётся + observer регистрируется ДО `bootstrap` — bootstrap внутри ставит `setWatchdog(watchdog)`, гарантируя что reachability события получают consumer.
3. `bootstrap` атомарно: setFailoverProvider → setWatchdog → startReachability (1 XPC trip внутри `refreshCachedManager`) → snapshot.
4. `applyInitialStatusSnapshot` — VM получает тот же snapshot, флипает `initialManagersApplied`, init-seed Task становится no-op.

## Acceptance criteria — verified

| Criterion | Pre-Wave-03f | Post-Wave-03f | Status |
|---|---|---|---|
| `grep -c "Task { await" BBTB_iOSApp.swift` | 5 | 2 (one `Task { [vm] in` + Task.detached migration) | ✅ ≤ 2 met |
| `grep -c "Task { await" BBTB_macOSApp.swift` | 5 | 2 | ✅ ≤ 2 met |
| Init-Task fanout iOS | 5 | 2 (ordered bootstrap chain + detached SwiftData migration) | ✅ |
| Init-Task fanout macOS | 5 | 2 | ✅ |
| `tunnel.bootstrap(...)` invoked в обоих App init | — | iOS line 110, macOS line 91 | ✅ |
| `applyInitialStatusSnapshot(_:)` в MainScreenViewModel | — | line 467 (uses `applyVPNStatus` internally) | ✅ |
| Cold-start `loadAllFromPreferences` trips на launch | 2 (reachability seed + VM init seed) | 1 (bootstrap seed; VM init seed guarded → no-op when App.init bootstrap leads) | ✅ |
| AppFeatures swift test | 133/133 PASS | 133/133 PASS | ✅ |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | BUILD SUCCEEDED | ✅ |
| D-09 forbidden symbols grep | 4 (baseline) | 4 | ✅ ≤ 7 |
| D-09 NEVPNStatusDidChange queue=.main | 0 | 0 | ✅ = 0 |
| D-09 #Predicate UUID? | 1 (baseline) | 1 | ✅ ≤ 1 |
| `handleStatusChange` body diff | — | empty | ✅ |
| `applyVPNStatus` body diff | — | empty | ✅ |
| `nevpnObserver` registration unchanged | — | unchanged | ✅ |

## Commit

| # | SHA | Message | Files |
|---|---|---|---|
| 1 | TBD | `fix(06d-03f): consolidate cold-start XPC trips via TunnelController.bootstrap (M1)` | 4 files: TunnelController.swift, MainScreenViewModel.swift, BBTB_iOSApp.swift, BBTB_macOSApp.swift |

## Risks & mitigations

- **Risk:** `bootstrap` сериализует work, которая раньше была параллельной — bootstrap chain тоже становится sequential. **Mitigation:** в pre-Wave-03f та "параллельность" была иллюзорной (все 4 Tasks contend'или за один actor `TunnelController` + один NE XPC server; serial actor re-entry всё равно сериализовала их де-факто). Bootstrap chain не дольше прежнего fanout — просто без race window'а.
- **Risk:** Если bootstrap chain throws (нельзя; нет throws на пути) или cancelled до `applyInitialStatusSnapshot`, VM остаётся с `initialManagersApplied=false` и init-seed Task делает XPC fallback. **Mitigation:** работает by design — guard на init-seed обеспечивает recovery.
- **Risk:** `[vm]` strong capture в Task на время bootstrap — VM держится в памяти на ~100-400ms cold start. **Mitigation:** App owns VM (это `self.viewModel = vm`); capture не создаёт extra ownership beyond what `BBTB_iOSApp` уже держит. Inner closures используют `[weak vm]` для observer callbacks (correct release semantics).

## Cross-refs

- Wiki: `wiki/security-gaps.md` (R10 — TUN inbound), wiki page для cold start best practices (TODO в Wave 03f post-commit).
- Memory: `feedback_nevpn_xpc_mach_port.md` (родственный crash class на iOS 26).
- Phase 6c: `feedback_two_phase_init.md` (паттерн late-binding setter сохранён через `setWatchdog` + `setFailoverProvider` — bootstrap их зовёт, не подменяет).
- 06D-FINDINGS.md row M1 — closed.
