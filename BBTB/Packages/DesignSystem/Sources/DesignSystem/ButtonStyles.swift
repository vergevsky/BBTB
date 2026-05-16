// ButtonStyles.swift — Phase 12 / Plan 12-01 / Task 3 / DS-10 / M7.
//
// Primary/Secondary pill-button styles (Figma Onboarding CTAs). Применяются в
// Plan 12-02 к OnboardingView (заменят system Button styles). См. RESEARCH §2.5 +
// UI-SPEC §2.3 (pressed motion contract) + §3.8 (Reduce-Motion fallback).
//
// Reduce-Motion gate (UI-SPEC §3.8): при `accessibilityReduceMotion = true`
// заменяем animated press (scale 0.97 + opacity 0.92 + easeOut 0.12s) на static
// `scaleEffect(1.0) + opacity(0.85)` без `.animation` modifier.
//
// Tap target ≥44pt: `.padding(.vertical, DS.Spacing.lg)` = 16 + label height (≥12pt)
// + 16 = ≥44pt (UI-SPEC §3.6 contract).
//
// Haptic feedback НЕ внутри ButtonStyle (API limitation — ButtonStyle.makeBody не
// имеет hook на tap). Поднимается на consumer-side в Plan 12-02 OnboardingView через
// `.sensoryFeedback(.impact(weight: .light), trigger: tapCounter)`.

import SwiftUI

/// Phase 12 / DS-10 / M7 — Primary pill-button (accent fill, alwaysWhite text).
///
/// Figma analog: Onboarding screen CTA "Добавить из буфера" (3062:345 → PrimaryButton frame
/// → text 3062:346 bound к `Color/alwaysWhite`).
/// Tokens: `DS.Color.accent` (fill), `DS.Color.alwaysWhite` (label — stays white в обоих
/// modes; на accent green pill чёрный текст был бы невидим), `DS.Typography.labelButton`
/// (SF Pro Expanded Semibold 14pt), `DS.Spacing.lg` (vertical padding 16pt).
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion: Bool

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.labelButton)
            .foregroundStyle(DS.Color.alwaysWhite)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .background(Capsule().fill(DS.Color.accent))
            .scaleEffect(
                accessibilityReduceMotion
                    ? 1.0
                    : (configuration.isPressed ? 0.97 : 1.0)
            )
            .opacity(
                accessibilityReduceMotion
                    ? (configuration.isPressed ? 0.85 : 1.0)
                    : (configuration.isPressed ? 0.92 : 1.0)
            )
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

/// Phase 12 / DS-10 / M7 — Secondary pill-button (textPrimary fill, textInverse text).
///
/// **Phase 12 / D-05 wire-only — Light mode визуально инвертирован (чёрная pill, белый текст).**
/// Это known wire-only artifact от D-05 (Light получает values из figma-tokens.json, но дизайнер
/// ещё не нарисовал Light-mode визуал). Final visual tuning сделается когда дизайнер нарисует
/// Light версии экранов в Figma. Plan 12-02 Task 9 UAT checklist предупреждает user'а явно.
///
/// Figma analog: Onboarding screen secondary CTA (whitepill).
/// Tokens: `DS.Color.textPrimary` (fill — белая pill в Dark, чёрная в Light),
/// `DS.Color.textInverse` (label — чёрный в Dark, белый в Light),
/// `DS.Typography.labelButton`, `DS.Spacing.lg`.
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion: Bool

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.labelButton)
            .foregroundStyle(DS.Color.textInverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .background(Capsule().fill(DS.Color.textPrimary))
            .scaleEffect(
                accessibilityReduceMotion
                    ? 1.0
                    : (configuration.isPressed ? 0.97 : 1.0)
            )
            .opacity(
                accessibilityReduceMotion
                    ? (configuration.isPressed ? 0.85 : 1.0)
                    : (configuration.isPressed ? 0.92 : 1.0)
            )
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
