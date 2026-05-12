import Foundation
import VPNCore

/// CORE-03 (Phase 5, Wave 3) — HTTPUpgrade transport handler.
///
/// Производит sing-box `transport: {type: "httpupgrade", ...}` JSON-блок из
/// `TransportConfig.httpUpgrade(path:host:)`. Структура блока (см. Example 2
/// HTTPUpgrade lines 743-752 в `.planning/phases/05-transports/05-RESEARCH.md`):
///
///     ["type": "httpupgrade",
///      "path": <path>,
///      "host": <host>]      // ONLY if host is non-empty
///
/// **Pitfall 7 invariant (HOST как STRING, не ARRAY)**: sing-box HTTPUpgrade
/// transport принимает `host` как **string** — это отличается от HTTP transport
/// (Wave 2), где `host` объявлено как `[]string` (массив для random-host
/// selection). Три разные schema по семейству V2Ray-транспортов:
///
///   | transport    | host shape              | URI param |
///   | ------------ | ----------------------- | --------- |
///   | ws           | headers.Host (string)   | ?host=X   |
///   | http         | host: [String] (array)  | ?host=X   |
///   | httpupgrade  | host: String (string)   | ?host=X   |
///
/// Если emit'ить `[host]` (array) — sing-box отвергнет outbound с
/// "expected string for host". Тест `test_buildTransportBlock_hostIsString_notArray`
/// фиксирует invariant.
///
/// **Empty host invariant**: при `.httpUpgrade(path, "")` ключ `host` ОПУЩЕН
/// целиком — этот случай возникает когда URI не содержит `&host=` query-параметра
/// (TransportParamParser fallback: `host: ""`). sing-box подставляет
/// `tls.server_name` (SNI) как :authority HTTP/1.1 Upgrade-запроса —
/// это безопасный default для R1 invariant (всегда SNI = honest server name).
///
/// **D-03 — Reality исключён**: XTLS Vision flow и HTTPUpgrade transport overlay
/// несовместимы; парсер VLESSURIParser Reality branch не использует
/// TransportParamParser, поэтому такой URI не может быть сконструирован.
///
/// Реализован как enum без cases — идиоматичный Swift namespace для static-only
/// контракта (по образцу TCPTransportHandler / WSTransportHandler / HTTPTransportHandler).
public enum HTTPUpgradeTransportHandler: TransportHandler {
    public static let identifier = "httpupgrade"
    public static let displayName = "HTTPUpgrade"
    /// D-03: Reality исключён (XTLS Vision несовместим с HTTPUpgrade overlay).
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]

    /// Строит sing-box `transport` блок для `.httpUpgrade(path:host:)`.
    /// Возвращает `nil` для всех остальных cases (defensive — handler обрабатывает
    /// только свой HTTPUpgrade-кейс; диспатчинг по `identifier` происходит в
    /// `TransportRegistry`).
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
        guard case let .httpUpgrade(path, host) = config else { return nil }
        var block: [String: Any] = [
            "type": "httpupgrade",
            "path": path,
        ]
        // Empty host → ключ опущен; sing-box подставляет tls.server_name
        // (см. doc-comment выше). Pitfall 7: host — STRING (не array)
        // — отличается от HTTP transport, где требуется [String].
        if !host.isEmpty {
            block["host"] = host  // sing-box httpupgrade host is STRING (NOT array — differs from "type": "http" transport per Pitfall 7)
        }
        return block
    }
}
