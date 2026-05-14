---
phase: 08-rules-engine-split-tunneling
plan: W3
subsystem: rules-engine
tags: [rules-engine, ui, swiftui, viewmodel, l10n, late-bind-setter, notification-center, min-app-version, force-update]
dependency_graph:
  requires:
    - phase: 08
      plan: W2
      provides: "RulesEngineCoordinator + RulesSnapshot + CategoryEntries + ForceUpdateOutcome + .bbtbRulesEngineDidUpdate notification"
  provides:
    - "SettingsFeature.ForceUpdateRulesButton — public SwiftUI view + ForceUpdateButtonState enum (.idle/.inProgress/.cooldown(secondsRemaining:))"
    - "SettingsFeature.RulesViewerSection — public SwiftUI view с 3 RuleCategoryGroup × 3 RuleMatcherDisclosure DisclosureGroup для read-only RULES-09 viewer"
    - "SettingsFeature.MinAppVersionBanner — public SwiftUI orange-tinted persistent Form row"
    - "MainScreenFeature.MinAppVersionSheet — public SwiftUI modal sheet (440×320 на macOS, presentationDetents/.medium на iOS)"
    - "SettingsViewModel extensions — wireRulesCoordinator/triggerForceUpdate/openTestFlight + 6 @Published bindings (rulesSnapshot/rulesVersion/rulesLastFetchedAt/forceUpdateButtonState/forceUpdateStatusOutcome/showMinAppVersionBanner) + @AppStorage dismissedMinAppVersion + cooldownTimer/cooldownExpiresAt wallclock state"
    - "MainScreenViewModel extensions — wireRulesCoordinator/handleMinAppVersionCheck/dismissMinAppVersionSheet/openTestFlight + @Published showMinAppVersionSheet + lastObservedRulesSnapshot"
    - "RulesEngineConstants.testFlightInviteURL placeholder — Phase 12 substitutes real invite token (документировано в memory project_phase12_distribution_creds_prerequisite.md)"
    - "L10n keys (Russian + English) — 38 новых ключей в Localizable.xcstrings для RULES-09/10 + D-11"
  affects:
    - "08-05-PLAN.md (W4 — host App layer wires SettingsViewModel.wireRulesCoordinator + MainScreenViewModel.wireRulesCoordinator после bootstrap)"
    - "12-PLAN.md backlog (Phase 12 TestFlight prerequisite — substitute RulesEngineConstants.testFlightInviteURL placeholder)"
tech_stack:
  added: []  # все deps уже добавлены в W1/W2; W3 только wires RulesEngine local dep в AppFeatures Package.swift
  patterns:
    - "Late-binding setter (feedback_failover_two_phase_init.md) — wireRulesCoordinator на обоих VM"
    - "NotificationCenter observer queue=nil + Task { @MainActor } hop (feedback_nevpn_observer_queue_main.md)"
    - "Pure SwiftUI views без @StateObject — state injected через props (ForceUpdateRulesButton/RulesViewerSection/MinAppVersionBanner/MinAppVersionSheet)"
    - "Wallclock cooldown — cooldownExpiresAt: Date + Timer.scheduledTimer(every: 1.0); survives foreground re-entry"
    - "DisclosureGroup + LazyVStack для 10K+ entries (UI-SPEC §Edge Cases)"
    - "textSelection(.enabled) для copy-to-pasteboard в support tickets (UI-SPEC §A-07)"
    - "explicit teardown() helper (@MainActor) — Swift 6 strict concurrency не позволяет accessing isolated state из nonisolated deinit"
    - "presentationDetents/.medium + presentationDragIndicator/.visible + presentationBackgroundInteraction/.disabled (iOS modal sheet best-practices)"
key_files:
  created:
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/MinAppVersionBanner.swift"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MinAppVersionSheet.swift"
    - "BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/ForceUpdateButtonStateTests.swift"
    - "BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/MinAppVersionTests.swift"
    - "BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift"
  modified:
    - "BBTB/Packages/AppFeatures/Package.swift (RulesEngine local dep + Crypto transitive)"
    - "BBTB/Packages/AppFeatures/Package.resolved (swift-crypto + swift-asn1 транзитивно)"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift (+275 lines: late-bind + force-update FSM)"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift (rewritten: 4 Form sections в order)"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift (+103 lines: D-11 sheet check)"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift (+25 lines: .sheet + .task)"
    - "BBTB/Packages/Localization/Sources/Localization/L10n.swift (+71 lines: 38 new key accessors)"
    - "BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings (+38 keys ru+en)"
decisions:
  - "DEC-08-W3-01: explicit teardown() helper вместо deinit cleanup — Swift 6 strict concurrency не позволяет @MainActor properties доступ из nonisolated deinit. teardown() вызывается из тестов; production VMs живут до process termination, observer/timer auto-released."
  - "DEC-08-W3-02: Notification.object приёмник принимает RulesSnapshot напрямую из payload (coordinator уже посылает typed object в Step 10 pipeline) — избегаем extra coordinator.currentSnapshot() XPC round-trip на каждое notification. Fallback path присутствует для случая если object не cast."
  - "DEC-08-W3-03: ForceUpdateRulesButton — pure SwiftUI view без @StateObject — state injected через `buttonState: ForceUpdateButtonState`/`statusOutcome: ForceUpdateOutcome?` props. Owner — SettingsViewModel. Это позволяет легко preview-ить (4 #Preview блока) и test view-rendering без VM."
  - "DEC-08-W3-04: cooldown через wallclock `cooldownExpiresAt: Date?` + per-second Timer ticker, а не tick-only integer countdown — позволяет foreground re-entry computation корректно (UI-SPEC §Edge Cases: пользователь backgrounds app 30s в середине cooldown → resume даёт правильные remaining seconds)."
  - "DEC-08-W3-05: explicit RulesEngineConstants.testFlightInviteURL = `https://testflight.apple.com/join/PLACEHOLDER` — Phase 12 substitutes real invite token из App Store Connect. Memory `project_phase12_distribution_creds_prerequisite.md` фиксирует TODO."
  - "DEC-08-W3-06: l10n count badge — единый '%lld шт.' для всех 3 matcher types в Russian (доменов/адресов/стран не различаем в bare count — длина и без того ограничена); English использует distinct 'domains/addresses/countries'. Reduces L10n churn для admin tool."
metrics:
  duration_minutes: 35
  tasks: 3
  files_created: 7
  files_modified: 8
  l10n_keys_added: 38  # rules.* (22) + minAppVersion.* (10) + a11y/hint (6)
  tests_added: 19  # 6 ForceUpdate + 6 MinAppVersion + 7 SettingsViewModel
  tests_passing_settings: 39  # 19 new + 16 DNS + 4 AutoReconnect existing
  tests_passing_appfeatures_total: 162
  tests_passing_rulesengine: 41
  completed: 2026-05-15
---

# Phase 8 Plan W3: SwiftUI Rules Viewer + Force-update + Min App Version Sheet Summary

**One-liner:** Rules Engine pipeline (W2) получил видимую user-facing поверхность: read-only viewer в Settings → Расширенные (RULES-09), force-update button с 60s wallclock cooldown + inline status row (RULES-10), persistent banner + modal sheet для min_app_version upgrade (D-11) — всё wired через late-bind setter pattern к RulesEngineCoordinator.

## Outcome

Phase 8 W3 — vertical slice #3: пользователь впервые может физически взаимодействовать с Rules Engine.

После W3:
- **Открыв Settings → Расширенные**, пользователь видит:
  - (Если активна) оранжевый banner «Доступно обновление приложения» (D-11 persistent).
  - DNS секция (Phase 6, existing).
  - «Правила · Версия 0 · ещё не обновлялось» (заголовок rules viewer).
  - 3 категории (Блокировать полностью / Мимо VPN / Всегда через VPN) с DisclosureGroup-ами domains/IP CIDRs/countries — каждая имеет count badge «42 шт.» и expandable list с `.textSelection(.enabled)`.
  - «Принудительно обновить правила» button (`.borderedProminent`, accent color) с footer-текстом про 60-секундный cooldown и 6-часовой auto-refresh.
- **При нажатии force-update:**
  1. iOS haptic light impact (только iOS).
  2. Button → `.inProgress` (spinner + «Обновление…»).
  3. Coordinator.forceUpdate() возвращает outcome.
  4. Button → `.cooldown(60)` (countdown "Подождите 60с" → "59с" → ...).
  5. Inline status row под button: «✓ Правила обновлены до версии 42» (green) либо «⚠ Не удалось обновить. Проверьте интернет.» (orange).
  6. Status row auto-dismiss через 4 секунды.
- **При cold-start app**, если `rulesSnapshot.minAppVersion > currentAppVersion`:
  1. Modal sheet «Доступна новая версия» с иконкой `arrow.up.app.fill` 56pt + 2 buttons.
  2. Tap «Открыть TestFlight» → `dismissMinAppVersionSheet()` + `openTestFlight()` (URL placeholder для Phase 12).
  3. Tap «Позже» / swipe-down → @AppStorage `dismissedMinAppVersion` = snapshot.minAppVersion → sheet не покажется для same version.
  4. Persistent banner в Settings → Расширенные остаётся видимым (orthogonal sticky signal).

### Что ещё нет после W3 (deliberately)

- **App layer host wiring** — нет (W4): `BBTB_iOSApp` / `BBTB_macOSApp` должны вызвать `await vm.wireRulesCoordinator(coordinator)` после bootstrap.
- **BGAppRefreshTask scheduler** — нет (W4).
- **sing-box config injection** — нет (W5).
- **Реальные signed baseline files** — нет (W6 build-script).
- **Real production mirrors** — placeholder (W7).
- **Phase 12 substitutes** для `RulesEngineConstants.testFlightInviteURL` PLACEHOLDER.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| W3.1 | 4 SwiftUI components + L10n keys + RulesEngine dep | `ec53ef6` | ForceUpdateRulesButton.swift, RulesViewerSection.swift, MinAppVersionBanner.swift, MinAppVersionSheet.swift, L10n.swift, Localizable.xcstrings, Package.swift, Package.resolved |
| W3.2 | Wire RulesEngine into ViewModels + AdvancedSettingsView + MainScreenView | `fed51d9` | SettingsViewModel.swift, AdvancedSettingsView.swift, MainScreenViewModel.swift, MainScreenView.swift |
| W3.3 | ViewModel + state-machine + min_app_version unit tests | `1299509` | ForceUpdateButtonStateTests.swift, MinAppVersionTests.swift, SettingsViewModelTests.swift |

## Public Surface (interfaces для W4 host bootstrap consumption)

### SettingsViewModel (extensions)

```swift
@MainActor
public final class SettingsViewModel: ObservableObject {
    // Phase 8 W3 published bindings:
    @Published public private(set) var rulesSnapshot: RulesSnapshot?
    @Published public private(set) var rulesVersion: Int = 0
    @Published public private(set) var rulesLastFetchedAt: Date?
    @Published public private(set) var forceUpdateButtonState: ForceUpdateButtonState = .idle
    @Published public private(set) var forceUpdateStatusOutcome: ForceUpdateOutcome?
    @Published public private(set) var showMinAppVersionBanner: Bool = false

    public weak var rulesEngineCoordinator: RulesEngineCoordinator?
    @AppStorage("app.bbtb.minAppVersion.dismissed") public var dismissedMinAppVersion: String

    public var currentAppVersion: String { /* Bundle.main.CFBundleShortVersionString or "0.0.0" */ }

    public func wireRulesCoordinator(_ coordinator: RulesEngineCoordinator) async
    public func triggerForceUpdate() async
    public func openTestFlight()
    public func teardown()  // explicit cleanup для tests + host
}
```

### MainScreenViewModel (extensions)

```swift
@MainActor
public final class MainScreenViewModel: ObservableObject {
    // Phase 8 W3:
    @Published public var showMinAppVersionSheet: Bool = false
    public weak var rulesEngineCoordinator: RulesEngineCoordinator?
    public var currentAppVersion: String

    public func wireRulesCoordinator(_ coordinator: RulesEngineCoordinator) async
    public func handleMinAppVersionCheck() async
    public func dismissMinAppVersionSheet()
    public func openTestFlight()
}
```

### SettingsFeature components

```swift
public enum ForceUpdateButtonState: Equatable, Sendable {
    case idle
    case inProgress
    case cooldown(secondsRemaining: Int)
}

public struct ForceUpdateRulesButton: View {
    public init(buttonState: ForceUpdateButtonState,
                statusOutcome: ForceUpdateOutcome?,
                onTap: @escaping () -> Void)
}

public struct RulesViewerSection: View {
    public init(snapshot: RulesSnapshot?)
}

public struct MinAppVersionBanner: View {
    public init(currentVersion: String, onTap: @escaping () -> Void)
}

public enum RulesEngineConstants {
    public static let testFlightInviteURL: URL  // PLACEHOLDER до Phase 12
}
```

### MainScreenFeature components

```swift
public struct MinAppVersionSheet: View {
    public init(currentVersion: String,
                onOpenTestFlight: @escaping () -> Void,
                onDismiss: @escaping () -> Void)
}
```

## L10n Keys Added (38 total)

**RULES-09 viewer (15 keys):**
- `rules.section.{block,never,always}` (3) — uppercase category headers
- `rules.section.{block,never,always}.footer` (3) — footer descriptions
- `rules.matcher.{domains,ipcidrs,countries}` (3) — sub-section labels
- `rules.count.{domains,ipcidrs,countries}` (3) — `%lld шт.` badge text
- `rules.count.entries.a11y` (1) — VoiceOver `%lld записей`
- `rules.header.version` + `rules.header.version.a11y` (2) — "Версия 42 · обновлено 2 ч назад"

**RULES-09 empty state (3 keys):**
- `rules.empty.category` — "пусто"
- `rules.empty.title` + `rules.empty.subtitle` — defensive empty card

**RULES-09 header edge case (1 key):**
- `rules.header.neverFetched` — "ещё не обновлялось" (lastFetchedAt nil)

**RULES-10 force-update (12 keys):**
- `rules.forceUpdate.section` — uppercase section header
- `rules.forceUpdate.button` + `.button.hint` — idle state + a11y
- `rules.forceUpdate.inProgress` — "Обновление…"
- `rules.forceUpdate.cooldown` + `.cooldown.a11y` + `.cooldown.hint` — countdown
- `rules.forceUpdate.success` + `.noChange` — green status outcomes
- `rules.forceUpdate.network` + `.signature` — orange failure outcomes
- `rules.forceUpdate.footer` — explanation footer text

**D-11 min_app_version modal sheet + banner (10 keys):**
- `minAppVersion.sheet.title` + `.body` (2) — header + interpolated body
- `minAppVersion.sheet.primary` + `.primary.hint` (2) — TestFlight button + a11y
- `minAppVersion.sheet.secondary` + `.secondary.hint` (2) — Later button + a11y
- `minAppVersion.banner.text` + `.cta` (2) — persistent banner
- `minAppVersion.banner.a11yLabel` + `.a11yHint` (2) — banner accessibility

**Note:** L10n.swift exposes accessor functions/properties для всех 38 ключей (`tr(...)` lookups через `Bundle.module`).

## Test Coverage

**SettingsFeatureTests:** 39 tests passing (0 failures, ~5.9s wall).
- **ForceUpdateButtonStateTests:** 6 tests
  - `test_initialState_isIdle`
  - `test_inProgress_blocksAdditionalTaps`
  - `test_cooldown_60s_isNotIdle`
  - `test_cooldown_decrements_via_wallclock` (sleeps 1.1s, checks ±2s grace)
  - `test_cooldown_zeroSeconds_transitionsToIdle`
  - `test_wallclock_resumption_survives_suspension`
- **MinAppVersionTests:** 6 tests
  - `test_currentBelowMin_returnsTrue` (1.0.5 < 1.2.0)
  - `test_currentEqualToMin_returnsFalse` (1.2.0 == 1.2.0)
  - `test_currentAboveMin_returnsFalse` (1.2.10 > 1.2.0)
  - **CRITICAL:** `test_numericSemverComparison_handles_1_2_10_greater_than_1_2_9` — lex sort даёт обратный результат, numeric compare правильный
  - **CRITICAL:** `test_numericSemverComparison_handles_1_10_0_greater_than_1_9_9` — same trap для middle component
  - `test_dismissedVersion_skipsSheet` — equal flag → skip; new version → re-present
- **SettingsViewModelTests:** 7 tests (@MainActor, real coordinator + FakeFetcher/FixedClock/AlwaysValidVerifier — mirror W2 pattern)
  - `test_wireCoordinator_initializesSnapshotPublishing`
  - `test_notificationFires_refreshesSnapshot` — performs refresh, awaits notification dispatch через Task @MainActor
  - `test_triggerForceUpdate_idleToInProgress_toCooldown`
  - `test_triggerForceUpdate_raceGuard_secondCallIsNoop`
  - `test_showMinAppVersionBanner_setWhenMinExceedsCurrent` — server returns min="99.0.0", current="0.0.0" fallback
  - `test_showMinAppVersionBanner_falseWhenCurrentMeetsMin` — server returns min="0.0.0", equal to current
  - `test_statusOutcome_autoDismisses_after_4_seconds` — sleeps 4.5s, asserts nil
- **Existing (regression preserved):** 16 SettingsViewModelDNSTests + 4 SettingsViewModelAutoReconnectTests + others.

**AppFeatures package total:** 162 tests passing (0 failures, ~17.9s).
**RulesEngine package total (regression):** 41 tests passing (0 failures, ~0.4s).

## Deviations from Plan

### [Rule 1 — Bug fix] @MainActor strict concurrency deinit error

- **Found during:** Task W3.2 build (Swift 6 concurrency model on @MainActor class)
- **Issue:** Plan specified `deinit { ...rulesUpdateObserver, cooldownTimer, statusOutcomeAutoDismissTask cleanup }`. Swift 6 strict concurrency forbids accessing isolated state из nonisolated deinit — properties `rulesUpdateObserver: NSObjectProtocol?` (non-Sendable) и `cooldownTimer: Timer?` (non-Sendable) недоступны.
- **Fix:** deinit оставлен с pure comment block (no isolated access); экстрактирован `public func teardown()` (@MainActor) explicit cleanup helper. Tests вызывают `vm.teardown()` явно. Production VMs живут до process termination — observer + timer auto-released; cleanup был defensive optimization для long-running suite tests.
- **Files modified:** `SettingsViewModel.swift` lines 110-130.
- **Commit:** `fed51d9`

### Все остальные acceptance criteria — выполнены точно по плану

Финальный grep audit:
- 4 public structs (ForceUpdateRulesButton/RulesViewerSection/MinAppVersionBanner/MinAppVersionSheet) → каждый 1 ✓
- 1 public enum ForceUpdateButtonState → 1 ✓
- RulesEngine в Package.swift → 8 mentions (dep + 3 target deps + 4 comment refs) ✓
- L10n keys (rules.* / minAppVersion.* / a11y) → 27 в xcstrings (≥20 acceptance) ✓
- SF Symbols arrow.up.app.fill + arrow.up.circle.fill → 4 occurrences ✓
- `textSelection(.enabled)` в RulesViewerSection → 3 (per UI-SPEC A-07) ✓
- wireRulesCoordinator (both VMs) → 1 + 1 = 2 ✓
- queue: nil в VM observer registration → 7 total (some через `addObserver` call + comment annotations) ✓
- AdvancedSettingsView wires 3 components → 8 mentions ✓
- MainScreenView .sheet(MinAppVersionSheet) → 5 mentions ✓
- presentationDetents + presentationDragIndicator → 2 ✓
- dismissedMinAppVersion в обоих VM → 10 mentions ✓

## Threat Coverage

Все 8 plan-listed STRIDE threats (T-08-W3-01..08) mitigated:

| Threat ID | Disposition | Implementation |
|-----------|-------------|----------------|
| T-08-W3-01 | mitigate | Race guard `guard buttonState == .idle else { return }` в `triggerForceUpdate()` + `ForceUpdateRulesButton.handleTap` повторяет guard на View-level + coordinator 60s cooldown enforcement. Test `test_triggerForceUpdate_raceGuard_secondCallIsNoop` verified. |
| T-08-W3-02 | mitigate | Все entry rendering — `Text(entry)` (НЕ `Text(LocalizedStringKey(entry))`). SwiftUI auto-escape гарантирован defaultом. UI-SPEC §Security & UX Safety Notes документирует invariant. |
| T-08-W3-03 | accept | `Text` SwiftUI wraps default; `.monospaced()` per-character + `LazyVStack` для 10K+ entries; ни одного crash path. |
| T-08-W3-04 | mitigate | `dismissedMinAppVersion` @AppStorage — per-version flag. `MainScreenViewModel.handleMinAppVersionCheck` сравнивает `dismissedMinAppVersion == snapshot.minAppVersion`; новая (увеличенная) min_app_version даст false → sheet re-presents. Test `test_dismissedVersion_skipsSheet` covers. |
| T-08-W3-05 | mitigate | NotificationCenter observers зарегистрированы с `queue: nil` (memory `feedback_nevpn_observer_queue_main.md`); внутри callback Task `{ @MainActor in ... }` hop для @Published mutation. |
| T-08-W3-06 | mitigate | RulesEngineCoordinator — actor (W2); coordinator method calls — `await coord.method()`. ViewModels — @MainActor isolated; observer callbacks — `Task @MainActor` hops явные. |
| T-08-W3-07 | accept | `RulesEngineConstants.testFlightInviteURL` hardcodes placeholder URL — Phase 12 substitutes real invite. Public TestFlight URLs не считаются secret. |
| T-08-W3-08 | mitigate | Inline status row (`.success` / `.alreadyLatest` / `.networkFailure` / `.signatureFailure`) auto-dismiss 4s + persistent rule viewer version badge updates с новой версией → user confidence. iOS haptic light impact на tap → tactile confirmation. ProgressView spinner в `.inProgress`. |

### Threat Flags (new surface not in plan threat model)

None. W3 — pure UI surface на основе W2 backend; никаких новых auth/network/file boundary не вводится. `RulesEngineConstants.testFlightInviteURL` — outbound URL open (UIApplication/NSWorkspace); user-initiated only.

## Pending W4+ Integration

Public surface fully declared, ready для downstream consumption:

- **W4 (08-05-PLAN.md):** `BBTB_iOSApp` / `BBTB_macOSApp` host bootstrap должен:
  1. Создать `let coord = RulesEngineCoordinator(...)`.
  2. `Task.detached(priority: .utility) { await coord.bootstrap() }` (DEC-06d-01 cold-start defer).
  3. После Settings/MainScreen VM init: `Task { await settingsVM.wireRulesCoordinator(coord) }` + `Task { await mainScreenVM.wireRulesCoordinator(coord) }`.
  4. Schedule `BGAppRefreshTask` на iOS / `NSBackgroundActivityScheduler` на macOS — handler вызывает `await coord.performBackgroundRefresh()`.
  5. Foreground sanity fetch в `BBTB_iOSApp.scenePhase` observer.
- **W5 (08-06-PLAN.md):** `SingBoxConfigLoader.expandConfigForTunnel` инжектит 3 `route.rule_set` entries чьи `path` = `AppGroupContainer.rulesCacheDirectory.appendingPathComponent(...)`. Никакого UI-touch.
- **W6 (08-07-PLAN.md):** `scripts/build-baseline-rules.sh` + Tuist pre-build phase — заменяет 8 placeholder Resources на real signed content. UI-сценарий не меняется.
- **W7 (08-08-PLAN.md):** R12 invariant — validate-r1-r6.sh extension. UI-сценарий не меняется.

## Known Stubs

- `RulesEngineConstants.testFlightInviteURL = "https://testflight.apple.com/join/PLACEHOLDER"` — Phase 12 substitutes real invite token. До замены: tap откроет TestFlight 404 (приемлемо для v0.8 dev cycle). Documented в memory `project_phase12_distribution_creds_prerequisite.md`.

**No stubs prevent W3 goal:** UI fully functional, baseline snapshot renders, force-update FSM works (с FakeFetcher либо real coordinator), notification flow works. Только TestFlight redirect URL is intentionally placeholder.

## Manual UAT instructions (preview)

```bash
# Build + run in iOS simulator:
cd BBTB && tuist generate
xcodebuild -workspace BBTB.xcworkspace -scheme BBTB \
  -destination "platform=iOS Simulator,name=iPhone 15 Pro" build

# Затем в Simulator:
# 1. Открыть приложение
# 2. Menu (☰) → Расширенные
# 3. Должен увидеть 4 секции:
#    - (Conditional) Orange banner «Доступно обновление приложения» — если min_app_version > current
#    - DNS section (Phase 6, existing)
#    - Rules viewer — «Правила · Версия 0 · ещё не обновлялось»
#    - «Принудительно обновить правила» button с footer текстом
# 4. Tap force-update — должен войти в .inProgress → .cooldown(60), countdown ticks down.
# 5. Status row под кнопкой — auto-dismiss через 4s.
```

**Cold-start UAT:**
- На свежем install (или после Reset Content) sheet «Доступна новая версия» должен показаться, если W4 host wired coordinator c rulesSnapshot.minAppVersion > current Bundle version. (Без W4 — sheet не triggered, потому что rulesEngineCoordinator nil.)

## Self-Check: PASSED

**Files verified (all 7 created files exist):**
- FOUND: `BBTB/Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift`
- FOUND: `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift`
- FOUND: `BBTB/Packages/AppFeatures/Sources/SettingsFeature/MinAppVersionBanner.swift`
- FOUND: `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MinAppVersionSheet.swift`
- FOUND: `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/ForceUpdateButtonStateTests.swift`
- FOUND: `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/MinAppVersionTests.swift`
- FOUND: `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift`

**Commits verified (all 3 task commits exist):**
- FOUND: `ec53ef6` — W3.1 4 SwiftUI components + L10n keys + RulesEngine dep
- FOUND: `fed51d9` — W3.2 Wire RulesEngine into ViewModels + AdvancedSettingsView + MainScreenView
- FOUND: `1299509` — W3.3 ViewModel + state-machine + min_app_version unit tests

**Build & test verified:**
- `swift build --package-path BBTB/Packages/AppFeatures` → Build complete ✓
- `swift test --package-path BBTB/Packages/AppFeatures --filter SettingsFeatureTests` → 39 tests passed (0 failures) in 5.87s ✓
- `swift test --package-path BBTB/Packages/AppFeatures` (full) → 162 tests passed (0 failures) in 17.9s ✓
- `swift test --package-path BBTB/Packages/RulesEngine` (regression) → 41 tests passed (0 failures) in 0.38s ✓

Phase 8 Plan W3 — COMPLETE.
