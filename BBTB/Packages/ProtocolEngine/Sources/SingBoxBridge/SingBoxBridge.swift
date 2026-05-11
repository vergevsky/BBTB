@_exported import Libbox
import Foundation

/// Public façade для libbox.xcframework.
/// PacketTunnelKit импортирует SingBoxBridge и через `@_exported import Libbox`
/// получает доступ к LibboxSetup, LibboxNewService, LibboxBoxService и протоколу
/// LibboxPlatformInterface.
public enum SingBoxBridge {
    public static let singBoxVersion = "1.13.11"
}
