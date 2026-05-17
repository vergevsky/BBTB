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
        /// T-A3 (closes C4-002 CRITICAL) — host попадает в SSRF blocklist
        /// (loopback / RFC1918 / .local / link-local / ULA / CGNAT / multicast / reserved).
        case blockedHost(String)
        /// T-A3 (closes C4-002) — URL malformed или missing host.
        case malformedURL
        /// T-A3 (closes A4-002 cascading): response body превысил cap.
        case bodyTooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .nonHTTPS(let s): return "JSON endpoint must be https:// (got \(s))"
            case .notJSON(let snippet): return "JSON endpoint returned non-JSON body: \(snippet)"
            case .httpStatusError(let code): return "JSON endpoint HTTP error: \(code)"
            case .fetchFailed(let s): return "JSON endpoint fetch failed: \(s)"
            case .blockedHost(let host): return "JSON endpoint host is blocked: \(host)"
            case .malformedURL: return "JSON endpoint URL is malformed"
            case .bodyTooLarge(let n): return "JSON endpoint body too large (\(n) bytes)"
            }
        }
    }

    public static func fetch(url: URL, session: URLSession = .shared) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else {
            throw FetchError.nonHTTPS(url.scheme ?? "")
        }
        // T-A3 (closes C4-002 CRITICAL): apply same SSRF host blocklist + redirect guard
        // как SubscriptionURLFetcher. Previously JSONEndpointFetcher had only HTTPS
        // check — any user-provided JSON endpoint URL could reach loopback / RFC1918
        // / mDNS hosts через DNS resolution OR HTTP redirect.
        guard let rawHost = url.host, !rawHost.isEmpty else {
            throw FetchError.malformedURL
        }
        if SubscriptionURLFetcher.isBlockedHost(rawHost) {
            throw FetchError.blockedHost(SubscriptionURLFetcher.normalizeHostForLog(rawHost))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // T-A3: redirect re-validation. Build ephemeral session с HTTPSRedirectGuard для
        // production callers (URLSession.shared); tests с MockURLProtocol session keep
        // existing setup.
        let activeSession: URLSession
        let needsCleanup: Bool
        if session === URLSession.shared {
            activeSession = URLSession(
                configuration: .ephemeral,
                delegate: HTTPSRedirectGuard(),
                delegateQueue: nil
            )
            needsCleanup = true
        } else {
            activeSession = session
            needsCleanup = false
        }
        defer {
            if needsCleanup { activeSession.invalidateAndCancel() }
        }

        // T-B2' (closes C4'-003 HIGH): stream body через `bytes(for:)` с inline cap
        // accumulation. Previously `data(for:)` buffered full response в memory
        // before cap check — hostile endpoint could OOM-kill before .bodyTooLarge
        // evaluated. Now caps per-byte, mirrors SubscriptionURLFetcher pattern.
        let byteStream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (byteStream, response) = try await activeSession.bytes(for: request)
        } catch {
            throw FetchError.fetchFailed(error.localizedDescription)
        }
        guard let httpResp = response as? HTTPURLResponse else {
            throw FetchError.fetchFailed("Not HTTP response")
        }
        guard (200..<300).contains(httpResp.statusCode) else {
            throw FetchError.httpStatusError(httpResp.statusCode)
        }
        // Content-Length fast-path reject (avoids streaming completely).
        if let lenHeader = httpResp.value(forHTTPHeaderField: "Content-Length"),
           let len = Int(lenHeader),
           len > SubscriptionURLFetcher.maxBodyBytes {
            throw FetchError.bodyTooLarge(len)
        }
        var data = Data()
        data.reserveCapacity(min(SubscriptionURLFetcher.maxBodyBytes,
                                  Int(httpResp.expectedContentLength > 0 ? httpResp.expectedContentLength : 16_384)))
        do {
            for try await chunk in byteStream {
                data.append(chunk)
                if data.count > SubscriptionURLFetcher.maxBodyBytes {
                    throw FetchError.bodyTooLarge(data.count)
                }
            }
        } catch let e as FetchError {
            throw e
        } catch {
            throw FetchError.fetchFailed(error.localizedDescription)
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
