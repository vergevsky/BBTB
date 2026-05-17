# C3 — MainScreenFeature (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 5 (0/2/2/1)

## Critical
No critical findings found in this MainScreenFeature pass.

## High
### C3'-3-001: `NEVPNStatusDidChange` still creates one MainActor job per duplicate event before dedupe runs
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:253`
- **Dimension:** Energy / reactive flood / MainActor starvation
- **Description:** The VM observer correctly uses `queue: nil`, reads `NEVPNConnection.status` and `connectedDate` synchronously, then enqueues `Task { @MainActor ... applyVPNStatus(...) }` for every notification (`MainScreenViewModel.swift:253-267`). The duplicate guard is inside `applyVPNStatus` (`MainScreenViewModel.swift:512-520`), so the known 8k duplicate-event class still produces 8k MainActor tasks before any coalescing happens. That avoids repeated `@Published` writes, but it does not protect the main executor from task flood, closure allocation, actor hops, or delayed UI work.
- **Why HIGH:** The historical failure mode was a reactive duplicate storm after connect. This path keeps the most expensive part of that storm on MainActor, just with cheaper per-task bodies. On a real device, hundreds of status echoes per second can still starve user input/animations and burn energy even though the state value is unchanged.
- **Suggested fix:** Keep `queue: nil`, but coalesce before hopping to MainActor. Options: route VM status through `TunnelController`'s already-deduped status path, add a small lock/actor-backed non-main coalescer keyed by `(status, connectedDate)`, or maintain one pending MainActor delivery that always applies the latest sample.

### C3'-3-002: Import and deep-link entry points are reentrant while `ConfigImporter` mutates SwiftData and Keychain
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:400`
- **Dimension:** Thread Safety / SwiftData write serialization
- **Description:** `importFromPasteboard`, `importFromQRString`, and `importFromFile` each spawn an unstructured MainActor task (`MainScreenViewModel.swift:400`, `MainScreenViewModel.swift:404`, `MainScreenViewModel.swift:417`). `handleDeepLink` starts a separate import-style task and sets `importInProgress = true` (`MainScreenViewModel.swift:1147-1154`). The shared worker `performImport` sets `importInProgress` but never checks it as an admission guard (`MainScreenViewModel.swift:777-795`). Because `@MainActor` methods are reentrant across `await`, two import tasks can overlap inside `ConfigImporter.importFromRawInput`, which creates its own `ModelContext`, merges/inserts rows, writes Keychain secrets, and saves (`ConfigImporter.swift:199-246`, `ConfigImporter.swift:280-320`). The Plan 05 mutex only serializes `provisionTunnelProfile` (`ConfigImporter.swift:561-564`), not these import paths.
- **Why HIGH:** A double tap, QR scan plus deep link, or file import plus paste import can run two SwiftData write transactions and Keychain tag writes concurrently against the same server/subscription tables. That can leave stale active-server selection, duplicated rows, lost merge results, or SwiftData context crashes on iOS 18+.
- **Suggested fix:** Add a real import serializer/admission gate. At minimum, `guard !importInProgress else { return }` before spawning/entering each import/deep-link task; stronger is an `AsyncMutex` or single `importTask` that serializes all `importFromRawInput` callers and deep-link import handling.

## Medium
### C3'-3-003: Foreground reentry has no in-flight coalescing around XPC, subscription fetch, and probe work
- **Location:** `BBTB/App/iOSApp/BBTB_iOSApp.swift:342`
- **Dimension:** Energy / foreground lifecycle
- **Description:** Every `.active` scene transition spawns a new `Task { @MainActor in await viewModel.handleForegroundReentry() }` on iOS and macOS (`BBTB_iOSApp.swift:330-342`, `BBTB_macOSApp.swift:286-294`). The handler then starts a detached upgrade pass, awaits foreground VPN resync, and runs `serverListViewModel.silentForegroundRefresh()` (`MainScreenViewModel.swift:740-773`). The silent refresh fetches every subscription and then pings all servers (`ServerListViewModel.swift:294-317`). There is no `foregroundReentryInProgress` flag or cancellation of a previous run.
- **Why MEDIUM:** Duplicate `.active` transitions, quick app switch churn, or separate platform hooks can overlap full subscription fetch + probe cycles. That is not a correctness blocker by itself, but it reintroduces the exact energy/XPC/network contention that the consolidated foreground hook was meant to control.
- **Suggested fix:** Coalesce foreground reentry with a single in-flight task or timestamp gate. If a run is active, either drop the new request or mark `needsForegroundRefresh = true` and perform one follow-up pass after the current one completes.

### C3'-3-004: `runIsSupportedUpgrade` throttle is set after the full pass, so detached foreground tasks can overlap
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:1181`
- **Dimension:** Thread Safety / Energy
- **Description:** `handleForegroundReentry` starts `runIsSupportedUpgrade` in a detached task (`MainScreenViewModel.swift:748-750`). The upgrade function reads the throttle timestamp and exits only if the last completed pass was within 5 minutes (`ConfigImporter.swift:1181-1183`), but it writes the timestamp at the very end (`ConfigImporter.swift:1223`). If two foreground reentry tasks start close together, both can pass the guard before either stores `now`, then both parse unsupported raw URIs, write Keychain payloads, mutate SwiftData rows, and save (`ConfigImporter.swift:1185-1220`).
- **Why MEDIUM:** This is a background path, but it can double work during foreground churn and overlaps SwiftData/Keychain mutation outside the Plan 05 provision serializer. It is also easy to trigger because the caller is detached and not awaited by the foreground hook.
- **Suggested fix:** Move the throttle claim to the start of the pass, or protect the method with an actor/async mutex plus `defer` cleanup if you want retry-on-failure semantics. Also check `Task.isCancelled` inside the candidate loop.

## Low
### C3'-3-005: Older failover auto-dismiss tasks can hide a newer failover banner
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:663`
- **Dimension:** Logic / UI state
- **Description:** `showFailoverBanner` starts a new 5-second MainActor sleep every time it is called (`MainScreenViewModel.swift:663-672`). The dismiss task only checks `if case .failover = reconnectBannerState`, not whether it is dismissing the same failover generation/server. If failover A fires and failover B fires 4 seconds later, A's old task wakes at 5 seconds and hides B after only ~1 second.
- **Why LOW:** This does not break the tunnel, but it makes multi-server failover feedback unreliable exactly when the user needs visibility into automatic recovery.
- **Suggested fix:** Store a `failoverDismissTask` and cancel/replace it on each new banner, or track a generation token/server name and only dismiss if the token still matches.

## Notes
- I read `AUDIT-2.md` first and did not re-report the Plan 05 T-B5' `ProvisionSerializer` reentrancy closure or the T-C9' `resolveConnectionSince` / future-clock clamp closure.
- The `NEVPNStatusDidChange` observers I checked use `queue: nil`, not `.main` (`MainScreenViewModel.swift:253`, `TunnelController.swift:562`). The remaining issue is pre-hop coalescing, not observer queue selection.
