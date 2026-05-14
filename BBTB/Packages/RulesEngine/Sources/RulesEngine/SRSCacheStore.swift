import Foundation
import PacketTunnelKit  // AppGroupContainer.rulesCacheDirectory

/// App Group filesystem actor для atomic read/write SRS + manifest files.
///
/// **Trust path:**
/// - Main app (`RulesEngineCoordinator`) — sole writer through this actor's `write(_:filename:)`.
/// - Network Extension (sing-box libbox via `route.rule_set.path`) — read-only consumer,
///   автоматически перечитывающий через `fswatch.Watcher` на mtime change.
///
/// **Atomicity contract (Pattern 5 — 08-RESEARCH.md):**
/// `Data.write(.atomic)` использует POSIX `rename(2)` под капотом → reader либо видит
/// старый inode, либо новый, никогда partial bytes. App Group container — single-volume,
/// `.atomic` гарантирован (не cross-filesystem).
///
/// **Concurrency:**
/// `actor` гарантирует serialization. Каждая операция write/read/mtime/exists — single-step,
/// в результате races между параллельными вызовами от main thread / Tasks невозможны.
/// `nonisolated let directory` — immutable, безопасно для cross-actor чтения (но всё равно
/// все file-I/O идут через actor-isolated методы).
///
/// **Test isolation:**
/// Constructor принимает injectable `directory: URL` — production callers получают
/// `AppGroupContainer.rulesCacheDirectory` по умолчанию; tests инжектят `FileManager.default
/// .temporaryDirectory.appendingPathComponent("rules-test-\(UUID())")` для полной изоляции.
///
/// **Logging:**
/// Все операции logged через `RulesEngineLogger.coordinator` (subsystem `app.bbtb.client`,
/// category `rules-engine.coordinator`). Write/overwrite — `.notice`; read-miss — `.debug`;
/// errors — `.error`.
public actor SRSCacheStore {

    /// Куда писать / откуда читать. `nonisolated let` — immutable после init, нет race
    /// при создании URLs внутри actor-isolated методов.
    public nonisolated let directory: URL

    /// Конструктор с injectable directory. По умолчанию использует production App Group path.
    ///
    /// - Parameter directory: целевая директория. Production default = `AppGroupContainer
    ///   .rulesCacheDirectory` (Library/Caches/rules под App Group). Tests passing tmp dir.
    public init(directory: URL = AppGroupContainer.rulesCacheDirectory) {
        self.directory = directory
        // Idempotent createDirectory — safe for repeated calls. AppGroupContainer.rulesCacheDirectory
        // тоже делает createDirectory, но defensive call покрывает test-injected URLs где
        // caller мог не создать parent dir.
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// Atomic write через `Data.write(.atomic)`. POSIX rename(2) — single-step replacement.
    ///
    /// - Parameter data: bytes to write.
    /// - Parameter filename: bare filename (no directory components). Сохраняется как
    ///   `directory.appendingPathComponent(filename)`.
    /// - Throws: any `Foundation` error из `Data.write` (out-of-space, permission denied, etc.).
    public func write(_ data: Data, filename: String) throws {
        let target = directory.appendingPathComponent(filename)
        try data.write(to: target, options: .atomic)
        RulesEngineLogger.coordinator.notice(
            "SRSCacheStore.write filename=\(filename, privacy: .public) bytes=\(data.count, privacy: .public)"
        )
    }

    /// Read bytes, returning nil if file missing or unreadable.
    ///
    /// **Never throws.** Missing file = `nil` (semantic — "no cached copy yet"). Production
    /// callers treat nil как signal к bootstrap-from-baseline или skip-this-step.
    public func read(filename: String) -> Data? {
        let target = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: target) else {
            RulesEngineLogger.coordinator.debug(
                "SRSCacheStore.read miss filename=\(filename, privacy: .public)"
            )
            return nil
        }
        return data
    }

    /// File modification time, или nil если файл missing / inaccessible.
    ///
    /// Используется в test assertions (`mtime delta < N seconds`) и в future RULES-09 UI
    /// для отображения «обновлено N часов назад».
    public func mtime(filename: String) -> Date? {
        let target = directory.appendingPathComponent(filename)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: target.path),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return nil
        }
        return modDate
    }

    /// Plain existence check (no read).
    public func exists(filename: String) -> Bool {
        let target = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: target.path)
    }
}
