# Журнал изменений wiki

Хронологическая запись всех операций над wiki. Append-only.

---

## 2026-05-16 — Phase 11 ✅ Closed (Onboarding + UX polish, v0.11)

Phase 11 implementation complete (8/8 plans, 5 waves). UX-01 / UX-08 / DETECT-01 / DETECT-02 / TELEM-02 / LOC-02 / LOC-03 / LOC-04 / IMP-03 ✅ Validated (9 ✓). UX-09 ⏸ figma-pending (Task 7.4 checkpoint signal — pixel-perfect re-Validated в Phase 12). DETECT-03 ⚙️ Infrastructure-validated (admin handoff `wiki/max-domains-blocklist.md` ready; server-side rules.json signing → Phase 12+ prerequisite).

**Scope Phase 11 (8 планов, 5 waves):**

- `11-01` (Wave 1) — Foundation: ~30 L10n keys onboarding/help/diagnostics/import-file/transport + LOC-02 cleanup ConfigImporter + TransportPicker 5 labels через L10n + lint-test
- `11-02` (Wave 2) — IMP-03: `ImportSource.file` case в VPNCore + `MainScreenView .fileImporter` modifier в Menu «+» + security-scoped resource + 3 tests
- `11-03` (Wave 2) — UX-01: `OnboardingView` fullScreenCover + `@AppStorage("app.bbtb.hasShownOnboarding")` sticky-forever + auto-dismiss + 3 tests
- `11-04` (Wave 2) — DETECT-01/02: `MAXDetector` silent service iOS `canOpenURL` + macOS `NSWorkspace.urlForApplication`; Info.plist `LSApplicationQueriesSchemes` + `wiki/max-domains-blocklist.md` (DETECT-03 admin handoff doc)
- `11-05` (Wave 3) — TELEM-02: `DiagnosticsExporter` actor (sing-box.log read → IP-mask D-12 → tmp file) + `DiagnosticsSection ShareLink` cross-platform + 5 tests
- `11-06` (Wave 3) — LOC-03/04: `HelpView` с 5 FAQ `DisclosureGroup` + NavigationLink из Settings + LOC-04 keyword check test
- `11-07` (Wave 4) — UX-08 ConnectionButton spinner overlay + UX-09 Figma polish (signal=figma-pending) + D-08 ServerListSheet height constants TODO + human-verify checkpoint resolved
- `11-08` (Wave 5) — Closure: regression gate (AppFeatures 207/207 + VPNCore 57/57 + ConfigParser 243/243 + PacketTunnelKit 91/91 + Localization build OK + iOS xcodebuild SUCCEEDED + macOS xcodebuild SUCCEEDED ad-hoc + LOC-02 lint 0/0 + R1/R6 invariants ALL PASS) + REQUIREMENTS/ROADMAP/STATE validated marks + wiki long-term memory + Final-SUMMARY

**Figma cleanup session 2026-05-15/16** (Task 7.4 follow-up, commit `cc7b216`):

- Figma file BBTB v3 cleaned: 51 variables (Primitives 11 + DS 40) в Dark+Light modes (Education plan native modes), 3 component sets (Button / Button_BG / Spinner) + 2 standalone (ServerRow default + selected + AutoCell), 50+ generic frame names → semantic, 6 orphan tokens удалены
- Code Connect Swift mappings создан как documentation contracts: 4 `.figma.swift` файла wrapped в `#if canImport(CodeConnect)` guard (compile-inert без SDK)
- Education plan blocker: `code_connect:write` scope недоступен; Organization+ tier ($45/user/mo) required для publish — `.figma.swift` файлы активируются automatically при upgrade plan
- 10 pixel-perfect mismatches M1-M10 enumerated в `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §4 — carry-forward в Phase 12
- Phase 12 redefined 2026-05-16 — was «TestFlight & Distribution», now «Swift pixel-perfect rebuild from Figma» (v0.12-design). TestFlight & Distribution moved to **Phase 13** (v0.13 + v1.0).

**Key decisions зафиксированы (см. `wiki/onboarding-ux-polish-2026.md` для детали):**

- D-01 — sticky-forever флаг `@AppStorage` (UX-01)
- D-02 — single-screen Onboarding с 2 CTA (UX-01)
- D-04 — File picker НЕ в Onboarding, только меню «+» (IMP-03)
- D-05 — ConnectionButton spinner = `ProgressView` overlay placeholder; Phase 12 заменит на custom 4-frame ring (UX-08)
- D-07 — Two-stream architecture: code stream + UI polish stream (UX-09)
- D-08 — ServerListSheet heights TODO (Phase 11 deferred to Phase 12 pixel-perfect rebuild)
- D-10 — Diagnostics section в Settings (TELEM-02)
- D-11 — Share Sheet без backend через `ShareLink(item: URL)` (TELEM-02)
- D-12 — IP-маскировка regex `(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}` → `$1xxx` (TELEM-02)
- DS-01..06 — design system tokens session decisions (two-tier model, Dark+Light modes, Education plan limitations)

**Wiki changes (Phase 11 closure):**

- [[onboarding-ux-polish-2026]] (НОВАЯ) — long-term memory: D-01..D-12 decisions + DS-01..06 design system + MAX-detection candidates + patterns + 10 Phase 12 mismatches
- [[max-domains-blocklist]] (создан Plan 04) — admin handoff documentation для DETECT-03 server-side activation
- [[index]] (ОБНОВЛЁН) — добавлена ссылка на `onboarding-ux-polish-2026.md`

**Tests (final regression gate):**

- AppFeatures: 207/207 PASS
- VPNCore: 57/57 PASS (1 skipped)
- ConfigParser: 243/243 PASS
- PacketTunnelKit: 91/91 PASS
- Localization: Build complete
- iOS xcodebuild (iPhone Simulator): SUCCEEDED
- macOS xcodebuild: SUCCEEDED (ad-hoc signing; Phase 1 DIST-02 carry-over — Distribution credentials prerequisite для Phase 13 TestFlight)
- LOC-02 lint: 0 Russian hardcoded + 0 English `Text("...")` hardcoded
- R1/R6/R10/R12/D-08 invariants: ALL PASS (`validate-r1-r6.sh`)

**Outstanding (carry-out):**

- **Phase 12 (Swift pixel-perfect rebuild from Figma, v0.12-design):** 10 mismatches M1-M10 + UX-09 full re-Validated
- **Phase 13 (TestFlight & Distribution, v0.13 + v1.0):** DETECT-03 admin handoff + Apple Distribution credentials + SPKI subscription pins replacement + macOS UAT replay (5 scenarios) + Numerical Instruments baseline

**Commits Phase 11 (key references):**

- Wave 1 (`2cc1041`) — L10n foundation + LOC-02 cleanup + IMP-03 (combined)
- Wave 2 (`d3e2773` merge) — DETECT-01/02 + Onboarding + IMP-03 wiring
- Wave 3 (`7765757`) — TELEM-02 DiagnosticsExporter + DiagnosticsSection
- Wave 3 (`21fc9c6`) — LOC-03/04 HelpView
- Wave 4 (`e23c6bc`) — UX-08 ConnectionButton spinner overlay
- Wave 4 (`4913a46`) — D-08 ServerListSheet height TODO + 4 height regression tests
- Wave 4 (`908e8e7`) — UX-09 OnboardingView Figma polish TODO marker
- Wave 4 (`cc7b216`) — Figma cleanup + Code Connect Swift mappings (session 2026-05-15/16)
- Wave 5 closure — REQUIREMENTS/ROADMAP/STATE/wiki/Final-SUMMARY

**Next:** `/gsd-discuss-phase 12` — Swift pixel-perfect rebuild from Figma (v0.12-design).

---

## 2026-05-15 — Phase 10 ✅ Closed (Advanced Settings + Security Polish, v0.10)

Phase 10 implementation complete (6/6 plans executed). UX-06/BIO-01..04/DPI-05/DPI-06/DPI-08/DPI-09/ONDEMAND-01/KILL-04 scope закрыт. DPI-06 (CDN fronting) — infrastructure-ready, activation pending Phase 11 admin handoff.

**Scope Phase 10 (6 планов):**
- `10-01` — AdvancedSettingsView (D-15 layout): uTLS picker, Mux toggle, CDN-фронтинг toggle, cert pinning toggle, STUN block toggle, macOS enforceRoutes toggle
- `10-02` — BiometricAuth: Face ID / Touch ID + LAContext + UX-06 (passphrase vault), BIO-01..04
- `10-03` — OnDemand / Mux: ONDEMAND-01 advanced rules + DPI-05 Mux (SingBoxConfigLoader injection)
- `10-04` — Cert pinning (DPI-08): PinStore + PinnedSessionDelegate + SubscriptionPinManager (actor) + PinnedSubscriptionURLFetcher; STUN block (BIO-04 complementary)
- `10-05` — CDN fronting package (DPI-06): FrontingEngine SwiftPM (FrontingProfile, 3 CDN adapters, FrontingConfigApplier, FrontingFailureCache, FrontingFallbackChain)
- `10-06` — Integration wave (W4): FrontingEngine wired into Tuist/AppFeatures; uTLS global picker override (DPI-09) в PoolBuilder; CDN hook в ConfigImporter (graceful degradation)

**Key decisions зафиксированы:**
- D-03: FrontingProfile — отдельный struct, не часть TransportConfig (ортогональный CDN-слой)
- D-05: CDN overlay blacklist (Reality/TUIC/Hy2/Vision — не совместимы с CDN overlay)
- D-06: Failure chain с cooldown ladder (6/12/24 часа по score)
- D-11: validUntil hard reject для remote pin manifest (replay attack защита)
- D-15: AdvancedSettingsView layout (5 секций, destructive STUN alert, macOS-only enforceRoutes)
- DPI-09 uTLS picker: URI fp= (non-"random") имеет приоритет над global picker

**Requirements promoted / validated:**
- UX-06 `[x]` ✅ (AdvancedSettingsView, биометрия)
- DPI-05 `[x]` ✅ (Mux injection в SingBoxConfigLoader)
- DPI-06 `[ ]` ⚙️ Infrastructure-only (extractFrontingProfile returns nil до Phase 11)
- DPI-08 `[x]` ✅ (SPKI SHA-256 cert pinning, Phase 12 prerequisite: реальные пины)
- DPI-09 `[x]` ✅ (uTLS global picker override)
- BIO-04 `[x]` ✅ (биометрия + STUN block)
- KILL-04 `[x]` ✅ (macOS enforceRoutes toggle)

**Wiki changes (Phase 10 closure):**
- [[advanced-settings]] (НОВАЯ) — AdvancedSettingsView D-15 layout; таблица тогглов; macOS-only gates
- [[cdn-fronting-architecture-2026]] (НОВАЯ) — FrontingEngine package; D-03/D-05/D-06 decisions; v0.10 status
- [[cdn-fronting-server-handoff]] (НОВАЯ) — инструкции для admin Marzban; Cloudflare Worker; FrontingProfile JSON
- [[cert-pinning-spki]] (НОВАЯ) — Apple Security SPKI pipeline; generate-spki-pin.swift; Phase 12 rotation procedure
- [[anti-dpi-techniques]] (ОБНОВЛЕНА) — добавлен раздел «Phase 10 toggles»; roadmap entry v0.10
- [[architecture]] (ОБНОВЛЕНА) — FrontingEngine в packages list; PinStore/PinnedSessionDelegate/SubscriptionPinManager
- [[security-gaps]] (ОБНОВЛЕНА) — R21 (cert pinning) + R22 (STUN block) + R23 (enforceRoutes) + R24 (CDN fronting)
- [[index]] (ОБНОВЛЕН) — cdn-fronting-*, cert-pinning-spki, advanced-settings добавлены

**Phase 12 prerequisite зафиксирован:**
- `project_phase12_subscription_pins_prerequisite.md` в MEMORY — placeholder пины в PinStore.swift ДОЛЖНЫ быть заменены через `generate-spki-pin.swift` ДО TestFlight upload (иначе все subscription requests упадут с pinning mismatch)

**Commits Phase 10-06 (final wave):**
- `a20993b` — test(10-06): TDD RED — failing PoolBuilderTests for uTLS picker override
- `dbe86f6` — feat(10-06): TDD GREEN — Tuist/AppFeatures wire + uTLS picker + CDN hook
- [docs commit] — Phase 10 closure docs + wiki sync

**Next:** Phase 11 — сервер-клиент интеграция (admin handoff CDN, real SPKI pins, universal links AASA), Phase 12 — TestFlight distribution.

---

## 2026-05-14 — Phase 7c ✅ Closed (Engine Boundary Cleanup, HYBRID variant)

После Phase 7b cancellation 2026-05-14, пользователь напомнил project core principle (Claude.md line 112): «Всегда предлагай и ставь такие варианты в приоритет, которые в будущем помогут проще маштабироваться (20 протоколов, 50+ транспортов)». Запрос: заложить основу для модульности и масштабируемости.

Запущен Codex deep research thread `019e2802-ed23-7f21-bd6a-138edea62528` (production iOS VPN multi-engine architecture survey). Verdict: **HYBRID** — boundary cleanup сейчас, full `protocol TunnelEngine` defer до реального второго engine. Production evidence: ни один production iOS VPN client не использует pre-built protocol abstraction с одной реализацией (Hiddify mono-engine, Amnezia switch-dispatch, IVPN separate extensions, Mullvad/Proton single-family).

User decision 2026-05-14: «Окей, делаем. Вариант B».

**Что сделано:**
- **Sing-box-specific код контейнеризован** в `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/`:
  - `BaseSingBoxTunnel.swift` (relocated, +breadcrumb-marker comment)
  - `ExtensionPlatformInterface.swift` (relocated)
  - `SingBoxConfigLoader.swift` (relocated)
  - `Resources/SingBoxConfigTemplate.vless-reality.json` (relocated)
  - `Package.swift` `resources:` path обновлён
- **Engine-agnostic utilities остались at top level**: AppGroupContainer, TunnelSettings (R6-safe), TunnelLogger, ExternalVPNStopMarker (Phase 6d), InterfaceFlagsInspector, PlatformSpecific/iOS+macOS.
- **`BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md`** (новый) — code-level decision document с триггерами для введения `protocol TunnelEngine`, recommended patterns (Path A switch-dispatch / Path B separate extensions), anti-patterns (generic naming запрещён пока один engine).
- **Cross-references обновлены**: PoolBuilder.swift + VLESSReality/ConfigBuilder.swift doc comments + `BBTB/scripts/validate-r1-r6.sh` paths + `wiki/security-gaps.md` § R10/R11 file references.
- **Pre-existing Phase 7a Wave 1 bug найден и исправлен**: `VPNCoreTests/ParsedConfigsTests.swift` exhaustiveness gate не был обновлён под `.tuic` case (был 9-й switch site, я обновил 8 в Wave 1). Теперь VPNCore tests проходят чисто.

**НЕ сделано (intentionally):**
- ❌ `protocol TunnelEngine` — НЕ создан (premature abstraction)
- ❌ `TunnelEngineFactory` / `TunnelEngineKind` enum — НЕ создан
- ❌ Placeholder engine файлы — НЕ создавались (становятся dead code)
- ❌ Generic-named classes — anti-pattern в decision doc

**Verification:**
- ✅ PacketTunnelKit 66/66 + ConfigParser 228/228 + AppFeatures 143/143 + TUIC 26/26 + Trojan/VLESSTLS/VLESSReality/Hysteria2/Shadowsocks все existing tests PASS.
- ✅ VPNCore — pre-existing bug зафикшен, tests PASS.
- ✅ `validate-r1-r6.sh` — 11 invariants PASS (R1/R6/KILL-01/SEC-03/SEC-05).
- ✅ tuist generate clean; iOS xcodebuild SUCCEEDED; macOS xcodebuild (ad-hoc signing) SUCCEEDED.
- ✅ Поведение приложения идентично — pure rename + reorganization.

**Wiki changes:**
- [[engine-abstraction-decision-2026]] (новая страница) — full decision log параллельно с openvpn / wireguard / amneziawg deferral pages.
- [[architecture]] — обновлена с описанием `SingBox/` namespace + ссылкой на decision page.
- [[security-gaps]] § R10 + R11 file references обновлены под новые paths.
- [[index]] — engine-abstraction-decision-2026 page registered.

**Триггеры для будущего введения `protocol TunnelEngine`** (см. EngineAbstractionDecision.md):
1. Buildable iOS spike для второго engine (AmneziaWG / OpenVPN-Partout) с реальным config'ом
2. Два engines coexist в одном TestFlight build (concrete product requirement)
3. PacketTunnelProvider gains second concrete lifecycle path с разными setup/teardown semantics
4. Engine lifecycle становится dominant complexity (overtakes config generation)

**Phase 7 финал** (включая 7a + 7c): 6 in-scope протоколов, mono-engine sing-box через libbox, sing-box код в чётком `SingBox/` namespace, engine abstraction triggers зафиксированы. Phase 7b cancelled. **v0.7 = v0.7.1** (Phase 7c — internal refactor без bumping).

**Next:** `/gsd-discuss-phase 8` (Rules Engine + Split tunneling, v0.8).

---

## 2026-05-14 — Phase 7b ❌ Cancelled (AmneziaWG 2.0 + engine abstraction → v2.0+ backlog)

После Phase 7a closure 2026-05-14, перед началом execute Phase 7b — запущен Codex deep research thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` для актуального состояния `amneziawg-apple` library + Amnezia VPN multi-engine reference. Ключевые факты:

- **`amneziawg-apple`** жив (latest commit 20 февраля 2026, MIT, AWG 2.0 встроен в Swift API), но Go bridge не самосборный — требует manual `libwg-go.a` через Makefile с Go 1.26 + GOROOT patches.
- **Amnezia VPN iOS reference** использует switch-dispatch в `PacketTunnelProvider.startTunnel`, Codex рекомендует НЕ копировать (нужен protocol-based clean boundary).
- **Go bridge на iOS 18** — memory footprint unknown (NetworkExtension 50MB limit), no crash isolation от Go panic, AWG 2.0 backward-incompat с v1.5 серверами.
- **Effort estimate**: 5-7 engineer-weeks full quality (включая crash isolation, real-device memory test, lifecycle race tests, CI prebuild artifact strategy).
- **User-base**: 50 friends-and-family с уже работающим Reality+Trojan+Hy2+TUIC стеком; AWG demand не подтверждён реальными запросами; X-UI/Marzban пока не поддерживают AWG 2.0 официально.

**User decision 2026-05-14:** «Давай отложим амнезию вообще на версию 2 или позднее.»

**Что переносится в Out of Scope (v2.0+ backlog conditional on demand):**
- PROTO-07 AmneziaWG 2.0
- DPI-04 random TCP/UDP delay (был AWG-bound — sing-box не поддерживает)
- Engine abstraction layer (был нужен ради AWG; без второго движка не нужен)

**Условие возврата:** 3+ независимых TestFlight запроса с рабочими AWG 2.0 подписками, ИЛИ ТСПУ поломал текущий стек, ИЛИ v2.0 milestone бюджет на architectural фазы.

**Финал Phase 7:** только Phase 7a сделано. v0.7 = v0.7.1 (нет v0.7.2). 6 in-scope протоколов в финальном MVP-наборе (VLESS+Reality, VLESS+TLS+Vision, Trojan, SS-2022, Hysteria2, TUIC v5). Архитектура остаётся **mono-engine sing-box** через `libbox.xcframework` v1.13.11.

**Wiki changes:**
- [[amneziawg-deferral-2026]] (новая страница) — полный decision log с research findings, эффект на REQUIREMENTS / ROADMAP / PROJECT, условие возврата.
- [[protocols-overview]] — обновлена с 8 → 6 in-scope протоколов; AmneziaWG 2.0 и OpenVPN strikethrough.
- [[anti-dpi-techniques]] — DPI-04 переведён с «AWG-only» в «Out of Scope»; roadmap обновлён.
- [[index]] — добавлена amneziawg-deferral-2026 ссылка.

**GSD updates:**
- `.planning/REQUIREMENTS.md` — PROTO-07 + DPI-04 → Out of Scope (strikethrough с rationale).
- `.planning/ROADMAP.md` — Phase 7b entry заменена на cancellation note; Global DoD обновлён «6 in-scope протоколов».
- `.planning/PROJECT.md` — Out of Scope расширена; R20 status обновлён 🟡 → ✅ Phase 7 fully Closed.
- `.planning/STATE.md` — Active Phase 7b → **Phase 8** (Rules Engine + Split tunneling); progress 71% → 85%.
- `.planning/phases/07-anti-dpi-suite-wireguard-family/07-CONTEXT.md` — добавлена «Phase 7b Cancellation Note» в шапке файла.

**Next:** `/gsd-discuss-phase 8` (Rules Engine + Split tunneling, v0.8).

---

## 2026-05-14 — Phase 7a ✅ Closed (TUIC v5 + anti-DPI smart defaults, v0.7.1)

Phase 7a iPhone UAT PASS на user's Trojan subscription `vpn.vergevsky.ru` (6 серверов). Из `debug-logs/` (5MB+): sing-box log (320KB) показывает сотни успешных Trojan-0 outbound connections к Instagram/Facebook/Apple Push/iTunes/iCloud с `tls.record_fragment: true` smart default; iOS Console (5MB) — ноль app crashes / fatalError / EXC_RESOURCE / PORT_SPACE / TLS handshake failures. Только expected noise (Trojan TCP-only UDP fallback, kernel NECP chatter, VPN extension lifecycle).

**Requirements promoted to Validated:**
- PROTO-08 TUIC v5 (architecture + unit tests; real connection test carved-out до появления TUIC сервера).
- DPI-01 uTLS random default.
- DPI-02 TLS ClientHello fragmentation (`tls.record_fragment` для VLESS+TLS / Trojan; не для TUIC per Codex QUIC «only ECH»; не для Reality/Vision — XTLS).
- DPI-07 порт diversity (URI парсеры уже принимали любой port).

**Carve-outs (carry-forward к Phase 7b и далее):**
- DPI-05 Mux infrastructure (smux/yamux/h2mux per-server) → Phase 10 unified PR с DPI-09 UI picker.
- TUIC connection device-UAT → conditional на появление TUIC сервера (self-host либо subscription provider).
- VLESS+Reality / Vision / TLS / Hy2 / SS-2022 device-UAT с новыми smart defaults — Trojan UAT даёт сильнейший signal, остальные exposed через future regression cycles.

**Commits:**
- `8ca1014` — feat(07a-w1): TUIC v5 protocol package (PROTO-08) +1418 lines / 21 files
- `1d98abc` — feat(07a-w2): anti-DPI smart defaults — uTLS=random + tls.record_fragment
- `cb6140b` — feat(07a-w4): register TUICHandler in apps + Tuist project
- `49c40d5` — docs(07a-w5): pre-UAT wiki sync + closure summary
- [this commit] — docs(07a): finalize closure after iPhone UAT PASS

**Next:** `/gsd-discuss-phase 7b` (Engine abstraction + AmneziaWG 2.0, v0.7.2).

---

## 2026-05-14 — Phase 7a 🟡 Pre-UAT → ✅ Closed (TUIC v5 + anti-DPI smart defaults, v0.7.1) — autonomous run

Phase 7a code-complete autonomous run per user request «выполни фазу до UAT тестов в автономном режиме». Waves 1+2+4 implemented, Wave 3 (mux infrastructure) intentionally deferred to Phase 10 для unified DPI-09 UI toggle PR (объясняется в `07a-PRE-UAT-SUMMARY.md`).

**Commits:**
- `8ca1014` — feat(07a-w1): TUIC v5 protocol package (PROTO-08) +1418 lines / 21 files
- `1d98abc` — feat(07a-w2): anti-DPI smart defaults — uTLS=random + tls.record_fragment
- `cb6140b` — feat(07a-w4): register TUICHandler in apps + Tuist project

**Технически закрыто:**
- TUIC v5 как 6-й protocol handler (sing-box outbound `type:tuic`, congestion_control + udp_relay_mode + R1 strict — НЕ Hy2 exception).
- `TUICURIParser` (18 tests) + `TUICHandler` + `TUIC.ConfigBuilder` (26 tests) + Clash YAML mapping.
- Анти-DPI smart defaults: uTLS=random для всех TLS, tls.record_fragment=true для VLESS+TLS / Trojan (Codex Q4 follow-up: NOT для TUIC — QUIC «only ECH»).
- TUICHandler регистрация в `BBTB_iOSApp` + `BBTB_macOSApp`.
- Tuist Project.swift расширен TUIC localPackage + product deps. iOS + macOS xcodebuild SUCCEEDED.

**Verification:**
- TUIC swift test 26/26 ✓.
- ConfigParser swift test 228/228 ✓ (+1 override-preserved invariant).
- AppFeatures 143/143 ✓.
- Trojan / VLESSTLS / Hysteria2 / VLESSReality / Shadowsocks — все existing tests preserved.
- `tuist generate` clean; iOS xcodebuild SUCCEEDED; macOS xcodebuild (ad-hoc signing) SUCCEEDED.

**Wiki changes:**
- [[anti-dpi-techniques]] — full update «Реальное состояние в sing-box 1.13.x (verified Phase 7a)» матрица (что доступно, что нет, default policy). DPI-04 → AmneziaWG-only; DPI-03 → mux-layer only; DPI-05 → infrastructure готова, default off.
- [[protocols-overview]] — 9 → 8 in-scope. WireGuard plain + OpenVPN strikethrough Out of Scope (linked to deferral pages). TUIC v5 + AmneziaWG 2.0 entries updated с Phase 7a/7b ссылками.

**Pre-UAT artifacts:**
- `.planning/phases/07-anti-dpi-suite-wireguard-family/07a-01-PLAN.md` — Wave 1 detailed plan (in commit `8ca1014`).
- `.planning/phases/07-anti-dpi-suite-wireguard-family/07a-PRE-UAT-SUMMARY.md` — full pre-UAT summary с commit hash table, test coverage, deferred items, UAT checklist.

**Awaits:**
- User builds v0.7.1 (bump version + build), uploads to TestFlight, distributes via External Testing.
- iPhone UAT smoke (по образцу Phase 6e UAT): TUIC import + connect + regression smoke 5 existing protocols + kill switch / on-demand R18 preserved.

**После UAT PASS:** REQUIREMENTS.md PROTO-08/DPI-01/DPI-02/DPI-07 → Validated; ROADMAP Phase 7a checkboxes ✓; STATE Active Phase → 7b.

---

## 2026-05-14 — Phase 7 discuss-phase ✅ Closed + 2 deferral decision logs

Phase 7 (Anti-DPI suite + WireGuard family) прошла `/gsd-discuss-phase 7` с deep research через Codex GPT-5 (3 advisory thread'а) + WebSearch по реальному статусу OpenVPN / WireGuard / AmneziaWG в РФ май 2026. Результат — 5 решений (D-01..D-05, см. R20 в `.planning/PROJECT.md`):

- **D-01:** PROTO-09 OpenVPN/TLS → Out of Scope, v1.x backlog conditional on TestFlight demand.
- **D-02:** PROTO-06 plain WireGuard → Out of Scope, v1.x backlog conditional.
- **D-03:** PROTO-07 AmneziaWG **2.0 only** через `amneziawg-apple` SwiftPM library + engine abstraction в Phase 7b.
- **D-04:** Phase 7 split на **7a** (v0.7.1, TUIC + anti-DPI smart defaults) + **7b** (v0.7.2, engine abstraction + AmneziaWG 2.0) с отдельными TestFlight-релизами и iPhone UAT-циклами.
- **D-05:** Anti-DPI **smart defaults** — uTLS=random автоматически, tls.fragment ON для VLESS+TLS/Trojan/TUIC, mux OFF (ломает Vision/Reality), URI overrides всегда.

**Reframes в REQUIREMENTS.md:**
- DPI-04 (random TCP/UDP delay) → covered by AmneziaWG 2.0 junk packets (Jc/Jmin/Jmax) в Phase 7b (sing-box не умеет).
- DPI-03 (packet padding) → mux-layer padding only, no global default.

**Wiki changes:**
- [[openvpn-deferral-2026]] (новая страница) — полное обоснование D-01: ТСПУ хронология blocks → Feb 2026 full block, OpenVPN+Cloak phased out из Amnezia Premium, OpenVPN XOR детектируется GRFC, Partout engine + GPLv3 cost, провайдер adoption (никто кроме Amnezia self-host).
- [[wireguard-deferral-2026]] (новая страница) — полное обоснование D-02: plain WG fixed-handshake детектируется, UDP closed in RU с лета 2025, AmneziaWG 2.0 покрывает нишу.
- [[index]] — добавлены 2 новые страницы в раздел «Anti-DPI и ТСПУ».

**GSD updates:**
- `.planning/phases/07-anti-dpi-suite-wireguard-family/07-CONTEXT.md` (новый, ~440 строк) — full downstream-agent contract.
- `.planning/phases/07-anti-dpi-suite-wireguard-family/07-DISCUSSION-LOG.md` (новый) — audit trail с Codex thread IDs.
- `.planning/STATE.md` — Active Phase: 7 (split на 7a + 7b), focus: Phase 7a planning autonomous.
- `.planning/ROADMAP.md` — Phase 7 entry replaced с Phase 7a + Phase 7b entries; Global DoD «9 протоколов» → «7 in-scope».
- `.planning/REQUIREMENTS.md` — PROTO-06/09 strikethrough Out of Scope; PROTO-07 narrowed to v2.0; DPI-01..05/07 annotated per smart-defaults matrix.
- `.planning/PROJECT.md` — Out of Scope расширена; Key Decisions добавлена R20.

**Carry-forward backlog:**
- AmneziaWG v1/v1.5 — conditional return on demand.
- `wg://` URI parser — НЕ Phase 7 (введёт в заблуждение).
- `vpn://` Amnezia URI format — Phase 7b discretion либо позже.
- Multi-engine hot-swap — future, после Phase 7b UAT pain signal.
- `wiki/amneziawg-integration.md` (decision log по engine abstraction + amneziawg-apple recipe) — создаётся **в Phase 7b** после первой рабочей integration.

**Files (new):**
- `wiki/openvpn-deferral-2026.md`
- `wiki/wireguard-deferral-2026.md`

**Files (updated):**
- `wiki/index.md` — § «Anti-DPI и ТСПУ» расширен 2 новыми страницами.

**Commits:** `9130e3c` (discuss-phase artefacts) + `444a09e` (ROADMAP/REQUIREMENTS/PROJECT sync) + (this commit, wiki).

---

## 2026-05-14 — Phase 6e ✅ Closed (Performance Audit Round 2 — tactical cleanup, v0.6.3)

Phase 6e — tactical cleanup-фаза после Phase 6d. Закрыты остатки 26 carved-out finding'ов из Phase 6d backlog с **hybrid closure rigor** (D-04): 4 atomic MEDIUM commit'а (per-commit regression gate) + 4 LOW bundle commit'а (single end-of-bundle gate) + 1 closure commit. Math (SCENARIO B + L18): 19 code-fixed (Wave 1: 5 = M7/M10/M8/L12/M11; Wave 2 bundles: 14) + 5 subsumed-by-Phase-6d (M6/M15/L6/L17/L19) + 2 deferred (L16 Codex no-go, L18 architectural incompatibility) = **26 ✓**. Дополнительно — 3 trivial unused imports (Wave 2 Theme D) → Periphery actionable 3 → 0 (QUAL-05 closure proof).

**Source:** `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/` (06E-CONTEXT, 06E-RESEARCH, 06E-PATTERNS, 06E-VALIDATION, 06E-01..03-PLAN, 06E-01/02/Final-SUMMARY)

**Code changes:**
- **Wave 1 (4 atomic MEDIUM):** M7 `ca21fa9` (scenePhase consolidate → `handleForegroundReentry`); M10 `6af41db` (loadFromStore idempotency + 100ms debounce); M8+L12 `368c82f` (validatedAt 24h cache marker — **R10 post-expand validate preserved unconditional**); M11 `4269570` (applyVPNStatus explicit early-return guard).
- **Wave 2 (4 LOW bundles):** Theme A perf `5c74423` (L3/L4/L7/L8/L11/L13); Theme B correctness `f857763` (L1/L9/L10/L20); Theme C-1 maintainability `a03007f` (L2/L5/L14/L15); Theme D trivial imports `f42499f` (3 imports). Theme C-2 (L16) **NOT committed** — deferred per Codex Plan Reviewer HIGH-RISK no-go + AUTO_MODE first-option safe-default.
- **Bookkeeping (5 subsumed-by-6d):** M6 (`1467328` + `9b38796`), M15 (`55bde6c`), L6 (`5ef3888`), L17 (`bc7bc26` + `1467328`), L19 (`b8d9294`) — no code change в Wave 2, tracking rows only.

**Invariants preserved (D-09 final 8-check grep audit PASS, см. 06E-Final-SUMMARY § 4):**
- DEC-06d-01..06 architectural patterns (cold-start defer, XPC ≤ 2 trips, event-driven status polling, bounded probe concurrency, Apple-canonical `options["manualStart"]` + ExternalVPNStopMarker, PerfSignposter spans).
- R10 defense-in-depth (post-expand `SingBoxConfigLoader.validate` ВСЕГДА runs; pre-expand теперь guarded by 24h cache).
- R18 sliding window (`toggle && intent` = 2 hits в OnDemandRulesBuilder.swift).
- D-09 invariants: forbidden symbols 0 actual usages (15 comment-only refs), NEVPN observer queue=.main = 0, `#Predicate UUID?` = 0 actual usage, applyVPNStatus = 1 actual func definition, ExternalVPNStopMarker `.consume(` callers = 0, PerfSignposter ≥ 20 production spans.

**Wiki changes:**
- [[performance-baseline]] — § «Open follow-ups (post-6e)» updated: 26 carved IDs → 19 closed in 6e + 5 subsumed-by-6d + 2 deferred (L16/L18) + 3 trivial imports закрыты separately (QUAL-05). Carry-forward backlog: NET-12 (Phase 7-8), Numerical Instruments + macOS UAT (Phase 11/12), L16/L18/MainScreenView scenePhase declaration (Phase 6f либо 7+).

**GSD updates:**
- `STATE.md` — Phase 6e row → ✅ Closed 2026-05-14; Active Phase → 7 (Anti-DPI suite + WireGuard family, v0.7); completed_phases 8 → 9; completed_plans +3.
- `ROADMAP.md` — Phase 6e plans `[x]` (все 3); Success Criteria checkboxes marked (Instruments + macOS UAT — Deferred → Phase 11/12 per D-02/D-03); Outcome note added.
- `REQUIREMENTS.md` — QUAL-04 Validated (с явным exception note про L16/L18 deferral); QUAL-05 Validated (Periphery actionable = 0).

**Регрессионные gate'ы (D-04 hybrid):** 4× Wave 1 per-commit + 1× Wave 2 end-of-bundle + 1× Wave 3 pre-closure (D-05a) = 6 gates total. Все green: AppFeatures 143/143 + PacketTunnelKit 66/66 + остальные пакеты baseline + iOS+macOS xcodebuild SUCCEEDED.

**Что дальше:** `/gsd-discuss-phase 7` — Anti-DPI suite + WireGuard family (v0.7). PROTO-06..09 + DPI-01..05 + DPI-07.

---

## 2026-05-14 — Phase 6d ✅ Closed (Performance & Code Quality Audit)

Triple-AI peer review (Claude Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) → 45 findings, 19 закрыто атомарными commits, 26 carved-out в backlog (Variant D, no pre-fix Instruments). Cold-start ~−500…−1100 мс, connect-tap ~−1000…−3000 мс, disconnect −2.5 сек, energy-win от eliminating shipping `logLevel: trace` + conditional ConnectionTimer publisher. Дополнительно — post-fix correctness saga для Settings-disable race (commits `5110ae0` → `9122bbd` → `cff3f46`) через App Group sticky marker (`ExternalVPNStopMarker.isPending`) + Apple-canonical `options["manualStart"]` discriminator (pattern derived from WireGuard iOS).

UAT regression smoke на iPhone iOS 26.5 (2026-05-14): все hard-blocker scenarios PASS (A, F-direct, F-reverse, G, I, Settings-disable; E deferred → NET-12; C macOS skipped — carry-over from Phase 6c). 6d-NEW-1 (cold-start ≤2sec) + 6d-NEW-2 (connect-tap responsive) PASS — pre-fix 4-8 sec white screen + 40 sec UI freeze устранены. Final regression gate: AppFeatures 133/133, iOS + macOS xcodebuild SUCCEEDED.

**Архитектурные decisions переехавшие в wiki:**
- [[performance-baseline]] new — pre/post comparison + DEC-06d-01..06 + methodology + 26 carved findings backlog.

**GSD updates:**
- STATE.md Phase 6d → ✅ Closed.
- ROADMAP.md Phase 6d → ✅ Complete; Phase 7 теперь next-active.
- REQUIREMENTS.md новые PERF-* / QUAL-* → Validated.

**Что дальше:** `/gsd-discuss-phase 7` — Anti-DPI suite + WireGuard family (v0.7).

---

## 2026-05-13 (Round 6) — Phase 6c re-UAT closed + follow-up fix (commit `44a5630`)

Пользователь прогнал re-UAT на iPhone iOS 26.5. Результат:
- **F-reverse:** ✅ PASS — intent-closing работает; BBTB сидит off после Happ takeover.
- **Settings-disable (Round 1):** ⚠️ **PARTIAL FAIL** — системный VPN выключился (intent-closing сработал в TunnelController), но BBTB UI остался в `.connected(since:)` с тикающим таймером.
- **G (passive 30+ min):** ✅ PASS — zero EXC_RESOURCE / PORT_SPACE.

**Codex GPT-5.2 architect диагноз** (advisory, read-only, 7-section delegation): `MainScreenViewModel.nevpnStatusObserver` зарегистрирован с `queue: .main`; iOS suspendирует приложение во время Settings round-trip → main queue paused → `.disconnected` notification coalesced/dropped, **не replays** на возврате. TunnelController observer выжил из-за `queue: nil`. VM не имел foreground-resync hook на iOS (`tc.handleForeground()` был no-op для iOS).

**Follow-up fix (commit `44a5630`)** — 3 surgical changes в `MainScreenViewModel.swift`:
1. Observer queue `.main → nil` (match TunnelController). Inner `Task { @MainActor }` hop сохраняет main-actor мутации.
2. New `MainScreenViewModel.handleForeground()` — одна `loadAllFromPreferences` XPC-поездка на scene `.active`, `ManagerSelector` filter, read `connection.status` + `connection.connectedDate` (sync), feed `applyVPNStatus(_:connectedDate:)`.
3. scenePhase wiring iOS + macOS — `viewModel.handleForeground()` рядом с `tc.handleForeground()`.

**Bonus fix в том же commit'е** (пользовательское Замечание 1 — таймер): `applyVPNStatus` принимает опциональный `connectedDate: Date?`; `.connected` ветка использует `connectedDate ?? state.connectionStart ?? Date()`. Чинит сценарий «BBTB активирован через iOS Settings → таймер начинает с захода в app». Теперь стартует с реального момента установления туннеля.

**Изменения wiki:**
- [[auto-reconnect]] — `Last updated` 2026-05-13 (Round 6), добавлены секции «VM foreground resync (Round 6 fix)» и «Bonus: connectedDate authority for `since`».

**Изменения GSD:**
- `STATE.md` Wave 3 → ✓ Complete + re-UAT PASS + follow-up fix.
- `ROADMAP.md` Phase 6c Wave 4 → ✓ Complete с ссылкой на commit `44a5630`.
- `REQUIREMENTS.md` NET-08..11 → `[x]` Validated (re-UAT PASS).
- `06C-04-SUMMARY.md` — добавлен раздел «Re-UAT outcome (2026-05-13 — Round 6)» с root cause + fix + verification.
- `06C-REVISION-LOG.md` — Round 6 entry с диагнозом + applied fix + invariants.

**Архитектурные инварианты** (все preserved):
- TunnelController intent-closing path UNCHANGED → F-reverse stays PASS.
- No XPC в NEVPNStatusDidChange observer hot path → G safety preserved (новая XPC — одна на scene `.active`, не в hot loop).
- No reintroduction of ReconnectStateMachine / NetworkReachability.
- `applyVPNStatus` остаётся SINGLE authority for `state` + `reconnectBannerState`.

**Что дальше:** `/gsd-plan-phase 06c-05` (UAT.md финальная документация + регрессионный smoke + NET-12 backlog + wiki touch). После — пользовательский запрос на новую Phase 6d (Performance & Code Quality Audit, multi-AI peer review через Claude Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) до Phase 7.

---

## 2026-05-13 — Phase 6c full check-up: 06C-04-SUMMARY + R18 в security-gaps + PROJECT/ROADMAP/REQUIREMENTS sync

После cutover'а 06C-04 (предыдущая запись) пользователь запросил полный чек-ап всех планов и wiki, пока выполняет re-UAT на iPhone iOS 26.5.

**Что было gap (пропущено в предыдущих коммитах)**:
- `.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md` не существовал (требуется по `<output>` спеке плана).
- `.planning/PROJECT.md` Key Decisions table не имел Phase 6c entry — последняя строка была из Phase 3 (2026-05-12).
- `.planning/ROADMAP.md` Wave 4 был помечен `[ ]` несмотря на завершённый cutover.
- `.planning/REQUIREMENTS.md` NET-08..11 не имели статус-аннотации о Phase 6c cutover.
- `wiki/security-gaps.md` не имел R18 для Phase 6c (R17 покрывал только Phase 6, который теперь частично замещён в auto-reconnect части).

**Изменения wiki**:
- [[security-gaps]] — добавлен **R18: Phase 6c — Apple's NEOnDemandRule auto-reconnect (sliding session window)**: 4 класса багов Phase 6, sliding session window invariant (`isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`), решения D-01..D-22 + Round 5 architect additions (intent-closing + reactive UI driver), 5-plan implementation overview, R1/R6/R10 invariants preserved, awaiting re-UAT scope. R17 (Phase 6) не обнуляется — auto-reconnect часть R17 теперь читается как «исторический контекст до R18 supersession».

**Изменения GSD планирования**:
- `06C-04-SUMMARY.md` — создан (~340 строк): file-level changes, deletion list with line counts, preservation contract (B-01/B-02), TunnelControllerTests methods, full verification table (build + tests + xcodebuild + line counts + grep audit), UAT 9-scenario status, architecture confirmations, Round 5 architect additions, executor pollution postmortem, reference index.
- `PROJECT.md` — добавлен Key Decision R18 (Phase 6c sliding session window); `Last updated` обновлён.
- `ROADMAP.md` — Wave 4 status `[ ]` → `[x] ✓ Cutover complete 2026-05-13` с commit refs + 06C-04-SUMMARY ссылкой.
- `REQUIREMENTS.md` — NET-08..11 аннотированы Phase 6c статусом; добавлен NET-12 (liveness probe) как backlog для Phase 7-8.

**Что НЕ менялось** (проверено grep'ом — stale references отсутствуют):
- `wiki/architecture.md` — не упоминает удалённые классы.
- `wiki/tech-stack.md` — не упоминает удалённые классы.
- `wiki/auto-reconnect.md` — уже актуально (legitimate references к history).

**Состояние ожидания** — re-UAT на iPhone iOS 26.5: F-reverse + Settings-disable + G passive. После signoff → Plan 06C-05.

---

## 2026-05-13 — Phase 6c cutover complete (commits 19f3fe7 + 5b0e28c + 69b8ae8)

**Что изменилось в коде на main**:
- Task 3a (`19f3fe7`) — TunnelController slim 909 → 316 строк; OLD machinery (ReconnectStateMachine ref, NetworkReachability ref, triggerRecoveryIfNeeded, reachability/wake recovery branches) удалена; intent-closing на external `.disconnected` (Settings-disable + другой VPN takeover → close user intent, BBTB stays off до явного Connect tap); `connectInProgress`/`manualDisconnectInProgress` flags сохранены как Round 5 carve-out для гонки с собственным connect/disconnect flow.
- Task 3b (`5b0e28c`) — `applyVPNStatus(_:)` reactive driver — NEVPNStatus теперь единственная авторитативность для main `state` AND `reconnectBannerState`. `connect()`/`disconnect()` остаются command methods (не выставляют `.connected(since:)` изнутри). Banner enum trim (`.retrying`/`.allFailed` → `.connecting`); `TunnelWatchdog.setFailoverObserver(_:)` setter + fire-site; начальный VM state seed через один ManagerSelector + status read; App entry points очищены от стейл `ReconnectStateObserverRelay` + `stateObserver:` refs.
- Task 3c (`69b8ae8`) — удалены 5 файлов (RSM + 2 теста, NetReach + 1 тест, TunnelControllerStateTests); сохранены `ReconnectClock.swift` + `TestClocks.swift` (B-01/B-02 cross-plan contract); создан `TunnelControllerTests.swift` (7 тестов, D-24 cat 2 — contract preservation).

**Финальная верификация на main**: AppFeatures 133/133 PASS; iOS Simulator xcodebuild SUCCEEDED; macOS xcodebuild SUCCEEDED; awk-stripped grep (B-08) возвращает 7 (только Round 5 carve-out флаги — никаких forbidden symbols).

**Изменённые страницы wiki**:
- [[auto-reconnect]] — обновлён header «Last updated» с пометкой о merge на main + готовности к re-UAT.

**Pending re-UAT (на iPhone iOS 26.5)** — 2 fresh сценария:
- **F-reverse** — BBTB active → активация Happ → BBTB stays off (не отвоёвывает route).
- **Settings-disable** — BBTB active → iOS Settings → VPN → toggle BBTB off → BBTB stays off до явного Connect.
- **G (passive)** — 30+ min background, Console.app на EXC_RESOURCE / PORT_SPACE crashes.

Источники: `.planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md` секция «Round 5 — CUTOVER EXECUTED».

---

## 2026-05-13 — Добавлена страница `auto-reconnect.md` (Phase 6c on-demand migration)

Phase 6c заменяет custom auto-reconnect machinery (ReconnectStateMachine + NEVPNStatusDidChange recovery + NetworkReachability) на iOS-нативный механизм `manager.isOnDemandEnabled` + `NEOnDemandRuleConnect`. Решение принято для устранения 4 классов багов Phase 6 (phantom reconnect, XPC storm/EXC_RESOURCE, fight-back с другими VPN, Mach port exhaustion). Ключевой инвариант — sliding session window: on-demand активен только между явным BBTB Connect и любым session-closing событием (Disconnect, iOS Settings off, takeover другим VPN).

Phase 6c прошла триплет ревью (gsd-plan-checker + Codex + Gemini) с APPROVE, после чего UAT на iPhone iOS 26.5 вскрыл два регрессионных бага из parallel-run hybrid (UI freeze + Settings → BBTB self-reactivates). Codex GPT-5.2 architect review (`06C-ARCHITECT-R5.md`) принял решение pull-forward Plan 04 Task 3 cleanup с двумя scope-additions (intent-closing на external disconnect + reactive UI driver).

Источники: `.planning/phases/06c-on-demand-migration/06C-CONTEXT.md`, `06C-RESEARCH.md`, `06C-REVISION-LOG.md`, `06C-ARCHITECT-R5.md`.

Файлы изменены:
- `wiki/auto-reconnect.md` (новый, ~190 строк)
- `wiki/index.md` (одна строка в разделе «Безопасность»)
- `wiki/log.md` (этот entry)

---

## 2026-05-13 — Phase 6 (network resilience) implementation complete — UAT deferred

**Источник**: GSD execution `/gsd-autonomous` — все 6 waves (06-01..06-06) реализованы.

**Изменённые страницы**:
- [[security-gaps]] — добавлен R17: Phase 6 — DNS-стратегия + Yandex eradication + IPv6 blackhole + auto-reconnect + failover. Описаны D-01..D-08, реализация по 6 waves, тестовые цифры, R1/R6/R10 invariants preserved, UAT carry-forward, Phase 7 follow-ups.

**Ключевые архитектурные решения, зафиксированные для будущих фаз**:
- Yandex `77.88.8.8` искоренён из shipping code — D-01 fallback к AdGuard `94.140.14.14`, для IPv4 server hosts — `tcp://<server-IP>`.
- `TunnelController` теперь `actor` (был `final class @unchecked Sendable`); Phase 1-5 `connect()/disconnect()` bodies preserved verbatim.
- Failover: round-robin cursor по `isSupported == true` + sorted by `id.uuidString`; reset triggers: manual disconnect ИЛИ 30s+ stable `.connected` с `startedAt` race guard (Pitfall 4).
- macOS wake: `NSWorkspace.shared.notificationCenter.addObserver` (НЕ `NotificationCenter.default` — Pitfall 10); `handleWake()` ставит flag, следующий `NetworkReachability.satisfied` consume-ит его.
- VM↔Controller init cycle решён через two-phase init: `setFailoverProvider(_:)` late-binder + `[weak tunnel]` connect closure.
- D-12 (no `#Predicate` с UUID) preserved в failover hot path — fetch-all + Swift filter.

**Тесты**: AppFeatures 120/120, VPNCore 57/57, ConfigParser 210/210, PacketTunnelKit 61/61, Localization 3/3 — все зелёные. iOS + macOS Xcode builds зелёные.

**Что отложено**:
- UAT (Task 3 Plan 06-06): 9 device sub-tests A-I — DNS leak, IPv6 leak, Wi-Fi↔LTE handoff, sleep wake, failover sequence, single-server notification, manual disconnect race, R1+R6 regression. Будут выполнены пользователем отдельно.

---

## 2026-05-13 — Phase 5 (transports) ✓ Complete — UAT deferred *(retroactive entry, добавлено при Phase 6e housekeeping 2026-05-14)*

**Источник**: GSD execution Phase 5 — 8 waves (05-01..05-08), v0.5 release, ~376 tests PASS.

**Изменённые страницы**:
- [[transports]] — задокументированы 5 transport handlers (TCP / WS / HTTP/2 / HTTPUpgrade / gRPC); `TransportRegistry` (CORE-03) startup registration pattern; per-protocol `buildOutbound` refactor; `ServerConfig.transportOverride` SwiftData lightweight migration v0.4.

**Ключевые архитектурные решения, зафиксированные для будущих фаз**:
- `TransportConfig` enum живёт в `VPNCore` пакете (общая зависимость для Protocols и TransportRegistry).
- `TransportRegistry` (CORE-03) — централизованный реестр; lookup by identifier; регистрируется в App startup, не lazy.
- `PoolBuilder` становится координатором, выбор транспорта делегируется per-protocol `buildOutbound` через registry handler.
- `ServerConfig.transportOverride` (SwiftData lightweight migration) — per-server манyally selected transport, применяется при следующем connect.
- R1 invariant (`insecure: false` для всех TLS блоков кроме Hysteria2 D-08 exception) preserved через refactor — invariant test PASSes.
- XHTTP/TRANSP-01 заморожен (sing-box upstream не поддерживает) — см. 05-CONTEXT.md «Не в скоупе».
- ServerDetailView (push from ServerListSheet chevron) — UI для ручного выбора транспорта.

**Тесты**: ~376 tests PASS (8 packages): AppFeatures + ConfigParser + VPNCore + PacketTunnelKit + Localization + TransportRegistry + 5 Protocols. iOS + macOS Xcode builds зелёные.

**Что отложено**:
- 5 manual UAT checks — subsumed within Phase 6c re-UAT scope (Round 6 closed 2026-05-13).

---

## 2026-05-12 — UX-решения: Kill Switch default + адаптивная высота шита серверов

**Изменённые страницы:**
- `wiki/kill-switch.md` — default изменён с «включён» на «выключен» (`@AppStorage = false`); обоснование: снижение friction при первом запуске
- `wiki/ux-specification.md` — раздел «Список серверов»: задокументирована адаптивная высота шита (≤88% экрана → `.height(estimated)`, иначе → `.large`); предупреждение о пересмотре констант при Figma Phase 11

**GSD-артефакты:**
- `REQUIREMENTS.md`: KILL-01 default обновлён → «выключен»; UX-04 добавлено описание адаптивного шита
- `ROADMAP.md`: Phase 11 — заметка про пересмотр констант высот `ServerListSheet` при Figma-интеграции

---

## 2026-05-12 — Phase 4 (protocol expansion) ✓ Complete *(retroactive entry, добавлено при Phase 6e housekeeping 2026-05-14)*

**Источник**: GSD execution Phase 4 — v0.4 release; добавлены протоколы Hysteria2, Shadowsocks, плюс расширение Trojan; 151+49 tests PASS.

**Изменённые страницы**:
- [[protocols-overview]] — добавлены секции Hysteria2 (D-08 R1 insecure: false exception для self-signed dev cert) и Shadowsocks (SIP002 dual-path URI parser).

**Ключевые архитектурные решения, зафиксированные для будущих фаз**:
- D-08 — R1 invariant exception для Hysteria2: `insecure: true` только если ИИ test cert (доверять через CA pinning при production); Phase 7+ — обязательное re-pinning при добавлении production Hysteria2 серверов.
- Yams YAML parser octal quirk — leading zeros в числовых полях (например `port: 0443`) парсятся как octal; решение в ConfigParser обрабатывает явно (strip + reparse).
- SIP002 dual-path URI parser — два формата Shadowsocks URI (legacy `ss://method:pass@host:port` vs SIP002 `ss://base64@host:port/...?plugin=...`); ConfigParser обрабатывает обе ветки.
- `runIsSupportedUpgrade` throttle — protocol-upgrade probes выполняются с rate-limit чтобы не дёргать сеть; задана в Wave 2 Hysteria2 (carried-over to Phase 6/6c).

**Тесты**: AppFeatures 151 + ConfigParser 49 (subset) PASS; iOS + macOS Xcode builds зелёные.

**Что отложено**:
- Manual UAT (— `--skip-uat` опция в /gsd-execute-phase 4) — выполнен пользователем отдельно через `/gsd-verify-work 4` сценарии Hysteria2 / Shadowsocks live-connect.

---

## 2026-05-12 — Phase 3 wiki update

**Новые страницы:**
- `wiki/server-management.md` — server list UI (Phase 3 v0.3): multi-subscription, merge-by-identity (D-14), SNI rotation fix, SwiftData UUID? predicate bug, TunnelController disconnect race, swipeActions limitation

**Обновлённые страницы:**
- `wiki/index.md` — добавлена ссылка [[server-management]]
- `.planning/ROADMAP.md` — Phase 3 отмечена ✓ Complete 2026-05-12
- `.planning/STATE.md` — Phase 3 ✓, next action Phase 4

---

## 2026-05-12 — Phase 2 wiki update (полный пакет)

**Новые страницы:**
- `wiki/trojan.md` — Trojan протокол: TCP+TLS и WS+TLS, ALPN h2 правило (R12), URI-парсинг, sing-box конфиг, urltest multi-server
- `wiki/config-importer.md` — универсальный import pipeline: 3 формата, ConfigImporter, PoolBuilder, serverHost/tunnelRemoteAddress, безопасность

**Обновлённые страницы:**
- `wiki/protocols-overview.md` — Trojan → ✓ v0.2; auto-fallback → реализован через urltest (было «появится»); добавлены ссылки [[trojan]], [[config-importer]]
- `wiki/kill-switch.md` — добавлена секция «Реализация v0.2»: тоггл в Безопасность + ReconnectBanner; roadmap обновлён (✓ v0.1, ✓ v0.2)
- `wiki/architecture.md` — добавлены реальные подмодули Phase 2: Protocols/Trojan, ConfigParser/(TrojanURIParser, PoolBuilder), AppFeatures/(MainScreenFeature, SettingsFeature, QRScanner)
- `wiki/release-roadmap.md` — v0.1 → ✓ Complete 2026-05-11 с DoD; v0.2 → ✓ Complete 2026-05-12 с DoD
- `wiki/index.md` — добавлены [[trojan]], [[config-importer]]; секция «Импорт и доставка конфигов» обновлена

## 2026-05-12 — Phase 2 UAT closure

**Операции:**
- `wiki/security-gaps.md` — добавлены R12 (Trojan-WS ALPN), R13 (tunnelRemoteAddress), R14 (Phase 2 security audit)
- `wiki/security-gaps.md` — обновлена дата Last updated

**Phase 2 итог:** UAT T0-T9 PASS. Три архитектурных решения зафиксированы. Три новых `[x]` требования в REQUIREMENTS.md (PROTO-02, PROTO-10, IMP-02, KILL-03). ROADMAP Phase 1 + Phase 2 отмечены Complete.

---

## 2026-05-11 — Первичный ингест

**Источники:**
- `raw/VPN-клиент для macOS и iOS — Промт для Claude Code.md` — главный системный промт / ТЗ на проект (~1050 строк)
- `raw/Дыры в безопасности, которые нужно обсудить.md` — список открытых вопросов и внешних ссылок (~20 строк)

**Внешние материалы, проанализированные в рамках ингеста:**
- https://github.com/xtclovver/RKNHardering — Android-приложение, реализующее методику РКН по детекту VPN (1231★, обновлён 2026-05-10). Изучены: архитектура, модули проверки, верификация по матрице сигналов.
- https://habr.com/ru/articles/1020080/ — статья «Из-за критической уязвимости VLESS клиентов скоро все ваши VPN будут заблокированы», автор runetfreedom, опубликовано 7 апреля 2026. Изучены: механизм уязвимости localhost-SOCKS5 в xray/sing-box, список затронутых клиентов, рекомендации.

**Созданные страницы (19):**

Архитектура и продукт:
- `product-overview.md`
- `architecture.md`
- `tech-stack.md`
- `release-roadmap.md`
- `ux-specification.md`

Протоколы и транспорты:
- `protocols-overview.md`
- `vless-reality.md`
- `transports.md`

Anti-DPI и ТСПУ:
- `tspu.md`
- `anti-dpi-techniques.md`

Безопасность:
- `kill-switch.md`
- `dns-strategy.md`
- `ipv6-strategy.md`
- `rules-engine.md`
- `deep-links.md`
- `max-messenger.md`
- `vpn-detection-by-apps.md` — из второго источника (22/30 приложений)
- `rkn-detection-methodology.md` — из внешнего репо xtclovver/RKNHardering
- `xray-localhost-vulnerability.md` — из внешней статьи Habr 1020080
- `security-gaps.md` — открытые вопросы из второго источника

Дистрибуция и юр-аспекты:
- `distribution-testflight.md`
- `licensing.md`

Сервис:
- `index.md`
- `log.md`

**Ключевые открытия для проекта:**

1. **Критическая угроза**: `libbox.xcframework` (sing-box, который мы планируем использовать) на Android запускает локальный SOCKS5 без авторизации — любое приложение на устройстве может это детектировать. На iOS sandbox теоретически изолирует loopback, но это требует обязательной верификации перед v0.1. См. `xray-localhost-vulnerability.md`.

2. **22 из 30 приложений** в РФ детектят VPN, 19 отправляют статус на сервер — банки, маркетплейсы, Яндекс, MAX. Это `known limitation` для primary-аудитории. См. `vpn-detection-by-apps.md`.

3. **Методичка РКН по детекту** (RKNHardering) — публичная и хорошо документированная. Используется и оптимизируется. Параллельно автор открыт к contributions по обратной задаче (антидетект). См. `rkn-detection-methodology.md`.

4. Три Instagram-reels из второго источника **не разобраны** — нужен пересказ от пользователя или альтернативный источник.

---

## 2026-05-11 — Второй ингест (методика РКН + парсер подписок)

**Новые источники:**
- `raw/ocr_methodika_vpn_proxy.md` (~47KB) — OCR-копия официальной методики РКН по выявлению VPN/Proxy на пользовательских устройствах. Структура: 10 разделов, 4 этапа внедрения, матрица решений из трёх сигналов.
- `raw/Документация парсера подписок singbox-launcher.md` — ссылка на документацию парсера из репо `Leadaxe/singbox-launcher`.

**Внешние материалы, проанализированные:**
- https://github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md — изучена документация парсера URI-схем и подписок.

**Уточнение от пользователя:**
- Фокус только на iOS и macOS — Android-специфика отрезана из ингеста.

**Созданные страницы (6):**

Детект VPN на устройстве:
- `rkn-methodology-document.md` — первоисточник методики, матрица решений, фокус на iOS/macOS-релевантные части
- `apple-detection-surface.md` — конкретные API детектирования на iOS (`CFNetworkCopySystemProxySettings`, `__SCOPED__`, `NWPathMonitor`, `NEVPNManager`, `utun*`) и macOS (`getifaddrs()`, маршруты, `Transparent Proxy API`, `enforceRoutes`)
- `geoip-detection.md` — Этап 1 как главный фронт защиты, hosting/ASN сигналы, resident-IP стратегии
- `snitch-rtt-detection.md` — метод задержек как ОС-независимая сетевая угроза, контрмеры через географическую близость exit'а
- `false-positives.md` — раздел 4 методики: корпоративный VPN, антивирусы, виртуализация, iCloud Private Relay

Референсы:
- `config-parser-singbox-launcher.md` — URI-схемы (vless, vmess, trojan, ss, hy2, ssh, socks, naive, wireguard), форматы подписок, edge cases для ConfigParser

**Обновлены страницы (6):**
- `rkn-detection-methodology.md` — переориентирована как «Android-имплементация», явно ссылается на новый первоисточник и apple-detection-surface
- `kill-switch.md` — добавлено предупреждение о конфликте `enforceRoutes` vs детектируемости на macOS
- `security-gaps.md` — добавлены 4 новых пункта: enforceRoutes-конфликт, iCloud Private Relay edge case, поверхность macOS шире iOS, hosting-IP exit-серверов
- `xray-localhost-vulnerability.md` — добавлены ссылки на первоисточник методики; уточнено, что список SOCKS-портов идёт прямо из методики (раздел 6.4)
- `vpn-detection-by-apps.md` — добавлен раздел «Когда они проверяют» (логин, оплата, ключевое действие); ссылки на методику и apple-detection-surface
- `index.md` — новый раздел «Детект VPN на устройстве», обновлена карта связей, добавлены новые пункты для проработки

**Ключевые открытия:**

1. **Главный фронт защиты — GeoIP**. Если серверный GeoIP не выявил аномалию, никакая комбинация прямых/косвенных сигналов **сама по себе** не приводит к жёсткому вердикту «обход выявлен» (Таблица 2 методики). Hosting-IP exit-серверов мгновенно ставит GeoIP в «выявлен» — это **главная архитектурная угроза** для нашего проекта.

2. **iOS защищён архитектурно sandbox'ом**. Из методики прямо: «доступ к системным данным существенно ограничен» (6.5), «анализ таблиц маршрутизации не применим для iOS» (7.6). На iOS детектируется только `utun*`-интерфейс и параметр P2P — но скрыть это без jailbreak невозможно.

3. **macOS уязвимее iOS**. Доступны `getifaddrs()`, маршруты, `Transparent Proxy API`. И — критически — методика прямо называет `enforceRoutes` техническим признаком, а мы его используем в kill switch. Это open trade-off.

4. **SNITCH — отдалённая, но реальная сетевая угроза**. RTT-триангуляция работает по физике задержек и не обходится никакими anti-DPI техниками. Единственный ответ — географическая близость exit'а к пользователю.

5. **Когда приложения детектят**: на login/payment/ключевом действии, не непрерывно (методика 6.3). Это объясняет реальный пользовательский опыт с банковскими и маркетплейс-приложениями.

6. **iCloud Private Relay юридически защищён** в методике от автоматической классификации как «обход блокировок». Это edge case для пользователей, у которых Private Relay одновременно с нашим VPN.

**Всего в wiki после второго ингеста:**
- 28 концептуальных страниц
- 1 index.md
- 1 log.md

---

## 2026-05-11 — Попытка ингеста Instagram-reels (неудача)

**Цель**: получить содержимое трёх Instagram-reels из `raw/Дыры в безопасности, которые нужно обсудить.md`.

**Попытки**:
- Firecrawl scrape: Instagram явно не поддерживается провайдером
- WebFetch на оригинальные URL: возвращает login-стену
- WebFetch через зеркало `ddinstagram.com`: ECONNREFUSED

**Решение пользователя**: оставить статус «недоступно», вернуться позже при наличии пересказа или скриншота. Зафиксировано в `security-gaps.md` пункт 4.

---

## 2026-05-11 — Аудит и фиксы

**Источник**: запрос пользователя «сделай аудит вики».

**Формальные проверки** (без правок, всё чисто):
- 30 файлов в wiki/
- 0 dangling links
- frontmatter и обязательные поля (Summary/Sources/Last updated/Related pages) на месте везде
- 0 orphan'ов в строгом смысле

**Применённые фиксы**:

1. **`protocols-overview.md`** — устранено терминологическое противоречие между «Phase 1» и «v0.1». Группы Phase 1/2/3 теперь явно описаны как «приоритетные группы», а не «релизы». В каждую таблицу добавлен столбец «Появляется в» с указанием конкретной версии (v0.1, v0.2, v0.4, v0.7). Summary переписан.

2. **`architecture.md`** — добавлена cross-ссылка на `[[config-parser-singbox-launcher]]` рядом с модулем `ConfigParser/` и в Related pages. Устранена слабая интеграция референс-страницы.

3. **`rules-engine.md`** — дата примера `rules.json` обновлена с `2025-01-15` (прошлое) на `2026-05-11`. Добавлена явная пометка «иллюстративные значения».

**Не сделано**: переименование `rkn-detection-methodology.md` → `rknhardering-android.md` отложено — требует подтверждения, ломает ~9 inbound-ссылок.

---

## 2026-05-11 — Инициализация GSD-планирования (.planning/)

**Источник**: запрос пользователя «Используя skill GSD спланируй реализацию приложения» → подтверждение варианта 1+B (`.planning/` живёт в корне проекта рядом с wiki, GSD-роадмап основан на промте v2).

**Конфигурация GSD** (`.planning/config.json`):
- Mode: YOLO (автоматический режим, без подтверждений на каждом шаге)
- Granularity: Fine (12 фаз = 12 релизов v0.1–v0.12+v1.0)
- Parallelization: Yes
- Git Tracking: Yes (планирующие документы под git)
- Workflow agents: Research + Plan Check + Verifier — все включены
- AI Models: Quality (Opus 4.7 для research/synthesizer/roadmapper)

**Созданные артефакты GSD**:
- `.planning/PROJECT.md` — описание проекта, core value, requirements (Active/OoS), context, constraints, key decisions (R1–R6 + остальные)
- `.planning/REQUIREMENTS.md` — ~130 v1-требований с REQ-IDs (CORE, SEC, KILL, PROTO, TRANSP, DPI, IMP, UX, SRV, NET, RULES, DEEP, DETECT, TELEM, BIO, ONDEMAND, LOC, DIST) + v2 (post-MVP)
- `.planning/ROADMAP.md` — 12 фаз, каждая = один релиз. Требования замаплены, success criteria сформулированы
- `.planning/STATE.md` — текущее состояние, активная фаза = Phase 1 (v0.1 Foundation)
- `.gitignore` создан (исключения `.DS_Store`, `.obsidian/`, `.firecrawl/`)
- `Claude.md` → `CLAUDE.md` (переименование линтером), расширен секцией «GSD Workflow (operational planning)» — wiki rules сохранены, добавлены GSD-инструкции
- `git init` выполнен — проект под версионным контролем

**Авторитет источников**:
1. `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — авторитетный источник по составу релизов и архитектуре
2. `.planning/ROADMAP.md` производный, согласован с промтом v2
3. Wiki — справочник + long-term decision log

**Принцип «wiki как decision log»** зафиксирован в auto memory и продублирован в `CLAUDE.md` (раздел GSD Workflow). При каждой фазе важные решения, новые открытия, изменения подхода переносятся в wiki — чтобы знание было долговременным, а не оставалось только в `.planning/`.

**Следующий шаг**: `/gsd-discuss-phase 1` — обсудить контекст Phase 1 (Foundation, v0.1) перед планированием.

**Источник**: запрос пользователя «давай разрешим спорные вопросы по архитектуре».

**Принятые решения** (зафиксированы в `security-gaps.md` секции «Закрытые / принятые решения»):

| # | Вопрос | Решение |
|---|--------|---------|
| R1 | Локальный SOCKS5 в sing-box на iOS/macOS | Security-блокер до v0.1: проверить конфиг libbox, отключить SOCKS5 и gRPC, написать iOS-тест |
| R2 | Sing-box vs WireGuardKit как основной движок | Sing-box. Без Reality проект бессмыслен |
| R3 | WebRTC STUN-блок по умолчанию | Выкл по дефолту, тоггл в Расширенных. Текущий план финальный для MVP |
| R4 | `enforceRoutes` на macOS | Оставляем `true` по дефолту. Защита от DNS-leak приоритетнее. TODO на v1.x — поиск альтернативы без выставления флага |
| R5 | «Stealth mode» на macOS | Одна опция в Расширенных «Отключить принудительную маршрутизацию» в v0.10. Не отдельный режим |
| R6 | Параметр `P2P` интерфейса на iOS | Проверить и не выставлять в v0.1 (30 мин работы) |

**Обновлены страницы**:
- `security-gaps.md` — переструктурирована: «Активные вопросы» (A1–A5) и «Закрытые / принятые решения» (R1–R6) с обоснованиями
- `kill-switch.md` — блок-предупреждение про `enforceRoutes` переведён из «trade-off открыт» в «принятое решение»; roadmap v0.10 расширен опцией
- `apple-detection-surface.md` — обновлены разделы про `enforceRoutes`, `P2P`, локальный SOCKS5; сводная таблица отражает резолюции
- `ux-specification.md` — в раздел Расширенных добавлен тоггл `enforceRoutes` (macOS only) с черновой формулировкой
- `release-roadmap.md` — v0.1 получил блок «Security review до релиза»; v0.10 — упоминание macOS-тоггла

**Открытые архитектурные вопросы** (после этого раунда):
- Только инфраструктурно-юридические: A1 (что делать с 19 приложениями), A2 (юр-риски аккаунта), A3 (iCloud Private Relay edge case), A4 (hosting-IP exit-серверов), A5 (Instagram-reels).
- Чистых вопросов «как кодить приложение» — нет.

---

## 2026-05-11 — Доработка промта Claude Code → v2

**Источник**: запрос пользователя «доработать промт-файл под принятые решения».

**Метод**: оригинал в `raw/` immutable (правило CLAUDE.md). Создана новая папка `prompts/` и скопирован файл как `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`. Точечные правки через Edit, без переписывания с нуля.

**Применённые изменения** (12 правок в одном проходе):

| # | Раздел | Изменение |
|---|--------|-----------|
| 1 | header | Добавлен HTML-комментарий `<!-- v2 (2026-05-11) -->` с перечнем изменений |
| 2 | `<role>` | Упомянута методика РКН и поверхность детекта на iOS/macOS как часть экспертизы |
| 3 | `<protocols>` | Phase 1 переформулировано в «приоритетная группа» с явным указанием «появляется в v0.1/v0.7/etc» для каждого протокола. Исправляет противоречие с release_roadmap |
| 4 | `<security>` Kill switch | Добавлен явный trade-off-блок про `enforceRoutes` (R4); добавлен пункт про `P2P=false` на интерфейсе (R6); добавлен блок «Sing-box engine — обязательные проверки до v0.1» (R1) |
| 5 | `<rules_engine>` пример | Дата обновлена с `2025-01-15` на `2026-05-11` |
| 6 | новый `<threat_model>` | Вставлен большой раздел между `<features>` и `<ux_specification>`: матрица решений РКН, поверхность детекта iOS vs macOS, что мы можем скрыть, SNITCH, known limitations (22 приложения) |
| 7 | новый `<server_infrastructure_requirements>` | Вставлен раздел с требованиями к exit-серверам: избегать hosting-IP, гео-близость, не покупать «засвеченные» IP, рекомендации против localhost-SOCKS5 уязвимости |
| 8 | `<advanced_screen>` | Добавлен macOS-only тоггл «Отключить принудительную маршрутизацию» (R5) |
| 9 | `<mvp_scope>` included_in_v0_1 | Добавлен блок «Security review до релиза» с конкретными чек-пунктами |
| 10 | `<phase_1>` | В цели и DoD добавлен security review (sing-box SOCKS5/gRPC, P2P) |
| 11 | `<release_roadmap>` v0.1 | Аналогично — security review в фичах и DoD |
| 12 | `<release_roadmap>` v0.10 | Упомянут тоггл `enforceRoutes` (R5) |
| 13 | `<definition_of_done>` | Добавлен пункт «Security review sing-box engine» + пункт про FAQ с known limitations |
| 14 | `<final_notes>` | Добавлена таблица «Архитектурные решения, принятые на этапе планирования» (R1–R6) |

**Файлы**:
- Создан: `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`
- Оригинал `raw/VPN-клиент для macOS и iOS — Промт для Claude Code.md` — не тронут (immutable по правилу CLAUDE.md)

**Замечания**:
- Формулировка тоггла `enforceRoutes` в Расширенных — черновая, помечена «уточнить с дизайнером в Figma»
- При следующем обновлении промта — синхронизировать с актуальным состоянием wiki, особенно `security-gaps.md`

---

## 2026-05-11 — Аудит и фиксы промта v2

**Источник**: запрос пользователя «проверь промт v2 на логичность и противоречия» → «фиксим всё».

**Применённые исправления** (8 правок):

| # | Категория | Что |
|---|-----------|-----|
| 1 | Опечатка | `Gerpc API sing-box` → `gRPC API sing-box` в таблице `<threat_model>` |
| 2 | Противоречие наследия | `<excluded_from_v0_1>`: «Биометрия (отложено в v0.2)» → «в v0.10» (release_roadmap кладёт биометрию именно в v0.10) |
| 3 | Противоречие наследия | `<settings_screen>` «Безопасность» — убрано «тоггл kill switch (вкл по дефолту)». Тоггл живёт в Расширенных, согласно `<security>` и `<release_roadmap>` v0.2. Оставлен указатель |
| 4 | Уточнение | Блок «Sing-box engine — обязательные проверки» в `<security>` явно расширен на iOS **и** macOS (раньше упоминался только iOS, но DoD требовал проверки на обеих) |
| 5 | Иерархия источников | В начало `<release_roadmap>` добавлена явная пометка «Авторитет источников»: release_roadmap — истина по релизам, `<phases>` — высокоуровневая группировка по этапам разработки. При расхождении приоритет за release_roadmap |
| 6 | Косметика | Пример `rules.json` помечен как «иллюстративный; конкретные домены — на этапе серверной конфигурации» |
| 7 | Косметика | `<onboarding>`: `vless://ss://trojan://` → `vless://`, `ss://` или `trojan://` с разделителями |
| 8 | Косметика | `<analytics>`: переформулирован тоггл «Отключить аналитику» (убрано двойное отрицание; явно: сбор включён по умолчанию, тоггл выключает) |

**Кросс-чек**: после правок противоречий в файле не осталось. Опечаток нет. Согласованность с принятыми решениями R1–R6 сохранена.

**Что НЕ исправлялось** (намеренно):
- Избыточность security review v0.1 (упомянут в 5 местах). Сейчас согласовано; пометка для будущих авторов в `security-gaps.md`. Это не баг, а дублирование для надёжности — Claude Code прочитает в любой из секций.

---

## 2026-05-11 — Phase 1 discuss + rebrand YourVPN → BBTB

**Источник**: запрос пользователя `/gsd-discuss-phase 1` → в процессе обсуждения, при закрывающем вопросе «фиксируем дефолты?», пользователь переименовал проект.

**Артефакты GSD**:
- `.planning/phases/01-foundation/01-CONTEXT.md` — контекст Phase 1 (Foundation, v0.1): 4 обсуждённых серых зоны, 7 Claude-defaults, черновая структура 6 wave'ов для planner.
- `.planning/phases/01-foundation/01-DISCUSSION-LOG.md` — лог диалога для аудита.

**Ключевые решения Phase 1** (зафиксированы в CONTEXT.md):
1. Идентификаторы: префикс `app.bbtb.*`, App Group `group.app.bbtb.shared`, Team ID `UAN8W9Q82U`.
2. Тест-сервер VLESS+Reality: уже есть у разработчика, server setup вне скоупа фазы.
3. PacketTunnelExtension iOS↔macOS: общий Swift Package `PacketTunnelKit` + два тонких NSExtension target shell (новое — расширение `prompts/v2 <swift_package_layout>`).
4. Security review R1+R6: security-first как первый wave (sing-box JSON без SOCKS5/mixed inbound, без gRPC API; standalone `SocksProbe` test-app — отдельный bundle `app.bbtb.tools.socksprobe`).

**Rebrand YourVPN → BBTB** (в одном проходе):
- Project codename: `BBTB` (Bring Back The Bug, аббревиатура).
- Display name: «Верни жука» (ru) / «Bring Back the Bug» (en).
- Универсальная замена `yourvpn` → `bbtb`, `YourVPN` → `BBTB`, `yourvpn.app` → `bbtb.app` во всех файлах планирования, спецификации, и wiki.

**Обновлены файлы** (10):
- `Claude.md` — путь Xcode-проекта.
- `.planning/config.json` — блок `project` расширен display names, bundle prefix, app group, universal links domain, team_id.
- `.planning/PROJECT.md` — title + display names + DEEP refs + Key Decisions row про rebrand.
- `.planning/REQUIREMENTS.md` — title + DEEP-01..03.
- `.planning/ROADMAP.md` — title + Phase 9 DEEP scheme.
- `.planning/STATE.md` — project codename + Active Phase status (Context gathered).
- `Wiki/index.md` — deep-links description.
- `Wiki/architecture.md` — root folder + DeepLinks scheme.
- `Wiki/deep-links.md` — все вхождения (custom scheme + домен + appIDs пример обновлён с реальным Team ID).
- `Wiki/release-roadmap.md` — v0.9 секция.
- `Wiki/product-overview.md` — новый раздел «Имя и идентификаторы» с полной таблицей bundle IDs.
- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — `<product_overview>` (финальное имя + Team ID), `<swift_package_layout>` root, deep links формат + домен + AASA appIDs, `<phase_4>` и v0.9 в release_roadmap, DoD.

**Сохранённые упоминания YourVPN** (как историческая запись):
- `.planning/PROJECT.md` — строка Key Decisions про rebrand.
- `Wiki/deep-links.md` — frontmatter description с пометкой «ранее yourvpn://».
- `Wiki/log.md` — этот журнал (история).

**Авторитет**: с момента этого commit'а `BBTB` — единственное каноническое имя. Любое появление `YourVPN`/`yourvpn` в новых артефактах считается багом, кроме исторических ссылок.

**Следующий шаг**: `/clear` → `/gsd-plan-phase 1`.

---

## 2026-05-11 — R7: Build system Tuist 4.x

**Источник**: Phase 1 execution checkpoint, пользователь споткнулся на Xcode 16 «Add Files → Create folder references» — этой опции больше нет (Xcode 15+ Synchronized Folders заменили старый dichotomy).

**Решение**: вместо Xcode UI flow генерировать xcodeproj через Tuist 4.x декларативно. См. `security-gaps.md` R7.

**Созданные артефакты**:
- `BBTB/Project.swift` — основной project с 5 targets
- `BBTB/Workspace.swift` — workspace declaration
- `BBTB/Tools/SocksProbe/Project.swift` — отдельный SocksProbe project (R1 invariant — изолированный sandbox)

**Обновлены страницы**:
- `security-gaps.md` — добавлено R7 (Build system: Tuist 4.x) в секции «Закрытые / принятые решения»
- `.planning/PROJECT.md` — Key Decisions table расширена строкой R7

**Что меняется в инструкции Phase 1**: бывший шаг 2 (создание xcodeproj через Xcode UI, ~50 мин) → новые шаги A+B+C (~10 мин через `tuist generate`). Бывший шаг 4 (SocksProbe.xcodeproj через UI) → одна команда `tuist generate` в `Tools/SocksProbe/`.

---

## 2026-05-11 — R10: TUN inbound runtime expansion (gap-closure W3.1)

**Источник**: Phase 1 W3 hack postmortem. В W3 добавили приватный `injectTunInbound` в `BaseSingBoxTunnel` (без тестов, runtime-инжект в extension). Gap-closure W3.1 перенёс это в `SingBoxConfigLoader.expandConfigForTunnel` + ослабил R1.

**Решение**: см. `security-gaps.md` R10.

**Изменённые файлы**:
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — relaxed R1 (`forbiddenInboundTypes` = {socks, http, mixed, redirect, tproxy}) + новый публичный метод `expandConfigForTunnel(json:mtu:tunIP:)`.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` — удалён приватный hack `injectTunInbound`; вызов `SingBoxConfigLoader.expandConfigForTunnel` после `validate`.
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` — 7 новых tests; fixture `valid-tun-inbound.json` (был invalid), новый `legacy-dns-outbound.json`.
- `BBTB/Packages/PacketTunnelKit/Package.swift` — linker settings на testTarget (libbox transitive deps: resolv, bsm, SystemConfiguration, AppKit/UIKit) — побочный fix чтобы `swift test` запускался.
- `Wiki/security-gaps.md` — R10 добавлен.

**Архитектурное правило**, зафиксированное навсегда: bundled template не содержит inbounds; TUN/WireGuard PacketTunnel inbound добавляется на runtime через expand loader'а. Это сохраняет принцип «минимальная shipped attack surface».

---

## 2026-05-11 (вечер) — Phase 1 W5 device test, partial pass + Vision incompatibility candidate

**Контекст**: Продолжение device debug session 2026-05-11. Серия из 5+ фиксов довела до partial pass — туннель и DNS работают, но Safari/HTTPS user-facing destinations всё ещё обрываются.

**Закрытое (commit `0299af6`)**:
- sing-box log injection + main-app→Documents bridge для извлечения через Xcode Devices GUI (App Group containers не выкачиваются напрямую)
- sing-box 1.13 sniff требование: `expandConfigForTunnel` теперь инжектит `{action: sniff}` первым правилом route (без него `protocol: dns` matcher не работает и DNS UDP падает на `vless-out` с "UDP not supported")
- DNS pipeline rebuild (Hiddify-canonical): fakeip CGNAT 100.64.0.0/10 + Yandex bootstrap (`tcp://77.88.8.8` direct) + DoH cloudflare-dns.com fallback + NXDOMAIN на HTTPS/SVCB queries
- `route.rules action: resolve` (sing-box v1.9+) — client-side pre-resolve через bootstrap, чтобы VLESS header нес IP, не hostname
- Outbound tuning: убран `packet_encoding: xudp` (Hiddify экспортирует empty для Vision+TCP, см. hiddify-app#758); MTU TUN 1400→9000 (Hiddify default)

**Что работает**: туннель `connected`, DNS pipeline, ~50% VLESS соединений завершаются `download/upload finished`, Apple iCloud / Telegram backbone трафик.

**Что НЕ работает**: Safari → user HTTPS-сайты (Cloudflare-anycast) обрывается до TLS completion. Подозрение — sing-box client Vision implementation incompatibility с Xray-core server Vision. Happ (форк с собственными патчами) с тем же URI работает.

**Архитектурное решение, зафиксированное**: DNS pipeline — fakeip + route.resolve + Hiddify-canonical — это **базовый working pattern** для sing-box+VLESS+Reality+Vision на iOS NE. См. [[dns-pipeline-decisions]] для деталей и обоснований.

**Открытый issue** (отслеживается в memory + wiki/vless-reality.md): «sing-box client Vision incompatibility candidate». Следующие шаги — trace log (Опция Б) → Hiddify-Next bit-by-bit diff (Опция В) → fallback partial-pass acceptance с SagerNet/sing-box bug report.

**Новые/обновлённые wiki-страницы**: [[dns-pipeline-decisions]] (новая), [[vless-reality]] (секция Vision short-stream issue добавлена).

---

## 2026-05-11 (поздний вечер) — Phase 1 W5 RESOLVED — 7 раундов device-debug + control test

**Контекст**: Продолжение partial-pass session. 7 раундов гипотез + 8 коммитов в день. Финал — `9aa3e93`.

**Реальный root cause (выяснен в раунде 6+7)**:
Template `SingBoxConfigTemplate.vless-reality.json` hardcode'ил `"flow": "xtls-rprx-vision"` независимо от того что в VLESS URI пользователя. Сервер пользователя в исходном тесте имел `flow: ""` (без Vision). Server-client frame format mismatch → server закрывал каждое соединение через ~30мс детерминированно (1 RTT). Симптом «оба направления close в одну мс» = server FIN, оба goroutine в bidirectional pipe sing-box'а получают EOF одновременно — нормальное поведение для server-initiated close.

**Что попробовали безуспешно (false leads из-за неверной гипотезы про Vision incompatibility)**:
1. MTU 9000→1500 (Codex hypothesis) — identical teardown
2. Снять `route.resolve` (Gemini hypothesis) — hostname теперь в VLESS, но teardown остался
3. TUN `stack: gvisor→mixed` (Hiddify default) — crash-loop в **нашей** libbox build (Hiddify собирает с другими build tags)
4. Subnet mask `/30→/28` (Hiddify alignment) — identical teardown

**Диагностический раунд (раунд 6)**: `flow: ""` → connections survive (126 conn, 44% >500ms, MAX 26.14 сек). Vision-mismatch локализован.

**Control test (раунд 7)**: `flow: "xtls-rprx-vision"` + URI от Vision-enabled сервера → connections работают (149 conn, 25% >2 сек, 15% >10 сек, 100 XtlsFilterTls events). Sing-box Vision сам по себе **работает корректно**.

**Финальный фикс (раунд 8, commit `9aa3e93`)**:
- `SingBoxConfigTemplate.vless-reality.json` template: `"flow": "${VLESS_FLOW}"` (placeholder)
- `ConfigBuilder.VLESSRealityInputs`: новое поле `flow: String` + substitution
- `ConfigImporter`: передаёт `parsed.flow` через
- `VLESSURIParser` default: `"xtls-rprx-vision"` → `""` (per Leadaxe ParserConfig spec — отсутствие `?flow=` в URI = без Vision)
- 3 новых теста: missing flow → "", explicit flow preserved, empty flow valid JSON

**Финальный dual-config test (раунд 8)**: оба типа URI (Vision-enabled + non-Vision) работают на iPhone 16 iOS 26 — пользователь подтвердил.

**Wiki-обновления**:
- [[vless-reality]] — раздел «РЕШЕНИЕ Phase 1 W5» переписан (server-client flow mismatch, не Vision bug)
- [[security-gaps]] R10 — TUN inbound параметры (mtu=1500, subnet /28, stack=gvisor)
- [[dns-pipeline-decisions]] — `route.resolve` снят
- [[index]] — нет изменений

**Lessons learned**:
1. Hardcoded template values — не делать; параметры из user URI должны flow through.
2. «Both directions close in same ms» — это **нормальное** sing-box поведение для server-initiated close, не сложный race condition.
3. Cross-AI consult (Codex+Gemini) был полезен для генерации гипотез, но none из них не предложили проверить server-side flow config.
4. **Спрашивать про server config раньше** — пользователь упомянул `flow: ""` на сервере только после 6 раундов.
5. `gh api` для OSS comparison (Hiddify-app + sing-box-for-apple) — полезный метод research, но в этом случае не вёл напрямую к решению.

**Открытый TODO** (`project_phase1_w5_resolved.md` memory): UI hint при импорте URI показывать обнаруженный flow — опциональное улучшение, не блокер.

**Использованная reference docs**: [Leadaxe singbox-launcher ParserConfig](https://github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md) — отличная карта VLESS URI query → sing-box JSON mapping.

---

## 2026-05-11 — Phase 1 security audit (`/gsd-secure-phase 1`)

**Что произошло**: запущен retroactive аудит мита́ций для 37 трэтов из PLAN.md W0..W5. 36 closed на первом проходе, 1 BLOCKER найден и закрыт в том же цикле.

**Изменённые страницы**:
- [[security-gaps]] — добавлен раздел **R11. Phase 1 security audit — 37/37 threats closed** с группами контролов (R1/R6/KILL/SEC-03/SEC-05/OSLog/CrashReporter), списком 9 accepted risks, описанием remediated W5-02 (`.gitignore` repo-root build artifacts), TODO для Phase 11 FAQ (W2-05 promote из RESEARCH.md) и Phase 12 (W3-05 codesign в CI; W5-01 crash UI отправка).

**Артефакты вне wiki**:
- `.planning/phases/01-foundation/01-SECURITY.md` — полный audit report (171 строка) со ссылками на каждую evidence-line в impl-файлах. status: verified, threats_open: 0.
- `/Users/vergevsky/ClaudeProjects/VPN/.gitignore` — добавлены `build/`, `*.xcarchive`, `*.dSYM`, `*.ipa` для root-scope (W5-02 mitigation).

**Commit**: `5b897a5` — docs(phase-1): close security audit — 37/37 threats verified, fix W5-02 .gitignore gap.

**Memory entries**:
- `project_phase1_security_audit_complete.md` — добавлено в MEMORY.md index. Phase 1 security gate пройден; перед Phase 12 нужен refresh аудит (supply-chain переходит из accept в mitigate).

**Lessons learned**:
1. **Scope mismatch в `.gitignore`**: PLAN.md писал «уже исключает build/», но это правило было в `BBTB/.gitignore`. После того как `archive-ios.sh` зафиксили на запись в repo-root `build/` (commits `b253ce1` + `b11196b`), правило перестало действовать — но никто не заметил, пока auditor не сделал `git check-ignore`. **Правило**: если меняешь output path script'а, проверяй что соответствующий ignore-rule всё ещё покрывает.
2. **Accepted risks log оптимизирует ре-аудиты**: 9 accepted без verification — это не «слабая защита», это документированные системные ограничения. Будущие аудиты не должны их пере-проверять.
3. **R6 на iOS 26**: Apple unconditionally ставит IFF_POINTOPOINT на utun независимо от destinationAddresses=nil. Code-side mitigation в `TunnelSettings.makeR6Safe` всё равно ценен — на случай если Apple вернёт настраиваемость в будущих iOS.


---

**Дата**: 2026-05-12
**Источник**: Phase 3 — server-management (GSD execution complete)
**Что произошло**: Phase 3 закрыта — 6 планов (5 основных + 1 gap-closure), 162 теста PASS, верификация PASSED.

**Изменённые страницы**:
- [[architecture]] — добавлены: ServerListFeature модуль, SwiftData-схема v0.3 (Subscription @Model + FK + cascade delete + idempotent migration), TCP-пробы/auto-select (ServerProbeService actor, score formula, ProbeAggregate.failures Int), новые ConfigParser-компоненты (ConfigImporting protocol, SubscriptionMergeService, SubscriptionURLFetcher)
- [[ux-specification]] — раздел «Список серверов» переписан под реализованные решения Phase 3: sheet+detents, ячейка «Авто», lazy scroll вместо List, latency badge тиры, pull-to-refresh 2-шага, merge-стратегия missingFromLastFetch, cascade delete, автореконнект без алерта
- [[security-gaps]] — добавлен R15: Phase 3 security audit (T-03-01 name sanitization, T-03-06 SSRF isBlockedHost, T-03-07 TCP accept, T-03-08 cascade correct, T-03-09 migration idempotent); CR-01/CR-04 code-review fixes; accepted T-G1-05 DNS-rebinding → Phase 7

**Ключевые решения, зафиксированные для будущих фаз**:
- `ConfigImporting` protocol живёт в `ConfigParser`, не в `MainScreenFeature` — иначе circular dependency с `ServerListFeature`
- `List` несовместим с прогрессивными async latency updates → использовать `ScrollView + LazyVStack + Section`
- `ProbeAggregate.failures: Int` (raw count) вместо `Int(lossRate * 3)` — IEEE-754 truncation bug
- `selectedID` guard в `provisionTunnelProfile` — silent fallback к другому серверу нарушает D-09 явного выбора пользователя

---

**Дата**: 2026-05-15
**Источник**: Phase 8 W0 — appproxy-deferral-2026.md (RULES-11 + Phase 8 SC #3 carve-out per D-08/D-09; Codex thread 019e284c). Updated ROADMAP.md Phase 8 entry + REQUIREMENTS.md RULES-11 row + Tuist Project.swift (deleted BBTB-AppProxy-macOS target) + macOS entitlements (removed app-proxy-provider value) + SubscriptionURLFetcher.swift (isBlockedHost + normalizeHostForLog promoted public для RulesEngine reuse).

**Что произошло**: Plan 08-01 (W0 foundation) формально вынес RULES-11 (macOS per-app routing data plane) и Phase 8 ROADMAP Success Criterion #3 в Out of Scope v0.8 с conditional return в v0.10+. Архитектурное обоснование — `wiki/appproxy-deferral-2026.md`.

**Изменённые страницы**:
- [[appproxy-deferral-2026]] — **создана** — long-term decision log: L3 sing-box vs L4 NEAppProxyFlow architectural mismatch, NETunnelProviderManager и NEAppProxyProviderManager mutually exclusive, рассмотрение трёх мостов (SOCKS5 inbound / multi-instance / plain TCP) и почему каждый ломает invariants, workaround `never_through_vpn` через `route.rule_set`, условие возврата (3+ TestFlight signal) + cost estimate.
- [[index]] — добавлен entry на `appproxy-deferral-2026` в Anti-DPI секцию (после `amneziawg-deferral-2026`).

**Ключевые решения, зафиксированные для будущих фаз**:
- AppProxy data plane carve-out не подразумевает потерю split-tunnel в v0.8 — `never_through_vpn` через sing-box `route.rule_set` (domain/IP/country matching) покрывает 95% friends-and-family TestFlight scenarios. Потеря — per-bundle-ID granularity (route Telegram через VPN при direct WhatsApp на тех же доменах).
- При v0.10+ возврате — schema **новый** `macos_app_proxy.json` с Apple-canonical `signing_identifier + designated_requirement` (NOT bundle IDs, которые spoofable per Apple HIG). НЕ возвращать поле `bundle_ids` в `rules.json` schema.
- Apple Developer Portal capability disable (`app-proxy-provider`) — manual step пользователя, не code change. Documented в Plan 08-01 frontmatter `user_setup`.
- `SubscriptionURLFetcher.isBlockedHost` + `normalizeHostForLog` повышены до `public` — впервые pattern «cross-package reuse через visibility promotion» в monorepo. Альтернатива (extract в `VPNCore/Net/HostBlocklist.swift`) рассмотрена в 08-PATTERNS Risk #1 и отложена до Phase 11/12 если потребуется third consumer.

---

**Дата**: 2026-05-15
**Источник**: Phase 8 W7 (closure) — Rules Engine + Split tunneling v0.8 implementation complete.

**Что произошло**: Phase 8 все 7 волн (W0..W6) выполнены. Новый SwiftPM пакет `RulesEngine` реализует Ed25519-signed rules pipeline + sing-box `route.rule_set` split-tunneling. UAT pending (M-04/M-05/M-07/M-08 на iPhone).

**Компоненты реализации**:
- W0 ✓ — RULES-11 + SC #3 carve-out; `AppProxyExtension-macOS` target deleted; `appproxy-deferral-2026.md` создан
- W1 ✓ — `RulesEngine` пакет: swift-crypto Ed25519 + HTTPS mirror failover + `RulesManifest` Codable + 9 unit tests
- W2 ✓ — `RulesEngineCoordinator` actor: bootstrap + performBackgroundRefresh + forceUpdate + `SRSCacheStore` actor + 13 tests
- W3 ✓ — SwiftUI: `RulesViewerSection`, `ForceUpdateRulesButton`, `MinAppVersionBanner`, `MinAppVersionSheet` + ~30 L10n keys (ru+en) + 17 tests
- W4 ✓ — iOS `BGAppRefreshTask` (6h) + macOS `NSBackgroundActivityScheduler` (6h tolerance 10min) + host wire-up
- W5 ✓ — `SingBoxConfigLoader.expandConfigForTunnel` инжектирует 3 `route.rule_set` entries + 3 priority rules; R1/R10 invariants preserved; 6 tests
- W6 ✓ — `scripts/build-baseline-rules.sh` (ephemeral + real modes); committed real signed baseline SRS (max.ru / mssgr.tatar.ru in block_completely); `PublicKey.swift` updated с real derived key bytes
- W7 ✓ — `validate-r1-r6.sh` extended: R8 (no inline rule_set in template) + R8b (AppGroupContainer usage) + RULES-02 (32-byte pubkey count) + R12 (no placeholder sequential bytes) + D-08 (no NEAppProxyProvider in main sources); RulesEngine added to per-package test loop

**Изменённые страницы**:
- [[rules-engine]] — **полная перезапись** с Phase 8 final state: D-01..D-13 decisions, архитектурная диаграмма pipeline, ротация ключей v1.x strategy, файловый layout, return conditions для RULES-11
- [[architecture]] — `AppProxyExtension-macOS` target помечен DELETED; `RulesEngine` пакет добавлен с Phase 8 ✓ пометкой; `AppProxyProvider` секция обновлена с deferral note
- [[security-gaps]] — R20 entry добавлен (Phase 8 Rules Engine trust path: угроза, mitigation, invariants table, known limitations, Codex refs)
- [[index]] — `rules-engine` entry обновлён с Phase 8 final state description

**Ключевые решения D-01..D-13 (коротко)**:
- D-01: sing-box route.rule_set через SRS binary (server-compiled) — единственный performant way без MMDB
- D-04: server-side country→CIDR expand — никаких client MMDB lookups
- D-07: two-file detached Ed25519 sig scheme
- D-08/D-09: AppProxy L4↔L3 mismatch → deferred v0.10+ → target deleted
- D-12: rules не блокируют cold start (DEC-06d-01 pattern)
- D-13: sequential mirror failover (bounded concurrency = 1, DEC-06d-04 pattern)

**Manual UAT pending** (на iPhone iOS 18+ test device):
- M-04: BGAppRefreshTask 6h real wall-time (или iOS Simulator Debug → Simulate Background Fetch)
- M-05: real domain blocking — curl max.ru через tunnel → connection reset
- M-07: split-tunnel country resolve — yandex.ru goes direct, non-RU through VPN
- M-08: min_app_version sheet UX — admin publishes 99.0.0 → sheet appears, persist через kill

**Следующий шаг**: `/gsd-verify-work 8` → если UAT пройден → Phase 9 Deep Links `/gsd-discuss-phase 9`.

---

---

**Дата**: 2026-05-15
**Источник**: Phase 8 UAT closure — M-04/M-05 PASS + M-07/M-08 deferred.

**Что произошло**: Phase 8 UAT проведён на реальном iPhone iOS 18+.

**Результаты UAT**:
- **M-04 PASS** — Логи устройства (debug-logs/logs.txt) подтвердили: bootstrap записывает `bbtb-baseline-block/never/always.srs` ✓; BGAppRefreshTask срабатывает ✓; `RulesFetcher.fetchWithFailover` пробует все 3 зеркала последовательно ✓; все 3 падают с DNS -1003 (ожидаемо — placeholder URLs). `bbtbRulesEngineDidUpdate` не постится — корректно (нотификация только при успешном обновлении с сервера). Механизм работает.
- **M-05 PASS** — пользователь подтвердил: curl `max.ru` через туннель → connection reset.
- **M-07 DEFERRED** — VPS admin pipeline не настроен. Требует реального VPS с подписанным манифестом `countries: ["RU"]`. Переносится на Phase 9 / pre-TestFlight.
- **M-08 DEFERRED** — VPS admin pipeline не настроен. Требует server-delivered manifest с `min_app_version > current`. Переносится на Phase 9 / pre-TestFlight.

**Phase 8 CLOSED** — паттерн как Phase 4/5/6 UAT deferred: implementation complete + основные device-UAT PASS; M-07/M-08 ждут VPS admin pipeline.

**Изменённые страницы**: нет новых страниц (обновлены артефакты планирования: STATE.md + 08-VERIFICATION.md).

**Следующий шаг**: `/gsd-discuss-phase 9` — Deep Links: `bbtb://` custom URL scheme + Universal Links (`import.bbtb.app`).

---

---

**Дата**: 2026-05-15
**Источник**: Phase 9 — Deep Links: Waves 1–3 complete, Wave 4 paused.

**Что произошло**: Phase 9 (Deep Links) реализована на уровне кода (Wave 1–3). Wave 4 (серверный деплой + device UAT) отложена.

**Реализовано (Wave 1–3):**
- `DeepLinks` SwiftPM пакет: `DeepLinkRouter` actor, `DeepLinkHandler` protocol, `DeepLinkError`, `DeepLinksLogger`, `TokenFetcher` stub
- `ImportHandler` — обрабатывает `bbtb://import?url=…` (DEEP-01) и `https://import.bbtb.app/import?url=…` (DEEP-02)
- L10n 5 ключей (ru+en): `alert.deep_link_error.title` + 4 error messages
- iOS + macOS App wiring: `.onOpenURL` + `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` + cold-start buffer `@State pendingDeepLink`
- `MainScreenViewModel.handleDeepLink` → `DeepLinkRouter` → `ImportHandler` → `importFromRawInput` → overlay/alert
- entitlements `applinks:import.bbtb.app`, Info.plist `CFBundleURLTypes bbtb://`
- 17/17 DeepLinks тестов + 164/164 AppFeatures тестов — зелёные

**Scope amendment (закреплён):** DEEP-03 (token endpoint) + DEEP-04 (landing page) → v1+ backlog. Архитектурная заглушка `TokenFetcher` protocol в пакете.

**Отложено (Wave 4):** деплой AASA на `import.bbtb.app` + Apple Developer Portal Associated Domains capability + device UAT F1–F4. Инструкция: `.planning/phases/09-deep-links/09-RESUME.md`.

**Изменённые страницы**: `wiki/deep-links.md` — полная перезапись (D-01..D-09, AASA content, macOS pitfall, v1+ return conditions).

**Следующий шаг**: `/gsd-discuss-phase 10` — Advanced settings + Security polish (UX-06, BIO-01..04, DPI-06/08/09, ONDEMAND-01, KILL-04, DPI-05 Mux carry-over from Phase 7).

---

## 2026-05-15 — Phase 11 Plan 04 (Wave 2) — MAX detection + handoff

**Что произошло**: реализован silent MAX-detection (DETECT-01 iOS / DETECT-02 macOS) и создан admin handoff документ для DETECT-03.

**Реализовано:**
- `MAXDetector.swift` (BBTB/Packages/AppFeatures/Sources/MainScreenFeature/): static enum + `URLSchemeQueryable` / `WorkspaceQueryable` protocols (mockable), `iOSSchemeCandidates` (4 schemes), `macOSBundleCandidates` (4 IDs); `@MainActor detectAndLog()` пишет одну `os.Logger.info()` с category `detection`. Никакого UI side-effect, никаких записей в App Group / Keychain / UserDefaults.
- `MAXDetectorTests.swift`: 5 unit-тестов на mocked detection (iOS skipped на macOS host; macOS — 4 теста + cross-platform invariant).
- iOS Info.plist: `LSApplicationQueriesSchemes` whitelist (max, max-app, ru-max, vkmax) — sync с `iOSSchemeCandidates`.
- iOS + macOS App entry points: `Task.detached(.utility) → MainActor.run { MAXDetector.detectAndLog() }` per DEC-06d-01 cold-start defer.

**Изменённые / новые страницы wiki**: `wiki/max-domains-blocklist.md` (новый) — admin handoff документ DETECT-03 с 7 кандидат-доменами (2 подтверждённых + 5 `[ASSUMED]`), verification protocol (DNS baseline → tcpdump → build-baseline-rules.sh sign+publish → 24h monitoring), closure dependency для REQ DETECT-03. `wiki/index.md` обновлён ссылкой на новую страницу.

**Тестовые метрики**: AppFeatures 178/178 PASS (было 173/173 — +5 новых тестов MAXDetector).

**Closure dependency**: DETECT-03 — client-side ✅ Validated; server-side ⏸ pending admin handoff (применить `max-domains-blocklist.md`). При закрытии — `⚙️ Infrastructure-validated` в REQUIREMENTS.md (паттерн Phase 10 DPI-06).

**Следующий шаг**: Phase 11 Wave 3+ (UX-01 Onboarding, UX-08 ConnectionButton spinner, LOC-03/04 HelpView, TELEM-02 DiagnosticsExporter, IMP-03 file picker) — параллельные потоки L10n-ready (Wave 1) и Figma-блокированы (UX-09).

---

## 2026-05-16 — Phase 12 ⏸ Implementation complete (awaiting closure UAT)

**Operation:** Phase 12 (v0.12-design) — Swift pixel-perfect rebuild from Figma BBTB v3. Автономная часть завершена; user закрывает через 7-screen visual UAT.

**Что сделано (15 commits на main, `a78ff24` → `7775a95`):**

- **Plan 12-01 Foundation (5 tasks)** — DesignSystem package расширен: `DS.Color` (15 семантических токенов через UIColor dynamic provider), `DS.Typography.Size` (7 размеров) + `expanded()` helper + 9 пресетов, `DS.Radius.section/sheet` (24/32), `DS.Blur.pill` (4), новые `DS.ConnectionButtonSize.compactDiameter=280 / regularDiameter=320 / compactIcon=112 / regularIcon=128` (M1+M2), deprecated `DS.accent` alias. Created `DSColor.swift` + `ButtonStyles.swift` (Primary+Secondary). Package.swift расширен `swift-snapshot-testing` 1.18.3+ (resolved 1.19.2) + 2 testTarget с StrictConcurrency=complete. 10 unit tests + 3 ButtonStyle snapshot baselines (iOS 17 Simulator) PASS.

- **Plan 12-02 Application (8/9 tasks)** — все 10 mismatches M1-M10 закрыты:
  - **M1+M2** — ConnectionButton diameter/icon size pick-up через DS.ConnectionButtonSize (numeric token update в Plan 12-01).
  - **M3** — `ConnectionButton.fillColor` switch на `DS.Color.controlIdle/.accent/.error` (private→internal per Phase 11 D-05 pattern) + 3 unit-теста.
  - **M4** — SF Pro Expanded через `Font.system(size:weight:).width(.expanded)` (iOS 16+ API). Бандлить .otf запрещено Apple Font SLA §2B.
  - **M5** — `DS.accent` redefined через `Color(uiColor: UIColor(dynamicProvider:))` literal (НЕ Asset Catalog — SPM nested `Bundle.module` имеет preview crash bug).
  - **M6** — `BBTBSpinner.swift` создан (Circle.trim + AngularGradient stroke 6pt + rotationEffect 1.2s linear repeatForever); Reduce-Motion fallback = pulsating opacity 0.6↔1.0 cycle 1.0s. ConnectionButton wires через `.overlay { if isConnecting { ... } }` на Circle (W3 fix — parent VStack frame НЕ jumps).
  - **M7** — OnboardingView rebuild: hero text split (white «Интернет, каким он » + accent green «должен быть» `#14664B`) в `expanded(.display=48, .semibold)`; 2 CTA через BBTBPrimaryButtonStyle/BBTBSecondaryButtonStyle + haptic feedback.
  - **M8** — ServerRow padding/font/colors token alignment (textPrimary/Secondary/Tertiary + iconMuted/iconSecondary) + selected accent background + Reduce-Motion-gated animation.
  - **M9** — ServerListSheet `UnevenRoundedRectangle(topLeading:32, topTrailing:32, bottomLeading:0, bottomTrailing:0).clipShape` — pure SwiftUI iOS 16+.
  - **M10** — AutoCell pill с `DS.Radius.section=24` + accent/surfaceSunken fills + Reduce-Motion-gated bouncyCheckmark.
  - **DS-15** — Snapshot test corpus: 11 функций (5 ConnectionButton incl. regular size class W1 + 1 OnboardingView hero + 4 ServerList + 1 Spinner = 15 total с Plan 12-01 ButtonStyles).

**Тесты:**
- AppFeatures: **210/210 PASS** (+3 новых `test_fillColor_*`)
- DesignSystem: **10/10 unit + 4/4 snapshot PASS** (3 ButtonStyle + 1 Spinner на iOS 17 Simulator)
- iOS xcodebuild: **SUCCEEDED** на iPhone 17

**Carve-outs (НЕ блокируют closure):**
1. AppFeatures snapshot baseline recording через xcodebuild test — линкер ошибка `_res_9_ninit/_res_9_nsearch` (libbox.xcframework transitive deps требуют `-lresolv`). Source-уровень готов; baseline зафиксируется в follow-up commit либо через `.linkerSettings([.linkedLibrary("resolv")])` в test target, либо через exposed Tuist test scheme.
2. Tuist BBTB workspace test scheme — `BBTB`/`BBTB-Workspace` не сконфигурированы для test action. `swift test --package-path` работает на macOS host.

**Изменённые / новые страницы wiki**: `wiki/swift-pixel-perfect-rebuild-2026.md` (новый, полный отчёт Phase 12 — locked decisions D-01..D-12, технические решения с rationale, patterns, carve-outs, backlog), `wiki/index.md` обновлён.

**Decisions зафиксированы**:
- Spinner = Circle.trim + AngularGradient (НЕ symbolEffect — gradient-incompatible)
- Font = .fontWidth(.expanded) (НЕ .otf bundle — Apple SLA §2B)
- DS.Color = Swift literal + UIColor dynamic provider (НЕ Asset Catalog — SPM Bundle.module crash)
- Snapshot = pointfreeco/swift-snapshot-testing ≥1.18.3 (1.18.0 имеет deadlock)
- Sheet = UnevenRoundedRectangle.clipShape (НЕ UIBezierPath)
- ConnectionButton spinner = .overlay on Circle (НЕ sibling в ZStack — иначе layout jumps)

**Следующий шаг**: Task 9 closure UAT — пользователь сверяет 7 экранов с Figma reference PNGs в iPhone 17 Simulator, заполняет `12-UAT.md`, signals `approved` → Phase 12 closure → `/gsd-discuss-phase 13`.

---

## 2026-05-16 (late) — Figma variable binding pass + designer Light mode finalization

**Operation:** User invoked full audit of Figma file BBTB v3 after observing «дизайн крайне плохо перенёсся из Figma в BBTB». Audit revealed 9 из 51 variables были bound; остальные nodes использовали raw hex literals (Phase 11 экспортировал tokens но не привязал к nodes).

**Что сделано:**

1. **Variable binding pass через `mcp__plugin_figma_figma__use_figma` Plugin API** — 170 fill/stroke bindings в 5 шагов:
   - Step 1 (Components page): Button_BG variants, Button texts, ServerRow/Selected, Spinner gradient — 25 bindings
   - Step 2 (Onboarding): hero text split, tip, PrimaryButton, SecondaryButton — 7 bindings
   - Step 3 (4× Home screens): TopBar icons, ServerStatusLabel, Уведомление — 18 bindings
   - Step 4 (both ServersSheets): 102 bindings (sheet bg, drag, header, AutoCell, sections, 16 ServerRows, ServerRowSelected, progress bar)
   - Step 5 fix: 5 screen backgrounds + 11 Button instance text overrides — 16 bindings

2. **User отредактировал Light mode** (designer finalization 2026-05-16):
   - `surface` Light: `#F4F4F6` → `#FFFFFF` (sheet visually = canvas)
   - `surfaceSunken` Light: `#ECEDEF` → `#F0F0F0`
   - `surfaceHeader` Light: `#E0E0E5` → `#E0E0E0`
   - **Создана новая variable `DS/Color/alwaysWhite`** (Dark=Light=#FFFFFF, scope TEXT_FILL) — для текста на accent/error backgrounds
   - **Lightning Vector** на AutoCell-Auto selected → перепривязан к `alwaysWhite` (был iconPrimary, который инвертируется в Light → invisible)

3. **17 rebindings к alwaysWhite** (Step 6) — все texts на accent/error backgrounds: ConnectionButton .connected/.error texts (master + 11 instance overrides), PrimaryButton text, Уведомление text, ServerRowSelected name text, AutoCell-Auto selected text.

4. **Smoke test Light mode (Home Disconnected, Servers Selected, Servers Auto, Onboarding):** все 7 экранов корректно рендерятся в обоих modes. Light mode переключение через Variables panel в Figma теперь полностью функционально.

5. **User-added scrim overlays:** Frame 14 (Selected sheet), Frame 15 (Auto sheet) — full-screen 402×874 black @20% opacity. UX pattern для presented sheet dimming. Hex literal, не bound — works visually в обоих modes.

**Swift code sync (этот commit):**
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/DSColor.swift` — добавлен `DS.Color.alwaysWhite` + обновлены Light hex'ы для surface/surfaceSunken/surfaceHeader
- `BBTB/Packages/DesignSystem/Tokens/figma-tokens.json` — totalVariables 51→52, metadata updated (lightModeFinalized + bindingsApplied dates)

**Изменённые / новые страницы wiki:**
- `wiki/swift-pixel-perfect-rebuild-2026.md` — добавлена секция «Figma binding (post-2026-05-16-late)» с binding count table, Light mode finalized values table, alwaysWhite usage pattern, known unbound nodes (Frame 14/15 scrims + Spinner stop[0] + dead Rectangle 2's)

**Следующий шаг:** Swift UI fix-loop по экранам (user написал что вернётся для постраничной правки кода). Figma теперь true source-of-truth — все правки кода могут ссылаться на DS variable name напрямую.

---

## 2026-05-16 (late evening) — Interactive UI fix-loop по 7 экранам BBTB v3

9 commits на main (`d7f35da` → `98c52a3`) после Figma binding pass — user
прошёл постранично по каждому экрану с детальным feedback'ом, добавлял Figma
codes из «Get Code» и подтверждал визуальные результаты.

**Commits chronologically:**

1. `d7f35da feat(ui): Home Empty State Figma rebuild + Phosphor SPM`
   - Phosphor Icons Bold пакет добавлен в DesignSystem (`@_exported import`)
   - EmptyStateCard full rewrite per Figma 3115:325
   - MainScreenView toolbar icons → `Ph.list.bold` / `Ph.plus.bold`

2. `3f06fad fix(ui): inline TopBar — removes iOS 26 Liquid Glass backdrop`
   - Native `.toolbar` заменён inline HStack в MainScreenView body
   - `.toolbar(.hidden, for: .navigationBar)` скрывает native chrome
   - Naked Phosphor glyphs без circle backdrop (Figma-aligned)

3. `23cdabd fix(ui): remove "Сервер: Авто" footer from EmptyStateCard`
   - Empty state не показывает server line (нет конфигов = нечего выбирать)
   - L10n.homeEmptyServerLine удалён, xcstrings entry убран

4. `bd9f8c2 feat(ui): Home states unified — embed Timer/Status into ConnectionButton`
   - External ConnectionTimer + StatusPill удалены из MainScreenView.content
   - ConnectionButton per-state labelContent: «СТАРТ»/«подключение»/«подключен»/«ошибка»
   - Inline TimelineView timer @ y=0 inside .connected ZStack
   - 5 new L10n keys: `home.button.*` (connecting/connected/error + hint_disconnect/reconnect)

5. `9a29eba feat(ui): ServerListSheet Figma BBTB v3 rebuild — Selected + Auto variants`
   - SectionCard wrapper (surfaceSunken bg + cornerRadius 24)
   - AutoCell single-line + Phosphor Lightning
   - ServerRow Phosphor Globe + 12pt Expanded Regular
   - LatencyBadge 9pt + «мс» suffix + isSelected param
   - SubscriptionHeader Phosphor CaretDown + progress placeholder

6. `a704cb8 fix(ui): ServerListSheet polish`
   - Header top padding 8 → 32pt (Figma 3064:1129 ServersSheet padding)
   - Progress bar убран (Subscription модель = бессрочная без quota fields)
   - ServerDetailView inline TopBar — устранён layout jump при push/pop

7. `0d54ceb fix(ui): collapsible sections + bottom dark strip fix`
   - ViewModel: `collapsedSectionIDs: Set<String>` + `toggleCollapsed`
   - SubscriptionHeader = Button + CaretDown `.rotationEffect(-90°)` CCW
   - Manual section header («Конфигурации») same pattern
   - `.ignoresSafeArea(edges: .bottom)` — surface bg доходит до home indicator
   - ServerRow hairline `.bottom` → `.top` (последняя строка без полосы)

8. `0ce1daa feat(ui): BBTBTopBar reusable + Connecting Spinner inset stroke ring`
   - **BBTBTopBar** component в DesignSystem (generic `<L, T>` slots +
     `BBTBBackButton` helper + convenience init `(title:, onBack:)`)
   - SettingsView / AdvancedSettingsView / HelpView migrated → BBTBTopBar
   - ConnectionButton.buttonBackground @ViewBuilder switch:
     `.connecting` → strokeBorder ring + BBTBSpinner @ diameter-6 на том же
     radius (Figma loading wheel pattern, было OUTER ring +24)

9. `98c52a3 feat(ui): floating banner overlay — no layout shift`
   - ReconnectBanner restyle: accent green pill + alwaysWhite + cornerRadius 16
   - MainScreenView: banner вынесен в `.overlay(alignment: .top)` —
     больше не shift'ит ConnectionButton/ServerLineView
   - `effectiveBannerMessage` derived: `.error` → «Ошибка подключения» (Figma
     3047:568), иначе `viewModel.reconnectBannerMessage`
   - Horizontal padding 80pt — banner между ≡ и + кнопками (per user spec)
   - Transition `.move(.top).combined(opacity)` + animation `.easeInOut(0.25)`

**Изменённые / новые wiki страницы:**
- `wiki/swift-pixel-perfect-rebuild-2026.md` — добавлена секция
  «2026-05-16 (late) — User-driven UI fix-loop» с patterns, per-screen
  changes, deferred backlog

**Деферрено за пределы UI fix-loop:**
- Migration existing inline TopBar'ы (MainScreenView, ServerListSheet,
  ServerDetailView) на `BBTBTopBar` — устранит дублирование. Текущие
  inline и `BBTBTopBar` сосуществуют корректно.
- Subscription quota fields + conditional progress bar in SubscriptionHeader
- Visual UAT всех states — требует реального config import (simctl без UI tap)

---
