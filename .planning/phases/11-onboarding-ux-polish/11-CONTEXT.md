# Phase 11: Onboarding + UX polish — Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

**Что фаза делает (v0.11):** Финальный UX-слой — onboarding для новых пользователей, анимации кнопки подключения по Figma-макетам, полная локализация ru/en без hardcoded строк, FAQ/Help экран, MAX-detection (тихий, только в лог), log export через Share Sheet, file picker (IMP-03, через меню «+»).

**Платформы:** iOS + macOS.

### В скоупе v0.11

1. **UX-01 — Onboarding:** 1 экран, только первый запуск. Заголовок + подзаголовок + 2 CTA (буфер / QR). После успешного импорта — сразу главный экран.
2. **UX-08 — Анимации кнопки:** Спиннер при `connecting` (точный вид — по Figma). Остальные состояния — по Figma-макетам.
3. **UX-09 — Visual review:** Pixel-perfect реализация по `11-FIGMA-SPEC.md`. Макеты рисуются параллельно.
4. **LOC-02 — Полная локализация:** Никаких hardcoded строк. Известные нарушители: `ConfigImporter.swift` (2 Russian strings), `TransportPicker.swift` (TCP/WebSocket/gRPC/HTTP/2/HTTPUpgrade labels).
5. **LOC-03/LOC-04 — FAQ:** Кнопка «Помощь» в Settings → NavigationLink → отдельный `HelpView`. 5 тем. Двуязычный (ru/en через L10n).
6. **TELEM-02 — Log export:** Секция «Диагностика» в Settings. Кнопка → собирает 24ч логов + версия приложения + версия ОС + анонимный device-id, маскирует последний октет IP → `UIActivityViewController` (Share Sheet). Без backend.
7. **DETECT-01/02/03 — MAX-detection:** iOS: `UIApplication.canOpenURL("max://")` + `LSApplicationQueriesSchemes`. macOS: `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`. Только в локальный лог, никакого UI. MAX-домены → `block_completely` через rules.json.
8. **IMP-03 — File picker:** `.json`/`.yaml` через `fileImporter` SwiftUI modifier. Точка входа — меню «+» на главном экране (НЕ в Onboarding).

### НЕ в скоупе v0.11

- Onboarding как многошаговые слайды — только один экран
- IMP-03 в Onboarding — только через меню «+»
- Backend для log export — Share Sheet достаточно
- NET-12 (liveness probe) — deferred Phase 12+
- Config editor / Network diagnostics — deferred

</domain>

<decisions>
## Implementation Decisions

### Area A — Onboarding (UX-01)

- **D-01: Триггер — только первый запуск.** `UserDefaults` флаг `hasShownOnboarding`. Устанавливается в `true` после первого показа — навсегда. Даже если пользователь удалит все серверы, onboarding больше не показывается.
- **D-02: Структура экрана.** 1 экран без NavigationView. Контент: заголовок + подзаголовок + 2 CTA-кнопки («Вставить из буфера» primary, «Сканировать QR» secondary). Никаких слайдов, никаких объяснений что такое VPN.
- **D-03: Переход после импорта.** После успешного импорта с Onboarding → dismiss sheet / navigate to main screen сразу. Без промежуточных экранов.
- **D-04: IMP-03 не в Onboarding.** File picker доступен только через меню «+» на главном экране — не показывается новому пользователю на старте.

### Area B — Анимации кнопки (UX-08)

- **D-05: Спиннер при connecting.** Тип и точные параметры спиннера определяются по Figma-макетам (рисуются параллельно с разработкой). Planner читает `11-FIGMA-SPEC.md §2` и ждёт макетов или реализует placeholder с возможностью замены.
- **D-06: Остальные состояния — по Figma.** Текущий `symbolEffect(.bounce)` остаётся как базовый fallback до получения макетов. Цвета состояний (серый/оранжевый/accent/красный) не меняются без Figma-подтверждения.

### Area C — Figma (UX-09)

- **D-07: Figma-макеты рисуются параллельно.** Дизайн ведётся по `11-FIGMA-SPEC.md`. Реализация pixel-perfect следует после передачи макетов. Phase 11 выполняется в двух независимых потоках: код (LOC, DETECT, TELEM, IMP-03) + UI polish (ждёт Figma).
- **D-08: Высоты ServerListSheet — обязательно пересмотреть.** Текущие статические константы (`serverRowH=80`, `autoCellH=116`, `subHeaderH=44`, `manHeaderH=36`, `emptyCardH=220`) в `ServerListSheet.swift` должны быть обновлены по Figma-значениям. Это блокирует корректное открытие шита.

### Area D — FAQ и Log export

- **D-09: FAQ — NavigationLink в Settings.** Кнопка «Помощь» как отдельная строка в `SettingsView` (последняя перед Footer). Tap → `NavigationLink` → `HelpView`. Контент: 5 тем (как добавить сервер / не подключается / WebRTC leak / 22 приложения из РФ / ограничения детектирования).
- **D-10: Log export — секция «Диагностика» в Settings.** Отдельный `Section("Диагностика")` в `SettingsView`. Содержит: кнопку «Отправить лог разработчику» + footer «Последние 24ч. IP-адреса маскируются.» + версия приложения/ОС под ней.
- **D-11: Share Sheet, без backend.** Лог → `UIActivityViewController` (iOS) / `NSSharingServicePicker` (macOS). Пользователь сам выбирает куда (почта, Telegram, AirDrop и т.д.). Backend не нужен в Phase 11. При масштабировании (100+ пользователей) — отдельная задача Phase 12+.
- **D-12: Маскировка IP в логах.** Regex-замена последнего октета IPv4 на `xxx` перед экспортом. Применяется ко всем строкам лога, содержащим IP-паттерн `\d{1,3}\.\d{1,3}\.\d{1,3}\.(\d{1,3})`.

### Claude's Discretion

- Точный текст заголовка и подзаголовка Onboarding — planner выбирает лаконичный вариант на русском, локализует на английский.
- `HelpView` структура — `List` с `DisclosureGroup` per FAQ-пункт или `ScrollView` со статическим контентом. Рекомендую `DisclosureGroup` для компактности.
- Анонимный device-id для лог-экспорта — `UIDevice.current.identifierForVendor?.uuidString` (iOS) / `IOPlatformExpertDevice` (macOS) или просто UUID генерированный при первом запуске и сохранённый в UserDefaults.
- MAX-detection: когда именно вызывать (при каждом запуске? при подключении?) — рекомендую при старте приложения, один раз.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements

- `.planning/REQUIREMENTS.md` §UX-01 — Onboarding spec
- `.planning/REQUIREMENTS.md` §UX-08 — Анимации кнопки
- `.planning/REQUIREMENTS.md` §UX-09 — Figma visual review
- `.planning/REQUIREMENTS.md` §LOC-02/03/04 — Локализация + FAQ
- `.planning/REQUIREMENTS.md` §DETECT-01/02/03 — MAX-detection
- `.planning/REQUIREMENTS.md` §TELEM-02 — Log export
- `.planning/REQUIREMENTS.md` §IMP-03 — File picker
- `.planning/ROADMAP.md` Phase 11 entry — Success Criteria + Notes (включая предупреждение про высоты ServerListSheet)

### Промт v2 (источник истины)

- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — авторитетный список всех требований. Planner сверяется при любых сомнениях.

### Figma Design Spec

- `.planning/phases/11-onboarding-ux-polish/11-FIGMA-SPEC.md` — перечень экранов и элементов для отрисовки. **Planner читает перед реализацией UI-волн** — там указаны текущие константы высот, которые нужно обновить.

### Существующий код — точки изменений

- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` — главный экран. Точка интеграции Onboarding (флаг → sheet или fullScreenCover).
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` — кнопка подключения. `symbolEffect(.bounce)` → заменить/дополнить спиннером по Figma.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TopBar.swift` — Top Bar. Меню «+» → добавить file picker (IMP-03).
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — 2 hardcoded Russian strings (строки 42, 984). Перенести в L10n.
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` — статические константы высот (строки 45–51). Обновить по Figma.
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift` — hardcoded protocol labels (TCP/WebSocket/gRPC). Перенести в L10n.
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` — добавить: секция «Диагностика» (TELEM-02) + строка «Помощь» (LOC-03).
- `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` — 189 ключей. Добавить новые ключи для Onboarding, Help, Diagnostics секций.

### Паттерны из предыдущих фаз

- `.planning/phases/09-deep-links/09-CONTEXT.md` — паттерн `fileImporter` SwiftUI modifier уже использовался в Phase 9 для URL handling. Аналогичный подход для IMP-03.
- `.planning/phases/10-advanced-settings-security-polish/10-CONTEXT.md` — паттерн `Section` + `Toggle` в SettingsView для новых секций.

### Wiki

- `wiki/vpn-detection-by-apps.md` — список 22 приложений из РФ, которые детектируют VPN. Используется для FAQ §LOC-04 и для DETECT-03 (блокировка MAX-доменов).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`QRScannerView.swift`** — уже есть, реиспользуется в Onboarding as-is.
- **`ConfigImporter`** — `pasteFromClipboard()` и `startQRScan()` — реиспользуются как action handlers для Onboarding CTA-кнопок.
- **`SettingsView.swift`** — существующий `Form` с секциями. Новые секции «Диагностика» и строка «Помощь» добавляются хвостом.
- **`L10n` enum** (из Localization пакета) — паттерн уже установлен. Новые строки добавляются через `Localizable.xcstrings`.
- **`AppGroupContainer`** — для чтения логов PacketTunnel extension. Лог находится в App Group shared container.

### Established Patterns

- **`UserDefaults` флаги** (например `autoReconnectEnabled`) — паттерн для `hasShownOnboarding`.
- **`fullScreenCover` / `.sheet`** — стандартный паттерн для модальных экранов в приложении.
- **`fileImporter` modifier** — SwiftUI встроенный document picker. Использовать вместо UIDocumentPickerViewController.
- **`symbolEffect(.bounce)`** — текущий паттерн для анимации иконки кнопки. Расширяется, не заменяется целиком.

### Integration Points

- `MainScreenView` → `fullScreenCover(isPresented:)` для Onboarding
- `TopBar` → `Menu` (уже есть кнопка «+») → добавить `.fileImporter` action
- `SettingsView` → `Section("Диагностика")` + `NavigationLink("Помощь")`
- `ConnectionButton` → `overlay` или `ZStack` для спиннера поверх/вместо power icon
- `AppGroupContainer.logsURL` → `FileManager` read → маскировка IP → `UIActivityViewController`

</code_context>

<specifics>
## Specific Ideas

- **Onboarding как `fullScreenCover`:** показывается поверх главного экрана при первом запуске. Dismiss происходит автоматически после успешного импорта — пользователь оказывается на уже заполненном главном экране.
- **Спиннер при connecting — два варианта для Figma:** (a) `ProgressView()` как overlay поверх кнопки, (b) rotating ring вокруг кнопки через `Circle().trim().rotationEffect`. Точный выбор — по Figma-макету.
- **Share Sheet на macOS:** `NSSharingServicePicker` требует `NSView` anchor. В SwiftUI — через `NSViewRepresentable` wrapper или `ShareLink` (iOS 16+ / macOS 13+). Рекомендую `ShareLink` — поддерживается обеими платформами начиная с нужных версий.
- **Маскировка IP:** применяется только при экспорте, не в runtime логах. Regex: `(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}` → `$1xxx`.
- **DETECT-03 MAX-домены:** добавляются в `rules.json` на сервере — не hardcode в приложении. Приложение получает их через RulesEngine (Phase 8). Список доменов — из `wiki/vpn-detection-by-apps.md`.

</specifics>

<deferred>
## Deferred Ideas

- **NET-12** (active liveness probe) — повторный carry-out, Phase 12+.
- **Config editor / Network diagnostics** — Phase 12+.
- **Backend для log export** — при масштабировании (100+ пользователей TestFlight), отдельная задача Phase 12+.
- **Onboarding доступность из Settings** («добавить ещё один сервер» кнопка) — не нужна по решению D-01. Если появится запрос от пользователей — отдельная фича.

</deferred>

---

*Phase: 11-onboarding-ux-polish*
*Context gathered: 2026-05-15*
