---
phase: 11-onboarding-ux-polish
plan: 06
subsystem: settings-help-faq
tags: [loc-03, loc-04, faq, settings, ui, swiftui, disclosure-group]
wave: 3
requires:
  - 11-01-PLAN.md  # Wave 1 L10n foundation — helpFaq*, helpTitle, helpEntryLabel, helpFooter keys
provides:
  - HelpView SwiftUI screen (public) с 5 FAQ DisclosureGroup
  - NavigationLink "Помощь" в SettingsView (последняя Section)
  - HelpViewTests с LOC-04 invariant check (FAQ4 must mention 22 apps)
affects:
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift
  - BBTB/Packages/AppFeatures/Package.swift (Localization explicit testTarget dep)
tech-stack:
  added: []
  patterns: [DisclosureGroup-FAQ-row, accessibility-id, xcstrings-direct-read-for-test, AppFeatures-test-explicit-Localization-dep]
key-files:
  created:
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/HelpView.swift  # 79 lines, 5 FAQ rows via private FAQRow struct
    - BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/HelpViewTests.swift  # 6 tests, LOC-04 invariant via xcstrings JSON read
  modified:
    - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift  # +11 lines: last Section с NavigationLink → HelpView
    - BBTB/Packages/AppFeatures/Package.swift  # +Localization testTarget dep
decisions:
  - D-09 (CONTEXT) — Help как NavigationLink в Settings (последняя Section перед Footer), отдельный HelpView screen
  - DisclosureGroup (не ScrollView+VStack) для каждой FAQ-пары — Apple-native, аксессабельный
  - List (не Form) внутри HelpView — Help — read-only контент, List более естественен и поддерживает navigationTitle
  - LOC-04 keyword check читает xcstrings JSON напрямую (а не L10n.helpFaq4Answer) — SPM не компилирует xcstrings в .strings → NSLocalizedString возвращает raw key как fallback (Plan 01 pattern)
  - Rule 1 (Bug fix) — оригинальный план проверял `hasPrefix("help.faq")` для защиты от unresolved key; под SPM это всегда true (раз L10n возвращает сырой ключ), тест бы упал в любом случае. Заменил на uniqueness check + xcstrings file-content check.
metrics:
  duration: "11min"
  completed: "2026-05-15T15:43:20Z"
  tasks_completed: 2
  tests_added: 6
  files_created: 2
  files_modified: 2
  lines_added: ~257
---

# Phase 11 Plan 06: Help/FAQ View Summary

Реализован экран Help/FAQ (LOC-03 / LOC-04) — `HelpView` с 5 раскрывающимися FAQ-секциями через `DisclosureGroup`, открывается из `SettingsView` через `NavigationLink` «Помощь» (последняя строка перед Footer). Все строки идут через L10n keys из Plan 01 (двуязычный ru/en); FAQ4 содержит обязательную секцию про 22 российских приложения, детектирующих VPN, что проверяется через прямое чтение xcstrings JSON.

## What Was Built

### 1. `HelpView.swift` (79 lines, NEW)

Public SwiftUI struct, `init() {}` без параметров. Структура:

```swift
public struct HelpView: View {
    public init() {}
    public var body: some View {
        List {
            Section {
                FAQRow(L10n.helpFaq1Question, L10n.helpFaq1Answer)
                    .accessibilityIdentifier("BBTB.Help.FAQ1")
                // ... FAQ2..FAQ5
            } footer: { Text(L10n.helpFooter) }
        }
        .navigationTitle(L10n.helpTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .accessibilityIdentifier("BBTB.HelpView")
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
    @State private var isExpanded: Bool = false
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .textSelection(.enabled)
                // ...
        } label: { Text(question) }
    }
}
```

**FAQ темы (через L10n из Plan 01):**

| # | L10n Question Key | L10n Answer Key | ru Тема (из xcstrings) |
|---|---|---|---|
| 1 | `help.faq1.question` | `help.faq1.answer` | Как добавить сервер / подписку |
| 2 | `help.faq2.question` | `help.faq2.answer` | VPN не подключается — что делать |
| 3 | `help.faq3.question` | `help.faq3.answer` | WebRTC leak — что это и как проверить |
| 4 | `help.faq4.question` | `help.faq4.answer` | **Почему 22 приложения из РФ видят, что я под VPN** (LOC-04) |
| 5 | `help.faq5.question` | `help.faq5.answer` | Ограничения детектирования MAX |

### 2. `SettingsView.swift` (+11 lines)

После Advanced Section добавлена новая Section с `NavigationLink(destination: HelpView())` и `Label(L10n.helpEntryLabel, systemImage: "questionmark.circle")`, `accessibilityIdentifier("BBTB.Settings.HelpRow")`.

**Final SettingsView Section order:**

1. Connection (auto-reconnect)
2. Security (kill switch)
3. Advanced (NavigationLink → AdvancedSettingsView)
4. **Help (Plan 06 — THIS, NavigationLink → HelpView)** ← последняя строка

> Если Plan 05 (DiagnosticsSection) применится позже, он встаёт МЕЖДУ Advanced и Help (без конфликта — оба зависят только от L10n keys из Plan 01).

### 3. `HelpViewTests.swift` (6 tests, NEW)

| Test | Что проверяет |
|---|---|
| `test_allFAQ_accessors_resolveNonEmpty` | 10 L10n accessor'ов (Q+A × 5) существуют и возвращают non-empty значения |
| `test_allFAQ_keys_areUnique` | 10 raw keys уникальны (защита от copy-paste reg) |
| `test_helpTitle_resolves` | `L10n.helpTitle` non-empty |
| `test_helpFooter_resolves` | `L10n.helpFooter` non-empty |
| `test_helpEntryLabel_resolves` | `L10n.helpEntryLabel` non-empty (для SettingsView строки «Помощь») |
| `test_LOC04_FAQ4_xcstrings_contains_detection_keywords` | **LOC-04 invariant** — читает `Localizable.xcstrings` JSON напрямую и проверяет, что ru-локализация `help.faq4.question` + `help.faq4.answer` содержит хотя бы один маркер из {«22», «приложен», «детект», «vpn»} |

### 4. `Package.swift` Localization dep

Добавлен `Localization` как explicit testTarget dependency к `SettingsFeatureTests` (паттерн установлен Plan 11-01 ServerListFeatureTests).

---

## L10n Key Inventory (used by HelpView)

Все ключи добавлены в Plan 11-01 Wave 1. Verified through Plan 11-01 SUMMARY и через прямое чтение `BBTB/Packages/Localization/Sources/Localization/L10n.swift:350-362` + `Localizable.xcstrings:1193-1252`.

| L10n accessor | xcstrings key | Локализации |
|---|---|---|
| `L10n.helpTitle` | `help.title` | ru + en |
| `L10n.helpEntryLabel` | `help.entry.label` | ru + en |
| `L10n.helpFooter` | `help.footer` | ru + en |
| `L10n.helpFaq1Question` / `Answer` | `help.faq1.question` / `.answer` | ru + en |
| `L10n.helpFaq2Question` / `Answer` | `help.faq2.question` / `.answer` | ru + en |
| `L10n.helpFaq3Question` / `Answer` | `help.faq3.question` / `.answer` | ru + en |
| `L10n.helpFaq4Question` / `Answer` | `help.faq4.question` / `.answer` | ru + en (LOC-04 обязательно про 22 приложения) |
| `L10n.helpFaq5Question` / `Answer` | `help.faq5.question` / `.answer` | ru + en |

**Итого: 13 L10n accessor'ов**, все из Plan 01.

---

## LOC-04 Keyword Set (used in test)

`test_LOC04_FAQ4_xcstrings_contains_detection_keywords` ищет в lowercased `q + " " + a` хотя бы один из:

- `"22"` — число российских приложений
- `"приложен"` — корень «приложение/приложения/приложений»
- `"детект"` — корень «детект/детектирует/детектирование» (защита если переформулируют без «22»)
- `"vpn"` — наличие самой аббревиатуры

**Текущее ru FAQ4 содержимое (из xcstrings):**

- Question: «Почему **22 приложения** из РФ видят, что я под VPN?» → matches `"22"`, `"приложен"`, `"vpn"`
- Answer: «Банковские, государственные приложения и «Госуслуги» активно **детектируют VPN**…» → matches `"приложен"`, `"детект"`, `"vpn"`

Защита: если переводчик случайно переформулирует и удалит все 4 маркера — тест упадёт.

---

## Acceptance Criteria Verification

### Task 6.1 (HelpView + tests)

| Criterion | Result |
|---|---|
| `swift build` зелёный | ✓ Build complete! (2.56s) |
| `swift test --filter HelpViewTests` PASS | ✓ 6/6 tests passed |
| Sentinels grep (≥4) | ✓ 14 (HelpView/FAQRow/DisclosureGroup/L10n.helpFaq*) |
| Файл ≥60 строк | ✓ 79 lines |
| FAQRow count == 5 | ✓ 5 |
| No hardcoded ru `"[А-Я]"` strings | ✓ 0 matches |
| No hardcoded en `"[A-Z][a-z]"` Text/Label literals | ✓ 0 matches |

### Task 6.2 (SettingsView wiring)

| Criterion | Result |
|---|---|
| `swift build` зелёный | ✓ Build complete! (2.49s) |
| `grep -c "NavigationLink(destination: HelpView"` == 1 | ✓ 1 |
| `grep -c "BBTB.Settings.HelpRow"` == 1 | ✓ 1 |
| `grep -c "Form {"` == 1 (regression) | ✓ 1 |
| Full AppFeatures `swift test` зелёный | ✓ 190/190 tests passed, 0 failures |
| iOS xcodebuild `BBTB` scheme green | ✓ BUILD SUCCEEDED (generic iOS Simulator) |
| macOS xcodebuild `BBTB-macOS` scheme green | ✓ BUILD SUCCEEDED (с `CODE_SIGN_IDENTITY=""` — see Deviations) |

---

## Deviations from Plan

### Rule 1 — Bug fix в логике тестов

**1. [Rule 1 - Bug] План testirov LOC-04 через `lowercased` на runtime L10n значениях**

- **Найдено во время:** Task 6.1 (test design phase, до запуска).
- **Issue:** План использовал `XCTAssertFalse(q.hasPrefix("help.faq"))` для защиты от unresolved L10n key и `combined = q.lowercased() + " " + a.lowercased()` для LOC-04 keyword check. Однако под SPM (`swift test`) `Localizable.xcstrings` НЕ компилируется в `.strings` (Plan 11-01 уже задокументировал это в `TransportPickerLabelsTests`). Поэтому `L10n.helpFaq4Question` под SPM = `"help.faq4.question"` — raw key. Это значит:
  - `hasPrefix("help.faq")` всегда `true` → `XCTAssertFalse` ВСЕГДА падает.
  - keyword set {«22», «детект», «приложен»} в raw key `"help.faq4.question"` НЕ найдётся → assertion упадёт.
- **Fix:** Заменил тесты на pattern Plan 11-01 (`TransportPickerLabelsTests`):
  - non-empty + uniqueness check (compile-time guard + защита от copy-paste).
  - LOC-04 content invariant читает xcstrings JSON напрямую через `#filePath`-навигацию (`URL(fileURLWithPath: #filePath).deletingLastPathComponent()×4 → Packages/Localization/.../Localizable.xcstrings`) и парсит ru-значение для `help.faq4.question` + `.answer`, после чего ищет ключевые слова. SoT = xcstrings file.
- **Files modified:** `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/HelpViewTests.swift`
- **Commit:** `b1b1d5b`

### Rule 3 — Auto-fix blocking issue (worktree libbox)

**2. [Rule 3 - Blocking] `libbox.xcframework` отсутствует в worktree**

- **Найдено во время:** baseline `swift build` (до Task 6.1).
- **Issue:** `BBTB/Vendored/libbox.xcframework` не закоммичен в git (только `.gitkeep` и `README.md` под version control). В worktree папка пустая → `swift build` упал с `local binary target 'Libbox' at '...libbox.xcframework' does not contain a binary artifact`.
- **Fix:** Создал symlink `BBTB/Vendored/libbox.xcframework → /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework` (main repo). Symlink не коммитится (gitignore impl-detail — vendored binary local-only).
- **Files modified:** filesystem symlink — НЕ в git.
- **Note:** Если future planner будет переиспользовать worktree pattern — стоит добавить шаг setup в orchestrator (либо включить libbox в LFS, либо документ instr в README).

### Out-of-scope (deferred / NOT auto-fixed)

**3. macOS xcodebuild signing config** — `xcodebuild ... -scheme BBTB-macOS` без явного `CODE_SIGN_IDENTITY` падает с «entitlements that require signing with a development certificate». Это pre-existing config issue worktree-окружения (signing certs не presented), не regression Plan 06. Build SUCCEEDS с `CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO`. Per scope boundary rule — НЕ фикшу.

**4. Swift 6 Sendable warnings в `BBTB_iOSApp.swift`** — pre-existing warnings (UserDefaults non-Sendable, Task.detached + sending). Не вызвано Plan 06 changes. Out-of-scope.

---

## Threat Surface Scan

Plan declared threat register `T-11-06-01..04` (все `accept`-disposition):

| Threat ID | Component | Disposition | Result |
|---|---|---|---|
| T-11-06-01 | FAQ4 раскрывает known detection apps | accept | ✓ Контент уже public в wiki/vpn-detection-by-apps.md. FAQ просто surfaces инфу. |
| T-11-06-02 | L10n strings подменены через jailbreak | accept | ✓ Apple-managed resource integrity; jailbreak — out-of-scope Phase 1 R6. |
| T-11-06-03 | DoS через huge FAQ answer | accept | ✓ Phase 11 answers ≤600 chars (xcstrings verified). |
| T-11-06-04 | Deep-link spoofing на HelpView | accept | ✓ Phase 11 не регистрирует new deep-link handler. |

**No new threat surface introduced** beyond static L10n strings (compile-time content). No network endpoints, no auth paths, no file access patterns, no schema changes.

---

## Wave 5 Manual UAT Instructions

После завершения Wave 4 (LOC-02 + IMP-03) — Wave 5 UAT:

1. **iOS device:**
   - Запустить BBTB на iPhone (iOS 18+).
   - Открыть «Настройки» (Settings tab).
   - Scroll до последней строки — должна быть **«Помощь»** с иконкой `questionmark.circle`.
   - Тап на «Помощь» → push на `HelpView` с навигационным title «Помощь».
   - Видны 5 строк FAQ:
     1. «Как добавить сервер»
     2. «Не подключается — что делать»
     3. «Что такое WebRTC leak»
     4. «Почему 22 приложения из РФ видят, что я под VPN»
     5. «Ограничения детектирования MAX»
   - Тап на каждую — `DisclosureGroup` раскрывается с ответом. Повторный тап — сворачивается.
   - Long-press на тексте ответа → можно скопировать (`.textSelection(.enabled)`).
2. **Переключение языка:** Settings → General → Language → English → BBTB → переоткрыть «Помощь». Title должен поменяться на «Help», все 5 вопросов/ответов — английский текст.
3. **macOS:** аналогично через Settings sheet → последняя строка → клик → HelpView в navigation stack.
4. **VoiceOver:** Включить VoiceOver, навигация → озвучка вопроса → expand swipe → озвучка ответа. Accessibility identifiers `BBTB.Settings.HelpRow` + `BBTB.Help.FAQ{1..5}` для XCUITest.

---

## Build / Test Status

| Step | Result |
|---|---|
| `swift build` (AppFeatures) | ✓ Build complete! |
| `swift test --filter HelpViewTests` | ✓ 6/6 passed |
| `swift test` (full AppFeatures) | ✓ 190/190 passed, 0 failures, 0 regressions |
| iOS `xcodebuild` `-scheme BBTB` | ✓ BUILD SUCCEEDED |
| macOS `xcodebuild` `-scheme BBTB-macOS` | ✓ BUILD SUCCEEDED (с `CODE_SIGN_IDENTITY=""`) |

---

## Auth Gates

None — Plan 06 is pure-code SwiftUI + tests. No external credentials, no network, no Apple Developer Portal actions.

---

## Self-Check: PASSED

- ✓ `BBTB/Packages/AppFeatures/Sources/SettingsFeature/HelpView.swift` — exists (79 lines).
- ✓ `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/HelpViewTests.swift` — exists (~177 lines).
- ✓ `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` — modified (NavigationLink + accessibility id present).
- ✓ `BBTB/Packages/AppFeatures/Package.swift` — modified (`Localization` testTarget dep).
- ✓ commit `b1b1d5b` exists in git log (`feat(11-06): add HelpView FAQ screen + tests`).
- ✓ commit `7b0656a` exists in git log (`feat(11-06): wire HelpView в SettingsView`).
- ✓ All 6 HelpViewTests pass; full AppFeatures suite 190/190 pass.
- ✓ iOS xcodebuild SUCCEEDED.
- ✓ macOS xcodebuild SUCCEEDED (with signing disabled — pre-existing env issue).

---

*Phase: 11-onboarding-ux-polish*
*Plan: 06 (Wave 3 — Help/FAQ view)*
*Executed: 2026-05-15*
*Duration: ~11 min*
