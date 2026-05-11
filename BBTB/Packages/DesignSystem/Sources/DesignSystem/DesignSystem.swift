import SwiftUI

/// CONTEXT.md §5 default: системные SF Symbols + system colors.
/// Phase 2 W4.T1 (UI-SPEC §8) расширяет до полной шкалы tokens.
/// Phase 11 переопределит значения но сохранит names (forward-compat).
public enum DS {
    public static let accent: Color = .accentColor  // Phase 1 carry-forward
    public static let titleFont: Font = .system(.title, design: .rounded).weight(.semibold)

    /// UI-SPEC §8.1 — 8-point grid (с 4pt для tight spacing).
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    /// UI-SPEC §8.2 — corner radius scale.
    public enum Radius {
        public static let small: CGFloat = 8
        public static let card: CGFloat = 12
        public static let cardLarge: CGFloat = 16
        public static let button: CGFloat = 12
    }

    /// UI-SPEC §8.4 — typography tokens, сопоставленный с Font.TextStyle.
    public enum Typography {
        public static let display: Font = .system(.largeTitle, design: .monospaced).monospacedDigit()
        public static let title: Font = .system(.title3, design: .rounded).weight(.bold)
        public static let body: Font = .body
        public static let callout: Font = .system(.callout, design: .rounded)
        public static let subheadline: Font = .system(.subheadline, design: .rounded).weight(.medium)
        public static let caption: Font = .caption
    }

    /// UI-SPEC §8.5 — ConnectionButton dimensions per size class.
    public enum ConnectionButtonSize {
        public static let compactDiameter: CGFloat = 140
        public static let regularDiameter: CGFloat = 160
        public static let compactIcon: CGFloat = 56
        public static let regularIcon: CGFloat = 64
    }
}
