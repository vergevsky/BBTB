import SwiftUI
import Localization

public struct StatusBadge: View {
    public let state: ConnectionState
    public init(state: ConnectionState) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch state {
        case .empty: return .gray
        case .idle: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
    private var label: String {
        switch state {
        case .empty: return L10n.statusEmpty
        case .idle: return L10n.statusIdle
        case .connecting: return L10n.statusConnecting
        case .connected: return L10n.statusConnected
        case .error: return L10n.statusError
        }
    }
}
