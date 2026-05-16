// SubscriptionHeader.swift — Figma BBTB v3 sync (2026-05-16 design pass).
//
// **Figma 3064:1154 (Подписка section header):**
//   HStack(spacing: 16) {
//     Phosphor CaretDown 20×20 (iconSecondary)
//     VStack(spacing: 8) {
//       HStack(spacing: 8) {
//         Text(subscription.name) 12pt Expanded Regular textPrimary
//         Text("11 Гб / 100 Гб") 8pt textSecondary
//       }
//       Capsule track (iconMuted) — высота 4pt, full width
//     }
//   }
//   .padding(.vertical, 12).padding(.horizontal, 16)
//   .background(surfaceHeader)
//
// Usage / progress placeholder — Subscription модель пока не содержит quota
// fields. Реальные значения подключим когда добавим subscription.usedBytes /
// totalBytes. Сейчас track-only progress bar (без fill).

import SwiftUI
import VPNCore
import DesignSystem
import Localization

public struct SubscriptionHeader: View {
    public let subscription: Subscription
    public let fetchError: String?
    public let onDelete: () -> Void

    public init(subscription: Subscription,
                fetchError: String? = nil,
                onDelete: @escaping () -> Void)
    {
        self.subscription = subscription
        self.fetchError = fetchError
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 16) {
            Ph.caretDown.bold
                .foregroundStyle(DS.Color.iconSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(subscription.name)
                        .font(DS.Typography.expanded(12, weight: .regular))
                        .foregroundStyle(DS.Color.textPrimary)

                    if let error = fetchError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .help(error)
                            .accessibilityLabel(Text(error))
                    }
                }

                // Progress track placeholder — quota wiring TODO.
                Capsule()
                    .fill(DS.Color.iconMuted)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceHeader)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(subscription.name))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.serverListDeleteSubscription, systemImage: "trash")
            }
        }
    }
}
