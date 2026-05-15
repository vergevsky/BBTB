// SettingsViewModelTests.swift — Phase 8 / W3.3
//
// Integration-тесты `SettingsViewModel` × `RulesEngineCoordinator` через
// late-bind `wireRulesCoordinator(_:)`. Используем real RulesEngineCoordinator с
// fake fetcher/signer/clock (тот же паттерн как RulesEngineCoordinatorTests
// в W2) чтобы не имитировать actor через protocol.

import XCTest
@testable import SettingsFeature
@testable import RulesEngine

@MainActor
final class SettingsViewModelTests: XCTestCase {

    var tmpDir: URL!
    var store: SRSCacheStore!

    private static let dismissedKey = "app.bbtb.minAppVersion.dismissed"
    private static let customDnsKey = "app.bbtb.customDNS"
    private static let adblockKey = "app.bbtb.adBlockEnabled"

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-vm-test-\(UUID().uuidString)", isDirectory: true)
        store = SRSCacheStore(directory: tmpDir)
        UserDefaults.standard.removeObject(forKey: Self.dismissedKey)
        UserDefaults.standard.removeObject(forKey: Self.customDnsKey)
        UserDefaults.standard.removeObject(forKey: Self.adblockKey)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        tmpDir = nil
        store = nil
        UserDefaults.standard.removeObject(forKey: Self.dismissedKey)
        UserDefaults.standard.removeObject(forKey: Self.customDnsKey)
        UserDefaults.standard.removeObject(forKey: Self.adblockKey)
        try await super.tearDown()
    }

    // MARK: - 1. wireCoordinator initializes snapshot publishing

    func test_wireCoordinator_initializesSnapshotPublishing() async throws {
        let coord = makeCoordinator(fetcher: FakeFetcher(), signer: AlwaysValidVerifier())
        await coord.bootstrap()

        let vm = SettingsViewModel()
        XCTAssertNil(vm.rulesSnapshot, "До wire snapshot nil")

        await vm.wireRulesCoordinator(coord)
        XCTAssertNotNil(vm.rulesSnapshot, "После wire snapshot инициализирован (baseline)")
        XCTAssertEqual(vm.rulesVersion, 0, "Baseline version=0")

        vm.teardown()
    }

    // MARK: - 2. notification fires → refreshes snapshot

    func test_notificationFires_refreshesSnapshot() async throws {
        // Setup: coord bootstrap → vm wires → coord performs refresh → notification fires
        // → vm должен обновить rulesSnapshot до новой версии.
        let fixtures = TestManifest.signed(version: 7)
        let manifestURL = URL(string: "https://example.com/manifest.json")!
        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.name)")!, response: entry.srsBytes)
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.sigPath)")!, response: entry.sigBytes)
        }

        let coord = makeCoordinator(fetcher: fakeFetcher, signer: AlwaysValidVerifier(),
                                    mirrorURL: manifestURL)
        await coord.bootstrap()

        let vm = SettingsViewModel()
        await vm.wireRulesCoordinator(coord)
        XCTAssertEqual(vm.rulesVersion, 0, "Initial baseline version=0")

        let didUpdate = await coord.performBackgroundRefresh()
        XCTAssertTrue(didUpdate)

        // Notification dispatched через Task @MainActor — yield чтобы pump runloop.
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if vm.rulesVersion == 7 { break }
        }
        XCTAssertEqual(vm.rulesVersion, 7, "Версия обновлена после notification")

        vm.teardown()
    }

    // MARK: - 3. triggerForceUpdate: idle → inProgress → cooldown

    func test_triggerForceUpdate_idleToInProgress_toCooldown() async throws {
        let fixtures = TestManifest.signed(version: 5)
        let manifestURL = URL(string: "https://example.com/manifest.json")!
        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.name)")!, response: entry.srsBytes)
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.sigPath)")!, response: entry.sigBytes)
        }

        let coord = makeCoordinator(fetcher: fakeFetcher, signer: AlwaysValidVerifier(),
                                    mirrorURL: manifestURL)
        await coord.bootstrap()

        let vm = SettingsViewModel()
        await vm.wireRulesCoordinator(coord)
        XCTAssertEqual(vm.forceUpdateButtonState, .idle, "Initial idle")

        await vm.triggerForceUpdate()

        // После triggerForceUpdate должен либо .cooldown (success path), либо .cooldown
        // (для других outcomes 60s).
        switch vm.forceUpdateButtonState {
        case .cooldown(let sec):
            XCTAssertGreaterThan(sec, 0, "Cooldown active с >0 seconds remaining")
            XCTAssertLessThanOrEqual(sec, 60)
        default:
            XCTFail("После triggerForceUpdate должен .cooldown(...), got \(vm.forceUpdateButtonState)")
        }

        // statusOutcome — должен быть .success(5) (FakeFetcher serves fresh manifest).
        if case .success(let v) = vm.forceUpdateStatusOutcome {
            XCTAssertEqual(v, 5, "Success outcome carries version 5")
        } else {
            XCTFail("Expected .success(5), got \(String(describing: vm.forceUpdateStatusOutcome))")
        }

        vm.teardown()
    }

    // MARK: - 4. race guard — second call is no-op

    func test_triggerForceUpdate_raceGuard_secondCallIsNoop() async throws {
        let fixtures = TestManifest.signed(version: 5)
        let manifestURL = URL(string: "https://example.com/manifest.json")!
        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.name)")!, response: entry.srsBytes)
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.sigPath)")!, response: entry.sigBytes)
        }

        let coord = makeCoordinator(fetcher: fakeFetcher, signer: AlwaysValidVerifier(),
                                    mirrorURL: manifestURL)
        await coord.bootstrap()

        let vm = SettingsViewModel()
        await vm.wireRulesCoordinator(coord)

        // First trigger — должен пройти.
        await vm.triggerForceUpdate()
        let stateAfterFirst = vm.forceUpdateButtonState

        // Second trigger — guard `state != .idle` → no-op.
        await vm.triggerForceUpdate()
        XCTAssertEqual(vm.forceUpdateButtonState, stateAfterFirst,
                       "Second triggerForceUpdate no-op — state не изменился")

        vm.teardown()
    }

    // MARK: - 5. showMinAppVersionBanner — when min exceeds current

    func test_showMinAppVersionBanner_setWhenMinExceedsCurrent() async throws {
        // Server snapshot.minAppVersion = "99.0.0" заведомо больше current (Bundle.main
        // в test target = test bundle, currentAppVersion fallback "0.0.0").
        let manifestURL = URL(string: "https://example.com/manifest.json")!
        let fixtures = TestManifest.signed(version: 5, minAppVersion: "99.0.0")
        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.name)")!, response: entry.srsBytes)
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.sigPath)")!, response: entry.sigBytes)
        }

        let coord = makeCoordinator(fetcher: fakeFetcher, signer: AlwaysValidVerifier(),
                                    mirrorURL: manifestURL)
        await coord.bootstrap()
        _ = await coord.performBackgroundRefresh()

        let vm = SettingsViewModel()
        await vm.wireRulesCoordinator(coord)
        XCTAssertTrue(vm.showMinAppVersionBanner,
                      "min=99.0.0 > current → banner shown")

        vm.teardown()
    }

    // MARK: - 6. showMinAppVersionBanner false когда current meets min

    func test_showMinAppVersionBanner_falseWhenCurrentMeetsMin() async throws {
        // Default baseline manifest имеет min_app_version = "0.8.0". Test bundle's
        // currentAppVersion = "0.0.0" (fallback) — это меньше 0.8.0. Поэтому для
        // правильного теста используем custom snapshot с min = "0.0.0" (равен current).
        let manifestURL = URL(string: "https://example.com/manifest.json")!
        let fixtures = TestManifest.signed(version: 5, minAppVersion: "0.0.0")
        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.name)")!, response: entry.srsBytes)
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.sigPath)")!, response: entry.sigBytes)
        }

        let coord = makeCoordinator(fetcher: fakeFetcher, signer: AlwaysValidVerifier(),
                                    mirrorURL: manifestURL)
        await coord.bootstrap()
        _ = await coord.performBackgroundRefresh()

        let vm = SettingsViewModel()
        await vm.wireRulesCoordinator(coord)
        XCTAssertFalse(vm.showMinAppVersionBanner,
                       "min=0.0.0 == current (test bundle fallback) → banner hidden")

        vm.teardown()
    }

    // MARK: - 7. statusOutcome auto-dismiss after 4 seconds

    func test_statusOutcome_autoDismisses_after_4_seconds() async throws {
        let fixtures = TestManifest.signed(version: 5)
        let manifestURL = URL(string: "https://example.com/manifest.json")!
        let fakeFetcher = FakeFetcher()
        await fakeFetcher.set(url: manifestURL, response: fixtures.manifestBody)
        await fakeFetcher.set(url: manifestURL.appendingPathExtension("sig"), response: fixtures.manifestSig)
        for entry in fixtures.entries {
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.name)")!, response: entry.srsBytes)
            await fakeFetcher.set(url: URL(string: "https://example.com/\(entry.sigPath)")!, response: entry.sigBytes)
        }

        let coord = makeCoordinator(fetcher: fakeFetcher, signer: AlwaysValidVerifier(),
                                    mirrorURL: manifestURL)
        await coord.bootstrap()

        let vm = SettingsViewModel()
        await vm.wireRulesCoordinator(coord)
        await vm.triggerForceUpdate()
        XCTAssertNotNil(vm.forceUpdateStatusOutcome, "Outcome set после trigger")

        // Wait 4.5s — auto-dismiss task должен установить outcome = nil.
        try await Task.sleep(nanoseconds: 4_500_000_000)

        XCTAssertNil(vm.forceUpdateStatusOutcome, "Outcome auto-dismissed после 4s")

        vm.teardown()
    }

    // MARK: - Phase 10 — new @AppStorage props + utlsOptions + stunBlockShowConfirm

    /// Test 1: default values for all 6 new Phase 10 props.
    func test_phase10_defaults() {
        // Clean test storage before VM creation.
        let phase10Keys = [
            "app.bbtb.cdnFrontingEnabled",
            "app.bbtb.muxEnabled",
            "app.bbtb.stunBlockEnabled",
            "app.bbtb.certPinningEnabled",
            "app.bbtb.utlsFingerprint",
        ]
        let groupDefaults = UserDefaults(suiteName: "group.app.bbtb.shared")
        let groupKeys = [
            "app.bbtb.muxEnabled",
            "app.bbtb.stunBlockEnabled",
            "app.bbtb.utlsFingerprint",
            "app.bbtb.macOSDisableEnforceRoutes",
        ]
        for key in phase10Keys { UserDefaults.standard.removeObject(forKey: key) }
        for key in groupKeys { groupDefaults?.removeObject(forKey: key) }
        defer {
            for key in phase10Keys { UserDefaults.standard.removeObject(forKey: key) }
            for key in groupKeys { groupDefaults?.removeObject(forKey: key) }
        }

        let vm = SettingsViewModel()
        XCTAssertFalse(vm.cdnFrontingEnabled, "cdnFrontingEnabled default = false")
        XCTAssertFalse(vm.muxEnabled, "muxEnabled default = false")
        XCTAssertFalse(vm.stunBlockEnabled, "stunBlockEnabled default = false")
        XCTAssertTrue(vm.certPinningEnabled, "certPinningEnabled default = true")
        XCTAssertEqual(vm.utlsFingerprint, "random", "utlsFingerprint default = random")
        #if os(macOS)
        XCTAssertFalse(vm.macOSDisableEnforceRoutes, "macOSDisableEnforceRoutes default = false")
        #endif
    }

    /// Test 2: persistence roundtrip — write keys to UserDefaults, then read via VM.
    func test_phase10_persistence_roundtrip() {
        let groupDefaults = UserDefaults(suiteName: "group.app.bbtb.shared")
        // Write to standard for cdn/certPinning, group for mux/stun/utls.
        UserDefaults.standard.set(true, forKey: "app.bbtb.cdnFrontingEnabled")
        groupDefaults?.set(true, forKey: "app.bbtb.muxEnabled")
        groupDefaults?.set(true, forKey: "app.bbtb.stunBlockEnabled")
        UserDefaults.standard.set(false, forKey: "app.bbtb.certPinningEnabled")
        groupDefaults?.set("chrome", forKey: "app.bbtb.utlsFingerprint")
        defer {
            UserDefaults.standard.removeObject(forKey: "app.bbtb.cdnFrontingEnabled")
            groupDefaults?.removeObject(forKey: "app.bbtb.muxEnabled")
            groupDefaults?.removeObject(forKey: "app.bbtb.stunBlockEnabled")
            UserDefaults.standard.removeObject(forKey: "app.bbtb.certPinningEnabled")
            groupDefaults?.removeObject(forKey: "app.bbtb.utlsFingerprint")
        }

        let vm = SettingsViewModel()
        XCTAssertTrue(vm.cdnFrontingEnabled, "cdnFrontingEnabled reads true from standard")
        XCTAssertTrue(vm.muxEnabled, "muxEnabled reads true from group suite")
        XCTAssertTrue(vm.stunBlockEnabled, "stunBlockEnabled reads true from group suite")
        XCTAssertFalse(vm.certPinningEnabled, "certPinningEnabled reads false from standard")
        XCTAssertEqual(vm.utlsFingerprint, "chrome", "utlsFingerprint reads chrome from group suite")
    }

    /// Test 3 (macOS only): macOSDisableEnforceRoutes reads from App Group suite.
    #if os(macOS)
    func test_macOSDisableEnforceRoutes_uses_app_group_suite() {
        let groupDefaults = UserDefaults(suiteName: "group.app.bbtb.shared")
        groupDefaults?.set(true, forKey: "app.bbtb.macOSDisableEnforceRoutes")
        defer { groupDefaults?.removeObject(forKey: "app.bbtb.macOSDisableEnforceRoutes") }

        let vm = SettingsViewModel()
        XCTAssertTrue(vm.macOSDisableEnforceRoutes,
                      "macOSDisableEnforceRoutes reads from group suite, not .standard")
    }
    #endif

    /// Test 4: utlsOptions contains all 7 expected values in correct order.
    func test_utlsOptions_contains_all_seven() {
        let expected = ["random", "chrome", "firefox", "safari", "ios", "android", "edge"]
        XCTAssertEqual(SettingsViewModel.utlsOptions, expected,
                       "utlsOptions must contain exactly 7 fingerprints in canonical order")
    }

    /// Test 5: stunBlockShowConfirm is initialized false.
    func test_stunBlockShowConfirm_initial_false() {
        let vm = SettingsViewModel()
        XCTAssertFalse(vm.stunBlockShowConfirm,
                       "stunBlockShowConfirm must be false on VM init (UI alert binding)")
    }

    /// Test 6: no key collision between new Phase 10 keys and existing keys.
    func test_phase10_keys_dont_collide() {
        let existingKeys = [
            "app.bbtb.killSwitchEnabled",
            "app.bbtb.customDNS",
            "app.bbtb.adBlockEnabled",
            "app.bbtb.autoReconnectEnabled",
            "app.bbtb.minAppVersion.dismissed",
        ]
        let newKeys = [
            "app.bbtb.cdnFrontingEnabled",
            "app.bbtb.muxEnabled",
            "app.bbtb.stunBlockEnabled",
            "app.bbtb.certPinningEnabled",
            "app.bbtb.utlsFingerprint",
            "app.bbtb.macOSDisableEnforceRoutes",
        ]
        for newKey in newKeys {
            for existingKey in existingKeys {
                XCTAssertNotEqual(newKey, existingKey,
                                  "New key '\(newKey)' collides with existing '\(existingKey)'")
            }
        }
    }

    // MARK: - Helpers

    private func makeCoordinator(
        fetcher: any RulesFetcherProtocol,
        signer: any SignatureVerifierProtocol,
        mirrorURL: URL = URL(string: "https://example.com/manifest.json")!
    ) -> RulesEngineCoordinator {
        RulesEngineCoordinator(
            fetcher: fetcher,
            cache: store,
            clock: FixedClock(now: Date()),
            mirrorURLs: [mirrorURL],
            signer: signer
        )
    }
}

// MARK: - Test fixtures (mirror RulesEngineCoordinatorTests private types)

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
        let data = await lookup(key: key)
        guard let data else {
            throw RulesFetcher.FetchError.allMirrorsFailed([
                RulesFetcher.FetchError.httpStatusError(404)
            ])
        }
        return RulesFetcher.FetchResult(body: data, etag: nil, mirrorURL: firstURL)
    }

    private func lookup(key: String) -> Data? { responses[key] }
}

private final class FixedClock: ClockProtocol, @unchecked Sendable {
    private var _now: Date
    private let lock = NSLock()
    init(now: Date) { self._now = now }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return _now }
    func setNow(_ date: Date) { lock.lock(); defer { lock.unlock() }; _now = date }
}

private struct AlwaysValidVerifier: SignatureVerifierProtocol {
    func verify(message: Data, signature: Data) -> Bool { true }
}

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

    static func signed(version: Int, minAppVersion: String = "0.8.0") -> Fixtures {
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
            "min_app_version": minAppVersion,
            "srs_format_version": 4,
            "total_size_bytes": entries.reduce(0) { $0 + $1.srsBytes.count },
            "files": entries.map { entry -> [String: Any] in
                [
                    "name": entry.name,
                    "category": entry.category,
                    "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
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
}
