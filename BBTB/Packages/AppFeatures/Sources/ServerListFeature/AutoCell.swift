// AutoCell.swift — Phase 3 / Plan 03 / Task 2.
//
// UI-SPEC §2.3 — sticky-top ячейка «Авто (рекомендуется)» в ServerListSheet.
// Closure-init pattern (EmptyStateCard analog).
//
// Visual: RoundedRectangle(cornerRadius=cardLarge=16), secondarySystemBackground,
// padding md, min-height 72. Leading bolt-icon в Circle 48×48. Trailing checkmark
// при isSelected. `.symbolEffect(.bounce, value: isSelected)` (iOS 17+).

import SwiftUI
import DesignSystem
import Localization

public struct AutoCell: View {
    public let isSelected: Bool
    public let onTap: () -> Void

    /// Phase 12 / DS-13 / M8+M10 — UI-SPEC §2.7 / §3.8 Reduce-Motion fallback
    /// для bouncyCheckmark `.symbolEffect(.bounce)`.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    public init(isSelected: Bool, onTap: @escaping () -> Void) {
        self.isSelected = isSelected
        self.onTap = onTap
    }

    /// Phase 12 / DS-13 / M8+M10 — pill design: accent fill (selected) /
    /// surfaceSunken (unselected), 24pt section radius, iconPrimary/iconSecondary
    /// icon color. См. CODE-CONNECT.md §1.6 + RESEARCH §3.
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                // 2026-05-16 sync — Lightning icon уходит в alwaysWhite когда selected
                // (cell bg = accent green). User вручную перепривязал Figma node
                // 3064:1354 → alwaysWhite по той же причине.
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isSelected ? DS.Color.alwaysWhite : DS.Color.iconSecondary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().fill(
                            isSelected
                            ? DS.Color.accent.opacity(0.25)
                            : DS.Color.surface.opacity(0.5)
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.serverAutoTitle)
                        .font(DS.Typography.title)
                        // 2026-05-16 sync — title text на accent green (selected) →
                        // alwaysWhite. Mirrors Figma binding I3064:1355;1:789 → alwaysWhite.
                        .foregroundStyle(isSelected ? DS.Color.alwaysWhite : DS.Color.textPrimary)
                    Text(L10n.serverAutoSubtitle)
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(
                            isSelected
                            ? DS.Color.alwaysWhite.opacity(0.8)
                            : DS.Color.textSecondary
                        )
                }
                Spacer()
                if isSelected {
                    bouncyCheckmark
                }
            }
            .padding(DS.Spacing.md)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.section)
                    .fill(isSelected ? DS.Color.accent : DS.Color.surfaceSunken)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("BBTB.ServerListSheet.AutoCell")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(L10n.serverAutoTitle))
        .accessibilityValue(Text(isSelected ? L10n.statusConnected : L10n.statusEmpty))
        .accessibilityHint(Text(isSelected ? "" : L10n.serverLineHint))
    }

    @ViewBuilder
    private var bouncyCheckmark: some View {
        // 2026-05-16 sync — bouncyCheckmark shows только когда AutoCell isSelected =>
        // cell bg = accent. Если checkmark fill = accent тоже — invisible. Switch на
        // alwaysWhite чтобы checkmark был видим на accent green pill в обоих modes.
        let img = Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(DS.Color.alwaysWhite)
        if #available(iOS 17.0, macOS 14.0, *) {
            // Phase 12 / DS-13 / UI-SPEC §3.8 — Reduce-Motion fallback:
            // symbolEffect отключается через .disabled() когда пользователь
            // включил Reduce Motion в Accessibility settings.
            img
                .symbolEffect(.bounce, value: isSelected)
                .disabled(reduceMotion)
        } else {
            img
        }
    }
}
