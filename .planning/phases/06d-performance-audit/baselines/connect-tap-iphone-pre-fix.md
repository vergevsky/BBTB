# Baseline — Connect-tap, iPhone, pre-fix

**Phase 6d Wave 06D-02c заполнит этот файл реальными данными после первого Instruments-прохода.**

## Summary

_(одна-две строки — pre-fix ConnectTap ms на iPhone, основной findings)_

## Methodology

- **Instrument:** `Time Profiler` + `Points of Interest` (subsystem=`app.bbtb.client`, category=`performance`, spans=`ConnectTap`, `PreConnectProbe`, `ProvisionProfile`; subsystem=`app.bbtb.tunnel`, category=`performance`, span=`LibboxStart`).
- **Build configuration:** Debug, app уже launched, VPN отключен. Тап на Connect → ждём status=connected.
- **Procedure:** 5 toggle-циклов (connect → wait connected → disconnect → wait disconnected) с 10s паузой между; медиана из 5.

## Device

- **Model:** _(iPhone 15 Pro / iPhone 13 / etc.)_
- **iOS version:** _(26.x)_
- **App version:** _(_/build_)_
- **Network:** _(Wi-Fi RU / Wi-Fi EU / Cellular)_

## Samples

| # | ConnectTap ms | PreConnectProbe ms | ProvisionProfile ms | LibboxStart ms | Notes |
|---|---|---|---|---|---|
| 1 | — | — | — | — | — |
| 2 | — | — | — | — | — |
| 3 | — | — | — | — | — |
| 4 | — | — | — | — | — |
| 5 | — | — | — | — | — |
| **Median** | **—** | **—** | **—** | **—** | — |

## Numerical summary

| Metric | Value | Source |
|---|---|---|
| ConnectTap median (ms) | — | OSSignposter outer span |
| Of which PreConnectProbe (ms) | — | nested span |
| Of which ProvisionProfile (ms) | — | nested span |
| Of which LibboxStart (extension process, ms) | — | nested span (other process!) |
| Main-thread blocking ops > 16 ms in connect path | — | Time Profiler |
| XPC round-trips (`loadAllFromPreferences` / `saveToPreferences`) | — | counted from logs / Network instrument |

## Top heavy stack traces

1. _(stack trace 1 + ms + annotation)_
2. _(stack trace 2 + ms + annotation)_
3. _(stack trace 3 + ms + annotation)_

## OSSignposter spans (Points of Interest)

| Span | begin → end (ms) | Process | Notes |
|---|---|---|---|
| ConnectTap | — | Host app | outer |
| PreConnectProbe | — | Host app | nested in ConnectTap |
| ProvisionProfile | — | Host app | nested in ConnectTap |
| LibboxStart | — | Tunnel extension | covers libbox.start through setTunnelNetworkSettings; NOT a nested span of ConnectTap process-wise (different OS process). Cross-process correlation through timeline view. |

## Screenshots / .trace artifacts

_(stored locally in `baselines/screenshots/` and `traces-local/`; not committed — see .gitignore)_

## Follow-ups

_(action items для Wave 06D-03 / 04 / 05, на основе findings выше)_
