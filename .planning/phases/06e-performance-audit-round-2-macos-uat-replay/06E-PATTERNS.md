---
phase: 06e
slug: performance-audit-round-2-macos-uat-replay
status: ready
created: 2026-05-14
type: pattern-map
---

# Phase 6e — Pattern Map

**Mapped:** 2026-05-14
**Files analyzed:** 4 MEDIUM × ~1–3 target files + 16 LOW × 4 themed bundles + 3 trivial imports + 5 optional new test files + 4 closure artifacts
**Analogs found:** 26 / 26 (100 % — all targets are EXISTING files, analogs live in same codebase / Phase 6d artifacts)
**Phase type:** **CLEANUP / REMEDIATION** (NOT feature phase). New net-new code limited к 5 optional test files (Wave 0 already complete; tests являются дополнениями).

> Каждый MEDIUM fix MUST уважать DEC-06d-01..06 + D-09 invariants + Phase 6c R18 sliding window. См. Section «Critical Preservation List» в конце документа.

---

## File Classification

### Wave 1 — MEDIUM fixes (atomic commits, per-commit regression gate)

| Finding | Target file (existing) | Role | Data flow | Closest analog | Match quality |
|---------|------------------------|------|-----------|----------------|---------------|
| **M7** scenePhase consolidation | `BBTB/App/iOSApp/BBTB_iOSApp.swift` + `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` + `MainScreenViewModel.swift` (add method) | SwiftUI scene observer + ViewModel async hook | event-driven (scenePhase) → sequential await | `MainScreenViewModel.handleForeground()` (M-View-Model.swift:544-560) — already coalesces XPC + applyVPNStatus through single async method | exact (same coalesce-into-async-method pattern) |
| **M10** loadFromStore idempotency + confirmDeleteSubscription collapse | `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` (single file, 6 call sites — lines 181, 224, 257, 282, 312, 323) | ViewModel — SwiftData fetch-all + Swift group | request-response (UI → SwiftData) | `ServerListViewModel.loadFromStore()` itself (line 328) + `confirmDeleteSubscription` early-exit branch (line 312 vs final 323) — duplicated cascade-delete refresh | role-match (idempotency guard = new pattern; collapse = local refactor) |
| **M8** validatedAt guard + L12 bundled | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` (lines 156-164 pre-expand; lines 240-251 post-expand) + `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (provision path that writes `providerConfiguration["configJSON"]`) | Tunnel extension validate gate + ConfigImporter timestamp setter | request-response (sync R1/SEC-06 enforcement) | `BaseSingBoxTunnel` post-expand validate (line 244-251) — defense-in-depth R10 pattern; `expandConfigForTunnel` invariant comment | exact (preserve R10 post-expand pattern; add pre-expand cache marker) |
| **M11** applyVPNStatus early-return guard | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (lines 410-487, `.connecting/.reasserting` branch, lines 420-436) | ViewModel — reactive UI driver | event-driven (NEVPNStatus → state mutation) | Existing `lastAppliedVPNStatus` outer-level guard (line 414) — Phase 6d post-fix `9b38796` | exact (mirror outer-guard idiom — same dedupe pattern at inner switch level) |

### Wave 2 — LOW themed bundles (single end-of-bundle regression gate)

| Theme | Findings | Target file cluster | Closest analog (existing perf/correctness/maintainability pattern) | Match quality |
|-------|----------|---------------------|---------------------------------------------------------------------|---------------|
| **A — perf** | L3, L4, L7, L8, L11, L13, L18 | `BBTB/Packages/Localization/Sources/Localization/L10n.swift`; `MainScreenView.swift:47-49`; `ServerListSheet.swift:35-55`; `QRScannerViewController.swift:40-41, 117`; `SettingsViewModel.swift:181-202`; `Protocols/{Shadowsocks,Hysteria2,VLESSReality,VLESSTLS,Trojan}/Sources/*/ConfigBuilder.swift`; `MainScreenViewModel.swift:97` (serverListViewModel) | `ConfigImporter` defer-throttle pattern (Phase 6d M3 `1099629` — `Task.detached(priority: .background)` + guard); `bbtbProvisionerDidSave` consumer chain (TunnelController.provisionerObserver line 577); `presentationDetents` body recomputation pattern (already used) | role-match (each LOW = local mechanical refactor) |
| **B — correctness** | L1, L9, L10, L20 | `ExtensionPlatformInterface.swift:372-383` (clearDNSCache); `MainScreenViewModel.swift:368-389` (failover banner); `TunnelWatchdog.swift:250-265` (fireFailover); `BaseSingBoxTunnel.swift:194-204` (commandServer.start catch) | `ExtensionPlatformInterface.openTun` 2-s timeout pattern (Phase 6d M16 `5a4db9f`); `TunnelWatchdog.handleObservedStatus` actor dedupe (Phase 6c) | exact (same defensive timeout / observer-fire-before-await / catch-cleanup idioms) |
| **C-1 — maintainability** | L2, L5, L14, L15 | `Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:159-169` + `TransportRegistry/WSTransportHandler.swift:36-47`; `UserNotificationsHelper.swift:37-125`; `ConfigImporter.swift:1010` (print() → Logger); `ExtensionPlatformInterface.swift:241,252,277,335` (.notice → .debug) | `WSTransportHandler` parameter-injection pattern (cross-protocol shared); `TunnelLogger` subsystem/category pattern (already canonical); Phase 6d M12 `1621a08` (VLESS+TLS WS-host fallback) | exact (M12 fix already canonized; L2 = mechanical replication) |
| **C-2 — L16 standalone (HIGH RISK)** | L16 (applyVPNStatus extraction) | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:410-487` | `OnDemandRulesBuilder.applyCurrentState(to:)` (static pure function pattern); `ConfigImporter.buildDNSConfig` (pure transform) — both = pure-function extraction analogs | role-match (extraction style matches; **but applyVPNStatus is D-09 single-authority — extreme caution**) |
| **D — trivial unused imports** | 3 files | `ServerDetailView.swift:18` (`import ConfigParser`); `ServerListSheet.swift:26` (`import ConfigParser`); `TransportPicker.swift:9` (`import DesignSystem`) | Periphery-flagged false-zero references; analog = standard SwiftPM-package import block (no other "scoped imports" pattern в codebase — used only top-level) | exact (trivial deletion, Periphery-verified) |

### Wave 0 — Optional NEW test files (up to 5)

| File (NEW) | Mapped finding | Analog test file | Match quality |
|------------|----------------|------------------|---------------|
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift` | M7 | `MainScreenFeatureTests/AutoSelectIntegrationTests.swift` (Mock TunnelControlling + Mock ConfigImporting + `@MainActor final class … : XCTestCase`) | exact |
| `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift` | M8 + L12 | `PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` (`XCTAssertNoThrow(try SingBoxConfigLoader.validate(json:))` pattern + fixture loader) | exact |
| `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift` | M10 | `ServerListFeatureTests/PullToRefreshTests.swift` (Mock probe/fetcher/parser + `@MainActor final class … : XCTestCase` + in-memory ModelContainer) | exact |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift` | M11 | `MainScreenFeatureTests/AutoSelectIntegrationTests` (Phase 6d post-fix re-armed `.connected → .disconnected → .connected` coverage) | exact |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift` | L16 (only if extraction executes per Q3) | `MainScreenFeatureTests/OnDemandRulesBuilderTests.swift` (pure-function test of static helper — 16-combination matrix) | role-match |

### Wave 3 — Closure artifacts (NEW + UPDATE)

| File | Action | Analog | Match quality |
|------|--------|--------|---------------|
| `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` | NEW | `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md` (front-matter YAML + Status + What Phase delivered + commit-SHA tables + DEC list) | exact |
| `wiki/performance-baseline.md` | UPDATE § Open follow-ups | existing wiki page (must add "26 closed in Phase 6e" entry, mark post-6e backlog as nil) | exact |
| `wiki/log.md` | APPEND closure entry | existing append-only changelog (Phase 6d entry as template) | exact |
| `.planning/STATE.md` + `.planning/ROADMAP.md` + `.planning/REQUIREMENTS.md` | UPDATE — Phase 6e ✅ Closed | Phase 6d state-sync pattern (Phase row → Closed; new QUAL-04..05 added → Validated) | exact |

---

## Pattern Assignments

### M7 — scenePhase consolidation (Wave 1, atomic commit)

**Targets:**
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` (lines 180-227 — `.onChange(of: scenePhase)` block)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` (lines 14, 79-85 — duplicate `.onChange(of: scenePhase)`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (NEW method `handleForegroundReentry()` near existing `handleForeground` at lines 521-560)

**Role:** SwiftUI scene observer coalesces 3 Tasks → 1 async method on ViewModel.

**Closest analog:** `MainScreenViewModel.handleForeground()` (MainScreenViewModel.swift:521-560) — already a single async method that does `loadAllFromPreferences` + filter + `applyVPNStatus` in one trip. Same coalesce-into-async-method shape.

**Code excerpt — analog (`MainScreenViewModel.swift:544-560`):**
```swift
public func handleForeground() async {
    let managers: [NETunnelProviderManager]
    do {
        managers = try await NETunnelProviderManager.loadAllFromPreferences()
    } catch {
        // Transient XPC failure — keep last state rather than flipping to `.invalid`.
        return
    }
    guard let ours = ManagerSelector.ourManagers(from: managers).first else {
        return
    }
    applyVPNStatus(ours.connection.status, connectedDate: ours.connection.connectedDate)
}
```

**Existing call site (analog, `BBTB_iOSApp.swift:194-225`):**
```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        let vmRef = viewModel
        Task.detached(priority: .background) {                // Task 1 (M3 deferred-detached)
            let snapshot = await MainActor.run {
                (isConnecting: vmRef.state == .connecting, importer: vmRef.importer)
            }
            guard !snapshot.isConnecting else { return }
            await snapshot.importer.runIsSupportedUpgrade()
        }
        if let tc = viewModel.tunnelController {
            Task { await tc.handleForeground() }              // Task 2
        }
        Task { await viewModel.handleForeground() }           // Task 3
    }
}
```
Plus `MainScreenView.swift:79-85`:
```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active, let vm = viewModel.serverListViewModel {
        Task { @MainActor in                                   // Task 4 (silent refresh)
            await vm.silentForegroundRefresh()
        }
    }
}
```

**Phase 6e application note:**
- Создать `MainScreenViewModel.handleForegroundReentry()` async method (sibling existing `handleForeground()`) — sequentially awaits all 3 hooks: `runIsSupportedUpgrade` (через `importer`) → `tunnelController?.handleForeground()` → `serverListViewModel?.silentForegroundRefresh()`.
- Сохраняем `Task.detached(priority: .background)` для `runIsSupportedUpgrade` (DEC-06d-01) — детач **внутри** `handleForegroundReentry` для not-blocking main render.
- `BBTB_iOSApp.swift` сворачиваем к `Task { @MainActor in await viewModel.handleForegroundReentry() }`. `MainScreenView.swift` удаляет dup `.onChange` block.
- **Не нарушать:** DEC-06d-01 (cold-start defer — внутри handleForegroundReentry сохраняем `Task.detached(priority: .background)` для upgrade); DEC-06d-02 (XPC ≤ 2 trips — handleForeground = 1 trip, sequential coalescing не добавляет XPC); D-09 applyVPNStatus single authority (не вызываем applyVPNStatus напрямую; через handleForeground).

---

### M10 — loadFromStore idempotency + confirmDeleteSubscription collapse (Wave 1, atomic commit)

**Target:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` (6 call sites lines 181, 224, 257, 282, 312, 323; loadFromStore body line 328-335)

**Role:** ViewModel — SwiftData fetch-all + Swift group; CRUD lifecycle method.

**Closest analog (idempotency guard pattern):** No exact analog для loadFromStore; closest = standard `private var inFlight: Bool` debounce pattern (typical SwiftUI / Combine guard). New pattern для этого codebase.

**Closest analog (collapse-multiple-calls):** Phase 6d M13 fix (`61f60a3`) — `defer`-based cleanup in `pingAllServers` guaranteed что все exit paths sync state.

**Code excerpt — existing `loadFromStore` (line 328-335):**
```swift
private func loadFromStore() async {
    let context = ModelContext(modelContainer)
    let subsDescriptor = FetchDescriptor<Subscription>()
    let serversDescriptor = FetchDescriptor<ServerConfig>()
    let subs = (try? context.fetch(subsDescriptor)) ?? []
    let servers = (try? context.fetch(serversDescriptor)) ?? []
    sections = Self.groupSections(subscriptions: subs, servers: servers)
}
```

**Code excerpt — `confirmDeleteSubscription` double-call (lines 286-323):**
```swift
public func confirmDeleteSubscription(_ subscription: Subscription) async {
    // … cascade delete logic …
    guard let row = try? context.fetch(subRowDesc).first else {
        // early-exit branch:
        try? context.save()
        if let selected = coordinator?.selectedServerID, linkedIDs.contains(selected) {
            coordinator?.applySelection(nil)
        }
        pendingDeleteSubscription = nil
        await loadFromStore()                      // ← 1st call (early exit)
        return
    }
    context.delete(row)
    try? context.save()
    // …
    pendingDeleteSubscription = nil
    await loadFromStore()                          // ← 2nd call (normal path)
}
```

**Phase 6e application note:**
- **Part A — collapse `confirmDeleteSubscription`:** refactor так чтобы `loadFromStore()` вызывался ровно один раз в конце try/catch блока (либо через `defer { await loadFromStore() }` если safe — нет, defer не поддерживает async; use single tail-call).
- **Part B — idempotency guard:** добавить `private var loadInProgress: Bool = false` + `private var lastLoadAt: Date = .distantPast`. Guard pattern:
  ```swift
  private func loadFromStore() async {
      if loadInProgress { return }
      if Date().timeIntervalSince(lastLoadAt) < 0.1 { return }  // 100ms debounce
      loadInProgress = true
      defer { loadInProgress = false; lastLoadAt = Date() }
      let context = ModelContext(modelContainer)
      …
  }
  ```
- **Не нарушать:** D-09 `#Predicate UUID?` = 0 (loadFromStore использует `FetchDescriptor<Subscription>` + `FetchDescriptor<ServerConfig>` БЕЗ #Predicate — preserve); никакого refactor's к `#Predicate { $0.id == X }` для UUID-полей (см. feedback_swiftdata_uuid_predicate.md).

---

### M8 — validatedAt timestamp guard (Wave 1, atomic commit, MEDIUM-HIGH risk — R10 defense-in-depth)

**Targets:**
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` (lines 156-164 pre-expand validate; lines 240-251 post-expand validate)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (provision path that writes `providerConfiguration["configJSON"]` — must additionally write `providerConfiguration["configJSONValidatedAt"] = ISO8601-now`)

**Role:** Tunnel extension validate gate (pre + post expand) — R1 + SEC-06 enforcement. M8 fix adds a "trust-but-verify within window" optimization without removing R10 defense-in-depth.

**Closest analog:** Same file — existing **post-expand R1 re-validation** (lines 240-251) is the canonical R10 defense-in-depth invariant. Phase 6e fix MUST preserve this pattern unchanged.

**Code excerpt — analog (post-expand validate, `BaseSingBoxTunnel.swift:240-251`):**
```swift
// 7b. Defense-in-depth (R10): повторная R1-валидация post-expand. Если expand
//     когда-нибудь добавит что-то запрещённое (регрессия) — поймаем здесь до
//     `startOrReloadService`. white-list inbound types гарантирует что только
//     {tun, direct} проходят, плюс experimental APIs всё ещё запрещены.
do {
    try SingBoxConfigLoader.validate(json: expandedJSON)
    TunnelLogger.lifecycle.info("startTunnel: post-expand R1 re-validation passed")
} catch {
    TunnelLogger.security.error("R1 post-expand validation failed: \(error.localizedDescription)")
    endLibboxStart()
    completionHandler(TunnelError.configValidationFailed(error)); return
}
```

**Code excerpt — pre-expand validate, currently always-run (lines 156-164) — this is the gate to be cached:**
```swift
// 2. R1 + SEC-06 валидация — fail-fast до любых side-effects.
do {
    try SingBoxConfigLoader.validate(json: configJSON)
    TunnelLogger.lifecycle.info("startTunnel: R1/SEC-06 validation passed")
} catch {
    TunnelLogger.security.error("R1 / SEC-06 validation failed: \(error.localizedDescription)")
    endLibboxStart()
    completionHandler(TunnelError.configValidationFailed(error)); return
}
```

**Phase 6e application note:**
- **ConfigImporter side:** when ConfigImporter сам успешно выполнил `SingBoxConfigLoader.validate(json: configJSON)` before save, set `providerConfiguration["configJSONValidatedAt"] = ISO8601DateFormatter().string(from: Date())`.
- **BaseSingBoxTunnel side (lines 156-164):** wrap pre-expand validate в guard:
  ```swift
  let skipPreExpand: Bool = {
      guard let validatedAtRaw = providerConfiguration["configJSONValidatedAt"] as? String,
            let validatedAt = ISO8601DateFormatter().date(from: validatedAtRaw)
      else { return false }
      return Date().timeIntervalSince(validatedAt) < 24 * 3600   // 24h window
  }()
  if !skipPreExpand {
      do { try SingBoxConfigLoader.validate(json: configJSON) } catch { … }
  }
  ```
- **CRITICAL — R10 preservation:** **post-expand validate (lines 240-251) MUST remain unchanged, always-run.** Это закрывает the attack surface "expandConfigForTunnel mutation adds forbidden inbound" — defense-in-depth invariant из wiki/security-gaps.md R10. **Grep audit after fix:** `grep -c "SingBoxConfigLoader.validate" BaseSingBoxTunnel.swift` ≥ 2 (1 pre-expand guarded + 1 post-expand unconditional).
- **L12 bundled:** L12 = LOW-tier version of M8 same surface. Один commit покрывает оба.
- **Не нарушать:** R10 (post-expand validate); R1 (white-list inbound types); SEC-06 (validation runs both at import time + at tunnel start).

---

### M11 — applyVPNStatus early-return guard (Wave 1, atomic commit, MEDIUM risk — D-09 single authority)

**Target:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (lines 420-436, `.connecting/.reasserting` branch)

**Role:** ViewModel — reactive UI driver; SINGLE authority for state mutation per D-09.

**Closest analog:** Existing **outer-level dedupe guard** at line 414 (Phase 6d post-fix `9b38796`). M11 fix mirrors the same idiom one level deeper, in `.connecting` branch.

**Code excerpt — analog (outer guard, `MainScreenViewModel.swift:410-418`):**
```swift
internal func applyVPNStatus(_ status: NEVPNStatus, connectedDate: Date? = nil) {
    // Phase 6d post-fix (2026-05-14) — UI dedupe. Skip identical re-applies
    // to spare SwiftUI body re-diff thrash. Spasy from 8k duplicate
    // `.connected` events that flooded MainActor in 40s post-Connect.
    guard lastAppliedVPNStatus != status || lastAppliedConnectedDate != connectedDate else {
        return
    }
    lastAppliedVPNStatus = status
    lastAppliedConnectedDate = connectedDate

    switch status {
    case .connecting, .reasserting:
        switch state {
        case .empty, .error, .connecting:    // ← inner case already implicitly no-ops .connecting
            break
        default:
            state = .connecting
        }
        // …
```

**Phase 6e application note:**
- **Option A (researcher recommendation):** explicit early-return guard в `.connecting/.reasserting` branch для readability — semantically equivalent к existing nested switch case `.connecting: break`, но документирует intent явно:
  ```swift
  case .connecting, .reasserting:
      // Idempotent: если уже .connecting — early-return до banner mutation.
      guard state != .connecting else { return }
      switch state { … }   // существующий nested switch
  ```
- **CRITICAL — D-09 single authority preservation:**
  - `applyVPNStatus` MUST остаться единственным setter для `state` + `reconnectBannerState` (grep `func applyVPNStatus` = 1).
  - НЕ добавлять новые `state = ...` setters вне этой функции.
  - НЕ удалять outer-level `lastAppliedVPNStatus` guard (Phase 6d 8k-event safety net).
- **Не нарушать:** D-09 applyVPNStatus single authority; Phase 6c R18 sliding window (separate surface — OnDemandRulesBuilder, не applyVPNStatus); NEVPNStatusDidChange observer queue=`nil` (feedback_nevpn_observer_queue_main.md — НЕ переименовывать к `.main`).
- **Regression test priority HIGH:** `AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects` MUST pass (Phase 6d post-fix re-armed `.connected → .disconnected → .connected` transition).

---

### Theme A — perf bundle (Wave 2, 1 commit) — L3, L4, L7, L8, L11, L13, L18

**Target files (cluster):**
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` (L3 — convert non-launch `static let` → `static var x: String { tr("x") }`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift:47-49` (L4 — wrap `ImportProgressOverlay` в `.overlay(... ? : nil)` modifier)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift:45-55` (L7 — `@State var detents` + `.onChange(of: viewModel.sections)`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift:40-41, 117` (L8 — `.userInitiated` → `.userInteractive`)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:181-202` (L11 — post notification ONCE outside for-loop)
- `BBTB/Packages/Protocols/{Shadowsocks,Hysteria2,VLESSReality,VLESSTLS,Trojan}/Sources/*/ConfigBuilder.swift` (L13 — `.prettyPrinted` → `[]` в `JSONSerialization.data(...)`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:97` + init lines 138-173 (L18 — `private(set) lazy var serverListViewModel`)

**Closest analog (Phase 6d M12 pattern для L11):** `SettingsViewModel.applyAutoReconnectToManager()` — already canonical notification consumer; reducing N → 1 mirrors Phase 6d "single XPC trip" pattern (DEC-06d-02).

**Code excerpt — analog (`SettingsViewModel.swift:181-202`):**
```swift
nonisolated public func applyAutoReconnectToManager() async {
    let log = Logger(subsystem: "app.bbtb.client", category: "settings-auto-reconnect")
    do {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let ours = ManagerSelector.ourManagers(from: managers)
        for manager in ours {
            OnDemandRulesBuilder.applyCurrentState(to: manager)
            do {
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()
                NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: manager)
                // ← L11 fix: post once OUTSIDE for-loop (use ours.first or .last); ours.count == 1 typically
            } catch { … }
        }
    } catch { … }
}
```

**Phase 6e application note:**
- L11 — post notification ONCE outside for-loop, `object: ours.first` (рare multi-manager edge case documented in comment). Consumer (`TunnelController.provisionerObserver:577`) handles `object: nil` gracefully — verified.
- L13 — `grep -rn "prettyPrinted" BBTB/Packages/Protocols/*/Tests/` must show 0 hits (если есть test что сравнивает raw pretty-formatted строки — update test первым).
- **Не нарушать:** DEC-06d-02 (L11 reduces XPC contention, не добавляет); DEC-06d-06 (PerfSignposter spans остаются — этим LOW не трогают).

---

### Theme B — correctness bundle (Wave 2, 1 commit) — L1, L9, L10, L20

**Target files (cluster):**
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift:372-383` (L1 — clearDNSCache 2s timeout, mirror Phase 6d M16 `5a4db9f` openTun pattern)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:368-389` + line 517 (L9 — failover banner 5s TTL Task в `showFailoverBanner`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift:250-265` (L10 — fire `failoverObserver` BEFORE awaiting `next.attempt()`)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift:194-204` (L20 — `commandServer.start` catch closes server + nils self.commandServer / self.platformInterface)

**Closest analog (timeout pattern):** Phase 6d M16 `5a4db9f` — `openTun` 5s → 2s semaphore timeout reduction. Same defensive-timeout idiom для L1.

**Closest analog (observer-fire-before-await):** TunnelWatchdog already uses `handleObservedStatus` actor (Phase 6c) — but `fireFailover` waits on `next.attempt()` BEFORE callback. L10 = reorder.

**Code excerpt — analog (TunnelWatchdog `fireFailover`, lines 250-265):**
```swift
private func fireFailover(provider: any FailoverProviding) async {
    debounceTask = nil
    stableSession = false
    guard let next = await provider.nextServerAttempt() else {
        log.notice("watchdog: failover requested but pool exhausted (nextServerAttempt returned nil)")
        return
    }
    log.notice("watchdog: firing failover to \(next.serverName, privacy: .public)")
    do {
        _ = try await next.attempt()                              // ← currently awaits attempt FIRST
        if let observer = failoverObserver {
            await observer(next.serverName)                        // ← then fires observer
        }
    } catch { … }
}
```

**Phase 6e application note (L10 fix):**
```swift
log.notice("watchdog: firing failover to \(next.serverName, privacy: .public)")
if let observer = failoverObserver {
    await observer(next.serverName)                                // ← fire FIRST (UI sees pending)
}
do {
    _ = try await next.attempt()
} catch {
    log.error("watchdog: failover attempt threw \(String(describing: error), privacy: .public)")
}
```

**Phase 6e application note (L9 — failover banner 5s TTL):**
- В `MainScreenViewModel.showFailoverBanner(toServerName:)` (line 517) spawn `Task { try? await Task.sleep(for: .seconds(5)); if case .failover = reconnectBannerState { reconnectBannerState = .hidden } }`.
- **Не нарушать:** Phase 6c R18 sliding-window invariant (`grep 'toggle && intent' OnDemandRulesBuilder.swift` = 2). Failover banner timing change orthogonal к sliding window — но grep audit обязателен.

**Не нарушать в Theme B в целом:**
- DEC-06d-03 (event-driven status polling — L10 fix preserves: пользователь видит pending immediately + actor await still drives logic).
- ExternalVPNStopMarker peek-only API (None of L1/L9/L10/L20 trogают marker — verified).

---

### Theme C-1 — maintainability bundle (Wave 2, 1 commit) — L2, L5, L14, L15

**Target files (cluster):**
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:159-169` + `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/WSTransportHandler.swift:36-47` (L2 — unify "WS host empty → substitute SNI" в `WSTransportHandler.buildTransportBlock(sniFallback:)`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift:37-125` (L5 — extract `ensureAuthorized() async -> Bool` + `post(content:identifier:)`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:1010` (L14 — `print()` → `Logger(subsystem: "app.bbtb.client", category: "importer-upgrade").info(...)`)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift:241, 252, 277, 335` (L15 — `.notice` → `.debug` для `autoDetectControl` per-call logs)

**Closest analog (cross-protocol WS fix — Phase 6d M12 `1621a08`):** VLESS+TLS WS-host fallback к SNI. L2 = mechanical replication для Trojan + unification в TransportHandler.

**Code excerpt — analog (Phase 6d M12 commit pattern, TransportRegistry handler):**
```swift
public static func buildTransportBlock(host: String?, path: String, sniFallback: String?) -> [String: Any] {
    let resolvedHost = (host?.isEmpty ?? true) ? (sniFallback ?? "") : (host ?? "")
    // …
}
```
Trojan + VLESSTLS callers pass `sniFallback: sni` после fix.

**Closest analog (TunnelLogger subsystem/category pattern для L14):**
```swift
let log = Logger(subsystem: "app.bbtb.client", category: "settings-auto-reconnect")
```
(from `SettingsViewModel.swift:182` — canonical pattern).

**Phase 6e application note:**
- L14 — категория `importer-upgrade` (унифицированно с naming Phase 6c — kebab-case feature-area).
- L15 — `.notice` → `.debug` гарантирует filterability через `log stream --predicate 'category=="lifecycle" && type >= "info"'`; production users остаются на default level.
- L2 — обязательно прогнать `TrojanTests` + `VLESSTLSTests` + `WSTransportHandlerTests` regression gate (cross-protocol coverage).
- **Не нарушать:** никакие D-09 / DEC-06d (Theme C-1 = code quality only).

---

### Theme C-2 — L16 standalone (Wave 2, 1 commit, HIGH RISK — D-09 + code reviewer mode)

**Target:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:410-487` (extraction of `reduceState(_:Date?) -> ConnectionState` + `reduceBanner(_:Date?) -> ReconnectBannerState` pure functions).

**Role:** Refactor of reactive UI driver — extract pure switch logic to standalone testable functions; `applyVPNStatus` retains single-authority + dedupe guard, calls extracted reducers internally.

**Closest analog (pure-function extraction):** `OnDemandRulesBuilder.applyCurrentState(to: manager)` — static pure function pattern с явным intent + sliding-window invariant comment. Same shape для extracted reducers.

**Code excerpt — analog (`OnDemandRulesBuilder` extraction style):**
```swift
public enum OnDemandRulesBuilder {
    /// Single source of truth for the Phase 6c R18 sliding-window invariant.
    /// `toggle && intent` is checked exactly once per call site (line 113).
    public static func applyCurrentState(to manager: NETunnelProviderManager) {
        let toggle = UserDefaults.bbtbAutoReconnectEnabled
        let intent = UserDefaults.bbtbUserIntendedConnected
        // …
    }
}
```

**Phase 6e application note:**
- Extract to static funcs (or private nonisolated helpers):
  ```swift
  internal static func reduceState(currentState: ConnectionState,
                                    status: NEVPNStatus,
                                    connectedDate: Date?) -> ConnectionState { … }
  internal static func reduceBanner(currentBanner: ReconnectBannerState,
                                     status: NEVPNStatus,
                                     needsKillSwitch: Bool) -> ReconnectBannerState { … }
  ```
- `applyVPNStatus` body shrinks к: dedupe guard + `state = Self.reduceState(...)` + `reconnectBannerState = Self.reduceBanner(...)`. **Single setter per @Published** preserved — D-09 invariant.
- **MANDATORY:** code reviewer mode (`mcp__codex__codex` sandbox=read-only) перед commit. Review brief MUST включать diff с byte-by-byte verification что 16 status × 4 current-state combinations отвечают тому же result.
- **Failure escalation per D-08:** если 2+ regression gate fail на L16 → escalate к Architect (`mcp__codex__codex`) либо defer L16 в Phase 6f с rationale в SUMMARY.
- **Не нарушать:** D-09 applyVPNStatus single authority (`grep -c "func applyVPNStatus" MainScreenViewModel.swift` = 1 после fix); каждая ветка switch byte-identical в reducers; `lastAppliedVPNStatus` outer guard остаётся в `applyVPNStatus` body, не в reducers.

---

### Theme D — trivial unused imports (Wave 2, 1 commit) — Periphery-verified

**Target files (3):**
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift:18` — remove `import ConfigParser`
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift:26` — remove `import ConfigParser`
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift:9` — remove `import DesignSystem`

**Closest analog (import block convention):** Standard SwiftPM top-level import blocks throughout codebase — no scoped imports anywhere. Pattern = `import <ModuleName>` only.

**Code excerpt — analog (`MainScreenView.swift:1-4`):**
```swift
import SwiftUI
import Localization
import DesignSystem
import ServerListFeature
```

**Phase 6e application note:**
- Three mechanical line deletions. Build MUST succeed после.
- Periphery scan delta: 37 baseline warnings → 34 (3 actionable imports removed; 34 remaining = false-positive).
- **Не нарушать:** N/A (trivial); regression gate full suite верифицирует compile.

---

## Test File Patterns (NEW files, optional per Wave 0)

### `HandleForegroundReentryTests.swift` (M7)

**Analog:** `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift`

**Closest excerpt (analog test scaffolding):**
```swift
import XCTest
import Foundation
import SwiftData
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class AutoSelectIntegrationTests: XCTestCase {
    private final class MockTunnel: TunnelControlling, @unchecked Sendable {
        var connectCount = 0
        var disconnectCount = 0
        func connect() async throws -> Date { … }
        func disconnect() async throws { disconnectCount += 1 }
        func startReachability() async {}
        func stopReachability() async {}
        func handleForeground() async {}
    }
    private final class MockImporter: ConfigImporting, @unchecked Sendable { … }
}
```

**Phase 6e application note:** mirror Mock TunnelControlling + Mock ConfigImporting + Mock ServerListViewModel; verify `handleForegroundReentry()` invokes 3 hooks sequentially through actor count или dispatch trace.

---

### `ValidatedAtGuardTests.swift` (M8 + L12)

**Analog:** `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift`

**Closest excerpt:**
```swift
import XCTest
@testable import PacketTunnelKit

final class SingBoxConfigLoaderTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> String { … }

    func test_acceptsValidVLESSRealityConfig() throws {
        let json = try loadFixture("valid-vless-reality")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }
}
```

**Phase 6e application note:** 3 tests — `test_pre_expand_validate_skipped_when_validatedAt_recent` / `_post_expand_validate_always_runs` / `_pre_expand_validate_runs_when_validatedAt_missing`. Mock `providerConfiguration` через NETunnelProviderProtocol stub.

---

### `LoadFromStoreIdempotencyTests.swift` (M10)

**Analog:** `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift`

**Closest excerpt:**
```swift
@MainActor
final class PullToRefreshTests: XCTestCase {
    private final class MockProbe: ServerProbing, @unchecked Sendable { … }
    private final class MockFetcher: SubscriptionURLFetching, @unchecked Sendable { … }
    private final class MockParser: UniversalImportParsing, @unchecked Sendable { … }
    // … in-memory SwiftData ModelContainer + ServerListViewModel under test
}
```

**Phase 6e application note:** 2 tests — `test_confirmDeleteSubscription_calls_loadFromStore_once` (verify counter) + `test_loadFromStore_idempotency_guard_within_100ms` (verify debounce). In-memory ModelContainer pattern reused.

---

### `ApplyVPNStatusGuardTests.swift` (M11)

**Analog:** `AutoSelectIntegrationTests.swift` (same `@MainActor final class … : XCTestCase` shell; same `applyVPNStatus(_:connectedDate:)` driver invocation).

**Phase 6e application note:** 1 test — `test_applyVPNStatus_connecting_called_twice_state_stable` (call applyVPNStatus(.connecting) дважды → state == .connecting + assertion no body diff).

---

### `ReduceStateBannerTests.swift` (L16 — only if extraction executes)

**Analog:** `OnDemandRulesBuilderTests.swift` (pure-function test of static helper — matrix of inputs).

**Phase 6e application note:** 2 test methods (or parametrized) — `test_reduceState_all_combinations` (4 statuses × 4 current states = 16 combos) + `test_reduceBanner_all_combinations` (4 statuses × 3 banner states = 12 combos). Pure functions = trivial XCTAssertEqual matrix.

---

## Wave 3 — Closure Artifacts Pattern

### `06E-Final-SUMMARY.md` (NEW)

**Analog:** `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md`

**Required front-matter (analog excerpt lines 1-14):**
```markdown
---
phase: 06e-performance-audit-round-2
plan: Final
type: summary
status: closed
date: 2026-05-14
findings_total: 26
findings_closed_in_6e: 21
findings_subsumed_by_6d: 5
commits_total: <count>
regression_gate_passes: <count>
hard_blockers_passed: "9/9 (D-07 PASS criteria)"
---
```

**Required sections** (compact per D-05):
1. **Status** — `Phase 6e ✅ Closed YYYY-MM-DD`.
2. **What Phase 6e delivered** — 4 MEDIUM atomic commits + 5 Wave 2 commits + downgrade narrative.
3. **Closed findings table** — 26 rows × `{ID, severity, action, commit SHA или 'subsumed by 6d <SHA>'}`.
4. **Regression gate evidence** — per-MEDIUM gate + final Wave 2 gate (test counts + xcodebuild results).
5. **D-09 invariants final grep audit** — 7 checks (RESEARCH Section 4 step output).
6. **DEC-06d-01..06 preservation confirmation** — bullet checklist.
7. **Deferred items** — Numerical Instruments + macOS UAT replay → Phase 11/12; NET-12 → Phase 7-8.
8. **Next phase signal** — Phase 7 ready.

**Phase 6e application note:** не нужен 06E-COMPARISON.md (D-02 skipped numerical baseline). Compact narrative заменяет numerical comparison.

---

### `wiki/performance-baseline.md` UPDATE

**Action:** § Open follow-ups переходит из "26 carved" → "26 closed in Phase 6e" + (если ничего не перенесено в Phase 6f) "Open follow-ups (post-6e): nil".

**Analog (existing structure):** see `wiki/performance-baseline.md` § Open follow-ups (Phase 6d closure entry).

**Phase 6e application note:** preserve DEC-06d-01..06 section unchanged. Только обновить Open follow-ups + добавить cross-link к `06E-Final-SUMMARY.md`.

---

### `wiki/log.md` APPEND

**Action:** append-only changelog entry (date, source = `.planning/phases/06e-...`, what changed).

**Analog:** Phase 6d closure entry в `wiki/log.md`.

**Phase 6e application note:** ровно один entry; format `## YYYY-MM-DD — Phase 6e closure` + bullet list (DEC preservation; findings closed; wiki updates; next-phase signal).

---

### `.planning/STATE.md` + `ROADMAP.md` + `REQUIREMENTS.md` UPDATE

**Analog:** Phase 6d closure state sync (commits `de35624`, `2a5eb8e`).

**Phase 6e application note:**
- **STATE.md** — Active block → Phase 7; Progress table row Phase 6e → ✅ Closed.
- **ROADMAP.md** — Phase 6e Success Criteria section → mark all checked; Phase 7 → Active.
- **REQUIREMENTS.md** — если planner добавил QUAL-04..05 → Validated.

---

## Shared Patterns

### Atomic commit + regression gate (Wave 1 idiom)

**Source:** Phase 6d sub-plans 03a-h (`c2d54ea` через `b6996cb` — 19 commits, gate green между каждым).

**Apply to:** All 4 Wave 1 MEDIUM commits.

**Pattern:**
1. Make code change в одном logical chunk.
2. `gsd-sdk query commit ... --files <explicit list>` (no `git add .`).
3. Commit message: `<type>(06e-<finding>): <short>` + рассказ + DEC-preservation note.
4. Run regression gate: `swift test --package-path BBTB/Packages/AppFeatures` (≥133/133) + iOS xcodebuild + macOS xcodebuild.
5. If FAIL → revert per D-08 (НЕ "fix forward").

---

### Bundle commit + single gate (Wave 2 idiom — NEW для Phase 6e)

**Source:** Phase 6e CONTEXT.md D-04 (pragmatic для cleanup-tier).

**Apply to:** Wave 2 Theme A/B/C-1/C-2/D bundles.

**Pattern:**
1. Group все findings в bundle theme.
2. Single commit с message `chore(06e): batch <theme> — L#/L#/L#`.
3. Optional intra-bundle `swift build` compile-check (fast).
4. Single regression gate **в конце Wave 2** (после всех 5 bundles).
5. D-09 grep audit (`06D-INVARIANT-AUDIT.md` patterns) + Periphery scan delta.

---

### Awk-stripped grep audit для invariants (D-09)

**Source:** Phase 6c B-08 pattern, used в `06D-INVARIANT-AUDIT.md`. См. `06E-VALIDATION.md` § "D-09 Final Grep Audit" (8 grep checks).

**Apply to:** Wave 3 closure (final invariant audit before SUMMARY commit).

**7 forbidden / canonical patterns:**
1. Forbidden symbols ≤ 7
2. `NEVPNStatusDidChange.*queue:.*\.main` = 0
3. `#Predicate.*UUID\?` = 0 (or 1 comment)
4. `func applyVPNStatus` = 1 (single authority)
5. `ExternalVPNStopMarker` `.consume(` callers = 0
6. `toggle && intent` в OnDemandRulesBuilder.swift = 2
7. AppFeatures swift test 133/133 (или ≥133 если new tests)

---

## Critical Preservation List (MUST be acknowledged by executor)

The following invariants and APIs MUST remain unchanged in Phase 6e. Each MEDIUM fix + LOW bundle must verify через grep audit before commit.

| # | Invariant / API | Source (wiki / feedback) | Grep / verification |
|---|-----------------|---------------------------|---------------------|
| 1 | `ExternalVPNStopMarker.isPending` peek-only API — **NO `.consume()` callers added** | `wiki/security-gaps.md` R19 + `feedback_phase6d_architectural_patterns.md` DEC-06d-05 | `grep -rn "ExternalVPNStopMarker" BBTB --include="*.swift" \| grep ".consume(" \| wc -l` = 0 |
| 2 | `applyVPNStatus` single authority — exactly ONE function definition | D-09 invariant + Phase 6c R18 | `grep -c "func applyVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` = 1 |
| 3 | NEVPNStatusDidChange observer queue = `nil` (NOT `.main`) | `feedback_nevpn_observer_queue_main.md` + `feedback_nevpn_xpc_mach_port.md` | `grep -rn 'NEVPNStatusDidChange.*queue:.*\.main' BBTB --include="*.swift" \| wc -l` = 0 |
| 4 | SwiftData `#Predicate` UUID? = 0 occurrences (or 1 comment) | `feedback_swiftdata_uuid_predicate.md` | `grep -rn '#Predicate.*UUID?' BBTB --include="*.swift" \| wc -l` ≤ 1 |
| 5 | R10 defense-in-depth — post-expand `SingBoxConfigLoader.validate` ALWAYS runs | `wiki/security-gaps.md` R10 + M8 fix | `grep -c "SingBoxConfigLoader.validate" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` ≥ 2 (1 pre guarded + 1 post unconditional) |
| 6 | Phase 6c R18 sliding window invariant — `toggle && intent` = 2 hits | `wiki/auto-reconnect.md` + `feedback_auto_reconnect_user_intent_guard.md` | `grep -n "toggle && intent" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift \| wc -l` = 2 |
| 7 | DEC-06d-01 cold-start init defer — `Task.detached(priority: .background\|utility)` patterns preserved | `feedback_phase6d_architectural_patterns.md` DEC-06d-01 | `grep -n "Task.detached.*priority:" BBTB/App/iOSApp/BBTB_iOSApp.swift \| wc -l` ≥ 1 |
| 8 | DEC-06d-02 XPC consolidation ≤ 2 trips — `loadAllFromPreferences()` total count bounded | `feedback_phase6d_architectural_patterns.md` DEC-06d-02 | `grep -rn "await NETunnelProviderManager.loadAllFromPreferences()" BBTB --include="*.swift" \| wc -l` ≤ 4 |
| 9 | DEC-06d-03 event-driven status polling — no new `Task.sleep`-based loops в TunnelController | `feedback_phase6d_architectural_patterns.md` DEC-06d-03 | `grep -n "Task.sleep" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift \| wc -l` per Phase 6d baseline (justified hits only) |
| 10 | DEC-06d-04 bounded probe concurrency — `maxConcurrentProbes = 8` preserved | `feedback_phase6d_architectural_patterns.md` DEC-06d-04 | `grep -n "maxConcurrentProbes" BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` = 1, value = 8 |
| 11 | DEC-06d-05 Apple-canonical options discriminator — `options["manualStart"]` = 2 sites | `feedback_phase6d_architectural_patterns.md` DEC-06d-05 | `grep -rn 'options\["manualStart"\]' BBTB --include="*.swift" \| wc -l` = 2 |
| 12 | DEC-06d-06 PerfSignposter spans — preserved in production code | `feedback_phase6d_architectural_patterns.md` DEC-06d-06 | `grep -rn "PerfSignposter" BBTB --include="*.swift" \| grep -v /Tests/ \| wc -l` ≥ 25 |

**Если any check fails в pre-fix или post-fix audit → STOP, revert, investigate.** Per D-08 (Phase 6c R18 lesson: НЕ "fix forward").

---

## No Analog Found

**None.** Все 26 carved findings + 4 closure artifacts имеют clear analogs в existing codebase либо в Phase 6d artifacts. Single new pattern = `loadInProgress` idempotency guard для M10 — но это standard SwiftUI / Combine debounce idiom (не требует кодового analog). 5 NEW test files имеют 1:1 analogs среди existing XCTestCase files.

---

## Metadata

**Analog search scope:**
- `BBTB/Packages/AppFeatures/Sources/{MainScreenFeature,ServerListFeature,SettingsFeature}/`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/`
- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/`
- `BBTB/Packages/Protocols/{Shadowsocks,Hysteria2,VLESSReality,VLESSTLS,Trojan}/Sources/`
- `BBTB/Packages/VPNCore/Sources/VPNCore/`
- `BBTB/Packages/AppFeatures/Tests/{MainScreenFeatureTests,ServerListFeatureTests,SettingsFeatureTests}/`
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/`
- `.planning/phases/06d-performance-audit/` (FINDINGS, Final-SUMMARY, PERIPHERY-POST-FIX, INVARIANT-AUDIT artifacts)
- `wiki/{performance-baseline,security-gaps,auto-reconnect,architecture,log}.md`

**Files scanned:** ~40 source files + ~10 test files + 8 Phase 6d artifacts + 5 wiki pages.

**Pattern extraction date:** 2026-05-14.

**Phase 6e specific notes:**
- This is a **cleanup / remediation phase**, NOT a feature phase. Every "target" file already exists.
- Only NEW files: 5 optional test files + 1 closure SUMMARY + (wiki/log.md is APPEND-only).
- No new modules / packages introduced.
- DEC-06d-01..06 + D-09 + R18 invariants preserved across all 26 findings — verified per Section "Critical Preservation List".

---

## PATTERN MAPPING COMPLETE
