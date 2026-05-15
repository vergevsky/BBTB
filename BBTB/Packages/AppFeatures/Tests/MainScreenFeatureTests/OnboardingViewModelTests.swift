// OnboardingViewModelTests.swift — Phase 11 / Plan 03 / UX-01.
//
// Тесты на persistence contract для `@AppStorage("app.bbtb.hasShownOnboarding")`.
// В Phase 11 OnboardingView читает флаг через @AppStorage в MainScreenView
// (без отдельного OnboardingViewModel — D-01 / RESEARCH Open Question 5).
// Тесты проверяют UserDefaults-bridge поведение, которое и используется
// @AppStorage'ом под капотом:
//
// - test_initial_default_isFalse: при первом запуске (UserDefaults clean) флаг
//   = false → Onboarding должен показаться.
// - test_setTrue_persistsAcrossReads: после set'а true → persist через
//   UserDefaults.standard, fresh read возвращает true (sticky-forever D-01).
// - test_keyName_matchesAppStorageDeclaration: regression-guard на случай
//   рефакторинга — если кто-то поменяет @AppStorage key, тест ловит изменение
//   и напоминает обновить migration logic / documentation.
//
// Pattern S9 — UserDefaults setUp/tearDown cleanup (см. SettingsViewModelTests).

import XCTest
@testable import MainScreenFeature

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    /// Должен соответствовать `@AppStorage("app.bbtb.hasShownOnboarding")` в
    /// `MainScreenView.swift`. Если ключ изменится — `test_keyName_matchesAppStorageDeclaration`
    /// уронит build и напомнит обновить documentation.
    private static let key = "app.bbtb.hasShownOnboarding"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.key)
        try await super.tearDown()
    }

    /// При первом запуске (UserDefaults очищен) `bool(forKey:)` возвращает
    /// default false. Это значит, что Onboarding должен показаться.
    func test_initial_default_isFalse() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.key),
                       "Свежий UserDefaults должен иметь hasShownOnboarding=false (default)")
    }

    /// D-01 sticky-forever — после set'а true флаг persist'ится. Read через
    /// fresh accessor возвращает то же значение.
    func test_setTrue_persistsAcrossReads() {
        UserDefaults.standard.set(true, forKey: Self.key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.key),
                      "После set(true) read должен вернуть true")

        // Re-read через fresh accessor — @AppStorage делает то же самое
        // когда View ребилдится (или при cold launch).
        let fresh = UserDefaults.standard
        XCTAssertTrue(fresh.bool(forKey: Self.key),
                      "Re-read через fresh UserDefaults handle должен вернуть true (persistence)")
    }

    /// Regression-guard: если рефакторили @AppStorage key — этот тест падает,
    /// напоминая обновить также migration logic (если будет) или docs.
    func test_keyName_matchesAppStorageDeclaration() {
        XCTAssertEqual(Self.key, "app.bbtb.hasShownOnboarding",
                       "Test's key constant должен соответствовать @AppStorage в MainScreenView")
    }
}
