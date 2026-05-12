import XCTest
@testable import TransportRegistry
import VPNCore

/// Phase 5 Wave 0 / Task 2 — coverage for TCPTransportHandler (Pitfall 2: TCP=no overlay).
final class TCPTransportHandlerTests: XCTestCase {

    func test_identifier_isTcp() {
        XCTAssertEqual(TCPTransportHandler.identifier, "tcp")
    }

    func test_displayName_isTCPLiteral() {
        XCTAssertEqual(TCPTransportHandler.displayName, "TCP")
    }

    func test_supportedProtocols_includesAll5() {
        let expected: Set<String> = [
            "vless-tls",
            "trojan",
            "vless-reality",
            "shadowsocks",
            "hysteria2",
        ]
        XCTAssertEqual(Set(TCPTransportHandler.supportedProtocols), expected)
    }

    func test_buildTransportBlock_alwaysReturnsNil_forAllCases() {
        // Pitfall 2: sing-box не имеет transport "tcp" — отсутствие поля = TCP.
        // TCPTransportHandler возвращает nil для всех 5 кейсов (defensive).
        let cases: [TransportConfig] = [
            .tcp,
            .ws(path: "/p", host: "h"),
            .grpc(serviceName: "s"),
            .http(path: "/p"),
            .httpUpgrade(path: "/p", host: "h"),
        ]
        for c in cases {
            XCTAssertNil(TCPTransportHandler.buildTransportBlock(for: c),
                         "TCPTransportHandler must return nil for \(c)")
        }
    }
}
