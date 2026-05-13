# Phase 6d Audit — GEMINI Pass

### 1. Executive Summary
- **Root Cause of Phase 5 "Heavy Feel" Identified:** An unaddressed Phase 5 TODO left `sing-box` unconditionally writing tens of megabytes of `trace` logs to disk, severely degrading system energy efficiency and dragging down performance across the board.
- **Critical Launch Bottleneck:** The aforementioned massive trace log is synchronously copied from the App Group to the Documents directory on the main thread during `App.init()`, creating a massive, unbounded cold start hitch before the UI can even render.
- **Connect-Tap Redundancies:** The `.connect()` method performs back-to-back, redundant XPC trips to `sysextd` (applying intent rules and then separately applying `isEnabled = true`), causing up to 6 slow inter-process calls in the direct hot path of a user tap.
- **MainActor Starvation:** Both the launch sequence (`refresh()`) and the Connect Tap sequence (`performPreConnectAutoSelect`) perform un-yielded, synchronous SwiftData disk fetches directly on the `@MainActor`, further compounding UI latency.

### 2. Findings

| # | Title | Dimension | Severity | File:Line | Description | Recommended fix |
|---|---|---|---|---|---|---|
| 1 | Synchronous log export blocks `App.init` | Launch | HIGH | `BBTB/App/iOSApp/BBTB_iOSApp.swift:23` | The app synchronously copies the `sing-box.log` file from the App Group to the Documents directory during App initialization, blocking the main thread before the first SwiftUI view renders. | Remove the Phase 1 debug bridge `AppGroupContainer.exportSingBoxLogToDocuments()` call entirely from `init()`, or move it to a background `Task`. |
| 2 | Trace logging causes massive I/O and energy drain | Energy | HIGH | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift:115` | A leftover Phase 5 TODO leaves the tunnel unconditionally running sing-box with `logLevel: "trace"`. This continuously writes tens of MBs to disk, draining battery and making the system "feel heavy." | Downgrade `logLevel` to `"warn"` or `"error"`, and disable `logPath` entirely for production builds inside `expandConfigForTunnel`. |
| 3 | Redundant XPC trips in `connect()` / `disconnect()` | Performance | HIGH | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:108` | `connect()` performs `applyCurrentStateToCachedManager()` (triggering an XPC load/save/load sequence) and immediately performs another `loadAll` / `save` / `load` cycle to set `isEnabled = true`. This causes up to 6 slow IPC calls to `sysextd`. | Consolidate updates. Load the manager once, apply both the On-Demand rules AND `isEnabled = true` to the same object, then perform exactly one `saveToPreferences()` and `loadFromPreferences()` sequence. |
| 4 | MainActor blocking SwiftData fetch on auto-connect | Performance | HIGH | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:338` | `performPreConnectAutoSelect()` executes a synchronous `context.fetch` on the `@MainActor` to load all supported servers for probing. This blocks the UI thread causing a noticeable hitch exactly when "Connect" is tapped. | Extract the fetch into an `async` method inside `ConfigImporter` using `Task.detached { ... }` or a `@ModelActor` to execute the database query off the main thread. |
| 5 | Sequential Keychain reads stall pool provisioning | Performance | MEDIUM | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:420` | During auto-connect, `provisionTunnelProfile` loops over all supported configs and calls `reparseFromKeychain` sequentially. `SecItemCopyMatching` is slow; doing dozens of sequential reads blocks the cooperative thread pool. | Wrap the `supported` iteration loop in `withTaskGroup` to fetch Keychain secrets concurrently, dramatically reducing the total latency for building the urltest pool. |
| 6 | Multiple synchronous fetches block UI on `refresh()` | Launch | MEDIUM | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:110` | On launch, `refresh()` invokes three distinct methods (`countSupportedConfigs`, `resolveServerLineName`, `reconcileSelectionWithStore`) that each create a new `ModelContext` and perform synchronous fetches on the `@MainActor`. | Consolidate these reads into a single `Task.detached` function that returns a tuple containing all required view-state values, then apply them to the `@Published` properties on the MainActor. |

### 3. Methodology
I utilized a targeted depth-first search approach:
- **What I read:** I read the iOS and macOS entry points (`BBTB_iOSApp.swift`, `BBTB_macOSApp.swift`) to trace the cold start. To investigate the Connect tap, I performed a full read of `TunnelController.swift`, `MainScreenViewModel.swift`, `ConfigImporter.swift`, and `TunnelWatchdog.swift`. Noting the Phase 5 "heavy feel" symptom, I read `BaseSingBoxTunnel.swift` and `PacketTunnelProvider.swift` to inspect the actual extension boot sequence and resource consumption. I also inspected `KeychainStore.swift` to confirm the synchronous nature of the API used.
- **What I skipped:** I skipped deep dives into the individual protocol parsers (e.g., `VLESSURIParser`, `ClashYAMLParser`) and protocol registry (`ProtocolRegistry.swift`) since UI hitching and energy drain during idle operation are rarely caused by string parsing that happens exclusively at the time of import. I also skipped `ServerListFeature` as it was explicitly outside the focus of the cold start and connect tap pain paths.
- **Why:** To rigorously enforce the Phase 6c invariants, I needed to observe exactly where Swift Concurrency crossed with older synchronous Apple frameworks (`SwiftData` contexts on `@MainActor`, `Keychain` API, and `NetworkExtension` XPC calls). The discovery of the leftover `trace` log bridges the gap between both the Connect Tap hitch and the Energy complaints perfectly.

### Closing
- **Estimated pass duration:** ~10-15 minutes (AI reading time).
- **Confidence levels:**
  - Performance: **HIGH** (the XPC trips and synchronous DB accesses are undeniable bottlenecks).
  - Energy: **HIGH** (I/O heavy trace logging on an NE extension is notoriously expensive).
  - Launch: **HIGH** (copying tens of megabytes on `App.init()` on the main thread is a severe block).
  - Simplicity: **MEDIUM** (addressed by consolidating DB fetches and XPC trips).
  - Memory: **MEDIUM** (the memory growth caused by loading all objects for a boolean toggle flag is present but standard for currently available SwiftData paradigms).

---

**Source:** `mcp__gemini__gemini` (sandbox=read-only, model=`gemini-3.1-pro-preview` — primary, no fallback needed)
**Date captured:** 2026-05-14
