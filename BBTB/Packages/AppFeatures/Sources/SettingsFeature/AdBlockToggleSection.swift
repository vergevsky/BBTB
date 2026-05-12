import SwiftUI
import Localization

/// Phase 6 / NET-03 (D-04) — Toggle row для AdBlock-DNS в AdvancedSettingsView.
/// Mirror `KillSwitchToggleSection`: один `@Binding Bool` + footer hint для accessibility.
public struct AdBlockToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String

    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn
        self.footerText = footerText
    }

    public var body: some View {
        Toggle(L10n.settingsDnsAdblockLabel, isOn: $isOn)
            .accessibilityHint(Text(footerText))
    }
}
