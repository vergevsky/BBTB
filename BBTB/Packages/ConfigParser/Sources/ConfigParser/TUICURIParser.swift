import Foundation
import VPNCore

/// PROTO-08 Phase 7a Wave 1 — TUIC v5 URI parser.
///
/// URI format (de facto standard, см. Codex thread `019e26cb-cf49-78c3-af80-d437a5b22f28`):
///
///     tuic://<uuid>:<password>@<host>:<port>?
///       congestion_control=<bbr|cubic|new_reno>&
///       udp_relay_mode=<native|quic>&
///       sni=<domain>&
///       alpn=<csv>&
///       fp=<utls_fingerprint>&
///       pinSHA256=<hex>
///       #<remark>
///
/// **R1 STRICT** (отличие от Hysteria2): `insecure=1` (и синонимы) **игнорируется**.
/// TUIC v5 НЕ получает Hysteria2-style allowInsecure exception. Серверы с self-signed
/// certs должны использовать `pinSHA256=<hex>` для cert trust establishment.
///
/// **Defaults:**
/// - `congestion_control`: "bbr" (sing-box рекомендация для QUIC)
/// - `udp_relay_mode`: "native" (TUIC v5 default per upstream docs)
/// - `sni`: host fallback если query не указывает
/// - `alpn`: ["h3"] (TUIC v5 = QUIC = HTTP/3 — mandatory)
/// - `fp`: "chrome" (Wave 2 D-05 перейдёт на "random" smart default)
public enum TUICURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingUUID
    case missingPassword
    case unsupportedCongestionControl(String)
    case unsupportedUDPRelayMode(String)

    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed tuic:// URI"
        case .missingUUID: return "TUIC URI missing UUID (userinfo before ':')"
        case .missingPassword: return "TUIC URI missing password (userinfo after ':')"
        case .unsupportedCongestionControl(let cc):
            return "TUIC congestion_control \"\(cc)\" not supported (allowed: cubic, new_reno, bbr)"
        case .unsupportedUDPRelayMode(let m):
            return "TUIC udp_relay_mode \"\(m)\" not supported (allowed: native, quic)"
        }
    }
}

public enum TUICURIParser {
    public static func parse(_ uri: String) throws -> ParsedTUIC {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              scheme == "tuic",
              let host = comps.host, !host.isEmpty,
              let user = comps.user
        else { throw TUICURIError.malformedURI }

        // TUIC v5 URI: userinfo = "<uuid>:<password>". URLComponents разбивает по ':'
        // в `user` и `password`. Оба обязательны.
        let uuid = (user.removingPercentEncoding ?? user).trimmingCharacters(in: .whitespaces)
        guard !uuid.isEmpty else { throw TUICURIError.missingUUID }

        guard let rawPassword = comps.password else { throw TUICURIError.missingPassword }
        let password = (rawPassword.removingPercentEncoding ?? rawPassword)
            .trimmingCharacters(in: .whitespaces)
        guard !password.isEmpty else { throw TUICURIError.missingPassword }

        let port = comps.port ?? 443

        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }

        // congestion_control whitelist — sing-box принимает только эти три значения.
        let congestionControlRaw = q["congestion_control"] ?? q["congestion-control"]
            ?? q["congestion_controller"] ?? "bbr"
        let congestionControl = congestionControlRaw.trimmingCharacters(in: .whitespaces).lowercased()
        guard ParsedTUIC.supportedCongestionControl.contains(congestionControl) else {
            throw TUICURIError.unsupportedCongestionControl(congestionControl)
        }

        // udp_relay_mode whitelist.
        let udpRelayModeRaw = q["udp_relay_mode"] ?? q["udp-relay-mode"] ?? "native"
        let udpRelayMode = udpRelayModeRaw.trimmingCharacters(in: .whitespaces).lowercased()
        guard ParsedTUIC.supportedUDPRelayMode.contains(udpRelayMode) else {
            throw TUICURIError.unsupportedUDPRelayMode(udpRelayMode)
        }

        // SNI — mandatory (R1); fallback to host если query не указывает.
        let sni = q["sni"] ?? host

        // ALPN — TUIC v5 mandatory ["h3"] (QUIC = HTTP/3). Если URI указывает alpn, парсим CSV.
        let alpn: [String] = {
            guard let raw = q["alpn"]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
                return ["h3"]
            }
            let items = raw.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            return items.isEmpty ? ["h3"] : items
        }()

        // uTLS fingerprint — Phase 7a Wave 2 DPI-01 smart default: "random" (was "chrome").
        let fingerprintRaw = q["fp"] ?? q["fingerprint"] ?? ""
        let fingerprint = fingerprintRaw.trimmingCharacters(in: .whitespaces).isEmpty
            ? "random"
            : fingerprintRaw.trimmingCharacters(in: .whitespaces)

        // R1 STRICT: TUIC v5 игнорирует `insecure=1` (отличие от Hysteria2 D-08 exception).
        // Параметр в URI просто не читается — pinSHA256 единственный way to handle self-signed certs.

        // pinSHA256 — optional certificate pinning.
        let pinSHA256 = q["pinSHA256"]?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? q["pinSHA256"]
            : nil

        return ParsedTUIC(
            host: host,
            port: port,
            uuid: uuid,
            password: password,
            congestionControl: congestionControl,
            udpRelayMode: udpRelayMode,
            sni: sni,
            alpn: alpn,
            fingerprint: fingerprint,
            pinSHA256: pinSHA256,
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
