---
status: partial
phase: 01-foundation
source: [.planning/ROADMAP.md Phase 1 Success Criteria, .planning/phases/01-foundation/01-W3.1-tun-inbound-cleanup-SUMMARY.md]
started: 2026-05-11T21:50:00Z
updated: 2026-05-11T22:13:00Z
mvp_mode_note: "Phase 1 имеет Mode: mvp но goal не в User Story формате (pre-mvp-pattern фаза). UAT генерирован из ROADMAP Phase 1 Success Criteria напрямую."
pause_note: "PAUSED 2026-05-11 22:13 — пользователь приостановил для context cleanup. Резюм: /gsd-verify-work 1 → picks up Test 7."
---

## Current Test

number: 7
name: DIST-01/DIST-02 Archive smoke
expected: |
  Resume command: `bash BBTB/scripts/archive-ios.sh 2>&1 | tail -30`
  Two script bugs already fixed (b253ce1 + b11196b); should succeed now.
awaiting: user response after resume (next session)
status: paused

## Tests

### 1. SwiftPM skeleton compiles (Success Criterion #5)
expected: SPM modules compile cleanly; validate-r1-r6.sh ends with "ALL STATIC INVARIANTS + UNIT TESTS PASS"
result: pass
auto_verified: true
evidence: "bash BBTB/scripts/validate-r1-r6.sh 2026-05-11 21:48 — exit 0, all PASS lines"

### 2. VLESS+Reality Import + Connect + IP swap (Success Criterion #1)
expected: |
  На iPhone: скопировать VLESS+Reality URI в clipboard → Open BBTB → tap "Import from clipboard"
  → tap "Connect" → tunnel status=connected
  → Safari → https://api.ipify.org → показывает IP сервера (отличается от реального IP).
  Уже verified сегодня (2026-05-11) round 7 + round 8 control test с Vision-enabled и non-Vision URI.
result: pass
reported: "Работают всё отлично"

### 3. Kill switch blocks traffic on tunnel drop (Success Criterion #2)
expected: |
  Туннель подключен. Симулировать разрыв туннеля: airplane mode toggle ИЛИ
  forget Wi-Fi network в iOS Settings.
  Safari → любой HTTPS-сайт → ошибка «No Internet Connection» / connection failed.
  Трафик НЕ должен идти мимо туннеля. Возврат к Wi-Fi → tunnel reconnects → трафик возобновляется.
result: pass
reported: "Kill switch активен"

### 4. R1 SocksProbe — no responding SOCKS ports (Success Criterion #3a)
expected: |
  Build & install SocksProbe-iOS из BBTB/Tools/SocksProbe/ на iPhone.
  Tunnel BBTB активен. Запустить SocksProbe → scan 127.0.0.1 well-known proxy ports.
  Результат: 0 SOCKS5 / HTTP CONNECT responses которые принадлежат BBTB.
result: pass
reported: |
  SocksProbe в первом запуске показал: Open: 1 (port 1080), R1 verdict: FAIL.
  Диагностика: SocksProbe re-scan с **выключенным BBTB tunnel** → порт 1080 всё равно открыт.
  Это доказывает что 1080 принадлежит ДРУГОМУ процессу на iPhone (AdGuard / iCloud Private Relay /
  cached service / etc.), не нашему PacketTunnelProvider.
  R1 invariant для BBTB ✓ — наш extension открывает 0 localhost-портов.
  Также pre-existing fix(tools/SocksProbe) commit `4431fd6` — Sendable conformance для Swift 6.
auto_verified: false
follow_up: "Phase 11 UX polish — SocksProbe verdict UI должен различать 'BBTB process' от 'другие процессы на устройстве' через PID attribution / process listing где возможно."

### 5. R6 IFF_POINTOPOINT (Success Criterion #3b) — N/A on iOS 26
expected: |
  На iOS 26: utun-интерфейсы ВСЕГДА имеют IFF_POINTOPOINT флаг независимо от destinationAddresses=nil.
  Это известное ограничение iOS 26 (commit 74605f8 — R6 assertion downgraded to warning).
  Verify: BBTB логи не должны падать с "R6 assertion failed" в production.
  Альтернатива на macOS (если есть в проекте): ifconfig | grep -A 2 utun → no POINTOPOINT.
result: skipped
reason: "N/A on iOS 26 — R6 заведомо не контролируется client-side; downgrade to warning документирован в commit 74605f8 + wiki/security-gaps.md"

### 6. No debug logs in Release mode (Success Criterion #4)
expected: |
  Xcode: Product → Scheme → Edit Scheme → Run → Configuration = Release.
  Run BBTB на iPhone.
  iOS Console.app (или Mac → Console.app + iPhone в sidebar) фильтр subsystem=app.bbtb.
  Видны только notice/error level entries. НЕТ debug-level entries.
  os_log({privacy: .public, ...}) в release-mode не печатает debug-уровень.
result: pass
reported: "Тест 6 удачный"

### 7. DIST-01/DIST-02 — Archive smoke (TestFlight readiness)
expected: |
  bash BBTB/scripts/archive-ios.sh завершается без error,
  build/iOS-Distribution/ содержит .ipa и manifest.
result: [pending]
note: |
  PRE-EXISTING bugs в archive-ios.sh fixed во время UAT session:
  - commit b253ce1: WORKSPACE path "BBTB.xcworkspace" → "BBTB/BBTB.xcworkspace"
  - commit b11196b: SCHEME "BBTB-iOS" → "BBTB" (correct iOS app scheme per xcodebuild -list)
  archive-macos.sh: WORKSPACE path тоже fixed в b253ce1, SCHEME уже был корректный.

  PAUSED 2026-05-11 22:13 — пользователь приостановил UAT для context cleanup.
  При resume: `bash BBTB/scripts/archive-ios.sh 2>&1 | tail -30` — последние 30 строк покажут
  итог (✓ iOS archive ready или ошибку), без переполнения context'а xcodebuild verbose output'ом.

## Summary

total: 7
passed: 5
issues: 0
pending: 1
skipped: 1
blocked: 0
status: paused-for-context-cleanup

## Gaps

[none yet]
