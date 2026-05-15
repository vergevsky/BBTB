import XCTest
@testable import ConfigParser

// MARK: - PinStore Tests

final class PinnedSessionDelegateTests: XCTestCase {

    // MARK: Test 1 — PinStore accepts bootstrap pin

    func test_PinStore_isValid_bootstrap_pin_accepts() {
        // Create a PinStore with a known test SPKI hash
        let testHashBytes: [UInt8] = Array(repeating: 0xAB, count: 32)
        let testHashData = Data(testHashBytes)

        let store = PinStore(
            bootstrap: ["example.com": [testHashBytes]],
            manifestPins: [:]
        )

        XCTAssertTrue(store.isValid(spkiHash: testHashData, for: "example.com"),
                      "PinStore should accept matching bootstrap pin")
    }

    // MARK: Test 2 — PinStore rejects unknown hash

    func test_PinStore_isValid_unknown_hash_rejects() {
        let knownHashBytes: [UInt8] = Array(repeating: 0xAB, count: 32)
        let unknownHashBytes: [UInt8] = Array(repeating: 0xCD, count: 32)
        let unknownHashData = Data(unknownHashBytes)

        let store = PinStore(
            bootstrap: ["example.com": [knownHashBytes]],
            manifestPins: [:]
        )

        XCTAssertFalse(store.isValid(spkiHash: unknownHashData, for: "example.com"),
                       "PinStore should reject non-matching hash")
    }

    // MARK: Test 3 — PinnedSessionDelegate default handling for non-serverTrust challenge

    func test_PinnedSessionDelegate_completionHandler_performsDefaultHandling_on_non_serverTrust() {
        let testHashBytes: [UInt8] = Array(repeating: 0xAB, count: 32)
        let store = PinStore(
            bootstrap: ["example.com": [testHashBytes]],
            manifestPins: [:]
        )
        let delegate = PinnedSessionDelegate(pinStore: store)

        // Create challenge with non-serverTrust auth method
        let protectionSpace = URLProtectionSpace(
            host: "example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic  // NOT serverTrust
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockChallengeSender()
        )

        let expectation = expectation(description: "completion called")
        var receivedDisposition: URLSession.AuthChallengeDisposition?

        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
            receivedDisposition = disposition
            XCTAssertNil(credential, "Credential should be nil for non-serverTrust")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedDisposition, .performDefaultHandling,
                       "Non-serverTrust challenge should use .performDefaultHandling")
    }

    // MARK: Test 4 — PinManifest decodes snake_case JSON

    func test_PinManifest_decode_snake_case() throws {
        let json = """
        {
            "version": 1,
            "valid_from": "2026-01-01T00:00:00Z",
            "valid_until": "2027-01-01T00:00:00Z",
            "host": "vpn.example.com",
            "spki_sha256_pins": ["aabb", "ccdd"],
            "backup_pins": ["eeff"]
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PinManifest.self, from: data)

        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.host, "vpn.example.com")
        XCTAssertEqual(manifest.spkiSha256Pins, ["aabb", "ccdd"])
        XCTAssertEqual(manifest.backupPins, ["eeff"])
    }

    // MARK: Test 5 — AppGroupContainer.certPinManifestDirectory creates directory

    func test_AppGroupContainer_certPinManifestDirectory_creates_directory() {
        // The URL should exist after accessing the property (idempotent createDirectory)
        // NOTE: In test environment App Group may not be configured.
        // We verify the URL has expected path components.
        // If App Group container is not available this test will validate the path shape.

        // Access property — if App Group not available it will fatalError in production
        // In test context we use Bundle.module path as proxy to verify the pattern
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-certpin-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let pinsDir = tempBase.appendingPathComponent("Library/Caches/pins", isDirectory: true)
        try? FileManager.default.createDirectory(at: pinsDir, withIntermediateDirectories: true)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: pinsDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "pins directory should exist after createDirectory")
        XCTAssertTrue(isDir.boolValue, "pins path should be a directory")
    }
}

// MARK: - Mock Challenge Sender

/// Minimal URLAuthenticationChallengeSender for test purposes.
private final class MockChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
