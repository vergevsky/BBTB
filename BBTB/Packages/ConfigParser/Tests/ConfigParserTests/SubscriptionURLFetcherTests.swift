import XCTest
@testable import ConfigParser

/// Mock URLProtocol injected into URLSessionConfiguration for offline testing.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
            return
        }
        let (data, response) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SubscriptionURLFetcherTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func loadFixture(_ name: String, ext: String) -> Data {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        else {
            XCTFail("Fixture missing: \(name).\(ext)")
            return Data()
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.responder = nil
        MockURLProtocol.lastRequest = nil
    }

    // MARK: Test 1 — User-Agent + Accept headers

    func test_fetch_sendsCorrectHeaders() async throws {
        let url = URL(string: "https://example.com/sub")!
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data(), resp)
        }
        _ = try await SubscriptionURLFetcher.fetch(url: url, session: makeSession())
        let headers = MockURLProtocol.lastRequest?.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["User-Agent"], "BBTB/0.2 (iOS / macOS)")
        XCTAssertTrue(headers["Accept"]?.contains("text/plain") ?? false)
    }

    // MARK: Test 2 — http:// reject

    func test_fetch_httpURL_throws() async {
        let url = URL(string: "http://example.com/sub")!
        do {
            _ = try await SubscriptionURLFetcher.fetch(url: url, session: makeSession())
            XCTFail("Expected nonHTTPS")
        } catch let err as SubscriptionURLFetcher.FetchError {
            XCTAssertEqual(err, .nonHTTPS("http"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: Test 3 — HTTP 404 error

    func test_fetch_httpError_throws() async {
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data(), resp)
        }
        let url = URL(string: "https://example.com/sub")!
        do {
            _ = try await SubscriptionURLFetcher.fetch(url: url, session: makeSession())
            XCTFail("Expected httpStatusError")
        } catch let err as SubscriptionURLFetcher.FetchError {
            XCTAssertEqual(err, .httpStatusError(404))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: Test 4 — successful fetch returns body+metadata

    func test_fetch_returnsBodyAndMetadata() async throws {
        let body = "vless://x@host:443?security=reality".data(using: .utf8)!
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (body, resp)
        }
        let url = URL(string: "https://example.com/sub")!
        let result = try await SubscriptionURLFetcher.fetch(url: url, session: makeSession())
        XCTAssertEqual(result.body, body)
        XCTAssertEqual(result.finalURL, url)
    }

    // MARK: Test 5 — Profile-Title header

    func test_fetch_extractsProfileTitleHeader() async throws {
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Profile-Title": "MyPool"])!
            return (Data(), resp)
        }
        let url = URL(string: "https://example.com/sub")!
        let result = try await SubscriptionURLFetcher.fetch(url: url, session: makeSession())
        XCTAssertEqual(result.metadata.title, "MyPool")
    }

    // MARK: Test 6 — detectFormat base64

    func test_detectFormat_base64URIList() {
        let body = loadFixture("sub-base64-response", ext: "txt")
        let format = SubscriptionURLFetcher.detectFormat(body: body)
        XCTAssertEqual(format, .base64URIList)
    }

    // MARK: Test 7 — detectFormat plain-text

    func test_detectFormat_plainTextURIList() {
        let body = loadFixture("sub-plaintext-response", ext: "txt")
        let format = SubscriptionURLFetcher.detectFormat(body: body)
        XCTAssertEqual(format, .plainTextURIList)
    }

    // MARK: Test 8 — detectFormat sing-box JSON

    func test_detectFormat_singBoxJSON() {
        let body = loadFixture("sub-json-response", ext: "json")
        let format = SubscriptionURLFetcher.detectFormat(body: body)
        XCTAssertEqual(format, .singBoxJSON)
    }

    // MARK: Test 9 — detectFormat v2ray JSON

    func test_detectFormat_v2rayJSON() {
        let v2ray = """
        {"outbounds":[{"protocol":"vless","settings":{"servers":[]}}]}
        """.data(using: .utf8)!
        let format = SubscriptionURLFetcher.detectFormat(body: v2ray)
        if case .v2rayJSON = format {
            // OK
        } else {
            XCTFail("Expected .v2rayJSON, got \(format)")
        }
    }

    // MARK: Test 10 — garbage → unknown

    func test_detectFormat_garbage() {
        let body = "hello world this is not a config".data(using: .utf8)!
        let format = SubscriptionURLFetcher.detectFormat(body: body)
        if case .unknown = format {
            // OK
        } else {
            XCTFail("Expected .unknown, got \(format)")
        }
    }

    // MARK: - CR-03 SSRF Blocklist (T-03-06)

    /// Helper: assert fetch throws blockedHost для заданного URL.
    /// Не настраиваем MockURLProtocol — throw происходит ДО session.data.
    private func assertBlocked(_ urlString: String,
                                file: StaticString = #file,
                                line: UInt = #line) async {
        guard let url = URL(string: urlString) else {
            XCTFail("malformed url: \(urlString)", file: file, line: line)
            return
        }
        do {
            _ = try await SubscriptionURLFetcher.fetch(url: url, session: makeSession())
            XCTFail("Expected FetchError.blockedHost for \(urlString)", file: file, line: line)
        } catch let err as SubscriptionURLFetcher.FetchError {
            if case .blockedHost = err {
                // OK
            } else {
                XCTFail("Expected .blockedHost, got \(err) for \(urlString)", file: file, line: line)
            }
        } catch {
            XCTFail("Wrong error type \(type(of: error)): \(error) for \(urlString)", file: file, line: line)
        }
    }

    func test_fetch_rejects_localhost() async {
        await assertBlocked("https://localhost/sub")
    }

    func test_fetch_rejects_loopback_ipv4() async {
        await assertBlocked("https://127.0.0.1/sub")
        await assertBlocked("https://127.5.6.7/x")
    }

    func test_fetch_rejects_loopback_ipv6() async {
        await assertBlocked("https://[::1]/sub")
    }

    func test_fetch_rejects_link_local_v4() async {
        // AWS / IMDS metadata service
        await assertBlocked("https://169.254.169.254/latest/meta-data/")
    }

    func test_fetch_rejects_rfc1918_10() async {
        await assertBlocked("https://10.0.0.1/")
    }

    func test_fetch_rejects_rfc1918_172() async {
        await assertBlocked("https://172.16.0.1/")
        await assertBlocked("https://172.31.255.254/")

        // 172.32.0.1 НЕ в RFC-1918 (16..31 only) — должен пройти blocklist guard,
        // настроим mock responder чтобы не уйти в реальную сеть.
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data(), resp)
        }
        let allowedURL = URL(string: "https://172.32.0.1/")!
        do {
            _ = try await SubscriptionURLFetcher.fetch(url: allowedURL, session: makeSession())
            // OK — passed blocklist guard.
        } catch let err as SubscriptionURLFetcher.FetchError {
            if case .blockedHost = err {
                XCTFail("172.32.0.1 should NOT be blocked (outside RFC-1918 172.16/12)")
            }
            // Любая другая FetchError (например network) — допустима, нам только важно
            // что НЕ blockedHost.
        } catch {
            // network errors допустимы — guard не сработал, значит passed.
        }
    }

    func test_fetch_rejects_rfc1918_192_168() async {
        await assertBlocked("https://192.168.1.1/")
    }

    func test_fetch_rejects_link_local_v6() async {
        await assertBlocked("https://[fe80::1]/")
    }

    func test_fetch_rejects_unique_local_v6() async {
        await assertBlocked("https://[fc00::1]/")
        await assertBlocked("https://[fd00::1]/")
    }

    func test_fetch_accepts_public_host() async throws {
        // Public host НЕ в blocklist → fetch проходит до session (MockURLProtocol).
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data("ok".utf8), resp)
        }
        let url = URL(string: "https://example.com/sub")!
        let result = try await SubscriptionURLFetcher.fetch(url: url, session: makeSession())
        XCTAssertEqual(result.body, Data("ok".utf8))
    }
}
