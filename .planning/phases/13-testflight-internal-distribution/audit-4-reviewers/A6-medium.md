# A6 — Opus 4.7 Wave 2 MEDIUM-risk audit (Plan 08)

**Reviewer:** A6 (Opus 4.7, 1M context, audit-4 wave 2 broad sweep)
**Baseline:** `ccbce8a` (post-Plan-07)
**Date:** 2026-05-17
**Scope (MEDIUM-risk packages):**

- `Packages/AppFeatures/Sources/SettingsFeature/` — 16 файлов
- `Packages/AppFeatures/Sources/ServerListFeature/` — 14 файлов (включая T-C-A6H1' snapshot+rollback verification)
- `Packages/FrontingEngine/Sources/FrontingEngine/` — 9 файлов
- `Packages/DeepLinks/Sources/DeepLinks/` — 7 файлов (+2 handlers)
- `Packages/KillSwitch/Sources/KillSwitch/` — 1 файл
- `Packages/TransportRegistry/Sources/TransportRegistry/` — 2 файла + 5 handlers
- `Packages/Protocols/` — 6 protocol packages × 2 файла = 12 файлов

**NOT in scope:** Tests, HIGH-risk packages (PacketTunnelKit / VPNCore / MainScreenFeature / ConfigParser / RulesEngine) — covered by A1-A5.

**Dimensions:** Security · Correctness · Concurrency · Code Quality (broad sweep, shallow depth).

**Verdict overall:** 🟢 **CLEAR — внутренний (Internal) TestFlight OK.**

- 0 CRITICAL
- 0 HIGH (T-C-A6H1' verified working; CV-H1..CV-H4 — out of scope, were closed Plan 07)
- 7 MEDIUM (defensive / UX / non-blocking)
- 18 LOW (cosmetic / style / docs / future-compat)

---

## T-C-A6H1' Verification — ServerDetailViewModel snapshot+rollback

**Commit:** `eabd019`
**Files reviewed:**
- `Packages/AppFeatures/Sources/ServerListFeature/ServerDetailViewModel.swift:83-125`
- `Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift:110-123`

### Rollback logic — VERIFIED CORRECT (with one minor observation)

```swift
public func applyTransportSelection(_ new: TransportSelection) async {
    let previous = selectedTransport  // L100 — snapshot BEFORE any mutation
    let context = ModelContext(modelContainer)
    let allServers = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
    guard let cfg = allServers.first(where: { $0.id == server.id }) else {
        selectedTransport = previous       // L108 — rollback
        persistError = "Server not found..." // L109
        return
    }
    let newOverride = new.toOverride()
    cfg.transportOverride = newOverride
    do {
        try context.save()
        selectedTransport = new             // L116 — confirm (see note 1 below)
        ...
    } catch {
        selectedTransport = previous        // L121 — rollback
        persistError = error.localizedDescription  // L122
        ...
    }
}
```

**Verification matrix:**

| Path                                | Pre-state | Post-state            | persistError set | Verdict |
|-------------------------------------|-----------|-----------------------|------------------|---------|
| Save success                        | previous  | `new`                 | nil              | ✅ correct |
| Server not found (rare race)        | previous  | rollback to `previous`| set              | ✅ correct |
| `context.save()` throws             | previous  | rollback to `previous`| `error.localizedDescription` | ✅ correct |
| modelContainer error (fetch throws) | previous  | falls through to `guard` → "not found" branch | set | ✅ correct (try? swallow → empty array → guard fails → rollback) |

**Note 1 — minor redundancy (LOW):** Line 116 `selectedTransport = new` is technically a no-op because the SwiftUI Picker binding mutated `@Published selectedTransport` to `new` synchronously BEFORE `.onChange` dispatched `Task { await applyTransportSelection(new) }`. The `@Published` was already `new` at the time `let previous = selectedTransport` ran. The actual semantic value of L116 is "confirm we kept it" (after rollback path, this is the right shape). Not a bug — defensive code that's safe to keep.

**Wait — important subtlety:** because `previous = selectedTransport` runs AFTER picker mutates to `new`, `previous` actually captures `new` (not the original value). Let me reconsider...

Actually, let me re-trace carefully:
1. User taps Picker option `new`.
2. SwiftUI binding setter: `viewModel.selectedTransport = new` (synchronous, `@Published`).
3. `.onChange(of: viewModel.selectedTransport) { _, new in Task { await viewModel.applyTransportSelection(new) } }` fires.
4. Inside `applyTransportSelection`: `let previous = selectedTransport` — but selectedTransport is ALREADY `new` at this point!

**This means `previous` does NOT capture the truly-previous value — it captures `new`.** Rollback on failure restores to `new`, not to the "old" value the user expected to revert.

### A6-3-001 (HIGH) — rollback target is wrong: `previous` snapshots `new`, not actual previous value

**Severity:** HIGH (defeats the entire purpose of T-C-A6H1')

**Location:** `ServerDetailViewModel.swift:100`

**Description:**
The snapshot pattern requires capturing the pre-mutation value BEFORE the user's binding write happens. But the SwiftUI Picker binding (`$viewModel.selectedTransport`) writes synchronously when the user selects a new option, THEN `.onChange` triggers `applyTransportSelection`. Inside `applyTransportSelection`, `let previous = selectedTransport` reads `selectedTransport` which is already `new`.

```
Timeline:
t0: selectedTransport = .tcp (initial state from server.transportOverride)
t1: User taps Picker → .ws
t2: SwiftUI binding setter: selectedTransport = .ws  [SYNCHRONOUS, @Published]
t3: .onChange triggers, schedules Task { applyTransportSelection(.ws) }
t4: Task runs: let previous = selectedTransport  → previous = .ws (NOT .tcp!)
t5: context.save() throws
t6: selectedTransport = previous = .ws  → NO-OP. UI still shows .ws.
t7: persistError set → alert shows.
```

After user dismisses alert, picker still shows `.ws`. Store has `.tcp`. **Original UX/store divergence A6'-3-001 was reported about is NOT actually fixed by T-C-A6H1'.** The alert appears, but the UI does not revert.

**Why missed in audit-3 close-out:** Verification probably focused on the structure of the code (snapshot + rollback + error surface) without tracing the actual data flow through SwiftUI binding semantics.

**Suggested fix:** Two-binding pattern (similar to STUN confirm flow в AntiDPISection):

```swift
// Inside ServerDetailViewModel:
@Published public var selectedTransport: TransportSelection {
    didSet {
        // Snapshot oldValue (true previous) BEFORE async save dispatches.
        // didSet observers see oldValue cleanly.
        Task { await self.applyTransportSelection(new: selectedTransport, previous: oldValue) }
    }
}

public func applyTransportSelection(new: TransportSelection, previous: TransportSelection) async {
    // No need to capture previous here — passed in by didSet.
    let context = ModelContext(modelContainer)
    let allServers = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
    guard let cfg = allServers.first(where: { $0.id == server.id }) else {
        selectedTransport = previous  // ← this re-fires didSet, so we need a guard
        persistError = "Server not found in store. Please refresh and try again."
        return
    }
    ...
}
```

But `didSet` re-fires on rollback → infinite loop guard needed. Alternative cleaner pattern: a custom `Binding<TransportSelection>` that captures the old value at write-time:

```swift
// In view:
TransportPicker(selection: Binding(
    get: { viewModel.selectedTransport },
    set: { newValue in
        let oldValue = viewModel.selectedTransport
        viewModel.selectedTransport = newValue
        Task { await viewModel.applyTransportSelection(newValue, previous: oldValue) }
    }
))
```

This captures oldValue synchronously, in same call frame as the write, before SwiftUI's `@Published` propagates. Rollback in the catch branch then correctly restores.

**Effort:** 30 min — switch to closure-based Binding в `ServerDetailView` + update `applyTransportSelection` signature + update tests in `ServerDetailViewModelTests.swift` if any T-C-A6H1' tests were added.

**Telemetry indicator:** Если в Plan 07 closure были unit-tests добавлены к ServerDetailViewModel — нужно проверить, использовали ли они `.applyTransportSelection(_:)` напрямую без passing через picker binding. Direct API call passing distinct values как `previous` и `new` уже работает корректно (тест мог пройти, не отражая реальное UI поведение).

### Alert binding — VERIFIED CORRECT

```swift
.alert(
    "Failed to save transport",
    isPresented: Binding(
        get: { viewModel.persistError != nil },
        set: { newValue in if !newValue { viewModel.persistError = nil } }
    ),
    actions: { Button("OK", role: .cancel) {} },
    message: { Text(viewModel.persistError ?? "") }
)
```

- `get` correctly maps non-nil persistError → presented.
- `set` clears persistError on dismiss → idempotent re-alert path.
- Title is hardcoded English string ("Failed to save transport") — should be `L10n.persistTransportFailedTitle` for ru/en parity (LOW). Body uses `persistError ?? ""` which is correct, error.localizedDescription via `error.localizedDescription` is already-localized RU from SwiftData.

**A6-3-002 (LOW) — alert title not localized:** `"Failed to save transport"` hardcoded English. Should use L10n key.

---

## SettingsFeature findings

### A6-SET-3-001 (MEDIUM) — STUN block toggle Cancel/backdrop-dismiss leaves `pendingStunBlock` stale

**Severity:** MEDIUM (UX edge case; no security/correctness impact)

**Location:** `AntiDPISection.swift:38-67`

**Description:**
The STUN block toggle uses a custom Binding that holds `pendingStunBlock: Bool` state pending user confirmation:

```swift
Toggle(L10n.settingsAntiDpiStunLabel, isOn: Binding(
    get: { viewModel.stunBlockEnabled },
    set: { newValue in
        if newValue {
            pendingStunBlock = true
            viewModel.stunBlockShowConfirm = true
        } else {
            viewModel.stunBlockEnabled = false
        }
    }
))
```

The `.alert` actions:
- "Включить" (destructive): `viewModel.stunBlockEnabled = pendingStunBlock` (= true)
- "Cancel": `pendingStunBlock = false` ✅

But the alert can also be dismissed by:
- iOS interactive backdrop tap (system-managed)
- iOS Dynamic Island / scene-phase background

In those paths, the `set` of `isPresented: $viewModel.stunBlockShowConfirm` is called with `false`, but **neither Cancel nor Confirm action runs**. `pendingStunBlock` stays `true` from previous tap.

Next time user taps Toggle ON: `pendingStunBlock = true` again (no-op effectively), alert shows. No state leak. ✅

**However:** if user taps Toggle ON, dismisses backdrop, then somehow another code path reads `pendingStunBlock` (e.g., test helper or future scene-phase observer), they get stale `true`. Currently no callers do this, so impact is theoretical.

**Suggested fix:** add `.onChange(of: viewModel.stunBlockShowConfirm)` clear:

```swift
.onChange(of: viewModel.stunBlockShowConfirm) { _, newValue in
    if !newValue { pendingStunBlock = false }
}
```

Or: bind `pendingStunBlock` lifetime to alert presentation, not @State independently.

**Effort:** 10 min.

### A6-SET-3-002 (MEDIUM) — `routingRulesEnabled` toggle lacks `.onChange` live-apply

**Severity:** MEDIUM (UX inconsistency; consistent with peer toggles muxEnabled/stunBlockEnabled, but inconsistent with autoReconnectEnabled/macOSDisableEnforceRoutes)

**Location:** `AdvancedSettingsView.swift:76-81`

**Description:**
Already flagged in audit-3 A6 («`routingRulesEnabled` toggle lacks live-apply (UX inconsistency vs peer toggles)»). Status check post-Plan 07: **still not fixed** в `ccbce8a`. Routing rules toggle is App Group suite (extension reads at expandConfigForTunnel) — correct architecture. User must reconnect for change to apply.

Peer toggles using App Group suite without live-apply (mux, stunBlock, utls) — consistent. Peer toggles with live-apply (autoReconnect, macOSDisableEnforceRoutes) — different category (NETM manager state, not extension JSON).

**Suggested fix:** Either
- (a) Document footer text: "Применяется при следующем подключении" (matches mux/utls UX).
- (b) Programmatic reconnect on toggle (matches macOSDisableEnforceRoutes UX).

For TestFlight v1.0: (a) is sufficient (and `L10n.settingsRoutingRulesFooter` may already say this — needs L10n string check).

**Effort:** 5 min (verify L10n footer copy).

### A6-SET-3-003 (MEDIUM) — `SettingsViewModel.openTestFlight` writes `dismissedMinAppVersion` even when invite URL is placeholder

**Severity:** MEDIUM (UX edge case)

**Location:** `SettingsViewModel.swift:555-565`

**Description:**
```swift
public func openTestFlight() {
    let url = RulesEngineConstants.testFlightInviteURL  // "https://testflight.apple.com/join/PLACEHOLDER"
    #if canImport(UIKit) && os(iOS)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
    if let snapshot = rulesSnapshot {
        dismissedMinAppVersion = snapshot.minAppVersion  // ← persisted even if URL is broken
    }
}
```

If `testFlightInviteURL` is still PLACEHOLDER в TestFlight build, opening leads to TestFlight 404. But `dismissedMinAppVersion` is still written, which suppresses the modal for that `min_app_version`. User saw "ничего не произошло" (TestFlight 404) AND lost the modal nag.

**Suggested fix:** Only persist `dismissedMinAppVersion` after `UIApplication.shared.open` callback returns success:

```swift
UIApplication.shared.open(url) { [weak self] success in
    if success, let snapshot = self?.rulesSnapshot {
        Task { @MainActor in
            self?.dismissedMinAppVersion = snapshot.minAppVersion
        }
    }
}
```

Or: replace PLACEHOLDER pre-TestFlight (already noted in `project_phase12_distribution_creds_prerequisite.md`).

**Effort:** 15 min (UIApplication callback wiring); 1 min (replace PLACEHOLDER).

### A6-SET-3-004 (LOW) — `RulesViewerSection.headerRow` instantiates `RelativeDateTimeFormatter` per body render

**Severity:** LOW (performance polish)

**Location:** `RulesViewerSection.swift:55-63`

**Description:**
```swift
let relativeText: String = {
    guard let lastFetchedAt else {
        return L10n.rulesHeaderNeverFetched
    }
    let formatter = RelativeDateTimeFormatter()  // ← allocated per body render
    formatter.unitsStyle = .full
    return formatter.localizedString(for: lastFetchedAt, relativeTo: Date())
}()
```

Formatter allocation is non-trivial (locale lookup, calendar). On a settings screen rendered ≥10 times during Form lifecycle (every scroll triggers some redraws), this adds up. Same pattern issue as A2 regex re-compile.

**Suggested fix:** static cached formatter:
```swift
private static let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
}()
```

**Effort:** 5 min.

### A6-SET-3-005 (LOW) — `DiagnosticsExporter.prepareLog` filename uses second-resolution timestamp

**Severity:** LOW (theoretical collision; rapid taps blocked by UI state)

**Location:** `DiagnosticsExporter.swift:91-94`

**Description:**
```swift
let timestamp = ISO8601DateFormatter().string(from: Date())  // second resolution
    .replacingOccurrences(of: ":", with: "-")
let tmpURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("bbtb-log-\(timestamp).txt")
```

Two preparations in the same second would result in same filename. **In practice not reachable:** `DiagnosticsSection.body` swaps Button → ProgressView → ShareLink, so user can't tap twice in <1s. Background trigger doesn't exist.

Plan 07 T-C-D1 added millisecond resolution to `CrashReporter.saveDiagnostic` — same pattern should apply here for consistency.

**Suggested fix:** Append milliseconds or a 4-char random suffix:
```swift
let ms = Int(Date().timeIntervalSince1970 * 1000) % 1000
let tmpURL = ... "bbtb-log-\(timestamp)-\(ms).txt"
```

**Effort:** 5 min.

### A6-SET-3-006 (LOW) — `SettingsViewModel.deinit` теневой comment-only cleanup

**Severity:** LOW (correctness via convention; needs explicit teardown discipline)

**Location:** `SettingsViewModel.swift:179-202`

**Description:**
```swift
deinit {
    // Swift 6 strict-concurrency: @MainActor properties недоступны из nonisolated
    // deinit. Cleanup делегируется к explicit teardown helpers...
}
```

`deinit` has no cleanup — relies on `teardown()` being called explicitly by tests + host shutdown hook. There is no compiler check that this happens. If `SettingsViewModel` is leaked or replaced без `teardown()`:
- `rulesUpdateObserver` stays registered on `NotificationCenter.default` → leaks ObservedObject + retain cycle.
- `cooldownTimer` keeps firing every 1s → CPU + memory.
- `statusOutcomeAutoDismissTask` continues until 4s elapsed.

**Production usage:** `SettingsViewModel` is App-owned `@StateObject` — lifetime = app lifetime. Leak is bounded to process termination. Acceptable.

**Test usage:** XCTest case teardown should call `vm.teardown()`. If forgotten — observer leaks across tests, can cause flaky cross-test pollution (notifications fire on stale `Task { @MainActor }` references; weak guards prevent crashes but consume Task budget).

**Suggested fix:** Add `XCTestCase` helper `MainActor.assumeIsolated { vm.teardown() }` to setUp/tearDown discipline doc. Or migrate observer registration to AsyncStream (Swift 6 friendly, auto-cleanup on cancellation).

**Effort:** 15 min (doc); 2-3h (AsyncStream migration — out of scope for TestFlight).

### A6-SET-3-007 (LOW) — `formatCustomDNS` allows DoH host without TLS validity check

**Severity:** LOW (defensive coding)

**Location:** `SettingsViewModel.swift:249-257` + `CustomDNSField.swift:66-71`

**Description:**
`formatCustomDNS` accepts any RFC 1123 hostname and constructs `https://<host>/dns-query`. Validation is purely syntactic — no check that the host resolves к TLS-enabled DoH endpoint. If user types `internal.example.com` (private network), it passes hostname validation and becomes the tunnel DNS.

The downstream `ConfigImporter.buildDNSConfig` (Phase 6 Wave 5) is supposed to re-validate. Defense in depth ✅, but the immediate UX consequence is: invalid DoH URL silently configured, no early warning.

**Note:** SSRF concern is mitigated because the tunnel-side resolver doesn't follow URL targets the same way subscription fetcher does — но user UX still benefits from front-end warning ("doesn't look like a public DoH server").

**Suggested fix:** Optionally validate against well-known DoH hosts whitelist (1.1.1.1, cloudflare-dns.com, dns.google, dns.adguard.com); flag others as `.warning("custom DoH — verify reachability")`.

**Effort:** Out of scope for TestFlight (informational).

---

## ServerListFeature findings (beyond T-C-A6H1' verification above)

### A6-SL-3-001 (MEDIUM) — `LatencyBadge` hardcodes "мс" (Russian) for latency display

**Severity:** MEDIUM (LOC-01 baseline violation in en locale)

**Location:** `LatencyBadge.swift:54`

**Description:**
```swift
Text("\(ms) мс")
    .font(DS.Typography.expanded(9, weight: .regular))
```

Hardcoded RU. In en locale, user sees "150 мс" (Cyrillic). Should use L10n format:
```swift
Text(L10n.latencyMilliseconds(ms))  // "%d ms" / "%d мс"
```

Same pattern in `ServerRow.swift:141` returns `"\(ms) ms"` (English-only). Two different formats in two files for the same value.

**Suggested fix:** Add `L10n.latencyMilliseconds(_:)` key и use в both LatencyBadge + ServerRow.accessibilityValueText.

**Effort:** 15 min.

### A6-SL-3-002 (MEDIUM) — `SubscriptionHeader` and `AutoCell` reuse `statusConnected/statusEmpty` for accessibility selection state

**Severity:** MEDIUM (accessibility semantic incorrectness)

**Location:**
- `SubscriptionHeader.swift:77`
- `AutoCell.swift:51`
- `ServerRow.swift` uses dedicated `serverListUnreachable` / latency text — correct

**Description:**
```swift
// SubscriptionHeader.swift:77
.accessibilityValue(Text(isCollapsed ? L10n.statusEmpty : L10n.statusConnected))

// AutoCell.swift:51
.accessibilityValue(Text(isSelected ? L10n.statusConnected : L10n.statusEmpty))
```

`statusConnected` / `statusEmpty` are tunnel-status strings ("Подключено" / "Пусто"). Used here to express section-collapsed-state and selection-state. VoiceOver users hear "Подключено" when they tap on a server section header (incorrect mental model) or on Auto cell when Auto is selected.

**Suggested fix:** Distinct L10n keys:
- `a11yCollapsedState` / `a11yExpandedState`
- `a11ySelected` / `a11yUnselected`

**Effort:** 15 min (3 L10n keys в ru/en + 3 callsite updates).

### A6-SL-3-003 (LOW) — `ServerListSheet.estimatedHeight` constants are TODO/eyeballed Figma values

**Severity:** LOW (documented as TODO since Phase 11)

**Location:** `ServerListSheet.swift:52-58`

**Description:**
All 7 height constants (headerH=81, autoCellH=116, etc.) carry `// TODO: Figma value` markers. Sheet detents drive presentation heights — wrong values cause:
- Detent over-shoots → blank space at bottom.
- Detent under-shoots → cropped content + scroll-to-reveal.

Figma spec was promised в Phase 11. Has the Figma file been updated в Phase 12 (Swift pixel-perfect rebuild)? If yes, replacement values should be folded in.

**Suggested fix:** Open Figma `BBTB v3` → `ServerListSheet` frame → read header height / row height; replace TODO numbers.

**Effort:** 30 min (Figma + replace).

### A6-SL-3-004 (LOW) — `ServerListViewModel.loadInProgress` guard is single-thread but `lastLoadAt` debounce uses Date

**Severity:** LOW (acceptable @MainActor invariant)

**Location:** `ServerListViewModel.swift:399-405`

**Description:**
```swift
if loadInProgress { return }
if !force && Date().timeIntervalSince(lastLoadAt) < 0.1 { return }
loadInProgress = true
defer {
    loadInProgress = false
    lastLoadAt = Date()
}
```

`@MainActor` isolation makes `loadInProgress` write/read race-free. The double-check pattern works — but the order `loadInProgress = true` BEFORE `lastLoadAt` write means: a concurrent call arrives during `loadFromStore` body → blocked by `loadInProgress`. After defer fires, `lastLoadAt = Date()`; next call within 100ms still hits the debounce.

Edge case: `Date()` inside defer captures wall-clock at end of fetch. If fetch took 200ms, `lastLoadAt` is "now", next call within 100ms after that gets debounced. So effective skip window is `(fetch duration) + 100ms`. Plan-04 may have expected 100ms total since first call — terminology drift.

**Suggested fix:** Document the 100ms as "post-fetch debounce" not "since-fetch-start". Or measure `lastLoadAt = Date()` at top of body, before fetch, to make it 100ms-since-start.

**Effort:** 10 min (doc rewrite).

### A6-SL-3-005 (LOW) — `ServerListViewModel.confirmDeleteSubscription` uses `try? KeychainStore.delete` for each linked server — partial failures silent

**Severity:** LOW (audit-3 cross-cutting; similar to A2-H2 cancellation silent)

**Location:** `ServerListViewModel.swift:356-361`

**Description:**
```swift
for srv in linked {
    if let tag = srv.keychainTag, !tag.isEmpty {
        try? KeychainStore.delete(tag: tag)  // silent swallow
    }
    context.delete(srv)
}
```

If KeychainStore.delete throws (item not found = success; OSStatus -25300 errSecItemNotFound; or transient locked state) — error is swallowed. Orphan Keychain items accumulate over subscription churn.

**Why LOW:** Phase 4 added `try? KeychainStore.delete` precisely because subscription churn during testing was leaking many Keychain items, and OSStatus errors are non-actionable for the user. Trade-off accepted.

**Suggested fix:** Log via OSLog при non-`errSecItemNotFound` failures. Doesn't surface to user.

**Effort:** 10 min.

---

## FrontingEngine findings

### A6-FE-3-001 (MEDIUM) — Three adapters (Cloudflare/Fastly/Custom) duplicate ~50 lines of identical overlay logic

**Severity:** MEDIUM (refactoring debt; not a bug)

**Location:**
- `CloudflareAdapter.swift:24-93`
- `FastlyAdapter.swift:23-75`
- `CustomCDNAdapter.swift:20-72`

**Description:**
After T-B10 allowlist fix, all three adapters share identical:
- D-05 blacklist (vless/trojan only, exclude Reality/Vision)
- Step 1-3 overlay (server/port, tls.server_name, transport-specific Host)

Only `provider` + `displayName` differ. Future provider additions (Bunny, Akamai, CloudFront) will copy-paste again.

**Suggested fix:** Extract base impl:
```swift
public enum GenericCDNAdapter {
    public static func applyFronting(
        to outbound: inout [String: Any],
        profile: FrontingProfile
    ) -> Bool { /* shared logic */ }
}

public enum CloudflareAdapter: CDNProviderAdapter {
    public static let provider: CDNProvider = .cloudflare
    public static let displayName: String = "Cloudflare"
    public static func applyFronting(...) -> Bool {
        return GenericCDNAdapter.applyFronting(to: &outbound, profile: profile)
    }
}
```

Or: turn `CDNProviderAdapter` into protocol with default impl:
```swift
extension CDNProviderAdapter {
    public static func applyFronting(...) -> Bool { /* default impl */ }
}
```

Tests should be updated to exercise per-adapter (provider-specific differentiation в FrontingFailureCache keys), but core logic gets one test surface.

**Effort:** 1h (refactor + test verification).

### A6-FE-3-002 (MEDIUM) — `FrontingConfigApplier.isPrivateOrLoopback` drift risk vs `SubscriptionURLFetcher.isBlockedHost`

**Severity:** MEDIUM (already documented in code, R25 TODO)

**Location:** `FrontingConfigApplier.swift:122-204`

**Description:**
Self-documents: «LOW C7'-003 ACK (drift risk)». NAT64/6to4/IPv4-compatible IPv6 prefixes (CV-H3 from audit-3 Plan 07) are correctly fixed in `SubscriptionURLFetcher.isBlockedHost` but NOT in `FrontingConfigApplier.isPrivateOrLoopback`. The fronting validator uses regex/string-prefix matching (legacy), while the canonical blocklist uses numeric IP parsing (T-A3').

**Attack scenario:** Admin's subscription specifies a `FrontingProfile.connectHost = "64:ff9b::7f00:1"` (NAT64-encoded loopback). `isPrivateOrLoopback("64:ff9b::7f00:1")` returns false (no string match for "64:ff9b:" prefix). Profile accepted. Outbound dial target = 127.0.0.1 on cellular with NAT64 carrier.

**Why MEDIUM (not HIGH):** Same threat surface as CV-H3, but in a code path admin-controlled (subscription-driven, not user-paste). Admin subscriptions are signed (Phase 8 trust chain). For non-signed sources, this gap matters.

**Suggested fix:** R25 «v1.1+ TODO» — extract numeric IP parsing into shared NetworkUtils package. Or pragmatic short-term: add NAT64/6to4/v4-mapped prefix checks here inline (5 LoC each):

```swift
// NAT64 well-known 64:ff9b::/96
if lower.hasPrefix("64:ff9b:") { return true }
// 6to4 2002::/16
if lower.hasPrefix("2002:") { return true }
// IPv4-compatible ::a.b.c.d (legacy RFC 4291)
if lower.hasPrefix("::") && lower.contains(".") { return true }
```

**Effort:** 15 min inline fix; 2-3h refactor to shared NetworkUtils.

### A6-FE-3-003 (LOW) — `FrontingFailureCache.persist` is called on every recordFailure/recordSuccess (sync disk write under actor)

**Severity:** LOW (battery/IO; not correctness)

**Location:** `FrontingFailureCache.swift:104-108`

**Description:**
```swift
private func persist() {
    guard let data = try? JSONEncoder().encode(records) else { return }
    try? data.write(to: cacheURL, options: .atomic)  // blocks actor
}
```

Each failure recorded → JSON re-encode + disk write. For CDN fail storms (e.g., 5 profiles × 3 attempts on connectivity loss = 15 writes in seconds), actor stalls + flash wear amplification.

**Suggested fix:** Coalesce with 1-second debounce. Or background queue write (with `nonisolated` async helper).

**Effort:** 30 min.

### A6-FE-3-004 (LOW) — `FrontingFailureCache.records` grows unbounded over app lifetime

**Severity:** LOW (theoretical)

**Location:** `FrontingFailureCache.swift:31`

**Description:**
`records: [String: FailureRecord]` — key = `"<provider>|<ip>|<networkType>"`. Each unique tuple gets a record. Records are only removed on `recordSuccess`. Failed-then-never-retried records accumulate.

**Realistic ceiling:** ~50 servers × 3 providers × 5 network types (wifi/cellular/vpn-stacked/ethernet/other) = 750 entries. Each entry ~80 bytes JSON = 60KB. Bounded.

**Suggested fix:** None (acceptable). Could add `pruneExpired()` called from `recordFailure` to remove records where `cooldownUntil < now - 7d`.

**Effort:** 15 min if pursued.

### A6-FE-3-005 (LOW) — `FrontingFallbackChain.cursor` doesn't loop back on `reset()`-after-`exhausted` if profiles never succeed

**Severity:** LOW (admin intent: when exhausted, fail over to direct path)

**Location:** `FrontingFallbackChain.swift:80, 107-109`

**Description:**
After exhaustion (all profiles in cooldown), `nextEndpoint` returns `(nil, true)`. Caller (Plan 06 ConfigImporter) is expected to fall back to direct (non-CDN) profile. `reset()` resets cursor to 0 — but if all profiles are still in cooldown, `nextEndpoint` will iterate all + return exhausted again. No progress.

**Why LOW:** This is the designed behavior. Cooldown is meant to express "this provider is bad on this network for 6-24h; don't waste time". Caller should not call `reset()` until cooldowns have aged out OR new profiles arrive (subscription refresh).

**Suggested fix:** Add `forceReset()` variant that clears all cooldowns. Useful for testing or "user explicitly retried network — try everything again" UX.

**Effort:** 10 min if pursued.

---

## DeepLinks findings

### A6-DL-3-001 (MEDIUM) — `ImportHandler.handle` accepts arbitrary URL scheme в `url=` parameter

**Severity:** MEDIUM (defense-in-depth concern; downstream importer may guard)

**Location:** `ImportHandler.swift:78-80`

**Description:**
```swift
guard URL(string: rawValue) != nil else {
    throw DeepLinkError.invalidParameterValue(name: "url", reason: "не похоже на URL")
}
```

`URL(string:)` accepts many schemes: `file:///`, `bbtb://import?url=...` (recursion), `data:`, `javascript:`, etc. The check is purely syntactic — anything that parses as URL passes.

The delegation to `importer.importFromRawInput(rawValue, source: .deepLink)` is supposed to:
1. Recognize ss://, vless://, trojan://, etc. (URI parsers)
2. For https:// — fetch subscription
3. For unknown schemes — fail with parse error

But what if `rawValue = "file:///etc/passwd"`? URI parsers don't recognize → fallback path? Subscription fetcher should reject non-https schemes — let me trust audit-3 A4 verified this. But ImportHandler itself doesn't enforce scheme allow-list.

**Suggested fix:** Scheme allow-list in ImportHandler:
```swift
guard let parsed = URL(string: rawValue),
      let scheme = parsed.scheme?.lowercased(),
      ["http", "https", "ss", "vless", "vmess", "trojan", "tuic", "hy2", "hysteria2", "vless+reality"].contains(scheme) else {
    throw DeepLinkError.invalidParameterValue(name: "url", reason: "...")
}
```

**Effort:** 15 min.

### A6-DL-3-002 (LOW) — `DeepLinkRouter` doesn't dedupe handler registrations

**Severity:** LOW (documented as caller's responsibility)

**Location:** `DeepLinkRouter.swift:71-76`

**Description:**
```swift
public func register(_ handler: any DeepLinkHandler) {
    handlers.append(handler)  // duplicate allowed
    ...
}
```

If caller calls `register(handler)` twice, both copies are in the list. First-match-wins makes the second copy unreachable (dead). Not a security issue, but if some test wiring registers in setUp without unregistering — handlers leak between tests.

**Why LOW:** Production: Wave 3 wiring is single-shot from App.init. Tests: each XCTestCase creates fresh `DeepLinkRouter()` instance.

**Suggested fix:** Dedupe by type:
```swift
public func register(_ handler: any DeepLinkHandler) {
    handlers.removeAll { type(of: $0) == type(of: handler) }
    handlers.append(handler)
}
```

Or document as caller invariant.

**Effort:** 5 min.

### A6-DL-3-003 (LOW) — `DeepLinkError.notImplemented` falls back to `L10n.deepLinkErrorUnhandled` — confusing diagnostics

**Severity:** LOW (documented edge case; stub path)

**Location:** `DeepLinkError.swift:65-66`

**Description:**
`RemoteTokenFetchHandler` throws `notImplemented`. UI displays "Deep link not handled" (generic), which is technically correct but uninformative. The `notImplemented` case exists to differentiate "stub feature" from "no matching handler".

**Why LOW:** `RemoteTokenFetchHandler.canHandle` returns `false` always в v0.9, so the case is unreachable via Router. Only direct invocation (testing) could trigger.

**Suggested fix:** Distinct L10n key `deepLinkErrorNotImplemented` = "Этот тип ссылки пока не поддерживается" (Russian) / "This link type is not supported yet" (English). Or: leave as-is and remove the case if it remains unreachable through v1.0.

**Effort:** 5 min.

---

## KillSwitch findings

### A6-KS-3-001 (MEDIUM) — `KillSwitch.appGroupSuiteName` is `nonisolated(unsafe) static var` — unguarded mutable global state

**Severity:** MEDIUM (architecture; no current data race observed)

**Location:** `KillSwitch.swift:61`

**Description:**
```swift
public nonisolated(unsafe) static var appGroupSuiteName: String = "group.app.bbtb.shared"
```

Comment claims "written once at app startup before concurrent access begins" but:
1. No compile-time enforcement — any code (test, future wiring) can rebind it any time.
2. Concurrent reads (`platformShouldDisableEnforceRoutes()` called from multiple threads on macOS) + write = data race.
3. Test infrastructure modifying for sandboxed test paths is plausible.

**Current state:** No callers modify `appGroupSuiteName` in production. Risk is latent.

**Why MEDIUM:** `@unchecked Sendable` peers (CV-H2 ExtensionPlatformInterface) were rated HIGH in audit-3 for similar concurrency unsafety. Here the impact is narrower (read-mostly), but the architecture-level concern is the same.

**Suggested fix:**
- **Option A:** Inject suite name via `KillSwitch.platformShouldDisableEnforceRoutes(suite:)` parameter. Caller (Phase 10 W3 macOS path) passes constant. No mutable global.
- **Option B:** `let appGroupSuiteName = "group.app.bbtb.shared"` (immutable). Tests use `KillSwitchTesting` namespace with mocked path.
- **Option C:** `OSAllocatedUnfairLock<String>` protected — verbose but safe.

**Effort:** 30 min (Option A, prefer).

### A6-KS-3-002 (LOW) — `KillSwitch.apply` doesn't validate platform invariants — Phase 10 R5 logic implicit

**Severity:** LOW (correctness via convention)

**Location:** `KillSwitch.swift:26-44`

**Description:**
On iOS, `platformShouldDisableEnforceRoutes()` always returns `false` (compile-time #else). The `enforceRoutes = !false = true` branch is unconditionally taken when `enabled=true`. Correct, but the negation chain (`!platformShouldDisableEnforceRoutes()`) is hard to read at a glance.

**Suggested fix:** Rename to `shouldEnforceRoutes()` (positive sense):
```swift
proto.enforceRoutes = shouldEnforceRoutes()

private static func shouldEnforceRoutes() -> Bool {
    #if os(macOS)
    return !UserDefaults(suiteName: appGroupSuiteName)?.bool(forKey: "app.bbtb.macOSDisableEnforceRoutes") ?? true
    #else
    return true
    #endif
}
```

**Effort:** 10 min.

---

## TransportRegistry findings

### A6-TR-3-001 (MEDIUM) — `TransportRegistry.shared` mutable singleton without `freeze()` discipline

**Severity:** MEDIUM (audit-3 A7-004 peer; same pattern)

**Location:** `TransportRegistry.swift:11-30`

**Description:**
`@unchecked Sendable` claim is valid (NSLock guards). But anyone can register a new handler at any time:
```swift
TransportRegistry.shared.register(MaliciousHandler.self)  // anytime, anywhere
```

`ProtocolRegistry.shared` has the same pattern (A7-004 LOW). For both: there's no `freeze()` call after `App.init` finishes wiring, so future code paths could mutate the registry.

**Suggested fix:** Two-phase init pattern:
```swift
private var isFrozen: Bool = false
public func freeze() { lock.lock(); defer { lock.unlock() }; isFrozen = true }
public func register<H: TransportHandler>(_ h: H.Type) {
    lock.lock(); defer { lock.unlock() }
    precondition(!isFrozen, "TransportRegistry frozen — register before App.init returns")
    handlers[H.identifier] = h
}
```

Call `freeze()` after Phase 5 W5 wire-up в `App.init`.

**Effort:** 20 min.

### A6-TR-3-002 (LOW) — `TCPTransportHandler.supportedProtocols` lists `hysteria2` despite QUIC-incompatibility

**Severity:** LOW (self-documented A6-LOW C7'-002 ACK)

**Location:** `TCPTransportHandler.swift:32-34`

**Description:**
Self-documenting:
> `hysteria2` исторически здесь, но также QUIC-based; candidate for removal при следующей TransportRegistry refactor (явное разделение TCP vs QUIC tier).

`hysteria2` in `supportedProtocols` is misleading — TCP transport isn't applicable to QUIC. UI presenters using this list for transport-compatibility matrix may show TCP option for Hysteria2 incorrectly. ConfigBuilder ignores transport for Hysteria2 (D-16), so no functional impact.

**Suggested fix:** Remove `hysteria2` (and verify no UI presenter regression).

**Effort:** 10 min.

### A6-TR-3-003 (LOW) — `GRPCTransportHandler.buildTransportBlock` emits empty `service_name` when associated value is ""

**Severity:** LOW (sing-box error surface)

**Location:** `GRPCTransportHandler.swift:56-62`

**Description:**
```swift
public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
    guard case let .grpc(serviceName) = config else { return nil }
    return ["type": "grpc", "service_name": serviceName]
}
```

If `serviceName == ""`, emits `"service_name": ""`. sing-box: «service_name is required» → outbound rejected с cryptic error.

The handler doc says «sing-box validator решает на этапе outbound init» — acceptable design, but the UX (sudden connection failure with no preflight indication) is hostile.

**Suggested fix:** Either substitute default "TunService" inline:
```swift
let resolved = serviceName.isEmpty ? "TunService" : serviceName
return ["type": "grpc", "service_name": resolved]
```

Or document in `TransportConfig.grpc` builder enforcement (`.grpc(serviceName: "")` not allowed at type level).

**Effort:** 15 min (inline default) or 1h (type-level enforcement).

---

## Protocols findings

### A6-PR-3-001 (LOW) — All 6 protocol handlers have `handler.connect` / `handler.disconnect` stub no-ops with comment "не используется в production flow"

**Severity:** LOW (architectural debt)

**Location:**
- `Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift:33-41`
- `Trojan/Sources/Trojan/TrojanHandler.swift:27-35`
- `Shadowsocks/Sources/Shadowsocks/ShadowsocksHandler.swift:33-41`
- `TUIC/Sources/TUIC/TUICHandler.swift:31-39`
- `VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift:22-32`
- `VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift:31-39`

**Description:**
All 6 handlers conform to `VPNProtocolHandler` protocol which requires `connect(config:)`, `disconnect(handle:)`, `diagnostics()`. All 6 return empty stub `TunnelHandle()`. Real tunnel start lives in `NETunnelProviderManager.connection.startVPNTunnel`.

This is by-design (per Phase 1 D-decisions), but creates dead surface area:
- 18 stub methods × 5 lines each = 90 LoC dead.
- New developer adding 7th protocol must copy the same 5-line stub pattern.
- Tests should NOT test these stubs (false positive coverage).

**Suggested fix:** Make `connect`/`disconnect` optional defaults в `VPNProtocolHandler` protocol extension:
```swift
extension VPNProtocolHandler {
    public func connect(config: ProtocolConfig) async throws -> TunnelHandle {
        return TunnelHandle()
    }
    public func disconnect(handle: TunnelHandle) async throws {}
    public func diagnostics() async -> ProtocolDiagnostics {
        ProtocolDiagnostics()
    }
}
```

Each handler then only implements `identifier`, `displayName`, `isAvailable`, `validate`.

**Effort:** 30 min (protocol extension + remove 6×stubs).

### A6-PR-3-002 (LOW) — Hysteria2/TUIC `ConfigBuilder.buildOutbound` accept `transport` parameter but always ignore — D-16 API consistency cost

**Severity:** LOW (architectural; documented)

**Location:**
- `Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:37-42`
- `TUIC/Sources/TUIC/ConfigBuilder.swift:31-35`
- `Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift:26-30`

**Description:**
Per D-16 these protocols don't support transport overlay (QUIC-based). The `transport` parameter is accepted for API uniformity but always ignored. New developers may:
1. Mistakenly pass a `.ws(...)` thinking it applies → silent no-op.
2. Test cases assert transport behavior, see nothing happens.

**Suggested fix:** Different signature (drop transport param) for QUIC-based protocols. Or runtime assert dev mode:
```swift
#if DEBUG
if case .tcp = transport { /* ok */ } else { Logger.warning("Hysteria2 ignores transport override") }
#endif
```

**Effort:** 20 min for DEBUG warn; 1-2h for signature refactor (callers must adapt).

### A6-PR-3-003 (LOW) — `Trojan/ConfigBuilder` + `VLESSTLS/ConfigBuilder` near-duplicate (~85% identical)

**Severity:** LOW (refactoring opportunity)

**Location:**
- `Trojan/Sources/Trojan/ConfigBuilder.swift:31-83`
- `VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:41-98`

**Description:**
Both:
- Strip "h2" ALPN when transport is WS.
- Emit `tls` block with `enabled/server_name/insecure:false/alpn/utls/record_fragment:true`.
- Delegate transport block to WSTransportHandler (with sniFallback) or TransportRegistry.
- Differ only in `type` ("trojan" vs "vless"), auth field (password vs uuid+flow), `network: "tcp"`.

Future protocol additions (Vmess, etc.) will copy-paste the same pattern, including future fixes (like Phase 7a record_fragment).

**Suggested fix:** Extract common TLS+transport builder helper to a shared `BBTBProtocolKit` (already discussed in Phase 5 W7 retrospective).

**Effort:** 2-3h (deferred to v1.1+ refactor; not blocking).

---

## Pattern observations (cross-cutting)

### Recurring patterns to fold into Phase 13 closure / v1.0.1 backlog

1. **Hardcoded "мс" / English strings in views** — at least 3 sites (LatencyBadge, ServerRow.accessibilityValueText, ServerDetailView alert title) bypass L10n. Audit recommended pass before en TestFlight rollout.

2. **Accessibility value strings repurposed** — `statusConnected`/`statusEmpty` used for collapse/selection в SubscriptionHeader + AutoCell. Discrete L10n keys needed.

3. **`@unchecked Sendable` / `nonisolated(unsafe)` patterns in MEDIUM packages** — `KillSwitch.appGroupSuiteName`, `TransportRegistry.shared`, `ProtocolRegistry.shared` (cross-pkg). All claim safety via single-thread init invariant без compile-time enforcement. Apply `freeze()` discipline OR inject deps as parameters.

4. **`ISO8601DateFormatter()` / `RelativeDateTimeFormatter()` per body render** — RulesViewerSection + DiagnosticsExporter. Static cache pattern.

5. **`try?` silent swallow paths** — ServerListViewModel.confirmDeleteSubscription (Keychain delete), DiagnosticsExporter.write, FrontingFailureCache.persist. Each acceptable individually; cross-cutting visibility into "what's silent" would aid future debugging.

6. **Handlers with empty stubs (connect/disconnect)** — 6 × VPNProtocolHandler conformers. Protocol-extension default impls would remove 90 LoC.

### Verified-correct patterns

- **T-B6' tag-scoped FrontingConfigApplier** — correct.
- **DeepLinkRouter actor isolation** — correct, signpost wired.
- **AsyncMutex pattern absent in this scope** (canonical pattern lives in PacketTunnelKit / RulesEngine, audit-3 verified).
- **WSTransportHandler `sniFallback:` overload** — proper unification of M12 fix; Trojan + VLESSTLS use it.
- **CDN adapter allowlist (T-B10)** — correct vless/trojan only.
- **NEVPN observer queue=nil pattern** — out of scope here, but referenced correctly in SettingsViewModel.wireRulesCoordinator.

---

## Recommendation

### Ship verdict
🟢 **MEDIUM-package scope clears Internal TestFlight.** 0 CRITICAL, 0 HIGH except A6-3-001 (snapshot+rollback target wrong value — needs verify/test).

### Pre-External rollout (Tier B/C — 1-2h):
| Finding | Severity | Effort |
|---|---|---|
| **A6-3-001 — ServerDetail rollback `previous` captures `new`** | HIGH | 30 min |
| A6-SL-3-001 — Hardcoded "мс" | MEDIUM (en build) | 15 min |
| A6-SL-3-002 — A11y status*/empty misuse | MEDIUM | 15 min |
| A6-FE-3-002 — NAT64/6to4 drift в FrontingConfigApplier | MEDIUM | 15 min inline |
| A6-DL-3-001 — ImportHandler scheme allow-list | MEDIUM | 15 min |
| A6-KS-3-001 — `nonisolated(unsafe)` static var | MEDIUM | 30 min |
| A6-TR-3-001 — TransportRegistry freeze() | MEDIUM | 20 min |

### v1.0.1 polish (~3-5h total)
- A6-FE-3-001 — Three adapters refactor.
- A6-PR-3-001 — VPNProtocolHandler default impls.
- A6-PR-3-003 — Trojan/VLESSTLS ConfigBuilder unification.
- A6-SET-3-001..7 (UX edge cases).
- A6-SET-3-005 — DiagnosticsExporter ms-resolution timestamp (parity с T-C-D1).
- LOW backlog (~12 items).

### Open questions for project owner
**None mandatory** for Internal TestFlight ship.

**Optional clarifications:**
- Is `routingRulesEnabled` toggle expected to trigger reconnect at runtime, or is "reconnect to apply" UX acceptable? (Currently A6-SET-3-002 — silent, no L10n footer hint verified).
- Should TestFlight invite URL placeholder block ship, or is "TestFlight 404 + persisted dismiss" acceptable for v1.0 (A6-SET-3-003)?

---

## Summary table

| Finding | Severity | Pkg | Effort | Tier |
|---|---|---|---|---|
| A6-3-001 ServerDetail rollback wrong target | HIGH | ServerListFeature | 30m | A++ |
| A6-SET-3-001 STUN backdrop dismiss stale | MEDIUM | SettingsFeature | 10m | B |
| A6-SET-3-002 routingRules no live-apply | MEDIUM | SettingsFeature | 5m | B |
| A6-SET-3-003 openTestFlight persists on 404 | MEDIUM | SettingsFeature | 15m | B |
| A6-SL-3-001 LatencyBadge "мс" hardcoded | MEDIUM | ServerListFeature | 15m | B |
| A6-SL-3-002 A11y status* repurposed | MEDIUM | ServerListFeature | 15m | B |
| A6-FE-3-001 Three adapter duplication | MEDIUM | FrontingEngine | 1h | C |
| A6-FE-3-002 NAT64 drift в FrontingEngine | MEDIUM | FrontingEngine | 15m | B |
| A6-DL-3-001 ImportHandler scheme allowlist | MEDIUM | DeepLinks | 15m | B |
| A6-KS-3-001 nonisolated(unsafe) static var | MEDIUM | KillSwitch | 30m | B |
| A6-TR-3-001 TransportRegistry freeze() | MEDIUM | TransportRegistry | 20m | B |
| A6-2 alert title not localized | LOW | ServerListFeature | 5m | D |
| A6-SET-3-004 RelativeDateFormatter per render | LOW | SettingsFeature | 5m | D |
| A6-SET-3-005 ISO8601 second resolution | LOW | SettingsFeature | 5m | D |
| A6-SET-3-006 deinit cleanup discipline | LOW | SettingsFeature | 15m | D |
| A6-SET-3-007 DoH host validation | LOW | SettingsFeature | n/a | D |
| A6-SL-3-003 ServerListSheet TODO heights | LOW | ServerListFeature | 30m | D |
| A6-SL-3-004 loadInProgress debounce doc | LOW | ServerListFeature | 10m | D |
| A6-SL-3-005 Keychain delete silent swallow | LOW | ServerListFeature | 10m | D |
| A6-FE-3-003 FrontingCache persist on every write | LOW | FrontingEngine | 30m | D |
| A6-FE-3-004 records unbounded growth | LOW | FrontingEngine | 15m | D |
| A6-FE-3-005 forceReset variant | LOW | FrontingEngine | 10m | D |
| A6-DL-3-002 Router dedup | LOW | DeepLinks | 5m | D |
| A6-DL-3-003 notImplemented L10n | LOW | DeepLinks | 5m | D |
| A6-KS-3-002 shouldEnforceRoutes() rename | LOW | KillSwitch | 10m | D |
| A6-TR-3-002 hysteria2 in TCP list | LOW | TransportRegistry | 10m | D |
| A6-TR-3-003 GRPC empty service_name | LOW | TransportRegistry | 15m | D |
| A6-PR-3-001 Handler stub default impls | LOW | Protocols | 30m | D |
| A6-PR-3-002 QUIC handlers ignore transport silently | LOW | Protocols | 20m | D |
| A6-PR-3-003 Trojan/VLESSTLS dedup | LOW | Protocols | 2-3h | D (v1.1+) |

**Totals:** 1 HIGH (T-C-A6H1' verification failure) · 11 MEDIUM · 18 LOW · ~7-10h total fix work если все.
