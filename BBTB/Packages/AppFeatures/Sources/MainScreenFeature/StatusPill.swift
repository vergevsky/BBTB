import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.5 — Capsule pill под power-кнопкой; visual rewrite Phase 1 StatusBadge.
public struct StatusPill: View {
    public let state: ConnectionState
    public init(state: ConnectionState) { self.state = state }

    public var body: some View {
        if case .empty = state {
            EmptyView()
        } else {
            Text(label)
                .font(DS.Typography.subheadline)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .clipShape(Capsule())
                .accessibilityHidden(true)  // duplicated by ConnectionButton accessibility
        }
    }

    private var label: String {
        switch state {
        case .empty: return ""
        case .idle: return L10n.statusDisconnected
        case .connecting: return L10n.statusConnecting
        case .connected: return L10n.statusConnected
        case .error: return L10n.statusError
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .empty: return .clear
        case .idle: return Color.gray.opacity(0.18)
        case .connecting: return Color.orange.opacity(0.18)
        case .connected: return Color.green.opacity(0.18)
        case .error: return Color.red.opacity(0.18)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .empty: return .clear
        case .idle: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}
