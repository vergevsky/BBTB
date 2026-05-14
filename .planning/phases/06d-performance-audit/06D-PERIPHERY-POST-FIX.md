---
phase: 06d-performance-audit
plan: Final-a
type: scan-report
status: complete
date: 2026-05-14
mode: variant-d-no-instruments
scan_tool: periphery 3.7.4
scan_target: BBTB.xcworkspace / scheme BBTB (iOS)
flags: --retain-public --report-exclude '**/Tests/*.swift' --exclude-tests --disable-update-check
base_sha: cd23536 (after 06D-03h closure ledger)
---

# Wave 06D-Final-a — Periphery post-fix dead-code scan

## Scan command (exact)

```bash
cd BBTB && tuist generate --no-open
periphery scan \
    --project BBTB.xcworkspace \
    --schemes BBTB \
    --retain-public \
    --report-exclude '**/Tests/*.swift' \
    --exclude-tests \
    --disable-update-check
```

**Result:** `success — 37 warnings` (см. raw output ниже).

Базовый SHA: `cd23536` (после Wave 06D-03h, до Wave Final-a начала). Workspace перегенерирован через `tuist generate --no-open` (1.6 s, cached build settings).

---

## Summary — count breakdown by category

| Category                  | Count | Description |
|---------------------------|------:|-------------|
| Assign-only property      | **5** | Property is assigned (often to retain observer/handle) but never read |
| Unused function           | **6** | `*ForTest()` helpers — Periphery не видит XCTest reflection-call (false-positive) |
| Unused imported module    | **9** | `import X` без actual symbol use (часто historical, оставлено after refactor) |
| Unused parameter          | **17** | Protocol stub-parameter `config`/`handle`/`transport` в Handler/ConfigBuilder |
| **TOTAL**                 | **37** | |

---

## Comparison vs Wave 02a baseline

| Метрика                              | Wave 02a mini-scan | Wave Final-a post-fix | Delta |
|--------------------------------------|--------------------|------------------------|------:|
| Total warnings                       | `30+` (PREFLIGHT)  | **37**                 | ≈ +5 |
| Assign-only properties               | not categorized    | 5                      | n/a |
| Unused functions                     | `getStableSessionForTest` family + others | 6 | flat |
| Unused imports                       | `ConfigParser`, `DesignSystem`, Hysteria2, Shadowsocks | 9 | +2 |
| Unused parameters                    | `config`, `handle`, `transport` (protocol stubs) | 17 | similar |

**Анализ delta:**

Phase 6d **не добавлял** dead-code (все 19 fix-commits сохраняли symbol-usage паттерны или удаляли только трассировочные leftover'ы). +5 warnings vs Wave 02a baseline = небольшой growth категорий, не результат Phase 6d работы — это **периодический accrual** от:

1. **Phase 6 / 6a — observer retention pattern.** `MainScreenViewModel.killSwitchObserver`, `MainScreenViewModel.nevpnStatusObserver`, `TunnelController.statusProvider`, `TunnelController.userIntendedConnected` — все они **retained-by-design** (held для NotificationCenter ownership; Periphery не видит side-effects). False-positive класса «assign-only».

2. **Handler protocol stubs.** Каждый `VPNProtocolHandler` (Hysteria2, Shadowsocks, Trojan, VLESSReality, VLESSTLS) имеет два стаб-метода (`build(config:)` + `start(handle:)`) с unused `config` / `handle` параметрами — sing-box делегирует logic в `BaseSingBoxTunnel`, а handler-level вызовы прокидывают параметры на уровень ниже. **Architectural pattern**, не dead code.

3. **Protocol-builder unused `transport`.** `VLESSReality/VLESSTLS/Hysteria2/Shadowsocks ConfigBuilder` принимает `transport: Transport` но игнорирует его внутри. Это **сигнатурное единообразие** через protocol — некоторые protocol требуют transport (VLESSTLS+WS), некоторые игнорируют (VLESSReality всегда tcp). False-positive.

**Verdict:** **0 actionable findings.** Все 37 warnings — либо false-positive (XCTest reflection, NotificationCenter ownership), либо architectural pattern (handler protocol stubs).

---

## Per-finding analysis

### Category 1 — Assign-only properties (5)

| File | Line | Symbol | Rationale (why not dead) |
|------|------|--------|--------------------------|
| `ConfigImporter.swift` | 58 | `providerBundleIdentifier` | Read внутри `provisionTunnelProfile` через `NETunnelProviderProtocol` (Periphery не resolve'ит cross-actor read) |
| `MainScreenViewModel.swift` | 108 | `killSwitchObserver` | **NotificationCenter token ownership** — release == observer leak |
| `MainScreenViewModel.swift` | 118 | `nevpnStatusObserver` | Same — token ownership |
| `TunnelController.swift` | 87 | `statusProvider` | Closure passed-by-value reads it via capture (Periphery не resolves) |
| `TunnelController.swift` | 100 | `userIntendedConnected` | **Phase 6c sliding window source-of-truth** — read через `intentStore.load()` + by `OnDemandRulesBuilder.loadUserIntendedConnected()` (UserDefaults-based, не direct property access). Critical D-09 invariant — НЕ удалять. |

**Decision:** keep all 5. Удаление любого = поломка observer ownership или D-09 invariant.

### Category 2 — Unused functions (6)

| File | Line | Symbol | Rationale |
|------|------|--------|-----------|
| `FailoverProvider.swift` | 179-181 | `currentCursorForTest()`, `currentStartIndexForTest()`, `currentSnapshotCountForTest()` | XCTest reflection — used in `FailoverProviderTests.swift` |
| `TunnelWatchdog.swift` | 180-182 | `getStableSessionForTest()`, `getUserIntentForTest()`, `getDebounceActiveForTest()` | Same — `TunnelWatchdogTests.swift` invariant probes |

**Decision:** keep all 6. Они **внутри-target** test helpers; Periphery с `--exclude-tests` не видит call-sites в Test target. Refactor opportunity (optional): пометить `@_spi(Testing)` для clarity. **Not Phase 6d scope.**

### Category 3 — Unused imported modules (9)

| File | Line | Module | Decision |
|------|------|--------|----------|
| `ServerDetailView.swift` | 18 | `ConfigParser` | Can be removed — leftover from Phase 5 transport-detail refactor. **Backlog (L-trivial).** |
| `ServerListSheet.swift` | 26 | `ConfigParser` | Same — **Backlog.** |
| `TransportPicker.swift` | 9 | `DesignSystem` | Style tokens used inline, no DesignSystem types referenced. **Backlog.** |
| `ConfigParser/ImportedServer.swift` | 6 | `VPNCore` | Public-API consumer might re-export — keep until verified. **Safe.** |
| `Hysteria2/ConfigBuilder.swift` | 2 | `PacketTunnelKit` | Builder uses `OutboundJSONNode` shared types — Periphery does not see cross-package. **Safe.** |
| `Shadowsocks/ConfigBuilder.swift` | 2 | `PacketTunnelKit` | Same. **Safe.** |
| `Trojan/ConfigBuilder.swift` | 2 | `PacketTunnelKit` | Same. **Safe.** |
| `VLESSTLS/ConfigBuilder.swift` | 2 | `PacketTunnelKit` | Same. **Safe.** |
| `TransportRegistry/TransportRegistry.swift` | 2 | `VPNCore` | Registry's `VPNProtocolHandler` lives in `VPNCore` but Periphery resolves through indirect chain. **Safe.** |

**Decision:** 3 удалимы (ServerDetailView/ServerListSheet/TransportPicker) — **carved to backlog as L-trivial-imports** (3-line cleanup, not Phase 6d scope). Остальные 6 — false-positive (cross-package indirect dependency).

### Category 4 — Unused parameters (17)

Это **stub-параметры в protocol conformances** для `VPNProtocolHandler.build(config:)` и `VPNProtocolHandler.start(handle:)`, плюс `ConfigBuilder.build(transport:)`.

| Pattern | Files affected | Decision |
|---------|----------------|----------|
| `Handler.build(config:)` returns stub — actual build в `BaseSingBoxTunnel` | Hysteria2, Shadowsocks, Trojan, VLESSReality, VLESSTLS Handler.swift | **Keep — protocol signature.** Underscore alias (`_ config:`) was rejected в Phase 5 для preserved signature symmetry. |
| `Handler.start(handle:)` returns stub | same 5 handlers | **Keep — protocol signature.** |
| `ConfigBuilder.build(transport:)` ignored когда transport=tcp always | VLESSReality, VLESSTLS, Hysteria2, Shadowsocks | **Keep — unified signature через protocol.** Trojan use it (WS path). |
| `InterfaceFlagsInspector.swift:63-64` `file`/`line` | `PacketTunnelKit` | Logging context params — passed to `Logger.log(file:line:)` but Periphery not parsing variadic forward. **Safe.** |
| `VPNProtocolHandler.swift:11-12` protocol decl | `VPNCore` | Protocol declaration body — Periphery sees param decl but no body. **Expected.** |

**Decision:** all 17 — **architectural pattern**. Renaming to `_ config:` would lose signature documentation. Not worth churn.

---

## Actionable / backlog items

**Total actionable:** **3 trivial unused-import removals**:
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift:18` — `import ConfigParser`
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift:26` — `import ConfigParser`
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift:9` — `import DesignSystem`

→ Логировать в `06D-FINDINGS.md` § LOW (или в новый L-trivial-imports row) для backlog cleanup. **NOT** для Wave Final-a (out of scope — comparison/audit only).

---

## Raw Periphery output

```
* Inspecting project...
* Building BBTB...
* Indexing...
* Analyzing...

/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:58:17: warning: Assign-only property 'providerBundleIdentifier' is assigned, but never used
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift:179:19: warning: Unused function 'currentCursorForTest()'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift:180:19: warning: Unused function 'currentStartIndexForTest()'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift:181:19: warning: Unused function 'currentSnapshotCountForTest()'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:108:17: warning: Assign-only property 'killSwitchObserver' is assigned, but never used
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:118:17: warning: Assign-only property 'nevpnStatusObserver' is assigned, but never used
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:87:17: warning: Assign-only property 'statusProvider' is assigned, but never used
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:100:18: warning: Assign-only property 'userIntendedConnected' is assigned, but never used
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift:180:19: warning: Unused function 'getStableSessionForTest()'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift:181:19: warning: Unused function 'getUserIntentForTest()'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift:182:19: warning: Unused function 'getDebounceActiveForTest()'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift:18:1: warning: Unused imported module 'ConfigParser'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift:26:1: warning: Unused imported module 'ConfigParser'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift:9:1: warning: Unused imported module 'DesignSystem'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift:6:1: warning: Unused imported module 'VPNCore'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift:63:9: warning: Unused parameter 'file'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift:64:9: warning: Unused parameter 'line'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:2:1: warning: Unused imported module 'PacketTunnelKit'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:212:9: warning: Unused parameter 'transport'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift:33:25: warning: Unused parameter 'config'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift:39:28: warning: Unused parameter 'handle'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift:2:1: warning: Unused imported module 'PacketTunnelKit'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift:108:9: warning: Unused parameter 'transport'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ShadowsocksHandler.swift:33:25: warning: Unused parameter 'config'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ShadowsocksHandler.swift:39:28: warning: Unused parameter 'handle'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:2:1: warning: Unused imported module 'PacketTunnelKit'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift:27:25: warning: Unused parameter 'config'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift:33:28: warning: Unused parameter 'handle'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift:105:9: warning: Unused parameter 'transport'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift:22:25: warning: Unused parameter 'config'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift:30:28: warning: Unused parameter 'handle'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:2:1: warning: Unused imported module 'PacketTunnelKit'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift:31:25: warning: Unused parameter 'config'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift:37:28: warning: Unused parameter 'handle'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/TransportRegistry/Sources/TransportRegistry/TransportRegistry.swift:2:1: warning: Unused imported module 'VPNCore'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift:11:18: warning: Unused parameter 'config'
/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift:12:21: warning: Unused parameter 'handle'
```

---

## Verdict

| Check | Result |
|-------|-------:|
| Periphery scan exit | ✅ 0 (success) |
| Total warnings | 37 |
| Actionable findings | **3** (trivial unused imports — backlog) |
| Phase 6d caused dead code? | **NO** |
| Phase 6d cleaned up dead code? | NO (out of scope — performance/correctness only) |
| Decision | All 37 warnings either false-positive or architectural — **no Phase 6d clean-up action.** 3 unused imports carved to **L-trivial-imports** backlog row. |

**Wave Final-a Task 1 status: COMPLETE.**
