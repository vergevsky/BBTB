---
phase: 03-server-management
verified: 2026-05-12T13:03:24Z
status: gaps_found
score: 3/4 roadmap success criteria VERIFIED; 4 requirements partially satisfied; 5 critical bugs block production readiness
overrides_applied: 0
gaps:
  - truth: "Auto-select correctly derives isUnreachable and score from probe results"
    status: failed
    reason: "CR-05: Int(agg.lossRate * 3) truncates IEEE-754 — e.g., 1/3 × 3 = 0.9999... → Int(0) = 0, so 1 failed probe is persisted as 0; cancellation skew also corrupts denominator. isUnreachable and score used for auto-select will be wrong."
    artifacts:
      - path: "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:297"
        issue: "row.failedProbeCount = Int(agg.lossRate * 3) — floating-point truncation + cancellation skew"
    missing:
      - "Expose failures: Int directly on ProbeAggregate OR use Int((agg.lossRate * 3).rounded()); prefer direct failure count"

  - truth: "provisionTunnelProfile(for:) connects to the server the user explicitly selected"
    status: failed
    reason: "CR-01: when the user has manually selected server X and Keychain decode fails for X, code silently falls back to a full-pool urltest config connecting to a different server. No error, no UI signal. Violates D-09 explicit-selection contract."
    artifacts:
      - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:458-464"
        issue: "parsedList.isEmpty && targets.count == 1 → fallback to full pool; user connected to a server they did not choose"
    missing:
      - "When selectedID != nil and that server's Keychain decode fails, throw ImporterError.configBuildFailed (or a new .selectionMissing(id)); only fall back to full pool when selectedID == nil"

  - truth: "Deleting a subscription removes it exactly once without SwiftData crash"
    status: failed
    reason: "CR-02: confirmDeleteSubscription deletes subscription via context.delete(row) in the if-branch, then falls through to context.delete(subscription) in the else-branch only when row is not found. The else-branch deletes the caller's passed-in subscription object — which may be from a different ModelContext than the fresh context created at line 234. Deleting a model object from a context it does not belong to is undefined behaviour in SwiftData and can crash or silently corrupt."
    artifacts:
      - path: "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:248-257"
        issue: "else branch calls context.delete(subscription) where subscription came from a different ModelContext than the local fresh context"
    missing:
      - "Replace else branch with an early return + log (subscription already gone); never delete a model object through a context it was not fetched from"

  - truth: "Subscription URL fetch blocks internal/localhost/private-range SSRF"
    status: failed
    reason: "CR-03: SubscriptionURLFetcher.fetch enforces HTTPS scheme only. No hostname validation. https://localhost/admin, https://169.254.169.254/, https://10.0.0.1/ are all accepted and fetched. T-03-06 claims SSRF is mitigated but the mitigation is not present in code."
    artifacts:
      - path: "BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:76-93"
        issue: "Only checks url.scheme == https; no hostname blocklist for localhost, 127.x, 10.x, 169.254.x, 192.168.x, ::1, etc."
    missing:
      - "Add hostname blocklist covering localhost, loopback (127./::1), link-local (169.254.), RFC-1918 private ranges (10./172.16-31./192.168.); add unit test verifying rejection"

  - truth: "isActive flag accurately reflects the active server without ambiguity or UI flicker"
    status: failed
    reason: "CR-04: after subscription merge, code sets savedConfigs.first.isActive = true with no sort order on FetchDescriptor (non-deterministic) and without clearing isActive on previously-active rows. Multiple rows can have isActive == true simultaneously; loadActiveServer returns unspecified row; server-line text can show different server names on each import."
    artifacts:
      - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:213-217"
        issue: "savedConfigs.first without sort + no prior isActive = false reset → non-deterministic multi-row isActive"
    missing:
      - "Before setting first.isActive = true, iterate savedConfigs and set isActive = false on all; sort savedConfigs deterministically (e.g. by createdAt) before picking first"
      - "Or: remove isActive writes from the merge path entirely (Phase 1 legacy); rely on selectedServerID from MainScreenViewModel instead"
---

# Phase 3: Server Management — Verification Report

**Phase Goal:** Управление серверами — auto-select по latency, список серверов с pull-to-refresh, поддержка нескольких подписок. Версия — v0.3.
**Verified:** 2026-05-12T13:03:24Z
**Status:** gaps_found — 5 critical bugs from code review confirmed in codebase; goal partially achieved; gap closure required before production
**Re-verification:** No — initial verification

---

## Goal Achievement

Phase 3 delivers all planned structures: Subscription @Model, ServerListFeature UI (9 files), ServerProbeService, ServerScore, pull-to-refresh, cascade delete, foreground refresh, and pre-connect auto-select. The code compiles, 152 unit tests pass. However, the code review (commit `8d32a5c`) found 5 correctness defects that were verified against the codebase. Three of them directly affect the user-visible goals of this phase (auto-select correctness, server selection fidelity, security of subscription import). None of the 5 were fixed after the review was committed.

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | Server list updates on pull-to-refresh, latency recalculated | VERIFIED | `ServerListSheet.swift:111-112` — `.refreshable { await viewModel.pullToRefresh() }`; `pullToRefresh` 2-phase: fetch all subscriptions → ping all supported. Latency written to `ServerConfig.lastLatencyMs` per `pingAllServers`. |
| SC-2 | Auto-select switches to server with lowest latency + minimum packet loss | PARTIAL | Auto-select formula `score = avgLatencyMs × (1 + lossRate)` is correct in `ProbeResult.score`. `ServerScore.autoSelect` is correct. But `failedProbeCount` persisted via `Int(agg.lossRate * 3)` (CR-05) can truncate, corrupting `isUnreachable` and therefore `score`. The goal is structurally present but numerically unreliable. |
| SC-3 | Connection timer counts from tunnel establishment | VERIFIED | `ConnectionTimer.swift` exists from Phase 1/2 (carry-forward); `MainScreenViewModel` drives timer state. Not a Phase 3 deliverable but confirmed working. |
| SC-4 | Multiple subscriptions show as sections in list | VERIFIED | `ServerListViewModel.groupSections` groups by Subscription, orphan servers in dedicated section; `ServerListSheet` renders `ForEach(viewModel.sections)` with `SubscriptionHeader` headers. 5 SectionGroupingTests pass. |

**Score:** 3 of 4 roadmap truths fully VERIFIED; 1 PARTIAL (SC-2 due to CR-05).

---

### Additional Phase Goal Truths (from phase goal description)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| A | Server list sheet: flag, name, latency badge, unreachable indicator, "не поддерживается" stub | VERIFIED | `ServerRow.swift`, `LatencyBadge.swift`, `AutoCell.swift` — all implemented; `countryFlag` regex-validated; `isUnreachable` computed; `isSupported=false` shows greyed-out stub. |
| B | Auto-select: score = latencyMs × (1 + lossRate), 3 probes, runs before every connect | PARTIAL | Formula correct in `ProbeAggregate.score`; 3 sequential probes in `probeServerThreeTimes`; `performPreConnectAutoSelect` called from `performToggleImpl`. CR-05 corrupts `failedProbeCount` → `isUnreachable` → score downstream. |
| C | Multi-subscription: @Model Subscription, cascade delete, sections in list, add via +, delete via swipe | VERIFIED | `Subscription.swift`, `SubscriptionMergeService.swift`, `ServerListViewModel.confirmDeleteSubscription`, `SubscriptionHeader` swipe-delete, `ServerListSheet` sections. 10 cascade-delete + merge tests green. CR-02 (cross-context delete in else-branch) is a latent crash risk but the primary path (row re-fetched) works. |
| D | Pull-to-refresh: fetch subscriptions → merge → ping all, sequential; also runs on app foreground | VERIFIED | `pullToRefresh` (2-phase sequential D-13), `silentForegroundRefresh` (scenePhase .active via `MainScreenView.onChange`). Both implemented and tested. |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift` | @Model Subscription entity | VERIFIED | 35 lines; id (unique), url, name, lastFetched |
| `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` | NWConnection TCP probe actor | VERIFIED | 184 lines; probeOnce + probeAll AsyncStream |
| `BBTB/Packages/VPNCore/Sources/VPNCore/ServerScore.swift` | Pure autoSelect function | VERIFIED | 23 lines; filters nil-score, returns min |
| `BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift` | ProbeResult + ProbeAggregate | VERIFIED | score formula correct; CR-05 is in callsite not here |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift` | D-14 identity-based merge | VERIFIED | identity = host:port:protocolID:sni; preserves latency |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` | HTTPS-only URL fetch | STUB | Only checks scheme == https; no hostname blocklist (CR-03) |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift` | DI protocol | VERIFIED | protocol with persistKeychainSecret + buildServerConfig + provisionTunnelProfile |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` | Sheet with refreshable | VERIFIED | .presentationDetents([.large]) + .refreshable wired |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` | pullToRefresh, deleteServer, confirmDeleteSubscription | PARTIAL | pullToRefresh working; confirmDeleteSubscription has cross-context else-branch (CR-02) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` | provisionTunnelProfile(for:) | PARTIAL | Implemented; CR-01 silent substitution + CR-04 non-deterministic isActive |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | auto-select + selectedServerID persist | VERIFIED | performPreConnectAutoSelect + UserDefaults didSet mirror working |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MainScreenView` | `ServerListSheet` | `.sheet(isPresented: $vm.isPresentingServerList)` | WIRED | Verified in `MainScreenView.swift:71` |
| `ServerLineView` (tap) | `MainScreenViewModel.presentServerList()` | onTap closure | WIRED | ServerLineView tap-enabled with chevron |
| `ServerListSheet` | `ServerListViewModel.pullToRefresh()` | `.refreshable` | WIRED | `ServerListSheet.swift:111-112` |
| `MainScreenView` | `ServerListViewModel.silentForegroundRefresh()` | `.onChange(of: scenePhase)` | WIRED | `MainScreenView.swift:71-74` |
| `ServerListViewModel` | `ServerProbeService.probeAll` | `for await (id, agg) in probeService.probeAll(payload)` | WIRED | `ServerListViewModel.swift:285-300` |
| `ServerListViewModel.pingAllServers` | `ServerConfig.failedProbeCount` | `row.failedProbeCount = Int(agg.lossRate * 3)` | WIRED but BROKEN | CR-05: truncation corrupts count |
| `MainScreenViewModel.performToggleImpl` | `provisionTunnelProfile(for:)` | Direct call via ConfigImporting protocol | WIRED | auto/manual paths both present |
| `provisionTunnelProfile(for:)` | User-selected server X | Keychain decode path | BROKEN | CR-01: silent fallback to different server on decode failure |
| `SubscriptionURLFetcher.fetch` | Remote subscription URL | URLSession data(for:) | WIRED but INSECURE | CR-03: no private-range hostname validation |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| `ServerListSheet` → `ServerRow` | `section.servers` | `ServerListViewModel.sections` ← `groupSections(subs, servers)` ← SwiftData fetch | Yes — real SwiftData rows | FLOWING |
| `LatencyBadge` | `pingStates[id]` | `pingAllServers()` → `probeService.probeAll` → `ProbeAggregate` | Yes — real NWConnection probes | FLOWING (but CR-05 corrupts stored count) |
| `AutoCell` | `selectedServerID == nil` | `MainScreenViewModel.selectedServerID` ← UserDefaults | Yes | FLOWING |
| `provisionTunnelProfile` | Connected server | `ServerConfig` from SwiftData + Keychain | Yes — but CR-01 can substitute wrong server silently | HOLLOW_PROP (conditional) |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| AppFeatures 37 tests | `swift test --package-path BBTB/Packages/AppFeatures` | 37/37 PASS | PASS |
| VPNCore 32 tests | `swift test --package-path BBTB/Packages/VPNCore` | 32/32 PASS (1 skip pre-existing) | PASS |
| ConfigParser 83 tests | `swift test --package-path BBTB/Packages/ConfigParser` | 83/83 PASS | PASS |
| Total: 152 tests | all packages | 152 PASS, 1 skip | PASS |
| CR-05 Int truncation | grep `Int(agg.lossRate * 3)` ServerListViewModel.swift:297 | Found exactly | FAIL |
| CR-01 silent substitution | grep `parsedList.isEmpty && targets.count == 1` ConfigImporter.swift:458 | Found — fallback to full pool | FAIL |
| CR-03 no hostname validation | grep `localhost\|blockedPrefix` SubscriptionURLFetcher.swift:76-93 | Not found — only scheme check | FAIL |
| CR-04 non-deterministic isActive | grep `savedConfigs.first` + no prior isActive=false loop | ConfigImporter.swift:214 confirmed | FAIL |
| CR-02 cross-context delete | grep `context.delete(subscription)` else-branch:256 | Found in `confirmDeleteSubscription` | FAIL |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SRV-01 | Plans 02, 03, 05 | Auto-select по пингу + потерям | PARTIAL | Score formula correct; CR-05 corrupts failedProbeCount used in isUnreachable + score |
| SRV-02 | Plans 01, 04 | Multi-subscription, секции в списке | VERIFIED | Subscription @Model; merge-by-identity; SubscriptionHeader sections; cascade delete |
| SRV-03 | Plans 03, 04 | Pull-to-refresh перепинговывает всё | VERIFIED | 2-phase pullToRefresh: fetch → merge → ping; also foreground refresh |
| UX-04 | Plans 03, 04 | Server list screen с флагами, latency, Авто | VERIFIED | ServerListSheet + ServerRow + LatencyBadge + AutoCell; 22 L10n keys |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `ServerListViewModel.swift` | 297 | `Int(agg.lossRate * 3)` — IEEE-754 truncation | BLOCKER | `failedProbeCount` wrong → `isUnreachable` wrong → auto-select selects wrong server |
| `ConfigImporter.swift` | 458-464 | Silent server substitution on Keychain decode failure | BLOCKER | User thinks they connect to server X; actually connects to urltest winner from full pool |
| `SubscriptionURLFetcher.swift` | 76-93 | No hostname blocklist — SSRF to private ranges | BLOCKER | User paste of `https://localhost/` or `https://192.168.x.x/` hits local network services |
| `ConfigImporter.swift` | 213-217 | `savedConfigs.first.isActive = true` — non-deterministic, no prior clear | BLOCKER | UI footer shows different server names non-deterministically; multiple rows have isActive=true |
| `ServerListViewModel.swift` | 248-257 | `else { context.delete(subscription) }` — cross-context delete | BLOCKER | Deleting model object through context it was not fetched from — undefined behaviour, potential crash |

---

### Human Verification Required

None identified — all gaps are programmatically verifiable.

---

## Gaps Summary

The code review (committed as `8d32a5c` after Plan 05 completion) identified 5 correctness defects. All 5 were verified in the final codebase. None were addressed after the review was written.

**Root cause grouping:**

**Group A — Probe metric corruption (CR-05):** The integer truncation `Int(agg.lossRate * 3)` is a single-line arithmetic bug that corrupts `failedProbeCount` stored in SwiftData, which flows into `isUnreachable` and `ProbeAggregate.score`. This breaks the core SC-2 goal of auto-select correctness.

**Group B — Server selection integrity (CR-01, CR-04):** Two separate bugs undermine the user's ability to connect to the server they chose. CR-01 silently connects to a different server when Keychain decode fails. CR-04 sets `isActive` non-deterministically on import, causing the UI to display inconsistent server state.

**Group C — Security and crash risk (CR-02, CR-03):** CR-03 is a SSRF vulnerability that allows subscription URLs pointing at localhost or private IP ranges to be fetched — the threat model explicitly listed T-03-06 as "mitigated" but the mitigation is absent. CR-02 is a SwiftData cross-context crash risk in the cascade-delete path.

**Recommendation:** Create a gap-closure plan targeting all 5 items before marking Phase 3 COMPLETE. The fixes are surgical (single-function scope each) and can be addressed in one plan iteration.

---

_Verified: 2026-05-12T13:03:24Z_
_Verifier: Claude (gsd-verifier)_
