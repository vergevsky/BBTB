# Phase 11 — Onboarding + UX polish — Final SUMMARY

**Status:** ✅ Closed 2026-05-16
**Version:** v0.11
**Duration:** 2026-05-15 (`/gsd-discuss-phase 11`) → 2026-05-16 (closure)
**Waves:** 5
**Plans:** 8 plans (11-01..11-08)
**Requirements closed:** 11 (9 ✅ Validated + 1 ⏸ figma-pending + 1 ⚙️ Infrastructure-validated)

## Goal recap

Финальный UX-слой v0.11 перед TestFlight: onboarding для новых пользователей, file picker импорт (IMP-03 carry-over из Phase 2 → Phase 11), тихий MAX-detection без UI, log export через Share Sheet, FAQ/Help экран, ConnectionButton spinner overlay, полная локализация ru/en без hardcoded строк, ServerListSheet height re-tune по Figma.

Phase 11 D-07 two-stream architecture: код stream (LOC, DETECT, TELEM, IMP-03) + UI polish stream (UX-08, UX-09, D-08) реализованы параллельно. Wave 4 human-verify checkpoint resolved with signal `figma-pending` — Figma cleanup + Code Connect setup сделаны в session 2026-05-15/16 (commit `cc7b216`); pixel-perfect Swift rebuild carried forward to Phase 12 (redefined as «Swift pixel-perfect rebuild from Figma»).

## Outcome

5 waves, 8 plans закрыты. Все 11 req IDs accounted: 9 ✅ Validated + 1 ⏸ figma-pending (UX-09; full re-Validated в Phase 12) + 1 ⚙️ Infrastructure-validated (DETECT-03; admin handoff Phase 12+).

### Requirements status

| Req ID | Status | Acceptance |
|--------|--------|------------|
| UX-01 | ✅ Validated | `OnboardingView` fullScreenCover + `@AppStorage("app.bbtb.hasShownOnboarding")` sticky-forever + auto-dismiss; 2 CTA (paste primary, QR secondary); file picker НЕ в Onboarding (D-04); 3 tests; Wave 2 merge `d3e2773` |
| UX-08 | ✅ Validated | `ConnectionButton` `ProgressView().circular.tint(.white).controlSize(.large)` overlay при `.connecting`; power-icon `.opacity(isConnecting ? 0 : 1)`; identifier `BBTB.ConnectionButton` preserved; +1 test `testSpinnerVisibleWhenConnecting`; commit `e23c6bc`; Phase 12 M6 followup (custom 4-frame ring) |
| UX-09 | ⏸ figma-pending | Task 7.4 human-verify checkpoint resolved with signal `figma-pending`; Figma file BBTB v3 cleaned in session 2026-05-15/16 (51 variables, 5 components, semantic naming, Code Connect documentation contracts); 10 mismatches M1-M10 enumerated в `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §4; commit `cc7b216`; **Phase 12 redefined as «Swift pixel-perfect rebuild from Figma» для full re-Validated** |
| DETECT-01 | ✅ Validated | `MAXDetector.detectIOS` через `URLSchemeQueryable` protocol abstraction; Info.plist `LSApplicationQueriesSchemes` whitelist 4 candidate schemes `[max, max-app, ru-max, vkmax]`; silent log only; mock-based unit tests; Wave 2 merge `d3e2773` |
| DETECT-02 | ✅ Validated | `MAXDetector.detectMacOS` через `WorkspaceQueryable` protocol abstraction; 4 candidate bundle IDs `[ru.vk.max, com.vkontakte.max, chat.max.app, ru.max.messenger]`; silent log only; mock-based tests; Wave 2 merge `d3e2773` |
| DETECT-03 | ⚙️ Infrastructure-validated | `wiki/max-domains-blocklist.md` admin handoff doc создан в Plan 04; client-side code = Phase 8 RulesEngine pipeline (D-01..D-13); server-side rules.json signing + publish MAX-domains → Phase 12+ admin handoff prerequisite |
| TELEM-02 | ✅ Validated | `DiagnosticsExporter` actor reads sing-box.log из App Group + IP-mask regex D-12 → tmp file; `DiagnosticsSection` cross-platform `ShareLink(item: URL)`; iOS 16+ / macOS 13+ minimum покрыт нашими 18/15; empty-state alert при отсутствии log; 5 tests; commit `7765757` (актуальный: `bbf6033` + `c7f8d65`) |
| LOC-02 | ✅ Validated | ~30 new L10n keys через `Localization/Resources/Localizable.xcstrings` (ru+en); ConfigImporter.swift hardcoded Russian strings cleared (line 42 + ~984); TransportPicker.swift 5 protocol labels → L10n; lint-gate `grep '"[А-Яа-яЁё]'` returns 0 + `grep '^Text\("[A-Z][a-z]+"\)'` returns 0; commit `5c6bdff` + `d5f9793` |
| LOC-03 | ✅ Validated | `HelpView` с 5 DisclosureGroup FAQ (как добавить сервер / не подключается / WebRTC leak / 22 приложения из РФ / ограничения детектирования); NavigationLink из `SettingsView`; полная ru+en локализация; 4 tests; commit `21fc9c6` |
| LOC-04 | ✅ Validated | FAQ4 «22 приложения из РФ»; `HelpViewTests.test_LOC04_FAQ4_contains_detection_keywords` PASS; cross-ref `wiki/vpn-detection-by-apps.md`; commit `21fc9c6` |
| IMP-03 | ✅ Validated | `ImportSource.file` case в VPNCore `ParsedConfigs`; `MainScreenView .fileImporter` modifier wired в меню «+»; `MainScreenViewModel.importFromFile`; security-scoped resource handling (Pitfall 5); 3 unit tests; D-04: file picker только через меню «+»; commit `2cc1041` |

## Tests (final regression gate Task 8.1)

- **AppFeatures swift test:** 207/207 PASS (0 failures, 0 skipped)
- **VPNCore swift test:** 57/57 PASS (1 test skipped — pre-existing)
- **ConfigParser swift test:** 243/243 PASS
- **PacketTunnelKit swift test:** 91/91 PASS
- **Localization swift build:** Build complete (no tests in package)
- **iOS xcodebuild (iPhone Simulator):** SUCCEEDED
- **macOS xcodebuild:** SUCCEEDED (ad-hoc signing — `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`; Phase 1 DIST-02 carry-over — Distribution credentials prerequisite для Phase 13 TestFlight)
- **LOC-02 lint:** 0 Russian hardcoded + 0 English `Text("...")` hardcoded
- **R1/R6/R10/R12/D-08 invariants** (`validate-r1-r6.sh`): ALL PASS — Phase 11 не сломала никаких previous invariants

## Invariants preserved

- **R1/R6/R10/R12** (Phase 1/8/10): нет SOCKS inbound, gRPC disabled, P2P=false, route.rule_set integrity, Ed25519 signing — verified `validate-r1-r6.sh` PASS.
- **D-08** (Phase 8 sing-box rule_set): preserved (мы не трогали route/engine code).
- **Phase 6c on-demand intent-closing**: preserved (no changes к TunnelController).
- **Phase 6d DEC-06d-01..06**: preserved (cold-start defer + XPC ≤ 2 trips + AsyncStream polling + bounded concurrency + Apple-canonical options + PerfSignposter spans). DiagnosticsExporter использует DEC-06d-01 pattern (file IO в Task).
- **Phase 9 DEEP-01/02/05**: preserved (no changes к `DeepLinkRouter`).
- **Phase 10 DPI-* + UX-06 + KILL-04**: preserved (no changes к Mux/STUN/Pinning/Fronting/enforceRoutes).
- **`BBTB.ConnectionButton` accessibility identifier**: preserved (Task 7.1 acceptance criterion — UX-08 spinner overlay не сломал accessibility surface).

## Final commits (chronological highlights)

**Wave 1 (L10n foundation):**
- `d5f9793` — feat(11-01): Phase 11 L10n keys (онбординг, FAQ, диагностика, transport, импорт-файл)
- `5c6bdff` — feat(11-01): LOC-02 cleanup — ConfigImporter + TransportPicker через L10n

**Wave 2 (parallel code stream — IMP-03, UX-01, DETECT-01/02):**
- `ffa9231` + `5311d16` + `2cc1041` — IMP-03 (ImportSource.file + fileImporter UI)
- `e0ace85` + `c4d7565` — UX-01 (OnboardingView + MainScreenView integration)
- `e636331` + `1a9f3ce` + `d3e2773` — DETECT-01/02 (MAXDetector + App entry wiring + Info.plist + admin handoff wiki)

**Wave 3 (Settings sections — TELEM-02, LOC-03/04):**
- `bbf6033` + `c7f8d65` — TELEM-02 (DiagnosticsExporter + DiagnosticsSection)
- `b1b1d5b` + `7b0656a` + `21fc9c6` — LOC-03/04 (HelpView + Settings NavigationLink)

**Wave 4 (UI polish stream + Figma checkpoint):**
- `e23c6bc` — UX-08 ConnectionButton spinner overlay
- `4913a46` — D-08 ServerListSheet height TODO + 4 height tests
- `908e8e7` — UX-09 OnboardingView Figma polish TODO marker
- `7a823ce` — Phase 11 state save at Wave 4 checkpoint pause
- `cc7b216` — Figma file cleanup (51 variables, 5 components, semantic naming) + Code Connect Swift mappings (4 `.figma.swift` files + figma.config.json + CODE-CONNECT.md) (Task 7.4 follow-up, session 2026-05-15/16)
- `e365d40` — Plan 07 closure SUMMARY (Task 7.4 figma-pending signal documented)

**Wave 5 (closure):** этот commit — `chore(11-08): phase 11 closure` (REQUIREMENTS / ROADMAP / STATE / wiki / Final-SUMMARY).

## Outstanding / carry-out

### → Phase 12 (Swift pixel-perfect rebuild from Figma, v0.12-design)

**10 mismatches M1-M10** (из `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §4):

- M1 — `DS.ConnectionButtonSize.compactDiameter` 140 → 280; `regularDiameter` 160 → 320
- M2 — `compactIcon` 56 → 112; `regularIcon` 64 → 128
- M3 — ConnectionButton fill colors → `DS.Color.controlIdle / .accent / .error` (new tokens)
- M4 — Font family `.system(.body, design: .rounded)` → SF Pro Expanded
- M5 — `DS.accent`: `.accentColor` → `Color("DS/Color/accent")` (hex #14664B)
- M6 — Spinner placeholder `ProgressView()` → custom 4-frame rotating ring matching Figma Spinner component
- M7 — Onboarding PrimaryButton/SecondaryButton — custom `ButtonStyle` matching Figma pill design (full-width 49pt height)
- M8 — ServerRow padding/spacing verified против Figma 16/12pt values; height constants update
- M9 — Sheet corner radius 32pt at top corners (`RoundedCorner` shape primitive)
- M10 — Section corner radius 24pt (новый `DS.Radius.section` token)

Plus **UX-09 figma-pending** → full re-Validated с side-by-side Figma↔simulator screenshot diff ≤ 2px на всех 7 key screens.

### → Phase 13 (Pre-release + Public TestFlight, v0.13 + v1.0)

1. **DETECT-03 admin handoff** — server-side rules.json sign + publish MAX-domains из `wiki/max-domains-blocklist.md`. Client side готов (Phase 8 RulesEngine pipeline).
2. **MAX bundle ID device UAT** — установить MAX на test device with MAX installed; обновить candidate lists (один-line code change).
3. **Apple Distribution credentials** — DIST-02 prerequisite, Phase 1 carry-over (cert + App Store profiles для `app.bbtb.client.ios` + `.tunnel` + `.macos` + `.macos.tunnel`).
4. **SPKI subscription pins replacement** — `PinStore.swift` placeholder pins (64 `a`s + 64 `b`s) ДОЛЖНЫ быть заменены через `generate-spki-pin.swift` ДО TestFlight upload (Phase 10 prerequisite).
5. **macOS UAT replay** (5 scenarios A / F-direct / F-reverse / Settings-disable / G) — Phase 6e D-03 defer.
6. **Numerical Instruments baseline** — Phase 6e D-02 defer; PerfSignposter готов (DEC-06d-06); capture для Phase 13 pre-TestFlight obligatory snap.

## Architecture notes

- **Two-stream architecture (D-07)** позволила параллельно ехать code stream (Plans 02/04/05/06) и UI stream (Plans 03/07) — особенно useful когда Figma приходит позже. Pattern переиспользуется в будущих UX-heavy phases где визуал может быть deferred.
- **MAXDetector mockable surface** — pattern для будущих cross-app probe (детектирование других messenger'ов, проверка наличия конкурентов). Protocol abstraction (`URLSchemeQueryable` / `WorkspaceQueryable`) изолирует platform APIs.
- **DiagnosticsExporter as namespace enum/actor** — stateless API проще test'ить и reason'ить чем actor; pattern переиспользуется в Phase 13 (TELEM-04+ batch analytics). IP-mask through `NSRegularExpression` regex `(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}` → `$1xxx` — простой и effective.
- **fullScreenCover + @AppStorage gate** — pattern для one-time onboarding flows. Установлен как стандарт для будущих welcome screens / privacy disclosure screens.
- **Code Connect canImport guard** — `#if canImport(CodeConnect)` wrapper позволяет добавлять Figma↔Swift documentation contracts без блокировки compilation (Figma Education plan limitations workaround).

## Session 2026-05-15/16 — Design system tokens decisions

Figma file BBTB v3 был передан пользователем 2026-05-15. Task 7.4 human-verify checkpoint reframed как Figma cleanup + Code Connect setup follow-up:

- **6-step Figma cleanup** через `figma-mcp-go` MCP (commit `cc7b216`): variable normalization, component set creation, semantic layer naming, orphan token removal
- **Two-tier token model**: Primitives (11 raw values) + DS (40 semantic tokens с binding)
- **Dark + Light modes**: native Figma modes (Education plan support); variable binding на canvas/surface/textPrimary
- **Component sets**: 3 sets (Button / Button_BG / Spinner) + 2 standalone (ServerRow + AutoCell)
- **Code Connect Education plan blocker**: `code_connect:write` scope недоступен на Education tier; Organization+ ($45/user/mo) required. Workaround: 4 `.figma.swift` файла как documentation contracts wrapped в `#if canImport(CodeConnect)` (compile-inert; auto-activate при plan upgrade + SDK install).
- **Figma — источник истины для визуала**; Swift догоняет в Phase 12 (user decision 2026-05-15: «приоритет: pixel-perfect дизайн в Фигме → код»).

## Wiki long-term memory

- **Created:** `wiki/onboarding-ux-polish-2026.md` (D-01..D-12 decisions + DS-01..06 design system + MAX-detection candidates + patterns + 10 Phase 12 mismatches) — 151 lines
- **Created Plan 04:** `wiki/max-domains-blocklist.md` (DETECT-03 admin handoff doc)
- **Updated:** `wiki/index.md` (link на `onboarding-ux-polish-2026.md`)
- **Appended:** `wiki/log.md` (daily entry 2026-05-16 Phase 11 closure)

## Next phase

`/gsd-discuss-phase 12` — Swift pixel-perfect rebuild from Figma (v0.12-design).

Phase 12 scope (redefined 2026-05-16):

- Все 10 mismatches M1-M10 (см. above)
- DS namespace expansion (`DS.Color.*`, `DS.Typography.Size.*`, `DS.Radius.section/sheet`, `DS.Blur.pill`)
- SF Pro Expanded font подключение через Info.plist `UIAppFonts`
- Side-by-side Figma↔simulator pixel diff ≤ 2px verification на 7 key screens
- Optional Light mode activation

Phase 12 prerequisites (не блокирующие, но желательные):

- Code Connect SDK Swift package (require Organization+ Figma plan для publish; Education plan можно development-only)
- Side-by-side comparison tooling (Figma plugin export или manual screenshot capture)

## Phase 12 → Phase 13 prerequisite chain

После Phase 12 закрытия → `/gsd-discuss-phase 13` для TestFlight & Distribution (was Phase 12 scope). Phase 13 prerequisites:

- Apple Distribution credentials (cert + 4 App Store profiles)
- SPKI subscription pins replacement (Phase 10 placeholder)
- DETECT-03 admin handoff (Phase 11 carry-out)
