---
name: WireGuard plain — deferral decision May 2026
description: Решение Phase 7 D-02 — PROTO-06 WireGuard plain в Out of Scope из-за ТСПУ behavioral fingerprinting; AmneziaWG 2.0 покрывает WG-нишу
type: project
---

# WireGuard plain — отложен на v1.x backlog (Phase 7 D-02)

**Summary**: По итогам Phase 7 discuss-phase 2026-05-14 (deep research Codex GPT-5 + WebSearch) — **удалить plain WireGuard (PROTO-06) из MVP**, перенести в Out of Scope. Причины: (а) ТСПУ блокирует WireGuard behaviorally с декабря 2025, полная блокировка с февраля 2026; (б) переключение на UDP/443 не помогает — РКН закрыл «неидентифицированный UDP» в РФ летом 2025; (в) сам Amnezia подтверждает что WG имеет фиксированные заголовки и предсказуемые размеры пакетов — DPI ловит без проблем; (г) AmneziaWG 2.0 (Phase 7b) покрывает WG-нишу с обфускацией; (д) ноль user-visible loss для анти-ТСПУ-аудитории.

**Sources**: Phase 7 discuss-phase 2026-05-14 (CONTEXT.md + DISCUSSION-LOG.md), Codex thread `019e26f2-55e1-79d3-af9f-3d89fdc93647` (deep research), WebSearch 2026-05-14.

**Last updated**: 2026-05-14

---

## Контекст

ROADMAP Phase 7 указывал WireGuard plain (PROTO-06) — нативную WireGuard-реализацию через WireGuardKit от ZX2C4 — как часть scope «закрыть оставшиеся 4 протокола из 9». На этапе discuss-phase 2026-05-14 запущено deep research по реальному статусу WireGuard в РФ 2026.

## Что показало исследование

### ТСПУ vs plain WireGuard — хронология

| Дата | Событие | Источник |
|---|---|---|
| **Лето 2025** | Роскомнадзор «почти полностью» закрыл неидентифицированный UDP-трафик в РФ — переключение WG-on-443/UDP больше не помогает | [TechRadar interview Mazay Banzaev / Amnezia 2026-01-24](https://www.techradar.com/vpn/vpn-services/russias-battle-against-vpns-is-entering-a-new-phase-heres-what-to-expect-in-2026) |
| **Декабрь 2025** | ТСПУ переходит на behavioral fingerprinting — plain WireGuard ловится по фиксированной структуре handshake-пакета | WebSearch consensus май 2026 |
| **Февраль 2026** | WireGuard заблокирован **полностью** наряду с OpenVPN | WebSearch consensus май 2026 |
| **Март 2026** | HRW: 3 самых популярных VPN-протокола под блоком с декабря 2025 (один из них WG) | [HRW 2026-03-12](https://www.hrw.org/news/2026/03/12/russia-digital-iron-curtain-falls-on-internet-freedom-protection-day) |
| **Апрель 2026** | ACF report: «standard protocols including vanilla WireGuard are not dependable building blocks in Russia» | [ACF report 2026](https://fbk.info/files/acf-internet-report-EN.pdf) |

### Самоощущение upstream

Amnezia в Habr-статье март 2026:
> «WireGuard имеет фиксированные заголовки и предсказуемые размеры пакетов, что позволяет DPI их детектировать»

— это **прямое признание** того, что plain WireGuard в РФ непригоден без obfuscation layer (которым становится AmneziaWG 2.0).

### Что говорит community

- **Codex GPT-5 advisory** (thread `019e26f2-55e1-79d3-af9f-3d89fdc93647`): «Do not integrate plain WireGuard as a Russia anti-ТСПУ protocol in Phase 7. It is useful only as a "known good outside Russia / LAN / corporate VPN import" feature, not as a bypass tool».
- **Net4People bbs**: 2025-2026 threads о Russia focus на TLS policing, VLESS/Reality, XHTTP, whitelists, Snowflake/DTLS, AmneziaWG 2.0. Plain WG появляется как «already-blocked baseline since 2023».
- **FOSDEM 2026 Russia circumvention slides**: «standard VPN protocols such as OpenVPN/L2TP/WireGuard are easily detectable by DPI».

### Sing-box endpoint реальность (если бы интегрировали)

В sing-box 1.13 WireGuard был перенесён из `outbound` в `endpoint` тип (миграция 1.11→1.13, см. [sing-box docs](https://sing-box.sagernet.org/migration/#migrate-wireguard-outbound-to-endpoint)). Это значит:
- WireGuard endpoint **не может быть членом `urltest.outbounds`** (наш auto-fallback пул) — потому что endpoints отдельный тип, не outbound
- Архитектурно требуется отдельная route rule для switch на WG-endpoint
- PoolBuilder.swift был бы вынужден учитывать endpoint vs outbound distinction

То есть даже технически интеграция plain WG усложняет PoolBuilder ради протокола, который не работает в РФ.

### Альтернативы — обфускация plain WG

| Техника | Статус | Engineering implication |
|---|---|---|
| **udp2raw / phantun** | Свой transport layer, не «plain WG» | Отдельная интеграция, не sing-box |
| **wstunnel поверх WG** | Не sing-box стек | Отдельная обёртка |
| **TURN/DTLS wrappers** | Niche | Не в анти-ТСПУ menu |
| **WireSock-style DPI protection** | Сторонний продукт | Не open-source стандарт |
| **AmneziaWG** | ✓ **Это и есть «обфусцированный WG»** | Phase 7b — отдельный engine через amneziawg-apple |

**Вывод по обфускации:** все «обфускации plain WG» — это либо отдельный transport layer (вне sing-box), либо отдельный протокол. Самый «правильный» путь — AmneziaWG, который и закрывает эту нишу.

## Решение

**PROTO-06 WireGuard plain → Out of Scope, v1.x backlog conditional on TestFlight demand.**

Critical insight: **AmneziaWG 2.0 = WireGuard, у которого изменили внешний вид пакетов** (S/H/I/J параметры) при той же криптографии. То есть AmneziaWG 2.0 **полностью покрывает функциональную нишу plain WG**, плюс делает его реально применимым в РФ.

Критерий возврата: пользователь в TestFlight явно попросил поддержку `.conf` файлов от **non-РФ WG-серверов** (корпоративный WG, личный WG-сервер за пределами РФ, для которых анти-ТСПУ не критично).

## Что мы теряем

- ✗ Phase 7 success criteria #4 «WireGuard через WireGuardKit и AmneziaWG со своей обфускацией работают параллельно» — переписан на «AmneziaWG 2.0 + Hysteria2 + TUIC v5 покрывают UDP-семейство; plain WireGuard not applicable для РФ-аудитории».
- ✗ Совместимость с `.conf` файлами от non-РФ WG-серверов — нишевая аудитория (друзья разработчика в РФ — не корпоративные WG-пользователи).
- ✗ Спецификация уменьшается с 9 до 8 протоколов.

## Что мы получаем

- ✓ Не интегрируем sing-box WireGuard endpoint pattern (новый distinction в PoolBuilder, миграция 1.11→1.13).
- ✓ Не вводим пользователя в заблуждение через plain WG-сервер который **не подключится** в РФ.
- ✓ Архитектурный фокус на **AmneziaWG 2.0** (Phase 7b) — реально-работающий WG-семейства протокол.
- ✓ Архитектура engine abstraction (Phase 7b) + Package-per-handler оставляет дверь открытой для будущего возврата plain WG без рефактора.

## Conditional return — что будет триггером

1. Пользователь в TestFlight явно попросил `.conf` импорт для non-РФ WG-сервера.
2. 3+ независимых таких запросов внутри 6 месяцев.
3. **Маловероятно, но возможно:** ТСПУ ситуация изменилась — plain WG снова стал работать (cat-and-mouse), что требует переоценки.

При триггере — реализация через sing-box WireGuard endpoint (тот же sing-box engine, минимальный effort: ~Short-Medium), с обязательной UI-пометкой «not for ТСПУ bypass» если сервер plain-WG.

## Related pages

- [[protocols-overview]] — общий список протоколов (8 in-scope, 1 out-of-scope) — будет обновлена после Phase 7a closure
- [[openvpn-deferral-2026]] — параллельное решение D-01 по OpenVPN
- [[anti-dpi-techniques]] — техники, которые реально применяются
- [[tspu]] — описание угрозы ТСПУ
- [[release-roadmap]] — версии v0.1 → v1.0
- [[security-gaps]] — Phase 7 R20 — общее обоснование архитектурных решений Phase 7

## Source URLs (full list)

- HRW reports: 2025-07-30, 2026-03-12
- ACF/FBK April 2026 internet report: `https://fbk.info/files/acf-internet-report-EN.pdf`
- TechRadar Mazay Banzaev / Amnezia interview 2026-01-24
- Habr Amnezia статьи 2026 (AmneziaWG 2.0 announcement)
- sing-box WireGuard endpoint docs + migration guide
- Net4People bbs 2025-2026 Russia threads (#490, #546, #589)
- FOSDEM 2026 Russia circumvention slides
- ACF/FBK April 2026 report
- Codex GPT-5 deep research thread `019e26f2-55e1-79d3-af9f-3d89fdc93647`

*Decision logged 2026-05-14 in `/gsd-discuss-phase 7` D-02. CONTEXT.md: `.planning/phases/07-anti-dpi-suite-wireguard-family/07-CONTEXT.md`. PROJECT.md: R20.*
