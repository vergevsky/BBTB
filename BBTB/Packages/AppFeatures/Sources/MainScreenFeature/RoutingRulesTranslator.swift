// RoutingRulesTranslator.swift — Phase 13 / D-04.
//
// Translates `RulesEngine.RulesSnapshot` → `[SingBoxRule]` (Sendable typed
// representation of sing-box `route.rules`). Used by `MainScreenViewModel`
// to thread routing rules через actor boundary (Swift 6 strict concurrency)
// → `ConfigImporter.provisionTunnelProfile(for:extraRoutingRules:)`.
//
// `RulesSnapshot` имеет 3 категории:
// - `block` (block_completely) → outbound: "block" (built-in sing-box outbound)
// - `never` (never_through_vpn) → outbound: "direct" (bypass tunnel)
// - `always` (always_through_vpn) → outbound: tunnel (redundant — `route.final`
//   уже = urltest/single outbound; skipped в translation)
//
// `CategoryEntries` fields:
// - `domains: [String]` → SingBoxRule.domainSuffix (sing-box `domain_suffix`,
//   suffix-match per RulesSnapshot semantics)
// - `ipCidrs: [String]` → SingBoxRule.ipCidr
// - `countries: [String]` → DISPLAY-ONLY (per RulesSnapshot doc comment);
//   routing already works через ipCidrs (resolved server-side). Skipped here.

import Foundation
import ConfigParser
import RulesEngine

enum RoutingRulesTranslator {

    /// Translate snapshot → `[SingBoxRule]`. Returns `[]` if snapshot is nil
    /// (caller passes nil when D-04 toggle is OFF).
    static func singBoxRules(from snapshot: RulesSnapshot?) -> [SingBoxRule] {
        guard let snapshot else { return [] }

        var rules: [SingBoxRule] = []
        if let blockRule = makeRule(from: snapshot.block, outbound: "block") {
            rules.append(blockRule)
        }
        if let directRule = makeRule(from: snapshot.never, outbound: "direct") {
            rules.append(directRule)
        }
        // `always_through_vpn` категория — semantically redundant: `route.final`
        // is already the tunnel outbound, so traffic matching `always` already
        // routes через VPN by default. Skip translation для economy.
        return rules
    }

    /// Build a single SingBoxRule from category entries + target outbound.
    /// Returns nil when category has no actionable fields (empty domains AND ipCidrs).
    private static func makeRule(from entries: CategoryEntries, outbound: String) -> SingBoxRule? {
        guard !entries.domains.isEmpty || !entries.ipCidrs.isEmpty else {
            return nil
        }
        return SingBoxRule(
            outbound: outbound,
            domainSuffix: entries.domains,
            ipCidr: entries.ipCidrs
        )
    }
}
