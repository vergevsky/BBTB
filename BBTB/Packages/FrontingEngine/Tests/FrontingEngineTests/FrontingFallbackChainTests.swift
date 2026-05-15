import Foundation
import Testing
@testable import FrontingEngine

// MARK: - Test helpers

/// Mutable clock for injecting controlled time in FrontingFailureCache tests.
private final class MutableClock: @unchecked Sendable {
    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    var closure: @Sendable () -> Date {
        { [weak self] in self?.now ?? Date() }
    }
}

private func makeProfile(
    provider: CDNProvider = .cloudflare,
    connectHost: String = "1.1.1.1"
) -> FrontingProfile {
    FrontingProfile(
        provider: provider,
        connectHost: connectHost,
        connectPort: 443,
        sniHost: "cdn.example.com",
        httpHost: "cdn.example.com",
        mode: .domain
    )
}

private func makeTempCacheURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("fronting-test-\(UUID().uuidString).json")
}

// MARK: - FrontingFailureCache tests

@Suite("FrontingFailureCache — score + cooldown")
struct FrontingFailureCacheTests {

    // MARK: Test 8 — recordFailure sets shouldSkip

    @Test("recordFailure sets shouldSkip to true during cooldown")
    func test_failure_cache_records_score_and_cooldown() async throws {
        let cacheURL = makeTempCacheURL()
        let clock = MutableClock(now: Date())
        let cache = FrontingFailureCache(cacheURL: cacheURL, clock: clock.closure)

        // Initially not skipped
        let skippedBefore = await cache.shouldSkip(provider: .cloudflare, ip: "1.2.3.4", networkType: "wifi")
        #expect(skippedBefore == false)

        // Record failure
        await cache.recordFailure(provider: .cloudflare, ip: "1.2.3.4", networkType: "wifi")

        // Now should be skipped (cooldown active)
        let skippedAfter = await cache.shouldSkip(provider: .cloudflare, ip: "1.2.3.4", networkType: "wifi")
        #expect(skippedAfter == true)

        // Verify persistence: cache file should exist
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    // MARK: Test 9 — cooldown expires after threshold

    @Test("shouldSkip returns false after cooldown expires")
    func test_failure_cache_cooldown_respected() async {
        let cacheURL = makeTempCacheURL()
        let clock = MutableClock(now: Date())
        let cache = FrontingFailureCache(cacheURL: cacheURL, clock: clock.closure)

        // Record failure (score=1 → 6h cooldown)
        await cache.recordFailure(provider: .fastly, ip: "2.2.2.2", networkType: "cellular")

        // Advance time by 5 hours — still in cooldown
        clock.advance(by: 5 * 3600)
        let stillBlocked = await cache.shouldSkip(provider: .fastly, ip: "2.2.2.2", networkType: "cellular")
        #expect(stillBlocked == true)

        // Advance past 6h threshold — cooldown expired
        clock.advance(by: 2 * 3600)
        let expired = await cache.shouldSkip(provider: .fastly, ip: "2.2.2.2", networkType: "cellular")
        #expect(expired == false)
    }

    // MARK: Test — recordSuccess resets shouldSkip

    @Test("recordSuccess resets failure score so shouldSkip returns false")
    func test_failure_cache_success_resets() async {
        let cacheURL = makeTempCacheURL()
        let cache = FrontingFailureCache(cacheURL: cacheURL)

        await cache.recordFailure(provider: .cloudflare, ip: "3.3.3.3", networkType: "wifi")
        let blocked = await cache.shouldSkip(provider: .cloudflare, ip: "3.3.3.3", networkType: "wifi")
        #expect(blocked == true)

        await cache.recordSuccess(provider: .cloudflare, ip: "3.3.3.3", networkType: "wifi")
        let cleared = await cache.shouldSkip(provider: .cloudflare, ip: "3.3.3.3", networkType: "wifi")
        #expect(cleared == false)
    }
}

// MARK: - FrontingFallbackChain tests

@Suite("FrontingFallbackChain — sequential cursor + exhaustion")
struct FrontingFallbackChainTests {

    // MARK: Test 10 — sequential advance on failure

    @Test("chain advances cursor on reportFailure and returns nil when exhausted")
    func test_fallback_chain_advances_on_failure() async {
        let cacheURL = makeTempCacheURL()
        // Use a fast clock so cooldown check passes for non-failed profiles
        let cache = FrontingFailureCache(cacheURL: cacheURL)

        let profiles = [
            makeProfile(connectHost: "10.0.0.1"),
            makeProfile(connectHost: "10.0.0.2"),
            makeProfile(connectHost: "10.0.0.3"),
        ]
        let chain = FrontingFallbackChain(profiles: profiles, cache: cache)

        // First endpoint: profile1
        let (p1, ex1) = await chain.nextEndpoint(networkType: "wifi")
        #expect(p1?.connectHost == "10.0.0.1")
        #expect(ex1 == false)

        // Report failure on profile1 — adds to cache
        await chain.reportFailure(profile: profiles[0], networkType: "wifi")

        // Second call: profile2 (profile1 now in cooldown, cursor already past it)
        let (p2, ex2) = await chain.nextEndpoint(networkType: "wifi")
        #expect(p2?.connectHost == "10.0.0.2")
        #expect(ex2 == false)

        // Report failure on profile2
        await chain.reportFailure(profile: profiles[1], networkType: "wifi")

        // Third call: profile3
        let (p3, ex3) = await chain.nextEndpoint(networkType: "wifi")
        #expect(p3?.connectHost == "10.0.0.3")
        #expect(ex3 == false)

        // Fourth call: exhausted
        let (p4, ex4) = await chain.nextEndpoint(networkType: "wifi")
        #expect(p4 == nil)
        #expect(ex4 == true)
    }

    // MARK: Test 11 — concurrent access is thread-safe (DEC-06d-04)

    @Test("concurrent nextEndpoint calls are thread-safe (actor isolation)")
    func test_fallback_chain_sequential_concurrency_1() async {
        let cacheURL = makeTempCacheURL()
        let cache = FrontingFailureCache(cacheURL: cacheURL)

        let profiles = (0..<5).map { i in
            makeProfile(connectHost: "10.1.0.\(i)")
        }
        let chain = FrontingFallbackChain(profiles: profiles, cache: cache)

        // Launch multiple concurrent nextEndpoint calls
        var results: [(FrontingProfile?, Bool)] = []

        await withTaskGroup(of: (FrontingProfile?, Bool).self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await chain.nextEndpoint(networkType: "wifi")
                }
            }
            for await result in group {
                results.append(result)
            }
        }

        // All results should be non-exhausted (we have exactly 5 profiles + 5 calls)
        let exhaustedCount = results.filter { $0.1 == true }.count
        let nonNilProfiles = results.compactMap { $0.0 }

        // With 5 profiles and 5 concurrent calls: actor serializes them,
        // all 5 profiles returned exactly once (no duplicates, no skip)
        #expect(exhaustedCount == 0)
        #expect(nonNilProfiles.count == 5)

        // All returned profiles must be unique (cursor advanced sequentially)
        let uniqueHosts = Set(nonNilProfiles.map { $0.connectHost })
        #expect(uniqueHosts.count == 5)
    }

    // MARK: Test — reset restores cursor

    @Test("reset() restores cursor to 0, allowing profiles to be reused")
    func test_fallback_chain_reset_restores_cursor() async {
        let cacheURL = makeTempCacheURL()
        let cache = FrontingFailureCache(cacheURL: cacheURL)

        let profiles = [
            makeProfile(connectHost: "20.0.0.1"),
            makeProfile(connectHost: "20.0.0.2"),
        ]
        let chain = FrontingFallbackChain(profiles: profiles, cache: cache)

        let (p1, _) = await chain.nextEndpoint(networkType: "wifi")
        let (p2, _) = await chain.nextEndpoint(networkType: "wifi")
        let (p3, ex3) = await chain.nextEndpoint(networkType: "wifi")
        #expect(p1?.connectHost == "20.0.0.1")
        #expect(p2?.connectHost == "20.0.0.2")
        #expect(p3 == nil && ex3 == true)

        // After reset, same profiles are reachable again
        await chain.reset()
        let (r1, _) = await chain.nextEndpoint(networkType: "wifi")
        #expect(r1?.connectHost == "20.0.0.1")
    }
}
