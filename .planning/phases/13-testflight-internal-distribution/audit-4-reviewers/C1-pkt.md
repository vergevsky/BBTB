# C1 — PacketTunnelKit (Codex 5.5)
**Baseline:** ccbce8a
**Total findings:** 4 (0/2/1/1)

## Plan 07 closure verification
- T-C-H1' route.rule_set: PASS
- T-C-H5' lifecycle race: FAIL
- T-C-H2' state queue: FAIL
- T-C-B1 adaptive timeout: PASS

## Critical
No critical findings in this PacketTunnelKit pass.

## High

### C1-4-001: Generation check still allows double-close between check and close
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/BaseSingBoxTunnel.swift:400`
- **Dimension:** Thread Safety / lifecycle race
- **Description:** The Plan 07 fix adds `lifecycleQueue` and `startGeneration`, but the async `startOrReloadService` error path checks `startGeneration` at `BaseSingBoxTunnel.swift:400-403`, releases `lifecycleQueue`, then closes the captured `server` at `BaseSingBoxTunnel.swift:405-406`. `stopTunnel` can run in that gap, increment the generation and capture/nil the same server at `BaseSingBoxTunnel.swift:449-456`, then close it at `BaseSingBoxTunnel.swift:457-463`. The async error path then resumes and closes the already-closed `LibboxCommandServer`.
- **Why HIGH:** This is the same rapid Connect -> Disconnect crash class Plan 07 intended to close. The generation check detects a stop only if the stop happened before the check; it does not make close ownership atomic. A real interleaving remains: error path checks "current", `stopTunnel` closes, error path closes again. Go/gomobile command-server close APIs are not documented as idempotent, so this can still produce extension SIGABRT or undefined libbox state.
- **Fix:** Move ownership transfer into one `lifecycleQueue.sync` block: if `startGeneration == capturedGeneration && self.commandServer === server`, set `commandServer = nil` and `platformInterface = nil`, return the server-to-close, then call `closeService()`/`close()` outside the queue. If the block returns nil, another lifecycle path already owns cleanup. Also apply the generation check to the success path before `completionHandler(nil)` at `BaseSingBoxTunnel.swift:391-397`, otherwise a stopped start can still report success after `stopTunnel` completed.

### C1-4-002: `ExtensionPlatformInterface` still bypasses `stateQueue` for protected fields
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:170`
- **Dimension:** Thread Safety / Swift 6 strict concurrency
- **Description:** The new invariant says all reads/writes of `networkSettings`, `nwMonitor`, `currentInterfaceIndex`, `physicalInterfaceSeeded`, and `autoDetectCallCount` go through `stateQueue` (`ExtensionPlatformInterface.swift:65-79`). Several accesses still bypass it: `networkSettings` is written directly in `openTun` at `ExtensionPlatformInterface.swift:170` and read directly in `clearDNSCache` at `ExtensionPlatformInterface.swift:485`; `nwMonitor` is written directly in `startDefaultInterfaceMonitor` at `ExtensionPlatformInterface.swift:334`, cancelled/nil'd directly at `ExtensionPlatformInterface.swift:418-420`, and read directly in `getInterfaces` at `ExtensionPlatformInterface.swift:426-429`.
- **Why HIGH:** The highest-risk `currentInterfaceIndex` hot path is now mostly serialized, and `stateQueue.sync` itself is not an obvious deadlock source because listener callbacks and semaphore waits happen outside the queue. But the closure is incomplete: libbox callbacks, NWPathMonitor callbacks, and `BaseSingBoxTunnel.stopTunnel`/`reset()` can still concurrently read/write the same `nwMonitor` and `networkSettings` object references. That keeps the `@unchecked Sendable` data-race risk alive and can surface as stale DNS settings restore, monitor use-after-cancel behavior, or crashes during stop/reload churn.
- **Fix:** Route every access to the five documented fields through `stateQueue`. For `nwMonitor`, capture under the queue and cancel outside it. For `networkSettings`, write after `openTun` with `stateQueue.sync` and snapshot in `clearDNSCache` before making NE XPC calls.

## Medium

### C1-4-003: `clearDNSCache()` still performs uncoalesced two-step NE settings churn
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:484`
- **Dimension:** Energy / NetworkExtension XPC churn
- **Description:** Every libbox `clearDNSCache()` callback clears tunnel settings and restores them (`ExtensionPlatformInterface.swift:489-496`), with up to two 2-second waits (`ExtensionPlatformInterface.swift:490-498`). There is no in-flight flag, debounce, or rate limit.
- **Why MEDIUM:** One DNS cache reset can be reasonable, but repeated callbacks during network churn can stack expensive NE settings reconfiguration work, keep the extension awake, and prolong reasserting state. This is not closed by T-C-B1; that fix only restored the initial `openTun` wait to 5 seconds at `ExtensionPlatformInterface.swift:157-159`.
- **Fix:** Add a serialized `isClearingDNSCache`/`pendingDNSCacheClear` state and coalesce callbacks while one reset is in flight. Snapshot `networkSettings` through `stateQueue` before starting the two XPC calls.

## Low

### C1-4-004: `route.rule_set[].path` policy documents symlink rejection but does not resolve symlinks
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:204`
- **Dimension:** Security / path hardening
- **Description:** The new rule-set validator standardizes paths with `NSString.standardizingPath` (`SingBoxConfigLoader.swift:204`) and then checks the rules-cache prefix and basename (`SingBoxConfigLoader.swift:211-222`). `standardizingPath` collapses lexical components but does not resolve filesystem symlinks, despite the policy comment promising "Reject `..`, symlinks" at `SingBoxConfigLoader.swift:187`.
- **Why LOW:** BBTB's own injected entries are not rejected: they use `bbtb-baseline-block.srs`, `bbtb-baseline-never.srs`, and `bbtb-baseline-always.srs` under `AppGroupContainer.rulesCacheDirectory` (`SingBoxConfigLoader.swift:434-446`), and the tests cover representative own entries at `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift:323-333`. A symlink exploit would require some other bug or local filesystem access to pre-place the symlink in the rules directory, so this is defense-in-depth rather than the original HIGH path traversal issue.
- **Fix:** Either remove the symlink claim from the policy or resolve symlinks before the prefix check using `URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().standardizedFileURL.path` and apply the same prefix/basename checks to the resolved path.

## Notes
- T-C-H1' is structurally closed for the original issue: `type:"remote"` is rejected at `SingBoxConfigLoader.swift:197-200`, paths must be under `AppGroupContainer.rulesCacheDirectory` at `SingBoxConfigLoader.swift:211-214`, and unsafe basenames are rejected at `SingBoxConfigLoader.swift:216-223`.
- T-C-H5' does not introduce a self-deadlock in the reviewed paths: `stopTunnel` captures under `lifecycleQueue` and calls libbox close methods after releasing it (`BaseSingBoxTunnel.swift:449-463`). The remaining problem is ownership atomicity, not queue recursion.
- T-C-H2' does not show an obvious `stateQueue.sync` deadlock from libbox/NWPathMonitor callbacks: semaphore waits and `listener.updateDefaultInterface` happen outside `stateQueue` (`ExtensionPlatformInterface.swift:269-272`, `ExtensionPlatformInterface.swift:386-404`). The remaining problem is direct state access outside the queue.
- T-C-D3 and T-C-D4 are closed: `PacketTunnelKit.swift` is documentation-only (`PacketTunnelKit.swift:1-15`), and `InterfaceFlagsInspector` now uses `TunnelLogger.security.warning` instead of `print()` (`InterfaceFlagsInspector.swift:69-74`).
