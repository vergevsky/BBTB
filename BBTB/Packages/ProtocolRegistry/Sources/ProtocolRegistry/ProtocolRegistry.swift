import Foundation
import VPNCore

/// CORE-02: реестр зарегистрированных VPNProtocolHandler-типов.
/// В Phase 1 регистрируется только VLESSReality (см. 01-W3-base-tunnel-PLAN.md).
public final class ProtocolRegistry: @unchecked Sendable {
    public static let shared = ProtocolRegistry()

    private let lock = NSLock()
    private var handlers: [String: any VPNProtocolHandler.Type] = [:]

    public func register<H: VPNProtocolHandler>(_ handlerType: H.Type) {
        lock.lock(); defer { lock.unlock() }
        handlers[H.identifier] = handlerType
    }

    public func handler(for identifier: String) -> (any VPNProtocolHandler.Type)? {
        lock.lock(); defer { lock.unlock() }
        return handlers[identifier]
    }

    public var registeredIdentifiers: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(handlers.keys).sorted()
    }
}
