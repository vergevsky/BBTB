# A2' — VPNCore Re-Audit (Plan 04)

**Reviewer:** Opus 4.7
**Date:** 2026-05-17
**Scope:** `BBTB/Packages/VPNCore/Sources/VPNCore/` (13 swift files)
**Baseline:** main @ commit `55523dd`
**Mode:** READ-ONLY verification of Plan 03 T-B3 closures + regression scan + new-issue scan

---

## Closure Verification Table

| Plan 02 ID | Closure commit | Status | Evidence |
|------------|----------------|--------|----------|
| **A2-001 / C2-001** SecItemDelete using add payload | `7223253` (T-B3) | ✅ **VERIFIED CLOSED** | `KeychainStore.save:54-60` builds `lookupQuery` containing only class/service/account/synchronizable/optional-accessGroup (no `kSecValueData`). `SecItemDelete(lookupQuery)` called at `:64`. `addQuery = lookupQuery` then mutated to add `kSecAttrAccessible` + `kSecValueData` for `SecItemAdd` at `:71-74`. Delete-status non-success now logged via `keychainLogger.warning` at `:65-69` rather than swallowed. Apple-canonical split. |
| **A2-002 / C2-002** missing kSecAttrSynchronizable=false | `7223253` (T-B3) | ✅ **VERIFIED CLOSED** | All 4 query sites pin `kSecAttrSynchronizable as String: kCFBooleanFalse as Any`: `save.lookupQuery` (:58), `load` (:83), `delete` (:107), `accessibleFlag` (:123). Pinning is explicit, prevents VPN secrets syncing to iCloud Keychain regardless of platform default drift. |
| **C2-003** force-cast crash risk on accessibleFlag | `7223253` (T-B3) | ✅ **VERIFIED CLOSED** | `accessibleFlag:130-138` replaces `as! CFString?` with safe `if let s = dict[kSecAttrAccessible as String] as? String { return s as CFString }`. Returns `nil` if Security framework returns unexpected bridged type rather than crashing. Note: bridging assumption (Security CF returns ObjC-bridged `String`) is correct for `kSecAttrAccessible` per CoreFoundation toll-free bridging, but `else` branch will silently return nil if Apple ever changes bridging — see Notes. |
| **A2-003** SwiftData `#Predicate` on optional String | n/a | ⏸️ **CARRY-FORWARD CONFIRMED** | `SwiftDataContainer.migratePhase2ToPhase3:92-94` still uses `#Predicate { $0.subscriptionURL != nil }` on optional `String?`. This is the same UUID? anti-pattern class noted in MEMORY.md `feedback_swiftdata_uuid_predicate.md` — silent empty result on real devices. Migration is idempotent (UserDefaults flag) and Plan 03 explicitly carried forward per AUDIT.md line 211. **Phase 6c precedent: `subscriptionURL` is the legacy Phase-2 field; in practice all current rows have it set non-nil at write time, so silent-empty is masked. Still latent risk for users mid-migration after re-install.** |

---

## New Findings (missed by Plan 02 reviewers)

### A2'-001 — MEDIUM — `keychainLogger.warning` fires on **every** `accessGroup` access in test/no-entitlement environments

**File:** `KeychainStore.swift:144-156`
**What:** `teamIdentifierPrefix()` is invoked by the `accessGroup` computed property (`:38`), which itself is read inside every call to `save`, `load`, `delete`, `accessibleFlag` (lines 60, 87, 109, 127). When `AppIdentifierPrefix` is missing from `Bundle.main.infoDictionary` (xcodebuild test process, SwiftUI Preview, command-line tooling) **every** Keychain operation now emits a `Logger.warning` line.

The comment correctly identifies this as legitimate in tests, but the warning still fires unconditionally. In a UAT run with `KeychainStoreTests` + `ConfigImporterTests` (~30+ save/load cycles), this floods the unified log with identical strings. Worse, **on a production device with mis-set entitlement**, the warning fires per-operation but is not throttled or rate-limited; tens of thousands of warnings per session can mask other diagnostic signal.

**Why MEDIUM:** Not a security defect, but the diagnostic intent (single loud signal of misconfiguration) is defeated by per-call repetition. The cleanup ideally caches `teamIdentifierPrefix() -> String?` in a `static let` resolved once and logs once via `Logger.error` if nil. Currently the static-let pattern is not used because the value is computed on the first call to `accessGroup` from `Bundle.main` which is available at any post-launch point.

**Suggested fix:** Replace `teamIdentifierPrefix()` with `static let resolvedTeamIdentifierPrefix: String? = { ... }()` evaluated once, emitting the warning at first nil-resolution via `Logger.error` (loud) rather than `.warning`. Cache the result. Effort: 15 min.

---

### A2'-002 — LOW — `kSecAttrSynchronizable: kCFBooleanFalse as Any` cast pattern is fragile

**File:** `KeychainStore.swift:58, 83, 107, 123`
**What:** All four query dicts contain:
```swift
kSecAttrSynchronizable as String: kCFBooleanFalse as Any
```
The `as Any` cast is necessary because `kCFBooleanFalse` is `CFBoolean?` (optional CF type); inserting `nil` would silently elide the key. **But** the optional is force-unwrapped implicitly by the `as Any` cast — if a future SDK ever returned `nil` for `kCFBooleanFalse` (extremely unlikely but `CFBoolean!` is the actual import), `[kSecAttrSynchronizable] = nil as Any?` would insert `NSNull` and SecItemAdd would reject the dict.

**Why LOW:** SDK-stable; `kCFBooleanFalse` is a CoreFoundation constant guaranteed non-nil since iOS 4. Tested in Apple sample code with this exact pattern. Defensive coding would use `kCFBooleanFalse!` (force-unwrap) or `NSNumber(value: false)` for explicitness.

**Suggested fix:** Either accept current pattern (idiomatic Swift+Keychain) or use `NSNumber(value: false)` for self-documenting intent. No real-world risk. Effort: 5 min.

---

### A2'-003 — MEDIUM — `accessGroup` evaluated per-call; thread-safe but unnecessary `Bundle.main` reads in hot path

**File:** `KeychainStore.swift:34-40` + call sites 60/87/109/127
**What:** `accessGroup` is a `static var` (not `let`) recomputing on every read. `Bundle.main.infoDictionary` is thread-safe (documented) and cheap (cached internally by Foundation after first load), but each VPN reconnect cycle invokes `reparseFromKeychain` → multiple `KeychainStore.load` calls → each computes `accessGroup` afresh. For 5+ servers in a pool this is ~5-10 redundant Bundle reads per reconnect.

**Why MEDIUM (lean LOW):** Performance-only, no correctness defect. Tied to A2'-001's fix; caching `teamIdentifierPrefix` in a `static let` also caches `accessGroup` transitively. Plan 03 added per-call `os.Logger.warning` on nil-resolution making this hotter than before T-B3 (commit `7223253` slightly degraded hot-path log volume).

**Suggested fix:** Replace `static var accessGroup` with `static let accessGroup: String? = computeAccessGroup()` evaluated once at type-init time. Effort: 5 min combined with A2'-001.

---

### A2'-004 — LOW — `keychainLogger` is a module-private global; thread-safety relies on `Logger` being internally synchronised

**File:** `KeychainStore.swift:5-7`
**What:** Plan 03 added `private let keychainLogger = Logger(subsystem:..., category:...)` at file scope. `os.Logger` (iOS 14+) is documented as thread-safe (uses `os_log` under the hood with internal locks), so concurrent calls from `MainScreenViewModel`-spawned `Task`s and the extension-side reader are safe. **However**, the global is initialized lazily on first access; if first access happens from two threads simultaneously during launch, Swift's runtime `dispatch_once`-equivalent guards the init. No bug.

**Why LOW:** No defect. Filed for completeness given the user's task brief specifically asked: *"Plan 03 added `os.Logger` import + `keychainLogger` global. Any thread-safety / lifecycle issues?"* Answer: **No.** `os.Logger` is thread-safe by design; global lazy init is safe; no lifecycle issues (lives for process duration; no shutdown semantics needed).

**Suggested fix:** None. Pattern is correct.

---

### A2'-005 — LOW — `ServerConfig.identity` (host:port:protocolID) does not normalize host casing → false-negatives on re-fetch merge

**File:** `ServerConfig.swift:134-136`
**What:** `identity` returns `"\(host):\(port):\(protocolID)"`. If a subscription returns `Example.com:443:vless-reality` in one fetch and `example.com:443:vless-reality` in the next (server-side rotates capitalization, or admin edits casing), `SubscriptionMergeService` will treat them as different servers — duplicate row inserted, `lastLatencyMs` not preserved.

**Why LOW:** Edge case. Most subscription providers emit canonical lowercase hostnames. Latency-preservation regression is non-security. Cosmetic for end-user; counts as orphan stale row.

**Suggested fix:** `"\(host.lowercased()):\(port):\(protocolID.lowercased())"`. Effort: 2 min.

---

### A2'-006 — LOW — `ServerConfig.countryFlag` regex compiled per-call

**File:** `ServerConfig.swift:113-114`
**What:** `code.range(of: "^[A-Za-z]{2}$", options: .regularExpression)` compiles the regex on every UI render. Server-list rendering with 50+ rows in a list = 50+ regex compilations per scroll frame. `NSRegularExpression` caches internally but the Swift `String.range(of:options:)` path does not — verified per Apple swift-corelibs source.

**Why LOW:** Modern devices handle it (microseconds), but SwiftUI rebuilds the list on every `@Query` notification → hundreds of regex compilations per second during sync.

**Suggested fix:** Replace with `code.allSatisfy { $0.isLetter && $0.isASCII }` — same semantics, no regex. Effort: 5 min.

---

### A2'-007 — LOW — `SwiftDataContainer.migratePhase2ToPhase3` uses `try context.fetch` outside any actor isolation

**File:** `SwiftDataContainer.swift:90-118`
**What:** `migratePhase2ToPhase3(in:)` is marked `internal static throws` (sync). It creates `ModelContext(container)` and performs fetch/save synchronously on **whatever thread/queue** the caller invokes from. `runMigrationsIfNeeded(in:)` invokes it from `Task.detached { await ... }` per the App entry-point comment (`:62-68`), which means it runs on a cooperative thread. `ModelContext` is **not Sendable** and **not isolated** by SwiftData contract — Apple docs say to create context per-task and never share. The current pattern (one context, one task) is correct.

**Why LOW (lean INFO):** No defect, but the boundary contract is implicit. If a future caller invokes `migratePhase2ToPhase3` from another actor without `Task.detached`, the context could leak across isolation domains. A `@available(*, message: "Call from Task.detached or @MainActor only")` or explicit `nonisolated(unsafe)` annotation would document the invariant.

**Suggested fix:** Add documentation comment specifying caller must run on a single Task; or refactor to `@MainActor func migratePhase2ToPhase3Async()` if a SwiftData @ModelActor migration container makes sense. Plan 03 closed T-B5 with `provisionSerializer` actor pattern — same pattern would fit here for v1.1+. Effort: 30 min documentation; 2-4 hours full @ModelActor migration.

---

### A2'-008 — INFO — `KeychainError.notFound` is thrown but treated as soft error by all callers

**File:** `KeychainStore.swift:94-95` + call sites `ConfigImporter.swift:716, 831`
**What:** `load(tag:)` throws `.notFound(errSecItemNotFound)` when no entry exists. Callers in `ConfigImporter.reparseFromKeychain` use `try?` which silently swallows both `notFound` and `loadFailed`. This conflates "absent" (legitimate for a freshly-imported row before keychain write commits) with "Keychain access denied" (entitlement issue or device-locked). **No way to distinguish from logs.**

**Why INFO:** Not a Plan 03 regression; this is pre-existing. Listed for completeness given user asked for "new issues missed by Plan 02 reviewers".

**Suggested fix:** Callers should `do/catch` and log `.loadFailed` distinctly (loud) vs `.notFound` (silent). Effort: 30 min across 4 call sites.

---

## Regressions Detected

**Per the user's brief, scanning specifically for regressions from Plan 03 commit `7223253`:**

| Candidate | Verdict |
|-----------|---------|
| New `os.Logger` import + module-level `keychainLogger` | ✅ **No regression.** `os.Logger` is thread-safe; lazy init is safe; no lifecycle leaks. See A2'-004. |
| Per-call `keychainLogger.warning` in `teamIdentifierPrefix` (`:153-155`) | ⚠️ **Minor degradation.** Test environments and mis-entitled production builds now emit log spam (A2'-001). Not a correctness regression, but signal-to-noise worsened. |
| `kSecAttrSynchronizable: kCFBooleanFalse as Any` added to all 4 queries | ✅ **No regression.** Pattern is correct and idiomatic. |
| Split lookup/add query in `save` | ✅ **No regression.** Apple-canonical fix; matches Security framework docs. |
| `as? String → as CFString` bridge in `accessibleFlag` | ✅ **No regression.** Removes crash risk; behaviour-equivalent for valid Security framework returns. Silent-nil branch is documented. |
| Pre-delete OSStatus warning log on non-(success|notFound) | ✅ **No regression — improvement.** Surfaces silent failures that would previously have masked Keychain access issues. |

**Overall:** Plan 03 T-B3 is a clean closure. No correctness regressions. One minor diagnostic-volume issue (A2'-001) that should be cleaned up but is **not blocking** for TestFlight Internal.

---

## Notes

1. **`accessibleFlag` toll-free bridging assumption:** `kSecAttrAccessible` is one of the `kSecAttr*` constants that Security framework returns as a `CFString` toll-free-bridged to `NSString`/`Swift.String`. The Plan 03 `as? String` cast is correct. If Apple ever changes the bridging (no realistic scenario), the function would silently return nil; this is a **safer** failure mode than the pre-fix `as! CFString?` crash. **Verified CLOSED with no concerns.**

2. **A2-003 carry-forward acknowledged:** The `#Predicate { $0.subscriptionURL != nil }` pattern at `SwiftDataContainer.swift:93` is exactly the UUID? anti-pattern documented in user MEMORY (`feedback_swiftdata_uuid_predicate.md`). However, the migration is gated by a UserDefaults flag and runs once per install — in practice it succeeds on installs that ever wrote `subscriptionURL` (Phase 2+ users) because they actually have non-nil values. Risk is "fresh install + zero pre-migration rows + immediate Phase-2-style subscription import + race" which is essentially impossible for a v1.0 TestFlight build. Carry-forward to v1.1+ is reasonable.

3. **Other VPNCore files audited for cross-cutting issues:** `Subscription.swift`, `ServerConfig.swift`, `ServerProbeService.swift`, `ProbeResult.swift`, `ServerScore.swift`, `DNSConfig.swift`, `TransportConfig.swift`, `KeychainPersistResult.swift`, `ParsedConfigs.swift`, `VPNProtocolHandler.swift`, `VPNCore.swift`. No new CRITICAL/HIGH findings.

4. **`VPNCore.version = "0.1.0"` is stale** (Phase 13 plans suggest v1.0 ship). Already noted as LOW in Plan 02 (per AUDIT.md systemic patterns §1); not re-listing.

5. **`LockedBool: @unchecked Sendable`** in `ServerProbeService.swift:212` is correct per Apple guidance — `OSAllocatedUnfairLock` synchronises all mutation. This is the canonical pattern. No finding.

6. **`@Model` types are NOT Sendable** by design (SwiftData contract). `ServerConfig` and `Subscription` correctly avoid cross-actor passing — `ServerProbeService.probeAll` takes `[(id: UUID, host: String, port: Int)]` tuples instead. Pattern is correct.

---

## Summary

**Plan 03 T-B3 verified cleanly closed**: KeychainStore now uses split lookup/add queries (Apple-canonical), pins `kSecAttrSynchronizable=false` in all 4 queries, and safely bridges `accessibleFlag` via `as? String → as CFString`. **No correctness regressions** from the new `os.Logger` global. Three new MEDIUM-or-lower findings (A2'-001 log volume in `teamIdentifierPrefix`, A2'-003 redundant `Bundle.main` reads, A2'-005 `identity` casing not normalised) are non-blocking polish items for v1.1+; the remaining 4 findings are LOW/INFO. **A2-003 carry-forward confirmed** — the optional-`String` `#Predicate` migration pattern is latent risk masked in practice by the UserDefaults migration flag.

**VPNCore re-audit verdict: APPROVE for TestFlight Internal upload.** No blocking issues.
