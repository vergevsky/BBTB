import XCTest
@testable import TransportRegistry
import VPNCore

/// Phase 5 Wave 4 / Plan 05-05 — `GRPCTransportHandler` coverage.
///
/// Контракт (см. 05-05-PLAN.md <interfaces>, 05-RESEARCH.md Example 2 gRPC
/// lines 715-725 + Pitfall 6 case-transformation invariant):
/// - identifier = `"grpc"` (single token lowercase — соответствует
///   `TransportConfig.grpc.identifier`, без `-` и без `_`)
/// - displayName = `"gRPC"` (lowercase `g`, uppercase `RPC` — стандартное обозначение)
/// - supportedProtocols = `["vless-tls", "trojan"]` (D-03 Reality исключён,
///   XTLS Vision несовместим с gRPC overlay)
/// - `buildTransportBlock(for: .grpc(serviceName: svc))` →
///   `["type": "grpc", "service_name": svc]`. **JSON ключ — `service_name`
///   (snake_case)** — это отличается от URI query-параметра `serviceName`
///   (camelCase). Это **Pitfall 6** (case-transformation invariant): если
///   emit'ить camelCase в JSON, sing-box отвергнет outbound с "unknown field
///   serviceName".
/// - Все non-grpc cases (`.tcp`, `.ws`, `.http`, `.httpUpgrade`) → `nil` (defensive).
final class GRPCTransportHandlerTests: XCTestCase {

    // MARK: Identity

    /// identifier — single-token lowercase, должно точно совпадать с
    /// `TransportConfig.grpc.identifier` ("grpc"). НЕ `"GRPC"` (uppercase) и
    /// НЕ `"g-rpc"`/`"g_rpc"` — sing-box JSON ожидает single-token.
    func test_identifier_isGrpc() {
        XCTAssertEqual(GRPCTransportHandler.identifier, "grpc")
        XCTAssertNotEqual(GRPCTransportHandler.identifier, "GRPC")
        XCTAssertNotEqual(GRPCTransportHandler.identifier, "g-rpc")
    }

    /// displayName — `"gRPC"` (lowercase `g`, uppercase `RPC`) — стандартное
    /// обозначение gRPC в документации/UI. Case-sensitive.
    func test_displayName_isGRPCLiteral() {
        XCTAssertEqual(GRPCTransportHandler.displayName, "gRPC")
    }

    func test_supportedProtocols_isVlessTlsAndTrojan() {
        // D-03 — Reality исключён (XTLS Vision несовместим с gRPC overlay).
        XCTAssertEqual(Set(GRPCTransportHandler.supportedProtocols),
                       Set(["vless-tls", "trojan"]))
    }

    // MARK: buildTransportBlock — happy path

    /// Example 2 (05-RESEARCH.md lines 715-725) — gRPC transport блок:
    /// ровно 2 ключа (`type`, `service_name`). JSON ключ `service_name` —
    /// snake_case (per sing-box JSON schema).
    func test_buildTransportBlock_full() throws {
        let cfg: TransportConfig = .grpc(serviceName: "tunsvc")
        let block = try XCTUnwrap(GRPCTransportHandler.buildTransportBlock(for: cfg),
                                  "gRPC handler must return non-nil for .grpc case")
        XCTAssertEqual(block["type"] as? String, "grpc")
        XCTAssertEqual(block["service_name"] as? String, "tunsvc")
        XCTAssertEqual(block.count, 2,
                       "gRPC block должен содержать ровно 2 ключа (type, service_name)")
    }

    /// **Pitfall 6 invariant test** — JSON ключ для gRPC `serviceName` — это
    /// **`service_name`** (snake_case). URI query-параметр — **`serviceName`**
    /// (camelCase, V2Ray URI стандарт). НЕ путать эти два namespace'а: если
    /// emit'ить camelCase ключ в JSON — sing-box отвергнет outbound с
    /// "unknown field serviceName". Тест явно проверяет ОБА: snake_case ключ
    /// присутствует, camelCase ключ ОТСУТСТВУЕТ.
    func test_buildTransportBlock_jsonKeyIsSnakeCase_notCamelCase() throws {
        let cfg: TransportConfig = .grpc(serviceName: "tunsvc")
        let block = try XCTUnwrap(GRPCTransportHandler.buildTransportBlock(for: cfg))
        XCTAssertNotNil(block["service_name"],
                        "Pitfall 6: gRPC JSON ключ MUST be 'service_name' (snake_case, sing-box schema)")
        XCTAssertNil(block["serviceName"],
                     "Pitfall 6: gRPC JSON ключ MUST NOT be 'serviceName' (camelCase URI param не должен протекать в JSON)")
    }

    /// Empty serviceName — ключ `service_name` ВСЁ РАВНО emit'ится с пустой
    /// строкой (не опускается). sing-box validator решает, допустима ли
    /// пустая строка для конкретного server (если сервер настроен на
    /// default service — empty ok; иначе error). Это отличается от поведения
    /// host в WS/HTTPUpgrade handlers (где empty → omit). Inv: handler
    /// прозрачно передаёт значение associated value наружу.
    func test_buildTransportBlock_emptyServiceName_stillEmitted() throws {
        let cfg: TransportConfig = .grpc(serviceName: "")
        let block = try XCTUnwrap(GRPCTransportHandler.buildTransportBlock(for: cfg))
        XCTAssertEqual(block["type"] as? String, "grpc")
        XCTAssertEqual(block["service_name"] as? String, "",
                       "Empty serviceName → service_name ключ присутствует с пустой строкой (sing-box validator решает)")
        XCTAssertEqual(block.count, 2,
                       "Пустой serviceName → всё равно ровно 2 ключа (type, service_name)")
        XCTAssertTrue(block.keys.contains("service_name"),
                      "service_name ключ ВСЕГДА присутствует для .grpc case — handler прозрачно передаёт associated value")
    }

    // MARK: buildTransportBlock — defensive nil для non-grpc cases

    func test_buildTransportBlock_tcpReturnsNil() {
        XCTAssertNil(GRPCTransportHandler.buildTransportBlock(for: .tcp),
                     "gRPC handler должен вернуть nil для .tcp")
    }

    func test_buildTransportBlock_wsReturnsNil() {
        XCTAssertNil(GRPCTransportHandler.buildTransportBlock(for: .ws(path: "/x", host: "h.com")),
                     "gRPC handler должен вернуть nil для .ws")
    }

    /// Параметризованный defensive-check: handler обрабатывает только свой
    /// .grpc case; для всех остальных диспатчинг идёт через TransportRegistry
    /// по identifier'у, handler возвращает nil.
    func test_buildTransportBlock_httpAndHttpUpgradeReturnNil() {
        let nonMatches: [TransportConfig] = [
            .http(path: "/api"),
            .httpUpgrade(path: "/upgrade", host: "h.example.com"),
        ]
        for cfg in nonMatches {
            XCTAssertNil(GRPCTransportHandler.buildTransportBlock(for: cfg),
                         "gRPC handler должен вернуть nil для \(cfg)")
        }
    }
}
