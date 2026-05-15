import Foundation

/// Phase 10 / DPI-06 / D-06 — Sequential CDN fallback chain.
///
/// **DEC-06d-04 concurrency=1:** actor isolation ensures sequential access to cursor.
/// Concurrent callers to `nextEndpoint` are serialized by Swift actor re-entrancy rules
/// (one caller at a time enters the actor). No additional locking needed.
///
/// **State machine:**
/// - `cursor` advances forward on each `nextEndpoint` call (skip cooldown entries).
/// - After exhaustion → returns (nil, exhausted: true). Admin must reset() or provision
///   new profiles for recovery.
/// - `reset()` — resets cursor to 0 for retry cycle. Called from ConfigImporter
///   after successful direct-connect (Plan 06 wiring).
///
/// **Threat T-10-W5-03 mitigation (D-06 FallbackChain):**
/// Sequential provider advance + cooldown 6-24ч. После exhaustion → Plan 06 ConfigImporter
/// falls back to direct Reality/Vision profile (non-CDN-fronted server).
///
/// **Threat T-10-W5-08 mitigation:** actor isolation makes concurrent nextEndpoint() calls safe.
/// Test 11 в FrontingFallbackChainTests verifies concurrent access correctness.
public actor FrontingFallbackChain {

    // MARK: - State

    /// Static ordered list of CDN endpoints. Admin provisioned via subscription JSON (Plan 06).
    private let profiles: [FrontingProfile]

    /// Current position in profiles list. Advances on each successful nextEndpoint call.
    private var cursor: Int = 0

    /// Shared failure cache для cooldown-aware filtering.
    private let cache: FrontingFailureCache

    // MARK: - Init

    /// - Parameters:
    ///   - profiles: Ordered list of CDN profiles to try (admin-provisioned pool).
    ///   - cache:    Shared FrontingFailureCache for cooldown-based skip decisions.
    public init(profiles: [FrontingProfile], cache: FrontingFailureCache) {
        self.profiles = profiles
        self.cache = cache
    }

    // MARK: - Public API

    /// Retrieve next viable CDN endpoint, skipping cooldown-blocked entries.
    ///
    /// - Parameter networkType: Current network type string (e.g., "wifi", "cellular").
    ///   Used as part of the failure cache composite key.
    /// - Returns: Tuple with next FrontingProfile (or nil if exhausted) + exhaustion flag.
    ///
    /// **Single-pass semantics:** iterates from cursor to end, returns first non-blocked
    /// profile. Advances cursor past returned profile (next call starts from cursor+1).
    ///
    /// **Actor reentrancy note (DEC-06d-04 concurrency=1):**
    /// `await cache.shouldSkip` is a suspension point. Swift actors allow reentrancy during
    /// await — another `nextEndpoint` caller can enter the actor while this one is suspended.
    /// To prevent cursor race: cursor is advanced (reserved) BEFORE the await suspension,
    /// and rolled back if the profile turns out to be in cooldown.
    /// This ensures each call claims a unique cursor slot atomically (before suspension).
    public func nextEndpoint(networkType: String) async -> (FrontingProfile?, exhausted: Bool) {
        // Pre-advance cursor to reserve slot before any suspension point.
        // If the reserved slot is blocked, continue to next reservation.
        while cursor < profiles.count {
            let index = cursor
            let p = profiles[index]
            // Reserve this slot — cursor advanced before await suspension.
            cursor = index + 1

            let skip = await cache.shouldSkip(
                provider: p.provider,
                ip: p.connectHost,
                networkType: networkType
            )
            if skip {
                // This profile is in cooldown — continue reserving next slot.
                continue
            }
            // Profile is viable — return it.
            return (p, false)
        }
        // All profiles consumed or blocked.
        return (nil, true)
    }

    /// Report failure for a profile — updates failure cache + cooldown.
    public func reportFailure(profile: FrontingProfile, networkType: String) async {
        await cache.recordFailure(
            provider: profile.provider,
            ip: profile.connectHost,
            networkType: networkType
        )
    }

    /// Report success for a profile — resets failure score in cache.
    public func reportSuccess(profile: FrontingProfile, networkType: String) async {
        await cache.recordSuccess(
            provider: profile.provider,
            ip: profile.connectHost,
            networkType: networkType
        )
    }

    /// Reset cursor to beginning of profiles list.
    /// Call after: exhaustion recovery, new subscription provisioning, or app restart.
    public func reset() {
        cursor = 0
    }
}
