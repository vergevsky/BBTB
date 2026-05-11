---
name: DNS pipeline (имплементированная конфигурация Phase 1 W5)
description: Реализованный DNS-pipeline после device-debug 2026-05-11 — fakeip + Yandex bootstrap + DoH fallback + HTTPS NXDOMAIN + route.resolve
type: project
---

# DNS pipeline — имплементация Phase 1 W5

**Summary**: Финальная DNS-конфигурация sing-box после серии fail-tests на iPhone iOS 26 (2026-05-11). Hiddify-canonical pattern: fakeip для пользовательских A/AAAA, Yandex direct TCP для bootstrap, DoH cloudflare-dns.com через VLESS как fallback, NXDOMAIN на HTTPS/SVCB чтобы избежать DDR/HTTP3-разведки.

**Sources**: device-debug session 2026-05-11, Codex+Gemini consultations, [hiddify/hiddify-app#758](https://github.com/hiddify/hiddify-app/issues/758), [SagerNet/sing-box#4023](https://github.com/SagerNet/sing-box/issues/4023), [XTLS/Xray-core#5966](https://github.com/XTLS/Xray-core/issues/5966)

**Last updated**: 2026-05-11

---

## Зачем такая сложная схема

Простые подходы **не работали** в нашей среде (iOS 26 NE + sing-box libbox 1.13.11 + VLESS+Reality+Vision к серверу в Латвии из РФ):

| Попытка | Симптом | Причина |
|---|---|---|
| `tcp://1.1.1.1` через vless-out | EOF при чтении ответа | Vision flow ломает короткие TCP/53 single-shot exchanges |
| `tcp://9.9.9.9` через vless-out | Идентичный EOF | Не Cloudflare-specific, а **Vision short-stream** issue (issue #397) |
| `https://1.1.1.1/dns-query` (DoH IP-literal SNI) | TLS handshake OK, EOF после HTTP/2 SETTINGS | Тот же Vision короткий-payload pattern |
| Direct plain DNS из РФ | TSPU spoofing для некоторых доменов | Российский DNS под ТСПУ |
| Прямой UDP DNS к Cloudflare | drop/timeout | ТСПУ блокирует UDP/53 к иностранным резолверам (см. wiki/tspu.md) |

## Финальная схема

```
┌──────────────────────────────────────────────────────────────┐
│ iPhone iOS 26 — Safari / iOS networking                      │
│   └─ DNS query for api.ipify.org                             │
│      └─ NEDNSSettings 1.1.1.1:53 (system level)              │
└──────────────────────────────────────────────────────────────┘
                            ↓ через TUN inbound
┌──────────────────────────────────────────────────────────────┐
│ sing-box (libbox 1.13.11) — Phase 1 W5 config                │
│                                                              │
│  route.rules:                                                │
│    1. { action: sniff, timeout: 1s }    ← классифицирует    │
│    2. { protocol: dns, action: hijack-dns }                  │
│    3. { network: tcp, action: resolve,                       │
│         server: dns-bootstrap, strategy: ipv4_only }         │
│       ← КЛЮЧЕВОЕ: pre-resolve до VLESS serialization        │
│                                                              │
│  dns.servers:                                                │
│    dns-remote (DoH https://cloudflare-dns.com/dns-query      │
│                via vless-out, address_resolver: bootstrap)   │
│    dns-bootstrap (tcp://77.88.8.8 via direct)                │
│    dns-fakeip (fakeip)                                       │
│                                                              │
│  dns.rules:                                                  │
│    1. { outbound: any, server: bootstrap }                   │
│       — proxy-bootstrap DNS direct, не через туннель        │
│    2. { query_type: [HTTPS, SVCB], → NXDOMAIN }              │
│       — обрубить iOS DDR/HTTP3 discovery (Vision-killer)    │
│    3. { query_type: [A, AAAA], → fakeip }                    │
│       — пользовательские queries → fake IP из CGNAT          │
│                                                              │
│  fakeip.inet4_range: 100.64.0.0/10                           │
│       — CGNAT, не конфликтует с TUN 198.18.0.1/30           │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ Safari открывает TCP к 100.64.0.5:443 (fake IP)              │
│   → sniff: TLS SNI=api.ipify.org                             │
│   → router rule[3]: resolve via bootstrap                    │
│   → Yandex (77.88.8.8) резолвит api.ipify.org → 8.47.69.6   │
│   → VLESS header: destination=8.47.69.6:443 (REAL IP)        │
│   → identical path как Apple Push hardcoded IPs              │
└──────────────────────────────────────────────────────────────┘
```

## Обоснование решений

### Почему fakeip
- Vision flow в sing-box ломает короткие TCP streams (single-shot DNS exchanges)
- fakeip убирает DNS-over-Vision полностью: запросы обслуживаются локально fake-ответами
- TSPU не видит DNS-трафик (он не уходит наружу), не может spoofить

### Почему Yandex (`tcp://77.88.8.8`) для bootstrap
- Direct из РФ к российскому резолверу — ТСПУ не вмешивается
- TCP (не UDP) — устойчивее к point-and-shoot блокировкам
- Yandex резолвит большинство доменов **корректно** (verified: api.ipify.org → real Cloudflare 8.47.69.6)

### Почему `action: resolve` обязателен
Без него sing-box после fakeip reverse-mapping отправляет **hostname** в VLESS header. Сервер пытается резолвить — поведение зависит от server config, часто молча fails (TCP connect succeeds, TLS handshake не завершается).

С `resolve` — клиент сам резолвит до отправки, VLESS header несёт IP, сервер просто открывает TCP к этому IP.

### Почему NXDOMAIN на HTTPS/SVCB
iOS делает DDR (RFC 9461 Discovery of Designated Resolvers) — каждый домен → HTTPS-record query. Safari также делает HTTPS-record для HTTP/3 discovery. Все они **не A/AAAA** → не попадают в fakeip → уходят на dns-remote (DoH через Vision) → короткая HTTP/2 сессия → Vision ломает → Safari блокируется ожиданием ответа.

NXDOMAIN на HTTPS/SVCB → iOS мгновенно понимает «нет HTTP/3 hints, делаем обычный TLS» → переходит к A-запросу → fakeip → работает.

### CGNAT 100.64.0.0/10 для fakeip
Sing-box default — `198.18.0.0/15`, но у нас TUN inbound на `198.18.0.1/30` — конфликт. CGNAT range не пересекается с RFC 1918, RFC 2544 (нашим TUN), default routes.

## Известные ограничения текущей реализации

**Status: partial pass** (Phase 1 W5 device test, 2026-05-11). См. memo `project_phase1_tunnel_debug_2026-05-11.md`.

- ~50% VLESS соединений (117/240) завершаются полным `download/upload finished`
- Apple/iCloud/Telegram backbone трафик работает
- Safari → user-facing HTTPS (api.ipify.org, любые Cloudflare-anycast destinations) обрывается до TLS completion

Подозрение — sing-box client Vision implementation incompatibility с Xray-core server-side Vision (Happ работает с тем же URI — он содержит свои патчи).

## Related pages

- [[tspu]] — что и как блокирует ТСПУ
- [[vless-reality]] — Reality/Vision design, известные incompatibility issues
- [[dns-strategy]] — high-level стратегия (planning), эта страница — concrete implementation
- [[security-gaps]] — R10 TUN inbound rationale
