---
phase: 06d-performance-audit
plan: 03e
slice: e
type: execute
wave: 3.5
mode: mvp
depends_on: [03c, 03d]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
autonomous: true
requirements: [QUAL-01, PERF-02]
findings_addressed: [H6_residual, M2, M3, M4_residual, M5]
tags: [swiftdata-fetchcount, deferred-migration, keychain-concurrency, hot-path, structured-concurrency]
status: complete

must_haves:
  truths:
    - "H6 residual: `countSupportedConfigs()` → `context.fetchCount(descriptor)` вместо `.fetch(descriptor).count`. SwiftData iOS 17+ API возвращает Int без материализации @Model rows."
    - "M2: `SwiftDataContainer.makeShared()` синхронно возвращает контейнер без вызова `migratePhase2ToPhase3`. Новый API `runMigrationsIfNeeded(in:) async` зовётся из `Task.detached(priority: .background)` в App.init после tunnel.startReachability(). UserDefaults flag устанавливается только при успехе."
    - "M3: `UniversalImportParser()` allocated ровно ОДИН раз выше `for cfg in candidates` в `runIsSupportedUpgrade`. ScenePhase=.active handler в iOS+macOS app: `Task.detached(priority: .background)` + connect-state guard через snapshot из `MainActor.run`. Throttle ключ `bbtb.lastIsSupportedUpgrade` сохранён."
    - "M4 residual: `refresh()` больше НЕ зовёт `await reconcileSelectionWithStore()` в конце — inline O(N) Swift filter против уже fetched `supported` массива. Public `reconcileSelectionWithStore()` сохранён без изменений для AutoSelectIntegrationTests T6 + других потенциальных callers."
    - "M5: Auto-mode loop в `provisionTunnelProfile(for:)` переписан на `withThrowingTaskGroup` с bounded concurrency cap=8. ServerConfig @Model НЕ передаётся в child Task — Sendable struct KCWork (index, tag, transportOverride, protocolID, sni, host, port, name) + helper `reparseFromKeychainScalar(...)`. Order восстанавливается через index sort."
    - "D-09 invariant grep (baseline ReconnectStateMachine=4, queue=.main=0, OperationQueue.main=0, #Predicate UUID?=1) — clean across все 5 commits, без новых hits."
    - "AppFeatures swift test 133/133 PASS + VPNCore swift test 57/57 PASS + iOS+macOS xcodebuild green после КАЖДОГО commit."
    - "Sensitive files (BBTB_iOSApp.swift, BBTB_macOSApp.swift, ConfigImporter.swift, MainScreenViewModel.swift): handleStatusChange / applyVPNStatus / nevpnObserver / sliding window — нетронуты во всех 5 commits."
---

# Wave 06D-03e — SwiftData fetch + migration + Keychain perf optimizations

## Цель волны

Закрытие пяти findings из Phase 6d audit, ориентированных на cold start и connect-tap latency:

- **H6 residual (3/3 strong consensus)** — `countSupportedConfigs()` материализовала каждый row через `fetch(...).count` (50 servers = 50 SwiftData object instantiations per cold start path).
- **M2 (2/3 moderate)** — `migratePhase2ToPhase3` шёл синхронно из `SwiftDataContainer.makeShared()`, блокируя App.init для upgrade users (200–1500ms до первого frame).
- **M3 (2/3 moderate)** — `UniversalImportParser()` allocation per-candidate в loop + `runIsSupportedUpgrade` запускался на каждом scene-active без guard'а на текущий connect-flow.
- **M4 residual (3/3 moderate)** — `MainScreenViewModel.refresh()` ранее закрытый Wave 03c Commit 2 (`dca8e58`) имел ещё один SwiftData fetch внутри `reconcileSelectionWithStore()`, который зовётся в конце refresh().
- **M5 (1/3 unique-but-valuable, Gemini #5)** — Sequential `reparseFromKeychain` в auto-mode loop последовательно жмёт `SecItemCopyMatching` (blocking I/O) перед каждый auto-connect tap.

Пять atomic commits, регрессионный gate D-08 после каждого, D-09 invariants clean во всех 5 проходах.

## Source consensus

| Finding | Source | Severity | Specifics |
|---|---|---|---|
| H6 | Opus #4 (HIGH) + Codex #14 (MEDIUM) + Gemini #6 (implicit) | HIGH | "`countSupportedConfigs()` материализует все объекты вместо `fetchCount`" |
| M2 | Opus #38 (MEDIUM) + Codex #8 (MEDIUM) | MEDIUM | "SwiftData Phase 3 migration синхронно в `SwiftDataContainer.makeShared()` блокирует cold start" |
| M3 | Opus #8+#9 (MEDIUM) + Codex #9 (MEDIUM) | MEDIUM | "`runIsSupportedUpgrade` reparse URI parser на каждый candidate; runs on every scene-active" |
| M4 | Opus #10 (MEDIUM) + Codex #15 (LOW) + Gemini #6 (MEDIUM) | MEDIUM | "`MainScreenViewModel.refresh()` делает N+1 SwiftData reads" |
| M5 | Gemini #5 | MEDIUM | "Sequential Keychain reads stall pool provisioning во время auto-connect" |

## D-09 invariant pre-check (sensitive files NOT modified в опасных секциях)

| Invariant | Status across 5 commits |
|---|---|
| `ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay` grep ≤ 7 | ✅ Baseline = 4 (pre-existing comments/refs в TunnelController/MainScreenViewModel) — unchanged across все 5 commits |
| `NEVPNStatusDidChange .*queue:.*\.main\)\|OperationQueue\.main` grep = 0 | ✅ Все 5 commits — clean |
| `#Predicate.*UUID?` grep ≤ 1 | ✅ Baseline = 1 (pre-existing comment в ConfigImporter.swift:175) — unchanged во всех 5 commits |
| `TunnelController.applyVPNStatus(_:connectedDate:)` body identical | ✅ TunnelController.swift не в diff ни одного commit |
| `nevpnStatusObserver` registration `(forName:.NEVPNStatusDidChange, object:nil, queue:nil)` unchanged | ✅ MainScreenViewModel/TunnelController nevpnObserver registration не тронут |
| `manager.isOnDemandEnabled` formula unchanged | ✅ TunnelController не в diff |
| Sliding session window invariant unchanged | ✅ TunnelWatchdog не тронут |
| PacketTunnelProvider*.swift не тронуты | ✅ git diff --stat подтверждает все 5 commits |

## Findings & acceptance per commit

### Fix 1 / Commit `1d035bb` — H6 residual (fetchCount replacement)

**Source consensus:** Opus #4 HIGH + Codex #14 MEDIUM + Gemini #6 implicit — 3/3 strong.

**Root cause:**

```swift
public func countSupportedConfigs() -> Int {
    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.isSupported == true }
    )
    return (try? context.fetch(descriptor).count) ?? 0  // <-- materializes every row
}
```

`context.fetch(descriptor).count` instantiates каждый `ServerConfig` row (модель + relationships) только чтобы посчитать. SwiftData с iOS 17 имеет drop-in API `fetchCount(_:)` который возвращает `Int` без object materialization. Метод зовётся из `refresh()` + `applySelection` + `resolveServerLineName` — каждый cold start минимум 1 вызов; больший pool → линейно растёт.

**Concrete fix (BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift):**

```swift
public func countSupportedConfigs() -> Int {
    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.isSupported == true }
    )
    return (try? context.fetchCount(descriptor)) ?? 0  // fetchCount — no materialization
}
```

| Acceptance | Required | Result |
|---|---|---|
| `fetchCount` grep в ConfigImporter.swift | ≥ 1 hit | ✅ 1 executable hit |
| `\.fetch.*\.count` grep в ConfigImporter.swift | 0 executable hits | ✅ только comment-reference в новой docstring |
| `#Predicate.*UUID?` baseline unchanged | =1 | ✅ |
| AppFeatures swift test | 133/133 PASS | ✅ 6.87s |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |

**Commit:** `1d035bb fix(06d-03e): replace fetch().count with fetchCount() in ConfigImporter (H6 residual)`

### Fix 2 / Commit `6c89996` — M2 (defer Phase 3 migration to background)

**Source consensus:** Opus #38 + Codex #8 — 2/3 moderate.

**Root cause:**

```swift
// до Wave 03e:
public static func makeShared() throws -> ModelContainer {
    // ... open container ...
    if !UserDefaults.standard.bool(forKey: migrationDoneKey) {
        try migratePhase2ToPhase3(in: container)   // <-- BLOCKS until done
        UserDefaults.standard.set(true, forKey: migrationDoneKey)
    }
    return container
}
```

На upgrade-устройствах migration читал ВСЕ `ServerConfig` rows с `subscriptionURL != nil`, group by URL, создавал `Subscription` rows. 50-100 серверов = 200-1500ms wall time перед возвратом контейнера из App.init → блокировка cold start, no first frame до завершения миграции.

**Concrete fix (3 файла):**

1. **`BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift`:**
   ```swift
   public static func makeShared() throws -> ModelContainer {
       // ... open container only ...
       return try ModelContainer(for: ..., configurations: config)
   }

   public static func runMigrationsIfNeeded(in container: ModelContainer) async {
       guard !UserDefaults.standard.bool(forKey: migrationDoneKey) else { return }
       do {
           try migratePhase2ToPhase3(in: container)
           UserDefaults.standard.set(true, forKey: migrationDoneKey)
           migrationLogger.notice("Phase 2→3 data migration completed (deferred)")
       } catch {
           migrationLogger.error("Phase 2→3 data migration failed (will retry next launch): \(error.localizedDescription, privacy: .public)")
           // flag НЕ set → следующий launch попытается снова
       }
   }
   ```

2. **`BBTB/App/iOSApp/BBTB_iOSApp.swift`** + **`BBTB/App/macOSApp/BBTB_macOSApp.swift`:**
   ```swift
   // ... existing tunnel/failover wiring + Task { await tunnel.startReachability() } ...
   let mc = modelContainer
   Task.detached(priority: .background) {
       await SwiftDataContainer.runMigrationsIfNeeded(in: mc)
   }
   ```

**Idempotency rules preserved:**
- UserDefaults flag установлен ТОЛЬКО после успешной миграции — failed migrations повторятся на next launch.
- internal `migratePhase2ToPhase3` API без изменений — `Phase3MigrationTests` (57/57 VPNCore tests) продолжают зов её напрямую для unit tests с in-memory контейнером.
- UI consumers толерантны к `subscriptionID == nil` (это и так инвариант схемы — migration просто заполняет FK поле, его отсутствие не ломает рендер).

| Acceptance | Required | Result |
|---|---|---|
| `makeShared()` больше не зовёт `migratePhase2ToPhase3` | yes | ✅ grep подтверждает |
| `runMigrationsIfNeeded(in:)` public API | yes | ✅ доступен с iOS/macOS app |
| `Task.detached(priority: .background)` в App.init | yes (iOS + macOS) | ✅ оба файла |
| AppFeatures swift test | 133/133 PASS | ✅ |
| VPNCore swift test | 57/57 PASS (1 skipped baseline) | ✅ Phase3MigrationTests + всё остальное PASS |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| Sensitive file diff (iOSApp/macOSApp) | только App.init body | ✅ scenePhase/observer/handleForeground не тронуты |

**Commit:** `6c89996 fix(06d-03e): defer SwiftData Phase 3 migration to background Task (M2)`

### Fix 3 / Commit `1099629` — M3 (parser allocation + scenePhase deferral)

**Source consensus:** Opus #8+#9 + Codex #9 — 2/3 moderate.

**Root cause (2 parts):**

**Part A — UniversalImportParser allocation per-candidate:**
```swift
// до Wave 03e — внутри loop:
for cfg in candidates {
    guard let rawURI = cfg.rawURI, !rawURI.isEmpty else { continue }
    let uParser = UniversalImportParser()  // <-- N allocations per upgrade pass
    guard let result = try? await uParser.import(rawInput: rawURI, source: .pasteboard), ...
}
```

Parser holds registry pointers + URL state machine init — каждое создание не дешёвое. На pool из N серверов с rawURI: N parser allocations per scene-active.

**Part B — runIsSupportedUpgrade triggered unconditionally on scene-active:**
```swift
// до Wave 03e:
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        Task { await viewModel.importer.runIsSupportedUpgrade() }  // <-- hot foreground path
        ...
    }
}
```

Запускалось на главной очереди (`MainActor`-bound Task) даже если пользователь только нажал Connect и tunnel в `.connecting`. Конкурирует с `handleForeground` за cooperative thread pool в самый чувствительный момент.

**Concrete fix:**

**Part A — `ConfigImporter.runIsSupportedUpgrade`:**
```swift
let context = ModelContext(modelContainer)
let descriptor = FetchDescriptor<ServerConfig>(predicate: #Predicate { !$0.isSupported })
guard let candidates = try? context.fetch(descriptor) else { return }

// Phase 6d-03e Commit 3 (M3): allocate ONCE
let uParser = UniversalImportParser()

var upgradedCount = 0
for cfg in candidates {
    guard let rawURI = cfg.rawURI, !rawURI.isEmpty else { continue }
    guard let result = try? await uParser.import(rawInput: rawURI, source: .pasteboard),
          ...
}
```

**Part B — iOS + macOS scenePhase handler:**
```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        let vmRef = viewModel
        Task.detached(priority: .background) {
            let snapshot = await MainActor.run {
                (isConnecting: vmRef.state == .connecting, importer: vmRef.importer)
            }
            guard !snapshot.isConnecting else { return }
            await snapshot.importer.runIsSupportedUpgrade()
        }
        // ... handleForeground + viewModel.handleForeground остаются ...
    }
}
```

Throttle ключ `bbtb.lastIsSupportedUpgrade` (5-минутный UserDefaults guard внутри runIsSupportedUpgrade) сохранён — мы не теряем upgrade calls, просто откладываем их с hot tap-flow на следующий scene-active или явный foreground re-entry.

| Acceptance | Required | Result |
|---|---|---|
| `UniversalImportParser()` allocation выше `for cfg in candidates` | yes | ✅ line 806 (alloc) над line 809 (loop) |
| Scene-active handler в `Task.detached(priority: .background)` | yes (iOS + macOS) | ✅ оба файла |
| Connect-state guard через `vmRef.state == .connecting` snapshot | yes | ✅ оба файла |
| `runIsSupportedUpgrade` 5min throttle preserved | yes | ✅ метод не менялся в этой части |
| AppFeatures swift test | 133/133 PASS | ✅ |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| Sensitive file diff (iOSApp/macOSApp) | только scenePhase body | ✅ App.init / handleStatusChange / nevpnObserver не тронуты |

**Commit:** `1099629 fix(06d-03e): allocate UniversalImportParser once + defer runIsSupportedUpgrade off hot path (M3)`

### Fix 4 / Commit `684fb5a` — M4 residual (inline selection reconcile)

**Source consensus:** Opus #10 + Codex #15 + Gemini #6 — 3/3 moderate.

**Status note:** Wave 06D-03c Commit 2 (`dca8e58`) уже свернул count + activeName + snapshot в один fetch. Оставшийся residual: `await reconcileSelectionWithStore()` в конце `refresh()` делает дополнительный SwiftData fetch с `#Predicate { $0.id == id }`.

**Root cause:**

```swift
// refresh() — конец:
await reconcileSelectionWithStore()

// reconcileSelectionWithStore():
public func reconcileSelectionWithStore() async {
    guard let container = modelContainer, let id = selectedServerID else { return }
    let context = ModelContext(container)
    let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
    let found = (try? context.fetch(desc).first) != nil  // <-- второй fetch
    if !found { selectedServerID = nil }
}
```

`refresh()` к этому моменту уже держит `supported: [ServerConfig]` массив — проверка membership доступна O(N) Swift filter'ом, без второго round-trip к SwiftData.

**Concrete fix (BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift):**

```swift
public func refresh() async {
    if let container = modelContainer {
        let context = ModelContext(container)
        let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.isSupported == true })
        let supported = (try? context.fetch(desc)) ?? []
        // ... snapshot + supportedConfigCount ...

        // Inline reconcile (M4 residual): O(N) Swift filter, no second fetch.
        if let id = selectedServerID,
           !supported.contains(where: { $0.id == id }) {
            selectedServerID = nil
        }
        // ... activeServerName / state ...
    } else {
        // ... legacy fallback (modelContainer == nil) — без reconcile, как раньше ...
    }
    // <-- await reconcileSelectionWithStore() УБРАН
}
```

Public `reconcileSelectionWithStore()` оставлен без изменений — он зовётся напрямую из `AutoSelectIntegrationTests.test_deleted_selected_server_falls_back_to_auto` (T6, delete-race scenario) и может пригодиться будущим callers.

| Acceptance | Required | Result |
|---|---|---|
| `refresh()` теперь ровно 1 SwiftData fetch на DI path | yes | ✅ inline filter заменил второй fetch |
| `reconcileSelectionWithStore()` public API сохранён | yes | ✅ метод не удалён, signature без изменений |
| AutoSelectIntegrationTests T6 passes | yes | ✅ внутри 133/133 PASS |
| AppFeatures swift test | 133/133 PASS | ✅ |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| Sensitive file diff (MainScreenViewModel.swift) | только refresh() body | ✅ handleStatusChange / applyVPNStatus / nevpnObserver / sliding window — empty diff |

**Commit:** `684fb5a fix(06d-03e): finalize refresh() N+1 cleanup via inline selection reconcile (M4)`

### Fix 5 / Commit `99530f2` — M5 (concurrent Keychain reads via TaskGroup)

**Source consensus:** Gemini #5 — 1/3 unique-but-valuable.

**Root cause:**

```swift
// Auto-mode branch до Wave 03e:
for cfg in supported {
    guard let tag = cfg.keychainTag,
          let parsed = try? reparseFromKeychain(cfg, tag: tag) else { continue }
    let withOverride = applyTransportOverride(parsed, transportOverride(for: cfg))
    parsedList.append(withOverride)
}
```

`reparseFromKeychain` каждой итерацией → `KeychainStore.load(tag:)` → `SecItemCopyMatching` (blocking I/O syscall). Sequential loop на pool из 50+ серверов: 100-500ms cumulative latency перед каждый auto-mode tap, блокирует cooperative thread pool во время самого чувствительного момента (user смотрит на spinning indicator).

**Concrete fix (BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift):**

1. **Sendable scalar struct KCWork** — извлекает поля `ServerConfig` на main side (NOT передаём @Model через Task boundary):
   ```swift
   struct KCWork: Sendable {
       let index: Int
       let tag: String
       let transportOverride: TransportConfig?
       let protocolID: String
       let sni: String?
       let host: String
       let port: Int
       let name: String
   }
   ```

2. **Новый internal helper `reparseFromKeychainScalar(tag:protocolID:host:port:sni:name:)`** — дублирует per-protocol parsing logic (vless-reality, trojan, vless-tls, shadowsocks, hysteria2) без зависимости от `ServerConfig` объекта. Старый `reparseFromKeychain(_:tag:)` оставлен для explicit-selection branch (один-к-одному lookup).

3. **`withThrowingTaskGroup` с bounded concurrency cap=8** (same constant как ServerProbeService в Wave 03c — оптимум для I/O bound операций):
   ```swift
   try await withThrowingTaskGroup(of: (Int, AnyParsedConfig)?.self) { group in
       var iterator = workItems.makeIterator()
       var inFlight = 0
       // prime до cap'а
       while inFlight < maxConcurrent, let work = iterator.next() {
           group.addTask { /* reparseFromKeychainScalar + applyTransportOverride */ }
           inFlight += 1
       }
       // drain + replenish
       while let result = try await group.next() {
           inFlight -= 1
           if let r = result { indexedParsed.append(r) }
           if let work = iterator.next() {
               group.addTask { ... }
               inFlight += 1
           }
       }
   }
   ```

4. **Order preservation** — child Task возвращает `(index, AnyParsedConfig)`, после drain'а массив сортируется по index → pool order детерминирован (Phase 5 snapshot тесты + UI consistency).

**Effective wall time:** теперь max(per-server latency), не sum — для 50 серверов с 50ms-средней Keychain latency и cap=8: ~50ms × ceil(50/8) = ~350ms → ~50-100ms (если все hit при cap=8).

| Acceptance | Required | Result |
|---|---|---|
| `withThrowingTaskGroup` grep в ConfigImporter | ≥ 1 hit | ✅ 1 executable hit (line 537) |
| Bounded concurrency cap=8 | yes | ✅ `let maxConcurrent = 8` |
| ServerConfig @Model не передаётся в child Task | yes | ✅ KCWork — Sendable struct с scalars |
| Order preservation через index sort | yes | ✅ `indexedParsed.sort { $0.0 < $1.0 }` |
| AppFeatures swift test | 133/133 PASS | ✅ |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| Sensitive file diff (ConfigImporter.swift) | только auto-mode loop body + новый helper | ✅ handleStatusChange / applyVPNStatus / nevpnObserver — empty diff (этих методов в ConfigImporter нет; они в MainScreenViewModel/TunnelController, которые не тронуты этим коммитом) |

**Commit:** `99530f2 fix(06d-03e): concurrent Keychain reads via TaskGroup in provisionTunnelProfile (M5)`

## Regression gate summary

| Commit | AppFeatures (133) | VPNCore (57) | iOS build | macOS build | D-09 baseline |
|---|---|---|---|---|---|
| 1 `1d035bb` | ✅ PASS | n/a (file not in pkg) | ✅ | ✅ | ✅ 4 / 0 / 1 |
| 2 `6c89996` | ✅ PASS | ✅ PASS | ✅ | ✅ | ✅ 4 / 0 / 1 |
| 3 `1099629` | ✅ PASS | n/a | ✅ | ✅ | ✅ 4 / 0 / 1 |
| 4 `684fb5a` | ✅ PASS | n/a | ✅ | ✅ | ✅ 4 / 0 / 1 |
| 5 `99530f2` | ✅ PASS | n/a | ✅ | ✅ | ✅ 4 / 0 / 1 |

D-09 baseline format: `ReconnectStateMachine refs / queue=.main / #Predicate UUID?`. Все три во всех 5 коммитах остались на стартовом значении.

## Architectural notes (for wiki sync — see CLAUDE.md GSD memory rule)

**Pattern 1 — `fetchCount` вместо `fetch().count`.** SwiftData iOS 17+ предоставляет drop-in `fetchCount(_:)` для count-only queries. Любое `.fetch(...).count` в codebase — кандидат на замену, особенно на cold start paths. (Closes H6.)

**Pattern 2 — deferred startup migrations.** Любая data migration в `SwiftDataContainer.makeShared()` или эквивалентной init-чейн blocks cold start. Идиом для async migration: открыть контейнер синхронно, мигрировать в `Task.detached(priority: .background)` ПОСЛЕ App.init завершён, флаг идемпотентности устанавливать ТОЛЬКО после успеха (failed migrations retry on next launch).

**Pattern 3 — scene-active hook deferral.** Любая работа в `.onChange(of: scenePhase)` для `newPhase == .active` должна:
1. Запускаться в `Task.detached(priority: .background)` если не строго critical для render path.
2. Иметь connect-state guard через `MainActor.run` snapshot — пропускать cycle если tunnel в `.connecting`.
3. Иметь idempotency throttle (UserDefaults timestamp) для guard'а от лишних reentry calls.

**Pattern 4 — Sendable scalars для cross-Task processing.** SwiftData `@Model` объекты bound к их `ModelContext`. Любое `withTaskGroup` / `Task.detached` для batch processing должно:
1. Извлекать Sendable struct scalars на main side ДО spawning'а child Tasks.
2. Помощник-функции для child Tasks должны принимать эти scalars вместо `@Model` объектов.
3. Order preservation через index — если pool order важен для downstream consumer.

**Pattern 5 — bounded concurrency cap для I/O bound TaskGroup.** Используем cap=8 (consistent с ServerProbeService после Wave 03c). Для Keychain operations + network probes этого достаточно — кооперативный thread pool обычно 4 workers, перекрытие до 8 даёт хороший throughput без contention.

## Plan vs Wave 03d delta

| Aspect | Wave 03d | Wave 03e |
|---|---|---|
| Findings closed | H5, H7 (2 atomic) | H6 residual, M2, M3, M4 residual, M5 (5 atomic) |
| Files modified | 2 (ConnectionTimer + ServerListViewModel) | 5 (ConfigImporter, MainScreenViewModel, SwiftDataContainer, iOSApp, macOSApp) |
| Sensitive file touches | 0 | 4 (ConfigImporter + MainScreenViewModel + iOSApp + macOSApp) — все D-09 protected sections нетронуты |
| D-09 baseline | 1 / 0 / 0 / 1 | 4 / 0 / 0 / 1 |
| Regression gate runs | 2 | 5 |
| New API surface | 0 | 2 (`SwiftDataContainer.runMigrationsIfNeeded` + `ConfigImporter.reparseFromKeychainScalar` internal) |
