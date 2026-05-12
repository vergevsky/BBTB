# Phase 6: Network Resilience — Context

**Date:** 2026-05-12
**Phase:** 6-network-resilience
**Goal:** DNS-стратегия (DoH + bootstrap), блокировка IPv6, авто-реконнект, failover. Версия v0.6.
**Requirements:** NET-01..11
**Status:** discussion-complete — ready for planning

---

## Decision Map

### D-01: Bootstrap DNS strategy (NET-01)

**Decision:** Трёхступенчатый bootstrap (DNS до поднятия туннеля):
1. IP-адрес сервера из `ServerConfig.host` — уже известен, DNS-запрос не нужен вообще
2. AdGuard DNS: `94.140.14.14` — российский сервис, редко блокируется ТСПУ
3. Cloudflare: `1.1.1.1` — резервный

**Rationale:** Bootstrap DNS виден ТСПУ до поднятия туннеля. Яндекс (`77.88.8.8`) захардкожен в `PoolBuilder.dnsBlock()` — критическая проблема: российская компания, может коллаборировать с ТСПУ. Использование IP сервера напрямую полностью исключает DNS-запрос до открытия туннеля.

**Code impact:** `PoolBuilder.dnsBlock()` — убрать `77.88.8.8`, принять `bootstrapServers: [String]` параметр.

---

### D-02: Tunnel DNS (NET-01b)

**Decision:** По умолчанию — Cloudflare DoH (`1.1.1.1`) внутри туннеля. Если пользователь указал `customDNS` в Advanced Settings — использовать его вместо Cloudflare. Если включён AdBlock — использовать AdGuard (D-04 ниже).

**Rationale:** Cloudflare — быстрый, приватный, независимый от России. DoH шифрует DNS-запросы внутри туннеля дополнительным слоем.

---

### D-03: Custom DNS (NET-02)

**Decision:** В Advanced Settings добавить текстовое поле «Свой DNS-сервер (IP)». Если заполнено — используется вместо Cloudflare для туннельного DNS. Если пусто — Cloudflare по умолчанию.

**Interplay:** Custom DNS имеет наивысший приоритет. Если задан Custom DNS — AdBlock toggle игнорируется (пользователь уже контролирует DNS).

**Placement:** Advanced Settings → секция DNS.

---

### D-04: AdBlock DNS toggle (NET-03)

**Decision:** В Advanced Settings добавить переключатель «Блокировать рекламу». Если включён — туннельный DNS переключается с Cloudflare на AdGuard (`94.140.14.14`), который по умолчанию блокирует рекламные домены и трекеры.

**Placement:** Advanced Settings → секция DNS, рядом с полем Custom DNS.

**Priority order (туннельный DNS):**
1. `customDNS` (если заполнен) → `customDNS`
2. `adBlockEnabled == true` → AdGuard `94.140.14.14`
3. По умолчанию → Cloudflare `1.1.1.1`

---

### D-05: DNS scope (NET-04)

**Decision:** DNS-настройки (Custom DNS, AdBlock toggle) — глобальные, не per-server. Хранятся в `AppStorage` в `SettingsViewModel`. Применяются ко всем подключениям.

**Rationale:** Per-server DNS — Phase 11 расширение ServerDetailView. В Phase 6 — глобальные настройки для простоты.

---

### D-06: IPv6 mode (NET-05..07)

**Decision:** Всегда блокировать IPv6 при включённом VPN (нет адаптивной проверки).

**Implementation:** В `NETunnelNetworkSettings` добавить `NEIPv6Settings` c маршрутом `::/0` внутри туннеля без реального IPv6-гейтвея на выходе → весь IPv6-трафик захватывается в туннель и там теряется (blackhole). **Нельзя** просто не включать `NEIPv6Settings` — тогда iOS пустит IPv6 мимо туннеля, что является утечкой.

В sing-box конфиге TUN: `"inet6_address": "::1/128"` + route `::/0` → blackhole.

**Rationale:** IPv6-only сайты крайне редки в России. Полная блокировка = ноль утечек = максимальная защита. Adaptive detection (проба при подключении) отложена — усложняет Phase 6.

---

### D-07: Auto-reconnect mechanism (NET-08..10)

**Decision:** При разрыве соединения — автоматически переподключаться до **3 попыток** с экспоненциальной задержкой (2с → 4с → 8с).

**UI во время попыток:** баннер «Переподключение...» (использовать существующий `ReconnectBanner`).

**После 3 провалов:** push-уведомление «Не удалось подключиться к [имя сервера]», VPN переходит в `.disconnected`.

**Trigger events (что запускает авто-реконнект):**
- Смена сети (Wi-Fi ↔ LTE): `NWPathMonitor` (Network.framework)
- Выход из сна / foreground: `UIApplication.didBecomeActiveNotification` (iOS) / `NSWorkspace.wakeNotification` (macOS)
- Потеря связи по ping-таймауту sing-box (если sing-box сообщает о разрыве)

**Code impact:** `TunnelController` — добавить `NWPathMonitor`, обработку wake-notifications, retry-state machine (счётчик попыток, задержки, сброс при успехе).

---

### D-08: Failover strategy (NET-11)

**Decision:** После 3 неудачных попыток авто-реконнекта к текущему серверу — автоматически переключиться на **следующий сервер в списке** (round-robin по порядку в `ServerListView`). Баннер: «Переключаюсь на резервный сервер».

**Edge cases:**
- Список из 1 сервера → показать уведомление «Сервер недоступен» и не пытаться failover
- Прошли весь круг (все серверы недоступны) → уведомление «Все серверы недоступны», остановить попытки

**State:** `TunnelController` хранит `failoverIndex: Int` (индекс в отсортированном массиве `ServerConfig`). Сбрасывается при ручном отключении или успешной сессии дольше 30 секунд.

---

## Codebase Impact

| Файл | Изменение |
|------|-----------|
| `VPNCore/DNSConfig.swift` (новый) | Struct: `bootstrapServers`, `tunnelDNS`, `adBlockEnabled` — передаётся в PoolBuilder |
| `PoolBuilder.swift` | `dnsBlock()` принимает `DNSConfig`; убрать хардкод Yandex `77.88.8.8` |
| `PacketTunnelProvider` | `NEIPv6Settings` blackhole `::/0`; передавать `DNSConfig` в PoolBuilder |
| `TunnelController.swift` | `NWPathMonitor`, retry state machine (3 попытки, exp backoff), failover логика |
| `SettingsViewModel.swift` | `customDNS: String`, `adBlockEnabled: Bool` добавить в `AppStorage` |
| `AdvancedSettingsView.swift` (новый) | DNS секция: toggle AdBlock + текстовое поле Custom DNS |
| `ReconnectBanner.swift` | Переиспользуется как есть или расширяется для «Переподключение...» текста |

---

## Claude's Discretion

- Точные поля `NEIPv6Settings` для blackhole-маршрута (iOS/macOS API нюансы)
- Параметры `NWPathMonitor` (queue, throttle callback чтобы не дёргать на каждое микроизменение сети)
- Точная структура `DNSConfig` (методы PoolBuilder)
- Тесты для retry state machine
- Как sing-box сигнализирует о разрыве (через libbox callback или мониторинг процесса)

---

## Deferred to Later Phases

- Per-server DNS override → Phase 11 (ServerDetailView расширение)
- Adaptive IPv6 detection (runtime probe при подключении) → Phase 7+
- Captive portal detection → Phase 7
- Обработка заблокированных bootstrap DNS серверов (например 1.1.1.1 заблокирован) → Phase 7

---

## Requirements Coverage

| ID | Требование | Решение |
|----|-----------|---------|
| NET-01 | Bootstrap DNS + tunnel DNS стратегия | D-01, D-02 |
| NET-02 | Custom DNS пользователя | D-03 |
| NET-03 | AdBlock через DNS | D-04 |
| NET-04 | DNS scope (global/per-server) | D-05 |
| NET-05 | IPv6 default mode | D-06 |
| NET-06 | IPv6 TUN setup | D-06 |
| NET-07 | IPv6 leak protection | D-06 |
| NET-08 | Auto-reconnect trigger events | D-07 |
| NET-09 | Retry policy (count, delays) | D-07 |
| NET-10 | Reconnect UI (banner + notification) | D-07 |
| NET-11 | Failover на следующий сервер | D-08 |
