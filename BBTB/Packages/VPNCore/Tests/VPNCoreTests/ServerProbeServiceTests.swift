// ServerProbeServiceTests — D-02: actor ServerProbeService TCP probe + parallel stream.
// Phase 3 / Plan 02 — TDD RED phase.
//
// Live test pattern: bring up NWListener (Apple-native, no external dependency) on
// 127.0.0.1:<ephemeral> в setUp; tearDown — cancel. Tests probe против собственного
// listener, чтобы убедиться что TCP-handshake возвращает .ok с реальным latency,
// а закрытый порт упирается в manual timeout.

import XCTest
import Network
@testable import VPNCore

final class ServerProbeServiceTests: XCTestCase {

    private var listener: NWListener?
    private var listenerPort: Int = 0

    override func setUp() async throws {
        try await super.setUp()
        // Запускаем TCP-listener на ephemeral порту 127.0.0.1.
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params)
        listener = l

        // Локальная queue (Sendable: DispatchQueue is Sendable). Не используем
        // stored property `self.listenerQueue`, иначе компилятор требует
        // ServerProbeServiceTests : Sendable, а XCTestCase не Sendable.
        let queue = DispatchQueue(label: "test.listener.queue")

        l.newConnectionHandler = { conn in
            // Accept и сразу cancel — нам нужен только TCP-handshake.
            conn.start(queue: queue)
            conn.cancel()
        }

        // Ждём, пока listener привяжется к порту.
        let portExpectation = expectation(description: "listener ready")
        l.stateUpdateHandler = { state in
            if case .ready = state {
                portExpectation.fulfill()
            }
        }
        l.start(queue: queue)
        await fulfillment(of: [portExpectation], timeout: 2.0)

        guard let port = l.port?.rawValue else {
            XCTFail("Listener did not bind to a port")
            return
        }
        listenerPort = Int(port)
    }

    override func tearDown() async throws {
        listener?.cancel()
        listener = nil
        try await super.tearDown()
    }

    // MARK: - probeOnce

    func test_probeOnce_listening_port_returns_ok() async {
        let svc = ServerProbeService()
        let result = await svc.probeOnce(host: "127.0.0.1", port: listenerPort, timeoutMs: 500)
        guard case .ok(let ms) = result else {
            XCTFail("Expected .ok, got \(result)")
            return
        }
        XCTAssertGreaterThanOrEqual(ms, 1, "Latency должен быть как минимум 1ms (clamped)")
        XCTAssertLessThan(ms, 500, "Latency loopback должен быть < 500ms")
    }

    func test_probeOnce_invalid_port_returns_error() async {
        let svc = ServerProbeService()
        let result = await svc.probeOnce(host: "127.0.0.1", port: 0, timeoutMs: 500)
        if case .error = result {
            // OK
        } else {
            XCTFail("Expected .error for invalid port, got \(result)")
        }
    }

    func test_probeOnce_closed_port_times_out_within_budget() async {
        // Используем порт, на котором ничего не слушает. Port 1 на macOS обычно
        // блокирован (privileged + closed); NWConnection должен повиснуть и manual
        // timeout должен сработать. Budget — ≤ 1500ms wall-clock (timeoutMs=200
        // + накладные расходы на handshake-retry от Network.framework).
        let svc = ServerProbeService()
        let startWall = Date()
        let result = await svc.probeOnce(host: "127.0.0.1", port: 1, timeoutMs: 200)
        let elapsedMs = Date().timeIntervalSince(startWall) * 1000.0

        // Допускаем .timeout или .error — Network.framework на разных OS может
        // вернуть RST → .error быстрее timeout. Главное: manual timeout НЕ должен
        // позволить probeOnce висеть на default ~60sec NWConnection timeout.
        switch result {
        case .timeout, .error:
            break
        case .ok:
            XCTFail("Closed port should not return .ok")
        }
        XCTAssertLessThan(elapsedMs, 1500,
                          "Manual timeout violated: wall-clock=\(elapsedMs)ms, budget=1500ms (timeoutMs=200)")
    }

    // MARK: - probeAll

    func test_probeAll_yields_results_for_all_servers() async {
        let svc = ServerProbeService()
        let s1 = (id: UUID(), host: "127.0.0.1", port: listenerPort)
        let s2 = (id: UUID(), host: "127.0.0.1", port: listenerPort)
        let s3 = (id: UUID(), host: "127.0.0.1", port: listenerPort)

        var results: [(UUID, ProbeAggregate)] = []
        for await result in svc.probeAll([s1, s2, s3]) {
            results.append(result)
        }

        XCTAssertEqual(results.count, 3, "Stream должен yield'ить ровно 3 элемента")
        for (_, agg) in results {
            XCTAssertNotNil(agg.avgLatencyMs,
                            "Все probes против listening port должны иметь avgLatencyMs != nil")
            XCTAssertFalse(agg.isUnreachable)
        }
    }

    func test_probeAll_cancellation_via_task_cancel() async {
        let svc = ServerProbeService()
        // Используем закрытый порт чтобы probe «вешалась» на timeout — даёт окно
        // для cancellation.
        let servers = (0..<5).map { _ in (id: UUID(), host: "127.0.0.1", port: 1) }

        let startWall = Date()
        let task = Task {
            var collected = 0
            for await _ in svc.probeAll(servers) {
                collected += 1
            }
            return collected
        }

        // Дать stream немного поработать, потом cancel.
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        _ = await task.value
        let elapsedMs = Date().timeIntervalSince(startWall) * 1000.0

        XCTAssertLessThan(elapsedMs, 2000,
                          "После cancel stream должен завершиться без hang (≤2s), получили \(elapsedMs)ms")
    }
}
