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
    - "OnDemandRulesBuilder.apply(to:autoReconnectEnabled:) writes a single NEOnDemandRuleConnect(.any) rule and sets isOnDemandEnabled = autoReconnectEnabled on a NETunnelProviderManager"
    - "OnDemandRulesBuilder.loadAutoReconnectEnabled() returns true on fresh install (no UserDefaults value present) — Default ON per D-04"
    - "OnDemandRulesBuilder.loadAutoReconnectEnabled() returns the persisted Bool when UserDefaults key `app.bbtb.autoReconnectEnabled` was set"
    - "Builder always writes both rules array AND isOnDemandEnabled — `false` toggle still persists rules so re-enable is cheap (no provisionTunnelProfile needed)"
    - "Builder is a static enum namespace (no instance state) — testable without entitlements; mirrors KillSwitch.apply pattern"
    - "Public API of the builder is stable enough that Phase 8 can prepend NEOnDemandRuleEvaluateConnection rules without changing callsite signatures"
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift"
      provides: "enum OnDemandRulesBuilder with apply(to:autoReconnectEnabled:) + loadAutoReconnectEnabled()"
      min_lines: 60
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift"
      provides: "Tests for rule shape, isOnDemandEnabled mirror, UserDefaults default-ON, persistence after disable"
      min_lines: 110
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
- Phase 6c заменяет custom auto-reconnect machinery на iOS-нативный `isOnDemandEnabled` + `NEOnDemandRule*`. Wave 0 — фундамент: builder + UserDefaults reader. Без него никто не сможет писать правила консистентно.
- D-01 RESEARCH-уточнение: использовать `NEOnDemandRuleConnect(interfaceType: .any)` (WireGuard pattern), а не `NEEvaluateConnectionRule` (последний требует non-empty matchDomains — Apple staff на forum thread/81249). Архитектурное намерение D-01 (extensibility под Phase 8) сохраняется через API — Phase 8 добавит `NEOnDemandRuleEvaluateConnection` в массив правил без изменения callsites.
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
// в массив правил ДО connectRule (first-match-wins). API `apply(to:autoReconnectEnabled:)`
// остаётся той же signature; внутри Phase 8 расширит `buildRules()`.

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
    Builder API (locked):
    ```swift
    public enum OnDemandRulesBuilder {
        public static func apply(to manager: NETunnelProviderManager, autoReconnectEnabled: Bool)
        public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard,
                                                    key: String = "app.bbtb.autoReconnectEnabled") -> Bool
    }
    ```

    Внутренний контракт:
    - `apply` ВСЕГДА записывает `manager.onDemandRules = [NEOnDemandRuleConnect with interfaceTypeMatch = .any]`. Если `autoReconnectEnabled == false`, правила всё равно остаются записанными (только `isOnDemandEnabled` становится false). Это важно: re-enable через UI toggle не должен требовать вызова `provisionTunnelProfile` или импорта конфига.
    - `loadAutoReconnectEnabled` возвращает `true` если ключ никогда не записывался (свежая установка) — D-04 default ON. Использует `object(forKey:) as? Bool ?? true` (НЕ `.bool(forKey:)`, который default'ит в false).
    - `apply` НЕ вызывает `saveToPreferences()` — это ответственность вызывающего (см. ConfigImporter в Wave 1). Builder только mutates in-memory manager state.

    Tests (all use SUT-isolated UserDefaults instances — never `.standard` — чтобы не загрязнять real preferences):

    - Test 1 (`test_apply_enabled_writesConnectAnyRule`):
      Given a fresh `NETunnelProviderManager()`, call `apply(to: manager, autoReconnectEnabled: true)`.
      Assert: `manager.isOnDemandEnabled == true`, `manager.onDemandRules?.count == 1`,
              `manager.onDemandRules?.first is NEOnDemandRuleConnect`,
              `(manager.onDemandRules?.first as? NEOnDemandRuleConnect)?.interfaceTypeMatch == .any`.

    - Test 2 (`test_apply_disabled_writesIsOnDemandEnabledFalseButPreservesRules`):
      Same fresh manager. Call `apply(autoReconnectEnabled: false)`.
      Assert: `manager.isOnDemandEnabled == false`, `manager.onDemandRules?.count == 1`
              (правила сохранены; см. Pitfall 9 RESEARCH — каждый apply записывает консистентный state).

    - Test 3 (`test_apply_isIdempotent_secondCallProducesIdenticalState`):
      Call `apply(autoReconnectEnabled: true)` дважды. Assert: после второго вызова rules.count == 1
      (не накапливается), isOnDemandEnabled == true.

    - Test 4 (`test_apply_replacesPreviousRules`):
      Pre-set `manager.onDemandRules = [NEOnDemandRuleDisconnect()]` (или mock-NEOnDemandRule).
      Call `apply(autoReconnectEnabled: true)`. Assert: only `NEOnDemandRuleConnect` остаётся (старые dropped).

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
  </behavior>
  <action>
    Сначала FAILING тесты в `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnDemandRulesBuilderTests.swift`.

    Структура тест-файла:
    1. Header doc-comment ссылающийся на Plan 06C-01 / Wave 0 / D-24 category 1 (новый тест-файл для OnDemandRulesBuilder).
    2. `import XCTest`, `import NetworkExtension`, `@testable import MainScreenFeature`.
    3. `final class OnDemandRulesBuilderTests: XCTestCase` с восемью методами `test_...` по списку выше.
    4. Helper: `private func freshSuite() -> UserDefaults` создаёт `UserDefaults(suiteName: "OnDemandTests-\(UUID().uuidString)")!` чтобы тесты были fully isolated.
    5. `tearDown` НЕ нужен потому что каждый тест создаёт свой uniquely-named suite (no shared state).
    6. Никаких calls к `manager.saveToPreferences()` — только in-memory property reads.

    После того как тесты компилируются и падают (manager rules nil, builder не существует) — пишем сам builder в `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift`:

    1. Header doc-comment на русском (per CLAUDE.md):
       - Ссылка на Phase 6c / D-01 / D-01b / D-02 / D-03 / D-04.
       - Объяснение почему `NEOnDemandRuleConnect`, не `NEEvaluateConnectionRule` (со ссылкой на 06C-RESEARCH.md anti-patterns).
       - Note про Phase 8 extension path: «Phase 8 добавит NEOnDemandRuleEvaluateConnection в начало массива rules перед connectRule».
       - Pattern reference: «Аналог `KillSwitch.apply` в `KillSwitch.swift`».
    2. `import Foundation`, `import NetworkExtension`, `import OSLog`.
    3. `public enum OnDemandRulesBuilder { ... }`:
       - `private static let userDefaultsKey = "app.bbtb.autoReconnectEnabled"` (constant, доступен через `defaultKey` если нужно тестам — но default parameter уже это покрывает).
       - `private static let log = Logger(subsystem: "app.bbtb.client", category: "ondemand-builder")`.
       - `public static func apply(to manager: NETunnelProviderManager, autoReconnectEnabled: Bool)` — body как в RESEARCH «Pattern 1»: создать `NEOnDemandRuleConnect`, set `.interfaceTypeMatch = .any`, replace `manager.onDemandRules = [rule]`, set `manager.isOnDemandEnabled = autoReconnectEnabled`. Log один info-level event с values (privacy `.public` для bool, никаких sensitive данных).
       - `public static func loadAutoReconnectEnabled(userDefaults: UserDefaults = .standard, key: String = "app.bbtb.autoReconnectEnabled") -> Bool` — body: `userDefaults.object(forKey: key) as? Bool ?? true` (D-04 default ON invariant).
       - `private static func buildRules() -> [NEOnDemandRule]` — выделяем чтобы Phase 8 имел chиз-cut point. Phase 6c body: `let rule = NEOnDemandRuleConnect(); rule.interfaceTypeMatch = .any; return [rule]`.
       - Phase 8 note inline: `// Phase 8: prepend NEOnDemandRuleEvaluateConnection rules here (first-match-wins).`

    Запускаем тесты — должны pass.

    Тонкости:
    - НЕ инжектить `Logger` через параметр — это static enum, logger как `private static let`.
    - `interfaceTypeMatch` это property `NEOnDemandRule` базового класса, доступно у `NEOnDemandRuleConnect`.
    - `NEOnDemandRuleInterfaceType.any` доступен на всех supported платформах (iOS 18+ / macOS 15+).
    - Не пишем `disconnectOnSleep` или другие manager.protocolConfiguration changes — это responsibility ConfigImporter (Wave 1).
  </action>
  <verify>
    <automated>cd BBTB && swift test --package-path Packages/AppFeatures --filter OnDemandRulesBuilderTests</automated>
  </verify>
  <acceptance_criteria>
    - Все 8 тестов pass.
    - `grep -c "NEOnDemandRuleConnect" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1.
    - `grep -c "NEEvaluateConnectionRule\\|NEOnDemandRuleEvaluateConnection" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 0 (Phase 6c не использует — anti-pattern per RESEARCH).
    - `grep -c "interfaceTypeMatch" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1.
    - `grep -c "app.bbtb.autoReconnectEnabled" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1.
    - `grep -c "?? true" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns ≥ 1 (D-04 default ON).
    - `grep -c "public enum OnDemandRulesBuilder" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 1.
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
- API stability check: `grep -c "public static func apply" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift` returns 1 (single public apply method — Phase 8 не должен менять signature).
</verification>

<success_criteria>
1. `OnDemandRulesBuilder.swift` существует как `public enum` в `MainScreenFeature` модуле.
2. `apply(to:autoReconnectEnabled:)` производит ровно один `NEOnDemandRuleConnect` с `.interfaceTypeMatch = .any` и записывает `manager.isOnDemandEnabled = autoReconnectEnabled`.
3. `loadAutoReconnectEnabled(userDefaults:key:)` возвращает `true` для свежей установки, иначе записанное значение.
4. 8 новых XCTest-методов проходят; нет regression в AppFeatures test suite.
5. Builder использует **только** `NEOnDemandRuleConnect` (никакого `NEEvaluateConnectionRule` — anti-pattern per Apple staff thread/81249).
6. Builder API оставляет hook для Phase 8 (`buildRules()` extension point с inline note).
7. Wave 0 строго аддитивен — никаких изменений в `TunnelController.swift`, `ConfigImporter.swift`, `MainScreenViewModel.swift`, `SettingsView*.swift`.
8. Реализация согласована с CLAUDE.md: doc-comments на русском, identifiers на английском.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-01-SUMMARY.md`. Include:
- Files created with line counts (builder + tests).
- Test names (8) + pass count.
- Confirmation: ONLY two new files; no modifications elsewhere (cite `git status` output).
- Confirmation: `NEOnDemandRuleConnect(.any)` rule shape used; `NEEvaluateConnectionRule` NOT used (D-01 RESEARCH-correction applied).
- Reference D-01, D-01b, D-02, D-03, D-04, D-05.
- Note for Plan 06C-02: builder API is `OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: ...)` + `loadAutoReconnectEnabled(...)`. Use these — no codebase exploration needed.
</output>
