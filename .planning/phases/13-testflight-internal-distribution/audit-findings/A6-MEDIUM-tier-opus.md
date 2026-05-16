# A6 — MEDIUM tier audit (Opus 4.7)

**Scope:** 12 packages (SettingsFeature + ServerListFeature + FrontingEngine + DeepLinks + KillSwitch + TransportRegistry + 6 Protocols)
**Files audited:** 41 source files across 12 packages
**Total findings:** 17 (CRITICAL: 0, HIGH: 3, MEDIUM: 8, LOW: 6)

Cross-cutting verification of `@AppStorage` suites against `SingBoxConfigLoader.expandConfigForTunnel` reads confirms that all 4 extension-read keys (`routingRulesEnabled`, `stunBlockEnabled`, `muxEnabled`, `macOSDisableEnforceRoutes`) are correctly declared with `store: UserDefaults(suiteName: "group.app.bbtb.shared")` in `SettingsViewModel`. No App-Group-suite mismatch found in this scope. `utlsFingerprint` is also App-Group-suited but extension never reads it (intent: future use / consistency — non-issue, just dead read-path).

The two highest-impact findings are (a) a default-value mismatch on `killSwitchEnabled` that can silently disable kill switch on macOS enforce-routes toggle, (b) a permissive Universal Link path prefix match (`/import` vs `/important*`), and (c) shared `nonisolated(unsafe)` mutable static in `KillSwitch.appGroupSuiteName` (writeable at any time, not guarded). None are CRITICAL exploits; all are HIGH-severity defects with clear mitigations.

## Findings (grouped by package)

### SettingsFeature

#### [HIGH] A6-001: `killSwitchEnabled` default mismatch between SettingsViewModel and ConfigImporter/MainScreenViewModel
- **Location:**
  - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:28` (`@AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false`)
  - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:589` (`UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? false`)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:1351` (`... as? Bool ?? true`)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:199` (`... as? Bool ?? true`)
- **Dimension:** Bugs + logic / security
- **Description:** On first install (key never written), `ConfigImporter` and `MainScreenViewModel` treat absence as `true` (KILL-01 carry-forward); but `SettingsViewModel.killSwitchEnabled` `@AppStorage` exposes the toggle as `false`, and `applyEnforceRoutesToManager` (macOS, line 589) reads with default `false`. So when a macOS user toggles enforce-routes BEFORE ever interacting with the kill-switch toggle, the code reads `killSwitchEnabled = false` from UserDefaults.standard (no value set) and silently passes `enabled: false` to `KillSwitch.apply`, which sets `includeAllNetworks = false` and `enforceRoutes = false`. That down-toggles the kill switch from the implicit ON state ConfigImporter created.
- **Why it matters:** Silent disable of kill switch on macOS = potential traffic leak outside tunnel during a user action that the user thinks only toggles enforceRoutes. R4 invariant (kill switch ON by default) is then violated mid-session.
- **Suggested fix:** Align all four read sites + the @AppStorage default. Decision options: (a) default `true` everywhere (matches KILL-01 carry-forward intent) — change `SettingsViewModel.swift:28` `= false` → `= true` and `:589` `?? false` → `?? true`. (b) default `false` everywhere and stop applying kill switch silently in ConfigImporter on first launch. Option (a) is consistent with the R4 doc-comment in `KillSwitch.swift:25-26` ("Phase 1 carry-forward / KILL-01 default").

#### [HIGH] A6-002: Race condition between SettingsViewModel.killSwitchEnabled toggle and applyEnforceRoutesToManager fresh read
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:589` inside `applyEnforceRoutesToManager()`
- **Dimension:** Bugs + logic
- **Description:** `applyEnforceRoutesToManager()` reads `killSwitchEnabled` from `UserDefaults.standard` directly rather than from the captured `@AppStorage` value or `await MainActor.run { … }` for consistency. This is `nonisolated`, called from `.onChange(of: macOSDisableEnforceRoutes)` via `Task { … }`. If the user toggles the kill switch and the enforceRoutes toggle in rapid succession (or if the @AppStorage write hasn't been flushed yet to `UserDefaults.standard`), the value read can lag — apply path uses stale kill-switch policy.
- **Why it matters:** SwiftUI `@AppStorage` writes synchronously to UserDefaults on toggle change, but the order with respect to `.onChange` firing on a different binding (`macOSDisableEnforceRoutes`) within the same SwiftUI transaction is not documented as guaranteed.
- **Suggested fix:** Capture a snapshot of `killSwitchEnabled` on MainActor before dispatching to nonisolated Task, e.g. `let killSwitchSnapshot = self.killSwitchEnabled` inside a small `@MainActor` wrapper, then pass into the nonisolated method. Alternatively, listen to combined toggle change in the host view and call a single live-apply method.

#### [HIGH] A6-003: ImportHandler matches over-broad Universal Link path prefix
- **Location:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:42-47`
- **Dimension:** Security at boundary
- **Description:** `canHandle` uses `url.path.hasPrefix("/import")` for the Universal Link branch. That string-prefix test matches `/import`, `/import/foo`, **and** `/important`, `/importer`, `/import-some-spam`, etc. A typo or admin misconfiguration of AASA could route an unrelated path to ImportHandler, where the missing `url=` query parameter would surface as a user-facing error alert — but more importantly, an attacker who can plant content at `https://import.bbtb.app/importx?url=...` (if the bucket hosts arbitrary paths) gets to influence the importer.
- **Why it matters:** Universal Link host whitelist is the only boundary check (line 44: `host == "import.bbtb.app"`). After that, path validation is permissive. AASA already restricts paths server-side, but defense-in-depth here is cheap.
- **Suggested fix:** Replace `url.path.hasPrefix("/import")` with explicit equality or trailing-slash tolerance: `url.path == "/import" || url.path == "/import/"`. Or use `URLComponents` and check `path` directly.

#### [MEDIUM] A6-004: DiagnosticsExporter IPv4 masking regex does not handle IPv6 (spec says it doesn't, but Russian transparency claim is misleading)
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:106-118` + `header` line 78-86
- **Dimension:** Security / privacy
- **Description:** Header text on line 83 reads `"Last 24h, IP addresses masked."` (and Russian L10n likely says the same). The regex `(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}` only masks IPv4. IPv6 addresses (`fe80::1234`, `2001:db8::1`) are NOT masked and will leak verbatim in shared diagnostic logs. The code docstring acknowledges this on line 110 ("IPv6 не покрывается по D-12 spec"), but the user-facing claim doesn't.
- **Why it matters:** Users who share logs through TestFlight feedback / Telegram trust the masking claim. iOS 14+ defaults to IPv6 on cellular; many sing-box log lines may contain IPv6 server IPs. Privacy expectation broken.
- **Suggested fix:** Either (a) add IPv6 masking via separate regex (`[0-9a-fA-F:]+::?[0-9a-fA-F:]+` family — non-trivial but feasible), or (b) update the header/L10n text to say `"IPv4-адреса маскированы"` so users know IPv6 may appear. Option (b) is the minimum.

#### [MEDIUM] A6-005: ForceUpdateButtonState Timer can outlive ViewModel if SwiftUI lifetime not respected
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:171-194` (deinit + teardown) + `:507-517` (startCooldownTimer)
- **Dimension:** Memory + thread safety
- **Description:** `Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { … }` runs on the RunLoop and retains its closure (which captures `[weak self]` correctly). But the `Timer` itself is stored in `cooldownTimer: Timer?` — neither `deinit` nor any automatic mechanism invalidates it. `teardown()` (line 185) does invalidate, but it's documented as "explicit teardown — вызывается tests + host shutdown hook". If host never calls teardown (e.g. SwiftUI lifecycle just deinits the VM), the Timer keeps firing on the main runloop, the captured `[weak self]` Task just no-ops on `self == nil`. Not a leak, but wastes runloop cycles indefinitely.
- **Why it matters:** TestFlight UAT typically presents Settings then dismisses. Across many sheet present/dismiss cycles, orphaned Timers accumulate. Per memory feedback `feedback_nevpn_observer_queue_main.md`, the project is sensitive to runloop pollution.
- **Suggested fix:** Document that host MUST call `teardown()` from `.onDisappear` / scene-phase transition, OR migrate Timer to async `Task { while !Task.isCancelled { try await Task.sleep ... } }` pattern stored in a Task property that can be `.cancel()`'d from a nonisolated deinit-safe context.

#### [MEDIUM] A6-006: Frontmost STUN-block confirmation dialog can persist after toggle navigation
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AntiDPISection.swift:38-69`
- **Dimension:** UX / state machine
- **Description:** `pendingStunBlock` is `@State private` inside `AntiDPISection`. If the user opens AntiDPISection, taps the STUN toggle ON (alert appears), then navigates back via the BBTBTopBar dismiss without confirming/cancelling, the alert dismisses but `pendingStunBlock` stays at `true` in @State (no `.onDisappear` cleanup). On next visit the @State is fresh (new view instance), but `viewModel.stunBlockShowConfirm` is `@Published` on the VM — if the alert is presented again from a stale value, the destructive button writes `pendingStunBlock` (= default `false` from new view instance), which now silently sets `stunBlockEnabled = false` — opposite of user intent.
- **Why it matters:** Edge-case but reproducible; can leave user thinking STUN is on when it isn't (or vice versa).
- **Suggested fix:** On alert dismiss (either button), also set `viewModel.stunBlockShowConfirm = false` explicitly (already done) AND `pendingStunBlock = false`. Alternative: lift `pendingStunBlock` into the ViewModel so it shares lifecycle with `stunBlockShowConfirm`.

#### [LOW] A6-007: `currentAppVersion` falls back to `"0.0.0"` sentinel without logging
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:165-167`
- **Dimension:** Maintainability / diagnostics
- **Description:** If `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` is nil, the comparison with `min_app_version` on line 435 will return `.orderedAscending`, so `showMinAppVersionBanner = true` — the banner is shown but no signal explains why. In tests this is intentional; in production this masks a broken Info.plist.
- **Why it matters:** Diagnostics for failed releases.
- **Suggested fix:** Log at `.fault` level if version is missing in non-test environment.

### ServerListFeature

#### [MEDIUM] A6-008: `ServerListViewModel.pullToRefresh` saves to ModelContext after partial-failure loop without rollback semantics
- **Location:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:257-267`
- **Dimension:** Bugs + logic
- **Description:** The `for sub in subscriptions` loop fetches and merges each subscription. If `fetchAndMerge` partially writes (creates new ServerConfig rows in context) and then throws, the partial mutations remain in context. `try? context.save()` on line 267 commits them. Other subscriptions' merges that ran before the throw also commit. There's no transactional boundary per subscription; if `merge` is non-atomic this can leave the store in an inconsistent state where one subscription is half-imported.
- **Why it matters:** Subscription refresh on real device with flaky network can produce inconsistent state — UI shows partial server list.
- **Suggested fix:** Either save inside the inner `do { ... ; try context.save() }` block per successful subscription, OR wrap each sub's merge in its own short-lived `ModelContext` so a thrown sub leaves no residue.

#### [MEDIUM] A6-009: `loadFromStore` 100ms debounce can mask legitimately needed refreshes
- **Location:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:382-410`
- **Dimension:** Bugs + logic
- **Description:** `if Date().timeIntervalSince(lastLoadAt) < 0.1 { return }` debounces all callers. Phase 6e M10 added this for storm protection, but the debounce skips legitimate post-write reloads. If a `deleteServer` finishes and immediately calls `loadFromStore`, then within 100 ms `confirmDeleteSubscription` also calls it, the second call (which is the one with the actually-final state) is skipped. The UI shows stale rows until the next non-debounced load.
- **Why it matters:** Cascading deletes can leave orphan rows visible briefly. Already known per memory `feedback_swiftdata_uuid_predicate.md` family; the workaround relies on subsequent UI activity to retrigger load.
- **Suggested fix:** Track "stale" flag — if a load is skipped due to debounce, schedule a one-shot Task that loads after 100 ms elapses. Alternatively, drop debounce in favour of `Task` deduplication only.

#### [LOW] A6-010: `pingAllServers` defer-cleanup task captures `[weak self]` but launches detached Task inside an actor-isolated method
- **Location:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:441-449`
- **Dimension:** Thread safety
- **Description:** The `defer` block creates an unstructured `Task { @MainActor [weak self] in ... }`. Inside a `@MainActor` ObservableObject's async method, the defer fires before suspension returns. Spawning a Task here is correct, but the Task is unstructured — if the VM is deinit'd before the Task runs, `self` is nil and cleanup is silently skipped, leaving rows stuck in `.pinging` cosmetically.
- **Why it matters:** Edge case; very narrow window.
- **Suggested fix:** Move cleanup inline using `await MainActor.run { ... }` before exit, structured.

### FrontingEngine

#### [MEDIUM] A6-011: SSRF guard `isPrivateOrLoopback` does not block CGNAT range (100.64.0.0/10) and uses prefix-string match
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:107-123`
- **Dimension:** Security at boundary
- **Description:** Blocklist covers loopback, 0.0.0.0, 169.254/16, 10/8, 192.168/16, 172.16-31. Missing: 100.64.0.0/10 (carrier-grade NAT, used on cellular carriers; on iOS sometimes on Wi-Fi), 224.0.0.0/4 (multicast), 240.0.0.0/4 (reserved), `::ffff:127.0.0.1` (IPv4-mapped IPv6 loopback). The check is a string-prefix `hasPrefix("127.")` — this matches `127.0.0.1` but ALSO `127.999.999.999` (a malformed IP that sing-box would reject), but more importantly, `127ABC.example.com` (a hostname starting with `127`) is also matched. False positives are tolerated (we just reject), but false negatives exist (CGNAT, IPv6 mapped).
- **Why it matters:** Malicious admin subscription can plant a `connectHost` in the CGNAT range pointing to a local network device on iOS cellular (rare but possible).
- **Suggested fix:** Parse the string as IP using `IPv4Address(_:)` / `IPv6Address(_:)` from Network framework; if parses, check against `IPv4.Range` for all RFC 1918/6598/4291. For hostnames, accept (no DNS lookup — out of threat model per existing comment).

#### [LOW] A6-012: Triple-duplicated D-05 blacklist + overlay code across 3 CDN adapters
- **Location:**
  - `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CloudflareAdapter.swift:25-86`
  - `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FastlyAdapter.swift:24-77`
  - `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CustomCDNAdapter.swift:21-74`
- **Dimension:** Maintainability
- **Description:** The 3 D-05 blacklist checks and the 3-step overlay (server/port/SNI/transport-host) are byte-for-byte duplicated across Cloudflare, Fastly, CustomCDNAdapter. Any future change (e.g. add VLESS over QUIC to blacklist) requires editing 3 places identically — easy to drift.
- **Why it matters:** Drift risk; doc-comments already say "identical to CloudflareAdapter".
- **Suggested fix:** Extract `commonOverlay(outbound:profile:)` and `commonBlacklist(outbound:) -> Bool` into a protocol extension on `CDNProviderAdapter` or a free helper enum. Each adapter then calls common + adds provider-specific tweaks.

#### [LOW] A6-013: FrontingProfile lacks port range validation
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingProfile.swift:54-93` + applier line 39-43
- **Dimension:** Bugs + logic
- **Description:** `connectPort: Int` accepts any Int (negative, 0, > 65535, INT_MAX). `validateProfile` only checks host. A malicious or buggy subscription can plant `connectPort = -1` or `0`, which sing-box will reject at outbound init — but the user-facing error is opaque.
- **Why it matters:** Diagnostics + defense-in-depth.
- **Suggested fix:** Add `guard (1...65535).contains(profile.connectPort) else { throw .invalidPort }` in `validateProfile`.

### DeepLinks

#### [MEDIUM] A6-014: `ImportHandler` permits any URL string in `url=` query without scheme allowlist
- **Location:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:69-77`
- **Dimension:** Security at boundary
- **Description:** After `URL(string: rawValue) != nil` (line 69), the rawValue is passed to `importer.importFromRawInput(rawValue, source: .deepLink)`. The handler doesn't verify the URL's scheme — it could be `file://`, `data:`, `javascript:`, `bbtb://` (recursive). Whether `ConfigImporting.importFromRawInput` enforces a scheme allowlist is outside this audit scope (A2 covered VPNCore), but the handler's "defense-in-depth" comment (line 67-68) is incomplete — it guards URL parseability but not URL category.
- **Why it matters:** A QR code or NSUserActivity link with `bbtb://import?url=file:///etc/passwd` would reach the importer, which may handle it gracefully or may attempt to fetch. Sandbox limits actual damage on iOS.
- **Suggested fix:** Inside `handle`, after parsing `URL(string: rawValue)`, assert `parsed.scheme?.lowercased() ∈ {"http", "https"}` (subscription URLs are HTTP/HTTPS; for raw vless://… payloads the existing `importFromRawInput` consumes strings, not URLs). If protocol URIs are intentionally allowed, document it.

#### [LOW] A6-015: `DeepLinkRouter.register` allows duplicate registrations silently
- **Location:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift:71-76`
- **Dimension:** Bugs + logic
- **Description:** Doc-comment acknowledges duplicates are "not blocked", but says "caller responsibility". If host bootstrap accidentally calls `register(ImportHandler(…))` twice (e.g. cold-start race in app init), the handler list has two entries, both `canHandle == true`, and `handle()` fires the first one — but it doesn't fail loudly. Duplicate import side effects (Keychain entries, SwiftData rows) become possible if handler is non-idempotent.
- **Why it matters:** ConfigImporter's import pipeline is likely idempotent (de-dups by Subscription URL), but it's a fragile contract.
- **Suggested fix:** Track registered identifiers in a Set; refuse duplicate by `static identifier` with a log.error.

### KillSwitch

#### [MEDIUM] A6-016: `KillSwitch.appGroupSuiteName` is `nonisolated(unsafe) static var` mutable at runtime
- **Location:** `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:61`
- **Dimension:** Thread safety / security
- **Description:** `public nonisolated(unsafe) static var appGroupSuiteName: String = "group.app.bbtb.shared"`. Comment says "written once at app startup before concurrent access begins" — but the API is public and writable. A test, a Phase 13 prerequisite, or a bug could mutate this at runtime, after the extension has already cached its own UserDefaults handle. macOS extension reads `app.bbtb.macOSDisableEnforceRoutes` from the suite (line 66) on every `platformShouldDisableEnforceRoutes()` call — a runtime mutation of `appGroupSuiteName` while extension is running would silently divert reads to a different suite where the toggle key doesn't exist, defaulting back to enforceRoutes ON. That's the safe direction, but the inverse failure path (suite has stale enabled value) is also possible.
- **Why it matters:** Phase 13 D-04 introduced strict App Group key contract. Mutable suite name is a foot-gun.
- **Suggested fix:** Make `appGroupSuiteName` `let` and read from `AppGroupContainer.identifier` (a `let` constant in PacketTunnelKit) — but the KillSwitch package can't depend on PacketTunnelKit per architecture. Alternative: keep `var` but make it private(set) with an explicit `configure(suiteName:)` once-per-process guarded helper.

### TransportRegistry

#### [LOW] A6-017: `TransportRegistry` uses `NSLock` + `@unchecked Sendable` rather than an actor
- **Location:** `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/TransportRegistry.swift:10-30`
- **Dimension:** Thread safety
- **Description:** Pattern works correctly (lock around dict access) but Swift 6 strict-concurrency prefers actor over `@unchecked Sendable`. The registry is read on every protocol's `buildOutbound` (hot path) and on every `expandConfigForTunnel`. NSLock has measurable contention overhead under high concurrency; actor with non-suspending sync methods would be neither faster nor slower here, but type-safer. No actual bug — just architectural inconsistency with the rest of the project which uses actors (e.g., FrontingFallbackChain, RulesEngineCoordinator).
- **Why it matters:** Style + future Swift 6 strict mode. Not blocking TestFlight.
- **Suggested fix:** Migrate to `public actor TransportRegistry { ... }` with `private nonisolated(unsafe) let shared = …` pattern, OR document the `@unchecked Sendable` rationale.

### Protocols (VLESSReality / VLESSTLS / Trojan / Shadowsocks / Hysteria2 / TUIC)

#### [LOW] A6-018: Trojan WS template uses string substitution for `${WS_PATH}` / `${WS_HOST}` into JSON string positions
- **Location:**
  - `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:72-77`
  - `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json:60,62`
- **Dimension:** Bugs + logic
- **Description:** `"path": "${WS_PATH}"` in template is a JSON string literal. `replacingOccurrences(of: "${WS_PATH}", with: path)` substitutes raw `path` into the JSON. If `path` contains `"`, `\`, control chars, or newlines, the result is invalid JSON and parsing fails at sing-box load. URI parser likely rejects such input upstream, but the layer is not defense-in-depth. The other 5 protocols use JSON mutation via `JSONSerialization` (port mutation pattern); only Trojan WS does naive string substitution for transport block.
- **Why it matters:** Pure code-smell + maintenance risk. Phase 4 pattern verified safe by upstream URI validation. Real-world URIs from misbehaving subscriptions could trip this.
- **Suggested fix:** Move `${WS_PATH}` and `${WS_HOST}` substitution into the `mutatePort`-style JSON-mutation path (i.e., template ships `"path": ""` placeholder string and Swift mutates via `JSONSerialization`). Or JSON-escape `path`/`wsHost` before string-substitution (`JSONEncoder().encode(path)` returns properly escaped string).

#### [LOW] A6-019: Hysteria2 `mutatePort` is invoked when port != 443, but Shadowsocks check uses port != 8388 (correct), and TUIC uses port != 443; minor inconsistency
- **Location:**
  - `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift:60`
  - `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:105`
  - `BBTB/Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift:108`
  - `BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift:72`
  - `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:69`
  - `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:79`
- **Dimension:** Maintainability
- **Description:** Each ConfigBuilder hardcodes its template's default port and skips `mutatePort` when input port equals that default. Skipping mutation is a micro-optimization; if the template's default port ever changes (e.g., Shadowsocks template switches from 8388 to 443), the optimization silently breaks (mutatePort never runs, wrong port committed). The fact that the values are duplicated across builder + template is a coupling smell.
- **Why it matters:** Maintenance hazard; trivial to overlook on template edit.
- **Suggested fix:** Always run `mutatePort` (cost is one JSONSerialization roundtrip, sub-ms). Or extract template default ports into a single constants module and reference from both builder and template-generator.

## Cross-package patterns observed

1. **`@AppStorage` suite contract is well-enforced.** Every key read by `SingBoxConfigLoader.expandConfigForTunnel` (routingRulesEnabled, stunBlockEnabled, muxEnabled, macOSDisableEnforceRoutes) uses `store: UserDefaults(suiteName: "group.app.bbtb.shared")` in `SettingsViewModel`. Phase 13 D-04 lesson learned has been applied correctly. The `utlsFingerprint` key is App-Group-suited as forward-compat for extension reads, although it's currently only consumed by the main-app PoolBuilder.

2. **`record_fragment: true` on VLESS+TLS / Trojan but NOT Hysteria2/TUIC/Reality.** Consistent and correct per DPI-02 doc-comments. Hysteria2 and TUIC are QUIC (no TLS record), Reality has its own XTLS path.

3. **D-08 R1 EXCEPTION (`tls.insecure: true`) only in Hysteria2.** Verified across all 6 protocol builders. The five non-Hy2 builders all hardcode `"insecure": false` or omit the field; Hysteria2 alone reads from `parsed.allowInsecure`. Multiple defense layers (struct shape, code comments, test invariant) consistently enforce this.

4. **Duplicated overlay logic across CDN adapters and across protocol ConfigBuilders.** Triple-duplicated D-05 blacklist in Cloudflare/Fastly/CustomCDNAdapter; near-duplicated `mutatePort` helper in all 6 protocols. Phase 6e Theme C-1 already extracted one duplication (WS host fallback into `WSTransportHandler`); this pattern could be applied here next.

5. **Diagnostics IPv6 leak gap.** `DiagnosticsExporter.maskIPv4` is documented to skip IPv6, but the user-facing label "IP addresses masked" is not qualified. iOS prefers IPv6 on cellular; real device logs likely contain IPv6 server addresses. Minimal fix: rename label to "IPv4-адреса маскированы". Full fix: add IPv6 masking regex.

6. **No critical exploit findings.** Phase 13 TestFlight Internal Testing distribution path is safe to proceed from this scope's perspective. The HIGH findings (killSwitch default mismatch, race on apply, UL path prefix) are correctness/security defects with bounded blast radius and clear fixes — none gate distribution.
