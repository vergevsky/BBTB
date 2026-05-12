---
phase: 03-server-management
plan: 02
subsystem: VPNCore — TCP-probe primitives
tags: [server-probe, network, async, sendable, tdd]
requirements: [SRV-01]
dependency_graph:
  requires: [VPNCore module Phase 1 baseline (Package.swift swift-tools-version: 6.0, platforms iOS 18 / macOS 15)]
  provides:
    - "ProbeResult / ProbeAggregate Sendable value types"
    - "ServerScore.autoSelect pure function"
    - "ServerProbeService actor — probeOnce + probeAll (nonisolated AsyncStream)"
  affects:
    - "Plan 03-03 ServerListViewModel.pingAllServers (consumer probeAll)"
    - "Plan 03-04 pull-to-refresh probe wiring"
    - "Plan 03-05 pre-connect auto-select через MainScreenViewModel"
tech_stack:
  added: []  # Все imports — Apple-native (Foundation, Network, OSLog, os/OSAllocatedUnfairLock)
  patterns:
    - "Public actor с private DispatchQueue + Logger (analog UniversalImportParser в ConfigParser)"
    - "NWConnection-based async probe c manual timeout через Task race"
    - "LockedBool helper (@unchecked Sendable + OSAllocatedUnfairLock) для single-resume guarantee"
    - "AsyncStream + TaskGroup parallel pattern; nonisolated для @MainActor consumer"
    - "Sendable cross-actor boundary через tuple (UUID, host, port), НЕ [@Model ServerConfig]"
key_files:
  created:
    - BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift
    - BBTB/Packages/VPNCore/Sources/VPNCore/ServerScore.swift
    - BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift
    - BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerScoreTests.swift
    - BBTB/Packages/VPNCore/Tests/VPNCoreTests/AutoSelectTests.swift
    - BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerProbeServiceTests.swift
  modified: []
decisions:
  - "LockedBool через OSAllocatedUnfairLock — стандарт WWDC22 для low-level synchronization, безопаснее ручного os_unfair_lock_t (no manual init/destroy). @unchecked Sendable — компилятор не видит OSAllocatedUnfairLock как actor-isolation, но контракт класса (вся mutation под lock) делает его cross-thread безопасным."
  - "ms calculation precision на ContinuousClock: Duration.components возвращает (seconds: Int64, attoseconds: Int64). ms = sec×1000 + attos / 1e15 (1 attosec = 1e-18 sec; 1e-3 sec = 1e15 attosec). max(1, ms) clamping — loopback handshake часто <1ms, но UI хочет показать «1 ms», не «0 ms»."
  - "lossRate normalization: probeServerThreeTimes делит на max(1, latencies.count + failures), а не на жёсткое 3. Это важно при cancellation в середине цикла — иначе аборт после 1-й probe дал бы lossRate=1.0 (ложно unreachable). При нормальном завершении всех 3 итераций знаменатель ровно 3."
  - "probeAll объявлен nonisolated на actor — чтобы @MainActor consumer в Plan 03/04 мог напрямую вызвать `for await ... in svc.probeAll(...)` без `await svc.probeAll(...)`. AsyncStream factory не требует actor-state, поэтому isolation не нужна."
  - "Sendable boundary: tuple `(UUID, host: String, port: Int)` соблюдается; компилятор Swift 6 strict mode не выдал warnings про non-Sendable cross-actor."
metrics:
  duration_min: "~5"
  completed_date: "2026-05-12"
  tasks_completed: 2
  files_changed: 5  # 3 source + 2 test (ServerProbeServiceTests + ServerScoreTests edited после Sendable / Double? fixes)
  commits: 2
test_results:
  unit_tests: "19/19 (1 skipped: SEC-05 keychain CLI gate, pre-existing)"
  new_tests: "14/14 GREEN (4 ServerScoreTests + 5 AutoSelectTests + 5 ServerProbeServiceTests)"
  wall_clock_critical:
    - "test_probeOnce_listening_port_returns_ok: 0.004s"
    - "test_probeOnce_invalid_port_returns_error: 0.107s"
    - "test_probeOnce_closed_port_times_out_within_budget: 0.107s (budget ≤1500ms, manual timeoutMs=200; verifies НЕ 60sec NWConnection default)"
    - "test_probeAll_yields_results_for_all_servers: 0.177s (3 servers × 3 probes loopback)"
    - "test_probeAll_cancellation_via_task_cancel: 0.213s (budget ≤2000ms)"
---

# Phase 3 Plan 02: ServerProbeService + Pure-Function AutoSelect Summary

**One-liner:** Core TCP-probing primitives — `actor ServerProbeService` с NWConnection-based async probe + manual 500ms timeout, Sendable `ProbeResult`/`ProbeAggregate` value types, pure-function `ServerScore.autoSelect` по формуле `score = avg × (1 + lossRate)`.

## Что сделано

Phase 3 Plan 02 — это второй вертикальный слайс foundation для server management. Реализованы три publicly-exposed compile units внутри module `VPNCore` плюс три RED→GREEN test файла. Все 14 новых тестов проходят; 19/19 в full VPNCore suite (1 предусмотренный SEC-05 skip Phase 1 baseline).

### D-01 — `ProbeResult.swift` (47 lines)

- `public enum ProbeResult: Sendable, Equatable` — три кейса: `.ok(latencyMs: Int)`, `.timeout`, `.error(String)`.
- `public struct ProbeAggregate: Sendable, Equatable` — поля `avgLatencyMs: Int?`, `lossRate: Double`, `probedAt: Date`. Computed:
  - `score: Double?` = `avg.map { Double($0) × (1 + lossRate) }` (формула D-01).
  - `isUnreachable: Bool` = `avgLatencyMs == nil`.

### D-03 — `ServerScore.swift` (23 lines)

- `public enum ServerScore` (namespace, не actor — pure).
- `static func autoSelect([(id: UUID, score: Double?)]) -> UUID?` — фильтрует nil-score кандидатов, выбирает min, возвращает nil если empty/all-unreachable.
- Тестируется изолированно от network (5 unit tests). Это важно для Plan 05 (pre-connect auto-select) — там не нужно поднимать NWListener.

### D-02 — `ServerProbeService.swift` (184 lines)

- `public actor ServerProbeService` с private `Logger(subsystem: "app.bbtb.server-probe", category: "probe")` и private `DispatchQueue(label: "app.bbtb.probe", qos: .userInitiated)`.
- `public func probeOnce(host: String, port: Int, timeoutMs: Int = 500) async -> ProbeResult`:
  - Guards port range `1..<65536`.
  - `ContinuousClock` для precise latency replay.
  - `withTaskCancellationHandler { withCheckedContinuation { ... } } onCancel: { connection.cancel() }` — propagation outer Task cancel в NWConnection.
  - `stateUpdateHandler`: `.ready` → `.ok(ms)`, `.failed`/`.waiting` → `.error`, `.cancelled` → `.timeout`.
  - Manual timeout: `Task { try? await Task.sleep(...); if resumed.tryFlip() { connection.cancel(); cont.resume(.timeout) } }` — НЕ зависит от NWConnection default ~60sec connectionTimeout (verified test_probeOnce_closed_port_times_out_within_budget: 0.107s wall-clock).
  - Single-resume invariant защищён `LockedBool` через `OSAllocatedUnfairLock` (Pitfall 1+10 mitigation).
- `public nonisolated func probeAll([(UUID, host, port)]) -> AsyncStream<(UUID, ProbeAggregate)>`:
  - `AsyncStream { continuation in let task = Task { withTaskGroup { ... } }; continuation.onTermination = { _ in task.cancel() } }`.
  - Внутри TaskGroup — `addTask { [self] in await self.probeServerThreeTimes(srv) }`; for-await stream → continuation.yield(result); проверка `Task.isCancelled` между iterations.
- `private func probeServerThreeTimes(...)`: 3 sequential `probeOnce` с 50ms gap, агрегация в `ProbeAggregate`. **lossRate normalization**: `failures / max(1, latencies.count + failures)` — устойчиво к partial cancellation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Test infrastructure bug] `XCTAssertEqual` с `Double?` требует unwrap**

- **Found during:** Task 2 compile.
- **Issue:** `XCTAssertEqual(agg.score, 100.0, accuracy: 0.0001)` — `agg.score` имеет тип `Double?`, а overload с `accuracy:` принимает только `Double` (не Optional). Compile error «cannot convert value of type 'Double?' to expected argument type 'Double'».
- **Fix:** Заменил на `XCTAssertEqual(agg.score ?? .nan, 100.0, accuracy: 0.0001)` + предшествующий `XCTAssertNotNil(agg.score)` для явной проверки non-nil.
- **Files modified:** `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerScoreTests.swift`.
- **Commit:** `04951ae` (вместе с GREEN-фазой — не отдельный коммит, т.к. ошибка теста была моей же в Task 1).

**2. [Rule 1 — Test infrastructure bug] Swift 6 strict concurrency: `XCTestCase` не Sendable**

- **Found during:** Task 2 compile.
- **Issue:** Использование stored property `private let listenerQueue = DispatchQueue(...)` приводило к `self.listenerQueue` capture внутри `@Sendable` newConnectionHandler closure. Swift 6 strict concurrency требует `ServerProbeServiceTests : Sendable`, но `XCTestCase` не Sendable (mutation от test framework).
- **Fix:** Переместил `let queue = DispatchQueue(...)` внутрь `setUp()` как локальную переменную — `DispatchQueue` сам Sendable, capture by-value, нет ссылки на self.
- **Files modified:** `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerProbeServiceTests.swift`.
- **Commit:** `04951ae`.

Эти два деффекта возникли в моём же RED-коде Task 1 — типы `ProbeAggregate` и stored queue ещё не существовали, поэтому compile-error при `swift test` маскировал бы реальные тестовые issue. После Task 2 source файлов compile дошёл до тестов и обнаружил эти gaps. Зафиксил вместе с feat-коммитом, т.к. отдельный test-fix коммит был бы фрагментацией для не-functional patch.

### Не возникало

- Архитектурных деффектов (Rule 4) — нет.
- Auth gates — нет (offline tests).
- Pitfall 1 (NWConnection strong-ref loss) — capture в closure через `connection.stateUpdateHandler = { state in ... connection.cancel() ... }` работает (verified test_probeOnce_listening_port_returns_ok PASS).
- Pitfall 4 (passing @Model через actor boundary) — соблюдён, передаётся `(UUID, host: String, port: Int)` tuple.

## TDD Gate Compliance

Plan-level TDD gate sequence verified:

- `test(03-02)` commit `15410b2` (RED) — predates `feat(03-02)` commit `04951ae` (GREEN).
- RED-фаза: compile-fail на «cannot find type 'ProbeAggregate'», «cannot find 'ServerScore'» — подтверждено через `grep -E "error:|FAILED|Cannot find"` в Task 1 verify.
- GREEN-фаза: 14/14 новых тестов PASS, 0 regressions в pre-existing 5 baseline tests.
- REFACTOR-фаза: не потребовалась (код после GREEN clean, без duplication).

## Key Decisions

### 1. LockedBool через `OSAllocatedUnfairLock`

WWDC22 ввёл `OSAllocatedUnfairLock` как стандартный API для low-level cross-thread synchronization (вместо ручного `os_unfair_lock_t` с UnsafeMutablePointer). Используется в Apple frameworks (XPC, NetworkExtension). Класс `LockedBool` — `final` + `@unchecked Sendable`: компилятор не видит OSAllocatedUnfairLock как actor-isolation, но контракт «вся mutation под lock.withLock» делает его cross-thread безопасным.

Альтернатива (отвергнута): atomic `OSAtomic*` — deprecated в Swift, не bridged автоматически.

### 2. ms calculation precision на ContinuousClock

`ContinuousClock().now - start` возвращает `Duration`. `.components` даёт `(seconds: Int64, attoseconds: Int64)`. Формула:

```swift
let ms = Int(comps.seconds * 1000) + Int(comps.attoseconds / 1_000_000_000_000_000)
```

1 attosecond = 1e-18 sec, 1ms = 1e-3 sec = 1e15 attoseconds. Итого: микросекунды разрешения. `max(1, ms)` — clamping, потому что loopback handshake часто <1ms (компонент seconds=0, attos<1e15 → ms=0), а UI хочет показать "1 ms" вместо "0 ms".

**Деviation от RESEARCH Example 1:** в RESEARCH строка 686 — `elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000`. Это вычисление в Int64 без explicit cast, что может overflow на очень больших latency (год+); в нашей реализации wrap в Int() через два терма даёт чуть более явное поведение. Функционально эквивалентно для probe-таймаутов до 60 секунд.

### 3. lossRate normalization

Если outer Task отменяется в середине 3-probe цикла (например, user удаляет subscription во время pingAll), то `probeServerThreeTimes` может выйти из loop через `if Task.isCancelled { break }` после 1 успешной probe. Деление `failures / 3.0` дало бы `0/3.0 = 0.0` (ложно perfect) или `1/3.0` (ложно lossy для single-attempt). Делим на `max(1, latencies.count + failures)`, чтобы знаменатель равен реально выполненным попыткам. На full cycle (нет cancellation) — знаменатель ровно 3, как в RESEARCH formula.

### 4. nonisolated probeAll

Объявлен `public nonisolated func probeAll(...)` — потому что factory только создаёт AsyncStream (без mutation actor state). Это позволяет @MainActor consumer (ServerListViewModel, Plan 03/04) написать:

```swift
for await (id, agg) in probeService.probeAll(servers) { ... }
```

без `await probeService.probeAll(servers)` — экономит turn-around, упрощает call site.

Children — `addTask { [self] in await self.probeServerThreeTimes(srv) }` — уже isolated (capture self, await на actor methods), поэтому actor isolation сохраняется на per-probe уровне.

## Threat Model Status

Из PLAN.md `<threat_model>`:

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-03-07 (TCP-probe leaks user IP) | accept | Documented (probe идёт ДО tunnel, IP неизбежно раскроется при actual connect; server из user-curated config). Дальнейшая работа — wiki entry в Plan 04 SECURITY review. |
| T-03-08 (200+ parallel handshakes DoS) | accept | Не реализовали throttling; TaskGroup без semaphore. Plan-checker может recommend max 30 concurrent при UAT. Phase 3 UAT покажет. |
| T-03-09 (race: pingAll vs delete subscription) | mitigate | `probeAll` cancellation propagation verified test_probeAll_cancellation_via_task_cancel (0.213s ≤ 2000ms budget). Plan 04 ViewModel будет cancel outer Task → stream finish'ится → onTermination cancel TaskGroup. |
| T-03-10 (LockedBool single-resume) | mitigate | `OSAllocatedUnfairLock` + `tryFlip()` гарантия. Тесты не crash'ятся под `Task.race` нагрузкой. |
| T-03-11 (NWConnection strong-ref loss) | mitigate | Capture внутри `stateUpdateHandler` closure → auto strong-ref до cancel. test_probeOnce_listening_port_returns_ok PASS (0.004s) подтверждает: probe не теряет ref. |

## Self-Check: PASSED

Verified:
- File `BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift`: FOUND
- File `BBTB/Packages/VPNCore/Sources/VPNCore/ServerScore.swift`: FOUND
- File `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift`: FOUND
- File `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerScoreTests.swift`: FOUND
- File `BBTB/Packages/VPNCore/Tests/VPNCoreTests/AutoSelectTests.swift`: FOUND
- File `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerProbeServiceTests.swift`: FOUND
- Commit `15410b2` (RED): FOUND
- Commit `04951ae` (GREEN): FOUND
- `swift test --package-path BBTB/Packages/VPNCore` exit 0: VERIFIED (19/19 PASS, 1 skipped)
- All acceptance criteria grep markers present.

## Consumer Notes

- **Plan 03-03** (ServerListViewModel.pingAllServers): consume `probeService.probeAll(servers.map { ($0.id, $0.host, $0.port) })` через `for await (id, agg) in stream`. Sendable boundary через tuple — НЕ передавать `[ServerConfig]` в actor.
- **Plan 03-04** (pull-to-refresh): обернуть `probeAll` в Task + `task.cancel()` при unmount. AsyncStream.onTermination сделает остальное.
- **Plan 03-05** (pre-connect auto-select через MainScreenViewModel): collect probe results в `[(UUID, ProbeAggregate)]`, передать в `ServerScore.autoSelect(results.map { ($0.0, $0.1.score) })`. Если returns nil — fallback на manually-selected или показать error.
