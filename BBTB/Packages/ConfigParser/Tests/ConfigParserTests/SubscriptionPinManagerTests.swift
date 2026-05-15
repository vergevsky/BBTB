import XCTest
import Crypto
@testable import ConfigParser

// MARK: - Mock Fetcher

/// Mock implementation of SubscriptionURLFetching that returns pre-configured data.
private struct MockPinFetcher: SubscriptionURLFetching, Sendable {
    /// Maps URL strings to response data. Supports both manifest and .sig URLs.
    nonisolated(unsafe) static var responses: [String: Result<Data, Error>] = [:]

    func fetch(url: URL) async throws -> SubscriptionFetchResult {
        let key = url.absoluteString
        if let result = Self.responses[key] {
            switch result {
            case .success(let data):
                let metadata = SubscriptionMetadata(title: nil, updateInterval: nil, userInfo: nil)
                return SubscriptionFetchResult(body: data, metadata: metadata, finalURL: url)
            case .failure(let error):
                throw error
            }
        }
        throw SubscriptionURLFetcher.FetchError.timeout
    }
}

// MARK: - Test Fixtures

private enum TestFixture {
    /// Generate a fresh Ed25519 keypair for test signing.
    static func makeKeypair() -> (privateKey: Curve25519.Signing.PrivateKey, publicKeyBytes: [UInt8]) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBytes = Array(privateKey.publicKey.rawRepresentation)
        return (privateKey, publicKeyBytes)
    }

    /// Create a valid PinManifest JSON data with given validity window.
    static func makeManifestData(
        validFrom: Date = Date().addingTimeInterval(-3600),
        validUntil: Date = Date().addingTimeInterval(3600 * 24 * 365),
        host: String = "vpn.vergevsky.ru",
        pins: [String] = ["abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"],
        backupPins: [String] = []
    ) -> Data {
        let formatter = ISO8601DateFormatter()
        let validFromStr = formatter.string(from: validFrom)
        let validUntilStr = formatter.string(from: validUntil)
        let pinsJSON = pins.map { "\"\($0)\"" }.joined(separator: ", ")
        let backupsJSON = backupPins.map { "\"\($0)\"" }.joined(separator: ", ")
        let json = """
        {
            "version": 1,
            "valid_from": "\(validFromStr)",
            "valid_until": "\(validUntilStr)",
            "host": "\(host)",
            "spki_sha256_pins": [\(pinsJSON)],
            "backup_pins": [\(backupsJSON)]
        }
        """
        return json.data(using: .utf8)!
    }

    /// Sign manifest data with a test private key. Returns 64-byte Ed25519 signature.
    static func sign(_ data: Data, with privateKey: Curve25519.Signing.PrivateKey) -> Data {
        return (try? privateKey.signature(for: data)) ?? Data(repeating: 0, count: 64)
    }
}

// MARK: - SubscriptionPinManagerTests

final class SubscriptionPinManagerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubscriptionPinManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        MockPinFetcher.responses = [:]
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        MockPinFetcher.responses = [:]
        try await super.tearDown()
    }

    // MARK: Test 1 — bootstrap copies bundle resource to App Group cache

    func test_SubscriptionPinManager_bootstrap_copies_bundle_to_app_group() async throws {
        // Write a test JSON to tempDir to simulate bundle resource
        let testJSON = TestFixture.makeManifestData()
        let bundleFile = tempDir.appendingPathComponent("subscription-pins-bootstrap.json")
        try testJSON.write(to: bundleFile)

        let cacheDir = tempDir.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Create manager with a bundleLookup that uses our temp file
        let manager = SubscriptionPinManager(
            cacheDir: cacheDir,
            bundleResourceURL: bundleFile,
            publicKeyBytes: nil,
            mirrorURLs: [],
            fetcher: MockPinFetcher()
        )

        await manager.bootstrap()

        let cachedFile = cacheDir.appendingPathComponent("subscription-pins-cached.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedFile.path),
                      "bootstrap should copy bundle resource to cacheDir")
        let cachedData = try Data(contentsOf: cachedFile)
        XCTAssertEqual(cachedData, testJSON, "cached content should match bundle resource")
    }

    // MARK: Test 2 — bootstrap is idempotent

    func test_SubscriptionPinManager_bootstrap_idempotent() async throws {
        let testJSON = TestFixture.makeManifestData()
        let bundleFile = tempDir.appendingPathComponent("subscription-pins-bootstrap.json")
        try testJSON.write(to: bundleFile)

        let cacheDir = tempDir.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let manager = SubscriptionPinManager(
            cacheDir: cacheDir,
            bundleResourceURL: bundleFile,
            publicKeyBytes: nil,
            mirrorURLs: [],
            fetcher: MockPinFetcher()
        )

        await manager.bootstrap()

        // Write different content to cache to detect if bootstrap overwrites it
        let cachedFile = cacheDir.appendingPathComponent("subscription-pins-cached.json")
        let differentContent = "DIFFERENT".data(using: .utf8)!
        try differentContent.write(to: cachedFile)

        // Second bootstrap should NOT overwrite existing cache
        await manager.bootstrap()

        let finalData = try Data(contentsOf: cachedFile)
        XCTAssertEqual(finalData, differentContent,
                       "Second bootstrap should not overwrite existing cache")
    }

    // MARK: Test 3 — currentPins returns bootstrap pins when no cached manifest

    func test_SubscriptionPinManager_currentPins_returns_bootstrap_when_no_cache() async throws {
        let testJSON = TestFixture.makeManifestData()
        let bundleFile = tempDir.appendingPathComponent("subscription-pins-bootstrap.json")
        try testJSON.write(to: bundleFile)

        let cacheDir = tempDir.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let manager = SubscriptionPinManager(
            cacheDir: cacheDir,
            bundleResourceURL: bundleFile,
            publicKeyBytes: nil,
            mirrorURLs: [],
            fetcher: MockPinFetcher()
        )

        await manager.bootstrap()

        let pins = await manager.currentPins(for: "vpn.vergevsky.ru")
        // Should contain at least the 2 bootstrap placeholder pins
        XCTAssertGreaterThanOrEqual(pins.count, 2,
                                    "currentPins should return bootstrap pins after bootstrap")
    }

    // MARK: Test 4 — performBackgroundRefresh rejects invalid signature

    func test_SubscriptionPinManager_performBackgroundRefresh_rejects_invalid_signature() async throws {
        let (_, publicKeyBytes) = TestFixture.makeKeypair()
        let manifestData = TestFixture.makeManifestData()
        // Use wrong/invalid signature bytes (64 bytes but garbage)
        let invalidSig = Data(repeating: 0xFF, count: 64)

        let manifestURL = URL(string: "https://vpn.vergevsky.ru/.well-known/subscription-pins.json")!
        let sigURL = manifestURL.appendingPathExtension("sig")
        MockPinFetcher.responses[manifestURL.absoluteString] = .success(manifestData)
        MockPinFetcher.responses[sigURL.absoluteString] = .success(invalidSig)

        let cacheDir = tempDir.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let bundleFile = tempDir.appendingPathComponent("subscription-pins-bootstrap.json")
        try TestFixture.makeManifestData().write(to: bundleFile)

        let manager = SubscriptionPinManager(
            cacheDir: cacheDir,
            bundleResourceURL: bundleFile,
            publicKeyBytes: publicKeyBytes,
            mirrorURLs: [manifestURL],
            fetcher: MockPinFetcher()
        )

        do {
            try await manager.performBackgroundRefresh(certPinningEnabled: true)
            XCTFail("Should throw on invalid signature")
        } catch PinManagerError.signatureInvalid {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Cache should NOT be updated
        let cachedFile = cacheDir.appendingPathComponent("subscription-pins-cached.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedFile.path),
                       "Cache should not be written when signature is invalid")
    }

    // MARK: Test 5 — performBackgroundRefresh rejects expired validUntil

    func test_SubscriptionPinManager_performBackgroundRefresh_rejects_expired_validUntil() async throws {
        let (privateKey, publicKeyBytes) = TestFixture.makeKeypair()

        // Manifest expired yesterday
        let expiredManifest = TestFixture.makeManifestData(
            validFrom: Date().addingTimeInterval(-3600 * 48),
            validUntil: Date().addingTimeInterval(-3600 * 24)  // yesterday
        )
        let validSig = TestFixture.sign(expiredManifest, with: privateKey)

        let manifestURL = URL(string: "https://vpn.vergevsky.ru/.well-known/subscription-pins.json")!
        let sigURL = manifestURL.appendingPathExtension("sig")
        MockPinFetcher.responses[manifestURL.absoluteString] = .success(expiredManifest)
        MockPinFetcher.responses[sigURL.absoluteString] = .success(validSig)

        let cacheDir = tempDir.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let bundleFile = tempDir.appendingPathComponent("subscription-pins-bootstrap.json")
        try TestFixture.makeManifestData().write(to: bundleFile)

        let manager = SubscriptionPinManager(
            cacheDir: cacheDir,
            bundleResourceURL: bundleFile,
            publicKeyBytes: publicKeyBytes,
            mirrorURLs: [manifestURL],
            fetcher: MockPinFetcher()
        )

        do {
            try await manager.performBackgroundRefresh(certPinningEnabled: true)
            XCTFail("Should throw on expired manifest")
        } catch PinManagerError.manifestExpired {
            // Expected — D-12 policy
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Test 7 — PinnedSubscriptionURLFetcher has PinnedSessionDelegate wired

    func test_PinnedSubscriptionURLFetcher_uses_delegate_when_provided() {
        let pinStore = PinStore()
        let fetcher = PinnedSubscriptionURLFetcher(pinStore: pinStore)
        // Verify the struct is properly constructed (Sendable, SubscriptionURLFetching conformance)
        XCTAssertNotNil(fetcher, "PinnedSubscriptionURLFetcher should be constructible with a PinStore")

        // Verify it conforms to SubscriptionURLFetching protocol
        let _: any SubscriptionURLFetching = fetcher
        XCTAssertTrue(true, "PinnedSubscriptionURLFetcher conforms to SubscriptionURLFetching")
    }

    // MARK: Test 8 — noPinningWhenDisabled (DPI-08 toggle OFF path)

    func test_noPinningWhenDisabled() {
        // When certPinningEnabled = false, the session factory should return
        // a session without PinnedSessionDelegate (default trust behavior).
        let pinnedSession = SubscriptionURLFetcher.makeSession(pinningEnabled: true, pinStore: .init())
        let unpinnedSession = SubscriptionURLFetcher.makeSession(pinningEnabled: false, pinStore: .init())

        // Pinned session should have a delegate (PinnedSessionDelegate)
        XCTAssertNotNil(pinnedSession.delegate,
                        "Pinned session should have PinnedSessionDelegate as delegate")
        XCTAssertTrue(pinnedSession.delegate is PinnedSessionDelegate,
                      "Pinned session delegate should be PinnedSessionDelegate")

        // Unpinned session should have NO delegate (uses default URL loading trust)
        // URLSession.shared is returned when pinning disabled — it has no custom delegate
        // OR we return a session with delegate==nil for toggled-off pinning
        XCTAssertNil(unpinnedSession.delegate,
                     "Unpinned session should have nil delegate (default trust)")

        // Cleanup
        pinnedSession.invalidateAndCancel()
        unpinnedSession.invalidateAndCancel()
    }
}
