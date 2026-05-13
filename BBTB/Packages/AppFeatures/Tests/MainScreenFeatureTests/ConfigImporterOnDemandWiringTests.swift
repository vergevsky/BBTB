// ConfigImporterOnDemandWiringTests.swift — Phase 6c / Plan 06C-02 / Wave 1.
//
// Тесты фиксируют интеграционный контракт между `DefaultTunnelProvisioner`
// (ConfigImporter.swift) и `OnDemandRulesBuilder.applyCurrentState` —
// единственная точка вычисления `isOnDemandEnabled` через AND-объединение
// UI toggle (`app.bbtb.autoReconnectEnabled`, D-04 default ON) и user intent
// (`app.bbtb.userIntendedConnected`, B-04 default FALSE).
//
// **Стратегия тестирования (B-07 / Round 2):**
// Тесты вызывают `OnDemandRulesBuilder.applyCurrentState(to:userDefaults:)`
// напрямую с инжектированным изолированным UserDefaults suite. Они НЕ зовут
// `provisionTunnelProfile(configJSON:serverHost:)` потому что `saveToPreferences`
// требует NetworkExtension entitlement, недоступный в `swift test`. Wiring
// (что callsite в `ConfigImporter` использует именно `applyCurrentState`)
// фиксируется через `grep` acceptance_criteria в Task 2 плана.
//
// **Покрытие (B-04 / W-04 / Pitfalls 8, 9):**
//   1. Свежая установка БЕЗ intent (тогда toggle default ON, intent default
//      FALSE) → manager.isOnDemandEnabled=false. Критический контракт: первый
//      import config'а НЕ запускает phantom auto-connect, пока user не нажмёт
//      Connect (Phase 6 bug class — теперь OS-driven, blocked through gate).
//   2. Both toggle ON + intent ON → manager.isOnDemandEnabled=true. Сценарий
//      «existing user апгрейднулся, ConfigImporter повторно импортирует
//      config (например, обновил subscription) — on-demand остаётся on».
//   3. Toggle OFF + intent ON → manager.isOnDemandEnabled=false. Pitfall 4:
//      user отключил toggle при активном туннеле — туннель не tear down, но
//      Apple's on-demand off.
//   4. Replays — два последовательных вызова с разными UserDefaults values
//      должны давать консистентный state (Pitfall 8 mitigation: каждый call
//      читает fresh UserDefaults, не cache).
//
// **B-07 fix (Round 2):** В этом тест-файле NET no `<verify>` block в plan —
// Task 2 GREEN verify покрывает wiring. Эти тесты компилируются и **проходят**
// сразу — они тестируют API, который уже создан в Plan 06C-01 Round 2.

import XCTest
import NetworkExtension
@testable import MainScreenFeature

final class ConfigImporterOnDemandWiringTests: XCTestCase {

    // MARK: - Helpers

    /// Изолированный UserDefaults suite — никакого `.standard`, никакого
    /// shared state между тестами. Уникальное имя через UUID.
    private func freshSuite() -> UserDefaults {
        UserDefaults(suiteName: "ConfigImporterOnDemandWiringTests-\(UUID().uuidString)")!
    }

    // MARK: - Tests

    /// Test 1 — fresh install (toggle default ON, intent default FALSE) →
    /// manager.isOnDemandEnabled=false. B-04 phantom-connect mitigation.
    func test_applyCurrentState_freshInstall_withoutIntent_writesIsOnDemandFalse() {
        let ud = freshSuite()
        // Никаких ключей не выставлено — это путь свежей установки.
        // toggle загрузится как default ON (?? true), intent как default FALSE (?? false).

        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)

        XCTAssertFalse(manager.isOnDemandEnabled,
                       "B-04: свежая установка без Connect тапа → on-demand НЕ активен (нет phantom auto-connect)")
        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "Правила всё равно записаны — re-enable дешёвый когда user нажмёт Connect")
        XCTAssertTrue(manager.onDemandRules?.first is NEOnDemandRuleConnect,
                      "Должно быть NEOnDemandRuleConnect (D-01)")
    }

    /// Test 2 — both toggle ON + intent ON → on-demand активен.
    /// Сценарий «existing user, повторный re-import config'а».
    func test_applyCurrentState_toggleOnIntentOn_writesIsOnDemandTrue() {
        let ud = freshSuite()
        ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")
        ud.set(true, forKey: "app.bbtb.userIntendedConnected")

        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)

        XCTAssertTrue(manager.isOnDemandEnabled,
                      "Toggle ON + intent ON → on-demand активен")
        XCTAssertEqual(manager.onDemandRules?.count, 1)
        XCTAssertTrue(manager.onDemandRules?.first is NEOnDemandRuleConnect)
    }

    /// Test 3 — toggle OFF + intent ON → on-demand НЕ активен.
    /// Pitfall 4: пользователь отключил toggle при активном туннеле.
    func test_applyCurrentState_toggleOffIntentOn_writesIsOnDemandFalse() {
        let ud = freshSuite()
        ud.set(false, forKey: "app.bbtb.autoReconnectEnabled")
        ud.set(true, forKey: "app.bbtb.userIntendedConnected")

        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)

        XCTAssertFalse(manager.isOnDemandEnabled,
                       "Pitfall 4: toggle OFF → on-demand off, даже если intent ON")
        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "Правила записаны (re-enable дешёвый через toggle flip)")
    }

    /// Test 4 — replays: каждый вызов читает fresh UserDefaults values.
    /// Pitfall 8 mitigation: applyCurrentState НЕ кеширует toggle/intent.
    func test_applyCurrentState_replays_pickFreshUserDefaultsValues() {
        let ud = freshSuite()
        ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")
        ud.set(true, forKey: "app.bbtb.userIntendedConnected")

        let manager = NETunnelProviderManager()

        // Первый вызов: оба true → on-demand on.
        OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)
        XCTAssertTrue(manager.isOnDemandEnabled,
                      "Initial state: both flags true → on-demand on")

        // Изменяем intent на false (пользователь сделал явный disconnect).
        ud.set(false, forKey: "app.bbtb.userIntendedConnected")

        // Второй вызов: intent уже false → on-demand off.
        OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)
        XCTAssertFalse(manager.isOnDemandEnabled,
                       "Pitfall 8: каждый applyCurrentState читает fresh UserDefaults — intent flip к false должен дать on-demand off")
        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "Правила остались записаны после flip")
    }
}
