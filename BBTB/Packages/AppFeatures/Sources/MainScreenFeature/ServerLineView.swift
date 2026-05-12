import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.7 / §4 — server line под power button.
/// Phase 3: tap ENABLED (D-08). Открывает ServerListSheet через `onTap` closure.
/// Chevron справа подчёркивает интерактивность (UI-SPEC §4.1).
public struct ServerLineView: View {
    public let name: String?  // nil → не рендерим
    public let onTap: () -> Void

    public init(name: String?, onTap: @escaping () -> Void = {}) {
        self.name = name
        self.onTap = onTap
    }

    public var body: some View {
        if let name = name {
            Button(action: onTap) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(L10n.serverLabel)
                    Text(name).fontWeight(.medium)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .font(DS.Typography.callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(L10n.serverLabel) \(name)"))
            .accessibilityHint(Text(L10n.serverLineHint))
        }
    }
}
