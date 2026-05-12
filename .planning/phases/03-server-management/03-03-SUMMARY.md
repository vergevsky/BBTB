---
phase: 03-server-management
plan: 03
subsystem: AppFeatures/ServerListFeature
tags: [server-list, ui, sheet, swiftui, l10n, coordinator]
requires:
  - 03-01-SUMMARY.md  # @Model Subscription + ServerConfig schema
  - 03-02-SUMMARY.md  # ServerProbeService actor + ProbeAggregate
provides:
  - ServerListFeature library (9 swift файлов)
  - ServerSelectionCoordinating protocol (one-way MainScreenFeature → ServerListFeature)
  - ServerConfig.countryFlag + ServerConfig.isUnreachable computed properties
  - MainScreenViewModel.{isPresentingServerList, selectedServerID, serverListViewModel, presentServerList()}
  - 22 L10n keys (RU + EN) per UI-SPEC §9.5
affects:
  - MainScreenFeature/MainScreenView (.sheet wiring)
  - MainScreenFeature/MainScreenViewModel (coordinator conformance + DI extension)
  - MainScreenFeature/ServerLineView (tap-enabled + chevron)
tech-stack:
  added:
    - SwiftUI .presentationDetents / .presentationDragIndicator (iOS 16+ / macOS 13+)
    - .symbolEffect(.bounce, value:) (iOS 17+ / macOS 14+) — graceful fallback
    - UIImpactFeedbackGenerator (iOS only — wrapped в #if os(iOS))
  patterns:
    - "@MainActor ObservableObject" — ServerListViewModel mirrors MainScreenViewModel pattern
    - "AsyncStream for-await consumer" — pingAllServers consume Plan 02 probeService
    - "Coordinator protocol" — избежали reverse module dep MainScreenFeature ↔ ServerListFeature
    - "Closure-init View" — AutoCell / SubscriptionHeader / ServerRow / ServerListSheet
    - "Pure static func for tests" — `groupSections(subscriptions:servers:)` nonisolated
key-files:
  created:
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListState.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/PingState.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerSelectionCoordinating.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/LatencyBadge.swift
    - BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/SectionGroupingTests.swift
    - BBTB/Packages/VPNCore/Tests/VPNCoreTests/CountryFlagTests.swift
  modified:
    - BBTB/Packages/AppFeatures/Package.swift  # +ServerListFeature target + testTarget
    - BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift  # +countryFlag extension
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift  # +DI init + coordinator conformance
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift  # +.sheet binding
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ServerLineView.swift  # tap-enabled
    - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings  # +22 keys
    - BBTB/Packages/Localization/Sources/Localization/L10n.swift  # +22 accessors
decisions:
  - "ServerSelectionCoordinating @MainActor protocol — избегаем reverse module dependency (ServerListFeature не должен импортировать MainScreenFeature). MainScreenViewModel conforms через extension."
  - "MainScreenViewModel получает второй init с modelContainer/probeService параметрами; convenience init без них сохраняет Phase 2 backward-compat (callsites без DI компилируются)."
  - "groupSections — `public nonisolated static func` для прямого вызова из XCTestCase без актёрного awaitable boundary."
  - "ServerConfig.countryFlag валидирует regex `^[A-Za-z]{2}$` (T-03-13 mitigation) — malicious cc=\"12\"/\"!@\" → 🌐 fallback."
metrics:
  duration_minutes: 8
  completed_date: "2026-05-12"
  tasks_completed: 2
  files_created: 11
  files_modified: 7
  l10n_keys_added: 22
---

# Phase 3 Plan 03: ServerListFeature UI (sheet, AutoCell, SubscriptionHeader, ServerRow, LatencyBadge) Summary

**One-liner:** Server-list sheet с sticky AutoCell + Section-grouping по подпискам + Manual section + progressive latency badges (через Plan 02 probeService AsyncStream) + ServerSelectionCoordinating protocol для one-way MainScreenFeature → ServerListFeature wiring.

## What was built

Третий вертикальный слайс Phase 3: тап на ServerLineView главного экрана открывает `.sheet` с full-height detent, прокачивающий sticky-top «Авто (рекомендуется)» ячейку + секции для каждой Subscription + секцию «ДОБАВЛЕНЫ ВРУЧНУЮ» для orphan-серверов. Каждая строка показывает emoji-флаг (regex-валидируемый или 🌐 fallback) + имя + LatencyBadge (state-driven: «не поддерживается» pill / «недоступен» red / spinner / `N ms` colored по UI-SPEC §2.6 tiers). При onAppear sheet прокидывает supported серверы в `ServerProbeService.probeAll(...)` AsyncStream (Plan 02) и progressively обновляет `pingStates`. Tap по серверу или Auto-ячейке записывает `selectedServerID` в MainScreenViewModel через `ServerSelectionCoordinating` protocol и dismiss'ит sheet.

## Tasks

### Task 1 — RED tests + package skeleton + value types + ServerConfig.countryFlag

- **Commits:** `9921694` (RED), `140fbfc` (GREEN)
- **Files:**
  - Создано: `CountryFlagTests.swift` (5 cases), `SectionGroupingTests.swift` (5 cases), `ServerListState.swift`, `PingState.swift`, `ServerSelectionCoordinating.swift`, `ServerListViewModel.swift` (skeleton + groupSections + onAppear/loadFromStore/pingAllServers stubs).
  - Изменено: `AppFeatures/Package.swift` (новый library + testTarget), `ServerConfig.swift` (`countryFlag` + `isUnreachable` computed).
- **Status:** GREEN. Все 5 CountryFlagTests pass; все 5 SectionGroupingTests pass.

### Task 2 — UI components + ServerListViewModel implementations + MainScreen wiring + 22 L10n keys

- **Commit:** `295f9cf`
- **Files:**
  - Создано: `AutoCell.swift`, `SubscriptionHeader.swift`, `ServerRow.swift`, `LatencyBadge.swift`, `ServerListSheet.swift`.
  - Изменено: `ServerLineView.swift` (tap-enabled + chevron), `MainScreenViewModel.swift` (DI init + ServerSelectionCoordinating extension + presentServerList), `MainScreenView.swift` (`.sheet` binding), `L10n.swift` + `Localizable.xcstrings` (22 ключа), `ServerSelectionCoordinating.swift` (`@MainActor` annotation для conformance isolation).
- **Status:** GREEN. 15/15 AppFeatures tests pass; 32/32 VPNCore tests pass.

## Verification

### Per-task automated

| Step | Command | Result |
|------|---------|--------|
| Task 1 RED | `swift test --package-path BBTB/Packages/VPNCore --filter CountryFlagTests` | RED (countryFlag missing) → confirmed |
| Task 1 GREEN — CountryFlagTests | same | **5/5 PASS** |
| Task 1 GREEN — SectionGroupingTests | `swift test --package-path BBTB/Packages/AppFeatures --filter SectionGroupingTests` | **5/5 PASS** |
| Task 1 build | `swift build --package-path BBTB/Packages/AppFeatures` | **Build complete** |
| Task 2 build | same | **Build complete** |
| Task 2 — AppFeatures | `swift test --package-path BBTB/Packages/AppFeatures` | **15/15 PASS** (no Phase 2 regressions) |
| Task 2 — VPNCore | `swift test --package-path BBTB/Packages/VPNCore` | **32/32 PASS** (1 skipped — pre-existing) |

### Plan-level acceptance

| Criterion | Status |
|-----------|--------|
| 9 ServerListFeature .swift файлов | ✓ (4 Task 1 + 5 Task 2) |
| `.presentationDetents([.large])` в ServerListSheet | ✓ |
| `.refreshable` hook в ServerListSheet (stub body) | ✓ (3 matches — body + .refreshable + comment) |
| ScrollView + LazyVStack + Section (НЕ List) | ✓ (List count = 0) |
| ServerListViewModel.onAppear / loadFromStore / pingAllServers заполнены | ✓ |
| MainScreenViewModel conforms ServerSelectionCoordinating | ✓ |
| ServerLineView init(name:onTap:) | ✓ |
| MainScreenView .sheet(isPresented: $vm.isPresentingServerList) | ✓ |
| 22 L10n keys в xcstrings + L10n.swift | ✓ |
| Phase 2 MainScreenFeature tests без regressions | ✓ |
| Phase 1/2 VPNCore tests без regressions | ✓ |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] ConformanceIsolation на ServerSelectionCoordinating**
- **Found during:** Task 2 step E (MainScreenViewModel extension conformance).
- **Issue:** Swift 6 strict concurrency: `extension MainScreenViewModel: ServerSelectionCoordinating` падал с error `conformance of 'MainScreenViewModel' to protocol 'ServerSelectionCoordinating' crosses into main actor-isolated code and can cause data races`. Protocol был nonisolated, conformer — `@MainActor`.
- **Fix:** Добавлен `@MainActor` на protocol declaration. Все members протокола обновляют UI state (`selectedServerID`, `isPresentingServerList`) — должны выполняться на main actor; conformers уже `@MainActor`. Annotation удовлетворяет ConformanceIsolation cleanly.
- **Files modified:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerSelectionCoordinating.swift`.
- **Commit:** Included в `295f9cf`.

**2. [Rule 3 — Blocking] groupSections actor-isolated при вызове из XCTest**
- **Found during:** Task 1 step G (run SectionGroupingTests).
- **Issue:** `ServerListViewModel.groupSections(...)` — `static func` внутри `@MainActor` class — implicit `@MainActor` isolation. XCTestCase методы — nonisolated; компилятор отверг synchronous call.
- **Fix:** Добавлен `public nonisolated static func groupSections(...)` — pure function, не касается `@Published` state, безопасно вызывается из любого контекста.
- **Files modified:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift`.
- **Commit:** Included в `140fbfc`.

**3. [Rule 3 — Blocking] libbox.xcframework отсутствует в worktree**
- **Found during:** Pre-Task 1 baseline build.
- **Issue:** Worktree filesystem не содержит `BBTB/Vendored/libbox.xcframework` (gitignored binary), build падал с `local binary target 'Libbox' does not contain a binary artifact`.
- **Fix:** Создан symlink `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`. Symlink НЕ закоммичен (gitignored через `Vendored/libbox.xcframework/` rule в BBTB/.gitignore).
- **Files modified:** none committed (symlink locally only).
- **Commit:** N/A — environment fix.

### Architectural decisions

- **ServerSelectionCoordinating one-way protocol** — Plan описывает rationale: ServerListFeature не должен импортировать MainScreenFeature (избегаем reverse module dep). Реализовано как `weak var coordinator: ServerSelectionCoordinating?` на ServerListViewModel + extension conformance на MainScreenViewModel. Retain cycle исключён `weak`.
- **MainScreenViewModel DI split** — `convenience init(importer:tunnel:)` для Phase 2 backward-compat callsites (без DI) → `serverListViewModel = nil`. Designated init принимает `modelContainer: ModelContainer?` (optional, потому что Phase 1/2 callsites могут не иметь container hookup — например, ConfigImporter уже init'ится с container, но VM этого не получает напрямую). При наличии container — создаётся ServerListViewModel + linkуется coordinator backlink.
- **DS.Spacing/Typography mapping** — UI-SPEC §8.1 фиксирует «md=16» (нормализованная шкала), но текущий DesignSystem package использует Phase 2 значения (md=12, lg=16). Use DS tokens as-is — это сохраняет visual consistency с Phase 2 экранами. Phase 11 переопределит values при сохранении token names (forward-compat).

### Deferred to Plan 04 (per HARD constraints in PLAN)

| Stub в Plan 03 | Plan 04 заполнит |
|---|---|
| `ServerListSheet.refreshable { /* Plan 04 */ }` | `await viewModel.pullToRefresh()` — fetch+merge всех subscriptions + ping cycle (D-13) |
| `ServerRow onDelete: { /* Plan 04 */ }` | `viewModel.deleteServer(id:)` + reconcile tunnel pool |
| `ServerListViewModel.requestDeleteSubscription(_:)` | confirmationDialog + cascade delete + reconcile |
| `SubscriptionHeader` без `fetchError:` parameter | Plan 04 расширит signature |
| `MainScreenViewModel.applySelection(_:)` без reconnect-on-active-tunnel | **Plan 05** (не Plan 04) добавит reconnect через ConfigImporter.provisionTunnelProfile |

## Self-Check

### File existence (created)

```
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListState.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/PingState.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerSelectionCoordinating.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift
[FOUND]  BBTB/Packages/AppFeatures/Sources/ServerListFeature/LatencyBadge.swift
[FOUND]  BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/SectionGroupingTests.swift
[FOUND]  BBTB/Packages/VPNCore/Tests/VPNCoreTests/CountryFlagTests.swift
```

### Commits exist

```
[FOUND]  9921694  test(03-03): add failing tests for countryFlag derivation + section grouping
[FOUND]  140fbfc  feat(03-03/task1): ServerListFeature skeleton + countryFlag + groupSections (Task 1 GREEN)
[FOUND]  295f9cf  feat(03-03/task2): UI components + MainScreen wiring + 22 L10n keys (Task 2 GREEN)
```

## Self-Check: PASSED

## Known Stubs

| File | Stub | Reason | Resolution Plan |
|------|------|--------|-----------------|
| `ServerListSheet.swift` | `.refreshable { /* Plan 04 */ }` empty body | Plan 04 owns pull-to-refresh logic (D-13: 2-phase fetch+merge+ping) | Plan 04 fills `await viewModel.pullToRefresh()` |
| `ServerListSheet.swift` | `ServerRow.onDelete: { /* Plan 04 */ }` empty closure | Plan 04 owns deleteServer flow (reconcile tunnel pool) | Plan 04 fills `viewModel.deleteServer(id:)` |
| `MainScreenViewModel.applySelection(_:)` | `// Plan 05: reconnect-on-active-tunnel` comment | Plan 05 owns reconnect-on-selection-change (D-09) | Plan 05 fills ConfigImporter.provisionTunnelProfile + tunnel.disconnect/connect |

Все stubs документированы и не блокируют user-visible vision Plan 03 («видеть и выбирать сервер»). Не нарушают core goal — selection пишется в state, sheet работает.

## Phase 3 Plan 03 Threat Flags

Нет новых threat surface'ов помимо тех, что уже описаны в `<threat_model>` PLAN.md:

- T-03-12 (subscription.name RTL) — mitigated через Plan 01 sanitization, Plan 03 только consume'ит sanitized strings.
- T-03-13 (countryCode tampering) — mitigated через regex `^[A-Za-z]{2}$` в `countryFlag` + verified в CountryFlagTests `test_country_flag_invalid_chars_returns_globe`.
- T-03-14 (VoiceOver leak) — accepted UX trade-off, документировано в PLAN.
- T-03-15 (weak coordinator nil-deref) — nil-check на coordinator? в applySelection/dismiss wrappers; нет логирования через OSLog в Plan 03 (Plan 05 finalize).
- T-03-16 (macOS sheet collapse) — mitigated через `#if os(macOS) .frame(minWidth: 480, minHeight: 720)` в ServerListSheet.

## Forward links

- **Plan 04** (Wave 3): pull-to-refresh logic, fetch + merge всех subscriptions, deleteServer / deleteSubscription cascade, foreground silent refresh, SubscriptionHeader fetchError parameter.
- **Plan 05** (Wave 3): reconnect-on-active-tunnel при applySelection, persistence `selectedServerID` в @AppStorage, visual smoke test checkpoint:human-verify.
- **Plan 06+ (Phase 11)**: GeoIP DB для country flag fallback, signal-strength dot на ServerLineView, search bar, edit subscription name, undo toast.

---

*Phase: 03-server-management — Plan 03 (Wave 2)*
*Completed: 2026-05-12*
*Commits: 3 (RED + Task 1 GREEN + Task 2 GREEN)*
*Tests: 15/15 AppFeatures + 32/32 VPNCore green*
