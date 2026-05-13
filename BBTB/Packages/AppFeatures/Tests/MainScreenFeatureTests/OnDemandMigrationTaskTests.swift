// OnDemandMigrationTaskTests.swift — Phase 6c / Plan 06C-03 / Task 2.
//
// Покрывает 5 тестов (Round 2: was 4, +1 для B-05 transient-failure safety):
//   1. test_runIfNeeded_alreadyMigrated_isNoOp — флаг уже true → no-op.
//   2. test_runIfNeeded_loadAllThrows_doesNotSetFlag — NEW Round 2 B-05.
//      Transient XPC failure при `loadAllFromPreferences()` НЕ выставляет флаг
//      → retry next launch.
//   3. test_runIfNeeded_emptyManagers_setsFlag — нет manager'ов (fresh install
//      или residue от другого VPN-app) → флаг выставляется.
//   4. test_runIfNeeded_isIdempotent_twoCallsSafe — два consecutive вызова
//      не крашат.
//   5. test_runIfNeeded_respectsTogglePersisted — миграция не трогает toggle.
//
// Tests используют isolated `UserDefaults(suiteName:)` чтобы не загрязнять
// `.standard` и не leak'ать между тестами (паттерн из OnDemandRulesBuilderTests).

import XCTest
import NetworkExtension
@testable import MainScreenFeature

final class OnDemandMigrationTaskTests: XCTestCase {

    // MARK: - Helpers

    private static let migratedKey = "app.bbtb.autoReconnectMigratedV6c"
    private static let toggleKey = "app.bbtb.autoReconnectEnabled"

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OnDemandMigrationTests-\(UUID().uuidString)")!
    }

    // MARK: - Tests

    /// Test 1 — flag уже true → no-op (idempotent).
    func test_runIfNeeded_alreadyMigrated_isNoOp() async {
        let ud = makeIsolatedDefaults()
        ud.set(true, forKey: Self.migratedKey)

        // Используем loader, который должен НЕ быть вызван (флаг уже true).
        var loaderCalls = 0
        await OnDemandMigrationTask.runIfNeeded(userDefaults: ud, loader: {
            loaderCalls += 1
            return []
        })

        XCTAssertEqual(loaderCalls, 0, "loader НЕ должен вызываться когда флаг уже true")
        XCTAssertTrue(ud.bool(forKey: Self.migratedKey), "флаг должен остаться true")
    }

    /// Test 2 (NEW Round 2 B-05) — transient throw от loadAllFromPreferences
    /// НЕ выставляет флаг → migration retry на следующем launch.
    func test_runIfNeeded_loadAllThrows_doesNotSetFlag() async {
        let ud = makeIsolatedDefaults()
        // Pre-condition: flag начинает с false.
        XCTAssertFalse(ud.bool(forKey: Self.migratedKey))

        let transientError = NSError(
            domain: "TestTransient",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "simulated XPC failure"]
        )

        await OnDemandMigrationTask.runIfNeeded(userDefaults: ud, loader: {
            throw transientError
        })

        XCTAssertFalse(
            ud.bool(forKey: Self.migratedKey),
            "B-05: на transient throw флаг должен остаться false → retry next launch"
        )
    }

    /// Test 3 — empty managers (fresh install или нет наших manager'ов) →
    /// флаг выставляется (одно из confirmed-empty paths).
    func test_runIfNeeded_emptyManagers_setsFlag() async {
        let ud = makeIsolatedDefaults()
        XCTAssertFalse(ud.bool(forKey: Self.migratedKey))

        await OnDemandMigrationTask.runIfNeeded(userDefaults: ud, loader: {
            []  // empty array — confirmed-empty path
        })

        XCTAssertTrue(
            ud.bool(forKey: Self.migratedKey),
            "флаг должен быть true после confirmed-empty migration"
        )
    }

    /// Counter actor для подсчёта вызовов loader без захвата `UserDefaults`
    /// в @Sendable closure (UserDefaults НЕ Sendable; capture даёт warning).
    actor LoaderCounter {
        var count: Int = 0
        func increment() { count += 1 }
        func get() -> Int { count }
    }

    /// Test 4 — два consecutive вызова безопасны (idempotency через флаг).
    func test_runIfNeeded_isIdempotent_twoCallsSafe() async {
        let ud = makeIsolatedDefaults()
        let counter = LoaderCounter()

        let loader: @Sendable () async throws -> [NETunnelProviderManager] = { [counter] in
            await counter.increment()
            return []
        }

        await OnDemandMigrationTask.runIfNeeded(userDefaults: ud, loader: loader)
        await OnDemandMigrationTask.runIfNeeded(userDefaults: ud, loader: loader)

        XCTAssertTrue(ud.bool(forKey: Self.migratedKey), "флаг true после 1-го вызова")
        let calls = await counter.get()
        XCTAssertEqual(
            calls,
            1,
            "loader должен быть вызван ровно 1 раз: второй вызов рано выходит по флагу"
        )
    }

    /// Test 5 — migration не трогает toggle UserDefaults значение.
    func test_runIfNeeded_respectsTogglePersisted() async {
        let ud = makeIsolatedDefaults()
        // Пользователь явно выключил toggle (или это значение из старой установки).
        ud.set(false, forKey: Self.toggleKey)

        await OnDemandMigrationTask.runIfNeeded(userDefaults: ud, loader: { [] })

        XCTAssertTrue(ud.bool(forKey: Self.migratedKey))
        XCTAssertFalse(
            ud.bool(forKey: Self.toggleKey),
            "migration НЕ должна изменять toggle UserDefaults значение"
        )
    }
}
