import Foundation
import PacketTunnelKit

/// iOS extension target shell. Вся логика — в BaseSingBoxTunnel (Packages/PacketTunnelKit).
/// CORE-04: PacketTunnelExtension target iOS.
///
/// `@objc(PacketTunnelProvider)` — обязателен, чтобы iOS NSBundle.principalClass()
/// мог найти Swift class через ObjC runtime. Без явного alias iOS 18+ silently fails
/// при попытке загрузить extension (нет crash logs, status=5 в main app).
@objc(PacketTunnelProvider)
final class PacketTunnelProvider: BaseSingBoxTunnel {
    // Никакого override'а startTunnel/stopTunnel — BaseSingBoxTunnel реализует всё.
    // Если в Phase 2+ нужны iOS-specific quirks (например, iOS Memory Pressure handler) —
    // override'нем здесь. В Phase 1 — пустой shell.
}
