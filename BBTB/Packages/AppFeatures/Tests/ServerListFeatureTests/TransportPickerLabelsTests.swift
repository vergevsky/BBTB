// TransportPickerLabelsTests.swift — Phase 11 / 11-01 / Task 1.2.
//
// LOC-02 lint guard для TransportPicker:
// - проверяет, что L10n.transportLabel* accessor'ы существуют и возвращают
//   non-empty значения (compile-time guard — если кто-то удалил ключ,
//   тест не скомпилируется),
// - гарантирует уникальность поднимаемых ключей: если кто-то случайно
//   замапит два label на один ключ (copy-paste reg), Set.count != 5.
//
// Note: при запуске через `swift test` (SPM) `Localizable.xcstrings` не
// компилируется в `.strings` (только Xcode build phase делает это через
// xcassetcatalog/stringsdict). Поэтому `NSLocalizedString` в SPM-test
// контексте возвращает raw key как fallback — для production-сборки
// (Xcode → Tuist → BBTB.xcworkspace) ключи резолвятся в нормальные ru/en
// значения. Этот тест НЕ проверяет фактический перевод (это делает Xcode UI
// snapshot test), а только наличие accessor'ов и уникальность keys.
//
// Регрессию «Text("TCP")» (raw literal в SwiftUI Text) ловит grep gate
// в acceptance criteria Plan 11-01 — отдельный shell-уровень.

import XCTest
@testable import ServerListFeature
import Localization

final class TransportPickerLabelsTests: XCTestCase {

    /// L10n.transportLabel* accessor'ы существуют, callable, non-empty.
    /// Если кто-то удалил ключ из L10n.swift — тест не скомпилируется.
    /// Если NSLocalizedString вернул пустую строку (broken bundle) — тест упадёт.
    func test_transportLabels_resolveViaL10n() {
        let pairs: [(name: String, value: String)] = [
            ("transportLabelTcp",         L10n.transportLabelTcp),
            ("transportLabelWebSocket",   L10n.transportLabelWebSocket),
            ("transportLabelGrpc",        L10n.transportLabelGrpc),
            ("transportLabelHttp2",       L10n.transportLabelHttp2),
            ("transportLabelHttpUpgrade", L10n.transportLabelHttpUpgrade),
        ]
        for pair in pairs {
            XCTAssertFalse(
                pair.value.isEmpty,
                "L10n.\(pair.name) вернул пустую строку — bundle/xcstrings setup сломан."
            )
        }
    }

    /// Пять transport labels должны соответствовать пяти разным ключам
    /// (даже если в SPM-test `NSLocalizedString` возвращает raw key —
    /// уникальность raw keys всё равно гарантирует, что в xcstrings
    /// каждый label маппится на отдельную запись).
    func test_transportLabels_areUnique() {
        let values: [String] = [
            L10n.transportLabelTcp,
            L10n.transportLabelWebSocket,
            L10n.transportLabelGrpc,
            L10n.transportLabelHttp2,
            L10n.transportLabelHttpUpgrade,
        ]
        let unique = Set(values)
        XCTAssertEqual(
            unique.count, 5,
            "Transport labels должны быть уникальными — получили \(unique.count) уникальных: \(values)"
        )
    }
}
