// ManagerSelectorTests.swift — Phase 6c / Plan 06C-02 / Task 0.
//
// Unit tests для `ManagerSelector` — single source of truth helper фильтрации
// `NETunnelProviderManager` по providerBundleIdentifier. Используется в 5
// callsites Phase 6c (ConfigImporter, SettingsViewModel, OnDemandMigrationTask,
// TunnelController.cachedManager, TunnelController.handleWake). Закрывает
// B-06 (multi-manager safety) + W-07 (shared helper).
//
// Стратегия: тесты НЕ вызывают `loadAllFromPreferences()` (entitlement-gated)
// — мы строим in-memory массив `NETunnelProviderManager` инстансов и проверяем
// что filter правильно опускает чужие managers по их providerBundleIdentifier.
// Это работает в test env без entitlements потому что мы НЕ зовём
// saveToPreferences (только in-memory mutation `protocolConfiguration`).
//
// Покрытие:
//   1. Пустой input → пустой output (sanity).
//   2. Mixed input (наш ios + чужой) → возвращается ровно один наш.
//   3. macOS bundle ID match (`app.bbtb.client.macos.tunnel`) — Set покрывает
//      обе платформы по дефолту.

import XCTest
import NetworkExtension
@testable import MainScreenFeature

final class ManagerSelectorTests: XCTestCase {

    // MARK: - Helpers

    /// Создаёт `NETunnelProviderManager` с заданным `providerBundleIdentifier`.
    /// Не вызывает `saveToPreferences()` — только in-memory mutation.
    private func makeManager(providerBundleID: String) -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleID
        // `serverAddress` обязателен на NETunnelProviderProtocol при ассертах
        // в некоторых iOS builds — ставим валидный hostname.
        proto.serverAddress = "test.example.com"
        manager.protocolConfiguration = proto
        return manager
    }

    // MARK: - Tests

    func test_ourManagers_emptyInput_returnsEmpty() {
        let result = ManagerSelector.ourManagers(from: [])
        XCTAssertEqual(result.count, 0,
                       "Пустой input → пустой output")
    }

    func test_ourManagers_mixedInput_returnsOnlyOurs() {
        let ours = makeManager(providerBundleID: "app.bbtb.client.ios.tunnel")
        let foreign = makeManager(providerBundleID: "com.example.other.vpn")

        let result = ManagerSelector.ourManagers(from: [foreign, ours])

        XCTAssertEqual(result.count, 1,
                       "Должен остаться ровно один наш manager")
        let resultProto = result.first?.protocolConfiguration as? NETunnelProviderProtocol
        XCTAssertEqual(resultProto?.providerBundleIdentifier,
                       "app.bbtb.client.ios.tunnel",
                       "Result должен содержать именно наш iOS manager")
    }

    func test_ourManagers_macOSBundleID_alsoMatches() {
        let macos = makeManager(providerBundleID: "app.bbtb.client.macos.tunnel")
        let foreign = makeManager(providerBundleID: "com.thirdparty.tunnel")

        let result = ManagerSelector.ourManagers(from: [foreign, macos])

        XCTAssertEqual(result.count, 1,
                       "Default ourProviderBundleIdentifiers Set покрывает macOS bundle ID")
        let resultProto = result.first?.protocolConfiguration as? NETunnelProviderProtocol
        XCTAssertEqual(resultProto?.providerBundleIdentifier,
                       "app.bbtb.client.macos.tunnel",
                       "Result должен содержать macOS manager")
    }
}
