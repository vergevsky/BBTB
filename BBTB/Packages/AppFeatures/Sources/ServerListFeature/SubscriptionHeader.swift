// SubscriptionHeader.swift — Figma BBTB v3 sync (2026-05-16 design pass).
//
// **Figma 3064:1154 — collapsible section header:**
//   Button(action: onToggle) {
//     HStack(spacing: 16) {
//       Phosphor CaretDown 20×20 (rotates -90° CCW when collapsed)
//       Text(subscription.name) 12pt Expanded Regular textPrimary
//     }
//     .padding(.vertical, 12).padding(.horizontal, 16)
//     .background(surfaceHeader)
//   }
//
// Quota progress bar пока удалён — Subscription модель не содержит usedBytes/
// totalBytes / expiresAt fields (все подписки трактуются как бессрочные).
// Реализуем conditional render при расширении модели.

import SwiftUI
import VPNCore
import DesignSystem
import Localization

public struct SubscriptionHeader: View {
    public let subscription: Subscription
    public let fetchError: String?
    /// 2026-05-16 — collapsible state (Figma CaretDown toggle).
    public let isCollapsed: Bool
    public let onToggle: () -> Void
    public let onDelete: () -> Void

    public init(subscription: Subscription,
                fetchError: String? = nil,
                isCollapsed: Bool = false,
                onToggle: @escaping () -> Void = {},
                onDelete: @escaping () -> Void)
    {
        self.subscription = subscription
        self.fetchError = fetchError
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.onDelete = onDelete
    }

    public var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Ph.caretDown.bold
                    .foregroundStyle(DS.Color.iconSecondary)
                    .frame(width: 20, height: 20)
                    // Counter-clockwise 90° rotation when collapsed (per user spec).
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isCollapsed)

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
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surfaceHeader)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(subscription.name))
        .accessibilityValue(Text(isCollapsed ? L10n.statusEmpty : L10n.statusConnected))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.serverListDeleteSubscription, systemImage: "trash")
            }
        }
    }
}
