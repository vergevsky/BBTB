import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.7 — server line под power button. Tap disabled на v0.2 (D-11).
public struct ServerLineView: View {
    public let name: String?  // nil → не рендерим

    public init(name: String?) { self.name = name }

    public var body: some View {
        if let name = name {
            HStack(spacing: DS.Spacing.xs) {
                Text(L10n.serverLabel)
                Text(name).fontWeight(.medium)
            }
            .font(DS.Typography.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(L10n.serverLabel) \(name)"))
        }
    }
}
