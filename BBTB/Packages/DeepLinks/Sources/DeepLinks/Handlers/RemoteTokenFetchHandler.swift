import Foundation
import ConfigParser

/// Phase 9 / D-03 — **STUB** for v1+ DEEP-03 token endpoint.
///
/// **NOT** registered with `DeepLinkRouter` в v0.9. Хранится в пакете как
/// архитектурная подготовка: когда в v1+ появится `GET /c/{token}` —
/// planner реализует body через `TokenFetcher` protocol и регистрирует
/// в App.init(). Тогда `canHandle` будет matching `https://import.bbtb.app/c/…`
/// либо `bbtb://c/{token}`.
///
/// **Why stub now (D-03):** держим shape interface стабильной — DI shape
/// `(TokenFetcher, ConfigImporting)` уже верифицирован compile-time, и tests
/// гарантируют что `canHandle == false` (router его никогда не вызовет в v0.9).
///
/// **Safety:** даже если кто-то instantiate'ит и invoke'нет `handle(_:)`
/// напрямую (минуя router), `notImplemented` гарантирует graceful throw —
/// no side effect (no network call, no state mutation).
public struct RemoteTokenFetchHandler: DeepLinkHandler {

    public static let identifier = "remote-token-fetch"

    private let tokenFetcher: TokenFetcher
    private let importer: ConfigImporting

    public init(tokenFetcher: TokenFetcher, importer: ConfigImporting) {
        self.tokenFetcher = tokenFetcher
        self.importer = importer
    }

    public func canHandle(_ url: URL) -> Bool {
        // v0.9 stub — НИКОГДА не matching (DEEP-03 deferred к v1+).
        // В v1+ planner раскрывает: `bbtb://c/{token}` или Universal Link
        // `https://import.bbtb.app/c/{token}`.
        return false
    }

    public func handle(_ url: URL) async throws {
        // TODO(v1+ DEEP-03): extract token from path, call tokenFetcher.fetchConfig,
        // forward raw config to importer.importFromRawInput(_, source: .deepLink).
        throw DeepLinkError.notImplemented
    }
}
