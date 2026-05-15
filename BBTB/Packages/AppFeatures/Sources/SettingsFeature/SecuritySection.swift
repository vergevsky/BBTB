import SwiftUI
import Localization

/// Phase 10 / 10-01 — Security секция AdvancedSettingsView.
///
/// Содержит 2 контрола:
/// - Certificate Pinning toggle (`certPinningEnabled`, DPI-08) — отображается на всех платформах.
/// - Enforce Routes toggle (`macOSDisableEnforceRoutes`, KILL-04) — только macOS.
///   Footer динамически переключается между `.on` и `.off` в зависимости от текущего значения
///   (`macOSDisableEnforceRoutes == false` → маршруты принудительны → footer.on).
///
/// Reuses L10n.settingsSecuritySection (уже существовал в Phase 6 для kill-switch).
public struct SecuritySection: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Section {
            // Certificate Pinning (DPI-08) — all platforms
            Toggle(L10n.settingsSecurityCertPinningLabel, isOn: $viewModel.certPinningEnabled)
                .accessibilityHint(Text(L10n.settingsSecurityCertPinningFooter))

            #if os(macOS)
            // Enforce Routes (KILL-04) — macOS only
            // NOTE: `macOSDisableEnforceRoutes = false` means routes ARE enforced.
            // Footer shows current enforcement state (not the toggle value).
            Toggle(L10n.settingsSecurityEnforceRoutesLabel, isOn: Binding(
                get: { !viewModel.macOSDisableEnforceRoutes },
                set: { enforced in viewModel.macOSDisableEnforceRoutes = !enforced }
            ))
            .accessibilityHint(Text(
                viewModel.macOSDisableEnforceRoutes
                    ? L10n.settingsSecurityEnforceRoutesFooterOff
                    : L10n.settingsSecurityEnforceRoutesFooterOn
            ))
            #endif
        } header: {
            Text(L10n.settingsSecuritySection)
        } footer: {
            #if os(macOS)
            Text(
                viewModel.macOSDisableEnforceRoutes
                    ? L10n.settingsSecurityEnforceRoutesFooterOff
                    : L10n.settingsSecurityEnforceRoutesFooterOn
            )
            #else
            Text(L10n.settingsSecurityCertPinningFooter)
            #endif
        }
    }
}
