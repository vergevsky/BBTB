import XCTest
@testable import ConfigParser

final class JSONEndpointFetcherTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.responder = nil
    }

    func test_https_json_returnsData() async throws {
        let body = "{\"outbounds\":[{\"type\":\"vless\"}]}".data(using: .utf8)!
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (body, resp)
        }
        let data = try await JSONEndpointFetcher.fetch(url: URL(string: "https://example.com/json")!,
                                                       session: makeSession())
        XCTAssertEqual(data, body)
    }

    func test_nonJSON_throws() async {
        let body = "vless://x@host:443?security=reality".data(using: .utf8)!
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (body, resp)
        }
        do {
            _ = try await JSONEndpointFetcher.fetch(url: URL(string: "https://example.com/json")!,
                                                    session: makeSession())
            XCTFail("Expected notJSON")
        } catch let err as JSONEndpointFetcher.FetchError {
            if case .notJSON = err { /* OK */ } else { XCTFail("Wrong error: \(err)") }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_httpError_throws() async {
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data(), resp)
        }
        do {
            _ = try await JSONEndpointFetcher.fetch(url: URL(string: "https://example.com/json")!,
                                                    session: makeSession())
            XCTFail("Expected httpStatusError")
        } catch let err as JSONEndpointFetcher.FetchError {
            XCTAssertEqual(err, .httpStatusError(500))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_http_url_throws() async {
        do {
            _ = try await JSONEndpointFetcher.fetch(url: URL(string: "http://example.com/json")!,
                                                    session: makeSession())
            XCTFail("Expected nonHTTPS")
        } catch let err as JSONEndpointFetcher.FetchError {
            XCTAssertEqual(err, .nonHTTPS("http"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
