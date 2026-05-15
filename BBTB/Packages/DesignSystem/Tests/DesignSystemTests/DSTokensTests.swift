// DSTokensTests.swift — Phase 12 / Plan 12-01 / Task 1 / DS-02..DS-06.
//
// Численные assertions для DS.Radius.section/sheet, DS.Blur.pill, DS.Typography.Size
// (7-tuple constants), DS.ConnectionButtonSize (phase 12 updated numerics),
// DS.Typography.expanded() helper + 9 sized presets + 6 deprecated aliases compile-check.
//
// См. RESEARCH §2.2 (lines 262-301), CODE-CONNECT.md §2.2 + §3, PATTERNS §MOD-1.
//
// RU error messages per PATTERNS §«Shared Patterns 5» (русские сообщения для assertion'ов).

import XCTest
import SwiftUI
@testable import DesignSystem

final class DSTokensTests: XCTestCase {

    // MARK: - DS-03 / M9 + M10 — Radius (section + sheet)

    func test_radius_sectionAndSheet() {
        XCTAssertEqual(
            DS.Radius.section, 24,
            "DS-03 / M10 — DS.Radius.section должен быть 24pt (Figma DS/Radius/section). См. CODE-CONNECT.md §2.2."
        )
        XCTAssertEqual(
            DS.Radius.sheet, 32,
            "DS-03 / M9 — DS.Radius.sheet должен быть 32pt (Figma DS/Radius/sheet). См. CODE-CONNECT.md §2.2."
        )
    }

    // MARK: - DS-04 — Blur.pill

    func test_blur_pill() {
        XCTAssertEqual(
            DS.Blur.pill, 4,
            "DS-04 — DS.Blur.pill должен быть 4pt (Figma DS/Blur/pill). См. CODE-CONNECT.md §2.2."
        )
    }

    // MARK: - DS-02 — Typography.Size 7-tuple

    func test_typographySize_sevenConstants() {
        XCTAssertEqual(
            DS.Typography.Size.display, 48,
            "DS-02 — Typography.Size.display = 48pt (Figma DS/Typography/Size/display). См. CODE-CONNECT.md §3."
        )
        XCTAssertEqual(
            DS.Typography.Size.title, 16,
            "DS-02 — Typography.Size.title = 16pt (Figma DS/Typography/Size/title)."
        )
        XCTAssertEqual(
            DS.Typography.Size.labelButton, 14,
            "DS-02 — Typography.Size.labelButton = 14pt (Figma DS/Typography/Size/labelButton)."
        )
        XCTAssertEqual(
            DS.Typography.Size.body, 12,
            "DS-02 — Typography.Size.body = 12pt (Figma DS/Typography/Size/body)."
        )
        XCTAssertEqual(
            DS.Typography.Size.tips, 10,
            "DS-02 — Typography.Size.tips = 10pt (Figma DS/Typography/Size/tips)."
        )
        XCTAssertEqual(
            DS.Typography.Size.caption, 9,
            "DS-02 — Typography.Size.caption = 9pt (Figma DS/Typography/Size/caption)."
        )
        XCTAssertEqual(
            DS.Typography.Size.micro, 8,
            "DS-02 — Typography.Size.micro = 8pt (Figma DS/Typography/Size/micro)."
        )
    }

    // MARK: - DS-05 — ConnectionButtonSize updated numerics (M1 + M2)

    func test_connectionButtonSize_phase12Values() {
        XCTAssertEqual(
            DS.ConnectionButtonSize.compactDiameter, 280,
            "DS-05 / M1 — ConnectionButtonSize.compactDiameter Phase 12 update 140→280 (Figma BBTB v3)."
        )
        XCTAssertEqual(
            DS.ConnectionButtonSize.regularDiameter, 320,
            "DS-05 / M1 — ConnectionButtonSize.regularDiameter Phase 12 update 160→320 (Figma BBTB v3)."
        )
        XCTAssertEqual(
            DS.ConnectionButtonSize.compactIcon, 112,
            "DS-05 / M2 — ConnectionButtonSize.compactIcon Phase 12 update 56→112 (Figma BBTB v3)."
        )
        XCTAssertEqual(
            DS.ConnectionButtonSize.regularIcon, 128,
            "DS-05 / M2 — ConnectionButtonSize.regularIcon Phase 12 update 64→128 (Figma BBTB v3)."
        )
    }

    // MARK: - DS-06 — Typography presets compile-check + B4 deprecated-alias proxy cross-check

    func test_typographyPresets_compileCheck() {
        // Все 9 sized presets должны существовать (compile-check). Если хотя бы
        // один не определён, файл не скомпилируется и тест провалится compile-time.
        let _: Font = DS.Typography.displayTimer
        let _: Font = DS.Typography.titleScreen
        let _: Font = DS.Typography.titleSection
        let _: Font = DS.Typography.titleUppercase
        let _: Font = DS.Typography.labelButton
        let _: Font = DS.Typography.bodyDefault
        let _: Font = DS.Typography.bodyCaption
        let _: Font = DS.Typography.bodyMicro
        let _: Font = DS.Typography.tipsLight

        // B4 cross-check: deprecated `body` alias должен идти через `expanded()` helper
        // и быть равен `bodyDefault`. SwiftUI.Font не имеет публичного Equatable; используем
        // string-description как proxy (захватывает size + weight + width modifier).
        // Если alias body вернёт другой Font (например legacy `.body` system style),
        // дескрипция будет отличаться. См. RESEARCH §2.2 «Migration plan».
        XCTAssertEqual(
            String(describing: DS.Typography.body),
            String(describing: DS.Typography.bodyDefault),
            "DS-06 / B4 — deprecated alias DS.Typography.body должен идти через expanded() helper и быть равен bodyDefault. См. RESEARCH §2.2 Migration plan."
        )

        // Compile-check для оставшихся 5 deprecated aliases (display, title, callout, subheadline, caption)
        let _: Font = DS.Typography.display
        let _: Font = DS.Typography.title
        let _: Font = DS.Typography.callout
        let _: Font = DS.Typography.subheadline
        let _: Font = DS.Typography.caption
    }
}
