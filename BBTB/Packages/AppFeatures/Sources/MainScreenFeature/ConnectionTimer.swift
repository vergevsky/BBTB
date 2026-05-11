import SwiftUI
import Localization
import DesignSystem

/// UX-03 + UI-SPEC §2.4 — формат HH:MM:SS.
/// Phase 2 W4.T3: `init(since: Date?)` — nil → render "00:00:00" без Timer.publish.
public struct ConnectionTimer: View {
    public let since: Date?
    @State private var now: Date = .now

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(since: Date?) { self.since = since }

    public var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Text(L10n.timerLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(timerText)
                .font(DS.Typography.display)
                .monospacedDigit()
        }
        .onReceive(timer) { value in
            if since != nil { self.now = value }
        }
    }

    private var timerText: String {
        guard let since = since else { return "00:00:00" }
        return Self.format(interval: now.timeIntervalSince(since))
    }

    public static func format(interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
