import Foundation
import os.signpost
import Crypto  // T-A1: SHA256 verification of fetched SRS bytes

// MARK: - Notification name contract

extension Notification.Name {
    /// Posted на `NotificationCenter.default` после successful `performBackgroundRefresh`.
    ///
    /// **Object:** `RulesSnapshot?` — текущий snapshot после refresh (или nil если
    /// `currentSnapshot()` ещё не material — race window отсутствует, post bottoms
    /// после atomic write + state update).
    ///
    /// **Posted on:** MainActor через `Task { @MainActor in ... }` для convenience
    /// SwiftUI consumers (Phase 6 MainScreenViewModel.swift pattern — `queue: nil` +
    /// async hop). Consumer не обязан быть MainActor, observer receive normally.
    ///
    /// **Stable identity:** `app.bbtb.client.rulesEngineDidUpdate` — same naming
    /// convention как другие Phase 6 notifications.
    public static let bbtbRulesEngineDidUpdate = Notification.Name("app.bbtb.client.rulesEngineDidUpdate")
}

// MARK: - Force-update outcome

/// Discriminated outcome от `forceUpdate()` — UI maps в toast message (RULES-10).
public enum ForceUpdateOutcome: Equatable, Sendable {
    /// Refresh succeeded; cache обновлён. `version` — newly cached version.
    case success(version: Int)
    /// Server returned `version <= cachedVersion`; cache untouched, нечего обновлять.
    case alreadyLatest(version: Int)
    /// Все mirrors недоступны (или DNS / SSRF / timeout).
    case networkFailure
    /// Signature verify failed на manifest либо на каком-либо `.srs`.
    case signatureFailure
    /// `total_size_bytes > 5 MB` либо individual payload too large.
    case payloadTooLarge
    /// Внутри 60-second cooldown окна (D-10) — refuse с remaining seconds.
    case cooldownActive(secondsRemaining: Int)
}

/// Internal classification причины refresh-failure для discriminated `ForceUpdateOutcome`
/// mapping. Не expose'ится publicly — coordinator state-private.
private enum RefreshFailureReason {
    case none           // success
    case network
    case signature
    case payloadSize
    case staleVersion   // version <= cached → .alreadyLatest
    case decode
    case formatVersion
    case fileError
}

// MARK: - PerfSignposter integration (DEC-06d-06)

/// Local subsystem-scoped Signposter mirroring AppFeatures `PerfSignposter` pattern.
///
/// Pattern source: `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift`.
/// RulesEngine — leaf package (AppFeatures consumes RulesEngine в W3), поэтому нельзя зависеть
/// от AppFeatures. Локальный enum даёт ту же signposter category (`performance`) + subsystem
/// (`app.bbtb.client`), что делает Instruments → Points of Interest unified view.
enum PerfSignposter {
    /// Shared client-side subsystem (mirrors AppFeatures `PerfSignposter.client`).
    static let client = OSSignposter(
        subsystem: "app.bbtb.client",
        category: "performance"
    )
}

// MARK: - Coordinator actor

/// Phase 8 Rules Engine orchestrator — owns full pipeline:
///
/// ```
/// ┌────────────────────────────────────────────────────────────────────┐
/// │ RulesEngineCoordinator (actor)                                     │
/// │                                                                    │
/// │  bootstrap()                  ─── first launch / cold start        │
/// │    └─→ BaselineRulesLoader → SRSCacheStore.write × 8 files         │
/// │                                                                    │
/// │  performBackgroundRefresh()   ─── BGAppRefreshTask / force-update  │
/// │    └─→ RulesFetcher (manifest) → RulesSigner.verify                │
/// │      └─→ Decode → version > cached? → total_size <= 5MB?           │
/// │        └─→ RulesFetcher × 3 (.srs) → RulesSigner × 3               │
/// │          └─→ SRSCacheStore.write × 8 (atomic)                      │
/// │            └─→ NotificationCenter.post .bbtbRulesEngineDidUpdate   │
/// │                                                                    │
/// │  forceUpdate()                ─── RULES-10 button                  │
/// │    └─→ 60s cooldown check (D-10)                                   │
/// │      └─→ performBackgroundRefresh → mapped ForceUpdateOutcome      │
/// │                                                                    │
/// │  currentSnapshot()            ─── RULES-09 viewer foundation       │
/// │    └─→ Materialize RulesSnapshot из cachedManifest CategoryBodies  │
/// └────────────────────────────────────────────────────────────────────┘
/// ```
///
/// **Thread-safety:** `actor` гарантирует mutual-exclusion. Re-entry guard (`isInFlight`)
/// предотвращает concurrent refresh, который мог бы race на cache write.
///
/// **Two-phase init:** Plan W2 не делает late-binding (нет circular deps в W2). W3
/// добавит `setSettingsViewModel(_:)` для SettingsViewModel observer pattern, если
/// потребуется. Текущий API — fully self-contained.
///
/// **Notification contract:** `Notification.Name.bbtbRulesEngineDidUpdate` posted
/// после успешного refresh, NOT после bootstrap (bootstrap = silent first-launch).
///
/// **D-12 cold-start defer:** `init` cheap (no I/O); `bootstrap()` invoked explicitly
/// от main app's `Task.detached` в `BBTB_iOSApp.swift` (W3). Никаких file scans / network
/// в init body.
public actor RulesEngineCoordinator {

    // MARK: - Static configuration

    /// Production mirror URLs — заменяются на real VPS URLs в W7 (08-08-PLAN.md).
    /// Текущие placeholder'ы корректно типизированы (HTTPS, non-loopback) для
    /// build-time compile checks.
    public static let productionMirrors: [URL] = [
        URL(string: "https://rules.bbtb.example/manifest.json")!,
        URL(string: "https://rules2.bbtb.example/manifest.json")!,
        URL(string: "https://rules3.bbtb.example/manifest.json")!,
    ]

    /// Force-update cooldown — 60 секунд per D-10. Не позволяет admin DoS-ить VPS
    /// repeated taps.
    private let cooldownDuration: TimeInterval = 60.0

    /// Per-file payload cap — 5 MB (Pitfall 3 — NE memory ceiling defense).
    private let maxBytesPerFile: Int = 5 * 1024 * 1024

    /// Max supported SRS format version — gate'им manifests где admin использовал
    /// sing-box CLI 1.14+ с SRS v5 (libbox 1.13.11 не парсит → silent fail).
    private let maxSrsFormatVersion: Int = 4

    // MARK: - Injected dependencies

    private let fetcher: RulesFetcherProtocol
    private let cache: SRSCacheStore
    private let clock: ClockProtocol
    private let mirrorURLs: [URL]
    private let signer: SignatureVerifierProtocol

    // MARK: - Mutable state (actor-isolated)

    /// In-memory copy последнего successfully decoded + verified manifest.
    /// nil = ни bootstrap ни refresh ещё не были success.
    private var cachedManifest: RulesManifest?

    /// Когда coordinator последний раз успешно завершил refresh (для `RulesSnapshot
    /// .lastFetchedAt`). nil после только-baseline bootstrap.
    private var lastFetchedAt: Date?

    /// Когда forceUpdate() был invoked последний раз (success или failure). Используется
    /// для cooldown gating.
    private var lastForceUpdateAt: Date?

    /// Re-entry guard — предотвращает concurrent performBackgroundRefresh от race-ить
    /// на SRSCacheStore writes. Set true entry → false defer на exit.
    private var isInFlight: Bool = false

    /// Last refresh failure classification — определяет mapping в `ForceUpdateOutcome`.
    private var lastFailureReason: RefreshFailureReason = .none

    // MARK: - Init

    /// - Parameter fetcher: injectable network layer; default = `DefaultRulesFetcher()`.
    /// - Parameter cache: injectable storage layer; default = `SRSCacheStore()`.
    /// - Parameter clock: injectable wallclock; default = `SystemClock()`.
    /// - Parameter mirrorURLs: ordered mirror list; default = `productionMirrors`.
    /// - Parameter signer: injectable signature verifier; default = `DefaultRulesSigner()`
    ///   (delegates к `RulesSigner.verify` под production placeholder key). Tests инжектят
    ///   stubs — см. doc-comment на `SignatureVerifierProtocol`.
    public init(
        fetcher: RulesFetcherProtocol = DefaultRulesFetcher(),
        cache: SRSCacheStore = SRSCacheStore(),
        clock: ClockProtocol = SystemClock(),
        mirrorURLs: [URL] = RulesEngineCoordinator.productionMirrors,
        signer: SignatureVerifierProtocol = DefaultRulesSigner()
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.clock = clock
        self.mirrorURLs = mirrorURLs
        self.signer = signer
    }

    // MARK: - Public API: bootstrap

    /// Copy baseline manifest + 3 .srs + sidecar .sig files в App Group cache **iff cache empty**.
    ///
    /// **Idempotent:** если `baseline-rules-manifest.json` уже existing в cache (signal "уже
    /// bootstrapped" или "уже refresh'ed"), bootstrap не overwrite. Это сохраняет real
    /// server-fetched updates от случайного отката к baseline.
    ///
    /// **D-12 cold-start defer:** safe для вызова из `Task.detached(priority: .utility)`
    /// — никаких MainActor блокировок, синхронный I/O ограничен 8 file writes.
    ///
    /// **Trust path:** baseline = embedded resources, integrity guaranteed by Apple code
    /// signing (T-08-W2-08 disposition `accept`). signature verify НЕ применяется к baseline
    /// — этот шаг pure delivery from Bundle.module → App Group.
    public func bootstrap() async {
        // Check existence first — idempotent.
        let alreadyBootstrapped = await cache.exists(filename: "baseline-rules-manifest.json")
        if alreadyBootstrapped {
            RulesEngineLogger.coordinator.notice(
                "RulesEngineCoordinator.bootstrap: cache already populated, no-op"
            )
            // Восстанавливаем cachedManifest из disk на cold-start (если bootstrap уже
            // случался в прошлой сессии). Без этого currentSnapshot() возвращает nil
            // до первого refresh.
            if cachedManifest == nil, let data = await cache.read(filename: "baseline-rules-manifest.json") {
                do {
                    cachedManifest = try JSONDecoder().decode(RulesManifest.self, from: data)
                } catch {
                    RulesEngineLogger.coordinator.error(
                        "RulesEngineCoordinator.bootstrap: failed to decode cached manifest на recovery: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return
        }

        RulesEngineLogger.coordinator.notice(
            "RulesEngineCoordinator.bootstrap: hydrating App Group cache из embedded baseline"
        )

        do {
            // 1. Manifest + sig
            let (manifestData, manifestSig) = try BaselineRulesLoader.loadManifest()
            try await cache.write(manifestData, filename: "baseline-rules-manifest.json")
            try await cache.write(manifestSig, filename: "baseline-rules-manifest.json.sig")

            // 2. 3 × .srs + .sig
            for category in [RulesManifest.Category.block, .never, .always] {
                let (srsData, sigData) = try BaselineRulesLoader.loadSRS(category: category)
                let basename = baselineFilename(for: category)
                try await cache.write(srsData, filename: basename)
                try await cache.write(sigData, filename: "\(basename).sig")
            }

            // 3. Materialize cached manifest в memory.
            cachedManifest = try JSONDecoder().decode(RulesManifest.self, from: manifestData)
            RulesEngineLogger.coordinator.notice(
                "RulesEngineCoordinator.bootstrap: baseline hydrated, version=\(self.cachedManifest?.version ?? -1, privacy: .public)"
            )
        } catch {
            RulesEngineLogger.coordinator.error(
                "RulesEngineCoordinator.bootstrap failed: \(error.localizedDescription, privacy: .public)"
            )
            // Fail-soft: bootstrap could fail если Bundle.module corrupted (build bug).
            // Тогда currentSnapshot() возвращает nil; UI отображает "rules not loaded" state.
        }
    }

    // MARK: - Public API: background refresh

    /// Полный pipeline fetch → verify → atomic-write → notify.
    ///
    /// - Returns: `true` iff cache was updated (new version applied). `false` для всех
    ///   failure paths AND для "no update available" (version <= cached).
    ///
    /// **Re-entry guard:** if call в-flight уже, return false immediately (DoS protection).
    ///
    /// **Atomicity:** sequence: srs files first, then their sigs, then manifest, then
    /// manifest.sig last. Reasoning: если interrupted mid-sequence, reader (sing-box) сначала
    /// видит новые .srs (old manifest references old hashes — mismatch) но libbox-side
    /// verify rejects mismatch (defense-in-depth). Manifest update last fences full
    /// transaction.
    public func performBackgroundRefresh() async -> Bool {
        guard !isInFlight else {
            RulesEngineLogger.coordinator.notice(
                "RulesEngineCoordinator.performBackgroundRefresh: rejected (in-flight)"
            )
            return false
        }
        isInFlight = true
        defer { isInFlight = false }

        // PerfSignposter span — DEC-06d-06.
        let signpostID = PerfSignposter.client.makeSignpostID()
        let state = PerfSignposter.client.beginInterval("RulesRefresh", id: signpostID)
        defer { PerfSignposter.client.endInterval("RulesRefresh", state) }

        lastFailureReason = .none

        // ─── Step 1: fetch manifest + sig ──────────────────────────────────────
        let manifestData: Data
        let manifestSig: Data
        do {
            let manifestRes = try await fetcher.fetchWithFailover(
                urls: mirrorURLs, maxBytes: maxBytesPerFile
            )
            let sigURLs = mirrorURLs.map { $0.appendingPathExtension("sig") }
            let sigRes = try await fetcher.fetchWithFailover(urls: sigURLs, maxBytes: 1024)
            manifestData = manifestRes.body
            manifestSig = sigRes.body
        } catch let err as RulesFetcher.FetchError {
            lastFailureReason = isPayloadError(err) ? .payloadSize : .network
            RulesEngineLogger.coordinator.warning(
                "RulesEngineCoordinator.performBackgroundRefresh: fetch failed: \(err.localizedDescription, privacy: .public)"
            )
            return false
        } catch {
            lastFailureReason = .network
            RulesEngineLogger.coordinator.warning(
                "RulesEngineCoordinator.performBackgroundRefresh: unexpected fetch error: \(String(describing: error), privacy: .public)"
            )
            return false
        }

        // ─── Step 2: verify manifest signature ─────────────────────────────────
        guard signer.verify(message: manifestData, signature: manifestSig) else {
            lastFailureReason = .signature
            RulesEngineLogger.coordinator.error(
                "RulesEngineCoordinator.performBackgroundRefresh: manifest signature verify FAILED"
            )
            return false
        }

        // ─── Step 3: decode manifest ───────────────────────────────────────────
        let newManifest: RulesManifest
        do {
            newManifest = try JSONDecoder().decode(RulesManifest.self, from: manifestData)
        } catch {
            lastFailureReason = .decode
            RulesEngineLogger.coordinator.error(
                "RulesEngineCoordinator.performBackgroundRefresh: manifest decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        // ─── Step 4: srs_format_version sanity (Pitfall 1) ──────────────────────
        guard newManifest.srsFormatVersion <= maxSrsFormatVersion else {
            lastFailureReason = .formatVersion
            RulesEngineLogger.coordinator.error(
                "RulesEngineCoordinator.performBackgroundRefresh: srs_format_version=\(newManifest.srsFormatVersion, privacy: .public) > max \(self.maxSrsFormatVersion, privacy: .public)"
            )
            return false
        }

        // ─── Step 5: monotonic version (replay protection — T-08-W2-02) ────────
        let cachedVersion = cachedManifest?.version ?? 0
        guard newManifest.version > cachedVersion else {
            lastFailureReason = .staleVersion
            RulesEngineLogger.coordinator.notice(
                "RulesEngineCoordinator.performBackgroundRefresh: server version=\(newManifest.version, privacy: .public) <= cached \(cachedVersion, privacy: .public) — no update needed"
            )
            return false
        }

        // ─── Step 6: total_size cap (Pitfall 3) ────────────────────────────────
        guard newManifest.totalSizeBytes <= maxBytesPerFile else {
            lastFailureReason = .payloadSize
            RulesEngineLogger.coordinator.error(
                "RulesEngineCoordinator.performBackgroundRefresh: total_size_bytes=\(newManifest.totalSizeBytes, privacy: .public) > 5MB cap"
            )
            return false
        }

        // ─── Step 6b: T-A1 (closes A5-002 / C5-004 CRITICAL) — validate ALL
        //              manifest-supplied filenames as bare BEFORE constructing URLs
        //              или filesystem writes.
        //              `entry.name` / `entry.sigPath` come from server-signed manifest.
        //              Without validation, a malicious or buggy server could write
        //              outside Library/Caches/rules через `../` или absolute paths,
        //              poisoning other App Group caches.
        for entry in newManifest.files {
            if hasPathTraversalRisk(entry.name) || hasPathTraversalRisk(entry.sigPath) {
                lastFailureReason = .decode  // closest existing — manifest field validation
                RulesEngineLogger.coordinator.error(
                    "RulesEngineCoordinator.performBackgroundRefresh: rejected unsafe filename in manifest: name=\(entry.name, privacy: .public) sigPath=\(entry.sigPath, privacy: .public)"
                )
                return false
            }
        }

        // ─── Step 7: fetch + verify each .srs file ─────────────────────────────
        var verifiedSrsPayloads: [(category: RulesManifest.Category, srs: Data, sig: Data, basename: String)] = []
        for entry in newManifest.files {
            // Build per-file URLs by appending entry.name to each mirror's directory.
            let srsURLs: [URL] = mirrorURLs.compactMap { manifestURL -> URL? in
                let base = manifestURL.deletingLastPathComponent()
                return base.appendingPathComponent(entry.name)
            }
            let sigURLs: [URL] = mirrorURLs.compactMap { manifestURL -> URL? in
                let base = manifestURL.deletingLastPathComponent()
                return base.appendingPathComponent(entry.sigPath)
            }

            do {
                let srsRes = try await fetcher.fetchWithFailover(urls: srsURLs, maxBytes: maxBytesPerFile)
                let sigRes = try await fetcher.fetchWithFailover(urls: sigURLs, maxBytes: 1024)
                guard signer.verify(message: srsRes.body, signature: sigRes.body) else {
                    lastFailureReason = .signature
                    RulesEngineLogger.coordinator.error(
                        "RulesEngineCoordinator.performBackgroundRefresh: .srs signature verify FAILED for \(entry.name, privacy: .public)"
                    )
                    return false
                }
                // ─── T-A1 (closes A5-003 / C5-002 CRITICAL): SHA-256 verification ───
                // Manifest declares `entry.sha256` для каждого SRS файла. Signature
                // alone не bind SRS bytes to THIS manifest version — стара valid signed
                // SRS could be replayed under a new manifest. Hash check + signature
                // together bind: this SRS bytes match what manifest claims.
                let expectedHex = entry.sha256
                if !expectedHex.isEmpty {
                    let actualHex = sha256Hex(srsRes.body)
                    guard actualHex.lowercased() == expectedHex.lowercased() else {
                        lastFailureReason = .signature
                        RulesEngineLogger.coordinator.error(
                            "RulesEngineCoordinator.performBackgroundRefresh: .srs sha256 MISMATCH for \(entry.name, privacy: .public) (expected=\(expectedHex.prefix(16), privacy: .public)… actual=\(actualHex.prefix(16), privacy: .public)…)"
                        )
                        return false
                    }
                }
                verifiedSrsPayloads.append((entry.category, srsRes.body, sigRes.body, entry.name))
            } catch let err as RulesFetcher.FetchError {
                lastFailureReason = isPayloadError(err) ? .payloadSize : .network
                RulesEngineLogger.coordinator.error(
                    "RulesEngineCoordinator.performBackgroundRefresh: .srs fetch failed for \(entry.name, privacy: .public): \(err.localizedDescription, privacy: .public)"
                )
                return false
            } catch {
                lastFailureReason = .network
                return false
            }
        }

        // ─── Step 8: group-atomic write (T-A1 / A5-005 / C5-005 HIGH) ─────────
        // Two-phase commit via SRSCacheStore.commitTransaction: всё писано к
        // staging suffix `.bbtb-staging`, потом atomic-rename каждый к final.
        // Improvement over old per-file Data.write(.atomic) loop:
        //   - if any staging write fails → old final files untouched (caller gets
        //     consistent old cache, not partial-new).
        //   - rename phase: each POSIX rename атомарен per file; group rename
        //     loop completes в milliseconds (best-effort group atomicity; true
        //     versioned-dir swap deferred к v1.1).
        // Filenames pre-validated в Step 6b (path traversal guard).
        do {
            var batch: [(data: Data, filename: String)] = []
            batch.reserveCapacity(2 + verifiedSrsPayloads.count * 2)
            for payload in verifiedSrsPayloads {
                batch.append((payload.srs, payload.basename))
                batch.append((payload.sig, "\(payload.basename).sig"))
            }
            batch.append((manifestData, "baseline-rules-manifest.json"))
            batch.append((manifestSig, "baseline-rules-manifest.json.sig"))
            try await cache.commitTransaction(batch)
        } catch {
            lastFailureReason = .fileError
            RulesEngineLogger.coordinator.error(
                "RulesEngineCoordinator.performBackgroundRefresh: write failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        // ─── Step 9: update in-memory state ────────────────────────────────────
        cachedManifest = newManifest
        lastFetchedAt = clock.now()
        RulesEngineLogger.coordinator.notice(
            "RulesEngineCoordinator.performBackgroundRefresh: success, version=\(newManifest.version, privacy: .public)"
        )

        // ─── Step 10: post notification (MainActor hop) ────────────────────────
        let snapshot = materializeSnapshot(from: newManifest)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .bbtbRulesEngineDidUpdate,
                object: snapshot
            )
        }

        return true
    }

    // MARK: - Public API: force update

    /// User-triggered refresh (RULES-10 button). Enforces 60-second cooldown.
    public func forceUpdate() async -> ForceUpdateOutcome {
        // Cooldown gate — D-10.
        if let last = lastForceUpdateAt {
            let elapsed = clock.now().timeIntervalSince(last)
            if elapsed < cooldownDuration {
                let remaining = Int(ceil(cooldownDuration - elapsed))
                RulesEngineLogger.coordinator.notice(
                    "RulesEngineCoordinator.forceUpdate: cooldown active, \(remaining, privacy: .public)s remaining"
                )
                return .cooldownActive(secondsRemaining: remaining)
            }
        }

        // Record attempt time BEFORE pipeline — even failed force-update counts toward cooldown.
        lastForceUpdateAt = clock.now()

        let updated = await performBackgroundRefresh()

        if updated {
            return .success(version: cachedManifest?.version ?? 0)
        }

        // Map last failure reason → outcome.
        switch lastFailureReason {
        case .staleVersion:
            return .alreadyLatest(version: cachedManifest?.version ?? 0)
        case .network, .none:
            return .networkFailure
        case .signature:
            return .signatureFailure
        case .payloadSize:
            return .payloadTooLarge
        case .decode, .formatVersion, .fileError:
            // Schema/format/IO errors fold в networkFailure для UI simplicity —
            // detailed logs available в Console.app.
            return .networkFailure
        }
    }

    // MARK: - Public API: snapshot

    /// Materialize `RulesSnapshot` из in-memory `cachedManifest`.
    ///
    /// Foundation для RULES-09 read-only viewer (Phase 8 W3). Без materialization
    /// SettingsViewModel.rulesSnapshot был бы permanently empty arrays.
    ///
    /// - Returns: snapshot или nil iff `cachedManifest` ещё не set (bootstrap не ran).
    public func currentSnapshot() -> RulesSnapshot? {
        guard let manifest = cachedManifest else { return nil }
        return materializeSnapshot(from: manifest)
    }

    // MARK: - Helpers

    /// Map manifest CategoryBodies → snapshot CategoryEntries (W2.3 critical materialization).
    private func materializeSnapshot(from manifest: RulesManifest) -> RulesSnapshot {
        return RulesSnapshot(
            version: manifest.version,
            lastFetchedAt: lastFetchedAt,
            block: entries(from: manifest.blockCompletely),
            never: entries(from: manifest.neverThroughVpn),
            always: entries(from: manifest.alwaysThroughVpn),
            minAppVersion: manifest.minAppVersion
        )
    }

    /// `CategoryBodies?` → `CategoryEntries` (nil → empty).
    private func entries(from bodies: RulesManifest.CategoryBodies?) -> CategoryEntries {
        return CategoryEntries(
            domains: bodies?.domains ?? [],
            ipCidrs: bodies?.ipCidrs ?? [],
            countries: bodies?.countries ?? []
        )
    }

    /// Baseline filename mapping (sync с `BaselineRulesLoader` and manifest's `files[].name`).
    private func baselineFilename(for category: RulesManifest.Category) -> String {
        switch category {
        case .block: return "bbtb-baseline-block.srs"
        case .never: return "bbtb-baseline-never.srs"
        case .always: return "bbtb-baseline-always.srs"
        }
    }

    /// Discriminate payload-related fetch errors → `RefreshFailureReason.payloadSize`.
    private func isPayloadError(_ err: RulesFetcher.FetchError) -> Bool {
        switch err {
        case .payloadTooLarge: return true
        case .allMirrorsFailed(let inner):
            return inner.contains(where: { if case .payloadTooLarge = $0 { return true } else { return false } })
        default: return false
        }
    }

    // MARK: - T-A1 defence-in-depth helpers

    /// T-A1 (closes A5-002 / C5-004 CRITICAL) — reject filenames с path-traversal
    /// patterns. Manifest-supplied `entry.name` / `entry.sigPath` proходят через эту
    /// проверку BEFORE URL construction и filesystem write.
    ///
    /// Rejected patterns:
    /// - Empty или whitespace-only
    /// - Path separators (`/`, `\`)
    /// - Parent-directory references (`..`, percent-encoded `%2e%2e`)
    /// - URL-encoded slashes (`%2f`, `%5c`)
    /// - Hidden prefix (`.something`)
    /// - Null byte (`\0`)
    private func hasPathTraversalRisk(_ filename: String) -> Bool {
        guard !filename.isEmpty else { return true }
        let trimmed = filename.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let forbidden: [String] = ["/", "\\", "..", "%2f", "%2F", "%5c", "%5C", "%2e%2e", "%2E%2E"]
        let lower = filename.lowercased()
        for token in forbidden {
            if lower.contains(token.lowercased()) { return true }
        }
        if filename.hasPrefix(".") || filename.contains("\0") { return true }
        return false
    }

    /// T-A1 (closes A5-003 / C5-002 CRITICAL) — compute SHA-256 of fetched SRS bytes
    /// и сравнить с `entry.sha256` из подписанного manifest. Hash check + signature
    /// together bind THIS bytes к THIS manifest version (without hash, valid signed
    /// SRS from старой version could be replayed under new manifest).
    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
