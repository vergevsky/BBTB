import Foundation
import ConfigParser  // SubscriptionURLFetcher.isBlockedHost (public, promoted in W0)

/// HTTPS fetcher с SSRF blocklist + sequential mirror failover для Rules Engine assets.
///
/// **Responsibilities:**
/// 1. Enforce `https://` scheme (refuse plain HTTP — anti-MITM при rules update).
/// 2. Reject SSRF hosts (loopback / RFC-1918 / link-local / ULA / multicast) — reused
///    `SubscriptionURLFetcher.isBlockedHost` из ConfigParser (W0 promoted public).
/// 3. Pre-flight max-bytes cap (default 5 MB) → защита от oversized payloads
///    (Pitfall 3: 50 MB NE memory ceiling).
/// 4. Sequential mirror failover при `fetchWithFailover` — concurrency=1 per DEC-06d-04.
///
/// **NOT in scope:**
/// - Signature verify (separate concern — `RulesSigner`).
/// - Manifest decode (separate concern — `RulesManifest`).
/// - Caching / atomic write (separate concern — W2 `SRSCacheStore`).
///
/// **User-Agent:** `"BBTB-Rules/0.8 (iOS / macOS)"` — distinguishable от main app's
/// `"BBTB/0.2 ..."` UA для server-side log analysis.
///
/// **Pattern source:** `ConfigParser/SubscriptionURLFetcher.fetch(url:session:)`
/// (Phase 2-3 audited). Phase 8 W1 adapts с дополнительным `maxBytes` cap +
/// `mirrorURL` tracking в FetchResult.
public enum RulesFetcher {

    /// Successful fetch outcome — body bytes + optional `ETag` + which mirror served the response.
    public struct FetchResult: Sendable, Equatable {
        public let body: Data
        public let etag: String?
        public let mirrorURL: URL

        public init(body: Data, etag: String?, mirrorURL: URL) {
            self.body = body
            self.etag = etag
            self.mirrorURL = mirrorURL
        }
    }

    /// Structured fetch failure modes. `Equatable` for unit-test assertions.
    public enum FetchError: Error, LocalizedError, Equatable {
        /// URL `scheme` was not `https` (e.g. `http`, `file`). String — actual scheme observed.
        case nonHTTPS(String)
        /// URL missing host / malformed.
        case malformedURL
        /// Host matched SSRF blocklist (loopback, RFC-1918, etc.). String — normalized host for log.
        case blockedHost(String)
        /// Response was not `HTTPURLResponse` (network library returned something exotic).
        case notHTTPResponse
        /// HTTP status code outside 200..<300.
        case httpStatusError(Int)
        /// URLSession timed out — explicit case for clarity (`URLError.timedOut`).
        case timeout
        /// Payload exceeded `maxBytes` pre-flight cap. Int — observed size.
        case payloadTooLarge(Int)
        /// All mirrors failed; aggregated list of per-mirror errors in iteration order.
        case allMirrorsFailed([FetchError])

        public var errorDescription: String? {
            switch self {
            case .nonHTTPS(let s): return "Rules URL must be https:// (got \(s))"
            case .malformedURL: return "Rules URL is malformed (missing host)"
            case .blockedHost(let h): return "Rules URL host is blocked (SSRF guard): \(h)"
            case .notHTTPResponse: return "Rules response was not HTTP"
            case .httpStatusError(let code): return "Rules HTTP error: \(code)"
            case .timeout: return "Rules fetch timed out"
            case .payloadTooLarge(let n): return "Rules payload too large: \(n) bytes"
            case .allMirrorsFailed(let errs): return "All mirrors failed: \(errs.count) errors"
            }
        }
    }

    /// Default body size cap — 5 MB (Pitfall 3 mitigation). W2.3 coordinator can tighten
    /// до 1 MB если manifest's `total_size_bytes` known smaller.
    public static let defaultMaxBytes: Int = 5 * 1024 * 1024

    /// Fetch single URL — HTTPS-only + SSRF-checked + size-capped.
    ///
    /// - Parameter url: target URL. MUST be `https://` and host MUST pass SSRF blocklist.
    /// - Parameter session: defaults to `URLSession.shared`; tests inject ephemeral
    ///   session с `MockURLProtocol` (W1.4 test fixture pattern).
    /// - Parameter maxBytes: pre-flight size cap; throws `payloadTooLarge` if exceeded.
    ///
    /// - Throws: `FetchError.*` для всех failure paths.
    /// - Returns: `FetchResult(body, etag, mirrorURL: url)`.
    public static func fetch(
        url: URL,
        session: URLSession = .shared,
        maxBytes: Int = defaultMaxBytes
    ) async throws -> FetchResult {

        // 1. HTTPS scheme guard.
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" else {
            RulesEngineLogger.fetcher.error(
                "RulesFetcher.fetch rejected non-HTTPS scheme: \(scheme, privacy: .public)"
            )
            throw FetchError.nonHTTPS(scheme)
        }

        // 2. Host present.
        guard let rawHost = url.host, !rawHost.isEmpty else {
            RulesEngineLogger.fetcher.error("RulesFetcher.fetch rejected malformed URL (no host)")
            throw FetchError.malformedURL
        }

        // 3. SSRF blocklist (reuse public W0-promoted helper from ConfigParser).
        if SubscriptionURLFetcher.isBlockedHost(rawHost) {
            let normalized = SubscriptionURLFetcher.normalizeHostForLog(rawHost)
            RulesEngineLogger.fetcher.error(
                "RulesFetcher.fetch rejected blocked host: \(normalized, privacy: .public)"
            )
            throw FetchError.blockedHost(normalized)
        }

        // 4. Build request — explicit timeout + UA + Accept + no cache.
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("BBTB-Rules/0.8 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, application/octet-stream", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // 5. Async fetch — URLSession.data(for:) is async-aware natively (iOS 15+).
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let err as URLError where err.code == .timedOut {
            RulesEngineLogger.fetcher.warning(
                "RulesFetcher.fetch timed out for \(url.absoluteString, privacy: .public)"
            )
            throw FetchError.timeout
        }

        // 6. HTTP response validation.
        guard let httpResp = response as? HTTPURLResponse else {
            throw FetchError.notHTTPResponse
        }
        guard (200..<300).contains(httpResp.statusCode) else {
            RulesEngineLogger.fetcher.warning(
                "RulesFetcher.fetch HTTP error \(httpResp.statusCode, privacy: .public) for \(url.absoluteString, privacy: .public)"
            )
            throw FetchError.httpStatusError(httpResp.statusCode)
        }

        // 7. Pre-flight size cap (Pitfall 3 — NE memory ceiling defense).
        // Pre-flight = post-receive проверка но ДО передачи в Codable / SRS parser.
        guard data.count <= maxBytes else {
            RulesEngineLogger.fetcher.warning(
                "RulesFetcher.fetch payload too large: \(data.count, privacy: .public) bytes > \(maxBytes, privacy: .public)"
            )
            throw FetchError.payloadTooLarge(data.count)
        }

        let etag = httpResp.value(forHTTPHeaderField: "ETag")
        RulesEngineLogger.fetcher.notice(
            "RulesFetcher.fetch succeeded: \(data.count, privacy: .public) bytes, etag=\(etag ?? "none", privacy: .public)"
        )
        return FetchResult(body: data, etag: etag, mirrorURL: url)
    }

    /// Sequential mirror failover (concurrency=1, DEC-06d-04).
    ///
    /// Iterates `urls` in order. On each iteration:
    ///   1. Calls `fetch(url:)`. On success → return immediately.
    ///   2. On failure → collect error, continue to next mirror.
    ///
    /// Если `urls` empty → throws `allMirrorsFailed([])`.
    /// Если все mirrors failed → throws `allMirrorsFailed(errors)` where errors order
    /// mirrors urls order.
    ///
    /// - NOTE: **Not parallel.** Mirrors are not raced — per DEC-06d-04 bounded
    ///   concurrency principle (preserves VPS quota и avoids redundant network).
    public static func fetchWithFailover(
        urls: [URL],
        session: URLSession = .shared,
        maxBytes: Int = defaultMaxBytes
    ) async throws -> FetchResult {

        guard !urls.isEmpty else {
            RulesEngineLogger.fetcher.error("RulesFetcher.fetchWithFailover called with empty URL array")
            throw FetchError.allMirrorsFailed([])
        }

        var collectedErrors: [FetchError] = []
        for (idx, url) in urls.enumerated() {
            RulesEngineLogger.fetcher.info(
                "RulesFetcher.fetchWithFailover trying mirror \(idx + 1, privacy: .public)/\(urls.count, privacy: .public): \(url.absoluteString, privacy: .public)"
            )
            do {
                let result = try await fetch(url: url, session: session, maxBytes: maxBytes)
                RulesEngineLogger.fetcher.notice(
                    "RulesFetcher.fetchWithFailover succeeded on mirror \(idx + 1, privacy: .public)/\(urls.count, privacy: .public)"
                )
                return result
            } catch let err as FetchError {
                RulesEngineLogger.fetcher.warning(
                    "RulesFetcher.fetchWithFailover mirror \(idx + 1, privacy: .public) failed: \(err.localizedDescription, privacy: .public)"
                )
                collectedErrors.append(err)
                continue
            } catch {
                // Non-FetchError (e.g. URLError other than timeout) — wrap as generic fail.
                // Map to httpStatusError(0) — caller treats as opaque mirror failure.
                RulesEngineLogger.fetcher.warning(
                    "RulesFetcher.fetchWithFailover mirror \(idx + 1, privacy: .public) failed with unexpected error: \(String(describing: error), privacy: .public)"
                )
                collectedErrors.append(.httpStatusError(0))
                continue
            }
        }

        RulesEngineLogger.fetcher.error(
            "RulesFetcher.fetchWithFailover: all \(urls.count, privacy: .public) mirrors failed"
        )
        throw FetchError.allMirrorsFailed(collectedErrors)
    }
}
