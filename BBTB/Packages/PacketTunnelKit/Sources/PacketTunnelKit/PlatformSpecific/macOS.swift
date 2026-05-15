#if os(macOS)
import Foundation

/// macOS-specific hooks для PacketTunnelKit.
///
/// **Phase 10 / D-17 / KILL-04:** `shouldDisableEnforceRoutes()` читает
/// `app.bbtb.macOSDisableEnforceRoutes` из App Group UserDefaults suite
/// (записан SettingsViewModel через @AppStorage(store: App Group suite)).
/// Default false = enforceRoutes остаётся true (безопасное поведение по умолчанию).
///
/// KillSwitch.apply(to:) вызывает этот хук для определения итогового значения
/// `enforceRoutes`. iOS не имеет этого файла (#if os(macOS)) — Phase 10 R5 scope.
public enum PlatformHooks {
    /// Phase 10 / D-17 / KILL-04: читает `app.bbtb.macOSDisableEnforceRoutes`
    /// из App Group UserDefaults suite. Default false — enforceRoutes enabled (R4).
    ///
    /// Вызывается из `KillSwitch.apply(to:enabled:)` при `enabled=true`.
    /// При `enabled=false` (KILL-03 off) — KillSwitch напрямую ставит enforceRoutes=false.
    public static func shouldDisableEnforceRoutes() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroupContainer.identifier)
        return defaults?.bool(forKey: "app.bbtb.macOSDisableEnforceRoutes") ?? false
    }
}
#endif
