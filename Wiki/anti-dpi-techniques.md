---
name: Anti-DPI техники
description: uTLS mimicking, фрагментация TLS ClientHello, packet padding, mux, CDN-фронтинг — все слои защиты от DPI
type: project
---

# Anti-DPI техники

**Summary**: Набор техник для обхода DPI поверх протоколов и транспортов — uTLS fingerprint mimicking, фрагментация TLS ClientHello, packet padding, random delay, mux, CDN-фронтинг.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md, Phase 7 discuss-phase (Codex GPT-5 sing-box 1.13.x research)

**Last updated**: 2026-05-14 (Phase 7a Wave 2 — smart defaults applied, реальное состояние sing-box зафиксировано)

---

## Зачем

Сами по себе [[vless-reality|VLESS+Reality]] и [[transports|транспорты]] дают базовый уровень маскировки. Эти техники — дополнительные слои защиты от ТСПУ (см. [[tspu]]).

## uTLS fingerprint mimicking

Клиент представляется DPI как Chrome / Firefox / Safari. По умолчанию **randomized** — fingerprint выбирается случайно при каждом подключении, чтобы он не был статичным.

В Расширенных пользователь может зафиксировать конкретный fingerprint (Chrome/Firefox/Safari) или оставить random.

## Фрагментация TLS ClientHello

Первый пакет TLS-handshake разбивается на несколько TCP-пакетов так, чтобы DPI **не успел распарсить SNI** (Server Name Indication — указание имени сервера). DPI видит начало TLS, но не видит, к какому домену идёт соединение.

## Packet padding

Добавляем случайные байты к пакетам, чтобы статистические характеристики (длина, частота) **не палили VPN-трафик**. Без padding'а DPI может опознать VPN по типичным длинам пакетов даже при шифровании.

## Random TCP/UDP delay

Рандомные задержки между пакетами для **убийства timing-based DPI**. DPI анализирует тайминги соединений — если они слишком регулярны, это признак автоматизированного протокола.

## Mux (мультиплексирование)

Несколько логических соединений мультиплексируются в **одно TCP-соединение**. Это:

- не палит количество одновременных сессий пользователя
- маскирует VPN под одно долгоживущее HTTPS-соединение (что выглядит как нормальный браузерный keep-alive)

## CDN-фронтинг

Поддержка работы через Cloudflare/Fastly как fallback transport. DPI видит соединение к Cloudflare (общий CDN — Content Delivery Network), а не к VPN-серверу напрямую. Появляется в v0.10 (см. [[release-roadmap]]).

## Разные порты

Разные протоколы — на разных портах для маскировки:

- **443** — приоритет, маскировка под HTTPS
- **80, 8443, 2096** и другие — дополнительные

## Защита целостности

- **Certificate pinning** для соединения с панелью подписок и rules.json
- **Ed25519-подпись** для rules.json (см. [[rules-engine]])

## Реальное состояние в sing-box 1.13.x (verified Phase 7a, 2026-05-14)

После discuss-phase deep research Codex GPT-5 — реальная карта поддержки техник в sing-box, на котором стоит наш `libbox.xcframework`:

| Техника | sing-box 1.13.x | Применимо к | Default в Phase 7a |
|---|---|---|---|
| **uTLS random** (DPI-01) | ✅ `tls.utls.fingerprint = "random"` | Все TLS-протоколы: VLESS+Reality, VLESS+Vision, VLESS+TLS, Trojan, TUIC v5 | **ON по умолчанию** (Wave 2 commit `1d98abc`) |
| **TLS ClientHello fragmentation** (DPI-02) | ✅ `tls.record_fragment` (Boolean), эскалация `tls.fragment` + `tls.fragment_fallback_delay` | TCP TLS: VLESS+TLS, Trojan | **`record_fragment: true` по умолчанию** для VLESS+TLS/Trojan (Wave 2). Эскалация per-server (manual). НЕ применяется к Reality/Vision (XTLS), НЕ к TUIC (QUIC: «Only ECH is supported in QUIC» upstream). |
| **Packet padding** (DPI-03) | ⚠️ Только mux-layer `multiplex.padding` | VLESS+TLS / Trojan / SS-2022 когда mux включён | Default OFF (mux off; per-server URI opt-in) |
| **Random TCP/UDP delay** (DPI-04) | ❌ НЕ доступно в sing-box | — | Реализуется через AmneziaWG 2.0 junk packets (Jc/Jmin/Jmax) — Phase 7b |
| **Mux** (DPI-05) | ✅ `multiplex.protocol = smux/yamux/h2mux` | VLESS+TLS / Trojan / SS-2022 (НЕ Reality/Vision — XTLS conflict; НЕ TUIC/Hy2 — QUIC уже multiplex; НЕ WG) | Per-server URI/Clash `mux=true` (UI toggle — Phase 10 DPI-09) |
| **CDN-фронтинг** (DPI-06) | ✅ через transport layer | VLESS+TLS / Trojan | Phase 10 (v0.10) |
| **Разные порты** (DPI-07) | ✅ ParsedXxx.port принимает любой | Все протоколы | Уже работает (URI парсеры) |

### Что мы НЕ можем (limitations)

- **Generic packet padding** (per-protocol, не mux-layer) — sing-box не имеет такого option. Альтернатива — AmneziaWG 2.0 junk packets для WG-семейства.
- **Random delay для не-AWG протоколов** — нет в sing-box. AmneziaWG junk packets решают для своего протокола.
- **AmneziaWG в sing-box** — upstream feature request closed «not planned» (см. [[amneziawg-integration]] которая создастся в Phase 7b).

## Roadmap

- **v0.7.1 (Phase 7a)** — TUIC v5 как 6-й протокол; uTLS=random + tls.record_fragment ON для applicable TLS-протоколов.
- **v0.7.2 (Phase 7b)** — AmneziaWG 2.0 через `amneziawg-apple` + engine abstraction. DPI-04 random delay становится свойством AmneziaWG.
- **v0.10 (Phase 10)** — UI toggles (DPI-06 CDN-фронтинг, DPI-08 cert pinning, DPI-09 uTLS picker).
- **Out of Scope (v1.x conditional)** — plain WireGuard (PROTO-06), OpenVPN/TLS (PROTO-09). См. [[wireguard-deferral-2026]] + [[openvpn-deferral-2026]].

## Связь с детектом VPN на устройстве

Anti-DPI техники защищают от **сетевого** DPI. Отдельная задача — защита от **локального** детекта VPN на устройстве пользователя (см. [[rkn-detection-methodology]], [[vpn-detection-by-apps]]). Это разные угрозы и разные защиты.

## Related pages

- [[tspu]]
- [[vless-reality]]
- [[transports]]
- [[protocols-overview]]
- [[rules-engine]]
