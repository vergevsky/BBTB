import SwiftUI
import Localization

/// UI-SPEC §4 / KILL-03 — Toggle row для Settings.
public struct KillSwitchToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String

    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn
        self.footerText = footerText
    }

    public var body: some View {
        Toggle(L10n.settingsKillSwitchLabel, isOn: $isOn)
            .accessibilityHint(Text(footerText))
    }
}
