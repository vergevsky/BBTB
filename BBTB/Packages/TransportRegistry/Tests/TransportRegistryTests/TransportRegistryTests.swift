import XCTest
@testable import TransportRegistry
import VPNCore

/// Phase 5 Wave 0 / Task 2 — coverage for TransportRegistry singleton (CORE-03, D-11/D-12).
final class TransportRegistryTests: XCTestCase {

    // MARK: - singleton identity

    func test_singleton_identity() {
        XCTAssertTrue(TransportRegistry.shared === TransportRegistry.shared)
    }

    // MARK: - register / lookup happy path

    func test_register_addsIdentifier() {
        TransportRegistry.shared.register(TCPTransportHandler.self)
        XCTAssertTrue(TransportRegistry.shared.registeredIdentifiers.contains("tcp"))
    }

    func test_handler_for_returnsRegisteredType() {
        TransportRegistry.shared.register(TCPTransportHandler.self)
        let handler = TransportRegistry.shared.handler(for: "tcp")
        XCTAssertNotNil(handler)
        XCTAssertEqual(handler?.identifier, "tcp")
    }

    func test_handler_for_unknownReturnsNil() {
        XCTAssertNil(TransportRegistry.shared.handler(for: "xyz-not-a-transport"))
    }

    // MARK: - concurrency smoke (NSLock contract)

    func test_concurrent_register_lookup_doesNotCrash() {
        // 100 параллельных операций: mixed register + handler(for:) lookup.
        // Падение на data race → краш (Thread Sanitizer); прохождение → NSLock работает.
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            if i % 2 == 0 {
                TransportRegistry.shared.register(TCPTransportHandler.self)
            } else {
                _ = TransportRegistry.shared.handler(for: "tcp")
                _ = TransportRegistry.shared.registeredIdentifiers
            }
        }
        // sanity: после concurrent operations TCP должен быть в реестре
        XCTAssertTrue(TransportRegistry.shared.registeredIdentifiers.contains("tcp"))
    }
}
