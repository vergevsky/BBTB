import Foundation
import VPNCore

public struct ParsedVLESS: Sendable, Equatable {
    public let uuid: UUID
    public let host: String
    public let port: Int
    public let flow: String
    public let security: String
    public let sni: String
    public let publicKey: String
    public let shortId: String
    public let fingerprint: String
    public let networkType: String
    public let remarks: String?

    public init(uuid: UUID, host: String, port: Int, flow: String, security: String,
                sni: String, publicKey: String, shortId: String, fingerprint: String,
                networkType: String, remarks: String?) {
        self.uuid = uuid; self.host = host; self.port = port; self.flow = flow
        self.security = security; self.sni = sni; self.publicKey = publicKey
        self.shortId = shortId; self.fingerprint = fingerprint
        self.networkType = networkType; self.remarks = remarks
    }
}

public enum VLESSURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case notRealityProtocol(String?)
    case unsupportedEncryption(String)
    // Phase 4 D-02: security=none / missing / other (не reality / не tls) — VLESS без TLS
    // нарушает R1 invariant (strict TLS). Возвращается из обновлённой parse(_:) сигнатуры.
    case unsupportedSecurity(String)
    // Phase 5 D-10 + Pitfall 10: VLESS+TLS URI с неизвестным `?type=` (например `quic`)
    // или с обязательным `?path=` отсутствующим. UniversalImportParser маршрутизирует
    // эту ошибку в `.unsupported(reason: .transportUnsupported)` — URI сохраняется в
    // `rawURI` для UI feedback. Reality branch (D-03) тип-only-TCP — этой ошибки не
    // выдаёт.
    case unsupportedTransport(String)

    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed vless:// URI"
        case .notRealityProtocol(let s): return "Not a Reality protocol URI (security=\(s ?? "missing"))"
        case .unsupportedEncryption(let e): return "Unsupported encryption: \(e) (only 'none' supported)"
        case .unsupportedSecurity(let s):
            return "Unsupported VLESS security: '\(s)' (R1 — only 'reality' or 'tls' accepted)"
        case .unsupportedTransport(let t):
            return "Unsupported VLESS+TLS transport: '\(t)'"
        }
    }
}

/// IMP-01 / PROTO-03 — parser для vless://{UUID}@{HOST}:{PORT}?...
///
/// Phase 4 D-02 двойная ветка:
/// 1. **Reality precedence** (Pitfall 3): URI с `pbk` query (non-empty) ИЛИ `security=reality`
///    → `.vlessReality(ParsedVLESS)`. Reality detection ВСЕГДА проверяется первой —
///    некоторые subscription провайдеры добавляют `security=tls` параллельно к Reality.
/// 2. **TLS branch**: URI с `security=tls` (без Reality маркеров) → `.vlessTLS(ParsedVLESSTLS)`.
///    Vision flow (`flow=xtls-rprx-vision`) — частный случай в TLS branch, `flow` — опциональное.
/// 3. **Иначе** (security=none / missing / другое) → throws `.unsupportedSecurity` (R1: VLESS
///    без TLS не поддерживается клиентом; UniversalImportParser маршрутизирует в `failed.invalid`).
public enum VLESSURIParser {
    public static func parse(_ uri: String) throws -> AnyParsedConfig {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "vless",
              let host = comps.host, !host.isEmpty,
              let port = comps.port,
              let user = comps.user,
              let uuid = UUID(uuidString: user)
        else {
            throw VLESSURIError.malformedURI
        }

        // Парсим query params (точно по RFC).
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }

        let security = q["security"] ?? ""

        // Phase 4 D-02 / Pitfall 3 — Reality detection ВСЕГДА проверяется ПЕРВОЙ.
        // Маркеры Reality: непустой `pbk` query OR explicit `security=reality`.
        // Пустой `pbk=` НЕ считается Reality (некоторые URI имеют empty placeholder).
        let pbk = q["pbk"] ?? ""
        let hasReality = (!pbk.isEmpty) || (security == "reality")

        if hasReality {
            // Reality branch — Phase 1 path. Encryption должна быть "none" (VLESS-only).
            let encryption = q["encryption"] ?? "none"
            guard encryption == "none" else {
                throw VLESSURIError.unsupportedEncryption(encryption)
            }
            let parsed = ParsedVLESS(
                uuid: uuid,
                host: host,
                port: port,
                // VLESS flow: пустая строка если не указан в URI = без Vision.
                // sing-box outbound `flow` поле должно matchить server-side config.
                // Reference: Leadaxe ParserConfig docs + sing-box VLESS outbound spec.
                flow: q["flow"] ?? "",
                security: "reality",
                sni: q["sni"] ?? "",
                publicKey: pbk,
                shortId: q["sid"] ?? "",
                fingerprint: q["fp"] ?? "chrome",
                networkType: q["type"] ?? "tcp",
                remarks: comps.fragment?.removingPercentEncoding
            )
            return .vlessReality(parsed)
        }

        // Phase 4 D-02 — TLS branch (security=tls без Reality маркеров).
        // R1: SNI всегда передаётся; fallback на host если не указан в query.
        if security == "tls" {
            // Encryption должна быть "none" — VLESS spec не поддерживает encryption у клиента.
            let encryption = q["encryption"] ?? "none"
            guard encryption == "none" else {
                throw VLESSURIError.unsupportedEncryption(encryption)
            }
            // ALPN: CSV → [String]. Default — ["h2", "http/1.1"] (R1 совместимое).
            let alpn: [String]
            if let rawAlpn = q["alpn"], !rawAlpn.isEmpty {
                alpn = rawAlpn
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } else {
                alpn = ["h2", "http/1.1"]
            }
            // Flow: nil если отсутствует или пустая строка — отличает «нет flow» от «есть flow="""».
            let flowRaw = q["flow"]
            let flow: String? = (flowRaw?.isEmpty ?? true) ? nil : flowRaw
            // Phase 5 D-09 — делегируем transport-парсинг в TransportParamParser.
            // VLESSURIParser (в отличие от TrojanURIParser) НЕ применяет SNI fallback
            // для WS-host=пусто — protocol package VLESS+TLS.buildOutbound в Wave 5
            // решит substitution from SNI на этапе сборки sing-box JSON (см. Plan
            // 05-02 §2 рекомендация).
            let transport: TransportConfig
            do {
                transport = try TransportParamParser.parse(query: q)
            } catch let TransportParamParser.ParserError.unsupportedType(typeRaw) {
                // D-10 + Pitfall 10 — preserve URI через `.unsupportedTransport`.
                throw VLESSURIError.unsupportedTransport(typeRaw)
            } catch {
                // wsMissingPath / httpMissingPath / httpUpgradeMissingPath — структурная
                // ошибка transport-блока в URI (например `?type=ws` без `&path=`). Тоже
                // классифицируется как unsupported (URI присутствует, но неполный).
                let typeRaw = (q["type"] ?? "unknown").lowercased()
                throw VLESSURIError.unsupportedTransport(typeRaw)
            }
            let parsed = ParsedVLESSTLS(
                uuid: uuid,
                host: host,
                port: port,
                flow: flow,
                sni: q["sni"] ?? host,
                fingerprint: q["fp"] ?? "chrome",
                alpn: alpn,
                transport: transport,
                remarks: comps.fragment?.removingPercentEncoding
            )
            return .vlessTLS(parsed)
        }

        // D-02 — security=none / missing / другое → throw (UniversalImportParser маршрутизирует в failed.invalid).
        throw VLESSURIError.unsupportedSecurity(security)
    }
}
