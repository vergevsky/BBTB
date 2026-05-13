---
phase: 06c-on-demand-migration
plan: 03
type: execute
wave: 3
depends_on: ["06c-on-demand-migration:02"]
files_modified:
  - BBTB/Packages/AppFeatures/Package.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift
  - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift
  - BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift
autonomous: true
requirements: [NET-08, NET-09, NET-10, NET-11]
must_haves:
  truths:
    - "ReconnectClock + SystemReconnectClock extracted в новый файл `ReconnectClock.swift` (B-01) — survive deletion of ReconnectStateMachine.swift в Plan 04 Task 3c"
    - "InstantReconnectClock extracted в новый файл `TestClocks.swift` (internal не private) (B-02) — survive deletion of TunnelControllerStateTests.swift в Plan 04 Task 3c"
    - "SettingsFeature target deps в Package.swift включает MainScreenFeature (B-09) — explicit Package.swift edit, не «if needed»"
    - "Settings showcases новый раздел «Подключение» с переключателем «Автоматическое переподключение» (D-04, D-07)"
    - "Toggle persists через UserDefaults `app.bbtb.autoReconnectEnabled` с default ON (D-05)"
    - "Toggle change live-применяется к manager: ManagerSelector → OnDemandRulesBuilder.applyCurrentState → save → reload → post bbtbProvisionerDidSave (D-06 + W-04 closure + B-03 cross-plan + B-06 multi-manager)"
    - "applyAutoReconnectToManager is nonisolated — выполняется off-main (W-03 fix); вызывается через Task.detached из .onChange modifier"
    - "Toggle OFF при активном туннеле НЕ tear down туннель — Apple's default behavior, footer текст это коммуницирует (OQ-4 / Pitfall 4)"
    - "OnDemandMigrationTask запускается в App init и идемпотентен: применяет applyCurrentState ко всем нашим manager'ам (ManagerSelector); ставит флаг `app.bbtb.autoReconnectMigratedV6c` = true ТОЛЬКО на confirmed-success или confirmed-empty paths (B-05 transient failure safety); D-17b/c, Pitfall 1"
    - "TunnelWatchdog actor реагирует на NEVPNStatusDidChange ТОЛЬКО при: stable session ≥ 30s + status .disconnected + managerEnabled snapshot (cached manager.isEnabled per B-03) + userIntent true (D-08)"
    - "TunnelWatchdog при срабатывании вызывает SwiftDataFailoverProvider.nextServerAttempt + выполняет returned attempt closure (D-09)"
    - "TunnelWatchdog добавляет 3-секундный debounce после `.disconnected` чтобы Apple's on-demand успел сам reconnect (Pitfall 10) — failover отменяется если status вернулся в .connecting / .reasserting / .connected (W-05 расширенная отмена)"
    - "Wave 2 НЕ удаляет ReconnectStateMachine.swift, NetworkReachability.swift, существующие custom-reconnect ветки в TunnelController — это Wave 3. Только перемещает ReconnectClock+SystemReconnectClock в свой файл (Round 2 B-01)"
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift"
      provides: "Extracted ReconnectClock protocol + SystemReconnectClock struct (Round 2 B-01) — survives Plan 04 cleanup"
      min_lines: 20
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift"
      provides: "Extracted InstantReconnectClock actor (Round 2 B-02, internal not private) — survives TunnelControllerStateTests.swift deletion"
      min_lines: 30
    - path: "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift"
      provides: "@AppStorage autoReconnectEnabled + applyAutoReconnectToManager async helper"
      contains: "autoReconnectEnabled"
    - path: "BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift"
      provides: "Reusable section view with toggle + localized footer"
      min_lines: 30
    - path: "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift"
      provides: "Section «Подключение» рендерится перед «Безопасность» с AutoReconnectToggleSection"
      contains: "AutoReconnectToggleSection"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift"
      provides: "static func runIfNeeded() — idempotent existing-install migration (D-17b/c) + B-05 transient-failure safety + B-06 multi-manager via ManagerSelector + applyCurrentState consumer"
      min_lines: 70
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift"
      provides: "actor TunnelWatchdog with handleStatusChange(_:managerEnabled:) + setUserIntent(_:) — uses extracted ReconnectClock (B-01); cancellation extended to .reasserting (W-05)"
      min_lines: 110
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift"
      provides: "Idempotency + UserDefaults flag tests + transient-failure test (B-05); 5 tests total (Round 2 +1)"
      min_lines: 100
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift"
      provides: "9 gate tests (stable-session, managerEnabled, userIntent, debounce, .reasserting cancellation per W-05); uses extracted InstantReconnectClock (B-02)"
      min_lines: 165
    - path: "BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift"
      provides: "Toggle persistence + default ON tests"
      min_lines: 60
  key_links:
    - from: "SettingsView Раздел «Подключение»"
      to: "SettingsViewModel.autoReconnectEnabled"
      via: "@AppStorage binding"
      pattern: "AutoReconnectToggleSection"
    - from: "SettingsViewModel.autoReconnectEnabled didSet"
      to: "OnDemandRulesBuilder.applyCurrentState + manager.saveToPreferences + post bbtbProvisionerDidSave"
      via: "applyAutoReconnectToManager nonisolated async (W-03)"
      pattern: "applyAutoReconnectToManager"
    - from: "App init (iOSApp + macOSApp)"
      to: "OnDemandMigrationTask.runIfNeeded"
      via: "Task at app startup"
      pattern: "OnDemandMigrationTask\\.runIfNeeded"
    - from: "TunnelWatchdog.handleStatusChange"
      to: "FailoverProviding.nextServerAttempt"
      via: "weak reference, no XPC in hot path"
      pattern: "nextServerAttempt"
    - from: "TunnelWatchdog clock parameter"
      to: "ReconnectClock protocol (extracted file)"
      via: "import from extracted ReconnectClock.swift (Round 2 B-01)"
      pattern: "ReconnectClock"
    - from: "SettingsFeature Package.swift target deps"
      to: "MainScreenFeature module"
      via: "explicit Package.swift edit (Round 2 B-09)"
      pattern: "MainScreenFeature"
    - from: "OnDemandMigrationTask manager selection"
      to: "ManagerSelector.ourManagers"
      via: "filter loadAllFromPreferences result (Round 2 B-06)"
      pattern: "ManagerSelector\\.ourManagers"
---

<objective>
Wave 2 / Migration + UI + Watchdog — Покрыть пять блоков локированных decisions, которые завершают «parallel run» state с пользовательской видимостью toggle и mid-session failover safety:

1. **(NEW Round 2 Task 2.5) Extract ReconnectClock + InstantReconnectClock** (B-01, B-02) — pre-condition for Plan 04 Task 3c cleanup. Перемещаем protocol+struct из `ReconnectStateMachine.swift` в свой файл и nested actor из `TunnelControllerStateTests.swift` в shared TestClocks.swift.
2. **Toggle UI** (D-04/D-05/D-06/D-07) — раздел «Подключение» в Settings → переключатель «Автоматическое переподключение» с live-apply на manager через `OnDemandRulesBuilder.applyCurrentState` (W-04 closure / B-04 single entry point). Helper `nonisolated` (W-03 fix) — никаких XPC trips на MainActor.
3. **Migration of existing installs** (D-17b/c, Pitfall 1) — один-shot idempotent task на app init. **Round 2:** flag set ТОЛЬКО на confirmed success или confirmed-empty (B-05 transient-failure safety); применяется ко всем нашим manager'ам через `ManagerSelector.ourManagers` (B-06).
4. **Mid-session watchdog** (D-08/D-09/D-10) — узко-целевой actor реагирующий на `.disconnected` после stable session, fires failover к следующему серверу через `SwiftDataFailoverProvider` (preserved). **Round 2:** debounce cancellation расширен на `.reasserting` (W-05). Clock через extracted `ReconnectClock` (B-01).
5. **macOS wake observer pattern documentation** — текущий wake observer в TunnelController уже соответствует D-11/D-12/D-13 (`startVPNTunnel()` идемпотентный nudge). Мы не дублируем его в этой wave; Wave 3 при cleanup TunnelController сохранит этот специфический фрагмент с 3 guards (W-06).
6. **Localization** — добавить 3 строки в `Localizable.xcstrings`: title + footer + section header на ru + en.
7. **(NEW Round 2 Task 1 Step 0) Package.swift edit** (B-09) — explicit добавление `MainScreenFeature` в SettingsFeature target deps. Замена нечёткой «if needed» формулировки Round 1.

**Это всё ещё parallel-run wave.** Старая custom-reconnect machinery (ReconnectStateMachine.swift как файл, NetworkReachability, NEVPNStatusDidChange recovery branches в TunnelController) ПРОДОЛЖАЕТ работать. Watchdog запускается **в дополнение**, не вместо них. После UAT в Wave 3 (Plan 06C-04) мы будем DELETE старые компоненты. Параллельно работающие custom + watchdog могут двукратно вызывать failover на тот же `.disconnected` — это известный risk (Pitfall 5 в RESEARCH), accepted на этой wave; UAT в Wave 3 проверит manifest.

**Round 2 single deviation from "no source-file edits":** Task 2.5 удаляет ReconnectClock protocol + SystemReconnectClock struct из `ReconnectStateMachine.swift` и переносит их в новый `ReconnectClock.swift`. Это semantic no-op (тот же module, types accessible через `import MainScreenFeature` как и раньше), но позволит Plan 04 Task 3c удалить ReconnectStateMachine.swift без losing dependency. ReconnectStateMachine class сам (machinery — состояние, методы) **остаётся в файле** до Plan 04 cleanup.

Purpose:
- D-17b/c (migration): без этого пользователи апгрейднувшиеся с Phase 6 видят toggle ON в UI, но manager в реальности не имеет on-demand rules — UX-regression. **Round 2:** transient XPC failure не блокирует retry (B-05).
- D-08 (watchdog): Apple's on-demand попробует ТОТ ЖЕ (теперь dead) сервер; watchdog знает что сервер dead и переключает на next через round-robin SwiftDataFailoverProvider. **Round 2:** managerEnabled gate использует кэшированный `manager.isEnabled` (cached в TunnelController, passed in) вместо broken `lastKnownStatus != .invalid` proxy (B-03 — fix lives в Plan 04 caller; контракт watchdog'а тот же).
- D-04..D-07 (UI): пользователь видит и контролирует поведение auto-reconnect; default ON для безшовного UX. **Round 2:** consumer вызывает `applyCurrentState` — phantom-connect mitigated (B-04: toggle ON + intent OFF = isOnDemandEnabled false).

Output (8 файлов changed + 4 новых тест-файла):
- New: `OnDemandMigrationTask.swift`, `TunnelWatchdog.swift`, `AutoReconnectToggleSection.swift`.
- Modified: `SettingsViewModel.swift` (новое @AppStorage + helper), `SettingsView.swift` (новая section), `Localizable.xcstrings` (2 new strings).
- New tests: `OnDemandMigrationTaskTests.swift`, `TunnelWatchdogTests.swift`, `SettingsViewModelAutoReconnectTests.swift`.

**Что НЕ делается в этой wave:**
- Не удаляется ReconnectStateMachine, NetworkReachability, UserIntentStore (Wave 3 / Plan 06C-04).
- Не модифицируются App entry points (BBTB_iOSApp / BBTB_macOSApp) — migration task **вызывается через async Task на app launch**, но wiring точку оставляем executor определить per Task 2 details. Wave 3 переделает app entry points в любом случае.
- НЕ wiring watchdog в TunnelController. Watchdog создаётся (file existence + actor API + tests), но в Wave 3 он становится частью замены NEVPNStatusDidChange recovery path.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/06c-on-demand-migration/06C-CONTEXT.md
@.planning/phases/06c-on-demand-migration/06C-RESEARCH.md
@.planning/phases/06c-on-demand-migration/06C-01-PLAN.md
@.planning/phases/06c-on-demand-migration/06C-02-PLAN.md

<interfaces>
<!-- Builder from Plan 06C-01 (Round 2 — 4 public methods): -->
```swift
public enum OnDemandRulesBuilder {
    public static func apply(to manager: NETunnelProviderManager, isOnDemandEnabled: Bool)
    public static func applyCurrentState(to manager: NETunnelProviderManager,
                                         userDefaults: UserDefaults = .standard)
    public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard,
                                                key: String = "app.bbtb.autoReconnectEnabled") -> Bool
    public static func loadUserIntendedConnected(userDefaults: UserDefaults = .standard,
                                                  key: String = "app.bbtb.userIntendedConnected") -> Bool
}
```

<!-- ManagerSelector from Plan 06C-02 Task 0 (Round 2): -->
```swift
public enum ManagerSelector {
    public static let ourProviderBundleIdentifiers: Set<String>
    public static func ourManagers(from managers: [NETunnelProviderManager],
                                   knownBundleIDs: Set<String> = ourProviderBundleIdentifiers)
        -> [NETunnelProviderManager]
}
extension Notification.Name {
    public static let bbtbProvisionerDidSave: Notification.Name
}
```

<!-- ReconnectClock (Round 2 B-01) — extracted в Task 2.5 этого плана: -->
<!-- File: BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift -->
```swift
public protocol ReconnectClock: Sendable {
    func sleep(seconds: TimeInterval) async throws
}
public struct SystemReconnectClock: ReconnectClock { ... }
```
Та же сигнатура что в текущем `ReconnectStateMachine.swift` (lines 36, 41) — pure move.

<!-- InstantReconnectClock (Round 2 B-02) — extracted в Task 2.5 этого плана: -->
<!-- File: BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift -->
```swift
internal actor InstantReconnectClock: ReconnectClock {
    // body перенесён из TunnelControllerStateTests.swift line ~57 (private → internal).
}
```

<!-- FailoverProvider protocol (existing, from Phase 6 Wave 6): -->
```swift
public protocol FailoverProviding: Sendable {
    func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)?
    func resetCycle() async
}
```

<!-- SettingsViewModel current shape (BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift): -->
```swift
@MainActor
public final class SettingsViewModel: ObservableObject {
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false
    @AppStorage("app.bbtb.customDNS") public var customDNS: String = ""
    @AppStorage("app.bbtb.adBlockEnabled") public var adBlockEnabled: Bool = false
    public init() {}
    public var dnsConfig: DNSConfig { ... }
    // ... validation helpers
}
```

<!-- SettingsView (BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift) — already has a Section pattern: -->
```swift
Section {
    KillSwitchToggleSection(isOn: $viewModel.killSwitchEnabled,
                            footerText: L10n.settingsKillSwitchFooter)
} header: {
    Text(L10n.settingsSecuritySection)
} footer: {
    Text(L10n.settingsKillSwitchFooter)
}
```

<!-- KillSwitchToggleSection.swift — reference pattern for our AutoReconnectToggleSection.swift -->
<!-- (BBTB/Packages/AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift) -->

<!-- TunnelController current relevant state (will NOT be modified in this wave): -->
<!-- - actor TunnelController preserves connect()/disconnect() -->
<!-- - NEVPNStatusDidChange observer at startReachability (reads from notification.object — XPC-free) -->
<!-- - macOS wake observer NSWorkspace.didWake at startReachability -->
<!-- - failoverProvider injected via setFailoverProvider (two-phase init) -->
<!-- - userIntendedConnected flag (persisted via UserIntentStore) — ОСТАЁТСЯ В ЭТОЙ WAVE -->

<!-- Localization pattern (Localizable.xcstrings is JSON; existing keys for reference): -->
<!-- - "settingsKillSwitchFooter" (ru + en) -->
<!-- - "settingsSecuritySection" (ru + en) -->
<!-- New keys we add: -->
<!-- - "settingsConnectionSection" → ru="Подключение", en="Connection" -->
<!-- - "settingsAutoReconnectTitle" → ru="Автоматическое переподключение", en="Auto-reconnect" -->
<!-- - "settingsAutoReconnectFooter" → ru="Восстанавливать соединение при смене сети или после сна. Если выключено — после обрыва нужно подключиться вручную.", en="Restore the connection on network change or after wake. When disabled, you must reconnect manually after a drop." -->

<!-- OnDemandMigrationTask API contract (Plan 06C-03 introduces): -->
```swift
public enum OnDemandMigrationTask {
    public static func runIfNeeded(userDefaults: UserDefaults = .standard) async
    // Idempotent: проверяет flag, делает работу, выставляет flag. Repeat call = no-op.
    // НЕ throws — все ошибки логируются, флаг НЕ выставляется на failure (retry next launch).
}
```
Idempotency flag key: `app.bbtb.autoReconnectMigratedV6c`.

<!-- TunnelWatchdog API contract (Plan 06C-03 introduces; Round 2 unchanged signature): -->
```swift
public actor TunnelWatchdog {
    public init(failoverProvider: any FailoverProviding,
                stableSessionThreshold: TimeInterval = 30,
                disconnectDebounce: TimeInterval = 3,
                clock: ReconnectClock = SystemReconnectClock())  // Round 2: from extracted ReconnectClock.swift
    public func handleStatusChange(_ status: NEVPNStatus, managerEnabled: Bool) async
    public func setUserIntent(_ intent: Bool) async
}
```
Note (Round 2): `setFailoverObserver` callback для banner state — НЕ в Plan 03; добавляется
в Plan 04 Task 3b (banner rewire). Plan 03 strictly parallel-run — никаких API surface для UI.
- `ReconnectClock` после Task 2.5 живёт в `ReconnectClock.swift` (extracted из `ReconnectStateMachine.swift` per Round 2 B-01) — reuse этот тип, НЕ define another. Same module → no `import` change beyond MainScreenFeature.

<!-- Watchdog logic (from RESEARCH Pattern 3 + Pitfall 10): -->
<!-- - .connected → schedule task; after stable threshold (30s), mark stableSession = true -->
<!-- - .disconnected → if stableSession && userIntent && managerEnabled: -->
<!--     - schedule debounce task (3s sleep) -->
<!--     - after debounce, check status STILL .disconnected (re-passed via Watchdog state — see Task 2 design) -->
<!--     - if yes: call failoverProvider.nextServerAttempt; execute attempt closure -->
<!-- - .connecting/.reasserting/.connected during debounce → cancel debounce task, don't fire (W-05 расширен) -->
<!-- - userIntent = false → reset stableSession; cancel pending tasks -->

<!-- Watchdog reads status from `notification.object` in the future caller (Wave 3 wiring). -->
<!-- Watchdog ITSELF не делает XPC trips — все аргументы passed in. -->
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: SettingsViewModel auto-reconnect toggle + live-apply + Settings UI + Localization</name>
  <files>BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift, BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift, BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift, BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings, BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Package.swift строки 40-50 (SettingsFeature target deps для B-09 Step 0)
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift полностью
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift полностью
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift полностью (pattern reference)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (Plan 06C-01 Round 2 — applyCurrentState API)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift (Plan 06C-02 Round 2 — ourManagers + bbtbProvisionerDidSave)
    - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings первые 200 строк — найти как формируются ключи (`settingsKillSwitchFooter`, `settingsSecuritySection`)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pattern 2: Toggle live-apply через handleUserDefaultsChange» и Pitfall 4
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md секции B-09 + W-03 + W-04 + B-06 + B-03
  </read_first>
  <behavior>
    SettingsViewModel.autoReconnectEnabled API (locked):
    ```swift
    @AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true
    ```
    @AppStorage default `true` — соответствует D-04 default ON. (Note: @AppStorage default value возвращается только если ключ ещё не записан; после первого toggle off + back on UserDefaults значение persists.)

    Live-apply helper (Round 2 W-03 + W-04 + B-06 + B-03):
    ```swift
    /// Phase 6c / D-06 — apply toggle change to existing NETunnelProviderManager.
    /// Single XPC trip per toggle press (NOT observer hot path).
    /// Не tear down active tunnel при toggle OFF (Pitfall 4) — Apple's default behavior.
    ///
    /// Round 2 changes:
    /// - W-03: помечен `nonisolated` — runs off main actor; вызывается через
    ///   `Task.detached { await viewModel.applyAutoReconnectToManager() }` из `.onChange(of:)` modifier.
    /// - W-04: использует `OnDemandRulesBuilder.applyCurrentState` — НЕ direct `apply`. Single source of truth.
    /// - B-06: применяет ко ВСЕМ нашим manager'ам через `ManagerSelector.ourManagers`. Multi-manager safe.
    /// - B-03: после save+reload каждого manager'а постит `.bbtbProvisionerDidSave` для refresh
    ///   `cachedManager` в TunnelController (cross-plan contract).
    nonisolated public func applyAutoReconnectToManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let ours = ManagerSelector.ourManagers(from: managers)
            for manager in ours {
                OnDemandRulesBuilder.applyCurrentState(to: manager)
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()  // RESEARCH §9.1
                NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: nil)
            }
        } catch {
            // Логируем; @AppStorage уже сохранил toggle value; on next provisionTunnelProfile
            // applyCurrentState подхватит fresh value (toggle + intent).
        }
    }
    ```

    Тесты (SettingsViewModelAutoReconnectTests.swift):
    - Test 1 (`test_freshInstall_autoReconnectEnabled_isTrue`): создать ViewModel в isolated suite; assert `autoReconnectEnabled == true` (default).
    - Test 2 (`test_setAutoReconnectFalse_persistsInUserDefaults`): set `viewModel.autoReconnectEnabled = false`; assert `userDefaults.bool(forKey: "app.bbtb.autoReconnectEnabled") == false` (после propagation через @AppStorage).
    - Test 3 (`test_setAutoReconnectTrue_persistsTrue`): same but set true.
    - Test 4 (`test_applyAutoReconnectToManager_swallowsErrorWhenNoManager`): `applyAutoReconnectToManager()` доес not throw когда `loadAllFromPreferences()` returns empty array (нет manager в test env). Это test поведения catch-block: «no-op gracefully».

    UI:
    - `AutoReconnectToggleSection.swift` — mirror of KillSwitchToggleSection: `Toggle(L10n.settingsAutoReconnectTitle, isOn: $isOn)` внутри, takes `Binding<Bool>` и footer string.
    - В SettingsView добавить новую Section с этим toggle ПЕРЕД секцией «Безопасность» (что соответствует UX-приоритету «Подключение → Безопасность → Расширенные»):
    ```swift
    Section {
        AutoReconnectToggleSection(
            isOn: $viewModel.autoReconnectEnabled,
            footerText: L10n.settingsAutoReconnectFooter
        )
    } header: {
        Text(L10n.settingsConnectionSection)
    } footer: {
        Text(L10n.settingsAutoReconnectFooter)
    }
    ```
    - Live-apply wire-up в View (Round 2 W-03): `.onChange(of: viewModel.autoReconnectEnabled) { Task.detached { await viewModel.applyAutoReconnectToManager() } }`. `Task.detached` гарантирует off-main выполнение (helper уже `nonisolated`, но `.detached` укрепляет контракт). Этот modifier ставится на корень `Form` чтобы не повторять для каждой section.

    Localization (3 new keys):
    - `settingsConnectionSection`: ru="Подключение", en="Connection"
    - `settingsAutoReconnectTitle`: ru="Автоматическое переподключение", en="Auto-reconnect"
    - `settingsAutoReconnectFooter`: ru="Восстанавливать соединение при смене сети или после сна. Если выключено — после обрыва нужно подключиться вручную.", en="Restore the connection on network change or after wake. When disabled, you must reconnect manually after a drop."

    L10n key access pattern (как для existing keys): `L10n.settingsConnectionSection`. Если в проекте используется SwiftGen или ручной enum — следовать существующему pattern (читать `Localization.swift` или сгенерированный файл).
  </behavior>
  <action>
    **Round 2 ordering:** Step 0 (Package.swift cycle-safe edit) → Step 1 (tests RED) → Step 2 (ViewModel) → Step 3 (UI component) → Step 4 (SettingsView wiring) → Step 5 (Localization) → Step 6 (L10n re-gen if needed) → final test.

    **Step 0 — Package.swift (B-09 fix — REPLACES Round 1 "import MainScreenFeature if needed" language):**

    Open `BBTB/Packages/AppFeatures/Package.swift`. Locate SettingsFeature target (~line 42-45):
    ```swift
    .target(
        name: "SettingsFeature",
        dependencies: ["VPNCore", "DesignSystem", "Localization", "KillSwitch"]
    ),
    ```
    Edit to add `"MainScreenFeature"`:
    ```swift
    .target(
        name: "SettingsFeature",
        dependencies: ["VPNCore", "DesignSystem", "Localization", "KillSwitch", "MainScreenFeature"]
    ),
    ```

    Cycle safety verification (Round 2 B-09 contract):
    - `grep -A 10 'name: "MainScreenFeature"' BBTB/Packages/AppFeatures/Package.swift` (lines ~27-37) must NOT contain `SettingsFeature` (verified at brief-time per §3 of revision brief).
    - `MainScreenFeatureTests` target (line ~55) already lists `SettingsFeature` — that's a TEST target, not a source cycle. OK.

    Run `swift build --package-path BBTB/Packages/AppFeatures` после правки — должен компилироваться (даже без новых файлов SettingsFeature — package resolution просто recompute'нет deps).

    **Step 1 — RED tests:**

    Создать `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift` с 4 методами по списку в `<behavior>`. RED state ожидается (autoReconnectEnabled не существует, applyAutoReconnectToManager не существует).
    - Если `SettingsFeatureTests` directory не существует — проверить Package.swift на наличие test target; создать если нет (по pattern существующего `MainScreenFeatureTests`).

    **Step 2 — SettingsViewModel:**

    Modify `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift`:
    - Добавить `import NetworkExtension`.
    - Добавить `import MainScreenFeature` (Step 0 уже сделал deps explicit).
    - Добавить `@AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true` сразу под существующими @AppStorage свойствами.
    - Добавить `nonisolated public func applyAutoReconnectToManager() async` (W-03 — nonisolated) с body как в behavior выше. Body использует `ManagerSelector.ourManagers` + `OnDemandRulesBuilder.applyCurrentState` + posts `.bbtbProvisionerDidSave`.
    - Doc-comment на русском с reference на D-04, D-06, Pitfall 4, W-03, W-04, B-06, B-03.
    - Запустить тесты — должны pass.

    **Step 3 — UI Component:**

    Создать `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift` — mirror KillSwitchToggleSection:
    ```swift
    import SwiftUI
    import Localization

    /// Phase 6c / D-04 — раздел «Подключение» / Toggle «Автоматическое переподключение».
    public struct AutoReconnectToggleSection: View {
        @Binding public var isOn: Bool
        public let footerText: String
        public init(isOn: Binding<Bool>, footerText: String) { ... }
        public var body: some View {
            Toggle(L10n.settingsAutoReconnectTitle, isOn: $isOn)
        }
    }
    ```

    **Step 4 — SettingsView wiring (W-03 Task.detached):**

    Modify `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift`:
    - Добавить новую Section с AutoReconnectToggleSection ПЕРЕД секцией Безопасность (KillSwitch).
    - Добавить **`.onChange(of: viewModel.autoReconnectEnabled) { Task.detached { await viewModel.applyAutoReconnectToManager() } }`** modifier на Form (W-03 fix — off-main).
    - Сохранить весь существующий код без regression.

    **Step 5 — Localization:**

    Modify `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`:
    - JSON modification: добавить 3 новых key entries по pattern существующих (`settingsKillSwitchFooter` — найти его блок и сшаблонировать).
    - Each key has `ru` + `en` localizations.
    - Использовать exact ru/en тексты из секции behavior выше.

    **Step 6 — L10n regeneration:**

    Если в проекте есть auto-generated L10n.swift / Strings.swift — может потребоваться запустить SwiftGen / build чтобы L10n.settingsConnectionSection стала доступна. Проверить через `grep -rn "L10n.settingsKillSwitch" BBTB/` — увидеть как existing keys генерируются.

    Final: `swift test --package-path BBTB/Packages/AppFeatures` full suite green.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter SettingsViewModelAutoReconnectTests && swift build --package-path Packages/AppFeatures</automated>
  </verify>
  <acceptance_criteria>
    - 4 теста SettingsViewModelAutoReconnectTests pass.
    - **`grep -A 5 'name: "SettingsFeature"' BBTB/Packages/AppFeatures/Package.swift | grep -c "MainScreenFeature"` returns ≥ 1** (Round 2 B-09 — explicit dep).
    - **`grep -A 10 'name: "MainScreenFeature"' BBTB/Packages/AppFeatures/Package.swift | grep -c "SettingsFeature"` returns 0** (Round 2 B-09 — no source-target cycle; test target on line ~55 doesn't count toward source cycle).
    - `grep -c "autoReconnectEnabled" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns ≥ 2 (declaration + apply helper).
    - `grep -c "app.bbtb.autoReconnectEnabled" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns ≥ 1.
    - **`grep -c "OnDemandRulesBuilder.applyCurrentState" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns 1** (Round 2 W-04: single source of truth).
    - **`grep -c "OnDemandRulesBuilder.apply\\b" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns 0** (Round 2 W-04: direct apply NOT used by callsite).
    - **`grep -c "nonisolated" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns ≥ 1** (W-03: helper nonisolated).
    - **`grep -c "ManagerSelector.ourManagers" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns 1** (B-06: multi-manager safe).
    - **`grep -c "bbtbProvisionerDidSave" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns ≥ 1** (B-03: notification post for TunnelController cache refresh).
    - **`grep -c "Task.detached" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` returns ≥ 1** (W-03: off-main execution).
    - `grep -c "AutoReconnectToggleSection" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` returns ≥ 1.
    - `grep -c "settingsConnectionSection\\|settingsAutoReconnectTitle\\|settingsAutoReconnectFooter" BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` returns ≥ 3.
    - `grep -c "Автоматическое переподключение" BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` returns ≥ 1.
    - `cd BBTB && swift test --package-path Packages/AppFeatures` full suite green (regression-safe).
    - No tear-down behavior added (отсутствует `stopVPNTunnel` в applyAutoReconnectToManager — Pitfall 4).
  </acceptance_criteria>
  <done>Toggle UI существует в Settings → раздел «Подключение». Default ON. Live-applies через `applyCurrentState` за один XPC trip per change (off-main via nonisolated + Task.detached). Localization добавлена для ru + en. Package.swift dep explicit (B-09). ManagerSelector + bbtbProvisionerDidSave hooked (B-06 + B-03).</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: OnDemandMigrationTask — idempotent one-shot migration для existing installs</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (Plan 06C-01 Round 2 — applyCurrentState API)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift (Plan 06C-02 Round 2)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pitfall 1» (полностью) + «Code Examples» Example 5 (migrateExistingManagerForOnDemand recipe)
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md D-17b, D-17c
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md B-05 + B-06
  </read_first>
  <behavior>
    API:
    ```swift
    public enum OnDemandMigrationTask {
        /// Idempotent migration. Safe to call multiple times — first successful call sets the flag;
        /// subsequent calls are no-op. On failure, flag NOT set → retry on next app launch.
        public static func runIfNeeded(userDefaults: UserDefaults = .standard) async
    }
    ```

    Flag key: `app.bbtb.autoReconnectMigratedV6c`.

    Logic (Round 2 B-05 + B-06 — six-branch decision tree, flag set ONLY on confirmed-success/confirmed-empty):

    1. Если `userDefaults.bool(forKey: migratedKey) == true` → log debug, return (already done — idempotent).
    2. Try `let managers = try await NETunnelProviderManager.loadAllFromPreferences()`. **EXPLICIT do/catch**:
       - **(Round 2 B-05) If `loadAllFromPreferences` THROWS** → log warn, **DO NOT set flag**, return.
         Transient XPC failure не должен permanently заблокировать migration → retry next launch.
    3. Если `managers.isEmpty` — fresh install с ещё-не-импортированным config'ом или абсолютная отсутствие profile'ов. Set flag = true и return: ConfigImporter Plan 06C-02 пишет on-demand через `applyCurrentState` на первый import. Idempotency invariant.
    4. **(Round 2 B-06)** `let ours = ManagerSelector.ourManagers(from: managers)`. Если `ours.isEmpty` (есть managers но ни один не наш — другой VPN-app или stale install residue) → set flag = true, return (наш профиль появится через ConfigImporter на следующий import).
    5. Else (`!ours.isEmpty`):
       - For each `manager in ours`:
         - `OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: userDefaults)` (Round 2 W-04 + B-04).
         - Try `manager.saveToPreferences()` + `manager.loadFromPreferences()` (RESEARCH §9.1).
         - **(Round 2 B-05) If save/load THROWS** → log error, **DO NOT set flag**, return (retry next launch).
       - **If ALL saves+reloads succeeded** → set flag = true. Post `.bbtbProvisionerDidSave` notification once (B-03 cross-plan — refresh TunnelController cache after batch migration).

    Тесты (OnDemandMigrationTaskTests.swift — **5 tests Round 2, was 4**):

    - Test 1 (`test_runIfNeeded_alreadyMigrated_isNoOp`): fresh suite, set `migratedKey = true`. Call `runIfNeeded(userDefaults: ud)`. Assert: no error, flag still true.

    - Test 2 (`test_runIfNeeded_emptyManagersOrOurManagersEmpty_setsFlag`) — RENAMED Round 2: было «freshInstallNoManager». Fresh suite. Call `runIfNeeded(userDefaults: ud)`. В test env `loadAllFromPreferences()` returns empty (no entitlements в test process; `loadAllFromPreferences` НЕ throws в `swift test` — она возвращает `[]` без entitlement-gated provider lookup; ИЛИ throws — оба case'а: branch 3 OR branch 4 leads to flag=true). Assert: `ud.bool(forKey: "app.bbtb.autoReconnectMigratedV6c") == true`.

    - Test 3 (`test_runIfNeeded_isIdempotent_twoCallsSafe`): fresh suite. Call twice. Assert: flag true; no crash.

    - Test 4 (`test_runIfNeeded_respectsTogglePersisted`): fresh suite. Set `ud.set(false, forKey: "app.bbtb.autoReconnectEnabled")`. Call `runIfNeeded`. Assert: flag true; toggle value НЕ changed (`ud.bool(forKey: "app.bbtb.autoReconnectEnabled") == false`).

    - **Test 5 (`test_runIfNeeded_loadAllThrows_doesNotSetFlag`)** — NEW Round 2 for B-05:
      Fresh suite. Этот test требует test seam: либо параметризовать `OnDemandMigrationTask.runIfNeeded` через
      `loader: () async throws -> [NETunnelProviderManager]` closure parameter с default = real `loadAllFromPreferences`,
      либо extract pure-logic helper `migrate(managers:userDefaults:)`. **Решение: добавить internal seam**
      `static func runIfNeeded(userDefaults:loader:)` где `loader` default'ит к реальной NEM API; тесты
      могут pass closure что throws.
      Test body: `await OnDemandMigrationTask.runIfNeeded(userDefaults: ud, loader: { throw NSError(...) })`.
      Assert: `ud.bool(forKey: "app.bbtb.autoReconnectMigratedV6c") == false` — flag STAYS FALSE на transient throw.

    Notes для test env:
    - `NETunnelProviderManager.loadAllFromPreferences()` поведение в `swift test` без entitlements: на macOS возвращает empty `[]` (NEM не активен); на CI может throw. Test 2 покрывает оба варианта (branches 3 и 4 ведут к flag=true).
    - Test 5 explicit `loader` throw seam: явная гарантия что transient failure path работает корректно (B-05 invariant).
    - Тесты НЕ проверяют что manager properties applied — это сделать без entitlements нельзя. Тесты проверяют:
      (a) Flag setting behavior (idempotency + transient safety).
      (b) UserDefaults toggle не изменяется при migration.
      (c) Crash-free.
    - Эти guarantee'и достаточны — фактический apply path проверен в OnDemandRulesBuilderTests Plan 06C-01.

    Decision: behavior #3 above («empty managers → set flag = true») — сознательное упрощение. Альтернатива: «не set flag, попробовать снова next launch». Простота preferred — fresh install после first config import уже получит on-demand через ConfigImporter Plan 06C-02 wiring. **Round 2 caveat:** branch 2 (loadAllFromPreferences THROWS) теперь explicitly preserves flag=false — это разница с Round 1, где throw treated as «fresh install proxy».
  </behavior>
  <action>
    Сначала RED тесты в `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift` с **5 методами** (Round 2: was 4, +1 для B-05).

    Затем создать `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift`:

    1. Header doc-comment на русском: ссылка на Phase 6c / Plan 06C-03 / D-17b / D-17c / Pitfall 1 / Round 2 B-05 / B-06. Объяснение six-branch decision tree; idempotency invariant; «transient failure → no flag, retry next launch».
    2. `import Foundation`, `import NetworkExtension`, `import OSLog`.
    3. `public enum OnDemandMigrationTask`:
       - `private static let migratedKey = "app.bbtb.autoReconnectMigratedV6c"`.
       - `private static let log = Logger(subsystem: "app.bbtb.client", category: "ondemand-migration")`.
       - **`public static func runIfNeeded(userDefaults: UserDefaults = .standard, loader: @Sendable () async throws -> [NETunnelProviderManager] = { try await NETunnelProviderManager.loadAllFromPreferences() }) async`** — Round 2 adds `loader` test seam (B-05 testability):
         - Branch 1: Check flag → if true, log debug, return (idempotent).
         - Branch 2: do/catch around `try await loader()`. **На throw — log warn, NO flag set, return** (B-05).
         - Branch 3: Если `managers.isEmpty` — log notice «no manager — fresh install/empty pool, marking migration done», **set flag = true**, return.
         - Branch 4: `let ours = ManagerSelector.ourManagers(from: managers)` (B-06). Если `ours.isEmpty` (есть чужие, но нет наших) — log notice, **set flag = true**, return.
         - Branch 5: For each `manager in ours`:
           - `OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: userDefaults)` (W-04 / B-04).
           - do/catch around `try await manager.saveToPreferences()`. **На throw — log error, NO flag set, return** (B-05).
           - do/catch around `try await manager.loadFromPreferences()` (RESEARCH §9.1). **На throw — log error, NO flag set, return**.
         - After loop succeeds: **set flag = true**, log notice «migration applied to N our managers», post `NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: nil)` once (B-03 — refresh TunnelController cache).

    Запустить tests — все 5 pass.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandMigrationTaskTests</automated>
  </verify>
  <acceptance_criteria>
    - **5 тестов** OnDemandMigrationTaskTests pass (Round 2: was 4, +1 для B-05).
    - `grep -c "autoReconnectMigratedV6c" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 1.
    - **`grep -c "OnDemandRulesBuilder.applyCurrentState" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 1** (Round 2 W-04: single source of truth).
    - **`grep -c "OnDemandRulesBuilder.apply\\b" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 0** (Round 2 W-04: direct apply NOT used).
    - **`grep -c "ManagerSelector.ourManagers" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 1** (Round 2 B-06: multi-manager filter).
    - **`grep -c "do {" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 2** (Round 2 B-05: explicit do/catch for loadAllFromPreferences AND saveToPreferences — at least 2 blocks; saveToPreferences may share single do/catch with loadFromPreferences if implemented together).
    - **`grep -cE "try\\? await" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 0** (Round 2 B-05: replaced `try?` with explicit do/catch — `try? await loadAllFromPreferences()` Round 1 pattern is FORBIDDEN).
    - **`grep -c "bbtbProvisionerDidSave" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 1** (B-03: refresh TunnelController cache after batch migration).
    - **`grep -c "loader:" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 1** (Round 2 B-05: test seam parameter).
    - `grep -c "public enum OnDemandMigrationTask" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 1.
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
    - Full AppFeatures test suite green.
  </acceptance_criteria>
  <done>OnDemandMigrationTask существует, идемпотентный, безопасный для fresh + existing installs. **Round 2:** transient XPC failure не блокирует retry (B-05); multi-manager safe (B-06); applyCurrentState single entry point (W-04 / B-04); постит bbtbProvisionerDidSave (B-03). Wave 3 (Plan 06C-04) wire это в App entry points.</done>
</task>

<task type="auto">
  <name>Task 2.5 (Round 2 B-01/B-02): Extract ReconnectClock + InstantReconnectClock to standalone files — pre-condition for watchdog tests AND Plan 04 cleanup safety</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift строки 1-50 (особенно lines 35-50: `public protocol ReconnectClock` + `public struct SystemReconnectClock`)
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift строки 50-70 (nested `actor InstantReconnectClock` — private)
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md секции B-01 + B-02
  </read_first>
  <action>
    **Round 2 B-01 + B-02 — pre-condition extraction:**

    Это semantic no-op shift: types перемещены, но module unchanged. После Task 2.5 `swift build` + `swift test`
    full suite ОСТАЁТСЯ green (no consumer broken). После Plan 04 Task 3c удаления `ReconnectStateMachine.swift` +
    `TunnelControllerStateTests.swift`, типы выживают благодаря этому extract.

    **Step 1 — Create `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift`** (B-01):

    Move `public protocol ReconnectClock` + `public struct SystemReconnectClock` ИЗ `ReconnectStateMachine.swift`
    В новый файл. Один-в-один копия (signature + body); добавить header doc-comment:
    ```swift
    /// Phase 6c / Plan 06C-03 Round 2 B-01 — extracted from `ReconnectStateMachine.swift` to survive
    /// Plan 06C-04 Task 3c cleanup. `TunnelWatchdog` (Plan 06C-03 Task 3) и любые будущие consumers
    /// импортируют этот тип; ReconnectStateMachine class сам в Plan 04 удалится, протокол ОСТАНЕТСЯ.
    import Foundation

    public protocol ReconnectClock: Sendable {
        func sleep(seconds: TimeInterval) async throws
    }

    public struct SystemReconnectClock: ReconnectClock {
        public init() {}
        public func sleep(seconds: TimeInterval) async throws {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
    ```

    **Step 2 — Modify `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift`** (B-01):

    Удалить `public protocol ReconnectClock` и `public struct SystemReconnectClock` declarations (lines 36 + 41 per brief §3).
    ReconnectStateMachine class сам **остаётся** в файле (parallel-run invariant — Plan 04 Task 3c удалит его).
    Поскольку оба файла в одном модуле (MainScreenFeature), consumer'ы (`stateMachine` в TunnelController) видят
    типы транзитивно — no import change.

    **Step 3 — Create `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift`** (B-02):

    Move `actor InstantReconnectClock` (private nested actor inside `TunnelControllerStateTests.swift` line ~57)
    в новый файл как `internal` (NOT private). Body — verbatim move:
    ```swift
    /// Phase 6c / Plan 06C-03 Round 2 B-02 — extracted from `TunnelControllerStateTests.swift` to survive
    /// Plan 06C-04 Task 3c cleanup. Shared test seam: `TunnelControllerStateTests` (during parallel-run window)
    /// AND `TunnelWatchdogTests` (Task 3 этого плана) used it.
    import Foundation
    @testable import MainScreenFeature  // for ReconnectClock protocol

    internal actor InstantReconnectClock: ReconnectClock {
        // body verbatim from TunnelControllerStateTests.swift line ~57.
        // Make sure `recordedSleeps: [TimeInterval]` accessor + sleep() impl present.
    }
    ```

    **Step 4 — Modify `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift`** (B-02):

    Удалить the private nested `actor InstantReconnectClock { ... }` declaration. File ОСТАЁТСЯ (deleted в Plan 04 Task 3c).
    Test code consumer (`reconnectClock: InstantReconnectClock()` на lines 106, 351, 476 per brief §3) теперь
    использует extracted shared type — automatically resolved через same target.

    **Step 5 — Build + verify:**

    `swift build --package-path BBTB/Packages/AppFeatures` succeeds (semantic no-op).
    `swift test --package-path BBTB/Packages/AppFeatures` full suite green — НИКАКИХ regressions.
    Особенно: TunnelControllerStateTests все ещё pass с extracted InstantReconnectClock.
  </action>
  <verify>
    <automated>cd BBTB && swift build --package-path Packages/AppFeatures && swift test --package-path Packages/AppFeatures</automated>
  </verify>
  <acceptance_criteria>
    - **`grep -c "protocol ReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` returns 1** (B-01: declared in new file).
    - **`grep -c "struct SystemReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` returns 1** (B-01).
    - **`grep -c "protocol ReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` returns 0** (B-01: removed from old file).
    - **`grep -c "struct SystemReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` returns 0** (B-01).
    - **`grep -c "actor InstantReconnectClock" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` returns 1** (B-02: declared in new file, internal not private).
    - **`grep -c "private.*actor InstantReconnectClock" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` returns 0** (B-02: removed from old file).
    - **`grep -c "internal actor InstantReconnectClock\\|actor InstantReconnectClock" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` returns 0** (B-02: NO declaration left in old file).
    - **ReconnectStateMachine class declaration ОСТАЁТСЯ в `ReconnectStateMachine.swift`** (parallel-run invariant): `grep -c "public final class ReconnectStateMachine\\|class ReconnectStateMachine" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` returns ≥ 1.
    - **TunnelControllerStateTests.swift ОСТАЁТСЯ как файл** (parallel-run): `test -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift`.
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
    - Full AppFeatures test suite green — TunnelControllerStateTests still pass с extracted InstantReconnectClock.
  </acceptance_criteria>
  <done>Round 2 B-01 + B-02 closed: ReconnectClock + SystemReconnectClock + InstantReconnectClock все экстрагированы в свои файлы. Parallel-run invariant preserved (ReconnectStateMachine class + TunnelControllerStateTests файл всё ещё на месте). Готово для Task 3 (TunnelWatchdog использует extracted ReconnectClock) и Plan 04 Task 3c (удаление RSM + TCS не сломает зависимости).</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: TunnelWatchdog actor — mid-session failover с 30s stable session gate + 3s debounce</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (полностью — для conventions, особенно lines 380-410 NEVPN observer pattern XPC-free)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift (полностью — нужный FailoverProviding contract)
    - **BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift** (Round 2 — extracted в Task 2.5; используем оттуда, НЕ создаём дубль; НЕ ссылаемся на ReconnectStateMachine.swift)
    - **BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift** (Round 2 — extracted `InstantReconnectClock` в Task 2.5; используем оттуда в watchdog tests)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pattern 3: Watchdog observer (D-08)» полностью + Pitfall 5 + Pitfall 10
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md D-08, D-09, D-10
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md секции B-01 + B-02 + W-05
  </read_first>
  <behavior>
    Actor API (locked):
    ```swift
    public actor TunnelWatchdog {
        public init(failoverProvider: any FailoverProviding,
                    stableSessionThreshold: TimeInterval = 30,
                    disconnectDebounce: TimeInterval = 3,
                    clock: ReconnectClock = SystemReconnectClock())

        /// Called from NEVPNStatusDidChange observer. `managerEnabled` snapshot
        /// passed by caller — watchdog NEVER reads manager.isEnabled itself (no XPC in hot path).
        public func handleStatusChange(_ status: NEVPNStatus, managerEnabled: Bool) async

        /// User intent gate (D-08). Set true at user-initiated connect, false at disconnect.
        public func setUserIntent(_ intent: Bool) async

        // Test seams:
        internal func getStableSessionForTest() -> Bool
        internal func getUserIntentForTest() -> Bool
        internal func getDebounceActiveForTest() -> Bool
    }
    ```

    Internal state:
    - `stableSession: Bool = false`
    - `stableSessionTask: Task<Void, Never>?`
    - `userIntent: Bool = false`
    - `debounceTask: Task<Void, Never>?`
    - `failoverProvider: any FailoverProviding` (weak ref — actor stores closure-based wrapper, see below)
    - `clock: ReconnectClock`
    - `stableSessionThreshold: TimeInterval`, `disconnectDebounce: TimeInterval`
    - `log = Logger(subsystem: "app.bbtb.client", category: "tunnel-watchdog")`

    Logic (full state machine):

    `setUserIntent(_:)`:
    - Set userIntent.
    - Если false → cancel stableSessionTask, cancel debounceTask, set stableSession = false.

    `handleStatusChange(.connected, ...)`:
    - Cancel any pending debounceTask (мы успешно реconnected — race won).
    - Cancel previous stableSessionTask (re-arm).
    - Spawn new stableSessionTask: sleep `stableSessionThreshold` секунд через `clock.sleep`; если не cancelled — set stableSession = true.

    `handleStatusChange(.disconnected, managerEnabled:)`:
    - Если !userIntent || !managerEnabled || !stableSession → log skip reason, return.
    - Если debounceTask already running → return (already debouncing).
    - Spawn debounceTask: sleep `disconnectDebounce` (3s) через clock; если не cancelled, AND все ещё в .disconnected (не получил новое .connected/.connecting — это устанавливается тем что debounceTask еще running, не cancelled при connected) → fire failover.
    - В debounceTask: после sleep, get nextServerAttempt; если nil — return. Иначе await attempt closure (try? — Apple's on-demand тоже might be retrying; не throw mistake).
    - Reset stableSession = false после firing (next .connected re-arms).

    `handleStatusChange(.connecting | .reasserting | ...)` (Round 2 W-05 — explicit `.reasserting` parity):
    - Cancel debounceTask (если активна) — Apple's on-demand reconnect выиграл race; не fire failover.
    - Не reset stableSession (это transient state, не loss-of-session).
    - **W-05:** cancellation now applies to both `.connecting` AND `.reasserting` (Round 1 cancelled only on `.connected`). `.reasserting` particularly important на iOS 26+ где Apple's on-demand попадает в reasserting state до full reconnect.

    Tests (TunnelWatchdogTests.swift) — **9 tests Round 2, was 8** (+1 for W-05):

    Use `InstantReconnectClock` ИЗ extracted `TestClocks.swift` (Round 2 B-02). `recordedSleeps: [TimeInterval]` accessor для verification. Pattern был в `TunnelControllerStateTests.swift` lines 56-62 — теперь shared internal в TestClocks.swift.

    Failover mock:
    ```swift
    final actor MockFailover: FailoverProviding {
        var nextAttemptCalls = 0
        var resetCalls = 0
        var nextResult: (serverName: String, attempt: @Sendable () async throws -> Date)?
        func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)? {
            nextAttemptCalls += 1
            return nextResult
        }
        func resetCycle() async { resetCalls += 1 }
    }
    ```

    - Test 1 (`test_disconnectedBeforeStableSession_noFailover`):
      Set userIntent(true); emit .disconnected (without prior 30s stable session). Yield. Assert `mock.nextAttemptCalls == 0`.

    - Test 2 (`test_stableSession_disconnected_firesFailoverAfterDebounce`):
      Set userIntent(true); emit .connected; await `getStableSessionForTest() == true` (через repeated yield + check until clock recorded 30s sleep — instant clock yields, then sets stableSession). Emit .disconnected (managerEnabled: true). Yield until debounce done. Assert `mock.nextAttemptCalls == 1`.

    - Test 3 (`test_disconnectButManagerDisabled_noFailover`):
      Set userIntent + stable session. Emit .disconnected (managerEnabled: **false**). Yield. Assert `mock.nextAttemptCalls == 0`.

    - Test 4 (`test_disconnectButNoUserIntent_noFailover`):
      Set userIntent(false); even with stable session, emit .disconnected. Yield. Assert `mock.nextAttemptCalls == 0`.

    - Test 5 (`test_debounceCancelledByReconnect`):
      Set userIntent + stable. Emit .disconnected. Before debounce expires (instant clock — но мы можем check `getDebounceActiveForTest() == true`), emit .connecting. Yield. Assert `mock.nextAttemptCalls == 0` AND `getDebounceActiveForTest() == false`.

    - Test 6 (`test_userIntentFalseResetsState`):
      Set userIntent(true); emit .connected; await stableSession. Set userIntent(false). Assert `getStableSessionForTest() == false`.

    - Test 7 (`test_failoverNextNil_noAttemptExecuted`):
      Set userIntent + stable. `mock.nextResult = nil`. Emit .disconnected. Yield. Assert `mock.nextAttemptCalls == 1` (вызов был сделан), but no crash and attempt closure never executed.

    - Test 8 (`test_failoverNextNonNil_attemptInvoked`):
      Set userIntent + stable. Mock failover returns attempt closure that increments local counter. Emit .disconnected. Yield. Assert counter == 1.

    - **Test 9 (`test_debounceCancelledByReasserting`)** — NEW Round 2 for W-05:
      Mirror of Test 5 but uses `.reasserting` instead of `.connecting`. Set userIntent + stable. Emit
      `.disconnected`. Before debounce expires (check `getDebounceActiveForTest() == true`), emit `.reasserting`.
      Yield. Assert `mock.nextAttemptCalls == 0` AND `getDebounceActiveForTest() == false`. Specifically
      validates W-05 expansion: `.reasserting` now cancels debounce (Round 1 only cancelled on `.connecting`/`.connected`).

    Critical:
    - Все тесты с `InstantReconnectClock` (instant yields), wallclock-free.
    - Helper `waitUntil` pattern из TunnelControllerStateTests.swift (1000 yields with predicate check) — reuse.
    - НИКАКИХ tests с реальным `NETunnelProviderManager` — все aspects тестируются через method args.
  </behavior>
  <action>
    RED first. Создать `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift` с 8 методами.

    Затем создать `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift`:

    1. Header doc-comment на русском: D-08, D-09, D-10, Pitfall 5, Pitfall 10. Объяснение почему watchdog параллелен Apple's on-demand (mid-session «сервер умер» — Apple retry same dead server, мы swap к next).
    2. `import Foundation`, `import NetworkExtension`, `import OSLog`.
    3. Use **extracted** `ReconnectClock` protocol from `ReconnectClock.swift` (Round 2 B-01 — extracted в Task 2.5 этого плана). НЕ дублировать. Same module (MainScreenFeature) → нет import statements нужно.
    4. `public actor TunnelWatchdog`:
       - Stored properties по списку behavior.
       - `failoverProvider` храним как `weak` через wrapper closure ИЛИ как strong `any FailoverProviding` (in test mocks actor reference stays alive; в production app holds the actor lifecycle). Решение: strong (без weak) — TunnelWatchdog имеет конкретный lifecycle, удаляется вместе с TunnelController. Эта design слабее по cycle prevention, но FailoverProvider сам имеет `[weak controller]` в своих closures (D-16 preserved).
       - Если cycle concerns: actor-actor cycle уже разрешён в FailoverProvider design (см. SwiftDataFailoverProvider — `[weak tunnelController]` в `connect` closure). Watchdog → failoverProvider strong → внутри failoverProvider → `[weak controller]` — нет cycle.
       - init(...) сохраняет params.
       - `handleStatusChange(_:managerEnabled:)` — switch по status, body per behavior.
       - `setUserIntent(_:)` — body per behavior.
       - Private helpers: `private func scheduleStableSessionTask()`, `private func fireFailover() async`.

    Запустить тесты — должны pass.

    Edge cases:
    - `Task.sleep` cancellation throwing CancellationError — обернуть в `try? await clock.sleep(seconds: ...)` чтобы кэнсел не shall down логи.
    - Reordering статусов из-за `Task { await self?.handle... }` в observer — не наша проблема (актора FIFO внутри). Tests sequence emit, потом yield → OK.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter TunnelWatchdogTests</automated>
  </verify>
  <acceptance_criteria>
    - **9 тестов** TunnelWatchdogTests pass (Round 2: was 8, +1 для W-05 `.reasserting` cancellation).
    - `grep -c "stableSession" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 2.
    - `grep -c "disconnectDebounce" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 1.
    - `grep -c "loadAllFromPreferences\\|connection.status" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns 0 (XPC-free invariant — все статусы приходят как parameters).
    - `grep -c "public actor TunnelWatchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns 1.
    - **`grep -c "ReconnectClock\\|SystemReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 2** (Round 2 B-01: uses extracted types, no redeclaration).
    - **`grep -cE "case \\.reasserting" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 1** (W-05: explicit handling).
    - **`grep -c "InstantReconnectClock" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift` returns ≥ 1** (Round 2 B-02: uses extracted helper).
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
    - Полная AppFeatures test-сюита green.
    - НЕТ wiring watchdog в TunnelController в этой wave — `grep -c "TunnelWatchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0 (Wave 3 / Plan 06C-04 делает wiring).
  </acceptance_criteria>
  <done>TunnelWatchdog существует с **9** проходящими тестами (Round 2: +1 W-05); XPC-free hot path; gate'ы (stable session / userIntent / managerEnabled) работают; debounce защищает от Apple's on-demand reconnect race (cancellation на .connected/.connecting/.reasserting). Uses extracted `ReconnectClock` (B-01) + `InstantReconnectClock` (B-02). Wiring в TunnelController — Wave 3.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| UI (SwiftUI Form) ↔ SettingsViewModel | Bound through @AppStorage / Binding; toggle changes propagate to UserDefaults. |
| SettingsViewModel ↔ NETunnelProviderManager.saveToPreferences | Single XPC trip per toggle change; ошибки swallowed (state recovers on next provisionTunnelProfile). |
| OnDemandMigrationTask ↔ NETunnelProviderManager (first launch) | One-time XPC at app init; failure → retry next launch. |
| TunnelWatchdog ↔ FailoverProvider | actor-to-actor; failover holds `[weak controller]` to break cycle (per SwiftDataFailoverProvider D-16). |
| NEVPNStatusDidChange observer ↔ TunnelWatchdog | Status passed as argument (no XPC inside watchdog). Apple's on-demand may double-trigger same .disconnected — debounce (3s) wins the race. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06C-03-01 | DoS | Toggle spam by user causes saveToPreferences loop | accept | Single XPC per toggle; SwiftUI animations debounce visual taps. Worst-case 1-2 XPC trips per user gesture (acceptable). |
| T-06C-03-02 | Tampering | UserDefaults toggle value externally mutated | mitigate | Sandbox-protected per app; @AppStorage reads Bool — non-Bool falls through to default true (D-04). |
| T-06C-03-03 | DoS | Watchdog double-fires failover on transient `.disconnected` | mitigate | 3-second debounce per Pitfall 10. Apple's on-demand reconnect window covered. |
| T-06C-03-04 | Tampering | TunnelWatchdog observed-status manipulated to spoof failover | accept | Observer reads `notification.object` (synchronous NEVPNConnection.status); no untrusted input path; sandboxed Mach msg. |
| T-06C-03-05 | DoS | Migration task fails repeatedly each launch | mitigate | Failed migration logs error AND keeps flag false → retry next launch. If repeated failure: existing manager unchanged (Phase 6 state preserved). UAT-Task B in Wave 3 verifies first-launch migration success. |
| T-06C-03-06 | Information Disclosure | Watchdog logs may include server names | accept | OSLog `notice` уровень с serverName privacy `.public` — server names are non-secret (user already added them). |
</threat_model>

<verification>
- Compile: `cd BBTB && swift build --package-path Packages/AppFeatures`
- **B-09 (Round 2):** `grep -A 5 'name: "SettingsFeature"' BBTB/Packages/AppFeatures/Package.swift | grep -c "MainScreenFeature"` returns ≥ 1.
- **B-01 (Round 2):** `test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` (file exists).
- **B-02 (Round 2):** `test -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` (file exists).
- Settings tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter SettingsViewModelAutoReconnectTests` (4 pass).
- Migration tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandMigrationTaskTests` (**5 pass** — Round 2: was 4, +1 for B-05).
- Watchdog tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter TunnelWatchdogTests` (**9 pass** — Round 2: was 8, +1 for W-05).
- Full regression: `cd BBTB && swift test --package-path Packages/AppFeatures` ВСЕЙ сюиты green — особенно TunnelControllerStateTests все ещё проходит after Task 2.5 extracts.
- Localization sanity: `grep -A 2 "settingsAutoReconnectFooter" BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings | grep -E "ru|en"` returns both ru and en blocks.
- Pitfall 4 invariant: `grep -c "stopVPNTunnel" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns 0 (toggle OFF does NOT tear down).
- Pitfall 10 invariant: `grep -c "disconnectDebounce" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 1.
- W-05 invariant: `grep -cE "case \\.reasserting" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 1.
- W-03 invariant: `grep -c "nonisolated" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns ≥ 1.
- W-04 invariant: `grep -c "applyCurrentState" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 2 (one per consumer).
- B-05 invariant: `grep -cE "try\\? await" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 0 (replaced с explicit do/catch).
- B-06 invariant: `grep -c "ManagerSelector.ourManagers" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 2.
- D-17b/c invariant: `grep -c "autoReconnectMigratedV6c" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 1.
- Parallel-run invariant: `grep -c "TunnelWatchdog\\|OnDemandMigrationTask" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0 (НЕТ wiring в Wave 2).
- B-01 invariant: `grep -c "protocol ReconnectClock" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` returns 0 (moved out).
- B-02 invariant: `grep -c "private.*actor InstantReconnectClock" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` returns 0 (moved out).
</verification>

<success_criteria>
1. SettingsViewModel имеет `autoReconnectEnabled` @AppStorage с default true + **nonisolated** `applyAutoReconnectToManager()` helper (W-03).
2. SettingsView рендерит новый раздел «Подключение» с переключателем + footer на ru + en (Localization).
3. Toggle change live-applies к manager через **`OnDemandRulesBuilder.applyCurrentState`** (Round 2 W-04 — single source of truth) + ManagerSelector iteration (B-06) + save + reload + post `.bbtbProvisionerDidSave` (B-03) — без tear-down активного туннеля (Pitfall 4).
4. SettingsFeature Package.swift target deps включает `MainScreenFeature` (Round 2 B-09 — explicit).
5. `OnDemandMigrationTask.runIfNeeded` идемпотентный, безопасный для fresh + existing installs, защищён UserDefaults flag. **Round 2:** transient XPC failure НЕ выставляет flag (B-05); multi-manager safe (B-06); applyCurrentState consumer (W-04); постит bbtbProvisionerDidSave после batch (B-03).
6. `TunnelWatchdog` actor с 4 stateful gates (stable session, user intent, manager enabled, debounce); **9 тестов pass** (Round 2: was 8, +1 W-05); uses extracted `ReconnectClock` (B-01).
7. **(Round 2 Task 2.5)** ReconnectClock + SystemReconnectClock extracted в `ReconnectClock.swift` (B-01); InstantReconnectClock extracted в `TestClocks.swift` (B-02). Parallel-run invariant сохранён — `ReconnectStateMachine.swift` + `TunnelControllerStateTests.swift` файлы остаются (Plan 04 Task 3c удалит).
8. Никакого wiring watchdog в TunnelController, никакого wiring migration task в App — Wave 3 это делает.
9. **4+5+9 = 18 новых тестов pass** (Round 2: was 16, +2 — B-05 migration test + W-05 reasserting test); полная AppFeatures suite green.
10. Все existing source files (TunnelController.swift, NetworkReachability.swift) не modified — strict parallel-run invariant. ReconnectStateMachine.swift modified только в Task 2.5 (extracted types removed, class body untouched).
11. Pitfall 1, 4, 5, 8, 9, 10 — explicitly mitigated по reference в коде.
12. CLAUDE.md соблюдён: doc-comments на русском, identifiers на английском, ru/en localization parity.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-03-SUMMARY.md`. Include:
- Files created/modified с line counts (Round 2 NEW: ReconnectClock.swift, TestClocks.swift; Round 2 MODIFIED: ReconnectStateMachine.swift [extract only], TunnelControllerStateTests.swift [extract only], Package.swift [SettingsFeature dep]).
- Test counts (Round 2): 4 (Settings) + 5 (Migration) + 9 (Watchdog) = **18 new** (was 16, +2 в Round 2).
- Confirmation: full AppFeatures suite green — особенно TunnelControllerStateTests все ещё проходит after extracts.
- Confirmation: TunnelController.swift UNCHANGED (parallel-run invariant); ReconnectStateMachine class body UNCHANGED (только extracted types removed).
- Confirmation: Round 2 fixes landed:
  - B-01: ReconnectClock + SystemReconnectClock extracted.
  - B-02: InstantReconnectClock extracted (internal).
  - B-05: explicit do/catch in migration; flag NOT set on transient throw.
  - B-06: ManagerSelector.ourManagers used in toggle + migration.
  - B-09: Package.swift SettingsFeature → MainScreenFeature dep explicit.
  - W-03: applyAutoReconnectToManager nonisolated.
  - W-04: applyCurrentState single source of truth (no wrapper).
  - W-05: debounce cancellation extended to .reasserting.
- Localization strings added (3 new keys × 2 locales = 6 entries).
- Reference: D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-17b, D-17c, B-01, B-02, B-03, B-04, B-05, B-06, B-09, W-03, W-04, W-05, Pitfall 1, 4, 5, 8, 9, 10.
- Note for Plan 06C-04 (Wave 3 cleanup):
  - Wire `OnDemandMigrationTask.runIfNeeded()` в App init Task (BBTB_iOSApp + BBTB_macOSApp).
  - Wire `TunnelWatchdog` в TunnelController; cachedManager + bbtbProvisionerDidSave observer для B-03 fix.
  - Task 3 split into 3a/3b/3c per W-01.
  - Delete: ReconnectStateMachine.swift (но `ReconnectClock.swift` SURVIVES — Round 2 B-01 contract), NetworkReachability.swift, related tests, TunnelControllerStateTests.swift (но `TestClocks.swift` SURVIVES — Round 2 B-02 contract), custom-reconnect branches в TunnelController.
  - Preserve: macOS `NSWorkspace.didWakeNotification` observer (D-11/12/13) с 3 guards (W-06).
  - Banner enum trim + audit (W-02).
- Note for UAT (Plan 06C-04): Pitfall 5 race (watchdog vs Apple's on-demand) requires explicit device test — UAT-Task E. Hard-blocker UAT set per B-10: {A, C, E, F, G, I}.
</output>
