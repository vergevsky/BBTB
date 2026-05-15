import SwiftUI
import Localization

/// Phase 10 / 10-01 — Anti-DPI секция AdvancedSettingsView.
///
/// Содержит 4 контрола (DPI-06/08/09 + ONDEMAND-01 карв-аут BIO-04/STUN):
/// - CDN Fronting toggle (`cdnFrontingEnabled`)
/// - Mux toggle (`muxEnabled`)
/// - uTLS fingerprint picker (`utlsFingerprint`) via `UTLSPickerView`
/// - STUN block toggle (`stunBlockEnabled`) с confirmation alert
///
/// `stunBlockShowConfirm` — `@Published` prop (NOT @AppStorage), управляется локально:
/// pending value хранится в `pendingStunBlock` до подтверждения пользователем.
public struct AntiDPISection: View {
    @ObservedObject public var viewModel: SettingsViewModel

    /// Временное значение STUN toggle, ожидающее подтверждения перед записью в VM.
    @State private var pendingStunBlock: Bool = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Section {
            // CDN Fronting
            Toggle(L10n.settingsAntiDpiCdnLabel, isOn: $viewModel.cdnFrontingEnabled)
                .accessibilityHint(Text(L10n.settingsAntiDpiCdnFooter))

            // Connection Multiplexing (Mux)
            Toggle(L10n.settingsAntiDpiMuxLabel, isOn: $viewModel.muxEnabled)
                .accessibilityHint(Text(L10n.settingsAntiDpiMuxFooter))

            // uTLS fingerprint picker
            UTLSPickerView(selection: $viewModel.utlsFingerprint)

            // STUN block toggle — требует подтверждения при включении
            Toggle(L10n.settingsAntiDpiStunLabel, isOn: Binding(
                get: { viewModel.stunBlockEnabled },
                set: { newValue in
                    if newValue {
                        // Показываем alert; pending state = true
                        pendingStunBlock = true
                        viewModel.stunBlockShowConfirm = true
                    } else {
                        viewModel.stunBlockEnabled = false
                    }
                }
            ))
            .accessibilityHint(Text(L10n.settingsAntiDpiStunFooter))
        } header: {
            Text(L10n.settingsAntiDpiSection)
        } footer: {
            Text(L10n.settingsAntiDpiSectionFooter)
        }
        .alert(
            L10n.settingsAntiDpiStunConfirmTitle,
            isPresented: $viewModel.stunBlockShowConfirm
        ) {
            Button(L10n.settingsAntiDpiStunConfirmAction, role: .destructive) {
                viewModel.stunBlockEnabled = pendingStunBlock
            }
            Button(L10n.settingsAntiDpiStunConfirmCancel, role: .cancel) {
                pendingStunBlock = false
            }
        } message: {
            Text(L10n.settingsAntiDpiStunConfirmMessage)
        }
    }
}
