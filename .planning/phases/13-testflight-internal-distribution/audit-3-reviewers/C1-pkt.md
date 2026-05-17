# C1 — PacketTunnelKit (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 6 (0/2/3/1)

## Critical
No critical findings found in this PacketTunnelKit pass.

## High
### C1'-3-001: `route.rule_set` entries are trusted, including remote URLs and arbitrary local paths
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:144`
- **Dimension:** Security / route.rule_set path validation
- **Description:** `validate(json:)` enters the `route` block but only validates `route.rules[].outbound` and `route.final` references. It does not reject operator-supplied `route.rule_set` entries, does not force `type == "local"`, does not force paths under `AppGroupContainer.rulesCacheDirectory`, and does not reject `type:"remote"`/`url` rule sets. `expandConfigForTunnel` then preserves any existing rule-set declarations and appends BBTB entries only for missing tags (`SingBoxConfigLoader.swift:368`). This is separate from the Plan 05 T-C6' closure, which fixed outbound references but not rule-set source/path policy.
- **Why HIGH:** Imported/operator JSON can make the Network Extension hand sing-box unreviewed rule-set sources. At best this can make the tunnel fail or load attacker-controlled routing state; at worst it bypasses the app's hardened fetch/SSRF controls by letting sing-box perform its own remote rule-set fetches or read unexpected sandbox/App Group paths.
- **Suggested fix:** In `validate(json:)`, allow only local binary rule sets whose `path` is canonicalized under `AppGroupContainer.rulesCacheDirectory` and whose basename matches the expected BBTB rule files, or strip all incoming `route.rule_set` entries and let `expandConfigForTunnel` be the single source of truth. Reject `remote` rule sets and any path containing symlinks, `..`, non-file URLs, or paths outside the cache directory.

### C1'-3-002: `ExtensionPlatformInterface` has unsynchronized hot-path state shared across libbox and `NWPathMonitor` threads
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:27`
- **Dimension:** Thread Safety / Swift 6 strict concurrency
- **Description:** The class is marked `@unchecked Sendable` and documents a sequential-callback assumption, but mutable fields such as `networkSettings`, `nwMonitor`, `currentInterfaceIndex`, `physicalInterfaceSeeded`, and `autoDetectCallCount` are plain vars (`ExtensionPlatformInterface.swift:38`, `ExtensionPlatformInterface.swift:42`, `ExtensionPlatformInterface.swift:49`, `ExtensionPlatformInterface.swift:59`, `ExtensionPlatformInterface.swift:63`). `autoDetectControl(_:)` reads/mutates them from libbox Go-runtime callback threads (`ExtensionPlatformInterface.swift:220`), while `NWPathMonitor` updates them on a global dispatch queue (`ExtensionPlatformInterface.swift:310`) and `reset()`/`closeDefaultInterfaceMonitor` can mutate them from the NE lifecycle path.
- **Why HIGH:** This is the connection hot path for `includeAllNetworks=YES`. A stale or torn `currentInterfaceIndex` can bind outbound sockets to interface 0 or an old physical interface, causing looped sockets, handshake failures, or traffic pinned to the wrong network after Wi-Fi/cellular changes. The `@unchecked Sendable` suppresses Swift 6 diagnostics instead of providing an actual synchronization boundary.
- **Suggested fix:** Put all mutable platform-interface state behind a private serial queue, lock, or actor-like executor. Route `NWPathMonitor` callbacks, libbox callbacks that read/write shared state, and `reset()` through that same synchronization primitive. Keep the semaphore handoff only for the “first physical interface ready” event, not as the general memory-safety mechanism.

## Medium
### C1'-3-003: Stop/start lifecycle can race while `startOrReloadService` is still running
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/BaseSingBoxTunnel.swift:353`
- **Dimension:** Thread Safety / NEPacketTunnelProvider lifecycle
- **Description:** `startTunnel` dispatches `server.startOrReloadService(...)` to a global queue, then later mutates provider state and calls the start completion from that background closure. `stopTunnel` can concurrently close the same `commandServer` and nil out `platformInterface` (`BaseSingBoxTunnel.swift:396`) without a lifecycle lock/state machine. The background start path can still complete after a stop request and call `completionHandler(nil)` (`BaseSingBoxTunnel.swift:359`) against a service that was already closed.
- **Why MEDIUM:** This is an edge-case user/OS race during rapid connect-disconnect, failed starts, or extension teardown. It can surface as false “connected” completion, double close, stale `commandServer` ownership, or non-deterministic restart behavior.
- **Suggested fix:** Add a lifecycle serial queue and a start generation token. `stopTunnel` should mark the generation cancelled before closing the server; the async start closure should check that token before reporting success or mutating provider fields. Keep all `commandServer`/`platformInterface` ownership changes on one queue.

### C1'-3-004: `clearDNSCache()` can issue repeated two-XPC reconfiguration cycles without coalescing
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:441`
- **Dimension:** Energy / XPC trip count cap
- **Description:** Every libbox `clearDNSCache()` callback performs `setTunnelNetworkSettings(nil)` and then restores settings (`ExtensionPlatformInterface.swift:446`, `ExtensionPlatformInterface.swift:452`). Each invocation can therefore spend up to four seconds waiting on two NetworkExtension XPC completions, and there is no in-flight flag, debounce, or rate limit if libbox calls this repeatedly.
- **Why MEDIUM:** The per-call trip count is capped at two, but the call site is not coalesced. A burst of DNS-cache-clear callbacks during network churn can keep the extension awake, churn NE settings, and make the tunnel appear unstable even though only one reset is useful.
- **Suggested fix:** Coalesce `clearDNSCache()` with an atomic/serialized `isClearingDNSCache` flag and a short debounce window. Drop or merge callbacks while one two-step reset is in flight, and consider using an event-driven trigger from path changes instead of honoring every libbox request immediately.

### C1'-3-005: Libbox messages and notifications are logged as public production-visible data
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:503`
- **Dimension:** Security / App Group and tunnel telemetry exposure
- **Description:** `writeDebugMessage(_:)` logs arbitrary libbox messages at `notice` with `.public` privacy. `send(_:)` also logs notification title/body as public (`ExtensionPlatformInterface.swift:466`). These strings are generated outside PacketTunnelKit's typed config model and can include server names, routing decisions, remote errors, or future protocol fields.
- **Why MEDIUM:** VPN metadata is sensitive even when it is not a raw password. Public `notice` logs are visible in production diagnostics and can expose server domains/IPs, SNI/fronting hostnames, or user routing state in sysdiagnose/Console output.
- **Suggested fix:** Downgrade arbitrary libbox debug output to `debug` and log it with private privacy by default. If selected fields need production visibility, parse/whitelist those fields explicitly and keep server identifiers/private config values redacted.

## Low
### C1'-3-006: Future `configJSONValidatedAt` timestamps skip pre-expand validation for longer than intended
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/BaseSingBoxTunnel.swift:134`
- **Dimension:** Logic / validation freshness
- **Description:** `shouldSkipPreExpandValidate` returns `now.timeIntervalSince(validatedAt) < 24 * 3600`. If the stored timestamp is in the future because of clock skew or corrupted provider configuration, the interval is negative and the pre-expand validation cache is treated as fresh until 24 hours after that future timestamp.
- **Why LOW:** Post-expand validation still runs unconditionally, so this does not reopen the Plan 05 route-reference closure. It is still a brittle freshness check and can hide stale/corrupt provider configuration from the cheaper pre-expand gate for longer than designed.
- **Suggested fix:** Require `validatedAt <= now` and reject timestamps with excessive future skew before applying the 24-hour freshness window.

## Notes
- I read `AUDIT-2.md` first and did not re-report the Plan 05 T-C6' `route.rules[].outbound` / `route.final` closure or the T-B9 command-server cleanup/STUN schema closures.
- No CRITICAL findings were identified in this pass.
