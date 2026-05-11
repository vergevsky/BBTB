import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §3.2 — empty-state карточка с двумя CTAs.
public struct EmptyStateCard: View {
    public let onAddFromClipboard: () -> Void
    public let onScanQR: () -> Void

    public init(onAddFromClipboard: @escaping () -> Void, onScanQR: @escaping () -> Void) {
        self.onAddFromClipboard = onAddFromClipboard
        self.onScanQR = onScanQR
    }

    public var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(L10n.emptyTitle)
                .font(DS.Typography.title)

            Text(L10n.emptySubtitle)
                .font(DS.Typography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: DS.Spacing.md) {
                Button(L10n.actionImportFromClipboard, action: onAddFromClipboard)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel(Text(L10n.actionImportFromClipboard))

                Button(L10n.actionScanQR, action: onScanQR)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel(Text(L10n.actionScanQR))
            }
        }
        .padding(DS.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
                .fill(Color.secondary.opacity(0.1))
        )
        .frame(maxWidth: 360)
    }
}
