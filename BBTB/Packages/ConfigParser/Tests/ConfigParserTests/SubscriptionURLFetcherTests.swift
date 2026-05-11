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
}
