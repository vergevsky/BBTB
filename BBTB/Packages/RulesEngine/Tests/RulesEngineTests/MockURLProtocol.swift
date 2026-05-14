import Foundation
import XCTest

/// Mock URLProtocol для injection в URLSessionConfiguration.ephemeral.
///
/// **Pattern source:** ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift
/// (Phase 2-3 audited). Phase 8 W1.4 adapts тот же recipe — copy-paste из-за того что
/// cross-package test-helper reuse не возможен (test targets изолированы).
///
/// **Usage:**
/// ```swift
/// let session = MockURLProtocol.makeSession()
/// MockURLProtocol.responder = { req in
///     let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
///                                 httpVersion: "HTTP/1.1", headerFields: nil)!
///     return (Data(), resp)
/// }
/// // ... call RulesFetcher.fetch(url:session:session)
/// ```
///
/// **Per-URL routing** через `urlResponder` dictionary — для mirror-failover tests where
/// different URLs need different responses. `responder` (single-URL form) — common case.
///
/// **nonisolated(unsafe)** acceptable in test context — tests serialize мутации через
/// `setUp()`/`tearDown()`; production code никогда не touches MockURLProtocol.
final class MockURLProtocol: URLProtocol {

    /// Default responder — fires for every URL when set.
    nonisolated(unsafe) static var responder: ((URLRequest) -> (Data, HTTPURLResponse))?

    /// Per-URL responder map — `responder` checked first if matching URL key exists.
    /// String key = `url.absoluteString` exact match.
    nonisolated(unsafe) static var urlResponder: [String: (URLRequest) -> (Data, HTTPURLResponse)] = [:]

    /// Most-recent intercepted request (for assertions about headers / URL).
    nonisolated(unsafe) static var lastRequest: URLRequest?

    /// Ordered list of all intercepted request URLs (for failover-order assertions).
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    /// Optional error to throw instead of returning a response (for timeout / network-failure tests).
    nonisolated(unsafe) static var injectedError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let url = request.url {
            Self.requestedURLs.append(url)
        }

        if let err = Self.injectedError {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }

        // 1. Check per-URL responder first.
        if let url = request.url?.absoluteString,
           let perURL = Self.urlResponder[url] {
            let (data, response) = perURL(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // 2. Fall back to global responder.
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockURLProtocol", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "no responder configured for \(request.url?.absoluteString ?? "<nil>")"]
            ))
            return
        }
        let (data, response) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { /* no-op */ }

    /// Reset all static state — call from XCTestCase.setUp() to avoid cross-test pollution.
    static func reset() {
        responder = nil
        urlResponder = [:]
        lastRequest = nil
        requestedURLs = []
        injectedError = nil
    }

    /// Construct ephemeral URLSession with this MockURLProtocol registered.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
