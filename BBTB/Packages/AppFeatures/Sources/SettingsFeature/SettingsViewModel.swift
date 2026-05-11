import Foundation
import SwiftUI

/// KILL-03 — Settings page ViewModel.
@MainActor
public final class SettingsViewModel: ObservableObject {
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = true
    public init() {}
}
