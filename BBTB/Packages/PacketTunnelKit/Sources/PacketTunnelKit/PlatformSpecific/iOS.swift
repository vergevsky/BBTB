#if os(iOS)
import Foundation

/// iOS-specific hooks для PacketTunnelKit.
///
/// Phase 1 — placeholder. Будущие фазы могут добавить:
/// - Pasteboard auto-detect (Phase 11)
/// - iOS-specific extension memory accounting (Phase 6+)
public enum PlatformHooks {
    /// CORE-os: на iOS нет R5 toggle — `enforceRoutes` всегда `true` (см. R4 default).
    public static func shouldDisableEnforceRoutes() -> Bool {
        return false
    }
}
#endif
