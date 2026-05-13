---
phase: 06c-on-demand-migration
plan: 02
type: execute
wave: 2
depends_on: ["06c-on-demand-migration:01"]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift
autonomous: true
requirements: [NET-08, NET-09, NET-10]
must_haves:
  truths:
    - "ManagerSelector.ourManagers(from:) helper существует в MainScreenFeature и фильтрует [NETunnelProviderManager] по providerBundleIdentifier ∈ {app.bbtb.client.ios.tunnel, app.bbtb.client.macos.tunnel} — single source of truth для всех 5 callsites (B-06 + W-07)"
    - "DefaultTunnelProvisioner.provisionTunnelProfile использует ManagerSelector.ourManagers(from:).first ?? NETunnelProviderManager() (вместо managers.first) — корректное поведение при наличии нескольких manager'ов от разных приложений или после re-import (B-06)"
    - "DefaultTunnelProvisioner.provisionTunnelProfile вызывает OnDemandRulesBuilder.applyCurrentState(to: manager) перед saveToPreferences — единый source of truth (W-04 / B-04): gate = toggle AND userIntent. Свежая установка без Connect → isOnDemandEnabled = false (нет phantom auto-connect)"
    - "ПОСЛЕ saveToPreferences + loadFromPreferences provisioner постит NotificationCenter notification `Notification.Name.bbtbProvisionerDidSave` — TunnelController наблюдает это для refresh cachedManager (B-03 cross-plan contract)"
    - "Каждый import нового конфига (initial + re-import) пишет on-demand rules согласованные с current toggle И user intent (Pitfall 9 mitigation + B-04 phantom-connect mitigation)"
    - "OnDemandRulesBuilder.applyCurrentState вызывается ПОСЛЕ KillSwitch.apply, но ДО saveToPreferences — порядок не имеет функционального значения, но фиксируется для читаемости"
    - "Ни один существующий test в ConfigImporter* test-файлах не падает после wiring (parallel-run: старая custom-reconnect machinery в TunnelController ПРОДОЛЖАЕТ работать)"
    - "Wave 1 НЕ удаляет ReconnectStateMachine, NetworkReachability, custom flags в TunnelController — это Wave 3"
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift"
      provides: "enum ManagerSelector.ourManagers(from:knownBundleIDs:) — filters [NETunnelProviderManager] by provider bundle ID; default ourProviderBundleIdentifiers Set covers iOS + macOS targets"
      min_lines: 30
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift"
      provides: "3 unit tests: empty input / mixed input (ours + foreign) / exact bundle ID match"
      min_lines: 50
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      provides: "Modified DefaultTunnelProvisioner.provisionTunnelProfile с OnDemandRulesBuilder.applyCurrentState call + post .bbtbProvisionerDidSave notification + ManagerSelector usage"
      contains: "OnDemandRulesBuilder.applyCurrentState"
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift"
      provides: "Tests verifying that provisionTunnelProfile applies on-demand rules per current toggle+intent gate"
      min_lines: 90
  key_links:
    - from: "DefaultTunnelProvisioner.provisionTunnelProfile"
      to: "OnDemandRulesBuilder.applyCurrentState"
      via: "static call before saveToPreferences (W-04 single entry point)"
      pattern: "OnDemandRulesBuilder\\.applyCurrentState"
    - from: "DefaultTunnelProvisioner.provisionTunnelProfile"
      to: "ManagerSelector.ourManagers"
      via: "filter loadAllFromPreferences result before .first ?? NETunnelProviderManager()"
      pattern: "ManagerSelector\\.ourManagers"
    - from: "DefaultTunnelProvisioner.provisionTunnelProfile"
      to: "NotificationCenter.default.post(.bbtbProvisionerDidSave)"
      via: "post after saveToPreferences+loadFromPreferences (B-03 cross-plan refresh hook)"
      pattern: "bbtbProvisionerDidSave"
---

<objective>
Wave 1 / Parallel run — Wire `OnDemandRulesBuilder` (built in Plan 06C-01) в `DefaultTunnelProvisioner.provisionTunnelProfile`. Каждый раз когда приложение создаёт или обновляет `NETunnelProviderManager`, on-demand rules + `isOnDemandEnabled` записываются согласно текущему UserDefaults toggle (default ON per D-04).

**Это parallel-run wave**: старый custom auto-reconnect machinery (`ReconnectStateMachine`, `NetworkReachability`, NEVPNStatusDidChange observer pipeline в TunnelController) ПРОДОЛЖАЕТ работать. Apple's on-demand теперь ТАКЖЕ работает параллельно. Может быть double-trigger race (Pitfall 5 в RESEARCH) — это known и accepted на этой wave; mitigation в Wave 2 (watchdog) и Wave 3 (cleanup).

Purpose:
- D-01..D-03 application: builder вызывается из единственной точки — `ConfigImporter.provisionTunnelProfile` (она же creates/updates manager во всём приложении).
- D-04..D-05: default ON per fresh install читается через `OnDemandRulesBuilder.applyCurrentState` (которая внутри зовёт `loadAutoReconnectEnabled` с `?? true`).
- **B-04 fix (Round 2):** consumer вызывает `applyCurrentState` (НЕ `apply` напрямую) — это гарантирует что `isOnDemandEnabled = toggle && userIntendedConnected`. На свежей установке (import без Connect тапа) intent=false → manager.isOnDemandEnabled=false → OS НЕ запускает phantom auto-connect. Первый Connect тап в Plan 04 wiring выставит intent=true и заново применит applyCurrentState.
- **B-06 fix (Round 2):** все `managers.first` callsites используют `ManagerSelector.ourManagers(from:).first` — single helper, hardcoded Set с iOS+macOS bundle IDs. Файл создаётся в новом Task 0 этого плана.
- **B-03 cross-plan (Round 2):** после saveToPreferences/loadFromPreferences post `.bbtbProvisionerDidSave` NotificationCenter notification → TunnelController в Plan 04 наблюдает её для refresh `cachedManager`. Loose coupling (ConfigImporter ничего не знает про TunnelController).
- **B-07 fix (Round 2):** removed broken `<verify>` block on Task 1 (RED phase) — Task 2 GREEN verify is sufficient.
- **W-04 closed by B-04:** drop the wrapper helper `applyOnDemandConfiguration` from original Round 1 plan. Все вызовы идут через `applyCurrentState`.
- Pitfall 9 (Fresh install + no manager): builder вызывается ВСЕГДА из `provisionTunnelProfile` — то есть как только пользователь импортирует первый config, on-demand уже включен (но `isOnDemandEnabled` зависит от toggle+intent — см. B-04).
- Migration of existing installs (D-17b/c) НЕ в этой wave — она в Plan 06C-03 (Wave 2). Свежие installs покрываются здесь; existing installs — позже.

Output:
- **NEW** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` — B-06 / W-07 shared helper.
- **NEW** `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift` — 3 tests.
- Modified `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (правки в `DefaultTunnelProvisioner.provisionTunnelProfile`, ~6-8 строк добавлено: ManagerSelector + applyCurrentState + notification post).
- Новый тест-файл `ConfigImporterOnDemandWiringTests.swift` проверяющий что provisioner вызывает builder через applyCurrentState.

**Что НЕ делается в этой wave:**
- Не добавляется toggle UI (Wave 2 / Plan 06C-03).
- Не удаляется ReconnectStateMachine / NetworkReachability (Wave 3 / Plan 06C-04).
- Не пишется migration code для existing installs (Wave 2 / Plan 06C-03).
- Не пишется watchdog (Wave 2 / Plan 06C-03).
- Не меняется ничего в TunnelController.swift (Wave 3).
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

<interfaces>
<!-- Builder API from Plan 06C-01 (locked — Round 2 expanded): -->
```swift
public enum OnDemandRulesBuilder {
    // Low-level — caller controls flag explicitly (Round 2: param renamed).
    public static func apply(to manager: NETunnelProviderManager, isOnDemandEnabled: Bool)
    // High-level single source of truth (Round 2: NEW for B-04 / W-04).
    // Computes isOnDemandEnabled = loadAutoReconnectEnabled() && loadUserIntendedConnected().
    public static func applyCurrentState(to manager: NETunnelProviderManager,
                                         userDefaults: UserDefaults = .standard)
    public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard,
                                                key: String = "app.bbtb.autoReconnectEnabled") -> Bool
    // Round 2: NEW reader — same UserDefaults key as UserIntentStore writes.
    public static func loadUserIntendedConnected(userDefaults: UserDefaults = .standard,
                                                  key: String = "app.bbtb.userIntendedConnected") -> Bool
}
```

<!-- ManagerSelector API (NEW in this plan — Task 0): -->
```swift
public enum ManagerSelector {
    public static let ourProviderBundleIdentifiers: Set<String> = [
        "app.bbtb.client.ios.tunnel",
        "app.bbtb.client.macos.tunnel"
    ]
    public static func ourManagers(from managers: [NETunnelProviderManager],
                                   knownBundleIDs: Set<String> = ourProviderBundleIdentifiers)
        -> [NETunnelProviderManager]
}
```

<!-- NotificationCenter contract (B-03 cross-plan with TunnelController in Plan 04): -->
```swift
extension Notification.Name {
    /// Posted by DefaultTunnelProvisioner.provisionTunnelProfile after saveToPreferences+loadFromPreferences.
    /// TunnelController (Plan 04) observes this to refresh its cachedManager reference for the
    /// watchdog managerEnabled gate. Loose coupling — ConfigImporter does NOT know TunnelController.
    public static let bbtbProvisionerDidSave = Notification.Name("app.bbtb.provisionerDidSave")
}
```
Этот extension либо в `ManagerSelector.swift` (один файл — два single-source-of-truth helpers),
либо в новом `BBTBNotifications.swift`. Решение: положить в `ManagerSelector.swift` — он
ужe сам по себе single source of truth артефакт для cross-cutting concerns этой фазы.

<!-- Existing DefaultTunnelProvisioner.provisionTunnelProfile (ConfigImporter.swift:1004-1029): -->
```swift
public func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {
    let managers = try await NETunnelProviderManager.loadAllFromPreferences()
    let manager = managers.first ?? NETunnelProviderManager()

    let proto = NETunnelProviderProtocol()
    proto.providerBundleIdentifier = providerBundleIdentifier
    proto.serverAddress = serverHost
    proto.providerConfiguration = ["configJSON": configJSON]

    let killSwitchEnabled = UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true
    KillSwitch.apply(to: proto, enabled: killSwitchEnabled)

    manager.protocolConfiguration = proto
    manager.localizedDescription = "BBTB"
    manager.isEnabled = true

    try await manager.saveToPreferences()
    try await manager.loadFromPreferences()  // RESEARCH §9.1 — обязательно после save
}
```

<!-- Insertion point: between manager.isEnabled = true и saveToPreferences. -->
<!-- KillSwitch.apply работает на `proto` (NETunnelProviderProtocol). -->
<!-- OnDemandRulesBuilder.apply работает на `manager` (NETunnelProviderManager). -->
<!-- Это two different objects — KillSwitch flags на proto, on-demand flags на manager. -->

<!-- Test patterns for ConfigImporter — existing files: -->
- BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterTests.swift (если есть — для импортов и patterns)
- BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift (использует stub `TunnelProvisioning`)

<!-- TunnelProvisioning protocol — DefaultTunnelProvisioner implementation: -->
// `DefaultTunnelProvisioner` reachable via `@testable import MainScreenFeature`.
// Тесты могут вызывать `provisionTunnelProfile(configJSON:serverHost:)` напрямую —
// `NETunnelProviderManager.loadAllFromPreferences()` returns `[]` в test env без entitlements,
// поэтому provisioner создаёт fresh `NETunnelProviderManager()` (нормальный path).
// `saveToPreferences()` бросит NSError на следующей строке — это ОК, мы проверяем PROPERTIES
// manager'а ПОСЛЕ apply (in-memory mutation) но ДО save — для этого требуется test seam ИЛИ
// мы перехватываем NSError + читаем последнее присвоенное значение через @testable surface.

<!-- ВАЖНО: Чтобы тесты могли проверить result БЕЗ entitlement-gated saveToPreferences, -->
<!-- нужно либо: -->
<!-- (a) добавить test-seam в DefaultTunnelProvisioner для injecting save closure, ИЛИ -->
<!-- (b) использовать stub TunnelProvisioning (как ConfigImporterSubscriptionTests делает), ИЛИ -->
<!-- (c) тестировать `OnDemandRulesBuilder.applyCurrentState` НАПРЯМУЮ через DI UserDefaults+manager — -->
<!--     это уже сделано в Plan 06C-01 Tests 9-11 (см. Round 2 revisions). ConfigImporterOnDemandWiringTests -->
<!--     дополнительно фиксируют что callsite использует именно `applyCurrentState` (не direct `apply`). -->

<!-- Round 2 (W-04 + B-04): wrapper helper `DefaultTunnelProvisioner.applyOnDemandConfiguration` DROPPED. -->
<!-- Все консьюмеры используют `OnDemandRulesBuilder.applyCurrentState(to:userDefaults:)`. -->
<!-- Single source of truth — никакого drift. -->

<!-- Pitfall 8 mitigation: builder PARAMETERIZED по flag value — не hardcode `true`. -->
<!-- Pitfall 9 mitigation: builder вызывается на КАЖДОМ provisionTunnelProfile — fresh install после -->
<!-- import получит on-demand сразу. -->
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 0: ManagerSelector helper + NotificationCenter contract (B-06 / W-07 / B-03 prep)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift</files>
  <read_first>
    - BBTB/App/iOSApp/BBTB_iOSApp.swift строка 60 (providerBundleIdentifier для iOS)
    - BBTB/App/macOSApp/BBTB_macOSApp.swift строка 49 (providerBundleIdentifier для macOS)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (созданный в Plan 06C-01 — pattern для static enum API)
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md секция B-06 + W-07 + B-03
  </read_first>
  <behavior>
    `ManagerSelector.swift` — single source of truth helper для фильтрации наших NETunnelProviderManager
    instances. Используется в 5 callsites (ConfigImporter в Plan 02, SettingsViewModel + OnDemandMigrationTask
    в Plan 03, TunnelController.cachedManager + handleWake в Plan 04). Закрывает B-06 (управление несколькими
    manager'ами) и W-07 (общий helper).

    Тот же файл декларирует `Notification.Name.bbtbProvisionerDidSave` — single source of truth для
    cross-plan B-03 contract (ConfigImporter постит, TunnelController наблюдает). Размещение в одном файле
    мотивировано: оба artifact'а — cross-cutting concerns Phase 6c, не относятся к specific feature.

    Тесты (ManagerSelectorTests.swift):

    - Test 1 (`test_ourManagers_emptyInput_returnsEmpty`):
      `ManagerSelector.ourManagers(from: [])` returns `[]`. Sanity check.

    - Test 2 (`test_ourManagers_mixedInput_returnsOnlyOurs`):
      Build fake `[NETunnelProviderManager]` array где protocolConfiguration.providerBundleIdentifier
      одного manager'а равен `"app.bbtb.client.ios.tunnel"`, другого — `"com.example.other.vpn"`.
      `ourManagers(from:)` returns ровно один manager (наш). NOTE: build NETunnelProviderProtocol() instance,
      set `.providerBundleIdentifier`, assign to `manager.protocolConfiguration` — это работает в test env
      без entitlements (только saveToPreferences требует entitlements).

    - Test 3 (`test_ourManagers_macOSBundleID_alsoMatches`):
      Similar mixed input, но один manager с `"app.bbtb.client.macos.tunnel"`. Returns this manager.
      (Default `ourProviderBundleIdentifiers` Set покрывает оба platform IDs.)
  </behavior>
  <action>
    1. RED: создать `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ManagerSelectorTests.swift` с 3 методами.

    2. GREEN: создать `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift`:
       ```swift
       import Foundation
       import NetworkExtension

       /// Phase 6c / Plan 06C-02 — single source of truth для фильтрации NETunnelProviderManager
       /// по providerBundleIdentifier. Используется в ConfigImporter, SettingsViewModel,
       /// OnDemandMigrationTask, TunnelController. Закрывает B-06 (multi-manager) + W-07 (shared helper).
       public enum ManagerSelector {
           /// Provider bundle IDs для BBTB tunnel extension на обеих платформах.
           /// Test fixtures используют `app.bbtb.test.tunnel` — natural mismatch (correct:
           /// тесты не запускают реальные NEM extensions, никаких manager'ов в test env).
           public static let ourProviderBundleIdentifiers: Set<String> = [
               "app.bbtb.client.ios.tunnel",
               "app.bbtb.client.macos.tunnel"
           ]

           /// Filter to managers our app owns. Caller iterates over result для all-managers
           /// behavior (toggle + migration), OR takes `.first` для legacy single-manager behavior
           /// (provisioner + cachedManager).
           public static func ourManagers(
               from managers: [NETunnelProviderManager],
               knownBundleIDs: Set<String> = ourProviderBundleIdentifiers
           ) -> [NETunnelProviderManager] {
               managers.filter { manager in
                   guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
                         let id = proto.providerBundleIdentifier else { return false }
                   return knownBundleIDs.contains(id)
               }
           }
       }

       extension Notification.Name {
           /// Phase 6c / B-03 cross-plan contract — posted by DefaultTunnelProvisioner.provisionTunnelProfile
           /// после saveToPreferences/loadFromPreferences. TunnelController (Plan 06C-04) наблюдает её
           /// чтобы refresh свой cachedManager reference (для watchdog managerEnabled gate).
           /// Loose coupling: ConfigImporter ничего не знает о TunnelController.
           public static let bbtbProvisionerDidSave = Notification.Name("app.bbtb.provisionerDidSave")
       }
       ```

    3. Тесты должны pass.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter ManagerSelectorTests</automated>
  </verify>
  <acceptance_criteria>
    - 3 теста ManagerSelectorTests pass.
    - `grep -c "public enum ManagerSelector" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` returns 1.
    - `grep -c "app.bbtb.client.ios.tunnel" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` returns 1.
    - `grep -c "app.bbtb.client.macos.tunnel" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` returns 1.
    - `grep -c "bbtbProvisionerDidSave" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` returns ≥ 1.
    - `grep -c "func ourManagers" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift` returns 1.
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
  </acceptance_criteria>
  <done>ManagerSelector существует, тесты pass, NotificationCenter контракт декларирован. Готово для использования в Task 2 + Plans 03/04.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 1: Тесты для wiring — provisionTunnelProfile через applyCurrentState (RED state, ждёт Task 2)</name>
  <files>BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (lines 990-1030, секция `DefaultTunnelProvisioner`)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (созданный в Plan 06C-01 с Round 2 API)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift (созданный в Task 0)
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift (использует stub TunnelProvisioning — pattern для DI)
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift (Round 2: 11 tests, pattern для UserDefaults suite isolation)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md Pitfall 8 (provisionTunnelProfile rebuilds and OVERWRITES user toggle) и Pitfall 9 (Auto toggle on but no servers in pool)
  </read_first>
  <behavior>
    Тесты проверяют поведение `OnDemandRulesBuilder.applyCurrentState(to:userDefaults:)` напрямую
    (тестируя интеграционный контракт через UserDefaults), потому что `provisionTunnelProfile` сам по себе
    требует entitlement-gated `saveToPreferences`. Wiring (что callsite в ConfigImporter использует именно
    `applyCurrentState`) фиксируется через grep-gate в acceptance_criteria Task 2.

    Round 2 (W-04): wrapper `DefaultTunnelProvisioner.applyOnDemandConfiguration` DROPPED — тестируем
    builder напрямую.

    Тесты (все с isolated UserDefaults suites — never `.standard`):

    - Test 1 (`test_applyCurrentState_freshInstall_withoutIntent_writesIsOnDemandFalse`):
      Fresh `UserDefaults(suiteName: ...)` без записанных ключей (toggle default true, intent default false).
      Fresh `NETunnelProviderManager()`.
      Call `OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)`.
      Assert: `manager.isOnDemandEnabled == false` (B-04 — без intent flag не активируется),
              `manager.onDemandRules?.count == 1` (правила всё равно записаны).
      Это критически важный test: на свежей установке после import config'а manager не должен
      auto-connect'ить пока user не нажмёт Connect.

    - Test 2 (`test_applyCurrentState_toggleOnIntentOn_writesIsOnDemandTrue`):
      Fresh suite. Set both `app.bbtb.autoReconnectEnabled=true` AND `app.bbtb.userIntendedConnected=true`.
      Call `applyCurrentState(to: manager, userDefaults: ud)`.
      Assert: `manager.isOnDemandEnabled == true`, rules.count == 1.
      Это симулирует scenario: existing user апгрейднулся (intent был выставлен в Phase 6 Connect тапе),
      ConfigImporter повторно импортирует config (например, обновил subscription) → on-demand остаётся on.

    - Test 3 (`test_applyCurrentState_toggleOffIntentOn_writesIsOnDemandFalse`):
      Fresh suite. Set `app.bbtb.autoReconnectEnabled=false` (toggle OFF) AND
      `app.bbtb.userIntendedConnected=true`.
      Call `applyCurrentState`. Assert: `manager.isOnDemandEnabled == false`, rules.count == 1.
      Pitfall 4 mitigation: toggle OFF при активном туннеле — не tear down, но on-demand off.

    - Test 4 (`test_applyCurrentState_freshSuiteAfterUpdate_picksFreshValues`):
      Pitfall 8 mitigation. Fresh suite. Set toggle=true, intent=true. Call applyCurrentState →
      `isOnDemandEnabled == true`. Change to intent=false (например, user сделал disconnect).
      Call applyCurrentState AGAIN → `isOnDemandEnabled == false`. Каждый call читает fresh UserDefaults
      (не cache).
  </behavior>
  <action>
    Создать `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift`:

    1. Header doc-comment ссылающийся на Plan 06C-02 / Wave 1 / D-01 / D-04 / B-04 / W-04 / Pitfall 8-9.
    2. `import XCTest`, `import NetworkExtension`, `@testable import MainScreenFeature`.
    3. `final class ConfigImporterOnDemandWiringTests: XCTestCase` с 4 методами по списку выше.
    4. `private func freshSuite() -> UserDefaults` helper (как в OnDemandRulesBuilderTests).

    Тесты должны компилироваться И pass — они тестируют existing API (`applyCurrentState` уже создан
    в Plan 06C-01 Round 2). Wiring grep — в acceptance_criteria Task 2.

    NOTES:
    - Не делаем integration test через `provisionTunnelProfile(configJSON:serverHost:)` — это требует
      saveToPreferences (entitlement-gated). Тестируем builder напрямую.
    - Round 2: эти тесты по сути дублируют Plan 06C-01 Tests 10-11, но добавляют дополнительные cases
      (toggle off / fresh values across calls) специфичные для callsite поведения ConfigImporter.
      Дубликат сохраняется намеренно: phase 6c-02 documentation хочет fixture показывающий «callsite use
      pattern» отдельно от builder unit tests.
    - **B-07 fix:** No `<verify>` block on this Task. Task 2 GREEN verify covers wiring.
  </action>
  <acceptance_criteria>
    - Тест-файл компилируется и **passes** (Round 2 — builder API уже существует, тесты тестируют существующий API).
    - В тесте нет вызовов `manager.saveToPreferences()` или `.loadAllFromPreferences()` (entitlement-gated).
    - Каждый test метод использует свой `UserDefaults(suiteName: ...)` — никакого `.standard`.
    - `grep -c "applyCurrentState" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift` returns ≥ 4 (один на test).
    - `grep -c "applyOnDemandConfiguration" BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift` returns 0 (Round 2: wrapper dropped).
  </acceptance_criteria>
  <done>4 теста для applyCurrentState wiring contract; готовы стать GREEN после Task 2 wiring (фактически они уже GREEN — Task 2 это про callsite, не про builder).</done>
</task>

<task type="auto">
  <name>Task 2: Wire OnDemandRulesBuilder.applyCurrentState + ManagerSelector + bbtbProvisionerDidSave notification в DefaultTunnelProvisioner.provisionTunnelProfile</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift строки 990-1030 (актуальная реализация DefaultTunnelProvisioner)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (Plan 06C-01 Round 2 — 4 публичных метода)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ManagerSelector.swift (Task 0 этого плана)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Code Examples» Example 1 (WireGuard pattern) и Pitfall 8
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md B-04 + B-06 + B-03 + W-04
  </read_first>
  <action>
    Modify `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`:

    **Round 2 changes vs Round 1:**
    - DROP `applyOnDemandConfiguration` wrapper (W-04 closure — single source of truth уже в builder).
    - REPLACE `managers.first` с `ManagerSelector.ourManagers(from: managers).first` (B-06).
    - CALL `OnDemandRulesBuilder.applyCurrentState(to: manager)` (NOT direct `apply` — B-04 / W-04).
    - POST `NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: nil)` после
      `loadFromPreferences()` (B-03 cross-plan contract с TunnelController).

    Конкретные правки в `provisionTunnelProfile(configJSON:serverHost:)`:

    1. Replace existing `let manager = managers.first ?? NETunnelProviderManager()` на:
       ```swift
       // B-06 (Round 2): фильтруем ТОЛЬКО наши manager'ы по providerBundleIdentifier.
       // Mixed installs (residue от другого приложения, legacy migration) больше не путают provisioner.
       let ours = ManagerSelector.ourManagers(from: managers)
       let manager = ours.first ?? NETunnelProviderManager()
       ```

    2. **Между** `manager.isEnabled = true` и `try await manager.saveToPreferences()`, вставить:
       ```swift
       // Phase 6c / Plan 06C-02 / B-04 / W-04 (Round 2): apply on-demand configuration через
       // высокоуровневую applyCurrentState — gates on (toggle AND userIntendedConnected).
       // Без intent flag (свежая установка, не было Connect) on-demand НЕ активируется → нет phantom
       // auto-connect при import (Phase 6 bug class — теперь OS-driven, blocked).
       // Pitfall 8: applyCurrentState читает fresh UserDefaults каждый call.
       OnDemandRulesBuilder.applyCurrentState(to: manager)
       ```

    3. **После** `try await manager.loadFromPreferences()`, вставить:
       ```swift
       // B-03 (Round 2): post notification чтобы TunnelController refreshed свой cachedManager
       // reference. Loose coupling (provisioner НЕ знает про TunnelController).
       // Observer side — TunnelController в Plan 06C-04 Task 1 Step 2.
       NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: nil)
       ```

    4. **DELETE** (если уже добавлено в Round 1 черновике) старый wrapper helper
       `applyOnDemandConfiguration` — W-04 / B-04 closure.

    5. Update header doc-comment у `provisionTunnelProfile` (или file-section, по conventions проекта)
       чтобы упомянуть Phase 6c on-demand wiring + B-03/B-04/B-06 references.

    КРИТИЧЕСКИ ВАЖНО:
    - НЕ удалять и НЕ менять KillSwitch.apply call — он остаётся как есть (это другой код-путь).
    - НЕ менять порядок saveToPreferences + loadFromPreferences (Apple invariant, RESEARCH §9.1).
    - НЕ трогать NetworkReachability, ReconnectStateMachine, TunnelController в этой wave.

    После правки запустить полную тест-сюиту package'а — все 11 тестов Plan 06C-01 + 4 теста
    ConfigImporterOnDemandWiringTests + 3 теста ManagerSelectorTests должны pass; никакие существующие
    тесты не должны regress.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter ConfigImporterOnDemandWiringTests && swift test --package-path Packages/AppFeatures --filter OnDemandRulesBuilderTests && swift test --package-path Packages/AppFeatures --filter ManagerSelectorTests</automated>
  </verify>
  <acceptance_criteria>
    - 4 теста ConfigImporterOnDemandWiringTests pass.
    - 11 тестов OnDemandRulesBuilderTests все ещё pass (regression-safe).
    - 3 теста ManagerSelectorTests pass.
    - **`grep -c "OnDemandRulesBuilder\.applyCurrentState" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 1** (B-04 single entry point — НЕ direct `apply`).
    - **`grep -c "OnDemandRulesBuilder\.apply\b" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 0** (Round 2: direct apply не вызывается из callsite; word-boundary исключает `applyCurrentState`).
    - **`grep -c "applyOnDemandConfiguration" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 0** (Round 2: wrapper dropped — W-04 closed via B-04).
    - **`grep -c "ManagerSelector.ourManagers" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 1** (B-06: multi-manager safe).
    - **`grep -c "bbtbProvisionerDidSave" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 1** (B-03: notification post).
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
    - `cd BBTB && swift test --package-path Packages/AppFeatures` (full suite) green — НИ ОДИН существующий тест не падает (parallel-run invariant).
    - Diff `git diff BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift | grep -E "^\+" | grep -v "^\+\+\+"` показывает только additions/replacements в provisionTunnelProfile — НИКАКИХ удалений старого кода вне этого method (parallel-run invariant).
  </acceptance_criteria>
  <done>provisionTunnelProfile теперь пишет on-demand rules через applyCurrentState (toggle+intent gate), фильтрует manager'ы через ManagerSelector, и постит bbtbProvisionerDidSave notification. Apple's on-demand параллельно работает рядом со старой custom-reconnect machinery. Никаких удалений в этой wave; никакого phantom auto-connect при import без Connect тапа.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| `UserDefaults.standard` ↔ DefaultTunnelProvisioner | Sandbox-protected per app; Bool-only — non-Bool falls through to default ON. |
| Apple's on-demand evaluation ↔ existing custom auto-reconnect machinery | Parallel run — both may trigger reconnect on path change. Race accepted on this wave; mitigation in Wave 2 watchdog + Wave 3 cleanup. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06C-02-01 | DoS | Double-trigger race: Apple on-demand + existing custom reconnect both fire after path change | accept | Wave 1 by design accepts the race. Pitfall 5 (RESEARCH) — UAT-Task E in Plan 06C-04 (Wave 3) validates whether race causes user-visible issues. Mitigation if needed: Wave 2 watchdog adds `isOnDemandEnabled = false` during swap. |
| T-06C-02-02 | Tampering | Stale UserDefaults toggle value from prior Phase 6 install causes inconsistent state | mitigate | `loadAutoReconnectEnabled` defaults to true (D-04). Migration of existing manager state covered in Plan 06C-03 (Wave 2 migration task). |
| T-06C-02-03 | Information Disclosure | provisionTunnelProfile logs may include server names | accept | Existing OSLog usage не меняется этой wave. No new log statements added. |
</threat_model>

<verification>
- Compile: `cd BBTB && swift build --package-path Packages/AppFeatures`
- Wave 1 unit tests (Round 2 counts):
  - `cd BBTB && swift test --package-path Packages/AppFeatures --filter ConfigImporterOnDemandWiringTests` (4 pass)
  - `cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandRulesBuilderTests` (**11 pass** — Round 2: 8 original + 3 for B-04)
  - `cd BBTB && swift test --package-path Packages/AppFeatures --filter ManagerSelectorTests` (3 pass — NEW in Round 2)
- Regression: `cd BBTB && swift test --package-path Packages/AppFeatures` full suite green.
- Diff hygiene: `git diff --stat BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` shows only insertions/replacements внутри `provisionTunnelProfile` (~10 lines).
- B-04 invariant: `grep -c "applyOnDemandConfiguration" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 0 (wrapper DROPPED per W-04 closure).
- B-06 invariant: `grep -c "ManagerSelector" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns ≥ 1.
- B-03 invariant: `grep -c "bbtbProvisionerDidSave" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 1.
- Source audit: ROADMAP success criterion 6 (tests cover on-demand rules config) advanced. SC 1 (Wi-Fi↔LTE auto-reconnect) теперь имеет TWO paths — Apple's + existing custom (parallel-run).
- ConfigImporter тесты: проверить что ConfigImporterSubscriptionTests / ConfigImporterTests (если существуют) НЕ падают.
</verification>

<success_criteria>
1. **(Round 2)** `ManagerSelector.swift` существует как public enum с `ourManagers(from:knownBundleIDs:)` + `Notification.Name.bbtbProvisionerDidSave` extension.
2. **(Round 2)** `provisionTunnelProfile(configJSON:serverHost:)` вызывает `OnDemandRulesBuilder.applyCurrentState(to: manager)` ровно один раз, до saveToPreferences. Wrapper `applyOnDemandConfiguration` ОТСУТСТВУЕТ (W-04 closed via B-04).
3. **(Round 2)** `provisionTunnelProfile` использует `ManagerSelector.ourManagers(from:).first` вместо `managers.first` (B-06).
4. **(Round 2)** `provisionTunnelProfile` постит `NotificationCenter.default.post(.bbtbProvisionerDidSave, object: nil)` после `loadFromPreferences` (B-03 cross-plan contract).
5. 4 теста в ConfigImporterOnDemandWiringTests pass.
6. **11 тестов OnDemandRulesBuilderTests** из Wave 0 продолжают pass (Round 2: 8 original + 3 new).
7. **3 теста ManagerSelectorTests** pass (NEW in Round 2).
8. Полная AppFeatures test-сюита green — никаких regressions, в том числе в TunnelControllerStateTests (старая machinery работает рядом).
9. `git diff` показывает только additions/replacements в ConfigImporter.swift — никаких удалений старого кода вне `provisionTunnelProfile`.
10. Pitfall 8 mitigated: каждый call читает fresh UserDefaults toggle И intent, не cache.
11. Pitfall 9 mitigated: даже fresh install (no manager before import) — первый import уже пишет on-demand rules с правильным gate'ом (toggle AND intent).
12. **B-04 phantom-connect mitigated:** на свежей установке после import (без Connect тапа) intent=false → manager.isOnDemandEnabled=false → OS НЕ запускает auto-connect.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-02-SUMMARY.md`. Include:
- NEW: ManagerSelector.swift (Task 0) + ManagerSelectorTests.swift (3 tests) — B-06 / W-07 closure.
- Modified file (ConfigImporter.swift) + line range with diff context — Round 2 changes: applyCurrentState + ManagerSelector + bbtbProvisionerDidSave.
- New test file ConfigImporterOnDemandWiringTests.swift с 4 методами.
- Confirmation: full AppFeatures suite green (parallel-run invariant — старая machinery не сломалась).
- Confirmation: NO wrapper `applyOnDemandConfiguration` — single source of truth в builder (W-04 closed via B-04).
- Confirmation: notification name `bbtbProvisionerDidSave` declared in ManagerSelector.swift (B-03 cross-plan contract).
- Note for Plan 06C-03: now каждый new import пишет on-demand через applyCurrentState (gates on toggle+intent). Plan 06C-03 добавит migration для EXISTING installs + UI toggle + watchdog + macOS wake nudge. Все Plan 03/04 callsites используют ManagerSelector + applyCurrentState.
- Reference: D-01, D-04, B-03, B-04, B-06, B-07, W-04, W-07, Pitfall 8, Pitfall 9.
</output>
