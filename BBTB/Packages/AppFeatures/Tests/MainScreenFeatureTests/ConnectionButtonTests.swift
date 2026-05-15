// ConnectionButtonTests.swift — Phase 11 / Plan 07 / Task 7.1 / UX-08.
//
// Тесты на pure helper `ConnectionButton.isConnecting`. View body (ProgressView
// overlay, opacity modifier на power-icon) тестируется визуально в Wave 4
// human-verify checkpoint (Task 7.4) — здесь нет ViewInspector, поэтому tap'ы
// на view-level state мы оставляем UAT'у.
//
// Подход: Alternative A (см. Plan 11-07 Task 7.1) — `isConnecting` сделан
// `internal` для @testable visibility; тесты вызывают property напрямую через
// instance, не симулируя body re-render.
//
// Что НЕ тестируется здесь и почему:
// - symbolEffect / accessibilityIdentifier / disabled — compile-time literals
//   и Apple-managed modifiers; regression caught manual UAT.
// - ProgressView visibility в дереве — нет ViewInspector, нет XCTViewController.
// - ARC retain cycle от action closure — out of scope D-05.

import XCTest
@testable import MainScreenFeature

@MainActor
final class ConnectionButtonTests: XCTestCase {

    /// D-05 — .connecting → isConnecting должен быть true.
    func test_isConnecting_trueWhenStateConnecting() {
        let button = ConnectionButton(state: .connecting, action: {})
        XCTAssertTrue(button.isConnecting,
                      ".connecting → isConnecting должен быть true")
    }

    /// .idle (есть конфиг, но не подключено) → spinner НЕ показывается.
    func test_isConnecting_falseForIdle() {
        let button = ConnectionButton(state: .idle, action: {})
        XCTAssertFalse(button.isConnecting,
                       ".idle → isConnecting должен быть false")
    }

    /// .connected → spinner НЕ показывается (соединение установлено).
    func test_isConnecting_falseForConnected() {
        let button = ConnectionButton(state: .connected(since: Date()), action: {})
        XCTAssertFalse(button.isConnecting,
                       ".connected → isConnecting должен быть false")
    }

    /// .error → spinner НЕ показывается (D-05 strict: только .connecting).
    func test_isConnecting_falseForError() {
        let button = ConnectionButton(state: .error(message: "test"), action: {})
        XCTAssertFalse(button.isConnecting,
                       ".error → isConnecting должен быть false")
    }

    /// .empty (нет конфига) → spinner НЕ показывается (кнопка disabled).
    func test_isConnecting_falseForEmpty() {
        let button = ConnectionButton(state: .empty, action: {})
        XCTAssertFalse(button.isConnecting,
                       ".empty → isConnecting должен быть false")
    }
}
