# Phase 7: Anti-DPI suite + WireGuard family — Context

**Gathered:** 2026-05-14
**Status:** ✅ **Phase 7 fully Closed 2026-05-14** — Phase 7a executed + UAT PASS; Phase 7b ❌ **Cancelled** post-7a-closure.

**Discuss-phase output of `/gsd-discuss-phase 7` 2026-05-14, после deep research с Codex GPT-5 + WebSearch по статусу OpenVPN / WireGuard / AmneziaWG / anti-DPI техник в РФ под ТСПУ на май 2026.**

> ## ⚠️ Phase 7b Cancellation Note (post-execution amendment 2026-05-14)
>
> **Phase 7b** (Engine abstraction + AmneziaWG 2.0) **отменена** ПОСЛЕ Phase 7a closure 2026-05-14.
>
> **Rationale:** Codex deep research thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` показал реальную стоимость integration:
> - 5-7 engineer-weeks full quality (manual `libwg-go.a` build chain через Makefile + Go 1.26 patches GOROOT)
> - AWG 2.0 backward-incompat с v1.5 серверами (требует fresh keys)
> - Go runtime memory unknown на iOS 18 NetworkExtension 50MB limit
> - No crash isolation от Go panic (убивает весь PacketTunnelProvider)
> - X-UI / Marzban пока не поддерживают AWG 2.0 официально
>
> User decision 2026-05-14: «отложим амнезию вообще на версию 2 или позднее».
>
> **Что переносится в Out of Scope (v2.0+ conditional on demand):**
> - **PROTO-07 AmneziaWG 2.0** (был Phase 7b primary scope) → Out of Scope, см. `wiki/amneziawg-deferral-2026.md`
> - **DPI-04 random TCP/UDP delay** (был AWG-bound — sing-box не поддерживает random delay для не-AWG протоколов) → Out of Scope
> - **Engine abstraction layer** (был нужен ради AWG; без второго движка не нужен) → не строим; архитектура остаётся mono-engine sing-box через `libbox.xcframework` v1.13.11
>
> **Условие возврата к AmneziaWG (см. `wiki/amneziawg-deferral-2026.md`):**
> 1. 3+ независимых TestFlight запроса с рабочими AWG 2.0 подписками, ИЛИ
> 2. ТСПУ поломал текущий рабочий стек (Reality / Hy2 / TUIC), ИЛИ
> 3. v2.0 milestone бюджет на architectural фазы (managed servers + биллинг)
>
> **Финал Phase 7:** только Phase 7a сделано. См. `07a-Final-SUMMARY.md`. Decisions D-03 + часть D-04 ниже отражают **изначальную** структуру discuss-phase до cancellation; это namespace-correct для исторической ссылки на reasoning, но не реализованный план.

<domain>
## Phase Boundary

Phase 7 закрывает оставшиеся протоколы спецификации **в формате реальности РФ-2026** (см. `<specifics>` ниже — deep research показал, что 2 из 4 запланированных протоколов в РФ 2026 не работают). Версия фазы — **v0.7**, разделена на два под-релиза:

### Phase 7a (v0.7.1) — sing-box-protocols + anti-DPI suite

**Scope:**
1. **TUIC v5 (PROTO-08)** — новый sing-box outbound `type: "tuic"`. Поля: `uuid`, `password`, TLS, QUIC, `congestion_control` (cubic/new_reno/bbr), `udp_relay_mode` (native/quic). Effort: **Short**. По образцу Phase 4 Hysteria2 handler.
2. **Anti-DPI smart defaults в sing-box outbounds:**
   - **DPI-01 uTLS random**: `tls.utls.fingerprint = "random"` — автоматически для всех TLS-протоколов (VLESS+Reality, VLESS+Vision, VLESS+TLS, Trojan, TUIC v5). Заменяет текущий hardcoded `chrome` fallback.
   - **DPI-02 TLS ClientHello fragmentation**: `tls.fragment = true` + (опц.) `tls.record_fragment` — автоматически для **VLESS+TLS / Trojan / TUIC v5** (НЕ для Reality/Vision — там собственный XTLS-механизм поверх TLS).
   - **DPI-05 Mux** (`multiplex.protocol = smux/yamux/h2mux` + `multiplex.enabled`): инфраструктура парсинга и handler-support для **VLESS+TLS / Trojan / Shadowsocks-2022**. Default: **off** (mux ломает Vision/Reality, не нужен для TUIC/Hy2 — там QUIC уже multiplex). Включается только если URI указывает `mux=true` или Clash YAML `smux: enabled: true`.
   - **DPI-03 packet padding** реализуется как `multiplex.padding = true` ТОЛЬКО когда mux включён per-server. Это `<deferred>` для глобального default — поскольку mux off-by-default, padding де-факто тоже off.
   - **DPI-07 разные порты**: уже работает — URI-парсеры принимают любой порт. Документируем явно в `wiki/anti-dpi-techniques.md` что 443/80/8443/2096 — норма, не feature-add.
3. **URI overrides** — если URI содержит `fp=chrome` / `fragment=false` / `mux=true` etc, эти параметры **переопределяют smart defaults** (URI = sole source of truth когда указан явно).

**НЕ в скоупе 7a:**
- WireGuard plain (PROTO-06) — Out of Scope (см. D-02 в `<decisions>`).
- AmneziaWG (PROTO-07) — Phase 7b.
- OpenVPN/TLS (PROTO-09) — Out of Scope (см. D-01).
- DPI-04 random TCP/UDP delay — не доступно в sing-box, переезжает в Phase 7b как свойство AmneziaWG junk packets.

### Phase 7b (v0.7.2) — Engine abstraction + AmneziaWG 2.0

**Scope:**
1. **Engine abstraction layer** — first multi-engine integration в проекте. Архитектурно: один `NEPacketTunnelProvider` extension, внутри runtime-выбор активного engine. Sing-box и AmneziaWG живут side-by-side; каждый эксклюзивно владеет `packetFlow` когда активен. Это «фундамент для будущих движков» — bias-toward-scalability per project rule. Конкретный паттерн (один extension vs два, как arbitrate) — для phase-researcher / planner определить, но **направление = один extension с engine selection**, не два extension.
2. **AmneziaWG 2.0 (PROTO-07)** — через `amneziawg-apple` SwiftPM library (репо: `github.com/amnezia-vpn/amneziawg-apple`, лицензия MIT, наследует от wireguard-apple). Используем библиотеку как vendored SwiftPM dependency либо extracted Swift wrapper.
   - **Версия:** только AmneziaWG 2.0 (выпущена 23-25 марта 2026). НЕ back-compat с v1/v1.5; v1.5-support — только при реальном demand в TestFlight (D-03 в `<decisions>`).
   - **Параметры:** S1-S4, H1-H4 (с range), I1-I5, Jc/Jmin/Jmax (junk packets) — все из v2 спеки.
   - **DPI-04 random delay** автоматически получается из junk packets (`Jc/Jmin/Jmax`) — это **свойство AmneziaWG**, не отдельное требование sing-box.
3. **URI / config-import** для AWG 2.0:
   - Стандартный `.conf` файл (WireGuard-classic format) с дополнительной секцией `[Interface]` параметров S1-S4, H1-H4, I1-I5, Jc/Jmin/Jmax.
   - `vpn://` Amnezia format — добавить позже если будет реальный demand.
   - Через `ConfigImporter` (Phase 2 archive) — расширение `UniversalImportParser` на детектирование `.conf` content.

**НЕ в скоупе 7b:**
- WireGuard plain `.conf` import — Out of Scope (см. D-02).
- AmneziaWG v1/v1.5 — Out of Scope для MVP; conditional на demand.

### Релизный поток

Phase 7a → close → TestFlight build v0.7.1 → iPhone UAT smoke (по образцу 6e) → ✓ closed → ROADMAP/STATE update → Phase 7b → close → TestFlight build v0.7.2 → iPhone UAT smoke → ✓ closed. **Два маленьких UAT-цикла**, не один большой. v0.7.1 работает как stable fallback если 7b затянется на архитектурной работе.

### Не в скоупе ВСЕЙ Phase 7

- **OpenVPN/TLS (PROTO-09)** — Out of Scope, v1.x backlog conditional on user demand. См. D-01.
- **WireGuard plain (PROTO-06)** — Out of Scope, v1.x backlog conditional on user demand. См. D-02.
- **AmneziaWG v1/v1.5** — Out of Scope для MVP; AWG 2.0 only.
- **UI toggles для anti-DPI** (DPI-06 CDN-фронтинг / DPI-08 cert pinning / DPI-09 uTLS picker) — Phase 10 (v0.10), unchanged.
- **DPI-04 random TCP/UDP delay** как отдельное требование — упразднено; переописать в REQUIREMENTS.md как «covered by AmneziaWG 2.0 junk packets in Phase 7b».
- **DPI-03 packet padding** как глобальный default — упразднено; работает только когда mux включён per-server.
- **Multi-port формат `host:port1,port2`** — backlog (carry from Phase 4 D-09 — Hysteria2 multi-port).
- **NET-12 active liveness probe** — carry from Phase 6c, остаётся carve-out для Phase 7-8 (не в Phase 7 scope).

</domain>

<decisions>
## Implementation Decisions

### D-01: OpenVPN/TLS (PROTO-09) → Out of Scope, v1.x backlog

**Decision:** удалить PROTO-09 из MVP. Перенести в `Out of Scope` (REQUIREMENTS.md), документировать решение в `wiki/openvpn-deferral-2026.md`. Условие возврата: реальные пользователи TestFlight предъявят рабочие `.ovpn` подписки.

**Rationale (deep research Codex GPT-5 + WebSearch 2026-05-14):**
- **Февраль 2026**: ТСПУ блокирует OpenVPN полностью (вместе с plain WireGuard) по behavioral fingerprinting.
- **OpenVPN+TLS на 443** не помогает — Windscribe CEO (TechRadar 2026-04-15): «trivially detected by DPI».
- **OpenVPN+Cloak** — Amnezia сам phased-out в Premium-продукте в 2026 («увеличивающаяся детектируемость»).
- **OpenVPN XOR** — GRFC обучилось детектировать «within hours» (FOSDEM 2026 slides).
- **Адопция в 2026**: только Amnezia self-host legacy. Hiddify / Marzban / 3X-UI / Lunaire / RyssVPN / FastSaveVPN — OpenVPN не в меню.
- **Engineering cost**: sing-box НЕ умеет OpenVPN. Единственный путь — Partout library (GPLv3 + commercial для AppStore), второй PacketTunnelProvider extension, Medium/Large effort (1-3 weeks calendar).
- **Аудитория**: 50 friends-and-family в РФ. Реалистично — все они уже на VLESS+Reality / Hysteria2 / SS-2022.

**User-visible loss:** ноль для РФ-аудитории. Совместимость с `.ovpn` подписками от non-РФ серверов — нишевая, conditional на demand.

**Roadmap impact:** Phase 7 success criteria #1 «все 9 протоколов» → «все 7 протоколов работающих в РФ 2026» (VLESS+Reality, VLESS+Vision, VLESS+TLS, Trojan, SS-2022, Hysteria2, TUIC v5, AmneziaWG 2.0). Phase 12 Global DoD аналогично.

### D-02: WireGuard plain (PROTO-06) → Out of Scope, v1.x backlog

**Decision:** удалить PROTO-06 из MVP. Перенести в `Out of Scope`. Документировать в `wiki/wireguard-deferral-2026.md`. Условие возврата: спрос на `.conf` файлы от non-РФ WG-серверов в TestFlight.

**Rationale (deep research 2026-05-14):**
- **Лето 2025**: Роскомнадзор закрыл «неидентифицированный UDP» практически полностью (TechRadar interview с Mazay Banzaev / Amnezia 2026-01-24). WG-on-443/UDP не помогает.
- **Декабрь 2025**: ТСПУ behavioral fingerprinting — WireGuard ловится по фиксированному handshake.
- **Февраль 2026**: WireGuard заблокирован полностью.
- **Март 2026 HRW**: 3 самых популярных VPN-протокола под блоком с декабря 2025 (один из них WG).
- **ACF report April 2026**: «standard protocols including vanilla WireGuard are not dependable building blocks in Russia».
- **Amnezia docs**: WG имеет фиксированные заголовки и предсказуемые размеры пакетов → детектируем DPI.

**User-visible loss:** ноль для anti-ТСПУ. Совместимость с non-РФ WG-серверами (корпоративный, личный) — нишевая.

**Roadmap impact:** Phase 7 success criteria #4 «WireGuard через WireGuardKit и AmneziaWG со своей обфускацией» → переписать как «AmneziaWG 2.0 + Hysteria2 + TUIC v5 покрывают UDP-семейство; plain WireGuard not applicable для РФ-аудитории».

### D-03: AmneziaWG 2.0 only — Phase 7b с engine abstraction

**Decision:** интегрировать **AmneziaWG 2.0** (не v1/v1.5) через `amneziawg-apple` SwiftPM library как второй engine в архитектуре. Phase 7b, отдельно от Phase 7a. v1.5 поддержка — только при реальном demand в TestFlight (conditional).

**Engine integration model:**
- Один `NEPacketTunnelProvider` extension.
- Внутри — engine abstraction: при connect выбирается active engine (sing-box или AmneziaWG-go) по типу протокола сервера.
- Каждый engine эксклюзивно владеет `packetFlow` когда активен; switch между протоколами требует disconnect → connect cycle (не hot-swap в первой итерации).
- **НЕ** второй PacketTunnelProvider extension — один extension с runtime engine selection. Это масштабируемое решение для будущих движков (Partout / kernel ports / любая будущая необходимость).

**Library:**
- Репо: `github.com/amnezia-vpn/amneziawg-apple` — форк wireguard-apple, MIT license, SwiftPM-ready, экспортирует `WireGuardKit` SwiftPM product, Go bridge через `amneziawg-go`.
- Подход: vendored SwiftPM dependency либо extracted Swift wrapper (researcher определит лучший вариант).
- Зрелость: репо это app-fork, не «чистая SDK» — потребуется минимальный SDK extraction work.
- License compat: MIT (наследует от wireguard-apple) — совместимо с нашим AGPL-3 ядром.

**Version policy:**
- **AWG 2.0 only** на MVP. v2 launched 23-25 марта 2026, **НЕ** back-compat с v1.5 (требует fresh keys).
- Lunaire / FastSaveVPN / Impuls Connect — уже маркетируют v2.0 в апреле-мае 2026.
- Amnezia Premium всё ещё на 1.5 — но Amnezia сам анонсирует apgrade в ближайшее время.
- Если реальные пользователи в TestFlight предъявят v1.5-серверы и захотят их использовать — добавить v1.5 как conditional в backlog.

**Rationale:**
- AmneziaWG 2.0 — один из 4-5 протоколов **реально работающих в РФ май 2026** (вместе с VLESS+Reality/XHTTP, Hysteria2/TUIC).
- Adopted by Lunaire (v2.0), FastSaveVPN (v1.5+), Firewalla router (beta март 2026), Keenetic (community).
- Engine abstraction = первый multi-engine integration → правильно сделать сейчас откроет дорогу будущим engine'ам без рефактора.

**Effort:** Codex оценка — 3-6 engineer-weeks calendar для quality integration (Go bridge build, SwiftPM/Xcode integration, AWG 2.0 config parsing, lifecycle/logging, DNS/routes/MTU, crash isolation, TestFlight diagnostics). С Claude Code — ~1.5-2 недели интенсивной фазы.

### D-04: Phasing — два отдельных TestFlight релиза v0.7.1 → v0.7.2

**Decision:** Phase 7a закрывается → отдельный TestFlight upload v0.7.1 → iPhone UAT smoke (по образцу 6e) → ✓ closed → ROADMAP/STATE update → начинается Phase 7b → закрывается → TestFlight v0.7.2 → UAT → ✓ closed.

**Rationale:**
- Два **маленьких** UAT-цикла на двух разных типах работы вместо одного огромного смешанного. Соответствует «качество > скорость».
- v0.7.1 работает как **stable fallback** если 7b затянется на architectural работе (engine abstraction — первый multi-engine integration, риск).
- Образец Phase 6c → 6d → 6e — у каждой свой UAT cycle.

### D-05: Anti-DPI smart defaults — uTLS=random + tls.fragment ON, mux OFF

**Decision:** в Phase 7a anti-DPI техники применяются **автоматически по умолчанию для применимых протоколов**, с возможностью URI override:

| Техника | Default | Применимо к | Не применимо к |
|---|---|---|---|
| **uTLS** | `random` | Все TLS-протоколы | — |
| **TLS fragmentation** | `record_fragment=true` (escalation `fragment=true` per-server) | VLESS+TLS, Trojan | VLESS+Reality, VLESS+Vision (XTLS), TUIC v5 (QUIC — sing-box поддерживает только ECH в QUIC) |
| **Mux** (smux/yamux/h2mux) | `disabled` | VLESS+TLS, Trojan, SS-2022 (если URI указывает) | Reality/Vision (ломает), TUIC/Hy2 (QUIC), WireGuard family |
| **Packet padding (mux-layer)** | `disabled` (зависит от mux) | Только когда mux включён | См. mux |

**URI override policy:** если URI содержит явный параметр (`fp=chrome`, `fragment=false`, `mux=true`, etc) — переопределяет smart default. Сервер-провайдер — sole source of truth когда указал параметр.

**Rationale:**
- Smart defaults дают user-visible anti-ТСПУ benefit «из коробки» без касания Advanced settings.
- uTLS=random безопасно — серверы обычно принимают любой fingerprint.
- TLS fragmentation добавляет ~5-10мс latency, но помогает с простыми DPI rules; для Reality/Vision выключен потому что XTLS свой механизм.
- Mux off-by-default — критично: mux ломает Vision/Reality (XTLS-mux incompatibility, well-documented).
- Готово к Phase 10 UI toggles (DPI-09 uTLS picker) — toggle перекрывает default через persisted setting.

### D-06: Carry-forward decisions от Phase 4 / 5 / 6c

**Архитектурные решения, которые применяются без обсуждения:**
- **Package-per-handler pattern** (Phase 4 CORE-02, Phase 5 CORE-03) — TUIC v5 handler оформляется по тому же шаблону что VLESSReality / VLESSTLS / Trojan / Shadowsocks / Hysteria2.
- **PoolBuilder = тонкий координатор**, `buildOutbound(parsed:transport:tag:)` static method per handler (Phase 5 D-14/D-15). TUIC получает свой `TUICHandler.buildOutbound`.
- **R1 invariant TLS strict** — единственное исключение `allowInsecure=1` для Hysteria2 (Phase 4 D-08). TUIC v5 — соответствует R1 без исключений.
- **TransportRegistry** (Phase 5 CORE-03) — TUIC использует свой transport (QUIC), не XHTTP/gRPC/WS/HTTPUpgrade. TransportRegistry может оставаться без расширения, или добавить `TUICTransportHandler` если планнер решит — discretion.
- **SwiftData lightweight migration** — TUIC может потребовать новые поля в `ParsedTUIC` (uuid, password, congestion_control, udp_relay_mode); добавляются как опциональные с auto-migration.
- **uTLS support уже частично есть** (Phase 4/5 — URI парсеры читают `fp=chrome`, sing-box JSON содержит `utls.fingerprint`). Phase 7 расширяет: парсеры читают `fp=random` и любой другой; ConfigBuilder при отсутствии указания применяет `random` (smart default).
- **R10 sing-box 1.13 DNS-hijack** (Phase 1) — действует для всех новых outbounds без изменений.
- **R18 Phase 6c on-demand semantics** (NEOnDemandRule + sliding session window) — действует для всех новых протоколов без изменений (auto-reconnect через iOS native).
- **DEC-06d-01..06** (Phase 6d architectural patterns — cold-start defer, XPC ≤2 trips, AsyncStream status polling, bounded probe concurrency, options["manualStart"] + ExternalVPNStopMarker, PerfSignposter) — действуют для всех новых path'ов; Phase 7b engine abstraction должна их сохранять.

### Claude's Discretion

Researcher / planner имеют discretion на:
- Точный sing-box JSON-шаблон для TUIC v5 (по образцу `SingBoxConfigTemplate.hysteria2.json`).
- Структура `AntiDPIConfig` (опции uTLS/fragment/mux) в `VPNCore/ParsedConfigs.swift` — либо отдельная struct, либо поля в каждом ParsedXxx.
- Порядок регистрации `TUICHandler.self` в `BBTB_iOSApp.swift` / `BBTB_macOSApp.swift` — по образцу Phase 4/5.
- Конкретный паттерн engine abstraction в Phase 7b — researcher должен изучить как Amnezia VPN iOS app + Hiddify-iOS делают multi-engine, и предложить минимально-инвазивный паттерн для нашего одного PacketTunnelProvider extension.
- Включение `wg://` парсера в Phase 7b (если AmneziaWG `.conf` парсер делается, плюс пять минут на `wg://` могут сэкономить будущий релиз) — но без UI exposure, чтобы не ввести пользователя в заблуждение «WG работает в РФ». Discretion: лучше не делать, чтобы избежать `wg://` URI попадания в subscription без явного маркера.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Планирование и требования (внутри проекта)
- `.planning/ROADMAP.md` § Phase 7 — scope + success criteria + carve-outs. **TODO post-discuss**: переписать Phase 7 entry на 7a/7b split, обновить success criteria (9 → 7 протоколов, AmneziaWG 2.0 explicit). Обработать через `/gsd-phase` или в рамках planning.
- `.planning/REQUIREMENTS.md` — PROTO-06..09, DPI-01..05, DPI-07 детали. **TODO post-discuss**: PROTO-09 + PROTO-06 → Out of Scope; DPI-04 reframe; DPI-03 reframe; добавить AWG 2.0 specifics в PROTO-07.
- `.planning/PROJECT.md` — core value, Decisions table. **TODO post-discuss**: добавить R20 (Phase 7 architectural decisions: OpenVPN+WG defer, AmneziaWG 2.0 engine abstraction, anti-DPI smart defaults).

### Спецификации форматов и upstream
- sing-box TUIC v5 outbound: `https://sing-box.sagernet.org/configuration/outbound/tuic/`
- sing-box WireGuard endpoint (для понимания почему PROTO-06 → Out of Scope — endpoint structure, не outbound): `https://sing-box.sagernet.org/configuration/endpoint/wireguard/` + migration `https://sing-box.sagernet.org/migration/#migrate-wireguard-outbound-to-endpoint`
- sing-box `tls.utls`, `tls.fragment`, `tls.record_fragment`: `https://sing-box.sagernet.org/configuration/shared/tls/`
- sing-box `multiplex` (smux/yamux/h2mux + padding): `https://sing-box.sagernet.org/configuration/shared/multiplex/`
- sing-box route action `tls_fragment`: `https://sing-box.sagernet.org/configuration/route/rule_action/`
- AmneziaWG docs: `https://docs.amnezia.org/documentation/amnezia-wg/`
- AmneziaWG 2.0 self-host docs: `https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/`
- AmneziaWG 2.0 launch blog (23-25 марта 2026): `https://amnezia.org/blog/amneziawg-2-0-available-for-self-hosted`
- AmneziaWG 2.0 Habr (русский): `https://habr.com/ru/companies/amnezia/articles/1014636/`
- `amneziawg-apple` репо: `https://github.com/amnezia-vpn/amneziawg-apple`
- `amneziawg-go` репо (Go backend): `https://github.com/amnezia-vpn/amneziawg-go`

### Существующая архитектура (точки расширения)
- `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift` — `AnyParsedConfig` enum (добавить `.tuic(ParsedTUIC)` и `.amneziaWG(ParsedAmneziaWG2)` cases); `ServerConfig` (`protocolID`, `isSupported`, `rawURI`, `outboundJSON`); `TransportConfig`.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — добавить TUIC URI detection (`tuic://`) и AmneziaWG `.conf` detection.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — координатор; добавить switch cases для TUIC и AmneziaWG 2.0.
- `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` — реестр; TUIC регистрируется по образцу Phase 4/5.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — `allowedOutboundTypes` whitelist (line 66-72) уже включает `"tuic"` и `"wireguard"` (готово для расширения). `expandConfigForTunnel` (R10 Phase 1) применяется без изменений.
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` + `BBTB/App/macOSApp/BBTB_macOSApp.swift` — startup hooks; добавить регистрацию `TUICHandler.self` в 7a и `AmneziaWG2Handler.self` в 7b.

### Образцы для новых компонентов (handler packages)
- `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift` + `ConfigBuilder.swift` — ближайший образец для TUIC (QUIC-based, R1 strict для TUIC).
- `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` — образец TLS handler с uTLS поддержкой (для расширения uTLS=random).
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` — образец TLS + transport overlay (для применения mux/fragment defaults).

### Архитектурные решения предыдущих фаз
- `.planning/phases/04-protocol-expansion/04-CONTEXT.md` § D-03/D-08/D-14 — patterns для protocol handler packages, R1 exception policy.
- `.planning/phases/05-transports/05-CONTEXT.md` § D-04/D-11/D-14/D-15 — TransportConfig pattern, TransportRegistry, PoolBuilder coordinator.
- `.planning/phases/06c-on-demand-migration/06C-CONTEXT.md` (если есть) либо ROADMAP § R18 — sliding session window + reactive UI driver.
- `.planning/phases/06d-performance-audit/06D-CONTEXT.md` либо ROADMAP § R19 — DEC-06d-01..06 patterns обязательны.
- `wiki/security-gaps.md` — R1 (TLS strict), R8 (libbox xcframework recipe), R10 (TUN inbound runtime expansion), R18 (NEOnDemandRule), R19 (DEC-06d-01..06).

### Wiki long-term memory (decision logs)
- `wiki/anti-dpi-techniques.md` — **обновить после Phase 7a closure**: какие техники реально есть в sing-box (uTLS=random / tls.fragment / multiplex.padding), какие нет (random delay → AmneziaWG only). Текущая страница описывает «как должно быть»; нужно обновить «как есть в коде».
- `wiki/protocols-overview.md` — **обновить**: список протоколов 9 → 8 (минус OpenVPN). Phase 1 «приоритетная группа» теряет WireGuard (Out of Scope, не v0.7 как было).
- `wiki/openvpn-deferral-2026.md` — **создать**: decision log по D-01 с research findings, dates, sources.
- `wiki/wireguard-deferral-2026.md` — **создать**: decision log по D-02.
- `wiki/amneziawg-integration.md` — **создать в Phase 7b**: decision log по D-03 с engine abstraction patterns, amneziawg-apple integration recipe.
- `wiki/release-roadmap.md` — **обновить**: v0.7 → v0.7.1 + v0.7.2 split, новые success criteria.
- `wiki/security-gaps.md` — **добавить R20**: Phase 7 architectural decisions (Russian-2026 reality + engine abstraction + smart defaults).

### Research artifacts (для phase-researcher)
- Codex GPT-5 advisory thread 1 (`019e26cb-cf49-78c3-af80-d437a5b22f28`, 2026-05-14): sing-box 1.13.x coverage + OpenVPN library state + WireGuard architecture + DPI techniques. **Cited in this CONTEXT.md.**
- Codex GPT-5 deep research thread 2 (`019e26d8-0397-7fa0-91b3-312e7e3e3ca9`, 2026-05-14): OpenVPN in Russia 2026, obfuscation survey, provider adoption, community stance, forward trajectory. **Источник для D-01.**
- Codex GPT-5 deep research thread 3 (`019e26f2-55e1-79d3-af9f-3d89fdc93647`, 2026-05-14): WireGuard / AmneziaWG status, AWG 2.0 details, amneziawg-apple library reality, engineering footprint, provider adoption. **Источник для D-02 и D-03.**
- WebSearch результаты 2026-05-14 (`Russia ТСПУ OpenVPN blocking 2025 2026`): подтверждение хронологии блокировок, Feb 2026 OpenVPN/WG full block, Dec 2025 behavioral fingerprinting, March 2026 ML-algorithms.

### Внешние referenced URLs (для исторической ссылки)
- Net4People bbs issues #274 / #490 / #546 / #589 — Russian VPN blocking timeline.
- HRW 2025-07-30 + 2026-03-12 reports — ТСПУ capabilities.
- ACF/FBK April 2026 internet report — protocol viability.
- TechRadar Mazay Banzaev interview 2026-01-24 + Amnezia review 2026.
- RKS Global censorship review 2024.
- FOSDEM 2026 Russia circumvention slides.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

**Для Phase 7a (TUIC + anti-DPI):**
- **Package-per-handler pattern** уже отработан 5 раз (VLESSReality, VLESSTLS, Trojan, Shadowsocks, Hysteria2). TUIC handler = 6-я итерация, нулевой риск архитектуры.
- **`PoolBuilder.buildSingBoxJSON`** — координатор готов; добавить case `.tuic` в switch (одна строка).
- **`SingBoxConfigLoader.allowedOutboundTypes`** уже включает `"tuic"` и `"wireguard"` в whitelist (file:66-72) — Phase 7a не требует расширения whitelist для TUIC.
- **uTLS infrastructure**: URI парсеры (`VLESSURIParser`, `TrojanURIParser`) уже читают `fp=`. sing-box JSON templates содержат `tls.utls.fingerprint`. Phase 7a меняет default-логику с hardcoded `chrome` на `random` — точечная правка ConfigBuilder'ов всех TLS handler'ов.
- **TransportConfig** (Phase 5) — TUIC использует QUIC transport, не из списка XHTTP/gRPC/WS/HTTPUpgrade. Можно либо расширить TransportConfig новым case `quic(server_name:)`, либо TUIC handler hardcoded QUIC в `buildOutbound` (discretion).

**Для Phase 7b (engine abstraction + AmneziaWG):**
- **`NEPacketTunnelProvider` extension** — один существующий target (`PacketTunnel/`). Engine abstraction делается внутри без второго extension.
- **`SingBoxBridge` / `LibboxBootstrap`** (`PacketTunnelKit`) — текущий engine driver; Phase 7b добавляет рядом `AmneziaWGBridge` через `amneziawg-go` Go bindings.
- **`ConfigImporter` (Phase 2/3)** + `UniversalImportParser` — точка расширения для `.conf` файла AmneziaWG 2.0. `multilineText` import source уже существует.

### Established Patterns

- **R1 invariant TLS strict** — TUIC v5 + AmneziaWG 2.0 соответствуют без исключений. Hysteria2 `allowInsecure` остаётся единственным исключением (Phase 4 D-08).
- **SwiftData lightweight migration** — применялась 5 раз; TUIC может потребовать `ParsedTUIC` поля; AmneziaWG потребует `ParsedAmneziaWG2` структуру с массивом param dictionaries (S1-S4, H1-H4, I1-I5, Jc/Jmin/Jmax).
- **DEC-06d-01..06** (Phase 6d performance patterns) — обязательны для всего нового кода. Engine abstraction должна сохранять XPC ≤2 trips, cold-start defer, AsyncStream status polling.
- **R18 Phase 6c (NEOnDemandRule + sliding session window)** — для обоих новых протоколов через iOS native `NEOnDemandRuleConnect.any`. AmneziaWG engine должен корректно вести себя в `NEVPNStatus` lifecycle.

### Integration Points

**Phase 7a:**
- `VPNCore/ParsedConfigs.swift` → новый case `.tuic(ParsedTUIC)`; (опционально) `AntiDPIConfig` struct.
- `ConfigParser/UniversalImportParser.swift` → TUIC URI detection branch.
- `ConfigParser/TUICURIParser.swift` (new file) → парсер `tuic://uuid:password@host:port?congestion_control=bbr&udp_relay_mode=native#name`.
- `ConfigParser/PoolBuilder.swift` → switch case `.tuic`.
- `ConfigParser/ClashYAMLParser.swift` → mapping `tuic` → ParsedTUIC.
- `Protocols/TUIC/` (new package) → `TUICHandler.swift` + `ConfigBuilder.swift` + `Resources/SingBoxConfigTemplate.tuic.json` + Tests.
- Anti-DPI: правка `Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` + `Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` + `Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift` — применить smart defaults (uTLS=random, tls.fragment ON, mux infra).
- `BBTB_iOSApp.swift` + `BBTB_macOSApp.swift` → регистрация `TUICHandler.self`.

**Phase 7b:**
- `PacketTunnelKit/Sources/PacketTunnelKit/EngineAbstraction.swift` (new) → `protocol VPNEngine` + `SingBoxEngine` (wrapping existing) + `AmneziaWG2Engine`.
- `PacketTunnelKit/Sources/PacketTunnelKit/AmneziaWGBridge/` (new) → Go bindings + Swift wrappers.
- `Protocols/AmneziaWG2/` (new package) → `AmneziaWG2Handler` + `ConfigBuilder` (выдаёт не sing-box JSON, а нативную AWG конфигурацию для AmneziaWGBridge) + Tests.
- `ConfigParser/AmneziaWG2ConfFileParser.swift` (new) → парсер `.conf` файлов с extended [Interface] секцией.
- `VPNCore/ParsedConfigs.swift` → `case .amneziaWG2(ParsedAmneziaWG2)`.
- `BBTB_iOSApp.swift` + `BBTB_macOSApp.swift` → регистрация `AmneziaWG2Handler.self`.

</code_context>

<specifics>
## Specific Ideas

### User-cited research принципы
- **«Качество > скорость»** — две отдельные UAT-фазы 7a и 7b вместо одной смешанной. AmneziaWG только v2.0 (не пытаемся покрыть две версии сразу).
- **«Масштабируемость на 20+ протоколов»** — engine abstraction в Phase 7b делается явно, как фундамент. Решение «один extension с runtime engine selection» а не «два extension» — для будущих движков.
- **«Подробное объяснение в простых словах»** — research findings transcribed inline в этом документе (даты, провайдеры, конкретика) чтобы downstream агенты понимали почему PROTO-06/09 → Out of Scope, не просто «было решено».

### Research findings, ключевые точки (sourced)
- **ТСПУ хронология блокировок:** OpenVPN/WG mass-block с 2023-08; mobile-level full с 2024-05; protocol-blocking since 2025-12; OpenVPN+WG полная блокировка 2026-02; ML-fingerprinting 2026-03.
- **AmneziaWG 2.0** — выпущен 23-25 марта 2026 как ответ на ТСПУ 2025-12 upgrade. AppStore app v2.0.0 — 2026-01-16 (early access).
- **Hiddify / Marzban / 3X-UI** — НЕ поддерживают AmneziaWG upstream (sing-box-based, feature request closed «not planned»).
- **Реальная адопция AWG 2.0 в РФ:** Lunaire (apr-may 2026), FastSaveVPN, Impuls Connect (v1.5+), Firewalla router (beta март 2026).
- **Working protocols в РФ май 2026** (по WebSearch + ACF report): VLESS+Reality, AmneziaWG 2.0, V2Ray/XRay, Hysteria2 — 4-5 протоколов. Plain WG, OpenVPN, L2TP, SOCKS5 — заблокированы behaviorally.

### Sing-box configuration ground truth (Codex Q1+Q4)
- **TUIC v5 outbound** — `type: "tuic"`, full support: uuid/password/TLS/QUIC/congestion_control (cubic/new_reno/bbr)/udp_relay_mode (native/quic)/udp_over_stream (conflicts с udp_relay_mode).
- **uTLS random** — `tls.utls.fingerprint = "random"` или `"randomized"` — supported.
- **TLS fragmentation** — outbound `tls.fragment`/`tls.fragment_fallback_delay`/`tls.record_fragment`; route action `tls_fragment`. Caveat: «for simple plaintext matching firewalls» per sing-box docs.
- **Multiplex padding** — `multiplex.padding = true`. Protocols smux/yamux/h2mux. Только для outbound-protocols (VLESS/Trojan/SS), не для TUIC/Hy2/WG.
- **DPI-04 random delay** — НЕ доступно в sing-box. Не путать с AmneziaWG junk packets (Jc/Jmin/Jmax) — те реализуются в AWG engine, не в sing-box.

### Engine abstraction precedent (Phase 7b context)
- **Amnezia VPN iOS app** — open-source, использует amneziawg-apple. Можно изучить multi-engine pattern (Amnezia поддерживает OpenVPN + AmneziaWG + WireGuard + XRay в одной app).
- **Hiddify-iOS** — sing-box-only, не multi-engine pattern. Не подходит как образец.
- **Outline iOS** — Shadowsocks-only, не multi-engine.
- Researcher должен изучить Amnezia VPN iOS source и предложить минимально-инвазивный паттерн для нашего одного PacketTunnelProvider.

</specifics>

<deferred>
## Deferred Ideas

### Перенесено в Out of Scope (REQUIREMENTS.md, conditional на demand)
- **PROTO-06 WireGuard plain** — ТСПУ блокирует с 2026-02, замещён AmneziaWG 2.0 для anti-ТСПУ.
- **PROTO-09 OpenVPN/TLS** — ТСПУ блокирует полностью, market shifted away, single-vendor (Amnezia) legacy.
- **AmneziaWG v1/v1.5** — back-compat path; добавляется только при реальном TestFlight demand.

### Перенесено в свойство другого протокола / удалено
- **DPI-04 random TCP/UDP delay** как отдельное требование — упразднено. Reframe в REQUIREMENTS.md как «covered by AmneziaWG 2.0 junk packets (Jc/Jmin/Jmax) in Phase 7b».
- **DPI-03 packet padding global** — упразднено как глобальный default. Reframe как «mux-layer padding, доступно когда mux включён per-server в URI».

### Backlog / future phases
- **`vpn://` Amnezia client URI format** — для AmneziaWG 2.0 alongside `.conf`. Backlog Phase 7b если планнер найдёт легко, иначе позже.
- **`wg://` URI парсер** — НЕ делаем в Phase 7 даже как разработческая утилита: введёт пользователя в заблуждение что WG работает в РФ. Если когда-то нужно — отдельным backlog item conditional на возврат PROTO-06.
- **Multi-engine hot-swap** — switch между протоколами в одном connect cycle без disconnect/connect. Phase 7b делает только cold-swap (disconnect → choose new server → connect). Hot-swap — future если будет UX-pain в TestFlight.
- **AmneziaWG router/Keenetic integration** — приходит «бесплатно» как сторона server-side; client отдельно не реализует.
- **CDN-фронтинг (DPI-06)** — Phase 10, без изменений.
- **Cert pinning (DPI-08)** — Phase 10, без изменений.
- **uTLS picker UI (DPI-09)** — Phase 10, без изменений; в Phase 7a smart default = random готов к перекрытию через persisted setting.
- **NET-12 active liveness probe** — carry from Phase 6c, остаётся carve-out для Phase 7-8 (рекомендую Phase 8, не 7a/7b).
- **Multi-port формат для Hysteria2 / TUIC** (`host:port1,port2`) — carry from Phase 4 D-09. Backlog.
- **macOS-specific UAT replay** (5 scenarios) — carry from Phase 6e D-03 explicit defer. Phase 11/12.

</deferred>

---

*Phase: 7-anti-dpi-suite-wireguard-family*
*Context gathered: 2026-05-14*
*Discuss-phase method: deep research (Codex GPT-5 ×3 advisory threads + WebSearch май 2026)*
*Downstream: `/gsd-phase` (split 7a/7b в ROADMAP) → `/gsd-plan-phase 7a` → `/gsd-execute-phase 7a` → UAT → `/gsd-plan-phase 7b` → engine abstraction + AmneziaWG 2.0 → UAT*
