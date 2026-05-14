---
status: partial
phase: 06e-performance-audit-round-2-macos-uat-replay
source: [06E-VERIFICATION.md]
started: 2026-05-14T15:55:00.000Z
updated: 2026-05-14T15:55:00.000Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. iPhone физический smoke-test (Wave 1 M7 + M10 in production NE stack)
expected: scenePhase re-entry после M7 не вызывает двойного подключения. M10 idempotency guard работает в реальном NE context — cascade-delete subscription не дёргает loadFromStore() дважды.
result: [pending — defer until next physical iPhone session либо смешать с Phase 7+ smoke]

### 2. macOS UAT replay (Phase 6c/6d scenarios A/F-direct/F-reverse/Settings-disable/G на MacBook macOS 15+)
expected: Wave 2 L9 banner TTL, L10 observer-before-attempt, L1 clearDNSCache timeout работают в боевом macOS NE стеке. R10 post-expand validate выполняется на каждом startTunnel.
result: [deferred per 06E-CONTEXT.md D-03 → Phase 11/12 pre-TestFlight obligatory]

## Summary

total: 2
passed: 0
issues: 0
pending: 1 (iPhone smoke — discretionary follow-up)
skipped: 0
blocked: 0
deferred: 1 (macOS UAT — authorized defer per D-03)

## Gaps

(none — all 26 carved Phase 6d findings accounted for per 06E-Final-SUMMARY.md)
