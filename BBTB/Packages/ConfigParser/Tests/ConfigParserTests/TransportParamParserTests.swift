import XCTest
@testable import ConfigParser
import VPNCore

/// Phase 5 Wave 0 / Task 3 — coverage for TransportParamParser (D-08, D-09, D-10, Pitfall 10).
final class TransportParamParserTests: XCTestCase {

    // MARK: - TCP default branches (D-10 + Example 3 line 792)

    func test_tcpDefault_emptyDict() throws {
        XCTAssertEqual(try TransportParamParser.parse(query: [:]), .tcp)
    }

    func test_tcpDefault_explicit() throws {
        XCTAssertEqual(try TransportParamParser.parse(query: ["type": "tcp"]), .tcp)
    }

    func test_rawAlias_returnsTcp() throws {
        // D-10 + Pitfall 10: type=raw — alias для tcp (v2rayNG legacy).
        XCTAssertEqual(try TransportParamParser.parse(query: ["type": "raw"]), .tcp)
    }

    func test_emptyTypeString_returnsTcp() throws {
        XCTAssertEqual(try TransportParamParser.parse(query: ["type": ""]), .tcp)
    }

    // MARK: - WS

    func test_ws_full() throws {
        let r = try TransportParamParser.parse(query: [
            "type": "ws",
            "path": "/buy",
            "host": "cdn.example",
        ])
        XCTAssertEqual(r, .ws(path: "/buy", host: "cdn.example"))
    }

    func test_ws_missingPath_throws() {
        XCTAssertThrowsError(try TransportParamParser.parse(query: ["type": "ws", "host": "h"])) { error in
            if case TransportParamParser.ParserError.wsMissingPath = error { /* OK */ } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_ws_emptyPath_throws() {
        XCTAssertThrowsError(try TransportParamParser.parse(query: ["type": "ws", "path": ""])) { error in
            if case TransportParamParser.ParserError.wsMissingPath = error { /* OK */ } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_ws_defaultHost() throws {
        // host отсутствует → host = "" (caller substitutes SNI later).
        let r = try TransportParamParser.parse(query: ["type": "ws", "path": "/x"])
        XCTAssertEqual(r, .ws(path: "/x", host: ""))
    }

    // MARK: - gRPC

    func test_grpc_full() throws {
        XCTAssertEqual(
            try TransportParamParser.parse(query: ["type": "grpc", "serviceName": "tunsvc"]),
            .grpc(serviceName: "tunsvc")
        )
    }

    func test_grpc_defaultServiceName() throws {
        // Default per Open Question 5 recommendation.
        XCTAssertEqual(
            try TransportParamParser.parse(query: ["type": "grpc"]),
            .grpc(serviceName: "TunService")
        )
    }

    // MARK: - HTTP / h2

    func test_http_full() throws {
        XCTAssertEqual(
            try TransportParamParser.parse(query: ["type": "http", "path": "/api"]),
            .http(path: "/api")
        )
    }

    func test_h2Alias_returnsHttp() throws {
        // h2 — alias для http.
        XCTAssertEqual(
            try TransportParamParser.parse(query: ["type": "h2", "path": "/api"]),
            .http(path: "/api")
        )
    }

    func test_http_missingPath_throws() {
        XCTAssertThrowsError(try TransportParamParser.parse(query: ["type": "http"])) { error in
            if case TransportParamParser.ParserError.httpMissingPath = error { /* OK */ } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - HTTPUpgrade

    func test_httpUpgrade_full() throws {
        XCTAssertEqual(
            try TransportParamParser.parse(query: ["type": "httpupgrade", "path": "/u", "host": "h"]),
            .httpUpgrade(path: "/u", host: "h")
        )
    }

    func test_httpUpgrade_defaultHost() throws {
        XCTAssertEqual(
            try TransportParamParser.parse(query: ["type": "httpupgrade", "path": "/u"]),
            .httpUpgrade(path: "/u", host: "")
        )
    }

    func test_httpUpgrade_missingPath_throws() {
        XCTAssertThrowsError(try TransportParamParser.parse(query: ["type": "httpupgrade"])) { error in
            if case TransportParamParser.ParserError.httpUpgradeMissingPath = error { /* OK */ } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Unsupported types

    func test_unsupported_quic_throws() {
        XCTAssertThrowsError(try TransportParamParser.parse(query: ["type": "quic"])) { error in
            if case TransportParamParser.ParserError.unsupportedType(let raw) = error {
                XCTAssertEqual(raw, "quic")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_unsupported_kcp_throws() {
        XCTAssertThrowsError(try TransportParamParser.parse(query: ["type": "kcp"])) { error in
            if case TransportParamParser.ParserError.unsupportedType(let raw) = error {
                XCTAssertEqual(raw, "kcp")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_unsupported_xhttp_throws() {
        // XHTTP deferred to backlog (sing-box upstream missing) per CONTEXT §Deferred.
        XCTAssertThrowsError(try TransportParamParser.parse(query: ["type": "xhttp"])) { error in
            if case TransportParamParser.ParserError.unsupportedType(let raw) = error {
                XCTAssertEqual(raw, "xhttp")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Case insensitivity + unknown params tolerance

    func test_caseInsensitive_type() throws {
        // Per Example 3 line 790: `.lowercased()` на typeRaw.
        XCTAssertEqual(
            try TransportParamParser.parse(query: ["type": "WS", "path": "/x"]),
            .ws(path: "/x", host: "")
        )
    }

    func test_unrelatedParams_ignored() throws {
        // Security pattern: unknown params silently ignored.
        let r = try TransportParamParser.parse(query: [
            "type": "ws",
            "path": "/x",
            "alpn": "h2,http/1.1",
            "security": "tls",
            "unknown": "x",
        ])
        XCTAssertEqual(r, .ws(path: "/x", host: ""))
    }

    // MARK: - Integration: real user fixture (backward-compat smoke per Phase 2)

    func test_realUserFixture_trojanWS_query_parses_correctly() throws {
        // trojan-ws-user-fixture.txt — Phase 2 real-user URI с type=ws+path+sni+fp.
        guard let url = Bundle.module.url(forResource: "trojan-ws-user-fixture", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Fixture trojan-ws-user-fixture.txt not found in test bundle")
            return
        }
        let uri = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: uri) else {
            XCTFail("Failed to parse fixture URI")
            return
        }
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }
        let r = try TransportParamParser.parse(query: q)
        // Fixture: type=ws, path=/ba0ca9ffa1d4, no host → host == "" (caller fills SNI).
        XCTAssertEqual(r, .ws(path: "/ba0ca9ffa1d4", host: ""))
    }
}
