---
phase: 06c-on-demand-migration
plan: 03
type: execute
wave: 3
depends_on: ["06c-on-demand-migration:02"]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift
  - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift
  - BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift
autonomous: true
requirements: [NET-08, NET-09, NET-10, NET-11]
must_haves:
  truths:
    - "Settings showcases новый раздел «Подключение» с переключателем «Автоматическое переподключение» (D-04, D-07)"
    - "Toggle persists через UserDefaults `app.bbtb.autoReconnectEnabled` с default ON (D-05)"
    - "Toggle change live-применяется к manager: загрузить → OnDemandRulesBuilder.apply → save → reload (D-06)"
    - "Toggle OFF при активном туннеле НЕ tear down туннель — Apple's default behavior, footer текст это коммуницирует (OQ-4 / Pitfall 4)"
    - "OnDemandMigrationTask запускается в App init и идемпотентен: на первый запуск Phase 6c build при наличии существующего manager — применяет on-demand rules + isOnDemandEnabled per current toggle, ставит флаг `app.bbtb.autoReconnectMigratedV6c` = true (D-17b/c, Pitfall 1)"
    - "TunnelWatchdog actor реагирует на NEVPNStatusDidChange ТОЛЬКО при: stable session ≥ 30s + status .disconnected + managerEnabled snapshot + userIntent true (D-08)"
    - "TunnelWatchdog при срабатывании вызывает SwiftDataFailoverProvider.nextServerAttempt + выполняет returned attempt closure (D-09)"
    - "TunnelWatchdog добавляет 3-секундный debounce после `.disconnected` чтобы Apple's on-demand успел сам reconnect (Pitfall 10) — failover отменяется если status вернулся в .connecting/.connected"
    - "Wave 2 НЕ удаляет ReconnectStateMachine, NetworkReachability, существующие custom-reconnect ветки в TunnelController — это Wave 3"
  artifacts:
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
      provides: "static func runIfNeeded() — idempotent existing-install migration (D-17b/c)"
      min_lines: 50
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift"
      provides: "actor TunnelWatchdog with handleStatusChange(_:managerEnabled:) + setUserIntent(_:)"
      min_lines: 100
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift"
      provides: "Idempotency + UserDefaults flag tests"
      min_lines: 80
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift"
      provides: "8 gate tests (stable-session, managerEnabled, userIntent, debounce)"
      min_lines: 150
    - path: "BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift"
      provides: "Toggle persistence + default ON tests"
      min_lines: 60
  key_links:
    - from: "SettingsView Раздел «Подключение»"
      to: "SettingsViewModel.autoReconnectEnabled"
      via: "@AppStorage binding"
      pattern: "AutoReconnectToggleSection"
    - from: "SettingsViewModel.autoReconnectEnabled didSet"
      to: "OnDemandRulesBuilder.apply + manager.saveToPreferences"
      via: "applyAutoReconnectToManager async"
      pattern: "applyAutoReconnectToManager"
    - from: "App init (iOSApp + macOSApp)"
      to: "OnDemandMigrationTask.runIfNeeded"
      via: "Task at app startup"
      pattern: "OnDemandMigrationTask\\.runIfNeeded"
    - from: "TunnelWatchdog.handleStatusChange"
      to: "FailoverProviding.nextServerAttempt"
      via: "weak reference, no XPC in hot path"
      pattern: "nextServerAttempt"
---

<objective>
Wave 2 / Migration + UI + Watchdog — Покрыть пять блоков локированных decisions, которые завершают «parallel run» state с пользовательской видимостью toggle и mid-session failover safety:

1. **Toggle UI** (D-04/D-05/D-06/D-07) — раздел «Подключение» в Settings → переключатель «Автоматическое переподключение» с live-apply на manager.
2. **Migration of existing installs** (D-17b/c, Pitfall 1) — один-shot idempotent task на app init: если `NETunnelProviderManager` существует и `isOnDemandEnabled == false` — применить on-demand rules с current toggle, поставить flag «migrated».
3. **Mid-session watchdog** (D-08/D-09/D-10) — узко-целевой actor реагирующий на `.disconnected` после stable session, fires failover к следующему серверу через `SwiftDataFailoverProvider` (preserved).
4. **macOS wake observer pattern documentation** — текущий wake observer в TunnelController уже соответствует D-11/D-12/D-13 (`startVPNTunnel()` идемпотентный nudge). Мы не дублируем его в этой wave; Wave 3 при cleanup TunnelController сохранит этот специфический фрагмент.
5. **Localization** — добавить 2 строки в `Localizable.xcstrings`: title + footer toggle на ru + en.

**Это всё ещё parallel-run wave.** Старая custom-reconnect machinery (ReconnectStateMachine, NetworkReachability, NEVPNStatusDidChange recovery branches) ПРОДОЛЖАЕТ работать. Watchdog запускается **в дополнение**, не вместо них. После UAT в Wave 3 (Plan 06C-04) мы будем DELETE старые компоненты. Параллельно работающие custom + watchdog могут двукратно вызывать failover на тот же `.disconnected` — это известный risk (Pitfall 5 в RESEARCH), accepted на этой wave; UAT в Wave 3 проверит manifest.

Purpose:
- D-17b/c (migration): без этого пользователи апгрейднувшиеся с Phase 6 видят toggle ON в UI, но manager в реальности не имеет on-demand rules — UX-regression.
- D-08 (watchdog): Apple's on-demand попробует ТОТ ЖЕ (теперь dead) сервер; watchdog знает что сервер dead и переключает на next через round-robin SwiftDataFailoverProvider.
- D-04..D-07 (UI): пользователь видит и контролирует поведение auto-reconnect; default ON для безшовного UX.

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
<!-- Builder from Plan 06C-01: -->
```swift
public enum OnDemandRulesBuilder {
    public static func apply(to manager: NETunnelProviderManager, autoReconnectEnabled: Bool)
    public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard,
                                                key: String = "app.bbtb.autoReconnectEnabled") -> Bool
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

<!-- TunnelWatchdog API contract (Plan 06C-03 introduces): -->
```swift
public actor TunnelWatchdog {
    public init(failoverProvider: any FailoverProviding,
                stableSessionThreshold: TimeInterval = 30,
                disconnectDebounce: TimeInterval = 3,
                clock: ReconnectClock = SystemReconnectClock())
    public func handleStatusChange(_ status: NEVPNStatus, managerEnabled: Bool) async
    public func setUserIntent(_ intent: Bool) async
}
```
- `ReconnectClock` уже существует в `ReconnectStateMachine.swift` — reuse этот тип (don't define another).

<!-- Watchdog logic (from RESEARCH Pattern 3 + Pitfall 10): -->
<!-- - .connected → schedule task; after stable threshold (30s), mark stableSession = true -->
<!-- - .disconnected → if stableSession && userIntent && managerEnabled: -->
<!--     - schedule debounce task (3s sleep) -->
<!--     - after debounce, check status STILL .disconnected (re-passed via Watchdog state — see Task 2 design) -->
<!--     - if yes: call failoverProvider.nextServerAttempt; execute attempt closure -->
<!-- - any non-.disconnected during debounce → cancel debounce task, don't fire -->
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
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift полностью
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift полностью
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift полностью (pattern reference)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (созданный в Plan 06C-01)
    - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings первые 200 строк — найти как формируются ключи (`settingsKillSwitchFooter`, `settingsSecuritySection`)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pattern 2: Toggle live-apply через handleUserDefaultsChange» и Pitfall 4
  </read_first>
  <behavior>
    SettingsViewModel.autoReconnectEnabled API (locked):
    ```swift
    @AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true
    ```
    @AppStorage default `true` — соответствует D-04 default ON. (Note: @AppStorage default value возвращается только если ключ ещё не записан; после первого toggle off + back on UserDefaults значение persists.)

    Live-apply helper:
    ```swift
    /// Phase 6c / D-06 — apply toggle change to existing NETunnelProviderManager.
    /// Single XPC trip per toggle press (NOT observer hot path).
    /// Не tear down active tunnel при toggle OFF (Pitfall 4) — Apple's default behavior.
    public func applyAutoReconnectToManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let manager = managers.first else { return }
            OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: autoReconnectEnabled)
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()  // RESEARCH §9.1
        } catch {
            // Логируем; флаг в UserDefaults уже записан @AppStorage; on next provisionTunnelProfile
            // builder подхватит fresh value
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
    - Live-apply wire-up в View: `.onChange(of: viewModel.autoReconnectEnabled) { Task { await viewModel.applyAutoReconnectToManager() } }`. Этот modifier ставится на корень `Form` чтобы не повторять для каждой section.

    Localization (3 new keys):
    - `settingsConnectionSection`: ru="Подключение", en="Connection"
    - `settingsAutoReconnectTitle`: ru="Автоматическое переподключение", en="Auto-reconnect"
    - `settingsAutoReconnectFooter`: ru="Восстанавливать соединение при смене сети или после сна. Если выключено — после обрыва нужно подключиться вручную.", en="Restore the connection on network change or after wake. When disabled, you must reconnect manually after a drop."

    L10n key access pattern (как для existing keys): `L10n.settingsConnectionSection`. Если в проекте используется SwiftGen или ручной enum — следовать существующему pattern (читать `Localization.swift` или сгенерированный файл).
  </behavior>
  <action>
    Implement в порядке: tests FIRST → ViewModel + helper → UI Section component → SettingsView wire-up → Localization keys.

    1. Создать `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelAutoReconnectTests.swift` с 4 методами по списку выше. RED state ожидается (autoReconnectEnabled не существует).
       - Если `SettingsFeatureTests` directory не существует — создать в Package.swift соответствующий test target. Проверить existing test targets для SettingsFeature (вероятно SettingsViewModelDNSTests.swift существует — он покажет structure).

    2. Modify `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift`:
       - Добавить `import NetworkExtension`.
       - Добавить `@AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true` сразу под существующими @AppStorage свойствами.
       - Добавить `public func applyAutoReconnectToManager() async` с body как в behavior выше. Использует `OnDemandRulesBuilder` — добавить `import MainScreenFeature` если требуется (или MainScreenFeature должен экспортировать `OnDemandRulesBuilder` для cross-module use; проверить existing dependency между SettingsFeature и MainScreenFeature в Package.swift — добавить depends_on если не было).
       - Doc-comment на русском с reference на D-04, D-06, Pitfall 4.
       - Запустить тесты — должны pass.

    3. Создать `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AutoReconnectToggleSection.swift` — mirror KillSwitchToggleSection:
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

    4. Modify `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift`:
       - Добавить новую Section с AutoReconnectToggleSection ПЕРЕД секцией Безопасность (KillSwitch).
       - Добавить .onChange modifier на Form для live-apply (см. behavior выше).
       - Сохранить весь существующий код без regression.

    5. Modify `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`:
       - JSON-сlovak modification: добавить 3 новых key entries по pattern существующих (например `settingsKillSwitchFooter` — найти его блок и сшаблонировать).
       - Each key has `ru` + `en` localizations.
       - Использовать exact ru/en тексты из секции behavior выше.

    6. Если в проекте есть auto-generated L10n.swift / Strings.swift — может потребоваться запустить SwiftGen / build чтобы L10n.settingsConnectionSection стала доступна. Проверить через `grep -rn "L10n.settingsKillSwitch" BBTB/` — увидеть как existing keys генерируются.

    Final: `swift test --package-path BBTB/Packages/AppFeatures` full suite green.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter SettingsViewModelAutoReconnectTests && swift build --package-path Packages/AppFeatures</automated>
  </verify>
  <acceptance_criteria>
    - 4 теста SettingsViewModelAutoReconnectTests pass.
    - `grep -c "autoReconnectEnabled" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns ≥ 2 (declaration + apply helper).
    - `grep -c "app.bbtb.autoReconnectEnabled" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns ≥ 1.
    - `grep -c "OnDemandRulesBuilder.apply" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns 1.
    - `grep -c "AutoReconnectToggleSection" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` returns ≥ 1.
    - `grep -c "settingsConnectionSection\\|settingsAutoReconnectTitle\\|settingsAutoReconnectFooter" BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` returns ≥ 3.
    - `grep -c "Автоматическое переподключение" BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` returns ≥ 1.
    - `cd BBTB && swift test --package-path Packages/AppFeatures` full suite green (regression-safe).
    - No tear-down behavior added (отсутствует `stopVPNTunnel` в applyAutoReconnectToManager — Pitfall 4).
  </acceptance_criteria>
  <done>Toggle UI существует в Settings → раздел «Подключение». Default ON. Live-applies single XPC trip per change. Localization добавлена для ru + en.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: OnDemandMigrationTask — idempotent one-shot migration для existing installs</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (Plan 06C-01)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pitfall 1» (полностью) + «Code Examples» Example 5 (migrateExistingManagerForOnDemand recipe)
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md D-17b, D-17c
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

    Logic:
    1. Если `userDefaults.bool(forKey: migratedKey) == true` → return (already done).
    2. `let managers = try? await NETunnelProviderManager.loadAllFromPreferences() ?? []`.
    3. Если `managers.isEmpty` — fresh install с ещё-не-импортированным config'ом. **Тоже set flag** = true и return: для fresh install миграция не нужна (ConfigImporter Plan 06C-02 пишет on-demand на первый import). Это критическая идемпотентность invariant.
    4. Если manager.first существует:
       - `let enabled = OnDemandRulesBuilder.loadAutoReconnectEnabled(userDefaults: userDefaults)`.
       - `OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: enabled)`.
       - `try? await manager.saveToPreferences()`.
       - Если save threw → НЕ set flag (retry next launch). Если success → set flag = true.
       - `try? await manager.loadFromPreferences()` (RESEARCH §9.1).

    Тесты (OnDemandMigrationTaskTests.swift):
    - Test 1 (`test_runIfNeeded_alreadyMigrated_isNoOp`): fresh suite, set `migratedKey = true`. Call `runIfNeeded(userDefaults: ud)`. Assert: no error, flag still true. (No manager access can be asserted because UserDefaults stays clean — нет других ключей записанных.)
    - Test 2 (`test_runIfNeeded_freshInstallNoManager_setsFlag`): fresh suite (migratedKey absent). Call `runIfNeeded(userDefaults: ud)`. В test env `loadAllFromPreferences()` returns empty или throws — оба пути приводят к flag = true. Assert: `ud.bool(forKey: "app.bbtb.autoReconnectMigratedV6c") == true`.
    - Test 3 (`test_runIfNeeded_isIdempotent_twoCallsSafe`): fresh suite. Call twice. Assert: flag true; no crash.
    - Test 4 (`test_runIfNeeded_respectsTogglePersisted`): fresh suite. Set `ud.set(false, forKey: "app.bbtb.autoReconnectEnabled")`. Call `runIfNeeded`. (В test env миграция дойдёт до проверки manager — пустого пула — и засетит flag = true.) Assert: flag true; toggle value НЕ changed (`ud.bool(forKey: "app.bbtb.autoReconnectEnabled") == false`).

    Notes для test env:
    - `NETunnelProviderManager.loadAllFromPreferences()` в `swift test` без entitlements **throws** — нормальное поведение. Migration task должна catch this gracefully.
    - Тесты НЕ проверяют что manager properties applied — это сделать без entitlements нельзя. Тесты проверяют:
      (a) Flag setting behavior (idempotency).
      (b) UserDefaults toggle не изменяется при migration.
      (c) Crash-free.
    - Эти guarantee'и достаточны — фактический apply path проверен в OnDemandRulesBuilderTests Plan 06C-01.

    Decision: behavior #3 above («fresh install, empty managers → set flag = true») — это сознательное упрощение. Альтернатива: «не set flag, попробовать снова next launch». Простота preferred — fresh install после first config import уже получит on-demand через ConfigImporter Plan 06C-02 wiring.
  </behavior>
  <action>
    Сначала RED тесты в `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandMigrationTaskTests.swift` с 4 методами.

    Затем создать `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift`:

    1. Header doc-comment на русском: ссылка на Phase 6c / Plan 06C-03 / D-17b / D-17c / Pitfall 1; объяснение зачем нужна migration; idempotency invariant; «failure → no flag, retry next launch».
    2. `import Foundation`, `import NetworkExtension`, `import OSLog`.
    3. `public enum OnDemandMigrationTask`:
       - `private static let migratedKey = "app.bbtb.autoReconnectMigratedV6c"`.
       - `private static let log = Logger(subsystem: "app.bbtb.client", category: "ondemand-migration")`.
       - `public static func runIfNeeded(userDefaults: UserDefaults = .standard) async`:
         - Check flag → if true, log debug, return.
         - Try `loadAllFromPreferences()`. Если throws — log warn, set flag = true (fresh install proxy), return.
         - Если managers.isEmpty — log notice «no manager — fresh install, marking migration done», set flag = true, return.
         - Else:
           - apply builder с current toggle.
           - try save; loadFromPreferences.
           - На success: set flag = true, log notice «migration applied».
           - На failure: log error, DO NOT set flag (retry next launch).

    Запустить tests — все 4 pass.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandMigrationTaskTests</automated>
  </verify>
  <acceptance_criteria>
    - 4 теста OnDemandMigrationTaskTests pass.
    - `grep -c "autoReconnectMigratedV6c" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 1.
    - `grep -c "OnDemandRulesBuilder.apply\\|OnDemandRulesBuilder.loadAutoReconnectEnabled" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 2.
    - `grep -c "loadAllFromPreferences" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 1.
    - `grep -c "public enum OnDemandMigrationTask" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns 1.
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
    - Full AppFeatures test suite green.
  </acceptance_criteria>
  <done>OnDemandMigrationTask существует, идемпотентный, безопасный для fresh + existing installs. Wave 3 (Plan 06C-04) wire это в App entry points.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: TunnelWatchdog actor — mid-session failover с 30s stable session gate + 3s debounce</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelWatchdogTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (полностью — для conventions, особенно lines 380-410 NEVPN observer pattern XPC-free)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift (полностью — нужный FailoverProviding contract)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift строки 1-50 (для ReconnectClock protocol reuse — НЕ создавать дубль)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pattern 3: Watchdog observer (D-08)» полностью + Pitfall 5 + Pitfall 10
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md D-08, D-09, D-10
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

    `handleStatusChange(.connecting | .reasserting | ...)`:
    - Cancel debounceTask (если активна) — Apple's on-demand reconnect выиграл race; не fire failover.
    - Не reset stableSession (это transient state, не loss-of-session).

    Tests (TunnelWatchdogTests.swift):

    Use `InstantReconnectClock` (test seam yielding immediately, with `recordedSleeps: [TimeInterval]` для verification). Pattern уже established в `TunnelControllerStateTests.swift` (см. lines 56-62 для example).

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
    3. Use **existing** `ReconnectClock` protocol from `ReconnectStateMachine.swift` (НЕ дублировать). Если SwiftPM module visibility требует — можно re-export, но желательно через прямой import одного и того же модуля.
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
    - 8 тестов TunnelWatchdogTests pass.
    - `grep -c "stableSession" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 2.
    - `grep -c "disconnectDebounce" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 1.
    - `grep -c "loadAllFromPreferences\\|connection.status" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns 0 (XPC-free invariant — все статусы приходят как parameters).
    - `grep -c "public actor TunnelWatchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns 1.
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
    - Полная AppFeatures test-сюита green.
    - НЕТ wiring watchdog в TunnelController в этой wave — `grep -c "TunnelWatchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0 (Wave 3 / Plan 06C-04 делает wiring).
  </acceptance_criteria>
  <done>TunnelWatchdog существует с 8 проходящими тестами; XPC-free hot path; gate'ы (stable session / userIntent / managerEnabled) работают; debounce защищает от Apple's on-demand reconnect race. Wiring в TunnelController — Wave 3.</done>
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
- Settings tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter SettingsViewModelAutoReconnectTests` (4 pass).
- Migration tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandMigrationTaskTests` (4 pass).
- Watchdog tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter TunnelWatchdogTests` (8 pass).
- Full regression: `cd BBTB && swift test --package-path Packages/AppFeatures` ВСЕЙ сюиты green.
- Localization sanity: `grep -A 2 "settingsAutoReconnectFooter" BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings | grep -E "ru|en"` returns both ru and en blocks.
- Pitfall 4 invariant: `grep -c "stopVPNTunnel" BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` returns 0 (toggle OFF does NOT tear down).
- Pitfall 10 invariant: `grep -c "disconnectDebounce" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 1.
- D-17b/c invariant: `grep -c "autoReconnectMigratedV6c" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` returns ≥ 1.
- Parallel-run invariant: `grep -c "TunnelWatchdog\\|OnDemandMigrationTask" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0 (НЕТ wiring в Wave 2).
</verification>

<success_criteria>
1. SettingsViewModel имеет `autoReconnectEnabled` @AppStorage с default true + async `applyAutoReconnectToManager()` helper.
2. SettingsView рендерит новый раздел «Подключение» с переключателем + footer на ru + en (Localization).
3. Toggle change live-applies к manager через `OnDemandRulesBuilder.apply` + save + reload — без tear-down активного туннеля (Pitfall 4).
4. `OnDemandMigrationTask.runIfNeeded` идемпотентный, безопасный для fresh + existing installs, защищён UserDefaults flag.
5. `TunnelWatchdog` actor с 4 stateful gates (stable session, user intent, manager enabled, debounce); 8 тестов pass.
6. Никакого wiring watchdog в TunnelController, никакого wiring migration task в App — Wave 3 это делает.
7. 4+4+8 = 16 новых тестов pass; полная AppFeatures suite green.
8. Все existing files (TunnelController.swift, ReconnectStateMachine.swift, NetworkReachability.swift) не modified — strict parallel-run invariant.
9. Pitfall 1, 4, 5, 8, 9, 10 — explicitly mitigated по reference в коде.
10. CLAUDE.md соблюдён: doc-comments на русском, identifiers на английском, ru/en localization parity.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-03-SUMMARY.md`. Include:
- Files created/modified с line counts.
- Test counts: 4 (Settings) + 4 (Migration) + 8 (Watchdog) = 16 new.
- Confirmation: full AppFeatures suite green.
- Confirmation: TunnelController.swift UNCHANGED (parallel-run invariant).
- Localization strings added (3 new keys × 2 locales = 6 entries).
- Reference: D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-17b, D-17c, Pitfall 1, 4, 5, 8, 9, 10.
- Note for Plan 06C-04 (Wave 3 cleanup):
  - Wire `OnDemandMigrationTask.runIfNeeded()` в App init Task (BBTB_iOSApp + BBTB_macOSApp).
  - Wire `TunnelWatchdog` в TunnelController вместо ReconnectStateMachine.
  - Delete: ReconnectStateMachine.swift, NetworkReachability.swift, related tests, custom-reconnect branches в TunnelController.
  - Preserve: macOS `NSWorkspace.didWakeNotification` observer (D-11/12/13 — already correct pattern).
- Note for UAT (Plan 06C-04): Pitfall 5 race (watchdog vs Apple's on-demand) requires explicit device test — UAT-Task E.
</output>
