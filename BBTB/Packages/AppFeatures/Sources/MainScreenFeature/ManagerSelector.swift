import Foundation
import NetworkExtension

/// **Phase 6c / Plan 06C-02 — B-06 / W-07.**
///
/// Single source of truth для фильтрации `NETunnelProviderManager` инстансов
/// по `providerBundleIdentifier`. iOS / macOS могут возвращать manager'ы от
/// разных приложений (или residue от legacy установок) — нам нужно brать
/// ТОЛЬКО наши, чтобы не мутировать чужие profile или не путать provisioner
/// при re-import config'а.
///
/// **5 callsites Phase 6c, которые используют этот helper:**
///   1. `ConfigImporter.DefaultTunnelProvisioner.provisionTunnelProfile` —
///      выбор существующего manager'а (Plan 06C-02 Task 2).
///   2. `SettingsViewModel.applyAutoReconnectToManager` — toggle handler
///      перебирает наши managers для re-apply (Plan 06C-03).
///   3. `OnDemandMigrationTask.runIfNeeded` — one-shot upgrade migration
///      перебирает наши managers для записи rules (Plan 06C-03).
///   4. `TunnelController.cachedManager` setup — резолвит наш manager при
///      bootstrap (Plan 06C-04).
///   5. `TunnelController.handleWake` — macOS wake nudge перебирает наши
///      managers (Plan 06C-04).
///
/// **B-06 (multi-manager safety):** на iOS 18+ возможны несколько manager'ов
/// если другое приложение тоже использует NEPacketTunnelProvider или если
/// у нас была старая установка с другим bundle ID. `managers.first` без
/// фильтра может вернуть чужой manager → silent corruption.
///
/// **W-07 (shared helper):** до этого helper'а 5 callsites дублировали бы
/// hardcoded `["app.bbtb.client.ios.tunnel", "app.bbtb.client.macos.tunnel"]`
/// Set — drift risk высокий. Single source of truth здесь.
///
/// Pattern зеркалит `KillSwitch.apply` / `OnDemandRulesBuilder.apply` —
/// static enum namespace, никакого instance state, тестируется без
/// entitlements (in-memory NETunnelProviderManager).
public enum ManagerSelector {

    /// Provider bundle IDs для BBTB tunnel extension на обеих платформах.
    ///
    /// iOS: `app.bbtb.client.ios.tunnel` (см. `BBTB_iOSApp.swift`).
    /// macOS: `app.bbtb.client.macos.tunnel` (см. `BBTB_macOSApp.swift`).
    ///
    /// Test fixtures используют другой ID (`app.bbtb.test.tunnel` и т.п.) —
    /// natural mismatch, потому что тесты не запускают реальные NEM
    /// extensions, никаких manager'ов в test env нет вообще.
    public static let ourProviderBundleIdentifiers: Set<String> = [
        "app.bbtb.client.ios.tunnel",
        "app.bbtb.client.macos.tunnel"
    ]

    /// Фильтрует переданный массив manager'ов, оставляя только те, у которых
    /// `protocolConfiguration` приводится к `NETunnelProviderProtocol` И
    /// `providerBundleIdentifier` входит в `knownBundleIDs`.
    ///
    /// Callsite берёт `.first` для legacy single-manager behavior
    /// (`provisionTunnelProfile`, `cachedManager`) или iterates по всему
    /// результату для multi-manager behavior (toggle, migration, wake nudge).
    ///
    /// - Parameters:
    ///   - managers: результат `NETunnelProviderManager.loadAllFromPreferences()`.
    ///   - knownBundleIDs: Set bundle IDs, считающихся "нашими"
    ///     (default — `ourProviderBundleIdentifiers`).
    /// - Returns: Подмножество `managers`, чьи provider bundle IDs
    ///   присутствуют в `knownBundleIDs`. Сохраняет исходный порядок.
    public static func ourManagers(
        from managers: [NETunnelProviderManager],
        knownBundleIDs: Set<String> = ourProviderBundleIdentifiers
    ) -> [NETunnelProviderManager] {
        managers.filter { manager in
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
                  let id = proto.providerBundleIdentifier else { return false }
            return knownBundleIDs.contains(id)
        }
    }
}

extension Notification.Name {
    /// **Phase 6c / Plan 06C-02 / B-03 cross-plan contract.**
    ///
    /// Posted by `DefaultTunnelProvisioner.provisionTunnelProfile` ПОСЛЕ
    /// `saveToPreferences()` + `loadFromPreferences()`. Подписчики могут
    /// рефрешить cached manager references / re-evaluate gates.
    ///
    /// **Observer side:** `TunnelController.refreshCachedManager` (Plan 06C-04
    /// Task 1) — рефрешит `cachedManager` для watchdog `managerEnabled` gate.
    /// Loose coupling: `ConfigImporter` НЕ знает про `TunnelController` —
    /// связь через NotificationCenter.
    ///
    /// `object` параметр notification: `NETunnelProviderManager?` — наш
    /// только что сохранённый manager (опционально, для удобства observer'а).
    public static let bbtbProvisionerDidSave = Notification.Name("app.bbtb.provisionerDidSave")
}
