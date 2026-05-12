// ReconnectStateMachine.swift — Phase 6 / Plan 06-04 / Wave 4 / Task 2.
//
// Auto-reconnect state machine implementing D-07 + D-08:
// - 3 attempts per server with exp backoff 2s / 4s / 8s.
// - On all-3-fails: invoke caller-provided `failoverNext()` to obtain the next
//   server's attempt closure; `.allFailed` if it returns nil.
// - `cancel()` propagates Task cancellation through `clock.sleep`.
// - `reportConnected()` resets to `.idle` (used when the OS reports `.connected`
//   externally — e.g. after a successful 30s+ session in Wave 5).
//
// All delays go through the injected `ReconnectClock` protocol — production uses
// `SystemReconnectClock` (delegates to `Task.sleep`), tests substitute a clock
// that records sleep durations and yields instantly. No GCD-based timer APIs
// anywhere (project standard from `06-PATTERNS.md` threading section).
//
// See `.planning/phases/06-network-resilience/06-RESEARCH.md` §9 and §14
// Pitfalls 3 and 4 for the design rationale; `06-CONTEXT.md` D-07/D-08 for the
// locked retry parameters.

import Foundation
import OSLog

// MARK: - Public state surface

public enum ReconnectStateMachineState: Equatable, Sendable {
    case idle
    case retrying(attempt: Int, delaySeconds: Int)
    case failover(toServerName: String)
    case allFailed
}

// MARK: - Clock protocol (test seam)

/// Abstraction over async sleeps so the state machine can be tested without
/// burning real wall-clock seconds. Production uses `SystemReconnectClock`.
public protocol ReconnectClock: Sendable {
    func sleep(seconds: Int) async throws
}

/// Production clock — delegates to `Task.sleep(nanoseconds:)`.
public struct SystemReconnectClock: ReconnectClock {
    public init() {}
    public func sleep(seconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(seconds, 0)) * 1_000_000_000)
    }
}

// MARK: - State machine

public actor ReconnectStateMachine {

    // MARK: Typealiases

    public typealias AttemptHandler = @Sendable () async throws -> Date
    public typealias FailoverProvider = @Sendable () async -> (serverName: String, attempt: AttemptHandler)?
    public typealias StateObserver = @Sendable (ReconnectStateMachineState) -> Void

    // MARK: Tunables (D-07)

    public let backoffSeconds: [Int] = [2, 4, 8]
    public let maxAttemptsPerServer: Int = 3

    // MARK: State

    private var state: ReconnectStateMachineState = .idle {
        didSet { observer?(state) }
    }
    private var currentTask: Task<Void, Never>?
    private let observer: StateObserver?
    private let clock: ReconnectClock
    private let log = Logger(subsystem: "app.bbtb.client", category: "reconnect")

    // MARK: Init

    public init(
        clock: ReconnectClock = SystemReconnectClock(),
        observer: StateObserver? = nil
    ) {
        self.clock = clock
        self.observer = observer
    }

    // MARK: Public API

    /// Returns the current state. Useful for tests and ad-hoc inspection.
    public func currentState() -> ReconnectStateMachineState { state }

    /// Starts a fresh reconnect cycle. Cancels any in-flight cycle first.
    /// `firstAttempt` is the closure for the currently-selected server; each call
    /// should `try await tunnel.connect()` and throw on failure. After
    /// `maxAttemptsPerServer` failures, `failoverNext()` is consulted for the next
    /// server. Returning nil collapses to `.allFailed`.
    public func run(
        firstAttempt: @escaping AttemptHandler,
        failoverNext: @escaping FailoverProvider
    ) {
        cancelInternal()
        currentTask = Task { [weak self] in
            await self?.driveLoop(attempt: firstAttempt, failoverNext: failoverNext)
        }
    }

    /// Cancels the running loop and resets to `.idle`. Safe to call repeatedly.
    public func cancel() {
        cancelInternal()
        state = .idle
    }

    /// Called by the controller when the OS reports `.connected` (or when the
    /// user has explicitly succeeded in a manual reconnect). Equivalent to
    /// `cancel()` but communicates intent for log readability.
    public func reportConnected() {
        cancelInternal()
        state = .idle
        log.notice("reconnect machine: reportConnected -> idle")
    }

    // MARK: Private

    private func cancelInternal() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// The retry loop. Outer iteration covers one server's full attempt budget;
    /// each successful pass of inner loop ends in `.idle` and returns. If the
    /// budget is exhausted, we consult `failoverNext()` for the next server's
    /// attempt closure and start the next outer iteration.
    private func driveLoop(
        attempt: @escaping AttemptHandler,
        failoverNext: @escaping FailoverProvider
    ) async {
        var currentAttempt = attempt

        while !Task.isCancelled {
            // Per-server retry budget (D-07: 3 attempts).
            for attemptIdx in 0..<maxAttemptsPerServer {
                if Task.isCancelled { return }
                let delay = backoffSeconds[min(attemptIdx, backoffSeconds.count - 1)]
                state = .retrying(attempt: attemptIdx + 1, delaySeconds: delay)
                log.notice("reconnect attempt \(attemptIdx + 1)/\(self.maxAttemptsPerServer) after \(delay)s")

                do {
                    try await clock.sleep(seconds: delay)
                } catch {
                    // Cancelled mid-sleep — Task is being torn down.
                    return
                }
                if Task.isCancelled { return }

                do {
                    _ = try await currentAttempt()
                    // Success. Caller is responsible for setting up follow-up
                    // health checks (Wave 5); we collapse to .idle here.
                    state = .idle
                    return
                } catch {
                    log.error("attempt \(attemptIdx + 1) failed: \(error.localizedDescription)")
                    // Fall through to next iteration of inner loop.
                }
            }

            // Exhausted attempts for current server. Try failover.
            if Task.isCancelled { return }
            guard let next = await failoverNext() else {
                state = .allFailed
                return
            }

            currentAttempt = next.attempt
            state = .failover(toServerName: next.serverName)
            log.notice("failover to \(next.serverName)")

            // Small breath before first attempt of the new server (matches §9).
            do {
                try await clock.sleep(seconds: 1)
            } catch {
                return
            }
        }
    }
}
