import XCTest
@testable import TransportRegistry
import VPNCore

/// Phase 5 Wave 1 / Task 1 — `WSTransportHandler` coverage.
///
/// Контракт (см. 05-02-PLAN.md <interfaces> и 05-RESEARCH.md Example 4):
/// - identifier = `"ws"`
/// - displayName = `"WebSocket"`
/// - supportedProtocols = `["vless-tls", "trojan"]` (D-03: Reality НЕ в списке —
///   XTLS Vision несовместим с WS overlay)
/// - `buildTransportBlock(for: .ws(path, host))`:
///   * non-empty host → `["type": "ws", "path": path, "headers": ["Host": host]]`
///   * empty host     → `["type": "ws", "path": path]` (headers ключ ОПУЩЕН — caller
///     подставит SNI на этапе сборки outbound JSON)
/// - Все non-ws cases (`.tcp`, `.grpc`, `.http`, `.httpUpgrade`) → `nil` (defensive).
final class WSTransportHandlerTests: XCTestCase {

    func test_identifier_isWs() {
        XCTAssertEqual(WSTransportHandler.identifier, "ws")
    }

    func test_displayName_isWebSocket() {
        XCTAssertEqual(WSTransportHandler.displayName, "WebSocket")
    }

    func test_supportedProtocols_isVlessTlsAndTrojan() {
        // D-03 — Reality исключён намеренно (XTLS Vision несовместим с WS).
        XCTAssertEqual(Set(WSTransportHandler.supportedProtocols),
                       Set(["vless-tls", "trojan"]))
    }

    /// Example 4 (05-RESEARCH.md lines 829-842) — full WS block с непустым Host header.
    func test_buildTransportBlock_full() throws {
        let cfg: TransportConfig = .ws(path: "/buy", host: "cdn.example")
        let block = try XCTUnwrap(WSTransportHandler.buildTransportBlock(for: cfg),
                                  "WS handler must return non-nil for .ws case")
        XCTAssertEqual(block["type"] as? String, "ws")
        XCTAssertEqual(block["path"] as? String, "/buy")
        let headers = try XCTUnwrap(block["headers"] as? [String: String],
                                    "headers ключ должен присутствовать когда host не пуст")
        XCTAssertEqual(headers["Host"], "cdn.example")
    }

    /// Example 4 invariant: пустой host → headers ключ ОПУЩЕН целиком
    /// (caller-protocol подставит SNI как Host на этапе сборки sing-box JSON).
    func test_buildTransportBlock_emptyHost_omitsHeaders() throws {
        let cfg: TransportConfig = .ws(path: "/x", host: "")
        let block = try XCTUnwrap(WSTransportHandler.buildTransportBlock(for: cfg))
        XCTAssertEqual(block["type"] as? String, "ws")
        XCTAssertEqual(block["path"] as? String, "/x")
        XCTAssertNil(block["headers"],
                     "headers ключ должен ОТСУТСТВОВАТЬ при empty host")
        XCTAssertFalse(block.keys.contains("headers"),
                       "block.keys не должен содержать 'headers' при empty host")
    }

    /// Defensive: WS handler возвращает nil для всех non-ws cases.
    func test_buildTransportBlock_nonWsConfig_returnsNil() {
        let cases: [TransportConfig] = [
            .tcp,
            .grpc(serviceName: "s"),
            .http(path: "/p"),
            .httpUpgrade(path: "/p", host: "h"),
        ]
        for c in cases {
            XCTAssertNil(WSTransportHandler.buildTransportBlock(for: c),
                         "WSTransportHandler должен вернуть nil для \(c)")
        }
    }
}
