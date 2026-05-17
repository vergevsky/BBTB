# A2 — VPNCore audit (Opus 4.7) — Plan 08 / Audit-4

**Reviewer:** A2 (round 2)
**Scope:** `BBTB/Packages/VPNCore/Sources/VPNCore/` (13 files)
**Baseline:** `ccbce8a` (Plan 07 fix-up applied — commit `b0a51aa` touches `ServerProbeService.swift`; rest of VPNCore unchanged since `fb2ff54`)
**Focus:** Thread Safety + Logic / Bugs
**Mode:** Read-only, single-pass. Compared structurally against `audit-3-reviewers/A2-vpncore.md`.

---

## Verdict

🟢 **CLEAR** для TestFlight (Internal AND External) с точки зрения VPNCore. Plan 07 fixes (T-C-A2H1' + T-C-A2H2') landed cleanly:
- `LockedBool` теперь typed `OSAllocatedUnfairLock<Bool>` без `@unchecked Sendable` mask → A2-H1 закрыт корректно.
- `probeServerThreeTimes` cancellation handling переведено на conservative «unverified» aggregate (`failures=3`, `lossRate=1.0`, `avgLatencyMs=nil`) → A2-H2 семантически закрыт.

**Однако** новая семантика создаёт **side-effect downstream** в двух consumer-сайтах, которые сейчас неконтролируемо записывают `failedProbeCount=3` в SwiftData rows на cancellation — это новый MEDIUM (A2-M5). Никакой связки с CRITICAL/HIGH — slow path autoSelect всегда есть в fallback'е.

Один новый HIGH найден (A2-H3): **`refreshProbeScoresInBackground` поверх `ServerProbing.probeAll` не дренажит in-flight servers после outer cancellation** — может poison SwiftData rows для всех servers, которые были в `cap=8` window когда cancel прилетел. Это амплифицирует A2-H2 в обратную сторону: было «слишком оптимистично», стало «слишком пессимистично» — но scale теперь N серверов вместо 1.

---

## Plan 07 closure re-verification

### T-C-A2H1' (commit `b0a51aa`) — `LockedBool` typed lock

**Diff verified** at `ServerProbeService.swift:244-254`:

```swift
private final class LockedBool: Sendable {
    private let lock = OSAllocatedUnfairLock<Bool>(initialState: false)

    func tryFlip() -> Bool {
        lock.withLock { state in
            guard !state else { return false }
            state = true
            return true
        }
    }
}
```

✅ **CLOSED correctly**:
1. Typed generic `OSAllocatedUnfairLock<Bool>(initialState: false)` — Sendable natively под Swift 6 strict concurrency.
2. `@unchecked Sendable` mask убран → плейн `Sendable` conformance компилятор валидирует automatically. Если будущий contributor добавит non-Sendable stored property, диагностика surface immediately.
3. State теперь compiler-visible **внутри** closure `withLock { state in ... }` — невозможно случайно мутировать `flipped` outside the lock (что было главной regression-prevention concern из A2-H1).
4. Behaviour identical: `guard !state else { return false }; state = true; return true` точно повторяет previous `guard !flipped else { return false }; flipped = true; return true` под locked critical section.

**Re-verify single-resume invariant on hot path** (`probeOnce`):
- `.ready` (line 57) — `guard resumed.tryFlip() else { return }` ✅
- `.failed` (line 66) — `guard resumed.tryFlip() else { return }` ✅
- `.waiting` (line 74) — `guard resumed.tryFlip() else { return }` ✅
- `.cancelled` (line 83) — `guard resumed.tryFlip() else { return }` ✅
- Manual timeout (line 94) — `if resumed.tryFlip() { connection.cancel(); cont.resume(returning: .timeout) }` ✅

Все 5 call sites корректно используют `tryFlip()`. Cancellation handler (line 102-106) НЕ resumes (`connection.cancel()` only — cont resumption через follow-up `.cancelled` state callback). Это корректно: `tryFlip()` остаётся одно-источниковым gate'ом.

### T-C-A2H2' (commit `b0a51aa`) — cancellation aggregate

**Diff verified** at `ServerProbeService.swift:189-228`:

```swift
private func probeServerThreeTimes(
    _ srv: (id: UUID, host: String, port: Int)
) async -> (UUID, ProbeAggregate) {
    var latencies: [Int] = []
    var failures = 0
    var iterationsCompleted = 0
    var cancelledMidRound = false
    for _ in 0..<3 {
        if Task.isCancelled {
            cancelledMidRound = true
            break
        }
        let result = await probeOnce(host: srv.host, port: srv.port)
        iterationsCompleted += 1
        switch result {
        case .ok(let ms): latencies.append(ms)
        case .timeout, .error: failures += 1
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    if cancelledMidRound && iterationsCompleted < 3 {
        return (srv.id, ProbeAggregate(
            avgLatencyMs: nil,
            failures: 3,
            lossRate: 1.0,
            probedAt: Date()
        ))
    }
    let avg = latencies.isEmpty ? nil : latencies.reduce(0, +) / latencies.count
    let totalAttempts = max(1, latencies.count + failures)
    let lossRate = Double(failures) / Double(totalAttempts)
    return (srv.id, ProbeAggregate(
        avgLatencyMs: avg,
        failures: failures,
        lossRate: lossRate,
        probedAt: Date()
    ))
}
```

✅ **Закрывает named A2-H2 scenario** (cancelled-after-one-`.ok` no longer scores как clean 3/3 OK):
- `Task.isCancelled` поднимает `cancelledMidRound = true` ДО `probeOnce`.
- Если cancelled между iter 0 и iter 1: `iterationsCompleted == 1`, `cancelledMidRound == true` → conservative branch.
- Если completed все 3 (no cancel): `cancelledMidRound == false` → normal path.
- **Edge case**: cancelled ровно после 3rd iteration completion (in `Task.sleep` или после loop body) — `iterationsCompleted == 3`, `cancelledMidRound == false` (Task.isCancelled выставится TO loop body на 4-й iter, но цикл `for _ in 0..<3` уже finished) → normal path. ✅

Однако новая семантика создаёт downstream consumer issue — см. **A2-H3** ниже.

⚠️ **Test coverage gap NOT closed**: `ServerProbeServiceTests.swift` имеет 5 unit tests (probeOnce_listening, probeOnce_invalid_port, probeOnce_closed_port_timeout, probeAll_yields_results, probeAll_cancellation_via_task_cancel) — НИ ОДИН не покрывает новую `cancelledMidRound` branch. Commit message честно заявляет «behavioural verification deferred к v1.0.1». **A2-L7** documents это.

---

## HIGH findings (1 new)

### A2-H3 — `refreshProbeScoresInBackground` + `performPreConnectAutoSelect` write conservative aggregates to SwiftData без `Task.isCancelled` guard → cancellation poisons N rows вместо 1 (downstream amplification of T-C-A2H2 fix)

- **Severity:** HIGH (logic / data integrity)
- **Files:**
  - `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift:189-218` (new conservative branch)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:1058-1072` (refresh background) — **no `Task.isCancelled` guard**
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:1105-1115` (`performPreConnectAutoSelect` slow path) — **no `Task.isCancelled` guard**
  - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:455-463` (`pingAllServers`) — **`if Task.isCancelled { break }` present** ✅

- **Description:**
  Pre-fix, mid-round cancellation сделала at-most-ONE server look «good» (with `failures: 0, lossRate: 0.0, avgLatencyMs: <one sample>`). Post-fix, mid-round cancellation теперь возвращает `ProbeAggregate(avgLatencyMs: nil, failures: 3, lossRate: 1.0, probedAt: now)` — что в downstream consumer'ах **записывается напрямую** как `row.failedProbeCount = 3` + `row.lastLatencyMs = nil`. Это `isUnreachable == true` condition (см. `ServerConfig.isUnreachable` на line 126: `(failedProbeCount ?? 0) >= 3`).

  Сценарий:
  1. App launch → `refreshProbeScoresInBackground()` стартует, `cap=8` servers одновременно in-flight.
  2. User быстро hits Disconnect / переключает Auto-Cancel manually / `Task.detached { … }` parent отменяется (например, scene phase background).
  3. `Task.isCancelled` поднимается во ВСЕХ probe-Task'ах (TaskGroup cancellation propagation), все 8 in-flight `probeServerThreeTimes` returns conservative `(failures: 3, …)`.
  4. `for await (id, agg) in probeService.probeAll(payload)` в `MainScreenViewModel.swift:1058` НЕ проверяет `Task.isCancelled` — все 8 conservative aggregates записываются в `aggregates: [UUID: ProbeAggregate]` dict.
  5. После цикла: `for row in rows { if let agg = aggregates[row.id] { row.failedProbeCount = agg.failures /* 3 */; row.lastLatencyMs = nil; … } }; try? context.save()`.
  6. Next `selectAutoWinner` fast path читает `supportedServerSnapshot`, `cache.filter { $0.failedProbeCount < 3 }.isEmpty` → fall back на slow path `performPreConnectAutoSelect()` (вызывает probe ещё раз = удвоение тщательно сэкономленных Phase 6d perf gains). **Self-healing** на следующем successful probe round, но временный hit ощутим.

  В `ServerListViewModel.pingAllServers` (line 456) есть `if Task.isCancelled { break }` — там corruption ограничена in-flight server, который результат YIELD'нул ровно в момент cancel-break race. В MainScreenViewModel этого guard'а нет → **N серверов corruption**.

- **Why HIGH:** Превращает Plan 07 fix (1 server = «good» → 1 server = «unreachable») в (1 server = «unreachable» → N servers = «unreachable») в hot path. Pre-fix UX: иногда autoSelect-выбирает плохой сервер. Post-fix UX: после rapid Disconnect autoSelect всегда падает на slow path (~500-1500ms extra), пока probe цикл не отработает заново.

  **Не CRITICAL** потому что:
  - `refreshProbeScoresInBackground` запускается из `Task.detached` (line 1029-1031) — actually НЕ cancelable обычным `Task.cancel()` от parent. Cancellation surface ограничена rare race (scene phase, explicit `swiftui ` task cancellation).
  - Self-heals на следующем normal probe round (нормальный refresh не cancelled).
  - Slow path `performPreConnectAutoSelect` всегда даёт fresh results.

  **HIGH** потому что:
  - Plan 06 A2-H2 был severity HIGH по same reason (autoSelect correctness on hot path). Симметрично — поправили one direction, открыли другую.
  - Pre-fix состояние было «иногда ошибочно good» (rare race condition в narrow window). Post-fix состояние «всегда ошибочно bad» когда cancellation попадает в `cap=8` window — детерминированно при rapid Disconnect → Connect → Disconnect шаблоне.

- **Repro path:**
  1. iPhone TestFlight build, 30+ серверов в pool, fresh launch (cache empty).
  2. Hit Connect (Auto-mode). Watchdog spawns `refreshProbeScoresInBackground` after winner picked.
  3. Hit Disconnect через ≤300ms (before probes complete). На iOS 26 это plausibly triggers `Task.detached` cancellation от scene phase backgrounding.
  4. Hit Connect снова. `selectAutoWinner` fast path читает cache → `hasUsableData == false` (all failedProbeCount == 3 теперь — записаны cancellation-poisoned aggregate'ом) → fall back to `performPreConnectAutoSelect` → 500-1500ms latency.

- **Suggested fix (option A — recommended, conservative):**
  В `ServerProbeService.probeServerThreeTimes`, INSTEAD of conservative-with-`failures=3`, return **dedicated marker case** — например, `nil` через `Optional<ProbeAggregate>` или enum tag:
  ```swift
  // Option A: nil-out the entire aggregate slot.
  // probeAll → AsyncStream<(UUID, ProbeAggregate?)>; consumers nil-check before persist.
  ```
  Consumer-side filter: `if let agg = agg, !cancelledMidRound { row.failedProbeCount = … }`.

- **Suggested fix (option B — defensive, minimal):**
  В `refreshProbeScoresInBackground` (line 1058) добавить `if Task.isCancelled { break }` ПЕРЕД `aggregates[id] = agg` — симметрия с `ServerListViewModel.pingAllServers`. Same fix в `performPreConnectAutoSelect` (line 1105).
  ```swift
  for await (id, agg) in probeService.probeAll(payload) {
      if Task.isCancelled { break }
      aggregates[id] = agg
  }
  ```
  Это **минимально-инвазивный** fix, который сохраняет conservative aggregate как «обозначение для caller'а» — caller сам решает писать или нет.

- **Suggested fix (option C — surgical, conservative semantics):**
  Различать «полностью cancelled» (`iterationsCompleted == 0`) от «частично-cancelled» (`iterationsCompleted >= 1, < 3`):
  - `iterationsCompleted == 0`: don't yield at all (skip via `continue` в TaskGroup, либо drop результат).
  - `iterationsCompleted >= 1`: yield current loss-rate (`failures / (latencies.count + failures)`) without override — это даёт partial info caller'у.

  Это сохраняет «не trust cancelled probes» policy, но без массового write `failures=3`.

- **Effort:** Option B = 5 минут (2 lines). Option A = 30 минут (signature change через protocol `ServerProbing`). Option C = 15 минут (in-place).

---

## MEDIUM findings (5)

### A2-M5 — Plan 07 T-C-A2H2' regression direction: conservative aggregate persists в SwiftData rows вместо «mark unverified» semantic

- **Severity:** MEDIUM (semantic correctness / data integrity)
- **File:** `ServerProbeService.swift:211-217` (new conservative branch) + downstream consumers
- **Description:** Commit message states «return conservative `ProbeAggregate(failures: 3, lossRate: 1.0, avgLatencyMs: nil)`. This treats cancellation as «unverified» not «good», which matches user intent ("I cancelled, don't trust partial result")». Однако «unverified» != «3 failures». **«Unverified»** должно бы быть orthogonal состоянием (e.g. dedicated `probedAt: nil`, либо `failedProbeCount = nil`), а «failures = 3» — это **«я выполнил 3 probe и все failed»**.
  
  Consumer-side downstream (`ServerListVM`, `MainScreenVM`) пишет `row.failedProbeCount = agg.failures` напрямую. `ServerConfig.isUnreachable` predicate `(failedProbeCount ?? 0) >= 3` теперь fires для серверов, которые на самом деле могут быть полностью доступны — мы их просто не успели probe.
  
  UI consequence: `LatencyBadge.unreachable` (grey badge с восклицательным знаком) displayed для серверов которые user cancel-ил. Cosmetic — но user'у выглядит как «сервер сломан», хотя на самом деле он не probed.

- **Why MEDIUM:** Cosmetic UI inconsistency + auto-select decision корректно exclude'ит unverified-как-unreachable, но slow path probably picks them up на next refresh. Не блокирует ship.

- **Suggested fix:** Same as A2-H3 option A или C. Сейчас «3 failures» как proxy «unverified» работает, но семантически hostage'ит существующий field.

- **Effort:** Tied с A2-H3 fix.

### A2-M6 — `probeServerThreeTimes` cancel-check лишь перед каждой следующей iteration; cancel прилетевший ВНУТРИ `await probeOnce(...)` не abort'ит probe inflight

- **Severity:** MEDIUM (energy / cancellation propagation)
- **File:** `ServerProbeService.swift:196-208`
- **Description:** Loop body:
  ```swift
  for _ in 0..<3 {
      if Task.isCancelled { cancelledMidRound = true; break }
      let result = await probeOnce(host: srv.host, port: srv.port)
      iterationsCompleted += 1
      ...
      try? await Task.sleep(for: .milliseconds(50))
  }
  ```
  `probeOnce` уже использует `withTaskCancellationHandler { … } onCancel: { connection.cancel() }` (line 102-107) — cancellation **внутри** probeOnce должно работать. **Но** ContinuationHandler cancellation callback на NWConnection (`connection.cancel()`) трактуется как `.cancelled` state → `cont.resume(returning: .timeout)` (line 84). Это **не error**, **не cancel** — probeOnce возвращает .timeout. Далее `failures += 1` (line 205) — то есть cancellation-внутри-probe seen как «timeout» а не «cancelled». `iterationsCompleted` инкрементится (line 202). Если все 3 cancels попадают INSIDE probeOnce, `iterationsCompleted == 3`, `cancelledMidRound == false` → ❌ **NOT в conservative branch** → returns `(failures: 3, lossRate: 1.0, avgLatencyMs: nil)` — а это тот же выход что и для legitimate 3/3 timeout. Indistinguishable.
  
  Это **не bug** per-se (legitimate 3/3 timeout = всё равно «unreachable»), но cancellation invariant `cancelledMidRound = true` пропускается. Будущий refactor, который захочет различать «cancelled-internally» vs «legit-timeout», не сможет.

- **Why MEDIUM:** Не корректность — текущая семантика «cancel inside probeOnce → .timeout → failures» работает корректно (timeout count up). Но invariant subtle и можно случайно сломать.

- **Suggested fix:** Внутри case `.cancelled` (line 83) различить — например, если `resumed.tryFlip()` succeeds AND `Task.isCancelled`, return `.error("cancelled")` вместо `.timeout`. Это даст вверх по стеку explicit signal.

- **Effort:** 15 минут + unit test (mock NWListener cancel-while-probing).

### A2-M7 — `ServerProbeService.probeOnce` манипулирует `connection.cancel()` из множества контекстов без cleanup в `default:` case

- **Severity:** MEDIUM (edge case / resource leak window)
- **File:** `ServerProbeService.swift:54-87` (state machine)
- **Description:** `connection.stateUpdateHandler` обрабатывает 4 states explicitly (.ready / .failed / .waiting / .cancelled) + `default: break`. `default:` ловит `.preparing` и `.setup` — для NWConnection это нормальные intermediate states которые НЕ resume continuation. Если manual timeout (line 92-98) НЕ срабатывает (`timeoutMs` слишком большой или Task.sleep cancelled), а connection застревает в `.preparing` (e.g. DNS resolve hangs), continuation NEVER resumes → outer Task awaits forever. Manual timeout — **единственный** safety net против такого hang.
  
  Сценарий: `withTaskCancellationHandler.onCancel` calls `connection.cancel()` (line 106), что должно flip state в `.cancelled` (line 78) → `tryFlip` → resume `.timeout`. Это OK на cancellation path.
  
  **Но** если task НЕ cancelled и connection стрелка не идёт ни в одну `case` (например `.preparing` forever на broken DNS), резерв полагается ТОЛЬКО на `Task.sleep(for: .milliseconds(timeoutMs))`. `Task.sleep` throws на cancellation (line 93 `try?`), но если NO cancellation arrives, sleep отрабатывает → `resumed.tryFlip() && connection.cancel()` → callback fires `.cancelled` → resume. ✅
  
  **Logic holds**, но subtle dependency: `connection.start(queue:)` ОБЯЗАН вызвать stateUpdateHandler eventually (либо ready/failed/waiting/cancelled). Apple docs гарантируют это, но не explicitly. Если SDK regression вызовет ситуацию где connection «idle» в `.preparing`, manual timeout — последний guard.

- **Why MEDIUM:** Defensive depth concern, не active bug. Manual timeout = working safety net.

- **Suggested fix:** Optional — add `connection.stateUpdateHandler = nil` после resume (defer-style) во всех 4 case'ах — это explicit cleanup. Также можно logger.debug `default: state=...` чтобы surfacing unknown states в production logs.

- **Effort:** 10 минут.

### A2-M2 carry-forward — `SwiftDataContainer.migratePhase2ToPhase3` force-unwrap `subscriptionURL!` 

- **Severity:** MEDIUM (carried from Plan 06 A2-M2)
- **File:** `SwiftDataContainer.swift:99`
- **Status:** **NOT closed** в Plan 07. Code identical к baseline `fb2ff54`. См. Plan 06 A2-vpncore.md A2-M2 для full description.
- **Why still MEDIUM in Plan 08:** Plan 07 fix-up scope (commits `9da8c96 → ccbce8a`) НЕ затрагивал SwiftDataContainer.swift. Deferred к v1.1+ из общего MEDIUM batch (AUDIT-3.md «Tier B (post-TestFlight, v1.0.1)»).

### A2-M3 carry-forward — `KeychainStore.accessGroup` no caching + log spam on entitlement misconfiguration

- **Severity:** MEDIUM (carried from Plan 06)
- **File:** `KeychainStore.swift:34-40, 161-174`
- **Status:** **NOT closed** в Plan 07. См. Plan 06 A2-M3.
- **Why still MEDIUM:** Same — deferred. Note: `keychainLogger.warning` fallback (line 170) **all-call** spam continues на missing AppIdentifierPrefix. Production builds with proper entitlements бесшумные. Test builds — verbose. Acceptable.

---

## LOW findings (8 — 6 carried + 2 new)

### A2-L8 (new) — `probeServerThreeTimes` documentation comment incorrectly references «failures: 3, latencies: []» semantics

- **File:** `ServerProbeService.swift:184-187`
- **Description:** Docstring говорит «mark aggregate as "incomplete" via `failures = 3, latencies = []`», но в актуальной branch (line 211-217) поле `latencies` НЕ существует в `ProbeAggregate` — есть только `avgLatencyMs: Int?`. Docstring мiscites internal-state names. Minor — будущий contributor может запутаться.
- **Suggested fix:** «mark aggregate via `failures = 3, avgLatencyMs = nil` → `lossRate = 1.0` → autoSelect excludes».
- **Effort:** 2 минуты.

### A2-L7 (new) — `ServerProbeServiceTests.swift` не имеет coverage новой `cancelledMidRound` branch

- **File:** `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerProbeServiceTests.swift` (5 existing tests, lines 13-152)
- **Description:** Существующий `test_probeAll_cancellation_via_task_cancel` (line 127) проверяет только что stream terminates без hang. **НЕ проверяет** что cancelled-mid-round aggregate содержит `failures: 3, avgLatencyMs: nil`. Plan 07 commit message честно отмечает «behavioural verification deferred к v1.0.1 если integration suite добавлен», но финт остался.
- **Why LOW:** Не active bug — fix landed clean при code-inspection. Но если кто-то revert'нёт T-C-A2H2', regression silent (no test break).
- **Suggested fix:** Добавить TDD test:
  ```swift
  func test_probeAll_cancellation_yields_unreachable_aggregate_not_partial_ok() async {
      let svc = ServerProbeService()
      let servers = (0..<5).map { _ in (id: UUID(), host: "127.0.0.1", port: 1) }
      let task = Task {
          var cancelledAgg: ProbeAggregate?
          for await (_, agg) in svc.probeAll(servers) {
              cancelledAgg = agg
              break // first yield then trigger cancel
          }
          task.cancel()  // ← cancellation после first yield
          return cancelledAgg
      }
      // Assert: subsequent yields (если есть после cancel propagation) либо absent либо have failures>=1
  }
  ```
  Точная shape unit test требует mocking NWConnection delays — non-trivial. Альтернатива — integration test.
- **Effort:** 30 минут.

### A2-L1 carry — `VPNCore.version = "0.1.0"` стале

- **File:** `VPNCore.swift:4`
- **Status:** carried from Plan 06. Не used (только в `VPNCoreTests.swift:6` test'е). Cosmetic.

### A2-L2 carry — `probeOnce` `.cancelled` branch returns `.timeout` (semantic confusion)

- **File:** `ServerProbeService.swift:78-84`
- **Status:** carried from Plan 06. Related к A2-M6 (Plan 08 new). Cancellation внутри probeOnce indistinguishable от legit-timeout downstream.

### A2-L3 carry — `ServerConfig.identity` IPv6 collision

- **File:** `ServerConfig.swift:134-136`
- **Status:** carried from Plan 06.

### A2-L4 carry — `ServerConfig.countryFlag` regex re-compile per render

- **File:** `ServerConfig.swift:111-122`
- **Status:** carried from Plan 06.

### A2-L5 carry — `DNSConfig.dohAddress()` custom address не validated

- **File:** `DNSConfig.swift:69-71`
- **Status:** carried from Plan 06.

### A2-L6 carry — `SwiftDataContainer.runMigrationsIfNeeded` UserDefaults flag race

- **File:** `SwiftDataContainer.swift:70-81`
- **Status:** carried from Plan 06.

---

## Re-verified previously closed items

### Plan 05 closures (T-C1', T-C2', T-B3) — still hold

| Plan 05 task | File:line | Status |
|---|---|---|
| T-C1' — `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` add-only | `KeychainStore.swift:89` | ✅ holds |
| T-C2' — Synchronizable cleanup sweep | `KeychainStore.swift:75-77` | ✅ holds |
| T-B3 — lookup/add separation, `kSecAttrSynchronizable=false` pinned всем 4-м call sites | `KeychainStore.swift:64-92, 100, 124, 140-144, 152-154` | ✅ holds |

### Plan 07 closure (T-C-A2H1' + T-C-A2H2') — verified ABOVE

Both closures structurally sound. T-C-A2H2' downstream side-effect → A2-H3 new HIGH.

---

## Files reviewed (13 — same scope as Plan 06 A2)

| File | LOC | Plan 08 Δ |
|---|---|---|
| `VPNCore.swift` | 6 | unchanged; A2-L1 still applies |
| `KeychainStore.swift` | 175 | unchanged; A2-M3 still applies |
| `KeychainPersistResult.swift` | 20 | unchanged; clean |
| `ServerConfig.swift` | 137 | unchanged; A2-L3 + A2-L4 still apply |
| `Subscription.swift` | 37 | unchanged; clean |
| `SwiftDataContainer.swift` | 126 | unchanged; A2-M2 + A2-L6 still apply |
| `DNSConfig.swift` | 73 | unchanged; A2-L5 still applies |
| `TransportConfig.swift` | 49 | unchanged; clean |
| `ParsedConfigs.swift` | 302 | unchanged; clean (struct types) |
| `ServerProbeService.swift` | 255 | **+32 net** (T-C-A2H1' + T-C-A2H2' закрыты); 1 new HIGH downstream (A2-H3) + 2 new MEDIUM (A2-M5/M6/M7) + 2 new LOW (A2-L7/L8) |
| `ProbeResult.swift` | 53 | unchanged; clean |
| `ServerScore.swift` | 23 | unchanged; clean (pure function) |
| `VPNProtocolHandler.swift` | 38 | unchanged; clean |

---

## Cross-cutting Swift 6 strict concurrency check

Plan 07 commit `b0a51aa` drops `@unchecked Sendable` mask from `LockedBool` — Swift 6 strict concurrency теперь validates `Sendable` conformance. Build PASSES (`fb2ff54 → ccbce8a` claims clean build).

Verified no other `@unchecked Sendable` declarations в VPNCore — all 13 files use proper `Sendable` или ничего (value types auto-Sendable).

`OSAllocatedUnfairLock<Bool>(initialState: false)` — Apple docs (iOS 16+) confirm typed variant is `Sendable`. Generic wrapper compiles cleanly с Swift 6.

Actor isolation: `ServerProbeService` is `actor`; `probeAll` is `nonisolated` — invariants preserved post-fix (cancellation handling добавлен внутри isolated `probeServerThreeTimes`, no actor boundary crosses).

---

## What I explicitly did NOT find

- **No new force-unwraps / force-casts** introduced by Plan 07 fix. ✅
- **No new `@unchecked Sendable`** masks. ✅
- **No regression of T-B3 (KeychainStore safe-cast)** — `accessibleFlag` line 152-153 still uses `as? String` then bridge to CFString. ✅
- **No new Yandex/yandex strings** — `grep -rn yandex Packages/VPNCore` = 0. ✅
- **No PII / secrets leakage в new os.Logger calls** — only `OSStatus`-formatted warnings, no tags / hostnames. ✅
- **No actor reentrancy footgun added** в `probeServerThreeTimes` — function is private actor method, called от `withTaskGroup` inside `probeAll` (nonisolated), single-flight через TaskGroup. ✅
- **Single-resume invariant preserved** через 5 callsite tryFlip + lock. ✅

---

## Recommendation

**No findings block TestFlight Internal upload from `ccbce8a`.** Plan 07 closures hold; new HIGH (A2-H3) is downstream amplification with bounded impact (self-heals на следующем normal probe cycle, slow-path autoSelect всегда available как fallback).

### Suggested triage

**Pre-External-TestFlight (highly recommended, ~10 min):**
- **A2-H3 option B** — add `if Task.isCancelled { break }` в 2-х call sites (`MainScreenViewModel.refreshProbeScoresInBackground` line 1058 + `performPreConnectAutoSelect` line 1105). Mirror existing `ServerListViewModel.pingAllServers` pattern. Minimal-invasive, prevents N-server poison on rapid Disconnect → Connect.

**Tier B (post-TestFlight, v1.0.1) — ~1h total:**
- A2-M5 + A2-M6 — refactor cancellation aggregate semantic (option A: nil-out aggregate, or option C: distinguish completed-vs-cancelled iterations).
- A2-M7 — add `stateUpdateHandler = nil` cleanup, log unknown states defensively.
- A2-L7 — TDD test for cancellation aggregate (regression-prevention для T-C-A2H2').
- A2-L8 — docstring typo «latencies = []» → «avgLatencyMs = nil».

**Tier C (v1.1+):**
- A2-M2 / A2-M3 carry-forwards.
- A2-L1..L6 carry-forwards (cosmetic / defensive depth).

### Net verdict

🟢 **VPNCore is shippable at `ccbce8a` для Internal AND External TestFlight.** Plan 07 fix-up landed structurally correct. One new HIGH (A2-H3) is bounded amplification — recommend 2-line fix pre-External rollout. 5 MEDIUM + 8 LOW carry-forwards / new — deferred к v1.0.1+.

**Confidence:** HIGH for code paths reviewed. Lower confidence for `refreshProbeScoresInBackground` cancellation timing — would benefit от device UAT шаблона «hit Connect → hit Disconnect через ≤300ms → hit Connect again, measure latency before tunnel-up».
