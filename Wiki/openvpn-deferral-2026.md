---
name: OpenVPN/TLS — deferral decision May 2026
description: Решение Phase 7 D-01 — PROTO-09 OpenVPN/TLS в Out of Scope из-за ТСПУ реальности РФ 2026, sing-box неподдержки и engine-cost
type: project
---

# OpenVPN/TLS — отложен на v1.x backlog (Phase 7 D-01)

**Summary**: По итогам Phase 7 discuss-phase 2026-05-14 (deep research Codex GPT-5 deep mode + WebSearch) решение — **удалить OpenVPN/TLS (PROTO-09) из MVP**, перенести в Out of Scope, conditional return только при появлении реальных пользователей TestFlight с рабочими `.ovpn` подписками. Причины: (а) ТСПУ блокирует OpenVPN behaviorally с февраля 2026; (б) техники обфускации (Cloak, XOR, Shadowsocks-wrap) не работают надёжно или мертвы; (в) sing-box не умеет OpenVPN — требует второго engine'а Partout с GPLv3-сложностями; (г) рынок anti-ТСПУ-провайдеров отказался от OpenVPN; (д) сам Amnezia удалил OpenVPN-over-Cloak из Premium-продукта в 2026.

**Sources**: Phase 7 discuss-phase 2026-05-14 (CONTEXT.md + DISCUSSION-LOG.md), Codex thread `019e26d8-0397-7fa0-91b3-312e7e3e3ca9` (deep research), WebSearch 2026-05-14.

**Last updated**: 2026-05-14

---

## Контекст

Phase 7 по ROADMAP должна была закрыть оставшиеся 4 протокола из 9-протокольной спецификации MVP (см. [[protocols-overview]]). Один из них — **OpenVPN over TLS (PROTO-09)** — позиционировался как «legacy совместимость» для пользователей с уже существующими `.ovpn` конфигами.

В рамках discuss-phase 2026-05-14 запущено deep research через Codex GPT-5 + параллельный WebSearch на тему «реальное состояние OpenVPN в РФ 2026», потому что технический owner проекта запросил «может быть нам нет смыла его интегрировать».

## Что показало исследование

### Хронология блокировок OpenVPN в РФ

| Дата | Событие | Источник |
|---|---|---|
| **2023-08-07** | Net4People: массовые отказы OpenVPN на TCP/UDP/443 на MTS/Tele2/Beeline/Yota — соединение устанавливается, трафик «замораживается» после первых пакетов с данными | [Net4People bbs #274](https://github.com/net4people/bbs/issues/274) |
| **2024-05-06** | Роскомсвобода / RKS Global: системная блокировка OpenVPN на mobile-операторах + краткие региональные блоки Cloak/OpenVPN на проводном интернете | [RKS Censorship Review 2024](https://files.rks.global/censorship_review_en.pdf) |
| **2025-07-30** | HRW: TSPU/EcoSGE может блокировать по типу VPN-протокола; DPIdetector подтверждает что блокируются минимум 7 типов VPN-протоколов, включая OpenVPN | [HRW report](https://www.hrw.org/report/2025/07/30/disrupted-throttled-and-blocked/state-censorship-control-and-increasing-isolation) |
| **Лето 2025** | Роскомнадзор «почти полностью» закрыл «неидентифицированный UDP» — переключение WG/OpenVPN на UDP/443 не помогает | [TechRadar interview Mazay Banzaev / Amnezia 2026-01-24](https://www.techradar.com/vpn/vpn-services/russias-battle-against-vpns-is-entering-a-new-phase-heres-what-to-expect-in-2026) |
| **Декабрь 2025** | ТСПУ переходит на behavioral fingerprinting — OpenVPN, WireGuard, L2TP, SOCKS5 и standard VLESS блокируются не по IP, а по паттерну трафика | WebSearch consensus май 2026 |
| **Февраль 2026** | OpenVPN заблокирован **полностью** (вместе с WireGuard) | WebSearch consensus май 2026 |
| **Март 2026** | В ТСПУ интегрированы ML-алгоритмы (контракт 2.3 млрд ₽) — распознают VPN по поведенческим характеристикам connections | WebSearch consensus май 2026 |
| **Март 2026** | HRW: 469 заблокированных VPN-сервисов (рост 70% с октября 2025); 3 самых популярных VPN-протокола под блоком с декабря 2025 (один — OpenVPN) | HRW 2026-03-12 |
| **Апрель 2026** | ACF/FBK report: «standard protocols including vanilla WireGuard [и OpenVPN] are not dependable building blocks in Russia» | [ACF report 2026](https://fbk.info/files/acf-internet-report-EN.pdf) |
| **Май 2026** | ТСПУ покрывает 95%+ интернет-трафика РФ; РКН получил задачу заблокировать 92% VPN к 2030 | The Moscow Times 2026-05-04 |

### Техники обфускации OpenVPN — реальный статус 2026

| Техника | Статус | Источник | Вердикт |
|---|---|---|---|
| **OpenVPN на TCP/443** | Не работает | CEO Windscribe в TechRadar 2026-04-15: «trivially detected by DPI»; Net4People 2023 уже фиксировали `openvpn 443` failures | Бесполезно |
| **OpenVPN + Cloak** | Уходит | Amnezia self-host поддерживает, но **Amnezia Premium удалил OpenVPN-over-Cloak в 2026** как «всё более детектируемое» (TechRadar Amnezia review 2026) | Не входит |
| **OpenVPN + Shadowsocks** | Niche, не measured | Amnezia docs + единичные Reddit-отчёты (дек 2025); ни одного публичного measurement о ТСПУ-resistance | Ненадёжно |
| **OpenVPN XOR-patch** | Мёртв | Tunnelblick документирует, Partout поддерживает; но FOSDEM 2026 slides на «Russian circumvention»: GRFC обучилось детектировать XOR-вариант **within hours** после появления нод | Тупиковая ветка |
| **OpenVPN + Stunnel / WebSocket** | Не существует как продукт | Никаких отчётов о массовом применении в РФ 2025-2026; WebSocket-обёртка релевантна для Xray/VLESS, не для OpenVPN | N/A |

**Вывод по обфускации:** «интегрировать OpenVPN/TLS» в реальности 2026 = «интегрировать второй engine (Partout) + ещё один обфускационный engine поверх (Cloak/Shadowsocks)». Это не «9-й протокол», это **новая под-архитектура**.

### Адопция OpenVPN в анти-ТСПУ-провайдерах 2026

| Провайдер / клиент | OpenVPN в меню? | Источник |
|---|---|---|
| **Amnezia self-host** | ✓ Legacy support | [Amnezia docs](https://docs.amnezia.org/documentation/protocols-info/) |
| **Amnezia Premium** | ✗ Phased out 2026 | TechRadar Amnezia review 2026 |
| **Hiddify** | ✗ | [hiddify.com](https://hiddify.com/) — sing-box-based, протоколы Hysteria2/TUIC/Reality/VLESS/VMess/Trojan/SS/WS/gRPC/ECH |
| **Marzban / 3X-UI / Xray-панели** | ✗ | Xray/VLESS panels — VLESS/VMess/Trojan/SS/Reality/WireGuard стек |
| **Lunaire VPN** | ✗ | [lunaire.app](https://lunaire.app/en) — Hysteria2 / VLESS Reality / xHTTP / VLESS WebSocket |
| **RyssVPN** | ✗ | [ryss.pro](https://ryss.pro/) — Hysteria2 |
| **FastSaveVPN / Impuls Connect** | ✗ | AmneziaWG + VLESS + Hysteria2 |

**Вывод по адопции:** OpenVPN — это **single-vendor (Amnezia) legacy**, не frontier-протокол. Все остальные участники анти-ТСПУ-рынка ушли на VLESS+Reality / Hysteria2 / TUIC / AmneziaWG 2.0.

### Сообщество (Net4People / sing-box / Hiddify / Amnezia)

В issue trackers Net4People bbs 2025-2026 OpenVPN упоминается как «already blocked baseline since 2023», не как актуальная цель. Конвергенция сообщества: VLESS+Reality / XHTTP, AmneziaWG 2.0, Hysteria2 / TUIC, Shadowsocks-2022. См.:
- [Net4People #490](https://github.com/net4people/bbs/issues/490) (2025-06-27)
- [Net4People #546](https://github.com/net4people/bbs/issues/546) (2025-11-14)
- [Net4People #589](https://github.com/net4people/bbs/issues/589)

### Engineering cost интеграции

sing-box (наш текущий engine через `libbox.xcframework`) **не поддерживает OpenVPN протокол** — это не оговорка, это архитектурная реальность sing-box (он не парсит OpenVPN handshake). Реальный путь интеграции в 2026:

- **OpenVPNAdapter** (passepartoutvpn/openvpn-apple) — **архивирован с марта 2022**, не подходит для iOS 18 / macOS 15
- **Partout** (passepartout.io, современный продолжатель) — Swift/C, SwiftPM, NetworkExtension-aware. **License: GPLv3 + commercial license** требуется для AppStore distribution если не выполняются GPLv3-условия

**Реальный engineering footprint:**
- Второй PacketTunnelProvider extension (либо multi-engine arbitration в одном — сложнее)
- Дублирование kill switch / on-demand R18 / диагностики
- 1-3 недели calendar только на интеграцию первой рабочей связи
- GPLv3 commercial license вопрос для AppStore (отдельный юридический фронт)
- Если нужна anti-ТСПУ-функциональность — ещё обёртка типа Cloak/Shadowsocks

**Оценка Codex GPT-5 deep research:** Medium/Large effort.

### Бизнес-сторона

Аудитория BBTB — **~50 friends-and-family TestFlight users в РФ**, бэкграунд анти-ТСПУ (не legacy enterprise). Реальная статистика анти-ТСПУ-подписок в РФ 2026: VLESS+Reality / Hysteria2 / Shadowsocks-2022 / AmneziaWG 2.0. У друзей разработчика **с высокой вероятностью** нет рабочих `.ovpn` подписок — этот рынок просто другой.

## Решение

**PROTO-09 OpenVPN/TLS → Out of Scope, v1.x backlog conditional on TestFlight demand.**

Критерий возврата: **в TestFlight появились реальные пользователи с рабочими `.ovpn` подписками от Amnezia self-host или non-РФ провайдеров**, и они явно попросили поддержку. До этого момента — никакой работы по интеграции.

## Что мы теряем

- ✗ Формальное «9 протоколов» в спецификации — Phase 7 success criteria переписана на «7 in-scope протоколов в РФ 2026».
- ✗ Совместимость с `.ovpn` файлами от Amnezia self-host (legacy) — мизерная доля рынка.
- ✗ Совместимость с non-РФ корпоративными OpenVPN-серверами — но это не наша аудитория.

## Что мы получаем

- ✓ Phase 7 не вырастает ~2x ради протокола, который **не работает** в РФ.
- ✓ Не вкладываемся в Partout engine, GPLv3 commercial licensing, second PacketTunnel extension.
- ✓ Сохраняем focus на **AmneziaWG 2.0** (Phase 7b) — фронтир-протокол РФ 2026.
- ✓ Архитектура `Package-per-handler` + engine abstraction (Phase 7b) **готова** к добавлению OpenVPN позже без рефактора, если когда-нибудь понадобится.

## Conditional return — что будет триггером

Реальные UAT-сигналы (не теоретическая возможность):
1. Пользователь в TestFlight явно попросил OpenVPN поддержку с конкретной `.ovpn` подпиской.
2. Возможен такой запрос от 3+ независимых пользователей внутри 6 месяцев.
3. ТСПУ ландшафт **существенно изменился** — например, OpenVPN-over-Cloak снова стал работать (маловероятно, но не исключено в cat-and-mouse динамике).

При триггере — отдельная Phase 7c либо v1.x feature phase с явной задачей: Partout engine integration + Cloak/SS обёртка + licensing resolution.

## Related pages

- [[protocols-overview]] — общий список протоколов (8 in-scope, 1 out-of-scope) — будет обновлена после Phase 7a closure
- [[anti-dpi-techniques]] — техники, которые реально применяются
- [[wireguard-deferral-2026]] — параллельное решение D-02 по plain WireGuard
- [[tspu]] — описание угрозы ТСПУ
- [[release-roadmap]] — версии v0.1 → v1.0
- [[security-gaps]] — Phase 7 R20 — общее обоснование архитектурных решений Phase 7

## Source URLs (full list)

- HRW reports: 2025-07-30, 2026-03-12
- ACF/FBK April 2026 internet report: `https://fbk.info/files/acf-internet-report-EN.pdf`
- Net4People bbs: #274 (2023-08-07), #490, #546, #589
- TechRadar Mazay Banzaev / Amnezia 2026-01-24
- TechRadar Amnezia review 2026
- Tunnelblick OpenVPN XOR patch docs
- FOSDEM 2026 Russia circumvention slides
- Amnezia docs (protocols-info, install-configure-protocols, platforms)
- Lunaire, RyssVPN, Hiddify, 3X-UI public pages
- ss-abramchuk/OpenVPNAdapter archive notice (GitHub)
- Partout.io license documentation

*Decision logged 2026-05-14 in `/gsd-discuss-phase 7` D-01. CONTEXT.md: `.planning/phases/07-anti-dpi-suite-wireguard-family/07-CONTEXT.md`. PROJECT.md: R20.*
