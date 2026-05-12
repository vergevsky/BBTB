import Foundation
import VPNCore

/// Phase 5 / CORE-03 — shared утилита для парсинга transport-params из URI.
///
/// Заменяет дублированный switch по `q["type"]` в `VLESSURIParser` и
/// `TrojanURIParser` (Phase 4) одной точкой правки. Все будущие URI-парсеры
/// (`ShadowsocksURIParser` etc.) также делегируют сюда (D-08, D-09).
///
/// Контракт type dispatch (D-10 + Pitfall 10 + Example 3):
/// - `type` absent / `"tcp"` / `"raw"` / `""` → `.tcp`
/// - `type=ws` требует `path` (иначе `.wsMissingPath`); `host` по умолчанию `""`
///   (caller подставляет SNI на этапе сборки sing-box JSON)
/// - `type=grpc` читает `serviceName` (camelCase per V2Ray URI conv); default `"TunService"`
/// - `type=http` или `type=h2` требует `path` (иначе `.httpMissingPath`)
/// - `type=httpupgrade` требует `path` (иначе `.httpUpgradeMissingPath`);
///   `host` по умолчанию `""`
/// - всё остальное → `.unsupportedType(typeRaw)`
///
/// Сравнение `type` — case-insensitive (`.lowercased()`); неизвестные query-params
/// тихо игнорируются (security pattern: extras = no-op).
public enum TransportParamParser {

    public enum ParserError: Error, LocalizedError, Equatable {
        case wsMissingPath
        case httpMissingPath
        case httpUpgradeMissingPath
        case unsupportedType(String)

        public var errorDescription: String? {
            switch self {
            case .wsMissingPath:          return "WebSocket transport requires non-empty path"
            case .httpMissingPath:        return "HTTP transport requires non-empty path"
            case .httpUpgradeMissingPath: return "HTTPUpgrade transport requires non-empty path"
            case .unsupportedType(let t): return "Unsupported transport type: \(t)"
            }
        }
    }

    /// Парсит словарь URI query-params в `TransportConfig`.
    /// Семантика см. doc-comment к enum.
    public static func parse(query: [String: String]) throws -> TransportConfig {
        let typeRaw = (query["type"] ?? "tcp").lowercased()
        switch typeRaw {
        case "tcp", "raw", "":
            return .tcp
        case "ws":
            guard let path = query["path"], !path.isEmpty else {
                throw ParserError.wsMissingPath
            }
            let host = query["host"] ?? ""
            return .ws(path: path, host: host)
        case "grpc":
            let svc = query["serviceName"] ?? "TunService"
            return .grpc(serviceName: svc)
        case "http", "h2":
            guard let path = query["path"], !path.isEmpty else {
                throw ParserError.httpMissingPath
            }
            return .http(path: path)
        case "httpupgrade":
            guard let path = query["path"], !path.isEmpty else {
                throw ParserError.httpUpgradeMissingPath
            }
            let host = query["host"] ?? ""
            return .httpUpgrade(path: path, host: host)
        default:
            throw ParserError.unsupportedType(typeRaw)
        }
    }
}
