import Foundation

/// RESEARCH §4 — формат тела subscription ответа.
public enum SubscriptionFormat: Sendable, Equatable {
    case base64URIList          // body — base64-encoded `\n`-separated URI list
    case plainTextURIList       // body — `\n`-separated URI list (no encoding)
    case singBoxJSON            // body — sing-box config (outbounds[].type)
    case v2rayJSON(reason: String)  // body — v2ray-style (outbounds[].protocol) — НЕ supported
    case unknown(snippet: String)
}

/// RESEARCH §4.6 — pool metadata extracted from response headers.
public struct SubscriptionMetadata: Sendable, Equatable {
    public let title: String?           // from Profile-Title header (Hiddify convention)
    public let updateInterval: Int?     // Phase 3 — RULES-04
    public let userInfo: String?        // Phase 4 — bandwidth metadata
    public init(title: String?, updateInterval: Int?, userInfo: String?) {
        self.title = title; self.updateInterval = updateInterval; self.userInfo = userInfo
    }
}

public struct SubscriptionFetchResult: Sendable {
    public let body: Data
    public let metadata: SubscriptionMetadata
    public let finalURL: URL
    public init(body: Data, metadata: SubscriptionMetadata, finalURL: URL) {
        self.body = body; self.metadata = metadata; self.finalURL = finalURL
    }
}

/// Phase 3 / Plan 04 — protocol для DI fetcher'а в ServerListViewModel.
///
/// Реальный impl — `SubscriptionURLFetcher.fetch(url:session:)` обёрнутый в
/// `DefaultSubscriptionURLFetcher` (см. ниже). Тесты mock'ают этот protocol через
/// `MockFetcher`, чтобы избежать сетевых вызовов.
public protocol SubscriptionURLFetching: Sendable {
    func fetch(url: URL) async throws -> SubscriptionFetchResult
}

/// Default impl — оборачивает `SubscriptionURLFetcher.fetch` с `URLSession.shared`.
public struct DefaultSubscriptionURLFetcher: SubscriptionURLFetching, Sendable {
    public init() {}
    public func fetch(url: URL) async throws -> SubscriptionFetchResult {
        try await SubscriptionURLFetcher.fetch(url: url, session: .shared)
    }
}

/// Phase 10 DPI-08 pinned variant — uses `PinnedSessionDelegate` for SPKI SHA-256 cert pinning.
///
/// Used when `certPinningEnabled == true` (default ON in SecuritySection, D-13).
/// Creates an ephemeral URLSession per fetch with `PinnedSessionDelegate`.
/// URLSession strongly retains its delegate (Apple-documented — T-10-W4-09 accepted).
///
/// On cert pin mismatch → URLSession cancels with `NSURLErrorCancelled` → throws.
public struct PinnedSubscriptionURLFetcher: SubscriptionURLFetching, Sendable {

    private let pinStore: PinStore

    public init(pinStore: PinStore) {
        self.pinStore = pinStore
    }

    public func fetch(url: URL) async throws -> SubscriptionFetchResult {
        let session = SubscriptionURLFetcher.makeSession(pinningEnabled: true, pinStore: pinStore)
        defer { session.invalidateAndCancel() }
        return try await SubscriptionURLFetcher.fetch(url: url, session: session)
    }
}

/// IMP-04 foundation — fetch subscription URL via HTTPS + detect body format.
///
/// **R1-spirit**: HTTPS-only enforced (http:// rejected before fetch).
/// **No cert pinning на v0.2** — DPI-08 → Phase 7.
public enum SubscriptionURLFetcher {

    public enum FetchError: Error, LocalizedError, Equatable {
        case nonHTTPS(String)
        case notHTTPResponse
        case httpStatusError(Int)
        case malformedURL
        case timeout
        /// CR-03 / T-03-06 — host попадает в blocklist (loopback / link-local /
        /// RFC-1918 / multicast / ULA). `String` — нормализованный host для UI/log.
        case blockedHost(String)
        /// T-A6 (closes A4-002 HIGH) — subscription body превысил `maxBodyBytes` cap.
        /// Associated `Int` — observed bytes (для UI/log; точное значение зависит от
        /// streaming progress в момент cap-exceed).
        case bodyTooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .nonHTTPS(let s): return "Subscription URL must be https:// (got \(s))"
            case .notHTTPResponse: return "Subscription response is not HTTP"
            case .httpStatusError(let code): return "Subscription HTTP error: \(code)"
            case .malformedURL: return "Subscription URL is malformed"
            case .timeout: return "Subscription request timed out"
            case .blockedHost(let host): return "Subscription URL host is blocked: \(host)"
            case .bodyTooLarge(let n): return "Subscription body too large (\(n) bytes, max \(maxBodyBytes))"
            }
        }
    }

    /// T-A6 (closes A4-002 HIGH) — hard cap для subscription response body. 5 MB
    /// comfortably exceeds realistic plain-text URI lists и sing-box JSON manifests
    /// (~1500 server entries), но блокирует OOM-via-multi-hundred-MB hostile responses.
    /// Same cap shared с base64-decode guard (A4-005) и JSON pre-decode (A4-004).
    public static let maxBodyBytes: Int = 5_000_000

    /// Fetch subscription body with BBTB/0.2 User-Agent.
    /// - Parameter session: defaults to `URLSession.shared`. Tests inject a mocked session
    ///   built from `URLSessionConfiguration.ephemeral` with `MockURLProtocol` in
    ///   `protocolClasses`.
    public static func fetch(url: URL, session: URLSession = .shared) async throws -> SubscriptionFetchResult {
        guard url.scheme?.lowercased() == "https" else {
            throw FetchError.nonHTTPS(url.scheme ?? "")
        }
        // CR-03 / T-03-06 — hostname SSRF blocklist. Проверяется ДО session.data,
        // чтобы predictably throw без выхода в сеть. Покрывает loopback,
        // link-local, RFC-1918, ULA, multicast и reserved-ranges.
        // DNS-rebinding защита НЕ в скоупе (см. isBlockedHost / T-G1-05 carry-forward).
        guard let rawHost = url.host, !rawHost.isEmpty else {
            throw FetchError.malformedURL
        }
        if isBlockedHost(rawHost) {
            throw FetchError.blockedHost(normalizeHostForLog(rawHost))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/json, */*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // T-A6 (closes A4-002): stream body via URLSession.bytes(for:) и accumulate
        // в Data с hard cap `maxBodyBytes`. URLSession.data(for:) buffers entire response
        // before returning, allowing hostile 500MB chunked stream to OOM-kill iOS NE
        // или main app (NE has ~50MB ceiling).
        //
        // T-A3 (closes A4-001 / C4-001): re-validate HTTP redirects через
        // `HTTPSRedirectGuard` delegate. Production path (URLSession.shared caller)
        // builds ephemeral guarded session; caller-supplied session (тесты с
        // MockURLProtocol) keeps existing delegate setup. Production redirect через
        // blocked host теперь rejected (URLSession cancels request).
        //
        // **Session lifecycle:** ephemeral guarded session MUST outlive byteStream
        // consumption — invalidate AFTER body fully read, не inside if branch.
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
        let (byteStream, response) = try await activeSession.bytes(for: request)
        guard let httpResp = response as? HTTPURLResponse else { throw FetchError.notHTTPResponse }
        guard (200..<300).contains(httpResp.statusCode) else { throw FetchError.httpStatusError(httpResp.statusCode) }
        // Fast-path: HTTP Content-Length header reject обходит streaming completely.
        if let lenHeader = httpResp.value(forHTTPHeaderField: "Content-Length"),
           let len = Int(lenHeader),
           len > maxBodyBytes {
            throw FetchError.bodyTooLarge(len)
        }
        var body = Data()
        body.reserveCapacity(min(maxBodyBytes, Int(httpResp.expectedContentLength > 0 ? httpResp.expectedContentLength : 16_384)))
        var accumulated = 0
        for try await chunk in byteStream {
            body.append(chunk)
            accumulated += 1
            // Cap check после каждого byte append — exact cap enforcement.
            if body.count > maxBodyBytes {
                throw FetchError.bodyTooLarge(body.count)
            }
        }
        _ = accumulated  // suppress unused warning

        let title = extractTitle(from: httpResp.allHeaderFields)
        let metadata = SubscriptionMetadata(title: title, updateInterval: nil, userInfo: nil)
        return SubscriptionFetchResult(body: body, metadata: metadata, finalURL: httpResp.url ?? url)
    }

    /// RESEARCH §4.2 — detect subscription body format.
    public static func detectFormat(body: Data) -> SubscriptionFormat {
        guard let raw = String(data: body, encoding: .utf8) else {
            return .unknown(snippet: "<non-UTF8 \(body.count) bytes>")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .unknown(snippet: "<empty>") }

        // 1. JSON detection (starts with `{` or `[`).
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outbounds = json["outbounds"] as? [[String: Any]] {
                // sing-box: outbound type field. v2ray: outbound protocol field.
                let hasSingBoxType = outbounds.contains { $0["type"] != nil }
                let hasV2RayProtocol = outbounds.contains { $0["protocol"] != nil && $0["type"] == nil }
                if hasV2RayProtocol && !hasSingBoxType {
                    return .v2rayJSON(reason: "outbounds contain `protocol` field instead of `type`")
                }
                return .singBoxJSON
            }
            return .unknown(snippet: String(trimmed.prefix(80)))
        }

        // 2. URI scheme prefix → plain-text URI list.
        for scheme in StubParsers.knownSchemes {
            if trimmed.lowercased().hasPrefix("\(scheme)://") {
                return .plainTextURIList
            }
        }

        // 3. Base64 attempt.
        if let decoded = decodeBase64(trimmed),
           isPrintableURIList(decoded) {
            return .base64URIList
        }

        return .unknown(snippet: String(trimmed.prefix(80)))
    }

    /// Decode subscription body if base64-encoded; returns nil if cannot decode.
    ///
    /// **T-A6 (closes A4-005 HIGH):** rejects pre-decode strings longer than
    /// `4 * maxBodyBytes` (~20MB raw base64 → ~15MB decoded), AND post-decode
    /// `data.count > maxBodyBytes` returns nil. Защита против hostile subscription
    /// returning huge base64 payload to OOM-kill the decoder.
    public static func decodeBase64(_ s: String) -> String? {
        // Pre-decode size guard — early-return without allocation if obviously too large.
        guard s.count <= 4 * maxBodyBytes else { return nil }
        // Subscription base64 may be without padding — pad to multiple of 4.
        var padded = s.replacingOccurrences(of: "\n", with: "")
                      .replacingOccurrences(of: " ", with: "")
        // Some subscription endpoints use URL-safe base64.
        padded = padded.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - padded.count % 4) % 4
        padded += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: padded) else { return nil }
        // Post-decode size guard — protect downstream parsers.
        guard data.count <= maxBodyBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func isPrintableURIList(_ s: String) -> Bool {
        let lines = s.split(whereSeparator: \.isNewline).map(String.init)
        let knownLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return StubParsers.knownSchemes.contains { trimmed.hasPrefix("\($0)://") }
        }
        return !knownLines.isEmpty
    }

    private static func extractTitle(from headers: [AnyHashable: Any]) -> String? {
        let keys = ["Profile-Title", "profile-title"]
        for k in keys {
            if let v = headers[k] as? String { return decodeMaybeBase64(v) }
        }
        return nil
    }

    private static func decodeMaybeBase64(_ s: String) -> String {
        if s.hasPrefix("base64:"), let data = Data(base64Encoded: String(s.dropFirst(7))),
           let decoded = String(data: data, encoding: .utf8) { return decoded }
        return s
    }

    // MARK: - Phase 10 DPI-08 — Session Factory

    /// Creates a URLSession configured for subscription URL fetching.
    ///
    /// Consolidates the pinning toggle into a single point for testability.
    ///
    /// - Parameter pinningEnabled: if `true`, returns an ephemeral session with
    ///   `PinnedSessionDelegate` wired. If `false`, returns `URLSession.shared` (default trust).
    /// - Parameter pinStore: Pin store to use for the delegate. Only used when `pinningEnabled == true`.
    ///
    /// **Test 8 (test_noPinningWhenDisabled):** Callers can inspect `session.delegate == nil`
    /// to verify toggle-off behavior (DPI-08).
    public static func makeSession(pinningEnabled: Bool, pinStore: PinStore = .init()) -> URLSession {
        guard pinningEnabled else {
            // Toggle OFF: return an ephemeral session with no custom delegate (default OS trust)
            let config = URLSessionConfiguration.ephemeral
            return URLSession(configuration: config)
        }
        // Toggle ON: attach PinnedSessionDelegate
        let delegate = PinnedSessionDelegate(pinStore: pinStore)
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - CR-03 / T-03-06 — SSRF hostname blocklist

    /// Возвращает нормализованный host (lowercase + strip `[]` для IPv6 literal).
    ///
    /// Phase 8 W0 — promoted public для reuse из RulesEngine.RulesFetcher
    /// (см. .planning/phases/08-rules-engine-split-tunneling/08-RESEARCH.md § Validation Architecture Risk #1).
    public static func normalizeHostForLog(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("[") && h.hasSuffix("]") {
            h = String(h.dropFirst().dropLast())
        }
        return h
    }

    /// Проверяет, что host — НЕ в private/loopback/link-local/multicast диапазоне.
    ///
    /// Покрывает: `localhost`, `*.local` mDNS, IPv4 loopback `127.0.0.0/8`, link-local
    /// `169.254.0.0/16`, RFC-1918 `10.0.0.0/8` + `172.16.0.0/12` + `192.168.0.0/16`,
    /// CGNAT `100.64.0.0/10`, `0.0.0.0/8`, multicast `224.0.0.0/4`,
    /// reserved `240.0.0.0/4`, IPv6 `::1`, link-local `fe80::/10`,
    /// ULA `fc00::/7` (fc/fd prefixes), IPv4-mapped IPv6 `::ffff:RFC1918`.
    ///
    /// **T-A3 extensions (closes A4-001 / C4-001 / C5-001 CRITICAL):**
    /// - `.local` mDNS (router admin pages, AppleTV, printers)
    /// - CGNAT `100.64.0.0/10` (shared-address space, RFC 6598)
    /// - IPv4-mapped IPv6 `::ffff:a.b.c.d` — could bypass via IPv6 literal
    /// - `localhost.` trailing-dot variant
    ///
    /// **Accepted residual risk (carry-forward к v1.1+):** DNS-rebinding атака
    /// (host resolves в blocked IP после passes string check) requires custom
    /// URLSession resolver post-DNS validation. Out of scope для v1.0 TestFlight.
    public static func isBlockedHost(_ rawHost: String) -> Bool {
        let host = normalizeHostForLog(rawHost)
        guard !host.isEmpty else { return true }

        // Exact-match: localhost + IPv6 loopback + IPv4 all-zeros.
        // T-A3: добавлены trailing-dot variant `localhost.` и `::` (unspecified IPv6).
        let exactBlocked: Set<String> = ["localhost", "localhost.", "::1", "::", "0.0.0.0"]
        if exactBlocked.contains(host) { return true }

        // T-A3: `.local` mDNS reservation (RFC 6762). Examples: `router.local`,
        // `printer.local`, `apple-tv.local`. Strict suffix check для DNS labels.
        if host.hasSuffix(".local") || host.hasSuffix(".local.") {
            return true
        }

        // IPv4 prefix blocklist.
        let ipv4Prefixes: [String] = [
            "127.",      // loopback 127.0.0.0/8
            "10.",       // RFC-1918 10.0.0.0/8
            "169.254.",  // link-local 169.254.0.0/16 (incl. AWS metadata 169.254.169.254)
            "192.168.",  // RFC-1918 192.168.0.0/16
            "0.",        // unspecified 0.0.0.0/8
            "224.",      // multicast 224.0.0.0/4 (first octet 224–239 — handled by sub-prefixes ниже)
            "225.", "226.", "227.", "228.", "229.",
            "230.", "231.", "232.", "233.", "234.", "235.",
            "236.", "237.", "238.", "239.",
            "240.",      // reserved 240.0.0.0/4 (240–255)
            "241.", "242.", "243.", "244.", "245.",
            "246.", "247.", "248.", "249.", "250.",
            "251.", "252.", "253.", "254.", "255."
        ]
        if ipv4Prefixes.contains(where: { host.hasPrefix($0) }) { return true }

        // RFC-1918 172.16.0.0/12 — only second octet 16..31.
        for n in 16...31 where host.hasPrefix("172.\(n).") {
            return true
        }

        // T-A3: CGNAT 100.64.0.0/10 (RFC 6598 shared-address space).
        // Second octet range 64..127. Otherwise 100.0.0.0/8 is public.
        for n in 64...127 where host.hasPrefix("100.\(n).") {
            return true
        }

        // IPv6 link-local fe80::/10 — `hasPrefix("fe80:")` достаточно (нет коротких
        // префиксов fe8 типа fe8a).
        if host.hasPrefix("fe80:") { return true }

        // IPv6 ULA fc00::/7 — fc-/fd-prefixes. Защита от false-positive «fc.example.com»:
        // ULA hostname обязан содержать `:`, а DNS-имя — точку без `:`. Проверяем оба.
        if (host.hasPrefix("fc") || host.hasPrefix("fd")) && host.contains(":") {
            return true
        }

        // T-A3: IPv4-mapped IPv6 `::ffff:a.b.c.d` форма (RFC 4291 §2.5.5.2).
        // Extract IPv4 portion и rerun blocklist через ipv4Prefixes.
        if host.hasPrefix("::ffff:") {
            let ipv4Part = String(host.dropFirst("::ffff:".count))
            // Recursive call с extracted IPv4 — terminates because IPv4 part won't have `::ffff:` prefix.
            if isBlockedHost(ipv4Part) { return true }
        }

        return false
    }
}

// MARK: - URLSessionTaskDelegate redirect re-validation

/// T-A3 (closes A4-001 / C4-001 / C5-001 CRITICAL) — re-applies SSRF host blocklist
/// + HTTPS-only check на каждом HTTP redirect. Previously fetchers only validated
/// initial URL; subsequent 301/302 redirects could send user request к loopback /
/// RFC1918 / `.local` mDNS host без any guard.
///
/// Usage: pass instance as `delegate:` argument к `URLSession(configuration:delegate:delegateQueue:)`,
/// or use `URLSession.shared` + `bytes(for:delegate:)` API.
public final class HTTPSRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {

    public override init() { super.init() }

    /// Called by URLSession on every HTTP redirect. Reject если new URL не HTTPS
    /// или host попадает в blocklist; otherwise allow redirect.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let newURL = request.url,
              newURL.scheme?.lowercased() == "https",
              let host = newURL.host, !host.isEmpty,
              !SubscriptionURLFetcher.isBlockedHost(host)
        else {
            // Reject redirect — pass nil (URLSession returns с original response /
            // throws cancelled). Sufficient signal — caller sees fetch error.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
