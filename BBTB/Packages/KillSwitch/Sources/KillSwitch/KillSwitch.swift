import Foundation
import NetworkExtension

/// **KILL-01, KILL-02, KILL-03, R4 default.**
///
/// Единственная точка установки kill switch флагов на `NETunnelProviderProtocol`.
/// Вызывается из main app (Phase 1 W4 / Phase 2 W3 ConfigImporter) при создании
/// `NETunnelProviderManager`'а. Никакой другой код не должен трогать
/// `includeAllNetworks` / `enforceRoutes` напрямую.
///
/// **Архитектурная связь:**
/// - `ConfigImporter` → создаёт `NETunnelProviderProtocol` → `KillSwitch.apply(to:enabled:)`.
/// - Phase 2 (v0.2) добавляет KILL-03 toggle (Settings → Безопасность → Kill Switch).
///   Flag читается из `UserDefaults.standard.bool(forKey: "app.bbtb.killSwitchEnabled")`
///   ConfigImporter'ом, и передаётся в `apply(to:enabled:)` (D-14, D-15).
/// - Phase 10 (v0.10) добавит R5 macOS-toggle через `platformShouldDisableEnforceRoutes()` —
///   реализация уже учитывает это hook'ом ниже.
public enum KillSwitch {

    /// Применить kill switch к `NETunnelProviderProtocol`.
    ///
    /// - Parameter enabled: D-15. Когда `true` (Phase 1 carry-forward / KILL-01 default) —
    ///   `includeAllNetworks=true` + `enforceRoutes=!platformShouldDisableEnforceRoutes()`.
    ///   Когда `false` — `includeAllNetworks=false` + `enforceRoutes=false` (split-VPN mode).
    ///   В обоих случаях `excludeLocalNetworks=false` и `disconnectOnSleep=false` (R4 default).
    public static func apply(to proto: NETunnelProviderProtocol, enabled: Bool) {
        if enabled {
            // KILL-01: системный kill switch (iOS 14+, macOS 11+).
            proto.includeAllNetworks = true
            // R4: enforceRoutes default (DNS-leak protection приоритетнее снижения детекта).
            // Phase 10 R5 hook: на macOS может вернуть true, тогда enforceRoutes=false.
            proto.enforceRoutes = !platformShouldDisableEnforceRoutes()
        } else {
            // KILL-03: пользователь явно выключил kill switch.
            proto.includeAllNetworks = false
            proto.enforceRoutes = false
        }

        // НЕ выставляем excludeLocalNetworks — нам нужен maximum lockdown ВСЕГДА.
        proto.excludeLocalNetworks = false

        // Всегда в туннеле — disconnectOnSleep=false важно для On-Demand (Phase 10).
        proto.disconnectOnSleep = false
    }

    // MARK: Platform-specific hook (R5 Phase 10 / KILL-04)

    /// Phase 10 / D-17 / KILL-04 — читает `app.bbtb.macOSDisableEnforceRoutes`
    /// из App Group UserDefaults suite на macOS. iOS возвращает false (нет тоггла).
    ///
    /// **Примечание:** Suite name захардкожен как `"group.app.bbtb.shared"` — KillSwitch
    /// package не зависит от PacketTunnelKit (Phase 1 architectural design; KillSwitch
    /// используется в main app, PacketTunnelKit — в extension). При изменении app_group
    /// в config.json необходимо обновить эту строку.
    ///
    /// macOS: читает App Group UserDefaults. Default false = enforceRoutes enabled (R4).
    /// iOS: всегда false (iOS не имеет macOS enforceRoutes toggle).
    public static func platformShouldDisableEnforceRoutes() -> Bool {
        #if os(macOS)
        let defaults = UserDefaults(suiteName: "group.app.bbtb.shared")
        return defaults?.bool(forKey: "app.bbtb.macOSDisableEnforceRoutes") ?? false
        #else
        return false
        #endif
    }
}
