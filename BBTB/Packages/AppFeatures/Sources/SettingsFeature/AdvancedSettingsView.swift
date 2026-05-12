import SwiftUI
import Localization

/// Phase 6 / 06-03 — экран Settings → Advanced.
///
/// Содержит DNS-секцию с двумя контролами:
/// - `AdBlockToggleSection` — bound to `viewModel.adBlockEnabled` (D-04).
/// - `CustomDNSField` — bound to `viewModel.customDNS` (D-03).
///
/// Footer объясняет priority: customDNS > AdBlock > Cloudflare default.
/// Логика выбора DNS — в `SettingsViewModel.dnsConfig` (D-01..D-04, см. 06-CONTEXT.md).
public struct AdvancedSettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section {
                AdBlockToggleSection(
                    isOn: $viewModel.adBlockEnabled,
                    footerText: L10n.settingsDnsAdblockFooter
                )
                CustomDNSField(text: $viewModel.customDNS)
            } header: {
                Text(L10n.settingsDnsSection)
            } footer: {
                Text(L10n.settingsDnsCustomFooter)
            }
        }
        .navigationTitle(L10n.settingsAdvancedTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
