import Foundation

/// Phase 10 / DPI-06 / D-04, D-05 — Cloudflare CDN provider adapter.
///
/// **Cloudflare-specific fronting strategy:**
/// - Anycast edge IPs (1.1.1.1, 104.x.x.x) accept any SNI in Cloudflare's cert pool.
/// - Cloudflare SaaS (Custom Hostnames) позволяет admin'у зарегистрировать origin hostname
///   под чужим Cloudflare-hosted SNI (sniHost).
/// - HTTP Host header должен совпадать с target backend hostname (httpHost).
///
/// **Pitfall note (RESEARCH.md §Pitfall 3):** Classic domain fronting (SNI = CDN, Host = target)
/// заблокирован Cloudflare с 2018 для free-tier accounts. Admin должен использовать
/// Cloudflare SaaS или Cloudflare Tunnel (argo) — это ответственность admin'а, не клиента.
/// Клиент просто выполняет overlay согласно FrontingProfile.
///
/// **D-05 blacklist:** TUIC / Hysteria2 (own crypto, CDN CONNECT-через-TLS не применимо);
/// Reality (XTLS X25519 proof, CDN не может MITM SNI); Vision flow (TLS-in-TLS).
public enum CloudflareAdapter: CDNProviderAdapter {

    public static let provider: CDNProvider = .cloudflare
    public static let displayName: String = "Cloudflare"

    @discardableResult
    public static func applyFronting(to outbound: inout [String: Any], profile: FrontingProfile) -> Bool {
        // MARK: D-05 blacklist checks

        // 1. TUIC / Hysteria2: own crypto обфускация incompatible with CDN CONNECT proxy.
        if let type_ = outbound["type"] as? String,
           (type_ == "tuic" || type_ == "hysteria2") {
            return false
        }

        // 2. XTLS Reality: X25519 proof makes SNI substitution detectable; CDN can't MITM.
        if let tls = outbound["tls"] as? [String: Any],
           let reality = tls["reality"] as? [String: Any],
           let enabled = reality["enabled"] as? Bool,
           enabled == true {
            return false
        }

        // 3. XTLS Vision flow: TLS-in-TLS режим несовместим с CDN transparent proxy.
        if let flow = outbound["flow"] as? String,
           flow == "xtls-rprx-vision" {
            return false
        }

        // MARK: Step 1 — Override dial target (outbound.server / outbound.server_port)
        outbound["server"] = profile.connectHost
        outbound["server_port"] = profile.connectPort

        // MARK: Step 2 — Override TLS SNI (outbound.tls.server_name)
        var tls: [String: Any] = (outbound["tls"] as? [String: Any]) ?? [:]
        tls["server_name"] = profile.sniHost
        outbound["tls"] = tls

        // MARK: Step 3 — Override transport-specific Host header
        guard var transport = outbound["transport"] as? [String: Any] else {
            // TCP / nil transport — server+SNI override sufficient for CDN CONNECT.
            return true
        }

        let transportType = transport["type"] as? String ?? ""
        switch transportType {
        case "ws":
            // WebSocket: override transport.headers.Host
            var headers: [String: Any] = (transport["headers"] as? [String: Any]) ?? [:]
            headers["Host"] = profile.httpHost
            transport["headers"] = headers

        case "httpupgrade":
            // HTTPUpgrade: override transport.host
            transport["host"] = profile.httpHost

        case "grpc":
            // gRPC: :authority header is determined by TLS SNI (already overridden above).
            // transport.service_name must remain unchanged (routing identifier to backend).
            break

        default:
            // Unknown transport type — skip (defense-in-depth; don't corrupt unknown fields).
            break
        }

        outbound["transport"] = transport
        return true
    }
}
