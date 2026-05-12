import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.3 / D-14 — баннер «Переподключитесь» когда KillSwitch toggle поменялся
/// во время active tunnel.
///
/// Phase 6 / Wave 5 — extension: принимает произвольный `message: String` и опциональный
/// dismiss-handler. Default message сохраняет Phase 2 KillSwitch banner текст, чтобы
/// существующие callsite-ы не сломались (Option B per `06-PATTERNS.md`).
/// Когда `onDismiss == nil` — close-кнопка скрыта (для авто-реконнект статусов,
/// которые user не дисмисит вручную — они исчезают сами).
public struct ReconnectBanner: View {
    public let message: String
    public let onDismiss: (() -> Void)?

    public init(message: String = L10n.bannerReconnectNeeded,
                onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    /// Backward-compat init для Phase 2 KillSwitch banner — required parameter.
    public init(onDismiss: @escaping () -> Void) {
        self.message = L10n.bannerReconnectNeeded
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(message)
                .font(DS.Typography.subheadline)
            Spacer()
            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.bannerDismiss))
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .fill(Color.orange.opacity(0.15))
        )
        .foregroundColor(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(message))
    }
}
