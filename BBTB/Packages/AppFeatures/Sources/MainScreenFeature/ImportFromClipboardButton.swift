import SwiftUI
import Localization

public struct ImportFromClipboardButton: View {
    public let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(L10n.emptyTitle).font(.headline)
            Text(L10n.emptySubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(L10n.actionImportFromClipboard, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
