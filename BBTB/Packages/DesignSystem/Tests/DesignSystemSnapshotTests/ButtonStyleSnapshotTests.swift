// ButtonStyleSnapshotTests.swift — Phase 12 / Plan 12-01 / Task 5 / DS-10 / DS-15.
//
// Snapshot baseline для PrimaryButtonStyle + SecondaryButtonStyle (M7 prereq).
// Это proof-of-infrastructure для DS-15: убеждаемся что swift-snapshot-testing 1.18.3+
// корректно работает в DesignSystem package перед расширением test corpus в Plan 12-02.
//
// Подход: `.image(layout: .fixed(width:height:))` + perceptualPrecision per UI-SPEC §5
// (0.98 для text + AA; 1.0 для solid fills — gradient strokes тут не задействованы).
//
// PLATFORM GATE (deviation from plan — Rule 3 blocking-issue fix):
//   swift-snapshot-testing's `Snapshotting where Value: SwiftUI.View, Format == UIImage`
//   только iOS/tvOS (SwiftUIView.swift §17 `#if os(iOS) || os(tvOS)`). На macOS SwiftUI.View
//   нет `.image(layout: .fixed(...))` extension — был бы compile error. Поэтому обёртываем
//   весь test class в `#if os(iOS) || os(tvOS)`. CLI fast path (`swift test` на macOS host) —
//   skip; iOS Simulator (`xcodebuild test -destination 'platform=iOS Simulator'`) — actual run.
//   Это согласно RESEARCH §6.4-6.5: snapshot infra iOS-only.
//
// RECORD PROTOCOL (N3 revision — env-var based, no manual isRecording uncomment cycle):
//   - Default: `assertSnapshot` использует library default `record: .missing` (создаёт
//     baseline только если его НЕТ, существующие PNG не overwrite'ит).
//   - First-time baseline: запустить `xcodebuild test ...` — первый прогон создаёт PNG
//     под `__Snapshots__/ButtonStyleSnapshotTests/`; assertSnapshot FAIL'ит first time
//     с сообщением "No reference was found on disk."; коммитим PNG; повторный прогон PASS.
//   - Full re-record (когда design меняется): `SNAPSHOT_TESTING_RECORD=1 xcodebuild test
//     -only-testing DesignSystemSnapshotTests/ButtonStyleSnapshotTests` — env var
//     overwrite'ит существующие baseline'ы.
//   - Local block-scoped re-record (опционально для surgical refresh одного теста):
//     обернуть `withSnapshotTesting(record: .all) { ... }` в test body — НЕ глобальная
//     модификация, не нужно commit-cycle с раскомментированием/коммитом/закомментированием.
//
// Что НЕ тестируется здесь:
// - Reduce-Motion fallback (UI-SPEC §3.8) — static snapshot не различает default vs
//   reduce-motion когда `isPressed = false`; динамическое поведение тестируется UAT'ом.
// - Pressed-state — отдельный тест в Plan 12-02 если потребуется (Phase 12 D-04 tight scope).

import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignSystem

#if os(iOS) || os(tvOS)

@MainActor
final class ButtonStyleSnapshotTests: XCTestCase {

    /// DS-10 / M7 — PrimaryButton Dark default state (accent green pill, white text).
    func testPrimaryButton_default_dark() {
        let view = Button("Подключить", action: {})
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 300, height: 56)
            .background(DS.Color.canvas)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 300, height: 56)
            )
        )
    }

    /// DS-10 / M7 — SecondaryButton Dark default state (white pill, dark text).
    func testSecondaryButton_default_dark() {
        let view = Button("Отмена", action: {})
            .buttonStyle(SecondaryButtonStyle())
            .frame(width: 300, height: 56)
            .background(DS.Color.canvas)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 300, height: 56)
            )
        )
    }

    /// DS-10 / D-05 wire-only — PrimaryButton Light default state (verification что Light
    /// mode wire correctly resolves через UIColor/NSColor dynamic provider).
    func testPrimaryButton_default_light() {
        let view = Button("Подключить", action: {})
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 300, height: 56)
            .background(DS.Color.canvas)
            .preferredColorScheme(.light)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 300, height: 56)
            )
        )
    }
}

#endif  // os(iOS) || os(tvOS)
