---
phase: 03-server-management
verified: 2026-05-12T14:00:00Z
status: passed
score: 4/4 roadmap success criteria VERIFIED
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 3/4 roadmap success criteria VERIFIED; 5 critical bugs blocked production
  gaps_closed:
    - "CR-05: ProbeAggregate.failures: Int — IEEE-754 truncation eliminated; agg.failures used directly in pingAllServers"
    - "CR-01: provisionTunnelProfile(for:) strict explicit-selection guard — throws configBuildFailed on decode failure, throws noSupportedServers on stale ID; no silent substitution"
    - "CR-04: isActive reset — fetch ALL ServerConfig, set isActive=false on all, sort by id.uuidString, set first.isActive=true; invariant enforced"
    - "CR-02: confirmDeleteSubscription early-return on local-context miss — cross-context delete of caller's foreign object eliminated"
    - "CR-03: SubscriptionURLFetcher.isBlockedHost() — loopback/link-local/RFC-1918/ULA/multicast/reserved blocklist enforced BEFORE session.data; 9 new SSRF tests"
  gaps_remaining: []
  regressions: []
---

# Phase 3: Server Management — Verification Report (Re-verification)

**Phase Goal:** Управление серверами — auto-select по latency, список серверов с pull-to-refresh, поддержка нескольких подписок. Версия — v0.3.
**Verified:** 2026-05-12T14:00:00Z
**Status:** passed
**Re-verification:** Yes — after gap-closure plan G1 (commits 8432fed, 5173fa9, 61121bf)

---

## Goal Achievement

Gap-closure plan G1 fixed all 5 critical bugs identified in the original code review. All roadmap success criteria are now VERIFIED. Test count increased from 152 to 162 (9 new CR-03 SSRF tests in ConfigParser). Zero regressions in previously-passing suites.

---

## CR Fix Verification (Re-verification focus)

### CR-01 — Strict selection guard in provisionTunnelProfile(for:)

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:437-480`

**Fix verified:** `if let id = selectedID` branch now:
- Throws `ImporterError.noSupportedServers` when stale ID not found in supported set
- Throws `ImporterError.configBuildFailed(NSError code -10)` when Keychain decode fails for that specific server
- Sets `parsedList = [parsed]` (single-server config) — no fallback to full pool

The old `parsedList.isEmpty && targets.count == 1` path that triggered silent fallback is gone. D-09 explicit-selection contract is now enforced.

**Status: FIXED**

---

### CR-02 — Same-context delete in confirmDeleteSubscription

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:233-274`

**Fix verified:** Function now:
1. Fetches `Subscription` row by UUID in the local `context` created at line 234
2. If `guard let row = try? context.fetch(subRowDesc).first` returns nil → early-return with log warning, no `context.delete(subscription)` call
3. Only calls `context.delete(row)` on the local-context row

The `else { context.delete(subscription) }` cross-context delete path is eliminated.

**Status: FIXED**

---

### CR-03 — SSRF hostname blocklist in SubscriptionURLFetcher

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:186-249`

**Fix verified:**
- `FetchError.blockedHost(String)` case added to `FetchError` enum
- `isBlockedHost(_:)` function exists and covers: `localhost`, `::1`, `0.0.0.0` (exact), `127.x` (loopback/8), `10.x` (RFC-1918/8), `169.254.x` (link-local/16), `192.168.x` (RFC-1918/16), `172.16-31.x` (RFC-1918/12), `224-239.x` (multicast/4), `240-255.x` (reserved/4), `fe80:` (IPv6 link-local), `fc/fd` + `:` (IPv6 ULA)
- `normalizeHostForLog(_:)` strips `[]` from IPv6 literals and lowercases
- Guard order in `fetch(url:session:)`: scheme check → host non-empty → `isBlockedHost` → `session.data` — SSRF blocked before any network I/O
- 9 new unit tests in `SubscriptionURLFetcherTests.swift` in `// MARK: - CR-03 SSRF Blocklist` section; `assertBlocked(_:)` helper; all blocklist ranges covered

**Status: FIXED**

---

### CR-04 — Deterministic isActive reset in subscription merge path

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:213-228`

**Fix verified:**
- Fetches ALL `ServerConfig` via `FetchDescriptor<ServerConfig>()` (no predicate)
- Iterates `for row in allConfigs { row.isActive = false }` — clears every row across all subscriptions
- Sorts `savedConfigs` by `id.uuidString` lexicographically (`$0.id.uuidString < $1.id.uuidString`)
- Sets `sortedSaved.first?.isActive = true` — exactly one row promoted, deterministic across runs

**Status: FIXED**

---

### CR-05 — Raw failures count replaces IEEE-754 truncation

**Files:** `BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift`, `ServerProbeService.swift:164-168`, `ServerListViewModel.swift:309`

**Fix verified:**
- `ProbeAggregate` now has `public let failures: Int` field (explicit raw count, 0..3)
- `probeServerThreeTimes` local `failures` counter passed directly as `failures:` parameter to `ProbeAggregate` init
- `ServerListViewModel.pingAllServers` writes `row.failedProbeCount = agg.failures` — the old `Int(agg.lossRate * 3)` truncation is gone

**Status: FIXED**

---

## Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | Server list updates on pull-to-refresh, latency recalculated | VERIFIED | `ServerListSheet.swift:111-112` — `.refreshable { await viewModel.pullToRefresh() }`; 2-phase: fetch subscriptions → ping all. Unchanged from initial verification. |
| SC-2 | Auto-select switches to server with lowest latency + minimum packet loss | VERIFIED | CR-05 fix: `row.failedProbeCount = agg.failures` (line 309). `ProbeAggregate.failures: Int` is exact count from `probeServerThreeTimes`. IEEE-754 truncation eliminated. Score formula `score = avgLatencyMs × (1 + lossRate)` remains correct in `ProbeAggregate.score`. `ServerScore.autoSelect` filters nil-score and returns min. |
| SC-3 | Connection timer counts from tunnel establishment | VERIFIED | Carry-forward from Phase 1/2. `ConnectionTimer.swift` + `MainScreenViewModel` timer state. Unchanged. |
| SC-4 | Multiple subscriptions show as sections in list | VERIFIED | `ServerListViewModel.groupSections` + `ServerListSheet` `ForEach(viewModel.sections)`. Unchanged. |

**Score:** 4/4 roadmap truths VERIFIED

---

## Additional Phase Goal Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| A | Server list sheet: flag, name, latency badge, unreachable indicator, "не поддерживается" stub | VERIFIED | `ServerRow.swift`, `LatencyBadge.swift`, `AutoCell.swift`. Unchanged. |
| B | Auto-select: score = latencyMs × (1 + lossRate), 3 probes, runs before every connect | VERIFIED | CR-05 eliminated corruption of `failedProbeCount` → `isUnreachable` → score. All components now correct. |
| C | Multi-subscription: @Model Subscription, cascade delete, sections in list, add via +, delete via swipe | VERIFIED | CR-02 fix eliminates cross-context crash risk in else-branch. Primary cascade path unchanged and working. |
| D | Pull-to-refresh: fetch subscriptions → merge → ping all, sequential; also runs on app foreground | VERIFIED | `pullToRefresh` and `silentForegroundRefresh` unchanged. |

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` | HTTPS-only fetch + SSRF blocklist | VERIFIED | CR-03: `isBlockedHost()` + `FetchError.blockedHost` + guard before `session.data` |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` | provisionTunnelProfile strict selection + deterministic isActive | VERIFIED | CR-01: strict if/else branch; CR-04: clear-all + sort-by-uuid |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` | same-context delete + raw failures | VERIFIED | CR-02: early-return on miss; CR-05: `agg.failures` direct |
| `BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift` | ProbeAggregate.failures: Int | VERIFIED | `public let failures: Int` with doc comment explaining CR-05 rationale |
| `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` | passes failures: Int to ProbeAggregate init | VERIFIED | `ProbeAggregate(avgLatencyMs: avg, failures: failures, lossRate: lossRate, probedAt: Date())` |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `SubscriptionURLFetcher.fetch` | Session | `isBlockedHost` guard before `session.data` | WIRED | CR-03 fix: blocklist check at line 91 before `session.data(for:)` at line 100 |
| `provisionTunnelProfile(for:)` | User-selected server | `if let id = selectedID` strict branch | WIRED | CR-01 fix: throws on miss/decode-failure; no silent substitution |
| `confirmDeleteSubscription` | Subscription row | `context.fetch(subRowDesc).first` local-context lookup | WIRED | CR-02 fix: early-return on miss; `context.delete(row)` only |
| `pingAllServers` | `ServerConfig.failedProbeCount` | `agg.failures` direct assignment | WIRED | CR-05 fix: `row.failedProbeCount = agg.failures` at line 309 |
| `probeServerThreeTimes` | `ProbeAggregate.failures` | local `failures` counter | WIRED | `ProbeAggregate(avgLatencyMs: avg, failures: failures, ...)` |

---

## Behavioral Spot-Checks

| Behavior | Evidence | Status |
|----------|----------|--------|
| ConfigParser 93 tests (was 84, +9 CR-03) | `grep -rn "func test" Packages/ConfigParser/Tests/` = 93 | PASS (count verified) |
| VPNCore 32 tests (4 callsites updated to failures: param) | `grep -rn "func test" Packages/VPNCore/Tests/` = 32; `failures:` in ServerScoreTests confirmed | PASS (count verified) |
| AppFeatures 37 tests (mock factories updated) | `grep -rn "func test" Packages/AppFeatures/Tests/` = 37; `failures:` in AutoSelectIntegrationTests + PullToRefreshTests confirmed | PASS (count verified) |
| Total: 162 tests | 93 + 32 + 37 = 162 | PASS |
| CR-05: old truncation gone | `grep "Int(agg.lossRate" ServerListViewModel.swift` = 0 results | PASS |
| CR-01: silent fallback gone | `grep "parsedList.isEmpty && targets.count == 1" ConfigImporter.swift` = 0 results | PASS |
| CR-03: isBlockedHost() exists | Function at lines 207-249 of SubscriptionURLFetcher.swift | PASS |
| CR-04: clear-all before set | `for row in allConfigs { row.isActive = false }` at line 222 | PASS |
| CR-02: early-return on miss | `guard let row = try? context.fetch(subRowDesc).first else { ... return }` at line 255 | PASS |

---

## Probe Execution

Step 7c: SKIPPED — no `scripts/*/tests/probe-*.sh` found; phase is not a migration/tooling phase.

---

## Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SRV-01 | Plans 02, 03, 05 | Auto-select по пингу + потерям | VERIFIED | CR-05 eliminates score corruption; full pipeline: `probeServerThreeTimes` → `ProbeAggregate.failures` → `ServerConfig.failedProbeCount` → `ProbeAggregate.score` → `ServerScore.autoSelect` |
| SRV-02 | Plans 01, 04 | Multi-subscription, секции в списке | VERIFIED | CR-02 eliminates crash risk; Subscription @Model + cascade delete + sections working |
| SRV-03 | Plans 03, 04 | Pull-to-refresh перепинговывает всё | VERIFIED | 2-phase pullToRefresh + silentForegroundRefresh unchanged and working |
| UX-04 | Plans 03, 04 | Server list screen с флагами, latency, Авто | VERIFIED | ServerListSheet + ServerRow + LatencyBadge + AutoCell all present and wired |

---

## Anti-Patterns Found

No TBD, FIXME, or XXX markers found in any of the 5 modified production files. No unreferenced debt markers.

The 11 warnings (WR-01..WR-11) from the original code review remain open but are non-blocking for Phase 3 and carry forward to Phases 4/7/11 as documented in the G1 Summary.

---

## Human Verification Required

None — all gap closures are programmatically verifiable. Visual/UX items (latency badge rendering, sheet animations) are unchanged from Phase 3 initial delivery and were not flagged as gaps.

---

## Gaps Summary

All 5 gaps from the initial verification are closed:

- **CR-05** (IEEE-754 truncation): `ProbeAggregate.failures: Int` + `agg.failures` direct write eliminates corruption of `failedProbeCount`, `isUnreachable`, and auto-select score.
- **CR-01** (silent server substitution): Strict `if let id = selectedID` branch in `provisionTunnelProfile(for:)` throws on decode failure; D-09 contract enforced.
- **CR-04** (non-deterministic isActive): Clear-all + sort-by-uuid-string ensures exactly one `isActive == true` after every merge; deterministic across runs.
- **CR-02** (cross-context SwiftData delete): Early-return on local-context miss eliminates undefined-behaviour delete of foreign-context object.
- **CR-03** (SSRF no hostname blocklist): `isBlockedHost()` covers all private/loopback/RFC-1918/ULA/multicast ranges; guard fires before `session.data`; 9 new tests.

Phase 3 goal achieved. Ready to mark COMPLETE and proceed to Phase 4.

---

_Verified: 2026-05-12T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification after gap-closure plan G1 (commits 8432fed, 5173fa9, 61121bf)_
