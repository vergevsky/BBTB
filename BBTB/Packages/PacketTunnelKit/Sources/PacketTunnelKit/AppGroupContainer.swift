import Foundation

/// App Group helper для shared storage между main app и extension.
/// CORE-07: конфигурация туннеля проксируется через App Group.
public enum AppGroupContainer {
    /// `group.app.bbtb.shared` — захардкожено по CONTEXT.md §1 (D-01 после rebrand).
    public static let identifier = "group.app.bbtb.shared"

    /// URL контейнера. Доступен и из main app, и из extension.
    /// Падает с fatalError если App Group не выписан в entitlements (=bootstrap bug).
    public static var url: URL {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else {
            fatalError("App Group \(identifier) not configured in entitlements")
        }
        return url
    }

    /// Working path для libbox (logs, internal state, command.sock).
    ///
    /// **Почему AppGroup root, а не поддиректория:** libbox создаёт Unix-сокет по пути
    /// `{workingPath}/command.sock`. На Darwin `sockaddr_un.sun_path` = 104 байта
    /// включая NUL → usable 103. Поддиректория `singbox/` давала путь длиной ровно
    /// 104 символа («…AppGroup/<UUID>/singbox/command.sock»), что вызывало
    /// `bind: invalid argument` при `commandServer.start()`. См. `wiki/security-gaps.md` R8.
    public static var singBoxWorkingPath: String {
        return url.path
    }

    /// Поддиректория для crash reports (Wave 5 MXMetricManager subscriber).
    public static var crashReportsURL: URL {
        let dir = url.appendingPathComponent("crash-reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Поддиректория для Phase 8 Rules Engine SRS cache.
    ///
    /// **Shared writer/reader contract:**
    /// - Main app (`RulesEngineCoordinator` + `SRSCacheStore`) — единственный writer.
    /// - Network Extension (sing-box libbox `route.rule_set.path`) — read-only consumer
    ///   через `fswatch.Watcher` (auto-reload при mtime change).
    /// - Atomic write через `Data.write(.atomic)` гарантирует POSIX rename(2) semantics —
    ///   reader либо видит старый файл, либо новый, никогда partial (см. 08-RESEARCH § Pattern 5).
    ///
    /// **Path layout:**
    /// - `{App Group}/Library/Caches/rules/baseline-rules-manifest.json` + `.sig`
    /// - `{App Group}/Library/Caches/rules/bbtb-block.srs` + `.sig`
    /// - `{App Group}/Library/Caches/rules/bbtb-never.srs` + `.sig`
    /// - `{App Group}/Library/Caches/rules/bbtb-always.srs` + `.sig`
    ///
    /// **Idempotent createDirectory** — safe для вызова из обоих процессов (defensive call
    /// в `expandConfigForTunnel` per 08-PATTERNS Risk #2 — extension cold-start race protection).
    public static var rulesCacheDirectory: URL {
        let dir = url.appendingPathComponent("Library/Caches/rules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Путь до sing-box internal log (Phase 1 device debug).
    /// Пишется extension'ом, читается main app (см. `exportSingBoxLogToDocuments`).
    public static var singBoxLogPath: String {
        return url.appendingPathComponent("sing-box.log").path
    }

    /// Phase 1 device debug bridge: App Group container недоступен через Xcode
    /// "Download Container" GUI — Apple показывает только sandbox самой app.
    /// Поэтому main app на старте копирует sing-box.log из App Group в свой
    /// Documents/, откуда Xcode уже скачивает.
    ///
    /// Возвращает destination URL если копирование удалось, иначе nil
    /// (лог отсутствует или ошибка ввода-вывода).
    ///
    /// TODO Phase 5: убрать вместе с logPath инъекцией в expandConfigForTunnel.
    @discardableResult
    public static func exportSingBoxLogToDocuments() -> URL? {
        let src = URL(fileURLWithPath: singBoxLogPath)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        guard let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let dst = docs.appendingPathComponent("sing-box.log")
        try? FileManager.default.removeItem(at: dst)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            return dst
        } catch {
            return nil
        }
    }
}
