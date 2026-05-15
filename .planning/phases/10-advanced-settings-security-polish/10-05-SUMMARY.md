---
phase: 10
plan: "05"
subsystem: FrontingEngine
tags: [cdn, fronting, anti-dpi, swiftpm-package, actor, dpi-06]
dependency_graph:
  requires: [10-01, 10-04]
  provides: [FrontingEngine package, AppGroupContainer.cdnFailureCacheURL]
  affects: [PacketTunnelKit/AppGroupContainer.swift, Plan-06 ConfigImporter wiring]
tech_stack:
  added:
    - "FrontingEngine SwiftPM package (swift-tools-version 6.0, iOS 18 / macOS 15)"
    - "CDNProviderAdapter protocol (static enum conformance, mirror TransportHandler)"
    - "FrontingFailureCache actor (score+cooldown 6-24h, App Group JSON persistence)"
    - "FrontingFallbackChain actor (sequential cursor, pre-advance anti-reentrancy pattern)"
  patterns:
    - "D-03: FrontingProfile orthogonal to TransportConfig (50+ transports don't duplicate CDN logic)"
    - "D-05: Blacklist checks in adapter.applyFronting (Reality/TUIC/Hy2/Vision)"
    - "D-06: Actor + App Group JSON persistence for failure scoring"
    - "DEC-06d-04: concurrency=1 via actor isolation + pre-advance cursor"
    - "Pre-advance cursor: cursor reserved BEFORE await suspension to prevent actor reentrancy race"
key_files:
  created:
    - BBTB/Packages/FrontingEngine/Package.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingProfile.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CDNProviderAdapter.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CloudflareAdapter.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FastlyAdapter.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CustomCDNAdapter.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingError.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingFailureCache.swift
    - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingFallbackChain.swift
    - BBTB/Packages/FrontingEngine/Tests/FrontingEngineTests/FrontingProfileTests.swift
    - BBTB/Packages/FrontingEngine/Tests/FrontingEngineTests/FrontingConfigApplierTests.swift
    - BBTB/Packages/FrontingEngine/Tests/FrontingEngineTests/FrontingFallbackChainTests.swift
  modified:
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift
decisions:
  - "Pre-advance cursor in FrontingFallbackChain.nextEndpoint to prevent actor reentrancy duplicate returns (Swift Concurrency actors allow reentrancy at await suspension points — cursor must be reserved before await cache.shouldSkip)"
  - "UniformTypeIdentifiers framework added to FrontingEngineTests linkerSettings (Libbox platform_mime_util_apple.o requires UTType symbols when linked directly through PacketTunnelKit)"
metrics:
  duration: "~10 min"
  tasks_completed: 2
  tasks_total: 2
  files_created: 13
  files_modified: 1
  tests_added: 20
  completed_date: "2026-05-15"
---

# Phase 10 Plan 05: FrontingEngine CDN-фронтинг пакет — Summary

**One-liner:** DPI-06 реализован как отдельный SwiftPM пакет FrontingEngine с 3 CDN адаптерами (Cloudflare/Fastly/Custom), JSON overlay applier, actor-based failure cache с cooldown 6-24ч и sequential fallback chain.

## What Was Built

### FrontingEngine SwiftPM Package

Новый пакет `BBTB/Packages/FrontingEngine` (swift-tools-version 6.0, iOS 18 / macOS 15):

**10 source files:**
- `FrontingProfile` — Codable Sendable struct: provider/connectHost/connectPort/sniHost/httpHost/mode. Critical decision D-03: отдельный struct, не часть TransportConfig, чтобы 50+ транспортов не дублировали CDN логику.
- `CDNProviderAdapter` — static protocol (mirror TransportHandler Phase 5). `applyFronting(to:profile:)` инвариант: D-05 blacklist в каждом адаптере.
- `CloudflareAdapter`, `FastlyAdapter`, `CustomCDNAdapter` — три реализации. Одинаковая sing-box transport mapping (WS headers.Host / HTTPUpgrade host / gRPC SNI-only). D-05 blacklist: TUIC/Hysteria2/Reality/Vision → return false.
- `FrontingError` — error enum (malformedJSON/unsupportedTransport/providerBlacklisted/fallbackExhausted/ioError).
- `FrontingConfigApplier` — pure static. `apply(json:profile:adapter:)` batch JSON roundtrip + `apply(outbound:profile:adapter:)` single dict variant.
- `FrontingFailureCache` — actor. Score + cooldown ladder (score 1→6ч, 2-3→12ч, ≥4→24ч). App Group JSON persistence (best-effort atomic write). Injectable clock для testability.
- `FrontingFallbackChain` — actor. Sequential cursor с pre-advance pattern (см. Deviations). `nextEndpoint(networkType:)` → `(FrontingProfile?, exhausted: Bool)`.

**AppGroupContainer.cdnFailureCacheURL** — добавлено в PacketTunnelKit (Library/Caches/cdn/cdn-failure-cache.json).

### Test Coverage: 20 tests, 4 suites

| Suite | Tests | Status |
|-------|-------|--------|
| FrontingProfile — Codable + CaseIterable | 6 | PASS |
| FrontingConfigApplier — transport overlay | 8 | PASS |
| FrontingFailureCache — score + cooldown | 3 | PASS |
| FrontingFallbackChain — sequential cursor + exhaustion | 3 + reset | PASS |
| **Total** | **20** | **ALL PASS** |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Actor reentrancy race in FrontingFallbackChain.nextEndpoint**
- **Found during:** Task 2 test_fallback_chain_sequential_concurrency_1
- **Issue:** Swift actors allow reentrancy at `await` suspension points. When 5 tasks concurrently called `nextEndpoint`, all read `cursor=0` before any advanced it (because `await cache.shouldSkip` created a suspension point before `cursor = index + 1`). Result: `uniqueHosts.count == 2` instead of 5.
- **Fix:** Pre-advance cursor BEFORE the `await` suspension point: `cursor = index + 1` first, then `await cache.shouldSkip`. If profile is blocked, continue to next pre-advance. This ensures each concurrent caller claims a unique cursor slot atomically.
- **Files modified:** `FrontingFallbackChain.swift`
- **Commit:** included in 6c0ac46

**2. [Rule 3 - Blocking] UniformTypeIdentifiers missing from linkerSettings**
- **Found during:** Task 1 test run
- **Issue:** FrontingEngine links PacketTunnelKit directly (not via ConfigParser chain), pulling in Libbox xcframework → `platform_mime_util_apple.o` which references `UTType` / `UTTagClassFilenameExtension` / `UTTagClassMIMEType` symbols from `UniformTypeIdentifiers.framework`. This framework was absent in linkerSettings.
- **Fix:** Added `.linkedFramework("UniformTypeIdentifiers")` to FrontingEngineTests linkerSettings.
- **Files modified:** `Package.swift`
- **Commit:** included in a25ab61

**3. [Rule 3 - Blocking] libbox.xcframework missing in worktree Vendored/
- **Found during:** Task 1 first build attempt
- **Issue:** Worktree `BBTB/Vendored/` directory contained only README.md; libbox.xcframework was gitignored and not present.
- **Fix:** Created symlink `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`. Symlink not committed (xcframework is gitignored — correct).
- **Impact:** Build and tests now work in worktree context.

## Stub Tracking

No stubs. Package is not wired into production yet (by design — Plan 06 wiring). All public APIs are fully implemented.

## Known Open Follow-ups (Plan 06 Wave 3)

1. **Tuist Project.swift wiring** — добавить `.package(path: "Packages/FrontingEngine")` к manifest. Currently FrontingEngine is SwiftPM-only, not in Xcode workspace.
2. **ConfigImporter integration** — `FrontingConfigApplier.apply(json:profile:adapter:)` вызов в ConfigImporter после `expandConfigForTunnel`. Profile lookup из subscription JSON.
3. **Admin handoff documentation** — `wiki/cdn-fronting-server-handoff.md` (FrontingProfile JSON schema для admin subscription side).
4. **FrontingFallbackChain provisioning** — admin subscription JSON → `[FrontingProfile]` parsing + FrontingFallbackChain init in ConfigImporter.

## Verification Results

```
swift build --package-path Packages/FrontingEngine → Build complete! ✓
swift test  --package-path Packages/FrontingEngine → 20 tests PASS ✓
swift build --package-path Packages/PacketTunnelKit → Build complete! ✓
```

## Threat Model Coverage

| Threat | Status |
|--------|--------|
| T-10-W5-03 DoS: CDN blackholes → FrontingFallbackChain D-06 | Implemented + Test 10 |
| T-10-W5-05 DoS(self): CDN overlay on Reality → D-05 blacklist | Implemented + Tests 4-7 |
| T-10-W5-06 Misuse: infinite cooldown → cap 24ч + score 10 | Implemented + Test 9 |
| T-10-W5-08 Race: concurrent nextEndpoint → actor isolation + pre-advance | Implemented + Test 11 |

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | a25ab61 | feat(10-05): FrontingEngine scaffolding + CDN adapters + AppGroupContainer.cdnFailureCacheURL + 6 tests |
| Task 2 | 6c0ac46 | feat(10-05): FrontingConfigApplier + FrontingFailureCache + FrontingFallbackChain + 14 tests |

## Self-Check: PASSED
