---
name: Обзор протоколов
description: 9 VPN-протоколов проекта, порядок реализации и роли
type: project
---

# Обзор протоколов

**Summary**: **6 in-scope протоколов в финальном MVP-наборе** (was 9 — после Phase 7 closure 2026-05-14: PROTO-06 plain WireGuard + PROTO-07 AmneziaWG 2.0 + PROTO-09 OpenVPN/TLS перенесены в Out of Scope, v2.0+ backlog conditional on demand. См. [[wireguard-deferral-2026]] + [[amneziawg-deferral-2026]] + [[openvpn-deferral-2026]]). Разнесены по группам приоритета (Phase 1/2/3). Группы — **не релизы**: конкретный график появления каждого протокола см. в [[release-roadmap]]. На v0.1 — только VLESS+Reality.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-14 (Phase 7 fully Closed — финальный список 6 in-scope протоколов; AmneziaWG + plain WG + OpenVPN → v2.0+ backlog conditional on demand)

---

## Принцип выбора протокола

Главная угроза — ТСПУ (см. [[tspu]]) с массовым DPI (Deep Packet Inspection — глубокая инспекция пакетов). Поэтому приоритетная группа — это **VLESS+Reality**, главный anti-DPI протокол: маскируется под TLS-handshake к настоящему сайту. Остальные протоколы — для разных сценариев и серверов.

## Phase 1 — приоритетная группа

Группа приоритетных протоколов. **Не значит, что все они появятся в v0.1** — конкретный график см. в [[release-roadmap]].

| Протокол | Роль | Появляется в |
|----------|------|--------------|
| **VLESS + Reality** | Главный anti-ТСПУ. Маскируется под TLS-handshake к настоящему сайту (`www.microsoft.com` и т.п.). Детально — [[vless-reality]]. | **v0.1** (единственный в первой сборке) |
| ~~**WireGuard plain**~~ | ~~Когда DPI не блокирует UDP~~. **Out of Scope per Phase 7 discuss 2026-05-14** — ТСПУ blocks plain WG behaviorally с Feb 2026; AmneziaWG 2.0 покрывает нишу. См. [[wireguard-deferral-2026]]. | — (v1.x conditional на demand) |

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
| ~~**AmneziaWG 2.0**~~ | ~~Модифицированный WireGuard от команды Amnezia с anti-DPI обфускацией~~. **Out of Scope per Phase 7b cancellation 2026-05-14** — Codex deep research показал 5-7 engineer-weeks integration cost (manual `libwg-go.a` build chain Go 1.26, Go runtime memory unknown на iOS 18 NetworkExtension 50MB limit, no crash isolation от Go panic, AWG 2.0 backward-incompat с v1.5 серверами); user-base — friends-and-family с уже работающим Reality+Trojan+Hy2+TUIC стеком, AWG demand не подтверждён реальными запросами. См. [[amneziawg-deferral-2026]]. | — (v2.0+ conditional на demand) |
| **TUIC v5** | QUIC-based, альтернатива Hysteria2. cubic/new_reno/bbr congestion_control, native/quic udp_relay_mode, R1-strict (НЕТ Hy2-style allowInsecure exception). Через sing-box outbound `type: "tuic"`. | **v0.7.1** ✅ (Phase 7a Closed 2026-05-14, iPhone UAT PASS на Trojan; реальный TUIC connection test carved-out до появления TUIC сервера) |
| ~~**OpenVPN over TLS**~~ | ~~Legacy-совместимость~~. **Out of Scope per Phase 7 discuss 2026-05-14** — ТСПУ blocks полностью с Feb 2026; sing-box не умеет OpenVPN; требует Partout engine с GPLv3 licensing. См. [[openvpn-deferral-2026]]. | — (v2.0+ conditional на demand) |

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
