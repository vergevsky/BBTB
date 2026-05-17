import Foundation
import Network  // Plan 09 C7-4-001: IPv4Address/IPv6Address numeric parsers

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

    /// **Plan 09 C7-4-001 + A6-FE-3-002 (closes parallel drift к T-C-H3):**
    /// CDN profile validation now uses numeric IP parsers (Network.framework
    /// IPv4Address/IPv6Address) — mirroring SubscriptionURLFetcher.isBlockedHost
    /// в ConfigParser/SubscriptionURLFetcher.swift:352. Pre-fix string-based
    /// regex missed embedded-IPv4 prefixes (NAT64 `64:ff9b::a.b.c.d`, 6to4
    /// `2002:wxyz::`, IPv4-compatible `::w.x.y.z`) — real-world SSRF bypass на
    /// cellular networks where carriers translate NAT64 → IPv4.
    ///
    /// **Architectural note:** FrontingEngine не зависит от ConfigParser
    /// архитектурно (D-03: CDN config orthogonal к transport config). Numeric
    /// parsing logic заинлайнена в `isBlockedIPv4Bytes` / `isBlockedIPv6Bytes`
    /// здесь же. Drift mitigation на v1.1+: extract в shared NetworkUtils package
    /// (see wiki/security-gaps.md R25).
    ///
    /// **Covered IPv4 ranges:** 0.0.0.0/8, 10/8, 100.64/10 CGNAT, 127/8, 169.254/16,
    /// 172.16/12, 192.168/16, 224/4 multicast, 240/4 reserved.
    ///
    /// **Covered IPv6 ranges:** ::/128, ::1/128, fe80::/10, fc00::/7, ff00::/8,
    /// IPv4-mapped (::ffff:/96), NAT64 (64:ff9b::/96), 6to4 (2002::/16),
    /// IPv4-compatible (::w.x.y.z) — все re-classify embedded IPv4 portion.
    ///
    /// **DNS rules** (non-IP hosts): exact-match localhost variants + `.local` mDNS.
    private static func isPrivateOrLoopback(_ host: String) -> Bool {
        var lower = host.lowercased()
        // Bracketed IPv6 literal `[::1]` — strip brackets for parsing.
        if lower.hasPrefix("[") && lower.hasSuffix("]") {
            lower = String(lower.dropFirst().dropLast())
        }
        guard !lower.isEmpty else { return true }

        // T-A3' security posture: reject any host containing IPv6 scope id (`%`).
        if lower.contains("%") || lower.contains("%25") { return true }

        // Try numeric IPv4 parse first.
        if let v4 = IPv4Address(lower) {
            return isBlockedIPv4Bytes(v4.rawValue)
        }
        // Try numeric IPv6 parse.
        if let v6 = IPv6Address(lower) {
            return isBlockedIPv6Bytes(Array(v6.rawValue))
        }

        // Not an IP literal → DNS rules apply.
        let exactBlocked: Set<String> = ["localhost", "localhost."]
        if exactBlocked.contains(lower) { return true }
        if lower.hasSuffix(".local") || lower.hasSuffix(".local.") { return true }
        return false
    }

    /// Plan 09 C7-4-001: byte-wise IPv4 blocklist, mirrored from
    /// `SubscriptionURLFetcher.isBlockedIPv4Bytes` (ConfigParser).
    /// Operates on canonical 4-byte `Network.IPv4Address.rawValue`.
    private static func isBlockedIPv4Bytes(_ bytes: Data) -> Bool {
        guard bytes.count == 4 else { return true }
        let b0 = bytes[0]
        let b1 = bytes[1]
        if b0 == 0 { return true }                                       // 0.0.0.0/8
        if b0 == 10 { return true }                                      // 10.0.0.0/8
        if b0 == 100 && (64...127).contains(b1) { return true }          // 100.64/10 CGNAT
        if b0 == 127 { return true }                                     // 127.0.0.0/8
        if b0 == 169 && b1 == 254 { return true }                        // 169.254/16
        if b0 == 172 && (16...31).contains(b1) { return true }           // 172.16/12
        if b0 == 192 && b1 == 168 { return true }                        // 192.168/16
        if (224...239).contains(b0) { return true }                      // 224/4 multicast
        if (240...255).contains(b0) { return true }                      // 240/4 reserved
        return false
    }

    /// Plan 09 C7-4-001: byte-wise IPv6 blocklist, mirrored from
    /// `SubscriptionURLFetcher.isBlockedIPv6Bytes` (ConfigParser). Detects
    /// IPv4-mapped, NAT64, 6to4, and IPv4-compatible IPv6 — все re-classify
    /// embedded IPv4 portion через isBlockedIPv4Bytes.
    private static func isBlockedIPv6Bytes(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }
        if bytes.allSatisfy({ $0 == 0 }) { return true }                 // ::
        let isLoopback = bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] == 1
        if isLoopback { return true }                                    // ::1
        if bytes[0] == 0xFE && (0x80...0xBF).contains(bytes[1]) { return true }  // fe80::/10
        if bytes[0] == 0xFC || bytes[0] == 0xFD { return true }          // fc00::/7 ULA
        if bytes[0] == 0xFF { return true }                              // ff00::/8 multicast
        // IPv4-mapped ::ffff:/96
        let isMapped = bytes.prefix(10).allSatisfy({ $0 == 0 })
            && bytes[10] == 0xFF && bytes[11] == 0xFF
        if isMapped { return isBlockedIPv4Bytes(Data(bytes[12...15])) }
        // NAT64 well-known 64:ff9b::/96 (RFC 6052)
        let isNAT64 = bytes[0] == 0x00 && bytes[1] == 0x64
            && bytes[2] == 0xFF && bytes[3] == 0x9B
            && bytes[4..<12].allSatisfy({ $0 == 0 })
        if isNAT64 { return isBlockedIPv4Bytes(Data(bytes[12...15])) }
        // 6to4 2002::/16 (RFC 3056)
        if bytes[0] == 0x20 && bytes[1] == 0x02 {
            return isBlockedIPv4Bytes(Data(bytes[2...5]))
        }
        // IPv4-compatible ::w.x.y.z (RFC 4291 deprecated)
        let isCompat = bytes.prefix(12).allSatisfy({ $0 == 0 })
            && (bytes[12] != 0 || bytes[13] != 0 || bytes[14] != 0 || bytes[15] > 1)
        if isCompat { return isBlockedIPv4Bytes(Data(bytes[12...15])) }
        return false
    }
}
