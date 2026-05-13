# Phase 6c: On-demand Reconnect Migration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-13
**Phase:** 06c-on-demand-migration
**Areas discussed:** Apple-механизм конфигурации, Mid-session failover, User toggle размещение, macOS wake fallback

---

## Apple-механизм конфигурации

| Option | Description | Selected |
|--------|-------------|----------|
| `NEOnDemandRuleConnect()` | Простое правило «подключайся всегда когда есть интернет». Минимум кода. | |
| Гранулярные rules (Wi-Fi/Cellular separate) | Отдельные правила для разных типов интерфейсов. Среднее по сложности. | |
| **`NEEvaluateConnectionRule`** с массивом правил | Мощный движок с конкретными условиями. На старте — одно базовое правило, но архитектура готова для Phase 8 Rules Engine. | ✓ |

**User's choice:** EvaluateConnection с самого начала.
**Notes:** Выбор обоснован правилом «приоритет масштабируемости» — Phase 8 Rules Engine добавляет правила в существующий массив без изменения API. Стартовое правило идентично простому Connect, но архитектурный hook уже на месте.

---

## Mid-session server failover

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Accept loss — user manual reconnect | Без mid-session failover. Пользователь видит обрыв и нажимает Connect сам, тогда initial-connect failover работает. | |
| **(b) Watchdog observer** | Узко-целевой наблюдатель: реагирует только на «туннель упал после стабильной сессии», запускает swap manager config + retry. | ✓ |
| (c) Extension-level rotation | Глубокое решение — failure detection внутри extension. Самое надёжное, но сложно. | |

**User's choice:** Watchdog observer (вариант b).
**Notes:** Сохраняет Wave 6 ценность (`SwiftDataFailoverProvider`). Watchdog отличается от старого NEVPNStatusDidChange observer'а: реагирует ТОЛЬКО на stable-session drops (>=30s connected), читает status без XPC. Extension-level rotation отложен в Phase 7+.

---

## User toggle размещение

| Option | Description | Selected |
|--------|-------------|----------|
| **Сейчас, в Phase 6c** | Добавить переключатель «Автоматическое переподключение» в Settings → новый раздел «Подключение». Default ON. | ✓ |
| Отложить до Phase 10 | Phase 10 (Advanced settings) добавляет полноценную страницу с этим toggle среди других. | |

**User's choice:** Сейчас, в Phase 6c, default ON.
**Notes:** Auto-reconnect — поведенческое решение пользователя, не продвинутая настройка. Должно быть видимо с первого дня. Архитектурно: добавление сейчас экономит миграцию данных в Phase 10. Раздел «Подключение» создаётся с одним переключателем, Phase 10 добавит остальные connection-settings туда же.

---

## macOS wake fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Чисто on-demand (как iOS) | Полагаемся только на Apple-механизм. Меньше кода. На macOS Apple-форумы пишут про glitches с wake. | |
| **Гибрид: on-demand + NSWorkspace.didWake observer** | Основной механизм on-demand, плюс backup observer nudge'ает manager при wake. WireGuard macOS делает именно так. | ✓ |

**User's choice:** Гибрид (вариант 2).
**Notes:** WireGuard macOS — эталонная реализация — сохраняет wake observer не зря. На iOS observer отключён через `#if os(macOS)`. Observer делает одно cheap действие — idempotent startVPNTunnel(). Никаких XPC trips или recovery state.

---

## Claude's Discretion

- Точная структура `OnDemandRulesBuilder.swift` API — определяется planner'ом.
- Расположение watchdog логики (внутри TunnelController vs отдельный actor/struct) — определяется planner'ом.
- Migration строй (one big PR vs пошагово) — рекомендуется по-фазно, конкретика на planning.
- Решение о сохранении `userIntendedConnected` / `connectInProgress` флагов — зависит от структуры watchdog.

## Deferred Ideas

- **Per-SSID rules** («Подключаться только в незнакомых Wi-Fi») — Phase 8 Rules Engine.
- **Per-domain trusted networks** («Не включать VPN дома») — Phase 8 Rules Engine.
- **Per-app VPN routing** (только Telegram через тоннель) — Phase 8 Split tunneling.
- **Extension-level server rotation** (вариант c mid-session failover) — Phase 7+.
- **«Always-on VPN»** как первоклассный UX-выбор (Mullvad-style) — Phase 10 Advanced settings.
