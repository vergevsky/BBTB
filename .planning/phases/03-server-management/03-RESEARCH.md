# Phase 3: Server management — Research

**Researched:** 2026-05-12
**Domain:** SwiftData @Model migration (new entity + @Relationship), NWConnection-based TCP latency probing с TaskGroup, SwiftUI `.sheet` + `.refreshable` для server-list, прогрессивное обновление UI на actor + AsyncStream, server-identity дедупликация при subscription merge
**Confidence:** HIGH по Apple-API контрактам (SwiftData, NWConnection, .refreshable — официальная документация); HIGH по Phase 2 carry-forward паттернам (ConfigImporter pipeline, PoolBuilder, SwiftDataContainer); MEDIUM по country-flag derivation (Hiddify `cc=XX` convention — community, не RFC).

---

## Сводка для планировщика

Пять вещей, которые planner обязан зафиксировать в PLAN.md правильно с первого раза:

1. **SwiftData migration для `Subscription` @Model — lightweight, но требует пакетной правки.** `[VERIFIED: developer.apple.com/documentation/swiftdata]` Adding a new @Model class — это lightweight migration (без VersionedSchema). НО переименование `ServerConfig.subscriptionURL: String?` → `subscriptionID: UUID?` с одновременным добавлением `Subscription` — это **structural change** (нужен Phase-3 data migration step: пройтись по существующим `ServerConfig where subscriptionURL != nil`, создать `Subscription` записи, проставить `subscriptionID`, обнулить `subscriptionURL`). **Recommendation:** оставить `subscriptionURL: String?` как deprecated поле в Phase 3 (lightweight migration), добавить новое `subscriptionID: UUID?` рядом, и в Wave-1 data-migration таске пройтись по rows. В Phase 4+ удалить `subscriptionURL`.

2. **NWConnection TCP-probe — это **success/failure через `state` callback**, не stream чтения данных.** `[VERIFIED: developer.apple.com/documentation/network/nwconnection]` Для latency measurement: засечь `startTime` при `start(queue:)`, в `stateUpdateHandler` отловить `.ready` → `endTime - startTime = latency` → `cancel()`. На `.failed(err)` / `.waiting(err)` / `.cancelled` → failure. **Pitfall:** надо держать strong reference на NWConnection до `cancel()` иначе автоматически закроется; и **timeout — manual через Task + Task.sleep cancellation**, потому что default `NWProtocolTCP.Options.connectionTimeout` = ~60 секунд, что слишком долго (D-03 хочет 500 ms).

3. **Прогрессивное обновление UI (D-02) — через `AsyncStream<(UUID, ProbeResult)>` от actor.** `[VERIFIED: developer.apple.com/videos/play/wwdc2021/10134]` Pattern: `ServerProbeService` — actor. `func probeAll(_ servers: [ServerConfig]) -> AsyncStream<(UUID, ProbeResult)>`. Внутри — `TaskGroup` со всеми servers; каждая child task: 3 sequential probes → emit через continuation. UI consumer (ViewModel actor) `for await (id, result) in stream { update(id: id, result: result) }`. Это даёт правильную structured concurrency (cancel parent task → cancel all children), правильную main-actor UI updates через @MainActor consumer, и progressive feedback за ~150–500 ms вместо 1500 ms.

4. **`.sheet` с `.presentationDetents([.large])` + `.refreshable` работает корректно в iOS 17/18.** `[CITED: developer.apple.com/documentation/swiftui/view/refreshable(action:)]` `.refreshable` modifier на ScrollView внутри sheet — стандартный паттерн, system handles spinner. **Pitfall:** на macOS `.presentationDetents` игнорируется (sheet всегда fixed size); macOS требует `.frame(minWidth:minHeight:)`. **Не использовать** `List` для server-list — `.swipeActions` на macOS в `List` работает менее предсказуемо, а кастомный grouping (sticky AutoCell + sections) проще через `ScrollView + LazyVStack + Section`. Phase 3 UI-SPEC §2.2 уже зафиксировал ScrollView+LazyVStack.

5. **Auto-select pre-connect (D-04) добавляет ~1.5 сек latency, но **не блокирует UI thread**.** Pattern: `MainScreenViewModel.performToggleImpl()` при `selectedServerID == nil` → state = `.connecting` → `await pingAllServers()` (1500 ms max) → выбрать min score → передать в PoolBuilder, вернувший pool **только** из выбранного outbound (degenerate-case path PoolBuilder.buildSingBoxJSON — уже работает для 1 outbound) → `await tunnel.connect()`. **Key insight:** PoolBuilder уже поддерживает 1-outbound case (degenerate без urltest), Phase 2 PROTO-10 carry-forward. Phase 3 НЕ ломает sing-box urltest — просто bypass'ит его в pre-connect выбора. Если `selectedServerID != nil` (manual selection) — тоже degenerate 1-outbound. urltest остаётся для случая когда manual выбран, но sing-box внутри runtime'а отслеживает live failures — это уже Phase 2 behavior, не Phase 3.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (нельзя пересматривать)

**Phase boundary (CONTEXT §domain):**
- Экран-список серверов — sheet с pull-to-refresh, открывается при tap на ServerLineView главного экрана. Список содержит флаг страны, имя, latency, индикаторы недоступности/«не поддерживается».
- Ячейка «Авто» закреплена в топе списка.
- Auto-select по score перед каждым connect (parallel TCP-probe всех supported серверов).
- Multi-subscription — новая `@Model Subscription` в SwiftData, несколько источников, секции в списке.
- Pull-to-refresh — fetch all subscriptions + перепинг всех серверов.
- При запуске приложения — silent refresh (auto-refresh on foreground).

**Auto-select / Latency probing (D-01..D-04):**
- D-01: Latency через TCP-connect пробы `NWConnection` к `host:port` — независимо от sing-box, работает без активного туннеля.
- D-02: Пробы параллельно через Swift Concurrency `TaskGroup`. UI обновляется прогрессивно (каждый сервер — как только его пробы завершились).
- D-03: `score = latencyMs × (1 + lossRate)`. 3 **последовательных** TCP-пробы с timeout 500 ms каждая. `lossRate = failedProbes / 3`. Серверы с 3/3 timeout — недоступны, пропускаются auto-select'ом.
- D-04: Auto-select запускается **перед каждым connect** (не сохраняется до pull-to-refresh). Добавляет ~1.5 сек к connect.

**Data model (D-05..D-07):**
- D-05: Новая `@Model Subscription { id: UUID, url: String, name: String, lastFetched: Date? }`. `ServerConfig.subscriptionURL: String?` → `subscriptionID: UUID?` FK. SwiftData lightweight migration. Серверы без подписки (одиночный paste) — `subscriptionID = nil`, секция «Добавлены вручную».
- D-06: Добавление подписки — через существующую кнопку «+» на главном экране (TopBar). Subscription URL импорт → создаётся `Subscription` запись. Без отдельного раздела в Settings.
- D-07: Удаление подписки — swipe по заголовку секции + confirmation dialog. Cascade delete (Subscription + все её ServerConfig). Удаление одиночного сервера — swipe по строке, без confirm.

**Server list UI (D-08..D-11):**
- D-08: Sheet (`.sheet` modifier), `.presentationDetents([.large])`. Закрывается свайпом вниз или выбором сервера.
- D-09: Выбор сервера при активном туннеле — **авто-reconnect без алерта** (паттерн ReconnectBanner из Phase 2).
- D-10: Кнопка «Авто» — отдельная ячейка в топе списка (sticky/top-pinned). Если выбрана — checkmark.
- D-11: Строка содержит флаг + имя + latency badge (или «недоступен» / «не поддерживается»). Название протокола **не показывается** (скрыто для нетехнических пользователей).

**Background refresh (D-12..D-14):**
- D-12: Подписки обновляются на app foreground + pull-to-refresh.
- D-13: Pull-to-refresh — **два шага последовательно**: fetch subscription URLs → merge → параллельный ping всех серверов.
- D-14: Merge при re-fetch: новые URI добавляются, исчезнувшие из ответа **помечаются** (не удаляются автоматически). `Subscription.lastFetched` обновляется.

### Claude's Discretion (свобода в этих рамках)

- TCP-probe timeout — D-03 фиксирует 500 ms; sequential probe spacing (gap между 3 probes) — Claude'у выбрать (рекомендация: 50ms gap → total ~1500 ms worst-case).
- Country-flag derivation — приоритет источников (URI `cc=XX`, fragment regex, fallback `🌐`); GeoIP отложен в Phase 11.
- Section sort order (А → Б → Manual или какой-то стабильный порядок) — Claude'у выбрать (рекомендация: by `Subscription.lastFetched DESC` плюс Manual в конце).
- `Subscription.name` derivation — приоритет (Profile-Title header → URL host → fallback `Подписка #N`).
- Sheet state machine (`.loading / .loaded / .pinging / .refreshing / .refreshError / .empty`) — Claude'у разложить на enum.
- ServerProbeService module placement — `VPNCore` vs новый `ServerProbing` package (рекомендация: VPNCore — переиспользуется и MainScreenViewModel для pre-connect, и ServerListViewModel для refresh).
- Pre-connect ping UI feedback (показывать ли progress в connection button vs sheet) — UI-SPEC §3.2 диктует: ConnectionButton переходит в `.connecting` (Phase 2 анимация bounce), sheet закрыт.

### Deferred Ideas (OUT OF SCOPE — игнорировать)

- BGAppRefreshTask (фоновое обновление по расписанию) — Phase 6+.
- Поиск/фильтр в server list — Phase 11 (UX-04 wiki упоминает поиск).
- Управление подписками в Settings (отдельный раздел «Подписки») — не нужно, всё через «+».
- Редактирование имени подписки — Phase 11.
- Signal-strength dot на ServerLineView (wiki target) — Phase 11.
- Smart-метрика auto-select с историческими данными (jitter, DPI-успех) — v1.1 (SMART-01).
- Undo toast после swipe-delete — Phase 11.
- GeoIP lookup для country-flag fallback — Phase 11 (offline DB).
- Server detail screen (статистика по серверу) — не планируется.
- Subscription quota indicator (если Subscription-Userinfo вернул traffic) — Phase 11 или 8.
- Cert pinning subscription URL (DPI-08) — Phase 7.
- Сортировка серверов (alphabetical / by-latency toggle) — Phase 11.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **SRV-01** | Auto-select сервера по пингу + потерям пакетов. Phase 2 foundation: sing-box urltest + SwiftData массив с isSupported. **Phase 3 finish:** server-list UI, ping monitor + потери, smart-метрика. | §1 (TCP probe via NWConnection), §2 (TaskGroup parallel probing), §3 (score = latency × (1 + lossRate)), §5 (PoolBuilder degenerate 1-outbound case) |
| **SRV-02** | Поддержка нескольких subscription URL — секции в списке серверов. Phase 2 foundation: одна `subscriptionURL` метаданная. **Phase 3 finish:** несколько источников + секции. | §4 (Subscription @Model + ServerConfig migration), §6 (ConfigImporter rewire для multi-subscription), §10 (server-list sectioned UI) |
| **SRV-03** | Pull-to-refresh перепинговывает все серверы. | §7 (.refreshable + sequential fetch+ping pattern), §11 (foreground silent refresh) |
| **UX-04** | Server list screen — кнопка «Авто» + поиск + список с флагами стран и latency + pull-to-refresh + секции по подпискам. **Phase 3 part:** Авто, список, флаги, latency, pull-to-refresh, секции. **Phase 11 part:** поиск, signal-strength dot, final visual polish. | §10 (UI layout — ScrollView + LazyVStack + Section), §13 (country-flag derivation) |

**Success Criteria mapping (CONTEXT):**
1. **SC-1 (список обновляется по pull-to-refresh, latency пересчитывается)** — §7 documents `.refreshable { await viewModel.pullToRefresh() }` flow.
2. **SC-2 (auto-select на сервер с min latency + min loss)** — §3 documents score formula; §5 documents PoolBuilder integration.
3. **SC-3 (timer от установки туннеля)** — Phase 2 carry-forward; UX-03 уже PASSed. Phase 3 не меняет таймер. См. §14 carry-forward.
4. **SC-4 (несколько подписок → секции в списке)** — §4 (data model) + §10 (UI sections) + §6 (ConfigImporter создаёт Subscription при importе subscription URL).
</phase_requirements>

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| TCP-probe networking | Network framework (`NWConnection`, system) | VPNCore actor `ServerProbeService` | Apple-native low-level TCP API; не нужны 3rd-party deps. Actor isolation для thread-safety и cancellation propagation. |
| Latency / score computation | VPNCore (`ServerProbeService`) | — | Pure data transform; testable без UI. Reused by MainScreenViewModel (pre-connect) и ServerListViewModel (refresh). |
| Subscription persistence | SwiftData (`@Model Subscription` в VPNCore) | App Group shared store | Same store как `ServerConfig` (Phase 1 carry-forward). FK через `subscriptionID: UUID?` на ServerConfig. |
| Subscription fetch / merge | ConfigParser (`SubscriptionURLFetcher` — Phase 2 carry-forward) + new `SubscriptionMergeService` | VPNCore (для server-identity дедупликации) | Fetch — уже работает; merge logic — новый. |
| Server-list UI | AppFeatures (new `ServerListFeature` sub-module) | DesignSystem (tokens), Localization | Изолированный feature module. Не depends on MainScreenFeature (связь через MainScreenViewModel в root App). |
| Pre-connect auto-select trigger | AppFeatures (`MainScreenViewModel`) | VPNCore (`ServerProbeService`), ConfigParser (`PoolBuilder`) | ViewModel orchestrates: state → ping → pool rebuild → connect. |
| Tunnel reconnect on selection change | AppFeatures (`TunnelController` — Phase 2 carry-forward, extended) | PacketTunnelKit (BaseSingBoxTunnel) | Pattern из Phase 2 ReconnectBanner: stopVPNTunnel → loadFromPreferences → updated providerConfiguration → startVPNTunnel. |
| Country flag derivation | VPNCore (computed property on ServerConfig) | ConfigParser (URI parsers store country hints) | Pure-data derive (Unicode regional indicator from countryCode). |

---

## Standard Stack

### Core

| Library / Framework | Version | Purpose | Why Standard |
|---------------------|---------|---------|--------------|
| Swift | 6.0 (Swift 6 mode where possible) | Strict concurrency, isolated actors | Phase 1/2 baseline; nothing changes |
| SwiftUI | iOS 18 / macOS 15 SDK | Server-list sheet, refreshable, swipe-actions | Apple-native; Phase 2 baseline |
| SwiftData | iOS 17+ (already in use) | `@Model Subscription` + lightweight migration | Phase 1 carry-forward (CORE-10) |
| Network framework (`NWConnection`) | iOS 12+ (long stable) | TCP-probe latency measurement | Apple-native; no entitlements; no root |
| Swift Concurrency (`TaskGroup`, `AsyncStream`, actors) | Swift 5.5+ | Parallel probing + progressive UI updates | Phase 1/2 baseline |
| Foundation `RelativeDateTimeFormatter` | iOS 13+ | «5 мин назад» last-fetched indicator | Apple-native |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Combine | Phase 2 baseline `@Published` carry-forward | ViewModel updates (`@Published var selectedServerID: UUID?` etc) | Already used in MainScreenViewModel — pattern continues |
| UIImpactFeedbackGenerator (`UIKit`) | iOS 10+ | Haptic feedback при tap на ServerRow (iOS only) | UI-SPEC §2.5 spec — `style: .light` |
| OSLog (logging) | iOS 14+ / macOS 11+ | Структурированное логирование TCP-probe events | tech-stack.md обязывает; subsystem `app.bbtb.server-probe` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff | Decision |
|------------|-----------|----------|----------|
| `NWConnection` TCP-probe | sing-box internal `urltest` HTTP probe | sing-box urltest требует **активный туннель** (через outbound), значит ping невозможен когда tunnel down; HTTP probe богаче (детектит TLS-fingerprint mismatch), но в pre-connect недоступен | **NWConnection** — D-01 фиксирует |
| `NWConnection` TCP-probe | ICMP ping (`SimplePing` Apple sample, raw socket) | ICMP требует elevated privileges на macOS и не доступен на iOS без NEPacketTunnelProvider extension | **TCP** — D-01 фиксирует |
| SwiftData `@Relationship(\.cascade)` для Subscription→ServerConfig | Manual FK `subscriptionID: UUID?` + manual cascade в delete logic | `@Relationship` элегантнее, НО Phase 2 ServerConfig уже имеет `subscriptionURL: String?` — миграция на @Relationship потребует custom MigrationStage. Manual FK — lightweight migration, проще rollback | **Manual FK** — рекомендация Claude (CONTEXT discretion) |
| `ScrollView + LazyVStack + Section` | `List` with `.swipeActions` | List has built-in styling, but macOS swipe-actions менее distinct; кастомный layout (sticky AutoCell + sectioned grouping) проще через ScrollView | **ScrollView+LazyVStack** — UI-SPEC §2.2 фиксирует |
| `.refreshable` modifier | Custom drag-to-refresh `ScrollViewReader` + offset detection | `.refreshable` — native iOS 15+, system handles UI spinner; custom — boilerplate | **`.refreshable`** — D-13 implicit |
| `ModelActor` для background ServerProbeService | actor + ModelContainer-passed-in pattern | ModelActor binds к одному ModelContainer; ServerProbeService не нужно перисистить probe results напрямую (только обновлять `lastLatencyMs` через main-actor ViewModel) — простой actor чище | **Plain actor** — рекомендация |

**Installation:**
```bash
# Никаких новых dependencies. Все frameworks — Apple-native, доступны через SDK.
# Network framework — implicit import (часть Foundation).
# SwiftData — уже linked в VPNCore через Phase 1.
```

**Version verification:**
- Swift toolchain — Xcode 16 (Swift 6.0). `[VERIFIED: tech-stack.md строки 24-29 + Phase 1 baseline]`
- iOS 18.0 / macOS 15.0 minimum — confirmed Package.swift `[VERIFIED: BBTB/Packages/VPNCore/Package.swift:5]`
- Phase 3 не вводит новых third-party deps (соответствует tech-stack.md «принципы выбора зависимостей»).

---

## Architecture Patterns

### System Architecture Diagram

```
User taps ServerLineView                  User taps "+" (subscription URL)
        │                                                 │
        ▼                                                 ▼
  MainScreenViewModel                        ConfigImporter (Phase 2 extended)
  ├─ isPresentingServerList = true           │
  │                                          ▼
  ▼                                  UniversalImportParser → subscriptionURL detected
ServerListSheet (.sheet, .large)            │
  │                                          ▼
  ├─ on appear → ServerListViewModel.load    Branch (Phase 3 NEW):
  │   ├─ fetch all Subscription              ├─ existing Subscription? → update lastFetched + merge
  │   ├─ fetch all ServerConfig grouped      └─ new? → create @Model Subscription
  │   │     by subscriptionID                       │
  │   └─ kick off pingAll() (background)            ▼
  │                                         For each parsed ServerConfig:
  ▼                                           set ServerConfig.subscriptionID = subscription.id
ServerProbeService (actor)                    │
  │                                           ▼
  ├─ probeAll([ServerConfig]) → AsyncStream <bridges>
  │   │                                  Phase 2 unchanged: SwiftData persist + Keychain + provisionTunnelProfile
  │   └─ TaskGroup
  │       └─ for each server (parallel):
  │            3× sequential NWConnection TCP-probe (500ms each)
  │            yield (id, ProbeResult)
  │
  ▼
ServerListViewModel
  ├─ for await (id, result) in stream → update SwiftData ServerConfig.lastLatencyMs
  └─ progressive UI refresh through @Published servers

User taps ServerRow / AutoCell
  │
  ▼
ServerListViewModel.selectServer(id)
  ├─ MainScreenViewModel.selectedServerID = id (or nil for Auto)
  ├─ dismiss sheet
  │
  ▼
if tunnel active (Phase 2 ReconnectBanner pattern):
  ├─ stopVPNTunnel
  ├─ rebuild providerConfiguration via PoolBuilder
  │   ├─ if selectedServerID != nil → degenerate 1-outbound (no urltest)
  │   └─ if nil (Auto) → run pre-connect auto-select → 1-outbound pool
  ├─ saveToPreferences + loadFromPreferences
  └─ startVPNTunnel

User pulls down in sheet
  │
  ▼
ServerListViewModel.pullToRefresh() [D-13 — sequential 2 phases]
  ├─ Phase 1: for each Subscription → fetch URL → merge ServerConfig (D-14)
  │   ├─ new URIs → insert as ServerConfig (subscriptionID = sub.id)
  │   ├─ existing URIs (same host+port+protocolID+sni) → update name/metadata, preserve lastLatencyMs
  │   └─ disappeared URIs → mark as missingFromLastFetch (not delete)
  │
  └─ Phase 2: pingAll() via ServerProbeService.probeAll → update latency

App scenePhase → .active (D-12)
  │
  ▼
MainScreenViewModel.onAppear / scenePhase handler → silent refresh
  (same as pull-to-refresh, but без UI spinner — badges update в фоне)
```

### Recommended Project Structure

```
BBTB/Packages/
├── VPNCore/Sources/VPNCore/
│   ├── ServerConfig.swift          # MODIFIED — add subscriptionID, countryCode, lastPingedAt, failedProbeCount
│   ├── Subscription.swift          # NEW — @Model class Subscription
│   ├── SwiftDataContainer.swift    # MODIFIED — register Subscription in schema
│   ├── ServerProbeService.swift    # NEW — actor для TCP probing
│   ├── ProbeResult.swift           # NEW — enum { ok(ms), timeout, error(String) }
│   └── ServerScore.swift           # NEW — pure-data score computation
│
├── ConfigParser/Sources/ConfigParser/
│   ├── PoolBuilder.swift           # MODIFIED — accept selectedServerID для degenerate path
│   ├── SubscriptionMergeService.swift  # NEW — merge fetch result into existing pool by identity
│   └── UniversalImportParser.swift # MODIFIED — emit Subscription metadata (extracted name from header)
│
└── AppFeatures/Sources/
    ├── MainScreenFeature/
    │   ├── MainScreenViewModel.swift   # MODIFIED — selectedServerID, isPresentingServerList, pingAllServers
    │   ├── MainScreenView.swift        # MODIFIED — .sheet presenting ServerListSheet
    │   ├── ConfigImporter.swift        # MODIFIED — Subscription creation path
    │   └── ServerLineView.swift        # MODIFIED — tap ENABLED + chevron
    │
    └── ServerListFeature/              # NEW sub-module
        ├── ServerListSheet.swift       # root view
        ├── ServerListViewModel.swift   # @MainActor — state, load, refresh, select, delete
        ├── ServerListState.swift       # enum (loading/loaded/pinging/refreshing/refreshError/empty)
        ├── AutoCell.swift              # «Авто» sticky top cell
        ├── SubscriptionHeader.swift    # section header (per subscription)
        ├── ServerRow.swift             # ServerConfig row
        ├── LatencyBadge.swift          # latency / unsupported / unreachable / pinging
        └── PingState.swift             # enum для row-level ping status
```

### Pattern 1: NWConnection async TCP-probe с timeout
**What:** Convert NWConnection callback API to async function с manual timeout (default `connectionTimeout` слишком долгий).
**When to use:** ServerProbeService.probeOnce(host, port) → returns latency ms or timeout.
**Example:**
```swift
// Source: developer.apple.com/documentation/network/nwconnection + Apple Forums 662177
// Adapted to Swift 6 strict concurrency + 500ms timeout (D-03)

public enum ProbeResult: Sendable, Equatable {
    case ok(latencyMs: Int)
    case timeout
    case error(String)
}

public actor ServerProbeService {
    private let probeQueue = DispatchQueue(label: "app.bbtb.probe", qos: .userInitiated)

    public func probeOnce(host: String, port: Int, timeoutMs: Int = 500) async -> ProbeResult {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return .error("invalid port \(port)")
        }
        let nwHost = NWEndpoint.Host(host)
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        let startTime = ContinuousClock.now

        return await withTaskGroup(of: ProbeResult.self) { group in
            // Probe task
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<ProbeResult, Never>) in
                    var resumed = false
                    connection.stateUpdateHandler = { state in
                        guard !resumed else { return }
                        switch state {
                        case .ready:
                            resumed = true
                            let elapsed = ContinuousClock.now - startTime
                            let ms = Int(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
                            connection.cancel()
                            cont.resume(returning: .ok(latencyMs: ms))
                        case .failed(let err), .waiting(let err):
                            resumed = true
                            connection.cancel()
                            cont.resume(returning: .error(err.localizedDescription))
                        case .cancelled:
                            if !resumed {
                                resumed = true
                                cont.resume(returning: .error("cancelled"))
                            }
                        default: break
                        }
                    }
                    connection.start(queue: self.probeQueue)
                }
            }
            // Timeout task
            group.addTask {
                try? await Task.sleep(for: .milliseconds(timeoutMs))
                connection.cancel()
                return .timeout
            }
            guard let first = await group.next() else { return .error("unexpected") }
            group.cancelAll()
            return first
        }
    }
}
```

> **CRITICAL pitfall:** strong reference на `NWConnection` должен жить до `cancel()`. В pattern выше — capturing inside closure держит references. `[VERIFIED: developer.apple.com/forums/thread/120438]`

### Pattern 2: Parallel probing с progressive AsyncStream updates
**What:** Probe N серверов параллельно, emit results через AsyncStream as they complete (D-02).
**When to use:** ServerListViewModel.pingAll() и MainScreenViewModel.preConnectAutoSelect().
**Example:**
```swift
// Source: developer.apple.com/videos/play/wwdc2021/10134 + Donny Wals TaskGroup guide

extension ServerProbeService {

    /// 3 sequential probes per server; emit final ProbeAggregate (avg latency, lossRate) on completion.
    public nonisolated func probeAll(
        _ servers: [(id: UUID, host: String, port: Int)]
    ) -> AsyncStream<(UUID, ProbeAggregate)> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: (UUID, ProbeAggregate).self) { group in
                    for srv in servers {
                        group.addTask { [self] in
                            var latencies: [Int] = []
                            var failures = 0
                            for _ in 0..<3 {
                                let result = await self.probeOnce(host: srv.host, port: srv.port)
                                switch result {
                                case .ok(let ms): latencies.append(ms)
                                case .timeout, .error: failures += 1
                                }
                                try? await Task.sleep(for: .milliseconds(50))  // tiny gap
                            }
                            let avg = latencies.isEmpty ? nil : latencies.reduce(0, +) / latencies.count
                            let agg = ProbeAggregate(
                                avgLatencyMs: avg,
                                lossRate: Double(failures) / 3.0,
                                probedAt: .now
                            )
                            return (srv.id, agg)
                        }
                    }
                    for await result in group {
                        continuation.yield(result)
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct ProbeAggregate: Sendable {
    public let avgLatencyMs: Int?       // nil = all 3 timed out
    public let lossRate: Double          // 0.0 (3/3 ok) ... 1.0 (3/3 fail)
    public let probedAt: Date
    public var score: Double? {
        guard let ms = avgLatencyMs else { return nil }
        return Double(ms) * (1.0 + lossRate)
    }
    public var isUnreachable: Bool { avgLatencyMs == nil }
}
```

> **Key insight (D-03 implementation):** `score = ms × (1 + lossRate)`. Если все 3 пробы упали — score = nil, сервер не участвует в auto-select. `[CITED: 03-CONTEXT.md D-03]`

### Pattern 3: SwiftData @Model Subscription с manual FK
**What:** New @Model with manual FK to existing ServerConfig — позволяет lightweight migration.
**When to use:** Wave 1 task — add Subscription model.
**Example:**
```swift
// Source: developer.apple.com/documentation/swiftdata + hackingwithswift.com/quick-start/swiftdata

import Foundation
import SwiftData

@Model
public final class Subscription {
    @Attribute(.unique) public var id: UUID
    public var url: String
    public var name: String
    public var lastFetched: Date?

    // NOTE: НЕ используем @Relationship — manual FK (subscriptionID на ServerConfig).
    // Reasoning: Phase 2 уже имеет ServerConfig.subscriptionURL: String? — миграция на
    // @Relationship потребует custom MigrationStage (VersionedSchema), что усложняет
    // rollback. Manual FK работает через lightweight migration (Phase 3 Wave 1).

    public init(id: UUID = UUID(), url: String, name: String, lastFetched: Date? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.lastFetched = lastFetched
    }
}

// MIGRATION strategy for ServerConfig:
// Phase 2 → Phase 3 lightweight migration:
//   1. Add new optional field `subscriptionID: UUID?` (default nil) — lightweight OK
//   2. Add new optional fields `countryCode: String?`, `lastPingedAt: Date?`,
//      `failedProbeCount: Int?` (defaults nil) — lightweight OK
//   3. Keep `subscriptionURL: String?` as DEPRECATED (для data-migration step)
//
// Data migration (one-time, Phase 3 Wave 1 — выполняется в SwiftDataContainer.makeShared
// после `ModelContainer` создания):
//   1. Fetch ServerConfig where subscriptionURL != nil GROUP BY subscriptionURL
//   2. For each unique subscriptionURL:
//      a. Create Subscription { url: subscriptionURL, name: derive(url), lastFetched: nil }
//      b. Update all ServerConfig with that subscriptionURL: set subscriptionID = sub.id,
//         subscriptionURL = nil
//   3. context.save()
//
// In Phase 4+, drop `subscriptionURL` field entirely (will require VersionedSchema then).
```

### Pattern 4: SwiftUI sheet с pull-to-refresh + progressive updates
**What:** `.sheet` with `.presentationDetents([.large])` containing `ScrollView { .refreshable }` with row-level state.
**When to use:** ServerListSheet root view.
**Example:**
```swift
// Source: developer.apple.com/documentation/swiftui/view/refreshable(action:)
//         developer.apple.com/documentation/swiftui/view/presentationdetents(_:)

struct ServerListSheet: View {
    @StateObject var viewModel: ServerListViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                AutoCell(isSelected: viewModel.isAutoSelected, onTap: viewModel.selectAuto)

                ForEach(viewModel.sections) { section in
                    Section {
                        ForEach(section.servers) { server in
                            ServerRow(
                                server: server,
                                isSelected: server.id == viewModel.selectedServerID,
                                pingState: viewModel.pingState(for: server.id),
                                onTap: { viewModel.selectServer(id: server.id) },
                                onDelete: { viewModel.deleteServer(id: server.id) }
                            )
                        }
                    } header: {
                        if let sub = section.subscription {
                            SubscriptionHeader(
                                subscription: sub,
                                onDelete: { viewModel.requestDeleteSubscription(sub) }
                            )
                        } else {
                            // Manual section — no swipe action
                            Text(L10n.serverListManualSection)
                                .font(DS.Typography.caption)
                                .textCase(.uppercase)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.pullToRefresh()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert(...)  // partial fetch error
        .confirmationDialog(...)  // delete subscription
        .task {
            await viewModel.onAppear()  // load + kick off ping
        }
    }
}
```

### Anti-Patterns to Avoid

- **❌ Использовать `ICMP ping` (raw socket)** — требует root на macOS, не доступно на iOS. TCP-connect ping (NWConnection) — единственный портативный variant. `[VERIFIED: 02-RESEARCH.md context]`
- **❌ Полагаться на NWConnection default `connectionTimeout`** — он ~60 сек, слишком долго для UI feedback. Использовать manual timeout через TaskGroup race. `[VERIFIED: developer.apple.com/forums/thread/662177]`
- **❌ Передавать `ServerConfig` instances между actor boundaries** — SwiftData @Model не Sendable. Передавать `PersistentIdentifier` (или `UUID id`) и refetch на target actor. `[VERIFIED: brightdigit.com/tutorials/swiftdata-modelactor]`
- **❌ Использовать `List` со `.swipeActions` на macOS для server-list** — swipe-actions на macOS менее distinct; UI-SPEC §11 рекомендует context-menu fallback. Phase 3 — `ScrollView+LazyVStack` (UI-SPEC §2.2).
- **❌ Делать pull-to-refresh атомарным («всё или ничего»)** — D-13 фиксирует 2-phase: fetch potresses each subscription separately, ping тоже independent. Partial failure UI индицируется на per-subscription header (UI-SPEC §3.4).
- **❌ Удалять disappeared URIs из последнего fetch автоматически** — D-14 явно: помечать (например `missingFromLastFetch: Bool = false`), не удалять. Пользователь сам решает через swipe.
- **❌ Стартовать ping ВСЕХ серверов синхронно (await каждый по очереди)** — D-02 фиксирует TaskGroup parallel. Sequential = 1500 ms × N servers, parallel = 1500 ms total.
- **❌ Хранить `Subscription` в Keychain** — там только секреты (passwords, UUIDs). Subscription URL — публичная метаданная, идёт в SwiftData. Соответствует Phase 1 SEC-05 архитектуре.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TCP-connect для probe | Custom BSD socket + select/poll | `NWConnection` | Apple-native, Network framework handles IPv4/IPv6 fallback, system-level integration, no entitlements |
| ICMP ping | Raw socket + ICMP header crafting | TCP-connect probe (NWConnection) | iOS не разрешает raw sockets без entitlement; macOS требует root; TCP-connect — единственный portable вариант для probe `host:port` |
| Pull-to-refresh visual | Custom `ScrollViewReader` + offset detection + custom spinner | `.refreshable { ... }` modifier | iOS 15+; system handles spinner; обновляет при правильном swipe; integrates с `UIRefreshControl` под капотом |
| Parallel async iteration | `DispatchGroup` + completion blocks | `TaskGroup` (structured concurrency) | Structured cancellation (parent cancel → child cancel автоматически), type-safe results, integrates с Swift 6 strict concurrency |
| Progressive UI updates from background work | `NotificationCenter` или KVO | `AsyncStream` | Type-safe, cancellation-aware, naturally integrated с TaskGroup; consumer iterates через `for await` |
| Country flag rendering | Custom SVG library / image set | Unicode regional indicator emoji (`🇩🇪`) | Apple-native, scales с system font, никаких assets; fallback `🌐` для unknown |
| Subscription URL parsing | Custom URL parsing | `URL` + `URLComponents` | Apple-native, RFC 3986 compliant, handles edge cases (percent-encoded fragments — Phase 2 carry-forward) |
| `relativeDateTimeFormatter` | Custom «X мин назад» strings | `RelativeDateTimeFormatter` с `.named` style | Apple-native, localized (ru/en), handles pluralization, time zones |
| Cascade delete | Manual fetch-and-delete loop | `@Relationship(deleteRule: .cascade)` — eventually | Phase 3 — manual FK (rationale выше). Phase 4+ — переход на `@Relationship` через VersionedSchema |
| Sheet state machine | Boolean flags `isLoading`, `isRefreshing`, `hasError` | Single enum `ServerListState` | Enum-as-state-machine pattern предотвращает invalid states (loading+refreshing одновременно) |
| Sticky AutoCell в scroll | Custom GeometryReader + offset tracking | Positional pinning через layout (не sticky-on-scroll, а top-of-list) | UI-SPEC §2.3 — AutoCell **top-pinned by layout**, не sticky-on-scroll. Это упрощает реализацию. |

**Key insight:** Phase 3 = orchestration новых паттернов из Apple-native frameworks + extending Phase 1/2 SwiftData/PoolBuilder pipelines. Никаких third-party libs не нужно. Главная сложность — **structured concurrency между actor (ServerProbeService), @MainActor ViewModel, и SwiftData ModelContext**.

---

## Runtime State Inventory

> Phase 3 — **гибридная фаза:** добавляет новый @Model + изменяет существующий ServerConfig. Runtime state checks ниже выполнены.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data (SwiftData) | **ServerConfig rows в App Group store** (`group.app.bbtb.shared/ServerConfigStore.sqlite`) — Phase 2 oставил несколько rows с `subscriptionURL: String?`. После Phase 3 migration: `subscriptionURL` помечается deprecated, `subscriptionID: UUID?` заполняется по результатам data-migration step. | **Data migration в Wave 1** (см. §4 миграционный план). Plan-check должен проверить: data-migration выполняется **idempotent** (повторный запуск не дублирует Subscription rows). |
| Stored data (Keychain) | **Keychain items с tag `bbtb-config-<UUID>`** — Phase 1/2 carry-forward, per-ServerConfig секреты. Phase 3 НЕ трогает Keychain — secrets остаются с тем же тегом. | None. Keychain ↔ ServerConfig.keychainTag mapping сохраняется. |
| Live service config | **NETunnelProviderManager в системных VPN settings** — один manager с providerBundleIdentifier `app.bbtb.client.{ios,macos}.tunnel`. Phase 3 НЕ создаёт новых managers; обновляет `providerConfiguration["configJSON"]` при server-switch (Phase 2 ReconnectBanner pattern). | None для baseline; Wave 4 task должен **проверить** через UAT: switch на другой сервер обновляет config (через D-09 flow). |
| OS-registered state | **VPN profile registration в iOS Settings** — name=«BBTB» (`manager.localizedDescription`). Phase 2 carry-forward. Phase 3 НЕ переименовывает. | None. |
| Secrets / env vars | **App Group identifier `group.app.bbtb.shared`** — захардкожен в `SwiftDataContainer.appGroupIdentifier`. Phase 3 НЕ меняет. | None. |
| Build artifacts | **libbox.xcframework** — Phase 1 carry-forward. Phase 3 НЕ требует upgrade (sing-box 1.13.11 stable). | None. |
| **Subscription table — NEW** | Не существует в Phase 2 store. После Phase 3 migration: `Subscription` table создаётся автоматически SwiftData lightweight migration. Data-migration step добавит rows для existing `ServerConfig.subscriptionURL != nil`. | Wave 1 task: implement data-migration script в `SwiftDataContainer.makeShared` (или отдельный `SchemaMigrationService.migrateToPhase3()` который вызывается один раз). |

**Idempotency check для data-migration:**
- Использовать `FetchDescriptor<Subscription>(predicate: #Predicate { $0.url == subscriptionURL })` — если existing → reuse `id`.
- Сетить `migrationCompleted: Bool` в `UserDefaults` (`app.bbtb.phase3.migrationDone`) после successful migration → следующий launch skip'ает.

---

## Common Pitfalls

### Pitfall 1: NWConnection strong-reference loss → silent connection cancel
**What goes wrong:** Local variable `let connection = NWConnection(...)` deinitializes when function returns; underlying TCP socket closes; `stateUpdateHandler` никогда не invokes `.ready`; probe hangs до timeout.
**Why it happens:** NWConnection cancels itself when last reference dropped. `[VERIFIED: developer.apple.com/forums/thread/120438]`
**How to avoid:** Capture connection в closures (auto-strong-ref) или хранить в `private var` actor's. Pattern в §1 — capturing inside `withCheckedContinuation` keeps reference alive.
**Warning signs:** Все probes возвращают `.timeout` несмотря на reachable host. Логи: `stateUpdateHandler` invokes только `.cancelled`.

### Pitfall 2: SwiftData lightweight migration fails for renamed @Attribute
**What goes wrong:** Renaming `subscriptionURL` → `subscriptionID` (different type) — НЕ lightweight migration. SwiftData удаляет старое поле + создаёт новое (без data carry-over). Data lost.
**Why it happens:** Lightweight migration supports add/delete/rename **типа сохраняется**; смена `String?` → `UUID?` = delete + add. `[VERIFIED: hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations]`
**How to avoid:** **НЕ удалять `subscriptionURL` в Phase 3.** Добавить `subscriptionID: UUID?` рядом (default nil). Data-migration step заполняет `subscriptionID` на основе `subscriptionURL`. В Phase 4+ — VersionedSchema удаляет `subscriptionURL`.
**Warning signs:** После launch — все ServerConfig rows имеют `subscriptionURL = nil` и `subscriptionID = nil` (вместо migrated state).

### Pitfall 3: TaskGroup probe — child task outlive group через actor isolation
**What goes wrong:** ServerProbeService — actor. Child task внутри `withTaskGroup` capture'нул `self`. Если parent task (consumer) cancelled — group cancels children, но если child уже в middle of `withCheckedContinuation` без cancellation check — hang.
**Why it happens:** `withCheckedContinuation` НЕ имеет cancellation support по default. Нужен manual check or `withTaskCancellationHandler`. `[VERIFIED: hackingwithswift.com/quick-start/concurrency/how-to-cancel-a-task-group]`
**How to avoid:** Wrap probe в `withTaskCancellationHandler { ... } onCancel: { connection.cancel() }` — на cancel call NWConnection.cancel(), что triggers `.cancelled` state и resume continuation.
**Warning signs:** Sheet dismiss во время ping → CPU/network usage продолжается до timeout каждого active probe.

### Pitfall 4: SwiftData @Model class passed across actor boundary
**What goes wrong:** ServerProbeService (actor) receives `[ServerConfig]` argument — compiler warning «Cannot send non-Sendable type». В Swift 6 mode — compile error.
**Why it happens:** SwiftData @Model не Sendable (mutable properties + no internal locking). `[VERIFIED: brightdigit.com/tutorials/swiftdata-modelactor]`
**How to avoid:** Передавать `[(id: UUID, host: String, port: Int)]` tuple — Sendable value types. Actor пингует, emit'ит `(UUID, ProbeAggregate)`, consumer (ViewModel) refetch'ит ServerConfig by ID на @MainActor.
**Warning signs:** Swift 6 build fails с «Sending value of non-Sendable type 'ServerConfig'».

### Pitfall 5: `.refreshable` async task block — leak когда sheet dismissed mid-refresh
**What goes wrong:** User pulls down → `await viewModel.pullToRefresh()` starts → user dismisses sheet (swipe) → SwiftUI cancels `.refreshable` task → но если refresh внутри запустил `Task { ... }` без structured concurrency — отдельный task leak'ит и продолжает.
**Why it happens:** `.refreshable` task правильно cancelled by SwiftUI, но `Task.detached { ... }` или `Task { ... }` внутри — НЕ child task'и refreshable task'а. `[VERIFIED: developer.apple.com/forums/thread/138006]`
**How to avoid:** Внутри `pullToRefresh()` использовать ТОЛЬКО `async let` или `await withTaskGroup` — structured concurrency. Не запускать unstructured `Task { ... }`. AsyncStream consumers (`for await ... in stream`) корректно подхватывают cancellation parent task.
**Warning signs:** Console показывает «Probe completed» events после dismiss sheet.

### Pitfall 6: Country flag emoji rendering — некоторые шрифты не имеют glyphs
**What goes wrong:** macOS / iOS — Color Emoji font содержит regional indicators (🇩🇪 = `\u{1F1E9}\u{1F1EA}`); но **Linux/server**-style rendering (unlikely on Apple platforms) — некоторые country codes без glyph. Также — некоторые «политические» страны (Тайвань vs Китай) могут рендериться по-разному в зависимости от региональных настроек устройства.
**Why it happens:** Unicode regional indicators — комбинация двух code points, не отдельный glyph.
**How to avoid:** Phase 3 — fallback `🌐` (globe) если countryCode == nil. **Не пытаться** обнаружить "missing glyph" — на Apple platforms practically всегда работает.
**Warning signs:** ServerRow shows два букв (например «DE») вместо flag — означает что glyph не объединился.

### Pitfall 7: Subscription URL fetch — нет cap на response body size (carry-forward)
**What goes wrong:** Malicious subscription URL отвечает 100 MB body → memory blow-up.
**Why it happens:** Phase 2 SubscriptionURLFetcher не cap'ит size. `[CITED: 02-SECURITY.md W-02-09]`
**How to avoid:** **Phase 3 наследует Phase 2 accepted risk** — defer cap к Phase 7 (DPI-08 cert pinning + body cap). Документировать в Phase 3 carry-forward.
**Warning signs:** App memory spike при subscription import.

### Pitfall 8: Auto-select pre-connect с 0 reachable servers
**What goes wrong:** Все supported servers timeout 3/3 → score = nil везде → auto-select не имеет winner → connect fails с unclear error.
**Why it happens:** D-03 фиксирует «3/3 timeout = недоступен, пропускаются». Если все недоступны — нечего select'ить.
**How to avoid:** Fallback strategy:
  - Если 0 reachable → пробовать с первого supported config в pool (fallback to «any», не «best»).
  - User-visible error: «Все серверы недоступны. Проверьте подключение к интернету.» (новый L10n key).
**Warning signs:** Connect button stuck in `.connecting` → eventually `.error`, log: «No reachable servers for auto-select».

### Pitfall 9: SwiftData data-migration runs twice → duplicate Subscription rows
**What goes wrong:** Wave 1 data-migration runs on every app launch (вместо one-time) → дубли Subscription с same URL.
**Why it happens:** Нет idempotency flag.
**How to avoid:** UserDefaults flag `app.bbtb.phase3.migrationDone: Bool` — set после successful migration. На launch — check flag, skip если true. Также добавить `@Attribute(.unique) url: String` на Subscription? **Нет — URL может содержать токены, два manual paste разных subscription URL с одного домена — два разных Subscription**. Достаточно UserDefaults flag.
**Warning signs:** В server list — 2× sections для одной подписки.

### Pitfall 10: Selected server deleted while tunnel active
**What goes wrong:** User selected Server A → tunnel connected → user swipes-delete Server A → tunnel в неконсистентном state (старый sing-box config ссылается на удалённый outbound).
**Why it happens:** Phase 3 D-07 cascade delete server, но не reconciliates с active tunnel.
**How to avoid:** ServerListViewModel.deleteServer flow:
  1. Check if `serverConfig.id == MainScreenViewModel.selectedServerID` → fallback `selectedServerID = nil` (Auto).
  2. Check if tunnel active AND server в active pool → reconnect через PoolBuilder с обновлённым массивом (если хоть один сервер остался) ИЛИ disconnect и MainScreen → `.empty` state.
**Warning signs:** Tunnel stuck в `.connected` state но network not flowing.

---

## Code Examples

Verified patterns from Apple-native frameworks.

### Example 1: NWConnection-based TCP probe (async + manual timeout)

```swift
// Source: developer.apple.com/documentation/network/nwconnection + WWDC 2018 «Introducing Network.framework»
// File: BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift (NEW)

import Foundation
import Network
import OSLog

public enum ProbeResult: Sendable, Equatable {
    case ok(latencyMs: Int)
    case timeout
    case error(String)
}

public struct ProbeAggregate: Sendable {
    public let avgLatencyMs: Int?
    public let lossRate: Double
    public let probedAt: Date
    public var score: Double? {
        guard let ms = avgLatencyMs else { return nil }
        return Double(ms) * (1.0 + lossRate)
    }
    public var isUnreachable: Bool { avgLatencyMs == nil }
}

public actor ServerProbeService {
    private let log = Logger(subsystem: "app.bbtb.server-probe", category: "probe")
    private let queue = DispatchQueue(label: "app.bbtb.probe", qos: .userInitiated)

    public init() {}

    public func probeOnce(host: String, port: Int, timeoutMs: Int = 500) async -> ProbeResult {
        guard port > 0, port < 65536, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return .error("invalid port")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let clock = ContinuousClock()
        let start = clock.now

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<ProbeResult, Never>) in
                let resumed = LockedBool()  // wrapper around os_unfair_lock
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard resumed.tryFlip() else { return }
                        let elapsed = clock.now - start
                        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                        connection.cancel()
                        cont.resume(returning: .ok(latencyMs: max(1, ms)))
                    case .failed(let err), .waiting(let err):
                        guard resumed.tryFlip() else { return }
                        connection.cancel()
                        cont.resume(returning: .error(err.debugDescription))
                    case .cancelled:
                        guard resumed.tryFlip() else { return }
                        cont.resume(returning: .timeout)
                    default: break
                    }
                }
                // Manual timeout via Task race
                Task {
                    try? await Task.sleep(for: .milliseconds(timeoutMs))
                    if resumed.tryFlip() {
                        connection.cancel()
                        cont.resume(returning: .timeout)
                    }
                }
                connection.start(queue: self.queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

// Helper: thread-safe boolean for one-shot continuation.resume
private final class LockedBool: @unchecked Sendable {
    private var flipped = false
    private let lock = OSAllocatedUnfairLock()
    func tryFlip() -> Bool {
        lock.withLock {
            guard !flipped else { return false }
            flipped = true
            return true
        }
    }
}
```

> **Note on `LockedBool`:** Continuation.resume must be called exactly once — иначе runtime crash. Multiple state callbacks (.ready then .cancelled) могут гонять; lock guarantees single-resume.

### Example 2: AsyncStream-based parallel probing

```swift
// Source: developer.apple.com/videos/play/wwdc2021/10134 + donnywals.com/swift-concurrencys-taskgroup-explained

extension ServerProbeService {

    public nonisolated func probeAll(
        _ servers: [(id: UUID, host: String, port: Int)]
    ) -> AsyncStream<(UUID, ProbeAggregate)> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: (UUID, ProbeAggregate).self) { group in
                    for srv in servers {
                        group.addTask { [self] in
                            await self.probeServerThreeTimes(srv)
                        }
                    }
                    for await result in group {
                        if Task.isCancelled { break }
                        continuation.yield(result)
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func probeServerThreeTimes(_ srv: (id: UUID, host: String, port: Int)) async -> (UUID, ProbeAggregate) {
        var latencies: [Int] = []
        var failures = 0
        for _ in 0..<3 {
            let result = await probeOnce(host: srv.host, port: srv.port)
            switch result {
            case .ok(let ms): latencies.append(ms)
            case .timeout, .error: failures += 1
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let avg = latencies.isEmpty ? nil : latencies.reduce(0, +) / latencies.count
        return (srv.id, ProbeAggregate(
            avgLatencyMs: avg,
            lossRate: Double(failures) / 3.0,
            probedAt: .now
        ))
    }
}
```

### Example 3: SwiftData @Model Subscription + migration helper

```swift
// File: BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift (NEW)

import Foundation
import SwiftData

@Model
public final class Subscription {
    @Attribute(.unique) public var id: UUID
    public var url: String
    public var name: String
    public var lastFetched: Date?

    public init(id: UUID = UUID(), url: String, name: String, lastFetched: Date? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.lastFetched = lastFetched
    }
}

// File: BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift (MODIFIED)

public enum SwiftDataContainer {
    public static let appGroupIdentifier = "group.app.bbtb.shared"
    private static let migrationDoneKey = "app.bbtb.phase3.migrationDone"

    public static func makeShared() throws -> ModelContainer {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            return try ModelContainer(
                for: ServerConfig.self, Subscription.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let storeURL = containerURL.appendingPathComponent("ServerConfigStore.sqlite")
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: ServerConfig.self, Subscription.self,
            configurations: config
        )

        // Phase 3 idempotent data migration
        if !UserDefaults.standard.bool(forKey: migrationDoneKey) {
            try migratePhase2ToPhase3(in: container)
            UserDefaults.standard.set(true, forKey: migrationDoneKey)
        }

        return container
    }

    /// Phase 3 Wave 1 data migration:
    /// For each unique `ServerConfig.subscriptionURL`, create a `Subscription` row
    /// and set `ServerConfig.subscriptionID` to the new subscription's id.
    /// Idempotent guarded by UserDefaults flag.
    private static func migratePhase2ToPhase3(in container: ModelContainer) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.subscriptionURL != nil }
        )
        let rows = try context.fetch(descriptor)
        guard !rows.isEmpty else { return }

        // Group by subscriptionURL
        let grouped = Dictionary(grouping: rows) { $0.subscriptionURL! }
        for (url, servers) in grouped {
            // Check if Subscription already exists (idempotency at row level too)
            let subQuery = FetchDescriptor<Subscription>(
                predicate: #Predicate { $0.url == url }
            )
            let sub: Subscription
            if let existing = try context.fetch(subQuery).first {
                sub = existing
            } else {
                sub = Subscription(url: url, name: derivedName(from: url), lastFetched: nil)
                context.insert(sub)
            }
            for srv in servers {
                srv.subscriptionID = sub.id
                // subscriptionURL retained — Phase 4 removes via VersionedSchema
            }
        }
        try context.save()
    }

    private static func derivedName(from url: String) -> String {
        URL(string: url)?.host ?? "Подписка"
    }
}
```

### Example 4: ServerConfig migration-friendly schema

```swift
// File: BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift (MODIFIED — Phase 3 additions)

@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var protocolID: String
    public var keychainTag: String?
    public var isActive: Bool
    public var createdAt: Date
    public var lastLatencyMs: Int?

    // Phase 2 fields — UNCHANGED
    public var isSupported: Bool
    public var subscriptionURL: String?     // DEPRECATED in Phase 3 — drop in Phase 4 via VersionedSchema
    public var outboundJSON: String
    public var protocolDisplayName: String
    public var sni: String?
    public var rawURI: String?

    // Phase 3 NEW (all optional → lightweight migration)
    public var subscriptionID: UUID?        // FK to Subscription.id (manual)
    public var countryCode: String?         // 2-letter ISO 3166-1 alpha-2 (derived from URI cc=XX or fragment regex)
    public var lastPingedAt: Date?
    public var failedProbeCount: Int?       // 0-3 from last probe round; 3 = unreachable
    public var missingFromLastFetch: Bool   // D-14 — true if last subscription re-fetch didn't include this server

    public init(...) { /* Phase 3 init signature — все new fields с defaults */ }

    // Computed property — no migration impact
    public var countryFlag: String {
        guard let code = countryCode, code.count == 2 else { return "🌐" }
        return code.uppercased().unicodeScalars
            .compactMap { Unicode.Scalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }

    public var isUnreachable: Bool {
        (failedProbeCount ?? 0) >= 3
    }
}
```

### Example 5: ServerListViewModel — orchestration of state, ping, refresh

```swift
// File: BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift (NEW)

import Foundation
import SwiftData
import VPNCore
import ConfigParser

@MainActor
public final class ServerListViewModel: ObservableObject {
    @Published public private(set) var state: ServerListState = .loading
    @Published public private(set) var sections: [ServerListSection] = []
    @Published public private(set) var pingStates: [UUID: PingState] = [:]
    @Published public var refreshError: String?
    @Published public var pendingDeleteSubscription: Subscription?

    public weak var mainViewModel: MainScreenViewModel?  // for selectedServerID + reconnect

    private let modelContainer: ModelContainer
    private let probeService: ServerProbeService
    private let importer: ConfigImporting

    public init(modelContainer: ModelContainer, probeService: ServerProbeService,
                importer: ConfigImporting) {
        self.modelContainer = modelContainer
        self.probeService = probeService
        self.importer = importer
    }

    public func onAppear() async {
        await loadFromStore()
        state = .pinging
        await pingAllServers()
        state = .loaded
    }

    public func pullToRefresh() async {
        state = .refreshing
        defer { state = .loaded }
        // D-13: sequential 2 phases
        await fetchAllSubscriptions()
        await pingAllServers()
    }

    private func loadFromStore() async { /* fetch Subscription + ServerConfig, group */ }
    private func fetchAllSubscriptions() async { /* per-subscription fetch + merge */ }
    private func pingAllServers() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isSupported == true }
        )
        guard let supported = try? context.fetch(descriptor) else { return }
        let payload = supported.map { (id: $0.id, host: $0.host, port: $0.port) }
        // Mark all as pinging
        for s in supported { pingStates[s.id] = .pinging }
        // Consume stream
        for await (id, agg) in probeService.probeAll(payload) {
            if Task.isCancelled { break }
            // Persist via main-actor context fetch
            if let row = supported.first(where: { $0.id == id }) {
                row.lastLatencyMs = agg.avgLatencyMs
                row.lastPingedAt = agg.probedAt
                row.failedProbeCount = Int(agg.lossRate * 3)
            }
            pingStates[id] = .completed(agg)
        }
        try? context.save()
    }

    public func selectServer(id: UUID) { /* set mainViewModel.selectedServerID; dismiss; reconnect if active */ }
    public func selectAuto() { /* set selectedServerID = nil; dismiss; reconnect */ }
    public func deleteServer(id: UUID) { /* cascade-delete + reconcile with tunnel */ }
    public func confirmDeleteSubscription(_ sub: Subscription) { /* delete + cascade ServerConfig */ }
}

public enum ServerListState: Equatable {
    case loading, loaded, pinging, refreshing
    case refreshError(String)
    case empty
}

public enum PingState: Equatable {
    case idle
    case pinging
    case completed(ProbeAggregate)
}

public struct ServerListSection: Identifiable {
    public let id: String  // subscription URL or "manual"
    public let subscription: Subscription?  // nil for "Manual" section
    public let servers: [ServerConfig]
}
```

### Example 6: PoolBuilder с manual-selection degenerate path

```swift
// File: BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift (MODIFIED)
// Phase 3 addition: support manual server selection — build pool с одним outbound, без urltest.

extension PoolBuilder {
    /// Phase 3: build pool с одним конкретным outbound (manual selection или auto-select winner).
    /// Bypass'ит urltest — degenerate case PoolBuilder.buildSingBoxJSON уже работает для 1 outbound.
    public static func buildSingleOutboundJSON(from parsed: AnyParsedConfig) throws -> String {
        return try buildSingBoxJSON(from: [parsed])  // existing degenerate path
    }
}

// In ConfigImporter.provisionTunnelProfile (called on reconnect):
// if mainViewModel.selectedServerID != nil → fetch that specific ServerConfig → parse → buildSingleOutboundJSON
// if nil → fetch all supported → buildSingBoxJSON (full urltest pool, Phase 2 behavior)
```

### Example 7: Subscription URL → Subscription @Model creation in ConfigImporter

```swift
// File: BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (MODIFIED snippet)

public func importFromRawInput(_ raw: String, source: ImportSource = .pasteboard) async throws -> ImportResult {
    let result: ImportResult = /* parse via UniversalImportParser — Phase 2 */

    let context = ModelContext(modelContainer)

    // Phase 3 NEW: handle Subscription
    var subscriptionID: UUID? = nil
    if let subURL = result.subscriptionURL {
        let sub = try getOrCreateSubscription(url: subURL, name: result.metadata?.title, in: context)
        sub.lastFetched = .now
        subscriptionID = sub.id
        // Phase 3 D-14 merge strategy
        try mergeIntoExistingPool(newSupported: result.supported,
                                  newUnsupported: result.unsupported,
                                  subscriptionID: sub.id, in: context)
    } else {
        // Single paste — no Subscription created; servers get subscriptionID = nil ("Manual" section)
        try deleteAllOrphanConfigs(in: context)  // existing Phase 2 behavior for paste
        // Persist new orphans
        for server in result.supported {
            _ = try persistSupported(server, subscriptionID: nil, in: context)
        }
    }
    try context.save()
    // ... rest of Phase 2 flow: build pool, provision tunnel profile (BUT с учётом mainViewModel.selectedServerID
    //     for degenerate path — TODO в ServerListViewModel after selection)
}

private func getOrCreateSubscription(url: String, name: String?, in context: ModelContext) throws -> Subscription {
    let query = FetchDescriptor<Subscription>(predicate: #Predicate { $0.url == url })
    if let existing = try context.fetch(query).first {
        if let newName = name { existing.name = newName }
        return existing
    }
    let derived = name ?? URL(string: url)?.host ?? "Подписка"
    let sub = Subscription(url: url, name: derived, lastFetched: .now)
    context.insert(sub)
    return sub
}

private func mergeIntoExistingPool(newSupported: [ImportedServer], newUnsupported: [ImportedServer],
                                    subscriptionID: UUID, in context: ModelContext) throws {
    // D-14 merge by server-identity: host + port + protocolID + sni
    let existingQuery = FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.subscriptionID == subscriptionID }
    )
    let existing = try context.fetch(existingQuery)
    let existingByIdentity = Dictionary(uniqueKeysWithValues: existing.map { ($0.identity, $0) })

    var newIdentities = Set<String>()
    for server in newSupported {
        let identity = ServerIdentity.compute(from: server)
        newIdentities.insert(identity)
        if let row = existingByIdentity[identity] {
            // Refresh metadata, preserve lastLatencyMs
            row.missingFromLastFetch = false
            row.name = server.displayName
        } else {
            // New server — insert
            _ = try persistSupported(server, subscriptionID: subscriptionID, in: context)
        }
    }
    // Mark disappeared servers
    for row in existing where !newIdentities.contains(row.identity) {
        row.missingFromLastFetch = true
    }
}
```

---

## State of the Art

| Old Approach (Phase 2 baseline) | New Approach (Phase 3) | When Changed | Impact |
|---------------------------------|------------------------|--------------|--------|
| `ServerConfig.subscriptionURL: String?` как метаданная | Manual FK `ServerConfig.subscriptionID: UUID?` → `Subscription` @Model | Phase 3 Wave 1 | Multi-subscription support; D-05 |
| ConfigImporter «replace pool по URL» | ConfigImporter «merge into existing Subscription» (D-14) | Phase 3 Wave 2 | Server identity preservation: lastLatencyMs не сбрасывается при re-fetch |
| Server-list UI отсутствует (D-11 Phase 2: tap disabled) | ServerListSheet + sticky AutoCell + sections | Phase 3 Wave 3 | UX-04 partial; SRV-01..03 finish |
| sing-box urltest сам выбирает outbound в runtime | Pre-connect auto-select через TCP-probe + degenerate 1-outbound pool | Phase 3 Wave 4 | D-04: deterministic best-by-score per connect; sing-box urltest остаётся как failover в runtime (Phase 2 PROTO-10) |
| `lastLatencyMs` всегда nil (поле есть, не заполнялось) | Заполняется через ServerProbeService после probe | Phase 3 Wave 2 | UI shows real latency badges; SC-1 |

**Deprecated / outdated в Phase 3:**
- `ServerConfig.subscriptionURL: String?` — помечен deprecated, удаляется в Phase 4 через VersionedSchema. Между Phase 3-4 поле живёт, но не пишется новым кодом.
- `ServerConfig.isActive: Bool` — Phase 1 carry-forward (singleton legacy). В Phase 3 заменяется по semantics на `selectedServerID` в MainScreenViewModel (state, not persisted to SwiftData). Поле остаётся для backward compat, но не используется новым flow. Удаление — Phase 4+.

---

## Assumptions Log

> Claims tagged `[ASSUMED]` — based on training knowledge, не verified in session. Planner / discuss-phase должен confirm с пользователем перед locking.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Hiddify `cc=XX` URI parameter — standard для country hint в subscription URIs | §10 Pattern 3, Pitfall 6 | Country flags не отображаются если subscription operator не следует Hiddify convention; fallback на `🌐` — degraded UX но не блокер |
| A2 | URI fragment regex `^[A-Z]{2}\s` (например `«DE Frankfurt»`) — common pattern | §13 country derivation | Если operator использует другой формат remark (`«🇩🇪 Frankfurt»` с emoji, или `«Frankfurt-DE»`) — country code не извлекается |
| A3 | TCP-probe 500 ms timeout — достаточно для удалённых серверов (Frankfurt → MSK = ~50 ms, MSK → Helsinki = ~30 ms; worst case 200-300 ms) | §3 Pattern 1, D-03 | Если сервер по ту сторону Pacific (USA West Coast → MSK = 200+ ms) — false unreachable. **Mitigation:** D-03 уже фиксировано CONTEXT'ом; если UAT покажет проблему — увеличить до 1000 ms |
| A4 | 50 ms gap между 3 sequential TCP probes — достаточно чтобы избежать SYN-flood detection на server side | §3 Pattern 2 | Низкий риск — 3 TCP-handshakes за 1.5 секунды это normal traffic |
| A5 | SwiftData lightweight migration **поддерживает** добавление новой @Model class без code | §4 Pattern 3 | `[VERIFIED via WebSearch]` — Apple confirms «SwiftData executes lightweight migration automatically for adding one or more new models». Низкий риск |
| A6 | `RelativeDateTimeFormatter` localizable в ru/en через system locale | §10 Pattern 4 | Низкий риск — Apple-native, supports localization out of the box |
| A7 | `.refreshable` + `.presentationDetents([.large])` work together без conflict в iOS 17+ | §7 Pattern 4 | Низкий риск — оба modifier'а Apple-native, нет известных incompatibility issues |
| A8 | `UIImpactFeedbackGenerator(style: .light)` доступен на iPhone (haptic motor required) | UI-SPEC §2.5 | Низкий риск — все iPhone 7+ имеют taptic engine; iPad/macOS — fallback no-op |

**Risks без `[ASSUMED]` tag:** все decisions из CONTEXT (D-01..D-14) считаются user-locked, не assumed. Реализационные patterns (TaskGroup, AsyncStream, NWConnection async wrapping) `[VERIFIED]` через Apple docs.

---

## Open Questions

1. **Probing concurrency limit — нужен ли throttle на TaskGroup?**
   - What we know: Network framework handles internal concurrency; 50-100 параллельных TCP-handshakes — стандартная нагрузка для современных iOS/macOS.
   - What's unclear: Если subscription returns 200+ серверов — есть ли OS-level throttling? Возможны ли issues с network conditioner на корпоративных Wi-Fi?
   - Recommendation: НЕ throttle'ить в Phase 3 (D-02 — TaskGroup, no limit). Plan-check может предложить добавить `.semaphore`-based limit (например max 30 concurrent) как safety net. UAT покажет нужно ли.

2. **Server-identity для дедупликации — host+port+protocolID+sni достаточно?**
   - What we know: Phase 2 CONTEXT D-06 фиксирует `host + port + protocolID + sni` как dedup key.
   - What's unclear: Если operator меняет sni на том же host:port → новый сервер или тот же? Если меняется password (Trojan) → не учитывается в identity, что может привести к stale Keychain.
   - Recommendation: Wave 2 task на implement merge: добавить test cases (UAT) для re-fetch subscription c изменённым password — verify, что Keychain entry обновляется.

3. **`pingAllServers()` running во время disconnect/reconnect — race condition?**
   - What we know: ServerProbeService — actor, isolated.
   - What's unclear: Если pull-to-refresh идёт, и параллельно user tap'ает Connect (запускает pre-connect auto-select) — два probe-runs одновременно.
   - Recommendation: Acceptable для Phase 3 — пробы independent, не shared state на actor (каждый probe создаёт own NWConnection). Plan может явно зафиксировать «no serialization required between concurrent probeAll calls». Single-actor isolation предотвращает data races.

4. **Pre-connect auto-select timeout — что если все ping'и 1500 ms и сервер ещё не выбран?**
   - What we know: D-04 фиксирует «добавляет ~1.5 сек к connect». 3 sequential probes × 500 ms timeout = max 1500 ms per server, but параллельно — total ≤ 1500 ms.
   - What's unclear: Если probeAll'у дать жёсткий timeout (например 2000 ms) и принудительно вернуть partial results?
   - Recommendation: Phase 3 — partial OK: ConnectionButton showed `.connecting`, user видит spinner; если занимает > 3 сек — UX-04 not blocker, можно accept. Plan может зафиксировать `await withTimeout(seconds: 3.0) { probeAll(...) }` с graceful fallback.

5. **`missingFromLastFetch` UI representation — показывать ли?**
   - What we know: D-14 фиксирует «помечать, не удалять». UI-SPEC не уточняет visual differentiation.
   - What's unclear: Если сервер пометен `missingFromLastFetch = true` — рендерить ли иначе в server-list (полупрозрачно, badge «удалён в последнем обновлении»)? Или просто оставлять без изменений?
   - Recommendation: Phase 3 — НЕ показывать differently (минимизировать UI complexity). Server отображается как обычно; если user удалит вручную — OK. Phase 11 может добавить visual hint. Plan-checker должен явно подтвердить с product owner.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 16 with iOS 18 / macOS 15 SDKs | Build whole project | ✓ (Phase 1/2 baseline) | 16.x | — |
| libbox.xcframework | Phase 2 carry-forward (sing-box runtime) | ✓ | 1.13.11 | — |
| Apple Developer Program account | Code signing (DIST-01 carry-forward) | ✓ | Team UAN8W9Q82U | — |
| Active iCloud / App Group entitlement | SwiftData shared store | ✓ (Phase 1 baseline) | `group.app.bbtb.shared` | — |
| Network framework (`NWConnection`) | TCP-probe latency measurement | ✓ (built-in iOS 12+/macOS 10.14+) | system | — |
| SwiftData | New `Subscription` model | ✓ (iOS 17+/macOS 14+) | system | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

> Phase 3 is **pure code/config phase** — no new external dependencies, frameworks, or tooling. Validation Architecture and Security sections below are still required per workflow config.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (XCTest co-exists per Phase 1/2 baseline) |
| Config file | none (SwiftPM auto-discovers `Tests/<Module>Tests/`) |
| Quick run command | `xcodebuild test -scheme VPNCore -destination 'platform=iOS Simulator,name=iPhone 15'` |
| Full suite command | `xcodebuild test -workspace BBTB.xcworkspace -scheme BBTB -destination 'platform=iOS Simulator,name=iPhone 15' -resultBundlePath /tmp/bbtb-test.xcresult` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SRV-01 | Score formula `latency × (1 + lossRate)` correct | unit | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/ServerScoreTests` | ❌ Wave 0 |
| SRV-01 | TCP-probe `.ok / .timeout / .error` enumeration covers 3 states | unit (mock NWConnection через abstraction) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/ServerProbeServiceTests` | ❌ Wave 0 |
| SRV-01 | Auto-select picks min-score server, skips unreachable | unit | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/AutoSelectTests` | ❌ Wave 0 |
| SRV-01 | PoolBuilder degenerate path для selected server | unit | `xcodebuild test -scheme ConfigParser -only-testing:ConfigParserTests/PoolBuilderSingleOutboundTests` | ❌ Wave 0 |
| SRV-02 | Subscription @Model creates, persists, fetches | unit | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/SubscriptionModelTests` | ❌ Wave 0 |
| SRV-02 | ConfigImporter creates/reuses Subscription on subscription URL import | unit | `xcodebuild test -scheme MainScreenFeature -only-testing:MainScreenFeatureTests/ConfigImporterSubscriptionTests` | ❌ Wave 0 |
| SRV-02 | Multi-subscription pool — sections grouped correctly | unit | `xcodebuild test -scheme ServerListFeature -only-testing:ServerListFeatureTests/SectionGroupingTests` | ❌ Wave 0 |
| SRV-02 | Cascade delete: removing Subscription deletes all linked ServerConfig | unit | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/CascadeDeleteTests` | ❌ Wave 0 |
| SRV-02 | Merge by identity preserves lastLatencyMs on re-fetch | unit | `xcodebuild test -scheme MainScreenFeature -only-testing:MainScreenFeatureTests/MergeStrategyTests` | ❌ Wave 0 |
| SRV-03 | pullToRefresh executes 2-phase (fetch + ping) sequentially | unit (mocked fetcher + probe) | `xcodebuild test -scheme ServerListFeature -only-testing:ServerListFeatureTests/PullToRefreshTests` | ❌ Wave 0 |
| UX-04 | ServerListSheet renders sticky AutoCell + sections + rows | snapshot или UI test | manual UAT | ❌ Wave 5 (UAT) |
| UX-04 | Country flag derivation correctness (cc= param, fragment regex, fallback) | unit | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/CountryFlagTests` | ❌ Wave 0 |
| (cross-cutting) | SwiftData Phase 2→3 data migration idempotent | unit (in-memory store + 2x migrate call) | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/Phase3MigrationTests` | ❌ Wave 0 |
| (cross-cutting) | Auto-select fallback strategy when 0 reachable servers | unit | `xcodebuild test -scheme VPNCore -only-testing:VPNCoreTests/AutoSelectTests/testAllUnreachable` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `swift test --package-path BBTB/Packages/<Module>` (затронутый module only) — fast feedback ~5-15 сек.
- **Per wave merge:** Full SwiftPM test для всех затронутых modules (`VPNCore`, `ConfigParser`, `AppFeatures`).
- **Phase gate:** Full Xcode build + test (`xcodebuild test -workspace ...`) для iOS Simulator + macOS, плюс UAT (Phase 1/2 carry-forward UAT pattern).

### Wave 0 Gaps

Existing tests cover Phase 1/2 functionality only. Phase 3 requires новые test files:

- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerProbeServiceTests.swift` — TCP probe state machine, timeout handling (use `Network`/mock loopback or `localhost:PORT_NOT_LISTENING` для timeout case)
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerScoreTests.swift` — pure score formula tests (no IO)
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/SubscriptionModelTests.swift` — @Model CRUD
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/CascadeDeleteTests.swift` — manual cascade verification
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/Phase3MigrationTests.swift` — idempotency, empty store, Phase 2 rows present
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/CountryFlagTests.swift` — flag derivation
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/AutoSelectTests.swift` — winner selection + fallback
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderSingleOutboundTests.swift` — degenerate path
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift` — Subscription branch
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MergeStrategyTests.swift` — D-14 merge by identity
- [ ] `BBTB/Packages/AppFeatures/Sources/ServerListFeature/` + Tests/ — новый target, новые test файлы
- [ ] No framework install needed — Swift Testing уже доступно через Xcode 16.

---

## Security Domain

> security_enforcement enabled (default — нет `false` в config). Включаем Security Domain.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 3 не добавляет auth flows; Subscription URLs могут содержать token в URL — обрабатывается Phase 2 (SubscriptionURLFetcher) уже. |
| V3 Session Management | no | Нет user sessions; VPN tunnel session — Phase 2 baseline. |
| V4 Access Control | no | App-local data; нет multi-user. |
| V5 Input Validation | **yes** | Phase 2 baseline: SubscriptionURLFetcher rejects non-HTTPS; UniversalImportParser classifies inputs strictly. **Phase 3 NEW input surface:** Subscription.name (derived from URL host или Profile-Title header — server-controlled string). Should be sanitized: max length 100 chars, strip control chars. |
| V6 Cryptography | no (carry-forward only) | Phase 1 — Keychain `kSecAttrAccessibleWhenUnlocked` для config secrets; Phase 3 не вводит новый crypto. |
| V9 Communication Security | **yes** | Phase 2 baseline: SubscriptionURLFetcher HTTPS-only enforced. **Phase 3 carry-forward gap:** W-02-09 (no body-size cap, no redirect-chain cap on subscription fetch) — accepted risk до Phase 7. |
| V12 File and Resource | no | SwiftData store — App Group sandbox; нет user-supplied file paths. |
| V13 API and Web Service | no | App-local API only. |

### Known Threat Patterns for Phase 3 stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious subscription URL response with oversized body | Denial of Service | Phase 7 DPI-08 + body cap. **Phase 3:** accepted carry-forward W-02-09. Document в Phase 3 SECURITY.md. |
| Malicious subscription URL response with too-long `Profile-Title` header — UI overflow / parsing crash | Tampering | New control: clamp `Subscription.name` к first 100 chars after stripping `\n\r\t`. |
| TCP-probe leaks user IP to malicious server | Information Disclosure | **Accepted:** TCP-probe идёт поверх системного интернета (не VPN), потому что pre-connect требует probe ДО tunnel установлен. User's real IP видим server (он уже знал host из конфига — это и так его сервер). Document в `wiki/security-gaps.md`. |
| SwiftData `@Predicate` injection через Subscription.url | Tampering | `@Predicate` использует Swift macro — type-safe, no string interpolation; SwiftData выполняет parameterized queries. **Mitigated by framework.** `[VERIFIED: developer.apple.com/documentation/swiftdata/predicate]` |
| Race condition: pingAll runs while user deletes subscription → orphan probe results | Tampering (data integrity) | **Mitigation:** ServerProbeService.probeAll вызывает `Task.isCancelled` check between iterations; ServerListViewModel.deleteSubscription cancels in-flight probe Task. |
| Country flag derivation via URI param `cc=<malicious-string>` → emoji injection / unexpected glyph | Tampering | Validate: `cc` value matches `^[A-Za-z]{2}$` regex strict. Reject otherwise → fallback 🌐. |
| Pull-to-refresh DoS: user spams pulls → many concurrent subscription fetches → backend overwhelmed | Denial of Service | `.refreshable` system handles debounce (system spinner blocks subsequent pulls until current completes). Acceptable risk. |
| Subscription disappears mid-fetch → leftover Subscription row | Tampering | D-07 cascade delete: removing Subscription deletes all linked ServerConfig. Wave 1 task — verify cascade test. |

**Phase 3 SECURITY.md draft (для Wave 5):** 8-9 threats identified, 0 BLOCKER expected. Carry-forward W-02-09 (body cap) → Phase 7. New control: clamp Subscription.name. Document IP-leak via TCP-probe в wiki.

---

## Project Constraints (from CLAUDE.md)

| Directive | Source | Phase 3 Application |
|-----------|--------|---------------------|
| Никогда не модифицировать `raw/` | CLAUDE.md Rules | Phase 3 не трогает `raw/` — все source-of-truth там carry-forward; Phase 3 операционные артефакты в `.planning/phases/03-server-management/` |
| Wiki как долговременная память решений | CLAUDE.md Synchronization + MEMORY feedback_wiki_decision_log | После Phase 3 — обновить `wiki/architecture.md` (новый ServerListFeature sub-module + Subscription @Model в VPNCore), `wiki/ux-specification.md` (server-list final state — Phase 11 для финала, Phase 3 — промежуточный шаг), создать `wiki/server-management.md` (концепт-страница для auto-select, multi-subscription, TCP-probe архитектуры) |
| Каждое архитектурное решение → wiki | CLAUDE.md GSD section | D-01..D-14 (14 решений CONTEXT) → переносим в `wiki/server-management.md` после Phase 3 close (контекст + решение + обоснование + что становится TODO для Phase 11) |
| Все ответы в Russian | CLAUDE.md Rules | Phase 3 user-facing strings — RU + EN через `Localizable.xcstrings` (UI-SPEC §9.5 — 22 новых ключей) |
| Сокращения → русские переводы в скобках | CLAUDE.md Rules | API → Application Programming Interface (программный интерфейс); FK → Foreign Key (внешний ключ); TCP → Transmission Control Protocol (протокол управления передачей); etc. — применять в wiki, но не загромождать код-комментарии |
| Source of truth — `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` | CLAUDE.md GSD section | Phase 3 матрицы requirements (SRV-01..03, UX-04) — derived из v2 prompt; не отклоняться от core values |
| Никаких сторонних аналитических SDK | CLAUDE.md (tech-stack.md) | Phase 3 не добавляет аналитику — OSLog для local diagnostic only |
| Только проверенные библиотеки | CLAUDE.md (tech-stack.md) | Phase 3 — все frameworks Apple-native (Network, SwiftData, SwiftUI); zero new deps |
| Локализация ru + en с первого дня | CLAUDE.md (требование LOC-01) | UI-SPEC §9.5 — 22 ключей в `Localizable.xcstrings` |

---

## Sources

### Primary (HIGH confidence)

- [Apple — NWConnection](https://developer.apple.com/documentation/network/nwconnection) — State handler semantics, connection lifecycle.
- [Apple — connectionTimeout (NWProtocolTCP.Options)](https://developer.apple.com/documentation/network/nwprotocoltcp/options/connectiontimeout) — Default timeout values (verified ~60 sec).
- [Apple — Detecting connection timeout with NWConnection (Forum 128576)](https://developer.apple.com/forums/thread/128576) — Manual timeout pattern.
- [Apple — NWConnection receive — cancel? (Forum 120438)](https://developer.apple.com/forums/thread/120438) — Strong reference requirement.
- [Apple — SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer) — Container API, schema migration.
- [Apple — `.refreshable(action:)`](https://developer.apple.com/documentation/swiftui/view/refreshable(action:)) — Pull-to-refresh modifier.
- [Apple — Schema.Relationship.DeleteRule.cascade](https://developer.apple.com/documentation/swiftdata/schema/relationship/deleterule-swift.enum/cascade) — Cascade delete rule semantics.
- [Apple — Beyond the basics of structured concurrency (WWDC 23)](https://developer.apple.com/videos/play/wwdc2023/10170/) — TaskGroup cancellation, AsyncStream from groups.
- [Apple — Explore structured concurrency in Swift (WWDC 21)](https://developer.apple.com/videos/play/wwdc2021/10134/) — Foundational TaskGroup patterns.
- [Apple — Migrate to SwiftData (WWDC 23)](https://developer.apple.com/videos/play/wwdc2023/10189/) — Migration concepts.
- [Apple — Model your schema with SwiftData (WWDC 23)](https://developer.apple.com/videos/play/wwdc2023/10195/) — Schema design.

### Secondary (MEDIUM confidence — verified with primary где возможно)

- [Hacking with Swift — Lightweight vs complex migrations](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations) — Confirms «add @Model = lightweight».
- [Hacking with Swift — How to cancel a task group](https://www.hackingwithswift.com/quick-start/concurrency/how-to-cancel-a-task-group) — Cooperative cancellation.
- [Hacking with Swift — How SwiftData works with Swift concurrency](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency) — @Model not Sendable rule.
- [SwiftLee — Task Groups in Swift](https://www.avanderlee.com/concurrency/task-groups-in-swift/) — Production usage patterns.
- [Donny Wals — Swift Concurrency's TaskGroup explained](https://www.donnywals.com/swift-concurrencys-taskgroup-explained/) — Iteration over AsyncSequence behavior.
- [BrightDigit — Using ModelActor in SwiftData](https://brightdigit.com/tutorials/swiftdata-modelactor/) — ModelActor pattern, PersistentIdentifier across actors.
- [Sarunw — Pull to refresh in SwiftUI with refreshable](https://sarunw.com/posts/pull-to-refresh-in-swiftui/) — Practical .refreshable usage.

### Tertiary (LOW confidence — flagged for validation if claims load-bearing)

- Hiddify `cc=XX` URI convention — community-documented, not RFC. **Assumption A1.**
- URI fragment regex `^[A-Z]{2}\s` pattern для country extraction — heuristic. **Assumption A2.**

### Project artifacts (carry-forward authoritative)

- `.planning/phases/03-server-management/03-CONTEXT.md` — 14 decisions (D-01..D-14)
- `.planning/phases/03-server-management/03-UI-SPEC.md` — visual design contract
- `.planning/phases/02-trojan-import-flow/02-RESEARCH.md` — sing-box urltest, NETunnelProviderManager runtime update patterns
- `.planning/phases/02-trojan-import-flow/02-CONTEXT.md` — Phase 2 D-01/D-06/D-07 (one manager, server-identity, pool replace strategy)
- `wiki/ux-specification.md` — Server list final state (Phase 11 target)
- `wiki/architecture.md` — Module structure baseline
- `wiki/tech-stack.md` — Tech constraints (Swift 6, no 3rd-party deps, no analytics SDKs)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Apple-native, Phase 1/2 carry-forward verified.
- Architecture: HIGH — Phase 2 patterns directly apply; new ServerListFeature module clearly bounded.
- Pitfalls: HIGH — Apple-documented quirks (NWConnection strong-ref, SwiftData Sendable, .refreshable cancellation) verified.
- Country derivation: MEDIUM (LOW for A1/A2 heuristics) — fallback `🌐` reduces blast radius.
- TCP probe timing: MEDIUM — A3 (500 ms timeout) acceptable per D-03; can tune in UAT.
- Migration strategy: HIGH — lightweight migration + idempotent data migration script standard pattern.

**Research date:** 2026-05-12
**Valid until:** 2026-06-11 (30 days — Apple frameworks stable; review if Xcode 17 / iOS 19 ships в interim)

---

*Phase: 03-server-management*
*Researcher: gsd-phase-researcher*
*Downstream consumer: gsd-planner (will produce 03-PLAN.md), gsd-executor, gsd-verifier*
