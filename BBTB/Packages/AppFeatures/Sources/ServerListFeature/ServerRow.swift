// ServerRow.swift — Phase 3 / Plan 03 / Task 2.
//
// UI-SPEC §2.5 — строка сервера в ServerListSheet:
// - leading flag (24pt) — server.countryFlag (🌐 fallback)
// - title (server.name) + optional «не поддерживается» subtitle если !isSupported
// - trailing LatencyBadge + optional checkmark при isSelected
// - opacity 0.4 если !isSupported или isUnreachable
// - tap → onTap closure (haptic .light на iOS)
// - swipeActions «Удалить» (.destructive)

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

    public init(server: ServerConfig,
                isSelected: Bool,
                pingState: PingState,
                onTap: @escaping () -> Void,
                onDelete: @escaping () -> Void) {
        self.server = server
        self.isSelected = isSelected
        self.pingState = pingState
        self.onTap = onTap
        self.onDelete = onDelete
    }

    public var body: some View {
        Button(action: handleTap) {
            HStack(spacing: DS.Spacing.md) {
                Text(server.countryFlag)
                    .font(.system(size: 24))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(DS.Typography.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(server.isSupported ? .primary : .secondary)
                    if !server.isSupported {
                        Text(L10n.serverListUnsupportedBadge)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                LatencyBadge(
                    pingState: pingState,
                    isSupported: server.isSupported,
                    isUnreachable: server.isUnreachable
                )
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .opacity(rowOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
        .accessibilityIdentifier("BBTB.ServerListSheet.ServerRow.\(server.id.uuidString)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(server.name))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityHint(Text(isSelected ? "" : L10n.serverLineHint))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.serverListDeleteServer, systemImage: "trash")
            }
        }
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
