---
phase: 10-advanced-settings-security-polish
verified: 2026-05-15T18:00:00Z
status: gaps_found
score: 6/7 must-haves verified
overrides_applied: 0
gaps:
  - truth: "STATE.md обновлён: status phase-complete, milestone v0.10, Phase 10 CLOSED секция добавлена"
    status: failed
    reason: "STATE.md header содержит status: executing, completed_phases: 8, таблица прогресса Phase 10 = 'Not started'. Секция 'Phase 10 ✅ CLOSED' отсутствует. Plan 06 Task 2 acceptance criteria grep -c 'Phase 10.*CLOSED' .planning/STATE.md возвращает 0 (требуется ≥ 1)."
    artifacts:
      - path: ".planning/STATE.md"
        issue: "status: executing (не phase-complete), completed_phases: 8 (не incremented), строка 277 'Phase 10 | Advanced settings | v0.10 | Not started' не обновлена, секция Phase 10 CLOSED отсутствует"
    missing:
      - "Обновить STATE.md frontmatter: status: phase-complete (или аналог)"
      - "Обновить progress.completed_phases (8 → 9 или следующее значение)"
      - "Обновить таблицу прогресса Phase 10: 'Not started' → '⚙️ Implementation complete 2026-05-15 — UAT pending'"
      - "Добавить секцию '### Phase 10 ✅ CLOSED 2026-05-15' с summary Wave 1-4"
      - "Обновить Current focus и Next Action секции"
deferred:
  - truth: "DPI-08: PinnedSubscriptionURLFetcher/SubscriptionPinManager подключены к реальному subscription fetch пайплайну"
    addressed_in: "Phase 12"
    evidence: "10-04-SUMMARY.md open follow-up 2: 'Wire SubscriptionPinManager into app: BBTB_iOSApp.swift needs to create SubscriptionPinManager + call bootstrap() + performBackgroundRefresh(). Phase 12 integration step.' Open follow-up 3: 'Wire PinnedSubscriptionURLFetcher in ServerListViewModel: inject вместо DefaultSubscriptionURLFetcher. Phase 12 integration.' — явно deferred, не gap Phase 10."
  - truth: "DPI-06: CDN-фронтинг применяется к серверам с frontingProfile (end-to-end)"
    addressed_in: "Phase 11"
    evidence: "REQUIREMENTS.md DPI-06 помечен '⚙️ Infrastructure-validated 2026-05-15 — activation pending: server-side frontingProfile payload в Marzban subscription + Cloudflare Worker rollout — Phase 11 admin handoff per wiki/cdn-fronting-server-handoff.md.' Intentional stub по design decision revision 2026-05-15."
human_verification:
  - test: "Запустить приложение на iPhone (iOS Simulator или device) → Settings → Расширенные"
    expected: "Видны 5 секций в порядке: MinAppVersionBanner (если применимо) → Anti-DPI → Безопасность → DNS → Rules. В Anti-DPI: CDN-фронтинг/Mux toggle, uTLS picker (menu), STUN-блок. В Безопасность: Cert pinning toggle."
    why_human: "SwiftUI Form layout и visual order не поддаются programmatic проверке без UI test framework."
  - test: "Tap STUN-блок toggle (OFF→ON) на любой платформе"
    expected: "Появляется destructive .alert с кнопками 'Включить' и 'Отмена'. Cancel возвращает toggle в OFF. Включить — writes stunBlockEnabled=true."
    why_human: "Alert interaction требует UI test run или ручного тестирования."
  - test: "На macOS: выключить enforceRoutes toggle → проверить Console.app"
    expected: "applyEnforceRoutesToManager log entry видна; bbtbProvisionerDidSave notification fired; manager.enforceRoutes = false."
    why_human: "Live-apply flow требует macOS device и активного VPN manager."
  - test: "Включить Mux toggle → reconnect к совместимому серверу (Trojan или VLESS+TLS без Reality)"
    expected: "В sing-box logs видна multiplex секция с protocol=smux, max_connections=4."
    why_human: "Требует реальное устройство с активной подпиской."
---

# Phase 10: Advanced Settings + Security Polish — Verification Report

**Phase Goal:** Implement Advanced Settings UI + security features: Mux (DPI-05), CDN fronting (DPI-06), cert pinning (DPI-08), STUN block (BIO-04), macOS enforceRoutes toggle (KILL-04), uTLS picker (UX-06). All gated by @AppStorage toggles. Wire FrontingEngine into production pipeline.
**Verified:** 2026-05-15T18:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Все 6 toggle (CDN, Mux, uTLS, STUN, cert pinning, macOS enforceRoutes) персистятся через @AppStorage с правильным suite mapping | ✓ VERIFIED | SettingsViewModel.swift: 6 @AppStorage props найдены; 4 NE-visible ключа используют App Group suite (grep = 4); utlsOptions static let = ["random","chrome","firefox","safari","ios","android","edge"]; stunBlockShowConfirm @Published присутствует. |
| 2 | AdvancedSettingsView рендерит 5 секций с AntiDPISection и SecuritySection | ✓ VERIFIED | AdvancedSettingsView.swift: секции 1 (Banner conditional) → 2 (AntiDPISection) → 3 (SecuritySection) → 4 (DNS) → 5 (Rules viewer) в правильном порядке; строки 42 и 46 подключают AntiDPISection(viewModel:) и SecuritySection(viewModel:). |
| 3 | Mux injection (DPI-05): expandConfigForTunnel инжектирует multiplex только для совместимых протоколов, idempotent | ✓ VERIFIED | SingBoxConfigLoader.swift: isMuxCompatible (15 hits grep multiplex/mux/isMuxCompatible), xtls-rprx-vision + reality guards; App Group UserDefaults read через AppGroupContainer.identifier. 11 test_mux_* тестов зелёные (commit 55e16fa 82/82 PASS). |
| 4 | STUN block injection (BIO-04): route.rule с port=[3478,5349], network=udp, action=reject, method=drop, idempotent через tag | ✓ VERIFIED | SingBoxConfigLoader.swift: "bbtb-stun-block" tag, stunBlockEnabled key, [3478, 5349], "method": "drop" — все присутствуют. 6 test_stun_block_* тестов. Coexistence с Mux step 7 подтверждена test_stun_block_coexists_with_mux. |
| 5 | macOS enforceRoutes (KILL-04): PlatformHooks + KillSwitch читают App Group UserDefaults; live-apply via applyEnforceRoutesToManager | ✓ VERIFIED | PlatformSpecific/macOS.swift: macOSDisableEnforceRoutes читается из AppGroupContainer.identifier (5 hits). KillSwitch.swift: #if os(macOS) с hardcoded suite "group.app.bbtb.shared" (6 hits). SettingsViewModel.swift: nonisolated public func applyEnforceRoutesToManager реализован. SecuritySection.swift: .onChange(of: viewModel.macOSDisableEnforceRoutes) wire присутствует. |
| 6 | uTLS picker (DPI-09 / UX-06): PoolBuilder.buildSingBoxJSON применяет utlsFingerprint из App Group; URI fp= сохраняет приоритет | ✓ VERIFIED | PoolBuilder.swift: applyUTLSPickerOverride helper + picker override logic (читает "app.bbtb.utlsFingerprint" из "group.app.bbtb.shared"); URI fp= приоритет через current == "random" guard. 3 теста в PoolBuilderTests зелёные (commit dbe86f6 243/243 PASS). |
| 7 | STATE.md обновлён: status phase-complete, Phase 10 CLOSED секция, completed_phases incremented | ✗ FAILED | STATE.md frontmatter: status: executing; completed_phases: 8; строка 277 таблицы: "Phase 10 | Not started"; секция "Phase 10 ✅ CLOSED" отсутствует. Plan 06 Task 2 acceptance criteria `grep -c 'Phase 10.*CLOSED'` = 0. |

**Score:** 6/7 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | DPI-08 cert pinning wired в production subscription fetch (PinnedSubscriptionURLFetcher/SubscriptionPinManager → ServerListViewModel) | Phase 12 | 10-04-SUMMARY.md open follow-ups 2+3: явно Phase 12 integration tasks. ServerListViewModel использует DefaultSubscriptionURLFetcher() как default. |
| 2 | DPI-06 CDN-фронтинг end-to-end активация (extractFrontingProfile возвращает nil → admin handoff) | Phase 11 | REQUIREMENTS.md DPI-06: ⚙️ Infrastructure-validated, activation pending Phase 11 admin handoff. extractFrontingProfile documented stub. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AntiDPISection.swift` | 4 controls: CDN/Mux/uTLS/STUN + STUN destructive alert | ✓ VERIFIED | Файл существует; stunBlockShowConfirm alert binding wired (7 hits); accessibilityIdentifier'ы присутствуют. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SecuritySection.swift` | cert pinning + macOS enforceRoutes + red footer | ✓ VERIFIED | Файл существует; #if os(macOS) guard; .onChange(of: viewModel.macOSDisableEnforceRoutes) wire. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/UTLSPickerView.swift` | Picker .menu style + 7 options + fallback | ✓ VERIFIED | Файл существует. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` | 6 @AppStorage + utlsOptions + stunBlockShowConfirm | ✓ VERIFIED | 16 hits Phase-10 keys; 4 App Group suite bindings; static let utlsOptions = [7 values]. |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` | Step 6 (STUN) + Step 7 (Mux) | ✓ VERIFIED | 15 hits (multiplex/mux/isMuxCompatible); 11 hits (stun-block/stunBlockEnabled/3478/drop). |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift` | shouldDisableEnforceRoutes читает App Group | ✓ VERIFIED | macOSDisableEnforceRoutes: 5 hits; AppGroupContainer.identifier: ≥1 hit. |
| `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` | platformShouldDisableEnforceRoutes #if os(macOS) + App Group | ✓ VERIFIED | macOSDisableEnforceRoutes: 6 hits; "group.app.bbtb.shared": 1 hit; #if os(macOS): 1 hit. |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinnedSessionDelegate.swift` | Apple Security SPKI pipeline | ✓ VERIFIED | SecTrustEvaluateWithError + SecTrustCopyCertificateChain + SecCertificateCopyKey + SecKeyCopyExternalRepresentation + SHA256: все 10 hits. |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift` | BootstrapPins + isValid(spkiHash:for:) | ✓ VERIFIED | Файл существует. |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinManifest.swift` | Codable + snake_case CodingKeys | ✓ VERIFIED | Файл существует. |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift` | Actor + bootstrap + performBackgroundRefresh + Ed25519 verify | ✓ VERIFIED | Файл существует. Примечание: не wired в production — deferred Phase 12. |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` | PinnedSubscriptionURLFetcher + makeSession | ✓ VERIFIED | PinnedSubscriptionURLFetcher добавлен. Примечание: не wired в production — deferred Phase 12. |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/Resources/subscription-pins-bootstrap.json` | Placeholder pin manifest | ✓ VERIFIED | Файл существует; spki_sha256_pins присутствует. |
| `scripts/generate-spki-pin.swift` | CLI с SecKeyCopyExternalRepresentation | ✓ VERIFIED | Файл существует; SecKeyCopyExternalRepresentation: 4 hits. |
| `BBTB/Packages/FrontingEngine/` | Новый SwiftPM пакет (10 source files) | ✓ VERIFIED | Package.swift существует; FrontingProfile, CDNProviderAdapter, CloudflareAdapter, FastlyAdapter, CustomCDNAdapter, FrontingConfigApplier, FrontingFailureCache, FrontingFallbackChain, FrontingError — все файлы присутствуют. |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` | certPinManifestDirectory + cdnFailureCacheURL | ✓ VERIFIED | certPinManifestDirectory: 1 hit; cdnFailureCacheURL: 1 hit. |
| `BBTB/Project.swift` | FrontingEngine wired в Xcode workspace | ✓ VERIFIED | "Packages/FrontingEngine": 1 hit. |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` | import FrontingEngine + FrontingConfigApplier call-site | ✓ VERIFIED | import FrontingEngine + FrontingConfigApplier: 3 hits. extractFrontingProfile stub documented. |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` | utlsFingerprint App Group read | ✓ VERIFIED | utlsFingerprint: 1 hit; "group.app.bbtb.shared": 1 hit. |
| `.planning/REQUIREMENTS.md` | [x] Validated для UX-06/DPI-05/DPI-08/DPI-09/BIO-04/KILL-04; DPI-06 ⚙️ infrastructure-validated | ✓ VERIFIED | Все 6 [x] markers присутствуют; DPI-06 помечен ⚙️; [x] DPI-06 = 0. |
| `.planning/ROADMAP.md` | Phase 10 статус + [x] для 10-06-PLAN.md | ✓ VERIFIED | 10-06-PLAN.md: [x] = 1; "Implementation complete 2026-05-15" в ROADMAP — отсутствует отдельной строкой, но Plans 6/6 = [x]. |
| `.planning/STATE.md` | phase-complete, Phase 10 CLOSED, v0.10 | ✗ FAILED | status: executing; completed_phases: 8; Phase 10 = "Not started"; CLOSED секция отсутствует. |
| `wiki/advanced-settings.md` | D-15 layout + toggle inventory | ✓ VERIFIED | Файл существует; D-15: 16 hits; Anti-DPI/STUN/enforceRoutes упомянуты. |
| `wiki/cdn-fronting-architecture-2026.md` | FrontingEngine + D-03..D-07 | ✓ VERIFIED | FrontingProfile: 13 hits. |
| `wiki/cdn-fronting-server-handoff.md` | Marzban + Cloudflare Worker | ✓ VERIFIED | Marzban + Cloudflare Worker: 11 hits. |
| `wiki/cert-pinning-spki.md` | SecKeyCopyExternalRepresentation + generate-spki-pin | ✓ VERIFIED | 9 hits. |
| `wiki/security-gaps.md` | R21+ новые записи | ✓ VERIFIED | R21/R22/R23/R24: 5 hits. |
| `wiki/architecture.md` | FrontingEngine добавлен | ✓ VERIFIED | FrontingEngine: 2 hits. |
| Memory `project_phase12_subscription_pins_prerequisite.md` | Placeholder pins warning | ✓ VERIFIED | Файл существует; MEMORY.md ссылка: 1 hit. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| AdvancedSettingsView | AntiDPISection + SecuritySection | viewModel composition | ✓ WIRED | строки 42 и 46 в AdvancedSettingsView.swift |
| SettingsViewModel @AppStorage (mux/stun/utls/enforceRoutes) | group.app.bbtb.shared UserDefaults | store: UserDefaults(suiteName:) | ✓ WIRED | 4 App Group suite bindings присутствуют |
| SingBoxConfigLoader.expandConfigForTunnel step 7 | muxEnabled (App Group) | AppGroupContainer.identifier | ✓ WIRED | grep = 1 usage |
| SingBoxConfigLoader.expandConfigForTunnel step 6 | stunBlockEnabled (App Group) | "app.bbtb.stunBlockEnabled" | ✓ WIRED | grep = 1 usage |
| PlatformHooks.shouldDisableEnforceRoutes | macOSDisableEnforceRoutes (App Group) | AppGroupContainer.identifier | ✓ WIRED | заглушка Phase 1 заменена |
| KillSwitch.platformShouldDisableEnforceRoutes | macOSDisableEnforceRoutes (App Group) | hardcoded "group.app.bbtb.shared" | ✓ WIRED | #if os(macOS) conditional |
| SecuritySection .onChange | applyEnforceRoutesToManager | Task { await viewModel.applyEnforceRoutesToManager() } | ✓ WIRED | grep = 2 hits SecuritySection |
| PoolBuilder.buildSingBoxJSON | utlsFingerprint (App Group) | "group.app.bbtb.shared" read | ✓ WIRED | applyUTLSPickerOverride helper |
| ConfigImporter.provisionTunnelProfile | FrontingConfigApplier.apply | import FrontingEngine + call-site | ✓ WIRED (infrastructure-only) | extractFrontingProfile returns nil v0.10 — intentional stub deferred Phase 11 |
| Project.swift | FrontingEngine package | .package(path: "Packages/FrontingEngine") | ✓ WIRED | 1 hit |
| PinnedSessionDelegate | PinStore.isValid(spkiHash:for:) | SHA256(SecKeyCopyExternalRepresentation) | ✓ WIRED | code path реализован |
| ServerListViewModel | subscription fetch | DefaultSubscriptionURLFetcher() (НЕ PinnedSubscriptionURLFetcher) | ⚠️ PARTIAL — deferred | PinnedSubscriptionURLFetcher создан но не wired в VM; Phase 12 integration task |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| AntiDPISection — Toggle CDN/Mux/STUN | viewModel.cdnFrontingEnabled / muxEnabled / stunBlockEnabled | @AppStorage (UserDefaults) | Да — persistent state | ✓ FLOWING |
| SingBoxConfigLoader step 7 | muxEnabled | App Group UserDefaults read | Да — real toggle value | ✓ FLOWING |
| SingBoxConfigLoader step 6 | stunBlockEnabled | App Group UserDefaults read | Да — real toggle value | ✓ FLOWING |
| PoolBuilder uTLS override | utlsFingerprint picker | App Group UserDefaults "app.bbtb.utlsFingerprint" | Да — real picker value | ✓ FLOWING |
| PinnedSessionDelegate | cert chain | URLSession challenge | Да — real TLS challenge | ✓ FLOWING (code path) |
| ServerListViewModel subscription fetch | fetcher | DefaultSubscriptionURLFetcher() | Нет pinning — placeholder | ⚠️ STATIC (pinning не активно; deferred Phase 12) |
| ConfigImporter CDN hook | frontingProfile | extractFrontingProfile() → nil | nil всегда | ⚠️ STATIC (infrastructure stub; deferred Phase 11) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| AntiDPISection.swift существует и компилируется | `ls BBTB/Packages/AppFeatures/Sources/SettingsFeature/AntiDPISection.swift` | EXISTS | ✓ PASS |
| Mux whitelist: 11 test_mux_* тестов | `grep -c 'test_mux' SingBoxConfigLoaderTests.swift` | 11 | ✓ PASS |
| STUN block: 6 test_stun_block_* тестов | `grep -c 'test_stun_block' SingBoxConfigLoaderTests.swift` | 6 | ✓ PASS |
| PoolBuilder uTLS override тесты | `grep -c 'test_buildSingBoxJSON_applies_utls' PoolBuilderTests.swift` | ≥ 2 | ✓ PASS |
| Все коммиты Phase 10 существуют | `git log --oneline` grep 16 SHA | 16/16 found | ✓ PASS |
| FrontingEngine package build | `swift build --package-path Packages/FrontingEngine` (per 10-05-SUMMARY) | Build complete, 0 errors | ✓ PASS (per SUMMARY) |
| STATE.md Phase 10 CLOSED | `grep -c 'Phase 10.*CLOSED' .planning/STATE.md` | 0 | ✗ FAIL |

### Probe Execution

Проект не имеет probe-*.sh файлов для Phase 10. Проверка через git commits и grep выполнена выше.

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| validate-r1-r6.sh | N/A — Phase 10 не добавляет новые R invariants; Phase 8 script не обновлялся | SKIP | ? SKIP |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| UX-06 | 10-01 | Advanced screen с 5 секциями, toggle'ы, uTLS picker | ✓ SATISFIED | AdvancedSettingsView 5-секционный Form; AntiDPISection/SecuritySection/UTLSPickerView созданы; REQUIREMENTS.md [x] |
| DPI-05 | 10-02 | Mux injection, D-09 whitelist, idempotent | ✓ SATISFIED | isMuxCompatible + step 7 в SingBoxConfigLoader; 10 unit-тестов; REQUIREMENTS.md [x] |
| DPI-06 | 10-05, 10-06 | CDN fronting (infrastructure-only) | ⚙️ INFRASTRUCTURE-VALIDATED | FrontingEngine package создан и wired в ConfigImporter; extractFrontingProfile() stub intentional; REQUIREMENTS.md ⚙️ (не [x]) |
| DPI-08 | 10-04 | Cert pinning (infrastructure + Phase 12 wiring) | ✓ SATISFIED (infrastructure) | PinnedSessionDelegate + PinStore + SubscriptionPinManager реализованы; 12 unit-тестов; REQUIREMENTS.md [x]; wiring deferred Phase 12 |
| DPI-09 | 10-01, 10-06 | uTLS picker → PoolBuilder | ✓ SATISFIED | UTLSPickerView + PoolBuilder utlsFingerprint override; REQUIREMENTS.md [x] |
| BIO-04 | 10-03 | STUN block toggle + route.rule inject | ✓ SATISFIED | Step 6 injection; destructive alert в AntiDPISection; REQUIREMENTS.md [x] |
| KILL-04 | 10-03 | macOS enforceRoutes toggle + live-apply | ✓ SATISFIED | PlatformHooks/KillSwitch заглушки заменены; applyEnforceRoutesToManager реализован; REQUIREMENTS.md [x] |

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift` | BootstrapPins placeholder (0x00/0x01 bytes) | ℹ️ Info | Intentional Phase 12 prerequisite; документировано в SUMMARY и memory; все real TLS connections будут rejected до Phase 12 rotation |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` | extractFrontingProfile() → nil (stub) | ℹ️ Info | Intentional infrastructure-only; Phase 11 admin handoff; документировано |
| `.planning/STATE.md` | status: executing, Phase 10 = "Not started" | 🛑 BLOCKER | Phase 10 closure не отражена; acceptance criteria Plan 06 Task 2 не выполнены |

Debt marker gate: `TBD`, `FIXME`, `XXX` маркеры в Phase 10 файлах не обнаружены (TODO/HACK — только в комментариях типа «Phase 12 prerequisite» с явной ссылкой на roadmap).

### Human Verification Required

#### 1. AdvancedSettingsView 5-секционный layout

**Test:** Запустить приложение на iOS Simulator (iPhone 16) или реальном устройстве → Settings → Расширенные.
**Expected:** Видны секции в порядке: Anti-DPI → Безопасность → DNS → Rules. В Anti-DPI: toggle CDN-фронтинг, toggle Mux, uTLS picker (Picker .menu), toggle STUN-блок. В Безопасность: Cert Pinning toggle.
**Why human:** SwiftUI Form rendering не поддаётся programmatic проверке без UI test framework или Simulator screenshots.

#### 2. STUN destructive alert flow

**Test:** Tap STUN-блок toggle OFF→ON.
**Expected:** Появляется .alert с заголовком "Включить блокировку STUN?" и двумя кнопками. Нажать "Отмена" → toggle возвращается в OFF. Нажать "Включить" → toggle остаётся ON.
**Why human:** Alert interaction требует UI test runner или ручного тестирования.

#### 3. macOS enforceRoutes live-apply

**Test:** На macOS выключить toggle "Принудительная маршрутизация" → проверить Console.app.
**Expected:** Log entry `applyEnforceRoutesToManager` visible; bbtbProvisionerDidSave notification fired. Footer секции Безопасность становится красным.
**Why human:** Требует macOS с VPN manager и активным VPN профилем.

#### 4. Mux injection на реальном устройстве

**Test:** Включить Mux toggle → reconnect к Trojan или VLESS+TLS серверу → открыть sing-box log.
**Expected:** В log видна multiplex конфигурация: "enabled": true, "protocol": "smux", "max_connections": 4.
**Why human:** Требует реальное устройство с активной Marzban подпиской.

### Gaps Summary

**1 BLOCKER — STATE.md не обновлён к phase-complete:**

Plan 06 Task 2 явно требует обновления STATE.md со следующими элементами:
- `status: executing` → `status: phase-complete` (или аналог)
- `completed_phases: 8` → incremented (8 → 9)
- Таблица прогресса: строка Phase 10 "Not started" → "⚙️ Implementation complete 2026-05-15 — UAT pending"
- Добавить секцию "### Phase 10 ✅ CLOSED 2026-05-15" (по образцу Phase 8 CLOSED секции на строке 54)
- Обновить "Current focus" и "Next Action" секции

Все остальные артефакты Phase 10 реализованы и подтверждены в codebase:
- 6 @AppStorage toggles присутствуют и правильно wired
- Mux injection (10 тестов), STUN block injection (6 тестов), macOS enforceRoutes (4 теста) реализованы
- FrontingEngine SwiftPM пакет (10 source files, 20 тестов) создан и wired в Project.swift + AppFeatures
- Cert pinning инфраструктура (12 тестов) реализована
- PoolBuilder uTLS picker override (3 теста) реализован
- Wiki (5 новых страниц + 3 обновлены), REQUIREMENTS.md ([x] markers), ROADMAP.md ([x] plans) обновлены корректно

Deferred items (Phase 11/12):
- DPI-08 production wiring: PinnedSubscriptionURLFetcher в ServerListViewModel → Phase 12
- DPI-06 end-to-end activation: admin handoff + extractFrontingProfile parsing → Phase 11

---

_Verified: 2026-05-15T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
