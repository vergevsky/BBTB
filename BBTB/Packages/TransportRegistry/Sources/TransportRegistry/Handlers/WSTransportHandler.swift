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
        return buildTransportBlock(for: config, sniFallback: nil)
    }

    /// Phase 6e Wave 2 Theme C-1 (L2) — WS-specific overload, унифицирует логику
    /// «empty host → substitute SNI как Host header» которая раньше дублировалась
    /// в Trojan/ConfigBuilder.swift:161-168 и VLESSTLS/ConfigBuilder.swift:163-168
    /// (Phase 6d M12 `1621a08` shipped local mirror в VLESSTLS — теперь оба caller'а
    /// идут через unified handler).
    ///
    /// **Дизайн-решение** (см. RESEARCH.md L2 fallback A2): мы НЕ меняем
    /// `TransportHandler` protocol signature (это сломало бы остальные 4 handler'а:
    /// TCP/HTTP/HTTPUpgrade/gRPC). Вместо этого — WS-specific overload, который
    /// вызывается явно из Trojan/VLESSTLS `buildOutbound`. Базовая
    /// `buildTransportBlock(for:)` (TransportHandler protocol requirement)
    /// делегирует сюда с `sniFallback = nil` — backward compat preserved.
    ///
    /// Семантика: если `host` пустой → используется `sniFallback` (если не nil
    /// и не empty), иначе headers ключ опущен (старое поведение).
    public static func buildTransportBlock(for config: TransportConfig,
                                            sniFallback: String?) -> [String: Any]? {
        guard case let .ws(path, host) = config else { return nil }
        var block: [String: Any] = [
            "type": "ws",
            "path": path,
        ]
        // resolvedHost: caller-supplied host wins; пустой → sniFallback; всё ещё
        // пусто → headers ключ опущен (preserves "empty host invariant").
        let resolvedHost: String = {
            if !host.isEmpty { return host }
            if let fallback = sniFallback, !fallback.isEmpty { return fallback }
            return ""
        }()
        if !resolvedHost.isEmpty {
            block["headers"] = ["Host": resolvedHost]
        }
        return block
    }
}
