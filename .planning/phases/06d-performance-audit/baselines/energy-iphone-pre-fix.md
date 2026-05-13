# Baseline — Energy, iPhone, pre-fix

**Phase 6d Wave 06D-02c заполнит этот файл реальными данными после первого Instruments-прохода.**

## Summary

_(одна-две строки — pre-fix Energy Impact, CPU/Network/Networking energy на iPhone)_

## Methodology

- **Instrument:** `Energy Log` + `Activity Monitor`.
- **Build configuration:** Release; реальное устройство (не Simulator).
- **Procedure:** 10-минутный run в фоне с активным VPN, экран выключен. Фиксируем CPU%, Wakeups/s, Network packets/s.

## Device

- **Model:** _(iPhone 15 Pro / iPhone 13 / etc.)_
- **iOS version:** _(26.x)_
- **App version:** _(_/build_)_
- **Battery level start / end:** _(% / %)_
- **Network:** _(Wi-Fi / Cellular)_

## Numerical summary

| Metric | Value | Source |
|---|---|---|
| Average CPU % (10 min, screen off) | — | Activity Monitor |
| Wakeups / second (NEVPNStatusDidChange и др.) | — | Activity Monitor |
| Energy impact score (Xcode) | — | Energy Log |
| Network — packets in / out per minute | — | Network instrument |
| Battery drop % over 10 min | — | Settings → Battery |
| Discharge rate %/hr (extrapolated) | — | derived |

## Wakeups breakdown

| Source | Wakeups/sec | Notes |
|---|---|---|
| NEVPNStatusDidChange | — | should be 0 in steady-state per D-09 |
| NWPathMonitor | — | network change events |
| Timer / DispatchSource | — | should be 0 in steady-state |
| Other | — | — |

## Top heavy stack traces (background)

1. _(stack trace 1 + wakeups + annotation)_
2. _(stack trace 2 + wakeups + annotation)_
3. _(stack trace 3 + wakeups + annotation)_

## Screenshots / .trace artifacts

_(stored locally in `baselines/screenshots/` and `traces-local/`; not committed — see .gitignore)_

## Follow-ups

_(action items для Wave 06D-03 / 04 / 05, на основе findings выше)_
