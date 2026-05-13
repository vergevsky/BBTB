import Foundation
import NetworkExtension
import OSLog

/// **Phase 6c / Plan 06C-01 — D-01, D-01b, D-02, D-03, D-04, D-05.**
///
/// Единственная точка конфигурации on-demand reconnect правил на
/// `NETunnelProviderManager`. Все Phase 6c консьюмеры (`ConfigImporter`,
/// `SettingsViewModel` toggle handler, `OnDemandMigrationTask`,
/// `TunnelController.connect`/`disconnect`) идут СЮДА — это аналог
/// `KillSwitch.apply` для on-demand системы.
///
/// **D-01 (RESEARCH correction):** Phase 6c использует
/// `NEOnDemandRuleConnect(interfaceType: .any)`. Альтернативный
/// evaluate-connection rule-тип по контракту Apple staff (forum thread
/// 81249) требует non-empty `matchDomains` — для catch-all «любой interface
/// → connect» это anti-pattern (см. `06C-RESEARCH.md` «Anti-Patterns»).
/// Идиоматический Apple-pattern, который используют WireGuard iOS и
/// sing-box-for-apple — `NEOnDemandRuleConnect(.any)`.
///
/// **D-01b extensibility (Phase 8 contract):** Phase 8 Rules Engine
/// (per-SSID, per-domain) добавит evaluate-connection rules (Apple's
/// rule-тип для матчинга по SSID/domain) в массив правил. Они МОГУТ
/// быть только prepended ПЕРЕД catch-all `NEOnDemandRuleConnect` —
/// `onDemandRules` это first-match-wins per Apple's NetworkExtension
/// semantics. Callsite signatures `apply` / `applyCurrentState` остаются
/// стабильны; меняется только внутренний `buildRules()`. См. doc-comment
/// `buildRules` ниже (W-08 ordering contract).
///
/// **B-04 cross-plan contract (UserDefaults shared keys):**
/// - `app.bbtb.autoReconnectEnabled` — UI toggle (D-04 default ON);
///   пишет `SettingsViewModel`, читает `loadAutoReconnectEnabled`.
/// - `app.bbtb.userIntendedConnected` — пользователь явно нажал Connect;
///   ПИШЕТ `UserIntentStore` (см. `TunnelController.swift` ~line 73), читает
///   `loadUserIntendedConnected`. Default false: на свежей установке / после
///   reinstall intent отсутствует → `applyCurrentState` НЕ включает on-demand
///   до явного пользовательского Connect (закрывает Phase 6 phantom connect
///   bug class — теперь OS-driven, но gate тот же).
///
/// **Pattern reference:** аналог `KillSwitch.apply(to:enabled:)` в
/// `Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` — static enum
/// namespace, никакого instance state, тестируется без entitlements.
public enum OnDemandRulesBuilder {

    private static let log = Logger(
        subsystem: "app.bbtb.client",
        category: "ondemand-builder"
    )

    // MARK: - Public API

    /// Низкоуровневый apply — callers контролируют флаг явно.
    ///
    /// Записывает один `NEOnDemandRuleConnect(.any)` rule в
    /// `manager.onDemandRules` и зеркалит `isOnDemandEnabled` в
    /// `manager.isOnDemandEnabled`.
    ///
    /// **Важно:** правила записываются ВСЕГДА, даже когда
    /// `isOnDemandEnabled == false`. Это позволяет re-enable через UI toggle
    /// БЕЗ вызова `provisionTunnelProfile` или импорта конфига (Pitfall 9
    /// RESEARCH — каждый apply записывает консистентный state).
    ///
    /// **Не вызывает** `saveToPreferences()` — это ответственность callsite
    /// (см. `ConfigImporter.provisionTunnelProfile` в Wave 1).
    ///
    /// **Round 2 (B-04 rename):** параметр был `autoReconnectEnabled`,
    /// переименован в `isOnDemandEnabled` чтобы избежать путаницы между
    /// UI-toggle и финальным manager-флагом. Финальный флаг = `toggle && intent`.
    /// Низкоуровневый apply теперь зарезервирован для тестов; продакшен код
    /// должен использовать `applyCurrentState(to:userDefaults:)`.
    ///
    /// - Parameters:
    ///   - manager: `NETunnelProviderManager`, чей on-demand state нужно настроить.
    ///   - isOnDemandEnabled: финальный флаг `manager.isOnDemandEnabled` — Bool,
    ///     управляющий тем, активирует ли iOS правила автоматически.
    public static func apply(
        to manager: NETunnelProviderManager,
        isOnDemandEnabled: Bool
    ) {
        manager.onDemandRules = buildRules()
        manager.isOnDemandEnabled = isOnDemandEnabled
        log.info("OnDemandRulesBuilder.apply isOnDemandEnabled=\(isOnDemandEnabled, privacy: .public)")
    }

    /// **Phase 6c single source of truth — все консьюмеры идут СЮДА.**
    ///
    /// Высокоуровневая точка входа: считывает UI toggle
    /// (`app.bbtb.autoReconnectEnabled`, default ON) И user intent
    /// (`app.bbtb.userIntendedConnected`, default false), AND-объединяет их,
    /// и вызывает низкоуровневый `apply`. Закрывает:
    ///
    /// - **B-04 phantom connect:** на свежей установке intent отсутствует →
    ///   on-demand НЕ активируется автоматически (нужен явный Connect).
    /// - **W-04 drift:** один путь вычисления `isOnDemandEnabled` для всех
    ///   четырёх Phase 6c consumer-callsites:
    ///     1. `ConfigImporter.provisionTunnelProfile` (после save manager'а).
    ///     2. `SettingsViewModel.applyAutoReconnectToManager` (toggle flip в UI).
    ///     3. `OnDemandMigrationTask.runIfNeeded` (one-shot upgrade migration).
    ///     4. `TunnelController.connect/disconnect` (mirror intent flip).
    ///
    /// **Не вызывает** `saveToPreferences()` — callsite отвечает.
    ///
    /// - Parameters:
    ///   - manager: `NETunnelProviderManager` для конфигурации.
    ///   - userDefaults: source of `autoReconnectEnabled` + `userIntendedConnected`.
    ///     Default `.standard`; tests инжектят изолированный suite.
    public static func applyCurrentState(
        to manager: NETunnelProviderManager,
        userDefaults: UserDefaults = .standard
    ) {
        let toggle = loadAutoReconnectEnabled(userDefaults: userDefaults)
        let intent = loadUserIntendedConnected(userDefaults: userDefaults)
        let enabled = toggle && intent
        apply(to: manager, isOnDemandEnabled: enabled)
    }

    /// Читает UI toggle «Автоматическое переподключение» из UserDefaults.
    ///
    /// **D-04: default ON.** На свежей установке (ключ никогда не записывался)
    /// возвращает `true`. Использует `object(forKey:) as? Bool ?? true` — НЕ
    /// `.bool(forKey:)`, который по умолчанию возвращает `false` и сломал бы
    /// D-04 invariant.
    ///
    /// - Parameters:
    ///   - userDefaults: store (default `.standard`).
    ///   - key: UserDefaults ключ (default `app.bbtb.autoReconnectEnabled`,
    ///     соответствует D-05 — паттерн `app.bbtb.killSwitchEnabled`).
    /// - Returns: `true` на свежей установке или если значение `true`;
    ///   `false` только если в UserDefaults явно записан `false`.
    public static func loadAutoReconnectEnabled(
        userDefaults: UserDefaults = .standard,
        key: String = "app.bbtb.autoReconnectEnabled"
    ) -> Bool {
        userDefaults.object(forKey: key) as? Bool ?? true
    }

    /// Читает user-intent флаг из UserDefaults.
    ///
    /// **B-04 cross-plan contract:** этот ключ ПИШЕТ `UserIntentStore`
    /// в `TunnelController.swift` (`save(_:)` метод). Builder ТОЛЬКО читает
    /// — write остаётся за UserIntentStore (Phase 6c не меняет writer).
    /// Один UserDefaults ключ — две роли (writer в TunnelController, reader
    /// здесь). Контракт документирован в обоих файлах.
    ///
    /// **Default FALSE** (в отличие от `loadAutoReconnectEnabled`): на свежей
    /// установке или после reinstall intent отсутствует. Это критический
    /// контракт против phantom auto-connect — пока пользователь не нажмёт
    /// Connect, on-demand НЕ активируется.
    ///
    /// - Parameters:
    ///   - userDefaults: store (default `.standard`).
    ///   - key: UserDefaults ключ (default `app.bbtb.userIntendedConnected`,
    ///     тот же что использует `UserIntentStore.init`).
    /// - Returns: `false` на свежей установке; иначе записанное значение.
    public static func loadUserIntendedConnected(
        userDefaults: UserDefaults = .standard,
        key: String = "app.bbtb.userIntendedConnected"
    ) -> Bool {
        userDefaults.object(forKey: key) as? Bool ?? false
    }

    // MARK: - Phase 8 extension point

    /// Returns the rule array. Phase 6c emits exactly one `NEOnDemandRuleConnect(.any)`.
    ///
    /// **W-08 Phase 8 ordering contract:** future evaluate-connection rules
    /// (per-SSID, per-domain — Apple's rule-тип для match-domain/SSID-based
    /// activation) MUST be prepended to the array — `onDemandRules` is
    /// first-match-wins per Apple's NetworkExtension semantics. The catch-all
    /// connect rule MUST remain the last entry so more specific rules can
    /// short-circuit ahead of it. Phase 8 will extend this function in place
    /// WITHOUT touching `apply` / `applyCurrentState` callsite signatures.
    ///
    /// Сейчас (Phase 6c): один catch-all правило.
    private static func buildRules() -> [NEOnDemandRule] {
        let connectRule = NEOnDemandRuleConnect()
        connectRule.interfaceTypeMatch = .any
        return [connectRule]
    }
}
