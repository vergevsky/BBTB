import Foundation

/// PROTO-02 / D-08 — parser для `trojan://password@host:port?security=tls&type=ws&path=...&sni=...&fp=...#remarks`
public struct ParsedTrojan: Sendable, Equatable {
    public let password: String
    public let host: String
    public let port: Int
    public let security: String          // always "tls" в supported case
    public let sni: String                // mandatory (R1, D-08)
    public let fingerprint: String        // default "chrome"
    public let alpn: [String]             // default ["h2", "http/1.1"]
    public let transport: TransportType
    public let remarks: String?

    public enum TransportType: Sendable, Equatable {
        case tcp
        case ws(path: String, host: String)
    }

    public init(password: String, host: String, port: Int, security: String, sni: String,
                fingerprint: String, alpn: [String], transport: TransportType, remarks: String?) {
        self.password = password; self.host = host; self.port = port
        self.security = security; self.sni = sni; self.fingerprint = fingerprint
        self.alpn = alpn; self.transport = transport; self.remarks = remarks
    }
}

public enum TrojanURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingPassword
    case notTLSSecurity(String?)
    case invalidTransport(String)

    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed trojan:// URI"
        case .missingPassword: return "Trojan URI missing password"
        case .notTLSSecurity(let s): return "Trojan requires security=tls (got: \(s ?? "missing"))"
        case .invalidTransport(let t): return "Trojan unsupported transport: \(t)"
        }
    }
}

/// D-08 — strict Trojan URI parsing:
/// - `security` **must** equal "tls" (missing or any other value rejected — R1 принцип)
/// - `allowInsecure=1` parsed and **ignored** (security stays "tls")
/// - SNI fallback chain: query `sni` → query `peer` → URI authority host
/// - Fingerprint fallback: `fp` → `fingerprint` → "chrome" default
/// - Transport: `type=tcp` (default), `type=ws` (requires non-empty `path`); other → reject
public enum TrojanURIParser {
    public static func parse(_ uri: String) throws -> ParsedTrojan {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "trojan",
              let host = comps.host, !host.isEmpty,
              let port = comps.port,
              let user = comps.user
        else {
            throw TrojanURIError.malformedURI
        }

        // userinfo is the password (Trojan URI spec — no separate username field).
        let password = user.removingPercentEncoding ?? user
        guard !password.isEmpty else { throw TrojanURIError.missingPassword }

        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }

        // R1 (D-08) — security STRICT: required and must equal "tls".
        let security = q["security"]
        guard security?.lowercased() == "tls" else {
            throw TrojanURIError.notTLSSecurity(security)
        }

        // allowInsecure is parsed but explicitly ignored (R1: insecure=false hardcoded
        // в template — этот URI param не может произвести insecure outbound).
        _ = q["allowInsecure"]

        // SNI fallback chain.
        let sni = q["sni"] ?? q["peer"] ?? host

        // Fingerprint fallback. Trim — реальные URI часто имеют `fp=` (пустое значение)
        // или `fp= ` (пробел), что для sing-box utls.fingerprint невалидно. Default = "chrome".
        let fingerprint: String = {
            let raw = (q["fp"] ?? q["fingerprint"] ?? "").trimmingCharacters(in: .whitespaces)
            return raw.isEmpty ? "chrome" : raw
        }()

        // ALPN CSV.
        let alpn: [String]
        if let raw = q["alpn"] {
            alpn = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        } else {
            alpn = ["h2", "http/1.1"]
        }

        // Transport.
        let transport: ParsedTrojan.TransportType
        let typeRaw = (q["type"] ?? "tcp").lowercased()
        switch typeRaw {
        case "tcp":
            transport = .tcp
        case "ws":
            guard let path = q["path"], !path.isEmpty else {
                throw TrojanURIError.invalidTransport("ws-missing-path")
            }
            let wsHost = q["host"] ?? sni
            transport = .ws(path: path, host: wsHost)
        default:
            throw TrojanURIError.invalidTransport(typeRaw)
        }

        return ParsedTrojan(
            password: password,
            host: host,
            port: port,
            security: "tls",
            sni: sni,
            fingerprint: fingerprint,
            alpn: alpn,
            transport: transport,
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
