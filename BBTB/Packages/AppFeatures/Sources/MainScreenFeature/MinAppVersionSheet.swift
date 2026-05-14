import SwiftUI
import Localization

#if canImport(AppKit)
import AppKit
#endif

/// Phase 8 W3 — D-11 modal sheet: «Доступна новая версия» upgrade prompt.
///
/// **Trigger:** `MainScreenViewModel.showMinAppVersionSheet` flips true когда
/// (`rulesSnapshot.minAppVersion > currentAppVersion`) И user ещё не dismiss'нул
/// для этой specific version (per-version `@AppStorage` flag в VM).
///
/// **Layout (08-UI-SPEC §Layout sheet):**
/// - 56pt SF Symbol arrow.up.app.fill (accent color) сверху
/// - title «Доступна новая версия» (DS.Typography.title)
/// - body с `currentVersion` interpolation
/// - 2 buttons: primary «Открыть TestFlight» (.borderedProminent) + secondary «Позже» (.plain)
///
/// **iOS:** presentationDetents = .medium; macOS: 440×320 pt fixed.
///
/// **Dismissal:** оба buttons + swipe-down → VM persists `dismissedMinAppVersion`
/// per @AppStorage флаг (UI-SPEC §Interaction Pattern 4). Persistent banner в
/// Settings → Advanced остаётся видимым (UI-SPEC §A-08).
public struct MinAppVersionSheet: View {

    public let currentVersion: String
    public let onOpenTestFlight: () -> Void
    public let onDismiss: () -> Void

    public init(
        currentVersion: String,
        onOpenTestFlight: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentVersion = currentVersion
        self.onOpenTestFlight = onOpenTestFlight
        self.onDismiss = onDismiss
    }

    public var body: some View {
        sheetContent
            // macOS fixed sizing (08-UI-SPEC §A-09 + §Layout sheet).
            #if os(macOS)
            .frame(width: 440, height: 320)
            #endif
    }

    @ViewBuilder
    private var sheetContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            // 56pt icon (08-UI-SPEC §A-10).
            Image(systemName: "arrow.up.app.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)
                .accessibilityHidden(true)

            // Title (08-UI-SPEC Typography §title).
            Text(L10n.minAppVersionSheetTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)

            // Body с `currentVersion` interpolation.
            Text(L10n.minAppVersionSheetBody(currentVersion))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

            // Primary button — borderedProminent, accent fill.
            Button(action: handleOpenTestFlight) {
                Text(L10n.minAppVersionSheetPrimary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.accentColor)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .accessibilityLabel(Text(L10n.minAppVersionSheetPrimary))
            .accessibilityHint(Text(L10n.minAppVersionSheetPrimaryHint))

            // Secondary button — plain.
            Button(action: handleDismiss) {
                Text(L10n.minAppVersionSheetSecondary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
            .accessibilityLabel(Text(L10n.minAppVersionSheetSecondary))
            .accessibilityHint(Text(L10n.minAppVersionSheetSecondaryHint))

            Spacer(minLength: 8)
        }
    }

    private func handleOpenTestFlight() {
        // Order: dismiss first → open TestFlight. Caller wires both;
        // VM выставляет dismissedMinAppVersion @AppStorage до open.
        onOpenTestFlight()
    }

    private func handleDismiss() {
        onDismiss()
    }
}

#if DEBUG
#Preview("iOS sheet") {
    Color.gray.opacity(0.2)
        .sheet(isPresented: .constant(true)) {
            MinAppVersionSheet(
                currentVersion: "0.7.0",
                onOpenTestFlight: {},
                onDismiss: {}
            )
            #if os(iOS)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #endif
        }
}
#endif
