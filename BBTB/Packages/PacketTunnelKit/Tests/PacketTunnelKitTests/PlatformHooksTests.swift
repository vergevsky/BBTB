#if os(macOS)
import XCTest
@testable import PacketTunnelKit

/// Phase 10 / KILL-04 — PlatformHooks.shouldDisableEnforceRoutes() unit tests.
///
/// Проверяет что macOS-only хук читает App Group UserDefaults, а не возвращает
/// hardcoded false (Phase 1 заглушку).
final class PlatformHooksTests: XCTestCase {

    private let suiteKey = "app.bbtb.macOSDisableEnforceRoutes"
    private let suiteName = "group.app.bbtb.shared"

    override func setUp() {
        super.setUp()
        // Очистить ключ до теста
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
    }

    override func tearDown() {
        super.tearDown()
        // Очистить ключ после теста
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
    }

    /// Test 1: ключ отсутствует → shouldDisableEnforceRoutes() возвращает false (safe default).
    func test_shouldDisableEnforceRoutes_default_false() {
        // Ключ не записан → должен вернуть false
        XCTAssertFalse(PlatformHooks.shouldDisableEnforceRoutes(),
                       "Default (ключ отсутствует) — должен быть false (enforceRoutes stays enabled)")
    }

    /// Test 2: ключ=true в App Group → shouldDisableEnforceRoutes() возвращает true.
    func test_shouldDisableEnforceRoutes_reads_true_from_app_group() {
        UserDefaults(suiteName: suiteName)?.set(true, forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
        XCTAssertTrue(PlatformHooks.shouldDisableEnforceRoutes(),
                      "При macOSDisableEnforceRoutes=true — должен вернуть true")
    }

    /// Test 3: ключ=false в App Group → shouldDisableEnforceRoutes() возвращает false.
    func test_shouldDisableEnforceRoutes_reads_false_from_app_group() {
        UserDefaults(suiteName: suiteName)?.set(false, forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
        XCTAssertFalse(PlatformHooks.shouldDisableEnforceRoutes(),
                       "При macOSDisableEnforceRoutes=false — должен вернуть false")
    }
}
#endif
