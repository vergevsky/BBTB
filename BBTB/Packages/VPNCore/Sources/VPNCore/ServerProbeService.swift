// ServerProbeService.swift — D-02: actor TCP probe + AsyncStream parallel pinger.
// Phase 3 / Plan 02.
//
// Архитектура (RESEARCH §«Example 1 / Example 2»):
// - probeOnce(host, port, timeoutMs) — NWConnection-based TCP handshake + manual
//   timeout через Task race. Single-resume invariant защищён LockedBool
//   (OSAllocatedUnfairLock), потому что NWConnection может вызывать stateUpdateHandler
//   несколько раз (.ready затем .cancelled).
// - probeAll(servers) — public nonisolated, чтобы @MainActor consumer (ServerListViewModel,
//   Plan 03/04) мог iterate stream без await self. Внутри — TaskGroup parallel +
//   onTermination → task.cancel() для cancellation propagation.
// - Cross-actor Sendable boundary через tuple (UUID, host: String, port: Int) — НЕ
//   через [ServerConfig] (Pitfall 4 — @Model classes не Sendable).

import Foundation
import Network
import OSLog
import os

/// Phase 3 / Plan 04 — protocol для DI ServerProbeService в ViewModel'и.
///
/// Actor type cannot be subclassed (Swift constraint); тесты mock'ают через protocol.
/// `nonisolated` declaration соответствует `ServerProbeService.probeAll(_:)` signature.
public protocol ServerProbing: Sendable {
    nonisolated func probeAll(_ servers: [(id: UUID, host: String, port: Int)])
        -> AsyncStream<(UUID, ProbeAggregate)>
}

public actor ServerProbeService: ServerProbing {

    private let log = Logger(subsystem: "app.bbtb.server-probe", category: "probe")
    private let queue = DispatchQueue(label: "app.bbtb.probe", qos: .userInitiated)

    public init() {}

    /// Однократный TCP probe до `host:port` с manual timeout. Возвращает .ok с
    /// измеренной latency (ms), .timeout при превышении `timeoutMs`, или .error
    /// при NWConnection failure.
    public func probeOnce(host: String, port: Int, timeoutMs: Int = 500) async -> ProbeResult {
        guard port > 0, port < 65536, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return .error("invalid port: \(port)")
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let clock = ContinuousClock()
        let start = clock.now
        let localQueue = self.queue
        let logger = self.log

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<ProbeResult, Never>) in
                let resumed = LockedBool()

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard resumed.tryFlip() else { return }
                        let elapsed = clock.now - start
                        // Duration.components: .seconds Int64 + .attoseconds Int64.
                        // ms = sec*1000 + attos/1e15.
                        let comps = elapsed.components
                        let ms = Int(comps.seconds * 1000) + Int(comps.attoseconds / 1_000_000_000_000_000)
                        connection.cancel()
                        cont.resume(returning: .ok(latencyMs: max(1, ms)))
                    case .failed(let err):
                        guard resumed.tryFlip() else { return }
                        logger.debug("probe failed: \(err.debugDescription, privacy: .public)")
                        connection.cancel()
                        cont.resume(returning: .error(err.debugDescription))
                    case .waiting(let err):
                        // .waiting = NWConnection не может установить соединение
                        // прямо сейчас (например, network down). Возвращаем .error
                        // быстро — не ждём timeout.
                        guard resumed.tryFlip() else { return }
                        logger.debug("probe waiting: \(err.debugDescription, privacy: .public)")
                        connection.cancel()
                        cont.resume(returning: .error(err.debugDescription))
                    case .cancelled:
                        // Cancel мог прийти от outer Task или от нашего же manual
                        // timeout. Если ещё не resumed — это значит, что cancel
                        // прилетел извне (cancellation handler), мы трактуем как
                        // .timeout (probe не успел дать результат).
                        guard resumed.tryFlip() else { return }
                        cont.resume(returning: .timeout)
                    default:
                        break
                    }
                }

                // Manual timeout (D-02): не полагаемся на NWConnection default
                // connectionTimeout (~60sec). Sleep + cancel при истечении.
                Task {
                    try? await Task.sleep(for: .milliseconds(timeoutMs))
                    if resumed.tryFlip() {
                        connection.cancel()
                        cont.resume(returning: .timeout)
                    }
                }

                connection.start(queue: localQueue)
            }
        } onCancel: {
            // Propagate outer Task cancellation — закрываем сокет, чтобы освободить
            // ресурсы. .cancelled callback может прилететь, но resumed.tryFlip()
            // уже false (continuation уже resumed либо timeout, либо .ready/.failed).
            connection.cancel()
        }
    }

    /// Phase 6d / Wave 06D-03c (H4) — bounded concurrency cap (Apple guidance
    /// для parallel NWConnection). Старый unbounded fan-out (`group.addTask`
    /// per server) на 30-50 supported серверах создавал десятки NWConnection
    /// одновременно, контендя за systemwide socket pool и Mach ports.
    private static let maxConcurrentProbes = 8

    /// Parallel probe для списка серверов. Каждый сервер пингуется 3 раза
    /// (sequential, 50ms gap между retry), результаты yield'ятся в AsyncStream
    /// progressively (UI обновляется по мере готовности каждого сервера).
    ///
    /// `nonisolated` — чтобы @MainActor consumer (ServerListViewModel) мог
    /// напрямую `for await ... in svc.probeAll(...)` без `await svc.probeAll(...)`.
    ///
    /// **Bounded concurrency (Wave 06D-03c, H4):** не более
    /// `maxConcurrentProbes` (=8) одновременно работающих probe-tasks. После
    /// финиша любого из них немедленно стартует следующий из очереди серверов
    /// (счётчик `nextIndex`). Гарантируется, что **каждый** сервер из входного
    /// массива получит probe — bounded variant ограничивает только
    /// parallelism, не drop'ает servers.
    ///
    /// Cancellation propagation: outer task cancel → AsyncStream onTermination →
    /// internal Task cancel → TaskGroup child probes завершаются через
    /// withTaskCancellationHandler в probeOnce.
    public nonisolated func probeAll(
        _ servers: [(id: UUID, host: String, port: Int)]
    ) -> AsyncStream<(UUID, ProbeAggregate)> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: (UUID, ProbeAggregate).self) { group in
                    let total = servers.count
                    let cap = min(Self.maxConcurrentProbes, total)
                    // Spawn первоначальные up-to-cap tasks.
                    var nextIndex = 0
                    while nextIndex < cap {
                        let srv = servers[nextIndex]
                        group.addTask { [self] in
                            await self.probeServerThreeTimes(srv)
                        }
                        nextIndex += 1
                    }
                    // Каждый раз, как один из probe завершается — yield его
                    // результат и (если ещё есть серверы) запускаем следующий.
                    // Поддерживает invariant: in-flight tasks ≤ cap.
                    while let result = await group.next() {
                        if Task.isCancelled { break }
                        continuation.yield(result)
                        if nextIndex < total {
                            let srv = servers[nextIndex]
                            group.addTask { [self] in
                                await self.probeServerThreeTimes(srv)
                            }
                            nextIndex += 1
                        }
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Internal: 3 sequential probes с 50ms gap, агрегация в ProbeAggregate.
    ///
    /// **T-C-A2H2' (closes A2-H2 HIGH):** mid-round cancellation handling.
    /// Pre-fix, если outer Task cancelled после первой `.ok` probe (e.g. user
    /// swiped away pull-to-refresh sheet), function returned
    /// `ProbeAggregate(failures: 0, lossRate: 0.0)` based on partial sample.
    /// That single-sample score is IDENTICAL к clean 3/3 OK probe →
    /// `ServerScore.autoSelect` prefers cancelled server over equally-fast
    /// server which completed 3/3. The cancelled aggregate poisoned SwiftData
    /// `failedProbeCount`/`lastLatencyMs` rows для lifetime row.
    ///
    /// Fix: when cancelled mid-round (less than 3 probes attempted), mark
    /// aggregate as "incomplete" via `failures = 3, latencies = []` →
    /// `lossRate = 1.0` → autoSelect excludes от ranking. This is conservative
    /// (treats cancellation as "unverified" не "good"), which matches user
    /// intent ("I cancelled, don't trust partial result").
    private func probeServerThreeTimes(
        _ srv: (id: UUID, host: String, port: Int)
    ) async -> (UUID, ProbeAggregate) {
        var latencies: [Int] = []
        var failures = 0
        var iterationsCompleted = 0
        var cancelledMidRound = false
        for _ in 0..<3 {
            if Task.isCancelled {
                cancelledMidRound = true
                break
            }
            let result = await probeOnce(host: srv.host, port: srv.port)
            iterationsCompleted += 1
            switch result {
            case .ok(let ms): latencies.append(ms)
            case .timeout, .error: failures += 1
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // T-C-A2H2': mid-round cancellation OR incomplete loop → conservative
        // "unverified" aggregate. Pre-fix masked it as "all OK".
        if cancelledMidRound && iterationsCompleted < 3 {
            return (srv.id, ProbeAggregate(
                avgLatencyMs: nil,
                failures: 3,
                lossRate: 1.0,
                probedAt: Date()
            ))
        }
        let avg = latencies.isEmpty ? nil : latencies.reduce(0, +) / latencies.count
        let totalAttempts = max(1, latencies.count + failures)
        let lossRate = Double(failures) / Double(totalAttempts)
        return (srv.id, ProbeAggregate(
            avgLatencyMs: avg,
            failures: failures,
            lossRate: lossRate,
            probedAt: Date()
        ))
    }
}

// MARK: - Single-resume helper

/// Thread-safe boolean «set-once». Гарантирует, что CheckedContinuation.resume
/// будет вызван ровно один раз — даже если NWConnection.stateUpdateHandler
/// вызывает callback дважды (например, .ready затем .cancelled) и параллельно
/// сработал manual timeout Task.
///
/// **T-C-A2H1' (closes A2-H1 HIGH):** typed `OSAllocatedUnfairLock<Bool>`
/// instead of stateless variant + `@unchecked Sendable` mask. The typed
/// generic form is `Sendable` natively (Swift 6 strict concurrency), and the
/// stored state is now compiler-visible — any future contributor who tries
/// к mutate `flipped` outside `withLock` will get diagnostics. Removes the
/// regression-prevention gap noted by Plan 06 audit.
private final class LockedBool: Sendable {
    private let lock = OSAllocatedUnfairLock<Bool>(initialState: false)

    func tryFlip() -> Bool {
        lock.withLock { state in
            guard !state else { return false }
            state = true
            return true
        }
    }
}
