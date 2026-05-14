# Roadmap: BBTB

**Source of truth:** `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` `<release_roadmap>` section.

**Phases:** 12 (one per release v0.1–v0.12 + v1.0 merged into Phase 12).
**Mode:** Each phase is `mvp` — vertical slice that compiles and tests end-to-end.

Phase numbering follows the release numbering. Sub-phases are not used at this granularity.

---

### Phase 1: Foundation ✓ Complete 2026-05-11
**Goal:** Минимально жизнеспособная сборка с VLESS+Vision+Reality, kill switch и базовой архитектурой SwiftPM. Версия — **v0.1**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** CORE-01, CORE-02, CORE-04, CORE-06, CORE-07, CORE-08, CORE-10, SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SEC-06, KILL-01, KILL-02, PROTO-01, IMP-01, UX-02, UX-03, UX-07, TELEM-01, LOC-01, DIST-01, DIST-02
**Success Criteria:**
1. На реальном iPhone и MacBook можно импортировать VLESS+Reality конфиг через буфер обмена → подключиться по одной кнопке → IP меняется на проверке `https://api.ipify.org`.
2. При разрыве туннеля kill switch блокирует весь трафик до восстановления или ручного отключения.
3. Security review passed: тест-приложение не находит отвечающих SOCKS-портов на `127.0.0.1` нашего PacketTunnelProvider; gRPC API sing-box отключён; `P2P=false` на интерфейсе (R1 + R6).
4. В release-режиме нет debug-логов в консоли.
5. Базовый SwiftPM-скелет соответствует структуре из `prompts/v2 <swift_package_layout>`: модули для VPNCore, ProtocolRegistry, ProtocolEngine, Protocols, KillSwitch созданы и компилируются.

---

### Phase 2: Trojan + Import flow ✓ Complete 2026-05-12
**Goal:** Расширить v0.1 до universal-парсера всех трёх форматов раздачи ссылок (subscription URL / multi-line plain-text URI / JSON endpoint), второго протокола (Trojan-TCP/TLS + Trojan-WS/TLS), auto-fallback через sing-box `urltest` outbound, toggle отключения kill switch. Версия — **v0.2**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** PROTO-02, PROTO-10, IMP-02, KILL-03 + foundation: IMP-04 (partial — universal URI parser + subscription URL fetch), IMP-05 (partial — все URI-схемы распознаются), TRANSP-03 (partial — WebSocket transport для Trojan), SRV-* (foundation — SwiftData массив `ServerConfig` с `isSupported` + `subscriptionURL` полями)
**Scope shifts (vs original ROADMAP, согласованы в `/gsd-discuss-phase 2` 2026-05-11):**
- IMP-03 (file picker) → **переезжает в Phase 11** (UX-01 onboarding) как угловая ссылка «У меня уже есть конфиг файл».
- IMP-04/IMP-05/TRANSP-03/SRV-* в Phase 2 — только foundation (parser + storage). UI выбора серверов / pull-to-refresh / multi-subscription / полная поддержка Outline+Clash YAML — остаются в Phase 3-4.
**Success Criteria:**
1. Пользователь импортирует конфигурацию через буфер обмена (URI / multi-line блок URI / subscription URL / JSON endpoint URL) или QR-код. Все три формата раздачи ссылок принимаются. Неподдержанные протоколы в подписке (например Shadowsocks в v0.2) парсятся с флагом `isSupported=false` без отказа всего импорта.
2. При блокировке VLESS+Reality sing-box `urltest` outbound автоматически переключается на Trojan (или другой работающий outbound из пула) без действий пользователя.
3. Trojan handler (PROTO-02) подключается на TCP+TLS и WebSocket+TLS транспорте.
4. Toggle «Kill Switch» появляется в Settings page → раздел «Безопасность», применяется при следующем connect (баннер «Переподключитесь для применения»).
5. Камера запрашивает permission корректно на iOS (NSCameraUsageDescription) и macOS.
6. Главный экран переписан под новый layout: top bar (≡ слева → Settings, + справа → меню QR/буфер), idle = timer → status pill → power-кнопка → server-line; empty = центральная карточка с двумя кнопками.
7. SwiftData массив `ServerConfig` — Phase 1 singleton успешно мигрирован.
8. Unit-test suite зелёный (ConfigParser форматы, Trojan template, urltest config builder, kill switch параметризация).

---

### Phase 3: Server management ✓ Complete 2026-05-12
**Goal:** Управление серверами — auto-select по latency, список серверов с pull-to-refresh, поддержка нескольких подписок. Версия — **v0.3**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** SRV-01, SRV-02, SRV-03, UX-04
**Success Criteria:**
1. Список серверов обновляется по pull-to-refresh, latency пересчитывается. ✓
2. Auto-select переключает на сервер с наименьшим latency + минимальными потерями пакетов. ✓
3. При подключении timer считает с момента установки туннеля. ✓
4. Если подписки несколько — секции в списке. ✓
**UAT**: T1-T8 PASS 2026-05-12. 3 бага закрыты: SwiftData UUID? predicate, SNI rotation в identity, TunnelController disconnect race. Подробности — `wiki/server-management.md`.

---

### Phase 4: Protocol expansion ✓ Complete 2026-05-12
**Goal:** Добавить ещё 3 протокола (VLESS+XTLS-Vision без Reality, Shadowsocks-2022, Hysteria2). Парсер URI-форматов уже работает с Phase 2 (foundation) — Phase 4 финализирует handler'ы для всех схем и полные subscription-форматы (Outline access keys, Clash YAML). Версия — **v0.4**.
**Mode:** mvp
**UI hint:** no
**Requirements:** PROTO-03, PROTO-04, PROTO-05, IMP-04 (finish — все URI handler'ы), IMP-05 (finish — Outline + Clash YAML)
**Success Criteria:**
1. Импортируется любой формат: `vless://`, `ss://`, `trojan://`, `hy2://`, subscription URL v2ray, Outline access keys.
2. Все 5 протоколов (Reality, Vision, SS-2022, Hysteria2, Trojan) подключаются на тестовых серверах.
3. ConfigParser написан с юнит-тестами для каждого формата.

**Plans:** 6 plans (waves 1-6)

Plans:
**Wave 1**
- [x] 04-01-PLAN.md — Wave 0 foundation: Yams 6.2.1 + AnyParsedConfig 5 cases + test scaffolds + 11 fixtures

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 04-02-PLAN.md — VLESS+TLS vertical slice (PROTO-03): VLESSURIParser D-02 + Protocols/VLESSTLS package + PoolBuilder branch

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 04-03-PLAN.md — Shadowsocks vertical slice (PROTO-04): ShadowsocksURIParser dual-decoder + Protocols/Shadowsocks + PoolBuilder branch

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 04-04-PLAN.md — Hysteria2 vertical slice (PROTO-05): D-08 R1 EXCEPTION + D-09 dual scheme + Protocols/Hysteria2 + R1 invariant test

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 04-05-PLAN.md — Clash YAML + universal routing finish (IMP-04, IMP-05): ClashYAMLParser + UniversalImportParser classify

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 04-06-PLAN.md — Integration: ConfigImporter 5-case switches + runIsSupportedUpgrade (D-14) + App registration + Tuist

**UAT:** Deferred to manual testing by user (--skip-uat). See 04-VALIDATION.md "Manual-Only Verifications" for test instructions.

---

### Phase 5: Transports
**Goal:** Финализация 4 транспортов поверх VLESS+TLS и Trojan (WebSocket уже partial в Phase 2 для Trojan), ручной выбор транспорта в ServerDetailView. Архитектурный refactor: shared `TransportConfig` enum (VPNCore) + `TransportRegistry` пакет (CORE-03) + per-protocol `buildOutbound` + PoolBuilder становится координатором. Версия — **v0.5**. (XHTTP/TRANSP-01 заморожен — sing-box upstream не поддерживает, см. 05-CONTEXT.md «Не в скоупе».)
**Mode:** mvp
**UI hint:** yes (ServerDetailView push from ServerListSheet chevron)
**Requirements:** CORE-03, TRANSP-02, TRANSP-03 (finish — расширить за пределы Trojan-WS), TRANSP-04, TRANSP-05
**Success Criteria:**
1. VLESS+TLS и Trojan работают поверх каждого из четырёх транспортов (gRPC, WebSocket, HTTP/2, HTTPUpgrade); TCP остаётся default.
2. `TransportRegistry` (CORE-03) регистрирует все 5 transport handler-ов (TCP + WS + HTTP + HTTPUpgrade + gRPC) в App startup; lookup by identifier работает.
3. В ServerDetailView (push от шеврона в ServerListSheet) пользователь может вручную выбрать транспорт; выбор persists в `ServerConfig.transportOverride` (SwiftData lightweight migration) и применяется при следующем connect.
4. R1 invariant (insecure=false для всех TLS блоков кроме Hy2 D-08 exception) сохраняется после refactor — invariant test PASSes.
5. ALPN h2-strip invariant для WS (Phase 2 W4) сохраняется в protocol package buildOutbound.

**Plans:** 8 plans (waves 1-8)

Plans:
**Wave 1**
- [ ] 05-01-PLAN.md — Wave 0 foundation: TransportConfig enum (VPNCore) + TransportRegistry package + TCPTransportHandler + TransportParamParser

**Wave 2** *(blocked on Wave 1 completion)*
- [ ] 05-02-PLAN.md — WebSocket vertical slice: ParsedVLESSTLS/ParsedTrojan migration + parser delegation + WSTransportHandler + WS tests/fixtures

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 05-03-PLAN.md — HTTP/2 transport: HTTPTransportHandler + 2 fixtures + 4 parser tests

**Wave 4** *(blocked on Wave 3 completion)*
- [ ] 05-04-PLAN.md — HTTPUpgrade transport: HTTPUpgradeTransportHandler (host as String, Pitfall 7) + 2 fixtures + 3 parser tests

**Wave 5** *(blocked on Wave 4 completion)*
- [ ] 05-05-PLAN.md — gRPC transport: GRPCTransportHandler (snake_case service_name, Pitfall 6) + 2 fixtures + 3 parser tests

**Wave 6** *(blocked on Wave 5 completion)*
- [ ] 05-06-PLAN.md — ParsedXxx types relocation: move ParsedVLESS/ParsedVLESSTLS/ParsedTrojan/ParsedShadowsocks/ParsedHysteria2 + AnyParsedConfig + UnsupportedReason from ConfigParser → VPNCore (устраняет cyclic dependency для Wave 7)

**Wave 7** *(blocked on Wave 6 completion)*
- [ ] 05-07-PLAN.md — Integration: per-protocol buildOutbound (5 protocol packages) + PoolBuilder coordinator + TransportOverride helper + App startup registration + ConfigImporter override stub

**Wave 8** *(blocked on Wave 7 completion)*
- [ ] 05-08-PLAN.md — UI + SwiftData: ServerConfig.transportOverride field + ServerDetailView + ServerDetailViewModel + TransportPicker + ServerListSheet chevron NavigationLink + ConfigImporter wires real cfg.transportOverride read (1 human-verify checkpoint)
---

### Phase 6: Network resilience
**Goal:** DNS-стратегия (DoH + bootstrap + whitelist), IPv6-туннелирование с fallback на блок, auto-reconnect, failover. Версия — **v0.6**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** NET-01, NET-02, NET-03, NET-04, NET-05, NET-06, NET-07, NET-08, NET-09, NET-10, NET-11
**Success Criteria:**
1. DNS leak-test пройден на iOS и macOS (через dnsleaktest.com и аналогичные).
2. IPv6 leak-test пройден (через ipv6-test.com).
3. Смена сети Wi-Fi ↔ LTE не приводит к утечкам трафика, реконнект автоматический.
4. Выход из sleep — реконнект происходит без вмешательства пользователя.
5. При падении сервера failover переключает на следующий из подписки.

**Note (2026-05-13):** UAT выявил 4 бага в текущей реализации auto-reconnect (custom state machine + NEVPNStatusDidChange observer): phantom reconnect на fresh install, phantom reconnect после import, Mach port exhaustion на iOS 26 (EXC_RESOURCE/PORT_SPACE краш), fighting с другими VPN-приложениями. Фиксы 1-3 закоммичены (`92028c2`). Баг #4 (other VPN takeover) и архитектурный долг — переносятся в **Phase 6c**.

---

### Phase 6c: On-demand reconnect migration
**Goal:** Заменить custom auto-reconnect machinery (ReconnectStateMachine + NEVPNStatusDidChange observer + NetworkReachability triggers + manual flag tracking) на iOS-нативный механизм `isOnDemandEnabled` + `NEOnDemandRule*`. Это устраняет целый класс багов (race conditions, XPC storm на iOS 26, конфликт с другими VPN-приложениями) и кладёт фундамент для будущих фич («always-on», «connect on untrusted Wi-Fi», per-SSID rules). Все Phase 6 success criteria сохраняются и проверяются повторно. Версия — **v0.6.1** (patch).
**Mode:** mvp
**UI hint:** minor (опциональная настройка «Auto-reconnect» в Settings)
**Requirements:** NET-08, NET-09, NET-10, NET-11 (re-validated via Apple-managed mechanism)
**Success Criteria:**
1. Смена сети Wi-Fi ↔ LTE — реконнект автоматический (carry-over из Phase 6, проверка через on-demand).
2. Выход из sleep на macOS — реконнект автоматический (carry-over).
3. **Активация другого VPN-приложения не приводит к "fight-back"** — наш профиль молчит, пока пользователь сам не активирует его обратно.
4. **На iOS 26+ нет EXC_RESOURCE/PORT_SPACE крашей** при длительной работе (>30 минут стабильной сессии).
5. Failover при падении сервера на начальном connect (через `SwiftDataFailoverProvider`) — сохраняется (не зависит от on-demand).
6. Tests: legacy `TunnelControllerStateTests` адаптированы / заменены; новые тесты покрывают on-demand rules конфигурацию.
7. ROADMAP-уровневая регрессия: всё Phase 1-6 success criteria продолжают выполняться (UAT smoke на iPhone iOS 26.5).

**Note:** Это remediation-фаза, не feature-добавка. Перенумерация Phase 7+ не нужна (используется суффикс `c`).

**Plans:** 5 plans (waves 1-5)

Plans:
**Wave 1**
- [x] 06C-01-PLAN.md — Foundation: OnDemandRulesBuilder (NEOnDemandRuleConnect.any) + tests (D-01, D-01b, D-02, D-03) — ✓ Complete 2026-05-13 (Round 2/3 API expansion: 4 public methods + 11 tests, see 06C-01-SUMMARY.md)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 06C-02-PLAN.md — Parallel-run wiring: DefaultTunnelProvisioner.provisionTunnelProfile вызывает builder; старая custom-reconnect machinery всё ещё работает — ✓ Complete 2026-05-13 (ManagerSelector + applyCurrentState + bbtbProvisionerDidSave; +7 tests; AppFeatures 145/145, see 06C-02-SUMMARY.md)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 06C-03-PLAN.md — Migration + UI + Watchdog: Settings toggle (D-04..D-07), OnDemandMigrationTask (D-17b/c), TunnelWatchdog actor (D-08..D-10) — ✓ Complete 2026-05-13 (4 tasks: Settings + ReconnectClock/TestClocks extract + Migration + Watchdog; +18 tests; AppFeatures 163/163; parallel-run preserved, see 06C-03-SUMMARY.md)

**Wave 4** *(blocked on Wave 3 completion, contains device UAT checkpoint)*
- [x] 06C-04-PLAN.md — Cutover cleanup: wire watchdog + migration; device UAT 9 scenarios; DELETE ReconnectStateMachine + NetworkReachability + slim TunnelController (D-10/D-14/D-15) — **✓ Complete 2026-05-13** (commits 19f3fe7 + 5b0e28c + 69b8ae8 + 44a5630): TunnelController 909→316 строк, 5 файлов удалены, 7 новых тестов в TunnelControllerTests.swift, AppFeatures **133/133 PASS**, iOS+macOS xcodebuild SUCCEEDED. Round 5 architect-driven scope expansion (intent-closing + reactive UI driver) applied. **Re-UAT closed на iPhone iOS 26.5 (2026-05-13):** F-reverse PASS, Settings-disable PASS (после follow-up fix `44a5630` — VM foreground resync + connectedDate authority; Codex GPT-5.2 архитекторский диагноз: observer queue `.main` drop во время Settings round-trip), G passive PASS. См. `06C-04-SUMMARY.md` (раздел «Re-UAT outcome»).

**Wave 5** *(blocked on Wave 4 re-UAT signoff)*
- [x] 06C-05-PLAN.md — Regression + Phase 6c UAT validation: 06C-UAT.md formal record; planning artifacts + wiki sync; mark NET-08..11 Validated; add NET-12 (liveness probe) backlog для Phase 7-8 (D-22) — **✓ Complete 2026-05-13** (commit `ce5913d`): `06C-UAT.md` (~230 строк, 5 sections — все 9 сценариев + Settings-disable + Phase 1-6 regression smoke + decisions + metrics + closure checklist), `06C-05-SUMMARY.md`, STATE/PROJECT touchups. **Phase 6c officially closed 2026-05-13.**

---

### Phase 6d: Performance & Code Quality Audit ✅ **Closed 2026-05-14**
_(INSERTED 2026-05-13 — remediation-фаза по аналогии с 6c, без перенумерации Phase 7+.)_
**Goal:** Cross-cutting multi-AI peer review кодовой базы на: (1) performance / responsiveness (cold start, переходы экранов, импорт, connect-кнопка), (2) energy consumption на iOS device, (3) code simplicity, deduplication, dead-code removal, (4) memory footprint, (5) launch time. Привлекаем три модели параллельно — **Claude Opus 4.7**, **Codex GPT-5.2**, **Gemini 3.1 Pro** — для независимых passes; синтезируем findings, классифицируем по severity, выполняем fix-cycle атомарными commit'ами. Версия — **v0.6.2** (patch). **Outcome:** 45 findings synthesized → 19 closed (cold-start ~−500…−1100 мс, connect-tap ~−1000…−3000 мс, disconnect −2.5 сек, energy + correctness wins) + 6 post-fix correctness commits (Settings-disable saga); 26 carved-out → backlog для Phase 6e. UAT regression smoke PASS на iPhone iOS 26.5.

**Mode:** mvp (vertical slice — audit pass → findings → prioritized fixes → verification → close)
**UI hint:** no (поведенческие fix'ы могут касаться UI responsiveness, но новых экранов нет)
**Requirements:** PERF-01..05 + QUAL-01..03 ✓ Validated (см. REQUIREMENTS.md + wiki/performance-baseline.md). Ничто не invalidates.

**Success Criteria:**
1. ✓ Multi-AI audit complete — `06D-FINDINGS.md` consolidated (45 findings, 3-AI / 2-AI / 1-AI consensus markers + invariant filter).
2. ✓ Findings классифицированы по severity (HIGH / MEDIUM / LOW) + dimension (cold-start / connect-tap / energy / memory / correctness).
3. ✓ Option-B scope: все HIGH + selected MEDIUM закрыты атомарными commit'ами (19 fixes); LOW + 6 MEDIUM carved out (см. `06D-FINDINGS.md` backlog).
4. ⏭ Pre-fix Instruments baseline skipped (Variant D, user decision at CHECKPOINT 1 — accept descriptive comparison вместо numerical для velocity). `wiki/performance-baseline.md` финализирован как long-term decision record + 26 carved findings backlog.
5. ✓ Cold-start + Connect-tap improvements verified через UAT smoke (6d-NEW-1 + 6d-NEW-2 PASS); numerical post-fix capture опционально доступен через PerfSignposter (DEC-06d-06).
6. ✓ AppFeatures swift test 133/133 green throughout; iOS + macOS xcodebuild SUCCEEDED on каждом из 45 commits.
7. ✓ Никаких новых features — только refactor / cleanup / perf + post-fix Settings-disable correctness saga.

**Note:** Это remediation-фаза, не feature-добавка. Перенумерация Phase 7+ не нужна (используется суффикс `d`, по аналогии с Phase 6c).

**Plans:** 7 plans + 8 sub-plans (Wave 03 split into 03a–03h после CHECKPOINT 1).

Plans:
- [x] 06D-01-PLAN.md — Audit briefing + 3 parallel AI passes (Opus + Codex + Gemini), wave 1 — ✓ Complete `e2c9ac6`
- [x] 06D-02a-PLAN.md — Wave 0 gaps: Periphery + PerfSignposter + baseline templates, wave 2.1 — ✓ Complete `7ffb398` + `64368c6` + `524939b` + `4ec9ca6`
- [x] 06D-02b-PLAN.md — Synthesis: consolidated FINDINGS + invariant filter + coverage matrix, wave 2.2 — ✓ Complete `85b16cb`
- [x] 06D-02c-PLAN.md — Pre-fix baseline skipped (Variant D); wiki/performance-baseline initial draft + CHECKPOINT 1, wave 2.3 — ✓ Complete
- [x] 06D-03a..03h-PLAN.md — Fix cycle (19 commits across 8 sub-plans), wave 3 — ✓ Complete; см. detailed list ниже. _(Note: `06D-03-PLAN.md` остался в директории как pre-split parent — superseded sub-plans 03a-03h после CHECKPOINT 1.)_
- [x] 06D-Final-a-PLAN.md — Comparison cataloging + D-09 invariant audit + periphery post-fix scan, wave Final.1 — ✓ Complete `c1fc126` + `8e6e660` + `6573af4` + `b4d869c`
- [x] 06D-Final-b-PLAN.md — UAT smoke + wiki sync + closure SUMMARY + STATE/ROADMAP/REQUIREMENTS sync, wave Final.2 — ✓ Complete 2026-05-14 (this commit)

**Wave 03 sub-plans:**
- 03a (`c2d54ea`) — H1 trace-logging gated за `#if DEBUG`
- 03b (`8749985` + `decd7c4` + `acd85fa`) — H2/H3/H8 XPC consolidation + connect/disconnect observer-stream
- 03c (`55bde6c` + `dca8e58`) — H4 bounded concurrency + cached auto-mode snapshot
- 03d (`5ef3888` + `b8d9294`) — H5/H7 UI re-render savings
- 03e (`1d035bb` + `6c89996` + `1099629` + `684fb5a` + `99530f2`) — H6/M2/M3/M4/M5 cold-start residual
- 03f (`cd4b297`) — M1 cold-start XPC consolidation
- 03g (`37e7d34` + `42a908a` + `5a4db9f`) — H9/M9/M16 extension correctness
- 03h (`1621a08` + `61f60a3` + `b6996cb`) — M12/M13/M14 correctness fixes

**Post-fix commits (after Final-a, before Final-b closure):**
- Cold-start + UI freeze post-fix block (4 commits) — `bc7bc26` + `1467328` + `9b38796` + `4983cab`
- Settings-disable saga (3 commits, final solution open-source-research-derived) — `5110ae0` + `9122bbd` + `cff3f46`

---

### Phase 6e: Performance Audit Round 2 + macOS UAT replay
_(INSERTED 2026-05-14 — remediation-фаза по аналогии с 6c/6d, без перенумерации Phase 7+.)_
**Goal:** Tactical cleanup-фаза после Phase 6d. Закрыть оставшиеся **26 carved-out findings** (6 MEDIUM + 20 LOW + 3 trivial unused imports), опционально снять **numerical Instruments baseline** на physical iPhone (post-Phase-6d, для regression detection в Phase 7+), выполнить **macOS-specific UAT replay** для Phase 6c/6d сценариев A/F-direct/F-reverse/Settings-disable/G (in Phase 6d закрыты только iOS-выборочно; macOS path использует тот же source code, но отдельная UAT-сессия даёт production strength перед Phase 11/12). Версия — **v0.6.3** (patch). Phase 7 (большой объём нового кода) проще ревью когда baseline maximally clean.

**Mode:** mvp (vertical slice — pick scope subset → fix bundle → verify → close)
**UI hint:** no
**Requirements:** новые QUAL-04..05 / PERF-06 (TBD в `/gsd-discuss-phase 6e`); maintains PERF-01..05 + QUAL-01..03. Ничто не invalidates.

**Success Criteria:** (to be finalized в `/gsd-discuss-phase 6e` — пока drafts)
1. Все scoped carved-out findings либо closed (атомарные commit'ы с regression gate), либо explicitly downgraded к «permanently accepted» с rationale в `wiki/performance-baseline.md` § Open follow-ups.
2. Numerical Instruments baseline снят на physical iPhone (Time Profiler cold-launch + connect-tap, Energy Log 5-min idle, Allocations host + extension) и зафиксирован в `.planning/phases/06e-perf-audit-round-2/baselines/` + summary в wiki — для regression detection в Phase 7+. _(Optional — может быть deferred если user выберет skip.)_
3. macOS UAT replay — Phase 6c/6d scenarios A/F-direct/F-reverse/Settings-disable/G выполнены на MacBook macOS 15+ либо explicitly deferred к Phase 11/12 (с rationale).
4. AppFeatures swift test 133/133 green throughout (либо increase если новые tests добавлены); iOS + macOS xcodebuild green throughout.
5. D-09 + Phase 6d invariants preserved (forbidden symbols grep ≤ 7, observer queue=.main = 0, `#Predicate` UUID? = 0, applyVPNStatus single authority, sliding window, no fire-and-forget XPC в TunnelController, no sleep-based status polling, bounded probe concurrency, ExternalVPNStopMarker semantics).
6. `wiki/performance-baseline.md` final state updated с post-6e closure (carved findings → closed-or-accepted list, numerical baseline если снят, macOS UAT result).
7. Никаких новых features — только cleanup / verification / measurement. **No scope creep в feature-direction.**

**Note:** Это вторая remediation-фаза подряд (после 6d), не feature-добавка. Перенумерация Phase 7+ НЕ нужна — суффикс `e` по аналогии с `c`/`d`.

**Plans:** 3 plans (waves 1-3)

Plans:
- [x] 06E-01-PLAN.md — Wave 1: 4 atomic MEDIUM fixes (M7 / M10 / M8+L12 / M11) — per-commit regression gate
- [ ] 06E-02-PLAN.md — Wave 2: 5 LOW bundle commits (Theme A perf / Theme B correctness / Theme C-1 maintainability / Theme C-2 L16 standalone HIGH-RISK / Theme D trivial imports) + single end-of-bundle gate
- [ ] 06E-03-PLAN.md — Wave 3: closure (06E-Final-SUMMARY + wiki sync + STATE/ROADMAP/REQUIREMENTS sync + final regression gate)

**Carved findings inventory (входной scope):**
- 6 MEDIUM (carved Phase 6d): M6, M7, M8, M10, M11, M15 — см. `.planning/phases/06d-performance-audit/06D-FINDINGS.md`
- 20 LOW: L1-L20 — см. `06D-FINDINGS.md`
- 3 trivial unused imports — см. `06D-PERIPHERY-POST-FIX.md`
- Open items: NET-12 (active liveness probe — Phase 7-8) — **НЕ в scope 6e** (откладываем к Phase 7-8 как было решено в 6c)

---

### Phase 7: Anti-DPI suite + WireGuard family
**Goal:** Полный набор anti-DPI техник и оставшиеся 4 протокола (WireGuard, AmneziaWG, TUIC v5, OpenVPN/TLS). Версия — **v0.7**.
**Mode:** mvp
**UI hint:** no
**Requirements:** PROTO-06, PROTO-07, PROTO-08, PROTO-09, DPI-01, DPI-02, DPI-03, DPI-04, DPI-05, DPI-07
**Success Criteria:**
1. Все 9 протоколов из спецификации подключаются на тестовых серверах.
2. uTLS-fingerprint работает и переключается между Chrome/Firefox/Safari/random.
3. Тестовый DPI-сценарий (имитация ТСПУ-блокировки по SNI) проходится без вмешательства пользователя.
4. WireGuard через WireGuardKit и AmneziaWG со своей обфускацией работают параллельно.

---

### Phase 8: Rules Engine + Split tunneling
**Goal:** Централизованные правила с Ed25519-подписью, split-tunneling по доменам/IP/странам, AppProxyProvider на macOS. Версия — **v0.8**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** CORE-05, RULES-01, RULES-02, RULES-03, RULES-04, RULES-05, RULES-06, RULES-07, RULES-08, RULES-09, RULES-10, RULES-11
**Success Criteria:**
1. Подмена `rules.json` на сервере → клиент применяет новые правила в течение 6 часов.
2. Битая Ed25519-подпись → приложение игнорирует обновление, использует кешированную версию.
3. На macOS AppProxyProvider позволяет роутить отдельные приложения через VPN.
4. Просмотр правил (read-only) в Расширенных отражает актуальный rules.json.
5. Кнопка «Принудительно обновить правила» в Расширенных работает.

---

### Phase 9: Deep links
**Goal:** Custom URL Scheme `bbtb://` и Universal Links через `import.bbtb.app` с landing page. Версия — **v0.9**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** DEEP-01, DEEP-02, DEEP-03, DEEP-04, DEEP-05
**Success Criteria:**
1. Тап в Telegram на `bbtb://import?config=...` открывает приложение и импортирует конфиг.
2. Тап на `https://import.bbtb.app/c/{token}` делает то же самое.
3. При отсутствии приложения Universal Link открывает landing page со ссылкой на TestFlight invite.
4. `DeepLinkRouter` корректно парсит и connect, и disconnect, и import URLs.

---

### Phase 10: Advanced settings + Security polish
**Goal:** Полные Расширенные настройки, биометрия, STUN-блок toggle, CDN-фронтинг, cert pinning, ручной выбор протокола, On-Demand rules, **macOS-тоггл enforceRoutes** (R5). Версия — **v0.10**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** UX-06, BIO-01, BIO-02, BIO-03, BIO-04, DPI-06, DPI-08, DPI-09, ONDEMAND-01, KILL-04
**Success Criteria:**
1. Все опции в Расширенных функциональны и сохраняются между запусками.
2. Биометрия защищает приложение при backgrounding (при включённой опции).
3. STUN-блок при включении блокирует UDP 3478/5349 и показывает предупреждение про сломанные браузерные звонки.
4. CDN-фронтинг через Cloudflare/Fastly доступен как fallback transport.
5. Cert pinning защищает соединение с панелью подписок.
6. **macOS:** тоггл «Отключить принудительную маршрутизацию» работает корректно — `enforceRoutes=false` применяется к туннелю при выборе пользователя (R5).

---

### Phase 11: Onboarding + UX polish
**Goal:** Финальный дизайн всех экранов по Figma, полная локализация ru/en, MAX-detection в логи, FAQ, **file picker импорт** (IMP-03, переехал из Phase 2 после `/gsd-discuss-phase 2` 2026-05-11). Версия — **v0.11**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** UX-01, UX-08, UX-09, DETECT-01, DETECT-02, DETECT-03, TELEM-02, LOC-02, LOC-03, LOC-04, IMP-03
**Notes:**
- `ServerListSheet` использует статические константы высоты строк (`serverRowH=80`, `autoCellH=116`, `subHeaderH=44`) для расчёта `presentationDetents`. **При применении Figma-макетов эти константы нужно пересмотреть** — они в `ServerListSheet.swift` (приватные `static let`). Иначе шит может открываться на неправильной высоте.

**Success Criteria:**
1. Visual review всех экранов соответствует Figma-макетам.
2. Локализация-аудит не находит «hardcoded English strings» ни в одном экране.
3. FAQ в Help содержит секции про WebRTC leak и про известные ограничения детектирования VPN (22 приложения).
4. MAX-detection отрабатывает корректно — без UI, только в локальный лог.
5. Кнопка «Отправить лог разработчику» собирает 24ч логов и отправляет на endpoint разработчика.
6. Анимации переходов состояний главной кнопки плавные.

---

### Phase 12: Pre-release + Public TestFlight (v0.12 + v1.0)
**Goal:** Telemetry, performance audit, Beta App Review submission, public invite link, лендинг. Финальная сборка для публичного TestFlight. Версии — **v0.12** и **v1.0**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** TELEM-03, TELEM-04, TELEM-05, TELEM-06, TELEM-07, TELEM-08, TELEM-09, SEC-07, DIST-03, DIST-04, DIST-05, DIST-06, DIST-07, DIST-08
**Success Criteria:**
1. Privacy-respecting аналитика батчем долетает до собственного VPS, агрегация работает.
2. Crash reporter с UI отправки запускается при следующем запуске после краша.
3. Performance audit (Instruments: CPU, memory, energy) пройден — нет утечек памяти при многочасовом подключении.
4. App Privacy declaration в App Store Connect заполнена корректно.
5. **Beta App Review пройден** — приложение одобрено для External Testing.
6. Public invite link через TestFlight работает; пользователь из Telegram может установить приложение и импортировать конфиг без помощи разработчика.
7. Сайт лендинга с invite-ссылкой опубликован.
8. About-screen содержит версию, ссылку на open-source ядро (GitHub), лицензии (AGPL-3.0 ядра).
9. Documentation для пользователей опубликована (как импортировать, как поделиться, как сообщить о баге).

---

## Global Definition of Done (после Phase 12)

- [ ] iOS-сборка работает на iPhone 11+ (минимальное устройство для iOS 18).
- [ ] macOS-сборка работает на Apple Silicon.
- [ ] Все 9 протоколов подключаются успешно.
- [ ] Kill switch блокирует утечки.
- [ ] IPv6 leak-test пройден.
- [ ] DNS leak-test пройден.
- [ ] WebRTC leak-test пройден (с дефолтным выключенным STUN-блоком, пользователь предупреждён через FAQ).
- [ ] **Security review sing-box engine** (R1): нет SOCKS5 на localhost, gRPC API отключён, P2P=false. Тест-приложение подтверждает.
- [ ] Rules Engine: подмена `rules.json` на сервере → приложение применяет в течение 6 часов; битая подпись → откат на кеш.
- [ ] Deep links работают (custom scheme + Universal Links).
- [ ] Аналитика батч долетает до сервера.
- [ ] Crash reporter ловит и отправляет крашлоги.
- [ ] Локализация ru/en полная.
- [ ] App Privacy declaration корректна.
- [ ] FAQ содержит известные ограничения детектирования VPN.
- [ ] Beta App Review пройден.

## Beyond v1.0

После v1.0 — внутри публичного TestFlight, расширение фичами в v1.1–v1.9 (smart auto-select, stats pro, multi-hop, widgets, watch, push, shortcuts, stealth, iCloud sync). Мажорное изменение бизнес-модели — v2.0 (managed servers + биллинг). См. `prompts/v2 <release_roadmap>` секции v1.1–v2.1 для детализации.

---
*Created: 2026-05-11 from prompts/v2 release_roadmap.*
*Coverage: ~130 v1 requirements, all mapped to one of 12 phases.*
