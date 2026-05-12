import XCTest
@testable import Trojan
import VPNCore
import TransportRegistry

/// Phase 5 Wave 7 — BuildOutbound tests for Trojan.ConfigBuilder.buildOutbound.
///
/// Tests cover:
/// - TCP transport (no transport block)
/// - WS transport (transport block with path + headers)
/// - WS with empty host (SNI fallback — Phase 2 backward-compat invariant)
/// - ALPN h2-strip for WS (Phase 2 W4 invariant)
/// - gRPC transport
/// - HTTP transport
/// - HTTPUpgrade transport
/// - R1 invariant (insecure: false for all transports)
final class BuildOutboundTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // Register all 5 transport handlers before any test.
        TransportRegistry.shared.register(TCPTransportHandler.self)
        TransportRegistry.shared.register(WSTransportHandler.self)
        TransportRegistry.shared.register(HTTPTransportHandler.self)
        TransportRegistry.shared.register(HTTPUpgradeTransportHandler.self)
        TransportRegistry.shared.register(GRPCTransportHandler.self)
    }

    private func makeParsed(
        password: String = "testpass",
        host: String = "trojan.example.com",
        port: Int = 443,
        sni: String = "trojan.example.com",
        fingerprint: String = "chrome",
        alpn: [String] = ["h2", "http/1.1"],
        transport: TransportConfig = .tcp
    ) -> ParsedTrojan {
        ParsedTrojan(
            password: password, host: host, port: port,
            security: "tls", sni: sni, fingerprint: fingerprint,
            alpn: alpn, transport: transport, remarks: nil
        )
    }

    // MARK: - TCP transport

    func test_trojan_tcp_outbound_hasNoTransportKey() {
        let parsed = makeParsed(transport: .tcp)
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "trojan-0")
        XCTAssertNil(result["transport"], "TCP transport must not add a 'transport' key")
        XCTAssertEqual(result["type"] as? String, "trojan")
        XCTAssertEqual(result["tag"] as? String, "trojan-0")
        XCTAssertEqual(result["password"] as? String, "testpass")
    }

    // MARK: - WS transport

    func test_trojan_ws_outbound_hasWsTransportBlock_withCustomHost() {
        let parsed = makeParsed()
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .ws(path: "/proxy", host: "cdn.example.com"), tag: "trojan-1")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key in result")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/proxy")
        guard let headers = transport["headers"] as? [String: String] else {
            XCTFail("Expected 'headers' in transport block")
            return
        }
        XCTAssertEqual(headers["Host"], "cdn.example.com")
    }

    func test_trojan_ws_outbound_emptyHost_usesSNI() {
        let parsed = makeParsed(sni: "sni.example.com")
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .ws(path: "/x", host: ""), tag: "t")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key for empty-host WS")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "ws")
        guard let headers = transport["headers"] as? [String: String] else {
            XCTFail("Expected 'headers' with SNI fallback")
            return
        }
        XCTAssertEqual(headers["Host"], "sni.example.com", "Empty WS host must fallback to SNI (Phase 2 backward-compat)")
    }

    // MARK: - ALPN h2-strip

    func test_trojan_ws_alpn_excludes_h2() {
        let parsed = makeParsed(alpn: ["h2", "http/1.1"])
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .ws(path: "/", host: "cdn.example.com"), tag: "t")
        guard let tls = result["tls"] as? [String: Any],
              let alpn = tls["alpn"] as? [String] else {
            XCTFail("Expected tls.alpn in result")
            return
        }
        XCTAssertFalse(alpn.contains("h2"), "WS transport must strip 'h2' from ALPN (Phase 2 W4 invariant)")
        XCTAssertTrue(alpn.contains("http/1.1"))
    }

    func test_trojan_ws_alpn_emptyAfterFilter_fallbackToHttp1() {
        let parsed = makeParsed(alpn: ["h2"])
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .ws(path: "/", host: "cdn.example.com"), tag: "t")
        guard let tls = result["tls"] as? [String: Any],
              let alpn = tls["alpn"] as? [String] else {
            XCTFail("Expected tls.alpn in result")
            return
        }
        XCTAssertEqual(alpn, ["http/1.1"], "When all ALPN entries are stripped, fallback to [\"http/1.1\"]")
    }

    // MARK: - gRPC transport

    func test_trojan_grpc_outbound_hasGrpcBlock() {
        let parsed = makeParsed()
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .grpc(serviceName: "TunService"), tag: "t")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key for gRPC")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "grpc")
        XCTAssertEqual(transport["service_name"] as? String, "TunService", "gRPC must use snake_case 'service_name'")
    }

    // MARK: - HTTP transport

    func test_trojan_http_outbound() {
        let parsed = makeParsed()
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .http(path: "/api"), tag: "t")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key for HTTP")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "http")
        XCTAssertEqual(transport["path"] as? String, "/api")
    }

    // MARK: - HTTPUpgrade transport

    func test_trojan_httpUpgrade_outbound() {
        let parsed = makeParsed()
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .httpUpgrade(path: "/u", host: "cdn.example.com"), tag: "t")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key for HTTPUpgrade")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "httpupgrade")
        XCTAssertEqual(transport["host"] as? String, "cdn.example.com")
    }

    // MARK: - R1 invariant

    func test_trojan_R1_insecure_false_invariant() {
        let parsed = makeParsed()
        let transports: [TransportConfig] = [
            .tcp,
            .ws(path: "/", host: "cdn.example.com"),
            .grpc(serviceName: "svc"),
            .http(path: "/"),
            .httpUpgrade(path: "/", host: "cdn.example.com"),
        ]
        for transport in transports {
            let result = ConfigBuilder.buildOutbound(from: parsed, transport: transport, tag: "t")
            guard let tls = result["tls"] as? [String: Any] else {
                XCTFail("Expected tls block for transport \(transport)")
                continue
            }
            XCTAssertEqual(tls["insecure"] as? Bool, false,
                           "R1 invariant: insecure must always be false for Trojan (transport: \(transport))")
        }
    }
}
