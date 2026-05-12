import Foundation
import VPNCore

/// CORE-03 (Phase 5) — TCP "no-overlay" handler.
///
/// sing-box не имеет transport-блока `tcp` (Pitfall 2): когда транспорт = TCP,
/// outbound JSON просто не содержит поле `transport`. Поэтому
/// `buildTransportBlock` всегда возвращает `nil` — для всех 5 cases enum'а
/// `TransportConfig` (defensive: handler обрабатывает только свой `.tcp` case).
///
/// `supportedProtocols` включает все 5 актуальных protocol-идентификаторов
/// (VLESS+TLS, Trojan, VLESS+Reality, Shadowsocks, Hysteria2) — TCP применим
/// ко всем (semantic "no transport overlay"). При добавлении новых протоколов
/// в Phase 6+ список расширяется.
///
/// Реализован как enum без cases — идиоматичный Swift namespace для type-only
/// контракта (static-only API без необходимости в инстансах).
public enum TCPTransportHandler: TransportHandler {
    public static let identifier = "tcp"
    public static let displayName = "TCP"
    public static let supportedProtocols: [String] = [
        "vless-tls",
        "trojan",
        "vless-reality",
        "shadowsocks",
        "hysteria2",
    ]

    /// Всегда `nil`: TCP = "no transport overlay", отсутствие поля `transport`
    /// в outbound JSON sing-box интерпретирует как TCP (Pitfall 2 invariant).
    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
        return nil
    }
}
