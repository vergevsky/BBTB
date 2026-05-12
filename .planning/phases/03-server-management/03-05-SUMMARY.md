---
phase: 03-server-management
plan: 05
subsystem: MainScreenFeature/ConfigParser/Localization
tags: [auto-select, reconnect, user-defaults, pre-connect-probe, pitfall-mitigation]
requires:
  - PoolBuilder.buildSingBoxJSON (Phase 2) degenerate-case path
  - ServerProbing protocol + ServerProbeService (Plan 02)
  - ServerScore.autoSelect (Plan 02)
  - ConfigImporting protocol + ConfigImporter (Plan 04)
  - ServerListViewModel coordinator backlink (Plan 03)
provides:
  - PoolBuilder.buildSingleOutboundJSON (public, 1-outbound deploy)
  - ConfigImporting.provisionTunnelProfile(for: UUID?) (single-outbound + Pitfall-10 fallback)
  - MainScreenViewModel.performPreConnectAutoSelect (parallel probe → autoSelect)
  - MainScreenViewModel.reconcileSelectionWithStore (Pitfall-10 reconcile)
  - MainScreenError enum (noReachableServers / noSupportedServers)
  - applySelection reconnect-on-active (D-09)
  - selectedServerID UserDefaults mirror (didSet)
  - L10n.serverListNoReachableServers / serverListNoSupportedServers
affects:
  - MainScreenViewModel init signature (probeService: ServerProbing, userDefaults: UserDefaults)
  - ConfigImporting protocol (NEW method provisionTunnelProfile(for:))
  - Existing test mocks (PullToRefreshTests, CascadeDeleteTests) — stub provisionTunnelProfile
tech-stack:
  added: []
  patterns: [pre-connect-tcp-probe, autoSelect-score-min, 1-outbound-degenerate-pool, reconnect-on-selection-no-alert, didSet-mirror-userDefaults, reconcileSelectionWithStore]
key-files:
  created:
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderSingleOutboundTests.swift
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift
    - .planning/phases/03-server-management/03-05-SUMMARY.md
  modified:
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
    - BBTB/Packages/Localization/Sources/Localization/L10n.swift
    - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
    - BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift
    - BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/CascadeDeleteTests.swift
decisions:
  - "buildSingleOutboundJSON — thin wrapper над degenerate-case (Phase 2 уже корректно работал для count==1, дублирования логики избежали)"
  - "provisionTunnelProfile(for:) Pitfall-10 fallback: если selectedID указывает на удалённый сервер → silent fallback на full pool urltest вместо exception"
  - "reconcileSelectionWithStore вызывается из refresh() — пассивная санитизация, НЕ trigger'ит reconnect (это бы caused reconnect spam при scenePhase .active)"
  - "selectedServerID UserDefaults через didSet — мирэр; init() читает UserDefaults и проставляет selectedServerID через свойство (didSet безопасно — UserDefaults уже содержит то же значение, no-op write)"
  - "ProbeServicing → использовали уже существующий `ServerProbing` protocol (Plan 04 уже ввёл — Plan 05 plan описание было основано на устаревшем снимке кода)"
  - "Pre-connect timeout — на 1 сервере выходим из ping-loop (degenerate case): не имеет смысла пинговать единственный supported сервер для autoSelect"
metrics:
  duration_min: 12
  completed: 2026-05-12
  red_commit: a6a9aa4
  green_commit: e1861e0
  task_count: 2_of_3
  test_count_added: 11
  packages_green: [VPNCore, ConfigParser, AppFeatures, Localization]
---

# Phase 3 Plan 05: Pre-connect auto-select + reconnect-on-selection Summary

**One-liner:** Pre-connect parallel TCP probe → min-score winner → 1-outbound pool deploy через `provisionTunnelProfile(for:)`; reconnect-on-selection без алерта (D-09); UserDefaults persist для selectedServerID; Pitfall 8 (all unreachable) + Pitfall 10 (deleted selected ID) graceful fallbacks. Tasks 1 + 2 завершены, Task 3 (UAT) — ожидает человеческой верификации.

## What was built

### Task 1 (RED) — commit `a6a9aa4`

**PoolBuilderSingleOutboundTests.swift** — 5 RED тестов:
- `test_buildSingleOutboundJSON_returns_pool_with_no_urltest` — 1 outbound + direct, без urltest, route.final = outbound tag.
- `test_buildSingleOutboundJSON_equals_buildSingBoxJSON_with_one_element_array` — структурный equality (NSDictionary deep equal — JSON key order non-deterministic).
- `test_buildSingleOutboundJSON_preserves_protocol_specific_settings_vless` — все VLESS-Reality поля сохранены (uuid, flow, sni, publicKey, shortId, fingerprint).
- `test_buildSingleOutboundJSON_preserves_protocol_specific_settings_trojan_ws` — Trojan-WS поля (password, path, host, ALPN h2-strip).
- `test_buildSingleOutboundJSON_dns_detour_points_to_outbound` — dns-remote.detour = outbound tag (не "urltest-out").

**AutoSelectIntegrationTests.swift** — 6 RED тестов:
- `test_pre_connect_auto_select_picks_min_score_server` (Auto winner = min score B 50ms из {A 100ms, B 50ms, C 200ms}).
- `test_pre_connect_all_unreachable_returns_error` (Pitfall 8 — state .error с L10n.serverListNoReachableServers).
- `test_manual_selected_server_skips_auto_select` (manual idA → provision(idA) даже если probe = unreach).
- `test_selection_change_during_active_tunnel_reconnects` (D-09 — disconnect → provision → connect, без banner).
- `test_selectedServerID_persists_via_user_defaults` (vm1 set idA → vm2 same suite → vm2.selectedServerID == idA).
- `test_deleted_selected_server_falls_back_to_auto` (Pitfall 10 — reconcileSelectionWithStore сбрасывает stale ID).

### Task 2 (GREEN) — commit `e1861e0`

**PoolBuilder.buildSingleOutboundJSON** — public static, thin wrapper над `buildSingBoxJSON([parsed])`. Reuse degenerate-case (Phase 2 уже корректно генерировал 1-outbound pool без urltest).

**ConfigImporting protocol extension:** новый метод
```swift
func provisionTunnelProfile(for selectedID: UUID?) async throws
```
Контракт:
- selectedID != nil + server present → 1-outbound через `buildSingleOutboundJSON`.
- selectedID != nil + server отсутствует (race deleted) → silent fallback на full pool через `buildSingBoxJSON` (Pitfall 10 graceful, NO exception).
- selectedID == nil → full pool urltest.
- 0 supported → throws `ImporterError.noSupportedServers`.

**ConfigImporter.provisionTunnelProfile(for:)** реализация:
- Fetch supported ServerConfig из ModelContext.
- Резолв targets (1 или N).
- Reparse `AnyParsedConfig` из Keychain payload + ServerConfig metadata (новый helper `reparseFromKeychain`).
- Build JSON (single или multi через урлtest), SingBoxConfigLoader.validate (R1 self-check), `tunnelProvisioner.provisionTunnelProfile`.
- tunnelRemoteAddress = host первого target (валидный IP/hostname per memory `feedback_netunnelnetworksettings_tunnelRemoteAddress.md`).

**MainScreenViewModel:**
- `init(probeService: ServerProbing? = nil, userDefaults: UserDefaults = .standard)` — full DI.
- `selectedServerID` теперь PERSIST через `didSet` → UserDefaults key `app.bbtb.selectedServerID`; восстанавливается в init из UserDefaults.
- `performToggleImpl` ветвление:
  - `selectedServerID != nil` → `provisionTunnelProfile(for: id)` напрямую (Manual path).
  - `selectedServerID == nil` → `performPreConnectAutoSelect()` (parallel probe → autoSelect) → `provisionTunnelProfile(for: winner)`.
- `performPreConnectAutoSelect()` async throws → UUID:
  - 1 supported → degenerate, return single id (no probe).
  - N supported → probe → ServerScore.autoSelect → throws `noReachableServers` если все nil.
- `MainScreenError` enum: `noReachableServers` / `noSupportedServers` с `errorDescription` мапящимся на L10n.
- `reconcileSelectionWithStore()` (public, async) — Pitfall 10 — сбрасывает stale ID в nil, БЕЗ trigger reconnect.
- `applySelection(_:)` в `.connected` → reconnect Task без alert (D-09 — UI просто видит .connected → .connecting → .connected sequence).

**L10n** — 2 новых ключа:
- `serverList.noReachableServers` — «Все серверы недоступны. Проверьте подключение к интернету.» / EN equivalent.
- `serverList.noSupportedServers` — «Нет поддерживаемых серверов.» / EN equivalent.

## Plan Goal Coverage

Phase 3 user story «As a пользователь BBTB, I want to ... подключаться к лучшему доступному серверу без ручной настройки» — **полностью покрыто** после Plan 05 Task 2:
- Auto mode → 3 sequential TCP probes для каждого supported сервера → min score winner → 1-outbound deploy → connect.
- Manual mode → 1-outbound deploy выбранного сервера, БЕЗ автовыбора.
- Switch при активном tunnel → reconnect без банера.
- Persistance — selectedServerID restored на следующий launch.

## Test Counts

| Package | Before | After | Delta |
|---------|--------|-------|-------|
| ConfigParser | 78 | 83 | +5 (PoolBuilderSingleOutboundTests) |
| AppFeatures | 31 | 37 | +6 (AutoSelectIntegrationTests) |
| VPNCore | 32 | 32 | 0 (no regressions) |
| Localization | 3 | 3 | 0 (no regressions) |

**Total new tests: 11 (5 ConfigParser + 6 AppFeatures).** Все green.

## Deviations from Plan

### Auto-fixed Issues (Rules 1-3)

**1. [Rule 1 — Bug] Test fixture: equality test fixed для non-deterministic JSON key order**
- **Found during:** Task 2 (GREEN run).
- **Issue:** `test_buildSingleOutboundJSON_equals_buildSingBoxJSON_with_one_element_array` использовал string equality (`XCTAssertEqual(single, multi)`), но `JSONSerialization.data` не гарантирует порядок ключей в dictionary. Тест failed несмотря на семантическое равенство JSON.
- **Fix:** заменили на NSDictionary structural equality через `parse(json) as NSDictionary` (recursive `isEqual`).
- **Files modified:** `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderSingleOutboundTests.swift`
- **Commit:** `e1861e0` (rolled into Task 2).

**2. [Rule 3 — Blocking] ProbeServicing protocol уже существовал**
- **Found during:** Task 1 RED compile.
- **Issue:** План описал «ввести `protocol ProbeServicing`», но Plan 04 уже ввёл `public protocol ServerProbing` в `ServerProbeService.swift`. Тесты использовали `ServerProbing` — это работало.
- **Fix:** использовали существующий `ServerProbing` (no new code), просто адаптировали init signature `MainScreenViewModel` чтобы принимать `ServerProbing?` вместо concrete `ServerProbeService?`.
- **Files modified:** `MainScreenViewModel.swift` (init signature).
- **Commit:** `e1861e0`.

**3. [Rule 3 — Blocking] Existing test mocks не conform'или к новому protocol surface**
- **Found during:** Task 2 GREEN compile.
- **Issue:** `PullToRefreshTests.MockImporter` и `CascadeDeleteTests.StubImporter` сломались с «type does not conform to protocol ConfigImporting» после добавления `provisionTunnelProfile(for:)` в `ConfigImporting`.
- **Fix:** добавили no-op stub `func provisionTunnelProfile(for selectedID: UUID?) async throws {}` в оба мока (эти тесты не проверяют provision-flow — Plan 03/04 scope).
- **Files modified:** `PullToRefreshTests.swift`, `CascadeDeleteTests.swift`.
- **Commit:** `e1861e0`.

**4. [Rule 1 — Bug] Test seed helper нужно было синхронизировать с MockImporter.supportedCount**
- **Found during:** Task 2 GREEN run.
- **Issue:** MockImporter.countSupportedConfigs() возвращал 0 (default), потому что seedServer вставлял ServerConfig только в SwiftData, но не извещал mock. Это приводило к refresh() → state=.empty → performToggle() returns early, provisionCalls=0.
- **Fix:** seedServer теперь принимает `importer: MockImporter` параметр и bump'ит `supportedCount`. Тесты создают importer ПЕРЕД seedServer.
- **Files modified:** `AutoSelectIntegrationTests.swift`.
- **Commit:** `e1861e0`.

### No architectural deviations (Rule 4)

Все изменения остаются в пределах plan'ской семантики. Никаких новых модулей, schema-изменений, breaking API.

## Authentication Gates

None — все тесты CLI-runnable без OS auth.

## Stub tracking

None — Plan 05 не вводит UI-stubs, plumbing полный.

## Known Stubs / Deferred Issues

Никаких stub'ов и deferred issues. Plan 05 закрывает связку pre-connect / reconnect / persist полностью.

## Threat Flags

Никаких новых threat surfaces за пределами `<threat_model>` в PLAN.md. T-03-23..T-03-27 mitigations реализованы в коде:
- T-03-23 (Tampering — stale UserDefaults selectedServerID) → `reconcileSelectionWithStore` + Pitfall 10 fallback в `provisionTunnelProfile`.
- T-03-24 (Information Disclosure — pre-connect probe leaks IP) → **accepted**; документировано в `wiki/security-gaps.md` (carry-forward от Plan 02 решения).
- T-03-25 (DoS — reconnect race) → `applySelection` структурирована через `Task { @MainActor in }` (sequential by main actor); test_selection_change_during_active_tunnel_reconnects подтверждает one-at-a-time.
- T-03-26 (.connecting stuck) → catch блок в `performToggleImpl` + `reconnectAfterSelectionChange` всегда переходит в `.error`. Test_pre_connect_all_unreachable_returns_error verifies.
- T-03-27 (extension privilege escalation) → reused Phase 2 ConfigImporter validate + R1 SingBoxConfigLoader.validate в новом provisionTunnelProfile path.

## Self-Check: PASSED

**Files created:**
- BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderSingleOutboundTests.swift — FOUND
- BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift — FOUND
- .planning/phases/03-server-management/03-05-SUMMARY.md — FOUND (this file)

**Commits:**
- a6a9aa4 (test 03-05 RED) — FOUND
- e1861e0 (feat 03-05 GREEN) — FOUND

**Tests:**
- ConfigParser 83/83 green
- AppFeatures 37/37 green
- VPNCore 32/32 green (1 pre-existing skipped)
- Localization 3/3 green

## Resume

Task 3 (UAT) — checkpoint:human-verify ожидает выполнения 16 device subtests на iPhone и macOS (см. PLAN.md Task 3 «how-to-verify»). При успешном UAT → user пишет `approved` → Phase 3 закрывается.

После UAT approval:
- Обновить `wiki/server-management.md` (новая страница) с D-01..D-14 + implementation summary.
- Перенести Phase 3 в `Validated` секцию `.planning/PROJECT.md`.
- Phase 3 goal полностью покрыт (см. «Plan Goal Coverage» выше).
