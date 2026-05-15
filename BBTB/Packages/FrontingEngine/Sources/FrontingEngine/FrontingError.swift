import Foundation

/// Phase 10 / DPI-06 — Error types для FrontingEngine operations.
///
/// Используется в:
/// - `FrontingConfigApplier.apply(json:...)` — JSON parse/serialize errors
/// - `FrontingFallbackChain` — exhaustion detection
/// - Logging layer в Plan 06 ConfigImporter integration
public enum FrontingError: Error, Sendable, Equatable {

    /// JSON input не может быть десериализован или сериализован обратно в String.
    /// Возникает если `expandConfigForTunnel` вернул невалидный JSON (defensive).
    case malformedJSON

    /// Transport type не поддерживается для CDN-фронтинга.
    /// - Parameter: transport type string из sing-box outbound (e.g. "quic", "h2").
    case unsupportedTransport(String)

    /// Outbound попал в D-05 blacklist (TUIC/Hysteria2/Reality/Vision).
    /// - Parameter: причина blacklist (e.g. "tuic", "reality", "xtls-rprx-vision").
    case providerBlacklisted(String)

    /// FrontingFallbackChain исчерпал все profiles в пуле.
    /// Вызывающий (ConfigImporter Plan 06) должен fallback на direct/next-node.
    case fallbackExhausted

    /// Ошибка ввода-вывода при чтении/записи FrontingFailureCache.
    /// - Parameter: локализованное описание ошибки (для logging).
    case ioError(String)
}
