# A1 — PacketTunnelKit audit (Opus 4.7)

**Scope:** BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/
**Files audited:** 11 (SingBoxConfigLoader, BaseSingBoxTunnel, ExtensionPlatformInterface, AppGroupContainer, ExternalVPNStopMarker, TunnelSettings, TunnelLogger, InterfaceFlagsInspector, PacketTunnelKit, PlatformSpecific/iOS, PlatformSpecific/macOS)
**Total findings:** 14 (CRITICAL: 0, HIGH: 3, MEDIUM: 6, LOW: 5)

## Findings

### [HIGH] A1-001: STUN-block rule injection lacks `tag` key — sing-box may reject schema or rule never matches
- **Location:** `SingBox/SingBoxConfigLoader.swift:411-418`
- **Dimension:** bugs
- **Description:** The injected STUN block rule writes `"tag": "bbtb-stun-block"` into a `route.rules` entry, but sing-box 1.13's `route.rules[]` schema does not include a `tag` field for rules (only `rule_set[]` entries have `tag`). Sing-box 1.13 will warn/reject unknown fields under strict parsing; either the rule will not be parsed at all or it will be silently dropped depending on engine version. The matching idempotency check on line 406 (`($0["tag"] as? String) == "bbtb-stun-block"`) therefore also fails on a second `expand` call, leading to **duplicate STUN-block rules** stacked into `route.rules` across cold-start retries.
- **Why it matters:** STUN block (DPI-05 / BIO-04) is a documented routing rule; if sing-box silently ignores the `tag` key or rejects the field, the rule may not actually drop STUN traffic, leaking the user's real-IP via WebRTC during P2P calls. On the duplicate-injection path, `route.rules` grows by one entry per `startOrReloadService` call within the same extension process lifecycle.
- **Suggested fix:** Replace inline `tag`-based de-dup with a structural check (port + network + action match), or move the marker into a comment/sibling tracking dictionary outside `route.rules`. Idempotency for `route.rules` should compare the actual matcher tuple, not a synthetic tag that sing-box will not preserve.

### [HIGH] A1-002: `UserDefaults(suiteName:)` is read inside hot path `expandConfigForTunnel` with no caching, and value reflects last-known disk state from a different process
- **Location:** `SingBox/SingBoxConfigLoader.swift:325, 400, 439`
- **Dimension:** thread-safety + performance
- **Description:** Three independent `UserDefaults(suiteName: AppGroupContainer.identifier)` calls happen every time `expandConfigForTunnel` runs. The factory itself is cheap, but each `bool(forKey:)` / `object(forKey:)` against an App Group suite forces a `cfprefsd` IPC round-trip on iOS when the suite has not been hydrated in this process. More importantly, the main app writes these flags via `@AppStorage(store:)`; reads from the extension may see stale values for several seconds because `cfprefsd` synchronization across container boundaries is eventual (Apple QA1923; confirmed in memory `feedback_extension_toggle_app_group_suite.md`). A user who flips a toggle and immediately reconnects gets the **previous** value injected into the live tunnel.
- **Why it matters:** A user who enables STUN-block / Mux / routing-rules and then taps Connect may run the next session without the feature enabled — the toggle appears non-deterministic. Worse, debugging "why is mux not active" loses obvious bisection points. Also each suite read in extension contends with main-app writes through `cfprefsd`, which on Phase 6d work (memory `feedback_nevpn_xpc_mach_port.md`) has caused port exhaustion under iOS 26.
- **Suggested fix:** Pass these three flags into `expandConfigForTunnel` as parameters; main app reads `UserDefaults` once at `connect()` time and stuffs the three booleans into `providerConfiguration` alongside `configJSON`. Extension reads from `providerConfiguration` (already in memory, no IPC, atomic per-start).

### [HIGH] A1-003: `expandConfigForTunnel` is documented "idempotent" but the route.rules sniff-insert and STUN-block-insert violate that contract on partial-feature toggle
- **Location:** `SingBox/SingBoxConfigLoader.swift:285-292, 403-422`
- **Dimension:** bugs + logic
- **Description:** Block 4 inserts `["action": "sniff"]` at index 0 if no `sniff` action already exists. Block 6 (STUN) inserts after `hijack-dns`. The contract says "идемпотентно". But: if the input JSON already has BOTH a sniff rule AND an existing STUN block rule (e.g., from a manually authored config), block 4 still succeeds; if the input JSON has NEITHER sniff NOR hijack-dns (e.g., a config without DNS hijack — possible for a config that simply uses external DNS outbound), `insertIdx = rules.count` and STUN block lands at end, breaking the documented insertion guarantee ("ПОСЛЕ hijack-dns (DNS должен работать) и ДО Phase 8 priority rules"). Block 5 priority rules also calculate `insertIdx` from `hijack-dns` position — if hijack-dns is absent, all three priority rules land at the end, after any user-defined rules — silently changing routing semantics.
- **Why it matters:** A user supplying a Hiddify/custom config without DNS hijack rule will see priority rules (block/never/always) appended after their own rules instead of before. Combined with `bbtb-block → reject` ending up after a user `outbound: direct` rule, blocklisted domains can bypass blocking.
- **Suggested fix:** Either: (a) make the helper require sniff+hijack-dns to exist as a precondition (add to `validate(json:)`), or (b) explicitly compute `insertIdx` from the first non-sniff/non-hijack-dns rule index, falling back to position 0 (not `rules.count`).

### [MEDIUM] A1-004: `BaseSingBoxTunnel` is `@unchecked Sendable` with mutable `commandServer` / `platformInterface` written from non-isolated threads
- **Location:** `SingBox/BaseSingBoxTunnel.swift:50, 81-86, 343-358`
- **Dimension:** thread-safety + Swift 6
- **Description:** `commandServer` and `platformInterface` are non-atomic instance properties. They are read on the provider queue (e.g., `stopTunnel`, `sleep`, `wake`) and written on `DispatchQueue.global(qos: .userInitiated)` inside the `startOrReloadService` async block at line 343-358 (writes `self?.commandServer = nil`, `self?.platformInterface = nil` on failure). NetworkExtension does serialize start/stop, but a fast Settings-disable arriving while the background dispatch is in flight is a documented race (memory `feedback_tunnelcontroller_disconnect_race.md`). `@unchecked Sendable` silences the compiler; the actual read/write happens-before is not enforced.
- **Why it matters:** Race window between background dispatch and `stopTunnel` could double-free `commandServer` (already nil'd by failure path, then `closeService()` invoked again in `stopTunnel`) — LibboxCommandServer is a Go-managed object; double-close is engine-defined behavior and has historically caused crashes in sing-box-for-apple.
- **Suggested fix:** Move the two properties under a `DispatchQueue.barrier` or, simpler, do not nil them out from the background dispatch — return the error and let `stopTunnel` (which is invoked by NetworkExtension after `completionHandler(error)`) own the cleanup. The pattern already works elsewhere in the file (line 275 in start-failure path is fine because it runs on provider queue).

### [MEDIUM] A1-005: `configJSONValidatedAt` cache uses ISO8601 string from `providerConfiguration` — no signature, attacker-controlled freshness
- **Location:** `SingBox/BaseSingBoxTunnel.swift:122-135, 219-231`
- **Dimension:** security
- **Description:** `shouldSkipPreExpandValidate` trusts an ISO8601 string carried inside `providerConfiguration`. `providerConfiguration` is writable by the main-app process via `NETunnelProviderProtocol`, so any local privilege escalation that can write to the VPN profile (e.g., MDM-installed config payload, or a buggy code path) can stuff `configJSONValidatedAt: <future date>` and disable the R1 pre-expand validate gate. The comment correctly notes that the **post-expand** validate at line 320-327 still runs — this is the saving grace — but post-expand only catches malicious additions from `expandConfigForTunnel`, not malicious inputs that pre-expand was meant to catch (forbidden inbound types, experimental APIs).
- **Why it matters:** Attack scenario: a malicious config payload sets `inbounds: [{type: "socks", listen: "127.0.0.1", port: 1080}]` and `configJSONValidatedAt: <fresh ISO8601 string>`. Pre-expand skipped. `expandConfigForTunnel` does not remove the socks inbound. Post-expand re-validates and **catches it** (the white-list is on inbound types). So the practical exploitability is blocked — but the defense-in-depth layering pretends pre-expand still runs, when in fact it can be bypassed at will.
- **Suggested fix:** If the cache marker stays, sign it (HMAC the JSON+timestamp with a key in Keychain), or compute a content-hash of `configJSON` and stuff `(hash, timestamp)` so the marker is bound to a specific JSON the host validated. Otherwise, drop the optimization — pre-expand validate is ≤ a few hundred microseconds, not a meaningful cold-start cost.

### [MEDIUM] A1-006: `ExtensionPlatformInterface` mutable state read from libbox Go-runtime threads without explicit memory barrier
- **Location:** `SingBox/ExtensionPlatformInterface.swift:42-63, 220-258, 331-362`
- **Dimension:** thread-safety + Swift 6
- **Description:** `currentInterfaceIndex`, `autoDetectCallCount`, `physicalInterfaceSeeded`, `nwMonitor`, `networkSettings` are plain `var` properties on a class marked `@unchecked Sendable`. `notifyInterfaceUpdate` runs on `DispatchQueue.global()` (line 318). `autoDetectControl(_:)` runs on libbox Go-runtime threads. Both touch `currentInterfaceIndex` and `physicalInterfaceSeeded` with no atomic/lock — the only sync primitive is `physicalInterfaceReady` semaphore, which orders the **first** seed but provides no read-coherency for subsequent updates (e.g., user changes from Wi-Fi to Cellular: NWPathMonitor sets `currentInterfaceIndex = N`; libbox concurrently reads it on another thread; Swift gives no guarantee the read sees the new value).
- **Why it matters:** A stale `currentInterfaceIndex` is bound into `IP_BOUND_IF` for new outbound sockets, attaching them to a no-longer-default interface. Symptom: brief connectivity stall after a Wi-Fi→Cellular handoff that should be invisible. Also `autoDetectCallCount += 1` race-tears the counter, but that is cosmetic.
- **Suggested fix:** Wrap reads/writes in a dedicated `DispatchQueue` (serial) used by both monitor callbacks and `autoDetectControl`. Or convert to actor (requires bigger refactor due to libbox sync semantics). At minimum, use `OSAtomic` / `Atomic<UInt32>` for the interface index.

### [MEDIUM] A1-007: `setTunnelNetworkSettings` semaphore wait on libbox thread blocks Go runtime — but the 2s timeout is below the documented worst case
- **Location:** `SingBox/ExtensionPlatformInterface.swift:129, 325`
- **Dimension:** bugs + performance
- **Description:** `openTun`'s 2s semaphore timeout is short. The comment claims "iPhone 13+ обычно <100ms"; in real cold-start scenarios after device reboot or under memory pressure, `setTunnelNetworkSettings` completion can take 3-5 seconds (multiple WireGuard iOS bug reports). The same 2s timeout is used in `startDefaultInterfaceMonitor` (line 325) and `clearDNSCache` (line 447, 453). On timeout, `openTun` throws and libbox aborts the tunnel start with no second chance — the user sees a connection failure that retry-on-foreground may not recover (the `commandServer.startOrReloadService` path is already executed).
- **Why it matters:** First-launch on a cold-rebooted iPhone shows intermittent "connection failed" with no clear cause. The 5s previous value was lowered to 2s in Phase 6c, but the rationale ("Phase 6c on-demand retry дешевле короткая ошибка") assumes on-demand retry is enabled and effective — on Internal TestFlight first impressions, this is exactly the worst path.
- **Suggested fix:** Raise `openTun` timeout to 5s (matches WireGuard iOS, sing-box-for-apple canonical), keep diagnostic logging on timeout. The 2s `clearDNSCache` timeout is acceptable since it's a non-critical reconfigure.

### [MEDIUM] A1-008: `expandConfigForTunnel` re-serializes JSON with non-deterministic key ordering — breaks `configJSON` hash-based caching downstream
- **Location:** `SingBox/SingBoxConfigLoader.swift:461-465`
- **Dimension:** bugs + performance
- **Description:** `JSONSerialization.data(withJSONObject: root, options: [])` does not guarantee key ordering of dictionaries. Each `expandConfigForTunnel` call may produce a different byte sequence for the same logical JSON, defeating any downstream caching that hashes the result (Phase 8 / Rules Engine appears to do this in main app per memory notes). It also makes diff'ing two extension log dumps painful.
- **Why it matters:** Cache invalidation cascades — if a hash-based marker exists upstream, every connect re-triggers full pipeline work. Cosmetic noise in logs.
- **Suggested fix:** Pass `.sortedKeys` to the options bitmask: `JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])`.

### [MEDIUM] A1-009: sing-box log file grows unbounded in DEBUG, written to App Group root — and DEBUG flag is build-config-driven, not user-controllable
- **Location:** `SingBox/BaseSingBoxTunnel.swift:295-301`; `AppGroupContainer.swift:95-97`
- **Dimension:** performance + bugs
- **Description:** In `#if DEBUG`, `logPath = singBoxLogPath` (App Group root, no rotation), `logLevel = "trace"`. Sing-box trace logs are extremely verbose (per-packet). The file has no rotation — multi-day debug session can fill the App Group container, which on iOS has a soft quota and shares pressure with the main-app's SwiftData store. Comment line 290 acknowledges this was Phase 5's pain point ("extension писал десятки MB на каждое соединение"). Release is safe (logPath=nil, level=info) — but engineers running DEBUG builds for hours on real devices can OOM the container, triggering jetsam on the extension.
- **Why it matters:** Internal TestFlight builds are Release, so users are safe. But during pre-flight bug triage with DEBUG sideloads, the log will keep growing, leading to confused "extension crashes randomly" reports.
- **Suggested fix:** Add size-based rotation (cap at e.g. 10 MB, rename `.log` → `.log.1` and truncate) on every `startTunnel`. Or use `os_log` only and remove the file sink entirely — `os_log` is already preferred per `TunnelLogger.swift`.

### [MEDIUM] A1-010: `clearDNSCache` does `reasserting = true → setTunnelNetworkSettings(nil) → restore` but does NOT clear `reasserting=false` on timeout path
- **Location:** `SingBox/ExtensionPlatformInterface.swift:441-458`
- **Dimension:** bugs
- **Description:** Flow: `provider.reasserting = true` → s1.wait (may timeout) → s2.wait (may timeout) → `provider.reasserting = false`. If `setTunnelNetworkSettings(nil)` completion never fires AND the second `setTunnelNetworkSettings(networkSettings)` also times out, `reasserting` is still cleared (line 457) — good. BUT: the network settings on the OS side are now in an undefined state because we called `setTunnelNetworkSettings(nil)` and never restored. The provider is back to "fully reasserting=false" but the tunnel has no settings → traffic is black-holed by iOS until next reconnect.
- **Why it matters:** Rare but real iOS bug where `setTunnelNetworkSettings` completion is dropped. User experience: VPN appears connected, all traffic stalls until manual disconnect/reconnect.
- **Suggested fix:** Check `waitResult2` on the restore call; on timeout, trigger a `cancelTunnelWithError(...)` so OS forces a clean restart instead of leaving the provider in a half-state.

### [LOW] A1-011: `AppGroupContainer.url` calls `fatalError` on missing entitlement — production crash instead of graceful failure
- **Location:** `AppGroupContainer.swift:11-18`
- **Dimension:** bugs
- **Description:** `fatalError` is reasonable for a "this should never happen" misconfiguration, but on TestFlight first-launch with an entitlement provisioning hiccup, this crashes the extension with no log line that survives. Apple's crash reports show this as "EXC_BAD_ACCESS in PacketTunnel.appex" — not actionable for support.
- **Why it matters:** Provisioning issues during TestFlight roll-out are common; a crash report is harder to debug than a logged error path.
- **Suggested fix:** Replace `fatalError` with `TunnelLogger.security.fault(...)` + return a sentinel; downstream `singBoxWorkingPath` getter returns "/dev/null" and `startTunnel` fails with a typed error early.

### [LOW] A1-012: `validate(json:)` strict-checks experimental block but accepts `dns` field as fully arbitrary
- **Location:** `SingBox/SingBoxConfigLoader.swift:93-104`
- **Dimension:** security
- **Description:** R1 + SEC-06 white-lists inbounds and bans experimental APIs, but `dns` block can contain `address: "dhcp://..."` or `dns_server: "8.8.8.8"` rules that bypass user DNS settings, and there's no validate gate on the DNS section at all. Combined with A1-005, a malicious provider configuration could plant a custom DNS rule that exfiltrates query data even with a well-formed proxy outbound.
- **Why it matters:** Subscription provider that ships a malicious config can hijack DNS resolution without tripping R1 — the user's DoH preference at `1.1.1.1` is overridden if the config supplies its own DNS block.
- **Suggested fix:** Either (a) normalize `dns` to a known-safe block during expand, or (b) add a validate check that warns on unexpected DNS keys. Phase 13 scope is internal-only so this is low priority.

### [LOW] A1-013: `LibboxBootstrap.setup` called on every startTunnel — comment claims idempotent, no defensive guard
- **Location:** `SingBox/BaseSingBoxTunnel.swift:236-246`
- **Dimension:** performance
- **Description:** Comment says "Идемпотентно для re-start цикла" but the underlying gomobile `LibboxSetup` re-creates paths each call. Cheap on warm process but adds ~5-20ms to every connect cycle. Since `BaseSingBoxTunnel` is reinstantiated by NetworkExtension on every tunnel restart (extension process can be recycled too), there's no persistent guard.
- **Why it matters:** Minor connect-time tax. Combined with A1-002 IPC overhead, contributes to perceived sluggishness on rapid reconnect.
- **Suggested fix:** Add a `static var didSetup = false` guard; this is safe within an extension process lifetime.

### [LOW] A1-014: `PlatformHooks.shouldDisableEnforceRoutes()` reads `UserDefaults` synchronously every call without caching
- **Location:** `PlatformSpecific/macOS.swift:19-22`
- **Dimension:** performance
- **Description:** Called from `KillSwitch.apply(to:enabled:)`; if that itself is called on hot paths, each call hits `cfprefsd`. Out of scope for the iOS TestFlight phase since this is `#if os(macOS)`, but worth noting that the same pattern repeats in `SingBoxConfigLoader` (A1-002) and the fix is identical.
- **Why it matters:** macOS-only; deferred until macOS Phase. Mentioned for pattern hygiene.
- **Suggested fix:** Cache in a static `Once` or pass through `providerConfiguration`.

## Notes

**Cross-file pattern:** The codebase has a clear and well-commented separation between "engine-agnostic utilities" and "sing-box specifics". `@unchecked Sendable` is used in three places (`BaseSingBoxTunnel`, `ExtensionPlatformInterface`, `UncheckedSendableBox`) — all are pragmatic Swift 6 escape hatches, but only `UncheckedSendableBox` has a comment explaining the contract. The two class-level `@unchecked Sendable` markers (A1-004, A1-006) have weaker actual happens-before guarantees than the comments imply.

**App Group reads from the extension are a recurring smell:** four read sites (SingBoxConfigLoader x3, macOS PlatformHooks x1) plus the `ExternalVPNStopMarker` read in `BaseSingBoxTunnel.startTunnel`. The marker pattern is fine (write-only from extension, read at start). The three toggle reads inside `expandConfigForTunnel` should be hoisted into `providerConfiguration` to eliminate IPC, eventual-consistency races, and dependency on `cfprefsd` (A1-002).

**Defense in depth on R10 (post-expand validate) is solid** — the post-expand re-validation at line 320-327 of `BaseSingBoxTunnel` is the bedrock; even if A1-005 pre-expand cache bypass is exploited, post-expand catches forbidden inbounds. Worth keeping that invariant prominent during future refactors.

**Idempotency claim of `expandConfigForTunnel` is overstated:** A1-001 (STUN tag), A1-003 (insertion-index fallback), and A1-008 (key-order non-determinism) all chip away at the contract. Either downgrade the doc claim to "convergent under repeated invocation **assuming** sniff+hijack-dns prerequisites" or add explicit precondition validation.

**No CRITICAL findings** for TestFlight Internal: the highest-severity items are either security-defense-in-depth (post-expand layer still holds) or race conditions whose practical exploitability requires unusual conditions. The HIGH items A1-001/A1-002/A1-003 should be triaged before External TestFlight; for Internal-only (≤100 testers), they are acceptable known-issues if documented.
