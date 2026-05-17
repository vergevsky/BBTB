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
    /// - Throws:
    ///   - `WriteError.unsafeFilename` если filename contains path-traversal characters
    ///     (T-A1 / C5-004 closure).
    ///   - any `Foundation` error из `Data.write` (out-of-space, permission denied, etc.).
    public func write(_ data: Data, filename: String) throws {
        try Self.validateBareFilename(filename)
        let target = directory.appendingPathComponent(filename)
        try data.write(to: target, options: .atomic)
        RulesEngineLogger.coordinator.notice(
            "SRSCacheStore.write filename=\(filename, privacy: .public) bytes=\(data.count, privacy: .public)"
        )
    }

    /// **T-A1 (closes A5-005 / C5-005 HIGH): two-phase group write для best-effort
    /// atomicity по группе файлов.**
    ///
    /// Procedure:
    /// 1. Validate каждый filename как bare (no path traversal).
    /// 2. Write each `(data, filename)` к `<filename>.bbtb-staging` через atomic single-file write.
    /// 3. После того как ВСЕ staging-files записаны успешно → POSIX-rename каждый
    ///    staging-file к final filename (FileManager.replaceItem — atomic per file).
    /// 4. Если step 2 fails — staging files могут остаться, но final files не тронуты
    ///    (старая версия кэша целая). Cleanup staging при следующем commit.
    /// 5. Если step 3 fails в середине — partial группы (старые + новые). Лучше чем
    ///    partial single file. Real atomicity требует versioned-dir swap (defer).
    ///
    /// - Parameter files: ordered массив `(data, filename)` пар. Каждый filename должен
    ///   быть bare (validated).
    /// - Throws: WriteError.unsafeFilename или I/O errors.
    public func commitTransaction(_ files: [(data: Data, filename: String)]) throws {
        // Step 1: validate ALL filenames before any disk write.
        for entry in files {
            try Self.validateBareFilename(entry.filename)
        }
        // Step 2: write all к staging suffix.
        var stagingURLs: [URL] = []
        for entry in files {
            let staging = directory.appendingPathComponent("\(entry.filename).bbtb-staging")
            try entry.data.write(to: staging, options: .atomic)
            stagingURLs.append(staging)
        }
        // Step 3: atomic-rename each staging → final.
        let fm = FileManager.default
        for (i, entry) in files.enumerated() {
            let final = directory.appendingPathComponent(entry.filename)
            // POSIX rename via replaceItemAt — atomic when source/destination same volume.
            // App Group container — single-volume; safe.
            _ = try fm.replaceItemAt(final, withItemAt: stagingURLs[i])
        }
        RulesEngineLogger.coordinator.notice(
            "SRSCacheStore.commitTransaction wrote \(files.count, privacy: .public) files group-atomically"
        )
    }

    public enum WriteError: Error, LocalizedError, Equatable {
        /// T-A1 / C5-004 — filename содержит path-traversal patterns (`/`, `\`, `..`,
        /// percent-encoded forms, absolute path) или non-bare префиксы (empty, hidden `.`).
        case unsafeFilename(String)

        public var errorDescription: String? {
            switch self {
            case .unsafeFilename(let s): return "SRSCacheStore: unsafe filename rejected: \(s)"
            }
        }
    }

    /// **T-A1 (closes C5-004 / A5-002 CRITICAL):** validate filename as bare —
    /// no directory components, no traversal patterns. Manifest-supplied filenames
    /// pass through here before any filesystem write.
    private static func validateBareFilename(_ filename: String) throws {
        // Reject empty, hidden, or weird characters.
        guard !filename.isEmpty else {
            throw WriteError.unsafeFilename("<empty>")
        }
        // Reject if contains path separators or traversal.
        let forbidden: [String] = ["/", "\\", "..", "%2f", "%2F", "%5c", "%5C", "%2e%2e", "%2E%2E"]
        let lower = filename.lowercased()
        for token in forbidden {
            if lower.contains(token.lowercased()) {
                throw WriteError.unsafeFilename(filename)
            }
        }
        // Reject absolute paths (starts с `/` already caught by separator check, но
        // double-check для null prefix bytes).
        if filename.hasPrefix(".") || filename.contains("\0") {
            throw WriteError.unsafeFilename(filename)
        }
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
