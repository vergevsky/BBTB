# Phase 6: Network Resilience — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 6-network-resilience
**Areas discussed:** Bootstrap DNS, Tunnel DNS, Custom DNS, AdBlock DNS, IPv6 mode, Auto-reconnect, Failover

---

## Bootstrap DNS (NET-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Только 1.1.1.1 | Всегда Cloudflare | |
| IP сервера напрямую | DNS не нужен до открытия туннеля | |
| Совместить: IP + AdGuard + 1.1.1.1 | Трёхступенчатый bootstrap | ✓ |

**User's choice:** Совместить второй и первый — IP сервера напрямую + AdGuard (94.140.14.14) + 1.1.1.1 резерв.
**Notes:** Пользователь указал, что VPN используется из России. Перефрейминг: Яндекс (`77.88.8.8`) сейчас захардкожен в `PoolBuilder.dnsBlock()` — это критическая проблема (ТСПУ может видеть запросы до туннеля). AdGuard — российская компания, но редко блокируется, не является государственной и ориентирована на приватность. Использование IP сервера напрямую = нулевой DNS-запрос до туннеля.

---

## Tunnel DNS (NET-01b)

| Option | Description | Selected |
|--------|-------------|----------|
| Cloudflare DoH (1.1.1.1) | Быстрый, приватный, международный | ✓ |
| Google DNS (8.8.8.8) | Широко известный, но Google = трекинг | |
| AdGuard DNS (94.140.14.14) | Приватный + блокирует рекламу по умолчанию | |

**User's choice:** Cloudflare по умолчанию.
**Notes:** Внутри туннеля DNS-запросы уже зашифрованы, ТСПУ их не видит. Cloudflare — де-факто стандарт для приватности.

---

## AdBlock DNS toggle (NET-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Advanced Settings | Рядом с DNS настройками, не загрязняет главный экран | ✓ |
| Главный экран | Быстрый доступ, но засоряет основной интерфейс | |
| Не реализовывать в Phase 6 | Отложить | |

**User's choice:** Настройки → Дополнительно (Advanced Settings).
**Notes:** AdBlock через DNS = переключение tunnel DNS с Cloudflare на AdGuard (который блокирует рекламные домены по умолчанию). Работает для всего трафика через VPN.

---

## Custom DNS (NET-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Да, текстовое поле | IP-адрес пользовательского DNS в Advanced Settings | ✓ |
| Нет, только Cloudflare | Единственный вариант | |

**User's choice:** Да, текстовое поле в Advanced Settings.
**Notes:** Сценарии: корпоративный DNS, NextDNS с персональными списками. Если заполнено — имеет наивысший приоритет над AdBlock toggle.

---

## IPv6 mode (NET-05..07)

| Option | Description | Selected |
|--------|-------------|----------|
| Умная проверка при подключении | Проба ~2-3с, если сервер не поддерживает — блок | |
| Всегда блокировать IPv6 | Просто и надёжно, редко нужен в России | ✓ |
| Всегда пускать через туннель | Работает где есть IPv6, зависает где нет | |

**User's choice:** Всегда блокировать IPv6.
**Notes:** Пользователь первоначально хотел умную проверку («если сервер не поддерживает — блокировать»). После разъяснения, что умная проверка усложняет Phase 6 и IPv6-only сайты в России практически не встречаются — выбрал простой вариант. Adaptive detection отложена на Phase 7+. Важно: блокировка реализуется через включение IPv6 в NEIPv6Settings с blackhole-маршрутом, а не через его отсутствие (иначе iOS пустит IPv6 мимо туннеля = утечка).

---

## Auto-reconnect (NET-08..10)

| Option | Description | Selected |
|--------|-------------|----------|
| Авто-переподключаться (до 3 попыток) | NWPathMonitor + retry state machine | ✓ |
| Только уведомление | Показать баннер, ждать пользователя | |
| Ничего | VPN тихо отключается | |

**User's choice:** Авто-переподключаться автоматически.
**Notes:** Триггеры: Wi-Fi↔LTE, sleep/wake. До 3 попыток, экспоненциальная задержка (2с→4с→8с). Баннер «Переподключение...» во время попыток. При провале всех 3 — уведомление.

---

## Failover (NET-11)

| Option | Description | Selected |
|--------|-------------|----------|
| Автоматический failover | После 3 провалов — следующий сервер (round-robin) | ✓ |
| Только уведомление | «Сервер недоступен», пользователь выбирает сам | |
| Отложить на следующую фазу | Реализовать только реконнект в Phase 6 | |

**User's choice:** Да, автоматический failover.
**Notes:** Срабатывает после 3 неудачных попыток реконнекта к текущему серверу. Round-robin по списку пользователя. Если серверов < 2 — только уведомление. Failover-цикл сбрасывается при ручном отключении или успешной сессии > 30с.

---

## Claude's Discretion

- Конкретные поля `NEIPv6Settings` для blackhole-маршрута
- Параметры `NWPathMonitor` (throttle callback)
- Структура `DNSConfig` struct
- Тесты retry state machine
- Как sing-box сигнализирует о разрыве (libbox callback или мониторинг)

## Deferred Ideas

- Per-server DNS override → Phase 11
- Adaptive IPv6 detection (runtime probe) → Phase 7+
- Captive portal detection → Phase 7
- Обработка заблокированного bootstrap DNS → Phase 7
