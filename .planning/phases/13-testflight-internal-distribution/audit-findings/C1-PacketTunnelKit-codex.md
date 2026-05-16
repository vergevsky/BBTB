# C1 — PacketTunnelKit audit (Codex 5.5)

**Scope:** BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/
**Files audited:** 12 (11 Swift + 1 JSON resource)
**Total findings:** 6 (CRITICAL: 0, HIGH: 3, MEDIUM: 3, LOW: 0)

## Findings

### [HIGH] C1-001: Command server leaks on post-start pre-service failures
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/BaseSingBoxTunnel.swift:303`
- **Dimension:** bugs | performance
- **Description:** `commandServer` is created and `server.start()` succeeds before `expandConfigForTunnel` and post-expand `validate`. If expand or validation throws, the method calls `completionHandler` but does not `close()` the already-started command server or clear `platformInterface`.
- **Why it matters:** A failed start can leave libbox command-channel resources alive in the extension process. Subsequent start attempts can hit stale state, socket/path conflicts, retained callbacks, or excess memory in the iOS extension budget.
- **Suggested fix:** Either expand/validate before creating the command server, or add a single cleanup path for every failure after `self.commandServer = server`.

### [HIGH] C1-002: Unsynchronized mutable state behind `@unchecked Sendable`
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:49`
- **Dimension:** thread-safety
- **Description:** `currentInterfaceIndex`, `physicalInterfaceSeeded`, `autoDetectCallCount`, `networkSettings`, and `nwMonitor` are read/written from libbox callback threads, `NWPathMonitor` callbacks, and provider stop/reset paths without a lock, actor, or serial queue. The `@unchecked Sendable` comment assumes sequential callback delivery, but the code itself starts `NWPathMonitor` on a global queue and `autoDetectControl` can be called per socket from Go runtime threads.
- **Why it matters:** Under Swift 6 strict concurrency this is an actual data-race risk. Races here can bind outbound sockets to index `0` or a stale interface, double-signal readiness, corrupt diagnostics counters, or race monitor cancellation during stop.
- **Suggested fix:** Put all mutable platform-interface state behind a dedicated serial queue/lock or a small actor-compatible state container, and make libbox callbacks hop through that synchronization point.

### [HIGH] C1-003: `validate` accepts non-dialable group-only proxy configs
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:113`
- **Dimension:** logic | bugs
- **Description:** `urltest` and `selector` count as proxy outbounds for `hasProxyOutbound`, but validation only checks references when `outbounds` is present and typed as `[String]`. A config with only `selector`/`urltest` and no children, empty children, or malformed children passes both pre- and post-expand validation.
- **Why it matters:** R10 is documented as a defense-in-depth gate before libbox startup, but this lets structurally unusable configs reach `startOrReloadService`. In TestFlight this becomes a late connection failure instead of a deterministic config error.
- **Suggested fix:** Treat group outbounds as proxy only if they resolve to at least one existing dialable proxy outbound; reject missing, empty, malformed, or group-cycle-only references.

### [MEDIUM] C1-004: Rule-set injection assumes cache files exist
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:338`
- **Dimension:** bugs | performance
- **Description:** The extension always injects three local binary rule sets when routing rules are enabled, but only ensures the cache directory exists. It does not verify that `bbtb-baseline-block.srs`, `bbtb-baseline-never.srs`, and `bbtb-baseline-always.srs` exist and are readable.
- **Why it matters:** The directory is under `Library/Caches`, so files can be absent on first launch, after cache purge, failed main-app warmup, or partial migration. sing-box may fail service startup because a referenced local rule-set path is missing.
- **Suggested fix:** Gate injection on all three files being present/readable, or ship/copy the baseline SRS files into the extension-visible App Group before start and fail with a clear config/cache error.

### [MEDIUM] C1-005: Production libbox messages are logged as public notice
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:501`
- **Dimension:** security | performance
- **Description:** `writeDebugMessage(_:)` logs arbitrary libbox/sing-box messages at `.notice` with `.public` privacy. Those messages can include connection metadata such as domains, endpoints, routing decisions, or DNS activity depending on sing-box log behavior.
- **Why it matters:** VPN extensions handle sensitive browsing/network metadata. Public notice-level logs are easier to collect from device logs and can also increase logging overhead during active traffic.
- **Suggested fix:** Drop this to debug level in release builds and use private/redacted interpolation for message bodies unless a specific safe subset is parsed.

### [MEDIUM] C1-006: App Group entitlement failure crashes the extension
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift:11`
- **Dimension:** bugs
- **Description:** `AppGroupContainer.url` calls `fatalError` if the App Group container is unavailable. Many hot paths call this during tunnel start, including libbox setup, rule-set path injection, and debug log path construction.
- **Why it matters:** A provisioning/profile/entitlement mismatch in TestFlight would terminate the PacketTunnel extension instead of returning a diagnosable `startTunnel` error. That makes field diagnosis harder and can look like an OS-level VPN failure.
- **Suggested fix:** Add a throwing/optional App Group resolver for extension startup paths and map failure to `completionHandler(TunnelError...)` with security/lifecycle logging.

## Notes

- No CRITICAL findings found.
- I did not run build or tests, per request.
- Read-only sandbox blocked clean git cache creation under `/tmp`, but `git log` and package source reads completed.
- Current package entries audited: 11 Swift files plus `SingBoxConfigTemplate.vless-reality.json`.
- I did not count the Phase 13 D-04 routing-rules toggle issue as a finding; the current source has the App Group gate in block 5.

**Verdict:** REQUEST CHANGES before TestFlight.
