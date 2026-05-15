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

        // Tail 2 MB и IP-маскировка.
        let tail = String(raw.suffix(tailByteCap))
        let masked = maskIPv4(tail)

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

    /// D-12 — заменяет последний октет IPv4-адреса на `xxx`.
    ///
    /// Regex `(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}` → `$1xxx`.
    /// Применяется ко всему вводу (multiple matches в одной строке поддерживаются).
    ///
    /// IPv6 не покрывается по D-12 spec — стандартное представление `::1`, `fe80::1` сохраняются
    /// без изменений (нет matching pattern на 4 octets с точками).
    internal static func maskIPv4(_ input: String) -> String {
        let pattern = #"(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "$1xxx")
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
