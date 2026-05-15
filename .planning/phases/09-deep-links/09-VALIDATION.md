---
phase: 9
slug: deep-links
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-15
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (project standard; verified `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/*.swift`) |
| **Config file** | None — XCTest in-package (Package.swift `.testTarget`) |
| **Quick run command** | `cd BBTB && swift test --package-path Packages/DeepLinks` |
| **Full suite command** | `cd BBTB && swift test` (все пакеты) + `xcodebuild test -scheme BBTB -destination 'platform=iOS Simulator,name=iPhone 15'` |
| **Estimated runtime** | ~10 seconds (DeepLinks unit), ~50 seconds (full suite) |

---

## Sampling Rate

- **After every task commit:** Run `cd BBTB && swift test --package-path Packages/DeepLinks`
- **After every plan wave:** Run `cd BBTB && swift test` (все пакеты) + switch-exhaustiveness grep gate
- **Before `/gsd-verify-work`:** Full suite must be green + iOS xcodebuild + manual UAT (W5)
- **Max feedback latency:** ~10 seconds (unit), ~50 seconds (full suite)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 09-W0-stubs | 01 | 0 | DEEP-01/05 | — | N/A | unit | `swift test --package-path Packages/DeepLinks` | ❌ Wave 0 | ⬜ pending |
| 09-01-01 | 01 | 1 | DEEP-05 | — | DeepLinkRouter регистрирует handler, итерирует canHandle | unit | `swift test --filter DeepLinkRouterTests.test_register_then_handle_routesToFirstMatchingHandler` | ❌ Wave 0 | ⬜ pending |
| 09-01-02 | 01 | 1 | DEEP-05 | — | Нет handler'а → throws DeepLinkError.unhandled | unit | `swift test --filter DeepLinkRouterTests.test_handle_noMatch_throwsUnhandled` | ❌ Wave 0 | ⬜ pending |
| 09-01-03 | 01 | 1 | DEEP-01 | T-09-04 | bbtb://import?url=encoded → ImportHandler.canHandle true | unit | `swift test --filter ImportHandlerTests.test_canHandle_bbtbImport_returnsTrue` | ❌ Wave 0 | ⬜ pending |
| 09-01-04 | 01 | 1 | DEEP-01 | T-09-04 | bbtb://other → ImportHandler.canHandle false | unit | `swift test --filter ImportHandlerTests.test_canHandle_unknownScheme_returnsFalse` | ❌ Wave 0 | ⬜ pending |
| 09-01-05 | 01 | 1 | DEEP-01 | T-09-02 T-09-04 | handle() → calls importer.importFromRawInput с decoded URL + source=.deepLink | unit | `swift test --filter ImportHandlerTests.test_handle_callsImporter_withDecodedURL_andDeepLinkSource` | ❌ Wave 0 | ⬜ pending |
| 09-01-06 | 01 | 1 | DEEP-01 | T-09-04 | Missing url param → throws DeepLinkError.missingQueryParameter | unit | `swift test --filter ImportHandlerTests.test_handle_missingURL_throws` | ❌ Wave 0 | ⬜ pending |
| 09-01-07 | 01 | 1 | DEEP-01 | T-09-04 | Empty url value → throws DeepLinkError.missingQueryParameter | unit | `swift test --filter ImportHandlerTests.test_handle_emptyURL_throws` | ❌ Wave 0 | ⬜ pending |
| 09-02-01 | 02 | 2 | DEEP-02 | — | https://import.bbtb.app/import?url=… → ImportHandler.canHandle true | unit | `swift test --filter ImportHandlerTests.test_canHandle_universalLink_returnsTrue` | ❌ Wave 0 | ⬜ pending |
| 09-02-02 | 02 | 2 | DEEP-02 | — | https://import.bbtb.app/other → canHandle false | unit | `swift test --filter ImportHandlerTests.test_canHandle_otherPath_returnsFalse` | ❌ Wave 0 | ⬜ pending |
| 09-03-01 | 03 | 3 | D-09 | T-09-03 | Cold-start: pendingURL НЕ выполняется до initialManagersApplied | manual | iPhone UAT + log inspection | manual-only | ⬜ pending |
| 09-03-02 | 03 | 3 | D-08 | — | Error alert: invalid URL → SwiftUI Alert с локализованным текстом | integration | MainScreenViewModel lastError snapshot | ❌ Wave 0 | ⬜ pending |
| 09-04-01 | 04 | 4 | DEEP-01 | T-09-01 | Manual UAT: bbtb://import?url=… из Telegram iOS → app opens + import | manual | iPhone iOS 18 device UAT (W5) | manual-only | ⬜ pending |
| 09-04-02 | 04 | 4 | DEEP-02 | T-09-05 | Manual UAT: AASA на import.bbtb.app отдаётся с Content-Type: application/json | manual | `curl -I https://import.bbtb.app/.well-known/apple-app-site-association` | manual-only | ⬜ pending |
| 09-04-03 | 04 | 4 | DEEP-02 | — | Manual UAT: тап Universal Link из Safari iOS 18 → app opens + import | manual | iPhone UAT (W5) | manual-only | ⬜ pending |
| 09-04-04 | 04 | 4 | DEEP-02 | Pitfall 1 | Manual UAT: macOS Universal Link → .onContinueUserActivity fires | manual | macOS UAT (W5) | manual-only | ⬜ pending |
| 09-05-01 | 05 | 1 | Pitfall 3 | — | ImportSource.deepLink switch exhaustiveness clean | gate | `! grep -rn 'switch.*ImportSource' BBTB/Packages/ | grep -v 'case .deepLink' | grep -v 'default:'` | gate-only, W1 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/DeepLinkRouterTests.swift` — register/handle iteration + unhandled throw
- [ ] `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/ImportHandlerTests.swift` — все canHandle + handle scenarios для DEEP-01 + DEEP-02
- [ ] `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/URLParsingTests.swift` — edge cases percent-decoding, double-encoded URLs (Pitfall 5)
- [ ] Test fixtures: stub `ConfigImporting` (capture-only, без real SwiftData/Keychain operations)
- [ ] Integration test для `MainScreenViewModel.handleDeepLink` — error flow в lastError

*Existing infrastructure (XCTest, Package.swift pattern) covers all phase requirements — только новые test files нужны.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| AASA файл на import.bbtb.app возвращает 200 + Content-Type: application/json | DEEP-02 | Требует реальный сервер; нельзя мокать Apple CDN | `curl -I https://import.bbtb.app/.well-known/apple-app-site-association` |
| Тап bbtb://import?url=… из Telegram → iOS app opens + import | DEEP-01 | LaunchServices — нельзя автоматизировать в simulator без UI test runner | iPhone iOS 18 device, Telegram, production build |
| Тап Universal Link https://import.bbtb.app/import?url=… из Safari → app opens | DEEP-02 | Requires real domain + Apple CDN validation; simulator supports but needs ≥24h AASA cache | iPhone iOS 18 device or `?mode=developer` simulator |
| macOS Universal Link → .onContinueUserActivity fires (не .onOpenURL) | DEEP-02 | Pitfall #1 — macOS-specific behavior | macOS 15 build, click link in Safari |
| Cold-start deep link — импорт начинается ПОСЛЕ initialStatusSnapshot | D-09 | Race condition timing; can't reliably reproduce в unit tests | iPhone device, terminate app, tap bbtb:// link, check Console.app для DeepLinksLogger ordering |
| Apple Developer Portal Associated Domains capability checked | DEEP-02 | Manual Portal step | developer.apple.com → Identifiers → app.bbtb.client.ios → Associated Domains ✓ |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s (unit), < 50s (full suite)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
