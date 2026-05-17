import Foundation
import VPNCore

/// CORE-03: реестр TransportHandler-типов (Phase 5).
///
/// По образцу `ProtocolRegistry.shared` — singleton с NSLock-защищённым словарём
/// `[String: any TransportHandler.Type]`. В Wave 0 регистрируется только
/// `TCPTransportHandler`; остальные транспорты добавляются в Wave 1-4 и
/// регистрируются на старте приложения в Wave 5 (см. PLAN 05-01 acceptance).
///
/// **Plan 09 A6-TR-3-001 (closes A6 MEDIUM freeze-discipline):** after
/// app bootstrap completes registering all transports, caller must invoke
/// `freeze()` to refuse subsequent `register()` calls. Prevents accidental
/// mid-runtime mutation (e.g. plugin scenario, test bleed-through) что нарушает
/// invariant: handlers dict is set-once, read-many. Reads remain valid после
/// freeze (lock still protects against torn reads из concurrent readers).
public final class TransportRegistry: @unchecked Sendable {
    public static let shared = TransportRegistry()

    private let lock = NSLock()
    private var handlers: [String: any TransportHandler.Type] = [:]
    private var frozen: Bool = false

    public func register<H: TransportHandler>(_ handlerType: H.Type) {
        lock.lock(); defer { lock.unlock() }
        // Plan 09 A6-TR-3-001: refuse post-freeze mutations. Soft-fail
        // (log + skip) rather than crash — production cold-start may have
        // benign re-register during plugin discovery; freeze-then-warn
        // signals contract violation without breaking startup.
        if frozen {
            // Note: cannot use os.Logger here без adding dep; freeze contract
            // documented in `wiki/architecture.md` (TransportRegistry section).
            assertionFailure("TransportRegistry: register(\(H.identifier)) called after freeze() — registration ignored.")
            return
        }
        handlers[H.identifier] = handlerType
    }

    /// **Plan 09 A6-TR-3-001:** after app bootstrap completes registering all
    /// transports, call freeze() to lock the registry. Subsequent register()
    /// calls become no-ops с assertion-failure в Debug (silent in Release).
    /// Idempotent — re-freeze is safe.
    public func freeze() {
        lock.lock(); defer { lock.unlock() }
        frozen = true
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
