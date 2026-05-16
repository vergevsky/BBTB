import SwiftUI
import DesignSystem

/// UI-SPEC §2.6 — main power button.
public struct ConnectionButton: View {
    public let state: ConnectionState
    public let action: () -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Phase 12 / Plan 12-02 / Task 6 — UI-SPEC §2.7: SF Symbol .symbolEffect(.bounce)
    /// disabled при Reduce-Motion. Hook читает `accessibilityReduceMotion` Environment.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    public init(state: ConnectionState, action: @escaping () -> Void) {
        self.state = state; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // Phase 12 / DS-08 / M6 — Spinner placement: ring AROUND Circle через .overlay
                // (W3 fix — НЕ sibling-in-ZStack чтобы parent VStack/HStack frame не
                // пересчитывался при isConnecting toggle). См. RESEARCH §2.1 + Plan 12-02
                // W3 revision note. Overlay не участвует в layout calculation родителя —
                // frame ConnectionButton остаётся = diameter × diameter независимо от
                // isConnecting; при .connecting ring рендерится поверх (но через `+24` —
                // диаметр кольца выходит за пределы Circle).
                Circle()
                    .fill(fillColor)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        if isConnecting {
                            BBTBSpinner(diameter: diameter + 24, lineWidth: 6, speed: 1.2)
                                .accessibilityHidden(true)
                        }
                    }

                // Phase 12 / DS-08 / M6 — power-icon ВИДНА во всех state'ах (RESEARCH §2.1
                // spinner-placement: Figma .connecting variant показывает icon present со
                // spinner ring around). Phase 11 D-05 hide-on-connecting modifier
                // удалён — icon `.opacity(1)` всегда.
                Image(systemName: "power")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .symbolEffect(.bounce, value: state)
                    .disabled(reduceMotion)
                    .opacity(1)
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
