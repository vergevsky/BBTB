// LatencyBadge.swift — Phase 3 / Plan 03 / Task 2.
//
// UI-SPEC §2.5 trailing badge: рендерит state-driven содержимое ServerRow:
// - !isSupported → «не поддерживается» pill (.tertiarySystemFill background)
// - isUnreachable → «недоступен» (red)
// - .pinging → ProgressView spinner
// - .completed(agg) с avgLatencyMs → «N ms» c colorForLatency (UI-SPEC §2.6 тиры)
// - .completed(agg) с nil avg → «—»
// - .idle → «—»

import SwiftUI
import DesignSystem
import Localization

public struct LatencyBadge: View {
    public let pingState: PingState
    public let isSupported: Bool
    public let isUnreachable: Bool

    public init(pingState: PingState, isSupported: Bool, isUnreachable: Bool) {
        self.pingState = pingState
        self.isSupported = isSupported
        self.isUnreachable = isUnreachable
    }

    public var body: some View {
        content
            .accessibilityHidden(true)  // значение озвучивается через ServerRow accessibilityValue
    }

    @ViewBuilder
    private var content: some View {
        if !isSupported {
            Text(L10n.serverListUnsupportedBadge)
                .font(DS.Typography.caption)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        } else if isUnreachable {
            Text(L10n.serverListUnreachable)
                .font(DS.Typography.subheadline)
                .foregroundStyle(.red)
        } else {
            switch pingState {
            case .pinging:
                ProgressView().scaleEffect(0.7)
            case .completed(let agg):
                if let ms = agg.avgLatencyMs {
                    Text("\(ms) ms")
                        .font(DS.Typography.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(colorForLatency(ms))
                } else {
                    Text("—").font(DS.Typography.subheadline).foregroundStyle(.secondary)
                }
            case .idle:
                Text("—").font(DS.Typography.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// UI-SPEC §2.6 — latency tiers.
    private func colorForLatency(_ ms: Int) -> Color {
        switch ms {
        case ..<81: return .green
        case ..<201: return .yellow
        case ..<501: return .orange
        default: return .red
        }
    }
}
