// DSColor.swift — Phase 12 / Plan 12-01 / Task 2 / DS-01 / DS-07.
//
// Semantic color tokens из Figma BBTB v3 (15 токенов). См. CODE-CONNECT.md §2.1
// + RESEARCH.md §2.3. Dark = pixel-perfect Figma source-of-truth; Light = placeholder
// per Phase 11 designer-decision (D-06). System auto-switch через
// UIColor(dynamicProvider:) на iOS / NSColor(name:dynamicProvider:) на macOS — D-07
// (без in-app toggle).
//
// REVISION B3: НЕ объявляем top-level `Color` ext-ension из-за Swift 6 ambiguity с
// системным `Color.accentColor` (self-referential lookup risk). Deprecated `DS.accent`
// → `DS.Color.accent` напрямую через DS namespace (см. DesignSystem.swift).

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public extension DS {
    /// 16 семантических color tokens из Figma BBTB v3. Каждый — `dynamic(dark:light:)`
    /// с автопереключением через UIColor/NSColor providers (D-07). См. CODE-CONNECT.md §2.1.
    ///
    /// **Synced 2026-05-16 (post designer Light-mode pass):**
    /// - surface Light: F4F4F6 → FFFFFF (sheet = canvas in Light, разделение через drag indicator + section headers)
    /// - surfaceSunken Light: ECEDEF → F0F0F0 (slight shift)
    /// - surfaceHeader Light: E0E0E5 → E0E0E0 (slight shift)
    /// - NEW token: `alwaysWhite` (Dark=Light=#FFFFFF) — для текста на accent/error backgrounds
    ///   которые не должны инвертироваться в Light mode.
    enum Color {
        // ─── Surfaces ─────────────────────────────────────────────────────────
        public static let canvas         = dynamic(dark: 0x000000, light: 0xFFFFFF)
        public static let surface        = dynamic(dark: 0x222222, light: 0xFFFFFF)
        public static let surfaceSunken  = dynamic(dark: 0x1A1A1A, light: 0xF0F0F0)
        public static let surfaceHeader  = dynamic(dark: 0x333333, light: 0xE0E0E0)
        public static let divider        = dynamic(dark: 0x333333, light: 0xD8D8DD)
        public static let controlIdle    = dynamic(dark: 0x222222, light: 0xE8E8EC)

        // ─── Brand + Status ───────────────────────────────────────────────────
        /// Brand accent (Figma DS/Color/accent #14664B Dark == Light per Phase 11 designer-decision).
        public static let accent         = dynamic(dark: 0x14664B, light: 0x14664B)
        public static let error          = dynamic(dark: 0x661414, light: 0xB3261E)

        // ─── Text ─────────────────────────────────────────────────────────────
        public static let textPrimary    = dynamic(dark: 0xFFFFFF, light: 0x111113)
        public static let textSecondary  = dynamic(dark: 0x808080, light: 0x6B6B72)
        public static let textTertiary   = dynamic(dark: 0x64706F, light: 0x7A8281)
        public static let textInverse    = dynamic(dark: 0x000000, light: 0xFFFFFF)
        /// Static white (Dark=Light=#FFFFFF) — для текста на цветном (accent/error) background,
        /// чтобы оставался читаемым в обоих modes. Figma scope: TEXT_FILL. Apply: PrimaryButton
        /// text, ConnectionButton .connected/.error texts, ServerRowSelected name, AutoCell
        /// selected label.
        public static let alwaysWhite    = dynamic(dark: 0xFFFFFF, light: 0xFFFFFF)

        // ─── Icons ────────────────────────────────────────────────────────────
        public static let iconPrimary    = dynamic(dark: 0xFFFFFF, light: 0x111113)
        public static let iconSecondary  = dynamic(dark: 0x808080, light: 0x6B6B72)
        public static let iconMuted      = dynamic(dark: 0xCCCCCC, light: 0xA5A5AC)

        // ─── Helpers ──────────────────────────────────────────────────────────

        /// Создаёт dynamic SwiftUI.Color, переключающийся между Dark и Light hex values
        /// в зависимости от системного userInterfaceStyle / NSAppearance (D-07).
        private static func dynamic(dark: UInt32, light: UInt32) -> SwiftUI.Color {
            #if os(iOS)
            return SwiftUI.Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? uiColor(hex: dark) : uiColor(hex: light)
            })
            #elseif os(macOS)
            return SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                return isDark ? nsColor(hex: dark) : nsColor(hex: light)
            })
            #endif
        }

        #if os(iOS)
        private static func uiColor(hex: UInt32) -> UIColor {
            UIColor(
                red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >>  8) & 0xFF) / 255.0,
                blue:  CGFloat( hex        & 0xFF) / 255.0,
                alpha: 1
            )
        }
        #elseif os(macOS)
        private static func nsColor(hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green:   CGFloat((hex >>  8) & 0xFF) / 255.0,
                blue:    CGFloat( hex        & 0xFF) / 255.0,
                alpha:   1
            )
        }
        #endif
    }
}
