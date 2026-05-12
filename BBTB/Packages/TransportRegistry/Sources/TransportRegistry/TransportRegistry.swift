import Foundation
import VPNCore

/// CORE-03: реестр TransportHandler-типов (Phase 5).
///
/// По образцу `ProtocolRegistry.shared` — singleton с NSLock-защищённым словарём
/// `[String: any TransportHandler.Type]`. В Wave 0 регистрируется только
/// `TCPTransportHandler`; остальные транспорты добавляются в Wave 1-4 и
/// регистрируются на старте приложения в Wave 5 (см. PLAN 05-01 acceptance).
public final class TransportRegistry: @unchecked Sendable {
    public static let shared = TransportRegistry()

    private let lock = NSLock()
    private var handlers: [String: any TransportHandler.Type] = [:]

    public func register<H: TransportHandler>(_ handlerType: H.Type) {
        lock.lock(); defer { lock.unlock() }
        handlers[H.identifier] = handlerType
    }

    public func handler(for identifier: String) -> (any TransportHandler.Type)? {
        lock.lock(); defer { lock.unlock() }
        return handlers[identifier]
    }

    public var registeredIdentifiers: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(handlers.keys).sorted()
    }
}
