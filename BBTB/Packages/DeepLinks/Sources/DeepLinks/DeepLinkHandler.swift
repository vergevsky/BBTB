import Foundation

/// Contract для всех deep-link handlers, регистрируемых в `DeepLinkRouter`.
///
/// Phase 9 / DEEP-05 — extensible registry pattern (analog `ProtocolRegistry`).
/// В Wave 1 пакет содержит ZERO conformers; Wave 2 добавляет concrete `ImportHandler`,
/// в v1+ — `RemoteTokenFetchHandler` (placeholder protocol — см. `TokenFetcher.swift`).
///
/// **Why protocol, not enum-switch:** один большой switch по scheme/host (`bbtb` / `https`)
/// усложняется при добавлении новых action'ов. Registry pattern даёт нулевую стоимость
/// расширения — новый handler регистрируется через `DeepLinkRouter.register(_:)` без
/// изменения routing core.
///
/// **Sendable constraint:** required, потому что handlers пересекают actor boundary —
/// `DeepLinkRouter` (actor) хранит `[any DeepLinkHandler]` и invoke'ит `handle(_:)`
/// внутри своей actor isolation. Swift 6 strict concurrency требует Sendable для
/// типов, передаваемых между actor контекстами.
///
/// **Static identifier:** уникальный stable идентификатор для observability (логирование
/// «registered handler=<id>», «dispatched url=… handler=<id>»). Конформеры объявляют
/// `static let identifier = "<short-name>"` (например, `"import"`, `"token"`).
public protocol DeepLinkHandler: Sendable {
    /// Stable string identifier для logging и diagnostics.
    ///
    /// Convention: lowercase short-name, без префиксов (`"import"`, не `"DeepLinkImportHandler"`).
    static var identifier: String { get }

    /// Returns `true` если этот handler может обработать переданный URL.
    ///
    /// **Contract:** должно быть pure (без side-effects, без network) — `DeepLinkRouter`
    /// iterating ALL зарегистрированных handlers и спрашивает каждого. First-match wins
    /// (см. `DeepLinkRouter.handle(_:)`).
    ///
    /// **Example:** `ImportHandler.canHandle(url)` returns `true` для
    /// `bbtb://import?url=...` AND `https://import.bbtb.app/import?url=...`.
    func canHandle(_ url: URL) -> Bool

    /// Performs handler-specific URL processing.
    ///
    /// **Contract:** invoked ТОЛЬКО если `canHandle(url) == true`. Async-throws — handler
    /// can perform network I/O (subscription fetch, token resolve), can throw
    /// `DeepLinkError` (e.g. `.missingQueryParameter`, `.invalidParameterValue`,
    /// `.importFailed`).
    ///
    /// **Threading:** invoked внутри `DeepLinkRouter` actor isolation. Handler сам отвечает
    /// за hop'ы на main-actor для UI updates (через injected dependencies).
    func handle(_ url: URL) async throws
}
