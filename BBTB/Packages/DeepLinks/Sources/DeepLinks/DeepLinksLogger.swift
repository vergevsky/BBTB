import Foundation
import OSLog

/// Subsystem-scoped Logger для Deep Links модуля.
///
/// Three categories track three architectural layers:
///   * **router** — `DeepLinkRouter` actor: register / handle / unhandled.
///   * **importer** — `ImportHandler` (Wave 2): URL parse / extract `url=` / delegate to
///     `ConfigImporter`.
///   * **token** — `RemoteTokenFetchHandler` (v1+ placeholder): token resolve / fetch.
///
/// Subsystem `app.bbtb.client` mirrors `RulesEngineLogger` conventions (main app side
/// — `app.bbtb.client`; tunnel side — `app.bbtb.tunnel`).
///
/// **Privacy:** see thread-model T-09-04 — URL `absoluteString` логируется с
/// `privacy: .public` ТОЛЬКО в Wave 1 (тестовые URL из unit tests). Wave 2 ImportHandler
/// MUST использовать `privacy: .private` для subscription token bodies.
enum DeepLinksLogger {
    static let router = Logger(subsystem: "app.bbtb.client", category: "deep-links.router")
    static let importer = Logger(subsystem: "app.bbtb.client", category: "deep-links.importer")
    static let token = Logger(subsystem: "app.bbtb.client", category: "deep-links.token")
}
