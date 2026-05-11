import SwiftUI
import DesignSystem

/// UI-SPEC §2.6 — main power button.
public struct ConnectionButton: View {
    public let state: ConnectionState
    public let action: () -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(state: ConnectionState, action: @escaping () -> Void) {
        self.state = state; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: diameter, height: diameter)
                Image(systemName: "power")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: state)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("BBTB.ConnectionButton")
    }

    private var diameter: CGFloat {
        #if os(iOS)
        return (horizontalSizeClass == .regular)
            ? DS.ConnectionButtonSize.regularDiameter
            : DS.ConnectionButtonSize.compactDiameter
        #else
        return DS.ConnectionButtonSize.regularDiameter
        #endif
    }
    private var iconSize: CGFloat {
        #if os(iOS)
        return (horizontalSizeClass == .regular)
            ? DS.ConnectionButtonSize.regularIcon
            : DS.ConnectionButtonSize.compactIcon
        #else
        return DS.ConnectionButtonSize.regularIcon
        #endif
    }

    private var fillColor: Color {
        switch state {
        case .empty: return .gray
        case .idle: return Color(white: 0.55)  // .systemGray equivalent
        case .connecting: return .orange
        case .connected: return .accentColor
        case .error: return Color.red.opacity(0.85)
        }
    }

    private var disabled: Bool {
        if case .connecting = state { return true }
        if case .empty = state { return true }
        return false
    }
}
