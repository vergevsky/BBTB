import Foundation
import VPNCore

/// CORE-03 (Phase 5, Wave 1) — WebSocket transport handler.
///
/// Производит sing-box `transport: {type: "ws", ...}` JSON-блок из
/// `TransportConfig.ws(path:host:)`. Структура блока (см. Example 4 в
/// `.planning/phases/05-transports/05-RESEARCH.md` lines 829-842):
///
///     ["type": "ws",
///      "path": <path>,
///      "headers": ["Host": <host>]]    // ONLY if host is non-empty
///
/// **Empty host invariant**: при `.ws(path, "")` ключ `headers` ОПУЩЕН целиком —
/// этот случай возникает когда URI не содержит `&host=` query-param. Caller
/// protocol package (VLESS+TLS / Trojan `buildOutbound` в Wave 5) при необходимости
/// подставит SNI в качестве WS Host header.
///
/// **D-03 — Reality исключён**: `supportedProtocols` НЕ содержит "vless-reality".
/// XTLS Vision flow и WebSocket overlay несовместимы (sing-box error на этапе
/// outbound init); парсер VLESSURIParser Reality branch не использует
/// TransportParamParser, поэтому такой URI просто не сгенерируется.
///
/// Реализован как enum без cases — идиоматичный Swift namespace для static-only
/// контракта (по образцу TCPTransportHandler).
public enum WSTransportHandler: TransportHandler {
    public static let identifier = "ws"
    public static let displayName = "WebSocket"
    /// D-03: Reality исключён (XTLS Vision несовместим с WS overlay).
    public static let supportedProtocols: [String] = ["vless-tls", "trojan"]

    /// Строит sing-box `transport` блок для `.ws(path:host:)`.
    /// Возвращает `nil` для всех остальных cases (defensive — handler обрабатывает
    /// только свой WS-кейс; диспатчинг по `identifier` происходит в `TransportRegistry`).
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
        guard case let .ws(path, host) = config else { return nil }
        var block: [String: Any] = [
            "type": "ws",
            "path": path,
        ]
        // Empty host → headers ключ опущен; caller подставляет SNI на этапе
        // сборки outbound JSON (см. Trojan/VLESS+TLS buildOutbound в Wave 5).
        if !host.isEmpty {
            block["headers"] = ["Host": host]
        }
        return block
    }
}
