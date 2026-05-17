import XCTest
import Crypto  // T-A1: SHA256 для test fixture hash computation
@testable import RulesEngine

/// End-to-end pipeline tests для `RulesEngineCoordinator`.
///
/// **Test fixtures:**
/// - `FakeFetcher` — actor-isolated in-memory response map keyed by URL string;
///   per-URL routing (для разных response между manifest/sig/srs).
/// - `FixedClock` — mutable `now` Date; advance via `setNow(_:)` для cooldown tests.
/// - `AlwaysValidVerifier` / `AlwaysInvalidVerifier` — stub signature verifiers; success-path
///   tests инжектят valid (по умолчанию `DefaultRulesSigner` всегда false под placeholder key).
/// - Каждый test использует fresh tmp directory + UUID + tearDown снос.
final class RulesEngineCoordinatorTests: XCTestCase {

    var tmpDir: URL!
    var store: SRSCacheStore!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules-coord-test-\(UUID().uuidString)", isDirectory: true)
        store = SRSCacheStore(directory: tmpDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        tmpDir = nil
        store = nil
        try await super.tearDown()
    }

    // MARK: - Test 1 — bootstrap copies baseline when cache empty

    func test_bootstrap_copiesBaselineWhenCacheEmpty() async throws {
        let coord = RulesEngineCoordinator(
            fetcher: FakeFetcher(),
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [URL(string: "https://example.com/manifest.json")!],
            signer: AlwaysValidVerifier()
        )

        let manifestExistsBefore = await store.exists(filename: "baseline-rules-manifest.json")
        XCTAssertFalse(manifestExistsBefore, "Sanity: cache пуст перед bootstrap")

        await coord.bootstrap()

        let manifestExistsAfter = await store.exists(filename: "baseline-rules-manifest.json")
        XCTAssertTrue(manifestExistsAfter, "После bootstrap baseline manifest скопирован")
        let blockSrsExists = await store.exists(filename: "bbtb-baseline-block.srs")
        let neverSrsExists = await store.exists(filename: "bbtb-baseline-never.srs")
        let alwaysSrsExists = await store.exists(filename: "bbtb-baseline-always.srs")
        XCTAssertTrue(blockSrsExists, "block.srs скопирован")
        XCTAssertTrue(neverSrsExists, "never.srs скопирован")
        XCTAssertTrue(alwaysSrsExists, "always.srs скопирован")

        // Snapshot должен быть materialized после bootstrap.
        let snapshot = await coord.currentSnapshot()
        XCTAssertNotNil(snapshot, "После bootstrap currentSnapshot != nil")
        XCTAssertEqual(snapshot?.version, 0, "Baseline version=0")
    }

    // MARK: - Test 2 — bootstrap idempotent (не overwrites existing cache)

    func test_bootstrap_idempotent_doesNotOverwriteExistingCache() async throws {
        let coord = RulesEngineCoordinator(
            fetcher: FakeFetcher(),
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [URL(string: "https://example.com/manifest.json")!],
            signer: AlwaysValidVerifier()
        )

        await coord.bootstrap()
        let mtime1 = await store.mtime(filename: "baseline-rules-manifest.json")
        XCTAssertNotNil(mtime1)

        // Add небольшую паузу + bootstrap снова — mtime не должен измениться.
        try await Task.sleep(nanoseconds: 50_000_000)  // 50 ms

        await coord.bootstrap()
        let mtime2 = await store.mtime(filename: "baseline-rules-manifest.json")
        XCTAssertEqual(mtime1, mtime2, "Idempotent bootstrap не перезаписывает existing файл")
    }

    // MARK: - Test 3 — successful refresh writes all files

    func test_performBackgroundRefresh_success_writesAllFiles() async throws {
        let fixtures = TestManifest.signed(version: 5)
        let manifestURL = URL(string: "https://example.com/manifest.json")!

        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            let srsURL = URL(string: "https://example.com/\(entry.name)")!
            let sigURL = URL(string: "https://example.com/\(entry.sigPath)")!
            await fakeFetcher.set(url: srsURL, response: entry.srsBytes)
            await fakeFetcher.set(url: sigURL, response: entry.sigBytes)
        }

        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [manifestURL],
            signer: AlwaysValidVerifier()
        )
        await coord.bootstrap()

        let didUpdate = await coord.performBackgroundRefresh()
        XCTAssertTrue(didUpdate, "Refresh должен succeed")

        let manifestData = await store.read(filename: "baseline-rules-manifest.json")
        XCTAssertEqual(manifestData, fixtures.manifestBody, "Manifest записан с server bytes")

        for entry in fixtures.entries {
            let srsData = await store.read(filename: entry.name)
            XCTAssertEqual(srsData, entry.srsBytes, ".srs payload записан для \(entry.name)")
            let sigData = await store.read(filename: entry.sigPath)
            XCTAssertEqual(sigData, entry.sigBytes, ".sig записан для \(entry.sigPath)")
        }

        let snapshot = await coord.currentSnapshot()
        XCTAssertEqual(snapshot?.version, 5, "Snapshot reflects new version 5")
    }

    // MARK: - Test 4 — tampered signature keeps cache + returns false

    func test_performBackgroundRefresh_tamperedSig_keepsCache_returnsFalse() async throws {
        let fixtures = TestManifest.signed(version: 5)
        let manifestURL = URL(string: "https://example.com/manifest.json")!

        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)

        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [manifestURL],
            signer: AlwaysInvalidVerifier()  // signature всегда отвергается
        )
        await coord.bootstrap()

        let baselineMtime = await store.mtime(filename: "baseline-rules-manifest.json")
        try await Task.sleep(nanoseconds: 50_000_000)  // ensure new write would change mtime

        let didUpdate = await coord.performBackgroundRefresh()
        XCTAssertFalse(didUpdate, "Tampered sig → returns false")

        let postMtime = await store.mtime(filename: "baseline-rules-manifest.json")
        XCTAssertEqual(baselineMtime, postMtime, "Cache mtime unchanged — manifest не перезаписан")

        let snapshot = await coord.currentSnapshot()
        XCTAssertEqual(snapshot?.version, 0, "Snapshot still baseline version=0")
    }

    // MARK: - Test 5 — network failure keeps cache + returns false

    func test_performBackgroundRefresh_networkFailure_keepsCache_returnsFalse() async throws {
        let fakeFetcher = FakeFetcher()
        // No responses set → fake throws .allMirrorsFailed на любой fetch.

        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [URL(string: "https://example.com/manifest.json")!],
            signer: AlwaysValidVerifier()
        )
        await coord.bootstrap()

        let baselineMtime = await store.mtime(filename: "baseline-rules-manifest.json")
        try await Task.sleep(nanoseconds: 50_000_000)

        let didUpdate = await coord.performBackgroundRefresh()
        XCTAssertFalse(didUpdate, "Network failure → false")

        let postMtime = await store.mtime(filename: "baseline-rules-manifest.json")
        XCTAssertEqual(baselineMtime, postMtime, "Cache untouched при network failure")
    }

    // MARK: - Test 6 — server version <= cached → no update

    func test_performBackgroundRefresh_versionNotNewer_returnsFalse() async throws {
        // Server returns version 0 (= baseline version → not >).
        let fixtures = TestManifest.signed(version: 0)
        let manifestURL = URL(string: "https://example.com/manifest.json")!

        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)

        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [manifestURL],
            signer: AlwaysValidVerifier()
        )
        await coord.bootstrap()

        let didUpdate = await coord.performBackgroundRefresh()
        XCTAssertFalse(didUpdate, "version=0 не > cached 0 → returns false")
    }

    // MARK: - Test 7 — forceUpdate cooldown active inside 60s window

    func test_forceUpdate_withinCooldown_returnsCooldownActive() async throws {
        let fakeFetcher = FakeFetcher()  // empty → network failure path

        let initialDate = Date()
        let clock = FixedClock(now: initialDate)
        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: clock,
            mirrorURLs: [URL(string: "https://example.com/manifest.json")!],
            signer: AlwaysValidVerifier()
        )

        // First call — записывает lastForceUpdateAt в clock state, returns .networkFailure.
        let first = await coord.forceUpdate()
        if case .cooldownActive = first {
            XCTFail("First forceUpdate не должен hit cooldown")
        }

        // Advance clock на 30s — внутри 60s окна.
        clock.setNow(initialDate.addingTimeInterval(30))

        let second = await coord.forceUpdate()
        switch second {
        case .cooldownActive(let remaining):
            XCTAssertGreaterThanOrEqual(remaining, 25, "remaining должен быть ~30s ± rounding")
            XCTAssertLessThanOrEqual(remaining, 35)
        default:
            XCTFail("Second forceUpdate в cooldown окне должен вернуть .cooldownActive, got \(second)")
        }
    }

    // MARK: - Test 8 — forceUpdate after cooldown succeeds

    func test_forceUpdate_afterCooldown_returnsSuccess() async throws {
        let fixtures = TestManifest.signed(version: 5)
        let manifestURL = URL(string: "https://example.com/manifest.json")!

        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            let srsURL = URL(string: "https://example.com/\(entry.name)")!
            let sigURL = URL(string: "https://example.com/\(entry.sigPath)")!
            await fakeFetcher.set(url: srsURL, response: entry.srsBytes)
            await fakeFetcher.set(url: sigURL, response: entry.sigBytes)
        }

        let initialDate = Date()
        let clock = FixedClock(now: initialDate)
        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: clock,
            mirrorURLs: [manifestURL],
            signer: AlwaysValidVerifier()
        )
        await coord.bootstrap()

        // First force-update — should succeed.
        let first = await coord.forceUpdate()
        if case .success(let v) = first {
            XCTAssertEqual(v, 5)
        } else {
            XCTFail("First forceUpdate должен .success(5), got \(first)")
        }

        // Advance clock +61s — cooldown expired.
        clock.setNow(initialDate.addingTimeInterval(61))

        // For second call we need fresh successful refresh; but server still returns v=5
        // → cached=5, server=5 → .alreadyLatest.
        let second = await coord.forceUpdate()
        if case .alreadyLatest(let v) = second {
            XCTAssertEqual(v, 5, "После cooldown server still 5 = cached → .alreadyLatest(5)")
        } else {
            XCTFail("Second forceUpdate должен .alreadyLatest(5), got \(second)")
        }
    }

    // MARK: - Test 9 — notification posted after successful refresh

    func test_notification_postedAfterSuccessfulRefresh() async throws {
        let fixtures = TestManifest.signed(version: 5)
        let manifestURL = URL(string: "https://example.com/manifest.json")!

        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            let srsURL = URL(string: "https://example.com/\(entry.name)")!
            let sigURL = URL(string: "https://example.com/\(entry.sigPath)")!
            await fakeFetcher.set(url: srsURL, response: entry.srsBytes)
            await fakeFetcher.set(url: sigURL, response: entry.sigBytes)
        }

        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [manifestURL],
            signer: AlwaysValidVerifier()
        )
        await coord.bootstrap()

        let exp = expectation(description: "notification received")
        let token = NotificationCenter.default.addObserver(
            forName: .bbtbRulesEngineDidUpdate, object: nil, queue: nil
        ) { notif in
            // object должен быть RulesSnapshot? (object кастуется к RulesSnapshot).
            XCTAssertNotNil(notif.object, "Notification.object — non-nil RulesSnapshot")
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let didUpdate = await coord.performBackgroundRefresh()
        XCTAssertTrue(didUpdate)
        await fulfillment(of: [exp], timeout: 1.0)
    }

    // MARK: - Test 10 — payload too large rejected

    func test_payloadTooLarge_returnsFalse() async throws {
        // Manifest declares total_size_bytes > 5MB → coordinator rejects pre-srs-fetch.
        let oversizedManifestJSON: [String: Any] = [
            "version": 5,
            "min_app_version": "0.8.0",
            "srs_format_version": 4,
            "total_size_bytes": 10 * 1024 * 1024,  // 10 MB > 5MB cap
            "files": [
                ["name": "bbtb-baseline-block.srs", "category": "block_completely",
                 "sha256": "00", "sig_path": "bbtb-baseline-block.srs.sig"],
                ["name": "bbtb-baseline-never.srs", "category": "never_through_vpn",
                 "sha256": "00", "sig_path": "bbtb-baseline-never.srs.sig"],
                ["name": "bbtb-baseline-always.srs", "category": "always_through_vpn",
                 "sha256": "00", "sig_path": "bbtb-baseline-always.srs.sig"],
            ],
            "block_completely": ["domains": [], "ip_cidrs": [], "countries": []],
            "never_through_vpn": ["domains": [], "ip_cidrs": [], "countries": []],
            "always_through_vpn": ["domains": [], "ip_cidrs": [], "countries": []],
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: oversizedManifestJSON, options: [])
        let manifestSig = Data(repeating: 0, count: 64)
        let manifestURL = URL(string: "https://example.com/manifest.json")!

        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: manifestData)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: manifestSig)

        let coord = RulesEngineCoordinator(
            fetcher: fakeFetcher,
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [manifestURL],
            signer: AlwaysValidVerifier()
        )
        await coord.bootstrap()

        let didUpdate = await coord.performBackgroundRefresh()
        XCTAssertFalse(didUpdate, "Oversized manifest → false")

        // forceUpdate должен mapping в .payloadTooLarge.
        let outcome = await coord.forceUpdate()
        if case .payloadTooLarge = outcome {
            // OK — matched expected outcome.
        } else {
            XCTFail("forceUpdate с oversized manifest должен .payloadTooLarge, got \(outcome)")
        }
    }

    // MARK: - Test 11 — CRITICAL: currentSnapshot materializes CategoryEntries из CategoryBodies

    /// Acceptance test для RULES-09 viewer foundation. Без этой materialization
    /// RULES-09 SettingsViewModel.rulesSnapshot всегда показывал бы empty
    /// domains/ipCidrs/countries arrays.
    func test_currentSnapshot_materializesCategoryEntriesFromManifest() async throws {
        let coord = RulesEngineCoordinator(
            fetcher: FakeFetcher(),
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [URL(string: "https://example.com/manifest.json")!],
            signer: AlwaysValidVerifier()
        )
        await coord.bootstrap()

        let snapshot = await coord.currentSnapshot()
        XCTAssertNotNil(snapshot, "Snapshot должен materialize после bootstrap")
        guard let snapshot else { return }

        // block_completely должен содержать max.ru + mssgr.tatar.ru (sync с baseline JSON).
        XCTAssertEqual(snapshot.block.domains, ["max.ru", "mssgr.tatar.ru"],
                       "Block domains materialized из manifest.blockCompletely.domains")
        XCTAssertEqual(snapshot.block.ipCidrs, [], "Block ipCidrs пустые")
        XCTAssertEqual(snapshot.block.countries, [], "Block countries пустые")

        // never и always категории пустые.
        XCTAssertEqual(snapshot.never.domains, [])
        XCTAssertEqual(snapshot.never.ipCidrs, [])
        XCTAssertEqual(snapshot.never.countries, [])
        XCTAssertEqual(snapshot.always.domains, [])
        XCTAssertEqual(snapshot.always.ipCidrs, [])
        XCTAssertEqual(snapshot.always.countries, [])

        XCTAssertEqual(snapshot.version, 0, "Baseline version=0")
        XCTAssertEqual(snapshot.minAppVersion, "0.8.0", "minAppVersion из manifest")
        XCTAssertNil(snapshot.lastFetchedAt, "Baseline bootstrap → lastFetchedAt nil (refresh не ran)")
    }
}

// MARK: - Fixtures

/// In-memory fake fetcher для test injection. Actor для thread-safety; tests mutate
/// responses через `set(url:response:)` перед invoke coordinator.
private actor FakeFetcher: RulesFetcherProtocol {
    private var responses: [String: Data] = [:]

    func set(url: URL, response data: Data) {
        responses[url.absoluteString] = data
    }

    nonisolated func fetchWithFailover(urls: [URL], maxBytes: Int) async throws -> RulesFetcher.FetchResult {
        guard let firstURL = urls.first else {
            throw RulesFetcher.FetchError.allMirrorsFailed([])
        }
        let key = firstURL.absoluteString
        let data = await self.lookup(key: key)
        guard let data else {
            throw RulesFetcher.FetchError.allMirrorsFailed([
                RulesFetcher.FetchError.httpStatusError(404)
            ])
        }
        return RulesFetcher.FetchResult(body: data, etag: nil, mirrorURL: firstURL)
    }

    private func lookup(key: String) -> Data? { responses[key] }
}

/// Mutable wallclock — tests advance time via `setNow(_:)`.
private final class FixedClock: ClockProtocol, @unchecked Sendable {
    private var _now: Date
    private let lock = NSLock()

    init(now: Date) { self._now = now }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    func setNow(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        _now = date
    }
}

/// Stub verifier — всегда `true`. Use в success-path tests (decouples от placeholder pubkey).
private struct AlwaysValidVerifier: SignatureVerifierProtocol {
    func verify(message: Data, signature: Data) -> Bool { true }
}

/// Stub verifier — всегда `false`. Use в tamper-sig tests.
private struct AlwaysInvalidVerifier: SignatureVerifierProtocol {
    func verify(message: Data, signature: Data) -> Bool { false }
}

// MARK: - Test manifest synthesis

/// Helper для генерации synthetic RulesManifest JSON + sidecar signatures + per-file
/// .srs payloads. Все signatures = 64 zero bytes (verify injection нужен на coordinator
/// level для accept-or-reject).
private enum TestManifest {
    struct Entry {
        let name: String
        let sigPath: String
        let category: String
        let srsBytes: Data
        let sigBytes: Data
    }
    struct Fixtures {
        let manifestBody: Data
        let manifestSig: Data
        let entries: [Entry]
    }

    static func signed(version: Int) -> Fixtures {
        let entries: [Entry] = [
            Entry(name: "bbtb-baseline-block.srs",
                  sigPath: "bbtb-baseline-block.srs.sig",
                  category: "block_completely",
                  srsBytes: Data([0x53, 0x52, 0x53, 0x04, 0xAA]),
                  sigBytes: Data(repeating: 0, count: 64)),
            Entry(name: "bbtb-baseline-never.srs",
                  sigPath: "bbtb-baseline-never.srs.sig",
                  category: "never_through_vpn",
                  srsBytes: Data([0x53, 0x52, 0x53, 0x04, 0xBB]),
                  sigBytes: Data(repeating: 0, count: 64)),
            Entry(name: "bbtb-baseline-always.srs",
                  sigPath: "bbtb-baseline-always.srs.sig",
                  category: "always_through_vpn",
                  srsBytes: Data([0x53, 0x52, 0x53, 0x04, 0xCC]),
                  sigBytes: Data(repeating: 0, count: 64)),
        ]

        let json: [String: Any] = [
            "version": version,
            "min_app_version": "0.8.0",
            "srs_format_version": 4,
            "total_size_bytes": entries.reduce(0) { $0 + $1.srsBytes.count },
            "files": entries.map { entry -> [String: Any] in
                [
                    "name": entry.name,
                    "category": entry.category,
                    // T-A1 (closes A5-003 / C5-002): coordinator теперь verifies
                    // SHA-256 of fetched SRS bytes against manifest.entry.sha256.
                    // Test fixtures должны provide real hash of srsBytes.
                    "sha256": Self.sha256Hex(entry.srsBytes),
                    "sig_path": entry.sigPath,
                ]
            },
            "block_completely": ["domains": ["server-test.example"], "ip_cidrs": [], "countries": []],
            "never_through_vpn": ["domains": [], "ip_cidrs": [], "countries": []],
            "always_through_vpn": ["domains": [], "ip_cidrs": [], "countries": []],
        ]
        let manifestBody = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let manifestSig = Data(repeating: 0, count: 64)
        return Fixtures(manifestBody: manifestBody, manifestSig: manifestSig, entries: entries)
    }

    /// T-A1: compute SHA-256 hex для real-hash test fixtures.
    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
