---
name: Обзор протоколов
description: 9 VPN-протоколов проекта, порядок реализации и роли
type: project
---

# Обзор протоколов

**Summary**: Девять протоколов, разнесённых по группам приоритета (Phase 1/2/3). Группы — **не релизы**: конкретный график появления каждого протокола см. в [[release-roadmap]]. На v0.1 — только VLESS+Reality.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-12

---

## Принцип выбора протокола

Главная угроза — ТСПУ (см. [[tspu]]) с массовым DPI (Deep Packet Inspection — глубокая инспекция пакетов). Поэтому приоритетная группа — это **VLESS+Reality**, главный anti-DPI протокол: маскируется под TLS-handshake к настоящему сайту. Остальные протоколы — для разных сценариев и серверов.

## Phase 1 — приоритетная группа

Группа приоритетных протоколов. **Не значит, что все они появятся в v0.1** — конкретный график см. в [[release-roadmap]].

| Протокол | Роль | Появляется в |
|----------|------|--------------|
| **VLESS + Reality** | Главный anti-ТСПУ. Маскируется под TLS-handshake к настоящему сайту (`www.microsoft.com` и т.п.). Детально — [[vless-reality]]. | **v0.1** (единственный в первой сборке) |
| **WireGuard** | Когда DPI не блокирует UDP. Через WireGuardKit от ZX2C4. | **v0.7** (вместе с anti-DPI suite и WireGuard-семейством) |

## Phase 2 — расширение протоколов

| Протокол | Роль | Появляется в |
|----------|------|--------------|
| **Trojan** | TLS-based, выглядит как обычный HTTPS. TCP+TLS и WS+TLS. Детально — [[trojan]]. | ✓ **v0.2** (реализован 2026-05-12) |
| **VLESS + XTLS-Vision** | Для серверов без поддержки Reality. | **v0.4** |
| **Shadowsocks-2022** (SS-2022, AEAD-2022) | Современная версия SS, AES-128-GCM. AEAD — Authenticated Encryption with Associated Data. | **v0.4** |
| **Hysteria2** | UDP-based, QUIC-обёртка (QUIC — Quick UDP Internet Connections), анти-DPI на password authentication. | **v0.4** |

## Phase 3 — anti-DPI advanced + WireGuard-семейство

| Протокол | Роль | Появляется в |
|----------|------|--------------|
| **AmneziaWG** | Модифицированный WireGuard от команды Amnezia с anti-DPI обфускацией. | **v0.7** |
| **TUIC v5** | QUIC-based, альтернатива Hysteria2. | **v0.7** |
| **OpenVPN over TLS** | Legacy-совместимость. | **v0.7** |

## Транспорты (поверх VLESS/VMess)

Применяются как обёртка вокруг основного протокола. Подробности — [[transports]]. Кратко:

- **XHTTP** — новый рекомендуемый, маскировка под HTTP/2 multiplexed traffic
- **gRPC** — HTTP/2 RPC, очень устойчив к DPI
- **WebSocket** — легаси, но широко поддерживается серверами
- **HTTPUpgrade** — минималистичный, легче gRPC

## Регистрация в проекте

Каждый протокол — отдельный SwiftPM-модуль с реализацией `VPNProtocolHandler` (см. [[architecture]]). Регистрация через `ProtocolRegistry.shared.register(...)` при старте. Чтобы убрать протокол — удалить регистрацию, остальное компилируется.

## Auto-fallback

✓ **Реализован в v0.2** через sing-box `urltest` outbound. При импорте нескольких URI (или subscription с несколькими серверами) `PoolBuilder` оборачивает все outbound-ы в `urltest` selector:

```json
{ "type": "urltest", "tag": "selector", "outbounds": ["trojan-0", "trojan-1"], "interval": "1m" }
```

Sing-box автоматически замеряет latency каждую минуту (запрос к `https://www.gstatic.com/generate_204`) и направляет трафик через наилучший outbound. При недоступности — переключается без вмешательства пользователя. Подробности — [[config-importer]].

## Multi-hop / chain-proxy

**Не реализуем на MVP.** Архитектура должна позволять добавить позже без рефакторинга. В roadmap — v1.3.

## Связанные риски

- Sing-box и xray-core имеют известную **уязвимость localhost-SOCKS5** на Android — см. [[xray-localhost-vulnerability]]. На iOS sandbox-модель строже, но обязательно проверить.

## Related pages

- [[vless-reality]]
- [[trojan]]
- [[config-importer]]
- [[transports]]
- [[anti-dpi-techniques]]
- [[tspu]]
- [[xray-localhost-vulnerability]]
- [[release-roadmap]]
