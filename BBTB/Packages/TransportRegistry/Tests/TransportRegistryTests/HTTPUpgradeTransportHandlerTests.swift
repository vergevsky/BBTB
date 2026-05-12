import XCTest
@testable import TransportRegistry
import VPNCore

/// Phase 5 Wave 3 / Plan 05-04 — `HTTPUpgradeTransportHandler` coverage.
///
/// Контракт (см. 05-04-PLAN.md <interfaces>, 05-RESEARCH.md Example 2
/// HTTPUpgrade lines 743-752 + Pitfall 7 host-as-STRING invariant):
/// - identifier = `"httpupgrade"` (single token — соответствует
///   `TransportConfig.httpUpgrade.identifier`, без `-` и без `_`)
/// - displayName = `"HTTPUpgrade"`
/// - supportedProtocols = `["vless-tls", "trojan"]` (D-03 Reality исключён,
///   XTLS Vision несовместим с HTTPUpgrade overlay)
/// - `buildTransportBlock(for: .httpUpgrade(path, host))`:
///   - host != "" → `["type": "httpupgrade", "path": path, "host": host]`
///     (host — STRING, **НЕ array** — Pitfall 7 invariant: HTTPUpgrade
///     отличается от HTTP transport, где host = `[String]`).
///   - host == "" → `["type": "httpupgrade", "path": path]` (host опущен;
///     sing-box подставит TLS server_name как :authority).
/// - Все non-httpUpgrade cases (`.tcp`, `.ws`, `.grpc`, `.http`) → `nil` (defensive).
final class HTTPUpgradeTransportHandlerTests: XCTestCase {

    // MARK: Identity

    /// identifier — single-token lowercase, должно точно совпадать с
    /// `TransportConfig.httpUpgrade.identifier` ("httpupgrade"). НЕ `"http-upgrade"`
    /// и НЕ `"httpUpgrade"` (camelCase) — sing-box JSON ожидает single-token.
    func test_identifier_isHttpupgrade() {
        XCTAssertEqual(HTTPUpgradeTransportHandler.identifier, "httpupgrade")
        XCTAssertNotEqual(HTTPUpgradeTransportHandler.identifier, "http-upgrade")
        XCTAssertNotEqual(HTTPUpgradeTransportHandler.identifier, "httpUpgrade")
    }

    func test_displayName_isHTTPUpgradeLiteral() {
        XCTAssertEqual(HTTPUpgradeTransportHandler.displayName, "HTTPUpgrade")
    }

    func test_supportedProtocols_isVlessTlsAndTrojan() {
        // D-03 — Reality исключён (XTLS Vision несовместим с HTTPUpgrade overlay).
        XCTAssertEqual(Set(HTTPUpgradeTransportHandler.supportedProtocols),
                       Set(["vless-tls", "trojan"]))
    }

    // MARK: buildTransportBlock — happy path with host

    /// Example 2 (05-RESEARCH.md lines 743-752) — HTTPUpgrade transport блок
    /// с непустым host: ровно 3 ключа (`type`, `path`, `host`).
    func test_buildTransportBlock_full() throws {
        let cfg: TransportConfig = .httpUpgrade(path: "/upgrade", host: "h.example.com")
        let block = try XCTUnwrap(HTTPUpgradeTransportHandler.buildTransportBlock(for: cfg),
                                  "HTTPUpgrade handler must return non-nil for .httpUpgrade case")
        XCTAssertEqual(block["type"] as? String, "httpupgrade")
        XCTAssertEqual(block["path"] as? String, "/upgrade")
        XCTAssertEqual(block["host"] as? String, "h.example.com")
        XCTAssertEqual(block.count, 3,
                       "HTTPUpgrade block с непустым host должен содержать ровно 3 ключа")
    }

    /// **Pitfall 7 invariant test** — host для HTTPUpgrade transport ВСЕГДА
    /// STRING, не array. Это противоположно HTTP transport (Wave 2), где host =
    /// `[String]`. sing-box строго различает эти shape по JSON-schema; если
    /// emit'ить array — sing-box отвергнет outbound init с
    /// "expected string for host".
    func test_buildTransportBlock_hostIsString_notArray() throws {
        let cfg: TransportConfig = .httpUpgrade(path: "/upgrade", host: "h.example.com")
        let block = try XCTUnwrap(HTTPUpgradeTransportHandler.buildTransportBlock(for: cfg))
        XCTAssertNotNil(block["host"] as? String,
                        "Pitfall 7: HTTPUpgrade host MUST be String (sing-box schema)")
        XCTAssertNil(block["host"] as? [String],
                     "Pitfall 7: HTTPUpgrade host MUST NOT be [String] (отличается от HTTP transport)")
    }

    /// Empty host — ключ `host` ОПУЩЕН (а не emit'ится с "" значением).
    /// Это случай когда URI не содержит `&host=` query-параметра;
    /// sing-box подставит `tls.server_name` (SNI) как :authority HTTP/2-запросов.
    func test_buildTransportBlock_emptyHost_omitsHostKey() throws {
        let cfg: TransportConfig = .httpUpgrade(path: "/x", host: "")
        let block = try XCTUnwrap(HTTPUpgradeTransportHandler.buildTransportBlock(for: cfg))
        XCTAssertEqual(block["type"] as? String, "httpupgrade")
        XCTAssertEqual(block["path"] as? String, "/x")
        XCTAssertEqual(block.count, 2,
                       "Пустой host → ровно 2 ключа (type, path); host ОПУЩЕН")
        XCTAssertNil(block["host"], "host ключ не должен присутствовать при empty host")
        XCTAssertFalse(block.keys.contains("host"),
                       "host ключ ОПУЩЕН (sing-box подставит tls.server_name)")
    }

    // MARK: buildTransportBlock — defensive nil для non-httpUpgrade cases

    func test_buildTransportBlock_tcpReturnsNil() {
        XCTAssertNil(HTTPUpgradeTransportHandler.buildTransportBlock(for: .tcp),
                     "HTTPUpgrade handler должен вернуть nil для .tcp")
    }

    func test_buildTransportBlock_wsHttpGrpcReturnNil() {
        // Параметризованный defensive-check: handler обрабатывает только свой
        // .httpUpgrade case; для всех остальных диспатчинг идёт через
        // TransportRegistry по identifier'у, handler возвращает nil.
        let nonMatches: [TransportConfig] = [
            .ws(path: "/x", host: "h.com"),
            .http(path: "/api"),
            .grpc(serviceName: "TunService"),
        ]
        for cfg in nonMatches {
            XCTAssertNil(HTTPUpgradeTransportHandler.buildTransportBlock(for: cfg),
                         "HTTPUpgrade handler должен вернуть nil для \(cfg)")
        }
    }
}
