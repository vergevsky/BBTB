---
status: complete
phase: 01-foundation
source: [.planning/ROADMAP.md Phase 1 Success Criteria, .planning/phases/01-foundation/01-W3.1-tun-inbound-cleanup-SUMMARY.md]
started: 2026-05-11T21:50:00Z
updated: 2026-05-11T22:25:00Z
mvp_mode_note: "Phase 1 имеет Mode: mvp но goal не в User Story формате (pre-mvp-pattern фаза). UAT генерирован из ROADMAP Phase 1 Success Criteria напрямую."
---

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
result: partial
reported: |
  Run 2026-05-11 22:12.

  **DIST-01 archive** ✓ — `** ARCHIVE SUCCEEDED **`.
  `build/BBTB-iOS.xcarchive/Products/Applications/BBTB.app` создан,
  подпись Apple Development cert (HT4962XJZJ), embedded BBTB_Tunnel_iOS.appex.

  **DIST-02 export** ✗ blocked-by-credentials — `xcodebuild -exportArchive`
  с `method=app-store` упал:
    - No profiles for 'app.bbtb.client.ios.tunnel' were found
    - No signing certificate "iOS Distribution" found
    - No profiles for 'app.bbtb.client.ios' were found
  Причина: на dev-машине только Apple Development cert + Development provisioning
  profile. App Store distribution cert + App Store profile не созданы.

  PRE-EXISTING bugs в archive-ios.sh fixed во время UAT session:
    - commit b253ce1: WORKSPACE path "BBTB.xcworkspace" → "BBTB/BBTB.xcworkspace"
    - commit b11196b: SCHEME "BBTB-iOS" → "BBTB" (correct iOS app scheme per xcodebuild -list)
  archive-macos.sh: WORKSPACE path тоже fixed в b253ce1, SCHEME уже был корректный.
follow_up: |
  Distribution credentials — Phase 12 prerequisite (Pre-release + Public TestFlight).
  Перед Phase 12: создать в Apple Developer Portal Apple Distribution cert +
  App Store provisioning profile для app.bbtb.client.ios и app.bbtb.client.ios.tunnel,
  скачать на машину сборки, затем re-run archive-ios.sh.

## Summary

total: 7
passed: 5
partial: 1
issues: 0
pending: 0
skipped: 1
blocked: 0
status: complete

## Gaps

- **G1 (Phase 12 prerequisite)**: Distribution credentials (Apple Distribution cert + App Store
  provisioning profiles for app.bbtb.client.ios + app.bbtb.client.ios.tunnel) не созданы.
  Блокирует DIST-02 export в TestFlight-готовый `.ipa`. Archive (DIST-01) собирается. Не блокирует
  Phase 1 goal (минимально жизнеспособная сборка с VLESS+Vision+Reality + kill switch +
  SwiftPM архитектура) — все остальные success criteria выполнены.
