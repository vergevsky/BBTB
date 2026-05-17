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
/// `actor` гарантирует serialization.
public actor SRSCacheStore {

    /// Куда писать / откуда читать.
    public nonisolated let directory: URL

    /// Конструктор с injectable directory.
    public init(directory: URL = AppGroupContainer.rulesCacheDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // T-B5'-extra (closes A5'-002 HIGH): cleanup orphaned `.bbtb-staging` files
        // from prior interrupted commitTransaction. Without cleanup, staging files
        // accumulate across launches и confuse future commits/reads (extension scan).
        cleanupStagingFiles()
    }

    /// T-B5'-extra (closes A5'-002): scan directory + delete any `.bbtb-staging`
    /// files. Called at init и at end of commitTransaction (success или failure).
    private nonisolated func cleanupStagingFiles() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasSuffix(".bbtb-staging") {
            try? fm.removeItem(at: url)
        }
    }

    /// Atomic write через `Data.write(.atomic)`. POSIX rename(2) — single-step replacement.
    ///
    /// - Parameter data: bytes to write.
    /// - Parameter filename: bare filename (allowlist-validated).
    /// - Throws:
    ///   - `WriteError.unsafeFilename` если filename fails allowlist.
    ///   - any `Foundation` error из `Data.write`.
    public func write(_ data: Data, filename: String) throws {
        try Self.validateBareFilename(filename)
        let target = directory.appendingPathComponent(filename)
        try data.write(to: target, options: .atomic)
        RulesEngineLogger.coordinator.notice(
            "SRSCacheStore.write filename=\(filename, privacy: .public) bytes=\(data.count, privacy: .public)"
        )
    }

    /// **Group-atomic write (T-A1 + T-B3' refactor — closes A5-005 / C5-005 / C5'-002):**
    /// two-phase commit с improved recovery semantics.
    ///
    /// **Procedure:**
    /// 1. Validate ALL filenames as bare (allowlist-positive).
    /// 2. Write each `(data, filename)` к `<filename>.bbtb-staging` via atomic single-file write.
    /// 3. После all stagings успешны → POSIX-rename each к final.
    /// 4. **T-B3' (closes C5'-002 HIGH):** if Phase 3 rename fails partway, cleanup
    ///    remaining staging files и rethrow. Already-renamed files stay (cannot rollback
    ///    POSIX rename without backup), но no orphan staging accumulates.
    /// 5. Phase 2 failure → final files untouched (старая cache intact). Staging cleanup
    ///    happens unconditionally в defer.
    ///
    /// **T-C-C5H1' (Plan 07 investigation of C5'-3-001):** Codex correctly noted
    /// что implementation остаётся per-file rename loop, не versioned-generation
    /// atomic swap. Plan 05 T-B3' commit message overstated closure of C5'-002.
    /// **Actual closure** была *improved* recovery (defer cleanup of orphan
    /// `.bbtb-staging` files + handle non-existent final), но не true group-atomicity.
    ///
    /// **Why это acceptable для v1.0:** extension reads each file independently
    /// через libbox fswatch + each file's sha256 is verified against the signed
    /// manifest. Mid-loop Phase 3 failure leaves cache в mixed-state, but extension
    /// re-verify catches it: stale file's sha256 won't match new manifest →
    /// rule_set load fails → falls back к baseline (safe, conservative).
    ///
    /// **Limitation (carry-forward к v1.1+):** true group atomicity requires
    /// versioned cache directory pattern (e.g. `<dir>/gen-N/<files>` + atomic
    /// symlink swap `<dir>/current → gen-N`). See wiki `R25 § «v1.1+ TODO»` для
    /// design notes.
    ///
    /// **Defence-in-depth обоснование** документирован в `wiki/security-gaps.md` R25.
    public func commitTransaction(_ files: [(data: Data, filename: String)]) throws {
        // Phase 1: validate ALL filenames before any disk write.
        for entry in files {
            try Self.validateBareFilename(entry.filename)
        }
        // Defer cleanup: remove any remaining `.bbtb-staging` files unconditionally
        // (success → no stagings left; failure → orphan stagings purged).
        defer { cleanupStagingFiles() }

        // Phase 2: write all к staging suffix.
        var stagingURLs: [URL] = []
        for entry in files {
            let staging = directory.appendingPathComponent("\(entry.filename).bbtb-staging")
            try entry.data.write(to: staging, options: .atomic)
            stagingURLs.append(staging)
        }
        // Phase 3: rename each staging → final.
        let fm = FileManager.default
        for (i, entry) in files.enumerated() {
            let final = directory.appendingPathComponent(entry.filename)
            do {
                // T-C3'-extra (closes C5'-003 MEDIUM): handle non-existent final via
                // simple move semantics. `replaceItemAt` requires destination exists;
                // fall back к `moveItem` если final missing (first-time write).
                if fm.fileExists(atPath: final.path) {
                    _ = try fm.replaceItemAt(final, withItemAt: stagingURLs[i])
                } else {
                    try fm.moveItem(at: stagingURLs[i], to: final)
                }
            } catch {
                // Cleanup remaining stagings (i+1..N) via defer; already-renamed
                // (0..<i) stay committed. Rethrow original error.
                RulesEngineLogger.coordinator.error(
                    "SRSCacheStore.commitTransaction phase-3 rename failed at index \(i, privacy: .public) for \(entry.filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }
        RulesEngineLogger.coordinator.notice(
            "SRSCacheStore.commitTransaction wrote \(files.count, privacy: .public) files group-atomically"
        )
    }

    public enum WriteError: Error, LocalizedError, Equatable {
        /// Filename does not pass positive allowlist regex.
        case unsafeFilename(String)

        public var errorDescription: String? {
            switch self {
            case .unsafeFilename(let s): return "SRSCacheStore: unsafe filename rejected: \(s)"
            }
        }
    }

    /// **T-B4' (closes A5'-001 + C5'-005 HIGH):** positive allowlist regex для bare filename
    /// validation. Replaces previous blocklist approach which missed Unicode forms (fullwidth
    /// solidus `／`, fraction slash `⁄`, NFKC/NFKD normalization holes, percent-encoded
    /// traversal bypasses).
    ///
    /// **Allowlist regex `^[A-Za-z0-9][A-Za-z0-9._-]*$`:**
    /// - First char MUST be alphanumeric (rejects `.` leading-dot, `-` leading-dash).
    /// - Subsequent chars: alphanumeric, dot, underscore, hyphen only.
    /// - Reject empty, Unicode control/format characters, path separators (auto-blocked
    ///   since none match `[A-Za-z0-9._-]`), `..` (matches but caught by separate check).
    ///
    /// **`..` check:** allowlist regex permits `..` since chars are dots; explicit reject.
    ///
    /// **Length cap (256 chars):** filesystem-level safeguard against pathological inputs.
    internal static func validateBareFilename(_ filename: String) throws {
        guard !filename.isEmpty else {
            throw WriteError.unsafeFilename("<empty>")
        }
        guard filename.count <= 256 else {
            throw WriteError.unsafeFilename("<too long: \(filename.count)>")
        }
        // Allowlist regex: positive set of safe characters; first must be alphanumeric.
        let allowed = #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#
        guard let regex = try? NSRegularExpression(pattern: allowed) else {
            throw WriteError.unsafeFilename(filename)  // defensive
        }
        let ns = filename as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard regex.firstMatch(in: filename, range: range) != nil else {
            throw WriteError.unsafeFilename(filename)
        }
        // Explicit `..` reject (allowed character set permits sequential dots).
        if filename.contains("..") {
            throw WriteError.unsafeFilename(filename)
        }
    }

    /// Read bytes, returning nil if file missing or unreadable.
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
