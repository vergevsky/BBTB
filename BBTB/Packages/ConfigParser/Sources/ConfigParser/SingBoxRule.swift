// SingBoxRule.swift — Phase 13 / D-04.
//
// Sendable representation of one sing-box `route.rules[]` entry. Used to
// thread RulesEngine snapshot → ConfigImporter → PoolBuilder через actor
// boundary без Swift 6 strict-concurrency violations (Sendable enforcement).
//
// Plain `[String: Any]` Swift dict is NOT Sendable. We wrap with a typed
// Sendable struct and serialize to JSON dict only at PoolBuilder render-time
// (synchronously, within JSON build).

import Foundation

public struct SingBoxRule: Sendable, Equatable {
    /// Target outbound tag. Common: "block" (built-in deny), "direct" (bypass
    /// tunnel), "{tunnel-tag}" (force через tunnel).
    public let outbound: String

    /// Domain suffix matchers — sing-box `domain_suffix` field. Suffix-match
    /// semantics: "example.com" matches "example.com" + "foo.example.com".
    public let domainSuffix: [String]

    /// IPv4/IPv6 CIDR blocks — sing-box `ip_cidr` field. Both literal IPs
    /// (e.g. "1.2.3.4/32") и ranges ("10.0.0.0/8") supported.
    public let ipCidr: [String]

    public init(outbound: String, domainSuffix: [String] = [], ipCidr: [String] = []) {
        self.outbound = outbound
        self.domainSuffix = domainSuffix
        self.ipCidr = ipCidr
    }

    /// Serialize to sing-box rule JSON dict — only invoked синхронно внутри
    /// `PoolBuilder.buildSingBoxJSON` render path (main actor / build thread).
    /// Plain Dict не Sendable, поэтому returned value НЕ должен crossить async
    /// boundaries — caller сразу feeds в JSONSerialization.
    public var jsonDict: [String: Any] {
        var d: [String: Any] = ["outbound": outbound]
        if !domainSuffix.isEmpty {
            d["domain_suffix"] = domainSuffix
        }
        if !ipCidr.isEmpty {
            d["ip_cidr"] = ipCidr
        }
        return d
    }
}
