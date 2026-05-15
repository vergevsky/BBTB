# CDN-фронтинг архитектура (2026)

**Summary**: Архитектура DPI-06 CDN-фронтинг — FrontingEngine SwiftPM пакет, 3 адаптера (Cloudflare/Fastly/Custom), sing-box transport mapping (D-05), failure fallback chain (D-06) и решение не использовать Cloudflare classic domain fronting.

**Sources**: `.planning/phases/10-advanced-settings-security-polish/10-CONTEXT.md` (D-03..D-07), `.planning/phases/10-advanced-settings-security-polish/10-RESEARCH.md`, Codex advisory threads Phase 10.

**Last updated**: 2026-05-15 (Phase 10 closure — FrontingEngine реализован, activation pending Phase 11 admin handoff)

---

## Архитектурное решение D-03 — FrontingProfile отдельно от TransportConfig

**Решение**: FrontingProfile — отдельный struct, не часть TransportConfig.

**Обоснование**: TransportRegistry содержит 50+ транспортов (TCP, WS, HTTP, HTTPUpgrade, gRPC, h2, ...). Если CDN логику встроить в TransportConfig — каждый транспорт должен был бы нести optional CDN поля или дублировать overlay логику. Это нарушает SRP (Single Responsibility Principle) и затрудняет масштабирование до 20+ протоколов.

Вместо этого: CDN config — **ортогональный слой** поверх TransportConfig. ConfigImporter решает «применять CDN или нет» в одном месте (`provisionTunnelProfile`), без изменений в транспортах.

## Компоненты FrontingEngine

```
FrontingEngine/Sources/FrontingEngine/
├── FrontingProfile.swift        — CDN dial target overlay struct
├── CDNProviderAdapter.swift     — static protocol (mirror TransportHandler)
├── CloudflareAdapter.swift      — Cloudflare anycast edge impl
├── FastlyAdapter.swift          — Fastly CDN edge impl
├── CustomCDNAdapter.swift       — generic SNI+Host swap impl
├── FrontingError.swift          — error enum
├── FrontingConfigApplier.swift  — pure static batch JSON overlay
├── FrontingFailureCache.swift   — actor: score+cooldown persistence
└── FrontingFallbackChain.swift  — actor: sequential cursor w/ pre-advance
```

### FrontingProfile — struct полей

| Field | Sing-box target | Пример |
|-------|----------------|--------|
| `connectHost` | `outbound.server` | `"1.1.1.1"` или `"cdn.example.com"` |
| `connectPort` | `outbound.server_port` | `443` |
| `sniHost` | `outbound.tls.server_name` | `"legit-customer.cdn-provider.com"` |
| `httpHost` | `transport.headers.Host` (WS) / `transport.host` (HTTPUpgrade) | Совпадает с sniHost обычно |
| `provider` | — | `.cloudflare` / `.fastly` / `.custom` |
| `mode` | — | `.domain` / `.ipPool` / `.remoteSigned` |

### CDNProviderAdapter — static protocol

```swift
public protocol CDNProviderAdapter {
    static func applyFronting(to outbound: inout [String: Any], profile: FrontingProfile) -> Bool
}
```

Возвращает `false` если outbound в D-05 blacklist. Adapters — static enums (mirror Phase 5 TransportHandler pattern).

## D-05 — Sing-box transport mapping + blacklist

**Транспорты, совместимые с CDN overlay** (adapter применяет overlay):

| Transport | Overlay | Что меняется |
|-----------|---------|-------------|
| WS | ✅ | `server`, `server_port`, `tls.server_name`, `transport.headers.Host` |
| HTTPUpgrade | ✅ | `server`, `server_port`, `tls.server_name`, `transport.host` |
| gRPC | ✅ (SNI-only) | `server`, `server_port`, `tls.server_name` (host в gRPC metadata нет) |

**D-05 Blacklist** (adapter возвращает false — overlay НЕ применяется):

| Protocol | Причина |
|----------|---------|
| VLESS+Reality | XTLS-Reality использует свой TLS handshake с publicKey/shortId; CDN overlay ломает reality pinning |
| TUIC | QUIC-based; CDN proxy требует TCP+TLS; CDN → QUIC forwarding нет у Cloudflare/Fastly |
| Hysteria2 | QUIC-based; аналогично TUIC |
| VLESS+Vision | Flow `xtls-rprx-vision` — специфичный TLS negotiation; CDN overlay меняет TLS handshake неправильно |

## D-06 — Failure chain + cooldown ladder

**FrontingFailureCache** (actor) хранит score для каждого CDN endpoint:

| Score | Cooldown | Когда |
|-------|----------|-------|
| 1 | 6 часов | Первый failure |
| 2-3 | 12 часов | Повторный failure |
| ≥4 | 24 часа | Persistent failure |
| 10 | 24 часа (cap) | Max score cap |

Persistence: JSON-файл в App Group `Library/Caches/cdn/cdn-failure-cache.json` (best-effort atomic write).

**FrontingFallbackChain** (actor) хранит cursor в массиве `[FrontingProfile]`. При вызове `nextEndpoint()`:

1. **Pre-advance cursor** перед `await` suspension (предотвращает actor reentrancy race — Swift actors allow reentrancy at await suspension points; cursor должен быть reserv'нут до suspension).
2. Проверить `FrontingFailureCache.shouldSkip(endpoint)`.
3. Если skip → advance к следующему без выдачи.
4. Return profile или `(nil, exhausted: true)` если все skip'нуты.

## Cloudflare classic domain fronting — почему НЕ используем

**«Classic domain fronting»** (tech 2016): SNI = `cdn-provider.com`, Host: `victim-server.cdn-provider.com` — два разных домена в одном TLS соединении. Cloudflare **заблокировал** эту технику в 2015-2017 (CNNI report, Signal abandonment); аналогично Fastly и Amazon CloudFront.

**Наш подход («свой домен»)**: Cloudflare SaaS или Workers — admin настраивает `legit-customer.cdn-provider.com` как свой кастомный домен, направляющий к origin VPN серверу. SNI = Host = тот же кастомный домен. DPI видит HTTPS к Cloudflare. VPN трафик проксируется через Cloudflare к origin. Это **не нарушает** Cloudflare ToS (если admin согласен).

Почему это работает: modern CDN-фронтинг — не cross-domain trick, а legitsite-based proxy. Admin владеет доменом (или арендует Cloudflare Custom Hostname), VPN-сервер — origin.

## v0.10 статус и Phase 11 activation

**Phase 10 v0.10**: FrontingEngine package готов (20 unit tests PASS). ConfigImporter вызывает `FrontingConfigApplier.apply` при `cdnFrontingEnabled=true`. Но `extractFrontingProfile()` возвращает nil для всех серверов — server-side payload ещё не доставляется.

**Phase 11 activation** потребует:
1. **Сервер**: admin в Marzban добавляет `frontingProfile` JSON blob в subscription payload (см. [[cdn-fronting-server-handoff]]).
2. **Клиент**: ~5-10 строк в `extractFrontingProfile()` — parse `server.frontingProfileJSON` или subscription metadata.

**Будущее (v1.x)**:
- 5+ CDN провайдеров (AWS CloudFront, Azure CDN, ...).
- IP pool remote sync — admin загружает пул IP адресов Cloudflare anycast edge; FrontingFallbackChain итерирует.
- `.remoteSigned` mode — FrontingProfile доставляется через signed subscription manifest (как rules.json).

## Related pages

- [[cdn-fronting-server-handoff]]
- [[anti-dpi-techniques]]
- [[security-gaps]]
- [[transports]]
- [[architecture]]
