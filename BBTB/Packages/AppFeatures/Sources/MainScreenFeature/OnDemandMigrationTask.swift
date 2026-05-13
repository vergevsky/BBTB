// OnDemandMigrationTask.swift — Phase 6c / Plan 06C-03 / Task 2.
//
// One-shot idempotent migration для existing-install upgrade path. Закрывает
// D-17b (на upgrade от Phase 6 → Phase 6c пользователь видит toggle ON в UI,
// но manager в реальности не имеет on-demand rules — UX regression) и D-17c
// (migration выполняется ровно один раз через UserDefaults flag).
//
// Round 2 invariants (см. `.planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md`):
// - **B-05 (transient-failure safety):** ЯВНЫЕ do/catch вокруг XPC вызовов
//   (`loadAllFromPreferences`, `saveToPreferences`, `loadFromPreferences`).
//   На throw — флаг НЕ выставляется, миграция retry'нется на следующем launch.
//   Round 1 паттерн (try-question-mark + await loadAllFromPreferences) — ЗАПРЕЩЁН: он маскировал
//   transient XPC failure под «empty managers» branch и преждевременно ставил флаг.
// - **B-06 (multi-manager safety):** через `ManagerSelector.ourManagers` фильтруем
//   только наши NETunnelProviderManager инстансы. Другие VPN-приложения / residue
//   старых установок игнорируются.
// - **W-04 (single source of truth):** используем `OnDemandRulesBuilder.applyCurrentState`
//   (НЕ низкоуровневый `apply`). Один путь вычисления `isOnDemandEnabled` для всех
//   четырёх Phase 6c consumer-callsites.
// - **B-03 (TunnelController cache refresh):** после successful batch postим
//   `.bbtbProvisionerDidSave` один раз — TunnelController рефрешит `cachedManager`.
//
// Six-branch decision tree:
//   1. Флаг уже true → no-op (idempotency).
//   2. `loadAllFromPreferences` throws → log warn, флаг НЕ ставится, return (B-05).
//   3. Empty `managers` → флаг = true (нет profile вообще — fresh install).
//   4. `ourManagers` empty (есть чужие, нет наших) → флаг = true.
//   5. Для каждого нашего manager: `applyCurrentState` + save + reload;
//      на любой throw — флаг НЕ ставится, return (B-05).
//   6. Все succeeded → флаг = true, post .bbtbProvisionerDidSave (B-03).
//
// **Pitfall 1 reference:** см. `06C-RESEARCH.md` — на upgrade без миграции
// rules не записаны до первого provisionTunnelProfile / connect; этот task
// закрывает gap.

import Foundation
import NetworkExtension
import OSLog

public enum OnDemandMigrationTask {

    /// UserDefaults ключ для idempotency. Префикс `app.bbtb.` соответствует
    /// project-wide convention (D-05).
    private static let migratedKey = "app.bbtb.autoReconnectMigratedV6c"

    private static let log = Logger(
        subsystem: "app.bbtb.client",
        category: "ondemand-migration"
    )

    /// Idempotent migration. Безопасно вызывать многократно — первый успешный
    /// вызов выставляет flag; subsequent вызовы — no-op. На любую failure
    /// (B-05) flag НЕ ставится → retry на следующем app launch.
    ///
    /// - Parameters:
    ///   - userDefaults: store для flag + чтения toggle/intent через
    ///     `OnDemandRulesBuilder.applyCurrentState`. Default `.standard`;
    ///     тесты инжектят изолированный suite.
    ///   - loader: test seam (B-05) — позволяет подменить `loadAllFromPreferences()`
    ///     на closure которое throws / возвращает stub data. Production использует
    ///     реальный `NETunnelProviderManager.loadAllFromPreferences()`.
    public static func runIfNeeded(
        userDefaults: UserDefaults = .standard,
        loader: @Sendable () async throws -> [NETunnelProviderManager] = {
            try await NETunnelProviderManager.loadAllFromPreferences()
        }
    ) async {
        // Branch 1: idempotency check.
        if userDefaults.bool(forKey: migratedKey) {
            log.debug("migration: already done — no-op")
            return
        }

        // Branch 2: load with explicit do/catch (B-05).
        let managers: [NETunnelProviderManager]
        do {
            managers = try await loader()
        } catch {
            log.warning("migration: loadAllFromPreferences failed: \(String(describing: error), privacy: .public) — flag NOT set, retry next launch")
            return
        }

        // Branch 3: empty managers (no profile at all — fresh install or residue).
        if managers.isEmpty {
            log.notice("migration: no managers — fresh install or empty pool, marking migration done")
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        // Branch 4: filter to our managers via ManagerSelector (B-06).
        let ours = ManagerSelector.ourManagers(from: managers)
        if ours.isEmpty {
            log.notice("migration: managers exist but none are ours — marking migration done; our profile will be created via ConfigImporter on next import")
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        // Branch 5: apply currentState to each our manager.
        for manager in ours {
            // W-04: single source of truth — applyCurrentState (NOT direct apply).
            OnDemandRulesBuilder.applyCurrentState(to: manager, userDefaults: userDefaults)
            do {
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()  // RESEARCH §9.1
            } catch {
                log.error("migration: save/load failed for manager: \(String(describing: error), privacy: .public) — flag NOT set, retry next launch")
                return
            }
        }

        // Branch 6: success — set flag and notify TunnelController to refresh cache.
        userDefaults.set(true, forKey: migratedKey)
        log.notice("migration: applied to \(ours.count, privacy: .public) our manager(s); migration complete")
        // B-03: refresh TunnelController.cachedManager after batch migration.
        NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: nil)
    }
}
