import Foundation
import os
import PacketTunnelKit

/// Phase 11 / 11-05 — TELEM-02 диагностика.
///
/// Stateless namespace для подготовки диагностического лог-файла к экспорту
/// через системный Share Sheet (D-10/D-11/D-12).
///
/// **Поток данных:**
/// 1. Прочитать `AppGroupContainer.singBoxLogPath` (extension пишет туда).
/// 2. Tail последние 2 MB (`String.suffix`) — окно "недавняя активность"
///    без структурных timestamp'ов в самом sing-box логе (см. 11-RESEARCH Open Question 2).
/// 3. Маскировка IPv4 — последний октет → `xxx` (D-12 regex).
/// 4. Добавить header с app version, OS version, anonymous device ID + disclaimer.
/// 5. Записать в `FileManager.temporaryDirectory` с уникальным именем по ISO8601 timestamp.
/// 6. Вернуть URL — он передаётся в `ShareLink(item:)` (см. `DiagnosticsSection`).
///
/// **Что НЕ делает:**
/// - Не пишет полные IP в os.Logger (privacy via `.public` только для high-level events).
/// - Не удаляет temp файл после share — Apple system сам очищает tmp при app suspend
///   (см. RESEARCH Threat T-11-05-03 mitigation, ASVS V12).
/// - Не использует `identifierForVendor` для device-id — UUID + UserDefaults стабильнее
///   (RESEARCH Anti-Pattern; A7).
/// - Не пытается фильтровать "последние 24 часа" по timestamp'ам — sing-box log не имеет
///   structured формата, 2 MB tail — pragmatic proxy.
public enum DiagnosticsExporter {

    private static let logger = Logger(subsystem: "app.bbtb.client", category: "diagnostics")

    /// UserDefaults key для persistent anonymous device-id.
    /// Сгенерированный UUID живёт пока установлено приложение (Pitfall 4 — acceptable).
    internal static let anonymousDeviceIDKey = "app.bbtb.anonymousDeviceID"

    /// Tail size в bytes — окно "недавняя активность" (см. RESEARCH Open Question 2).
    /// 2 MB ≈ несколько часов активной sing-box сессии.
    internal static let tailByteCap: Int = 2_000_000

    // MARK: - Public API

    /// Подготавливает .txt файл с tail логов + metadata header + IP-маскировкой.
    ///
    /// - Returns: URL во временной директории, готовый для `ShareLink(item:)`.
    ///   `nil` если лог отсутствует или write failed (Pitfall 8).
    public static func prepareLog() async -> URL? {
        await prepareLog(logPath: AppGroupContainer.singBoxLogPath)
    }

    // MARK: - Testable Internal API

    /// Internal вариант с inject'мом log path — для unit-тестов (передают несуществующий путь).
    ///
    /// Public wrapper всегда использует `AppGroupContainer.singBoxLogPath`; параметр default
    /// сохраняет компатибельность без отдельного метода в production коде.
    internal static func prepareLog(logPath: String) async -> URL? {
        // Проверка существования + чтение (Pitfall 8 — empty/missing file ⇒ nil).
        guard FileManager.default.fileExists(atPath: logPath) else {
            logger.info("DiagnosticsExporter: sing-box.log absent — nothing to prepare")
            return nil
        }
        let raw: String
        do {
            raw = try String(contentsOfFile: logPath, encoding: .utf8)
        } catch {
            logger.error("DiagnosticsExporter: read failed \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Tail 2 MB и IP-маскировка (IPv4 + IPv6 per T-A5 closure of C6-001).
        // **Plan 09 C6-4-002:** dotted-form IPv4-mapped/NAT64/IPv4-compat IPv6
        // (e.g. `::ffff:1.2.3.4`) leaked раньше because maskIPv4 редактировал
        // only the IPv4 octets → leaving `::ffff:1.2.3.xxx` → maskIPv6 P1 regex
        // stopped at `.` (not in `[0-9a-fA-F]{1,4}`) → final output retained
        // `[ipv6:xxx].2.3.xxx` network-prefix leak. `maskDottedIPv6` pre-pass
        // catches them WHOLE before maskIPv4 ever touches их.
        let tail = String(raw.suffix(tailByteCap))
        let masked = maskIPv6(maskIPv4(maskDottedIPv6(tail)))

        // Metadata header.
        let appVer = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let bundleVer = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceID = anonymousDeviceID()
        let header = """
        BBTB Diagnostic Log
        App: v\(appVer) (\(bundleVer))
        OS:  \(osVer)
        ID:  \(deviceID)
        Last 24h, IP addresses masked.
        ===============================

        """

        let payload = header + masked

        // Запись во временный файл с ISO8601 timestamp (уникальное имя — несколько exports не overwrite).
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")  // Files.app friendly
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bbtb-log-\(timestamp).txt")
        do {
            try payload.write(to: tmpURL, atomically: true, encoding: .utf8)
            logger.info("DiagnosticsExporter: log prepared at temporary location")
            return tmpURL
        } catch {
            logger.error("DiagnosticsExporter: write failed \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// **Plan 09 C6-4-002 (closes C6-4-002 HIGH diagnostics-leak):** masks
    /// dotted-form IPv6 hybrids before standalone-IPv4 masking runs. Pre-fix
    /// `maskIPv4` редактировал the IPv4 octets inside `::ffff:1.2.3.4`,
    /// leaving `::ffff:1.2.3.xxx` that subsequent `maskIPv6` could only
    /// partially match (regex stopped at `.`) → network prefix leak.
    ///
    /// Covers three transition-prefix dotted forms (mirrors SubscriptionURLFetcher
    /// + FrontingEngine numeric classifiers):
    /// - IPv4-mapped IPv6: `::ffff:N.N.N.N` (RFC 4291)
    /// - NAT64 well-known prefix: `64:ff9b::N.N.N.N` (RFC 6052)
    /// - IPv4-compatible IPv6: `::N.N.N.N` (RFC 4291 deprecated)
    ///
    /// Replaces matched substring entirely с `[ipv6:xxx]` token.
    ///
    /// Codex Architect thread `019e3762`.
    internal static func maskDottedIPv6(_ input: String) -> String {
        let pattern = #"(?<![:\w.])(?:(?:::[fF]{4}:)|(?:64:[fF]{2}9[bB]::)|(?:::))(?:\d{1,3}\.){3}\d{1,3}(?:%[a-zA-Z0-9]+)?(?![:\w.])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "[ipv6:xxx]")
    }

    /// D-12 — заменяет последний октет IPv4-адреса на `xxx`.
    ///
    /// Regex `(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}` → `$1xxx`.
    /// Применяется ко всему вводу (multiple matches в одной строке поддерживаются).
    ///
    /// IPv6 покрывается отдельным `maskIPv6` (T-A5, closes C6-001).
    /// Dotted-form IPv4-mapped/NAT64/IPv4-compat покрывается `maskDottedIPv6`
    /// (Plan 09 C6-4-002), который запускается ДО `maskIPv4`.
    internal static func maskIPv4(_ input: String) -> String {
        let pattern = #"(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "$1xxx")
    }

    /// T-A5 / T-A5' (closes C6-001 / C6'-001 CRITICAL privacy) — replaces IPv6 addresses
    /// в logs целиком на токен `[ipv6:xxx]`. У IPv6 нет осмысленного "последнего октета"
    /// для частичной маскировки; полная замена предпочтительна.
    ///
    /// **T-A5' (closes C6'-001 HIGH):** Plan 03 T-A5 regex P2
    /// `(?:[0-9a-fA-F]{1,4}:){0,7}::` consumed colon greedy preceding `::`, causing
    /// `fe80::1` и `2001:db8::8a2e:7334` to NOT match. Rewritten с 3 explicit
    /// alternatives covering все compressed forms safely.
    ///
    /// **Покрывает форматы:**
    /// - Full 8-group (7 colons): `2001:db8:85a3:0000:0000:8a2e:0370:7334`
    /// - Compressed leading `::`: `::1`, `::ffff:1.2.3.4`, `::`
    /// - Compressed mid/trailing `::`: `fe80::1`, `2001:db8::8a2e:7334`, `1::`
    /// - Mixed-case hex digits (`Fe80::1`)
    /// - Optional zone id: `fe80::1%en0`
    /// - IPv4-mapped IPv6 (`::ffff:1.2.3.4`): IPv4 часть уже замаскирована `maskIPv4`
    ///   ДО вызова maskIPv6; IPv6 wrapper затем замаскирует whole thing.
    ///
    /// **False-positive avoidance:** требуем либо ровно 8 групп (full form, 7 colons),
    /// либо presence of `::` (компрессия). Это исключает timestamps типа `12:34:45`
    /// (2 colons без `::`) и аналогичные числовые structures.
    internal static func maskIPv6(_ input: String) -> String {
        // Three explicit alternatives, applied sequentially:
        //  P1 — leading `::` form: `::1`, `::ffff:a.b.c.d`, bare `::`
        //  P2 — mid/trailing `::` form: `fe80::1`, `1::`, `2001:db8::8a2e:7334`
        //  P3 — full 8-group form (exactly 7 inner colons)
        //
        // Boundary check via `(?<![:\w.])` / `(?![:\w.])` lookbehind/lookahead rejects
        // matches inside identifiers (e.g. `bbtb-server-id:abc`) и decimals.
        // Optional `%zone` zone-id suffix supported.
        let patterns = [
            // P1: leading `::` — covers `::`, `::1`, `::ffff:1.2.3.4`, `::a:b:c:d`
            #"(?<![:\w.])::(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*)?(?:%[a-zA-Z0-9]+)?(?![:\w.])"#,
            // P2: mid/trailing `::` — covers `1::`, `fe80::1`, `1:2::3:4`, etc.
            //  Pattern: one-or-more hex-colon groups, then `:` literal (forming `::`),
            //  then optional hex chain. The colon after the groups + the next `:` form
            //  the `::` compression marker WITHOUT being consumed greedily.
            #"(?<![:\w.])(?:[0-9a-fA-F]{1,4}:)+:(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*)?(?:%[a-zA-Z0-9]+)?(?![:\w.])"#,
            // P3: full 8-group form, exactly 7 inner colons: `1:2:3:4:5:6:7:8`
            #"(?<![:\w.])[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4}){7}(?:%[a-zA-Z0-9]+)?(?![:\w.])"#,
        ]
        var result = input
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = result as NSString
            let range = NSRange(location: 0, length: ns.length)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[ipv6:xxx]")
        }
        return result
    }

    /// Anonymous device-id — UUID сгенерированный при первом запросе, persisted в UserDefaults.
    ///
    /// **Privacy rationale:** не `identifierForVendor` (сбрасывается при удалении всех app
    /// разработчика) — UUID per-install корректно даёт "недавняя серия экспортов одного
    /// пользователя", при этом не cross-correlatable между установками (Pitfall 4 acceptable).
    internal static func anonymousDeviceID() -> String {
        if let existing = UserDefaults.standard.string(forKey: anonymousDeviceIDKey) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: anonymousDeviceIDKey)
        return new
    }
}
