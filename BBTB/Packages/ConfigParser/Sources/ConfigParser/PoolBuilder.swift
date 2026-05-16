import Foundation
import os
import VPNCore
import VLESSReality
import VLESSTLS
import Trojan
import Shadowsocks
import Hysteria2
import TUIC  // Phase 7a Wave 1 — PROTO-08

/// T-B11 (closes C8-002, C8-004, C8-006, C8-008, C8-010, C8-012 — 6 HIGH)
/// logger для PoolBuilder pre-build validation skips.
private let poolBuilderLogger = Logger(subsystem: "app.bbtb.client", category: "pool-builder")

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
        // Phase 10 / DPI-09 — global uTLS picker override.
        // Priority: URI fp= param (non-"random") > @AppStorage picker > Phase 7a default "random".
        // Logic: if picker is "random" → no override (leave protocol defaults and URI-set values).
        //        if picker is non-"random" → override ONLY outbounds whose current fingerprint == "random"
        //        (= URI did NOT set an explicit fp= param; Phase 7a default applies).
        // This preserves URI-explicit fingerprints (e.g. fp=firefox) while applying user's
        // global preference to servers that rely on the "random" Phase 7a smart default.
        let utlsPickerOverride: String? = {
            let picker = UserDefaults(suiteName: "group.app.bbtb.shared")?
                .string(forKey: "app.bbtb.utlsFingerprint") ?? "random"
            return picker == "random" ? nil : picker
        }()

        for (index, parsed) in truncated.enumerated() {
            // T-B11 (closes C8-002, C8-004, C8-006, C8-008, C8-010, C8-012):
            // pre-validate each Parsed* config before calling buildOutbound. Single-template
            // path (each protocol's buildSingBoxJSON) validates inline, но buildOutbound dict
            // path historically trusted public initializers. URI parsers already validate,
            // но programmatic constructors могли bypass. Centralized validation here defends
            // против malformed configs reaching sing-box.
            if !isValidPoolEntry(parsed) {
                continue
            }
            let tag: String
            var outbound: [String: Any]
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
            case .tuic(let t):
                tag = "tuic-\(index)"
                outbound = TUIC.ConfigBuilder.buildOutbound(from: t, transport: .tcp, tag: tag)
            }
            // Apply uTLS picker override: replace "random" fingerprint with user-chosen value.
            if let override = utlsPickerOverride {
                applyUTLSPickerOverride(&outbound, fingerprint: override)
            }
            outbounds.append(outbound)
            tags.append(tag)
        }
        // Re-check that at least one valid outbound survived validation.
        guard !outbounds.isEmpty else {
            throw PoolError.noSupportedServers
        }

        let finalTag: String
        // T-B11: degenerate path checks `outbounds.count`, NOT `truncated.count`, since
        // entries могли быть skipped by isValidPoolEntry above.
        if outbounds.count == 1 {
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

    // MARK: Phase 10 / DPI-09 — uTLS picker override helper

    /// Applies the global uTLS fingerprint picker override to a single outbound dictionary.
    ///
    /// **Override rule:** Only fingerprints currently set to "random" are replaced.
    /// "random" = Phase 7a smart default (URI did NOT provide an explicit `fp=` parameter).
    /// Non-"random" fingerprints (e.g. "chrome", "firefox" from explicit `fp=` in URI) are
    /// preserved — URI-explicit values take precedence over the global picker.
    ///
    /// **Protocols handled:** VLESS+TLS / VLESS+Vision (tls.utls.fingerprint),
    /// Trojan (tls.utls.fingerprint), TUIC (tls.utls.fingerprint).
    /// VLESS+Reality uses tls.reality.utls — handled via tls.utls.fingerprint path (same key).
    /// Shadowsocks and Hysteria2 do not have tls.utls → no-op for those outbounds.
    private static func applyUTLSPickerOverride(
        _ outbound: inout [String: Any],
        fingerprint: String
    ) {
        guard var tls = outbound["tls"] as? [String: Any],
              var utls = tls["utls"] as? [String: Any],
              let current = utls["fingerprint"] as? String,
              current == "random"
        else { return }  // No tls.utls.fingerprint or it's not the default "random" → skip.
        utls["fingerprint"] = fingerprint
        tls["utls"] = utls
        outbound["tls"] = tls
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

    /// DNS block matching PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json
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

    // MARK: - T-B11 — pre-build validation gate

    /// T-B11 (closes C8-002, C8-004, C8-006, C8-008, C8-010, C8-012 — 6 HIGH):
    /// validate each Parsed* config against same invariants the per-protocol
    /// `buildSingBoxJSON` template path enforces. Returns false (skip) if invalid;
    /// emits warning log. URI parsers already validate so production flows rarely
    /// hit this gate, но programmatic constructors / future test paths could.
    ///
    /// **Validation matrix per protocol:**
    /// - VLESS Reality: port 1..65535, non-empty host, publicKey, sni
    /// - VLESS TLS: port 1..65535, non-empty host, sni
    /// - Trojan: port 1..65535, non-empty host, password, sni
    /// - Shadowsocks: port 1..65535, non-empty host, method, password
    /// - Hysteria2: port 1..65535, non-empty host, auth, sni
    /// - TUIC: port 1..65535, non-empty host, uuid, password, sni, congestionControl
    ///   in supportedCongestionControl, udpRelayMode in supportedUDPRelayMode
    private static func isValidPoolEntry(_ parsed: AnyParsedConfig) -> Bool {
        let validRange = 1...65535
        switch parsed {
        case .vlessReality(let v):
            guard validRange.contains(v.port), !v.host.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping VLESS Reality invalid host/port")
                return false
            }
            guard !v.publicKey.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping VLESS Reality empty publicKey")
                return false
            }
            guard !v.sni.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping VLESS Reality empty sni")
                return false
            }
            return true
        case .vlessTLS(let v):
            guard validRange.contains(v.port), !v.host.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping VLESS TLS invalid host/port")
                return false
            }
            return true
        case .trojan(let t):
            guard validRange.contains(t.port), !t.host.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Trojan invalid host/port")
                return false
            }
            guard !t.password.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Trojan empty password")
                return false
            }
            guard !t.sni.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Trojan empty sni")
                return false
            }
            return true
        case .shadowsocks(let s):
            guard validRange.contains(s.port), !s.host.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Shadowsocks invalid host/port")
                return false
            }
            guard !s.method.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Shadowsocks empty method")
                return false
            }
            guard !s.password.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Shadowsocks empty password")
                return false
            }
            // SS method whitelist: matches ShadowsocksURIParser.supportedSSMethods
            // (declared в ConfigParser, same module — direct reference).
            guard ShadowsocksURIParser.supportedSSMethods.contains(s.method) else {
                poolBuilderLogger.warning("PoolBuilder: skipping Shadowsocks unsupported method")
                return false
            }
            return true
        case .hysteria2(let h):
            guard validRange.contains(h.port), !h.host.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Hysteria2 invalid host/port")
                return false
            }
            guard !h.auth.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Hysteria2 empty auth")
                return false
            }
            guard !h.sni.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping Hysteria2 empty sni")
                return false
            }
            return true
        case .tuic(let t):
            guard validRange.contains(t.port), !t.host.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping TUIC invalid host/port")
                return false
            }
            guard !t.uuid.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping TUIC empty uuid")
                return false
            }
            guard !t.password.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping TUIC empty password")
                return false
            }
            guard !t.sni.isEmpty else {
                poolBuilderLogger.warning("PoolBuilder: skipping TUIC empty sni")
                return false
            }
            guard ParsedTUIC.supportedCongestionControl.contains(t.congestionControl) else {
                poolBuilderLogger.warning("PoolBuilder: skipping TUIC unsupported congestion_control")
                return false
            }
            guard ParsedTUIC.supportedUDPRelayMode.contains(t.udpRelayMode) else {
                poolBuilderLogger.warning("PoolBuilder: skipping TUIC unsupported udp_relay_mode")
                return false
            }
            return true
        }
    }
}
