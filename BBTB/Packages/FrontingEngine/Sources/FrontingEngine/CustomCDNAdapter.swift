import Foundation

/// Phase 10 / DPI-06 / D-04 — Generic custom CDN adapter.
///
/// **Use case:** Admin's own reverse proxy / self-hosted CDN / any provider not in the
/// predefined list (Cloudflare/Fastly). Applies identical overlay logic без CDN-specific
/// assumptions о header naming или edge behavior.
///
/// **Admin configuration:** connectHost points to the admin's proxy IP/domain;
/// sniHost = the proxy's TLS hostname; httpHost = the upstream VPN origin hostname.
/// The proxy is expected to forward based on HTTP Host header or SNI.
///
/// **D-05 blacklist:** Same as other adapters (TUIC / Hysteria2 / Reality / Vision).
public enum CustomCDNAdapter: CDNProviderAdapter {

    public static let provider: CDNProvider = .custom
    public static let displayName: String = "Custom CDN"

    @discardableResult
    public static func applyFronting(to outbound: inout [String: Any], profile: FrontingProfile) -> Bool {
        // MARK: D-05 blacklist checks

        if let type_ = outbound["type"] as? String,
           (type_ == "tuic" || type_ == "hysteria2") {
            return false
        }

        if let tls = outbound["tls"] as? [String: Any],
           let reality = tls["reality"] as? [String: Any],
           let enabled = reality["enabled"] as? Bool,
           enabled == true {
            return false
        }

        if let flow = outbound["flow"] as? String,
           flow == "xtls-rprx-vision" {
            return false
        }

        // MARK: Step 1 — Override dial target
        outbound["server"] = profile.connectHost
        outbound["server_port"] = profile.connectPort

        // MARK: Step 2 — Override TLS SNI
        var tls: [String: Any] = (outbound["tls"] as? [String: Any]) ?? [:]
        tls["server_name"] = profile.sniHost
        outbound["tls"] = tls

        // MARK: Step 3 — Override transport-specific Host header
        guard var transport = outbound["transport"] as? [String: Any] else {
            return true
        }

        let transportType = transport["type"] as? String ?? ""
        switch transportType {
        case "ws":
            var headers: [String: Any] = (transport["headers"] as? [String: Any]) ?? [:]
            headers["Host"] = profile.httpHost
            transport["headers"] = headers

        case "httpupgrade":
            transport["host"] = profile.httpHost

        case "grpc":
            break

        default:
            break
        }

        outbound["transport"] = transport
        return true
    }
}
