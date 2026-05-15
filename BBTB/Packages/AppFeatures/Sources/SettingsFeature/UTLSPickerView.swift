import SwiftUI
import Localization

/// Phase 10 / 10-01 — DPI-09: uTLS fingerprint picker для Anti-DPI секции.
///
/// Отображает `Picker` с меню из 7 значений: random, chrome, firefox, safari, ios, android, edge.
/// `selection` связан с `SettingsViewModel.utlsFingerprint` (@AppStorage App Group suite).
public struct UTLSPickerView: View {
    @Binding public var selection: String

    public init(selection: Binding<String>) {
        self._selection = selection
    }

    public var body: some View {
        Picker(L10n.settingsAntiDpiUtlsLabel, selection: $selection) {
            Text(L10n.settingsAntiDpiUtlsOptionRandom).tag("random")
            Text(L10n.settingsAntiDpiUtlsOptionChrome).tag("chrome")
            Text(L10n.settingsAntiDpiUtlsOptionFirefox).tag("firefox")
            Text(L10n.settingsAntiDpiUtlsOptionSafari).tag("safari")
            Text(L10n.settingsAntiDpiUtlsOptionIos).tag("ios")
            Text(L10n.settingsAntiDpiUtlsOptionAndroid).tag("android")
            Text(L10n.settingsAntiDpiUtlsOptionEdge).tag("edge")
        }
        .pickerStyle(.menu)
    }
}
