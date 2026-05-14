---
name: AmneziaWG 2.0 — deferral decision May 2026
description: Решение Phase 7b cancellation 2026-05-14 — PROTO-07 AmneziaWG 2.0 + DPI-04 random delay + engine abstraction отложены до v2.0+ backlog
type: project
---

# AmneziaWG 2.0 — отложен на v2.0+ backlog (Phase 7b cancellation)

**Summary**: По итогам Codex deep research состояния `amneziawg-apple` library + Amnezia VPN multi-engine reference (thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae`) и принятого пользователем 2026-05-14 решения «отложим амнезию вообще на версию 2 или позднее» — **Phase 7b отменена ПОСЛЕ Phase 7a closure**. PROTO-07 AmneziaWG 2.0 + DPI-04 random delay переезжают в Out of Scope (v2.0+ conditional). Engine abstraction layer не строим — ради одного нового движка не оправдан в MVP, архитектура остаётся mono-engine sing-box через `libbox.xcframework` v1.13.11.

**Sources**: Phase 7 discuss-phase 2026-05-14 (CONTEXT.md + DISCUSSION-LOG.md), Codex thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` (deep research состояния amneziawg-apple library + Amnezia VPN multi-engine pattern).

**Last updated**: 2026-05-14

---

## Контекст и хронология решения

### Round 1 — discuss-phase 2026-05-14

В рамках `/gsd-discuss-phase 7` принято решение **D-03**: PROTO-07 AmneziaWG 2.0 only через `amneziawg-apple` SwiftPM library с engine abstraction layer в одном `NEPacketTunnelProvider` extension. Phase 7 разделена на **Phase 7a** (TUIC v5 + anti-DPI smart defaults, sing-box only — простая by-the-book работа) и **Phase 7b** (engine abstraction + AmneziaWG 2.0 — архитектурная фаза, первый multi-engine integration в проекте).

### Round 2 — Phase 7a executed + UAT PASS 2026-05-14

Phase 7a выполнена автономно за один день: 5 commits (`8ca1014` + `1d98abc` + `cb6140b` + `49c40d5` + closure), TUIC v5 protocol package + uTLS=random + tls.record_fragment smart defaults, ~470 tests green, iOS+macOS xcodebuild SUCCEEDED, iPhone UAT PASS на Trojan subscription. Phase 7a → ✅ Closed.

### Round 3 — Phase 7b discuss + Codex deep research 2026-05-14

Перед началом Phase 7b execute запущен Codex deep research thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` для актуального состояния `amneziawg-apple` library + Amnezia VPN iOS multi-engine reference. Ключевые факты:

#### `amneziawg-apple` library state (verified May 2026)

| Факт | Источник |
|---|---|
| Latest commit master: 20 февраля 2026 (`5cbc86f` «update xray and tun2socks»). Жив, AWG 2.0 уже встроен в Swift API (`InterfaceConfiguration.junkPacketCount/Min/Max`, `S1-S4`, `H1-H4`, `I1-I5`). | https://github.com/amnezia-vpn/amneziawg-apple/commits/master/ |
| Всё ещё GitHub fork `WireGuard/wireguard-apple`, MIT license inherited. | https://github.com/amnezia-vpn/amneziawg-apple |
| SwiftPM продукт `WireGuardKit` экспортируется, но **Go bridge не самосборный**. README прямо: «WireGuardKit cannot build [Go bridge] automatically due to Swift package manager limitations». Требуется Xcode External Build System target + manual `make` → `libwg-go.a` через Makefile с `go build -buildmode c-archive`, `CGO_ENABLED=1`, `GOOS=ios`, `lipo` для arm64+sim+macOS slices. | https://raw.githubusercontent.com/amnezia-vpn/amneziawg-apple/master/Package.swift + Sources/WireGuardKitGo/Makefile |
| `go.mod` требует Go 1.26 (README mentions Go 1.19 — stale). Makefile patches GOROOT через `goruntime-*.diff` — reproducibility depends on local Go layout. | https://raw.githubusercontent.com/amnezia-vpn/amneziawg-apple/master/Sources/WireGuardKitGo/go.mod |

#### Amnezia VPN iOS multi-engine reference (`amnezia-client` repo, GPL-3.0)

- Multi-engine pattern там — простой **switch-dispatch в `PacketTunnelProvider.startTunnel`** по ключам `providerConfiguration` (`ovpn` / `wireguard` / `xray`). Не protocol-based.
- One engine runs at a time, нет hot-swap.
- Codex рекомендация: **«Don't copy Amnezia's switch-heavy provider directly»** — у нас уже есть sing-box runtime через libbox, и AWG имеет совершенно другую packet ownership модель (TUN fd vs sing-box library). Нужен protocol-based clean boundary.

#### Go bridge на iOS 18 — главные неопределённости

- Memory: iOS NetworkExtension limit 50MB iOS 15+. **AWG Go runtime footprint неизвестен** — нет публичных измерений на iOS 18. Codex настаивает: «spike must measure RSS/dirty memory and first connect latency on iOS 18 hardware».
- **No crash isolation** — Go panic, fatal runtime abort, memory corruption, jetsam event убивают весь PacketTunnelProvider extension (включая всё что у нас уже работает: VLESS+Reality, Trojan, Hy2, TUIC). Единственная альтернатива — второй extension target (out of Phase 7b scope).
- Cold-start cost — DEC-06d-01 invariant (cold-start init defer pattern); Go runtime init имеет measurable cost.

#### AmneziaWG 2.0 config format

- Native = WireGuard `.conf` файл с extended `[Interface]` секцией с AWG params (Jc/Jmin/Jmax + S1-S4 + H1-H4 + I1-I5).
- Backward compat: AWG 2.0 **НЕ совместим** с v1.5 серверами. Upgrade existing 1.5 connection требует fresh keys.
- Server-side: только Amnezia self-host installer (4.8.12.9+) + community `wiresock/amneziawg-install`. **X-UI / Marzban пока не поддерживают AWG 2.0 официально** (verified май 2026).

#### Codex effort estimate

- Integration only (без production hardening): **2-3 engineer-weeks calendar** (~1 неделя интенсивной фазы Claude Code).
- Full quality (включая crash isolation, real-device memory test, lifecycle race tests, reconnect policy, CI prebuild artifact strategy): **5-7 engineer-weeks calendar** (~2-2.5 недели Claude Code).

### User decision 2026-05-14

«**Давай отложим амнезию вообще на версию 2 или позднее.**»

## Что входит в cancellation scope

### Удаляется из MVP

| Item | Original scope | Status |
|---|---|---|
| **PROTO-07 AmneziaWG 2.0** | Phase 7b primary scope (через `amneziawg-apple` library) | → Out of Scope, v2.0+ backlog conditional |
| **DPI-04 random TCP/UDP delay** | Был запланирован как «свойство AWG junk packets» | → Out of Scope (sing-box не поддерживает random delay для не-AWG протоколов) |
| **Engine abstraction layer** | Архитектурный фундамент в `PacketTunnelKit/Engines/*` | → Не строим; архитектура остаётся mono-engine sing-box |
| **AmneziaWG `.conf` parser** | URI/файл импорт для AWG 2.0 | → Не реализуется в MVP |
| **`vpn://` Amnezia share format parser** | Опциональный для AWG | → Не реализуется в MVP |
| **AmneziaWG v1.5 backward-compat** | Был conditional на demand | → Out of Scope (полностью) |

### Не входит в cancellation (что остаётся)

- Phase 7a ✅ Closed как было (TUIC v5 + uTLS=random + tls.record_fragment + DPI-07 port diversity)
- 6 in-scope протоколов: VLESS+Reality, VLESS+TLS+Vision (handler покрывает обе формы), Trojan, Shadowsocks-2022, Hysteria2, TUIC v5
- Anti-DPI smart defaults (DPI-01 + DPI-02) применены к VLESS+TLS / Trojan где applicable
- Phase 8 (Rules Engine + Split tunneling) — следующая фаза, без изменений

## Что мы теряем

- **AmneziaWG 2.0** — один из 4-5 реально работающих в РФ май 2026 протоколов (по Codex deep research thread `019e26f2-...` + ACF April 2026 report).
- Часть аудитории, у которой **только** AmneziaWG-серверы (например пользователи Amnezia self-host панели) — не сможет импортировать.
- Возможность гибкости: если когда-то понадобится OpenVPN или другой движок — придётся делать engine abstraction с нуля (а не «расширяем существующее»).

## Что мы получаем

- **Архитектурная простота**: один PacketTunnelProvider extension, один sing-box runtime через libbox. Ноль multi-engine arbitration кода. Меньше surface для bugs.
- **No Go bridge dependency** в проекте — никаких manual `libwg-go.a` build chains, GOROOT patches, Go 1.26 reproducibility issues, CI prebuild artifact concerns.
- **Crash isolation сохранена**: один engine = одна failure domain. Не рискуем тем что Go panic убьёт работающие 6 протоколов.
- **NetworkExtension memory headroom**: ~50MB limit не съедается Go runtime + AWG state.
- **5-7 engineer-weeks** освобождено для Phase 8 (Rules Engine) и далее.

## Условие возврата AmneziaWG в roadmap

Возвращаемся к AmneziaWG только если выполняется ОДНО из условий:

1. **Реальные пользователи в TestFlight явно попросили** — 3+ независимых запроса с рабочими AWG 2.0 подписками (от Amnezia self-host либо community provider). Запросы должны быть подтверждены: вижу, что у них действительно есть рабочий AWG-сервер, не просто «хочу AmneziaWG потому что слышал».

2. **ТСПУ поломал текущий рабочий стек** (Reality / Hy2 / TUIC) настолько, что AmneziaWG становится критическим выходом. Это означает: 3+ TestFlight пользователей сообщают что Reality+Hy2+TUIC одновременно не работают в их регионе (например МТС / Билайн / Yota), и тестовый AWG сервер (можно self-host через `wiresock/amneziawg-install`) подтверждает что он проходит.

3. **v2.0 milestone** — в roadmap v2.0 (managed servers + биллинг — мажорное изменение бизнес-модели) есть бюджет на architectural фазы. AmneziaWG там можно сделать как часть «expanded protocol matrix».

При выполнении условия — отдельная Phase X (нумерация в момент возврата) с детальным execution планом по образцу cancelled Phase 7b плана:
- Spike-фаза для измерения memory + cold-start на реальном iOS hardware (Codex risk #2)
- Manual `libwg-go.a` build chain в Tuist + CI artifact strategy (Codex risk #1)
- Engine abstraction layer в `PacketTunnelKit/Engines/*` (Codex Q5 рекомендация — protocol-based, не switch-style как Amnezia)
- AWG 2.0 `.conf` parser + integration в `UniversalImportParser` + `ConfigImporter`
- Real-device UAT с self-hosted AWG 2.0 сервером

## Альтернативы для пользователей которые хотят AWG прямо сейчас

Если у тебя в TestFlight появился пользователь с AWG-only сервером и он не может ждать:

1. **Использовать другой клиент:** Amnezia VPN iOS app, AmneziaWG iOS app в AppStore (v2.0.0+), Hiddify-iOS (если поддерживает на их fork — не подтверждено upstream).
2. **Если у пользователя есть собственный VPS** где живёт AWG 2.0 server — попроси добавить второй inbound на том же VPS (например Trojan + AWG в одной панели). BBTB подключится через Trojan inbound.

## Phase 7 financials итог

| Phase | Status | Result |
|---|---|---|
| Phase 7a (v0.7.1) | ✅ Closed 2026-05-14 | TUIC v5 + uTLS=random + tls.record_fragment + DPI-07. iPhone UAT PASS на Trojan. |
| Phase 7b (v0.7.2) | ❌ Cancelled 2026-05-14 | AmneziaWG 2.0 + engine abstraction отложены до v2.0+. |
| **Phase 7 общий итог** | **✅ Closed** | **+1 protocol (TUIC v5) + anti-DPI smart defaults для всех TLS-протоколов**. 6 in-scope протоколов в MVP. |

## Related pages

- [[openvpn-deferral-2026]] — параллельное решение D-01 (Phase 7 discuss): PROTO-09 OpenVPN/TLS → Out of Scope
- [[wireguard-deferral-2026]] — параллельное решение D-02 (Phase 7 discuss): PROTO-06 plain WireGuard → Out of Scope
- [[anti-dpi-techniques]] — реальное состояние sing-box 1.13.x техник после Phase 7a (DPI-04 reframed как «AWG-only, не доступно в sing-box»)
- [[protocols-overview]] — финальный список 6 in-scope протоколов
- [[release-roadmap]] — версии v0.1 → v1.0
- [[security-gaps]] — R20 общее обоснование архитектурных решений Phase 7

## Source URLs (full list)

- amneziawg-apple repo: https://github.com/amnezia-vpn/amneziawg-apple
- amneziawg-apple commits 2026-02-20: https://github.com/amnezia-vpn/amneziawg-apple/commits/master/
- amneziawg-apple Package.swift: https://raw.githubusercontent.com/amnezia-vpn/amneziawg-apple/master/Package.swift
- amneziawg-apple WireGuardKit sources: https://github.com/amnezia-vpn/amneziawg-apple/tree/master/Sources/WireGuardKit
- amnezia-client iOS provider (multi-engine reference): https://github.com/amnezia-vpn/amnezia-client/tree/dev/client/platforms/ios
- AmneziaWG 2.0 self-host docs: https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/
- amneziawg-go (Go bridge): https://github.com/amnezia-vpn/amneziawg-go
- amneziawg-linux-kernel-module: https://github.com/amnezia-vpn/amneziawg-linux-kernel-module
- wiresock/amneziawg-install (community installer): https://github.com/wiresock/amneziawg-install
- ACF/FBK April 2026 internet report: https://fbk.info/files/acf-internet-report-EN.pdf
- Codex deep research thread Phase 7b: `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` (Codex GPT-5 architect, advisory mode, 2026-05-14)

*Decision logged 2026-05-14 после Phase 7a closure. CONTEXT.md cancellation note: `.planning/phases/07-anti-dpi-suite-wireguard-family/07-CONTEXT.md`. PROJECT.md: R20 (status updated to ✅ Phase 7 Closed).*
