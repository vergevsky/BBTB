import SwiftUI
import Localization

/// UI-SPEC §4 / D-12 — раздел «Подключение» (Phase 6c / Plan 06C-03 / D-04..D-07)
/// располагается ПЕРЕД «Безопасностью» по UX-приоритету «Подключение → Безопасность → Расширенные».
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            // Phase 6c / Plan 06C-03 — раздел «Подключение» с переключателем
            // «Автоматическое переподключение» (D-04 default ON; D-06 live-apply).
            Section {
                AutoReconnectToggleSection(
                    isOn: $viewModel.autoReconnectEnabled,
                    footerText: L10n.settingsAutoReconnectFooter
                )
            } header: {
                Text(L10n.settingsConnectionSection)
            } footer: {
                Text(L10n.settingsAutoReconnectFooter)
            }

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

            // Phase 6 / 06-03 — entry to AdvancedSettingsView (DNS, AdBlock).
            Section {
                NavigationLink(destination: AdvancedSettingsView(viewModel: viewModel)) {
                    Text(L10n.settingsAdvancedEntryLabel)
                }
            }

            // Phase 11 / 11-05 — TELEM-02: «Диагностика» секция (D-10/D-11/D-12).
            // DiagnosticsSection сам возвращает Section на верхнем уровне body —
            // НЕ оборачиваем в outer Section, иначе Form покажет вложенные Section.
            DiagnosticsSection()

            // Phase 11 / 11-06 / LOC-03 / D-09 — Help / FAQ entry (последняя секция Form).
            Section {
                NavigationLink(destination: HelpView()) {
                    Label(L10n.helpEntryLabel, systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("BBTB.Settings.HelpRow")
            }
        }
        // Phase 6c / Plan 06C-03 / W-03 — live-apply toggle через off-main `Task.detached`.
        // Helper `applyAutoReconnectToManager` сам `nonisolated`, но `.detached`
        // укрепляет контракт: SwiftUI Form никогда не блокируется на XPC trip.
        // D-06 single XPC trip per toggle press; Pitfall 4 — toggle OFF не tear down.
        .onChange(of: viewModel.autoReconnectEnabled) { _, _ in
            Task.detached { await viewModel.applyAutoReconnectToManager() }
        }
        .navigationTitle(L10n.settingsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
