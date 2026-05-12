import Foundation
import VPNCore

/// CORE-03 (Phase 5, Wave 4) — gRPC transport handler.
///
/// Производит sing-box `transport: {type: "grpc", ...}` JSON-блок из
/// `TransportConfig.grpc(serviceName:)`. Структура блока (см. Example 2
/// gRPC lines 715-725 в `.planning/phases/05-transports/05-RESEARCH.md`):
///
///     ["type": "grpc",
///      "service_name": <serviceName>]
///
/// **Pitfall 6 invariant (CASE TRANSFORMATION URI → JSON)**: gRPC имеет
/// два разных namespace'а для одного семантического поля:
///
///   | layer              | key            | example           |
///   | ------------------ | -------------- | ----------------- |
///   | URI query (V2Ray)  | `serviceName`  | `?serviceName=X`  | camelCase
///   | sing-box JSON      | `service_name` | `"service_name":"X"` | snake_case
///   | Swift label        | `serviceName`  | `.grpc(serviceName:)` | camelCase (matches URI)
///
/// Если emit'ить `"serviceName"` (camelCase) в JSON — sing-box отвергнет
/// outbound с "unknown field serviceName" (sing-box JSON decoder strict-by-default).
/// Тест `test_buildTransportBlock_jsonKeyIsSnakeCase_notCamelCase` фиксирует
/// invariant: ОДНОВРЕМЕННО `block["service_name"] != nil` И `block["serviceName"] == nil`.
///
/// **Empty serviceName**: при `.grpc(serviceName: "")` ключ `service_name`
/// ВСЁ РАВНО emit'ится с пустой строкой (не опускается, в отличие от
/// host в WS/HTTPUpgrade handlers). sing-box validator решает на этапе
/// outbound init: если сервер настроен на default service — empty ok;
/// иначе sing-box вернёт error. Handler прозрачно передаёт associated value.
///
/// **D-03 — Reality исключён**: XTLS Vision flow и gRPC transport overlay
/// несовместимы; парсер VLESSURIParser Reality branch не использует
/// TransportParamParser, поэтому такой URI не может быть сконструирован.
///
/// **gRPC default serviceName**: при отсутствии URI query-параметра
/// `serviceName=` TransportParamParser подставляет `"TunService"` (Open
/// Question 5 в 05-RESEARCH.md) — это sing-box-совместимый default
/// для серверов, использующих стандартное имя tunnel-сервиса.
///
/// Реализован как enum без cases — идиоматичный Swift namespace для static-only
/// контракта (по образцу TCPTransportHandler / WSTransportHandler /
/// HTTPTransportHandler / HTTPUpgradeTransportHandler).
public enum GRPCTransportHandler: TransportHandler {
    public static let identifier = "grpc"
    public static let displayName = "gRPC"
    /// D-03: Reality исключён (XTLS Vision несовместим с gRPC overlay).
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]

    /// Строит sing-box `transport` блок для `.grpc(serviceName:)`.
    /// Возвращает ровно 2 ключа: `type` и `service_name` (snake_case — Pitfall 6).
    /// Возвращает `nil` для всех остальных cases (defensive — handler
    /// обрабатывает только свой gRPC-кейс; диспатчинг по `identifier`
    /// происходит в `TransportRegistry`).
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
        guard case let .grpc(serviceName) = config else { return nil }
        return [
            "type": "grpc",
            "service_name": serviceName,  // sing-box JSON key is snake_case "service_name"; URI query param is camelCase "serviceName" — Pitfall 6 asymmetry
        ]
    }
}
