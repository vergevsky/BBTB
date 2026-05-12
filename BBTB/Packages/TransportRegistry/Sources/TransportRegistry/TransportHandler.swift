import Foundation
import VPNCore

/// CORE-03 (Phase 5) — protocol contract для transport overlay handlers.
///
/// Каждый handler знает свой `identifier` (совпадает с `TransportConfig.identifier`),
/// человекочитаемое имя для UI, список протоколов, которым он применим, и умеет
/// строить sing-box `transport` JSON-блок из `TransportConfig`.
///
/// Реализации — `TCPTransportHandler` (Wave 0), `WSTransportHandler` (Wave 1),
/// `GRPCTransportHandler` / `HTTPTransportHandler` / `HTTPUpgradeTransportHandler`
/// (Wave 2-4). Регистрируются в `TransportRegistry.shared` на старте приложения.
public protocol TransportHandler: Sendable {
    /// Wire-уровневый идентификатор: "tcp" | "ws" | "grpc" | "http" | "httpupgrade".
    /// Должен совпадать с `TransportConfig.identifier` соответствующего case.
    static var identifier: String { get }

    /// UI-facing имя: "TCP" | "WebSocket" | "gRPC" | "HTTP/2" | "HTTPUpgrade".
    static var displayName: String { get }

    /// Список идентификаторов протоколов, поддерживаемых этим транспортом.
    /// Например WS-handler возвращает `["vless-tls", "trojan"]`. TCP-handler —
    /// все 5 (semantic "no transport overlay").
    static var supportedProtocols: [String] { get }

    /// Построить sing-box `transport: { ... }` JSON-блок из `TransportConfig`.
    /// Возвращает `nil`, если случай не относится к этому handler-у (defensive)
    /// или если транспорт = TCP (Pitfall 2: sing-box не имеет transport `tcp`,
    /// отсутствие поля = TCP).
    static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
}
