import Foundation
import ConfigParser
import VPNCore

/// Phase 9 / DEEP-01 + DEEP-02 — concrete handler для **обеих** дорожек:
///   * Custom scheme: `bbtb://import?url={subscription_url}`
///   * Universal Link: `https://import.bbtb.app/import?url={subscription_url}`
///
/// Обе дорожки сходятся к одному handler per RESEARCH.md § Pattern 5 path
/// convergence. После validation handler делегирует raw subscription URL
/// существующему `ConfigImporting.importFromRawInput(_:source:)` pipeline
/// (Phase 2+ universal parser — SSRF + size cap + redirect cap всё внутри).
///
/// **Validation order** (per behavior contract):
///   1. URL parseable to URLComponents → otherwise `invalidParameterValue`.
///   2. `url` query item exists и непустой → otherwise `missingQueryParameter`.
///   3. `URL(string: rawValue)` non-nil — guard против double-encoded payload
///      (Pitfall #5: URLComponents single-decode уже applied; если результат
///      не URL по форме → reject, не передавать в importer).
///   4. Delegate to `importer.importFromRawInput(rawValue, source: .deepLink)`.
///      Любая ошибка importer → wrap в `.importFailed(underlying:)` с
///      `error.localizedDescription` (ImporterError уже localized RU).
///
/// **Sendable:** struct + immutable `let importer: ConfigImporting` (Sendable
/// protocol). Безопасно использовать в `DeepLinkRouter` actor.
public struct ImportHandler: DeepLinkHandler {

    public static let identifier = "import"

    private let importer: ConfigImporting

    public init(importer: ConfigImporting) {
        self.importer = importer
    }

    public func canHandle(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        // Custom scheme: bbtb://import?url=…
        if scheme == "bbtb", url.host?.lowercased() == "import" {
            return true
        }
        // Universal Link: https://import.bbtb.app/import…
        if scheme == "https",
           url.host?.lowercased() == "import.bbtb.app",
           url.path.hasPrefix("/import") {
            return true
        }
        return false
    }

    public func handle(_ url: URL) async throws {
        DeepLinksLogger.importer.notice(
            "ImportHandler.handle url=\(url.absoluteString, privacy: .public)"
        )

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DeepLinkError.invalidParameterValue(name: "url", reason: "не URL")
        }

        // URLComponents.queryItems делает single percent-decode automatically.
        guard let urlItem = components.queryItems?.first(where: { $0.name == "url" }),
              let rawValue = urlItem.value, !rawValue.isEmpty
        else {
            throw DeepLinkError.missingQueryParameter(name: "url")
        }

        // Defense against double-encoding (Pitfall #5) AND non-URL payload:
        // если после single-decode результат не URL по форме — reject.
        guard URL(string: rawValue) != nil else {
            throw DeepLinkError.invalidParameterValue(name: "url", reason: "не похоже на URL")
        }

        do {
            _ = try await importer.importFromRawInput(rawValue, source: .deepLink)
        } catch {
            throw DeepLinkError.importFailed(underlying: error.localizedDescription)
        }
    }
}
