import Foundation
import VPNCore

/// CORE-03 (Phase 5, Wave 2) — HTTP/2 transport handler.
///
/// Производит sing-box `transport: {type: "http", ...}` JSON-блок из
/// `TransportConfig.http(path:)`. Минимальная структура блока (см. Example 2
/// в `.planning/phases/05-transports/05-RESEARCH.md`):
///
///     ["type": "http",
///      "path": <path>]
///
/// **Pitfall 7 (HOST как ARRAY, не STRING)**: sing-box HTTP transport
/// принимает `host` как `[]string` (массив строк для random-host selection).
/// **В Wave 2 этот ключ НЕ emit'ится**: sing-box использует `tls.server_name`
/// (SNI) в качестве `:authority` HTTP/2-запросов когда поле `host` отсутствует
/// — этого достаточно для R1 invariant и текущих use-cases.
///
/// Если в будущем потребуется явный multi-host random selection — расширять
/// `TransportConfig.http` ассоциированным значением `hosts: [String]` и
/// emit'ить здесь как `block["host"] = hosts` (array, НЕ string — Pitfall 7).
/// Out of Phase 5 scope.
///
/// **Внимание (для Wave 5 protocol packages)**: если конкретный protocol
/// package решит подставить host explicit-ом, ОН должен emit'ить массив
/// `[String]`, а не строку — в противном случае sing-box отвергнет outbound
/// JSON. Эта ответственность лежит на каллере, не на handler-е.
///
/// **D-03 — Reality исключён**: XTLS Vision flow и HTTP transport overlay
/// несовместимы; парсер VLESSURIParser Reality branch не использует
/// TransportParamParser, поэтому такой URI не может быть сконструирован.
///
/// Реализован как enum без cases — идиоматичный Swift namespace для static-only
/// контракта (по образцу TCPTransportHandler / WSTransportHandler).
public enum HTTPTransportHandler: TransportHandler {
    public static let identifier = "http"
    public static let displayName = "HTTP/2"
    /// D-03: Reality исключён (XTLS Vision несовместим с HTTP transport overlay).
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]

    /// Строит sing-box `transport` блок для `.http(path:)`.
    /// Возвращает ровно 2 ключа: `type` и `path`. Host НЕ emit'ится
    /// (sing-box подставит `tls.server_name` как :authority — Pitfall 7).
    ///
    /// Возвращает `nil` для всех остальных cases (defensive — handler
    /// обрабатывает только свой HTTP-кейс; диспатчинг по `identifier`
    /// происходит в `TransportRegistry`).
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
        // sing-box uses tls.server_name as :authority when host is omitted;
        // explicit multi-host support is future work.
        guard case let .http(path) = config else { return nil }
        return [
            "type": "http",
            "path": path,
        ]
    }
}
