import XCTest
@testable import RulesEngine

/// Unit tests для `RulesFetcher.fetch` + `fetchWithFailover` — HTTPS + SSRF + mirror failover.
///
/// **Mock pattern:** `URLSessionConfiguration.ephemeral` + `MockURLProtocol` (test-only
/// URLProtocol subclass под Fixtures/MockURLProtocol.swift). Pattern audited в Phase 2-3
/// для ConfigParser/SubscriptionURLFetcher; W1.4 copy-pastes same recipe.
final class RulesFetcherTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Single-URL `fetch` tests

    // Test 1 — http:// rejected with `nonHTTPS`
    func test_fetch_rejectsNonHTTPSScheme() async {
        let url = URL(string: "http://example.com/rules-manifest.json")!
        do {
            _ = try await RulesFetcher.fetch(url: url, session: MockURLProtocol.makeSession())
            XCTFail("Expected nonHTTPS to throw")
        } catch let err as RulesFetcher.FetchError {
            XCTAssertEqual(err, .nonHTTPS("http"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // Test 2 — SSRF blocklist rejects 127.0.0.1
    func test_fetch_rejectsBlockedHost_loopback() async {
        let url = URL(string: "https://127.0.0.1/rules-manifest.json")!
        do {
            _ = try await RulesFetcher.fetch(url: url, session: MockURLProtocol.makeSession())
            XCTFail("Expected blockedHost to throw for 127.0.0.1")
        } catch let err as RulesFetcher.FetchError {
            // Normalized host depends на SubscriptionURLFetcher.normalizeHostForLog;
            // 127.0.0.1 normalize → "127.0.0.1" (lowercase no brackets).
            if case .blockedHost(let h) = err {
                XCTAssertEqual(h, "127.0.0.1")
            } else {
                XCTFail("Expected .blockedHost, got \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // Test 3 — successful 200 returns body + ETag + mirrorURL
    func test_fetch_returnsBodyAndEtagOn200() async throws {
        let url = URL(string: "https://example.com/rules-manifest.json")!
        let payload = Data(#"{"version":1}"#.utf8)
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["ETag": "\"abc123\""]
            )!
            return (payload, resp)
        }

        let result = try await RulesFetcher.fetch(
            url: url, session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(result.body, payload)
        XCTAssertEqual(result.etag, "\"abc123\"")
        XCTAssertEqual(result.mirrorURL, url)

        // Verify request headers
        let headers = MockURLProtocol.lastRequest?.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["User-Agent"], "BBTB-Rules/0.8 (iOS / macOS)")
        XCTAssertTrue(headers["Accept"]?.contains("application/json") ?? false)
    }

    // Test 4 — HTTP 500 → httpStatusError(500)
    func test_fetch_throwsOnHTTP500() async {
        let url = URL(string: "https://example.com/rules-manifest.json")!
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (Data(), resp)
        }
        do {
            _ = try await RulesFetcher.fetch(url: url, session: MockURLProtocol.makeSession())
            XCTFail("Expected httpStatusError to throw")
        } catch let err as RulesFetcher.FetchError {
            XCTAssertEqual(err, .httpStatusError(500))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // Test 5 — body > maxBytes → payloadTooLarge
    func test_fetch_rejectsPayloadAboveMaxBytes() async {
        let url = URL(string: "https://example.com/rules-manifest.json")!
        let bigPayload = Data(repeating: 0x42, count: 10 * 1024 * 1024)  // 10 MB
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (bigPayload, resp)
        }
        do {
            _ = try await RulesFetcher.fetch(
                url: url, session: MockURLProtocol.makeSession(),
                maxBytes: 5 * 1024 * 1024  // cap at 5MB
            )
            XCTFail("Expected payloadTooLarge to throw")
        } catch let err as RulesFetcher.FetchError {
            if case .payloadTooLarge(let n) = err {
                XCTAssertEqual(n, 10 * 1024 * 1024)
            } else {
                XCTFail("Expected payloadTooLarge, got \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: `fetchWithFailover` tests

    // Test 6 — empty URLs → allMirrorsFailed([])
    func test_fetchWithFailover_emptyURLsThrowsAllFailed() async {
        do {
            _ = try await RulesFetcher.fetchWithFailover(
                urls: [], session: MockURLProtocol.makeSession()
            )
            XCTFail("Expected allMirrorsFailed for empty URLs")
        } catch let err as RulesFetcher.FetchError {
            XCTAssertEqual(err, .allMirrorsFailed([]))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // Test 7 — first mirror 503, second mirror 200 → returns from mirror #2
    func test_fetchWithFailover_succeedsOnSecondMirror() async throws {
        let mirror1 = URL(string: "https://primary.example.com/rules-manifest.json")!
        let mirror2 = URL(string: "https://mirror-eu.example.com/rules-manifest.json")!
        let mirror3 = URL(string: "https://mirror-asia.example.com/rules-manifest.json")!
        let payload = Data(#"{"version":42}"#.utf8)

        MockURLProtocol.urlResponder[mirror1.absoluteString] = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (Data(), resp)
        }
        MockURLProtocol.urlResponder[mirror2.absoluteString] = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (payload, resp)
        }
        // mirror3 will not be tried because mirror2 succeeded.
        MockURLProtocol.urlResponder[mirror3.absoluteString] = { req in
            XCTFail("mirror3 must NOT be tried after mirror2 success")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        }

        let result = try await RulesFetcher.fetchWithFailover(
            urls: [mirror1, mirror2, mirror3], session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(result.body, payload)
        XCTAssertEqual(result.mirrorURL, mirror2)

        // Sequential order verified: mirror1 then mirror2, NOT mirror3.
        XCTAssertEqual(MockURLProtocol.requestedURLs.count, 2)
        XCTAssertEqual(MockURLProtocol.requestedURLs[0], mirror1)
        XCTAssertEqual(MockURLProtocol.requestedURLs[1], mirror2)
    }

    // Test 8 — all 3 mirrors fail → allMirrorsFailed with 3 errors in order
    func test_fetchWithFailover_throwsAllFailedWhenAllMirrorsDown() async {
        let mirrors = [
            URL(string: "https://m1.example.com/r")!,
            URL(string: "https://m2.example.com/r")!,
            URL(string: "https://m3.example.com/r")!,
        ]
        // Every mirror returns 500.
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (Data(), resp)
        }

        do {
            _ = try await RulesFetcher.fetchWithFailover(
                urls: mirrors, session: MockURLProtocol.makeSession()
            )
            XCTFail("Expected allMirrorsFailed when every mirror returns 500")
        } catch let err as RulesFetcher.FetchError {
            if case .allMirrorsFailed(let errs) = err {
                XCTAssertEqual(errs.count, 3, "must collect error from each mirror")
                XCTAssertEqual(errs[0], .httpStatusError(500))
                XCTAssertEqual(errs[1], .httpStatusError(500))
                XCTAssertEqual(errs[2], .httpStatusError(500))
            } else {
                XCTFail("Expected allMirrorsFailed, got \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // Sequential proof: 3 requests in mirror-list order.
        XCTAssertEqual(MockURLProtocol.requestedURLs, mirrors)
    }

    // Test 9 — mirror with non-HTTPS scheme aggregated correctly
    func test_fetchWithFailover_aggregatesMixedErrors() async {
        let httpURL = URL(string: "http://m1.example.com/r")!   // nonHTTPS
        let blockedURL = URL(string: "https://127.0.0.1/r")!    // blockedHost
        let ok = URL(string: "https://m3.example.com/r")!
        let payload = Data("ok".utf8)

        MockURLProtocol.urlResponder[ok.absoluteString] = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (payload, resp)
        }

        let result = try? await RulesFetcher.fetchWithFailover(
            urls: [httpURL, blockedURL, ok], session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(result?.body, payload)
        XCTAssertEqual(result?.mirrorURL, ok)

        // The first two mirrors failed *pre-flight* (no network call), so requestedURLs
        // содержит ТОЛЬКО ok (URLProtocol gets invoked only after pre-flight passes).
        XCTAssertEqual(MockURLProtocol.requestedURLs, [ok])
    }

    // MARK: RulesManifest decode integration sanity (cheap addition)

    // Test 10 — RulesManifest decodes minimal payload без CategoryBodies
    func test_rulesManifest_decodesMinimalPayload() throws {
        let json = """
        {
          "version": 1,
          "min_app_version": "0.8.0",
          "srs_format_version": 4,
          "total_size_bytes": 100,
          "files": [
            {"name": "bbtb-block.srs", "sha256": "abc", "sig_path": "bbtb-block.srs.sig", "category": "block_completely"}
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(RulesManifest.self, from: json)
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.minAppVersion, "0.8.0")
        XCTAssertEqual(manifest.srsFormatVersion, 4)
        XCTAssertEqual(manifest.totalSizeBytes, 100)
        XCTAssertEqual(manifest.files.count, 1)
        XCTAssertEqual(manifest.files[0].name, "bbtb-block.srs")
        XCTAssertEqual(manifest.files[0].sigPath, "bbtb-block.srs.sig")
        XCTAssertEqual(manifest.files[0].category, .block)
        XCTAssertNil(manifest.blockCompletely)
        XCTAssertNil(manifest.neverThroughVpn)
        XCTAssertNil(manifest.alwaysThroughVpn)
    }

    // Test 11 — RulesManifest decodes rich payload with CategoryBodies + ip_cidrs CodingKey
    func test_rulesManifest_decodesRichPayload() throws {
        let json = """
        {
          "version": 7,
          "min_app_version": "0.8.1",
          "srs_format_version": 4,
          "total_size_bytes": 2048,
          "files": [],
          "block_completely": {
            "domains": ["max.ru", "mssgr.tatar.ru"],
            "ip_cidrs": ["192.0.2.0/24"],
            "countries": []
          },
          "never_through_vpn": {
            "domains": ["sberbank.ru"]
          },
          "always_through_vpn": {}
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(RulesManifest.self, from: json)
        XCTAssertEqual(manifest.version, 7)
        XCTAssertEqual(manifest.blockCompletely?.domains, ["max.ru", "mssgr.tatar.ru"])
        XCTAssertEqual(manifest.blockCompletely?.ipCidrs, ["192.0.2.0/24"])
        XCTAssertEqual(manifest.blockCompletely?.countries, [])
        XCTAssertEqual(manifest.neverThroughVpn?.domains, ["sberbank.ru"])
        XCTAssertNil(manifest.neverThroughVpn?.ipCidrs)
        XCTAssertNotNil(manifest.alwaysThroughVpn)
        XCTAssertNil(manifest.alwaysThroughVpn?.domains)
    }
}
