---
phase: 10
plan: "02"
subsystem: packet-tunnel-kit
tags: [anti-dpi, mux, multiplex, singbox, smux, protocol-whitelist, tdd, dpi-05]
dependency_graph:
  requires: [10-01, 08-W5-ruleset-injection, 01-foundation]
  provides: [SingBoxConfigLoader-Step7-Mux, isMuxCompatible-whitelist]
  affects: [SingBoxConfigLoader.swift, SingBoxConfigLoaderTests.swift]
tech_stack:
  added: []
  patterns: [dict-mutation-expandConfigForTunnel, App-Group-UserDefaults-read, protocol-whitelist-guard]
key_files:
  created: []
  modified:
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift
    - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift
decisions:
  - "isMuxCompatible(_:) handles both sing-box 1.9 (top-level reality key) and 1.10+ (tls.reality.enabled) Reality schemas"
  - "Step 7 placed after Step 5b rule_set injection, before final JSONSerialization — consistent with Phase 8 pattern"
  - "ob['multiplex'] != nil guard preserves per-server URI/Clash overrides (D-08 double-control) for both global ON and global OFF"
  - "App Group UserDefaults read uses AppGroupContainer.identifier constant (not hardcoded string)"
metrics:
  duration: "~8 minutes (TDD: 3m RED + 4m GREEN + 1m verify)"
  completed: "2026-05-15"
  tasks_completed: 1
  tasks_total: 1
  files_created: 0
  files_modified: 2
---

# Phase 10 Plan 02: DPI-05 Mux Injection in SingBoxConfigLoader Summary

**One-liner:** `isMuxCompatible` whitelist + Step 7 smux injection in `expandConfigForTunnel` — reads App Group `muxEnabled`, idempotent, preserves per-server overrides via TDD RED→GREEN.

## Tasks Completed

| Task | Description | Commit | Result |
|------|-------------|--------|--------|
| 1 (TDD RED) | 10 failing test_mux_* tests covering all whitelist edge cases | 0fd8546 | 4 tests failing RED as expected |
| 1 (TDD GREEN) | isMuxCompatible + Step 7 Mux injection implementation | 55e16fa | 82/82 tests PASS |

## Implementation Details

### isMuxCompatible(_:) — Protocol Whitelist Helper

New private static helper before `expandConfigForTunnel`. Handles 3 VLESS variants:

| Outbound | Result | Detection Logic |
|----------|--------|-----------------|
| VLESS+TLS plain | ALLOWED | type=vless, no reality key, flow absent/not "xtls-rprx-vision" |
| VLESS+Reality (1.9-) | SKIPPED | `outbound["reality"] as? [String: Any] != nil` |
| VLESS+Reality (1.10+) | SKIPPED | `tls.reality.enabled == true` |
| VLESS+Vision | SKIPPED | `flow.contains("xtls-rprx-vision")` |
| Trojan | ALLOWED | type=trojan direct return |
| Shadowsocks | ALLOWED | type=shadowsocks direct return (includes 2022-blake3-* AEAD) |
| TUIC, Hysteria2 | SKIPPED | default case false |

### Step 7 Mux Injection Block

Inserted between existing Step 5b (Phase 8 rule_set inject) and final `JSONSerialization.data(...)`:

- Reads `UserDefaults(suiteName: AppGroupContainer.identifier)?.bool(forKey: "app.bbtb.muxEnabled") ?? false`
- Early exit if `muxEnabled == false`
- Loops `outbounds.indices`, skips if `ob["multiplex"] != nil` (idempotent + D-08 per-server override)
- Skips if `!isMuxCompatible(ob)`
- Injects `multiplex: {enabled:true, protocol:"smux", max_connections:4, padding:true}` (D-10)
- Writes back `root["outbounds"] = outbounds`

Lines added: +85 in SingBoxConfigLoader.swift (helper ~45 + block ~40)

### Test Coverage

10 `test_mux_*` tests + helpers added to SingBoxConfigLoaderTests.swift (+298 lines):

| Test | Coverage | Result |
|------|----------|--------|
| test_mux_injects_for_vless_plain_when_toggle_on | VLESS plain inject + D-10 values | GREEN |
| test_mux_skipped_for_vless_reality | tls.reality.enabled=true skip | GREEN |
| test_mux_skipped_for_vless_vision | flow=xtls-rprx-vision skip | GREEN |
| test_mux_injects_for_trojan | Trojan inject + D-10 values | GREEN |
| test_mux_injects_for_shadowsocks_2022 | SS-2022 inject + D-10 values | GREEN |
| test_mux_skipped_for_tuic_and_hysteria2 | Two QUIC outbounds, both skip | GREEN |
| test_mux_skipped_when_toggle_off | Global toggle false/absent → no inject | GREEN |
| test_mux_idempotent | Double expand → single multiplex, no nesting | GREEN |
| test_mux_preserves_existing_per_server_override | yamux override preserved when global OFF | GREEN |
| test_mux_preserves_existing_when_global_on | yamux override preserved when global ON | GREEN |

Helpers: `setMuxToggle()`, `clearMuxToggle()`, `makeMinimalSingBoxJSON()`, `firstOutbound()`, `tearDown()` override.

## Deviations from Plan

None — plan executed exactly as written. The snippet in PATTERNS.md had a simplified VLESS detection logic; RESEARCH.md Step 7 code examples were used as a more accurate basis (as the plan directed).

## Known Stubs

None. The implementation is fully functional. The `muxEnabled` flag is read from the App Group UserDefaults key `app.bbtb.muxEnabled` which was established in Wave 1 (10-01). When the user enables Mux toggle in AntiDPISection, the key is written; on next tunnel connect + `expandConfigForTunnel`, multiplex is injected for compatible servers.

## Threat Flags

No new network endpoints or auth paths introduced. All threat register mitigations from PLAN.md:

- T-10-W2-01: Unknown outbound type → `isMuxCompatible` returns false (default case). MITIGATED.
- T-10-W2-02: Mux + VLESS+Vision panic — `flow.contains("xtls-rprx-vision")` + reality.enabled guard. MITIGATED. Covered by tests 2 and 3.
- T-10-W2-06: Phase 8 rule_set injection unaffected — Step 7 only mutates `outbounds`, not `route`/`dns`/`inbounds`. MITIGATED.

## TDD Gate Compliance

- RED gate commit: 0fd8546 (`test(10-02): add failing tests for DPI-05 Mux injection`) — 4 tests failing as expected
- GREEN gate commit: 55e16fa (`feat(10-02): implement DPI-05 Mux injection`) — 82/82 tests passing

## Self-Check: PASSED

- SingBoxConfigLoader.swift modified: FOUND
- SingBoxConfigLoaderTests.swift modified: FOUND
- `isMuxCompatible` occurrences in SingBoxConfigLoader.swift: 3 (≥2 required) ✓
- `app.bbtb.muxEnabled` in SingBoxConfigLoader.swift: 1 (≥1 required) ✓
- `AppGroupContainer.identifier` in SingBoxConfigLoader.swift: 1 (≥1 required) ✓
- `xtls-rprx-vision` in SingBoxConfigLoader.swift: 4 (≥1 required) ✓
- `reality` in SingBoxConfigLoader.swift: 7 (≥1 required) ✓
- `"protocol": "smux"` in SingBoxConfigLoader.swift: 1 (≥1 required) ✓
- `"max_connections": 4` in SingBoxConfigLoader.swift: 1 (≥1 required) ✓
- `"padding": true` in SingBoxConfigLoader.swift: 1 (≥1 required) ✓
- `multiplex` in SingBoxConfigLoader.swift: 8 (≥2 required) ✓
- `test_mux` count in SingBoxConfigLoaderTests.swift: 11 (≥8 required) ✓
- swift test --filter SingBoxConfigLoaderTests: 51/51 PASS ✓
- swift test full PacketTunnelKit suite: 82/82 PASS ✓
- Commits 0fd8546, 55e16fa: present in git log ✓
