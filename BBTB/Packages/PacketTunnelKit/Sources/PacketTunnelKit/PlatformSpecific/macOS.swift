#if os(macOS)
import Foundation

/// macOS-specific hooks для PacketTunnelKit.
///
/// **Phase 10 заглушка:** `shouldDisableEnforceRoutes()` пока всегда возвращает `false`,
/// но точка интеграции уже определена. Когда в Phase 10 (R5) появится UI-тоггл
/// «Отключить принудительную маршрутизацию», эта функция будет читать UserDefaults
/// или SwiftData-флаг и возвращать его. KillSwitch.apply(to:) уже учитывает эту функцию,
/// так что Phase 10 не потребует менять KillSwitch — только эту implementation.
public enum PlatformHooks {
    /// R5 (Phase 10): macOS-only тоггл в Расширенных. Phase 1 — hardcoded false.
    public static func shouldDisableEnforceRoutes() -> Bool {
        return false
    }
}
#endif
