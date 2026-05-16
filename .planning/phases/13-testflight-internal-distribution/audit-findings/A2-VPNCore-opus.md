# A2 — VPNCore audit (Opus 4.7)

**Scope:** `BBTB/Packages/VPNCore/Sources/VPNCore/`
**Files audited:** 13 (DNSConfig, KeychainPersistResult, KeychainStore, ParsedConfigs, ProbeResult, ServerConfig, ServerProbeService, ServerScore, Subscription, SwiftDataContainer, TransportConfig, VPNCore, VPNProtocolHandler)
**Total findings:** 11 (CRITICAL: 0, HIGH: 3, MEDIUM: 5, LOW: 3)

> Scope note: `TunnelController.swift` is NOT in VPNCore (it lives in `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`). State-machine / disconnect-race findings will be covered by the AppFeatures audit. VPNCore is data layer + probe service + Keychain wrapper only.

## Findings

### [HIGH] A2-001: KeychainStore silently falls back to app-private access group when `AppIdentifierPrefix` is missing
- **Location:** `KeychainStore.swift:29-35, 45, 60, 81, 98, 109-117`
- **Dimension:** security / bugs (extension interop)
- **Description:** `accessGroup` reads `Bundle.main.infoDictionary["AppIdentifierPrefix"]` and returns `nil` if absent. All four query builders write `if let group = accessGroup { query[kSecAttrAccessGroup] = group }` — when nil, items are written to the calling process's **default** (private) access group, NOT to the shared `<TeamID>.app.bbtb.shared` group. Tunnel extension cannot read items written this way.
- **Why it matters:** On TestFlight builds, if `AppIdentifierPrefix` is not exported into the main bundle's Info.plist (it is auto-injected by Xcode signing, but trivial to drop in a custom build configuration), the app will silently write VLESS secrets to the wrong group and the extension's `startTunnel` will fail at Keychain load with `errSecItemNotFound` — symptom looks like "first connect always fails." No assertion / log warns of this.
- **Suggested fix:** Add `assert(accessGroup != nil, "AppIdentifierPrefix missing — Keychain will be unshared")` in release-builds-with-precondition, and `Logger.error` in DEBUG when nil while running under a real bundle (i.e. not xctest). Optionally add an env-detection helper `isRunningInTestEnvironment()` to avoid noise in unit tests.

### [HIGH] A2-002: `KeychainStore.save` does not pin `kSecAttrSynchronizable=false`
- **Location:** `KeychainStore.swift:37-50`
- **Dimension:** security
- **Description:** Save query omits `kSecAttrSynchronizable` entirely. Default behavior for `kSecClassGenericPassword` is `kSecAttrSynchronizableAny` for queries but `false` for writes — however explicit pinning is recommended Apple best practice for secrets that must not leave the device. Without it, future code or a malformed merge could allow iCloud Keychain sync of VPN credentials.
- **Why it matters:** VLESS UUID + Reality private/public material is exfiltration-grade if synced to iCloud. The user trust boundary for a VPN client is "stays on this device." Pinning is a one-line defense-in-depth.
- **Suggested fix:** Add `kSecAttrSynchronizable as String: false` to the `save` query (and to delete/load match queries — using `kSecAttrSynchronizableAny` if reading is desired). Also consider `kSecUseDataProtectionKeychain: true` on macOS Catalyst builds.

### [HIGH] A2-003: SwiftData `#Predicate` on optional `String` in migration; force-unwrap risk via grouping
- **Location:** `SwiftDataContainer.swift:90-118`
- **Dimension:** bugs (SwiftData / lightweight migration)
- **Description:** Migration fetches via `#Predicate { $0.subscriptionURL != nil }`, then `Dictionary(grouping: rows) { $0.subscriptionURL! }`. The known anti-pattern (`feedback_swiftdata_uuid_predicate.md`) is `#Predicate` over `UUID?`; the String? case is documented to work but has had Apple-side regressions across iOS 17/17.4 (returns empty / partial result sets when the underlying SQLite NULL handling differs from predicate optimizer). If the predicate silently returns a subset of nonzero rows, the force-unwrap on line 99 is safe but **rows with non-nil subscriptionURL escape migration**, leaving `subscriptionID = nil` permanently — UI then shows them under fallback `nil` bucket forever.
- **Why it matters:** Migration is idempotent on subsequent launches BUT only re-runs on launches where `migrationDoneKey == false`. If first migration ran on a buggy iOS minor and skipped rows, the flag was set and silent data corruption is permanent. Users see "missing servers."
- **Suggested fix:** Replace `#Predicate` with `FetchDescriptor<ServerConfig>()` (all rows) + Swift-side filter `rows.filter { $0.subscriptionURL != nil }`. This mirrors the established workaround pattern. Cost is negligible (≤ a few thousand rows once).

### [MEDIUM] A2-004: `KeychainStore.accessibleFlag` force-casts attribute value
- **Location:** `KeychainStore.swift:102`
- **Dimension:** bugs (crash risk)
- **Description:** `return dict[kSecAttrAccessible as String] as! CFString?` — force-cast to `CFString?`. If the keychain attribute dictionary ever returns the value under a different type (e.g. an `NSString` bridged but compared incorrectly, or a future Apple-side change), the unwrap traps.
- **Why it matters:** This helper is verification-only (used in SEC-05 tests + diag). Not in hot path, so impact is limited. But a forced cast on opaque keychain output is fragile — could turn a "low confidence" diagnostic into a crash.
- **Suggested fix:** `return dict[kSecAttrAccessible as String] as CFString?` (conditional cast, no `!`), or `dict[kSecAttrAccessible as String].flatMap { $0 as? CFString }`.

### [MEDIUM] A2-005: Probe timeout `Task {}` does not inherit parent task and may leak past stream cancellation
- **Location:** `ServerProbeService.swift:92-98`
- **Dimension:** thread-safety / concurrency
- **Description:** Inside `withCheckedContinuation`, the timeout is started with `Task { try? await Task.sleep(for: .milliseconds(timeoutMs)) ... }`. This unstructured Task does NOT inherit cancellation from the parent. The outer `onCancel` block correctly cancels the `connection`, which fires `.cancelled` on the state handler → `tryFlip` returns true → cont resumes `.timeout`. The detached timeout Task still wakes ~500ms later; `tryFlip` returns false; it's a no-op. So no double-resume — but on heavy cancellation (e.g. user spamming refresh), dozens of dormant timeout tasks linger up to 500ms each, holding `cont`, `clock`, `connection`, `resumed` capture refs.
- **Why it matters:** Modest memory churn on probe storms (8-way concurrent × 30 servers × cancel/restart). Not a leak (tasks DO complete), but adds GC pressure and Mach port turnover. Aligns with DEC-06d-04 spirit (bounded concurrency).
- **Suggested fix:** Replace the bare `Task {}` with `Task.detached(priority: .userInitiated) { [weak resumed] in ... }` and check `Task.isCancelled` after sleep, or use `withTaskCancellationHandler` + `try await Task.sleep` (which throws on cancel) to short-circuit immediately. Even simpler: use Apple's `Task.sleep(for:tolerance:clock:)` with cancellation-on-throw.

### [MEDIUM] A2-006: `probeAll` retains TaskGroup work even when `AsyncStream` consumer detaches mid-iteration
- **Location:** `ServerProbeService.swift:133-171`
- **Dimension:** thread-safety / lifecycle
- **Description:** `continuation.onTermination = { _ in task.cancel() }` fires on consumer disconnect AND on `continuation.finish()`. Inside the inner `Task`, `withTaskGroup` checks `Task.isCancelled` only inside the `while let result = await group.next()` loop — not when spawning the initial up-to-cap tasks (lines 142-149). If the AsyncStream is cancelled BEFORE the first `await group.next()` returns, those up to 8 probes still run to completion (≤ ~1.5s each). Same concern in `probeServerThreeTimes` — cancellation between iterations triggers `break`, but a probe already in-flight runs to its 500ms timeout.
- **Why it matters:** Pull-to-refresh + rapid back-tap (common UX pattern) leaves up to 8 sockets open for ~1.5s. Bounded but still wasteful on cellular. Doesn't violate Swift 6 concurrency — `[self]` capture of actor is fine.
- **Suggested fix:** Before each `group.addTask` (lines 144, 158), check `if Task.isCancelled { break }`. Inside `probeServerThreeTimes`, wrap `probeOnce` in `withTaskCancellationHandler` such that an external cancel forces the inner NWConnection to cancel immediately (the cancel path is already there via `connection.cancel()` in `onCancel:`).

### [MEDIUM] A2-007: `ProbeAggregate.score` formula divides by total but is computed elsewhere with bare arithmetic
- **Location:** `ServerProbeService.swift:188-198`
- **Dimension:** logic
- **Description:** `let avg = latencies.isEmpty ? nil : latencies.reduce(0, +) / latencies.count`. Integer division → loss of precision (e.g. [101, 102, 103] → 102). Then `lossRate = Double(failures) / Double(totalAttempts)` where `totalAttempts = max(1, latencies.count + failures)`. If cancellation truncated the loop to 1 iteration with 0 successes + 1 failure → `lossRate = 1.0`, but score formula `avg × (1 + lossRate)` returns nil (avg nil) so server is treated as unreachable. The auto-select then drops it. **However**: if the consumer persists `failedProbeCount: failures` to ServerConfig (Plan 04 merge), a partial-cancel result (failures=1) is written, lowering the displayed `isUnreachable` threshold incorrectly on next launch.
- **Why it matters:** UI labels servers "unreachable" only at failedProbeCount >= 3. Persisting failures=1 from a cancelled probe round is silently OK. But persisting failures=2 from a 2-step cancel (sleep step interrupted between 2 and 3) is a stale gauge. Edge-case correctness.
- **Suggested fix:** Either: (a) only return ProbeAggregate when the full 3-round cycle completed (return Optional<ProbeAggregate>, nil on cancellation); or (b) document explicitly that consumer must guard `failures < 3` writes against cancellation flag. Cleaner: skip yield in the outer TaskGroup when cancelled (line 154 already does this).

### [MEDIUM] A2-008: `ServerConfig.transportOverride: TransportConfig?` SwiftData migration relies on undocumented Codable optional support
- **Location:** `ServerConfig.swift:64`
- **Dimension:** bugs (data migration risk)
- **Description:** Optional Codable enum stored as a SwiftData attribute is documented as a lightweight-migration Pitfall 3 (RESEARCH note in comment). Field was added in Phase 5 D-19; existing rows are expected to migrate with `nil`. If iOS SwiftData migrator encodes a default `.tcp` for non-null storage and then decode fails on next launch, the row is dropped silently (SwiftData ModelContext.fetch logs an error to OSLog but does not throw).
- **Why it matters:** Phase 13 ships v1.0 — first TestFlight users have NO data to migrate (clean install). But once v1.0 ships and users upgrade to v1.1 (which we know per memory will add SPKI pins, possibly more @Attribute), any further model changes compound the optional Codable risk. Worth a regression test in CI snapshot baselines (we have AppFeatures snapshots — extending to Phase3MigrationTests covers this).
- **Suggested fix:** Add a `Phase5TransportOverrideMigrationTests` that round-trips a v0 schema → v1 schema with one row that has `transportOverride = nil` and one with `transportOverride = .ws(...)`. Verify both fetchable post-migration.

### [MEDIUM] A2-009: `KeychainStore.delete` returns success when `accessGroup == nil` even if item exists in shared group
- **Location:** `KeychainStore.swift:75-87`
- **Dimension:** security / logic
- **Description:** When tests run without entitlement (`accessGroup == nil`), delete query has no access group. Per Apple docs, omitting `kSecAttrAccessGroup` matches the calling app's default. The result: a stale item in `<TeamID>.app.bbtb.shared` from a prior installed development build will NOT be cleared by a unit test cleanup. Cross-test contamination possible.
- **Why it matters:** Doesn't affect production runtime (entitlements always present), but does affect test reliability — particularly KeychainStoreTests on simulators reusing keychain across schemes.
- **Suggested fix:** In test environment, set a unique service prefix (e.g. `service = "app.bbtb.shared.tests.\(UUID())"`) per test run. Or: have `delete` enumerate both default + shared by trying both query variants.

### [LOW] A2-010: `VPNCore.version` is stale ("0.1.0") at Phase 13
- **Location:** `VPNCore.swift:4`
- **Dimension:** logic (code smell)
- **Description:** Version string was set Phase 1 and never bumped. Unused except perhaps in diagnostics? No callers grep'd.
- **Why it matters:** Diagnostic signal mismatch. Trivial.
- **Suggested fix:** Either bump to `"1.0.0"` matching app version, or remove if unused.

### [LOW] A2-011: `ServerConfig.identity` does not include `sni`, intentional — but `isUnreachable` computed-property naming collides between ServerConfig and ProbeAggregate
- **Location:** `ServerConfig.swift:126` and `ProbeResult.swift:51`
- **Dimension:** code smell / maintainability
- **Description:** Two `isUnreachable` computed properties with different semantics: ServerConfig uses persisted `failedProbeCount`; ProbeAggregate uses transient `avgLatencyMs == nil`. They drift if probe round is cancelled (see A2-007).
- **Why it matters:** Future contributors confuse the two. The persistence/transient mismatch is a latent bug source.
- **Suggested fix:** Rename `ServerConfig.isUnreachable` → `ServerConfig.isPersistentlyUnreachable` or `lastKnownUnreachable`. Add doc comment cross-referencing ProbeAggregate.

## Notes

- **No CRITICAL findings.** Nothing in VPNCore would block TestFlight. The two HIGH findings (A2-001 access group fallback, A2-002 missing `kSecAttrSynchronizable=false`) are both pre-existing latent risks worth fixing before public 1.0 but unlikely to bite Internal Testing (≤100 known testers, dev-trust env).
- **TunnelController state machine and disconnect-race patterns** are NOT in VPNCore — they live in `AppFeatures/MainScreenFeature/TunnelController.swift`. Defer A1/A3 audit subagent to those.
- **Swift 6 strict concurrency:** VPNCore is mostly clean. `ServerProbeService` actor + `nonisolated` annotations are correct; `LockedBool` is properly `@unchecked Sendable` with lock-pinned mutation; all @Model classes are `final` as required; value types (DNSConfig, TransportConfig, ProbeResult, ProbeAggregate, KeychainPersistResult, AnyParsedConfig + Parsed* structs) are explicitly Sendable. No race conditions detected at this layer.
- **Keychain query construction is the highest-risk surface** in this package (A2-001, A2-002, A2-004, A2-009). Consider extracting a helper `private static func baseQuery(tag:) -> [String: Any]` to enforce consistent `kSecAttrSynchronizable`, `kSecAttrAccessGroup`, and `kSecUseDataProtectionKeychain` pinning across all four call sites.
- **Idempotent migration discipline is correctly applied** in `SwiftDataContainer` (UserDefaults guard + per-row check). The single risk is the `#Predicate` reliance (A2-003).
- **Recommended pre-TestFlight action:** fix A2-001 and A2-003 (both ≤30 min). A2-002 is a defense-in-depth one-liner worth landing. Others can defer to v1.1.
