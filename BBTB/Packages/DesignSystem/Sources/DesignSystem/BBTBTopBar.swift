// BBTBTopBar.swift — 2026-05-16 design pass.
//
// Reusable inline TopBar component (replaces native `.toolbar` to avoid iOS 26
// Liquid Glass auto-applied circle backdrop on toolbar items — Figma BBTB v3
// дизайн рисует naked Phosphor glyphs без подложки).
//
// **Layout (Figma BBTB v3 TopBar consistency):**
//   HStack(spacing: 16) {
//     leading slot (24×24 — Phosphor icon button)
//     title? (16pt Expanded Semibold textPrimary)
//     Spacer
//     trailing slot (24×24 — Phosphor icon button)
//   }
//   .padding(.horizontal, 28)
//   .padding(.top, 32)        ← дыхание сверху (matches ServerListSheet header)
//   .padding(.bottom, 16)
//
// **Usage patterns:**
// 1. Back + title (sub-screens — SettingsView, AdvancedSettingsView, HelpView):
//      BBTBTopBar(title: L10n.settingsTitle, onBack: { dismiss() })
// 2. Menu + Add (MainScreen-style):
//      BBTBTopBar(
//        leading: { Button(action: openMenu) { Ph.list.bold... }.buttonStyle(.plain) },
//        trailing: { Menu { ... } label: { Ph.plus.bold... } }
//      )
// 3. Title + refresh (ServerListSheet-style):
//      BBTBTopBar(
//        title: L10n.serverListTitle,
//        trailing: { Button(action: refresh) { Ph.arrowClockwise.bold... } }
//      )
//
// Consumer hides native nav chrome via `.toolbar(.hidden, for: .navigationBar)`
// (BBTBTopBar заменяет визуально весь nav bar).

import SwiftUI

public struct BBTBTopBar<Leading: View, Trailing: View>: View {
    public let title: String?
    @ViewBuilder public let leading: () -> Leading
    @ViewBuilder public let trailing: () -> Trailing

    public init(
        title: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 16) {
            leading()
            if let title {
                Text(title)
                    .font(DS.Typography.expanded(16, weight: .semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 28)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }
}

// MARK: - Convenience back-button helper

/// Re-usable Phosphor CaretLeft back button. Используется в sub-screen
/// BBTBTopBar `leading` slot — back-action через `@Environment(\.dismiss)`
/// или явный closure.
public struct BBTBBackButton: View {
    public let action: () -> Void
    public let accessibilityLabel: String?

    public init(accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.action = action
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Button(action: action) {
            Ph.caretLeft.bold
                .foregroundStyle(DS.Color.iconSecondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("BBTB.BackButton")
        .modifier(_AccessibilityLabelIfPresent(accessibilityLabel))
    }
}

private struct _AccessibilityLabelIfPresent: ViewModifier {
    let label: String?
    init(_ label: String?) { self.label = label }
    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(Text(label))
        } else {
            content
        }
    }
}

// MARK: - Convenience init — "back + title" pattern

public extension BBTBTopBar where Leading == BBTBBackButton, Trailing == EmptyView {
    /// Sub-screen pattern (Settings, Help, AdvancedSettings):
    ///   BBTBTopBar(title: L10n.settingsTitle, onBack: { dismiss() })
    init(title: String, onBack: @escaping () -> Void) {
        self.init(
            title: title,
            leading: { BBTBBackButton(action: onBack) },
            trailing: { EmptyView() }
        )
    }
}
