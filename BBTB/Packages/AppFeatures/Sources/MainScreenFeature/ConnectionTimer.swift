import SwiftUI
import Localization
import DesignSystem

/// UX-03 + UI-SPEC §2.4 — формат HH:MM:SS.
/// Phase 2 W4.T3: `init(since: Date?)` — nil → render "00:00:00" без Timer.publish.
///
/// Phase 6d / Wave 06D-03d (H5 fix): полностью убран `Timer.publish(every: 1.0).autoconnect()`.
/// Раньше publisher создавался в инициализаторе View **независимо** от `since`,
/// и каждую секунду доставлял tick. Даже когда `since == nil`, SwiftUI re-diff'ил
/// body 60×/min на idle/error screen → StatusPill, ConnectionButton, ServerLineView,
/// toolbar пересчитывались впустую.
///
/// Текущая реализация:
/// - `since == nil` → статический `Text("00:00:00")` без таймера. Zero ticks.
/// - `since != nil` → `TimelineView(.periodic(from: since, by: 1))`. SwiftUI нативно
///   паузит расписание, когда view off-screen, и не существует timer publisher'а вообще,
///   когда disconnected.
public struct ConnectionTimer: View {
    public let since: Date?

    public init(since: Date?) { self.since = since }

    public var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Text(L10n.timerLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            timerLabel
                .font(DS.Typography.display)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var timerLabel: some View {
        if let since {
            TimelineView(.periodic(from: since, by: 1.0)) { context in
                Text(Self.format(interval: context.date.timeIntervalSince(since)))
            }
        } else {
            Text("00:00:00")
        }
    }

    public static func format(interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
