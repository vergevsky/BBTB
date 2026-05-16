// LatencyBadge.swift — Figma BBTB v3 sync (2026-05-16 design pass).
//
// **Figma "N мс" 9pt Expanded Regular textSecondary (или iconMuted если selected).**
//
// Tier color logic (green/yellow/orange/red по latency) сохранена для
// функционального UX benefit — пользователю важно сразу видеть качество
// соединения. На accent-bg (isSelected) tier colors сливаются с фоном —
// force iconMuted.

import SwiftUI
import DesignSystem
import Localization

public struct LatencyBadge: View {
    public let pingState: PingState
    public let isSupported: Bool
    public let isUnreachable: Bool
    /// 2026-05-16 Figma sync — на accent bg (selected row) tier colors сливаются
    /// с зелёным background; force iconMuted чтобы оставалась читаемость.
    public let isSelected: Bool

    public init(pingState: PingState, isSupported: Bool, isUnreachable: Bool, isSelected: Bool = false) {
        self.pingState = pingState
        self.isSupported = isSupported
        self.isUnreachable = isUnreachable
        self.isSelected = isSelected
    }

    public var body: some View {
        content
            .accessibilityHidden(true)  // значение озвучивается через ServerRow accessibilityValue
    }

    @ViewBuilder
    private var content: some View {
        if !isSupported {
            Text(L10n.serverListUnsupportedBadge)
                .font(DS.Typography.expanded(9, weight: .regular))
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.surfaceHeader)
                .foregroundStyle(DS.Color.textSecondary)
                .clipShape(Capsule())
        } else if isUnreachable {
            Text(L10n.serverListUnreachable)
                .font(DS.Typography.expanded(9, weight: .regular))
                .foregroundStyle(.red)
        } else {
            switch pingState {
            case .pinging:
                ProgressView().scaleEffect(0.6)
            case .completed(let agg):
                if let ms = agg.avgLatencyMs {
                    Text("\(ms) мс")
                        .font(DS.Typography.expanded(9, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? DS.Color.iconMuted : colorForLatency(ms))
                } else {
                    Text("—")
                        .font(DS.Typography.expanded(9, weight: .regular))
                        .foregroundStyle(isSelected ? DS.Color.iconMuted : DS.Color.textSecondary)
                }
            case .idle:
                Text("—")
                    .font(DS.Typography.expanded(9, weight: .regular))
                    .foregroundStyle(isSelected ? DS.Color.iconMuted : DS.Color.textSecondary)
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
