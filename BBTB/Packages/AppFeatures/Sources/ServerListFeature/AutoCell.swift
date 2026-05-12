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

    public init(isSelected: Bool, onTap: @escaping () -> Void) {
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().fill(
                            isSelected
                            ? Color.accentColor.opacity(0.15)
                            : Color.secondary.opacity(0.12)
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.serverAutoTitle)
                        .font(DS.Typography.title)
                        .foregroundStyle(.primary)
                    Text(L10n.serverAutoSubtitle)
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    bouncyCheckmark
                }
            }
            .padding(DS.Spacing.md)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
                    .fill(Color.secondary.opacity(0.1))
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
        let img = Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        if #available(iOS 17.0, macOS 14.0, *) {
            img.symbolEffect(.bounce, value: isSelected)
        } else {
            img
        }
    }
}
