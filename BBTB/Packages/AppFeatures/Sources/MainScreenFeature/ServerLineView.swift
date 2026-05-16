import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.7 / §4 — server line под power button.
///
/// **2026-05-16 Figma BBTB v3 sync** — restyle под `ServerStatusLabel` footer
/// (Figma node `3047:529` в frame 3043:341 "Home — Disconnected"):
/// - HStack spacing 4pt (Figma gap)
/// - 12pt SF Pro Expanded **Semibold** (was DS.Typography.callout regular)
/// - DS.Color.textPrimary (was `.secondary`)
/// - Без `chevron.right` Image (Figma footer не показывает chevron — простой
///   static text, tap action сохранён через invisible Button + contentShape)
///
/// Tap action остаётся ENABLED (Phase 3 D-08) — открывает ServerListSheet
/// через `onTap` closure. Visual hint не нужен на static footer, потому что
/// весь footer area tappable.
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
                HStack(spacing: 4) {
                    Text(L10n.serverLabel)
                    Text(name)
                }
                .font(DS.Typography.expanded(12, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(L10n.serverLabel) \(name)"))
            .accessibilityHint(Text(L10n.serverLineHint))
        }
    }
}
