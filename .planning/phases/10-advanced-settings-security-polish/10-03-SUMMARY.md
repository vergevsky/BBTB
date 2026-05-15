---
phase: 10-advanced-settings-security-polish
plan: "03"
subsystem: vpn-core
tags: [stun-block, kill-switch, enforce-routes, macos, anti-dpi, sing-box, route-rule, platform-hooks, userdefaults]

# Dependency graph
requires:
  - phase: 10-advanced-settings-security-polish/10-01
    provides: "@AppStorage keys for stunBlockEnabled + macOSDisableEnforceRoutes wired to App Group suite"
  - phase: 10-advanced-settings-security-polish/10-02
    provides: "SingBoxConfigLoader.expandConfigForTunnel step 7 (Mux injection) already in place"
  - phase: 01-foundation
    provides: "PlatformHooks + KillSwitch Phase 1 stubs to replace"
provides:
  - "BIO-04 STUN block: route.rule inject for UDP 3478/5349 (action=reject, method=drop) in expandConfigForTunnel step 6"
  - "KILL-04 macOS enforceRoutes: PlatformHooks.shouldDisableEnforceRoutes() reads App Group UserDefaults"
  - "KILL-04 macOS enforceRoutes: KillSwitch.platformShouldDisableEnforceRoutes() platform-conditional (#if os(macOS))"
  - "KILL-04 live-apply: SettingsViewModel.applyEnforceRoutesToManager() async (macOS only)"
  - "SecuritySection .onChange wire-up for live-apply on toggle change"
affects:
  - 10-advanced-settings-security-polish
  - phase-11-ui-polish

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Step insertion in expandConfigForTunnel: STUN block as step 6 between Phase 8 rule_set (step 5b) and Mux (step 7)"
    - "Idempotency via tag-based deduplication: rules.contains { $0[\"tag\"] == \"bbtb-stun-block\" }"
    - "#if os(macOS) conditional in KillSwitch package for platform-specific UserDefaults read"
    - "KillSwitch hardcodes App Group suite name string — does not import PacketTunnelKit (Phase 1 arch design)"
    - "nonisolated applyEnforceRoutesToManager follows applyAutoReconnectToManager pattern (Phase 6c)"

key-files:
  created:
    - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/PlatformHooksTests.swift
  modified:
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift
    - BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SecuritySection.swift
    - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift
    - BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift
    - BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift

key-decisions:
  - "STUN block inserted as step 6 (between phase 8 rule_set and step 7 Mux) to avoid file conflict with Plan 02"
  - "Idempotency via tag lookup ('bbtb-stun-block') matches Plan 02 Mux idempotency pattern (key existence check)"
  - "KillSwitch hardcodes App Group suite name 'group.app.bbtb.shared' — cannot import PacketTunnelKit (arch boundary)"
  - "applyEnforceRoutesToManager follows exact same nonisolated async pattern as applyAutoReconnectToManager (Phase 6c)"
  - "SecuritySection .onChange uses iOS 17+ / macOS 14+ two-parameter signature (project targets iOS 18 / macOS 15)"

patterns-established:
  - "sing-box route.rule idempotency via tag field: check before insert, skip on duplicate"
  - "Platform-conditional UserDefaults read: #if os(macOS) with hardcoded suite name when cross-package import not allowed"
  - "live-apply toggle pattern: nonisolated async method + .onChange(of:) wire + post .bbtbProvisionerDidSave"

requirements-completed: [BIO-04, KILL-04]

# Metrics
duration: 6min
completed: 2026-05-15
---

# Phase 10 Plan 03: Wave 3 — STUN block + macOS enforceRoutes Summary

**STUN-block UDP 3478/5349 injected into sing-box route.rules as idempotent step 6; macOS enforceRoutes Phase 1 stubs replaced with App Group UserDefaults reads in PlatformHooks + KillSwitch; live-apply wired via applyEnforceRoutesToManager + SecuritySection .onChange**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-15T14:54:00Z
- **Completed:** 2026-05-15T15:00:30Z
- **Tasks:** 2 (TDD: both with RED → GREEN cycle)
- **Files modified:** 9 (1 created, 8 modified)

## Accomplishments

- BIO-04 STUN block: `expandConfigForTunnel` step 6 injects `{tag:"bbtb-stun-block", port:[3478,5349], network:"udp", action:"reject", method:"drop"}` when `stunBlockEnabled=true`; idempotent via tag check; inserted AFTER hijack-dns and BEFORE Phase 8 rule_set priority rules; coexists with step 7 Mux injection
- KILL-04 macOS enforceRoutes: both hook stubs replaced — `PlatformHooks.shouldDisableEnforceRoutes()` reads `AppGroupContainer.identifier` suite; `KillSwitch.platformShouldDisableEnforceRoutes()` uses `#if os(macOS)` with hardcoded suite name (arch boundary between packages)
- live-apply flow complete: `SettingsViewModel.applyEnforceRoutesToManager()` async (macOS-only extension) follows Phase 6c pattern; SecuritySection `.onChange(of: viewModel.macOSDisableEnforceRoutes)` wired with two-parameter iOS 17+/macOS 14+ signature
- 10 new unit tests across 3 test files + 1 new test file (PlatformHooksTests.swift); all 271 tests green (91 PacketTunnelKit + 9 KillSwitch + 171 AppFeatures)

## Task Commits

Each task was committed atomically:

1. **Task 1: STUN block route.rule injection (BIO-04)** - `165d6d0` (feat)
2. **Task 2: macOS enforceRoutes — PlatformHooks + KillSwitch + live-apply (KILL-04)** - `268e70e` (feat)

_Note: TDD tasks — both went through RED (failing tests first) → GREEN (implementation) cycle_

## Files Created/Modified

- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` - Added step 6 STUN block injection block (35 lines) between step 5b and step 7
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift` - Replaced Phase 1 `return false` stub with App Group UserDefaults read
- `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` - Replaced Phase 1 `return false` stub with `#if os(macOS)` conditional UserDefaults read
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` - Added `import KillSwitch` + `applyEnforceRoutesToManager()` macOS extension (~45 lines)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SecuritySection.swift` - Added `.onChange(of: viewModel.macOSDisableEnforceRoutes)` modifier to enforceRoutes Toggle
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/PlatformHooksTests.swift` - NEW: 3 macOS-only tests for PlatformHooks UserDefaults read
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` - Added 6 STUN block tests (test_stun_block_*)
- `BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift` - Added macOS enforceRoutes toggle test
- `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift` - Added macOS smoke test for applyEnforceRoutesToManager

## Decisions Made

- **STUN block as step 6:** Inserted between existing step 5b (Phase 8 rule_set) and step 7 (Mux, Plan 02) to match plan design and avoid file conflicts. This ordering ensures DNS hijack works (above STUN) and STUN drop happens before final outbound routing.
- **KillSwitch hardcodes suite name:** `"group.app.bbtb.shared"` hardcoded in KillSwitch.swift — package cannot import PacketTunnelKit (Phase 1 architectural constraint). Doc-comment warns about drift risk.
- **applyEnforceRoutesToManager pattern:** Follows Phase 6c `applyAutoReconnectToManager` pattern exactly — `nonisolated async`, `ManagerSelector.ourManagers`, `KillSwitch.apply`, `saveToPreferences`, `bbtbProvisionerDidSave` notification.

## Deviations from Plan

None — plan executed exactly as written. All tests and acceptance criteria pass.

## Issues Encountered

None. KillSwitch package already had `KillSwitch` as a dependency in SettingsFeature (found in Package.swift), so only `import KillSwitch` was needed in SettingsViewModel.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced. Changes are internal UserDefaults reads within existing App Group sandbox. T-10-W3-01 through T-10-W3-07 threats from plan's threat model — all handled per disposition (accept/mitigate per plan spec).

## Known Stubs

None. All Phase 1 stubs replaced with real implementations.

## Next Phase Readiness

- Wave 3 complete: BIO-04 and KILL-04 requirements satisfied
- STUN block and Mux injection coexist (verified by `test_stun_block_coexists_with_mux`)
- macOS enforceRoutes live-apply ready for UAT (device test needed — verify bbtbProvisionerDidSave notification fires)
- Ready for Phase 10 Wave 4 (remaining plans in phase)

---
*Phase: 10-advanced-settings-security-polish*
*Completed: 2026-05-15*

## Self-Check: PASSED

Files verified present:
- BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift: FOUND
- BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift: FOUND
- BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift: FOUND
- BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift: FOUND
- BBTB/Packages/AppFeatures/Sources/SettingsFeature/SecuritySection.swift: FOUND
- BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/PlatformHooksTests.swift: FOUND (new)

Commits verified present:
- 165d6d0: feat(10-03): STUN block route.rule injection (BIO-04 / D-16)
- 268e70e: feat(10-03): macOS enforceRoutes toggle — PlatformHooks + KillSwitch + live-apply (KILL-04)
