import XCTest
@testable import VLESSTLS
import VPNCore
import TransportRegistry

/// Phase 5 Wave 7 — BuildOutbound tests for VLESSTLS.ConfigBuilder.buildOutbound.
///
/// Tests cover:
/// - TCP transport (no transport block)
/// - WS transport (transport block with path + headers)
/// - ALPN h2-strip for WS (Phase 2 W4 invariant)
/// - gRPC transport (service_name snake_case)
/// - HTTP transport
/// - HTTPUpgrade transport
/// - R1 invariant (insecure: false for all transports)
/// - UUID lowercased
/// - flow = "" when nil
final class BuildOutboundTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // Register all 5 transport handlers before any test.
        // Production bootstrap (BBTB_iOSApp / BBTB_macOSApp) registers all 5.
        TransportRegistry.shared.register(TCPTransportHandler.self)
        TransportRegistry.shared.register(WSTransportHandler.self)
        TransportRegistry.shared.register(HTTPTransportHandler.self)
        TransportRegistry.shared.register(HTTPUpgradeTransportHandler.self)
        TransportRegistry.shared.register(GRPCTransportHandler.self)
    }

    private func makeParsed(
        uuid: UUID = UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!,
        host: String = "vpn.example.com",
        port: Int = 443,
        flow: String? = nil,
        sni: String = "vpn.example.com",
        fingerprint: String = "chrome",
        alpn: [String] = ["h2", "http/1.1"],
        transport: TransportConfig = .tcp
    ) -> ParsedVLESSTLS {
        ParsedVLESSTLS(
            uuid: uuid, host: host, port: port,
            flow: flow, sni: sni, fingerprint: fingerprint,
            alpn: alpn, transport: transport, remarks: nil
        )
    }

    // MARK: - TCP transport

    func test_vlessTLS_tcp_outbound_hasNoTransportKey() {
        let parsed = makeParsed(transport: .tcp)
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-tls-0")
        XCTAssertNil(result["transport"], "TCP transport must not add a 'transport' key")
        XCTAssertEqual(result["type"] as? String, "vless")
        XCTAssertEqual(result["tag"] as? String, "vless-tls-0")
    }

    // MARK: - WS transport

    func test_vlessTLS_ws_outbound_hasWsTransportBlock() {
        let parsed = makeParsed()
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .ws(path: "/buy", host: "cdn.example.com"), tag: "vless-tls-1")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key in result")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/buy")
        guard let headers = transport["headers"] as? [String: String] else {
            XCTFail("Expected 'headers' in transport block")
            return
        }
        XCTAssertEqual(headers["Host"], "cdn.example.com")
    }

    // MARK: - ALPN h2-strip

    func test_vlessTLS_ws_alpn_excludes_h2() {
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

    func test_vlessTLS_ws_alpn_emptyAfterFilter_fallbackToHttp1() {
        let parsed = makeParsed(alpn: ["h2"])
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .ws(path: "/", host: "cdn.example.com"), tag: "t")
        guard let tls = result["tls"] as? [String: Any],
              let alpn = tls["alpn"] as? [String] else {
            XCTFail("Expected tls.alpn in result")
            return
        }
        XCTAssertEqual(alpn, ["http/1.1"], "When all ALPN entries are stripped, fallback to [\"http/1.1\"]")
    }

    func test_vlessTLS_tcp_alpn_not_stripped() {
        let parsed = makeParsed(alpn: ["h2", "http/1.1"])
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "t")
        guard let tls = result["tls"] as? [String: Any],
              let alpn = tls["alpn"] as? [String] else {
            XCTFail("Expected tls.alpn in result")
            return
        }
        // TCP: ALPN h2-strip must NOT apply
        XCTAssertTrue(alpn.contains("h2"), "TCP transport must NOT strip 'h2' from ALPN")
    }

    // MARK: - gRPC transport

    func test_vlessTLS_grpc_outbound_hasGrpcBlock() {
        let parsed = makeParsed()
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .grpc(serviceName: "TunService"), tag: "t")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key for gRPC")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "grpc")
        XCTAssertEqual(transport["service_name"] as? String, "TunService", "gRPC must use snake_case 'service_name'")
        XCTAssertNil(transport["serviceName"], "gRPC must NOT use camelCase 'serviceName'")
    }

    // MARK: - HTTP transport

    func test_vlessTLS_http_outbound_hasHttpBlock() {
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

    func test_vlessTLS_httpUpgrade_outbound_hasHttpUpgradeBlock() {
        let parsed = makeParsed()
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .httpUpgrade(path: "/u", host: "cdn.example.com"), tag: "t")
        guard let transport = result["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' key for HTTPUpgrade")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "httpupgrade")
        // HTTPUpgrade host is a String (not array — per WSTransportHandler vs HTTPHandler distinction)
        XCTAssertEqual(transport["host"] as? String, "cdn.example.com")
    }

    // MARK: - R1 invariant

    func test_vlessTLS_R1_insecure_false_invariant() {
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
                           "R1 invariant: insecure must always be false for VLESS+TLS (transport: \(transport))")
        }
    }

    // MARK: - UUID lowercased

    func test_vlessTLS_uuid_lowercased() {
        let uuid = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        let parsed = makeParsed(uuid: uuid)
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "t")
        let uuidStr = result["uuid"] as? String
        XCTAssertEqual(uuidStr, "550e8400-e29b-41d4-a716-446655440000", "UUID must be lowercased")
    }

    // MARK: - flow nil → empty string

    func test_vlessTLS_flow_emptyString_when_nil() {
        let parsed = makeParsed(flow: nil)
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "t")
        XCTAssertEqual(result["flow"] as? String, "", "nil flow must produce empty string")
    }

    func test_vlessTLS_flow_passthrough_when_set() {
        let parsed = makeParsed(flow: "xtls-rprx-vision")
        let result = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "t")
        XCTAssertEqual(result["flow"] as? String, "xtls-rprx-vision")
    }
}
