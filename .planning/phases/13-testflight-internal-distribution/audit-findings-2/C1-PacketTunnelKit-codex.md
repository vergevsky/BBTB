# C1' — PacketTunnelKit re-audit (Codex 5.5)

**Baseline:** commit 55523dd

## Plan 02 Closure Verification

| Plan 02 Finding | Plan 03 Fix Commit | Re-audit Status | Notes |
|---|---|---|---|
| A1-001 STUN tag | T-B9 (78e216f) | ✅ Closed | `SingBoxConfigLoader.swift:412-429`: emitted STUN rule no longer includes `tag`; dedup now fingerprints preserved schema fields: `action == reject`, `network == udp`, `port == [3478, 5349]`. R10 post-expand validation remains intact. |
| C1-001 commandServer leak | T-B9 (78e216f) | ✅ Closed | `BaseSingBoxTunnel.swift:310-319` and `:329-336`: both `expandConfigForTunnel` failure and post-expand `validate` failure now call `server.close()`, clear `commandServer`, clear `platformInterface`, end signpost, then complete. |

## New Findings

### [MEDIUM] C1'-001: Post-expand validation does not verify route-rule outbound references injected by PacketTunnelKit
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:121`, `:365`, `:379`, `:382`
- **Dimension:** correctness
- **Description:** `validate(json:)` builds `allTags` but only checks `urltest` / `selector` outbound child references. It does not check ordinary `route.rules[].outbound` references. Block 5 injects `outbound: "direct"` and `outbound: firstProxyTag`; if the input config lacks a `direct` outbound tag or has a proxy outbound without a tag, post-expand validation still passes and libbox fails later.
- **Why it matters:** Production builders appear to add `direct` and proxy tags, so immediate risk is limited. But `PacketTunnelKit`'s validator accepts broader configs than the builders emit.
- **Suggested fix:** Extend `validate(json:)` to validate all `route.rules[].outbound` values against outbound tags.

## Regressions Detected

None from T-B9. STUN schema fix is minimal and compatible. Command-server cleanup is added only to pre-service failure paths.

## Notes

Verdict for this package: APPROVE for Internal TestFlight, with C1'-001 tracked as Tier C unless raw/custom sing-box JSON import is in active TestFlight scope.
