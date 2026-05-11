import Foundation

/// IMP-04 foundation — JSON endpoint fetcher (D-02 variant 3).
///
/// Технически тот же URL fetcher, что и SubscriptionURLFetcher, но:
/// - Accept: application/json
/// - Post-fetch sanity check: body trimmed must start with `{`
/// - Caller (UniversalImportParser / ConfigImporter) делает SingBoxConfigLoader.validate.
public enum JSONEndpointFetcher {

    public enum FetchError: Error, LocalizedError, Equatable {
        case nonHTTPS(String)
        case notJSON(String)             // snippet
        case httpStatusError(Int)
        case fetchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .nonHTTPS(let s): return "JSON endpoint must be https:// (got \(s))"
            case .notJSON(let snippet): return "JSON endpoint returned non-JSON body: \(snippet)"
            case .httpStatusError(let code): return "JSON endpoint HTTP error: \(code)"
            case .fetchFailed(let s): return "JSON endpoint fetch failed: \(s)"
            }
        }
    }

    public static func fetch(url: URL, session: URLSession = .shared) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else {
            throw FetchError.nonHTTPS(url.scheme ?? "")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FetchError.fetchFailed(error.localizedDescription)
        }
        guard let httpResp = response as? HTTPURLResponse else {
            throw FetchError.fetchFailed("Not HTTP response")
        }
        guard (200..<300).contains(httpResp.statusCode) else {
            throw FetchError.httpStatusError(httpResp.statusCode)
        }

        guard let raw = String(data: data, encoding: .utf8) else {
            throw FetchError.notJSON("<non-UTF8 \(data.count) bytes>")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            throw FetchError.notJSON(String(trimmed.prefix(80)))
        }
        return data
    }
}
