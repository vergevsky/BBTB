import Foundation
import Network
import os

public enum PortStatus: Equatable {
    case open
    case closed
    case timeout
    case error(String)
}

public struct PortResult: Identifiable {
    public let id = UUID()
    public let port: UInt16
    public let status: PortStatus
    public let durationMs: Int
}

public enum PortProber {
    /// Async TCP-connect probe c configurable timeout.
    /// Wave 1 default: 500ms — этого достаточно для loopback (≤1ms latency на nominal device).
    public static func probe(
        port: UInt16,
        host: String = "127.0.0.1",
        timeout: TimeInterval = 0.5
    ) async -> PortResult {
        let start = Date()
        let conn = NWConnection(
            host: .init(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let status: PortStatus = await withCheckedContinuation { (cont: CheckedContinuation<PortStatus, Never>) in
            let timer = DispatchSource.makeTimerSource(queue: .global())
            let resumedLock = OSAllocatedUnfairLock(initialState: false)
            let resume: @Sendable (PortStatus) -> Void = { newStatus in
                let shouldResume = resumedLock.withLock { resumed -> Bool in
                    guard !resumed else { return false }
                    resumed = true
                    return true
                }
                guard shouldResume else { return }
                timer.cancel()
                conn.cancel()
                cont.resume(returning: newStatus)
            }
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { resume(.timeout) }
            timer.activate()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resume(.open)
                case .failed(let err):
                    resume(.error(err.localizedDescription))
                case .cancelled:
                    resume(.closed)
                case .waiting:
                    // ConnectionWaiting обычно = port closed; завершаем сразу.
                    resume(.closed)
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return PortResult(port: port, status: status, durationMs: durationMs)
    }

    /// Сканировать список портов параллельно (Task group), вернуть массив результатов
    /// в том же порядке что и input.
    public static func probeAll(
        _ ports: [UInt16],
        host: String = "127.0.0.1",
        timeout: TimeInterval = 0.5
    ) async -> [PortResult] {
        await withTaskGroup(of: (Int, PortResult).self) { group in
            for (idx, port) in ports.enumerated() {
                group.addTask {
                    let r = await probe(port: port, host: host, timeout: timeout)
                    return (idx, r)
                }
            }
            var results: [(Int, PortResult)] = []
            for await pair in group { results.append(pair) }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}
