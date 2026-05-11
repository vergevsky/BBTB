import SwiftUI

/// UX-03: формат HH:MM:SS, обновляется каждую секунду.
public struct ConnectionTimer: View {
    public let since: Date
    @State private var now: Date = .now

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(since: Date) { self.since = since }

    public var body: some View {
        Text(Self.format(interval: now.timeIntervalSince(since)))
            .font(.system(.title, design: .monospaced))
            .monospacedDigit()
            .onReceive(timer) { self.now = $0 }
    }

    public static func format(interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
