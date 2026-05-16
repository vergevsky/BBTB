// AutoCell.swift — Figma BBTB v3 sync (2026-05-16 design pass).
//
// **Layout per Figma 3064:1316 (Selected) / accent variant (Auto active):**
//   HStack(spacing: 16) {
//     Phosphor Lightning icon 20×20 (iconSecondary | alwaysWhite when isSelected)
//     Text("Автовыбор по скорости") 12pt Expanded Regular
//   }
//   .padding(.vertical, 12).padding(.horizontal, 16)
//   .background(RoundedRectangle(24) — accent (isSelected) | surfaceHeader)
//
// Pre-v3 design (circle bolt-icon + title + subtitle + bouncyCheckmark) удалён —
// упрощено до single-line label (Figma убрал subtitle, checkmark избыточен т.к.
// bg=accent сам по себе communicates "выбрано").

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
            HStack(spacing: 16) {
                Ph.lightning.bold
                    .foregroundStyle(isSelected ? DS.Color.alwaysWhite : DS.Color.iconSecondary)
                    .frame(width: 20, height: 20)
                Text(L10n.serverAutoTitle)
                    .font(DS.Typography.expanded(12, weight: .regular))
                    .foregroundStyle(isSelected ? DS.Color.alwaysWhite : DS.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isSelected ? DS.Color.accent : DS.Color.surfaceHeader)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("BBTB.ServerListSheet.AutoCell")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(L10n.serverAutoTitle))
        .accessibilityValue(Text(isSelected ? L10n.statusConnected : L10n.statusEmpty))
        .accessibilityHint(Text(isSelected ? "" : L10n.serverLineHint))
    }
}
