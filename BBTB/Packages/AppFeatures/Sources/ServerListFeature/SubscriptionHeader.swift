// SubscriptionHeader.swift — Phase 3 / Plan 03 / Task 2.
//
// UI-SPEC §2.4 — section header для каждой Subscription:
// - uppercase subscription.name (.caption .secondary)
// - relative last-fetched timestamp (.caption .tertiary) с arrow.clockwise иконкой
// - swipe action «Удалить» (.destructive) — Plan 04 wiring к confirmationDialog.
//
// Plan 04 расширит signature `fetchError: String?` для partial-failure indicator;
// Plan 03 — без этого параметра.

import SwiftUI
import VPNCore
import DesignSystem
import Localization

public struct SubscriptionHeader: View {
    public let subscription: Subscription
    /// Plan 04 UI-SPEC §3.4 — inline fetch-error indicator (warning triangle + tooltip).
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
        HStack(spacing: DS.Spacing.sm) {
            Text(subscription.name)
                .font(DS.Typography.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let error = fetchError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(error)
                    .accessibilityLabel(Text(error))
            }
            Spacer()
            if let fetched = subscription.lastFetched {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text(RelativeDateTimeFormatter().localizedString(for: fetched, relativeTo: .now))
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(subscription.name))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.serverListDeleteSubscription, systemImage: "trash")
            }
        }
    }
}
