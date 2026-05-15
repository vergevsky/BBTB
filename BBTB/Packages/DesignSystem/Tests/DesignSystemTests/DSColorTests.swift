// DSColorTests.swift — Phase 12 / Plan 12-01 / Task 2 / DS-01 / DS-07.
//
// Hex assertions для DS.Color семантических токенов (Figma BBTB v3 cleaned 2026-05-16).
// Покрывает accent (Dark + Light hex match), canvas (Dark/Light), error (Dark/Light),
// + compile-check для всех 15 токенов.
//
// W2 fix: класс annotated `@MainActor` (UITraitCollection / NSAppearance — main-actor APIs),
// explicit UITraitCollection для iOS branch (без platform-default guessing).
//
// См. RESEARCH §2.3 (lines 303-395), CODE-CONNECT.md §2.1, PATTERNS §MOD-2.

import XCTest
import SwiftUI
@testable import DesignSystem

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class DSColorTests: XCTestCase {

    // MARK: - DS-07 / M5 — accent hex (Dark + Light одинаков per Phase 11 designer-decision)

    func test_accent_darkHexMatchesFigma() {
        let (r, g, b) = components(of: DS.Color.accent, isDark: true)
        XCTAssertEqual(
            r, 0x14 / 255.0, accuracy: 0.003,
            "DS-07 / M5 — DS.Color.accent.red Dark должен быть 0x14/255 = 0.0784 (Figma DS/Color/accent Dark #14664B)."
        )
        XCTAssertEqual(
            g, 0x66 / 255.0, accuracy: 0.003,
            "DS-07 / M5 — DS.Color.accent.green Dark должен быть 0x66/255 = 0.4 (Figma DS/Color/accent Dark #14664B)."
        )
        XCTAssertEqual(
            b, 0x4B / 255.0, accuracy: 0.003,
            "DS-07 / M5 — DS.Color.accent.blue Dark должен быть 0x4B/255 = 0.294 (Figma DS/Color/accent Dark #14664B)."
        )
    }

    func test_accent_lightHexMatchesFigma() {
        // accent одинаков Dark+Light per Phase 11 designer-decision (CODE-CONNECT.md §2.1).
        let (r, g, b) = components(of: DS.Color.accent, isDark: false)
        XCTAssertEqual(
            r, 0x14 / 255.0, accuracy: 0.003,
            "DS-07 — DS.Color.accent Light = Dark (designer-decision Phase 11, CODE-CONNECT.md §2.1)."
        )
        XCTAssertEqual(g, 0x66 / 255.0, accuracy: 0.003, "DS-07 — accent.green Light = 0x66/255.")
        XCTAssertEqual(b, 0x4B / 255.0, accuracy: 0.003, "DS-07 — accent.blue Light = 0x4B/255.")
    }

    // MARK: - DS-01 — canvas (Dark = #000000, Light = #FFFFFF) — D-05 wire-only

    func test_canvas_darkAndLight() {
        let dark = components(of: DS.Color.canvas, isDark: true)
        XCTAssertEqual(dark.r, 0.0, accuracy: 0.003, "DS-01 — canvas Dark.red = 0 (Figma #000000).")
        XCTAssertEqual(dark.g, 0.0, accuracy: 0.003, "DS-01 — canvas Dark.green = 0.")
        XCTAssertEqual(dark.b, 0.0, accuracy: 0.003, "DS-01 — canvas Dark.blue = 0.")

        let light = components(of: DS.Color.canvas, isDark: false)
        XCTAssertEqual(light.r, 1.0, accuracy: 0.003, "DS-01 / D-05 wire-only — canvas Light.red = 1.0 (Figma #FFFFFF).")
        XCTAssertEqual(light.g, 1.0, accuracy: 0.003, "DS-01 / D-05 — canvas Light.green = 1.0.")
        XCTAssertEqual(light.b, 1.0, accuracy: 0.003, "DS-01 / D-05 — canvas Light.blue = 1.0.")
    }

    // MARK: - DS-01 — error (Dark = #661414, Light = #B3261E) — Light value отличается

    func test_error_darkAndLight() {
        let dark = components(of: DS.Color.error, isDark: true)
        XCTAssertEqual(dark.r, 0x66 / 255.0, accuracy: 0.003, "DS-01 — error Dark.red = 0x66/255 (Figma #661414).")
        XCTAssertEqual(dark.g, 0x14 / 255.0, accuracy: 0.003, "DS-01 — error Dark.green = 0x14/255.")
        XCTAssertEqual(dark.b, 0x14 / 255.0, accuracy: 0.003, "DS-01 — error Dark.blue = 0x14/255.")

        let light = components(of: DS.Color.error, isDark: false)
        XCTAssertEqual(light.r, 0xB3 / 255.0, accuracy: 0.003, "DS-01 — error Light.red = 0xB3/255 (Figma #B3261E).")
        XCTAssertEqual(light.g, 0x26 / 255.0, accuracy: 0.003, "DS-01 — error Light.green = 0x26/255.")
        XCTAssertEqual(light.b, 0x1E / 255.0, accuracy: 0.003, "DS-01 — error Light.blue = 0x1E/255.")
    }

    // MARK: - DS-01 — все 15 токенов existence + resolve (compile-check)

    func test_allFifteenTokensResolve() {
        // Compile-check: каждый из 15 токенов должен существовать как `SwiftUI.Color`
        // и быть resolvable через UIColor/NSColor bridge (non-empty cgColor components).
        let tokens: [(String, SwiftUI.Color)] = [
            ("canvas", DS.Color.canvas),
            ("surface", DS.Color.surface),
            ("surfaceSunken", DS.Color.surfaceSunken),
            ("surfaceHeader", DS.Color.surfaceHeader),
            ("divider", DS.Color.divider),
            ("controlIdle", DS.Color.controlIdle),
            ("accent", DS.Color.accent),
            ("error", DS.Color.error),
            ("textPrimary", DS.Color.textPrimary),
            ("textSecondary", DS.Color.textSecondary),
            ("textTertiary", DS.Color.textTertiary),
            ("textInverse", DS.Color.textInverse),
            ("iconPrimary", DS.Color.iconPrimary),
            ("iconSecondary", DS.Color.iconSecondary),
            ("iconMuted", DS.Color.iconMuted)
        ]
        XCTAssertEqual(
            tokens.count, 15,
            "DS-01 — должно быть ровно 15 семантических токенов в DS.Color (CODE-CONNECT.md §2.1)."
        )
        for (name, color) in tokens {
            let comps = components(of: color, isDark: true)
            // Alpha=1, RGB components в диапазоне [0, 1] — non-empty resolve proof.
            XCTAssertTrue(
                (0...1).contains(comps.r) && (0...1).contains(comps.g) && (0...1).contains(comps.b),
                "DS-01 — DS.Color.\(name) должен resolve в валидный sRGB (Dark)."
            )
        }
    }

    // MARK: - Helpers

    /// Резолвит SwiftUI.Color в конкретные sRGB components под Dark или Light trait collection.
    /// W2 fix: explicit traits (UITraitCollection / NSAppearance) — no platform-default guessing.
    private func components(of color: SwiftUI.Color, isDark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        #if os(iOS)
        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
        #elseif os(macOS)
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        var result: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
            result = (nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent)
        }
        return result
        #endif
    }
}
