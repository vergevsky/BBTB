// SettingsViewModelAutoReconnectTests.swift — Phase 6c / Plan 06C-03 / Task 1.
//
// Тесты `SettingsViewModel.autoReconnectEnabled` (D-04 default ON) и
// `applyAutoReconnectToManager()` helper (D-06, W-03 nonisolated, B-05 swallow).
//
// Стратегия изоляции: каждый тест clear'ит общий ключ
// `app.bbtb.autoReconnectEnabled` в setUp/tearDown — @AppStorage привязан к
// `UserDefaults.standard`, поэтому изоляция per-key, не per-suite.
// Тот же pattern что в `SettingsViewModelDNSTests`.

import XCTest
@testable import SettingsFeature

@MainActor
final class SettingsViewModelAutoReconnectTests: XCTestCase {

    private static let key = "app.bbtb.autoReconnectEnabled"

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.key)
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Test 1 — D-04 default ON: на свежей установке (ключ ещё не записан)
    /// `autoReconnectEnabled == true`.
    func test_freshInstall_autoReconnectEnabled_isTrue() {
        let vm = SettingsViewModel()
        XCTAssertTrue(vm.autoReconnectEnabled,
                      "D-04 invariant: default ON на свежей установке")
    }

    /// Test 2 — toggle OFF персистится в UserDefaults через @AppStorage.
    func test_setAutoReconnectFalse_persistsInUserDefaults() {
        let vm = SettingsViewModel()
        vm.autoReconnectEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.key),
                       "Toggle OFF должен записать false в UserDefaults")
    }

    /// Test 3 — toggle ON персистится в UserDefaults.
    func test_setAutoReconnectTrue_persistsTrue() {
        let vm = SettingsViewModel()
        vm.autoReconnectEnabled = false  // прокачиваем «not default»
        vm.autoReconnectEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.key),
                      "Toggle ON должен записать true в UserDefaults")
    }

    /// Test 4 — `applyAutoReconnectToManager()` гладко обрабатывает отсутствие
    /// manager'а: в `swift test` без entitlements `loadAllFromPreferences()`
    /// возвращает `[]` или throws — обе ветки обернуты в do/catch (W-03 / B-05
    /// swallow). Helper не должен бросать и не должен крашить.
    func test_applyAutoReconnectToManager_swallowsErrorWhenNoManager() async {
        let vm = SettingsViewModel()
        // Crash-free invariant: helper НЕ throws, любые NEM ошибки swallowed.
        await vm.applyAutoReconnectToManager()
        // Контракт: @AppStorage сам по себе уже сохранил toggle;
        // helper НЕ перезаписывает значение.
        XCTAssertTrue(vm.autoReconnectEnabled,
                      "Helper не должен менять @AppStorage значение")
    }
}
