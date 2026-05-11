import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.3 / D-14 — баннер «Переподключитесь» когда KillSwitch toggle поменялся
/// во время active tunnel.
public struct ReconnectBanner: View {
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(L10n.bannerReconnectNeeded)
                .font(DS.Typography.subheadline)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.bannerDismiss))
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .fill(Color.orange.opacity(0.15))
        )
        .foregroundColor(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L10n.bannerReconnectNeeded))
    }
}
