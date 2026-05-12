import Foundation
import SwiftUI
import VPNCore

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
}
