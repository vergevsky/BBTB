import Foundation
import PacketTunnelKit

/// macOS extension target shell. Вся логика — в BaseSingBoxTunnel (Packages/PacketTunnelKit).
/// CORE-04: PacketTunnelExtension target macOS.
///
/// `@objc(PacketTunnelProvider)` — alias для NSExtension lookup через ObjC runtime.
/// См. iOS аналог.
///
/// Phase 6d Wave 02a — `LibboxStart` OSSignposter span instrumented в
/// BaseSingBoxTunnel.startTunnel (single point covers both iOS + macOS shells).
/// Instruments → Points of Interest → subsystem=app.bbtb.tunnel,
/// category=performance, span="LibboxStart".
@objc(PacketTunnelProvider)
final class PacketTunnelProvider: BaseSingBoxTunnel {
    // Phase 10 (R5) hook — `PlatformHooks.shouldDisableEnforceRoutes()` уже читается
    // из KillSwitch.apply на стороне main app. Здесь — нечего override'нить.
}
