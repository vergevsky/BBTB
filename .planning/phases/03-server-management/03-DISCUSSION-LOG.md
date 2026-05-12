# Phase 3: Server management — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 03-server-management
**Areas discussed:** Измерение latency, Data model подписок, Server list UI, Background refresh

---

## Измерение latency

| Option | Description | Selected |
|--------|-------------|----------|
| TCP connect пробы | Клиент сам делает TCP-соединение к host:port и замеряет время. Независимо от sing-box, работает без активного туннеля. | ✓ |
| sing-box urltest метрики | sing-box уже гоняет HTTP-пробы через каждый outbound. libbox API позволяет читать эти значения. Точнее (end-to-end), но работает только пока туннель активен. | |
| Комбо | TCP-пробы — для UI, sing-box metrics — для smart-автовыбора пока туннель активен. Больше кода. | |

**User's choice:** TCP connect пробы

---

| Option | Description | Selected |
|--------|-------------|----------|
| Параллельно | async let / TaskGroup — все серверы пингуются одновременно, UI обновляется по мере результатов. | ✓ |
| Последовательно | Один сервер — ждём результат — следующий. Проще отладка, но на практике слишком медленно при 5+ серверах. | |

**User's choice:** Параллельно

---

| Option | Description | Selected |
|--------|-------------|----------|
| score = latencyMs × (1 + lossRate) | 3 последовательных TCP-пробы на сервер (timeout 500ms). lossRate = failed/3. | ✓ |
| Только latency без lossRate | 1 проба на сервер, берём среднее или min. Проще, но нет информации о потерях. | |

**User's choice:** score = latencyMs × (1 + lossRate)
**Notes:** Пользователь уточнил — важна скорость алгоритма, не простота. Обсудили, что 3 последовательных пробы с timeout 500ms при параллельном запуске по всем серверам дают ~1.5 сек максимум. ТСПУ-риск от TCP-проб минимальный (TCP SYN к порту 443 неотличим от HTTPS). Недоступные серверы (3/3 timeout) — пропускаются auto-select'ом.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Перед каждым connect | Клиент пингует все серверы перед каждым подключением. Всегда актуально. | ✓ |
| Фиксируется до следующего pull-to-refresh | Auto-select выбирает сервер один раз, запоминает. Connect — мгновенный. Может выбрать устаревший сервер. | |

**User's choice:** Перед каждым connect

---

## Data model подписок

| Option | Description | Selected |
|--------|-------------|----------|
| Новая @Model Subscription | Subscription { id, url, name, lastFetched }. ServerConfig.subscriptionID: UUID? как FK. Чистая нормализация, легко редактировать/удалять подписки. Требует lightweight migration. | ✓ |
| Плоский ServerConfig | Секции в UI через группировку по subscriptionURL String. Меньше кода, но нельзя переименовать подписку, не зная её URL. | |

**User's choice:** Новая @Model Subscription

---

| Option | Description | Selected |
|--------|-------------|----------|
| Settings → Подписки | Отдельный раздел в Settings, список URL + кнопка «+». | |
| Кнопка «+» в server list | Прямо из списка серверов. Меньше навигации. | |
| Существующий «+» на главном экране | Та же кнопка «+» (TopBar) что используется для импорта URI. | ✓ |

**User's choice:** Существующий «+» на главном экране
**Notes:** Пользователь отметил — зачем усложнять, кнопка «+» уже есть. Subscription URL при импорте просто создаёт Subscription запись.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Swipe по заголовку секции | В server list — свайп по заголовку секции → «Удалить». Cascade delete. | ✓ |
| Context menu по долгому нажатию | Long press на заголовке → меню «Переименовать / Обновить / Удалить». Больше опций. | |

**User's choice:** Swipe по заголовку секции

---

## Server list UI

| Option | Description | Selected |
|--------|-------------|----------|
| Sheet | Тап на server-line → выезжает снизу поверх главного экрана. Свайп вниз закрывает. Паттерн Hiddify. | ✓ |
| Push navigation | Отдельный экран, переход влево. Кнопка «Назад» в nav bar. | |

**User's choice:** Sheet
**Notes:** Пользователь сначала выбрал Push, затем вернулся и переключился на Sheet.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Авто-reconnect | Тап на сервер → sheet закрылся → тихо disconnect + ping + connect. Без алерта. | ✓ |
| Алерт подтверждения | Alert «Выбор нового сервера отключит туннель. Продолжить?» | |

**User's choice:** Авто-reconnect

---

| Option | Description | Selected |
|--------|-------------|----------|
| Отдельная ячейка в топе | Всегда первая строка, выделяется. Тап — включает режим auto-select. Если выбрана — чекбокс. | ✓ |
| Часть строки сервера | Строка «Авто (выберет лучший)» внутри списка наравне с обычными серверами. | |

**User's choice:** Отдельная ячейка в топе

---

| Option | Description | Selected |
|--------|-------------|----------|
| Имя сервера | Текст из ServerConfig.name | ✓ |
| Протокол | VLESS+Reality, Trojan и т.д. — секретный бейдж или иконка | |
| Индикатор недоступности | Серый цвет / зачёркнутая строка если 3/3 timeout | ✓ |
| Не поддерживается (stub) | Плашка «не поддерживается» если isSupported=false | ✓ |

**User's choice:** Имя + Индикатор недоступности + Не поддерживается. Протокол скрыт.

---

## Background refresh

| Option | Description | Selected |
|--------|-------------|----------|
| При запуске + pull-to-refresh | При открытии приложения и по pull-to-refresh в server list. | ✓ |
| Только pull-to-refresh | Только по явному действию. Минимально. | |
| BGAppRefreshTask (фон) | iOS будит приложение раз в час/день для обновления. Больше кода, entitlement, негарантированное расписание. | |

**User's choice:** При запуске + pull-to-refresh

---

| Option | Description | Selected |
|--------|-------------|----------|
| И latency, и подписки | Pull → fetch всех subscription URL (merge) → ping всех серверов. | ✓ |
| Только latency | Pull перепинговывает без обновления списка серверов. | |

**User's choice:** И latency, и подписки

---

## Claude's Discretion

- Merge-стратегия при re-fetch подписки: новые URI добавляются, исчезнувшие помечаются (не удаляются автоматически)
- Серверы без подписки (одиночный paste) группируются в секцию «Добавлены вручную»
- `.presentationDetents([.large])` для sheet

## Deferred Ideas

- **BGAppRefreshTask** — фоновое обновление по расписанию, Phase 6+
- **Поиск / фильтр в server list** — Phase 11 (UX polish)
- **Редактирование имени подписки** — Phase 11
- **Smart-метрика с историческими данными** — v1.1
