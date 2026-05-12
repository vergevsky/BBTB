import Foundation

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
    public static func buildSingBoxJSON(from supportedConfigs: [AnyParsedConfig]) throws -> String {
        let truncated = Array(supportedConfigs.prefix(50))  // RESEARCH §9.5 — iOS 256KB limit
        guard !truncated.isEmpty else { throw PoolError.noSupportedServers }

        var outbounds: [[String: Any]] = []
        var tags: [String] = []
        for (index, parsed) in truncated.enumerated() {
            let tag: String
            let outbound: [String: Any]
            switch parsed {
            case .vlessReality(let v):
                tag = "vless-\(index)"
                outbound = buildVLESSOutbound(parsed: v, tag: tag)
            case .trojan(let t):
                tag = "trojan-\(index)"
                outbound = buildTrojanOutbound(parsed: t, tag: tag)
            case .vlessTLS(let v):
                // Phase 4 Plan 02 — PROTO-03 — VLESS+TLS (без Reality).
                tag = "vless-tls-\(index)"
                outbound = buildVLESSTLSOutbound(parsed: v, tag: tag)
            case .shadowsocks(let s):
                // Phase 4 Plan 03 — PROTO-04 — Shadowsocks (SIP002 + SIP022).
                tag = "ss-\(index)"
                outbound = buildShadowsocksOutbound(parsed: s, tag: tag)
            case .hysteria2(let h):
                // Phase 4 Plan 04 — PROTO-05 — Hysteria2 (D-08 R1 EXCEPTION).
                tag = "hy2-\(index)"
                outbound = buildHysteria2Outbound(parsed: h, tag: tag)
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
            "dns": dnsBlock(detour: finalTag),
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

    // MARK: Outbound builders

    private static func buildVLESSOutbound(parsed: ParsedVLESS, tag: String) -> [String: Any] {
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": parsed.sni,
            "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
        ]
        if !parsed.publicKey.isEmpty {
            tls["reality"] = [
                "enabled": true,
                "public_key": parsed.publicKey,
                "short_id": parsed.shortId,
            ]
        }
        return [
            "type": "vless",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid.uuidString.lowercased(),
            "flow": parsed.flow,
            "network": "tcp",
            "tls": tls,
        ]
    }

    /// Phase 4 Plan 02 — PROTO-03 — VLESS+TLS pool outbound.
    ///
    /// **R1 invariant — VLESS+TLS strict TLS (no Hy2-style exception).**
    /// `tls.insecure` хардкодим `false`; НЕ читаем из `ParsedVLESSTLS` (тот не содержит
    /// `allowInsecure` поля по дизайну — D-08 exception применяется ТОЛЬКО к Hysteria2,
    /// не к VLESS+TLS / Trojan / VLESS+Reality).
    ///
    /// Phase 5 D-05 — `parsed.networkType: String` мигрировано в `parsed.transport:
    /// TransportConfig`. Wave 1 (этот файл): outbound `network` поле — всегда
    /// `"tcp"`. Transport overlay в этом builder-е НЕ добавляется (Wave 5
    /// перенесёт построение outbound в protocol package + добавит transport
    /// блок через TransportRegistry).
    private static func buildVLESSTLSOutbound(parsed: ParsedVLESSTLS, tag: String) -> [String: Any] {
        let tls: [String: Any] = [
            "enabled": true,
            "server_name": parsed.sni,
            "insecure": false,  // R1 invariant — VLESS+TLS strict TLS (no Hy2-style exception)
            "alpn": parsed.alpn,
            "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
        ]
        return [
            "type": "vless",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid.uuidString.lowercased(),
            // Phase 1 W5 pattern — flow: пустая строка если nil (sing-box примет, нет Vision).
            "flow": parsed.flow ?? "",
            // Phase 5 Wave 1 — VLESS over transport overlay требует `network: "tcp"`
            // на уровне outbound; собственно overlay (ws / grpc / http) пойдёт через
            // `transport: {...}` блок начиная с Wave 5.
            "network": "tcp",
            "tls": tls,
        ]
    }

    /// Phase 4 Plan 03 — PROTO-04 — Shadowsocks pool outbound.
    ///
    /// **R1 invariant trivial:** Shadowsocks outbound НЕ содержит TLS block — encryption
    /// делается на уровне протокола, не TLS. Поэтому `insecure` поле отсутствует by design
    /// (нельзя случайно скопировать D-08 Hy2-style exception в SS outbound).
    /// `network: "tcp"` — Phase 4 не реализует UDP relay (sing-box поддерживает, но мы
    /// фиксируем TCP для consistent failover поведения).
    private static func buildShadowsocksOutbound(parsed: ParsedShadowsocks, tag: String) -> [String: Any] {
        return [
            "type": "shadowsocks",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "method": parsed.method,
            "password": parsed.password,
            "network": "tcp",
        ]
    }

    // ============================================================
    // R1 EXCEPTION — ONLY Hysteria2 (D-08).
    // This is the ONLY outbound builder in BBTB where tls.insecure
    // may legitimately be set to true. Copying this pattern to any
    // other protocol builder is a security bug (Pitfall 2).
    //
    // Mitigation layers:
    //   1. This comment block (code-level marker for PR review).
    //   2. test_nonHy2_outbounds_neverHaveInsecureTrue invariant
    //      test (test-level enforcement at CI gate).
    //   3. ParsedShadowsocks/ParsedVLESSTLS/ParsedTrojan structs
    //      do NOT have an allowInsecure field (type-level by design).
    //
    // See: wiki/security-gaps.md R17,
    //      .planning/phases/04-protocol-expansion/04-CONTEXT.md D-08.
    // ============================================================
    private static func buildHysteria2Outbound(parsed: ParsedHysteria2, tag: String) -> [String: Any] {
        // R1 EXCEPTION — only Hysteria2 (D-08). Любое появление этого поля
        // в другом builder'е = bug.
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": parsed.sni,
            "insecure": parsed.allowInsecure,
            "alpn": ["h3"],  // Hysteria2 = QUIC = HTTP/3 ALPN
        ]
        if let fp = parsed.fingerprint, !fp.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fp]
        } else {
            tls["utls"] = ["enabled": true, "fingerprint": "chrome"]
        }
        if let pin = parsed.pinSHA256, !pin.isEmpty {
            // sing-box принимает certificate_public_key_sha256 как массив строк.
            tls["certificate_public_key_sha256"] = [pin]
        }

        var outbound: [String: Any] = [
            "type": "hysteria2",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "password": parsed.auth,
            "tls": tls,
        ]
        if let obfs = parsed.obfs, obfs == "salamander",
           let obfsPwd = parsed.obfsPassword, !obfsPwd.isEmpty {
            outbound["obfs"] = ["type": "salamander", "password": obfsPwd]
        }
        return outbound
    }

    private static func buildTrojanOutbound(parsed: ParsedTrojan, tag: String) -> [String: Any] {
        // WS upgrade is HTTP/1.1 — if ALPN includes h2, server negotiates h2 and
        // rejects the upgrade (framing mismatch → i/o timeout). Strip h2 for WS.
        let isWS: Bool
        if case .ws = parsed.transport { isWS = true } else { isWS = false }
        let alpn: [String]
        if isWS {
            let filtered = parsed.alpn.filter { $0 != "h2" }
            alpn = filtered.isEmpty ? ["http/1.1"] : filtered
        } else {
            alpn = parsed.alpn
        }

        var outbound: [String: Any] = [
            "type": "trojan",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "password": parsed.password,
            "network": "tcp",
            "tls": [
                "enabled": true,
                "server_name": parsed.sni,
                "insecure": false,
                "alpn": alpn,
                "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
            ] as [String: Any],
        ]
        if case let .ws(path, host) = parsed.transport {
            let wsHost = host.isEmpty ? parsed.sni : host
            outbound["transport"] = [
                "type": "ws",
                "path": path,
                "headers": ["Host": wsHost],
            ] as [String: Any]
        }
        return outbound
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
    public static func buildSingleOutboundJSON(from parsed: AnyParsedConfig) throws -> String {
        return try buildSingBoxJSON(from: [parsed])
    }

    /// DNS block matching PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
    /// structure, with detour parameterised.
    private static func dnsBlock(detour: String) -> [String: Any] {
        return [
            "servers": [
                [
                    "tag": "dns-remote",
                    "address": "https://cloudflare-dns.com/dns-query",
                    "address_resolver": "dns-bootstrap",
                    "address_strategy": "ipv4_only",
                    "detour": detour,
                ] as [String: Any],
                [
                    "tag": "dns-bootstrap",
                    "address": "tcp://77.88.8.8",
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
