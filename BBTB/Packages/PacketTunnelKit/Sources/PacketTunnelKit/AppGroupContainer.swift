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
}
