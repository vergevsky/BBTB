# Baseline — Cold launch, iPhone, pre-fix

**Phase 6d Wave 06D-02c заполнит этот файл реальными данными после первого Instruments-прохода.**

## Summary

_(одна-две строки — pre-fix ColdLaunch ms на iPhone, основной findings)_

## Methodology

- **Instrument:** `App Launch` + `Points of Interest` (subsystem=`app.bbtb.client.ios`, category=`performance`, span=`ColdLaunch`).
- **Build configuration:** Debug, без attach debugger (cold launch).
- **Procedure:** 5 cold-launches с killall между каждым; первый прогон отбрасываем (filesystem cache warm-up); медиана из 4 оставшихся.

## Device

- **Model:** _(iPhone 15 Pro / iPhone 13 / etc.)_
- **iOS version:** _(26.x)_
- **App version (CFBundleShortVersionString + CFBundleVersion):** _(_/build_)_
- **Storage free:** _(GB)_
- **Battery state:** _(plugged in / unplugged / battery %)_

## Samples

| # | ColdLaunch ms | Notes |
|---|---|---|
| 1 (discarded) | — | filesystem warm-up |
| 2 | — | — |
| 3 | — | — |
| 4 | — | — |
| 5 | — | — |
| **Median (#2–#5)** | **—** | — |

## Numerical summary

| Metric | Value | Source |
|---|---|---|
| ColdLaunch median (ms) | — | OSSignposter span |
| Time to first frame (ms) | — | App Launch instrument |
| Total CPU time (ms) | — | App Launch instrument |
| Peak resident memory (MB) | — | Allocations |
| Pre-main dyld load time (ms) | — | App Launch |
| Main-thread blocking calls > 16 ms | — | Time Profiler |

## Top heavy stack traces

_(top 3–5 stacks, sorted by self-time, with brief annotation)_

1. _(stack trace 1 + ms + annotation)_
2. _(stack trace 2 + ms + annotation)_
3. _(stack trace 3 + ms + annotation)_

## OSSignposter spans (Points of Interest)

| Span | begin → end (ms) | Notes |
|---|---|---|
| ColdLaunch | — | outer span |
| ProvisionProfile | — | only if connect-on-launch ran |
| ConnectTap | — | only if connect-on-launch ran |
| PreConnectProbe | — | only if connect-on-launch ran |
| LibboxStart | — | only if connect-on-launch ran |

## Screenshots / .trace artifacts

_(stored locally in `baselines/screenshots/` and `traces-local/`; not committed — see .gitignore)_

## Follow-ups

_(action items для Wave 06D-03 / 04 / 05, на основе findings выше)_
