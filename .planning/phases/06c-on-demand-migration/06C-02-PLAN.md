---
phase: 06c-on-demand-migration
plan: 02
type: execute
wave: 2
depends_on: ["06c-on-demand-migration:01"]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift
autonomous: true
requirements: [NET-08, NET-09, NET-10]
must_haves:
  truths:
    - "DefaultTunnelProvisioner.provisionTunnelProfile вызывает OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: OnDemandRulesBuilder.loadAutoReconnectEnabled()) перед saveToPreferences"
    - "Каждый import нового конфига (initial + re-import) пишет on-demand rules согласованные с current toggle (Pitfall 9 mitigation)"
    - "OnDemandRulesBuilder.apply вызывается ПОСЛЕ KillSwitch.apply, но ДО saveToPreferences — порядок не имеет функционального значения, но фиксируется для читаемости"
    - "Ни один существующий test в ConfigImporter* test-файлах не падает после wiring (parallel-run: старая custom-reconnect machinery в TunnelController ПРОДОЛЖАЕТ работать)"
    - "Wave 1 НЕ удаляет ReconnectStateMachine, NetworkReachability, custom flags в TunnelController — это Wave 3"
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      provides: "Modified DefaultTunnelProvisioner.provisionTunnelProfile с OnDemandRulesBuilder.apply call"
      contains: "OnDemandRulesBuilder.apply"
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift"
      provides: "Tests verifying that provisionTunnelProfile applies on-demand rules per current UserDefaults toggle"
      min_lines: 90
  key_links:
    - from: "DefaultTunnelProvisioner.provisionTunnelProfile"
      to: "OnDemandRulesBuilder.apply"
      via: "static call before saveToPreferences"
      pattern: "OnDemandRulesBuilder\\.apply"
    - from: "DefaultTunnelProvisioner.provisionTunnelProfile"
      to: "OnDemandRulesBuilder.loadAutoReconnectEnabled"
      via: "read UserDefaults flag"
      pattern: "loadAutoReconnectEnabled"
---

<objective>
Wave 1 / Parallel run — Wire `OnDemandRulesBuilder` (built in Plan 06C-01) в `DefaultTunnelProvisioner.provisionTunnelProfile`. Каждый раз когда приложение создаёт или обновляет `NETunnelProviderManager`, on-demand rules + `isOnDemandEnabled` записываются согласно текущему UserDefaults toggle (default ON per D-04).

**Это parallel-run wave**: старый custom auto-reconnect machinery (`ReconnectStateMachine`, `NetworkReachability`, NEVPNStatusDidChange observer pipeline в TunnelController) ПРОДОЛЖАЕТ работать. Apple's on-demand теперь ТАКЖЕ работает параллельно. Может быть double-trigger race (Pitfall 5 в RESEARCH) — это known и accepted на этой wave; mitigation в Wave 2 (watchdog) и Wave 3 (cleanup).

Purpose:
- D-01..D-03 application: builder вызывается из единственной точки — `ConfigImporter.provisionTunnelProfile` (она же creates/updates manager во всём приложении).
- D-04..D-05: default ON per fresh install читается через `OnDemandRulesBuilder.loadAutoReconnectEnabled()` (default `?? true`).
- Pitfall 9 (Fresh install + no manager): builder вызывается ВСЕГДА из `provisionTunnelProfile` — то есть как только пользователь импортирует первый config, on-demand уже включен.
- Migration of existing installs (D-17b/c) НЕ в этой wave — она в Plan 06C-03 (Wave 2). Свежие installs покрываются здесь; existing installs — позже.

Output:
- Modified `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (одна правка в `DefaultTunnelProvisioner.provisionTunnelProfile`, ~3-5 строк добавлено).
- Новый тест-файл `ConfigImporterOnDemandWiringTests.swift` проверяющий что provisioner вызывает builder.

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
<!-- Builder API from Plan 06C-01 (locked): -->
```swift
public enum OnDemandRulesBuilder {
    public static func apply(to manager: NETunnelProviderManager, autoReconnectEnabled: Bool)
    public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard,
                                                key: String = "app.bbtb.autoReconnectEnabled") -> Bool
}
```

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
<!-- (c) выделить pure-logic helper static func applyOnDemandToManager(manager:userDefaults:) и тестировать ЕГО -->
<!--     отдельно, в DefaultTunnelProvisioner.provisionTunnelProfile он просто вызывается. -->

<!-- Выбираем (c) — это самое чистое и минимально-инвазивное решение. -->
<!-- ДОБАВЬ helper в DefaultTunnelProvisioner: -->
<!-- internal static func applyOnDemandConfiguration(to manager: NETunnelProviderManager, -->
<!--                                                  userDefaults: UserDefaults = .standard) -->
<!-- which просто читает flag и зовёт OnDemandRulesBuilder.apply. Это testable без entitlements. -->

<!-- Pitfall 8 mitigation: builder PARAMETERIZED по flag value — не hardcode `true`. -->
<!-- Pitfall 9 mitigation: builder вызывается на КАЖДОМ provisionTunnelProfile — fresh install после -->
<!-- import получит on-demand сразу. -->
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Тесты — applyOnDemandConfiguration helper + verification что provisionTunnelProfile его зовёт</name>
  <files>BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (lines 990-1030, секция `DefaultTunnelProvisioner`)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (созданный в Plan 06C-01)
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift (использует stub TunnelProvisioning — pattern для DI)
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift (созданный в Plan 06C-01 — pattern для UserDefaults suite isolation)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md Pitfall 8 (provisionTunnelProfile rebuilds and OVERWRITES user toggle) и Pitfall 9 (Auto toggle on but no servers in pool)
  </read_first>
  <behavior>
    Helper API (locked для этой wave):
    ```swift
    // Inside DefaultTunnelProvisioner (internal scope for testability):
    internal static func applyOnDemandConfiguration(
        to manager: NETunnelProviderManager,
        userDefaults: UserDefaults = .standard
    ) {
        let enabled = OnDemandRulesBuilder.loadAutoReconnectEnabled(userDefaults: userDefaults)
        OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: enabled)
    }
    ```

    Тесты (все с isolated UserDefaults suites — never `.standard`):

    - Test 1 (`test_applyOnDemandConfiguration_freshInstall_writesEnabledRules`):
      Fresh `UserDefaults(suiteName: ...)` без записанного ключа. Fresh `NETunnelProviderManager()`.
      Call `DefaultTunnelProvisioner.applyOnDemandConfiguration(to: manager, userDefaults: ud)`.
      Assert: `manager.isOnDemandEnabled == true` (D-04 default ON), `manager.onDemandRules?.count == 1`,
              first rule is `NEOnDemandRuleConnect` with `.interfaceTypeMatch == .any`.

    - Test 2 (`test_applyOnDemandConfiguration_userDisabled_writesDisabledFlagButPreservesRules`):
      Fresh suite. Set `ud.set(false, forKey: "app.bbtb.autoReconnectEnabled")`.
      Call helper. Assert: `manager.isOnDemandEnabled == false`, rules.count == 1.

    - Test 3 (`test_applyOnDemandConfiguration_userEnabled_writesEnabledRules`):
      Fresh suite. Set `ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")`.
      Call helper. Assert: `manager.isOnDemandEnabled == true`, rules.count == 1.

    - Test 4 (`test_applyOnDemandConfiguration_replaysOnSubsequentCalls`):
      Pitfall 8 mitigation check. Fresh suite. Set `false`. Call helper → `isOnDemandEnabled == false`.
      Change suite value to `true`. Call helper AGAIN → `isOnDemandEnabled == true`. Каждый call читает
      свежий toggle (не cache).
  </behavior>
  <action>
    Создать `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterOnDemandWiringTests.swift`:

    1. Header doc-comment ссылающийся на Plan 06C-02 / Wave 1 / D-01 / D-04 / Pitfall 8-9.
    2. `import XCTest`, `import NetworkExtension`, `@testable import MainScreenFeature`.
    3. `final class ConfigImporterOnDemandWiringTests: XCTestCase` с 4 методами по списку выше.
    4. `private func freshSuite() -> UserDefaults` helper (как в OnDemandRulesBuilderTests).

    Тесты должны компилироваться, но fail с «No such symbol: applyOnDemandConfiguration» — это RED.

    NOTES:
    - Не делаем integration test через `provisionTunnelProfile(configJSON:serverHost:)` — это требует saveToPreferences (entitlement-gated). Тестируем helper напрямую — это design decision: extract pure-logic helper для testability.
    - Verifying что `provisionTunnelProfile` вызывает helper — делаем через grep-gate в acceptance_criteria task 2 (один callsite).
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter ConfigImporterOnDemandWiringTests 2>&1 | grep -E "error|fail" | head -5</automated>
  </verify>
  <acceptance_criteria>
    - Тест-файл компилируется ПОСЛЕ Task 2 (то есть GREEN после helper существует). RED state до Task 2 ожидается.
    - В тесте нет вызовов `manager.saveToPreferences()` или `.loadAllFromPreferences()` (entitlement-gated).
    - Каждый test метод использует свой `UserDefaults(suiteName: ...)` — никакого `.standard`.
  </acceptance_criteria>
  <done>Тестовый файл создан с 4 методами; ожидает Task 2 для GREEN.</done>
</task>

<task type="auto">
  <name>Task 2: Wire OnDemandRulesBuilder в DefaultTunnelProvisioner.provisionTunnelProfile</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift строки 990-1030 (актуальная реализация DefaultTunnelProvisioner)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (созданный в Plan 06C-01)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Code Examples» Example 1 (WireGuard pattern) и Pitfall 8 (read flag fresh on each call)
  </read_first>
  <action>
    Modify `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`:

    1. Inside `DefaultTunnelProvisioner` class, ДО `provisionTunnelProfile`, добавить новый `internal static` helper:
       ```swift
       /// Phase 6c / Plan 06C-02 — apply on-demand rules + isOnDemandEnabled to a manager
       /// based on the current UserDefaults toggle. Single source of truth via OnDemandRulesBuilder.
       /// Default ON для свежих установок (D-04). Pitfall 8 — каждый call читает fresh toggle.
       internal static func applyOnDemandConfiguration(
           to manager: NETunnelProviderManager,
           userDefaults: UserDefaults = .standard
       ) {
           let enabled = OnDemandRulesBuilder.loadAutoReconnectEnabled(userDefaults: userDefaults)
           OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: enabled)
       }
       ```

    2. Внутри `provisionTunnelProfile(configJSON:serverHost:)`, **между** строкой `manager.isEnabled = true` (текущая строка 1025) и `try await manager.saveToPreferences()` (строка 1027), вставить:
       ```swift
       // Phase 6c / Plan 06C-02 — apply on-demand configuration per current toggle.
       // Pitfall 9: каждый import (initial + re-import) пишет согласованный state.
       DefaultTunnelProvisioner.applyOnDemandConfiguration(to: manager)
       ```

    3. Update header doc-comment file-section (если необходимо) или inline doc-comment у `provisionTunnelProfile` чтобы упомянуть Phase 6c on-demand wiring.

    КРИТИЧЕСКИ ВАЖНО:
    - НЕ удалять и НЕ менять KillSwitch.apply call — он остаётся как есть (это другой код-путь).
    - НЕ менять порядок saveToPreferences + loadFromPreferences (Apple invariant, RESEARCH §9.1).
    - НЕ трогать NetworkReachability, ReconnectStateMachine, TunnelController в этой wave.

    После правки запустить полную тест-сюиту package'а — все тесты Plan 06C-01 + новый ConfigImporterOnDemandWiringTests должны pass; никакие существующие тесты не должны regress.
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter ConfigImporterOnDemandWiringTests && swift test --package-path Packages/AppFeatures --filter OnDemandRulesBuilderTests</automated>
  </verify>
  <acceptance_criteria>
    - 4 теста ConfigImporterOnDemandWiringTests pass (GREEN после Task 2).
    - 8 тестов OnDemandRulesBuilderTests все ещё pass (regression-safe).
    - `grep -c "OnDemandRulesBuilder\\.apply\\|applyOnDemandConfiguration" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns ≥ 2 (helper sutra + одна call inside provisionTunnelProfile).
    - `grep -c "applyOnDemandConfiguration" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns 2 (definition + one usage внутри provisionTunnelProfile).
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
    - `cd BBTB && swift test --package-path Packages/AppFeatures` (full suite) green — НИ ОДИН существующий тест не падает (parallel-run invariant).
    - Diff `git diff BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift | grep -E "^\\+" | grep -v "^\\+\\+\\+"` показывает только additions — НИКАКИХ удалений старого кода в этой wave.
  </acceptance_criteria>
  <done>provisionTunnelProfile теперь пишет on-demand rules per current toggle на каждый import. Apple's on-demand reconnect параллельно работает рядом со старой custom-reconnect machinery. Никаких удалений в этой wave.</done>
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
- Wave 1 unit tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter ConfigImporterOnDemandWiringTests` (4 pass) + `--filter OnDemandRulesBuilderTests` (8 pass from Wave 0).
- Regression: `cd BBTB && swift test --package-path Packages/AppFeatures` full suite green.
- Diff hygiene: `git diff --stat BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` shows only insertions (~10 lines).
- Source audit: ROADMAP success criterion 6 (tests cover on-demand rules config) advanced. SC 1 (Wi-Fi↔LTE auto-reconnect) теперь имеет TWO paths — Apple's + existing custom (parallel-run).
- ConfigImporter тесты: проверить что ConfigImporterSubscriptionTests / ConfigImporterTests (если существуют) НЕ падают.
</verification>

<success_criteria>
1. `DefaultTunnelProvisioner.applyOnDemandConfiguration(to:userDefaults:)` существует как internal static helper.
2. `provisionTunnelProfile(configJSON:serverHost:)` вызывает этот helper ровно один раз, до saveToPreferences.
3. 4 теста в ConfigImporterOnDemandWiringTests pass.
4. 8 тестов OnDemandRulesBuilderTests из Wave 0 продолжают pass.
5. Полная AppFeatures test-сюита green — никаких regressions, в том числе в TunnelControllerStateTests (старая machinery работает рядом).
6. `git diff` показывает только additions в ConfigImporter.swift — никаких удалений.
7. Pitfall 8 mitigated: каждый call читает fresh UserDefaults toggle, не cache.
8. Pitfall 9 mitigated: даже fresh install (no manager before import) — первый import уже пишет on-demand rules.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-02-SUMMARY.md`. Include:
- Modified file (ConfigImporter.swift) + line range with diff context.
- New test file with method count.
- Confirmation: full AppFeatures suite green (parallel-run invariant — старая machinery не сломалась).
- Confirmation: ZERO deletions в этой wave — pure additive.
- Note for Plan 06C-03: now каждый new import пишет on-demand. Plan 06C-03 добавит migration для EXISTING installs + UI toggle + watchdog + macOS wake nudge.
- Reference D-01, D-04, Pitfall 8, Pitfall 9.
</output>
