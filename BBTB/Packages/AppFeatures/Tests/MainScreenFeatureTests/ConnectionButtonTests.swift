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
import SwiftUI
import DesignSystem
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

    // MARK: - Phase 12 / Plan 12-02 / Task 1 / DS-09 / M3 — fillColor switch на DS.Color.
    //
    // W2 fix (Plan 12-02 revision iteration 1): `fillColor` мигрировал из
    // `private` в `internal` для @testable visibility — тот же Alternative A
    // pattern что в Phase 11 D-05 / Plan 11-07 Task 7.1 для `isConnecting`.
    //
    // Стратегия assertions: сравниваем SwiftUI.Color через `String(describing:)`.
    // Это семантический dump, который отличает `DS.Color.controlIdle` от
    // `DS.Color.accent` / `DS.Color.error` (разные dynamic providers
    // компилируются в разные SwiftUI representations), но НЕ зависит от
    // unstable `UIColor(SwiftUI.Color).resolvedColor(with:)` API в Swift 6
    // strict-concurrency mode (план: «Альтернативный path»).
    //
    // Russian assertion messages per CLAUDE.md.

    /// .idle → fillColor резолвит DS.Color.controlIdle (Figma idle variant).
    func test_fillColor_idleReturnsControlIdle() {
        let button = ConnectionButton(state: .idle, action: {})
        XCTAssertEqual(
            String(describing: button.fillColor),
            String(describing: DS.Color.controlIdle),
            "DS-09 / M3 — .idle должен резолвить DS.Color.controlIdle (#222222 Dark)"
        )
    }

    /// .connected → fillColor резолвит DS.Color.accent (#14664B Dark).
    func test_fillColor_connectedReturnsAccent() {
        let button = ConnectionButton(state: .connected(since: Date()), action: {})
        XCTAssertEqual(
            String(describing: button.fillColor),
            String(describing: DS.Color.accent),
            "DS-09 / M3 — .connected должен резолвить DS.Color.accent (#14664B Dark)"
        )
    }

    /// .error → fillColor резолвит DS.Color.error (#661414 Dark).
    func test_fillColor_errorReturnsError() {
        let button = ConnectionButton(state: .error(message: "тестовая ошибка"), action: {})
        XCTAssertEqual(
            String(describing: button.fillColor),
            String(describing: DS.Color.error),
            "DS-09 / M3 — .error должен резолвить DS.Color.error (#661414 Dark)"
        )
    }
}
