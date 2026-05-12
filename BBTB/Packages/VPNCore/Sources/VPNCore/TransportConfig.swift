import Foundation

/// Phase 5 / CORE-03 — shared transport overlay type для всех VPN-протоколов
/// (Decision D-04 в `.planning/phases/05-transports/05-CONTEXT.md`).
///
/// Один enum заменяет per-protocol `TransportType` (`ParsedTrojan.TransportType`,
/// `ParsedVLESSTLS.networkType: String`). При 15+ протоколах × N транспортах это
/// единое место правки — каждый новый транспорт добавляется как один case плюс
/// один handler в `TransportRegistry`.
///
/// Codable: используется synthesized conformance (SE-0295, Swift 5.5+) для enum
/// с associated values. Никаких custom `CodingKeys` / `init(from:)` / `encode(to:)`
/// — это снижает риск рассинхрона при будущих SwiftData миграциях.
///
/// Идентификаторы транспортов (`identifier`) совпадают со значениями `type` в
/// sing-box JSON конфигурации и в URI query-параметре `type=` (`"tcp"`, `"ws"`,
/// `"grpc"`, `"http"`, `"httpupgrade"` — single token, lowercase). См. Pitfall 6
/// в `.planning/phases/05-transports/05-RESEARCH.md`.
public enum TransportConfig: Sendable, Equatable, Codable, Hashable {
    case tcp
    case ws(path: String, host: String)
    case grpc(serviceName: String)
    case http(path: String)
    case httpUpgrade(path: String, host: String)

    /// Wire-уровневый идентификатор: совпадает с `type` в sing-box outbound JSON
    /// и с `type=` query-параметром в URI. Lowercase, без дефисов и подчёркиваний.
    public var identifier: String {
        switch self {
        case .tcp:         return "tcp"
        case .ws:          return "ws"
        case .grpc:        return "grpc"
        case .http:        return "http"
        case .httpUpgrade: return "httpupgrade"
        }
    }

    /// UI-уровневая строка для Transport Picker (Wave 6 / `ServerDetailView`,
    /// D-18). Стиль — «как показывается пользователю».
    public var displayName: String {
        switch self {
        case .tcp:         return "TCP"
        case .ws:          return "WebSocket"
        case .grpc:        return "gRPC"
        case .http:        return "HTTP/2"
        case .httpUpgrade: return "HTTPUpgrade"
        }
    }
}
