import Foundation

/// Phase 10 / DPI-06 / D-04 — Fastly CDN provider adapter.
///
/// **Fastly-specific fronting strategy:**
/// - Fastly anycast edge accepts SNI-based virtual hosting via Fastly Shielding.
/// - Transport-level overlay identifcal к Cloudflare (same sing-box field mapping).
/// - Fastly-specific header customization (если потребуется) — расширять здесь в v0.11+.
///
/// **v0.10 scope:** Behavior identical к CloudflareAdapter (same sing-box transport mappings).
/// Separate type для:
/// a) UI differentiation (displayName = "Fastly" в Advanced Settings CDN picker)
/// b) FrontingFailureCache keyed per provider (Cloudflare failure != Fastly failure)
/// c) Future Fastly-specific header extensions без breaking changes.
///
/// **D-05 blacklist:** Same as CloudflareAdapter (TUIC / Hysteria2 / Reality / Vision).
public enum FastlyAdapter: CDNProviderAdapter {

    public static let provider: CDNProvider = .fastly
    public static let displayName: String = "Fastly"

    @discardableResult
    public static func applyFronting(to outbound: inout [String: Any], profile: FrontingProfile) -> Bool {
        // T-B10 (closes C7-001 HIGH): allowlist — see CloudflareAdapter docstring
        // for rationale. Only vless / trojan with non-reality, non-vision configs.
        guard let type_ = outbound["type"] as? String,
              type_ == "vless" || type_ == "trojan"
        else { return false }

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
