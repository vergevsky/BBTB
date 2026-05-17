# A6 — MEDIUM-risk packages broad sweep (Opus 4.7)

**Wave:** 2 (MEDIUM)
**Baseline:** `fb2ff54`
**Scope:** SettingsFeature, ServerListFeature, FrontingEngine, DeepLinks, KillSwitch, TransportRegistry, Protocols × 6

**Files reviewed (≈50):**
- SettingsFeature: 16 files (~2164 LoC)
- ServerListFeature: 15 files (~1835 LoC) — incl. 2 `.figma.swift` Code Connect docs
- FrontingEngine: 9 files
- DeepLinks: 7 files
- KillSwitch: 1 file
- TransportRegistry: 7 files (TransportRegistry, TransportHandler, 5 handlers)
- Protocols: 12 files (6 protocols × 2: ConfigBuilder + Handler)

**Scope reminders honored (per task brief AUDIT-2.md):**
- T-B6' (c1ee6b4) — `FrontingConfigApplier.apply(json:profile:adapter:targetTag:)` tag-scoped. **Confirmed** reading `FrontingConfigApplier.swift:42-79` + `ConfigImporter.swift:715-744` (caller now computes `targetTag` from selected server's `parsedList.first` protocol case). Closes C7'-001.
- T-C7' (4f918c7) — `ServerListViewModel.loadFromStore(force:)`. **Confirmed** at `ServerListViewModel.swift:388-414`; mutation callers (`deleteServer`, `confirmDeleteSubscription`, `pullToRefresh`, `silentForegroundRefresh`) all pass `force: true`. Lifecycle caller `onAppear` keeps `force: false`. Closes C6'-002.
- T-C8' — Dead `SingBoxConfigTemplate.*.json` deletion. Not directly verified inside this scope (Package.swift `.process` declarations are out-of-scope for SwiftFile review); finding A6'-3-005 captures a knock-on observation (Hysteria2 / TUIC handler comments still reference removed templates).
- C8'-001 (fb2ff54 Tier D) — TUIC `insecure` comment clarified. **Confirmed** `TUIC/ConfigBuilder.swift:23-30` accurately describes "key NOT emitted at all" instead of "hardcoded false".
- C7'-002 (fb2ff54) — TCPTransportHandler "tuic" rationale. **Confirmed** `TCPTransportHandler.swift:18-23` documents intentional omission.
- C7'-003 (fb2ff54) — FrontingEngine drift-risk ACK. **Confirmed** `FrontingConfigApplier.swift:122-128` references R25 + decision-log.
- C9'-001 — Localizable duplicate key. Out of scope (xcstrings not in file list).

**Total findings:** 24 (C: 0 / H: 1 / M: 9 / L: 14)

---

## Critical

No CRITICAL findings in this scope.

---

## High

### A6'-3-001: ServerDetailViewModel.applyTransportSelection — `selectedTransport` mutated optimistically by Picker binding, NOT rolled back on persistence failure → UI/SwiftData divergence
- **Location:** `Packages/AppFeatures/Sources/ServerListFeature/ServerDetailViewModel.swift:83-100`
- **Dimension:** correctness
- **Description:**
  `TransportPicker` is bound to `$viewModel.selectedTransport` (a `@Published` var) — when the user picks a new transport, Swift's `Binding<TransportSelection>` setter writes `selectedTransport = newSelection` **immediately**, synchronously, before any `onChange` handler fires. Then `.onChange(of: viewModel.selectedTransport) { _, new in Task { await viewModel.applyTransportSelection(new) } }` schedules an async persistence task.

  Inside `applyTransportSelection`:
  1. Open fresh ModelContext.
  2. Fetch all `ServerConfig`, filter by `id == server.id` (Pitfall 4 acknowledged).
  3. If not found → log warning + return. **`selectedTransport` is NOT rolled back** → Picker still shows new selection, but store has previous value.
  4. Otherwise set `cfg.transportOverride = newOverride`; `try context.save()`. If `save()` throws → log error + return. **Again `selectedTransport` not rolled back.**
  5. Inside the `do {}` block at line 95: `selectedTransport = new` — this is a redundant no-op (already mutated by Picker binding).

  Concrete failure mode: SwiftData backing storage hit by `OSStatus` (disk full, container locked, model migration race) → user thinks they switched WS → gRPC, returns to ServerListSheet, reconnects → sing-box still gets old transport (next call to `ConfigImporter.buildPoolJSON` reads `transportOverride` from persisted row).

- **Why HIGH:**
  Silent state divergence between visible UI and persisted state. Worse than a stale read: user has positive proof («I tapped gRPC, the picker says gRPC») but the actual behaviour is WS. Combined with the absence of a `loadFromStore` refresh after transport mutation, a parent ServerListSheet observing the same `ServerConfig.transportOverride` will also stay stale. On reconnect the user gets unexpected behaviour with no error feedback.

  Severity tipped HIGH (not MEDIUM) by the lack of any user-visible error path: there is no equivalent of `refreshError` for transport persistence failure. SwiftData writes can fail silently on real devices (sandbox container locked during background snapshot, disk pressure on low-storage iPhones — both reachable scenarios in TestFlight).

- **Suggested fix:**
  Two options, prefer (a):
  1. **Snapshot-and-rollback pattern:**
     ```swift
     public func applyTransportSelection(_ new: TransportSelection) async {
         let previous = selectedTransport
         // selectedTransport already set by binding; this assignment is the "commit"
         let context = ModelContext(modelContainer)
         ...
         do {
             try context.save()
             // Persisted — keep new selection.
             Self.log.info("...")
         } catch {
             // Roll back UI state.
             selectedTransport = previous
             // Surface error — add @Published var persistError: String?
             persistError = error.localizedDescription
             Self.log.error("...")
         }
     }
     ```
     Add a top-level `.alert` driven by `persistError` (matching the existing `refreshErrorBinding` pattern in `ServerListSheet.swift:303-308`).
  2. Decouple Picker from VM state — use a separate `pendingTransport` `@State` in the view, only commit to `@Published selectedTransport` after `applyTransportSelection` succeeds. More refactor work but cleaner.

  Also: line 95 `selectedTransport = new` is dead code — Picker binding already wrote it. Remove or replace with `assert(selectedTransport == new)` in DEBUG to document the invariant.

---

## Medium

### A6'-3-002: SettingsView routingRulesEnabled toggle — no live-apply to active tunnel; toggle effect deferred to next manager re-provision
- **Location:** `Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift:76-81` + `Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:94-95`
- **Dimension:** correctness / UX
- **Description:**
  Phase 13 / D-04 — Routing rules toggle. `@AppStorage` writes to `group.app.bbtb.shared` suite. Extension reads it in `SingBoxConfigLoader.expandConfigForTunnel:329-366` (verified). Toggle change while active tunnel is connected DOES NOT trigger re-provision: there is no `.onChange(of: viewModel.routingRulesEnabled)` modifier (compare `AdvancedSettingsView.swift:39-43` `SecuritySection`'s `.onChange` → `applyEnforceRoutesToManager()`).

  Result: user toggles `routingRulesEnabled = false` mid-session expecting full-tunnel mode (everything through outbound) → extension still has old config baked in until user manually disconnects + reconnects. The current behavior matches what Apple's NETunnelProvider semantics give "for free" (extension reads UserDefaults at `startTunnel` time only), but the toggle's UX gives no signal about the deferred application.

- **Why MEDIUM:**
  Functional but not catastrophic; mirrors several other Phase 10 toggles (`muxEnabled`, `stunBlockEnabled`, `cdnFrontingEnabled`) which all share the same defer-until-reconnect semantic. The MEDIUM mark is for inconsistency: `autoReconnectEnabled` and `macOSDisableEnforceRoutes` DO live-apply (`applyAutoReconnectToManager`, `applyEnforceRoutesToManager`), but `routingRulesEnabled` (and four others) silently defer. Worth either a footer disclaimer ("Изменение применится при следующем подключении") or full live-apply path.

- **Suggested fix:**
  Cheapest: extend `L10n.settingsRoutingRulesFooter` (line 80) to mention "применится при следующем подключении" (matches existing copy patterns). Mirror across the four sibling toggles (`muxEnabled`, `stunBlockEnabled`, `cdnFrontingEnabled`, `utlsFingerprint`).
  Better: add `applyRoutingRulesToManager()` that posts `.bbtbProvisionerDidSave` so `TunnelController` can decide to re-provision (or surface a banner offering "Перезапустить туннель сейчас?"). Out of scope for v1.0 TestFlight if too invasive — but the footer fix is 3 lines.

### A6'-3-003: SettingsViewModel.cooldownTimer is a wall-clock Timer that does NOT pause when app suspends — drains state mid-cooldown
- **Location:** `Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:515-545`
- **Dimension:** correctness
- **Description:**
  Phase 8 W3 RULES-10 force-update cooldown uses `Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)`. The comment on `cooldownExpiresAt` (line 158) claims this is "Wallclock deadline для cooldown countdown — выживает foreground re-entry". However:

  1. The deadline is wallclock-correct (`cooldownTick` recomputes from `Date()`). ✓
  2. BUT — when the app is suspended, the `Timer` stops firing. On foreground re-entry the Timer resumes its tick schedule, but **`cooldownTick` is called only once per second of foreground time**, NOT instantly. If wallclock has advanced past `cooldownExpiresAt`, the button remains in `.cooldown(remaining: N>0)` for up to one extra second (or longer if the run loop is busy) until the next fire.
  3. Worse: there is no `.onChange(of: scenePhase)` or `applicationDidBecomeActive` hook to force a re-tick immediately on resume.

  Concrete repro: tap force-update → app sent to background for 60+ seconds → return to app → button shows e.g. `.cooldown(secondsRemaining: 42)` (stale snapshot from last tick before suspend) → next tick fires → recomputes → transitions to `.idle`. Visible UI flicker / "false locked out" for ≤1s.

  Additional concern: in `startCooldownTimer`, the Timer captures `[weak self]` but is owned by `cooldownTimer: Timer?` strong reference (line 163). When `teardown()` is called, timer is invalidated and removed; OK. But Timer also holds a strong reference to itself once scheduled on the run loop, AND captures the Task inside. The `Task { @MainActor [weak self] }` is fine, but the Timer-Self cycle relies on `teardown()` being called. Memory comment at line 184-189 says `deinit` cannot reach `@MainActor` properties — so if `teardown()` is never called and VM goes out of scope, Timer keeps firing forever (with `self?.cooldownTick` returning nil-self → re-runs). Effectively a self-cancelling leak (timer cycles run forever but do nothing), but eats CPU at 1Hz.

- **Why MEDIUM:**
  Visible UI flicker on app resume is annoying but not blocking. The phantom-timer-leak case requires VM disposal without calling `teardown()` — currently only host shutdown / tests path; production code keeps the same SettingsViewModel for the app lifetime, so this is effectively unreachable in production.

- **Suggested fix:**
  Add a `.onChange(of: scenePhase) { if newValue == .active { viewModel.refreshCooldownNow() } }` modifier in `AdvancedSettingsView` (or `SettingsView` if the host always presents AdvancedSettings via NavigationLink) and expose `refreshCooldownNow()` → calls `cooldownTick()` once. This guarantees the first frame on resume shows correct state.

  Optional: add an autoreleasepool-style hard reference removal in `teardown()` followed by a unit-test pattern using `MainActor.assumeIsolated { vm.teardown() }`.

### A6'-3-004: ServerListViewModel.pingAllServers swallows save errors silently when an existing refreshError is set — first save failure surfaces, subsequent ones don't
- **Location:** `Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:465-478`
- **Dimension:** correctness
- **Description:**
  M13 fix (Phase 6d) surfaces SwiftData save errors through `refreshError`, but the guard `if refreshError == nil { refreshError = L10n.serverListRefreshErrorMessage }` means:

  1. `pullToRefresh` runs → `subscriptionFetchErrors` partial fill → `refreshError = msg` (if all-failed) OR no refreshError set (if some succeeded).
  2. `pingAllServers` follows. If a save fails AND `pullToRefresh` already set `refreshError`, the more-recent ping-save failure is silently dropped.
  3. Or: `pullToRefresh` left `refreshError = nil` (mixed success), then ping save fails → user sees `"Не удалось обновить серверы"` (the L10n key implies subscription fetch failure, not ping persistence failure) — wrong copy.

  The L10n key `serverListRefreshErrorMessage` is also used by the alert in `ServerListSheet.swift:107-115` — that alert title is `serverListRefreshErrorTitle` (likely "Ошибка обновления подписки" or similar). Ping save failure shows the wrong title.

- **Why MEDIUM:**
  Misleading error copy on ping save failure (rare path); silent loss of error context when subscription error already present (also rare path). Not catastrophic but breaks the contract that "M13 surfaces all save errors".

- **Suggested fix:**
  Either add a separate `@Published var pingPersistError: String?` channel (matches `subscriptionFetchErrors` per-domain pattern), or change the merge: `refreshError = [prev, new].compactMap{$0}.joined(separator: "\n")`. Lower-impact: rename the L10n key or add a new key `serverListPingPersistError` and use it here.

### A6'-3-005: Hysteria2 + TUIC ConfigBuilders still reference removed `SingBoxConfigTemplate.*.json` templates in docstrings — drift risk
- **Location:**
  - `Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:6-23` (T-A2 comment block)
  - `Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift:6-17` (T-A2 comment block)
  - `Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ShadowsocksHandler.swift:13-16` (refers to "SingBoxConfigTemplate.shadowsocks.json НЕ содержит `tls` block")
- **Dimension:** correctness / docs
- **Description:**
  T-A2 (commit `55523dd`) removed raw-substitution template builders and (per T-C8') deleted dead `SingBoxConfigTemplate.*.json` resources from 5 of 6 protocol packages. The doc comments in `ConfigBuilder.swift` files correctly mark the templates as "removed" but the `Handler.swift` files in some protocols still reference template behavior as if alive.

  Examples:
  - `ShadowsocksHandler.swift:13-16` — «SingBoxConfigTemplate.shadowsocks.json НЕ содержит `tls` block в outbound[0]» — references a JSON file that no longer exists. Reader learning the codebase will hunt for the file.
  - `Hysteria2/ConfigBuilder.swift:6` says "Dead code в production" then later (`buildOutbound`) emits the live outbound. Reader confused: which is the live path?

  This is a documentation hygiene issue without functional impact.

- **Why MEDIUM:**
  Will mislead future code-review of D-08 R1 exception (Hysteria2 `allowInsecure`) — reader checks the documented test invariants and looks for `test_nonHy2_outbounds_neverHaveInsecureTrue` (line 22) which exists, but the surrounding context («Template-based ... removed») suggests the test runs against a non-existent template. Both halves of the comment are accurate but they don't compose well.

- **Suggested fix:**
  Sweep all 6 protocol packages' Handler + ConfigBuilder doc comments for references to `SingBoxConfigTemplate*.json` and rewrite. Pattern: replace «template» with «dict-based outbound builder». Also remove the "Dead code" sentence from `ConfigBuilder.swift:8-12` since post-T-A2 there is no dead template builder anymore in source — comment refers to a code path that was deleted.

### A6'-3-006: KillSwitch.appGroupSuiteName is `nonisolated(unsafe) static var` but never written from any call site — should be `let`
- **Location:** `Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:61`
- **Dimension:** concurrency / API hygiene
- **Description:**
  `public nonisolated(unsafe) static var appGroupSuiteName: String = "group.app.bbtb.shared"` — declared as a mutable static with manual safety annotation. `grep -rn "KillSwitch.appGroupSuiteName" Packages --include="*.swift"` returns ZERO write sites (no test, no app init, no Phase 10 setup). The accompanying comment claims «written once at app startup before concurrent access begins» — but no such write exists.

  Net effect:
  - The default value `"group.app.bbtb.shared"` is the only value ever seen.
  - The `nonisolated(unsafe)` annotation is an opt-out from Swift 6 strict-concurrency checking for a variable that is effectively immutable in practice.
  - A future contributor reading the comment will assume there's a setup hook somewhere and waste time looking for it.

- **Why MEDIUM:**
  Safety annotation lies (says «writes are safe because rare» when truth is «never written»). Swift 6 strict concurrency exemption for code that doesn't need it. Trivial fix.

- **Suggested fix:**
  Change to `public static let appGroupSuiteName: String = "group.app.bbtb.shared"`. Drops the `nonisolated(unsafe)` opt-out; gains compile-time guarantee against future writes; reduces the «documented invariant» surface. If a future Phase wants to override the suite name, that Phase can add a setter then.

### A6'-3-007: FrontingFallbackChain.nextEndpoint advances cursor BEFORE awaiting cache check — exhausts profiles even when none should be consumed
- **Location:** `Packages/FrontingEngine/Sources/FrontingEngine/FrontingFallbackChain.swift:62-85`
- **Dimension:** correctness
- **Description:**
  The actor-reentrancy mitigation moves `cursor = index + 1` BEFORE `await cache.shouldSkip(...)`. Rationale per docstring: prevents two concurrent callers from claiming the same slot (since `await` is a suspension point).

  Consequence: if `shouldSkip` returns true, the cursor has already advanced — the cooldowned profile is permanently skipped past for this `nextEndpoint` chain. That's intentional (we want to keep moving). However combined with `reset()` being the ONLY way to cycle through cooldowned profiles a second time, AND `reset()` being called only from `ConfigImporter` after «successful direct-connect» (per docstring) — there is no path where a profile that was in cooldown at iteration time gets re-evaluated WITHIN the same provisioning attempt.

  Example failure: profiles = [P1, P2, P3]. P1, P2 in cooldown, P3 not. First call → cursor 0→1, P1 cooldown → continue. cursor 1→2, P2 cooldown → continue. cursor 2→3, P3 viable → return P3. ✓.

  Second example (the bug): P1 cooldown, P2 viable, P3 unused. After return of P2, cursor=2. P2 fails → reportFailure → cache marks P2 cooldown. Caller invokes `nextEndpoint` again. cursor=2 → P3 → cursor=3 → P3 viable → return P3. ✓ no bug here.

  Third example (real edge): P1 viable, P2 viable, P3 viable. First call → returns P1 (cursor=1). P1 fails → marks cooldown. Second call → cursor=1 → P2 → cursor=2 → P2 viable → return P2. ✓.

  Fourth (concurrent): two `nextEndpoint` calls land at same time. Both enter while loop. First reads cursor=0, advances to 1, awaits cache (P1 not cooldown). Second enters while loop, reads cursor=1, advances to 2, awaits cache (P2 not cooldown). Both return distinct profiles. ✓ — this is the intended invariant.

  Fifth (the actual concern): one call enters, cursor=0, advances to 1, awaits cache (P1 IS cooldown), `continue`. Now cursor=1. Concurrently another caller enters, cursor=1, advances to 2, awaits cache (P2 viable), returns P2. First caller resumes its `while`, cursor=2, advances to 3, awaits cache (P3 viable? viable), returns P3. ✓ — but P2 was returned to caller B, P3 to caller A; that's fine semantically.

  After analysis the cursor-advance-before-await pattern is **correct under Swift actor semantics**. However the docstring claims «Single-pass semantics: iterates from cursor to end, returns first non-blocked profile.» — this is true per-call but not what a reader expects. A reader might expect that if cooldown expires between two `nextEndpoint` calls, the previously-skipped profile becomes eligible again. **It does not — `reset()` is required.**

- **Why MEDIUM (downgraded from initial HIGH):**
  Not a correctness bug per Swift actor model. But the documented contract is misleading — `nextEndpoint` consumes the profile chain monotonically, ignoring cooldown expiry mid-chain. With cooldown windows of 6-24h, a long-running app session could exhaust the entire chain in minutes during a flaky connectivity event, then refuse to retry P1 even after its cooldown lapses 6h later.

  ConfigImporter's `reset()` policy mitigates this — but I cannot verify the reset call pattern matches «after successful direct-connect» semantics without reading ConfigImporter (out of scope).

- **Suggested fix:**
  Either (a) Document the contract more precisely in the actor docstring: «`nextEndpoint` consumes the profile pool monotonically; expired cooldowns are NOT re-evaluated until `reset()` — caller must `reset()` periodically or after exhaustion.» Or (b) re-evaluate cooldowns lazily: on `nextEndpoint`, if `cursor == profiles.count` and we hit «exhausted», walk back through `profiles[0..<cursor]` and check `shouldSkip` for each — find first that is now ready, set cursor to it+1, return that profile.

  Option (b) is more user-friendly (transparent recovery). Out of v1.0 scope; (a) is the v1.0 cure.

### A6'-3-008: FrontingFailureCache score saturates at 10 — score cap silently changes cooldown semantics for hostile-CDN scenarios
- **Location:** `Packages/FrontingEngine/Sources/FrontingEngine/FrontingFailureCache.swift:67-69`
- **Dimension:** correctness / security
- **Description:**
  `let newScore = min(oldScore + 1, 10)` caps score at 10 to "prevent integer overflow" (per docstring at line 13). However the cooldown ladder maps score 1 → 6h, score 2-3 → 12h, score 4+ → 24h (default branch). The score-10 cap is therefore largely cosmetic: the ladder already saturates at score 4.

  BUT — the score is a Codable persistent value. A score-cap of 10 with a 4-step ladder means scores 4-10 all yield 24h. A malicious or buggy CDN provider could push score to exactly 10 and then any future failure recorded leaves score at 10. There is no monotonic decay; the only way to lower score is `recordSuccess` which sets to nil.

  Consequence: a CDN that flakes badly for 10+ attempts gets locked out for 24h on every cooldown cycle, with NO way to "earn back" trust short of a full success. After 10 fails, an admin who fixes the CDN can never get a successful connection because the cache still skips it for 24h, refresh cycle goes another 24h, etc. — feedback loop.

  Practical risk: scoring is per `<provider>|<ip>|<networkType>` key, so changing networks (wifi → cellular) resets to a different key. Mitigates the lockout in practice (user moves between networks).

- **Why MEDIUM:**
  Persistent state across app launches with no decay; admin recovery requires manual cache wipe. Low real-world impact for v1.0 (CDN fronting is opt-in, infrastructure-only — `extractFrontingProfile` returns nil pre-rollout) but a debt that will bite at Phase 11 activation.

- **Suggested fix:**
  Add cooldown ladder cap matching score cap: at score ≥ 4, cap cooldown at 24h (already implicit) but consider an explicit «retry every 6h regardless of score» fallback. Or: implement linear score decay on successful network change (`networkType` mismatch resets the cooldown for the new networkType — already happens naturally via the composite key; document explicitly).

  Or: lower the score cap to 5 to match the ladder's saturation point — clear semantic alignment.

### A6'-3-009: ImportHandler.canHandle host matching is case-sensitive in the Universal Link path — RFC 3986 says host is case-insensitive
- **Location:** `Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:36-54`
- **Dimension:** correctness
- **Description:**
  ```swift
  if scheme == "bbtb", url.host?.lowercased() == "import" { return true }
  if scheme == "https",
     url.host?.lowercased() == "import.bbtb.app",
     url.path == "/import" || url.path == "/import/" || url.path.hasPrefix("/import/") { ... }
  ```
  Host is lowercased; OK. But the **path** is compared with `==` and `hasPrefix` against literal `/import` — which is correct because path is case-sensitive per RFC 3986. ✓ for path.

  The case-sensitivity check on `url.path == "/import" || url.path == "/import/"` does NOT cover `url.path == "/IMPORT"` — but per RFC 3986 path is case-sensitive so this is correct behavior. ✓

  Real issue: `url.scheme?.lowercased()` is applied for the scheme (`bbtb` vs `BBTB`), which is correct (RFC 3986 § 3.1 schemes are case-insensitive, lowercased canonical). ✓

  Actually after re-reading there's no real bug here. Let me find a different issue:

  Closer look: the `canHandle` for `bbtb://import?url=…` works for any case combination since `url.scheme?.lowercased()` and `url.host?.lowercased()` both lowercased.

  BUT — `url.host` in `bbtb://IMPORT?url=...` may be `"IMPORT"` (host of custom-scheme URL). `URL(string: "bbtb://IMPORT?url=…").host` returns `"import"` lowercased by `URL` automatic canonicalization on iOS. So `.lowercased()` is defensive against the off-chance Foundation behavior differs across iOS versions. ✓ no bug.

  **Downgraded to LOW — see A6'-3-014 below.** Striking this finding from MEDIUM.

  (Keeping placeholder for finding numbering consistency.)

### A6'-3-010: DeepLinkRouter handlers registration is NOT idempotent — duplicate registrations stack
- **Location:** `Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift:71-76`
- **Dimension:** correctness
- **Description:**
  Docstring at line 67-70 explicitly says: «**Idempotency:** duplicate registrations НЕ блокируются». OK, that's intentional. But if a future contributor (or a test that re-uses the same router across multiple test cases) registers `ImportHandler` twice, both instances live in the list. `canHandle` will return true for both, `handle` will dispatch to the first registered (first-match wins).

  Concrete risk in v1.0: the App init wires ONE handler; not a runtime risk. But the testability bug — running multiple test cases that share a router via `static let` or DI singleton — silently passes (handler runs once, no observable error) but accumulates handlers, eventually exceeding registry threshold and slowing `handle` (linear scan).

- **Why MEDIUM:**
  Code hygiene; will bite Phase 11+ when adding `RemoteTokenFetchHandler` or other handlers. The «first-match wins» contract is sound but undiscoverable without reading the docstring.

- **Suggested fix:**
  Add a `register(_ handler:replacing:)` overload, or make `register` deduplicate by `identifier` (constant on `DeepLinkHandler`):
  ```swift
  public func register(_ handler: any DeepLinkHandler) {
      handlers.removeAll { type(of: $0).identifier == type(of: handler).identifier }
      handlers.append(handler)
      ...
  }
  ```
  Preserves order semantics (re-registration moves to end → lowest priority); avoids stacking.

### A6'-3-011: TransportRegistry uses NSLock for atomic dict access but `register/handler/registeredIdentifiers` could be an actor — Swift 6 mismatch with rest of codebase
- **Location:** `Packages/TransportRegistry/Sources/TransportRegistry/TransportRegistry.swift:10-30`
- **Dimension:** concurrency
- **Description:**
  `public final class TransportRegistry: @unchecked Sendable` with a manually-locked dict. Mirrors `ProtocolRegistry.shared` pattern (per docstring line 5-9), but the codebase otherwise embraces Swift actors (`FrontingFailureCache`, `FrontingFallbackChain`, `DeepLinkRouter`, `ProvisionSerializer`).

  No correctness issue: NSLock + `@unchecked Sendable` is sound. But the `register` method is called from multiple call sites at app init — if any of those call sites are themselves `async` (and most provisioning hooks are), the `lock()` + `defer unlock()` is a synchronous wait inside an `async` context, blocking the underlying thread.

  Actor-based registry would let `register` be async:
  ```swift
  public actor TransportRegistry {
      public static let shared = TransportRegistry()
      private var handlers: [String: any TransportHandler.Type] = [:]
      public func register<H: TransportHandler>(_ h: H.Type) { handlers[H.identifier] = h }
      ...
  }
  ```

- **Why MEDIUM:**
  Minor concurrency mismatch; current code is correct. Worth normalizing during a future codebase-wide Swift 6 audit.

- **Suggested fix:**
  Convert to actor; or leave with NSLock and add explicit `@_unavailable("Use async actor accessor")` markers. Not v1.0 priority.

---

## Low

### A6'-3-012: CustomDNSField duplicates `looksLikeIPv4` / `isValidIPv4` / `isValidHostname` from SettingsViewModel — intentional but maintenance hazard
- **Location:**
  - `Packages/AppFeatures/Sources/SettingsFeature/CustomDNSField.swift:66-110` (static helpers)
  - `Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:260-307` (private helpers)
- **Dimension:** maintainability
- **Description:**
  Both files implement byte-identical helpers. CustomDNSField docstring at line 63-64 acknowledges «intentionally duplicated to keep this view standalone — both layers validate per Pitfall 9».

  Risk: future fix to one (e.g. IPv6 acceptance, IDN handling, expanded RFC 1123 subset) won't propagate to the other. Today the implementations match; tomorrow they will drift.

- **Suggested fix:**
  Extract to a shared `DNSAddressValidator` enum in a small `Localization` adjacent module (already imported by both files), or a new `DNSValidation` module. Minimal cost; one-time fix.

### A6'-3-013: DiagnosticsExporter.anonymousDeviceID race on first-launch parallel access
- **Location:** `Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:175-182`
- **Dimension:** concurrency
- **Description:**
  ```swift
  internal static func anonymousDeviceID() -> String {
      if let existing = UserDefaults.standard.string(forKey: anonymousDeviceIDKey) {
          return existing
      }
      let new = UUID().uuidString
      UserDefaults.standard.set(new, forKey: anonymousDeviceIDKey)
      return new
  }
  ```
  If two callers race on first-launch (DiagnosticsSection on AppearTask + a hypothetical other reader), both can pass the `if let` check returning nil, both generate distinct UUIDs, both write — last writer wins, first writer's UUID-stamped log already shipped. Minor: anonymous device ID intended as «недавняя серия экспортов одного пользователя» per docstring; pair of disagreeing logs is annoying not catastrophic.

- **Suggested fix:**
  Wrap in `os_unfair_lock` or move to an actor; or use `UserDefaults.standard.register(defaults:)` with a sentinel and generate on first read using `dispatch_once`-like pattern. Trivial.

### A6'-3-014: ImportHandler scheme/host comparison correctness review pass — minor robustness suggestions
- **Location:** `Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:37-54`
- **Dimension:** correctness
- **Description:**
  Per-RFC compliance check on `ImportHandler.canHandle`:
  - Scheme `bbtb` / `https` compared after `lowercased()` ✓
  - Host `import` / `import.bbtb.app` compared after `lowercased()` ✓
  - Path `/import` / `/import/` / `hasPrefix("/import/")` compared case-sensitively ✓ (RFC 3986 § 3.3 path is case-sensitive)

  Remaining nit: `url.host?.lowercased() == "import"` will reject `bbtb://import.example.com/import?url=…` correctly because `host` is `import.example.com` not `import`. ✓

  Tighter check would be to compare on `URLComponents` instead of `URL`, but `URL.host` is well-defined. No functional issue.

- **Suggested fix:**
  None required; flagged for documentation that case-sensitivity intent is explicit.

### A6'-3-015: FrontingProfile init has no validation — invalid combinations accepted then rejected late
- **Location:** `Packages/FrontingEngine/Sources/FrontingEngine/FrontingProfile.swift:78-92`
- **Dimension:** correctness
- **Description:**
  `FrontingProfile(provider:connectHost:connectPort:sniHost:httpHost:mode:)` accepts any string values. `validateProfile` in `FrontingConfigApplier.swift:132-143` checks SSRF + port range. The init itself does no checks:
  - Empty `connectHost` accepted → `validateProfile` rejects via `isPrivateOrLoopback("")` returning true ✓
  - `connectPort = 0` accepted → `validateProfile` rejects via range check ✓
  - But `sniHost` and `httpHost` empty strings are accepted by validate (only `connectHost` checked against private/loopback, but actually all three hosts ARE checked by `validateProfile.hosts = [connectHost, sniHost, httpHost]` — empty hosts pass `isPrivateOrLoopback` returning true at line 154). ✓

  So validate catches these. But the layered design (init permissive, validate strict) means consumers may build a profile, store it, then late-fail at JSON apply time. Defensible. Worth a `validate()` instance method on FrontingProfile itself for consumers who want early failure.

- **Suggested fix:**
  Add `public func validate() throws` to `FrontingProfile`, delegating to `FrontingConfigApplier.validateProfile`. Lets callers fail fast.

### A6'-3-016: ServerListViewModel.silentForegroundRefresh doesn't reset subscriptionFetchErrors — stale errors carry across silent refreshes
- **Location:** `Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:294-318`
- **Dimension:** correctness
- **Description:**
  `pullToRefresh` (line 248-289) clears `subscriptionFetchErrors = [:]` at line 250 before fetching. `silentForegroundRefresh` (line 294-318) does NOT clear it. Errors from a previous failed pull-to-refresh persist as inline error badges on SubscriptionHeader even after a subsequent silent refresh succeeds.

  Concrete scenario: user pulls to refresh, subscription URL fails → `subscriptionFetchErrors[sub.id] = "Network timeout"` → red triangle on SubscriptionHeader. Network recovers → user backgrounds the app → returns → `silentForegroundRefresh` succeeds silently → red triangle persists because `subscriptionFetchErrors` is not cleared.

- **Why LOW:**
  UI annoyance; user can pull-to-refresh manually to clear. Not data correctness.

- **Suggested fix:**
  Clear `subscriptionFetchErrors[sub.id] = nil` on success path inside the `for sub in subscriptions` loop in `silentForegroundRefresh`. Per-subscription clearing avoids wiping pending errors from other subscriptions.

### A6'-3-017: SettingsViewModel deinit comment says cleanup at process termination is automatic — incorrect for Timer
- **Location:** `Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:179-188`
- **Dimension:** correctness / docs
- **Description:**
  Comment: «Observer token: SwiftUI .ObservedObject lifetimes гарантируют VM живёт пока View on-screen; cleanup at process termination automatic.»

  Actually:
  - `NotificationCenter` observer registered via `addObserver(forName:object:queue:using:)` returns a token; the system retains it until removed. Process termination automatically tears down the NotificationCenter; OK.
  - `Timer` scheduled on the main run loop is retained by the run loop. Process termination automatically tears down the run loop; OK.

  Both are correct, BUT the timer continues to fire while the VM is dealloc'd-but-not-teardown'd (rare; SwiftUI keeps VM alive while view on-screen). The 1Hz Timer fire calls `cooldownTick()` via `Task { @MainActor [weak self] in self?.cooldownTick() }` which returns early on `self == nil`. So the cycle is benign — a zombie timer firing into the void.

- **Suggested fix:**
  Rewrite the comment to say: «Timer invalidate() done in `teardown()`. If `teardown()` not called, timer survives until run loop teardown — `[weak self]` capture ensures no retain cycle but timer keeps firing at 1Hz until process exit.»

### A6'-3-018: FrontingFailureCache.persist() best-effort silent failure — disk-full disables fronting cache without log
- **Location:** `Packages/FrontingEngine/Sources/FrontingEngine/FrontingFailureCache.swift:103-108`
- **Dimension:** observability
- **Description:**
  `try? data.write(to: cacheURL, options: .atomic)` swallows ALL errors including disk-full, sandbox container locked, parent directory missing. The actor's «best-effort persistence» contract is sound, but with no log, ops have no visibility into a degraded cache state.

  Phase 10 v0.10 mitigates: CDN fronting is gated by `cdnFrontingEnabled = false` default + `extractFrontingProfile == nil` infrastructure stub. So persist is rarely called in v1.0. Phase 11 activation will surface this gap.

- **Suggested fix:**
  Add `os.Logger` warning on write failure. Keep `try?` semantics (don't propagate); just log.

### A6'-3-019: DiagnosticsExporter.prepareLog uses `String.suffix` on potentially-binary content — UTF-8 decode failure returns nil
- **Location:** `Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:62-67`
- **Dimension:** correctness
- **Description:**
  `try String(contentsOfFile: logPath, encoding: .utf8)` — if sing-box ever writes non-UTF-8 bytes (corrupted byte mid-line, libbox raw bytes leaking through, or filesystem corruption), the read throws. Caller returns nil, alert shows «Нет данных» — misleading for «file exists but unreadable» case.

  Lesser concern: the entire file is loaded into memory before `suffix(tailByteCap)` — for 100MB+ sing-box logs this is wasteful. Could `seek` to last 2MB and read only that.

- **Suggested fix:**
  Differentiate «missing» vs «unreadable»: separate `.alert` cases. Use `FileHandle` + `seek(toOffset:)` for memory efficiency.

### A6'-3-020: ServerListViewModel.refreshError L10n key is generic — used for both subscription fetch + ping persist
- **Location:** `Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:271,476`
- **Dimension:** UX
- **Description:**
  Same L10n key `serverListRefreshErrorMessage` used by `pullToRefresh` (subscription fetch all-failed) and `pingAllServers` (SwiftData save failed). Different root causes, same user-facing copy. User cannot distinguish.

- **Suggested fix:**
  Add `L10n.serverListPingSaveError` etc. Tie key to the cause.

### A6'-3-021: DeepLinkError.invalidParameterValue reason field can leak unsanitized user input through L10n format
- **Location:** `Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift:36, 61` + `Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:67-79`
- **Dimension:** security / docs
- **Description:**
  `throw DeepLinkError.invalidParameterValue(name: "url", reason: "не URL")` — current call sites pass static Russian strings. The L10n format `L10n.deepLinkErrorInvalidParameter(name:reason:)` substitutes both into a user-facing alert. If a future call site passes the offending URL or raw input as `reason`, that string surfaces in the alert with no escaping or truncation — potential for `\n` injection, RTL char abuse, or long-string DoS to the SwiftUI Text rendering.

  v0.13 call sites are clean; flagging for future hygiene.

- **Suggested fix:**
  Add `Codable` + length cap on `reason` field. Or constrain to a fixed enum of `enum InvalidParameterReason: String { case notAURL, doubleEncoded, ... }` rather than free-form String.

### A6'-3-022: KillSwitch.platformShouldDisableEnforceRoutes uses `nonisolated(unsafe) var` accessing UserDefaults on macOS — could miss App Group setup race
- **Location:** `Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:63-70`
- **Dimension:** concurrency
- **Description:**
  ```swift
  public static func platformShouldDisableEnforceRoutes() -> Bool {
      #if os(macOS)
      let defaults = UserDefaults(suiteName: appGroupSuiteName)
      return defaults?.bool(forKey: "app.bbtb.macOSDisableEnforceRoutes") ?? false
      #else
      return false
      #endif
  }
  ```
  On macOS, called from `KillSwitch.apply(to:enabled:)` which runs at provision time. If App Group entitlement is misconfigured, `UserDefaults(suiteName:)` returns nil and `?? false` defaults to «enforceRoutes ON» — safer default per R4 invariant. ✓ defensive.

  If user sets `macOSDisableEnforceRoutes = true` in UI and immediately taps Connect, the @AppStorage write on MainActor must flush before KillSwitch.apply reads. `@AppStorage` writes are synchronous to the underlying UserDefaults (verified Apple docs), but the `suiteName` lookup goes through a different defaults instance — and CFPreferences cache coherence between two `UserDefaults(suiteName: same)` instances within the same process is generally fine but not formally guaranteed. Unlikely race.

- **Suggested fix:**
  Add a `UserDefaults.standard.synchronize()` (deprecated but functional) or use `UserDefaults(suiteName:)` static singleton instead of creating a fresh defaults object on each call. Negligible perf gain, but tightens the read contract.

### A6'-3-023: ForceUpdateRulesButton handleTap haptic fires before VM `triggerForceUpdate` early-return guard
- **Location:** `Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift:97-104` + `SettingsViewModel.swift:460-461`
- **Dimension:** UX
- **Description:**
  ```swift
  private func handleTap() {
      guard buttonState == .idle else { return }
      #if canImport(UIKit) && os(iOS)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      #endif
      onTap()
  }
  ```
  Local guard `buttonState == .idle` checks state, fires haptic, calls `onTap()`. Then `triggerForceUpdate` in VM re-checks `forceUpdateButtonState == .idle`. Both checks pass simultaneously typically. But if a race: the VM-side guard would catch double-taps that bypass the view-side guard (e.g. accessibility tap + actual tap landing in the same frame). In that race, the haptic fires twice but only one update goes through.

  Minor — haptic-without-action is a small UX wart.

- **Suggested fix:**
  Move haptic into `triggerForceUpdate` after the guard passes, hop back to MainActor for UIKit call. Or accept the double-haptic edge case.

### A6'-3-024: TUIC ConfigBuilder hardcodes `zero_rtt_handshake: false` and `heartbeat: "10s"` — no override pathway documented
- **Location:** `Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift:55-56`
- **Dimension:** correctness / docs
- **Description:**
  Hardcoded values in dict literal:
  ```swift
  "zero_rtt_handshake": false,
  "heartbeat": "10s",
  ```
  Comments don't explain rationale. TUIC v5 spec allows tuning both. URI parser likely doesn't expose them — verifiable by reading TUIC URI parser (out of scope). Server-driven config can't override unless the URI parser surfaces these as fields in `ParsedTUIC`.

  Probably correct for v1.0 (zero-RTT off = safer for TLS), but worth a code comment.

- **Suggested fix:**
  Add `// Phase 7a security default: 0-RTT replay protection requires per-server tuning; default off (sing-box recommended baseline). To customize, surface via URI parameter in future TUIC parser.`

### A6'-3-025: RulesViewerSection.expandedContent uses `LazyVStack` inside DisclosureGroup body — Form may force-eager-render
- **Location:** `Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift:208-228`
- **Dimension:** performance
- **Description:**
  RulesViewer claims «LazyVStack для 10K+ entries scrolling» (line 216). But the parent context is a SwiftUI `Form` → `Section` → `RuleCategoryGroup` → `DisclosureGroup` → `LazyVStack`. Forms on iOS internally use `UITableView` and may force eager layout of all content when computing `Section` height — Apple's behavior here is undocumented but well-known to force-render lazy content inside Forms on iOS 17+.

  Concrete consequence: 10K domain entries inside an expanded disclosure could spike memory and freeze the Form scroll on expand. Test before TestFlight with a realistic large baseline rules snapshot (RulesEngine baseline has ~10K domains per spec).

- **Suggested fix:**
  Replace `LazyVStack` with `ScrollView` + `LazyVStack` (still inside DisclosureGroup but with explicit scroll containment) → forces lazy semantics. Or use UITableView-like collection: cap visible entries at 100 with "+9900 more" pagination. Latter is more user-friendly.

---

## Summary

24 findings (0 C / 1 H / 9 M / 14 L) across ~50 files.

**Headline H finding** is `A6'-3-001` ServerDetailViewModel transport persistence UI/store divergence — silent failure can mislead user about transport selection. Recommend fix before TestFlight.

**Notable observations:**
- T-B6' tag-scoped fronting apply: **CONFIRMED CLOSED** structurally and at caller site.
- T-C7' force-reload after mutations: **CONFIRMED CLOSED** in `loadFromStore(force:)`.
- C7'-003 drift-risk ACK in `FrontingConfigApplier.isPrivateOrLoopback`: properly documented; no LOW spawn.
- Phase 13 D-04 routing rules gate (extension reads `app.bbtb.routingRulesEnabled` from App Group suite): wiring verified end-to-end.
- 6× protocol packages: post-T-A2 docstring drift across 3 protocols (A6'-3-005) — cosmetic but worth cleanup.
- KillSwitch: trivial `var → let` fix (A6'-3-006).
- FrontingEngine: actor reentrancy mitigation is correct but documentation misleading (A6'-3-007); failure cache score-cap semantic mismatch (A6'-3-008).
- DeepLinks: handler registration not idempotent (A6'-3-010), error reason field potentially user-input-tainted (A6'-3-021).

**No CRITICAL findings in scope.** Wave 1 HIGH-risk reviewers carry the C-tier verification burden; this MEDIUM sweep finds no regressions in Plan 05 closures.

**Recommendation:** A6'-3-001 should be addressed pre-TestFlight (UI/store divergence on transport selection is user-visible inconsistency). Remaining 23 findings can defer to v1.0.1 polish pass.
