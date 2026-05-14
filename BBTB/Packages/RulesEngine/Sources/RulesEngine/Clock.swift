import Foundation

/// Wallclock abstraction для test-injectable time.
///
/// **Pattern source:** Phase 6c `ReconnectClock` (см. memory `feedback_connectedDate_authority_for_since`).
/// Production использует `SystemClock` (wraps `Date()`); tests инжектят `FixedClock` (mutable
/// `now` property) → forceUpdate cooldown / age-based decisions test-deterministic без `Task.sleep`.
public protocol ClockProtocol: Sendable {
    func now() -> Date
}

/// Production clock — direct `Date()` delegation.
public struct SystemClock: ClockProtocol {
    public init() {}
    public func now() -> Date { Date() }
}
