---
gsd_state_version: 1.0
milestone: v0.12
milestone_name: + v1.0)
status: paused
last_updated: "2026-05-15T10:03:08.667Z"
progress:
  total_phases: 16
  completed_phases: 8
  total_plans: 70
  completed_plans: 51
  percent: 51
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-12 after Phase 3)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 09 — deep-links (⏸ PAUSED at Wave 4 Task 4.2 — human actions deferred)

## Active Phase

- **Phase:** 9 — Deep Links
- **Name:** Deep Links: `bbtb://` custom URL scheme + Universal Links via `import.bbtb.app`
- **Status:** ⏸ PAUSED — код готов (W1–W3 ✅), ждём: деплой AASA на `import.bbtb.app` + Apple Portal Associated Domains capability + device UAT

### Phase 9 прогресс

| Wave | Статус | Что сделано |
|------|--------|-------------|
| W1 | ✅ MERGED | `DeepLinks` SwiftPM пакет, `DeepLinkRouter` actor, 3/3 tests |
| W2 | ✅ MERGED | `ImportHandler` + L10n 5 ключей + `URLParsingTests`, 17/17 tests |
| W3 | ✅ MERGED | Tuist + entitlements + Info.plist + App wiring + `handleDeepLink`, 164/164 tests |
| W4 Task 4.1 | ✅ COMMITTED | `09-AASA-RUNBOOK.md` написан |
| W4 Task 4.2 | ⏸ DEFERRED | Деплой AASA + Apple Portal capability — ждёт ручных действий |
| W4 Task 4.3 | ⏸ DEFERRED | Device UAT F1-F4 — ждёт после 4.2 |
| W4 Task 4.4 | ⏳ NOT STARTED | Wiki sync + REQUIREMENTS Validated + phase closure |

**Resume file:** .planning/phases/10-advanced-settings-security-polish/10-CONTEXT.md

**Команда для возобновления:**

```
/gsd-execute-phase 9 --wave 4
```

или сказать Claude: «Продолжаем Phase 9. AASA задеплоен через Вариант A/B.»

### Phase 8 ✅ CLOSED 2026-05-15 — Rules Engine + Split tunneling

#### Phase 8 implementation summary (7 waves complete)

- **W0 ✓** — RULES-11 + SC #3 carve-out; `AppProxyExtension-macOS` target deleted (D-09); `wiki/appproxy-deferral-2026.md` created
- **W1 ✓** — `RulesEngine` SwiftPM пакет: swift-crypto 4.x Ed25519 + `RulesFetcher` + `RulesManifest` + `RulesSigner` + 9 unit tests
- **W2 ✓** — `RulesEngineCoordinator` actor: bootstrap + background refresh + forceUpdate + `SRSCacheStore` + `BaselineRulesLoader` + 13 tests
- **W3 ✓** — SwiftUI: `RulesViewerSection`, `ForceUpdateRulesButton`, `MinAppVersionBanner`, `MinAppVersionSheet` + ~30 L10n keys (ru+en) + 17 tests
- **W4 ✓** — iOS `BGAppRefreshTask` (6h re-submit) + macOS `NSBackgroundActivityScheduler` (6h, tolerance 10min) + host wiring
- **W5 ✓** — `SingBoxConfigLoader.expandConfigForTunnel` injects 3 `route.rule_set` + 3 priority rules (block→reject; never→direct; always→urltest-auto); R1/R10 preserved; 6 tests
- **W6 ✓** — `scripts/build-baseline-rules.sh` developer workflow; committed real signed SRS baseline (max.ru / mssgr.tatar.ru → block_completely); `PublicKey.swift` updated с real derived pubkey bytes
- **W7 ✓** — `validate-r1-r6.sh` extended: R8 + R8b + RULES-02 + R12 + D-08; `RulesEngine` added to per-package test loop; wiki long-term memory synced (this STATE update)

**Tests**: RulesEngine 41 + PacketTunnelKit 72+ + AppFeatures 162+ + all existing packages — all green.

**Manual UAT pending** (на iPhone iOS 18+ test device, `wiki/rules-engine.md` § Manual UAT):

- M-04: BGAppRefreshTask 6h real wall-time (или Simulator Debug → Simulate Background Fetch)
- M-05: real domain blocking — curl max.ru через tunnel → connection reset
- M-07: split-tunnel country resolve — yandex.ru goes direct, non-RU through VPN
- M-08: min_app_version sheet UX — admin publishes 99.0.0 → sheet appears, persist через kill

### Phase 8 decisions (D-01..D-13)

| ID | Decision | Rationale |
|----|----------|-----------|
| D-01 | sing-box `route.rule_set` via server-compiled SRS binary | Единственный performant option без MMDB на клиент; sing-box auto-reload с 1.10.0 |
| D-02 | domain/IP/country в SRS (no client MMDB) | country→CIDR expand server-side при signing |
| D-03 | DNS sniffing обязателен | `sniff: true` в TUN inbound — domain rules не работают без |
| D-04 | Full server-side country resolve | MaxMind GeoLite2 на VPS, не на клиенте |
| D-05 | Embedded signed baseline в .app bundle | Bootstrap до первого server fetch; один trust-path |
| D-07 | Two-file detached Ed25519 sig | manifest.json.sig + per-SRS .sig — один verify код path |
| D-08 | RULES-11 + SC#3 → Out of Scope v0.10+ | L4 AppProxy ↔ L3 sing-box mismatch; mutual exclusivity NETunnelProviderManager/NEAppProxyProviderManager; R1 break |
| D-09 | AppProxyExtension-macOS target DELETE | D-08 corollary; Tuist + entitlements cleanup |
| D-10 | Force-update cooldown = 60 сек | VPS DDoS protection при ручном refresh |
| D-11 | min_app_version = modal sheet + banner | Dismissible (не full-screen takeover), persistent banner в Advanced |
| D-12 | rules не блокируют cold start | DEC-06d-01 pattern: baseline из bundle → BG fetch |
| D-13 | Mirror failover sequential (concurrency=1) | DEC-06d-04 bounded concurrency pattern |

See full details: `wiki/rules-engine.md` § Архитектурные решения Phase 8; Codex threads `019e2841` (Area A sing-box rule_set) + `019e284c` (Area D AppProxy deferral).

### Phase 8 context summary (для quick resume)

- **D-01 (Area A):** sing-box `route.rule_set` + server-side SRS pipeline. Updates без restart (auto-reload since sing-box 1.10.0). 3 binary .srs файла: block / never / always.
- **D-04 (Area B):** country resolve server-side при signing (MaxMind GeoLite2 weekly). MMDB на клиент не грузим.
- **D-05 (Area C):** embedded `baseline-rules.json` (signed Ed25519, version=0) в .app bundle для bootstrap.
- **D-07 (Area E auto):** two-file signature `rules.json` + `rules.json.sig` (NOT embedded).
- **D-08+D-09 (Area D):** RULES-11 + Phase 8 SC #3 → **Out of Scope v0.8** (Codex review: arch mismatch + R1 invariant risk). AppProxyExtension-macOS target → DELETE в Plan W0.
- **D-10..D-13 (auxiliary defaults):** force-update cooldown=60s, min_app_version=modal sheet dismissible, fetch не блокирует cold start, failover concurrency=1.

### Previous phase (Phase 7c — Engine Boundary Cleanup ✅ Closed 2026-05-14)

- **Status:** ✅ Closed 2026-05-14 — HYBRID variant per Codex thread `019e2802-ed23-7f21-bd6a-138edea62528` production iOS VPN multi-engine architecture survey + user confirmation «делаем Вариант B».
- **Goal:** Заложить основу для модульности и масштабируемости (Claude.md line 112 principle) — sing-box-specific код в чёткий namespace + decision document с триггерами для будущего `protocol TunnelEngine`. **Без** premature abstraction layer.
- **Outcome:**
  - **Code reorganization:** 4 файла переехали в `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/` (BaseSingBoxTunnel.swift, ExtensionPlatformInterface.swift, SingBoxConfigLoader.swift, Resources/SingBoxConfigTemplate.vless-reality.json). Engine-agnostic utilities (AppGroupContainer, TunnelSettings, TunnelLogger, ExternalVPNStopMarker, InterfaceFlagsInspector, PlatformSpecific/) остались at top level.
  - **Package.swift `resources:` path** обновлён + breadcrumb-marker добавлен в BaseSingBoxTunnel.swift.
  - **Decision document:** `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md` (новый) — триггеры + Path A (switch-dispatch) vs Path B (separate extensions) + anti-patterns.
  - **Cross-references обновлены:** `validate-r1-r6.sh` R1/R6 invariant gate paths, `wiki/security-gaps.md` § R10/R11 file references, ConfigParser/PoolBuilder + VLESSReality/ConfigBuilder doc comments.
  - **Pre-existing Phase 7a Wave 1 bug закрыт:** `VPNCoreTests/ParsedConfigsTests.swift` exhaustiveness gate не был обновлён под `.tuic` case (был 9-й switch site, я обновил 8 в Wave 1) — теперь зафикшен.
  - **Verification:** PacketTunnelKit 66/66 + ConfigParser 228/228 + AppFeatures 143/143 + TUIC 26/26 + VPNCore + 5 protocol packages — все existing tests PASS. `validate-r1-r6.sh` 11 invariants PASS. `tuist generate` clean. iOS + macOS xcodebuild SUCCEEDED. Поведение приложения идентично — pure rename + reorganization.
- **Версия:** internal refactor, без version bump (v0.7.1 stays).
- **Architectural decisions:**
  - HYBRID variant ([[engine-abstraction-decision-2026]]): boundary cleanup сейчас, full `protocol TunnelEngine` defer до реального второго engine (триггеры в `EngineAbstractionDecision.md`).
  - Anti-pattern зафиксирован: generic-named classes (`VPNEngine`, `CoreManager`, `ProtocolService`) запрещены пока есть один engine; sing-box-explicit naming сохранён.
- **Wiki long-term memory:** `wiki/engine-abstraction-decision-2026.md` (new), `wiki/architecture.md` updated с описанием SingBox/ namespace + ссылкой на decision page.
- **Closure SUMMARY:** `.planning/phases/07c-engine-boundary-cleanup/07c-Final-SUMMARY.md`.

### Previous-previous phase (Phase 7b — Engine abstraction + AmneziaWG 2.0 ❌ Cancelled 2026-05-14)

- **Status:** ❌ **Cancelled 2026-05-14** by user decision after Phase 7a closure: «отложим амнезию вообще на версию 2 или позднее».
- **Original goal:** Engine abstraction layer + AmneziaWG 2.0 (PROTO-07) через `amneziawg-apple` SwiftPM library.
- **Cancellation rationale:** Codex deep research thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` показал реальную стоимость integration — 5-7 engineer-weeks full quality (manual `libwg-go.a` build chain через Makefile + Go 1.26 patches GOROOT, AWG 2.0 backward-incompat с v1.5 серверами требует fresh keys, Go runtime memory unknown на iOS 18 NetworkExtension 50MB limit, no crash isolation — Go panic убивает весь PacketTunnelProvider, X-UI/Marzban пока не поддерживают AWG 2.0 официально). User-base = 50 friends-and-family с уже работающим Reality+Trojan+Hy2+TUIC стеком; AWG demand не подтверждён реальными запросами.
- **Что переносится в Out of Scope (v2.0+ conditional):**
  - PROTO-07 AmneziaWG 2.0 (был Phase 7b primary scope)
  - DPI-04 random TCP/UDP delay (был AWG-bound — sing-box не поддерживает random delay для не-AWG протоколов)
  - Engine abstraction layer (был нужен ради AWG; без второго движка не нужен)
- **Условие возврата (decision log в `wiki/amneziawg-deferral-2026.md`):** 3+ независимых TestFlight запроса с рабочими AWG 2.0 подписками, ИЛИ ТСПУ поломал текущий стек (Reality/Hy2/TUIC), ИЛИ v2.0 milestone бюджет на architectural фазы.
- **Финал Phase 7:** только Phase 7a сделано. Phase 7 Total: 6 in-scope протоколов в финальном MVP-наборе (VLESS+Reality, VLESS+TLS+Vision, Trojan, SS-2022, Hysteria2, TUIC v5). Архитектура остаётся mono-engine sing-box через `libbox.xcframework` v1.13.11.

### Previous phase (Phase 7a — TUIC v5 + anti-DPI smart defaults ✅ Closed 2026-05-14)

- **Status:** ✅ Closed 2026-05-14 — iPhone UAT PASS на Trojan-based subscription (`vpn.vergevsky.ru`, 6 серверов в пуле). Sing-box logs (320KB) показывают ноль TLS handshake errors после смены default uTLS=random + tls.record_fragment=true для VLESS+TLS/Trojan; сотни успешных Trojan-0 outbound connections к Instagram/Facebook/Apple Push/iTunes/iCloud. iOS Console (5MB) — ноль crashes / fatalError / EXC_RESOURCE / PORT_SPACE.
- **Goal:** Добавить TUIC v5 + anti-DPI smart defaults без user-visible regression.
- **Version:** v0.7.1
- **Requirements:** PROTO-08 (TUIC v5) + DPI-01 (uTLS random) + DPI-02 (TLS ClientHello fragmentation, реализована как `record_fragment` per Codex Q4) + DPI-07 (port diversity) — все ✅ Validated.
- **Outcome:**
  - **Implementation:** Waves 1+2+4 autonomous code-complete (W1 TUIC package, W2 smart defaults, W4 registration+Tuist+xcodebuild). W3 (mux infrastructure) intentionally deferred to Phase 10 (unified DPI-09 UI toggle PR). W5 wiki/STATE/SUMMARY sync.
  - **Tests:** ~470+ tests green (TUIC 26/26 + ConfigParser 228/228 + AppFeatures 143/143 + 5 protocol packages preserved).
  - **Build:** iOS xcodebuild SUCCEEDED + macOS xcodebuild SUCCEEDED (ad-hoc signing).
  - **UAT:** iPhone smoke на Trojan subscription PASS — самый стрессовый случай (record_fragment ON для Trojan) подтверждает что smart default не ломает соединение.
  - **TUIC connection test** carved-out: пользователь сообщил «нет конфигурации TUIC v5». Архитектурная готовность 100% покрыта unit-тестами; реальный connection test ожидает появления TUIC сервера (self-host либо subscription provider).
- **Architectural carve-outs:**
  - PROTO-09 OpenVPN/TLS, PROTO-06 plain WireGuard → Out of Scope, v1.x backlog conditional on demand (Phase 7 D-01/D-02 deep research).
  - Wave 3 Mux infrastructure (smux/yamux/h2mux per-server) → Phase 10 unified PR с DPI-09 UI picker.
  - TUIC connection device-UAT → carry-out до появления реального TUIC сервера.
- **Final commits:** `8ca1014` (W1 TUIC package +1418 lines) + `1d98abc` (W2 smart defaults) + `cb6140b` (W4 registration+Tuist) + `49c40d5` (W5 wiki+STATE+SUMMARY) + closure commit (this).
- **Closure SUMMARY:** `.planning/phases/07-anti-dpi-suite-wireguard-family/07a-Final-SUMMARY.md`.
- **Wiki long-term memory:** `wiki/anti-dpi-techniques.md` (реальное состояние sing-box 1.13.x) + `wiki/protocols-overview.md` (8 in-scope) + `wiki/openvpn-deferral-2026.md` + `wiki/wireguard-deferral-2026.md`.
- **Goal:** ~~Полный набор anti-DPI техник и оставшиеся 4 протокола (WG, AmneziaWG, TUIC v5, OpenVPN/TLS)~~. **Реальный scope после discuss:** 2 новых протокола (TUIC v5, AmneziaWG 2.0) + anti-DPI smart defaults в sing-box. PROTO-06 WireGuard plain + PROTO-09 OpenVPN/TLS → Out of Scope (ТСПУ blocks both behaviorally since Feb 2026).
- **Version:** v0.7.1 (Phase 7a) + v0.7.2 (Phase 7b)
- **Requirements (in-scope after discuss):**
  - **Phase 7a:** PROTO-08 (TUIC v5), DPI-01 (uTLS random), DPI-02 (TLS fragmentation), DPI-05 (Mux infrastructure), DPI-07 (ports — already works)
  - **Phase 7b:** PROTO-07 (AmneziaWG 2.0 only, через amneziawg-apple library + engine abstraction)
  - **Reframed:** DPI-04 random delay → «covered by AmneziaWG junk packets in 7b»; DPI-03 packet padding → «mux-layer padding when mux enabled per-server»
  - **Out of Scope (v1.x conditional):** PROTO-06 plain WireGuard, PROTO-09 OpenVPN/TLS

### Previous phase (Phase 6e — Performance Audit Round 2 + macOS UAT replay ✅ Closed 2026-05-14)

- **Status:** ✅ Closed 2026-05-14 после Wave 3 closure (06E-Final-SUMMARY + wiki sync + state/roadmap/requirements sync + D-05a final regression gate green).
- **Goal:** Tactical cleanup-фаза после Phase 6d. Закрыть 26 carved-out findings из Phase 6d с hybrid closure rigor (4 MEDIUM atomic + 4 LOW bundles + 3 trivial imports + closure).
- **Version:** v0.6.3 (patch)
- **Requirements:** QUAL-04 + QUAL-05 ✅ Validated (с явным exception note по L16/L18 deferral для QUAL-04); maintains PERF-01..05 + QUAL-01..03 (Phase 6d Validated).
- **Scope decisions (06E-CONTEXT.md):**
  - D-01 — ALL 26 findings (6 MED + 20 LOW + 3 trivial imports). Researcher cross-checked vs post-6d code state.
  - D-02 — Numerical Instruments baseline SKIPPED (deferred к Phase 11/12).
  - D-03 — macOS UAT replay SKIPPED (deferred к Phase 11/12).
  - D-04 — Hybrid closure rigor: MEDIUM atomic-commit-per-fix + per-commit regression gate; LOW bundle commits + single end-of-bundle gate; trivial imports один commit.
  - D-06 — NO 3-AI re-audit (findings уже triaged в 6d).
- **Outcome (SCENARIO B + L18 deferral):**
  - **19 code-fixed IDs:** Wave 1 (5) = M7 / M10 / M8+L12 / M11; Wave 2 (14) = L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L20.
  - **5 bookkeeping subsumed-by-Phase-6d:** M6, M15, L6, L17, L19.
  - **2 deferred IDs:** L16 (Codex Plan Reviewer HIGH-RISK no-go + AUTO_MODE safe-default); L18 (lazy var incompatible с init-time coordinator backlink + ObservedObject ABI change).
  - **3 trivial imports closed (Wave 2 Theme D)** — Periphery actionable count 3 → 0 (QUAL-05 closure proof).
- **Final regression gate (D-05a):** 4× Wave 1 per-commit + 1× Wave 2 end-of-bundle + 1× Wave 3 pre-closure = 6 gates total. AppFeatures 143/143 + PacketTunnelKit 66/66 + остальные packages baseline + iOS+macOS xcodebuild SUCCEEDED.
- **Invariants preserved:** DEC-06d-01..06 (cold-start defer / XPC ≤ 2 trips / event-driven status polling / bounded probe concurrency / Apple-canonical options + ExternalVPNStopMarker peek-only / PerfSignposter spans); R10 defense-in-depth (post-expand validate unconditional); R18 sliding window (`toggle && intent` = 2); D-09 single authority.
- **Final commits:** Wave 1 atomic: `ca21fa9` (M7) + `6af41db` (M10) + `368c82f` (M8+L12) + `4269570` (M11); Wave 2 bundles: `5c74423` (Theme A perf) + `f857763` (Theme B correctness) + `a03007f` (Theme C-1 maintainability) + `f42499f` (Theme D trivial imports); Wave 3 closure: docs(06e) Phase 6e closure (this commit).
- **Closure SUMMARY:** `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md`.
- **Wiki long-term memory:** `wiki/performance-baseline.md` § «Open follow-ups (post-6e)» updated.

### Previous-previous phase (Phase 6d — Performance & Code Quality Audit ✅ Closed 2026-05-14)

- **Status:** ✅ Closed 2026-05-14 после UAT regression smoke PASS на iPhone iOS 26.5 (hard-blockers: A, F-direct, F-reverse, G, I, Settings-disable; E deferred → NET-12; C macOS skipped — carry-over).
- **Goal:** Multi-AI peer review (Claude Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) на cold-start / connect-tap / energy / memory / code quality. Findings classified by severity, fixed atomically.
- **Version:** v0.6.2 (patch)
- **Requirements:** PERF-01..05 + QUAL-01..03 ✅ Validated (new section в REQUIREMENTS.md).
- **Outcome:** 45 findings synthesized → 19 closed (cold-start ~−500…−1100 мс, connect-tap ~−1000…−3000 мс, disconnect −2.5 сек, energy + correctness wins) + 6 post-fix commits (cold-start UI freeze block + Settings-disable saga). 26 carved-out → backlog для Phase 6e.
- **Phase 6d-specific architectural decisions:** DEC-06d-01..06 (см. `wiki/performance-baseline.md`):
  - DEC-06d-01 — Cold-start init defer pattern.
  - DEC-06d-02 — XPC consolidation в TunnelController (≤ 2 trips).
  - DEC-06d-03 — Event-driven status polling (AsyncStream, не sleep-loops).
  - DEC-06d-04 — Bounded concurrency для probe-style operations.
  - DEC-06d-05 — Apple-canonical `options["manualStart"]` discriminator + sticky App Group marker для Settings-disable correctness (open-source-research-derived from WireGuard iOS).
  - DEC-06d-06 — PerfSignposter spans сохранены в production code как standard tooling.
- **Final commits:** Audit + Wave 02a + Synthesis (`e2c9ac6`, `7ffb398`, `64368c6`, `85b16cb`); Wave 03a-03h fix cycle (19 commits, see ROADMAP Phase 6d sub-plans); Wave Final-a (`c1fc126` + `8e6e660` + `6573af4` + `b4d869c`); Post-fix (4 cold-start commits + 3 Settings-disable saga, final `cff3f46`); Wave Final-b (`0a9d1af` UAT + `e2e72ab` wiki sync + closure commit).
- **UAT report:** `.planning/phases/06d-performance-audit/06D-UAT.md`.
- **Closure SUMMARY:** `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md`.
- **Wiki long-term memory:** `wiki/performance-baseline.md` (new, comprehensive).

### Backlog (carried forward post-Phase-6e closure)

- **26 carved-out findings** — ✅ Closed in Phase 6e (2026-05-14): 19 code-fixed (Wave 1: M7/M10/M8+L12/M11; Wave 2 bundles: 14 LOW) + 5 subsumed-by-Phase-6d (M6/M15/L6/L17/L19) + 2 deferred (L16 Codex no-go, L18 architectural incompatibility) = 26 ✓. Carry-forward к Phase 6f либо Phase 7+ refactor: L16, L18, MainScreenView.swift:15 scenePhase declaration cleanup (Wave 1 M7 leftover).
- **NET-12** (Phase 6c carve-out, не закрыт в 6d/6e) — active liveness probe для soft-kill server detection. Phase 7-8.
- **macOS-specific UAT replay** (5 scenarios A / F-direct / F-reverse / Settings-disable / G) — Phase 6e D-03 explicit defer. Phase 11/12 pre-TestFlight polish.
- **Numerical Instruments baseline** (Time Profiler / Energy Log / Allocations) — Phase 6e D-02 explicit defer. PerfSignposter (DEC-06d-06) готов в production code. Phase 11/12 pre-TestFlight obligatory snap.

### Previous-previous phase (Phase 6c — On-demand reconnect migration ✅ Closed 2026-05-13)

- **Status:** ✅ Closed 2026-05-13 после re-UAT PASS pair (F-reverse + Settings-disable + G passive on iPhone iOS 26.5).
- **Goal:** Заменить custom auto-reconnect machinery на iOS-нативный `isOnDemandEnabled` + `NEOnDemandRule*` (D-01..D-22, post-Round-1 triple-reviewer APPROVE)
- **Version:** v0.6.1 (patch)
- **Requirements:** NET-08..11 ✅ Validated через Apple-managed mechanism + re-UAT.
- **Final commits:** `19f3fe7` + `5b0e28c` + `69b8ae8` (cutover) + `44a5630` (Round 6 follow-up VM resync + connectedDate authority) + `ce5913d` (Plan 05 closure — UAT.md + SUMMARY).
- **Wave progress:**
  - Wave 0 (06C-01) ✓ — OnDemandRulesBuilder foundation: 4 public methods + 11 tests; strictly additive; AppFeatures 138/138.
  - Wave 1 (06C-02) ✓ — ManagerSelector + ConfigImporter wiring + bbtbProvisionerDidSave: +7 tests (3 selector + 4 wiring); AppFeatures 145/145; parallel-run invariant preserved (TunnelController/RSM/NetworkReachability untouched).
  - Wave 2 (06C-03) ✓ — Settings toggle + ReconnectClock/TestClocks extract (B-01/B-02) + OnDemandMigrationTask (B-05 transient-failure guard) + TunnelWatchdog (W-05 .reasserting cancel): +18 tests (4 Settings + 5 Migration + 9 Watchdog); AppFeatures 163/163; TunnelController/NetworkReachability still untouched (wiring deferred to Wave 3).
  - Wave 3 (06C-04) — **✓ COMPLETE 2026-05-13 — re-UAT PASS + follow-up fix landed**:
    - Task 1 ✓ (commit d49e635) — additive wiring: cachedManager + bbtbProvisionerDidSave observer + setWatchdog + applyCurrentStateToCachedManager (Round 3 N-01 fallback + MINOR-01 graceful catch) + macOS wake 3 guards + .connecting banner case. AppFeatures 163/163 PASS.
    - Round 4 (commits 83260c1 + 9206b8c + 76ae2d6) — interim UAT hotfixes (fight-back + UI desync + narrow guards). All three superseded by Task 3a/3b rewrites.
    - Task 2 (UAT) — partial signal: A/C/F-direct/F-reverse (Round 4-fixed) PASS; Bug A (UI freeze on Connect) + Bug B (Settings off → auto-reactivate) discovered. **Codex GPT-5.2 architect review (`06C-ARCHITECT-R5.md`)** диагностировал оба бага как parallel-run hybrid → pull Task 3 cleanup forward, scope expanded.
    - Task 3a ✓ (commit `19f3fe7`) — TunnelController slim 909 → 316 строк; intent-closing on external `.disconnected` (Settings-disable + other-VPN takeover → close intent); `connectInProgress`/`manualDisconnectInProgress` PRESERVED (Round 5 carve-out); old machinery + ReconnectStateObserverRelay GONE.
    - Task 3b ✓ (commit `5b0e28c`) — `applyVPNStatus(_:)` reactive driver — NEVPNStatus authority for BOTH `state` AND `reconnectBannerState`; `.connecting` enum case added, `.retrying`/`.allFailed` dropped (W-02 audit cleared all consumer sites); `TunnelWatchdog.setFailoverObserver(_:)` setter + fire-site wired; App entry points cleaned of stale relay refs; seed initial state at VM init.
    - Task 3c ✓ (commit `69b8ae8`) — DELETED 5 files (RSM + tests + NetReach + tests + TCST); PRESERVED `ReconnectClock.swift` + `TestClocks.swift` (B-01/B-02); NEW `TunnelControllerTests.swift` (7 tests, D-24 cat 2); AppFeatures 133/133 PASS; awk-stripped grep returns 7 (only Round 5 carve-out flags, no forbidden symbols).
    - **Final build verification:** `swift build` + `swift test 133/133` + `xcodebuild BBTB iOS Simulator` + `xcodebuild BBTB-macOS` — все green на main.
    - **Re-UAT outcome (iPhone iOS 26.5, 2026-05-13):**
      - **F-reverse:** ✓ PASS — BBTB active → Happ takeover → BBTB stays off (intent-closing работает).
      - **Settings-disable Round 1:** ⚠️ PARTIAL FAIL — system VPN off, но UI stuck on `.connected` с тикающим таймером. Codex GPT-5.2 architect диагноз: VM `NEVPNStatusDidChange` observer на `queue: .main` теряет notification во время Settings round-trip (app suspended → main queue paused → notification dropped, не replays).
      - **G (passive):** ✓ PASS — zero EXC_RESOURCE / PORT_SPACE crashes.
    - **Follow-up fix landed (commit `44a5630`):** 3 surgical changes в `MainScreenViewModel.swift`:
      1. Observer queue `.main → nil` (match TunnelController; Task hop сохраняет main-actor мутации).
      2. New `MainScreenViewModel.handleForeground()` — one XPC trip на scene `.active`: `loadAllFromPreferences` + `ManagerSelector` filter + read `connection.status` + `connection.connectedDate` → feed `applyVPNStatus(_:connectedDate:)`.
      3. Wire `viewModel.handleForeground()` в `BBTB_iOSApp` + `BBTB_macOSApp` рядом с существующим `tc.handleForeground()`.
      Bonus (Замечание 1): `applyVPNStatus` теперь принимает `connectedDate: Date?` (default nil); `.connected` ветка использует `connectedDate ?? state.connectionStart ?? Date()`. Чинит сценарий «BBTB активирован через iOS Settings → таймер начинает с захода в app». Verification: 133/133 PASS + iOS+macOS xcodebuild SUCCEEDED. **Settings-disable re-tested PASS** (пользователь подтвердил).

  - Wave 4 (06C-05) — pending: regression + UAT.md документация + wiki sync + NET-12 (liveness probe) backlog для Phase 7-8.

### Previous phase (Phase 6 — Network Resilience)

- **Status:** ✓ Implementation complete 2026-05-13 — UAT отложен пользователем (Task 3 A-I deferred)
- **Goal:** DNS-стратегия (DoH + bootstrap, без хардкода Yandex), блокировка IPv6, авто-реконнект с retry, failover на следующий сервер
- **Version:** v0.6
- **Requirements:** NET-01..11
- **All 6 waves complete:**
  - Wave 1 (06-01) — DNSConfig + AdvancedSettingsStore
  - Wave 2 (06-02) — PoolBuilder DNS API + 6 sing-box template DNS swaps (Yandex→AdGuard)
  - Wave 3 (06-03) — Settings → Advanced DNS UI
  - Wave 4 (06-04) — NetworkReachability + ReconnectStateMachine actors
  - Wave 5 (06-05) — TunnelController actor + DNS wiring + wake + banner + notifications + Yandex eradication
  - Wave 6 (06-06) — SwiftDataFailoverProvider + manual-disconnect reset + 30s stable-session reset + single-server notification
- **Test totals (Phase 6):** AppFeatures 120/120, VPNCore 57/57, ConfigParser 210/210, PacketTunnelKit 61/61, Localization 3/3 + protocol packages — all green.
- **Pending:** Device UAT (Task 3 sub-tests A-I) — `/gsd-verify-work 6` once UAT signoff collected.
- **Previous phase (Phase 5) — Transports ✓ Complete 2026-05-13:**
  - 8 waves, ~376 tests PASS (VPNCore 45, TransportRegistry 42, ConfigParser 200, AppFeatures 54, Protocols 35+)
  - TransportConfig + Registry + per-protocol buildOutbound + ServerDetailView shipped
  - UAT отложен пользователем — 5 пунктов manual checks ждут (SwiftData migration, chevron nav, picker persistence, WS override connect, Trojan-WS regression)

## Progress

| Phase | Name | Version | Status |
|-------|------|---------|--------|
| 1 | Foundation | v0.1 | ✓ Complete 2026-05-11 |
| 2 | Trojan + Import flow | v0.2 | ✓ Complete 2026-05-12 — UAT T0-T9 PASS |
| 3 | Server management | v0.3 | ✓ Complete 2026-05-12 — UAT T1-T8 PASS |
| 4 | Protocol expansion | v0.4 | ✓ Complete 2026-05-12 — UAT deferred (manual) |
| 5 | Transports | v0.5 | ✓ Complete 2026-05-13 — UAT deferred (manual, 5 checks) |
| 6 | Network resilience | v0.6 | ✓ Implementation complete 2026-05-13 — UAT deferred (Task 3 A-I manual) |
| 6c | On-demand reconnect migration | v0.6.1 | ✅ Closed 2026-05-13 — re-UAT PASS pair; NET-08..11 Validated |
| 6d | Performance & Code Quality Audit _(INSERTED 2026-05-13)_ | v0.6.2 | ✅ Closed 2026-05-14 — 19 findings closed + 7 post-fix; UAT regression smoke PASS; PERF-01..05 + QUAL-01..03 Validated |
| 6e | Performance Audit Round 2 + macOS UAT replay _(INSERTED 2026-05-14)_ | v0.6.3 | ✅ Closed 2026-05-14 — 26 carved cleanup (19 code-fixed + 5 subsumed-by-6d + 2 deferred L16/L18) + 3 trivial imports; QUAL-04 + QUAL-05 Validated |
| 7 | Anti-DPI suite + WireGuard family | v0.7 | ✓ Complete 2026-05-14 — Phase 7a+7c (TUIC v5, anti-DPI, engine boundary) |
| **8** | **Rules Engine + Split tunneling** | **v0.8** | **Implementation complete 2026-05-15 — UAT pending (M-04/M-05/M-07/M-08 manual)** |
| 9 | Deep links | v0.9 | Wave 3/4 complete — Wave 3 app wiring + VM integration done; Wave 4 (AASA + Portal) pending |
| 10 | Advanced settings + Security polish | v0.10 | Not started |
| 11 | Onboarding + UX polish | v0.11 | Not started |
| 12 | Pre-release + Public TestFlight | v0.12 + v1.0 | Not started |

## Accumulated Context

### Recent decisions (Phase 9 Wave 3 — 2026-05-15)

- **D-09 cold-start buffer (DEEP-05)** — `initialManagersApplied` guard in `routeOrBuffer()` before dispatching to `handleDeepLink`; URL buffered in `@State private var pendingDeepLink: URL?` in root view; flushed in `.task` modifier after both `wireRulesCoordinator` calls complete. Applied identically on iOS and macOS.
- **macOS Universal Links Pitfall #1** — `.onOpenURL` does NOT deliver Universal Links on macOS (they open Safari instead). Must add `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` alongside `.onOpenURL` on both platforms. Documented in `09-RESEARCH.md`.
- **DEC-06d-01 for DeepLinkRouter** — `DeepLinkRouter()` init is cheap (actor init, no I/O); `ImportHandler` registration deferred to `Task.detached(priority: .utility)` — mirrors `RulesEngineCoordinator.bootstrap()` pattern.
- **DEEP-01/02/05 Validated (code-side)** — entitlements, Info.plist, `.onOpenURL`, `.onContinueUserActivity`, `handleDeepLink` all wired. Wave 4 preconditions: Apple Portal capability + AASA server hosting remain.

### Recent decisions (Phase 8 — 2026-05-15)

- **D-01 sing-box route.rule_set** — Server-side SRS binary pipeline; sing-box auto-reload from App Group; `SingBoxConfigLoader.expandConfigForTunnel` injects 3 rule_set entries + 3 priority rules. Invariant gate: `validate-r1-r6.sh` R8/R8b.
- **D-04 server-side country resolve** — VPS expands `countries:["RU"]` to CIDR set at signing time (no client MMDB). Accuracy depends on admin GeoIP source.
- **D-07 two-file Ed25519 sig** — `manifest.json.sig` + per-SRS `.sig`; `swift-crypto` `Curve25519.Signing.PublicKey.isValidSignature`. 32-byte pubkey compile-time constant in `PublicKey.swift`; invariant: R12 in `validate-r1-r6.sh`.
- **D-08/D-09 AppProxy deferral + target deletion** — L4↔L3 mismatch + mutual exclusivity → target deleted in W0. D-08 invariant gate in `validate-r1-r6.sh`. Full doc: `wiki/appproxy-deferral-2026.md`.
- **D-12 cold-start non-blocking** — Baseline SRS из bundle → App Group на first launch; BG fetch schedule via BGAppRefreshTask/NSBackgroundActivityScheduler. Per DEC-06d-01 pattern.
- **D-13 sequential mirror failover** — concurrency=1 при fetch; per DEC-06d-04 bounded probe concurrency.
- **Codex threads**: `019e2841` (Area A architectural — sing-box rule_set strategy) + `019e284c` (Area D — AppProxy deferral). All 4 Open Questions in RESEARCH.md resolved.
- **Wiki sync**: `wiki/rules-engine.md` полная перезапись (D-01..D-13 + архитектура + rotation v1.x + return conditions); `wiki/architecture.md` Phase 8 updates; `wiki/security-gaps.md` R20 entry; `wiki/log.md` daily entry.

### Recent decisions (Phase 6)

- **D-01 bootstrap DNS strategy** (2026-05-13) — `buildDNSConfig` selects `tcp://<server-IP>` when first parsed config has IPv4 host; otherwise AdGuard `tcp://94.140.14.14` fallback. **Yandex `77.88.8.8` полностью искоренён из shipping code** (`grep -RIn "77.88.8.8" Packages/ | grep -v .build/ | grep -v Tests/` = 0).
- **D-02 tunnel DNS default** (2026-05-13) — Cloudflare DoH (`https://1.1.1.1/dns-query`) when no custom DNS + no AdBlock.
- **D-03 custom DNS priority** (2026-05-13) — non-empty validated `customDNS` overrides; AdBlock toggle ignored when custom set.
- **D-04 AdBlock toggle** (2026-05-13) — `customDNS` empty + `adBlockEnabled == true` → AdGuard DNS (`94.140.14.14` / `94.140.15.15`).
- **D-07 retry policy** (2026-05-13) — 3 attempts × 2/4/8 s exp backoff via `ReconnectStateMachine` actor; on exhaustion → `.allFailed` → `notifyReconnectFailed`.
- **D-08 failover** (2026-05-13) — `SwiftDataFailoverProvider` actor: round-robin cursor over `isSupported == true` servers sorted by `id.uuidString`; cursor seeded at currently-selected server; full circle → nil → `.allFailed`; single-server pool → `notifySingleServerUnavailable` + nil; reset triggers: manual disconnect OR 30s+ stable `.connected` (with `startedAt` race guard per Pitfall 4).
- **TunnelController promoted to actor** (2026-05-13) — was `final class @unchecked Sendable`; Phase 1-5 `connect()/disconnect()` bodies preserved verbatim; new state (`manualDisconnectInProgress`, `lastSuccessfulConnectAt`, `wakePending`, `failoverProvider`) actor-isolated. `setFailoverProvider(_:)` late-binds the real provider to break VM↔Controller init cycle (`[weak tunnel]` connect closure).
- **Pitfall 10 macOS wake** (2026-05-13) — `NSWorkspace.shared.notificationCenter.addObserver(forName: .NSWorkspaceDidWake)` (NOT `NotificationCenter.default` — wake events only fire on workspace center). `handleWake()` sets `wakePending` flag; next `NetworkReachability.satisfied` event consumes it and triggers recovery.
- **6 × sing-box templates** (2026-05-13, Wave 2) — JSON bootstrap DNS swapped Yandex → AdGuard (VLESS-Reality, VLESS-TLS, Trojan-TCP, Trojan-WS, Shadowsocks, Hysteria2). These are legacy single-protocol templates — production runtime uses PoolBuilder, which threads `DNSConfig` from `buildDNSConfig`.

### Recent decisions (Phase 4)

- **D-02 VLESS branching** (2026-05-12) — VLESSURIParser breaks on presence of `pbk`/`sid` params: with → `.vlessReality`; without → `.vlessTLS`. This is a breaking change to the parser return type (now returns `AnyParsedConfig` instead of `ParsedVLESS`).
- **D-08 R1 exception for Hysteria2** (2026-05-12) — Only Hysteria2 sets `allowInsecure` based on URI params. All other protocols hardcode `insecure: false`. Enforced at 3 layers: type system (no allowInsecure field on non-Hy2 structs), hardcoded literals in templates, invariant test `test_nonHy2_outbounds_neverHaveInsecureTrue`.
- **D-09 dual scheme** (2026-05-12) — Both `hy2://` and `hysteria2://` schemes supported; all three insecure synonyms (`insecure`, `allowInsecure`, `skip-cert-verify`) collapse to one Bool.
- **Yams 6.2.1 + octal quirk** (2026-05-12) — Added Jpsim/Yams for Clash YAML parsing. Values like `short-id: 01234567` parsed as octal integers by Yams — mitigated with `stringValue()` helper that calls `.description` on Int.
- **SIP002 dual-path for SS** (2026-05-12) — AEAD-2022 methods (`2022-blake3-*`) use percent-encoded userinfo; legacy methods use base64url. `URLComponents.password` splits on `:` — fixed with explicit userinfo reassembly before splitting.
- **runIsSupportedUpgrade throttle** (2026-05-12) — D-14 auto-upgrade: 5-min throttle via UserDefaults `bbtb.lastIsSupportedUpgrade`; fetch-all + Swift filter (not `#Predicate` on UUID — same bug as Phase 3); `rawURI = nil` on success (T-02-04 invariant).
- **Security Phase 4** (2026-05-12) — 7 threats T-04-06-01..T-04-06-07: all mitigated or accepted. R1 invariant preserved across all 5 protocols. No new carry-forwards beyond existing WR-* list.

### Recent decisions (Phase 3)

- **D-14: SNI исключён из identity key** (2026-05-12) — Subscription-серверы с Reality ротируют SNI (anti-fingerprint). identity = `host:port:protocolID`. SNI обновляется в UPDATE-ветке SubscriptionMergeService. Commits `2077fa7`, `84192a1`.
- **SwiftData #Predicate UUID?** (2026-05-12) — `#Predicate { $0.optionalUUID == uuid }` молча возвращает empty на реальных устройствах. Везде заменено на `context.fetch(all).filter { ... }`. Commit `84192a1`.
- **TunnelController disconnect race** (2026-05-12) — `stopVPNTunnel()` fire-and-forget; `connect()` видел `.disconnecting` и бросал ошибку. `disconnect()` теперь поллит до `.disconnected` (max 5s, 0.5s шаг). `connect()` трактует `.disconnecting` как transient. Commit `b5d3120`.
- **Security Phase 3** (2026-05-12) — T-03-01..T-03-09 (Plan 01-04) + T-03-23..T-03-27 (Plan 05): все mitigated или accepted. WR-01..WR-11 carry-forward: Phase 4 (WR-01/05/07) / Phase 7 (WR-02/11) / Phase 11 (WR-03/04/06/08/09/10). Подробности — `wiki/security-gaps.md` R15/R16.

### Recent decisions (Phase 2)

- **Trojan-WS ALPN** (2026-05-12) — ALPN `["h2", "http/1.1"]` нельзя использовать для Trojan-WS: при TLS handshake сервер выбирает h2, WebSocket upgrade (HTTP/1.1) отвергается. Фикс: `PoolBuilder` и шаблон `trojan-ws.json` используют `["http/1.1"]` для WS-транспорта. Commit `4255a77`.
- **NETunnelNetworkSettings.tunnelRemoteAddress** (2026-05-12) — `proto.serverAddress` должен быть валидным IP/hostname (iOS отвергает произвольные строки типа `"BBTB"`). Значение = `host` первого supported outbound из пула. Commit `39356a4`. См. memory `feedback_netunnelnetworksettings_tunnelRemoteAddress.md`.
- **Security audit Phase 2** (2026-05-12) — 13 threats: 11 COVERED, 1 PARTIAL (T-02-04 rawURI → зафикшен), 1 ACCEPT (T-02-03 audit log → Phase 12). 0 BLOCKER. Carry-forward: W-02-09 (fetcher body-size/redirect cap → Phase 7), W-02-10 (macOS `network.server` entitlement → Phase 10). Commit `2c52e27`.

### Recent decisions (Phase 1)

Полный лог решений — `wiki/security-gaps.md` (R1–R11) и `.planning/PROJECT.md` Key Decisions table. Кратко:

- **R10** (2026-05-11) — TUN inbound runtime expansion + sing-box 1.13 DNS-hijack migration. R1 = default-deny white-list `{tun, direct}`; `SingBoxConfigLoader.expandConfigForTunnel` публичный + idempotent; post-expand re-validation defense-in-depth.
- **R11** (2026-05-11) — Phase 1 security audit closed: 37/37 threats verified. См. `.planning/phases/01-foundation/01-SECURITY.md`.
- **${VLESS_FLOW} placeholder** (commit `9aa3e93`) — template support dual-config (Vision-enabled + non-Vision URIs); flow extracted из URI вместо hardcoded `xtls-rprx-vision`.

### Blockers / Concerns

- ⚠️ **[Phase 11 follow-up]** Empty-state UX issue: после удаления VPN profile из iOS Settings, MainScreen остаётся в `error` state без recovery action. Workaround: delete + reinstall. Fix план — auto-recreate manager при старте если активный ServerConfig есть, а manager отсутствует. Связано с REQ UX-02, CORE-07.
- ⚠️ **[Phase 11 follow-up]** SocksProbe UX — verdict UI должен различать «BBTB process» от «другие процессы на устройстве» через PID attribution. Сейчас port 1080 от AdGuard/iCloud Private Relay показывается как FAIL.
- ⚠️ **[Phase 12 prerequisite]** Apple Distribution credentials — перед TestFlight upload создать Apple Distribution cert + App Store profiles для `app.bbtb.client.ios` и `app.bbtb.client.ios.tunnel`. Phase 1 DIST-02 export на этом упал (UAT T7 partial); archive (DIST-01) сам собирается.
- ⚠️ **[Phase 11/12]** W2-05 iOS 16.1+ Apple-leak документация — promote из `.planning/phases/01-foundation/01-RESEARCH.md:277,982` в отдельную wiki-страницу либо в FAQ.

## Next Action

**Phase 6e ✅ Closed 2026-05-14 — Performance Audit Round 2 (tactical cleanup, v0.6.3).**

**Следующий шаг:** `/gsd-discuss-phase 7` — Anti-DPI suite + WireGuard family (v0.7). PROTO-06 (WireGuard через WireGuardKit) + PROTO-07 (AmneziaWG) + PROTO-08 (TUIC v5) + PROTO-09 (OpenVPN/TLS) + DPI-01..05 (uTLS fingerprint mimicking, ClientHello фрагментация, packet padding, random TCP/UDP delay, Mux) + DPI-07 (разные порты).

**Backlog (carry forward в Phase 7+):**

- **L16** — applyVPNStatus extraction (Phase 6e Wave 2 Theme C-2 deferred per Codex no-go) → Phase 6f либо integrated в Phase 7+ refactor.
- **L18** — lazy `serverListViewModel` (Phase 6e Wave 2 Theme A deferred per architectural incompatibility) → Phase 6f либо Phase 7+.
- **MainScreenView.swift:15** — unused `@Environment(\.scenePhase)` declaration (leftover из Wave 1 M7 `ca21fa9`) → Phase 6f либо Phase 7+. Trivial 1-line removal.
- **NET-12** (active liveness probe — Pitfall 5 soft-kill server detection) — Phase 7-8 carve-out.
- **Numerical Instruments baseline** (Time Profiler / Energy Log / Allocations) — Phase 11/12 pre-TestFlight obligatory snap. PerfSignposter готов (DEC-06d-06).
- **macOS UAT replay** (5 scenarios A / F-direct / F-reverse / Settings-disable / G) — Phase 11/12 pre-TestFlight polish.
- **Historical Phase 6 UAT (sub-tests A-I — DNS leak / IPv6 leak / single-server notification)** — субсумированы Phase 6c re-UAT + 6d regression smoke. Phase 12 pre-TestFlight checklist если потребуется отдельный smoke.

## UAT findings (накапливаются)

**Fixed во время UAT Phase 2:**

- `6d0f798` — TrojanURIParser default fingerprint при пустом `fp=` (был `""`, стал `"chrome"`).
- `39356a4` — ConfigImporter `serverAddress` ставился literal `"BBTB"`, что отвергалось iOS как невалидный `tunnelRemoteAddress`. Восстановлено Phase 1 поведение (host первого outbound).

**Fixed во время UAT Phase 3:**

- `84192a1` — SwiftData `#Predicate { $0.subscriptionID == UUID? }` тихо возвращал empty; заменён на fetch-all + Swift filter в SubscriptionMergeService и ServerListViewModel.
- `2077fa7` — Subscription-серверы ротируют SNI (Reality anti-fingerprint); SNI исключён из identity key `host:port:protocolID`; SNI обновляется в UPDATE-ветке merge.
- `b5d3120` — T6 reconnect: `disconnect()` не ждал реального закрытия туннеля; добавлен poll до `.disconnected` (max 5s); `connect()` теперь пропускает `.disconnecting` как transient.

**Phase 11 backlog (UX polish):**

- Tunnel error message не отображается в `.error` state (только pill, без подробного текста).
- Wrapped error text — alert показывает технические префиксы из enum-обёрток (`Parse: Fetch failed: ...`). Должна показываться только пользовательская строка.
- Empty-state layout уточнён через диалог (карточка с 2 кнопками, не только текст).

После полного UAT:

- `/gsd-discuss-phase 3` — Server management (server-list UI, pull-to-refresh, multi-subscription).

## Известные не-блокеры Phase 2

- **macOS Debug signing-cert**: Phase 1 DIST-02 carry-forward gap, не Phase 2 regression. Перед Phase 12 TestFlight нужно создать Distribution cert + App Store profiles для `app.bbtb.client.macos` и `.macos.tunnel`.
- **W-02-09**: Subscription/JSON fetcher не имеют body-size cap и redirect-chain cap. Defence-in-depth gap, deferred to Phase 7 (DPI-08 cert pinning).
- **W-02-10**: Orphan `com.apple.security.network.server` entitlement на macOS app. Deferred to Phase 10 (вместе с R5 enforceRoutes toggle).
- **T-02-03**: Repudiation — нет audit-логов импорта/connect. Deferred to Phase 12.

## Phase 2 Artefacts

`.planning/phases/02-trojan-import-flow/` содержит:

- `02-CONTEXT.md` (15 decisions, 4 areas)
- `02-DISCUSSION-LOG.md` (audit trail)
- `02-UI-SPEC.md` (757 lines, design contract)
- `02-RESEARCH.md` (2817 lines, sing-box + Apple APIs)
- `02-PATTERNS.md` (1554 lines, Phase 1 analog map)
- `02-PLAN.md` (3412 lines, 7 waves × 34 tasks)
- `02-PLAN-CHECK.md` (plan-check: APPROVED, 0 HIGH)
- `02-EXECUTION-LOG.md` (chronological deviation log)
- `02-SECURITY.md` (12/13 closed, 0 BLOCKER)
- `02-VERIFICATION.md` (8/8 SC PASS in code)
- `02-UAT.md` (9 device tests T1-T9)

---
*Last updated: 2026-05-15 после завершения Phase 9 Wave 3 (09-03-PLAN.md: App Wiring + VM Integration). Deep links code-side complete: Tuist + entitlements + Info.plist + root view URL delivery chain (iOS + macOS) + D-09 cold-start buffer + MainScreenViewModel.handleDeepLink + 2 integration tests. 164/164 AppFeatures tests PASS. DEEP-01/02/05 Validated (code-side); Wave 4 preconditions: Apple Portal capability + AASA server hosting. completed_plans: 49.*
