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
    /// 15 семантических color tokens из Figma BBTB v3. Каждый — `dynamic(dark:light:)`
    /// с автопереключением через UIColor/NSColor providers (D-07). См. CODE-CONNECT.md §2.1.
    enum Color {
        // ─── Surfaces ─────────────────────────────────────────────────────────
        public static let canvas         = dynamic(dark: 0x000000, light: 0xFFFFFF)
        public static let surface        = dynamic(dark: 0x222222, light: 0xF4F4F6)
        public static let surfaceSunken  = dynamic(dark: 0x1A1A1A, light: 0xECEDEF)
        public static let surfaceHeader  = dynamic(dark: 0x333333, light: 0xE0E0E5)
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
