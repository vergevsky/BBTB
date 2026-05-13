import SwiftUI
import Localization

/// **Phase 6c / Plan 06C-03 — D-04 / D-05 / D-07.**
///
/// Reusable toggle row для раздела «Подключение» в Settings.
/// Зеркалит pattern `KillSwitchToggleSection`: один `Toggle` + accessibility hint
/// с footer-текстом; внешний `Section` собирается в `SettingsView`.
///
/// Footer объясняет пользователю D-07 invariant: «без auto-reconnect — после
/// обрыва нужно подключиться вручную» (Pitfall 4 — toggle OFF не tear down
/// активный туннель, footer коммуницирует это поведение).
public struct AutoReconnectToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String

    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn
        self.footerText = footerText
    }

    public var body: some View {
        Toggle(L10n.settingsAutoReconnectTitle, isOn: $isOn)
            .accessibilityHint(Text(footerText))
    }
}
