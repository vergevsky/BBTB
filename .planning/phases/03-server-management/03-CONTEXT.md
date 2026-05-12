# Phase 3: Server management — Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Реализовать управление серверами в v0.3:

1. **Экран-список серверов** — sheet, открывающийся при тапе на server-line главного экрана. Показывает флаг страны, имя, latency, индикатор недоступности, плашку «не поддерживается» для stub-протоколов. Ячейка «Авто» закреплена в топе.
2. **Auto-select по score** — перед каждым connect клиент параллельно пингует все supported-серверы и выбирает с наименьшим score.
3. **Multi-subscription** — новая @Model `Subscription` в SwiftData, несколько источников, секции в списке. Добавление — через существующую кнопку «+», удаление — swipe по заголовку секции.
4. **Pull-to-refresh** — перезагружает подписки из URL + перепинговывает все серверы. При запуске приложения — тоже автоматически.

### Не в скоупе Phase 3

- BGAppRefreshTask (фоновое обновление по расписанию) — Phase 6 или позже.
- Поиск/фильтр в server list — Phase 11 (UX polish).
- Управление подписками в Settings — не нужен отдельный раздел, всё через «+».
- Редактирование имени подписки — Phase 11.

</domain>

<decisions>
## Implementation Decisions

### Измерение latency и auto-select

- **D-01:** Latency измеряется TCP-connect пробами (`NWConnection` к `host:port`) — независимо от sing-box, работает без активного туннеля.
- **D-02:** Пробы запускаются параллельно для всех серверов через Swift Concurrency `TaskGroup`. UI обновляется по мере поступления результатов (прогрессивно).
- **D-03:** Алгоритм auto-select: `score = latencyMs × (1 + lossRate)`. Для каждого сервера — 3 **последовательных** TCP-пробы с timeout 500 ms. `lossRate = failedProbes / 3`. Сервер с минимальным score побеждает. Серверы, у которых 3/3 timeout — недоступны, пропускаются.
- **D-04:** Auto-select запускается **перед каждым connect** (не сохраняется до pull-to-refresh). Пользователь нажал «Подключиться» → клиент пингует все supported-серверы → выбирает лучший → подключается. Добавляет ~1.5 сек.

### Data model подписок

- **D-05:** Новая `@Model Subscription { id: UUID, url: String, name: String, lastFetched: Date? }` в SwiftData. `ServerConfig` получает поле `subscriptionID: UUID?` как FK (заменяет `subscriptionURL: String?`). Требует SwiftData lightweight migration. Серверы без подписки (одиночный paste-импорт) имеют `subscriptionID = nil` и группируются в секцию «Добавлены вручную».
- **D-06:** Добавление новой подписки — через существующую кнопку «+» на главном экране (TopBar). Если импортируется subscription URL → создаётся `Subscription` запись, серверы привязываются через `subscriptionID`. Отдельного раздела в Settings не нужно.
- **D-07:** Удаление подписки — swipe по заголовку секции в server list → «Удалить». Cascade delete: удаляется `Subscription` + все её `ServerConfig`. Удаление отдельного сервера — swipe по строке.

### Server list UI

- **D-08:** Server list открывается как **sheet** (`.sheet` modifier) при тапе на server-line на главном экране. Высота — `.presentationDetents([.large])`. Закрывается свайпом вниз или выбором сервера.
- **D-09:** Выбор сервера при активном туннеле — **авто-reconnect** без алерта: sheet закрывается → disconnect → ping → connect с новым сервером. Паттерн аналогичен reconnect-banner из Phase 2.
- **D-10:** Кнопка «Авто» — отдельная ячейка в топе списка (до секций подписок). Если выбрана — чекбокс/галочка. При тапе — включает режим «перед connect выбирать лучший по score». Sheet закрывается. Если выбран конкретный сервер — «Авто» снята, используется выбранный.
- **D-11:** Строка сервера содержит: флаг страны (emoji) + имя (`ServerConfig.name`) + latency badge (`lastLatencyMs` ms). Если сервер недоступен (3/3 timeout) — строка серая / latency «недоступен». Если `isSupported = false` — плашка «не поддерживается», строка полупрозрачная. Название протокола — не показывается (скрыто для нетехнических пользователей).

### Background refresh

- **D-12:** Подписки обновляются в двух случаях: (1) при запуске приложения (app foreground), (2) pull-to-refresh в server list.
- **D-13:** Pull-to-refresh делает **два шага последовательно**: сначала fetch всех subscription URL → merge новых серверов, затем параллельный ping всех серверов. Один жест — полностью актуальный список.
- **D-14:** Merge при re-fetch подписки: новые URI добавляются, исчезнувшие из ответа серверы помечаются (не удаляются автоматически — пользователь сам удаляет через swipe). `lastFetched` у `Subscription` обновляется.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Планирование и требования
- `.planning/ROADMAP.md` — Phase 3 scope, success criteria, requirements mapping
- `.planning/REQUIREMENTS.md` — SRV-01, SRV-02, SRV-03, UX-04 детали

### Существующий data model
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` — @Model ServerConfig (Phase 2 schema); Phase 3 добавляет `subscriptionID: UUID?` вместо `subscriptionURL: String?`, оставляет `lastLatencyMs: Int?`
- `BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift` — SwiftData container setup и migration strategy

### Существующий import flow
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — точка входа для «+», Phase 3 расширяет для создания Subscription @Model
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — сборка sing-box config из ServerConfig массива; Phase 3 filtered по `isSupported = true`

### Архитектурные решения из Phase 2
- `.planning/phases/02-trojan-import-flow/02-CONTEXT.md` — D-01 (один NETunnelProviderManager), D-06 (массив ServerConfig), D-07 (replace-pool при re-import одного URL → в Phase 3 заменяется merge-стратегией)

### UX Reference
- `wiki/ux-specification.md` — целевой дизайн экранов; server-list = «кнопка Авто + поиск + флаги + latency + секции» (UX-04)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ServerConfig.lastLatencyMs: Int?` — поле уже есть в Phase 2 schema; Phase 3 заполняет его после TCP-проб
- `PoolBuilder` — уже фильтрует по `isSupported`; Phase 3 использует его для сборки pool после выбора сервера
- `reconnect-banner` паттерн из Phase 2 (`ReconnectBanner.swift`) — аналогичная логика для авто-reconnect при смене сервера
- `TopBar` с кнопкой «+» — точка входа для импорта; Phase 3 расширяет обработчик subscription URL для создания Subscription @Model

### Established Patterns
- SwiftData lightweight migration — уже применялась в Phase 2 (добавление `isSupported`, `subscriptionURL`, `outboundJSON`)
- `TaskGroup` для параллельных async задач — стандартный паттерн в проекте (Swift Concurrency)
- `@Model` с `@Attribute(.unique)` — уже в `ServerConfig.id`

### Integration Points
- `MainScreenViewModel` — добавить `selectedServerID: UUID?` (nil = Авто) и `pingAllServers()` метод
- `PacketTunnelKit/BaseSingBoxTunnel` — получает итоговый `configJSON` от `PoolBuilder` после выбора сервера auto-select'ом
- `SwiftDataContainer` — регистрирует новую модель `Subscription` в schema

</code_context>

<specifics>
## Specific Ideas

- Паттерн Hiddify для server list sheet — быстрый выбор без навигации «назад»
- TCP-пробы через `NWConnection` (Network.framework) — уже доступен в проекте, не требует root/entitlements
- Прогрессивное обновление latency в UI: каждый сервер обновляется как только его пробы завершились, не ждёт всех

</specifics>

<deferred>
## Deferred Ideas

- **BGAppRefreshTask** (фоновое обновление подписок по расписанию) — Phase 6 или позже
- **Поиск / фильтр в server list** — Phase 11 (UX polish, UX-04 упоминает поиск)
- **Редактирование имени подписки** — Phase 11
- **Smart-метрика auto-select с историческими данными** — ROADMAP отложил на v1.1

</deferred>

---

*Phase: 03-server-management*
*Context gathered: 2026-05-12*
