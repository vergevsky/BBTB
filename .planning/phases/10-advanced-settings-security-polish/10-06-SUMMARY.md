---
phase: "10"
plan: "06"
subsystem: FrontingEngine integration, uTLS picker, CDN hook, Phase 10 closure
tags: [fronting, cdn, utls, dpi, wiki, documentation, tdd]
dependency_graph:
  requires: [10-05-PLAN.md, FrontingEngine SwiftPM package, PoolBuilder, ConfigImporter]
  provides: [uTLS global picker override, CDN fronting wire, Phase 10 requirements, wiki sync]
  affects: [ConfigParser/PoolBuilder.swift, AppFeatures/ConfigImporter.swift, Tuist Project.swift, REQUIREMENTS.md, ROADMAP.md, STATE.md, wiki/*]
tech_stack:
  added: []
  patterns:
    - uTLS picker via App Group UserDefaults (group.app.bbtb.shared / app.bbtb.utlsFingerprint)
    - CDN fronting hook via FrontingConfigApplier.apply (graceful degradation)
    - TDD RED/GREEN for uTLS picker behavior
key_files:
  created:
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift (3 new uTLS picker tests)
    - Wiki/advanced-settings.md
    - Wiki/cdn-fronting-architecture-2026.md
    - Wiki/cdn-fronting-server-handoff.md
    - Wiki/cert-pinning-spki.md
    - .claude/projects/.../memory/project_phase12_subscription_pins_prerequisite.md
  modified:
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
    - BBTB/Packages/AppFeatures/Package.swift
    - BBTB/Project.swift
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md
    - .planning/STATE.md
    - Wiki/anti-dpi-techniques.md
    - Wiki/architecture.md
    - Wiki/security-gaps.md
    - Wiki/index.md
    - Wiki/log.md
decisions:
  - FrontingEngine wired to main app targets only (NOT tunnel extension — extension reads from App Group)
  - uTLS picker overrides only when current outbound fingerprint == "random" (preserves URI-explicit fp=)
  - CDN hook uses graceful degradation — FrontingConfigApplier errors caught, VPN connect proceeds unmodified
  - extractFrontingProfile() returns nil for all servers in v0.10 (infrastructure-only, Phase 11 activates)
  - DPI-06 stays [ ] in REQUIREMENTS (not [x]) — infrastructure-validated but not end-to-end validated
metrics:
  duration: "~45 minutes (across 2 sessions)"
  completed_date: "2026-05-15"
  tasks_completed: 2
  files_changed: 18
---

# Phase 10 Plan 06: Final Integration Wave Summary

**One-liner:** FrontingEngine wired into Tuist/AppFeatures with uTLS global picker override (DPI-09) and CDN fronting hook (DPI-06 infrastructure); Phase 10 requirements, state, and wiki synced for closure.

## Tasks Completed

| Task | Type | Description | Commit |
|------|------|-------------|--------|
| 1 | TDD (RED+GREEN) | FrontingEngine Tuist wire + uTLS picker + CDN hook | RED: a20993b / GREEN: dbe86f6 |
| 2 | auto | REQUIREMENTS/ROADMAP/STATE updates + wiki sync (12 files) | 481d6da |

## Task 1 — TDD Execution

### RED (a20993b)

Added 3 failing tests to `PoolBuilderTests.swift` (+ `tearDown` UserDefaults cleanup):

1. `test_buildSingBoxJSON_applies_utls_picker_from_app_group_userDefaults` — picker "chrome" → outbound fingerprint must become "chrome"
2. `test_buildSingBoxJSON_picker_default_random_preserves_existing_behavior` — picker absent/default "random" → fingerprint stays "random"
3. `test_buildSingBoxJSON_picker_does_not_override_uri_explicit_fp` — URI fp="chrome" + picker "firefox" → fingerprint stays "chrome" (URI has priority)

All 3 failed before implementation (confirmed RED gate).

### GREEN (dbe86f6)

Implemented in 4 files:

**PoolBuilder.swift** — added `applyUTLSPickerOverride(_:fingerprint:)` helper and picker override logic in `buildSingBoxJSON`. Key rule: override fires only when `current == "random"` — non-"random" URI values are preserved.

**Tuist Project.swift** — added FrontingEngine to `localPackages` and to iOS + macOS main app target dependencies. NOT added to tunnel extension targets (extension reads processed config from App Group).

**AppFeatures/Package.swift** — added `../FrontingEngine` to package dependencies, `"FrontingEngine"` to MainScreenFeature target.

**ConfigImporter.swift** — added `import FrontingEngine`, CDN fronting hook between `buildSingBoxJSON` and R1 validate. Hook is no-op in v0.10 because `extractFrontingProfile()` returns nil.

### Verification

- ConfigParser 243/243 tests PASS (includes 3 new uTLS picker tests)
- FrontingEngine 20/20 tests PASS
- AppFeatures 171/171 tests PASS

## Task 2 — Phase 10 Closure

### REQUIREMENTS.md

| Requirement | Change |
|-------------|--------|
| UX-06 | `[ ]` → `[x]` ✅ |
| DPI-05 | `[ ]` → `[x]` ✅ (Mux injection in SingBoxConfigLoader) |
| DPI-06 | kept `[ ]` with ⚙️ infrastructure-validated suffix |
| DPI-08 | already `[x]`, added Phase 10 closure suffix |
| DPI-09 | already `[x]`, added Phase 10 closure suffix |
| BIO-04 | `[ ]` → `[x]` ✅ |
| KILL-04 | already `[x]`, added Phase 10 closure suffix |

### ROADMAP.md

- Phase 10 status: ⚙️ Implementation complete 2026-05-15
- 10-06-PLAN.md marked `[x]` (6/6 plans executed)
- Success criteria annotated with ✓ markers (criterion 3 = ⚙️ for DPI-06)

### STATE.md

- Milestone: v0.10
- Status: phase-complete
- Phase 10 ✅ CLOSED section with 6-wave table and key decisions

### Wiki (5 new + 3 updated)

New pages:
- `advanced-settings.md` — D-15 layout, toggle table, macOS-only gates
- `cdn-fronting-architecture-2026.md` — FrontingEngine, D-03/D-05/D-06, v0.10 status
- `cdn-fronting-server-handoff.md` — Cloudflare Worker code, FrontingProfile JSON, Marzban instructions
- `cert-pinning-spki.md` — Apple Security SPKI pipeline, generate-spki-pin.swift, Phase 12 rotation

Updated pages:
- `anti-dpi-techniques.md` — Phase 10 toggles section, v0.10 roadmap entry
- `architecture.md` — FrontingEngine in packages, PinStore in ConfigParser
- `security-gaps.md` — R21 cert pinning, R22 STUN block, R23 enforceRoutes, R24 CDN fronting

index.md and log.md also updated.

### Memory

Created `project_phase12_subscription_pins_prerequisite.md` — warns about placeholder SPKI pins in PinStore.swift that MUST be replaced before TestFlight via `generate-spki-pin.swift`.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Design Decisions Applied

**[Rule 2 - Missing Info] Priority rule for uTLS picker documented in code**
- The plan's DPI-09 spec said "picker override" but did not specify priority between URI fp= and global picker
- Applied research decision: URI fp= (non-"random") wins over global picker
- Implementation: `applyUTLSPickerOverride` only modifies fingerprint when `current == "random"`
- This correctly handles the case where URI explicitly sets fp=chrome — the picker should not override it

**[Rule 2 - Missing Validation] extractFrontingProfile marked as infrastructure-only**
- DPI-06 marked `[ ]` in REQUIREMENTS (not `[x]`) to reflect actual state
- extractFrontingProfile() returns nil for all servers until Phase 11 admin handoff
- CDN fronting is therefore no-op in v0.10

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `extractFrontingProfile(for:) → nil` | ConfigImporter.swift | Phase 11 task — server-side FrontingProfile payload not yet delivered by Marzban |
| `BootstrapPins.vpnVergevskyRu` = placeholder | PinStore.swift | Phase 12 prerequisite — replace with real SPKI via generate-spki-pin.swift BEFORE TestFlight |

These stubs are intentional and documented — DPI-06 activation and real pins are Phase 11/12 tasks.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes were introduced by this plan. The CDN fronting hook in ConfigImporter is outbound-only and fails closed (graceful degradation on error).

## Self-Check

### Created files exist:
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift` — 3 new tests added (file existed)
- `Wiki/advanced-settings.md` — new file (commit 481d6da)
- `Wiki/cdn-fronting-architecture-2026.md` — new file
- `Wiki/cdn-fronting-server-handoff.md` — new file
- `Wiki/cert-pinning-spki.md` — new file

### Commits exist:
- `a20993b` — TDD RED test commit
- `dbe86f6` — TDD GREEN implementation commit
- `481d6da` — Phase 10 closure docs commit

### Test verification:
- ConfigParser 243/243 PASS
- FrontingEngine 20/20 PASS
- AppFeatures 171/171 PASS

## Self-Check: PASSED
