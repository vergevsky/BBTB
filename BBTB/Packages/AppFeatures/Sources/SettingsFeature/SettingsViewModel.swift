import Foundation
import SwiftUI
import VPNCore
import NetworkExtension
import MainScreenFeature
import OSLog

/// KILL-03 + Phase 6 / NET-02..NET-03 — Settings page ViewModel.
///
/// Хранит global-настройки VPN через `@AppStorage` (per-app, синхронизируется с UserDefaults).
/// Phase 6 добавляет: `customDNS`, `adBlockEnabled` и computed `dnsConfig` —
/// derived DNSConfig по priority D-01..D-04 (CONTEXT 06).
@MainActor
public final class SettingsViewModel: ObservableObject {

    // MARK: - Stored prefs

    /// KILL-03 — kill switch toggle.
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false

    /// Phase 6 / NET-02 — D-03. Пользовательский DNS-сервер: IPv4 или hostname.
    /// Пустая строка = не задан → fall through to `adBlockEnabled` / Cloudflare.
    /// Невалидное значение (мусор) НЕ применяется — `dnsConfig` его игнорирует.
    @AppStorage("app.bbtb.customDNS") public var customDNS: String = ""

    /// Phase 6 / NET-03 — D-04. Если true и `customDNS` пуст → tunnel DNS = AdGuard.
    @AppStorage("app.bbtb.adBlockEnabled") public var adBlockEnabled: Bool = false

    /// **Phase 6c / Plan 06C-03 — D-04 / D-05.**
    ///
    /// UI toggle «Автоматическое переподключение» в разделе «Подключение».
    /// `@AppStorage` default `true` — D-04: безшовный UX из коробки, on-demand
    /// активируется автоматически после первого успешного Connect (user intent
    /// записан через `UserIntentStore` в `TunnelController`).
    ///
    /// **Pitfall 4 (RESEARCH §10):** toggle OFF при активном туннеле НЕ tear down
    /// туннель — это Apple's default behavior, footer текст коммуницирует.
    /// `applyAutoReconnectToManager` ниже только пересчитывает `isOnDemandEnabled`
    /// флаг manager'а (через `applyCurrentState`); активный туннель продолжает
    /// работать до явного пользовательского Disconnect.
    @AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true

    public init() {}

    // MARK: - Derived DNS strategy

    /// Phase 6 / NET-01..04 — derive `DNSConfig` по приоритету D-01..D-04.
    ///
    /// Priority (см. 06-CONTEXT.md):
    /// 1. `customDNS` (если валиден IPv4 или RFC 1123 hostname) — D-03.
    /// 2. `adBlockEnabled == true` → AdGuard — D-04.
    /// 3. Cloudflare default — D-02.
    ///
    /// `bootstrapAddress` всегда `tcp://1.1.1.1` (Cloudflare). Phase 6 Wave 5 (`ConfigImporter.buildDNSConfig`)
    /// переопределит bootstrap на server IP per D-01 — этот ViewModel не знает про конкретный сервер.
    ///
    /// **Defense in depth (Pitfall 9):** мусорный `customDNS` НЕ ломает sing-box JSON —
    /// валидация здесь + повторная в `ConfigImporter`.
    public var dnsConfig: DNSConfig {
        let trimmed = customDNS.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty, let formatted = formatCustomDNS(trimmed) {
            return DNSConfig(
                bootstrapAddress: "tcp://1.1.1.1",
                tunnelDNS: .custom(address: formatted)
            )
        }

        if adBlockEnabled {
            return DNSConfig(
                bootstrapAddress: "tcp://1.1.1.1",
                tunnelDNS: .adguard
            )
        }

        return DNSConfig(
            bootstrapAddress: "tcp://1.1.1.1",
            tunnelDNS: .cloudflare
        )
    }

    // MARK: - Validation helpers

    /// Returns sing-box-formatted DNS address (`tcp://<ip>` или `https://<host>/dns-query`)
    /// or `nil` если input невалиден. Trimmed input assumed (caller обязан trim).
    ///
    /// If input *looks* like an IPv4 (all dot-separated labels are pure digits) but isn't
    /// valid (octet > 255, wrong arity), reject — don't fall through to hostname check
    /// because `1.2.3.999` is clearly an intended IP, not a hostname.
    private func formatCustomDNS(_ trimmed: String) -> String? {
        if looksLikeIPv4(trimmed) {
            return isValidIPv4(trimmed) ? "tcp://\(trimmed)" : nil
        }
        if isValidHostname(trimmed) {
            return "https://\(trimmed)/dns-query"
        }
        return nil
    }

    /// All labels are pure ASCII digits → user intended an IPv4 address.
    private func looksLikeIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        for part in parts {
            guard !part.isEmpty else { return false }
            for ch in part where !ch.isASCII || !ch.isNumber {
                return false
            }
        }
        return true
    }

    /// IPv4 validation: 4 dot-separated octets, each 0...255, no extras.
    private func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            // No leading "+", "-", or spaces; must be pure digits.
            guard !part.isEmpty, part.count <= 3 else { return false }
            for ch in part where !ch.isASCII || !ch.isNumber {
                return false
            }
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
        }
        return true
    }

    /// RFC 1123 hostname (subset): non-empty, ≤ 253 chars, dot-separated labels,
    /// each label 1...63 chars, letters/digits/hyphens, no leading/trailing hyphen.
    /// Must contain at least one dot (single-label "localhost" rejected — not a DoH host).
    private func isValidHostname(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 253 else { return false }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            // First and last chars: letter or digit (no hyphen).
            guard let first = label.first, let last = label.last else { return false }
            guard first.isLetter || first.isNumber else { return false }
            guard last.isLetter || last.isNumber else { return false }
            for ch in label {
                guard ch.isASCII else { return false }
                if ch.isLetter || ch.isNumber || ch == "-" { continue }
                return false
            }
        }
        return true
    }

    // MARK: - Phase 6c — auto-reconnect live-apply

    /// **Phase 6c / Plan 06C-03 — D-06 (live-apply toggle to manager).**
    ///
    /// Применяет текущее состояние UI-toggle к `NETunnelProviderManager`
    /// (через `OnDemandRulesBuilder.applyCurrentState` — single source of truth,
    /// W-04). Один XPC-trip на toggle press; НЕ горячий путь observer.
    ///
    /// **Pitfall 4:** toggle OFF при активном туннеле НЕ tear down туннель —
    /// мы только обновляем `manager.isOnDemandEnabled` (Apple's default
    /// behavior; активный сеанс продолжает работать).
    ///
    /// **Round 2 changes:**
    /// - **W-03:** помечен `nonisolated` — выполняется off MainActor. View
    ///   вызывает через `Task.detached { await viewModel.applyAutoReconnectToManager() }`
    ///   из `.onChange(of:)` modifier, чтобы Form не блокировался XPC-trip'ом.
    /// - **W-04:** consumer `OnDemandRulesBuilder.applyCurrentState` (high-level
    ///   API), НЕ direct `apply`. Финальный `isOnDemandEnabled` всегда
    ///   `toggle && intent` — phantom auto-connect class закрыт через B-04.
    /// - **B-06:** итерируется по ВСЕМ нашим manager'ам через
    ///   `ManagerSelector` (multi-manager safe).
    /// - **B-03 cross-plan:** после save+reload КАЖДОГО manager'а постит
    ///   `.bbtbProvisionerDidSave` чтобы `TunnelController` (Plan 06C-04)
    ///   refresh свой `cachedManager` для watchdog `managerEnabled` gate.
    /// - **B-05:** explicit do/catch вокруг `loadAllFromPreferences`; ошибка
    ///   swallowed (НЕ throws). Следующий `provisionTunnelProfile` подхватит
    ///   fresh toggle value через `applyCurrentState`.
    ///
    /// Read-only consumer: значение `autoReconnectEnabled` уже записано
    /// в @AppStorage до вызова (`.onChange` срабатывает после изменения).
    /// Helper НЕ возвращает значение — он только применяет state к manager'у.
    nonisolated public func applyAutoReconnectToManager() async {
        let log = Logger(subsystem: "app.bbtb.client", category: "settings-auto-reconnect")
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let ours = ManagerSelector.ourManagers(from: managers)
            for manager in ours {
                OnDemandRulesBuilder.applyCurrentState(to: manager)
                do {
                    try await manager.saveToPreferences()
                    try await manager.loadFromPreferences()  // RESEARCH §9.1
                    NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: manager)
                } catch {
                    log.error("applyAutoReconnectToManager: save/reload failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            // B-05: transient NEM ошибка не critical — toggle value уже в @AppStorage,
            // следующий provisionTunnelProfile / migration task подхватит fresh value
            // через OnDemandRulesBuilder.applyCurrentState.
            log.warning("applyAutoReconnectToManager: loadAllFromPreferences failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
