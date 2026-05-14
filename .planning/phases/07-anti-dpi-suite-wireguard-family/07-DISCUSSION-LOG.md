# Phase 7: Anti-DPI suite + WireGuard family — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `07-CONTEXT.md` — this log preserves the alternatives considered и research артефакты.

**Date:** 2026-05-14
**Phase:** 7-anti-dpi-suite-wireguard-family
**Mode:** default discuss-phase + multi-round Codex consultations + WebSearch deep research
**Areas discussed:** Phasing (7a vs 7b vs unified), OpenVPN scope, WireGuard/AmneziaWG engine, Anti-DPI defaults

---

## Pre-discussion: загрузка контекста

Загружены: `.planning/PROJECT.md`, `.planning/STATE.md`, `.planning/ROADMAP.md` § Phase 7, `.planning/REQUIREMENTS.md` (PROTO-06..09, DPI-01..05/07), `prompts/v2 § v0.7`, prior CONTEXT.md фаз 4 + 5, wiki: `anti-dpi-techniques.md` + `protocols-overview.md`. Codebase scout: `BBTB/Packages/Protocols/*`, `ProtocolRegistry`, `ConfigParser/ImportedServer.swift`+`ParsedConfigs.swift`, `PoolBuilder`, `BBTB_iOSApp.swift` + `BBTB_macOSApp.swift` (registration sites), `SingBoxConfigLoader.allowedOutboundTypes`.

Pattern carry-forward (без re-discussion):
- Package-per-handler + ProtocolRegistry (Phase 4 CORE-02).
- TransportRegistry + buildOutbound static (Phase 5 CORE-03/D-14/D-15).
- R1 invariant TLS strict, единственное исключение allowInsecure Hysteria2 (Phase 4 D-08).
- R10 sing-box 1.13 DNS-hijack (Phase 1).
- R18 NEOnDemandRule sliding window (Phase 6c).
- DEC-06d-01..06 performance patterns (Phase 6d).

---

## Round 1: User выбрал 4 серые зоны для deep-dive

Multi-select AskUserQuestion с 4 опциями. User выбрал ВСЕ ЧЕТЫРЕ:

| Зона | Selected |
|---|---|
| Фазирование — единая Phase 7 vs split 7a/7b | ✓ |
| OpenVPN/TLS — в scope или отложить | ✓ |
| WireGuard / AmneziaWG engine — sing-box vs native lib | ✓ |
| Anti-DPI defaults — глобально / per-server / ждём Phase 10 | ✓ |

7-я опция (URI parsers — какие форматы), 6-я (test infrastructure), 5-я (uTLS strategy) — попали в Claude's discretion / canonical refs.

---

## Codex consultation #1: техническая ground truth для всех 4 зон

**Thread:** `019e26cb-cf49-78c3-af80-d437a5b22f28` (Codex GPT-5 advisory).

**Запрос:** sing-box 1.13.x coverage (WG/AmneziaWG/TUIC), OpenVPN на Apple, WireGuardKit vs sing-box endpoint, DPI-01..05 sing-box options.

**Key findings (бэкгрунд для всех последующих вопросов):**

| Факт | Источник |
|---|---|
| sing-box 1.13: WireGuard → endpoint (НЕ outbound). Не может быть в urltest pool | https://sing-box.sagernet.org/migration/#migrate-wireguard-outbound-to-endpoint |
| sing-box AmneziaWG outbound НЕ поддерживается, feature request closed "not planned" | https://github.com/SagerNet/sing-box/issues/3159 |
| sing-box TUIC v5 — type:tuic, full support | https://sing-box.sagernet.org/configuration/outbound/tuic/ |
| OpenVPNAdapter архивирован с 2022, Partout — modern path (GPLv3 + commercial для AppStore) | https://github.com/ss-abramchuk/OpenVPNAdapter + https://partout.io/license/ |
| uTLS random: tls.utls.fingerprint=random — supported, но docs warns «не для censorship resistance» | https://sing-box.sagernet.org/configuration/shared/tls/ |
| TLS fragmentation: tls.fragment + tls.record_fragment + route action tls_fragment | https://sing-box.sagernet.org/configuration/shared/tls/ |
| Packet padding: ТОЛЬКО mux-layer (multiplex.padding), не generic | https://sing-box.sagernet.org/configuration/shared/multiplex/ |
| Random TCP/UDP delay (DPI-04) — НЕТ в sing-box. Только AmneziaWG junk packets | (sing-box config index, не найдено) |
| Mux smux/yamux/h2mux — supported, НО несовместим с Vision/Reality (XTLS-mux conflict) | upstream community + AppFeatures |

---

## Round 2: OpenVPN scope — deep research

User не дал прямой ответ, попросил `углубленное исследование вместе с CODEX`.

### Codex consultation #2 (deep research mode)

**Thread:** `019e26d8-0397-7fa0-91b3-312e7e3e3ca9` (Codex GPT-5 + WebSearch).

**Запрос:** OpenVPN/TLS в России 2025-2026 — status, obfuscation techniques, market adoption, community stance, forward trajectory.

**Bottom line Codex:** Defer to v1.x. ТСПУ blocks OpenVPN behaviorally (since Feb 2026). Even OpenVPN+Cloak phased out from Amnezia Premium 2026. Engineering cost не оправдан.

### Параллельный WebSearch

Подтвердил Codex + добавил:
- 469 заблокированных VPN-сервисов к началу марта 2026 (рост 70% с октября 2025).
- Дек 2025 — ТСПУ behavioral fingerprinting; Feb 2026 — OpenVPN/WG full block.
- Март 2026 — ТСПУ ML-algorithms (2.3 млрд ₽ контракт).
- РКН задача: 92% VPN заблокировать к 2030.

### AskUserQuestion после research

| Option | Description | Selected |
|--------|-------------|----------|
| Убрать из MVP, в v1.x backlog по demand (Recommended) | Out of Scope с явным критерием возврата. Wiki decision log. | ✓ |
| Отложить в Phase 7c после 7a/7b | Active, отдельная фаза. Не рекомендую. | |
| Включить в Phase 7 вместе с WG-семейством | Не рекомендую. | |

**User's choice:** Убрать из MVP. **Decision saved as D-01.**

---

## Round 3: WireGuard / AmneziaWG — deep research

User снова попросил `углубленное исследование вместе с CODEX`.

### Codex consultation #3 (deep research mode)

**Thread:** `019e26f2-55e1-79d3-af9f-3d89fdc93647` (Codex GPT-5 + WebSearch).

**Запрос:** Plain WireGuard и AmneziaWG status в РФ 2026, AmneziaWG 2.0 specifics, Amnezia-apple library reality, engineering footprint, provider adoption.

**Bottom line Codex:**
- Plain WireGuard — drop. UDP в РФ closed Lehnen 2025, WG fixed-handshake детектируется DPI.
- AmneziaWG 2.0 — integrate (но не rushed). `amneziawg-apple` real, SwiftPM-ready, MIT license. Engine abstraction в одном PacketTunnelProvider extension. Effort: Medium/Large (3-6 engineer-weeks calendar).

**Конкретика AmneziaWG 2.0 (новая инфа):**
- Released 23-25 March 2026 (Amnezia blog + Habr).
- НЕ back-compat с v1/v1.5 (fresh keys).
- New: S3/S4, range support для H1-H4, I1-I5 custom signature packets.
- AppStore AmneziaWG app v2.0.0 — 16 января 2026.
- `amneziawg-apple` — fork wireguard-apple, MIT license, экспортирует WireGuardKit SwiftPM product, Go bridge через amneziawg-go.

**Provider adoption 2026:**
- ✅ Amnezia self-host + Premium (v1.5)
- ✅ Lunaire VPN (v2.0 marketing)
- ✅ FastSaveVPN, Impuls Connect
- ✅ Firewalla router beta (28 марта 2026)
- ❌ Hiddify / Marzban / 3X-UI (sing-box-based, no AWG upstream)

**Cat-and-mouse:** Amnezia сам признаёт периодические ТСПУ blocks AWG signatures — AWG 2.0 is the response.

### AskUserQuestion после research (две вопроса параллельно)

**Q1: WireGuard plain (PROTO-06) — что делаем?**

| Option | Description | Selected |
|--------|-------------|----------|
| Drop из MVP, в v1.x backlog (Recommended) | Out of Scope, AmneziaWG 2.0 покрывает WG-нишу. Wiki decision log. | ✓ |
| Import-compat only (sing-box endpoint, пометка «не для ТСПУ») | Минимум effort, но размытое user-promise. | |
| Интегрировать полноценно | Не рекомендую — плохой UX в РФ. | |

**User's choice:** Drop из MVP. **Decision saved as D-02.**

**Q2: AmneziaWG (PROTO-07) — версия и фазирование?**

| Option | Description | Selected |
|--------|-------------|----------|
| AWG 2.0 only, отдельная Phase 7b (Recommended) | v2.0 через amneziawg-apple + engine abstraction. v1.5 conditional. | ✓ |
| AWG 2.0 + v1.5 в одной Phase 7b | Поддерживаем обе версии — больше серверов, но 2 config-формата. | |
| Отложить AmneziaWG в v1.x backlog | Не рекомендую — теряем главный «убийца ТСПУ». | |

**User's choice:** AWG 2.0 only, Phase 7b. **Decision saved as D-03.**

---

## Round 4: Phasing — релизный поток

| Option | Description | Selected |
|--------|-------------|----------|
| Два отдельных релиза v0.7.1 → v0.7.2 (Recommended) | 7a → TestFlight → UAT → ✓ closed → 7b → TestFlight → UAT → ✓ closed. Два маленьких UAT. v0.7.1 как stable fallback если 7b затянется. | ✓ |
| Один релиз v0.7.0 в конце | 7a + 7b → один большой UAT. Хуже изоляция проблем. | |

**User's choice:** Два релиза. **Decision saved as D-04.**

---

## Round 5: Anti-DPI defaults

После обсуждения user-care-about (visible поведение «из коробки»):

| Option | Description | Selected |
|--------|-------------|----------|
| Smart defaults (uTLS=random + frag, mux off) (Recommended) | uTLS=random автоматически, tls.fragment для VLESS+TLS/Trojan/TUIC, mux off (ломает Vision/Reality). URI overrides всегда. | ✓ |
| Conservative — только из URI/Clash params | Безопасно, но Phase 7 без user-visible value в РФ. | |
| All-off, ждём UI toggles в Phase 10 | Phase 7 без user-visible value до v0.10. | |

**User's choice:** Smart defaults. **Decision saved as D-05.**

---

## Claude's Discretion (по user instructions «scaling-friendly + quality > speed»)

- **TUIC v5 handler structure** — по образцу Hysteria2 (Phase 4). sing-box JSON template + ConfigBuilder + URI parser + handler registration.
- **AntiDPIConfig struct в VPNCore** — либо отдельная struct, либо поля в каждом ParsedXxx. Researcher / planner определит.
- **Engine abstraction pattern в Phase 7b** — researcher изучает Amnezia VPN iOS source (open-source) для minimally-invasive паттерна. Цель: один PacketTunnelProvider extension, runtime engine selection.
- **AmneziaWG `.conf` parser** — стандартный WireGuard format + extended [Interface] секция с S/H/I/J параметрами. По образцу TrojanURIParser.
- **`vpn://` Amnezia client URI format** — backlog Phase 7b если researcher найдёт легко, иначе позже.
- **`wg://` URI парсер** — НЕ делаем в Phase 7 (введёт пользователя в заблуждение про РФ-blocking plain WG).
- **DPI-04 reframe в REQUIREMENTS.md** — «covered by AmneziaWG 2.0 junk packets in Phase 7b», не отдельное требование.
- **DPI-03 reframe в REQUIREMENTS.md** — «mux-layer padding, available together with DPI-05 when mux enabled per-server».
- **TUIC test infrastructure** — unit tests на config-generation + один merged test server (если/когда появится). По образцу Phase 4 — без device UAT per protocol.

---

## Deferred Ideas (carry-forward к будущим фазам)

- **OpenVPN/TLS (PROTO-09)** — v1.x backlog conditional на TestFlight demand. Wiki decision log: `wiki/openvpn-deferral-2026.md`.
- **WireGuard plain (PROTO-06)** — v1.x backlog conditional на non-RU WG-серверов demand. Wiki: `wiki/wireguard-deferral-2026.md`.
- **AmneziaWG v1/v1.5** — conditional на demand в TestFlight.
- **DPI-06 CDN-фронтинг, DPI-08 cert pinning, DPI-09 uTLS picker UI** — Phase 10 (v0.10), без изменений.
- **Multi-port формат `host:port1,port2`** — backlog (carry from Phase 4 D-09).
- **NET-12 active liveness probe** — carry from Phase 6c, для Phase 8 (не 7a/7b).
- **Multi-engine hot-swap** — future, после Phase 7b если будет UX-pain.
- **`wg://` URI парсер** — НЕ Phase 7. Conditional на возврат PROTO-06.
- **`vpn://` Amnezia URI format** — Phase 7b discretion либо backlog.
- **macOS UAT replay** — carry from Phase 6e D-03, для Phase 11/12.

---

## Research artifacts (Codex thread references)

| Thread ID | Mode | Topic | Used for |
|---|---|---|---|
| `019e26cb-cf49-78c3-af80-d437a5b22f28` | Advisory | sing-box 1.13.x ground truth, OpenVPN library state, DPI techniques | Background context для всех 4 зон |
| `019e26d8-0397-7fa0-91b3-312e7e3e3ca9` | Deep research | OpenVPN в РФ 2026 | D-01 rationale |
| `019e26f2-55e1-79d3-af9f-3d89fdc93647` | Deep research | WireGuard / AmneziaWG в РФ 2026 + amneziawg-apple integration | D-02 и D-03 rationale |

WebSearch 2026-05-14: подтверждение ТСПУ хронологии блокировок (Roskomsvoboda, ACF, HRW, TechRadar, FOSDEM 2026 slides).

---

*Discussion completed: 2026-05-14. Ready для plan-phase 7a.*
