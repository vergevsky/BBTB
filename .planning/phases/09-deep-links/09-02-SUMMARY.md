---
phase: 09-deep-links
plan: 02
subsystem: deep-links
tags:
  - deep-links
  - url-parsing
  - l10n
  - import-handler
  - phase-9-wave-2
status: complete
completed: 2026-05-15
requirements:
  - DEEP-01
  - DEEP-02
  - DEEP-05
requirements_stub_only:
  - DEEP-03  # RemoteTokenFetchHandler stub (per D-03 — NOT registered with router in v0.9)
dependency_graph:
  requires:
    - DeepLinks Wave 1 (DeepLinkRouter actor + DeepLinkHandler protocol + DeepLinkError enum)
    - ConfigParser (ConfigImporting protocol — DI target)
    - Localization (Phase 1 baseline xcstrings + L10n.swift)
    - VPNCore (ImportSource.deepLink case from Wave 1)
  provides:
    - ImportHandler concrete (bbtb://import + Universal Link path convergence)
    - RemoteTokenFetchHandler stub (v1+ readiness)
    - 5 deep-link L10n keys (ru+en)
    - DeepLinkError.errorDescription using L10n (no more inline RU strings)
  affects:
    - Wave 3 (App-wiring) — instantiates ImportHandler via DI'ed ConfigImporter, registers с DeepLinkRouter в App.init
    - Wave 4 (AASA + UAT) — exercises full pipeline end-to-end on device
tech_stack:
  added: []
  patterns:
    - DI via constructor (ImportHandler holds ConfigImporting protocol reference)
    - URLComponents single-decode (Pitfall #5 — no double-decode)
    - Path convergence (both deep-link дорожки → один handler.handle)
    - FakeImporter capture-then-assert (XCTest stub-protocol idiom)
    - Phase 6e Theme A L10n split: launch-critical `static let` vs lazy `static var`
key_files:
  created:
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/RemoteTokenFetchHandler.swift
    - BBTB/Packages/DeepLinks/Tests/DeepLinksTests/ImportHandlerTests.swift
    - BBTB/Packages/DeepLinks/Tests/DeepLinksTests/URLParsingTests.swift
  modified:
    - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings (+5 entries ru+en)
    - BBTB/Packages/Localization/Sources/Localization/L10n.swift (+5 accessors)
    - BBTB/Packages/DeepLinks/Package.swift (+Localization dep on target + package)
    - BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift (errorDescription → L10n)
decisions:
  - DEEP-01/02 path convergence implemented в одном ImportHandler (per RESEARCH.md Pattern 5)
  - Pitfall #5 (double-decoded URL) handled через post-decode URL(string:) re-validation, NOT через double-decode
  - .notImplemented → L10n.deepLinkErrorUnhandled fallback (no separate user-facing key — v0.9 stub never reached from registered handlers)
  - alertDeepLinkErrorTitle as `static let` (launch-critical) per Phase 6e Theme A
metrics:
  duration: ~5 minutes  # automation-driven, no architectural exploration
  task_count: 3
  files_created: 4
  files_modified: 4
  tests_added: 14   # 9 ImportHandler + 5 URL parsing
  tests_passing: 17 # 3 router (Wave 1 preserved) + 9 + 5
---

# Phase 09 Plan 02: ImportHandler + L10n + URL parsing — Summary

**One-liner:** Concrete `ImportHandler` accept'ит обе deep-link дорожки (`bbtb://import?url=…` + `https://import.bbtb.app/import?…`), forwards в `ConfigImporting.importFromRawInput(_, source: .deepLink)`; `RemoteTokenFetchHandler` остаётся как public stub для v1+ DEEP-03; 5 L10n ключей (ru+en) переехали в xcstrings и `DeepLinkError.errorDescription` больше не содержит inline RU строк.

## Tasks executed

| # | Name | Commit | Status |
|---|------|--------|--------|
| 2.1 | 5 L10n keys (xcstrings + L10n.swift) + DeepLinkError → L10n swap | `cf6160b` | ✓ done |
| 2.2 | ImportHandler + RemoteTokenFetchHandler stub + 9 ImportHandlerTests | `26b99c3` | ✓ done |
| 2.3 | URLParsingTests (5 edge cases — Pitfall #5) | `6a79388` | ✓ done |

## Files

### Created (4)

| File | Lines | Purpose |
|------|-------|---------|
| `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift` | 79 | Concrete handler с DI'ed `ConfigImporting`; accept ОБОИХ путей; single-decode + URL(string:) re-validation; importer errors wrapped в `.importFailed` |
| `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/RemoteTokenFetchHandler.swift` | 43 | v1+ stub (D-03); canHandle всегда false; handle throws .notImplemented |
| `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/ImportHandlerTests.swift` | 189 | 9 tests: 4 canHandle scenarios + 5 handle scenarios + FakeImporter с full ConfigImporting conformance |
| `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/URLParsingTests.swift` | 139 | 5 tests: standard / double-encoded / `+` preservation / Cyrillic UTF-8 / empty query |

### Modified (4)

- `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` — +5 entries (ru+en) added в конец перед `}`:
  - `alert.deep_link_error.title`
  - `deep_link.error.unhandled`
  - `deep_link.error.missing_parameter` (format `%@`)
  - `deep_link.error.invalid_parameter` (format `%1$@`, `%2$@`)
  - `deep_link.error.import_failed` (format `%@`)
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` — +5 accessors добавлены в самом конце `enum L10n` (новая MARK секция «Phase 9 / DEEP-01..05 — deep-link error alert»). `alertDeepLinkErrorTitle` — `static let` (launch-critical per Phase 6e Theme A); остальные 4 — `static var` getter / `static func` для форматных подстановок.
- `BBTB/Packages/DeepLinks/Package.swift` — Localization SwiftPM package added как `.package(path: "../Localization")` + target dependency `"Localization"`.
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift` — `import Localization` + body `errorDescription` swap'нут с inline RU strings на L10n accessor calls (5/5 cases использует L10n; `.notImplemented` fallback'ает на `L10n.deepLinkErrorUnhandled` так как stub никогда не reach'ит router в v0.9).

## DeepLinkError → L10n swap diff fragment

```diff
- public var errorDescription: String? {
-     switch self {
-     case .unhandled(let url):
-         return "Не удалось обработать ссылку: \(url.absoluteString)"
-     case .missingQueryParameter(let name):
-         return "В ссылке отсутствует параметр «\(name)»"
-     case .invalidParameterValue(let name, let reason):
-         return "Параметр «\(name)» некорректен: \(reason)"
-     case .importFailed(let underlying):
-         return "Импорт не удался: \(underlying)"
-     case .notImplemented:
-         return "Эта функция станет доступна в следующей версии."
-     }
- }
+ public var errorDescription: String? {
+     switch self {
+     case .unhandled:                                  return L10n.deepLinkErrorUnhandled
+     case .missingQueryParameter(let name):            return L10n.deepLinkErrorMissingParameter(name)
+     case .invalidParameterValue(let name, let reason): return L10n.deepLinkErrorInvalidParameter(name: name, reason: reason)
+     case .importFailed(let underlying):                return L10n.deepLinkErrorImportFailed(underlying)
+     case .notImplemented:                              return L10n.deepLinkErrorUnhandled
+     }
+ }
```

**UX-driven semantic change:** `.unhandled` теперь НЕ показывает `url.absoluteString` в alert body — generic L10n string «Ссылка не поддерживается. Скопируйте подписку и импортируйте через меню «+».» per UI-SPEC Copywriting Contract. URL пользователю не нужен (он его и так в Telegram видит), но advice — нужен.

## Tests

| Suite | Tests | Description |
|------|-------|-------------|
| `DeepLinkRouterTests` (Wave 1 preserved) | 3 | dispatch / unhandled / registration order — Wave 1 changes transparent |
| `ImportHandlerTests` (Wave 2 new) | 9 | canHandle (4) + handle (5) — covers VALIDATION.md rows 09-01-03..09-01-07 + 09-02-01..09-02-02 |
| `URLParsingTests` (Wave 2 new) | 5 | Pitfall #5 edge cases: standard / double-encoded / plus / multibyte / empty query |
| **Total** | **17** | **`swift test --package-path Packages/DeepLinks` → exit 0** |

```
Executed 17 tests, with 0 failures (0 unexpected) in 0.004 (0.006) seconds
```

### ImportHandlerTests scenarios

| # | Test | Verifies |
|---|------|----------|
| 1 | `test_canHandle_bbtbImport_returnsTrue` | bbtb://import → true (DEEP-01 custom scheme); case-insensitive scheme/host |
| 2 | `test_canHandle_unknownScheme_returnsFalse` | bbtb://connect, bbtb://disconnect, vless://... → false |
| 3 | `test_canHandle_universalLink_returnsTrue` | https://import.bbtb.app/import + /import/anything → true (DEEP-02) |
| 4 | `test_canHandle_otherPath_returnsFalse` | /landing, other.bbtb.app, http (not https) → false |
| 5 | `test_handle_callsImporter_withDecodedURL_andDeepLinkSource` | percent-encoded URL → forwarded decoded; source == .deepLink |
| 6 | `test_handle_missingURL_throws` | bbtb://import (no `url=`) → .missingQueryParameter(name: "url") |
| 7 | `test_handle_emptyURL_throws` | bbtb://import?url= → .missingQueryParameter |
| 8 | `test_handle_invalidURL_throws` | url=https:// space.com (decoded contains space) → .invalidParameterValue(name: "url") |
| 9 | `test_handle_importerThrows_wrapsAsImportFailed` | NSError thrown → DeepLinkError.importFailed(underlying: "test-error") |

### URLParsingTests scenarios

| # | Test | Verifies |
|---|------|----------|
| 1 | `test_standardPercentEncoded_decodesToOriginalURL` | RFC 3986 percent → URLComponents single-decode roundtrip |
| 2 | `test_doubleEncodedURL_singleDecodeOnly` | `https%253A%252F%252Fexample.com` → after single decode intermediate `https%3A%2F%2Fexample.com` rejected (URL(string:) returns nil) — handler never reaches importer |
| 3 | `test_plusSignInQueryValue_preservedAsPlus` | `%2B` (`+`) preserved as literal `+`, not converted to space (RFC 3986, not x-www-form-urlencoded) |
| 4 | `test_multibytePercentEncoded_decodesUTF8` | Cyrillic `тест` percent-encoded → decoded back to UTF-8 |
| 5 | `test_emptyQueryString_throwsMissingParam` | `bbtb://import?` (no query items) → .missingQueryParameter |

## Plan-level verification gates (all PASS)

| # | Gate | Result |
|---|------|--------|
| 1 | `swift test --package-path Packages/DeepLinks` | EXIT 0 — 17/17 tests passed |
| 2 | `swift build --package-path Packages/Localization` | EXIT 0 (Build complete!) |
| 3 | `swift build --package-path Packages/AppFeatures` | EXIT 0 (Build complete!) |
| 4 | `grep -c "L10n.deepLinkError" DeepLinkError.swift` | 10 (≥ 4 required) |
| 5 | `grep -c "\.deepLink" ImportHandler.swift` | 2 (≥ 1 required) |
| 6 | done criteria 2.1 (5 xcstrings keys + 5 L10n accessors + import Localization + L10n.deepLinkError ≥ 4) | all PASS |
| 7 | done criteria 2.2 (ImportHandler struct + RemoteTokenFetchHandler struct + .notImplemented + source: .deepLink) | all PASS |
| 8 | done criteria 2.3 (5 test method names present in URLParsingTests) | PASS |

## Threat model coverage (Phase 9 W2)

Все T-09-01..T-09-08 покрыты per plan:

| Threat ID | Disposition | Where mitigated в Wave 2 |
|-----------|-------------|--------------------------|
| T-09-01 Spoofing — canHandle | mitigate | Exact case-insensitive match scheme `bbtb`/`https` + host `import` или `import.bbtb.app` + path prefix `/import`. Universal Link path enforced by Apple CDN AASA (Wave 4). |
| T-09-02 Tampering — URL value | mitigate | URLComponents single-decode + post-decode URL(string:) re-validation rejects malformed. Empty rejection → .missingQueryParameter. Importer errors rethrown via .importFailed с уже-sanitized error.localizedDescription. |
| T-09-03 Repudiation — logger | accept | DeepLinksLogger.importer.notice URL string privacy: .public (Foundation Logger pretty-print mask). Wave 4 UAT verifies нет subscription tokens в Console. |
| T-09-04 Info Disclosure — L10n format args | mitigate | `%@` args pre-sanitized: `name` literal ("url"), `reason` literal predicate string ("не URL"/"не похоже на URL"), `underlying` уже-localized importer description. No URL bodies pass as L10n format args. |
| T-09-05 DoS — URLComponents | accept | Apple-hardened Foundation framework. No unbounded recursion. |
| T-09-06 EoP — RemoteTokenFetchHandler stub | mitigate | canHandle всегда false → handle никогда не invoked from router. Even if called directly, throws .notImplemented immediately. |
| T-09-07 Tampering — ImportHandler → importer | mitigate | Phase 2+ importer pipeline уже hardened (SSRF + size cap + redirect cap + HTTPS-only). Wave 2 deep link layer добавляет НИ единого trust assumption — просто routes pre-validated URL. |
| T-09-08 Info Disclosure — test fixtures | mitigate | URLParsingTests + ImportHandlerTests используют statically-built fixture URLs. FakeImporter/CaptureImporter — in-memory, no SwiftData/Keychain side-effects. |

**Block-on:** none.

## Deviations from Plan

**Single deviation** — `test_handle_invalidURL_throws` construction:

- **Plan suggestion:** `URL(string: "bbtb://import?url=not%20a%20valid url")!` для проверки invalidParameterValue.
- **Found during:** Task 2.2 (RED→GREEN cycle — 8/9 PASS первый раз).
- **Issue:** Изначальная fixture в плане сама непарсится в `URL(string:)` (literal пробел в URL string), вторая попытка `%00%01%02` decode'ится в string которую `URL(string:)` accept'ит (NUL/control bytes valid в URL value).
- **Fix:** Используем `URLComponents` для конструирования fixture URL (scheme + host + queryItems), которая дает decoded value `https:// space.com` (literal space inside) — этот string `URL(string:)` returns nil. Test corrrectly verifies handler's `.invalidParameterValue` throw path.
- **Classification:** [Rule 1 — Bug] Test fixture corrected. Не deviation от plan goals, deviation от plan's example test code.
- **Commit:** `26b99c3` (Task 2.2 commit body неявно содержит fix).

**Auto-fix decisions:** None other. Plan executed exactly as written, modulo above fixture correction.

## Codex Consultation Gap (carry-forward from Wave 1)

Wave 1 SUMMARY noted Codex consultation для `DeepLinkHandler` Sendable signature unavailable. Wave 2 продолжает в том же режиме — реализация `ImportHandler` follows codebase canonical pattern:

- DI of `ConfigImporting` через init (`MainScreenViewModel.ConfigImporter` reference Phase 1+).
- URLComponents single-decode (Foundation pattern; RFC 3986 compliant).
- Error wrapping `.importFailed(underlying:)` mirrors `ImporterError` shape (ConfigImporter.swift:27-49).
- Test fakes use `@unchecked Sendable` (Phase 6c established pattern for in-test stubs).

Wave 3 / 4 могут consult Codex по `.onOpenURL` cold-start race patterns (D-09) если возникнут вопросы.

## Self-Check

Files claimed in Summary all exist:

- `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift` — FOUND
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/RemoteTokenFetchHandler.swift` — FOUND
- `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/ImportHandlerTests.swift` — FOUND
- `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/URLParsingTests.swift` — FOUND
- `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` — FOUND (with 5 new keys)
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` — FOUND (with 5 new accessors)
- `BBTB/Packages/DeepLinks/Package.swift` — FOUND (with Localization dep)
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift` — FOUND (L10n-backed errorDescription)

Commits claimed all reachable:

- `cf6160b` — FOUND (`feat(09-02): add 5 deep-link L10n keys + swap DeepLinkError to L10n`)
- `26b99c3` — FOUND (`feat(09-02): implement ImportHandler + RemoteTokenFetchHandler stub`)
- `6a79388` — FOUND (`test(09-02): add URLParsingTests covering Pitfall #5 edge cases`)

## Self-Check: PASSED

---

**Next:** Wave 3 (09-03-PLAN.md) — App wiring (BBTB_iOSApp + BBTB_macOSApp `.onOpenURL` / `.onContinueUserActivity` + MainScreenViewModel `handleDeepLink` + cold-start pendingDeepLink buffer + Tuist Project.swift + Info.plist + entitlements + Apple Developer Portal Associated Domains).
