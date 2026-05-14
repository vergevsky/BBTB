---
phase: 06d-performance-audit
plan: 03d
slice: d
type: execute
wave: 3.4
mode: mvp
depends_on: [03c]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
autonomous: true
requirements: [QUAL-01, PERF-02]
findings_addressed: [H5, H7]
tags: [hot-path, ui-render, timer-publisher, swiftdata-fetch-collapse, computed-property-cache]
status: complete

must_haves:
  truths:
    - "ConnectionTimer полностью убирает Timer.publish(every: 1.0).autoconnect() — больше не создаётся в init View'а. `since == nil` → static Text без publisher'а; `since != nil` → TimelineView(.periodic(...)) с нативной SwiftUI pause-when-off-screen семантикой."
    - "MainScreenView body больше не пересчитывается 60×/min на idle/error screen — StatusPill, ConnectionButton, ServerLineView, toolbar не diff'ятся, когда disconnected."
    - "pendingDeleteSubscriptionServerCount = stored @Published private(set) var, пересчитывается ровно один раз через didSet на pendingDeleteSubscription. Все три pathway покрыты (VM set, VM clear, UI Cancel binding)."
    - "confirmationDialog в ServerListSheet больше не триггерит SwiftData fetch на каждый body diff (5-10×/sec во время dialog animation)."
    - "D-09 invariant grep (baseline=1, queue=.main=0, OperationQueue.main=0, #Predicate UUID?=1) — clean across both commits, без новых hits."
    - "AppFeatures swift test 133/133 PASS + iOS+macOS xcodebuild green после КАЖДОГО commit."
    - "Sensitive files (TunnelController.swift / MainScreenViewModel.swift / BBTB_iOSApp.swift / BBTB_macOSApp.swift / PacketTunnelProvider*.swift) НЕ тронуты в diff обоих коммитов."
---

# Wave 06D-03d — H5 + H7 UI re-render perf fixes

## Цель волны

Закрытие двух UI-render hot-path findings из Phase 6d audit:

- **H5 (2/3 moderate consensus, Opus #2 HIGH + Codex #10 MEDIUM)** — `ConnectionTimer` 1Hz publisher работает даже когда disconnected, форсируя SwiftUI body re-evaluation на 60×/min на idle/error screen.
- **H7 (1/3 unique-but-valuable, Opus #5 HIGH)** — `pendingDeleteSubscriptionServerCount` computed property делает full SwiftData fetch-all + Swift filter на каждый body refresh `confirmationDialog message:` (5-10 accesses/sec во время dialog animation).

Два atomic commits, регрессионный gate D-08 после каждого, D-09 invariants clean both runs.

## Source consensus

| Finding | Source | Severity | Specifics |
|---|---|---|---|
| H5 | Opus #2 | HIGH | `Timer.publish(every: 1.0).autoconnect()` создаётся в init view'а independently от `since != nil` — `.onReceive` обновляет `now` только при non-nil, но publisher tick'и форсируют body re-diff |
| H5 | Codex #10 | MEDIUM | "Idle screen keeps a 1 Hz timer publisher alive" |
| H7 | Opus #5 | HIGH | Computed property внутри `confirmationDialog message:` — ModelContext + fetch-all + Swift filter на каждый SwiftUI diff |

## D-09 invariant pre-check (sensitive files NOT touched)

| Invariant | Status across 2 commits |
|---|---|
| `ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay` grep ≤ 7 | ✅ Baseline = 1 (pre-existing comment в MainScreenViewModel.swift:81) — unchanged across both commits |
| `NEVPNStatusDidChange .*queue: *\.main` grep = 0 | ✅ Both commits — clean |
| `OperationQueue.main` grep = 0 | ✅ Both commits — clean |
| `#Predicate.*UUID?` grep | ✅ Baseline = 1 (pre-existing comment в ConfigImporter.swift:175) — unchanged. H7 fix использует fetch-all + Swift filter (не `#Predicate` с UUID?) — D-09 memory feedback compliance |
| `TunnelController.applyVPNStatus(_:connectedDate:)` body identical | ✅ TunnelController.swift не в diff обоих commits |
| `nevpnStatusObserver` registration `(forName:.NEVPNStatusDidChange, object:nil, queue:nil)` unchanged | ✅ MainScreenViewModel.swift / TunnelController.swift не в diff обоих commits |
| `manager.isOnDemandEnabled` formula unchanged | ✅ TunnelController.swift не в diff обоих commits |
| PacketTunnelProvider*.swift / BBTB_iOSApp.swift / BBTB_macOSApp.swift не тронуты | ✅ git diff --stat подтверждает обоих commits |

## Findings & acceptance per commit

### Fix 1 / Commit `5ef3888` — H5 (ConnectionTimer conditional publisher)

**Source consensus:** Opus #2 (HIGH) + Codex #10 (MEDIUM) — 2/3 moderate.

**Root cause:**

В предыдущей реализации `ConnectionTimer.swift`:

```swift
public struct ConnectionTimer: View {
    public let since: Date?
    @State private var now: Date = .now
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    // ...
    public var body: some View {
        VStack { /* ... */ Text(timerText) }
            .onReceive(timer) { value in
                if since != nil { self.now = value }
            }
    }
}
```

`Timer.publish(...).autoconnect()` создаётся в init View'а как `let` property — **независимо** от `since`. Publisher идёт бесконечно, каждую секунду доставляя Date в `.onReceive`. Хотя guard `if since != nil` предотвращает write в `@State now`, **сам факт прихода value в combine pipeline** заставляет SwiftUI re-evaluate body (Combine subscription mark'ает View как `dirty`).

Результат: MainScreenView body re-rendered 60×/min на idle/error screen, диффинг StatusPill, ConnectionButton, ServerLineView, toolbar пересчитывается впустую.

**Concrete fix (BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift):**

- Полностью убран `Timer.publish` и `@State now` из тела типа.
- `since == nil` → статический `Text("00:00:00")`. Zero ticks, zero publisher.
- `since != nil` → `TimelineView(.periodic(from: since, by: 1.0)) { context in Text(format(...)) }`. SwiftUI нативно паузит расписание, когда view off-screen, и spawn'ит timer лениво только при non-nil since.

**Option A выбрана** (TimelineView) над Option B (lazy state holder) — потому что нативное SwiftUI API проще и идиоматичнее, без ручного управления lifecycle через onAppear/onChange.

| Acceptance | Required | Result |
|---|---|---|
| `Timer.publish\|TimelineView` grep — новый pattern | yes | ✅ 4 hits (1 TimelineView executable + 3 Timer.publish в comments/docstrings) |
| `autoconnect` grep — 0 executable | yes | ✅ 1 hit (только в docstring) |
| `ConnectionTimerTests` 6/6 format tests | yes | ✅ Все 6 (zero/seconds/minutes/hours/long/negative) PASS |
| AppFeatures swift test | 133/133 | ✅ 6.81s, 0 failures |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild (CODE_SIGNING_ALLOWED=NO) | BUILD SUCCEEDED | ✅ |
| D-09 invariant grep | clean | ✅ baseline=1, queue=.main=0, OperationQueue.main=0, UUID? predicate=1 |
| Sensitive files в diff | none | ✅ git diff --stat: только ConnectionTimer.swift |

**Side effect:** Finding L6 (`MainScreenView.connectionStartDate` computed на каждом body refresh) теперь irrelevant — body не пересчитывается на 1Hz, когда disconnected. L6 остаётся в backlog (в этой волне не трогаем — отдельный helper-property).

**Commit:** `5ef3888 fix(06d-03d): conditional ConnectionTimer publisher — no ticks when disconnected (H5)`

### Fix 2 / Commit `b8d9294` — H7 (pendingDeleteSubscriptionServerCount cache)

**Source consensus:** Opus #5 (HIGH) — 1/3 unique-but-valuable.

**Root cause:**

В предыдущей реализации `ServerListViewModel.swift`:

```swift
public var pendingDeleteSubscriptionServerCount: Int {
    guard let sub = pendingDeleteSubscription else { return 0 }
    let context = ModelContext(modelContainer)
    let allDesc = FetchDescriptor<ServerConfig>()
    return (try? context.fetch(allDesc).filter { $0.subscriptionID == sub.id }.count) ?? 0
}
```

Computed property embedded в `confirmationDialog message:` (ServerListSheet.swift:90). SwiftUI re-reads computed properties **на каждый state diff** — во время dialog animation это 5-10 access/sec, на каждом из них: новый `ModelContext` → fetch всех `ServerConfig` → Swift filter → выброс результата.

SwiftData материализует все строки на каждом access → IO + memory traffic на каждом dialog frame.

**Concrete fix (BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift):**

1. **`pendingDeleteSubscriptionServerCount` → stored property:**
   ```swift
   @Published public private(set) var pendingDeleteSubscriptionServerCount: Int = 0
   ```

2. **`pendingDeleteSubscription` — `didSet` observer:**
   ```swift
   @Published public var pendingDeleteSubscription: Subscription? {
       didSet {
           refreshPendingDeleteSubscriptionServerCount()
       }
   }
   ```

3. **`refreshPendingDeleteSubscriptionServerCount()` helper — один fetch, ровно когда меняется pendingDeleteSubscription:**
   ```swift
   private func refreshPendingDeleteSubscriptionServerCount() {
       guard let sub = pendingDeleteSubscription else {
           pendingDeleteSubscriptionServerCount = 0
           return
       }
       let context = ModelContext(modelContainer)
       let allDesc = FetchDescriptor<ServerConfig>()
       pendingDeleteSubscriptionServerCount =
           (try? context.fetch(allDesc).filter { $0.subscriptionID == sub.id }.count) ?? 0
   }
   ```

**Все три pathway покрыты `didSet`:**

| Pathway | Trigger | Result |
|---|---|---|
| `requestDeleteSubscription(_:)` | VM устанавливает `pendingDeleteSubscription = sub` | didSet → fetch → count |
| `confirmDeleteSubscription(_:)` success path L285 | VM очищает `pendingDeleteSubscription = nil` | didSet → reset to 0 без fetch'а |
| `confirmDeleteSubscription(_:)` early-return path L274 | VM очищает `pendingDeleteSubscription = nil` | didSet → reset to 0 без fetch'а |
| `ServerListSheet.deleteSubscriptionBinding` Cancel button | UI пишет nil напрямую в @Published var | didSet → reset to 0 |

**D-09 compliance (критично):**

НЕ добавлен `#Predicate` с UUID?. Используется fetch-all + Swift filter по `$0.subscriptionID == sub.id`, как и был в старом computed property (тот же паттерн, просто переместился из getter в helper). Причина — `ServerConfig.subscriptionID: UUID?` (Optional), а `#Predicate` с UUID? тихо возвращает empty (см. memory `feedback_swiftdata_uuid_predicate.md` и D-09 invariant в Phase 6c).

| Acceptance | Required | Result |
|---|---|---|
| `pendingDeleteSubscriptionServerCount` grep hits ≥ 3 | yes | ✅ 5 hits (declaration, reset, assignment + 2 doc references) |
| `@Published private(set) var` (not computed) | yes | ✅ `grep -A 3 "var pendingDeleteSubscriptionServerCount"` → `@Published public private(set) var ... Int = 0` |
| `#Predicate.*UUID?` grep | ≤1 baseline | ✅ 1 (только pre-existing comment в ConfigImporter.swift:175) |
| AppFeatures swift test | 133/133 | ✅ 6.81s, 0 failures |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild (CODE_SIGNING_ALLOWED=NO) | BUILD SUCCEEDED | ✅ |
| D-09 invariant grep | clean | ✅ baseline=1, queue=.main=0, OperationQueue.main=0, UUID? predicate=1 |
| Sensitive files в diff | none | ✅ git diff --stat: только ServerListViewModel.swift |

**Commit:** `b8d9294 fix(06d-03d): cache pendingDeleteSubscriptionServerCount — no per-body fetch (H7)`

## Expected user-visible delta

### H5 (ConnectionTimer)

- **Idle/error screen:** SwiftUI body re-evaluation rate drops с 60/min до 0/min (Combine timer pipeline отсутствует вообще).
- **Connected screen:** unchanged perceptually — TimelineView спавнит publisher только когда view on-screen, что эквивалентно prior behavior, но без overhead идущего publisher'а в background.
- **Battery / energy:** 60 wasted body diff'ов в минуту × N child views (StatusPill, ConnectionButton, ServerLineView, toolbar) × idle minutes = noticeable improvement на energy report для idle scenarios.

### H7 (pendingDeleteSubscriptionServerCount)

- **Confirmation dialog appears smoother:** dialog animation не блокируется 5-10 SwiftData fetch'ами/sec.
- **Memory footprint во время dialog:** zero `ServerConfig` materializations after initial count computation (raньше = N materializations × 5-10 fps = 50-100/sec).

## Architectural changes summary

| Change | File | Type |
|---|---|---|
| Removed `Timer.publish(every: 1.0).autoconnect()` from View init | `ConnectionTimer.swift` | Render-cycle optimization (eliminate 1Hz background publisher) |
| Added `TimelineView(.periodic(from:by:))` for connected state | `ConnectionTimer.swift` | Native SwiftUI publisher gating |
| `pendingDeleteSubscriptionServerCount`: computed → stored `@Published private(set) var` | `ServerListViewModel.swift` | Hot-path SwiftData fetch elimination |
| Added `didSet` observer on `pendingDeleteSubscription` | `ServerListViewModel.swift` | One-shot recompute trigger |
| Private helper `refreshPendingDeleteSubscriptionServerCount()` | `ServerListViewModel.swift` | Encapsulates fetch + filter + count |

## Commit list

| Commit | Subject |
|---|---|
| `5ef3888` | `fix(06d-03d): conditional ConnectionTimer publisher — no ticks when disconnected (H5)` |
| `b8d9294` | `fix(06d-03d): cache pendingDeleteSubscriptionServerCount — no per-body fetch (H7)` |

## Next

Wave 06D-03e (если решат закрывать) — H6 (`countSupportedConfigs()` → `fetchCount`; уже **частично** адресован в 06D-03c Commit 2, осталась поверхность в `ConfigImporter.swift:98-104` и `resolveServerLineName`), H9 (`NWPathMonitor` `semaphore.wait()` без timeout в `ExtensionPlatformInterface.swift:274` — correctness HIGH).

L6 (`MainScreenView.connectionStartDate`) — **resolved by H5 fix** (body не пересчитывается на 1Hz, когда disconnected) — можно вычеркнуть из backlog.

L7 (`ServerListSheet.estimatedSheetHeight` O(n)) и M10 (`loadFromStore` 4 раза в pullToRefresh) остаются в backlog как кандидаты для следующей мини-волны.
