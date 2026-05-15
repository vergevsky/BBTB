---
phase: 09-deep-links
plan: "03"
subsystem: ui
tags:
  - deep-links
  - tuist
  - entitlements
  - cold-start-defer
  - swiftui-modifiers
  - universal-links
  - custom-url-scheme

# Dependency graph
requires:
  - phase: 09-deep-links
    provides: DeepLinkRouter actor + ImportHandler + DeepLinkError + L10n keys (Waves 1+2)
provides:
  - Tuist Project.swift wired with DeepLinks local package (iOS + macOS targets)
  - Associated Domains entitlement (applinks:import.bbtb.app) in both .entitlements files
  - CFBundleURLTypes bbtb:// custom scheme in both Info.plist files
  - BBTB_iOSApp + BBTB_macOSApp: DeepLinkRouter init + ImportHandler registration (DEC-06d-01 defer pattern)
  - SwiftUI .onOpenURL + .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) in both root views
  - D-09 cold-start buffer (pendingDeepLink @State + routeOrBuffer helper + .task flush)
  - MainScreenViewModel.handleDeepLink(_:router:) public method
  - public private(set) var initialManagersApplied exposed for routeOrBuffer guard
  - AppFeatures/Package.swift DeepLinks dependency wired
  - 2 integration tests: error path + success path for handleDeepLink
affects:
  - 09-04-PLAN (Wave 4 — AASA server hosting + Apple Portal capability registration)
  - 12-pre-release (TestFlight — Associated Domains requires provisioning profile with capability)

# Tech tracking
tech-stack:
  added:
    - DeepLinks local SwiftPM package wired into AppFeatures (test target) and Tuist app targets
  patterns:
    - D-09 cold-start buffer: pendingDeepLink @State + routeOrBuffer() + .task flush (mirror iOS/macOS)
    - DEC-06d-01: cheap actor init in App.init, registration in Task.detached(priority: .utility)
    - macOS Pitfall #1: .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) required for Universal Links (NOT .onOpenURL)
    - Two-phase init: DeepLinkRouter init cheap + register after App.init returns

key-files:
  created:
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MainScreenViewModelDeepLinkTests.swift
  modified:
    - BBTB/Project.swift
    - BBTB/App/iOSApp/BBTB-iOS.entitlements
    - BBTB/App/macOSApp/BBTB-macOS.entitlements
    - BBTB/App/iOSApp/Info.plist
    - BBTB/App/macOSApp/Info.plist
    - BBTB/App/iOSApp/BBTB_iOSApp.swift
    - BBTB/App/macOSApp/BBTB_macOSApp.swift
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
    - BBTB/Packages/AppFeatures/Package.swift

key-decisions:
  - "D-09 cold-start buffer: initialManagersApplied guard before routing; pendingDeepLink flushed in .task after VM ready"
  - "macOS requires .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) for Universal Links — .onOpenURL alone is insufficient (macOS Pitfall #1)"
  - "DEC-06d-01 pattern applied: DeepLinkRouter.init() cheap in App.init; ImportHandler registration deferred to Task.detached(priority: .utility)"
  - "handleDeepLink fires Task { @MainActor } internally; importInProgress cleared via defer; lastError set on throw"
  - "public private(set) var initialManagersApplied — T-09-08 accepted threat; needed by routeOrBuffer in root view"

patterns-established:
  - "D-09 cold-start buffer pattern: all future URL-scheme features should use routeOrBuffer() guard"
  - "macOS Universal Links: always add .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) alongside .onOpenURL"
  - "DeepLink error path: router throws -> lastError populated, importInProgress cleared by defer"

requirements-completed:
  - DEEP-01
  - DEEP-02
  - DEEP-05

# Metrics
duration: ~90min
completed: 2026-05-15
---

# Phase 9 Plan 03: Wave 3 — App Wiring + VM Integration Summary

**bbtb:// custom URL scheme + Universal Links fully wired end-to-end: Tuist manifest, entitlements, Info.plist, root view URL handlers, cold-start D-09 buffer, and MainScreenViewModel.handleDeepLink with integration tests**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-05-15T08:28:10Z
- **Completed:** 2026-05-15
- **Tasks:** 3/3
- **Files modified:** 9 (1 created)

## Accomplishments

- Wired DeepLinks SwiftPM package into Tuist Project.swift (iOS + macOS app targets + AppFeatures test target) and AppFeatures/Package.swift
- Added Associated Domains entitlement (`applinks:import.bbtb.app`) and CFBundleURLTypes (`bbtb://`) to both platforms' entitlements and Info.plist files
- Implemented full root view URL delivery chain on both iOS and macOS: `.onOpenURL` (custom scheme) + `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` (Universal Links, required on macOS per Pitfall #1), with D-09 cold-start pending buffer pattern (`pendingDeepLink @State` + `routeOrBuffer()` + flush in `.task`)
- Added `MainScreenViewModel.handleDeepLink(_:router:)` public method with `importInProgress` spinner + `lastError` error path + post-success `refresh()`, and exposed `initialManagersApplied` as `public private(set)` for routeOrBuffer guard
- 2 integration tests covering error path (AlwaysThrowsHandler → lastError set, importInProgress cleared) and success path (NoOpHandler → no error, importInProgress cleared); predicate-based polling, no arbitrary sleep

## Task Commits

1. **Task 3.1: Tuist + Entitlements + Info.plist** - `02e6d2a` (feat)
2. **Task 3.2: iOS + macOS App URL delivery chain** - `8412e4c` (feat)
3. **Task 3.3: AppFeatures Package.swift + MainScreenViewModel + integration test** - `e0d8283` (feat)

## Files Created/Modified

- `BBTB/Project.swift` — added `.package(path: .relativeToManifest("Packages/DeepLinks"))` to localPackages + `DeepLinks` dep in both iOS and macOS app targets
- `BBTB/App/iOSApp/BBTB-iOS.entitlements` — added `com.apple.developer.associated-domains: ["applinks:import.bbtb.app"]`
- `BBTB/App/macOSApp/BBTB-macOS.entitlements` — same Associated Domains addition (compatible with existing sandbox entitlement)
- `BBTB/App/iOSApp/Info.plist` — added `CFBundleURLTypes` with `bbtb` scheme, name `app.bbtb.client.ios.url`
- `BBTB/App/macOSApp/Info.plist` — same CFBundleURLTypes with name `app.bbtb.client.macos.url`
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` — added `import DeepLinks`, `private let deepLinkRouter: DeepLinkRouter`, init wiring, `BBTBRootView` updated with router + `pendingDeepLink` + `.onOpenURL` + `.onContinueUserActivity` + `.task` flush + `routeOrBuffer()` helper
- `BBTB/App/macOSApp/BBTB_macOSApp.swift` — mirror iOS pattern; `BBTBMacOSRootView` updated identically; macOS Pitfall #1 comment documenting why `.onContinueUserActivity` is critical
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` — `import DeepLinks`, `initialManagersApplied` visibility `public private(set)`, `handleDeepLink(_:router:)` public method added
- `BBTB/Packages/AppFeatures/Package.swift` — `.package(path: "../DeepLinks")` dependency + `"DeepLinks"` in MainScreenFeature target deps + `"DeepLinks"` in MainScreenFeatureTests target deps
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MainScreenViewModelDeepLinkTests.swift` — **created**: 2 integration tests with MockImporter/MockTunnel/makeContainer/freshDefaults pattern mirroring HandleForegroundReentryTests.swift

## Decisions Made

- **D-09 cold-start buffer**: `initialManagersApplied` checked in `routeOrBuffer()` before calling `handleDeepLink`; URL buffered in `@State private var pendingDeepLink: URL?` and flushed in `.task` after both VM wiring calls complete. Mirrors the macOS pattern already established in the summary context.
- **macOS .onContinueUserActivity required**: `.onOpenURL` does NOT deliver Universal Links on macOS — they open in Safari without this modifier. Both modifiers applied on both platforms per 09-RESEARCH Pitfall #1.
- **DEC-06d-01 applied**: `DeepLinkRouter()` init is cheap (actor init); `ImportHandler` registration deferred to `Task.detached(priority: .utility)` — same pattern as `RulesEngineCoordinator.bootstrap()`.
- **handleDeepLink internal Task**: fires `Task { @MainActor }` internally so callers (SwiftUI event handlers) need not be async. `defer { importInProgress = false }` guarantees spinner always clears.
- **T-09-08 accepted threat**: `initialManagersApplied` exposed `public private(set)` — read-only from outside, write protected. Root view observes this to guard cold-start buffering.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing libbox.xcframework symlink in worktree**
- **Found during:** Task 3.1 (tuist generate verification)
- **Issue:** The git worktree's `BBTB/Vendored/` directory only contained `README.md`; the binary xcframework was not present. `tuist generate` failed: `local binary target 'Libbox' does not contain a binary artifact`.
- **Fix:** Created symlink `ln -s /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework /Users/vergevsky/ClaudeProjects/VPN/.claude/worktrees/agent-ac9bdf7de98187fa3/BBTB/Vendored/libbox.xcframework`
- **Files modified:** `BBTB/Vendored/libbox.xcframework` (new symlink in worktree)
- **Verification:** `tuist generate` succeeded after symlink creation
- **Committed in:** `02e6d2a` (Task 3.1 commit)

**2. [Rule 3 - Blocking] Worktree absolute-path drift (#3099)**
- **Found during:** Task 3.1 (post-edit verification grep)
- **Issue:** Initial Read and Edit calls used main repo paths (`/Users/vergevsky/ClaudeProjects/VPN/BBTB/...`) instead of worktree paths (`/Users/vergevsky/ClaudeProjects/VPN/.claude/worktrees/agent-ac9bdf7de98187fa3/BBTB/...`). Edits landed in main repo, not worktree.
- **Fix:** Detected via `grep -c "Packages/DeepLinks"` returning 0 in worktree. Reverted main repo files with `git checkout -- <files>`. Re-read all files from worktree paths and re-applied all edits.
- **Files modified:** All Task 3.1 files (re-applied to correct worktree paths)
- **Verification:** `grep "Packages/DeepLinks" BBTB/Project.swift` returned match in worktree
- **Committed in:** `02e6d2a` (Task 3.1 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking Rule 3)
**Impact on plan:** Both fixes were infrastructure/tooling issues unrelated to feature scope. No behavior changes to plan.

## Issues Encountered

- Task 3.2 (App files) and Task 3.3 (ViewModel method) have a build dependency: the App files reference `viewModel.handleDeepLink(url, router:)` which didn't exist until Task 3.3. Both tasks were implemented before running xcodebuild verification, then committed separately per plan. This is expected per the plan's task ordering.

## User Setup Required

**Wave 4 preconditions confirmed — the following remain for Wave 4:**

1. **Apple Developer Portal** — Add "Associated Domains" capability to both `app.bbtb.client.ios` and `app.bbtb.client.macos` App IDs. Required before provisioning profiles with the entitlement can be generated. (See MEMORY: `project_phase9_deep_links_todo.md`)
2. **AASA server** — Host `https://import.bbtb.app/.well-known/apple-app-site-association` with correct JSON (applinks section with `app.bbtb.client.ios` team+bundle ID). Required before Universal Links will work on device.
3. **Provisioning profiles** — Regenerate iOS Debug + Distribution profiles for `app.bbtb.client.ios` after capability is added in Portal.

**Code-side (this Wave 3) is complete:**
- entitlements: Associated Domains present in both platforms
- Info.plist: CFBundleURLTypes bbtb:// registered in both platforms
- App code: .onOpenURL + .onContinueUserActivity + D-09 cold-start buffer wired
- VM: handleDeepLink method implemented and tested

## Verification Results

- `swift test --package-path Packages/DeepLinks`: **17/17 PASS** (no regressions)
- `swift test --package-path Packages/AppFeatures`: **164/164 PASS** (162 existing + 2 new integration tests)
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build`: **BUILD SUCCEEDED**
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination 'generic/platform=macOS' build`: **BUILD SUCCEEDED** (ad-hoc signing; codesign warning expected in CI without Distribution cert)

## Next Phase Readiness

- Wave 3 complete: code-side deep link infrastructure is fully wired on both platforms
- Wave 4 (09-04-PLAN) can proceed: AASA server setup + Apple Portal capability registration are the remaining steps before Universal Links work on device
- Custom URL scheme (`bbtb://`) is already functional without Portal changes (scheme delivery via `.onOpenURL` works without Associated Domains)
- Associated Domains entitlement will cause build warning until Portal capability is added — not a blocker for development builds

---
*Phase: 09-deep-links*
*Completed: 2026-05-15*
