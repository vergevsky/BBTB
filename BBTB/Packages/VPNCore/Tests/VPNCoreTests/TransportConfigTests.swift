import XCTest
@testable import VPNCore

/// Phase 5 Wave 0 / Task 1 — coverage for shared TransportConfig enum (CORE-03, D-04).
final class TransportConfigTests: XCTestCase {

    // MARK: - identifier mapping (5 cases per D-04 + RESEARCH §Example 1)

    func test_identifier_mapping() {
        XCTAssertEqual(TransportConfig.tcp.identifier, "tcp")
        XCTAssertEqual(TransportConfig.ws(path: "/p", host: "h").identifier, "ws")
        XCTAssertEqual(TransportConfig.grpc(serviceName: "TunService").identifier, "grpc")
        XCTAssertEqual(TransportConfig.http(path: "/p").identifier, "http")
        XCTAssertEqual(TransportConfig.httpUpgrade(path: "/p", host: "h").identifier, "httpupgrade")
    }

    // MARK: - displayName mapping (UI-facing strings, D-04)

    func test_displayName_mapping() {
        XCTAssertEqual(TransportConfig.tcp.displayName, "TCP")
        XCTAssertEqual(TransportConfig.ws(path: "/p", host: "h").displayName, "WebSocket")
        XCTAssertEqual(TransportConfig.grpc(serviceName: "TunService").displayName, "gRPC")
        XCTAssertEqual(TransportConfig.http(path: "/p").displayName, "HTTP/2")
        XCTAssertEqual(TransportConfig.httpUpgrade(path: "/p", host: "h").displayName, "HTTPUpgrade")
    }

    // MARK: - Codable round-trip (synthesized Codable conformance, SE-0295)

    func test_codable_roundtrip() throws {
        let cases: [TransportConfig] = [
            .tcp,
            .ws(path: "/buy", host: "cdn.example"),
            .grpc(serviceName: "tunsvc"),
            .http(path: "/api"),
            .httpUpgrade(path: "/upgrade", host: "example.com"),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(TransportConfig.self, from: data)
            XCTAssertEqual(decoded, original, "Codable round-trip failed for \(original)")
        }
    }

    // MARK: - Equatable considers associated values

    func test_equatable_associated_values_differ() {
        let a = TransportConfig.ws(path: "/a", host: "h")
        let b = TransportConfig.ws(path: "/a", host: "h2")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_associated_values_match() {
        let a = TransportConfig.ws(path: "/a", host: "h")
        let b = TransportConfig.ws(path: "/a", host: "h")
        XCTAssertEqual(a, b)
    }

    // MARK: - Hashable (Set membership)

    func test_hashable_set_membership() {
        let allFive: Set<TransportConfig> = [
            .tcp,
            .ws(path: "/p", host: "h"),
            .grpc(serviceName: "s"),
            .http(path: "/p"),
            .httpUpgrade(path: "/p", host: "h"),
        ]
        XCTAssertEqual(allFive.count, 5)
    }
}
