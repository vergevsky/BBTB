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

        public var errorDescription: String? {
            switch self {
            case .nonHTTPS(let s): return "Subscription URL must be https:// (got \(s))"
            case .notHTTPResponse: return "Subscription response is not HTTP"
            case .httpStatusError(let code): return "Subscription HTTP error: \(code)"
            case .malformedURL: return "Subscription URL is malformed"
            case .timeout: return "Subscription request timed out"
            case .blockedHost(let host): return "Subscription URL host is blocked: \(host)"
            }
        }
    }

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

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else { throw FetchError.notHTTPResponse }
        guard (200..<300).contains(httpResp.statusCode) else { throw FetchError.httpStatusError(httpResp.statusCode) }

        let title = extractTitle(from: httpResp.allHeaderFields)
        let metadata = SubscriptionMetadata(title: title, updateInterval: nil, userInfo: nil)
        return SubscriptionFetchResult(body: data, metadata: metadata, finalURL: httpResp.url ?? url)
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
    public static func decodeBase64(_ s: String) -> String? {
        // Subscription base64 may be without padding — pad to multiple of 4.
        var padded = s.replacingOccurrences(of: "\n", with: "")
                      .replacingOccurrences(of: " ", with: "")
        // Some subscription endpoints use URL-safe base64.
        padded = padded.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - padded.count % 4) % 4
        padded += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: padded) else { return nil }
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
    /// Покрывает: `localhost`, IPv4 loopback `127.0.0.0/8`, link-local `169.254.0.0/16`,
    /// RFC-1918 `10.0.0.0/8` + `172.16.0.0/12` + `192.168.0.0/16`, `0.0.0.0/8`,
    /// multicast `224.0.0.0/4`, reserved `240.0.0.0/4`, IPv6 `::1`, link-local `fe80::/10`,
    /// ULA `fc00::/7` (fc/fd prefixes).
    ///
    /// **Accepted risk:** DNS-rebinding атака (host resolves в blocked IP после
    /// passes string check) НЕ закрыта в Phase 3 — потребует custom URLSession
    /// resolver. Carry-forward → Phase 7 (DPI-08 cert pinning + connection guards).
    ///
    /// Phase 8 W0 — promoted public для reuse из RulesEngine.RulesFetcher
    /// (см. .planning/phases/08-rules-engine-split-tunneling/08-RESEARCH.md § Validation Architecture Risk #1).
    public static func isBlockedHost(_ rawHost: String) -> Bool {
        let host = normalizeHostForLog(rawHost)
        guard !host.isEmpty else { return true }

        // Exact-match: localhost + IPv6 loopback + IPv4 all-zeros.
        let exactBlocked: Set<String> = ["localhost", "::1", "0.0.0.0"]
        if exactBlocked.contains(host) { return true }

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

        // IPv6 link-local fe80::/10 — `hasPrefix("fe80:")` достаточно (нет коротких
        // префиксов fe8 типа fe8a).
        if host.hasPrefix("fe80:") { return true }

        // IPv6 ULA fc00::/7 — fc-/fd-prefixes. Защита от false-positive «fc.example.com»:
        // ULA hostname обязан содержать `:`, а DNS-имя — точку без `:`. Проверяем оба.
        if (host.hasPrefix("fc") || host.hasPrefix("fd")) && host.contains(":") {
            return true
        }

        return false
    }
}
