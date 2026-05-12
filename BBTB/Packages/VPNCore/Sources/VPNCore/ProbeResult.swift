// ProbeResult.swift — D-01: Sendable value types для TCP probe results.
// Phase 3 / Plan 02.

import Foundation

/// Результат одной TCP-проверки до удалённого хоста.
///
/// Sendable (enum w/ associated values из Int/String) — безопасно передавать через
/// actor boundary без `await self.` (см. Phase 3 RESEARCH «Pitfall 4 — не передавать
/// [ServerConfig] через actor»).
public enum ProbeResult: Sendable, Equatable {
    /// Handshake успешен; `latencyMs` — wall-clock от старта до .ready (clamped к ≥1).
    case ok(latencyMs: Int)
    /// Manual 500ms timeout сработал ИЛИ outer Task cancellation отменил probe.
    case timeout
    /// NWConnection вернул .failed/.waiting с описательной ошибкой.
    case error(String)
}

/// Aggregate по 3 probes (D-01): средняя latency, loss rate, момент замера.
///
/// `score = avgLatencyMs × (1 + lossRate)` — формула из D-01. nil avgLatencyMs
/// (все 3 probe failed) → nil score → сервер не участвует в autoSelect.
public struct ProbeAggregate: Sendable, Equatable {
    /// Средняя latency успешных probes, ms. nil если все 3 failed (isUnreachable).
    public let avgLatencyMs: Int?
    /// Число failed probes (0..3). CR-05: источник истины для
    /// `ServerConfig.failedProbeCount`; `lossRate` derived =
    /// `Double(failures) / Double(failures + successes)`. Сохраняется напрямую
    /// чтобы избежать IEEE-754 truncation при обратном пересчёте `Int(lossRate * 3)`.
    public let failures: Int
    /// Доля failed probes: 0.0, 1/3, 2/3, 1.0.
    public let lossRate: Double
    /// Wall-clock момент завершения 3-probe цикла (для UI «обновлено N сек назад»).
    public let probedAt: Date

    public init(avgLatencyMs: Int?, failures: Int, lossRate: Double, probedAt: Date) {
        self.avgLatencyMs = avgLatencyMs
        self.failures = failures
        self.lossRate = lossRate
        self.probedAt = probedAt
    }

    /// Композитный score для autoSelect. nil если сервер unreachable.
    public var score: Double? {
        guard let ms = avgLatencyMs else { return nil }
        return Double(ms) * (1.0 + lossRate)
    }

    /// true если все 3 probes failed (avgLatencyMs == nil). Используется для
    /// серых badge'ей в UI (Plan 03 LatencyBadge.unreachable).
    public var isUnreachable: Bool { avgLatencyMs == nil }
}
