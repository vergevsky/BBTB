import Foundation
import VPNCore

// ParsedTrojan relocated to VPNCore/Sources/VPNCore/ParsedConfigs.swift (Phase 5 Wave 6).
// Available here via `import VPNCore`.

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

        // Phase 5 D-09 — делегируем парсинг transport-params в TransportParamParser.
        // Trojan-specific reviewer choice (Plan 05-02 §2 alternative): сохраняем SNI
        // fallback для WS-host=пусто (Phase 2 backward-compat invariant — fixture
        // trojan-ws-user-fixture.txt полагается на это).
        let parsedTransport: TransportConfig
        do {
            parsedTransport = try TransportParamParser.parse(query: q)
        } catch TransportParamParser.ParserError.wsMissingPath {
            throw TrojanURIError.invalidTransport("ws-missing-path")
        } catch {
            // TransportParamParser.ParserError.unsupportedType / httpMissingPath /
            // httpUpgradeMissingPath. Для Trojan сейчас только tcp/ws — остальные
            // приходят с типизированными errors, мы их сворачиваем в одну
            // invalidTransport ошибку с typeRaw для logging.
            let typeRaw = (q["type"] ?? "tcp").lowercased()
            throw TrojanURIError.invalidTransport(typeRaw)
        }
        // Trojan reviewer-choice host fallback: при WS-без-host подставляем SNI
        // (preserve существующее поведение Phase 2 для backward-compat fixture).
        let transport: TransportConfig
        if case let .ws(path, host) = parsedTransport, host.isEmpty {
            transport = .ws(path: path, host: sni)
        } else {
            transport = parsedTransport
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
