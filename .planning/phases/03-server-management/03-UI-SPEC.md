---
phase: 3
slug: server-management
status: draft
shadcn_initialized: false
preset: not applicable (SwiftUI native, Apple platforms)
created: 2026-05-12
---

# Phase 3 — UI Design Contract

> Контракт визуала и взаимодействий для версии v0.3 (Server management — multi-subscription, server-list sheet, auto-select по score, pull-to-refresh). Промежуточный шаг к финальному Phase 11 UX (`wiki/ux-specification.md`).
> Платформа: SwiftUI native iOS 17+ / macOS 14+. Никакого web/React стека — таблицы шкал ниже выражены в pt и сопоставлены с системными `Font.TextStyle` / SF Symbols.
> Все component identifiers, SF Symbols, UserDefaults keys — English. Все пользовательские строки — Russian + English через `Localizable.xcstrings`.
> Все 14 решений (D-01..D-14) взяты из `03-CONTEXT.md` — UI-SPEC только конкретизирует визуальные/UX-параметры.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (SwiftUI native, no shadcn) |
| Preset | not applicable (Apple platforms — SwiftUI) |
| Component library | SwiftUI native + Phase 2 `DesignSystem` package (`DS.Spacing`, `DS.Radius`, `DS.Typography`) |
| Icon library | SF Symbols (system) |
| Font | San Francisco (system) — через `Font.TextStyle` (Dynamic Type compatible) |

> shadcn-init gate: **N/A** — стек Swift/SwiftUI, components.json не применим. Registry-safety gate: **N/A** — нет third-party registries, никаких внешних шаблонов в Phase 3.

---

## 1. Information Architecture

### 1.1 Карта экранов (Phase 3 delta)

```
RootScene
├─ MainScreenView ............................................. главный экран (Phase 2)
│   ├─ NavigationLink → SettingsView (Phase 2)
│   ├─ Menu "+" → importFromPasteboard / QR (Phase 2, расширяется: subscription URL = создаёт @Model Subscription)
│   └─ ServerLineView ........................................ tap ENABLED (Phase 3) → presentServerList()
│
└─ ServerListSheet [NEW Phase 3] .............................. sheet (.large detent) — D-08
    ├─ ScrollView c .refreshable [pull-to-refresh] ............ D-13
    │   ├─ AutoCell ........................................... закреплено в топе (sticky) — D-10
    │   ├─ Section[Subscription А] ........................... header = SubscriptionHeader
    │   │   └─ ServerRow × N
    │   ├─ Section[Subscription Б]
    │   │   └─ ServerRow × N
    │   └─ Section["Добавлены вручную"] ...................... для серверов с subscriptionID = nil
    └─ Swipe-actions:
        ├─ ServerRow swipe → «Удалить сервер» (D-07)
        └─ SubscriptionHeader swipe → «Удалить подписку» (cascade, D-07)
```

### 1.2 Граф навигации (Phase 3 delta)

| Откуда | Куда | Trigger | Презентация |
|---|---|---|---|
| MainScreen | ServerListSheet | tap по `ServerLineView` (Phase 3 включает tap) | `.sheet` с `.presentationDetents([.large])`, `.presentationDragIndicator(.visible)` |
| ServerListSheet | dismiss + connect | tap по `ServerRow` ИЛИ `AutoCell` | sheet dismiss → applySelection → if tunnel active → reconnect (D-09) |
| ServerListSheet | dismiss | swipe down ИЛИ tap по фону вне sheet (iOS) / `✕` toolbar (macOS) | sheet dismiss без действий |
| ServerListSheet | confirm delete subscription | swipe по header → «Удалить» | `.confirmationDialog` («Удалить подписку «{name}»? Будет удалено N серверов.») |
| ServerListSheet | confirm delete server | swipe по row → «Удалить» | inline destructive action (без confirm — единичный объект, D-07) |
| ServerListSheet | progress overlay | pull-to-refresh запущен | inline header indicator (`.refreshable` system spinner) — без full-screen overlay |
| ServerListSheet | re-fetch failure alert | network error при refresh | `.alert` поверх sheet (не диcмиссит sheet) |
| MainScreen (`+` menu) | subscription URL import | классификация даёт `.httpURL` → subscription | Phase 2 `ImportProgressOverlay` (`.regularMaterial`) — без изменений в UI, но downstream создаёт `Subscription` @Model + привязывает `ServerConfig.subscriptionID` |

### 1.3 Состояния ServerListSheet

```
ServerListState (новый enum в Phase 3):
  .loading          ← initial mount, до первого pingAllServers() — skeleton rows
  .loaded           ← список отрисован, latency badges заполнены (могут быть .unknown по серверам)
  .pinging          ← фоновый ping в процессе (после pull-to-refresh или auto-select trigger) — badges рендерятся прогрессивно
  .refreshing       ← pull-to-refresh: fetch subscription + ping; `.refreshable` system spinner виден
  .refreshError(msg)← network error при refresh; alert, sheet остаётся открыт
  .empty            ← нет ни одного ServerConfig вообще (теоретически невозможно — Phase 2 empty-state блокирует переход в Phase 3)
```

> `.empty` ветка — defensive, чтобы крэш не падал если пользователь удалил все серверы через swipe. Показывает inline empty-card внутри sheet (см. §3.5).

---

## 2. ServerListSheet — layout

### 2.1 Вертикальная композиция (loaded state)

```
┌────────────────────────────────────────────────────┐
│  ▬▬▬ (drag indicator)                              │  ← .presentationDragIndicator(.visible)
│                                                    │
│ ┌──────────────────────────────────────────────┐   │
│ │  ⚡  Авто (рекомендуется)              ✓     │   │  ← AutoCell (sticky, top)
│ │       Выберет лучший по скорости             │   │
│ └──────────────────────────────────────────────┘   │
│                                                    │
│  ПОДПИСКА А                          ↻ 2ч назад   │  ← SubscriptionHeader
│ ┌──────────────────────────────────────────────┐   │
│ │ 🇩🇪 Frankfurt #1                    42 ms     │   │  ← ServerRow
│ ├──────────────────────────────────────────────┤   │
│ │ 🇳🇱 Amsterdam #1                    58 ms     │   │
│ ├──────────────────────────────────────────────┤   │
│ │ 🇫🇮 Helsinki #2          [не поддерживается]  │   │  ← isSupported = false
│ ├──────────────────────────────────────────────┤   │
│ │ 🇱🇻 Riga #1                   недоступен      │   │  ← 3/3 timeout
│ └──────────────────────────────────────────────┘   │
│                                                    │
│  ПОДПИСКА Б                         ↻ 5 мин назад │
│ ┌──────────────────────────────────────────────┐   │
│ │ 🇸🇪 Stockholm #1                    71 ms     │   │
│ └──────────────────────────────────────────────┘   │
│                                                    │
│  ДОБАВЛЕНЫ ВРУЧНУЮ                                 │  ← Section для subscriptionID = nil
│ ┌──────────────────────────────────────────────┐   │
│ │ 🌐 Custom (paste)                  133 ms     │   │
│ └──────────────────────────────────────────────┘   │
│                                                    │
└────────────────────────────────────────────────────┘
```

### 2.2 Sheet container

| Свойство | Значение |
|---|---|
| Presentation | `.sheet(isPresented:)` |
| Detents | `.presentationDetents([.large])` — full-height на iOS |
| Drag indicator | `.presentationDragIndicator(.visible)` |
| Background interaction | `.presentationBackgroundInteraction(.disabled)` (фон не интерактивен пока sheet открыт) |
| macOS size | 480×720 pt (resizable=true, min 400×600) |
| Scroll | `ScrollView { LazyVStack(spacing: 0) }` с `.refreshable { await viewModel.pullToRefresh() }` |
| Background | `Color(.systemGroupedBackground)` (iOS) / `Color(NSColor.windowBackgroundColor)` (macOS) — отличается от MainScreen surface чтобы подчеркнуть modality |

### 2.3 AutoCell — спецификация компонента [D-10]

| Элемент | Свойство | Значение |
|---|---|---|
| Container | shape | `RoundedRectangle(cornerRadius: DS.Radius.cardLarge = 16)` |
| Container | background | `Color(.secondarySystemBackground)` |
| Container | padding | `.lg` (16 pt) вертикальный, `.lg` (16 pt) горизонтальный |
| Container | margin | `.lg` (16 pt) от краёв sheet, `.sm` (8 pt) bottom |
| Container | min-height | 72 pt (touch target + breathing room) |
| Sticky behaviour | `.scrollIndicatorsFlash(false)` + position above первой секции (не sticky-on-scroll — top-pinned by layout) |
| Leading icon | SF Symbol | `bolt.fill` |
| Leading icon | size | `.system(size: 28, weight: .semibold)` |
| Leading icon | foreground | `Color.accentColor` if `isAutoSelected == true` else `.secondary` |
| Leading icon | container | `Circle()` 48×48, fill `Color.accentColor.opacity(0.15)` if selected else `.tertiarySystemFill` |
| Trailing checkmark | SF Symbol | `checkmark.circle.fill` |
| Trailing checkmark | visible if | `isAutoSelected == true` (`selectedServerID == nil` в `MainScreenViewModel`) |
| Trailing checkmark | foreground | `Color.accentColor` |
| Trailing checkmark | size | `.system(size: 24, weight: .semibold)` |
| Title | text | `L10n.serverAutoTitle` = «Авто (рекомендуется)» |
| Title | font | `DS.Typography.title` (= `.title3 .bold .rounded`) |
| Subtitle | text | `L10n.serverAutoSubtitle` = «Выберет лучший по скорости» |
| Subtitle | font | `DS.Typography.subheadline` |
| Subtitle | foreground | `.secondary` |
| Tap action | — | `selectAuto()` → sets `selectedServerID = nil` → dismiss sheet → if tunnel active → reconnect (D-09) |
| Animation | — | `.symbolEffect(.bounce, value: isAutoSelected)` на checkmark при изменении |

### 2.4 SubscriptionHeader — спецификация компонента

| Элемент | Свойство | Значение |
|---|---|---|
| Container | layout | `HStack` |
| Container | padding | `.lg` (16 pt) horizontal, `.sm` (8 pt) vertical |
| Container | background | inherit (no separate fill) |
| Title | text | `subscription.name` (по умолчанию = host из subscription URL, например `«panel.example.com»`) |
| Title | font | `.system(.caption, design: .default).weight(.semibold)` (UPPERCASE через `.textCase(.uppercase)`) |
| Title | foreground | `.secondary` |
| Trailing | layout | last-fetched indicator |
| Trailing | content | SF Symbol `arrow.clockwise` (size 11 pt, weight `.regular`) + relative timestamp (`«2ч назад»`, `«5 мин назад»`, `«только что»`) |
| Trailing | font | `.system(.caption2)` |
| Trailing | foreground | `.tertiary` |
| Trailing | logic | если `subscription.lastFetched == nil` → "—" |
| Trailing | format | `RelativeDateTimeFormatter` с `.named` style, `unitsStyle: .short` |
| Swipe action | trigger | `.swipeActions(edge: .trailing, allowsFullSwipe: false)` |
| Swipe action | label | `L10n.serverList.deleteSubscription` = «Удалить» |
| Swipe action | tint | `Color.red` (destructive) |
| Swipe action | confirmation | `.confirmationDialog` (см. §6.1) |

**Особый случай — "Добавлены вручную" секция:**
- `subscription = nil` для всей секции (виртуальная)
- Title = `L10n.serverList.manualSection` = «Добавлены вручную»
- Trailing — пусто (нет lastFetched)
- Swipe action **disabled** (нечего «удалять» — это не подписка, а группа одиночных серверов)

### 2.5 ServerRow — спецификация компонента [D-11]

| Элемент | Свойство | Значение |
|---|---|---|
| Container | layout | `HStack(spacing: DS.Spacing.md = 12)` |
| Container | padding | `.lg` (16 pt) horizontal, `.md` (12 pt) vertical |
| Container | min-height | 56 pt (44 pt touch + breathing room) |
| Container | background | `Color(.secondarySystemBackground)` (iOS) / `Color(NSColor.controlBackgroundColor)` (macOS) |
| Container | separator | system default (`Divider()` between rows внутри секции) |
| Container | corner radius | `DS.Radius.card = 12` для группы (применяется через `.clipShape` к первой/последней строке секции) |
| Container | opacity | `0.4` если `isSupported == false` или 3/3 timeout |
| Leading flag | emoji | `ServerConfig.countryFlag` (Unicode regional indicator pair, например `🇩🇪`) |
| Leading flag | font | `.system(size: 24)` |
| Leading flag | fallback | `🌐` (globe) если страна не определена (paste-imported без country hint) |
| Title | text | `ServerConfig.name` (`remark` из URI fragment, fallback `host`) |
| Title | font | `DS.Typography.body` (`.body .regular`) |
| Title | foreground | `.primary` (или `.secondary` если `isSupported = false`) |
| Title | line limit | 1 (truncate tail) |
| Title | accessibility | full name в `accessibilityLabel` |
| Trailing badge | type | latency badge ИЛИ "не поддерживается" pill ИЛИ "недоступен" text |
| Trailing badge (latency, OK) | text | `"\(ms) ms"` |
| Trailing badge (latency, OK) | font | `.system(.subheadline, design: .rounded).monospacedDigit()` |
| Trailing badge (latency, OK) | foreground | по latency-tier (см. §2.6) |
| Trailing badge (unsupported) | text | `L10n.serverList.unsupportedBadge` = «не поддерживается» |
| Trailing badge (unsupported) | style | capsule, padding `.sm` h × `.xs` v, background `.tertiarySystemFill`, foreground `.secondary`, font `.caption2 .medium` |
| Trailing badge (unreachable) | text | `L10n.serverList.unreachable` = «недоступен» |
| Trailing badge (unreachable) | font | `.system(.subheadline)` |
| Trailing badge (unreachable) | foreground | `Color.red` |
| Trailing badge (pinging) | content | `ProgressView()` `.scaleEffect(0.7)` |
| Trailing checkmark | visible if | `serverConfig.id == selectedServerID` (manual selection) |
| Trailing checkmark | SF Symbol | `checkmark.circle.fill` |
| Trailing checkmark | foreground | `Color.accentColor` |
| Trailing checkmark | size | `.system(size: 22, weight: .semibold)` |
| Tap action | enabled | only if `isSupported == true && lastPingResult != .allTimeout` |
| Tap action | — | `selectServer(id)` → set `selectedServerID = id` → dismiss sheet → if tunnel active → reconnect (D-09) |
| Tap feedback | iOS | `UIImpactFeedbackGenerator(style: .light).impactOccurred()` при выборе |
| Tap feedback | macOS | no-op |
| Swipe action | trigger | `.swipeActions(edge: .trailing, allowsFullSwipe: false)` |
| Swipe action | label | `L10n.serverList.deleteServer` = «Удалить» |
| Swipe action | tint | `Color.red` |
| Swipe action | confirm | inline (без alert) — одиночный сервер, не cascade |

### 2.6 Latency tiers — цветовая семантика

| Tier | Range (ms) | Foreground color | Semantic | Wiki source |
|---|---|---|---|---|
| Excellent | 0–80 | `Color.green` | «отлично» | mapping из `ux-specification.md` (signal-strength dot) |
| Good | 81–200 | `Color(.systemYellow)` | «приемлемо» | same |
| Poor | 201–500 | `Color.orange` | «медленно» | same |
| Bad | 501+ | `Color.red` | «плохо» | same |
| Unknown | nil | `.secondary` | «не измерен» | initial state |
| Unreachable | 3/3 timeout | `Color.red` (текст «недоступен») | sentinel | D-03 |

> Цвет применяется **только** к тексту latency badge — без отдельной dot/иконки (signal-strength dot — Phase 11 финал, см. §13).

---

## 3. Pull-to-refresh + ping flow [D-12, D-13]

### 3.1 Trigger sources

| Source | Trigger | Что выполняется |
|---|---|---|
| App foreground (D-12) | `.onChange(of: scenePhase) where .active` | silent refresh всех подписок + ping всех серверов; без UI overlay (badges обновляются на фоне) |
| ServerListSheet pull-to-refresh (D-13) | системный `.refreshable` (swipe-down при `scrollOffset > threshold`) | (1) fetch subscription URL ∀ Subscription → merge ServerConfig (D-14) → (2) ping всех supported серверов через TCP-пробу TaskGroup |
| Auto-select pre-connect (D-04) | tap ConnectionButton (`.idle` → `.connecting`) при `selectedServerID == nil` | ping всех supported серверов → выбрать min score → передать в PoolBuilder → start tunnel |

### 3.2 Visual indicators

| State | Indicator | Placement |
|---|---|---|
| `.refreshing` | `.refreshable` system spinner (UIRefreshControl-like) | top of sheet, system position |
| `.pinging` (per row) | `ProgressView().scaleEffect(0.7)` | в trailing slot ServerRow вместо latency badge |
| `.pinging` (background, foreground refresh) | none | без overlay; пользователь видит как badges обновляются |
| Auto-select pre-connect | ConnectionButton переходит в `.connecting` (с Phase 2 анимацией bounce) | главный экран — без отдельного индикатора в sheet (sheet закрыт) |
| Network error при refresh | inline alert поверх sheet | system `.alert` modifier |

### 3.3 Progressive UI update (D-02)

ServerRow обновляется **немедленно** при завершении его TCP-пробы (а не «все 3 пробы»):
- проба 1 завершилась → если `latencyMs` есть → отобразить (предварительная оценка)
- проба 2 завершилась → пересчитать avg → обновить
- проба 3 завершилась → финальный score, `lastLatencyMs = avg(successful)`

Это даёт visual feedback за ~150–500 ms вместо 1500 ms ожидания.

### 3.4 Refresh failure alert (партиальный failure)

| Случай | Поведение |
|---|---|
| Все подписки fetch'нулись успешно, все серверы запинговались | dismiss spinner silently, sheet остаётся в `.loaded` |
| Одна подписка fetch failed | inline error на SubscriptionHeader: badge «обновление не удалось» (tooltip с деталями), остальные обновились |
| Все подписки fetch failed | `.alert` поверх sheet: title = «Не удалось обновить подписки», message = «Проверьте подключение к интернету и попробуйте снова.», single button «OK» |
| Network reachable но subscription URL вернул 4xx/5xx | inline indicator на SubscriptionHeader: `exclamationmark.triangle` (orange) + tooltip с HTTP кодом |
| Ping всех серверов 3/3 timeout | без alert — каждый сервер показывает «недоступен» badge |

### 3.5 Inline empty card (defensive)

Если после удаления всех серверов (через swipe) sheet остался открыт:

| Элемент | Свойство |
|---|---|
| Container | `VStack(spacing: DS.Spacing.lg)` centered, padding `.xxl` (32 pt) |
| Icon | SF Symbol `tray` size 48 pt, foreground `.tertiary` |
| Title | text `L10n.serverList.emptyTitle` = «Нет серверов», font `DS.Typography.title` |
| Subtitle | text `L10n.serverList.emptySubtitle` = «Импортируйте конфигурацию через «+» на главном экране.», font `DS.Typography.subheadline`, `.secondary`, multiline center |
| Action | (нет inline-кнопки — fallback к dismiss → MainScreen empty-state) |

AutoCell тоже скрывается (нечего автоселектить).

---

## 4. ServerLineView — изменения [Phase 3 delta]

### 4.1 Tap ENABLED [D-08]

Phase 2 имел `Tap disabled (полный server-list — Phase 3 SRV-*)`. **Phase 3 включает tap.**

| Элемент | Phase 2 | Phase 3 |
|---|---|---|
| Tap action | disabled | `presentServerList()` → opens `.sheet` |
| Chevron `›` | hidden | **shown** (SF Symbol `chevron.right`, size 11 pt, foreground `.tertiary`) |
| Hit area | content-sized | extended через `.contentShape(Rectangle())` для удобного тапа по всей строке |
| Accessibility hint | — | `«Дважды нажмите чтобы открыть список серверов»` |

### 4.2 Контент name — расширение

Phase 2 имел:
- 1 outbound → `name = ServerConfig.remark`
- N outbound → `name = "Авто"`

Phase 3:
- `selectedServerID != nil` → `name = ServerConfig.name(by: selectedServerID)`
- `selectedServerID == nil` → `name = L10n.serverAuto` («Авто»)

> Содержание поля `name` управляется `MainScreenViewModel.selectedServerID`, а не количеством outbound'ов в pool. Pool всегда содержит >1 outbound (urltest), но manual selection переопределяет fallback.

### 4.3 Сигнал-strength dot — **NOT** в Phase 3

Wiki `ux-specification.md` упоминает «иконку-индикатор справа: signal-strength по latency (зелёный/жёлтый/красный)» на ServerLineView. **Это отложено в Phase 11** (UX финал) — Phase 3 показывает только текстовое имя + chevron. Latency tier по выбранному серверу видно при открытии ServerListSheet.

---

## 5. ConfigImporter — изменения [Phase 3 delta]

### 5.1 Subscription URL импорт — теперь создаёт @Model Subscription [D-06]

Phase 2 импортировал subscription URL → массив `ServerConfig` с `subscriptionURL: String?` на каждом. Phase 3 расширяет:

```
import subscription URL
    ↓
[Phase 3 NEW] check if Subscription c этим URL уже существует:
    YES → use existing.id, обновить `lastFetched`, merge серверов (D-14)
    NO  → create @Model Subscription { id, url, name = derive(url), lastFetched = now }
    ↓
для каждого parsed ServerConfig:
    → set ServerConfig.subscriptionID = subscription.id
    → set ServerConfig.subscriptionURL = nil (replaced by FK)
    ↓
[Phase 2 unchanged] SwiftData persist + Keychain save + provisionTunnelProfile
    ↓
[Phase 3 NEW] success alert: title включает имя подписки
```

### 5.2 Derive `Subscription.name` from URL

| URL pattern | Derived name |
|---|---|
| `https://panel.example.com/sub/xxx` | `panel.example.com` (host only) |
| `https://api.foo.bar/v1/subscribe?token=...` | `api.foo.bar` |
| Содержит meta header `Subscription-Userinfo` с `name=Foo` | `Foo` (приоритет server-provided) |
| Не удалось распарсить | `«Подписка #N»` (N = next index) |

> Редактирование `Subscription.name` пользователем — **отложено в Phase 11** (CONTEXT deferred).

### 5.3 Success alert — обновлённый текст

| Случай | Title | Message |
|---|---|---|
| Subscription URL → создана новая подписка | «Подписка добавлена» | «Добавлено: %lld серверов из «%@». Будут включены в следующих версиях: %lld.» (третий аргумент опускается если 0) |
| Subscription URL → обновлена существующая подписка | «Подписка обновлена» | «Добавлено новых: %lld. Всего серверов в «%@»: %lld.» |
| Single URI paste (без подписки) | «Импорт завершён» | (Phase 2 текст без изменений) |

### 5.4 ImportProgressOverlay — без изменений

Phase 2 overlay (`ImportProgressOverlay`) реиспользуется один в один для subscription URL fetch. Spinner + label «Загрузка конфигурации…».

---

## 6. Destructive actions — спецификация [D-07]

### 6.1 Удаление подписки (cascade)

Trigger: swipe-leading на SubscriptionHeader.

| Элемент | Свойство | Значение |
|---|---|---|
| Confirmation type | `.confirmationDialog` (iOS) / `.alert` (macOS — confirmationDialog ограничен) |
| Title (iOS) | nil (system displays question как title) |
| Message | text | «Удалить подписку «%@»? Будет удалено серверов: %lld.» |
| Destructive button | text | «Удалить» |
| Destructive button | role | `.destructive` |
| Destructive button | tint | `Color.red` (auto) |
| Cancel button | text | «Отмена» |
| Cancel button | role | `.cancel` |
| On confirm | side-effect | cascade delete: `Subscription` + все `ServerConfig where subscriptionID == sub.id`; refresh server list; если `selectedServerID` был одним из удалённых → fallback к Auto (`selectedServerID = nil`) |
| On confirm + tunnel active | side-effect | reconnect через PoolBuilder с новым составом (если хоть один сервер остался); если ни одного — disconnect и MainScreen → `.empty` state |

### 6.2 Удаление одиночного сервера

Trigger: swipe-leading на ServerRow.

| Элемент | Свойство | Значение |
|---|---|---|
| Confirmation type | inline (без dialog) |
| Action | direct delete `ServerConfig` |
| Если `selectedServerID == deleted.id` | fallback к Auto |
| Если tunnel active И server в активном пуле | reconnect через PoolBuilder с обновлённым массивом |
| Undo | none (D-07 — Phase 3 не реализует undo; Phase 11 может добавить toast «Отменить» через `SubstitutionInsertion`) |

### 6.3 macOS confirmationDialog fallback

SwiftUI `.confirmationDialog` на macOS работает иначе (popover, не sheet). Контракт:
- На macOS используется `.alert` modifier с теми же параметрами
- Buttons: «Удалить» (`.destructive`) + «Отмена» (`.cancel`)
- Identical strings, identical side-effects

---

## 7. Component Inventory & Refactor Plan

### 7.1 Phase 2 → Phase 3 modifications

| Файл | Действие | Что меняется |
|---|---|---|
| `ServerLineView.swift` | **modify** | tap action enabled; добавляется `chevron.right`; new init: `init(name: String?, onTap: @escaping () -> Void)` |
| `ConfigImporter.swift` | **modify** | branch для `.httpURL → subscription`: создаёт/обновляет `@Model Subscription` + проставляет `subscriptionID` на каждом `ServerConfig` |
| `MainScreenViewModel.swift` | **modify** | новые published: `@Published var selectedServerID: UUID?`, `@Published var isPresentingServerList: Bool`; новые методы: `presentServerList()`, `dismissServerList()`, `selectServer(id:)`, `selectAuto()`, `pingAllServers()` async |
| `ServerConfig.swift` (VPNCore) | **modify** (SwiftData migration) | удаляется `subscriptionURL: String?`, добавляется `subscriptionID: UUID?` (lightweight migration с дефолтом nil); `lastLatencyMs: Int?` остаётся; добавляется `lastPingedAt: Date?`, `failedProbeCount: Int?` |
| `PoolBuilder.swift` (ConfigParser) | **modify** | при `selectedServerID != nil` → собрать pool из одного outbound (вместо urltest); при `nil` → текущее поведение (urltest pool из всех supported) |
| `TopBar.swift` | **no change** | menu `+` сохраняется, importer downstream создаёт Subscription автоматически |
| `MainScreenView.swift` | **modify** | добавляется `.sheet(isPresented: $vm.isPresentingServerList)` презентующий `ServerListSheet` |

### 7.2 Новые компоненты Phase 3

| Компонент | Файл | Public API |
|---|---|---|
| `ServerListSheet` | `AppFeatures/ServerListFeature/ServerListSheet.swift` (новый sub-module) | `init(viewModel: ServerListViewModel)` |
| `ServerListViewModel` | `AppFeatures/ServerListFeature/ServerListViewModel.swift` | `@Published var state: ServerListState`, `@Published var subscriptions: [Subscription]`, `@Published var orphanServers: [ServerConfig]`, методы `pullToRefresh() async`, `pingAll() async`, `deleteSubscription(_:) async`, `deleteServer(_:) async` |
| `AutoCell` | `AppFeatures/ServerListFeature/AutoCell.swift` | `init(isSelected: Bool, onTap: @escaping () -> Void)` |
| `SubscriptionHeader` | `AppFeatures/ServerListFeature/SubscriptionHeader.swift` | `init(subscription: Subscription, onDelete: @escaping () -> Void)` (для virtual "Manual" секции — отдельный inline `Text` без swipe) |
| `ServerRow` | `AppFeatures/ServerListFeature/ServerRow.swift` | `init(server: ServerConfig, isSelected: Bool, pingState: PingState, onTap: () -> Void, onDelete: () -> Void)` |
| `LatencyBadge` | `AppFeatures/ServerListFeature/LatencyBadge.swift` | `init(latencyMs: Int?, isSupported: Bool, isUnreachable: Bool, isPinging: Bool)` (рендерит правильное содержимое из §2.5 trailing slot) |
| `Subscription` @Model | `VPNCore/Sources/VPNCore/Subscription.swift` | `@Model class Subscription { id: UUID, url: String, name: String, lastFetched: Date? }` |
| `ServerProbeService` | `VPNCore/Sources/VPNCore/ServerProbeService.swift` (новый actor) | `func probe(_ server: ServerConfig) async -> ProbeResult`, `func probeAll(_ servers: [ServerConfig]) -> AsyncStream<(UUID, ProbeResult)>` |

### 7.3 Country flag derivation

`ServerConfig.countryFlag: String` — computed property:

```swift
extension ServerConfig {
    public var countryFlag: String {
        guard let code = countryCode, code.count == 2 else { return "🌐" }
        return code.uppercased().unicodeScalars
            .compactMap { Unicode.Scalar(127397 + $0.value) }
            .map { String($0) }
            .joined()
    }
}
```

`countryCode: String?` — derive sources (приоритет):
1. URI `cc=XX` query param (Hiddify convention)
2. URI fragment regex `^[A-Z]{2}\s` (например `«DE Frankfurt»`)
3. GeoIP lookup по host — **отложено в Phase 11** (offline DB добавляется позже)
4. fallback — nil (показывается 🌐)

### 7.4 Module boundaries

- **Новый sub-module:** `AppFeatures/Sources/ServerListFeature/` — содержит весь UI sheet. Depends on `Localization`, `DesignSystem`, `VPNCore` (для `ServerConfig` + `Subscription` types).
- `ServerListFeature` **не** depends on `MainScreenFeature` — связь через shared `@EnvironmentObject MainScreenViewModel` (presented в root App).
- `ServerProbeService` — внутри `VPNCore` (не в feature module — это core network-layer concern, переиспользуется в `MainScreenViewModel` для auto-select pre-connect).
- `Subscription` @Model + migration — в `VPNCore` рядом с `ServerConfig`.

---

## 8. Design Tokens (Phase 2 inherited + Phase 3 additions)

### 8.1 Spacing scale — `DS.Spacing` (no changes)

Inherits Phase 2 token set:

| Token | Value (pt) | Phase 3 usage |
|---|---|---|
| `xs` | 4 | ServerRow flag-to-name gap |
| `sm` | 8 | AutoCell margin-bottom, SubscriptionHeader vertical padding |
| `md` | 12 | ServerRow vertical padding, HStack spacing |
| `lg` | 16 | ServerRow horizontal padding, AutoCell internal padding, sheet margins |
| `xl` | 24 | inline empty card padding |
| `xxl` | 32 | inline empty card outer padding |
| `xxxl` | 48 | (зарезервирован — не используется в Phase 3) |

Все значения кратны 4 pt — соответствует Apple HIG 8-point grid.

**Exceptions:** none для Phase 3.

### 8.2 Corner radius — `DS.Radius` (no changes)

| Token | Value (pt) | Phase 3 usage |
|---|---|---|
| `small` | 8 | ServerRow внутренние пиктограммы (если потребуется) |
| `card` | 12 | ServerRow rounded corners секции (через `.clipShape` к first/last в Section) |
| `cardLarge` | 16 | AutoCell, inline empty card |
| `button` | 12 | confirmationDialog buttons (system-controlled) |
| `pill` | 999 (через `Capsule()`) | "не поддерживается" badge |
| `circle` | use `Circle()` shape | AutoCell leading icon container |

### 8.3 Color contract — 60/30/10 (Phase 2 baseline + Phase 3 additions)

| Role | iOS | macOS | Usage (Phase 3) |
|---|---|---|---|
| **Dominant (60%)** — surface | `Color(.systemGroupedBackground)` (sheet bg, отличается от MainScreen чтобы подчеркнуть modality) | `Color(NSColor.windowBackgroundColor)` | sheet container background |
| **Secondary (30%)** — cards | `Color(.secondarySystemBackground)` | `Color(NSColor.controlBackgroundColor)` | AutoCell, ServerRow group, inline empty card |
| **Tertiary fill** — pills | `Color(.tertiarySystemFill)` | similar | «не поддерживается» badge background, AutoCell leading icon container (when not selected) |
| **Accent (10%)** | `Color.accentColor` (system blue — Phase 11 финал палитра) | same | AutoCell leading icon (selected), AutoCell trailing checkmark (selected), ServerRow trailing checkmark, ConnectionButton `.connected` (Phase 2 inherited) |
| **Destructive** | `Color.red` | same | swipe action delete, unreachable text, destructive confirmation button, refresh failure alert |
| **Success / Latency-Excellent** | `Color.green` | same | latency badge 0–80 ms |
| **Warning / Latency-Good** | `Color(.systemYellow)` | same | latency badge 81–200 ms |
| **Caution / Latency-Poor** | `Color.orange` | same | latency badge 201–500 ms; partial fetch error indicator на SubscriptionHeader |

**Accent reserved for** (явный список — никаких «all interactive elements»):
- `AutoCell` leading icon foreground когда `isAutoSelected == true`
- `AutoCell` leading icon container fill когда `isAutoSelected == true` (с `.opacity(0.15)`)
- `AutoCell` trailing checkmark когда `isAutoSelected == true`
- `ServerRow` trailing checkmark когда `isSelected == true`
- `ServerLineView` chevron tint (`.tertiary` baseline, но в `.connected` state наследует от `.accentColor`)
- `ConnectionButton` fill когда `state == .connected` (Phase 2 inherited)
- Primary button в `EmptyStateCard` (Phase 2 inherited)
- NavigationBar tint, system Settings sheets, alert primary buttons (system-controlled)

Все остальные интерактивные элементы — system-default tint (secondary buttons `.bordered`, swipe-actions с явным `.tint(.red)`, Form rows).

### 8.4 Typography — `DS.Typography` (Phase 2 inherited + Phase 3 usage map)

| Role | Style | Weight | Design | Phase 3 usage |
|---|---|---|---|---|
| `display` | `.largeTitle` | `.medium` | `.monospaced` (timer) | (Phase 2 — ConnectionTimer, не используется в Phase 3 sheet) |
| `title` | `.title3` | `.bold` | `.rounded` | AutoCell title, inline empty card title |
| `headline` | `.headline` | `.semibold` | `.default` | (зарезервирован) |
| `body` | `.body` | `.regular` | `.default` | ServerRow title (имя сервера) |
| `callout` | `.callout` | `.regular` | `.rounded` | ServerLineView (Phase 2), inline error tooltips |
| `subheadline` | `.subheadline` | `.medium` | `.rounded` | AutoCell subtitle, latency badge, inline empty card subtitle |
| `caption` | `.caption` | `.regular` | `.default` | SubscriptionHeader title (`.textCase(.uppercase)`) |
| `caption2` (inline) | `.caption2` | `.regular` | `.default` | SubscriptionHeader trailing (last-fetched), unsupported pill |

Body line-height: системный (~1.4–1.5 у Dynamic Type). Не переопределяем (Apple platform consistency).

Latency-числа — `.monospacedDigit()` чтобы цифры не дрейфовали (Phase 2 ConnectionTimer pattern).

### 8.5 Section grouping radius

ServerRow внутри Section применяет corner radius **только** к первой и последней строке:

```swift
.clipShape(SectionRowShape(isFirst: isFirst, isLast: isLast, radius: DS.Radius.card))
```

Где `SectionRowShape` — custom Shape, рендерящий 12 pt corners на top если isFirst, на bottom если isLast, 0 pt в середине. Divider между строками — `Divider().padding(.leading, DS.Spacing.lg + 32)` (отступ под флаг).

---

## 9. Copywriting Contract

### 9.1 Primary CTA для Phase 3

| Контекст | Copy | Localization key |
|---|---|---|
| Primary CTA в sheet (default action) | «Авто (рекомендуется)» (AutoCell title) | `server.auto.title` |
| Server selection action | (нет explicit CTA-кнопки — tap по row = action) | — |
| Empty subscription state (inline) | «Импортируйте конфигурацию через «+» на главном экране.» | `serverList.empty.subtitle` |
| Pull-to-refresh hint | (system `.refreshable` — без custom label) | — |

### 9.2 Empty state

| Элемент | Copy | Localization key |
|---|---|---|
| Heading | «Нет серверов» | `serverList.empty.title` |
| Body | «Импортируйте конфигурацию через «+» на главном экране.» | `serverList.empty.subtitle` |

### 9.3 Error state

| Случай | Copy | Localization key |
|---|---|---|
| Полный refresh failure (все подписки) | Title: «Не удалось обновить подписки» / Body: «Проверьте подключение к интернету и попробуйте снова.» | `serverList.refresh.error.title`, `serverList.refresh.error.message` |
| Партиальный fetch failure (одна подписка) | inline tooltip на SubscriptionHeader: «Не удалось обновить: код %lld» | `serverList.subscription.fetchError` |
| Server unreachable | «недоступен» | `serverList.unreachable` |
| Unsupported protocol | «не поддерживается» | `serverList.unsupportedBadge` |

### 9.4 Destructive confirmations

| Действие | Confirmation copy | Localization keys |
|---|---|---|
| Delete subscription | «Удалить подписку «%@»? Будет удалено серверов: %lld.» / Buttons: «Удалить» (`.destructive`) + «Отмена» (`.cancel`) | `serverList.deleteSubscription.confirm.message`, `action.delete`, `action.cancel` |
| Delete server | inline destructive swipe action «Удалить» (без confirm) | `serverList.deleteServer` |

### 9.5 Full localization key set (Phase 3 additions)

Добавляются в `Localizable.xcstrings` + `L10n.swift`:

| Key | Russian | English |
|---|---|---|
| `server.auto.title` | Авто (рекомендуется) | Auto (recommended) |
| `server.auto.subtitle` | Выберет лучший по скорости | Picks the fastest server |
| `serverList.title` | Серверы | Servers |
| `serverList.manualSection` | ДОБАВЛЕНЫ ВРУЧНУЮ | ADDED MANUALLY |
| `serverList.unsupportedBadge` | не поддерживается | unsupported |
| `serverList.unreachable` | недоступен | unreachable |
| `serverList.deleteServer` | Удалить | Delete |
| `serverList.deleteSubscription` | Удалить | Delete |
| `serverList.deleteSubscription.confirm.message` | Удалить подписку «%@»? Будет удалено серверов: %lld. | Delete subscription "%@"? %lld server(s) will be removed. |
| `serverList.empty.title` | Нет серверов | No servers |
| `serverList.empty.subtitle` | Импортируйте конфигурацию через «+» на главном экране. | Import configuration via "+" on the main screen. |
| `serverList.refresh.error.title` | Не удалось обновить подписки | Failed to refresh subscriptions |
| `serverList.refresh.error.message` | Проверьте подключение к интернету и попробуйте снова. | Check your internet connection and try again. |
| `serverList.subscription.fetchError` | Не удалось обновить: код %lld | Refresh failed: code %lld |
| `serverList.lastFetched.justNow` | только что | just now |
| `serverList.lastFetched.minutes` | %lld мин назад | %lld min ago |
| `serverList.lastFetched.hours` | %lld ч назад | %lld h ago |
| `serverList.lastFetched.days` | %lld дн назад | %lld d ago |
| `action.delete` | Удалить | Delete |
| `import.subscription.added.title` | Подписка добавлена | Subscription added |
| `import.subscription.added.message` | Добавлено: %lld серверов из «%@». Будут включены в следующих версиях: %lld. | Imported: %lld server(s) from "%@". Will be enabled in future versions: %lld. |
| `import.subscription.updated.title` | Подписка обновлена | Subscription updated |
| `import.subscription.updated.message` | Добавлено новых: %lld. Всего серверов в «%@»: %lld. | New: %lld. Total in "%@": %lld. |
| `serverList.manualSubscriptionName.fallback` | Подписка #%lld | Subscription #%lld |

### 9.6 Phase 2 ключи — судьба в Phase 3

| Phase 2 key | Phase 3 fate |
|---|---|
| `server.label` («Сервер:») | сохраняется |
| `server.auto` («Авто») | сохраняется как короткая форма для ServerLineView; AutoCell использует `server.auto.title` |
| `import.success.title` («Импорт завершён») | сохраняется для single-URI; subscription-import получает новые keys |
| `import.success.message` | сохраняется для single-URI |
| остальные | без изменений |

---

## 10. Accessibility

### 10.1 Все интерактивные элементы

| Component | accessibilityLabel | accessibilityHint | accessibilityValue |
|---|---|---|---|
| ServerLineView (Phase 3 mode) | «Текущий сервер» | «Дважды нажмите чтобы открыть список серверов» | имя сервера или «Авто» |
| ServerListSheet (root) | «Список серверов» | — | — |
| AutoCell | «Авто — выбор лучшего сервера» | если selected: «выбрано»; если нет: «Дважды нажмите чтобы включить автовыбор» | «Выбрано» / «Не выбрано» |
| AutoCell trailing checkmark | hidden (`accessibilityHidden(true)`) | — | — (state уже в parent value) |
| SubscriptionHeader | имя подписки | «Свайп влево чтобы удалить подписку» (если не Manual section) | — |
| SubscriptionHeader last-fetched | hidden (`accessibilityHidden(true)`) | — | — |
| ServerRow (supported, reachable) | «%@ — %@» (countryName + serverName) | если selected: «выбрано»; если нет: «Дважды нажмите чтобы подключиться» | latency в человеческой форме: «%lld миллисекунд» |
| ServerRow (unsupported) | «%@ — не поддерживается» | — | (без latency) |
| ServerRow (unreachable) | «%@ — недоступен» | «Сервер не отвечает» | — |
| ServerRow (pinging) | «%@» | «Измеряется скорость» | — |
| ServerRow trailing checkmark | hidden | — | — |
| LatencyBadge | hidden (`accessibilityHidden(true)`) | — | — (значение уже в ServerRow value) |
| Pull-to-refresh | системный VoiceOver hint | — | — |
| Swipe delete (server) | «Удалить сервер %@» | — | — |
| Swipe delete (subscription) | «Удалить подписку %@» | «Подтверждение потребуется» | — |

### 10.2 VoiceOver order в ServerListSheet (loaded state)

```
1. Drag indicator (hidden)
2. AutoCell (group element с state)
3. SubscriptionHeader [А]
4. ServerRow ... ServerRow [А servers]
5. SubscriptionHeader [Б]
6. ServerRow ... ServerRow [Б servers]
7. SubscriptionHeader [Manual]
8. ServerRow ... ServerRow [orphan servers]
```

Внутри ServerRow — `.accessibilityElement(children: .combine)` — флаг + имя + latency читаются как одна группа.

### 10.3 Dynamic Type

Все шрифты — через системные `Font.TextStyle` (см. §8.4). ServerListSheet корректно рендерится вплоть до `AX5`:
- ServerRow становится многострочным (флаг + name на одной линии, latency badge переносится под имя)
- AutoCell вертикально растёт
- min row height masculine'ится через `.frame(minHeight: 56)` без max-height — sliders ok
- SubscriptionHeader caption переносится на 2 строки

ScrollView корректно прокручивается при больших размерах текста.

### 10.4 Reduce Motion

`@Environment(\.accessibilityReduceMotion)`:
- если `true` → `.symbolEffect(.bounce)` на AutoCell checkmark — disabled (заменяется на mгновенную смену иконки)
- pull-to-refresh spinner — system handles
- progressive UI updates — без анимации (мгновенная замена ProgressView → LatencyBadge)

### 10.5 VoiceOver announcement on selection

При выборе сервера в sheet:
- iOS: `UIAccessibility.post(notification: .announcement, argument: L10n.serverList.selectedAnnouncement.format(name))`
- Текст: «Выбран сервер %@» / `«Selected server %@»` (key: `serverList.selectedAnnouncement`)

При выборе Auto:
- Текст: «Включён автовыбор» / `«Auto selection enabled»` (key: `serverList.autoSelectedAnnouncement`)

---

## 11. Platform Differences

| Поведение | iOS | macOS |
|---|---|---|
| ServerListSheet презентация | `.sheet` с `.presentationDetents([.large])` | `.sheet` 480×720, resizable=true, min 400×600 |
| Drag indicator | `.presentationDragIndicator(.visible)` | n/a (window has title bar; добавить `✕` button в toolbar) |
| Swipe-to-delete | `.swipeActions` (нативный) | `.swipeActions` доступен в SwiftUI macOS, но менее distinct — альтернатива: context menu `.contextMenu { Button(role: .destructive) { ... } }` |
| Confirmation dialog | `.confirmationDialog` (action sheet) | `.alert` (popover-style) |
| Haptic on selection | `UIImpactFeedbackGenerator(style: .light)` | no-op |
| Pull-to-refresh | `.refreshable` (нативный gesture) | `.refreshable` доступен; альтернатива — toolbar button `arrow.clockwise` для discoverability (опционально) |
| Sheet dismiss | swipe down ИЛИ tap по фону | `✕` button в toolbar ИЛИ Cmd+W |
| Flag rendering | emoji native | emoji native (Color Emoji font) — но проверить рендеринг 24 pt size |
| VoiceOver gestures | swipe-up/down для actions | rotor для swipe-actions |
| Country flag fallback (no flag font) | `🌐` | `🌐` |

---

## 12. Out of Scope (Phase 3)

Явный список того, что НЕ реализуется в Phase 3:

- ❌ **Поиск / фильтр в server list** (UX-04 wiki) — Phase 11 polish.
- ❌ **Signal-strength dot в ServerLineView** (wiki target) — Phase 11.
- ❌ **Редактирование имени подписки** — Phase 11 (deferred CONTEXT).
- ❌ **BGAppRefreshTask** (фоновое обновление подписок по расписанию) — Phase 6+.
- ❌ **Smart-метрика auto-select с историческими данными** — v1.1 (ROADMAP SMART-01).
- ❌ **Управление подписками в отдельном Settings разделе** — не нужно (всё через «+» на главном).
- ❌ **Undo toast после swipe-delete** — Phase 11.
- ❌ **Multi-select для batch delete** — не планируется (single-select pattern достаточно).
- ❌ **Сортировка серверов** (alphabetical / by-latency toggle) — Phase 11.
- ❌ **GeoIP lookup по host для country-flag fallback** — Phase 11 (offline DB).
- ❌ **Server detail screen** (tap-into про статистику) — не планируется (нетехнический пользователь не нужен; Расширенные в Phase 10).
- ❌ **Pull-to-refresh кастомный label** — system default «Pull to refresh» / «Обновление...» SwiftUI рендерит сам.
- ❌ **Subscription quota indicator** (если subscription header возвращает `Subscription-Userinfo` с trafficUsed/total) — Phase 11 или Phase 8 (с rules engine).
- ❌ **Auto-import при tap на subscription URL** — Deep Links (Phase 9).
- ❌ **Manual refresh per-subscription** — общий pull-to-refresh достаточно на v0.3.

---

## 13. Phase 11 Forward-Compatibility Notes

Все компоненты v0.3 — **placeholder design** в части visual polish. Phase 11 (UX-08, UX-09, Figma финал) заменит:

| Компонент / token | Что изменится в Phase 11 |
|---|---|
| AutoCell иконка `bolt.fill` | Кастомная BBTB иллюстрация (вероятно жук с молнией) |
| ServerRow флаг emoji | Кастомные SVG flags (consistent style, no platform variance) или сохранение emoji с supplementary country code badge |
| LatencyBadge цвет | Возможен переход на дополнительный signal-strength dot слева от ms (как UX-04 требует) |
| ServerLineView | Возврат chevron + signal-strength dot |
| SubscriptionHeader | Возможен переход на full-row pill с avatar (или иконкой провайдера если parsed из URL) |
| AutoCell subtitle copy | Финальный copywriting под BBTB-тон |
| Sheet drag indicator | Кастомный visual |
| Swipe action icons | SF Symbol → кастомные icons |
| Empty state inline card | Брендированная иллюстрация (как EmptyStateCard на MainScreen) |
| Sticky header pattern | Возможен переход на full-sticky SubscriptionHeader при scroll (а не top-pinned-once AutoCell) |
| Search bar | UX-04 — добавляется (Phase 11) |
| Edit subscription name flow | Long-press / context menu → inline rename (Phase 11) |
| Undo toast | Phase 11 — после destructive action показывается toast «Отменить» 4 sec |
| GeoIP DB | Phase 11 — offline lookup для country flag fallback |

DesignSystem package (`DS.Spacing`, `DS.Radius`, `DS.Typography`) — token names остаются, значения переопределяются.

---

## 14. Security & UX safety notes (Phase 3 specific)

Phase 3 не вводит новых security threats (нет нового parsing/network surface — subscription URL fetch уже covered Phase 2 SEC review). Но UI-SPEC фиксирует следующие safety contracts:

| Сценарий | Контракт |
|---|---|
| Удаление активного сервера во время connect | reconnect через PoolBuilder с обновлённым массивом (если есть resilient outbounds); если pool пуст → disconnect и `.empty` MainScreen state |
| Удаление подписки во время refresh | refresh job отменяется через `Task.cancellation`; partial state не сохраняется |
| Pull-to-refresh во время connect | refresh выполняется без disconnect (не трогает sing-box runtime); если auto-select pre-connect в процессе — refresh ждёт его завершения через actor serialisation |
| Malicious subscription URL (redirect chain, body-size) | **carry-forward W-02-09 → Phase 7** (DPI-08 cert pinning). Phase 3 наследует Phase 2 fetcher без cap'ов — accepted risk на v0.3. |
| Subscription URL с private network IP (`10.x`, `192.168.x`, `localhost`) | Phase 2 SEC-PARSE-01 валидация остаётся в силе — paste такого URL `→` error «Адрес недоступен». Auto-select не меняет surface. |
| TCP probe к serverConfig host:port | работает **только** при `isSupported = true`. Probe сам по себе не leakит данные — TCP SYN без TLS, host уже известен (из конфига пользователя). |
| Pinging серверов без активного туннеля | пробы идут **поверх системного интернета** (не через VPN). Это intended — auto-select должен работать когда tunnel down. Документировано в `wiki/security-gaps.md` (TODO в Phase 3 implementation log). |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|---|---|---|
| (none) | n/a | **not applicable** — SwiftUI native, нет shadcn / web component registries |

---

## Checker Sign-Off

(Адаптировано к SwiftUI native стеку — не shadcn.)

- [ ] Dimension 1 Copywriting: PASS — все user-facing строки определены в §9 (включая 22 новых L10n key)
- [ ] Dimension 2 Visuals: PASS — layout композиция ServerListSheet + AutoCell + ServerRow + SubscriptionHeader в §2; pull-to-refresh / ping в §3
- [ ] Dimension 3 Color: PASS — 60/30/10 распределение + 6 latency-tier цветов + accent reserved-for list в §8.3
- [ ] Dimension 4 Typography: PASS — 8 ролей через системные TextStyle в §8.4
- [ ] Dimension 5 Spacing: PASS — 8-point grid (с 4 pt для tight) в §8.1, все pt значения кратны 4
- [ ] Dimension 6 Registry Safety: **not applicable** (SwiftUI native + SF Symbols, нет third-party registries)
- [ ] Dimension 7 Accessibility: PASS — labels/hints/values + VoiceOver order + Dynamic Type AX5 + Reduce Motion + announcements в §10
- [ ] Dimension 8 Platform parity: PASS — iOS vs macOS отличия в §11 (sheet detents, swipe vs context menu, haptic, confirm dialog vs alert)

**Approval:** pending — ждёт `gsd-ui-checker`.

---

*Phase: 3-server-management*
*UI-SPEC drafted: 2026-05-12*
*Source decisions: CONTEXT.md D-01..D-14 (14 locked decisions)*
*Pre-populated from: CONTEXT.md (14 decisions), Phase 2 carry-forward (DesignSystem tokens, MainScreenViewModel skeleton, ConfigImporter pipeline, ServerLineView component), wiki/ux-specification.md (UX-04 target — forward-compat notes §13)*
*Downstream consumers: `gsd-planner` (W1-W4 task breakdown — Subscription model + migration, ServerListFeature module, ServerProbeService, ConfigImporter rewire), `gsd-executor` (visual source of truth), `gsd-ui-checker` (6+2 dimension validation), `gsd-ui-auditor` (retrospective compliance check)*
