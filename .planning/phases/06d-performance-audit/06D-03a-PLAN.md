---
phase: 06d-performance-audit
plan: 03a
slice: a
type: execute
wave: 3.1
mode: mvp
depends_on: [02b]
files_modified:
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
autonomous: true
requirements: [QUAL-01, PERF-02]
findings_addressed: [H1]
tags: [fix-cycle, phase-5-leftover, debug-gating, energy-launch-win]
status: complete

must_haves:
  truths:
    - "logLevel='trace' и logPath gated под #if DEBUG в BaseSingBoxTunnel.swift; Release: logPath=nil + logLevel='info'."
    - "exportSingBoxLogToDocuments() gated под #if DEBUG в BBTB_iOSApp.swift; Release: cold-start не делает file copy."
    - "AppFeatures swift test 133/133 + iOS+macOS xcodebuild green."
    - "Никаких behavioral changes для DEBUG buildов — `xcodebuild build` (default Debug) идентичен прежнему."
    - "D-09 invariant pre-check для BBTB_iOSApp.swift (sensitive file): не тронут intent-closing path, observer queue, applyVPNStatus authority, sliding window. Touch limited к Phase-1 debug bridge block."
---

# Wave 06D-03a — H1 trace-logging cleanup

## Цель волны

Закрытие **H1 (3/3 strong consensus)** — Phase 5 debug leftover, главный кандидат на «феель тяжести с Phase 5».

Два места исправлены через `#if DEBUG` gating:

1. **`BaseSingBoxTunnel.swift:186-205`** — extension вызов `expandConfigForTunnel(logPath:logLevel:)`:
   - Debug: `logPath = AppGroupContainer.singBoxLogPath`, `logLevel = "trace"` (current dev behavior preserved).
   - Release: `logPath = nil`, `logLevel = "info"` → SingBoxConfigLoader skip-ает весь log block (line 150-157), sing-box не пишет log файл.

2. **`BBTB_iOSApp.swift:36-52`** — cold-start вызов `AppGroupContainer.exportSingBoxLogToDocuments()`:
   - Debug: full file copy + Logger notice (preserved для разработки).
   - Release: весь блок skipped — no main-thread file copy, no diagnostic Logger setup.

## D-09 invariant pre-check (sensitive file BBTB_iOSApp.swift)

| Invariant | Status |
|---|---|
| TunnelController.handleStatusChange UNCHANGED | ✅ Не тронут (другой файл) |
| No XPC в NEVPNStatusDidChange observer | ✅ Не тронут (observer выше по коду) |
| No reintroduction ReconnectStateMachine / NetworkReachability | ✅ Файл не trog'ет эти классы |
| applyVPNStatus single authority | ✅ Не тронут |
| Sliding window invariant | ✅ Не тронут |
| Observer queue=`nil` (Phase 6c Round 6) | ✅ Не тронут |
| No `#Predicate` UUID? | ✅ Не тронут |

Edit limited к Phase-1 debug bridge block (lines 36-52). PerfSignposter ColdLaunch span (lines 22-31 + 127-133) preserved.

## Acceptance criteria per finding

### H1 acceptance

| Check | Required | Result |
|---|---|---|
| `BaseSingBoxTunnel.swift` contains `#if DEBUG` gate для logPath/logLevel | yes | ✅ lines 186-198 |
| `BaseSingBoxTunnel.swift` Release branch has `logPath: String? = nil` | yes | ✅ line 192 |
| `BaseSingBoxTunnel.swift` Release branch has `logLevel = "info"` | yes | ✅ line 193 |
| `BBTB_iOSApp.swift` contains `#if DEBUG ... #endif` wrap для exportSingBoxLogToDocuments call | yes | ✅ lines 45-52 |
| AppFeatures swift test 133/133 | yes | ✅ 7.41s, 0 failures |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| D-09 forbidden symbols grep | 0 / 0 / 0 | ✅ untouched |

## Atomic commit

```
fix(06d-03a): gate Phase 5 trace-logging behind #if DEBUG (H1)

3/3 strong consensus finding from Wave 06D-01:
- Opus #40 (MEDIUM): logLevel="trace" leftover from Phase 1 debug
- Codex #4 (HIGH): tens of MB log writes per session
- Gemini #2 (HIGH): main cause of "feels heavy since Phase 5"

Fix 1 (BaseSingBoxTunnel.swift): gate logPath + logLevel="trace"
behind #if DEBUG. Release builds pass logPath=nil + logLevel="info".
SingBoxConfigLoader.expandConfigForTunnel skips the entire log block
when logPath is nil (existing behavior).

Fix 2 (BBTB_iOSApp.swift): gate exportSingBoxLogToDocuments() call
behind #if DEBUG. Release builds skip the multi-MB file copy that
blocked cold-start main thread before first frame.

Regression gate green:
- AppFeatures swift test 133/133 (7.41s)
- iOS Simulator xcodebuild BUILD SUCCEEDED
- macOS xcodebuild BUILD SUCCEEDED

Expected user-visible delta (post-baseline):
- Cold start: -200-500ms on warm Release builds (no file copy)
- Energy: significant reduction during long sessions (no trace I/O)
- Disk: App Group quota usage near-zero in Release
```

## Next

Wave 06D-03b — H2 (redundant XPC trips в `TunnelController.connect()`) + H3 (1s connect polling) + H8 (5s disconnect polling). 3 atomic commits в TunnelController.swift.
