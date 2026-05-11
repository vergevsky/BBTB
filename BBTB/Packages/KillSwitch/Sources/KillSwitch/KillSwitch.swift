import Foundation
import NetworkExtension

/// **KILL-01, KILL-02, R4 default.**
///
/// Единственная точка установки kill switch флагов на `NETunnelProviderProtocol`.
/// Вызывается из main app (Wave 4 ConfigImporter) при создании
/// `NETunnelProviderManager`'а. Никакой другой код не должен трогать
/// `includeAllNetworks` / `enforceRoutes` напрямую.
///
/// **Архитектурная связь:**
/// - Wave 4 `ConfigImporter` → создаёт `NETunnelProviderProtocol` → `KillSwitch.apply(to:)`
/// - Phase 2 (v0.2) добавит KILL-03 toggle (Расширенные → «Отключить kill switch»)
/// - Phase 10 (v0.10) добавит R5 macOS-toggle через `PlatformHooks.shouldDisableEnforceRoutes()`
///   — реализация уже учитывает это hook'ом ниже.
public enum KillSwitch {
    public static func apply(to proto: NETunnelProviderProtocol) {
        // KILL-01: системный kill switch (iOS 14+, macOS 11+)
        proto.includeAllNetworks = true

        // R4: enforceRoutes default (DNS-leak protection приоритетнее снижения детекта).
        // Phase 10 R5 hook: на macOS может вернуть true, тогда enforceRoutes=false.
        // В Phase 1 hook всегда возвращает false → enforceRoutes остаётся true.
        proto.enforceRoutes = !platformShouldDisableEnforceRoutes()

        // НЕ выставляем excludeLocalNetworks — нам нужен maximum lockdown.
        proto.excludeLocalNetworks = false

        // Всегда в туннеле — disconnectOnSleep=false важно для On-Demand (Phase 10).
        proto.disconnectOnSleep = false
    }

    // MARK: Platform-specific hook (R5 Phase 10)

    /// Phase 1 — hardcoded false на обеих платформах. Phase 10 на macOS включит чтение
    /// UserDefaults / SwiftData флага.
    private static func platformShouldDisableEnforceRoutes() -> Bool {
        // Импортировать PlatformHooks из PacketTunnelKit нельзя (KillSwitch не зависит от PacketTunnelKit
        // по архитектуре — он используется в main app, PacketTunnelKit в extension).
        // Phase 10 заменит на чтение @AppStorage/UserDefaults флага.
        return false
    }
}
