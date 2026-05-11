import SwiftUI

public struct ConnectionButton: View {
    public let state: ConnectionState
    public let action: () -> Void

    public init(state: ConnectionState, action: @escaping () -> Void) {
        self.state = state; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 200, height: 200)
                Image(systemName: iconName)
                    .font(.system(size: 80, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: state)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("BBTB.ConnectionButton")
    }

    private var fillColor: Color {
        switch state {
        case .empty, .idle: return .accentColor.opacity(0.85)
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
    private var iconName: String {
        switch state {
        case .empty, .idle, .error: return "power"
        case .connecting: return "bolt"
        case .connected: return "checkmark"
        }
    }
    private var disabled: Bool {
        if case .connecting = state { return true }
        if case .empty = state { return true }
        return false
    }
}
