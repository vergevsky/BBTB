import Foundation
import PacketTunnelKit

/// Phase 10 / DPI-06 / D-06 — CDN failure score + cooldown cache.
///
/// **Persistence:** App Group `cdnFailureCacheURL` (Library/Caches/cdn/cdn-failure-cache.json).
/// JSON encoding: `[String: FailureRecord]` dict, key = `"<provider>|<ip>|<networkType>"`.
///
/// **Cooldown ladder (Threat T-10-W5-06 mitigation):**
///   - score 1     → 6ч cooldown
///   - score 2..3  → 12ч cooldown
///   - score ≥ 4   → 24ч cooldown (max cap at score 10 to prevent integer overflow)
///
/// **Thread safety:** actor isolation. Все мутации — в actor context.
/// Single writer (main app FrontingFallbackChain). Extension не читает (D-06 invariant).
///
/// **Persistence strategy:** best-effort (try?) — cache miss не блокирует CDN функциональность.
/// При corruptd JSON: decode fails silently → fresh empty cache → CDN entries re-learn on failures.
public actor FrontingFailureCache {

    // MARK: - Codable internal types

    private struct FailureRecord: Codable {
        let score: Int
        let cooldownUntil: Date
    }

    // MARK: - State

    /// In-memory store. Persisted на disk через persist() после каждой мутации.
    private var records: [String: FailureRecord]

    /// App Group path для persistence (injectable для testing с temp path).
    private let cacheURL: URL

    /// Clock abstraction для testability (injectable в tests с mocked time).
    private let clock: @Sendable () -> Date

    // MARK: - Init

    /// - Parameters:
    ///   - cacheURL: Path для JSON persistence. Default = AppGroupContainer.cdnFailureCacheURL.
    ///   - clock:    Current time provider. Default = Date.init (wall clock).
    public init(
        cacheURL: URL = AppGroupContainer.cdnFailureCacheURL,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cacheURL = cacheURL
        self.clock = clock

        // Load existing records from disk. Best-effort: if missing or corrupt → empty cache.
        if let data = try? Data(contentsOf: cacheURL),
           let loaded = try? JSONDecoder().decode([String: FailureRecord].self, from: data) {
            self.records = loaded
        } else {
            self.records = [:]
        }
    }

    // MARK: - Public API

    /// Записать факт failure для (provider, ip, networkType).
    /// Увеличивает score, пересчитывает cooldown deadline, персистирует.
    public func recordFailure(provider: CDNProvider, ip: String, networkType: String) {
        let key = cacheKey(provider: provider, ip: ip, networkType: networkType)
        let oldScore = records[key]?.score ?? 0
        let newScore = min(oldScore + 1, 10)
        let cooldownSec = cooldownSeconds(newScore)
        let cooldownUntil = clock().addingTimeInterval(cooldownSec)
        records[key] = FailureRecord(score: newScore, cooldownUntil: cooldownUntil)
        persist()
    }

    /// Проверить, нужно ли пропустить (provider, ip, networkType) из-за активного cooldown.
    /// Returns `true` если текущее время < cooldownUntil (endpoint заблокирован).
    public func shouldSkip(provider: CDNProvider, ip: String, networkType: String) -> Bool {
        let key = cacheKey(provider: provider, ip: ip, networkType: networkType)
        guard let record = records[key] else { return false }
        return clock() < record.cooldownUntil
    }

    /// Записать факт success. Сбрасывает score и cooldown для (provider, ip, networkType).
    public func recordSuccess(provider: CDNProvider, ip: String, networkType: String) {
        let key = cacheKey(provider: provider, ip: ip, networkType: networkType)
        records[key] = nil
        persist()
    }

    // MARK: - Private helpers

    private func cacheKey(provider: CDNProvider, ip: String, networkType: String) -> String {
        "\(provider.rawValue)|\(ip)|\(networkType)"
    }

    private func cooldownSeconds(_ score: Int) -> TimeInterval {
        switch score {
        case 1:    return 6 * 3600   // 6 hours
        case 2, 3: return 12 * 3600  // 12 hours
        default:   return 24 * 3600  // 24 hours (cap)
        }
    }

    /// Best-effort JSON persistence. Failure is non-fatal (cache miss ≠ functional failure).
    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        // Atomic write (POSIX rename semantics) для consistency с RulesEngine pattern.
        try? data.write(to: cacheURL, options: .atomic)
    }
}
