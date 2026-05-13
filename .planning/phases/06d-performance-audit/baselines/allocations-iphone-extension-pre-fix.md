# Baseline — Allocations (PacketTunnel extension), iPhone, pre-fix

**Phase 6d Wave 06D-02c заполнит этот файл реальными данными после первого Instruments-прохода.**

## Summary

_(одна-две строки — pre-fix memory footprint tunnel extension на iPhone; iOS extension memory hard limit = 50 MB на современных версиях, важно знать запас)_

## Methodology

- **Instrument:** `Allocations` + `Leaks`, attach к `BBTB_Tunnel_iOS.appex` process.
- **Build configuration:** Debug.
- **Procedure:** Connect tunnel → idle 60s → run 100 MB of typical traffic (~ 30 sec sustained download) → idle 60s → disconnect. Snapshot peak.

## Device

- **Model:** _(iPhone 15 Pro / iPhone 13 / etc.)_
- **iOS version:** _(26.x)_
- **App version:** _(_/build_)_

## Numerical summary

| Metric | Value | Limit | Source |
|---|---|---|---|
| Peak resident memory (MB) | — | **50 MB** (iOS extension hard limit) | Allocations |
| Heap allocations at peak | — | — | Allocations |
| Sing-box Go runtime heap (MB) | — | — | runtime/pprof через LibboxCommandServer (если экспонировано) |
| libIndexStore + Libbox framework size | — | — | static |
| Memory-pressure events | — | should be 0 | log Subsystem `com.apple.networkextension` |

## Top heavy class allocations

| Class / category | Persistent count | Persistent bytes | Notes |
|---|---|---|---|
| _(class 1)_ | — | — | — |
| _(class 2)_ | — | — | — |
| _(class 3)_ | — | — | — |

## Sing-box internal allocations (если доступны)

| Component | Heap MB |
|---|---|
| outbound (VLESS-Reality TLS state) | — |
| TUN inbound buffer | — |
| DNS cache | — |
| Rule engine | — |

## Detected leaks

_(если 0 — записать «No leaks detected»; иначе stack traces)_

## Screenshots / .trace artifacts

_(stored locally in `baselines/screenshots/` and `traces-local/`; not committed — see .gitignore)_

## Follow-ups

_(action items для Wave 06D-03 / 04 / 05; критично для bug class «extension jetsam-kill при > 50 MB»)_
