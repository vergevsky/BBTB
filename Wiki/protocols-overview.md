---
name: Обзор протоколов
description: 9 VPN-протоколов проекта, порядок реализации и роли
type: project
---

# Обзор протоколов

**Summary**: 8 in-scope протоколов (was 9 — PROTO-06 WireGuard plain + PROTO-09 OpenVPN/TLS перенесены в Out of Scope per Phase 7 discuss 2026-05-14, см. [[wireguard-deferral-2026]] + [[openvpn-deferral-2026]]). Разнесены по группам приоритета (Phase 1/2/3). Группы — **не релизы**: конкретный график появления каждого протокола см. в [[release-roadmap]]. На v0.1 — только VLESS+Reality.

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
| **AmneziaWG 2.0** | Модифицированный WireGuard от команды Amnezia с anti-DPI обфускацией (S1-S4, H1-H4, I1-I5, Jc/Jmin/Jmax junk packets). v2.0 only (not v1/v1.5). Через `amneziawg-apple` SwiftPM library + engine abstraction в Phase 7b. | **v0.7.2** (Phase 7b) |
| **TUIC v5** | QUIC-based, альтернатива Hysteria2. cubic/new_reno/bbr congestion_control, native/quic udp_relay_mode, R1-strict (НЕТ Hy2-style allowInsecure exception). Через sing-box outbound `type: "tuic"`. | **v0.7.1** (Phase 7a, реализация code-complete 2026-05-14, awaiting UAT) |
| ~~**OpenVPN over TLS**~~ | ~~Legacy-совместимость~~. **Out of Scope per Phase 7 discuss 2026-05-14** — ТСПУ blocks полностью с Feb 2026; sing-box не умеет OpenVPN; требует Partout engine с GPLv3 licensing. См. [[openvpn-deferral-2026]]. | — (v1.x conditional на demand) |

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
