import XCTest
@testable import TransportRegistry
import VPNCore

/// Phase 5 Wave 2 / Plan 05-03 — `HTTPTransportHandler` coverage.
///
/// Контракт (см. 05-03-PLAN.md <interfaces>, 05-RESEARCH.md Example 2
/// + Pitfall 7 host-as-array invariant):
/// - identifier = `"http"` (соответствует `TransportConfig.http.identifier`)
/// - displayName = `"HTTP/2"`
/// - supportedProtocols = `["vless-tls", "trojan"]` (D-03 Reality исключён,
///   XTLS Vision несовместим с HTTP transport overlay)
/// - `buildTransportBlock(for: .http(path))` → `["type": "http", "path": path]`
///   (exactly 2 keys; host ключ ОПУЩЕН — sing-box подставляет TLS server_name
///   как `:authority`; explicit multi-host array — future work, не в Phase 5)
/// - Все non-http cases (`.tcp`, `.ws`, `.grpc`, `.httpUpgrade`) → `nil` (defensive).
final class HTTPTransportHandlerTests: XCTestCase {

    // MARK: Identity

    func test_identifier_isHttp() {
        XCTAssertEqual(HTTPTransportHandler.identifier, "http")
    }

    func test_displayName_isHTTP2Literal() {
        XCTAssertEqual(HTTPTransportHandler.displayName, "HTTP/2")
    }

    func test_supportedProtocols_isVlessTlsAndTrojan() {
        // D-03 — Reality исключён намеренно (XTLS Vision несовместим с HTTP overlay).
        XCTAssertEqual(Set(HTTPTransportHandler.supportedProtocols),
                       Set(["vless-tls", "trojan"]))
    }

    // MARK: buildTransportBlock — happy path

    /// Example 2 (05-RESEARCH.md lines 728-740) — HTTP transport блок состоит
    /// ровно из 2 ключей: `type` и `path`. Host НЕ emit'ится handler-ом
    /// (sing-box подставляет tls.server_name).
    func test_buildTransportBlock_http_returnsTypePathOnly() throws {
        let cfg: TransportConfig = .http(path: "/api")
        let block = try XCTUnwrap(HTTPTransportHandler.buildTransportBlock(for: cfg),
                                  "HTTP handler must return non-nil for .http case")
        XCTAssertEqual(block["type"] as? String, "http")
        XCTAssertEqual(block["path"] as? String, "/api")
        XCTAssertEqual(block.count, 2,
                       "HTTP block должен содержать ровно 2 ключа (type, path); host omitted (Pitfall 7)")
        XCTAssertFalse(block.keys.contains("host"),
                       "host ключ должен быть ОПУЩЕН — sing-box подставит tls.server_name")
        XCTAssertFalse(block.keys.contains("headers"),
                       "headers ключ для HTTP overlay не emit'ится")
    }

    /// Root path `/` — типичный для V2Ray HTTP transport URI; assertion на
    /// корректное прохождение через handler.
    func test_buildTransportBlock_rootPath() throws {
        let cfg: TransportConfig = .http(path: "/")
        let block = try XCTUnwrap(HTTPTransportHandler.buildTransportBlock(for: cfg))
        XCTAssertEqual(block["type"] as? String, "http")
        XCTAssertEqual(block["path"] as? String, "/")
    }

    // MARK: buildTransportBlock — defensive nil для non-http cases

    func test_buildTransportBlock_tcpReturnsNil() {
        XCTAssertNil(HTTPTransportHandler.buildTransportBlock(for: .tcp),
                     "HTTP handler должен вернуть nil для .tcp")
    }

    func test_buildTransportBlock_wsReturnsNil() {
        XCTAssertNil(HTTPTransportHandler.buildTransportBlock(for:
                        .ws(path: "/x", host: "h.com")),
                     "HTTP handler должен вернуть nil для .ws")
    }

    func test_buildTransportBlock_grpcReturnsNil() {
        XCTAssertNil(HTTPTransportHandler.buildTransportBlock(for:
                        .grpc(serviceName: "TunService")),
                     "HTTP handler должен вернуть nil для .grpc")
    }

    func test_buildTransportBlock_httpUpgradeReturnsNil() {
        XCTAssertNil(HTTPTransportHandler.buildTransportBlock(for:
                        .httpUpgrade(path: "/upg", host: "h.com")),
                     "HTTP handler должен вернуть nil для .httpUpgrade")
    }
}
