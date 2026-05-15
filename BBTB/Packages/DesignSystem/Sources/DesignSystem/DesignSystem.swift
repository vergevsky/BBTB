import SwiftUI

/// CONTEXT.md §5 default: системные SF Symbols + system colors.
/// Phase 2 W4.T1 (UI-SPEC §8) расширяет до полной шкалы tokens.
/// Phase 12 / Plan 12-01 — pixel-perfect rebuild from Figma BBTB v3:
///   * `DS.Color` (DSColor.swift) — 15 семантических токенов (DS-01 / DS-07).
///   * `DS.Typography.expanded()` helper + 9 sized presets — SF Pro Expanded font family
///     (DS-06 / M4). Существующие aliases (display/title/body/callout/subheadline/caption)
///     сохранены и переопределены через expanded(), что миграирует ~95 call-sites без правок.
///   * `DS.Radius.section` (24) + `DS.Radius.sheet` (32) + `DS.Blur.pill` (4) — DS-03 / DS-04.
///   * `DS.ConnectionButtonSize.*` — numerics обновлены 140→280, 160→320, 56→112, 64→128 (DS-05 / M1 + M2).
///   * `DS.accent` deprecated alias на `DS.Color.accent` (B3 — без extension SwiftUI.Color во избежание
///     Swift 6 ambiguity с системным `Color.accentColor`).
/// См. RESEARCH §2.2/§2.3 + CODE-CONNECT.md §2.1/§2.2/§3.
public enum DS {
    /// Phase 12 / DS-07 / M5 — deprecated alias на `DS.Color.accent`.
    /// **B3 fix:** прямая ссылка через DS namespace (НЕ через extension `SwiftUI.Color`) —
    /// избегаем коллизии с системным `Color.accentColor` и self-referential lookup в Swift 6.
    /// Все consumer-сайды (Plan 12-02) читают через `DS.Color.accent` напрямую.
    ///
    /// `SwiftUI.Color` указан явно — внутри `enum DS` короткое `Color` резолвится в nested
    /// `DS.Color` (enum), а нам нужен SwiftUI's foundational `Color` type.
    @available(*, deprecated, renamed: "DS.Color.accent")
    public static let accent: SwiftUI.Color = DS.Color.accent

    // Phase 1 legacy `DS.titleFont` удалён в Plan 12-01 (dead code — 0 call-sites; verified
    // через `grep -rn "DS.titleFont"` 2026-05-16). Phase 12 / B4 fix требует 0 `.rounded`
    // в non-comment коде — это закрывает B4 grep gate без потери функциональности.

    /// UI-SPEC §8.1 — 8-point grid (с 4pt для tight spacing).
    /// Phase 12: совпадает с Figma DS/Spacing/* (CODE-CONNECT.md §2.2) — preserve as-is.
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
    /// Phase 12 / DS-03 / M9-M10 — добавлены `section` (24pt) + `sheet` (32pt) tokens.
    /// См. CODE-CONNECT.md §2.2.
    public enum Radius {
        public static let small: CGFloat = 8
        public static let card: CGFloat = 12
        public static let cardLarge: CGFloat = 16
        public static let button: CGFloat = 12
        /// Phase 12 / DS-03 / M10 — section radius (Подписка / Конфигурации / Авто frames).
        public static let section: CGFloat = 24
        /// Phase 12 / DS-03 / M9 — sheet radius (Server List Sheet top corners).
        public static let sheet: CGFloat = 32
    }

    /// Phase 12 / DS-04 — Blur tokens from Figma DS/Blur/*. См. CODE-CONNECT.md §2.2.
    public enum Blur {
        /// Pill blur (Server List selection pill background blur).
        public static let pill: CGFloat = 4
    }

    /// UI-SPEC §8.4 — typography tokens.
    /// Phase 12 / DS-02 / DS-06 / M4 — все презенты теперь идут через `expanded(_:weight:)`
    /// helper, который применяет `.system(size:weight:).width(.expanded)` (SF Pro Expanded
    /// font family). Существующие aliases (display/title/body/callout/subheadline/caption)
    /// сохранены для backward compat — внутри они проксируют через `expanded(...)`.
    ///
    /// SF Pro Expanded НЕ бундлится (Apple Font SLA §2B); используем системный
    /// `.fontWidth(.expanded)` SwiftUI modifier (iOS 16+). См. RESEARCH §2.2.
    ///
    /// Dynamic Type intentionally NOT applied per Phase 12 UI-SPEC §3.4. Backlog: v1.x.
    public enum Typography {
        /// Phase 12 / DS-02 — sized constants (CGFloat) для всех presets.
        /// См. CODE-CONNECT.md §3 + Figma DS/Typography/Size/*.
        public enum Size {
            public static let display: CGFloat = 48
            public static let title: CGFloat = 16
            public static let labelButton: CGFloat = 14
            public static let body: CGFloat = 12
            public static let tips: CGFloat = 10
            public static let caption: CGFloat = 9
            public static let micro: CGFloat = 8
        }

        /// Phase 12 / DS-06 / M4 — base helper для SF Pro Expanded font family.
        /// Применяет `.system(size:weight:).width(.expanded)`. SF Pro Expanded НЕ бундлится
        /// (Apple Font SLA §2B); `.fontWidth(.expanded)` — Apple-blessed путь (iOS 16+).
        public static func expanded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight).width(.expanded)
        }

        // ─── 9 sized presets (Phase 12 / DS-06, per CODE-CONNECT.md §3) ───────────────────────

        /// Figma `Typography/Display/Timer` — Expanded Medium 48pt (00:01:07 timer).
        public static let displayTimer: Font = expanded(Size.display, weight: .medium)
        /// Figma `Typography/Title/Screen` — Expanded Semibold 16pt ("Список серверов" sheet title).
        public static let titleScreen: Font = expanded(Size.title, weight: .semibold)
        /// Figma `Typography/Title/Section` — Expanded Semibold 12pt ("Подписка" section header).
        public static let titleSection: Font = expanded(Size.body, weight: .semibold)
        /// Figma `Typography/Title/SectionUpper` — Expanded Semibold 9pt (uppercase section labels).
        public static let titleUppercase: Font = expanded(Size.caption, weight: .semibold)
        /// Figma `Typography/Label/Button` — Expanded Semibold 14pt ("Добавить из буфера" CTA).
        public static let labelButton: Font = expanded(Size.labelButton, weight: .semibold)
        /// Figma `Typography/Body/Default` — Expanded Regular 12pt ("WL Латвия" server names).
        public static let bodyDefault: Font = expanded(Size.body, weight: .regular)
        /// Figma `Typography/Body/Caption` — Expanded Regular 9pt ("20 мс" latency).
        public static let bodyCaption: Font = expanded(Size.caption, weight: .regular)
        /// Figma `Typography/Body/Micro` — Expanded Regular 8pt ("11 Гб / 100 Гб" usage stats).
        public static let bodyMicro: Font = expanded(Size.micro, weight: .regular)
        /// Figma `Tips` — Expanded Light 10pt ("Добавьте конфигурацию" Onboarding hint).
        public static let tipsLight: Font = expanded(Size.tips, weight: .light)

        // ─── Deprecated aliases (preserve ~95 call-sites; внутри идут через expanded()) ───────
        // Phase 12 / DS-06 / M4 — внутреннее переопределение через expanded() даёт всем
        // существующим call-sites автоматический SF Pro Expanded font family switch без
        // массового find-and-replace. Имена aliases сохранены (no breaking change).

        /// Phase 1 alias — теперь проксирует через `expanded(Size.display, .medium)` ≡ `displayTimer`.
        public static let display: Font = expanded(Size.display, weight: .medium)
        /// Phase 1 alias — теперь проксирует через `expanded(Size.title, .semibold)` ≡ `titleScreen`.
        public static let title: Font = expanded(Size.title, weight: .semibold)
        /// Phase 1 alias — теперь проксирует через `expanded(Size.body, .regular)` ≡ `bodyDefault`.
        public static let body: Font = expanded(Size.body, weight: .regular)
        /// Phase 1 alias — теперь проксирует через `expanded(Size.body, .regular)`.
        public static let callout: Font = expanded(Size.body, weight: .regular)
        /// Phase 1 alias — теперь проксирует через `expanded(Size.body, .medium)`.
        public static let subheadline: Font = expanded(Size.body, weight: .medium)
        /// Phase 1 alias — теперь проксирует через `expanded(Size.caption, .regular)` ≡ `bodyCaption`.
        public static let caption: Font = expanded(Size.caption, weight: .regular)
    }

    /// UI-SPEC §8.5 — ConnectionButton dimensions per size class.
    /// Phase 12 / DS-05 / M1 + M2 — numerics обновлены под Figma BBTB v3:
    /// compactDiameter 140→280, regularDiameter 160→320, compactIcon 56→112, regularIcon 64→128.
    /// Имена preserved (no API break). См. CODE-CONNECT.md §2.2.
    public enum ConnectionButtonSize {
        public static let compactDiameter: CGFloat = 280
        public static let regularDiameter: CGFloat = 320
        public static let compactIcon: CGFloat = 112
        public static let regularIcon: CGFloat = 128
    }
}
