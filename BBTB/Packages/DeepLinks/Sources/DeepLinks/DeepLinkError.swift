import Foundation

/// Errors thrown by deep-link routing pipeline (`DeepLinkRouter` + конформеры
/// `DeepLinkHandler`).
///
/// Phase 9 / DEEP-05 — discriminated cases для UI mapping:
/// - `.unhandled` — нет зарегистрированного handler'а, который `canHandle == true`.
/// - `.missingQueryParameter` — handler matched, но required параметр (например, `url`)
///   отсутствует.
/// - `.invalidParameterValue` — параметр присутствует, но содержимое некорректно
///   (например, URL parse failure, scheme mismatch).
/// - `.importFailed` — handler делегировал в `ConfigImporting.importFromRawInput(_:source:)`,
///   и тот бросил ошибку; `underlying` несёт localizedDescription для пользовательского
///   alert.
/// - `.notImplemented` — placeholder для v1+ features (token-fetch flow). Возвращается
///   `TokenFetcher` conformer'ами, которые ещё не реализованы.
///
/// **Inline RU strings (Wave 1):** Wave 2 plan заменит эти на L10n keys через
/// `Localizable.xcstrings`. Сейчас inline-строки достаточны — Wave 1 пакет
/// тестируется unit-тестами, не UI.
///
/// **Equatable:** позволяет XCTest assertions через `XCTAssertEqual(error, .unhandled(url: …))`
/// без ручного pattern-matching. URL Equatable conformance — Foundation gives it for free.
///
/// **Sendable:** required, потому что error пересекает actor boundary
/// (`DeepLinkRouter.handle` throws → caller catches на другом actor).
public enum DeepLinkError: Error, LocalizedError, Equatable, Sendable {
    /// Ни один зарегистрированный handler не вернул `canHandle == true`.
    case unhandled(url: URL)

    /// Required query parameter отсутствует в URL.
    case missingQueryParameter(name: String)

    /// Параметр присутствует, но его значение невалидно.
    case invalidParameterValue(name: String, reason: String)

    /// Underlying import operation (`ConfigImporting.importFromRawInput`) бросил ошибку.
    /// `underlying` — `localizedDescription` оригинала, готов для UI alert.
    case importFailed(underlying: String)

    /// Feature ещё не реализована (placeholder для v1+ token-fetch flow).
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .unhandled(let url):
            return "Не удалось обработать ссылку: \(url.absoluteString)"
        case .missingQueryParameter(let name):
            return "В ссылке отсутствует параметр «\(name)»"
        case .invalidParameterValue(let name, let reason):
            return "Параметр «\(name)» некорректен: \(reason)"
        case .importFailed(let underlying):
            return "Импорт не удался: \(underlying)"
        case .notImplemented:
            return "Эта функция станет доступна в следующей версии."
        }
    }
}
