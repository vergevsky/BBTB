# Baseline — Allocations (host app), iPhone, pre-fix

**Phase 6d Wave 06D-02c заполнит этот файл реальными данными после первого Instruments-прохода.**

## Summary

_(одна-две строки — pre-fix memory footprint host app на iPhone)_

## Methodology

- **Instrument:** `Allocations` + `Leaks`.
- **Build configuration:** Debug (Allocations требует non-stripped symbols).
- **Procedure:** Cold launch → idle 10s → connect → idle 60s → disconnect → idle 30s. Snapshot peak resident memory + outstanding allocations.

## Device

- **Model:** _(iPhone 15 Pro / iPhone 13 / etc.)_
- **iOS version:** _(26.x)_
- **App version:** _(_/build_)_

## Numerical summary

| Metric | Value | Source |
|---|---|---|
| Peak resident memory (MB) | — | Allocations |
| Heap allocations at peak | — | Allocations |
| Persistent bytes after disconnect | — | Allocations snapshot delta |
| Leaks detected | — | Leaks instrument |
| Number of NETunnelProviderManager retain cycles | — | Memory Graph |

## Top heavy class allocations

| Class / category | Persistent count | Persistent bytes | Notes |
|---|---|---|---|
| _(class 1)_ | — | — | — |
| _(class 2)_ | — | — | — |
| _(class 3)_ | — | — | — |

## Heap growth analysis (connect → disconnect cycle)

| Cycle # | Heap size before connect | Heap size after disconnect | Delta |
|---|---|---|---|
| 1 | — | — | — |
| 2 | — | — | — |
| 3 | — | — | — |

_(growth > 1 MB per cycle = potential leak)_

## Detected leaks

_(если 0 — записать «No leaks detected»; иначе stack traces)_

## Screenshots / .trace artifacts

_(stored locally in `baselines/screenshots/` and `traces-local/`; not committed — see .gitignore)_

## Follow-ups

_(action items для Wave 06D-03 / 04 / 05, на основе findings выше)_
