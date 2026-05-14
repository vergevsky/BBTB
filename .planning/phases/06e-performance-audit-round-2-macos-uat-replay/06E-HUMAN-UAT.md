---
status: complete
phase: 06e-performance-audit-round-2-macos-uat-replay
source: [06E-VERIFICATION.md]
started: 2026-05-14T15:55:00.000Z
updated: 2026-05-14T16:35:00.000Z
---

## Current Test

[testing complete]

## Tests

### 1. iPhone smoke — M7 (scenePhase coalesce) на физическом iOS 26+
expected: foreground re-entry (background → foreground) запускает один Task, hooks выполняются последовательно (runIsSupportedUpgrade → handleForeground → silentForegroundRefresh), нет двойного loadAllFromPreferences XPC, UI не зависает на 1-3 секунды.
result: pass
evidence: |
  debug-logs/logs.txt lines 26-27 — subscription merge при foreground re-entry показывает
  consistent server counts ("existing 6, new identities 6"), single coordinated hook chain.
  User confirmed plавный foreground re-entry, актуальный статус виден сразу.
tested_on: physical iPhone iOS 26+, build c6f21ba (post-Wave-2 merge)

### 2. iPhone smoke — M10 (cascade-delete subscription idempotency)
expected: удаление подписки с серверами вызывает loadFromStore() ровно один раз; список серверов обновляется одним cohesive update'ом без двойного flicker.
result: pass
evidence: |
  debug-logs/logs.txt lines 8, 15, 24, 26-27 — multiple subscription merge calls
  все idempotent ("existing N, new identities N" pattern). User confirmed списки
  обновились одним update'ом без двойного flicker.
tested_on: physical iPhone iOS 26+, build c6f21ba

### 3. macOS UAT replay (Phase 6c/6d scenarios A/F-direct/F-reverse/Settings-disable/G)
expected: Wave 2 L9 banner TTL, L10 observer-before-attempt, L1 clearDNSCache timeout работают в macOS NE стеке. R10 post-expand validate выполняется на каждом startTunnel.
result: deferred
reason: "Authorized defer per 06E-CONTEXT.md D-03 → Phase 11/12 pre-TestFlight obligatory. Не блокирует закрытие Phase 6e."

## Summary

total: 3
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0
deferred: 1

## Gaps

(none — all Phase 6e must-haves verified; 26 carved Phase 6d finding IDs accounted per 06E-Final-SUMMARY.md)

## Bonus Findings (from log inspection)

iPhone smoke session логи независимо подтвердили работу адъюнктных invariants:
- **DEC-06d-05 (Settings-disable):** `userIntent=false → OnDemand disabled → .disconnected skipped` (lines 29-31) — fire-and-forget XPC + ExternalVPNStopMarker semantics корректны.
- **M11 applyVPNStatus single authority:** один armed stableSession task (line 23), не двойной — D-09 invariant preserved в production NE стеке.
- **No новых regression warning'ов** — все error/warn сообщения в логах — benign Network.framework / cfprefsd artifacts (error 49 EAGAIN на teardown, error 53 ECONNRESET на probe setup, cfprefsd App Group "detaching" Apple-known warning).
