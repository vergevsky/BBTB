import SwiftUI
import Localization
import DesignSystem

/// UI-SPEC §6.2 — overlay для HTTPS subscription / JSON endpoint fetch.
public struct ImportProgressOverlay: View {
    public let message: String

    public init(message: String? = nil) {
        self.message = message ?? L10n.importProgress
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.001)  // tap-through guard
                .background(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: DS.Spacing.lg) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.5)
                Text(message)
                    .font(DS.Typography.callout)
            }
            .padding(DS.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
                    .fill(.regularMaterial)
            )
        }
    }
}
