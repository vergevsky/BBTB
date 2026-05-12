---
phase: 03-server-management
reviewed: 2026-05-12T00:00:00Z
depth: deep
files_reviewed: 25
files_reviewed_list:
  - BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/ServerScore.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/KeychainPersistResult.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/LatencyBadge.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerSelectionCoordinating.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListState.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/PingState.swift
  - BBTB/Packages/AppFeatures/Package.swift
findings:
  critical: 5
  warning: 11
  info: 7
  total: 23
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-05-12T00:00:00Z
**Depth:** deep
**Files Reviewed:** 25
**Status:** issues_found

## Summary

Phase 3 introduces server-management (subscription pull-to-refresh, server list sheet,
auto-select via TCP probes, manual selection persistence, cascade delete). The implementation
follows the planned architecture (actor-based probe service, pure-function autoSelect, protocol
DI for testability) and has clear documentation/comments referencing decisions D-03..D-14 and
RESEARCH pitfalls.

However, deep cross-file analysis surfaces **5 BLOCKER-level defects** that affect correctness
of the most user-visible paths:

- **Silent server substitution (CR-01):** if a user manually selects server X and X's Keychain
  decode fails, `provisionTunnelProfile(for:)` silently switches to a different server pool —
  the user is connected to a server they did not choose. This violates the explicit-selection
  contract (D-09).
- **Cascade-delete double-delete crash (CR-02):** `confirmDeleteSubscription` deletes the
  fetched row AND the passed-in `subscription` argument, which is the same persistent object —
  SwiftData will throw on the second `context.delete` of a deleted object.
- **Subscription URL no-host-validation SSRF (CR-03):** `SubscriptionURLFetcher.fetch` enforces
  HTTPS but does NOT validate the hostname — `https://localhost/admin`, `https://169.254.169.254/`
  (cloud metadata), or `https://10.0.0.1/` URLs will be hit when the user pastes them.
- **`isActive` flag race overwrites user data (CR-04):** in subscription merge path, the line
  `if let first = savedConfigs.first { first.isActive = true }` flips one ServerConfig's
  isActive without clearing other rows — and the chosen "first" depends on SwiftData fetch
  ordering which is unspecified. This can promote a different server on every import.
- **`failedProbeCount` truncation losing failures (CR-05):** `Int(agg.lossRate * 3)` truncates
  IEEE-754 floating-point result (e.g., 1/3 × 3 = 0.99999...) → 1 failed probe persisted as 0.
  Plus when probe was cancelled mid-cycle the lossRate denominator isn't 3, making the *3 math
  meaningless. This corrupts `ServerConfig.isUnreachable` and `score` used for auto-select.

The 11 warnings cover: missing observer removal (leaked NotificationCenter observer), unhandled
empty-base64-input edge case, race between init and refresh(), missing context save after
mutating fetched rows in `pingAllServers`, and several silent error-swallowing patterns
(`try?` discarding important failures).

## Critical Issues

### CR-01: `provisionTunnelProfile(for:)` silently substitutes server when manual selection fails to decode

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:438-464`
**Issue:** When the user has manually selected a server (`selectedID != nil`) and
`reparseFromKeychain` returns `nil` (Keychain miss/corrupt for that one server), the code
falls through to building a full multi-outbound pool with `urltest` over **all** other
supported servers. The user expects to connect to server X; they get connected to a different
server (the urltest winner). The Pitfall 10 comment claims this is "graceful fallback", but
it silently violates D-09 explicit-selection contract — there is no UI signal that selection
was ignored. This is the same class of issue as VPN-redirect that the threat model treats
seriously.

Worse: there is no log line or error surfaced — `try? reparseFromKeychain(...)` swallows the
specific failure, so debugging which server failed to decode is impossible.

**Fix:**
```swift
// If a specific server was requested but cannot be reconstructed, FAIL — do not
// substitute another server silently. Only fall back to full pool when selectedID == nil.
if let id = selectedID {
    guard let cfg = supported.first(where: { $0.id == id }) else {
        throw ImporterError.noSupportedServers // or .selectionMissing(id)
    }
    guard let tag = cfg.keychainTag,
          let parsed = try? reparseFromKeychain(cfg, tag: tag) else {
        throw ImporterError.configBuildFailed(
            NSError(domain: "BBTB.ConfigImporter", code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "Selected server cannot be decoded"]))
    }
    parsedList = [parsed]
} else {
    // Auto / full-pool path
    for cfg in supported {
        guard let tag = cfg.keychainTag,
              let parsed = try? reparseFromKeychain(cfg, tag: tag) else { continue }
        parsedList.append(parsed)
    }
}
```

---

### CR-02: `confirmDeleteSubscription` deletes the same subscription row twice

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:248-258`
**Issue:** The code fetches a fresh `Subscription` row by id (`row`) and deletes it; then has
an `else` branch that deletes the passed-in `subscription`. The comment claims this protects
against "non-persisted scenarios", but it's both paths in one logical operation. The real
hazard is in the **success path of the first branch**: `row` and `subscription` typically
refer to the same persistent object (SwiftData returns the same managed instance for the same
id within a context, but the caller's `subscription` may be from a different context). Even
if not the same instance, the subscription was already deleted via the cascade fetch—repeated
`context.delete(row)` of a tombstoned row in some SwiftData builds throws and aborts the save.

Additionally, the comparison `subscription.id` between the caller-passed value and the freshly
fetched row is not necessarily safe: `subscription` is a `Subscription @Model` that may have
been invalidated by other context activity between confirmation dialog open and confirm tap.

**Fix:**
```swift
// Refetch by id and delete exactly once. Do not retain the caller's instance.
let lookupID: UUID = subscription.id
let subRowDesc = FetchDescriptor<Subscription>(predicate: #Predicate { $0.id == lookupID })
guard let row = try? context.fetch(subRowDesc).first else {
    // Already gone — log and bail; do NOT attempt to delete `subscription`.
    Self.log.warning("confirmDeleteSubscription: subscription \(lookupID) already deleted")
    pendingDeleteSubscription = nil
    await loadFromStore()
    return
}
context.delete(row)
try? context.save()
```

---

### CR-03: `SubscriptionURLFetcher.fetch` allows SSRF — no hostname validation

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:76-93`
**Issue:** The function enforces `scheme == "https"` but performs **no validation of the
hostname**. An attacker (or even a copy/paste mistake) can submit:
- `https://localhost/foo` → hits the device's own loopback HTTPS endpoints
- `https://127.0.0.1/`, `https://[::1]/`
- `https://169.254.169.254/latest/meta-data/` (cloud metadata service — relevant when device
  is on a corporate Wi-Fi with cloud bastion)
- `https://10.0.0.1/admin` → hits LAN router admin pages
- `https://internal.corp.example/` → hits intranet via captive Wi-Fi

The fetched response is then parsed and (T-03-17 threat) the Profile-Title is propagated into
`Subscription.name` which is shown in UI — the attacker may control content via internal HTTP
servers.

The threat model `T-03-06` claims this is mitigated, but the mitigation is not implemented in
this code path. The R1-spirit comment in line 50 says "HTTPS-only enforced", but HTTPS alone
does not stop SSRF to private ranges.

**Fix:**
```swift
public static func fetch(url: URL, session: URLSession = .shared) async throws -> SubscriptionFetchResult {
    guard url.scheme?.lowercased() == "https" else { throw FetchError.nonHTTPS(url.scheme ?? "") }
    guard let host = url.host, !host.isEmpty else { throw FetchError.malformedURL }
    // Reject private/loopback/link-local hostnames (basic check; full IP-range check
    // requires resolving DNS — for v0.2 string-prefix reject covers common cases).
    let lowerHost = host.lowercased()
    let blocked: [String] = ["localhost"]
    let blockedPrefixes: [String] = ["127.", "10.", "169.254.", "192.168.",
                                     "172.16.", "172.17.", /* ... 172.31. */
                                     "0.", "::1", "fc", "fd", "fe80:"]
    if blocked.contains(lowerHost) || blockedPrefixes.contains(where: { lowerHost.hasPrefix($0) }) {
        throw FetchError.malformedURL  // reuse or add .blockedHost
    }
    // ... rest unchanged
}
```

For Phase 3 ship-ready: add an explicit blocklist of private/loopback ranges and a unit test.

---

### CR-04: `isActive` flag is set on a non-deterministic "first" row in subscription merge path

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:174-217`
**Issue:** After `SubscriptionMergeService.merge` completes for a subscription URL, the code
fetches all supported servers for that subscription (`postMergeDescriptor`) and marks the
**first** one (`savedConfigs.first`) as `isActive = true`. Two problems:

1. **Non-deterministic ordering:** `FetchDescriptor<ServerConfig>` with no `sortBy:` returns
   rows in unspecified order. On every re-import the "first" can be a different server, so the
   UI footer (Phase 1 carry-forward) shows different server names randomly. More importantly,
   other code paths (e.g., `loadActiveServer`) fetch `isActive == true` and use it.
2. **Stale isActive on other rows:** the code sets `first.isActive = true` but does NOT clear
   `isActive = false` on the previously-active row. If a previous import marked server A
   active, and a new merge promotes server B without clearing A, both will report
   `isActive == true`. `loadActiveServer` returns the first, which is unspecified —
   `currentServerLineText` may flicker.

**Fix:**
```swift
// Clear isActive on all rows under this subscription first, then promote the chosen one.
for cfg in savedConfigs { cfg.isActive = false }
// Pick deterministically — e.g., first by createdAt (oldest), or by id ordering:
if let first = savedConfigs.sorted(by: { $0.createdAt < $1.createdAt }).first {
    first.isActive = true
}
try? context.save()
```

Better: drop `isActive` from the merge path entirely. Phase 3 has explicit `selectedServerID`
in MainScreenViewModel + UserDefaults — `isActive` is Phase 1 legacy and should not be re-set
implicitly during subscription import. The comment "Phase 1 carry-forward для UI footer"
acknowledges this should go.

---

### CR-05: `failedProbeCount` corrupted by floating-point truncation and cancellation skew

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:297`
(also referenced behavior in `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift:159-168`)
**Issue:**
```swift
row.failedProbeCount = Int(agg.lossRate * 3)
```

Two distinct correctness defects:

1. **IEEE-754 truncation:** `Double(1)/Double(3) * Double(3)` is not exactly `1.0` for all
   compilers/architectures (the IEEE result is bit-for-bit `0.9999999999999999`, depending on
   how the FPU rounds the intermediate). `Int(0.9999...) == 0`. So a 1/3 loss rate
   (1 failure out of 3) can be persisted as `failedProbeCount = 0`. This in turn makes
   `ServerConfig.isUnreachable` (defined as `failedProbeCount ?? 0 >= 3`) inaccurate.
2. **Cancellation skew:** `ProbeAggregate.lossRate = Double(failures) / Double(totalAttempts)`
   where `totalAttempts` can be 1 or 2 when the probe was cancelled mid-cycle. Multiplying
   that ratio by 3 yields a number that conflates "1 failure out of 2 attempts" with
   "1.5 failures out of 3", which gets stored as `Int(1.5) = 1` — internally inconsistent
   with the canonical "0..3 — число failed TCP-probe" semantics in the doc comment of
   `ServerConfig.failedProbeCount`.

**Fix:** Persist the raw failure count directly. Either expose `failures` on
`ProbeAggregate`, or compute it from rounding:
```swift
// Expose `failures: Int` directly on ProbeAggregate (preferred):
public struct ProbeAggregate: Sendable, Equatable {
    public let avgLatencyMs: Int?
    public let failures: Int            // explicit count, 0..3
    public let lossRate: Double         // derived: Double(failures)/Double(attempts)
    public let probedAt: Date
    // ...
}
// In probeServerThreeTimes: return failures explicitly.
// In ServerListViewModel.pingAllServers:
row.failedProbeCount = agg.failures
```

If you cannot change ProbeAggregate this phase, fall back to `Int((agg.lossRate * 3).rounded())`
— but that still aliases the cancellation case (2 attempts) onto a 3-attempt scale.

---

## Warnings

### WR-01: `pingAllServers` mutates fetched `@Model` rows without re-fetching in the same context

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:279-302`
**Issue:** The function fetches `supported` rows, iterates `probeService.probeAll(...)` (which
streams asynchronously over many seconds), then mutates `row.lastLatencyMs`, `row.lastPingedAt`,
`row.failedProbeCount`. During those seconds, the rows can be deleted (cascade delete,
swipe delete) or replaced (pull-to-refresh merge). Writing to a tombstoned `@Model` instance
is undefined behavior in SwiftData — it may crash on `context.save()` or silently no-op.

Additionally, the comment `lastLatencyMs` setter doesn't go through a guard to confirm the row
is still alive.

**Fix:** Either re-fetch the row by id inside the await loop, or capture the id at probe start
and update by predicate fetch when each result arrives:
```swift
for await (id, agg) in probeService.probeAll(payload) {
    if Task.isCancelled { break }
    let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
    guard let row = try? context.fetch(desc).first else { continue }
    row.lastLatencyMs = agg.avgLatencyMs
    row.lastPingedAt = agg.probedAt
    row.failedProbeCount = agg.failures  // see CR-05
    pingStates[id] = .completed(agg)
}
```

---

### WR-02: NotificationCenter observer never removed → leak + risk of stale callback

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:94-105,112-115`
**Issue:** The observer is stored in `killSwitchObserver` but never removed. The comment claims
"ViewModel lives entire app lifecycle so manual removal is не критичен" — but this is wrong
in tests (the test target creates ViewModels frequently) and in SwiftUI previews. Worse:
`UserDefaults.didChangeNotification` is global; the observer references `self` via closure
even with `[weak self]`, but the observer **token itself is retained by NotificationCenter**
until removed. Multiple ViewModel instances stack up listeners; every UserDefaults change
spawns multiple `handleUserDefaultsChange` invocations.

**Fix:**
```swift
deinit {
    if let observer = killSwitchObserver {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

Or migrate to `for await _ in NotificationCenter.default.notifications(named:...)` inside a
structured Task that gets cancelled when ViewModel deinits.

The comment about "non-Sendable killSwitchObserver from nonisolated deinit" is correct for
Swift 6 strict concurrency, but the standard workaround is to capture the token as a local
inside the closure setup, or use `MainActor.assumeIsolated { ... }` in deinit.

---

### WR-03: `SubscriptionURLFetcher.decodeBase64` returns `Data` for empty padded input

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:136-147`
**Issue:** If the input string after stripping `\n` and spaces is empty, `padded.count = 0`,
`pad = (4 - 0) % 4 = 0`, `padded = ""`, and `Data(base64Encoded: "")` returns an empty `Data`
object (not nil). Subsequent `String(data: data, encoding: .utf8)` returns "" (not nil). The
function therefore returns `""` for any all-whitespace input, masking it as "valid base64".
Callers (`isPrintableURIList`, `classify`) then treat empty as "valid base64 → not a URI list"
which falls through, but in `UniversalImportParser.classify` line 141-143 the branch
`isPrintableURIList(decoded)` correctly returns false for empty — OK in current callers. But
this is a latent landmine.

**Fix:**
```swift
public static func decodeBase64(_ s: String) -> String? {
    var padded = s.replacingOccurrences(of: "\n", with: "")
                  .replacingOccurrences(of: " ", with: "")
    guard !padded.isEmpty else { return nil }
    padded = padded.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
    let pad = (4 - padded.count % 4) % 4
    padded += String(repeating: "=", count: pad)
    guard let data = Data(base64Encoded: padded), !data.isEmpty else { return nil }
    return String(data: data, encoding: .utf8)
}
```

---

### WR-04: `selectedServerID` UserDefaults restore in `init` triggers immediate writeback

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:84-89`
**Issue:** The init reads UserDefaults and assigns `self.selectedServerID = uuid`, which
fires the `didSet` observer, which writes the exact same value back to UserDefaults. The
comment claims "didSet безопасен" — true for value, but this:
- causes a `UserDefaults.didChangeNotification` to fire during init, which invokes
  `handleUserDefaultsChange` — even though the value is unchanged
- writes UserDefaults on the launch path (minor I/O cost)
- if `userDefaults` is the same instance observed by `killSwitchObserver`, the observer is
  set up AFTER this assignment, so the immediate change is missed; but on subsequent reads of
  `app.bbtb.killSwitchEnabled` from the same notification, this is fine — still confusing.

**Fix:** Avoid the property setter on init — use a private restore method that bypasses didSet:
```swift
// Make selectedServerID storage explicit
@Published public var selectedServerID: UUID? = nil {
    didSet { saveSelectedServerID() }
}
// In init, before observer setup:
if let stored = userDefaults.string(forKey: Self.selectedServerIDKey),
   let uuid = UUID(uuidString: stored) {
    // _selectedServerID accessor isn't available; use a flag to suppress one persist
    _isRestoringFromUserDefaults = true
    self.selectedServerID = uuid
    _isRestoringFromUserDefaults = false
}
// In saveSelectedServerID():
private func saveSelectedServerID() {
    guard !_isRestoringFromUserDefaults else { return }
    // ...
}
```

---

### WR-05: `MainScreenViewModel.init` spawns unstructured `Task { await refresh() }` race

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:91`
**Issue:** `Task { @MainActor in await refresh() }` is detached/unstructured. Callers of
`init` (App / preview / tests) cannot await this completion. Tests that call `init` then
check `state` immediately will observe `.empty` regardless of stored content. This is a
common source of flaky tests and "first-launch shows empty then flickers to idle" bugs.

**Fix:** Expose `start()` (or `bootstrap()`) async on the ViewModel; let the App scene call it
in `.task { await vm.start() }`. Or document explicitly that this is "fire and forget" and
ensure tests use the explicit refresh() path.

---

### WR-06: `subscriptionFetchErrors.count == subscriptions.count` doesn't account for sequencing/empty case

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:163-168`
**Issue:** The "all failed" check compares dictionary count to array count. If `subscriptions`
was non-empty but every subscription was cancelled (Task.isCancelled break on line 153), some
subscriptions never had an error recorded, so `subscriptionFetchErrors.count < subscriptions.count`,
and the user sees no error indicator even though nothing was refreshed. Conversely, if a
subscription's URL changes between two iterations (theoretically impossible mid-loop, but
the predicate-based count is fragile), this can drift.

**Fix:**
```swift
let totalAttempted = subscriptions.count
let failedCount = subscriptionFetchErrors.count
if totalAttempted > 0 && failedCount == totalAttempted && !Task.isCancelled {
    let msg = L10n.serverListRefreshErrorMessage
    refreshError = msg
    state = .refreshError(msg)
}
```

---

### WR-07: `applySelection(nil)` during cascade delete of selected server triggers reconnect-to-deleted

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:212-230, 260-262`
**Issue:** In `deleteServer`/`confirmDeleteSubscription`, the order is:
1. `context.delete(row)` + `context.save()` → server gone from store
2. `coordinator?.applySelection(nil)` if it was selected

But `applySelection(nil)` (in MainScreenViewModel) goes into `reconnectAfterSelectionChange`
if state is `.connected`. That function calls `provisionTunnelProfile(for: nil)` → fetches
remaining supported servers and builds a full-pool urltest config → connects. **Result:** the
user explicitly deleted a server while connected to it, the app auto-reconnects to a different
server without confirmation. This may or may not be desired UX, but D-09 says auto-reconnect
should happen only on `applySelection(_:)` user gesture — not on cascade delete.

**Fix:** Differentiate "user changed selection" vs "selection auto-reset because deleted":
```swift
// Option A: Add a parameter
public func applySelection(_ id: UUID?, reason: SelectionChangeReason = .userTap)
// In deleteServer:
coordinator?.applySelection(nil, reason: .selectedServerDeleted)
// In reconnectAfterSelectionChange — only reconnect if reason == .userTap
```

Or: disconnect tunnel before deleting the active server's row, and surface a banner asking the
user whether to reconnect.

---

### WR-08: `silentForegroundRefresh` ignores cancellation when committing context.save

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:187-209`
**Issue:** `try? context.save()` runs unconditionally after the fetch loop, even if
`Task.isCancelled` broke the loop early. If the loop was cancelled because the user backgrounded
the app and the system is shutting down, the save still attempts I/O — and partially merged
state may be persisted (some subscriptions fetched, others not).

**Fix:**
```swift
for sub in subscriptions {
    if Task.isCancelled { break }
    // ... fetch + merge
}
if Task.isCancelled {
    Self.log.debug("silentForegroundRefresh cancelled; skipping save")
    return
}
try? context.save()
await loadFromStore()
await pingAllServers()
state = savedState
```

---

### WR-09: `provisionTunnelProfile(for:)` uses `parsedList[0]` host even when full-pool fallback contains many servers

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:488-499`
**Issue:** In the fallback-to-full-pool path (manual selection failed decode, see CR-01), the
`tunnelRemoteAddress` is set to `parsedList[0].host` — which is the **first server in fetch
order**, not the urltest's choice. The auto-memory note
`feedback_netunnelnetworksettings_tunnelRemoteAddress.md` says iOS requires a valid IP/hostname
for this field. While `parsedList[0]` will be valid, it has nothing to do with the actual
selected server; the display label in Settings → VPN may show the wrong host. Combined with
CR-01, this compounds the silent-substitution problem.

**Fix:** Document that `tunnelRemoteAddress` is decorative; alternatively pick a stable
representative (e.g., the most-recently-pinged supported host) and update on every reconnect.
The `manager.localizedDescription` set to "BBTB" is fine, but consider including the active
server name in the description.

---

### WR-10: `getOrCreateSubscription` allows duplicate URL when normalization differs

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:621-636`
**Issue:** The query `$0.url == url` does exact string equality. Trivial differences create
duplicate Subscription rows for the same logical endpoint:
- `https://example.com/sub` vs `https://example.com/sub/`
- `https://example.com/sub` vs `https://Example.com/sub` (host case)
- `https://example.com/sub` vs `https://example.com/sub?token=...` (after server-side redirect)

Each duplicate gets its own pool of ServerConfig rows, doubling Keychain entries. The migration
function in `SwiftDataContainer.migratePhase2ToPhase3` has the same issue (line 71-72).

**Fix:** Normalize before storing (lowercase host, strip trailing slash, drop default port,
keep query). Add `@Attribute(.unique) public var url: String` if normalization is reliable —
but that requires migration if existing data has duplicates.

---

### WR-11: `decodeMaybeBase64` does not handle URL-safe base64 in Profile-Title header

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:166-170`
**Issue:** The function decodes `base64:...` prefixed values with `Data(base64Encoded:)`, which
rejects URL-safe alphabet (`-` `_`). Most Hiddify-style subscription endpoints emit titles in
URL-safe base64. Currently the function leaves the `base64:XYZ` literal string in
`Subscription.name`, which then goes through sanitization and shows as garbled text in UI.

**Fix:** Reuse the URL-safe-aware `decodeBase64` from this file:
```swift
private static func decodeMaybeBase64(_ s: String) -> String {
    if s.hasPrefix("base64:") {
        let body = String(s.dropFirst(7))
        if let decoded = decodeBase64(body) { return decoded }
    }
    return s
}
```

---

## Info

### IN-01: `outboundJSON` is always passed as `""` — dead field

**File:** `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift:41`,
`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:369,386,403,604`
**Issue:** `outboundJSON: String` is declared as "raw outbound dict как JSON-string (для
re-emit в pool)" but every call site passes `""`. The `reparseFromKeychain` reconstructs from
Keychain payload, not from this field. Dead serialized state takes space in SwiftData.
**Fix:** Either populate it (as a perf optimization for re-emit) or remove the field via
schema migration. Add a TODO until Phase 4 versioned schema migration.

---

### IN-02: `subscriptionURL` field marked DEPRECATED but still mutated

**File:** `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift:38-40`,
`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:307`
**Issue:** The doc says `subscriptionURL` is DEPRECATED, "новый код пишет ОБА поля для
backward-compat" — but the Phase 3 merge path (`SubscriptionMergeService.merge`) writes ONLY
`subscriptionID`, not `subscriptionURL`. Inconsistent. New servers added via merge will have
`subscriptionURL = nil`. If anything in Phase 4 still reads `subscriptionURL` (extension
read-only path?), it will break.
**Fix:** Either ensure all write paths populate both fields until Phase 4 schema rev, or
remove `subscriptionURL` immediately with a one-off cleanup migration.

---

### IN-03: `Self.log.error` in `pullToRefresh` doesn't surface to user for per-subscription failures

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:157-159`
**Issue:** Per-subscription fetch failure goes into `subscriptionFetchErrors[sub.id]` for UI
inline indicator (good) and OS log (good). But if the user has no other diagnostics, a single
failed subscription (e.g., TLS error) needs more context. Consider adding the underlying NSError
domain/code to the message; right now `error.localizedDescription` is often "operation could
not be completed".
**Fix:** Use `String(describing: error)` or extract `(error as NSError).code` for diagnostic
purposes when logging; UI message stays user-friendly.

---

### IN-04: Magic numbers without symbolic constants

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift:34`,
`BBTB/Packages/AppFeatures/Sources/ServerListFeature/LatencyBadge.swift:66-70`,
`BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift:39,157`
**Issue:** Several magic numbers scattered across files:
- `50` (max outbounds) at PoolBuilder.swift:34
- `81/201/501` (latency tiers) at LatencyBadge.swift:67-70
- `500` (probe timeout ms), `50` (gap ms), `3` (probe count) at ServerProbeService
- `100` (name clamp) at SubscriptionMergeService.swift:147 and ConfigImporter.swift:646
**Fix:** Hoist to `enum Constants { static let maxOutbounds = 50; static let probeTimeoutMs = 500; ... }` per file or in VPNCore. Easier to tune and document the source of each threshold.

---

### IN-05: `RelativeDateTimeFormatter()` instantiated on every body re-render

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/SubscriptionHeader.swift:49`
**Issue:** Allocating a new `RelativeDateTimeFormatter` per render is wasteful in a list view
that recomputes frequently. Not a correctness bug (out of v1 scope per review rules), but
worth flagging since Phase 3 explicitly cares about list scroll perf with many subscriptions.
**Fix:** Hoist to `private static let formatter = RelativeDateTimeFormatter()`.

---

### IN-06: `persistSupported` placeholder UUID is leaked into `buildServerConfig` then immediately overwritten

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:298-307`
**Issue:**
```swift
let cfg = buildServerConfig(
    from: server,
    id: persistResult.id,
    subscriptionID: subscriptionID ?? UUID(),  // placeholder, не используется в single-paste path
    keychainTag: persistResult.tag
)
cfg.subscriptionID = subscriptionID
```
A throwaway UUID is generated even when the caller passed nil, then the field is reassigned.
Confusing; future readers may not notice the overwrite and propagate the placeholder.
**Fix:** Make `subscriptionID` an Optional parameter throughout the chain, or split
`buildServerConfig` into `buildSupportedServerConfig(subscriptionID: UUID?)`.

---

### IN-07: `Subscription.id` `@Attribute(.unique)` but `Subscription.url` is not

**File:** `BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift:23-24`
**Issue:** Without unique-constraint on `url`, the `getOrCreateSubscription` predicate query
is the only line of defense against duplicates. Any new code path that creates Subscriptions
without going through that helper (tests? future bulk import?) can produce duplicates.
**Fix:** Add `@Attribute(.unique) public var url: String` if SwiftData migration allows.
Otherwise document the invariant prominently in `Subscription.init` doc comment.

---

_Reviewed: 2026-05-12T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
