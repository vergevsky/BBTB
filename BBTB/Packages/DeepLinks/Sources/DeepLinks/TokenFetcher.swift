import Foundation

/// Phase 9 / D-03 — PROTOCOL PLACEHOLDER for v1+ DEEP-03 token endpoint.
///
/// **No conformers in Phase 9.** В v1+ planner реализует `MarzbanDirectTokenFetcher`
/// или `ShlinkTokenFetcher` — concrete тип, который при `bbtb://c/{token}` (или
/// Universal Link `https://import.bbtb.app/c/{token}`) делает HTTPS request к VPS
/// `/c/{token}` endpoint'у и возвращает raw subscription URL (или сразу JSON конфиг).
///
/// **Why protocol now (not later):** держим shape interface стабильной — Wave 2
/// `RemoteTokenFetchHandler` (тоже stub в Phase 9) inject'ит `TokenFetcher` через DI,
/// а runtime registration `DeepLinkRouter.register(_:)` add'ит handler по необходимости.
/// В v1+ один concrete тип реализует protocol — routing core НЕ изменяется.
///
/// **Sendable required:** для cross-actor использования внутри `DeepLinkRouter` (actor)
/// под Swift 6 strict concurrency.
public protocol TokenFetcher: Sendable {
    /// Запрашивает у backend конфигурацию (subscription URL или raw JSON) по токену.
    ///
    /// - Parameter token: непустой токен из URL path (например, `c/{token}`).
    /// - Returns: raw configuration content — формат определяется implementor'ом:
    ///     - Marzban-style: возврат `vless://...` либо `vmess://...` URI.
    ///     - Shlink-style: возврат full subscription URL (для дальнейшего fetch).
    /// - Throws: implementation-specific ошибки; рекомендуется wrap'ить в
    ///   `DeepLinkError.importFailed(underlying:)` на handler boundary.
    func fetchConfig(forToken token: String) async throws -> String
}
