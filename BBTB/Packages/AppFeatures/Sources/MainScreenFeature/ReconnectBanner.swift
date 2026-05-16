import SwiftUI
import Localization
import DesignSystem

/// **2026-05-16 Figma BBTB v3 sync** — floating pill banner для transient
/// уведомлений (auto-reconnect status, kill-switch reconfigure, .error state).
///
/// **Layout (Figma 3047:568 «Ошибка подключения» pill):**
///   Pill: accent green bg + alwaysWhite text + cornerRadius 16
///   Text: 10pt SF Pro Expanded Regular (Figma 8pt — bumped до 10pt для
///         accessibility minimum legibility; 8pt < Apple HIG 11pt рекомендации)
///   Padding [vertical: 8, horizontal: 16]
///
/// **Behavior:** Парентский view рендерит banner через `.overlay(alignment: .top)`
/// с slide+opacity transition — banner НЕ shift'ит underlying content layout.
/// Pre-2026-05-16 inline rendering (внутри VStack) deprecated — пользовательский
/// feedback: «уведомления типа "переподключение 1 из 3" должны быть всплывающими,
/// не сдвигать контент».
///
/// **Dismiss:** опциональный `onDismiss` — рендерит X-кнопку справа (для
/// kill-switch reconfigure banner, который требует manual dismiss). Без callback
/// X скрыт (auto-reconnect статусы исчезают сами через timer / state-change).
///
/// Имя `ReconnectBanner` сохранено для backward-compat; семантически теперь это
/// generic FloatingBanner / Toast.
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
        HStack(spacing: 8) {
            Text(message)
                .font(DS.Typography.expanded(10, weight: .regular))
                .foregroundStyle(DS.Color.alwaysWhite)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Color.alwaysWhite)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.bannerDismiss))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Color.accent)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(message))
    }
}
