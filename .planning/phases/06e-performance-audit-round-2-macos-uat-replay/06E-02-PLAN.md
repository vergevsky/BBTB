---
phase: 06e
slug: performance-audit-round-2-macos-uat-replay
plan: 02
type: execute
wave: 2
mode: mvp
depends_on: [01]
autonomous: false
requirements: [QUAL-04, QUAL-05]
findings_addressed: [L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L16, L18, L20, L6, L17, L19, Trivial-1, Trivial-2, Trivial-3]
tags: [low-bundle, perf-cleanup, correctness-cleanup, maintainability-cleanup, reducestate-extraction, periphery-cleanup, code-reviewer]
files_modified:
  - BBTB/Packages/Localization/Sources/Localization/L10n.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
  - BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift
  - BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift
  - BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift
  - BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift
  - BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
  - BBTB/Packages/TransportRegistry/Sources/TransportRegistry/WSTransportHandler.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift

must_haves:
  truths:
    - "Theme A (perf cleanup, 1 commit): L3 (L10n lazy non-launch keys), L4 (.overlay modifier), L7 (@State detents + .onChange), L8 (.userInteractive QR), L11 (notification once outside for-loop), L13 (.prettyPrinted → []), L18 (lazy serverListViewModel) — все mechanical refactors с zero functional impact."
    - "Theme B (correctness cleanup, 1 commit): L1 (clearDNSCache 2s timeout), L9 (failover banner 5s TTL), L10 (failoverObserver fire-before-attempt), L20 (commandServer.start catch cleanup)."
    - "Theme C-1 (maintainability cleanup, 1 commit): L2 (WS sniFallback parameter unification), L5 (UserNotificationsHelper ensureAuthorized/post extraction), L14 (print → Logger), L15 (.notice → .debug)."
    - "Theme C-2 (L16 standalone HIGH-RISK, 1 commit AFTER code reviewer mode): applyVPNStatus extraction в reduceState(_:_:_:) + reduceBanner(_:_:_:) pure static helpers — D-09 single authority preserved (applyVPNStatus signature unchanged; outer guard + assignments остаются)."
    - "Theme D (trivial imports, 1 commit): 3 `import` line deletions (ServerDetailView.swift:18 ConfigParser; ServerListSheet.swift:26 ConfigParser; TransportPicker.swift:9 DesignSystem) — Periphery-verified zero references."
    - "Bookkeeping rows: L6 (subsumed by Phase 6d H5 `5ef3888`), L17 (subsumed by 6d post-fix `bc7bc26` + `1467328`), L19 (subsumed by 6d H7 `b8d9294`) — NO code change в Wave 2; documented в Wave 3 SUMMARY."
    - "Single end-of-Wave-2 regression gate после всех 5 bundle commits: AppFeatures ≥ 143/143 (≥ 145 если L16 extraction adds 2 ReduceStateBannerTests methods) + PacketTunnelKit ≥ 65/65 + iOS + macOS xcodebuild SUCCEEDED + Periphery actionable count = 0 (down from 3) + D-09 grep audit (subset)."
    - "DEC-06d-01..06 preserved: cold-start defer (M7-related, unchanged); XPC consolidation (L11 reduces XPC notification posts N→1, не добавляет); event-driven status polling (L9 TTL Task не sleep-loop, .seconds(5)); bounded probe concurrency (untouched); Apple-canonical options (L9/L10 не трогают marker); PerfSignposter spans preserved."
    - "Phase 6c R18 sliding window invariant preserved: L9/L10 трогают reactive UI driver/Watchdog, но не OnDemandRulesBuilder.swift — `grep 'toggle && intent' = 2`."
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift"
      provides: "NEW pure-function tests для extracted reduceState/reduceBanner — 16+12 combinations matrix"
      contains: "reduceState"
    - path: "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift"
      provides: "removed `import ConfigParser` (line 18)"
    - path: "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift"
      provides: "removed `import ConfigParser` (line 26) + @State detents migration (L7)"
    - path: "BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift"
      provides: "removed `import DesignSystem` (line 9)"
    - path: "BBTB/Packages/TransportRegistry/Sources/TransportRegistry/WSTransportHandler.swift"
      provides: "unified `sniFallback: String?` parameter в buildTransportBlock (L2)"
      contains: "sniFallback"
  key_links:
    - from: "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift"
      to: ".bbtbProvisionerDidSave notification (L11)"
      via: "single post() outside for-loop"
      pattern: "NotificationCenter\\.default\\.post.*bbtbProvisionerDidSave"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift"
      to: "failoverObserver callback (L10)"
      via: "fire observer BEFORE awaiting next.attempt()"
      pattern: "await observer|await next.attempt"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift"
      to: "reduceState + reduceBanner pure static helpers (L16)"
      via: "applyVPNStatus body calls Self.reduceState() + Self.reduceBanner() after outer guard"
      pattern: "Self\\.reduceState|Self\\.reduceBanner"
---

<objective>
Phase 6e — Wave 2: 16 still-applicable LOW findings + 3 trivial unused imports, организованных в 5 bundle commits. Single end-of-Wave-2 regression gate (per CONTEXT.md D-04 hybrid closure rigor для cleanup-tier).

Theme C-2 (L16 applyVPNStatus extraction) — HIGH-RISK, требует code reviewer mode (mcp__codex__codex sandbox=read-only) ПЕРЕД commit per CONTEXT.md D-06.

**Purpose:** очистить maintainability / perf / correctness debt одним сфокусированным wave; cumulative regression gate ловит chunk-level regressions.

**Output:**
- 5 bundle commits (Theme A perf → Theme B correctness → Theme C-1 maintainability → Theme C-2 L16 extraction → Theme D trivial imports)
- 1 final regression gate (full suite + iOS + macOS + Periphery + D-09 grep audit subset)
- 1 NEW test file для L16 (ReduceStateBannerTests.swift, только если L16 extraction proceeds — see Task 4)
- Bookkeeping rows для L6, L17, L19 (subsumed-by-6d) — для Wave 3 SUMMARY

**Scope NOT in this plan:** 4 MEDIUM atomic fixes (Wave 1) + closure documentation (Wave 3).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-CONTEXT.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-VALIDATION.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-01-PLAN.md
@.planning/phases/06d-performance-audit/06D-FINDINGS.md
@.planning/phases/06d-performance-audit/06D-INVARIANT-AUDIT.md
@.planning/phases/06d-performance-audit/06D-PERIPHERY-POST-FIX.md
@wiki/performance-baseline.md
@wiki/auto-reconnect.md
@wiki/security-gaps.md

<interfaces>
<!-- Key contracts the executor needs. Extracted from existing files. -->

From `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/WSTransportHandler.swift` (L2 target):
- Current signature (approx): `static func buildTransportBlock(host: String?, path: String) -> [String: Any]`
- L2 changes signature: adds `sniFallback: String?` parameter.
- Callers to update: Trojan/ConfigBuilder.swift:159-169 (existing fallback logic — collapses); VLESSTLS/ConfigBuilder.swift (M12 already canonized в Phase 6d `1621a08` — adapted к unified parameter).

From `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift:37-125` (L5 target):
- Two functions `notifyReconnectFailed()` and `notifySingleServerUnavailable(serverName:)` — duplicate ~30 LOC each.
- Extract: `private static func ensureAuthorized() async -> Bool` + `private static func post(content: UNMutableNotificationContent, identifier: String) async`.

From `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:410-487` (L16 target):
- `applyVPNStatus(_ status: NEVPNStatus, connectedDate: Date? = nil)` — D-09 single authority.
- Inner switch produces `state: ConnectionState` + `reconnectBannerState: ReconnectBannerState`.
- L16 extracts pure static helpers:
  - `internal static func reduceState(currentState: ConnectionState, status: NEVPNStatus, connectedDate: Date?) -> ConnectionState`
  - `internal static func reduceBanner(currentBanner: ReconnectBannerState, status: NEVPNStatus, needsKillSwitch: Bool) -> ReconnectBannerState`
- applyVPNStatus body после extraction: outer dedupe guard (preserved) + `state = Self.reduceState(currentState: state, status: status, connectedDate: connectedDate)` + `reconnectBannerState = Self.reduceBanner(currentBanner: reconnectBannerState, status: status, needsKillSwitch: needsKillSwitchSetting)` + lastApplied updates.

From `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift:250-265` (L10 target):
- Current `fireFailover(provider:)` calls `_ = try await next.attempt()` BEFORE invoking `failoverObserver`.
- L10 reorders: fire observer BEFORE await attempt; on attempt throw — log only (banner stays briefly).

From `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift:372-383` (L1 target):
- `clearDNSCache()` has 2 `semaphore.wait()` calls without timeout.
- L1 adds 2s timeout (mirror Phase 6d M16 `5a4db9f` openTun pattern).
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Theme A — perf-cleanup bundle (L3, L4, L7, L8, L11, L13, L18) — single commit</name>

  <files>
    BBTB/Packages/Localization/Sources/Localization/L10n.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
    BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift
    BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
    BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift
    BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift
    BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift
    BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift
    BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  </files>

  <read_first>
    - `BBTB/Packages/Localization/Sources/Localization/L10n.swift` (количество static let accessors; identify launch-critical vs non-launch для L3)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift:47-49` (L4 — current `if viewModel.importInProgress { ImportProgressOverlay() }` внутри ZStack)
    - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift:45-55` (L7 — current computed `estimatedSheetHeight` iterating `viewModel.sections`)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift:40-41, 117-118` (L8 — `DispatchQueue.global(qos: .userInitiated)`)
    - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:181-202` (L11 — current per-iteration `NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: manager)` внутри for-loop)
    - Все 5 ConfigBuilder.swift файлы — `grep -n "prettyPrinted" Packages/Protocols/*/Sources/*/ConfigBuilder.swift` (L13 — 6 hits в 5 файлах)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:97` + init lines 138-173 (L18 — `serverListViewModel` strong reference; конвертация к `private(set) lazy var`)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 1 L3, L4, L7, L8, L11, L13, L18
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "Theme A — perf bundle"
    - Pre-check на тесты — `grep -rn "prettyPrinted" BBTB/Packages/Protocols/*/Tests/` — verify NO test compares pretty-formatted JSON strings; если есть — update тест ПЕРЕД L13 fix
  </read_first>

  <action>
    7 LOW findings в одном commit. Каждый — local mechanical refactor с zero functional impact. Если L11 raises concern в review — допустимо split в отдельный commit (см. RESEARCH.md Q2).

    **L3 (L10n lazy):** Конвертировать `static let` в L10n.swift к `static var x: String { tr("x") }` для non-launch-critical keys. Сохранить `static let` ТОЛЬКО для launch-critical keys (e.g., `appName`, main button labels — определить по grep инициализаторов в `MainScreenView` / `BBTB_iOSApp.init`). Минимум 50%+ keys должны стать computed `static var`.

    **L4 (.overlay modifier):** В `MainScreenView.swift:47-49` заменить inline-в-ZStack `if viewModel.importInProgress { ImportProgressOverlay() }` на ZStack `.overlay {` modifier closure. SwiftUI dependency tracking trigger-ит re-eval только when `importInProgress` changes.

    **L7 (@State detents):** В `ServerListSheet.swift:45-55` заменить computed `estimatedSheetHeight` на: `@State private var detents: Set<PresentationDetent> = [.large]` + helper `static func computeDetents(sections:)` + `.onChange(of: viewModel.sections) { _, new in detents = Self.computeDetents(sections: new) }`.

    **L8 (.userInteractive QR):** В `QRScannerViewController.swift:40-41, 117-118` заменить `DispatchQueue.global(qos: .userInitiated)` на `DispatchQueue.global(qos: .userInteractive)` per Apple WWDC sample для AVCaptureSession setup.

    **L11 (notification once outside for-loop):** В `SettingsViewModel.swift:181-202` (`applyAutoReconnectToManager`) переместить `NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: ours.first)` ИЗ внутри for-loop в ПОСЛЕ for-loop body. Сохранить per-manager try-catch; post происходит ровно один раз (если хотя бы один manager success). Add inline comment про DEC-06d-02 timing semantics.

    **L13 (.prettyPrinted → []):** Во всех 5 ConfigBuilder.swift файлах (Shadowsocks/Hysteria2 ×2/VLESSReality/VLESSTLS/Trojan) заменить `JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)` на `JSONSerialization.data(withJSONObject: dict, options: [])`. Pre-check tests grep done в read_first.

    **L18 (lazy serverListViewModel):** В `MainScreenViewModel.swift:97` заменить `public let serverListViewModel: ServerListViewModel?` на `public private(set) lazy var serverListViewModel: ServerListViewModel? = { ... }()`. Инициализация переезжает в lazy initializer. CRITICAL — verify coordinator wiring (line ~252 `serverListViewModel?.coordinator = self`); если access pattern несовместим с lazy — fallback к standard non-lazy (документировать в commit message).

    **Commit message:** `chore(06e): batch perf-cleanup — L3 L10n lazy / L4 overlay modifier / L7 detents @State / L8 QR qos / L11 notification once / L13 .prettyPrinted → [] / L18 lazy serverListVM`.

    НЕ нарушить: DEC-06d-02 (L11 reduces XPC contention); DEC-06d-06 (PerfSignposter untouched); D-09; applyVPNStatus single authority.
  </action>

  <verify>
    <automated>swift build --package-path BBTB/Packages/AppFeatures</automated>
    Intra-bundle compile check sufficient; full regression gate в Task 5 finale.

    Local checks:
    - `grep -c "static var.*tr(" BBTB/Packages/Localization/Sources/Localization/L10n.swift` ≥ 30 (L3 partial conversion; точное число — discretion executor)
    - `grep -c "userInteractive" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift` ≥ 1 (L8)
    - `grep -rc "prettyPrinted" BBTB/Packages/Protocols/Shadowsocks BBTB/Packages/Protocols/Hysteria2 BBTB/Packages/Protocols/VLESSReality BBTB/Packages/Protocols/VLESSTLS BBTB/Packages/Protocols/Trojan` (sources only, no Tests) = 0
    - `grep -c "@State.*detents" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` ≥ 1 (L7)
  </verify>

  <done>
    - 7 LOW findings applied в одном commit
    - `swift build --package-path BBTB/Packages/AppFeatures` SUCCEEDED
    - 5 Protocols packages build SUCCEEDED
    - Commit `chore(06e): batch perf-cleanup — L3/L4/L7/L8/L11/L13/L18`
  </done>
</task>

<task type="auto">
  <name>Task 2: Theme B — correctness-cleanup bundle (L1, L9, L10, L20) — single commit</name>

  <files>
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
  </files>

  <read_first>
    - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift:372-383` (L1 — `clearDNSCache` semaphore.wait() без timeout); also `openTun` (Phase 6d M16 `5a4db9f` 2s timeout pattern — analog)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:368-389` + line 517 (L9 — current failover banner sticky logic)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift:250-265` (L10 — current `fireFailover`: attempt FIRST then observer; reorder needed)
    - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift:194-204` (L20 — current `commandServer.start` catch missing close + nil-out)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 1 L1, L9, L10, L20
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "Theme B — correctness bundle"
    - `wiki/auto-reconnect.md` (R18 sliding window — L9/L10 трогают reactive UI/Watchdog но не sliding window itself; preserve)
  </read_first>

  <action>
    4 correctness LOW findings в одном commit.

    **L1 (clearDNSCache timeout):** В `ExtensionPlatformInterface.swift` найти `clearDNSCache` (около line 372-383). Заменить каждый `semaphore.wait()` на `semaphore.wait(timeout: .now() + 2.0)`. Если результат `.timedOut` — `TunnelLogger.lifecycle.warning("clearDNSCache: semaphore.wait timed out after 2s")`. Mirror M16 `5a4db9f` openTun pattern.

    **L9 (failover banner 5s TTL):** В `MainScreenViewModel.swift` найти `showFailoverBanner(toServerName:)` (около line 517). После `reconnectBannerState = .failover(serverName: name)` spawn auto-dismiss Task через `Task { [weak self] in try? await Task.sleep(for: .seconds(5)); ... if case .failover = reconnectBannerState { reconnectBannerState = .hidden } }` обёрнутый в MainActor для мутации. `Task.sleep` через `.seconds(5)` — one-shot event-driven sleep, НЕ poll-loop; не нарушает DEC-06d-03. Inline comment с этим контекстом.

    **L10 (failoverObserver fire-before-attempt):** В `TunnelWatchdog.swift:250-265` `fireFailover(provider:)` переставить observer fire BEFORE `next.attempt()`. После reordering: log notice → `if let observer = failoverObserver { await observer(next.serverName) }` → do/catch для `_ = try await next.attempt()`. UX trade-off (banner stays briefly если attempt throws) — acceptable per RESEARCH.md L10.

    **L20 (commandServer.start catch cleanup):** В `BaseSingBoxTunnel.swift:194-204` catch блока `commandServer.start()` добавить defensive cleanup ПЕРЕД endLibboxStart: если LibBox API имеет `server.close()` — вызвать; затем `self.commandServer = nil` + `self.platformInterface = nil`. Если LibBox API не имеет `close()` — пропустить close, но всё равно nil-out references. Document в commit message.

    **Commit message:** `chore(06e): batch correctness-cleanup — L1 clearDNSCache 2s timeout / L9 failover banner 5s TTL / L10 observer-fire-before-attempt / L20 commandServer cleanup`.

    НЕ нарушить:
    - **Phase 6c R18 sliding window:** L9/L10 трогают failover UI/Watchdog но не OnDemandRulesBuilder.swift — `grep 'toggle && intent' = 2` остаётся.
    - **DEC-06d-03 event-driven status polling:** L9 TTL = one-shot Task.sleep (event-driven completion), не poll-loop в TunnelController.
    - **ExternalVPNStopMarker peek-only API:** L1/L9/L10/L20 не трогают marker.
    - **applyVPNStatus single authority:** L9 пишет в `reconnectBannerState`, не в `state`; не добавляет state setter.
  </action>

  <verify>
    <automated>swift build --package-path BBTB/Packages/AppFeatures &amp;&amp; swift build --package-path BBTB/Packages/PacketTunnelKit</automated>
    Дополнительно:
    - `grep -A 2 "clearDNSCache" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift | grep -c "timeout:"` ≥ 1 (L1)
    - `grep -A 8 "showFailoverBanner" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift | grep -c "sleep(for: .seconds(5))\|Task.sleep"` ≥ 1 (L9)
    - `grep -A 5 "commandServer.start failed\|commandServer.start fail" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift | grep -c "self.commandServer = nil\|self.platformInterface = nil"` ≥ 1 (L20)
    - `grep -n "toggle && intent" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift | wc -l` = 2 (R18 preserved)
  </verify>

  <done>
    - 4 correctness LOW findings applied в одном commit
    - swift build PacketTunnelKit + AppFeatures SUCCEEDED
    - R18 sliding window grep audit: 2 hits preserved
    - Commit `chore(06e): batch correctness-cleanup — L1/L9/L10/L20`
  </done>
</task>

<task type="auto">
  <name>Task 3: Theme C-1 — maintainability-cleanup bundle (L2, L5, L14, L15) — single commit</name>

  <files>
    BBTB/Packages/TransportRegistry/Sources/TransportRegistry/WSTransportHandler.swift
    BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift
    BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift
  </files>

  <read_first>
    - `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/WSTransportHandler.swift:14-47` (L2 — "Empty host invariant" comment + current `buildTransportBlock` без sniFallback)
    - `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:159-169` (L2 — current Trojan SNI substitution logic — collapses)
    - `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` (Phase 6d M12 fix `1621a08` уже добавил local mirror; L2 unifies к параметру)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift:37-125` (L5 — duplicate ~30 LOC pair)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:1010` (L14 — `print(...)`)
    - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:182` (analog для L14: canonical `Logger(subsystem: "app.bbtb.client", category: "settings-auto-reconnect")` pattern)
    - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift:241, 252, 277, 335` (L15 — `.notice`/`.info` per-call autoDetectControl logs)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 1 L2, L5, L14, L15
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "Theme C-1 — maintainability bundle"
    - `grep -rn "WSTransportHandler.buildTransportBlock" BBTB --include="*.swift"` (audit ВСЕХ callers перед signature change)
  </read_first>

  <action>
    4 maintainability LOW findings в одном commit.

    **L2 (WS sniFallback unification):** В `WSTransportHandler.swift` изменить signature `buildTransportBlock` — добавить `sniFallback: String?` параметр; internal logic `resolvedHost = host?.isEmpty ?? true ? (sniFallback ?? "") : (host ?? "")`. Headers ключ опускается если resolvedHost пустой (preserves "empty host invariant"). В `Trojan/ConfigBuilder.swift:159-169` удалить local SNI substitution; вызвать unified `WSTransportHandler.buildTransportBlock(host: ..., path: ..., sniFallback: parsed.sni)`. В `VLESSTLS/ConfigBuilder.swift` (M12 shipped local mirror) — аналогично удалить local fallback, вызвать unified handler с sniFallback.

    **Fallback decision:** Если signature change ломает другие 4 TransportHandler implementations (TCP/HTTP/HTTPUpgrade/gRPC) — STOP, fallback на Option A2: добавить второй WSTransportHandler overload с sniFallback (старая signature остаётся для backward-compat). Document в commit message. Acceptable per RESEARCH.md L2.

    **L5 (UserNotificationsHelper extraction):** В `UserNotificationsHelper.swift:37-125` extract two `private static` helpers:
    - `ensureAuthorized() async -> Bool` — существующая authorization check логика.
    - `post(content: UNMutableNotificationContent, identifier: String) async` — существующая post логика.
    Refactor `notifyReconnectFailed()` и `notifySingleServerUnavailable(serverName:)` to: `guard await ensureAuthorized() else { return }` + create UNMutableNotificationContent + `await post(content:, identifier:)`. Сокращение ~60 LOC → ~25.

    **L14 (print → Logger):** В `ConfigImporter.swift:1010` заменить `print("runIsSupportedUpgrade: ...")` на `Logger(subsystem: "app.bbtb.client", category: "importer-upgrade").info(...)` (Logger из `os`). Использовать `privacy: .public` interpolation modifier для `\(upgradedCount, privacy: .public)/\(candidates.count, privacy: .public)`. Category — kebab-case `importer-upgrade` (унификация с Phase 6c naming).

    **L15 (.notice → .debug):** В `ExtensionPlatformInterface.swift:241, 252, 277, 335` заменить `.notice` / `.info` per-call autoDetectControl logs на `.debug`. Keep `.error` levels для diagnostic events. Inline comment про filterability через `log stream --predicate 'category=="lifecycle" && type >= "info"'`.

    **Commit message:** `chore(06e): batch maintainability-cleanup — L2 WS sniFallback unification / L5 UserNotificationsHelper extraction / L14 print → Logger / L15 autoDetectControl log level downgrade`.

    НЕ нарушить: никакие D-09 / DEC-06d invariants (Theme C-1 = code quality only). TrojanTests / VLESSTLSTests / WSTransportHandlerTests должны pass в Task 5 finale.
  </action>

  <verify>
    <automated>swift build --package-path BBTB/Packages/TransportRegistry &amp;&amp; swift build --package-path BBTB/Packages/Protocols/Trojan &amp;&amp; swift build --package-path BBTB/Packages/Protocols/VLESSTLS &amp;&amp; swift build --package-path BBTB/Packages/AppFeatures &amp;&amp; swift build --package-path BBTB/Packages/PacketTunnelKit</automated>
    Дополнительно:
    - `grep -c "sniFallback" BBTB/Packages/TransportRegistry/Sources/TransportRegistry/WSTransportHandler.swift` ≥ 1 (L2 parameter added)
    - `grep -c "sniFallback" BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` ≥ 1 (Trojan call updated) — OR fallback documented
    - `grep -c "ensureAuthorized\|private static func post" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift` ≥ 2 (L5 extracted helpers)
    - `grep -c "Logger.*importer-upgrade" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` ≥ 1 (L14)
    - `grep -c "print(" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` reduced by at least 1 (L14 print() removed)
    - `grep -c "\.notice\|\.info" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift` reduced (L15 — at least 2 of 4 autoDetectControl calls downgraded)
  </verify>

  <done>
    - 4 maintainability LOW findings applied в одном commit
    - swift build всех затронутых packages SUCCEEDED
    - Commit `chore(06e): batch maintainability-cleanup — L2/L5/L14/L15`
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4 (pre-extraction): Theme C-2 — L16 applyVPNStatus extraction — code reviewer mode review BEFORE commit (HIGH RISK)</name>

  <files>
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
    BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift
  </files>

  <action>
    Это HUMAN-VERIFY checkpoint. Executor выполняет шаги описанные в <what-built> (extraction implementation + Codex code reviewer delegation), затем останавливается и ждёт человеческого signal согласно <resume-signal>. Полная instruction set — в <what-built> + <how-to-verify> ниже.
  </action>

  <verify>
    Human inspection per <how-to-verify> ниже. NO automated gate в этом task — это decision point. Manual verification steps: review git diff, run swift test AutoSelectIntegrationTests + ReduceStateBannerTests, read Codex reviewer response.
  </verify>

  <done>
    Human responded one of: "approved go" / "approved with notes: ..." / "reject defer L16". Executor proceeds accordingly: Task 5 commit OR revert + skip Task 5.
  </done>

  <what-built>
    L16 — extraction `applyVPNStatus` body в pure static helpers `reduceState` + `reduceBanner`. **Высокий риск:** applyVPNStatus — D-09 single authority + Phase 6c R18 sliding window invariant participant. Любое cosmetic change требует byte-by-byte verification что 16 status × 4 current-state combinations возвращают идентичный result.

    Per CONTEXT.md D-06 + RESEARCH.md Q3: BEFORE commit — обязательная code reviewer mode delegation к `mcp__codex__codex` (sandbox: read-only) для review diff.

    Шаги executor'а ПЕРЕД этим checkpoint:
    1. Прочитать `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:410-487` целиком.
    2. Реализовать extraction (см. <how-to-verify> для конкретных шагов).
    3. Создать NEW `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift` с матрицей тестов.
    4. Запустить `swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.ReduceStateBannerTests` (≥ 2 new tests PASS).
    5. Запустить `swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.AutoSelectIntegrationTests` (CRITICAL — Phase 6d post-fix armed test MUST PASS).
    6. Запустить `swift test --package-path BBTB/Packages/AppFeatures` (≥ baseline + new tests).
    7. Delegate к code reviewer: `mcp__codex__codex` с sandbox: "read-only", developer-instructions из `${CLAUDE_PLUGIN_ROOT}/prompts/code-reviewer.md` (per delegator rule), prompt 7-секционный с:
       - **CONTEXT:** Phase 6e L16 extraction; D-09 single authority + Phase 6c R18 sliding window
       - **MUST DO:** Verify byte-by-byte equivalence applyVPNStatus before/after; 16 status × 4 current-state combinations
       - **MUST NOT DO:** Suggest functional change; не предлагать новые setter sites
       - **OUTPUT:** Advisory — list of risks + go/no-go recommendation
    8. Если reviewer returns no-go → revert extraction + STOP; document в commit message rationale defer L16 в Phase 6f.
    9. Если reviewer returns go → human approves этот checkpoint → executor proceeds to Task 5.
  </what-built>

  <how-to-verify>
    **L16 extraction implementation requirements (что executor сделал ПЕРЕД checkpoint):**

    1. В `MainScreenViewModel.swift` СНАЧАЛА существующего класса (или в private extension) определить static helpers:
       ```
       internal static func reduceState(currentState: MainScreenState,
                                         status: NEVPNStatus,
                                         connectedDate: Date?) -> MainScreenState
       internal static func reduceBanner(currentBanner: ReconnectBannerState,
                                          status: NEVPNStatus,
                                          needsKillSwitch: Bool) -> ReconnectBannerState
       ```
       (точные имена типов взять из существующего кода в MainScreenViewModel.swift)

    2. Body этих helpers — switch logic byte-identical existing applyVPNStatus body. Никаких behavioral changes — только relocation.

    3. В `applyVPNStatus(_:connectedDate:)` body сократить до:
       ```
       internal func applyVPNStatus(_ status: NEVPNStatus, connectedDate: Date? = nil) {
           guard lastAppliedVPNStatus != status || lastAppliedConnectedDate != connectedDate else { return }
           lastAppliedVPNStatus = status
           lastAppliedConnectedDate = connectedDate
           state = Self.reduceState(currentState: state, status: status, connectedDate: connectedDate)
           reconnectBannerState = Self.reduceBanner(currentBanner: reconnectBannerState, status: status, needsKillSwitch: needsKillSwitchSetting)
       }
       ```
       (точные имена / additional side-effects, если есть в существующем коде — preserve as-is; relocation НЕ удаляет дополнительные mutations типа `connectionStart = connectedDate`).

    4. Phase 6e M11 explicit early-return guard (`guard state != .connecting else { return }` для .connecting/.reasserting ветки) перенести из applyVPNStatus body внутрь reduceState body — preserved.

    5. ReduceStateBannerTests.swift — минимум 2 test methods:
       - `test_reduceState_all_combinations` — matrix 4 NEVPNStatus values × 4 ConnectionState values = 16 assertions (XCTAssertEqual для каждой пары input → expected output).
       - `test_reduceBanner_all_combinations` — matrix 4 NEVPNStatus × 3 ReconnectBannerState × {true, false} needsKillSwitch ≥ 12 combinations.

    **Verification steps для HUMAN:**

    1. Открыть diff `git diff HEAD` (или последний commit candidate перед staging) — review:
       - applyVPNStatus body shrunk to ~5-7 lines после outer guard
       - Two new static funcs `reduceState` / `reduceBanner` added
       - Outer guard `lastAppliedVPNStatus / lastAppliedConnectedDate` preserved
       - Single setter authority: `grep -c "state = .*reduce\|reconnectBannerState = .*reduce" MainScreenViewModel.swift` = 2 (один в applyVPNStatus, один — это вызовы reducers)
       - НЕТ новых direct `state = ` setters в других местах
    2. Запустить локально `swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.AutoSelectIntegrationTests` — MUST PASS
    3. Запустить `swift test --package-path BBTB/Packages/AppFeatures` — ≥ baseline + 2 new tests
    4. Прочитать Codex code reviewer response — convey verdict (go / no-go / minor concerns)
    5. Решение:
       - **APPROVED + go** → type "approved go" → Task 5 proceeds (commit L16)
       - **APPROVED + minor concerns** → type "approved with notes: <list>" + executor addresses notes → re-review optional → proceed to Task 5
       - **REJECTED / no-go** → type "reject defer L16" → executor reverts extraction, документирует defer L16 в SUMMARY → SKIP Task 5 commit, proceed to Task 6 (Theme D) и далее
  </how-to-verify>

  <resume-signal>Type one of:
    - "approved go" — proceed to Task 5 (L16 commit)
    - "approved with notes: <details>" — executor addresses notes → proceed
    - "reject defer L16" — revert extraction, defer L16 в Phase 6f, skip Task 5
  </resume-signal>
</task>

<task type="auto">
  <name>Task 5: Theme C-2 — L16 commit (если checkpoint approved) — single commit</name>

  <files>
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
    BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift
  </files>

  <read_first>
    - Diff текущего рабочего дерева (extraction уже implemented в Task 4 pre-check)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "Theme C-2 — L16 standalone" (CRITICAL preservation notes)
    - Optional: Codex code reviewer response (если sandboxed читаем через provider thread output)
  </read_first>

  <action>
    Закоммитить extraction L16 (уже implemented + reviewer approved per checkpoint).

    1. `gsd-sdk query commit "refactor(06e-L16): extract reduceState/reduceBanner from applyVPNStatus (D-09 authority preserved; reviewer approved)" --files BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift`

    2. Verify commit:
       - `grep -c "func applyVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` = 1 (D-09 single authority)
       - `grep -c "func reduceState\|func reduceBanner" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` = 2
       - `grep -c "lastAppliedVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` ≥ 2 (outer guard preserved)

    **Skip-условие:** Если checkpoint Task 4 returned "reject defer L16" — SKIP this task. Executor вместо commit вызывает `git restore BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` + удаляет ReduceStateBannerTests.swift. Document в SUMMARY: "L16 deferred к Phase 6f per Codex code reviewer no-go".

    НЕ нарушить:
    - **D-09 applyVPNStatus single authority:** func count = 1.
    - **lastAppliedVPNStatus outer guard preserved.**
    - **AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects MUST PASS** (Phase 6d post-fix armed coverage).
  </action>

  <verify>
    <automated>swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.AutoSelectIntegrationTests</automated>
    Если этот test FAIL — IMMEDIATE revert per D-08 (НЕ "fix forward").

    Дополнительно:
    - `swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.ReduceStateBannerTests` PASS (новые тесты)
    - `swift test --package-path BBTB/Packages/AppFeatures` ≥ baseline + 2 (ReduceStateBannerTests)
    - `grep -c "func applyVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` = 1
  </verify>

  <done>
    - L16 commit landed (если checkpoint approved) OR L16 deferred к Phase 6f (если no-go)
    - AutoSelectIntegrationTests PASS
    - ReduceStateBannerTests PASS (если extraction proceeded)
    - D-09 applyVPNStatus single authority preserved
  </done>
</task>

<task type="auto">
  <name>Task 6: Theme D — trivial unused imports bundle (3 imports) — single commit</name>

  <files>
    BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift
    BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
    BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift
  </files>

  <read_first>
    - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift:18` (verify line 18 содержит `import ConfigParser`)
    - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift:26` (verify line 26 содержит `import ConfigParser`)
    - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift:9` (verify line 9 содержит `import DesignSystem`)
    - `.planning/phases/06d-performance-audit/06D-PERIPHERY-POST-FIX.md` (audit baseline — 37 warnings; после removal 3 imports → 34 false-positive remaining)
  </read_first>

  <action>
    3 trivial line deletions в одном commit.

    1. Edit `ServerDetailView.swift` line 18 — delete entire line `import ConfigParser`.
    2. Edit `ServerListSheet.swift` line 26 — delete entire line `import ConfigParser`. **Note:** Если Theme A Task 1 уже модифицировал этот файл (L7 @State detents), `import ConfigParser` всё ещё там — удалить.
    3. Edit `TransportPicker.swift` line 9 — delete entire line `import DesignSystem`. **Note:** `DS.*` types использовались через transitively-imported chain; verify build SUCCEEDED после removal.

    Use `Edit` tool с exact-line match для каждого файла.

    **Commit message:** `chore(06e): remove 3 unused imports (Periphery audit) — ServerDetailView/ServerListSheet ConfigParser; TransportPicker DesignSystem`.

    НЕ нарушить: build MUST SUCCEED после removal (Periphery scan уже verified zero references).
  </action>

  <verify>
    <automated>swift build --package-path BBTB/Packages/AppFeatures</automated>
    Дополнительно:
    - `grep -c "^import ConfigParser" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift` = 0
    - `grep -c "^import ConfigParser" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` = 0
    - `grep -c "^import DesignSystem" BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift` = 0
  </verify>

  <done>
    - 3 trivial imports removed в одном commit
    - swift build SUCCEEDED
    - Commit `chore(06e): remove 3 unused imports (Periphery audit) — ...`
  </done>
</task>

<task type="auto">
  <name>Task 7: End-of-Wave-2 final regression gate + D-09 grep audit + Periphery delta</name>

  <files>
    (no source files modified — verification step)
  </files>

  <read_first>
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-VALIDATION.md` (sampling rate + D-09 grep script — full 8-check audit)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 4 (architectural invariant map)
    - `.planning/phases/06d-performance-audit/06D-INVARIANT-AUDIT.md` (grep audit patterns)
  </read_first>

  <action>
    Final regression gate ПОСЛЕ всех 5 (или 4 если L16 deferred) bundle commits Wave 2.

    1. **Full swift test suite:**
       - `swift test --package-path BBTB/Packages/AppFeatures` — expected ≥ 145 (143 baseline после Wave 1 + 2 если L16 extraction proceeded) OR ≥ 143 (если L16 deferred)
       - `swift test --package-path BBTB/Packages/PacketTunnelKit` — expected 65/65 (61 baseline + 4 от Wave 1 M8)
       - `swift test --package-path BBTB/Packages/VPNCore` — baseline (Phase 6d 57/57)
       - `swift test --package-path BBTB/Packages/ConfigParser` — baseline (210/210)
       - `swift test --package-path BBTB/Packages/Localization` — baseline (3/3)
       - `swift test --package-path BBTB/Packages/TransportRegistry` — baseline (42/42)
       - `swift test --package-path BBTB/Packages/Protocols/Trojan` — baseline +
       - `swift test --package-path BBTB/Packages/Protocols/VLESSTLS` — baseline
       Each MUST be green.

    2. **iOS + macOS xcodebuild:**
       - `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build`
       - `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
       Both MUST be BUILD SUCCEEDED.

    3. **D-09 grep audit (full from VALIDATION.md):**
       ```
       grep -rIn --include='*.swift' 'ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay' BBTB/Packages BBTB/App | grep -v '/Tests/' | wc -l   # ≤ 7 (baseline 4)
       grep -rIn --include='*.swift' 'NEVPNStatusDidChange' BBTB/ | grep -E 'queue:\s*\.main' | wc -l   # 0
       grep -rIn --include='*.swift' -E '#Predicate.*UUID\?' BBTB/ | wc -l   # ≤ 1
       grep -rIn --include='*.swift' 'func applyVPNStatus' BBTB/ | wc -l   # 1
       grep -rIn --include='*.swift' 'ExternalVPNStopMarker' BBTB/ | grep '.consume(' | wc -l   # 0
       grep -n 'toggle && intent' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift | wc -l   # 2
       grep -rn 'PerfSignposter' BBTB --include="*.swift" | grep -v Tests | wc -l   # ≥ 25 (Phase 6d baseline)
       grep -c 'SingBoxConfigLoader.validate' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift   # ≥ 2 (Wave 1 M8 invariant)
       ```
       Each MUST match expected (либо документировать deviation в SUMMARY если deliberate).

    4. **Periphery scan:**
       ```
       cd BBTB && periphery scan --workspace BBTB.xcworkspace --schemes BBTB BBTB-macOS --retain-public --report json
       ```
       Expected: 34 warnings (37 baseline − 3 trivial imports removed). All remaining = false-positive. Actionable count = 0 (down from 3 в Phase 6d closure). Это закрывает QUAL-05.

    5. Если ANY check FAIL → STOP. Investigate root cause per D-08 (Phase 6c R18 lesson). НЕ "fix forward". Document failure + remediation в Wave 3 SUMMARY либо revert offending commit.

    6. Если ALL checks PASS → document в commit-less notes (для Wave 3 SUMMARY): tests counts + xcodebuild results + grep audit numbers + Periphery actionable=0.
  </action>

  <verify>
    <automated>swift test --package-path BBTB/Packages/AppFeatures &amp;&amp; swift test --package-path BBTB/Packages/PacketTunnelKit &amp;&amp; xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build &amp;&amp; xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO</automated>

    Дополнительно executor выполняет D-09 grep audit script (8 checks) + Periphery scan и записывает результаты для Wave 3 SUMMARY (через temporary working notes — НЕ commit).
  </verify>

  <done>
    - All swift test packages green (AppFeatures ≥ 143/143 либо ≥ 145; PacketTunnelKit ≥ 65/65; others baseline)
    - iOS + macOS xcodebuild BUILD SUCCEEDED
    - D-09 grep audit (8 checks) — все expected values matched
    - Periphery actionable count = 0 (QUAL-05 closed)
    - Working notes prepared для Wave 3 SUMMARY (test counts, xcodebuild results, audit grep results)
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| App ↔ NEVPN system observers | L9 / L10 trogают reactive UI / Watchdog timing — sliding window / single authority surface |
| App ↔ TransportRegistry / Protocols | L2 changes WSTransportHandler signature; cross-protocol contract |
| App ↔ PacketTunnelExtension | L1 (clearDNSCache timeout) + L20 (commandServer cleanup) modify extension correctness |
| L16 — applyVPNStatus extraction | D-09 single authority surface; Phase 6c R18 sliding window invariant participant |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-6e-02 | Denial of Service / Correctness | L16 — reduceState/reduceBanner extraction | **mitigate** | (carries forward from Wave 1) Byte-by-byte verification 16 status × 4 current-state combinations via ReduceStateBannerTests; AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects MUST PASS. **Code reviewer mode delegation (mcp__codex__codex sandbox=read-only) MANDATORY перед commit** (Task 4 checkpoint). Failure → revert + defer L16 в Phase 6f per D-08. HIGH severity if reactive UI driver breaks. |
| T-6e-03 | Information Disclosure | L5 — UserNotificationsHelper extraction | **accept** | Extract refactor preserves существующий authorization + post logic; no new attack surface. LOW severity. |
| T-6e-05 | Tampering | L2 — WS sniFallback parameter unification | **mitigate** | Signature change может breaking change для других TransportHandler implementations. Fallback на Option A2 (overload, не signature change) если other 4 handlers breaking. Tests TrojanTests + VLESSTLSTests + WSTransportHandlerTests должны PASS в Task 7 final gate. MEDIUM severity if cross-protocol contract drifts. |
| T-6e-06 | Denial of Service | L1 — clearDNSCache 2s timeout | **mitigate** | Mirror M16 `5a4db9f` proven pattern (openTun 5s → 2s). Timeout fallback logs warning but не блокирует libbox thread. LOW severity — defensive correctness fix. |
| T-6e-07 | Tampering | L20 — commandServer.start catch cleanup | **mitigate** | Defensive nil-out prevents stale references если start throws. LOW severity — improves error path hygiene. |
| T-6e-08 | Information Disclosure | L14 — print → Logger + L15 .notice → .debug | **accept** | Observability trade-off documented. LOW severity. |
</threat_model>

<verification>
**Single end-of-Wave-2 regression gate (Task 7) per CONTEXT.md D-04:**
1. `swift test --package-path BBTB/Packages/AppFeatures` ≥ 143/143 (или ≥ 145 если L16 extraction landed)
2. `swift test --package-path BBTB/Packages/PacketTunnelKit` ≥ 65/65
3. Other packages: baseline (VPNCore 57/57, ConfigParser 210/210, Localization 3/3, TransportRegistry 42/42, Protocols 35+)
4. `xcodebuild ... BBTB iOS Simulator build` → BUILD SUCCEEDED
5. `xcodebuild ... BBTB-macOS build` → BUILD SUCCEEDED
6. D-09 grep audit (8 checks per VALIDATION.md) — all expected values matched
7. Periphery actionable count = 0 (QUAL-05 closure proof)

**Intra-bundle (Tasks 1-3, 6):** `swift build` compile-only checks acceptable (per D-04a — single gate в конце Wave 2).

**Task 4 checkpoint:** code reviewer mode delegation MANDATORY перед L16 commit (mcp__codex__codex sandbox=read-only). If reviewer returns no-go → defer L16, skip Task 5 commit.

**D-08 FAIL recovery:** если final gate FAIL — revert offending commit (likely L9/L10 R18 violation или L2 cross-protocol breaking), investigate, retry. НЕ "fix forward" (Phase 6c R18 lesson). Если 2+ failures на одном LOW finding — defer в Phase 6f per RESEARCH.md Section 5 Q3 escalation path.
</verification>

<success_criteria>
- 4 или 5 bundle commits landed (Theme A perf, Theme B correctness, Theme C-1 maintainability, Theme C-2 L16 [conditional], Theme D imports)
- L16: либо committed (если reviewer approved) либо deferred к Phase 6f (если reviewer no-go) — оба acceptable
- ReduceStateBannerTests.swift created с 16+12 = ≥ 28 combinatorial assertions (если L16 extraction proceeded)
- Final regression gate Task 7 green: swift test всех packages baseline+ ≥; iOS + macOS xcodebuild SUCCEEDED; D-09 grep audit (8 checks) match expected; Periphery actionable = 0
- 3 trivial imports removed (Periphery delta: 37 → 34 warnings, все remaining = false-positive)
- Bookkeeping rows для L6 (subsumed by H5 `5ef3888`), L17 (subsumed by `bc7bc26` + `1467328`), L19 (subsumed by H7 `b8d9294`) — для Wave 3 SUMMARY (no code change в Wave 2)
- DEC-06d-01..06 preserved: cold-start defer; XPC consolidation (L11 reduces N→1); event-driven status polling (L9 TTL = one-shot Task.sleep, не poll); bounded probe; Apple-canonical options; PerfSignposter spans
- Phase 6c R18 sliding window invariant: `grep 'toggle && intent' OnDemandRulesBuilder.swift = 2` (preserved)
- ExternalVPNStopMarker `.consume(` callers = 0 (peek-only API preserved)
- D-09 applyVPNStatus single authority preserved: `grep -c "func applyVPNStatus" MainScreenViewModel.swift = 1`
- AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects PASS (CRITICAL — Phase 6d post-fix armed coverage)
</success_criteria>

<output>
After completion, create `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-02-SUMMARY.md` со следующим:
- 4 или 5 bundle commits + their SHAs
- L16 status: commit landed (SHA) OR deferred к Phase 6f (rationale + Codex reviewer notes)
- ReduceStateBannerTests.swift test count (если landed)
- End-of-Wave-2 regression gate results: AppFeatures / PacketTunnelKit / iOS / macOS test counts + xcodebuild results
- D-09 grep audit (8 checks) — actual values vs expected
- Periphery actionable count (target 0)
- Bookkeeping rows для L6, L17, L19 (subsumed-by-6d references)
- Carry-forward для Wave 3: closure documentation + STATE/ROADMAP/REQUIREMENTS sync + wiki sync
</output>
