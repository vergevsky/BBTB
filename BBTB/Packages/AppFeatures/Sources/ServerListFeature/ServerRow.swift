// ServerRow.swift — Figma BBTB v3 sync (2026-05-16 design pass).
//
// **Figma node 3064:1162 (normal) / 3064:1169 (selected):**
//   HStack(spacing: 16) {
//     Phosphor GlobeHemisphereWest 20×20 (iconSecondary | iconMuted)
//     Text(server.name) 12pt Expanded Regular (textPrimary | alwaysWhite)
//     Spacer
//     Text("N мс") 9pt Expanded Regular (textSecondary | iconMuted)
//     Phosphor CaretRight 18×18 (iconSecondary | iconMuted)
//   }
//   .padding(16)
//   .background(accent when selected else clear)
//   .overlay(bottom hairline 0.5pt surfaceHeader stroke — divider)
//
// Pre-v3 design (emoji flag + checkmark icon + LatencyBadge with tier colors)
// упрощён до single-line row: бренд-агностичный Globe + neutral typography.
// Tier color logic в LatencyBadge сохранена через `isSelected` flag (iconMuted
// override на accent bg для читаемости).

import SwiftUI
import VPNCore
import DesignSystem
import Localization
#if os(iOS)
import UIKit
#endif

public struct ServerRow: View {
    public let server: ServerConfig
    public let isSelected: Bool
    public let pingState: PingState
    public let onTap: () -> Void
    public let onDelete: () -> Void
    public let onDetailTap: () -> Void

    public init(server: ServerConfig,
                isSelected: Bool,
                pingState: PingState,
                onTap: @escaping () -> Void,
                onDelete: @escaping () -> Void,
                onDetailTap: @escaping () -> Void = {}) {
        self.server = server
        self.isSelected = isSelected
        self.pingState = pingState
        self.onTap = onTap
        self.onDelete = onDelete
        self.onDetailTap = onDetailTap
    }

    public var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 16) {
                Ph.globeHemisphereWest.bold
                    .foregroundStyle(globeColor)
                    .frame(width: 20, height: 20)

                Text(server.name)
                    .font(DS.Typography.expanded(12, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(nameColor)

                Spacer()

                LatencyBadge(
                    pingState: pingState,
                    isSupported: server.isSupported,
                    isUnreachable: server.isUnreachable,
                    isSelected: isSelected
                )

                // Detail chevron — собственный tap target для ServerDetailView push.
                Button(action: onDetailTap) {
                    Ph.caretRight.bold
                        .foregroundStyle(chevronColor)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("BBTB.ServerListSheet.ServerRow.Detail.\(server.id.uuidString)")
                .accessibilityLabel(Text(L10n.serverDetailAccessibilityHint))
            }
            .padding(16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .opacity(rowOpacity)
            .background(isSelected ? DS.Color.accent : Color.clear)
            // Figma hairline: 0.5pt stroke surfaceHeader на bottom edge каждой
            // строки — визуальный divider между rows в section card.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.Color.surfaceHeader)
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
        .accessibilityIdentifier("BBTB.ServerListSheet.ServerRow.\(server.id.uuidString)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(server.name))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityHint(Text(isSelected ? "" : L10n.serverLineHint))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.serverListDeleteServer, systemImage: "trash")
            }
        }
    }

    private var globeColor: SwiftUI.Color {
        isSelected ? DS.Color.iconMuted : DS.Color.iconSecondary
    }

    private var nameColor: SwiftUI.Color {
        if isSelected { return DS.Color.alwaysWhite }
        return server.isSupported ? DS.Color.textPrimary : DS.Color.textSecondary
    }

    private var chevronColor: SwiftUI.Color {
        isSelected ? DS.Color.iconMuted : DS.Color.iconSecondary
    }

    private var rowOpacity: Double {
        if !server.isSupported { return 0.4 }
        if server.isUnreachable { return 0.4 }
        return 1.0
    }

    private var isTappable: Bool {
        server.isSupported && !server.isUnreachable
    }

    private var accessibilityValueText: String {
        if !server.isSupported { return L10n.serverListUnsupportedBadge }
        if server.isUnreachable { return L10n.serverListUnreachable }
        switch pingState {
        case .completed(let agg):
            if let ms = agg.avgLatencyMs { return "\(ms) ms" }
            return "—"
        case .pinging: return ""
        case .idle: return "—"
        }
    }

    private func handleTap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        onTap()
    }
}
