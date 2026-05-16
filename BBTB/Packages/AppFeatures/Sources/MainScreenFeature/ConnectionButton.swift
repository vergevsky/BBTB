import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.6 — main connection button.
///
/// **2026-05-16 Figma BBTB v3 sync** — full per-state composition внутри 280×280
/// Circle (frames 3043:341/3047:538/3047:598/3047:568). Status text + timer +
/// hint теперь живут ВНУТРИ кнопки; external ConnectionTimer / StatusPill
/// удалены из MainScreenView (visual noise per user feedback).
///
/// Layout per state:
/// - `.idle`/`.empty`:  "СТАРТ" 48pt Bold (controlIdle bg)
/// - `.connecting`:     "подключение" 16pt Semibold + outer Spinner ring (controlIdle bg)
/// - `.connected`:      ZStack {
///                        "подключен" 16pt Semibold @ y=-48.5,
///                        HH:MM:SS    32pt Semibold @ y=0 (TimelineView ticker),
///                        "нажми чтобы отключиться" 10pt Light @ y=+42
///                      } (accent bg, alwaysWhite text)
/// - `.error`:          ZStack {
///                        "ошибка" 16pt Semibold @ y=0,
///                        "нажми чтобы переподключиться" 10pt Light @ y=+42
///                      } (error bg, alwaysWhite text)
public struct ConnectionButton: View {
    public let state: ConnectionState
    /// Connected timestamp — passed in для inline TimelineView ticker (`.connected`
    /// state). `nil` для всех остальных states.
    public let connectedSince: Date?
    public let action: () -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(state: ConnectionState, connectedSince: Date? = nil, action: @escaping () -> Void) {
        self.state = state
        self.connectedSince = connectedSince
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // 2026-05-16 Figma BBTB v3 sync — background per state:
                // - `.connecting` → transparent fill + inset stroke ring 6pt
                //   controlIdle (Figma: static hollow ring INSIDE 280pt Circle) +
                //   rotating BBTBSpinner gradient arc ON TOP of static ring at
                //   the same diameter (visual "loading wheel").
                // - other states → solid Circle fill (controlIdle / accent / error).
                buttonBackground

                labelContent
                    .frame(width: diameter, height: diameter)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("BBTB.ConnectionButton")
    }

    /// Per-state Circle background. Connecting → inset stroke ring (Figma hollow
    /// ring внутри 280pt), other states → solid fill.
    @ViewBuilder
    private var buttonBackground: some View {
        if isConnecting {
            // Static hollow ring (Figma stroke 6pt inset by 6 inside 280pt frame).
            // `.strokeBorder` рисует stroke INSIDE frame edges — exactly matches
            // Figma `Ellipse().inset(by: 6).stroke(...)`.
            Circle()
                .strokeBorder(DS.Color.controlIdle, lineWidth: 6)
                .frame(width: diameter, height: diameter)
                .overlay {
                    // Rotating gradient arc ON TOP of static ring at same radius.
                    // BBTBSpinner uses `.stroke` (centered on frame edge) — для
                    // совпадения с inner strokeBorder ring (radius D/2 - 3) даём
                    // spinner frame `diameter - lineWidth` чтобы его stroke centered
                    // на том же radius.
                    BBTBSpinner(diameter: diameter - 6, lineWidth: 6, speed: 1.2)
                        .accessibilityHidden(true)
                }
        } else {
            Circle()
                .fill(fillColor)
                .frame(width: diameter, height: diameter)
        }
    }

    /// Per-state centered label composition (Figma BBTB v3 spec).
    @ViewBuilder
    private var labelContent: some View {
        switch state {
        case .empty, .idle:
            // Figma 3043:341 — "СТАРТ" 48pt Bold center.
            Text(L10n.actionConnect)
                .font(DS.Typography.expanded(48, weight: .bold))
                .foregroundStyle(DS.Color.textPrimary)

        case .connecting:
            // Figma 3047:538 — "подключение" 16pt Semibold center + outer Spinner ring.
            Text(L10n.homeButtonConnecting)
                .font(DS.Typography.expanded(16, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)

        case .connected:
            // Figma 3047:598 — 3-line ZStack composition с absolute y-offsets
            // matching Figma Get-Code reference (3062:249 instance @ Connected variant).
            ZStack {
                Text(L10n.homeButtonConnected)
                    .font(DS.Typography.expanded(16, weight: .semibold))
                    .foregroundStyle(DS.Color.alwaysWhite)
                    .offset(y: -48.5)

                connectedTimerView
                    .font(DS.Typography.expanded(32, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.alwaysWhite)

                Text(L10n.homeButtonHintDisconnect)
                    .font(DS.Typography.tipsLight)
                    .foregroundStyle(DS.Color.alwaysWhite)
                    .multilineTextAlignment(.center)
                    .offset(y: 42)
            }

        case .error:
            // Figma 3047:568 — 2-line ZStack: "ошибка" center + hint @ y=+42.
            ZStack {
                Text(L10n.homeButtonError)
                    .font(DS.Typography.expanded(16, weight: .semibold))
                    .foregroundStyle(DS.Color.alwaysWhite)

                Text(L10n.homeButtonHintReconnect)
                    .font(DS.Typography.tipsLight)
                    .foregroundStyle(DS.Color.alwaysWhite)
                    .multilineTextAlignment(.center)
                    .offset(y: 42)
            }
        }
    }

    /// Inline timer (replaces external ConnectionTimer for `.connected` button label).
    /// TimelineView паузит при off-screen — без cost когда screen скрыт.
    @ViewBuilder
    private var connectedTimerView: some View {
        if let since = connectedSince {
            TimelineView(.periodic(from: since, by: 1.0)) { ctx in
                Text(Self.formatInterval(ctx.date.timeIntervalSince(since)))
            }
        } else {
            Text("00:00:00")
        }
    }

    private static func formatInterval(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// Phase 11 / UX-08 — true когда state ∈ {.connecting}.
    /// `internal` для @testable access из ConnectionButtonTests (Alternative A
    /// в Plan 11-07 Task 7.1).
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

    /// Phase 12 / DS-09 / M3 — fill switch на DS.Color семантические токены.
    /// `internal` — для @testable access (ConnectionButtonTests).
    internal var fillColor: SwiftUI.Color {
        switch state {
        case .empty, .idle:  return DS.Color.controlIdle
        case .connecting:    return DS.Color.controlIdle
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
