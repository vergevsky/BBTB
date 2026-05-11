import SwiftUI
import Localization

/// UI-SPEC §4 / D-12 — Phase 2 v0.2 содержит ТОЛЬКО раздел «Безопасность» с Kill Switch toggle.
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section {
                KillSwitchToggleSection(
                    isOn: $viewModel.killSwitchEnabled,
                    footerText: L10n.settingsKillSwitchFooter
                )
            } header: {
                Text(L10n.settingsSecuritySection)
            } footer: {
                Text(L10n.settingsKillSwitchFooter)
            }
        }
        .navigationTitle(L10n.settingsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
