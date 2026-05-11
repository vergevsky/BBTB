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

    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed vless:// URI"
        case .notRealityProtocol(let s): return "Not a Reality protocol URI (security=\(s ?? "missing"))"
        case .unsupportedEncryption(let e): return "Unsupported encryption: \(e) (only 'none' supported)"
        }
    }
}

/// IMP-01 — parser для vless://{UUID}@{HOST}:{PORT}?...
/// Phase 1 поддерживает ТОЛЬКО Reality (security=reality + encryption=none).
public enum VLESSURIParser {
    public static func parse(_ uri: String) throws -> ParsedVLESS {
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
        guard security == "reality" else {
            throw VLESSURIError.notRealityProtocol(q["security"])
        }
        let encryption = q["encryption"] ?? "none"
        guard encryption == "none" else {
            throw VLESSURIError.unsupportedEncryption(encryption)
        }

        return ParsedVLESS(
            uuid: uuid,
            host: host,
            port: port,
            flow: q["flow"] ?? "xtls-rprx-vision",
            security: "reality",
            sni: q["sni"] ?? "",
            publicKey: q["pbk"] ?? "",
            shortId: q["sid"] ?? "",
            fingerprint: q["fp"] ?? "chrome",
            networkType: q["type"] ?? "tcp",
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
