// OnDemandRulesBuilderTests.swift — Phase 6c / Plan 06C-01 / Wave 0 / Task 1.
//
// Unit tests для `OnDemandRulesBuilder` (D-24 категория 1 — конфигурация правил
// + UserDefaults readers, без entitlements).
//
// Покрывает контракты:
//  - `apply(to:isOnDemandEnabled:)` пишет один `NEOnDemandRuleConnect(.any)`
//    rule и зеркалит передаваемый Bool в `manager.isOnDemandEnabled`
//    (Round 2 B-04 fix: параметр переименован с `autoReconnectEnabled` в
//     `isOnDemandEnabled` для disambiguation между UI-toggle и финальным
//     manager-флагом).
//  - При `isOnDemandEnabled == false` правила всё равно записаны (persistence
//    после disable — re-enable не должен звать `provisionTunnelProfile`).
//  - Идемпотентность повторных `apply` (не накапливаем rules).
//  - Replace-семантика: предыдущие правила (если были) вытесняются.
//  - `loadAutoReconnectEnabled` default ON для свежей установки (D-04).
//  - `loadAutoReconnectEnabled` персистент path: true/false читаются.
//  - Кастомный ключ корректно подхватывается.
//
// Round 2 (B-04) additions:
//  - `loadUserIntendedConnected` default FALSE для свежей установки —
//    критический контракт против phantom auto-connect (Phase 6 bug class).
//    Ключ `app.bbtb.userIntendedConnected` — тот же, что пишет
//    `UserIntentStore` в `TunnelController.swift`.
//  - `applyCurrentState(to:userDefaults:)` — единая точка входа для всех
//    Phase 6c консьюмеров. Считает `isOnDemandEnabled = toggle && intent`
//    и вызывает низкоуровневый apply. Покрытие:
//      - toggle ON + intent OFF (отсутствует) → manager.isOnDemandEnabled = false
//        (rules всё равно записаны — re-enable будет дешёвый).
//      - toggle ON + intent ON → manager.isOnDemandEnabled = true.
//
// Стратегия изоляции: каждый тест создаёт уникальный `UserDefaults`
// suite (`OnDemandTests-<UUID>`) — никакого общения с `.standard`, нет
// необходимости в tearDown.
//
// Тесты НЕ вызывают `manager.saveToPreferences()` — только проверка
// in-memory свойств после apply. Это позволяет запускать через
// `swift test` без entitlements.

import XCTest
import NetworkExtension
@testable import MainScreenFeature

final class OnDemandRulesBuilderTests: XCTestCase {

    // MARK: - Helpers

    /// Создаёт изолированный `UserDefaults` suite для одного теста.
    /// Уникальное имя — никакой shared state между тестами.
    private func freshSuite() -> UserDefaults {
        UserDefaults(suiteName: "OnDemandTests-\(UUID().uuidString)")!
    }

    // MARK: - Tests 1-4: apply(to:isOnDemandEnabled:) contract

    func test_apply_enabled_writesConnectAnyRule() {
        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.apply(to: manager, isOnDemandEnabled: true)

        XCTAssertTrue(manager.isOnDemandEnabled,
                      "isOnDemandEnabled должен зеркалить переданное true")
        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "Phase 6c эмитирует ровно одно правило")
        XCTAssertTrue(manager.onDemandRules?.first is NEOnDemandRuleConnect,
                      "Правило должно быть NEOnDemandRuleConnect (D-01 RESEARCH correction — не NEEvaluateConnectionRule)")
        let connectRule = manager.onDemandRules?.first as? NEOnDemandRuleConnect
        XCTAssertEqual(connectRule?.interfaceTypeMatch, .any,
                       "interfaceTypeMatch должен быть .any — WireGuard pattern")
    }

    func test_apply_disabled_writesIsOnDemandEnabledFalseButPreservesRules() {
        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.apply(to: manager, isOnDemandEnabled: false)

        XCTAssertFalse(manager.isOnDemandEnabled,
                       "isOnDemandEnabled должен быть false")
        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "Правила должны остаться записанными — re-enable не должен звать provisionTunnelProfile (Pitfall 9 RESEARCH)")
        XCTAssertTrue(manager.onDemandRules?.first is NEOnDemandRuleConnect)
    }

    func test_apply_isIdempotent_secondCallProducesIdenticalState() {
        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.apply(to: manager, isOnDemandEnabled: true)
        OnDemandRulesBuilder.apply(to: manager, isOnDemandEnabled: true)

        XCTAssertTrue(manager.isOnDemandEnabled)
        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "Повторный apply не должен накапливать rules")
    }

    func test_apply_replacesPreviousRules() {
        let manager = NETunnelProviderManager()

        // Pre-set: правило другого типа должно быть вытеснено.
        let disconnectRule = NEOnDemandRuleDisconnect()
        disconnectRule.interfaceTypeMatch = .any
        manager.onDemandRules = [disconnectRule]

        OnDemandRulesBuilder.apply(to: manager, isOnDemandEnabled: true)

        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "После apply должно быть ровно одно правило (старые dropped)")
        XCTAssertTrue(manager.onDemandRules?.first is NEOnDemandRuleConnect,
                      "Replace-семантика: NEOnDemandRuleDisconnect должен исчезнуть")
        XCTAssertFalse(manager.onDemandRules?.first is NEOnDemandRuleDisconnect)
    }

    // MARK: - Tests 5-8: loadAutoReconnectEnabled contract (D-04 default ON)

    func test_loadAutoReconnectEnabled_freshInstall_defaultsTrue() {
        let ud = freshSuite()
        // No key set — fresh install path.

        let value = OnDemandRulesBuilder.loadAutoReconnectEnabled(userDefaults: ud)

        XCTAssertTrue(value, "D-04: на свежей установке auto-reconnect default ON")
    }

    func test_loadAutoReconnectEnabled_persistedFalse_returnsFalse() {
        let ud = freshSuite()
        ud.set(false, forKey: "app.bbtb.autoReconnectEnabled")

        let value = OnDemandRulesBuilder.loadAutoReconnectEnabled(userDefaults: ud)

        XCTAssertFalse(value, "Персистентный false должен читаться как false")
    }

    func test_loadAutoReconnectEnabled_persistedTrue_returnsTrue() {
        let ud = freshSuite()
        ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")

        let value = OnDemandRulesBuilder.loadAutoReconnectEnabled(userDefaults: ud)

        XCTAssertTrue(value, "Персистентный true должен читаться как true")
    }

    func test_loadAutoReconnectEnabled_customKey_usesCustomKey() {
        let ud = freshSuite()
        let customKey = "custom.test.key"
        ud.set(false, forKey: customKey)

        let value = OnDemandRulesBuilder.loadAutoReconnectEnabled(
            userDefaults: ud,
            key: customKey
        )

        XCTAssertFalse(value, "Builder должен использовать переданный ключ")
    }

    // MARK: - Test 9 (B-04 NEW): loadUserIntendedConnected default FALSE

    func test_loadUserIntendedConnected_freshInstall_defaultsFalse() {
        let ud = freshSuite()
        // No key set — fresh install / reinstall path.

        let value = OnDemandRulesBuilder.loadUserIntendedConnected(userDefaults: ud)

        XCTAssertFalse(value,
                       "B-04: на свежей установке intent должен быть false. " +
                       "Это критический контракт: applyCurrentState не включит on-demand " +
                       "пока пользователь не нажмёт Connect (нет phantom auto-connect).")
    }

    // MARK: - Tests 10-11 (B-04 NEW): applyCurrentState gate

    func test_applyCurrentState_intentFalse_writesIsOnDemandFalse() {
        let ud = freshSuite()
        // Toggle ON, но intent отсутствует (фактически false).
        ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")
        // Намеренно НЕ выставляем `app.bbtb.userIntendedConnected`.

        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)

        XCTAssertFalse(manager.isOnDemandEnabled,
                       "B-04 intent gate: toggle ON + intent OFF → on-demand НЕ активен")
        XCTAssertEqual(manager.onDemandRules?.count, 1,
                       "Правила всё равно записаны — re-enable будет дешёвый когда intent flip true")
    }

    func test_applyCurrentState_bothTrue_writesIsOnDemandTrue() {
        let ud = freshSuite()
        ud.set(true, forKey: "app.bbtb.autoReconnectEnabled")
        ud.set(true, forKey: "app.bbtb.userIntendedConnected")

        let manager = NETunnelProviderManager()

        OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: ud)

        XCTAssertTrue(manager.isOnDemandEnabled,
                      "toggle ON + intent ON → on-demand активен")
        XCTAssertEqual(manager.onDemandRules?.count, 1)
        XCTAssertTrue(manager.onDemandRules?.first is NEOnDemandRuleConnect)
    }
}
