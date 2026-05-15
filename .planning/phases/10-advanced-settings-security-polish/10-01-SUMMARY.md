---
phase: 10
plan: "01"
subsystem: settings-feature
tags: [anti-dpi, utls, mux, cdn-fronting, stun-block, cert-pinning, enforce-routes, app-group, localization, tdd]
dependency_graph:
  requires: [08-W3-rules-engine, 07-anti-dpi-suite]
  provides: [AntiDPISection, SecuritySection, UTLSPickerView, SettingsViewModel-Phase10]
  affects: [AdvancedSettingsView, L10n, Localizable.xcstrings, REQUIREMENTS.md]
tech_stack:
  added: [UTLSPickerView]
  patterns: [AppStorage-AppGroup-suite, Published-alert-binding, conditional-macOS-compilation]
key_files:
  created:
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/AntiDPISection.swift
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SecuritySection.swift
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/UTLSPickerView.swift
  modified:
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
    - BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift
    - BBTB/Packages/Localization/Sources/Localization/L10n.swift
    - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
    - .planning/REQUIREMENTS.md
decisions:
  - "App Group suite (group.app.bbtb.shared) for NE-visible keys (mux, stun, utls, enforceRoutes); .standard for main-app-only keys (cdn, certPinning)"
  - "stunBlockShowConfirm uses @Published (NOT @AppStorage) — ephemeral UI state, not persisted"
  - "SecuritySection enforceRoutes toggle is inverted (value=false means routes ARE enforced) to match KILL-04 semantics"
  - "BIO-01/02/03 + ONDEMAND-01 deferred out of Phase 10 scope per D-01/D-02 in 10-CONTEXT.md"
metrics:
  duration: "~35 minutes"
  completed: "2026-05-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 3
  files_modified: 8
---

# Phase 10 Plan 01: Anti-DPI + Security Settings Foundation Summary

**One-liner:** `@AppStorage` App Group props + AntiDPISection/SecuritySection/UTLSPickerView + 22 xcstrings keys via TDD RED→GREEN.

## Tasks Completed

| Task | Description | Commit | Result |
|------|-------------|--------|--------|
| 1 (TDD RED) | Failing tests for 6 new @AppStorage props | c800127 | 6 tests RED |
| 1 (TDD GREEN) | Scope amendment + 6 @AppStorage props in SettingsViewModel | 07c91d9 | 170 tests PASS |
| 2 | AntiDPISection + SecuritySection + UTLSPickerView + AdvancedSettingsView restructure + L10n | 8d85f3e | Build + 170 tests PASS |

## Implementation Details

### Task 1: SettingsViewModel @AppStorage Properties

6 new properties added under `// MARK: - Phase 10`:

| Property | Store | Default | NE-visible |
|----------|-------|---------|------------|
| `cdnFrontingEnabled` | .standard | false | No |
| `muxEnabled` | App Group | false | Yes |
| `stunBlockEnabled` | App Group | false | Yes |
| `certPinningEnabled` | .standard | true | No |
| `utlsFingerprint` | App Group | "random" | Yes |
| `macOSDisableEnforceRoutes` | App Group | false | Yes (macOS only) |

Additionally: `static let utlsOptions: [String]` (7 fingerprint values) and `@Published var stunBlockShowConfirm: Bool = false`.

### Task 2: UI Components

**UTLSPickerView:** `Picker` with `.menu` style over 7 uTLS fingerprint options bound to `$viewModel.utlsFingerprint`.

**AntiDPISection:** 4 controls — CDN fronting, Mux, uTLS (via UTLSPickerView), STUN block. STUN toggle uses pending-value pattern: `@State private var pendingStunBlock` set before showing alert, only committed on confirm.

**SecuritySection:** Cert Pinning toggle (all platforms) + Enforce Routes toggle (`#if os(macOS)`). EnforceRoutes toggle is inverted (UI shows "Enable" but property is "Disable"). Footer dynamically switches between `.footer.on` and `.footer.off`.

**AdvancedSettingsView:** Restructured from 4-section to 6-section Form: banner → Anti-DPI → Security → DNS → Rules viewer → Force-update.

### L10n Changes

22 new xcstrings keys added (en + ru translations). 22 L10n accessor static vars added to L10n.swift under `// MARK: Phase 10 / 10-01`.

### REQUIREMENTS.md Scope Amendment

- BIO-01, BIO-02, BIO-03: marked `~~deferred~~ → Out of Scope v0.10` per D-01 in 10-CONTEXT.md
- ONDEMAND-01: marked deferred per D-02 in 10-CONTEXT.md
- BIO-04 (STUN block) and KILL-04 (macOS enforceRoutes): remain in-scope Phase 10

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All UI controls are wired to real `@AppStorage` / `@Published` properties in SettingsViewModel. No hardcoded empty values or placeholder text in rendered UI paths.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. All new surface (5 @AppStorage keys via App Group) was already covered in the plan's threat model (App Group key isolation, no cross-app leakage beyond sibling NE extension).

## TDD Gate Compliance

- RED gate commit: c800127 (`test(10-01): add failing tests...`) — 6 tests failing as expected
- GREEN gate commit: 07c91d9 (`feat(10-01): scope amendment + 6 new @AppStorage props...`) — all 170 tests passing

## Self-Check: PASSED

- AntiDPISection.swift: FOUND
- SecuritySection.swift: FOUND
- UTLSPickerView.swift: FOUND
- AdvancedSettingsView.swift (modified): FOUND
- SettingsViewModel.swift (modified): FOUND
- L10n.swift (modified): FOUND
- Localizable.xcstrings (modified): FOUND
- Commits c800127, 07c91d9, 8d85f3e: all present in git log
- swift build: Build complete, 0 errors
- swift test: 170/170 PASS, 0 failures
