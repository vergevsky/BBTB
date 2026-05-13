---
phase: 06c-on-demand-migration
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift
autonomous: true
requirements: [NET-08, NET-09, NET-10]
must_haves:
  truths:
    - "OnDemandRulesBuilder.apply(to:isOnDemandEnabled:) writes a single NEOnDemandRuleConnect(.any) rule and sets manager.isOnDemandEnabled to the passed Bool (param renamed from autoReconnectEnabled to disambiguate toggle vs final flag — B-04 fix)"
    - "OnDemandRulesBuilder.applyCurrentState(to:userDefaults:) — Phase 6c single source of truth — computes isOnDemandEnabled = loadAutoReconnectEnabled() && loadUserIntendedConnected() and calls low-level apply (B-04 + W-04 fix)"
    - "OnDemandRulesBuilder.loadAutoReconnectEnabled() returns true on fresh install (no UserDefaults value present) — Default ON per D-04"
    - "OnDemandRulesBuilder.loadAutoReconnectEnabled() returns the persisted Bool when UserDefaults key `app.bbtb.autoReconnectEnabled` was set"
    - "OnDemandRulesBuilder.loadUserIntendedConnected() returns the persisted Bool from UserDefaults key `app.bbtb.userIntendedConnected` (same key UserIntentStore in TunnelController writes) — defaults to false on fresh install (no phantom connect at import time — B-04)"
    - "Builder always writes both rules array AND isOnDemandEnabled — `false` flag still persists rules so re-enable is cheap (no provisionTunnelProfile needed)"
    - "Builder is a static enum namespace (no instance state) — testable without entitlements; mirrors KillSwitch.apply pattern"
    - "Public API of the builder is stable enough that Phase 8 can prepend NEOnDemandRuleEvaluateConnection rules without changing callsite signatures (W-08 ordering contract documented in buildRules doc-comment)"
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift"
      provides: "enum OnDemandRulesBuilder with apply(to:isOnDemandEnabled:) + applyCurrentState(to:userDefaults:) + loadAutoReconnectEnabled() + loadUserIntendedConnected()"
      min_lines: 80
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift"
      provides: "Tests for rule shape, isOnDemandEnabled mirror, UserDefaults default-ON, persistence after disable, applyCurrentState gate (intent), loadUserIntendedConnected reader"
      min_lines: 150
  key_links:
    - from: "OnDemandRulesBuilder.apply"
      to: "NETunnelProviderManager.onDemandRules + isOnDemandEnabled"
      via: "direct property assignment"
      pattern: "manager\\.onDemandRules"
    - from: "OnDemandRulesBuilder.loadAutoReconnectEnabled"
      to: "UserDefaults `app.bbtb.autoReconnectEnabled`"
      via: "object(forKey:) as? Bool ?? true"
      pattern: "app\\.bbtb\\.autoReconnectEnabled"
---

<objective>
Wave 0 / Foundation — Создать `OnDemandRulesBuilder` как **single source of truth** для on-demand rules + первые тесты. Это покрывает D-01, D-01b, D-02, D-03 и закладывает Phase 8 extensibility, не меняя поведения приложения (builder создан, но ещё нигде не вызывается).

Purpose:
- Phase 6c заменяет custom auto-reconnect machinery на iOS-нативный `isOnDemandEnabled` + `NEOnDemandRule*`. Wave 0 — фундамент: builder + UserDefaults readers. Без него никто не сможет писать правила консистентно.
- D-01 RESEARCH-уточнение: использовать `NEOnDemandRuleConnect(interfaceType: .any)` (WireGuard pattern), а не `NEEvaluateConnectionRule` (последний требует non-empty matchDomains — Apple staff на forum thread/81249). Архитектурное намерение D-01 (extensibility под Phase 8) сохраняется через API — Phase 8 добавит `NEOnDemandRuleEvaluateConnection` в массив правил без изменения callsites.
- **B-04 fix (revision Round 2):** API расширен до 4 публичных методов. Параметр `autoReconnectEnabled` переименован в `isOnDemandEnabled` (disambiguates toggle vs final manager flag). Новый высокоуровневый метод `applyCurrentState(to:userDefaults:)` — **единый source of truth для всех консьюмеров (ConfigImporter, SettingsViewModel, OnDemandMigrationTask, TunnelController connect/disconnect)** — вычисляет `isOnDemandEnabled = toggle && userIntent` и вызывает низкоуровневый apply. Новый reader `loadUserIntendedConnected` читает тот же UserDefaults ключ что пишет `UserIntentStore` (контракт документирован inline). Без intent-gate Wave 1 рисковал phantom auto-connect при import без явного Connect тапа (Phase 6 bug class, теперь OS-driven).
- **W-08 fix (revision Round 2):** `buildRules()` private function получает doc-comment про Phase 8 ordering contract: "first-match-wins; future NEOnDemandRuleEvaluateConnection rules MUST be prepended; catch-all connect remains last". File header doc-comment также упоминает ordering контракт.
- Wave 0 строго **аддитивен**: никакого удаления существующего кода, никакого изменения runtime поведения. Это гарантирует rollback safety — если что-то пойдёт не так в Wave 1+, можно откатиться без потери foundation.

Output:
- Новый файл `OnDemandRulesBuilder.swift` в `MainScreenFeature` модуле.
- Новый тестовый файл `OnDemandRulesBuilderTests.swift` с покрытием rule shape + UserDefaults default ON + persistence-on-disable.
- Никаких изменений в `TunnelController.swift`, `ConfigImporter.swift`, или других существующих файлах. Если planner/executor видит соблазн потрогать ConfigImporter — это Wave 1 (план 06C-02), не сейчас.
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

<interfaces>
<!-- Apple NetworkExtension on-demand APIs (Phase 6c uses ONLY NEOnDemandRuleConnect): -->
```swift
import NetworkExtension

class NEOnDemandRuleConnect: NEOnDemandRule {
    // inherited from NEOnDemandRule:
    var interfaceTypeMatch: NEOnDemandRuleInterfaceType  // .any, .wiFi, .cellular, .ethernet
}

class NETunnelProviderManager: NEVPNManager {
    // inherited from NEVPNManager:
    var isOnDemandEnabled: Bool                          // master toggle
    var onDemandRules: [NEOnDemandRule]?                 // first-match-wins array
    func saveToPreferences() async throws
    func loadFromPreferences() async throws
}
```

<!-- Reference pattern: KillSwitch.apply (BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift) -->
```swift
// Static enum namespace — no instance state, callers pass the manager/proto.
// Single source of truth — каждый call-site (ConfigImporter, future toggle handlers) идёт сюда.
public enum KillSwitch {
    public static func apply(to proto: NETunnelProviderProtocol, enabled: Bool) {
        if enabled {
            proto.includeAllNetworks = true
            // ...
        }
    }
}
```

<!-- UserDefaults default-ON pattern (verified in KillSwitch consumer + Phase 6 UAT): -->
```swift
// `object(forKey:)` returns nil if key never set; `as? Bool ?? true` defaults to ON
// on fresh install per D-04. `.bool(forKey:)` would default to false — DO NOT use.
let enabled = UserDefaults.standard.object(forKey: "app.bbtb.autoReconnectEnabled") as? Bool ?? true
```

<!-- WireGuard reference (BSD/MIT — verified raw GitHub fetch in 06C-RESEARCH.md Example 1): -->
```swift
let connectRule = NEOnDemandRuleConnect()
connectRule.interfaceTypeMatch = .any
manager.onDemandRules = [connectRule]
manager.isOnDemandEnabled = true
```

<!-- D-01b extensibility contract — Phase 8 must compile without touching THIS file's callsites: -->
// Phase 8 будет добавлять `NEOnDemandRuleEvaluateConnection` (per-SSID/per-domain)
// в массив правил ДО connectRule (first-match-wins). API `apply(to:isOnDemandEnabled:)` (Round 2 rename per B-04)
// остаётся той же signature после Phase 6c shipping; внутри Phase 8 расширит `buildRules()`.

<!-- Test strategy (D-24 category 1): tests run in `swift test` без entitlements. -->
<!-- NETunnelProviderManager() CAN be instantiated in tests — it's only saveToPreferences/connect -->
<!-- that требует entitlements. Все наши assertions читают property values после apply, -->
<!-- не вызывая никаких XPC trips. -->
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: OnDemandRulesBuilder + UserDefaults reader (RED-GREEN)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift</files>
  <read_first>
    - BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift (полностью — pattern reference: static enum, apply, doc-comments на русском, ASVS-style ссылки на D-XX)
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md секция «Apple-механизм конфигурации» (D-01, D-01b, D-02, D-03) и «User-facing toggle» (D-04, D-05)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pattern 1: OnDemandRulesBuilder API» (recommended shape — exact API decided by planner; см. ниже) и «Code Examples» Example 1 + Example 3
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Anti-Patterns to Avoid» (особенно «Empty matchDomains в NEEvaluateConnectionRule» и «Multi-rule conflict pattern»)
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/KillSwitchToggleSectionTests.swift (если есть) или другой существующий test-файл в `MainScreenFeatureTests` — для перенимания import-блока, XCTest setUp/tearDown UserDefaults-pattern
  </read_first>
  <behavior>
    Builder API (locked — Round 2 revision):
    ```swift
    public enum OnDemandRulesBuilder {
        // Низкоуровневый apply — callers контролируют флаг явно.
        // ПЕРЕИМЕНОВАН: autoReconnectEnabled → isOnDemandEnabled (B-04 disambiguation).
        public static func apply(to manager: NETunnelProviderManager,
                                 isOnDemandEnabled: Bool)

        // НОВЫЙ — единый source of truth для всех консьюмеров фазы 6c.
        // Вычисляет isOnDemandEnabled = loadAutoReconnectEnabled() && loadUserIntendedConnected()
        // и вызывает низкоуровневый apply. Закрывает B-04 (phantom connect) + W-04 (drift).
        public static func applyCurrentState(to manager: NETunnelProviderManager,
                                             userDefaults: UserDefaults = .standard)

        // Существующий reader — UserDefaults toggle (D-04 default ON).
        public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard,
                                                    key: String = "app.bbtb.autoReconnectEnabled") -> Bool

        // НОВЫЙ — reader user-intent флага. Тот же UserDefaults ключ, что пишет
        // UserIntentStore в TunnelController.swift (см. cross-plan contract в REVISION-LOG).
        // Default false: на свежей установке/после reinstall intent отсутствует → on-demand
        // НЕ включится сам, пока пользователь не нажмёт Connect.
        public static func loadUserIntendedConnected(userDefaults: UserDefaults = .standard,
                                                      key: String = "app.bbtb.userIntendedConnected") -> Bool
    }
    ```

    Внутренний контракт:
    - `apply(to:isOnDemandEnabled:)` ВСЕГДА записывает `manager.onDemandRules = [NEOnDemandRuleConnect with interfaceTypeMatch = .any]`. Если `isOnDemandEnabled == false`, правила всё равно остаются записанными (только `manager.isOnDemandEnabled` становится false). Это важно: re-enable через UI toggle не должен требовать вызова `provisionTunnelProfile` или импорта конфига.
    - `applyCurrentState(to:userDefaults:)` — high-level entry point. Body: `let enabled = loadAutoReconnectEnabled(userDefaults: userDefaults) && loadUserIntendedConnected(userDefaults: userDefaults); apply(to: manager, isOnDemandEnabled: enabled)`. Каждый callsite в Phase 6c (ConfigImporter.provisionTunnelProfile, SettingsViewModel.applyAutoReconnectToManager, OnDemandMigrationTask.runIfNeeded, TunnelController.connect/disconnect) использует именно этот метод — НЕ низкоуровневый `apply`.
    - `loadAutoReconnectEnabled` возвращает `true` если ключ никогда не записывался (свежая установка) — D-04 default ON. Использует `object(forKey:) as? Bool ?? true` (НЕ `.bool(forKey:)`, который default'ит в false).
    - `loadUserIntendedConnected` возвращает `false` если ключ никогда не записывался. Использует `object(forKey:) as? Bool ?? false` (default false — explicit Connect тап выставляет true; reinstall сбрасывает intent — это правильное поведение).
    - `apply` НЕ вызывает `saveToPreferences()` — это ответственность вызывающего (см. ConfigImporter в Wave 1). Builder только mutates in-memory manager state.

    Tests (all use SUT-isolated UserDefaults instances — never `.standard` — чтобы не загрязнять real preferences). **11 тестов total (Round 2: was 8, +3 for `applyCurrentState` × 2 + `loadUserIntendedConnected` × 1).**

    - Test 1 (`test_apply_enabled_writesConnectAnyRule`):
      Given a fresh `NETunnelProviderManager()`, call `apply(to: manager, isOnDemandEnabled: true)`.
      Assert: `manager.isOnDemandEnabled == true`, `manager.onDemandRules?.count == 1`,
              `manager.onDemandRules?.first is NEOnDemandRuleConnect`,
              `(manager.onDemandRules?.first as? NEOnDemandRuleConnect)?.interfaceTypeMatch == .any`.

    - Test 2 (`test_apply_disabled_writesIsOnDemandEnabledFalseButPreservesRules`):
      Same fresh manager. Call `apply(to: manager, isOnDemandEnabled: false)`.
      Assert: `manager.isOnDemandEnabled == false`, `manager.onDemandRules?.count == 1`
              (правила сохранены; см. Pitfall 9 RESEARCH — каждый apply записывает консистентный state).

    - Test 3 (`test_apply_isIdempotent_secondCallProducesIdenticalState`):
      Call `apply(to: manager, isOnDemandEnabled: true)` дважды. Assert: после второго вызова rules.count == 1
      (не накапливается), isOnDemandEnabled == true.

    - Test 4 (`test_apply_replacesPreviousRules`):
      Pre-set `manager.onDemandRules = [NEOnDemandRuleDisconnect()]` (или mock-NEOnDemandRule).
      Call `apply(to: manager, isOnDemandEnabled: true)`. Assert: only `NEOnDemandRuleConnect` остаётся (старые dropped).

    - Test 5 (`test_loadAutoReconnectEnabled_freshInstall_defaultsTrue`):
      Use fresh `UserDefaults(suiteName: "test-fresh-\(UUID().uuidString)")` (no key set).
      Call `loadAutoReconnectEnabled(userDefaults: ud)`. Assert: returns `true`.

    - Test 6 (`test_loadAutoReconnectEnabled_persistedFalse_returnsFalse`):
      Fresh suite UserDefaults. Set `ud.set(false, forKey: "app.bbtb.autoReconnectEnabled")`.
      Call `loadAutoReconnectEnabled(userDefaults: ud)`. Assert: returns `false`.

    - Test 7 (`test_loadAutoReconnectEnabled_persistedTrue_returnsTrue`):
      Fresh suite UserDefaults. Set `ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")`.
      Call `loadAutoReconnectEnabled(userDefaults: ud)`. Assert: returns `true`.

    - Test 8 (`test_loadAutoReconnectEnabled_customKey_usesCustomKey`):
      Pass `key: "custom.test.key"` к `loadAutoReconnectEnabled`. Set value под этим ключом
      в fresh suite. Assert returns the value.

    - **Test 9 (`test_loadUserIntendedConnected_freshInstall_defaultsFalse`)** — NEW for B-04:
      Fresh suite UserDefaults (no key set). Call `loadUserIntendedConnected(userDefaults: ud)`.
      Assert: returns `false`. Это критический контракт — на свежей установке intent отсутствует,
      `applyCurrentState` не активирует on-demand → нет phantom auto-connect.

    - **Test 10 (`test_applyCurrentState_intentFalse_writesIsOnDemandFalse`)** — NEW for B-04:
      Fresh suite. Set `ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")` (toggle ON)
      BUT не set `app.bbtb.userIntendedConnected` (intent отсутствует ≡ false).
      Fresh `NETunnelProviderManager()`. Call `applyCurrentState(to: manager, userDefaults: ud)`.
      Assert: `manager.isOnDemandEnabled == false` (intent gate работает), `manager.onDemandRules?.count == 1`
      (правила всё равно записаны — re-enable будет дешёвый когда intent flip true).

    - **Test 11 (`test_applyCurrentState_bothTrue_writesIsOnDemandTrue`)** — NEW for B-04:
      Fresh suite. Set both keys to true. Call `applyCurrentState(to: manager, userDefaults: ud)`.
      Assert: `manager.isOnDemandEnabled == true`, rules.count == 1.
  </behavior>
  <action>
    Сначала FAILING тесты в `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift`.

    Структура тест-файла:
    1. Header doc-comment ссылающийся на Plan 06C-01 / Wave 0 / D-24 category 1 (новый тест-файл для OnDemandRulesBuilder). Reference на B-04 + W-08 (Round 2 revisions).
    2. `import XCTest`, `import NetworkExtension`, `@testable import MainScreenFeature`.
    3. `final class OnDemandRulesBuilderTests: XCTestCase` с **11 методами** `test_...` по списку в `<behavior>` (Tests 1-8 как в Round 1 + Tests 9-11 новые для B-04).
    4. Helper: `private func freshSuite() -> UserDefaults` создаёт `UserDefaults(suiteName: "OnDemandTests-\(UUID().uuidString)")!` чтобы тесты были fully isolated.
    5. `tearDown` НЕ нужен потому что каждый тест создаёт свой uniquely-named suite (no shared state).
    6. Никаких calls к `manager.saveToPreferences()` — только in-memory property reads.

    После того как тесты компилируются и падают — пишем сам builder в `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift`:

    1. Header doc-comment на русском (per CLAUDE.md):
       - Ссылка на Phase 6c / Plan 06C-01 / D-01 / D-01b / D-02 / D-03 / D-04.
       - Объяснение почему `NEOnDemandRuleConnect`, не `NEEvaluateConnectionRule` (со ссылкой на 06C-RESEARCH.md anti-patterns).
       - **W-08 ordering contract:** Note в header doc-comment: «Phase 8 prepend-only — `NEOnDemandRuleEvaluateConnection` rules MUST go in front of the catch-all connect rule; `onDemandRules` is first-match-wins per Apple NetworkExtension semantics».
       - **B-04 contract:** Note про shared UserDefaults key с `UserIntentStore` (TunnelController.swift): «Builder reads `app.bbtb.userIntendedConnected` — этот ключ ПИШЕТ `UserIntentStore`. Контракт документирован в обеих файлах (cross-plan).»
       - Pattern reference: «Аналог `KillSwitch.apply` в `KillSwitch.swift`».
    2. `import Foundation`, `import NetworkExtension`, `import OSLog`.
    3. `public enum OnDemandRulesBuilder { ... }`:
       - `private static let log = Logger(subsystem: "app.bbtb.client", category: "ondemand-builder")`.
       - **`public static func apply(to manager: NETunnelProviderManager, isOnDemandEnabled: Bool)`** — body как в RESEARCH «Pattern 1»: вызывает `buildRules()`, replace `manager.onDemandRules`, set `manager.isOnDemandEnabled = isOnDemandEnabled`. Log один info-level event (privacy `.public` для bool). **NOTE: параметр переименован c `autoReconnectEnabled` (Round 2 B-04 fix).**
       - **`public static func applyCurrentState(to manager: NETunnelProviderManager, userDefaults: UserDefaults = .standard)`** — NEW for B-04. Body: `let toggle = loadAutoReconnectEnabled(userDefaults: userDefaults); let intent = loadUserIntendedConnected(userDefaults: userDefaults); apply(to: manager, isOnDemandEnabled: toggle && intent)`. Doc-comment: «Phase 6c single source of truth: все консьюмеры (ConfigImporter, SettingsViewModel, OnDemandMigrationTask, TunnelController) идут СЮДА. Низкоуровневый apply зарезервирован для тестов».
       - `public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard, key: String = "app.bbtb.autoReconnectEnabled") -> Bool` — body: `userDefaults.object(forKey: key) as? Bool ?? true` (D-04 default ON invariant).
       - **`public static func loadUserIntendedConnected(userDefaults: UserDefaults = .standard, key: String = "app.bbtb.userIntendedConnected") -> Bool`** — NEW for B-04. Body: `userDefaults.object(forKey: key) as? Bool ?? false`. **DEFAULT FALSE** (не true как у toggle) — на свежей установке/после reinstall intent отсутствует.
       - **`private static func buildRules() -> [NEOnDemandRule]`** — Phase 8 cut point. Phase 6c body: `let rule = NEOnDemandRuleConnect(); rule.interfaceTypeMatch = .any; return [rule]`. **W-08 doc-comment:**
         ```swift
         /// Returns the rule array. Phase 6c emits exactly one `NEOnDemandRuleConnect(.any)`.
         ///
         /// Phase 8 extensibility contract: future `NEOnDemandRuleEvaluateConnection` rules
         /// (per-SSID, per-domain) MUST be prepended to the array — `onDemandRules` is
         /// first-match-wins per Apple's NetworkExtension semantics. The catch-all
         /// connect rule remains the last entry so specific rules can short-circuit.
         private static func buildRules() -> [NEOnDemandRule] { ... }
         ```

    Запускаем тесты — должны pass (все 11).

    Тонкости:
    - НЕ инжектить `Logger` через параметр — это static enum, logger как `private static let`.
    - `interfaceTypeMatch` это property `NEOnDemandRule` базового класса, доступно у `NEOnDemandRuleConnect`.
    - `NEOnDemandRuleInterfaceType.any` доступен на всех supported платформах (iOS 18+ / macOS 15+).
    - Не пишем `disconnectOnSleep` или другие manager.protocolConfiguration changes — это responsibility ConfigImporter (Wave 1).
    - **B-04 cross-plan note:** ключ `app.bbtb.userIntendedConnected` тот же, что использует `UserIntentStore` в `TunnelController.swift` (~line 73 default param `key: String = "app.bbtb.userIntendedConnected"`). Reader builder'а просто читает то же значение — write остаётся в UserIntentStore (Phase 6c не меняет writer).
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandRulesBuilderTests</automated>
  </verify>
  <acceptance_criteria>
    - Все **11 тестов** pass (Round 2: было 8, добавлено 3 для B-04).
    - `grep -c "NEOnDemandRuleConnect" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1.
    - `grep -c "NEEvaluateConnectionRule\\|NEOnDemandRuleEvaluateConnection" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 0 (Phase 6c не использует — anti-pattern per RESEARCH).
    - `grep -c "interfaceTypeMatch" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1.
    - `grep -c "app.bbtb.autoReconnectEnabled" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1.
    - **`grep -c "app.bbtb.userIntendedConnected" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1** (B-04 — shared key with UserIntentStore).
    - `grep -c "?? true" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1 (D-04 default ON for toggle).
    - **`grep -c "?? false" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1** (B-04 — default false for intent).
    - `grep -c "public enum OnDemandRulesBuilder" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 1.
    - **`grep -c "func applyCurrentState" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 1** (B-04 single entry point).
    - **`grep -c "func loadUserIntendedConnected" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 1** (B-04 intent reader).
    - **`grep -c "isOnDemandEnabled:" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 2** (low-level apply signature + applyCurrentState body — Round 2 param rename).
    - **`grep -c "autoReconnectEnabled:" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 0** (Round 2: old param name should NOT appear as a function parameter; method `loadAutoReconnectEnabled` does not match this pattern because it lacks the trailing colon).
    - **`grep -c "first-match-wins\\|prepend" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1** (W-08 ordering contract).
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds (no compile errors anywhere).
    - **No existing files modified** — `git diff --name-only` shows ТОЛЬКО два новых файла (builder + tests).
  </acceptance_criteria>
  <done>OnDemandRulesBuilder существует как static enum с двумя public методами; 8 тестов проходят; нет regression в existing test suite; ни одно production-файло не тронуто кроме нового builder.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| UserDefaults `app.bbtb.autoReconnectEnabled` ↔ builder | Sandbox-protected per app; no cross-app access; Bool-only — no parse-time injection vector. |
| Builder ↔ NETunnelProviderManager properties | In-memory mutation only at Wave 0; persistence happens at Wave 1's saveToPreferences callsite. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06C-01-01 | Tampering | UserDefaults value manipulated to non-Bool (e.g., String) by stale data after upgrade | mitigate | `object(forKey:) as? Bool ?? true` graceful fallback: non-Bool → nil cast → default true. Test 5 validates fresh install path; ASVS V5 (UserDefaults `Bool`-only, no parse path) covered. |
| T-06C-01-02 | DoS | Builder called in tight loop allocates rules arrays | accept | Builder is leaf code — no callers in Wave 0. Wave 1+ callers (ConfigImporter, SettingsViewModel toggle handler) are user-event-driven, not hot path. No allocation explosion vector. |
</threat_model>

<verification>
- Compile: `cd BBTB && swift build --package-path Packages/AppFeatures`
- Unit tests: `cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandRulesBuilderTests` (expect 8 passing)
- Regression: `cd BBTB && swift test --package-path Packages/AppFeatures` full suite stays green (Wave 0 строго аддитивен).
- Source audit: `git status` shows ровно два новых файла — никаких modifications в существующих files.
- API stability check (Round 2): `grep -c "public static func apply\\b" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 1 (single low-level `apply` method) + `grep -c "public static func applyCurrentState\\b" ...` returns 1 (single high-level entry). Phase 8 не должен менять signatures.
</verification>

<success_criteria>
1. `OnDemandRulesBuilder.swift` существует как `public enum` в `MainScreenFeature` модуле.
2. `apply(to:isOnDemandEnabled:)` (Round 2 rename per B-04) производит ровно один `NEOnDemandRuleConnect` с `.interfaceTypeMatch = .any` и записывает `manager.isOnDemandEnabled = isOnDemandEnabled`.
3. `applyCurrentState(to:userDefaults:)` (NEW per B-04) — единый source of truth: вычисляет `toggle && intent` и зовёт низкоуровневый apply. Все Phase 6c консьюмеры используют именно его.
4. `loadAutoReconnectEnabled(userDefaults:key:)` возвращает `true` для свежей установки, иначе записанное значение.
5. `loadUserIntendedConnected(userDefaults:key:)` (NEW per B-04) возвращает `false` для свежей установки, иначе записанное значение. Reads тот же UserDefaults ключ, что пишет `UserIntentStore` в TunnelController.
6. **11** новых XCTest-методов проходят (Round 2: было 8, +3 для B-04); нет regression в AppFeatures test suite.
7. Builder использует **только** `NEOnDemandRuleConnect` (никакого `NEEvaluateConnectionRule` — anti-pattern per Apple staff thread/81249).
8. Builder API оставляет hook для Phase 8 (`buildRules()` extension point с inline note про prepend-only ordering — W-08).
9. Wave 0 строго аддитивен — никаких изменений в `TunnelController.swift`, `ConfigImporter.swift`, `MainScreenViewModel.swift`, `SettingsView*.swift`.
10. Реализация согласована с CLAUDE.md: doc-comments на русском, identifiers на английском.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-01-SUMMARY.md`. Include:
- Files created with line counts (builder + tests).
- Test names (11) + pass count (Round 2: 8 original + 3 new for B-04).
- Confirmation: ONLY two new files; no modifications elsewhere (cite `git status` output).
- Confirmation: `NEOnDemandRuleConnect(.any)` rule shape used; `NEEvaluateConnectionRule` NOT used (D-01 RESEARCH-correction applied).
- Reference D-01, D-01b, D-02, D-03, D-04, D-05.
- Note for Plan 06C-02: builder API is `OnDemandRulesBuilder.apply(to: manager, isOnDemandEnabled: ...)` + `applyCurrentState(to:userDefaults:)` (preferred high-level entry) + `loadAutoReconnectEnabled(...)` + `loadUserIntendedConnected(...)`. Plan 06C-02 ConfigImporter wiring uses `applyCurrentState`, NOT direct `apply` — see Round 2 revisions per B-04.
</output>
