import Foundation
import VPNCore
import VLESSReality
import VLESSTLS
import Trojan
import Shadowsocks
import Hysteria2

/// PROTO-10 — собирает N supported outbounds + urltest selector + dns + route в один
/// sing-box config JSON.
///
/// **Degenerate case (RESEARCH §6.5):** ровно 1 supported outbound → НЕ генерируем urltest;
/// route.final = тег единственного outbound. Это упрощает Phase 1 single-server path.
///
/// **256KB iOS limit mitigation (RESEARCH §9.5):** capping at 50 outbounds.
///
/// **R1 invariants (sanity, не validate — validate вызывается caller'ом):**
/// - `experimental: {}` empty.
/// - `insecure: false` для всех TLS блоков.
/// - Никаких clash_api / v2ray_api / cache_file.
public enum PoolBuilder {

    public enum PoolError: Error, LocalizedError, Equatable {
        case noSupportedServers
        case serialisationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noSupportedServers: return "PoolBuilder requires at least 1 supported config"
            case .serialisationFailed(let s): return "Pool JSON serialisation failed: \(s)"
            }
        }
    }

    /// Builds a sing-box configuration JSON from N supported servers.
    /// - ≥2 supported → outbounds + urltest selector + direct + dns/route → urltest-out.
    /// - 1 supported → degenerate (no urltest), route.final = single outbound tag.
    /// - 0 supported → throws .noSupportedServers.
    ///
    /// **Phase 6 / NET-01..NET-04 (D-01..D-04):** `dns` parameter threads bootstrap +
    /// tunnel DoH addresses into `dns.servers[*].address`. Default = `DNSConfig.default`
    /// (Cloudflare) — backward compat for Phase 1-5 callers. ConfigImporter (Wave 5)
    /// overrides with server-IP-aware bootstrap + user AdBlock / customDNS settings.
    public static func buildSingBoxJSON(
        from supportedConfigs: [AnyParsedConfig],
        dns: DNSConfig = .default
    ) throws -> String {
        let truncated = Array(supportedConfigs.prefix(50))  // RESEARCH §9.5 — iOS 256KB limit
        guard !truncated.isEmpty else { throw PoolError.noSupportedServers }

        var outbounds: [[String: Any]] = []
        var tags: [String] = []
        // Phase 5 Wave 7 (D-15) — coordinator pattern: each protocol package owns its
        // outbound assembly. PoolBuilder is a thin coordinator — 5 one-liner calls.
        for (index, parsed) in truncated.enumerated() {
            let tag: String
            let outbound: [String: Any]
            switch parsed {
            case .vlessReality(let v):
                tag = "vless-\(index)"
                outbound = VLESSReality.ConfigBuilder.buildOutbound(from: v, transport: .tcp, tag: tag)
            case .vlessTLS(let v):
                tag = "vless-tls-\(index)"
                outbound = VLESSTLS.ConfigBuilder.buildOutbound(from: v, transport: v.transport, tag: tag)
            case .trojan(let t):
                tag = "trojan-\(index)"
                outbound = Trojan.ConfigBuilder.buildOutbound(from: t, transport: t.transport, tag: tag)
            case .shadowsocks(let s):
                tag = "ss-\(index)"
                outbound = Shadowsocks.ConfigBuilder.buildOutbound(from: s, transport: .tcp, tag: tag)
            case .hysteria2(let h):
                tag = "hy2-\(index)"
                outbound = Hysteria2.ConfigBuilder.buildOutbound(from: h, transport: .tcp, tag: tag)
            }
            outbounds.append(outbound)
            tags.append(tag)
        }

        let finalTag: String
        if truncated.count == 1 {
            finalTag = tags[0]  // degenerate case — direct route.final
        } else {
            finalTag = "urltest-out"
            let urltest: [String: Any] = [
                "type": "urltest",
                "tag": "urltest-out",
                "outbounds": tags,
                "url": "https://cp.cloudflare.com/generate_204",
                "interval": "1m",
                "tolerance": 50,
                "idle_timeout": "30m",
                "interrupt_exist_connections": false,
            ]
            outbounds.append(urltest)
        }
        outbounds.append(["type": "direct", "tag": "direct"])

        let root: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "dns": dnsBlock(detour: finalTag, dns: dns),
            "outbounds": outbounds,
            "route": [
                "rules": [
                    ["action": "sniff", "timeout": "1s"],
                    ["protocol": "dns", "action": "hijack-dns"],
                ] as [Any],
                "final": finalTag,
                "auto_detect_interface": true,
            ],
            "experimental": [:],
        ]

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root, options: [])
        } catch {
            throw PoolError.serialisationFailed(error.localizedDescription)
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw PoolError.serialisationFailed("UTF-8 encode")
        }
        return json
    }

    // MARK: Phase 3 / Plan 05 — single-outbound builder

    /// Phase 3 / Plan 05 — pool с одним конкретным outbound (manual selection или
    /// auto-select winner). Thin wrapper над `buildSingBoxJSON` (degenerate-case
    /// path внутри уже корректно работает для 1 outbound — без urltest, route.final
    /// = tags[0]).
    ///
    /// Используется в MainScreenViewModel.performToggle:
    /// - Auto-mode → pre-connect ping → ServerScore.autoSelect → buildSingleOutboundJSON(winner).
    /// - Manual selection → buildSingleOutboundJSON(selected).
    ///
    /// **Phase 6 / NET-01..NET-04:** `dns` parameter threaded through to underlying
    /// `buildSingBoxJSON`. Default = `DNSConfig.default` (Cloudflare, backward compat).
    public static func buildSingleOutboundJSON(
        from parsed: AnyParsedConfig,
        dns: DNSConfig = .default
    ) throws -> String {
        return try buildSingBoxJSON(from: [parsed], dns: dns)
    }

    /// DNS block matching PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
    /// structure, with detour parameterised. Phase 6 / NET-01..NET-04 (D-01..D-04):
    /// `dns-bootstrap.address` and `dns-remote.address` read from `DNSConfig`. The
    /// previous Russian-DNS bootstrap hardcode is gone (D-01 mandate — see
    /// `.planning/phases/06-network-resilience/06-CONTEXT.md` Decision D-01).
    ///
    /// All other fields (rules, fakeip, final=dns-remote, strategy=ipv4_only,
    /// independent_cache=true) are R10 invariants and stay unchanged.
    private static func dnsBlock(detour: String, dns: DNSConfig) -> [String: Any] {
        return [
            "servers": [
                [
                    "tag": "dns-remote",
                    "address": dns.dohAddress(),
                    "address_resolver": "dns-bootstrap",
                    "address_strategy": "ipv4_only",
                    "detour": detour,
                ] as [String: Any],
                [
                    "tag": "dns-bootstrap",
                    "address": dns.bootstrapAddress,
                    "detour": "direct",
                    "strategy": "ipv4_only",
                ] as [String: Any],
                [
                    "tag": "dns-fakeip",
                    "address": "fakeip",
                ] as [String: Any],
            ] as [Any],
            "rules": [
                ["outbound": "any", "server": "dns-bootstrap"] as [String: Any],
                ["query_type": ["HTTPS", "SVCB"], "action": "predefined", "rcode": "NXDOMAIN"] as [String: Any],
                ["query_type": ["A", "AAAA"], "server": "dns-fakeip"] as [String: Any],
            ] as [Any],
            "fakeip": [
                "enabled": true,
                "inet4_range": "100.64.0.0/10",
                "inet6_range": "fc00::/18",
            ] as [String: Any],
            "final": "dns-remote",
            "strategy": "ipv4_only",
            "independent_cache": true,
        ]
    }
}
