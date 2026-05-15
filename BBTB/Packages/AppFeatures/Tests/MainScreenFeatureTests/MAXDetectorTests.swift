// MAXDetectorTests.swift — Phase 11 / Plan 04 / Task 4.1.
//
// Unit-тесты на `MAXDetector` через mock'и URLSchemeQueryable / WorkspaceQueryable.
// Production callsite (BBTB_iOSApp/macOSApp) использует real wrappers вокруг
// UIApplication.shared / NSWorkspace.shared — это integration boundary;
// здесь мы покрываем pure detection логику (iteration, first-match-wins,
// nil-return-when-no-match) без real iOS/macOS singletons (которые в
// SPM xctest context недоступны / непредсказуемы).
//
// Cross-platform invariant test (`test_candidates_nonEmpty_andNoDuplicates`)
// бежит на ОБОИХ платформах — guard от случайного удаления / дублирования
// candidate'ов при будущих refactor'ах (Plan 11-04 Pitfall 1 sync constraint).

import XCTest
@testable import MainScreenFeature

@MainActor
final class MAXDetectorTests: XCTestCase {

    // MARK: - Mocks

    /// Mock URLSchemeQueryable. `@unchecked Sendable` потому что test-only
    /// контролируемая mutation (registered set заполняется единожды в test setup).
    private final class MockSchemeQuery: URLSchemeQueryable, @unchecked Sendable {
        var registered: Set<String> = []
        func canOpenURL(_ url: URL) -> Bool {
            // Compare on scheme component — игнорируем "://" и прочее.
            registered.contains(url.scheme ?? "")
        }
    }

    /// Mock WorkspaceQueryable.
    private final class MockWorkspace: WorkspaceQueryable, @unchecked Sendable {
        var installed: [String: URL] = [:]
        func urlForApplication(withBundleIdentifier identifier: String) -> URL? {
            installed[identifier]
        }
    }

    // MARK: - iOS path

    #if os(iOS)
    func test_iOS_detectsFirstMatchingScheme() {
        let mock = MockSchemeQuery()
        mock.registered = ["max-app"]
        let result = MAXDetector.detectIOS(query: mock)
        XCTAssertEqual(result, "max-app")
    }

    func test_iOS_returnsNilWhenNoneRegistered() {
        let mock = MockSchemeQuery()
        // registered = empty set — никакая scheme не matched.
        let result = MAXDetector.detectIOS(query: mock)
        XCTAssertNil(result)
    }

    func test_iOS_prefersFirstCandidateWhenMultipleRegistered() {
        // Both "vkmax" и "max" зарегистрированы (как если бы у пользователя
        // был странный set-up с двумя приложениями), но iteration order
        // canonical → должны вернуть "max" (первый в iOSSchemeCandidates).
        let mock = MockSchemeQuery()
        mock.registered = ["vkmax", "max"]
        let result = MAXDetector.detectIOS(query: mock)
        XCTAssertEqual(result, "max")
    }

    func test_iOS_handlesArbitraryRegisteredScheme() {
        // Если бы у пользователя зарегистрирована только "ru-max" — должны
        // её и вернуть. Сanary что iteration не bail'ит на середине.
        let mock = MockSchemeQuery()
        mock.registered = ["ru-max"]
        let result = MAXDetector.detectIOS(query: mock)
        XCTAssertEqual(result, "ru-max")
    }
    #endif

    // MARK: - macOS path

    #if os(macOS)
    func test_macOS_detectsFirstMatchingBundle() {
        let mock = MockWorkspace()
        mock.installed["chat.max.app"] = URL(fileURLWithPath: "/Applications/MAX.app")
        let result = MAXDetector.detectMacOS(workspace: mock)
        XCTAssertEqual(result?.bundleID, "chat.max.app")
        XCTAssertEqual(result?.path, "/Applications/MAX.app")
    }

    func test_macOS_returnsNilWhenNoneInstalled() {
        let mock = MockWorkspace()
        // installed = empty dict — никакой bundle не найден.
        let result = MAXDetector.detectMacOS(workspace: mock)
        XCTAssertNil(result)
    }

    func test_macOS_prefersFirstCandidateWhenMultipleInstalled() {
        // Если бы Apple parallel-running случилось — два bundle ID одновременно
        // указывают на MAX-приложение. iteration по macOSBundleCandidates
        // — первый match wins. "ru.vk.max" первый в списке.
        let mock = MockWorkspace()
        mock.installed["chat.max.app"] = URL(fileURLWithPath: "/Applications/MAX.app")
        mock.installed["ru.vk.max"] = URL(fileURLWithPath: "/Applications/MAX-VK.app")
        let result = MAXDetector.detectMacOS(workspace: mock)
        XCTAssertEqual(result?.bundleID, "ru.vk.max")
        XCTAssertEqual(result?.path, "/Applications/MAX-VK.app")
    }

    func test_macOS_handlesArbitraryRegisteredBundle() {
        // Если бы у пользователя установлена только "ru.max.messenger" —
        // должны её и вернуть (последняя в списке — canary против early-exit).
        let mock = MockWorkspace()
        mock.installed["ru.max.messenger"] = URL(fileURLWithPath: "/Applications/MAX-Msg.app")
        let result = MAXDetector.detectMacOS(workspace: mock)
        XCTAssertEqual(result?.bundleID, "ru.max.messenger")
    }
    #endif

    // MARK: - Cross-platform invariants

    func test_candidates_nonEmpty_andNoDuplicates() {
        // Guard от случайного удаления всех candidate'ов или дублирования.
        // Phase 11 / Pitfall 1: iOSSchemeCandidates ДОЛЖЕН быть в sync с
        // Info.plist LSApplicationQueriesSchemes; если кто-то почистит список
        // → этот тест сломается раньше чем production behavior.
        #if os(iOS)
        XCTAssertFalse(MAXDetector.iOSSchemeCandidates.isEmpty, "iOS candidate schemes list пуст")
        XCTAssertEqual(
            Set(MAXDetector.iOSSchemeCandidates).count,
            MAXDetector.iOSSchemeCandidates.count,
            "iOS candidate schemes содержат дубликаты"
        )
        // Defensive: каждый candidate scheme должен быть non-empty (иначе
        // `URL(string: "://")` вернёт nil → silent skip).
        for scheme in MAXDetector.iOSSchemeCandidates {
            XCTAssertFalse(scheme.isEmpty, "Пустой scheme в iOSSchemeCandidates")
        }
        #endif
        #if os(macOS)
        XCTAssertFalse(MAXDetector.macOSBundleCandidates.isEmpty, "macOS candidate bundles list пуст")
        XCTAssertEqual(
            Set(MAXDetector.macOSBundleCandidates).count,
            MAXDetector.macOSBundleCandidates.count,
            "macOS candidate bundles содержат дубликаты"
        )
        for bid in MAXDetector.macOSBundleCandidates {
            XCTAssertFalse(bid.isEmpty, "Пустой bundle ID в macOSBundleCandidates")
        }
        #endif
    }
}
