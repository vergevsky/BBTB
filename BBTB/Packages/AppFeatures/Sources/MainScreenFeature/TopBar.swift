import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §2.2 — top bar с menu icon (leading) + `+` Menu (trailing).
///
/// Plan-check F-02: используется SwiftUI native `.toolbar` ToolbarItem с placement
/// `.topBarLeading`/`.topBarTrailing` (вариант A). Этот TopBar component используется
/// как fallback на macOS если нужно дублировать toolbar вне NavigationStack.
/// MainScreenView (W4.T5) использует `.toolbar` modifier на NavigationStack.
public struct TopBar: View {
    public let onMenuTap: () -> Void
    public let onAddFromClipboard: () -> Void
    public let onScanQR: () -> Void

    public init(onMenuTap: @escaping () -> Void,
                onAddFromClipboard: @escaping () -> Void,
                onScanQR: @escaping () -> Void) {
        self.onMenuTap = onMenuTap
        self.onAddFromClipboard = onAddFromClipboard
        self.onScanQR = onScanQR
    }

    public var body: some View {
        HStack {
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("BBTB.MenuButton")
            .accessibilityLabel(Text(L10n.menuAddConfig))  // generic menu label

            Spacer()

            Menu {
                Button(action: onScanQR) {
                    Label(L10n.menuScanQR, systemImage: "qrcode.viewfinder")
                }
                Button(action: onAddFromClipboard) {
                    Label(L10n.menuImportFromClipboard, systemImage: "doc.on.clipboard")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
            }
            .accessibilityIdentifier("BBTB.AddButton")
        }
        .padding(.horizontal)
        .padding(.top, DS.Spacing.xl)
    }
}
