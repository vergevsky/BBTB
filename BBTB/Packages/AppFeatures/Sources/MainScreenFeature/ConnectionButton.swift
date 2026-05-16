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
                    // Phase 11 / UX-08 / D-05 — скрываем power-icon во время
                    // .connecting; spinner overlay показывает progress.
                    // Figma-revision (Task 7.4): если spec скажет «icon visible»
                    // — заменить на opacity(1) и поместить spinner снаружи Circle.
                    .opacity(isConnecting ? 0 : 1)
                if isConnecting {
                    // UX-08 placeholder реализация — circular ProgressView .large
                    // на белом tint. Figma-precise variant (rotating ring etc.)
                    // подменим после Task 7.4 visual review.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .controlSize(.large)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("BBTB.ConnectionButton")
    }

    /// Phase 11 / UX-08 — true когда state ∈ {.connecting}.
    /// `internal` для @testable access из ConnectionButtonTests (Alternative A
    /// в Plan 11-07 Task 7.1 — простейший diff, без extract'а free function).
    internal var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
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

    /// Phase 12 / DS-09 / M3 — fill switch на DS.Color семантические токены.
    /// См. CODE-CONNECT.md §1.1 + RESEARCH §4.5.
    ///
    /// W2 fix (Plan 12-02 revision iteration 1): `internal` access level (НЕ
    /// `private`) — Alternative A pattern из Phase 11 D-05 / Plan 11-07 Task 7.1.
    /// Аналог `isConnecting`: доступ через `@testable import MainScreenFeature`
    /// для `ConnectionButtonTests.test_fillColor_*` regression assertions.
    internal var fillColor: SwiftUI.Color {
        switch state {
        case .empty, .idle:  return DS.Color.controlIdle
        case .connecting:    return DS.Color.controlIdle  // Figma .connecting = idle fill + spinner ring AROUND (Task 6).
        case .connected:     return DS.Color.accent
        case .error:         return DS.Color.error
        }
    }

    private var disabled: Bool {
        if case .connecting = state { return true }
        if case .empty = state { return true }
        return false
    }
}
