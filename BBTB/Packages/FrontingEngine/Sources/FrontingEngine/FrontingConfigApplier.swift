import Foundation

/// Phase 10 / DPI-06 / D-05 — JSON overlay для CDN-фронтинга над expandConfigForTunnel output.
///
/// **Design:** Pure static function — zero instance state, thread-safe, actor-friendly.
/// Mirrors `SingBoxConfigLoader.expandConfigForTunnel` approach: deserialize JSON dict →
/// mutate outbound fields → re-serialize. Pattern source: 08-PATTERNS.md Pattern 5.
///
/// **D-05 blacklist** делегируется в adapter.applyFronting — каждый outbound решает
/// сам на основе type / tls.reality.enabled / flow. Этот applier не дублирует логику.
///
/// **Usage pipeline (Plan 06 ConfigImporter wiring):**
/// 1. `expandConfigForTunnel` → sing-box JSON string
/// 2. `FrontingConfigApplier.apply(json: singBoxJSON, profile: profile, adapter: CloudflareAdapter.self)`
/// 3. Pass modified JSON to BaseSingBoxTunnel (instead of raw expandConfigForTunnel output)
///
/// **Threat T-10-W5-05:** D-05 blacklist в adapters защищает Reality/Vision outbounds
/// от ошибочного overlay. Tests 4-7 в FrontingConfigApplierTests покрывают.
public enum FrontingConfigApplier {

    // MARK: - Batch JSON variant

    /// Применить CDN overlay к всем outbounds в sing-box JSON строке.
    ///
    /// - Parameters:
    ///   - json:    Полный sing-box JSON string (output от `expandConfigForTunnel`).
    ///   - profile: CDN dial target overlay (sniHost, httpHost, connectHost, connectPort).
    ///   - adapter: CDN provider adapter type (CloudflareAdapter.self / FastlyAdapter.self / etc.).
    /// - Returns: Модифицированный JSON string со всеми совместимыми outbounds overridden.
    /// - Throws:  `FrontingError.malformedJSON` если input не парсится или output не сериализуется.
    ///
    /// Incompatible outbounds (Reality/TUIC/Hysteria2/Vision) возвращаются неизменёнными —
    /// adapter.applyFronting вернёт false, изменения не применяются.
    /// **T-B6' (closes C7'-001 HIGH):** New `targetTag:` parameter scopes fronting overlay
    /// к single outbound matching `tag`. Previous behavior applied profile к ALL compatible
    /// outbounds в pool, breaking routing semantics when single server's CDN config
    /// overwrote unrelated VLESS/Trojan servers's connectHost/SNI.
    ///
    /// - Parameter targetTag: if non-nil, only mutate outbound с matching `tag` field.
    ///   If nil, applies к all compatible outbounds (legacy behavior; not used in production —
    ///   single-server path always knows its tag).
    public static func apply(
        json: String,
        profile: FrontingProfile,
        adapter: any CDNProviderAdapter.Type,
        targetTag: String? = nil
    ) throws -> String {
        try validateProfile(profile)

        guard let data = json.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw FrontingError.malformedJSON
        }

        var outbounds = (root["outbounds"] as? [[String: Any]]) ?? []

        for i in outbounds.indices {
            // T-B6' tag-scoped check: skip outbounds whose tag does not match target.
            if let targetTag = targetTag {
                let obTag = outbounds[i]["tag"] as? String
                if obTag != targetTag { continue }
            }
            var ob = outbounds[i]
            // Return value ignored — each outbound decides its own compatibility.
            _ = adapter.applyFronting(to: &ob, profile: profile)
            outbounds[i] = ob
        }

        root["outbounds"] = outbounds

        guard let modified = try? JSONSerialization.data(withJSONObject: root, options: []),
              let result = String(data: modified, encoding: .utf8)
        else {
            throw FrontingError.malformedJSON
        }

        return result
    }

    // MARK: - Single-outbound variant

    /// Применить CDN overlay к одному outbound dict (без JSON roundtrip).
    ///
    /// Inline вариант для использования в ConfigImporter когда outbound dict
    /// уже в памяти (zero-copy, no JSON serialization overhead).
    ///
    /// **T-B10 (closes C7-002 HIGH):** теперь throws + calls validateProfile.
    /// Previously this fast-path bypassed validateProfile, allowing localhost /
    /// private CDN targets если caller passed unvalidated FrontingProfile.
    /// Batch JSON path (apply(json:profile:adapter:)) already validates;
    /// inline path now matches.
    ///
    /// - Parameters:
    ///   - outbound: Mutable sing-box outbound dict.
    ///   - profile:  CDN overlay profile.
    ///   - adapter:  CDN provider adapter type.
    /// - Returns: `true` если overlay applied; `false` если outbound в blacklist.
    /// - Throws: `FrontingError.profileRejected` если profile host blocked.
    @discardableResult
    public static func apply(
        outbound: inout [String: Any],
        profile: FrontingProfile,
        adapter: any CDNProviderAdapter.Type
    ) throws -> Bool {
        try validateProfile(profile)
        return adapter.applyFronting(to: &outbound, profile: profile)
    }

    // MARK: - SSRF guard

    /// Reject profiles whose `connectHost` / `sniHost` / `httpHost` resolve to loopback,
    /// private, link-local, CGNAT, mDNS or other reserved ranges. Prevents a malicious
    /// admin subscription from redirecting tunnel traffic к local services on the device.
    ///
    /// **T-B10 (closes C7-003 MEDIUM):** extended coverage matching the canonical
    /// `SubscriptionURLFetcher.isBlockedHost` (но inline — FrontingEngine не зависит
    /// от ConfigParser архитектурно). Covers IPv6 ULA/link-local, IPv4-mapped IPv6,
    /// `.local` mDNS, CGNAT `100.64/10`, multicast/reserved IPv4. Also validates
    /// `connectPort` range 1..65535.
    ///
    /// **LOW C7'-003 ACK (drift risk):** SubscriptionURLFetcher.isBlockedHost (Plan 05
    /// T-A3') теперь использует numeric IP parsing через Network.framework
    /// `IPv4Address`/`IPv6Address`. Этот inline `isPrivateOrLoopback` пока остаётся
    /// string-based (regex'ы для compressed forms). При следующей крупной refactor:
    /// → consider extract'ить в shared `NetworkUtils` package (would add dep, но
    /// устраняет drift risk если SubscriptionURLFetcher логика evolves).
    /// Decision-log: `wiki/security-gaps.md` R25 § «v1.1+ TODO».
    ///
    /// Only the syntax of the string is checked (no DNS lookup) — DNS rebinding защита
    /// требует custom resolver (carry-forward к v1.1+).
    static func validateProfile(_ profile: FrontingProfile) throws {
        // T-B10 / C7-003: port range check.
        guard (1...65535).contains(profile.connectPort) else {
            throw FrontingError.profileRejected(host: "port \(profile.connectPort) out of range")
        }
        let hosts = [profile.connectHost, profile.sniHost, profile.httpHost]
        for host in hosts {
            if isPrivateOrLoopback(host) {
                throw FrontingError.profileRejected(host: host)
            }
        }
    }

    /// T-B10 (closes C7-003 MEDIUM): comprehensive blocklist matching extended
    /// `SubscriptionURLFetcher.isBlockedHost` (covers `.local`, CGNAT, IPv6 ULA/
    /// link-local, IPv4-mapped IPv6, multicast/reserved IPv4, localhost variants).
    private static func isPrivateOrLoopback(_ host: String) -> Bool {
        var lower = host.lowercased()
        // Bracketed IPv6 literal `[::1]` — strip brackets for matching.
        if lower.hasPrefix("[") && lower.hasSuffix("]") {
            lower = String(lower.dropFirst().dropLast())
        }
        guard !lower.isEmpty else { return true }

        // Exact match.
        let exactBlocked: Set<String> = ["localhost", "localhost.", "::1", "::", "0.0.0.0"]
        if exactBlocked.contains(lower) { return true }

        // mDNS .local suffix.
        if lower.hasSuffix(".local") || lower.hasSuffix(".local.") { return true }

        // IPv4 prefix blocklist.
        let ipv4Prefixes: [String] = [
            "127.", "10.", "169.254.", "192.168.", "0.",
            // Multicast 224..239
            "224.", "225.", "226.", "227.", "228.", "229.",
            "230.", "231.", "232.", "233.", "234.", "235.",
            "236.", "237.", "238.", "239.",
            // Reserved 240..255
            "240.", "241.", "242.", "243.", "244.", "245.",
            "246.", "247.", "248.", "249.", "250.",
            "251.", "252.", "253.", "254.", "255."
        ]
        if ipv4Prefixes.contains(where: { lower.hasPrefix($0) }) { return true }

        // 172.16.0.0/12 — second octet 16..31.
        if lower.hasPrefix("172.") {
            let parts = lower.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }

        // CGNAT 100.64.0.0/10 — second octet 64..127.
        if lower.hasPrefix("100.") {
            let parts = lower.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (64...127).contains(second) { return true }
        }

        // IPv6 link-local fe80::/10.
        if lower.hasPrefix("fe80:") { return true }

        // IPv6 ULA fc00::/7 — fc/fd with colons (hostname-vs-ULA disambiguation).
        if (lower.hasPrefix("fc") || lower.hasPrefix("fd")) && lower.contains(":") {
            return true
        }

        // IPv4-mapped IPv6: ::ffff:a.b.c.d.
        if lower.hasPrefix("::ffff:") {
            let ipv4Part = String(lower.dropFirst("::ffff:".count))
            if isPrivateOrLoopback(ipv4Part) { return true }
        }

        return false
    }
}
