# Onboarding + UX polish (Phase 11, 2026)

**Summary**: Финальный UX-слой v0.11 перед TestFlight — onboarding для новых пользователей, file picker импорт, тихий MAX-detection, log export через Share Sheet, FAQ/Help экран, ConnectionButton spinner, полная локализация ru/en, ServerListSheet TODO-маркеры по Figma. 5 waves, 8 plans, 11 req IDs (9 ✅ Validated + 1 ⏸ figma-pending + 1 ⚙️ Infrastructure-validated).

**Sources**: `.planning/phases/11-onboarding-ux-polish/{11-CONTEXT,11-RESEARCH,11-PATTERNS,11-FIGMA-SPEC,11-DISCUSSION-LOG,11-Final-SUMMARY}.md`, `.planning/phases/11-onboarding-ux-polish/11-{01..08}-SUMMARY.md`, `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`, `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` (session 2026-05-15/16).

**Last updated**: 2026-05-16

---

## Phase 11 архитектурные решения (D-01..D-12)

### Area A — Onboarding (UX-01)

- **D-01** — Sticky-forever флаг: `@AppStorage("app.bbtb.hasShownOnboarding")`. Устанавливается в `true` после первого показа — навсегда. Даже если пользователь удалит все серверы, onboarding больше не показывается. Reset возможен только при полной переустановке app. Acceptable per Pitfall 4 (`@AppStorage` сбрасывается при удалении app).
- **D-02** — Single-screen, 2 CTA: один экран без `NavigationView`. Контент: заголовок + подзаголовок + 2 кнопки («Вставить из буфера» primary, «Сканировать QR» secondary). Никаких слайдов «что такое VPN».
- **D-03** — Auto-dismiss: observer `.onChange(of: viewModel.state)` в OnboardingView; при переходе state на non-empty → `onDismiss()` → `hasShownOnboarding=true`.
- **D-04** — File picker НЕ в Onboarding: только через меню «+» на главном экране. Новому пользователю не показывается на старте, чтобы не перегружать первый запуск.

### Area B — Анимации кнопки (UX-08)

- **D-05** — Спиннер при connecting: `ProgressView().progressViewStyle(.circular).tint(.white).controlSize(.large)` overlay в существующем ZStack { Circle + Image }; identifier `BBTB.ConnectionButton` preserved. Phase 12 заменит на custom 4-frame rotating ring (Figma Spinner component, M6 в CODE-CONNECT.md).
- **D-06** — Остальные states: сохранён current `symbolEffect(.bounce)`; цвета состояний (серый/оранжевый/accent/красный) не меняются без Figma-подтверждения.

### Area C — Figma compliance (UX-09)

- **D-07** — Two-stream architecture: Stream A (код — LOC, DETECT, TELEM, IMP-03) + Stream B (UI polish — ждёт Figma). Реализованы параллельно. Wave 4 human-verify checkpoint.
- **D-08** — ServerListSheet heights: static let константы (`serverRowH=80`, `autoCellH=116`, `subHeaderH=44`, `manHeaderH=36`, `emptyCardH=220`, `bottomBuf=40`) в Phase 11 помечены TODO с reference на Figma; pixel-perfect heights — Phase 12 (M8 в CODE-CONNECT.md).

### Area D — FAQ и Log export

- **D-09** — FAQ как NavigationLink: «Помощь» отдельная строка в `SettingsView` (последняя перед Footer) → NavigationLink → `HelpView` с 5 `DisclosureGroup` (как добавить сервер / не подключается / WebRTC leak / 22 приложения из РФ / ограничения детектирования).
- **D-10** — Diagnostics section в Settings: отдельный `Section("Диагностика")` после Advanced row. Содержит: кнопку «Отправить лог разработчику» + footer «Последние 24ч. IP-адреса маскируются.» + версия приложения/ОС.
- **D-11** — Share Sheet без backend: `ShareLink(item: URL)` cross-platform (iOS 16+ / macOS 13+ — наш минимум 18/15 покрывает). Пользователь сам выбирает куда (почта, Telegram, AirDrop). Backend для log export не нужен в Phase 11; при масштабировании 100+ TestFlight — отдельная задача Phase 13+.
- **D-12** — IP-маскировка: regex `(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}` → `$1xxx`. Применяется в `DiagnosticsExporter.maskIPv4` перед записью в tmp файл; ко всем строкам лога, содержащим IP-паттерн.

## Design system tokens — session 2026-05-15/16 decisions

В рамках Task 7.4 follow-up (Figma file BBTB v3 передан пользователем 2026-05-15) приняты решения по дизайн-системе:

- **DS-01** — Two-tier token model: `Primitives` (11 raw color/spacing/typography values) + `DS` (40 semantic tokens с binding на primitives). Permits Dark+Light modes без duplication.
- **DS-02** — Dark + Light modes реализованы как native Figma modes на Education plan. Variable binding активирован на ключевые fills (canvas/surface/textPrimary).
- **DS-03** — Component sets: 3 sets (Button / Button_BG / Spinner) + 2 standalone (ServerRow default + ServerRow Selected + AutoCell).
- **DS-04** — Semantic layer naming: 50+ generic frame names (Frame 23 etc.) → semantic (Hero / CTAs / FAQ List). 6 orphan tokens удалены.
- **DS-05** — Code Connect Education plan blocker: `code_connect:write` scope недоступен на Education tier; для publish требуется Organization+ ($45/user/mo). Workaround — создали 4 `.figma.swift` файла как documentation contracts wrapped в `#if canImport(CodeConnect)` guard. Компилируются inert без SDK; активируются автоматически при upgrade plan + добавлении SDK.
- **DS-06** — Figma как источник истины для визуала; Swift догоняет в Phase 12 (user decision 2026-05-15: «приоритет: pixel-perfect дизайн в Фигме → код»).

## Key file references

### Code created (Phase 11 implementation)

- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.swift` — UX-01
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MAXDetector.swift` — DETECT-01/02 (silent service, protocol abstractions URLSchemeQueryable + WorkspaceQueryable for mocking)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift` — TELEM-02 (actor; IP-mask; tmp file)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsSection.swift` — TELEM-02 UI (ShareLink)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/HelpView.swift` — LOC-03/04 (5 DisclosureGroup)

### Code modified (Phase 11)

- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` (~30 new keys)
- `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` (~30 entries ru+en)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` (Onboarding fullScreenCover + .fileImporter integration)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (`importFromFile`)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` (UX-08 spinner overlay)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (LOC-02 cleanup — 2 Russian strings → L10n)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift` (LOC-02 cleanup — 5 protocol labels → L10n)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` (D-08 height constants TODO comments)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` (Diagnostics + Help sections)
- `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift` (`ImportSource.file` case)
- `BBTB/Packages/AppFeatures/Package.swift` (SettingsFeature → PacketTunnelKit dep for log read)
- `BBTB/App/iOSApp/Info.plist` (`LSApplicationQueriesSchemes`)
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` + `BBTB/App/macOSApp/BBTB_macOSApp.swift` (MAXDetector wire at startup)

### Design system files (session 2026-05-15/16)

- `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` — полный Figma↔Swift contract + §4 «10 Mismatches M1-M10»
- `BBTB/Packages/DesignSystem/Tokens/figma-tokens.json` — machine-readable token export (51 variables)
- `figma.config.json` — Code Connect CLI config (repo root)
- 4 `.figma.swift` files — Code Connect Swift mappings (ConnectionButton + ServerRow default/selected + AutoCell + OnboardingView)
- `.planning/phases/11-onboarding-ux-polish/figma-inspect/TOKEN-MAP.md` — variable ID map
- `.planning/phases/11-onboarding-ux-polish/figma-inspect/*.png` — 21 visual references (before/after)

## MAX-detection candidate lists (snapshot Phase 11)

iOS URL schemes (Info.plist `LSApplicationQueriesSchemes` + `MAXDetector.iOSSchemeCandidates`):

- `max`, `max-app`, `ru-max`, `vkmax`

macOS bundle IDs (`MAXDetector.macOSBundleCandidates`):

- `ru.vk.max`, `com.vkontakte.max`, `chat.max.app`, `ru.max.messenger`

**NB:** все 4 кандидата для каждой платформы — `[ASSUMED]` per RESEARCH A1/A2. Реальный bundle ID/scheme MAX публично не задокументирован. Обновление списка — после device UAT с установленным MAX (Phase 12+ follow-up — один-line code change).

## Patterns established

1. **OnboardingView reuses EmptyStateCard layout** — та же `VStack + Image + Text + Title + Subtitle + 2 Buttons` структура, но full-screen вместо card. Reuse via `ConfigImporter.pasteFromClipboard()` + `startQRScan()` as action handlers.
2. **ConnectionButton spinner pattern** — `if isConnecting { ProgressView() }` overlay в существующем ZStack; identifier preserved (Phase 7c accessibility invariant). Применяется при добавлении state-driven overlays к existing buttons.
3. **DiagnosticsExporter pattern** — stateless enum с public async API; file IO внутри Task; IP-mask через NSRegularExpression перед write. Применяется при экспорте log/файлов в Phase 13 (TELEM-04+ batch analytics) или любых других экспортах sanitized data.
4. **MAXDetector mockable surface** — protocol abstraction (`URLSchemeQueryable` / `WorkspaceQueryable`) для DI в unit-тестах. Применяется при любом cross-app probe (детектирование других messenger'ов, проверка наличия конкурентов).
5. **L10n key naming convention** — `<feature>.<element>` (dot.notation в xcstrings), camelCase Swift accessor. Установлен Plan 01 как стандарт.
6. **fullScreenCover + @AppStorage gate** — pattern для one-time onboarding flows. `@AppStorage("hasShownX")` → `if !hasShownX` → fullScreenCover; auto-dismiss через state observer.

## Pitfalls learned

1. `canOpenURL` без `LSApplicationQueriesSchemes` молча возвращает false на iOS (RESEARCH Pitfall 1). Whitelist обязателен.
2. `@AppStorage` сбрасывается при удалении app — acceptable per D-01 (sticky-forever).
3. `fileImporter` URL — security-scoped, требует `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` (RESEARCH Pitfall 5). Без этого read fails на iOS.
4. macOS Share UX через `ShareLink` имеет различные available activity-types vs iOS (RESEARCH Pitfall 3). Поведение одинаковое, но options отличаются.
5. sing-box.log может быть пуст или отсутствовать (extension ещё не запускался) — `DiagnosticsExporter.prepareLog()` возвращает `nil` → empty-state alert вместо краша (RESEARCH Pitfall 8).
6. Figma Education plan имеет жёсткие ограничения на Code Connect (`code_connect:write` scope недоступен; Organization+ tier required для publish). `.figma.swift` файлы должны компилироваться без SDK через `#if canImport(CodeConnect)` guard.

## 10 Mismatches enumerated for Phase 12

Финальный список pixel-perfect deltas (из `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §4):

- **M1** — `DS.ConnectionButtonSize.compactDiameter` 140 → 280; `regularDiameter` 160 → 320
- **M2** — `compactIcon` 56 → 112; `regularIcon` 64 → 128
- **M3** — ConnectionButton fill colors → `DS.Color.controlIdle / .accent / .error` (new tokens)
- **M4** — Font family: `.system(.body, design: .rounded)` → SF Pro Expanded
- **M5** — `DS.accent`: `.accentColor` → `Color("DS/Color/accent")` (hex #14664B)
- **M6** — Spinner placeholder `ProgressView()` → custom 4-frame rotating ring matching Figma Spinner component
- **M7** — Onboarding PrimaryButton/SecondaryButton — custom `ButtonStyle` matching Figma pill design (full-width 49pt height)
- **M8** — ServerRow padding/spacing verified против Figma 16/12pt values; height constants update
- **M9** — Sheet corner radius 32pt at top corners (using `RoundedCorner` shape, новый primitive)
- **M10** — Section corner radius 24pt (новый `DS.Radius.section` token)

## Outstanding / carry-out → Phase 12 / Phase 13

- **Phase 12 (Swift pixel-perfect rebuild from Figma, v0.12-design):**
  - Все 10 mismatches M1-M10 (см. above)
  - UX-09 figma-pending → full re-Validated с side-by-side Figma↔simulator screenshot diff ≤ 2px
- **Phase 13 (Pre-release + Public TestFlight, v0.13 + v1.0):**
  - **DETECT-03 admin handoff** — server-side rules.json sign + publish MAX-domains из `wiki/max-domains-blocklist.md`. Client side готов (Phase 8 RulesEngine pipeline).
  - **MAX bundle ID device UAT** — установить MAX на test device, проверить log output, обновить candidate list (один-line code change).
  - **Apple Distribution credentials** — DIST-02 carry-over from Phase 1; cert + App Store profiles для всех 4 bundle IDs.
  - **SPKI subscription pins replacement** — `PinStore.swift` placeholder pins (64 `a`s + 64 `b`s) ДОЛЖНЫ быть заменены через `generate-spki-pin.swift` до TestFlight upload.
  - **macOS UAT replay** — 5 scenarios A / F-direct / F-reverse / Settings-disable / G (Phase 6e D-03 defer).
  - **Numerical Instruments baseline** — PerfSignposter готов (DEC-06d-06); capture для Phase 13 pre-TestFlight obligatory snap.

## Related pages

- [[vpn-detection-by-apps]] — 22 приложения из РФ, контекст FAQ4 и DETECT-03 (которые домены блокируются)
- [[max-domains-blocklist]] — admin handoff documentation для DETECT-03 server-side activation
- [[max-messenger]] — описание мессенджера MAX, детект и блокировка
- [[security-gaps]] — R10/R11 baseline для `DiagnosticsExporter` sanitization (IP-mask D-12)
- [[architecture]] — обновлена с упоминанием OnboardingFeature / DiagnosticsExporter / MAXDetector
- [[rules-engine]] — Phase 8 D-01..D-13; DETECT-03 server-side pipeline зависит от RulesEngine
- [[deep-links]] — Phase 9 для контекста как deep-links не пересекаются с Onboarding flow
- [[advanced-settings]] — Phase 10 AdvancedSettingsView; Diagnostics секция добавлена ниже Advanced
- [[performance-baseline]] — Phase 6d/6e DEC-06d-01..06 patterns preserved (cold-start defer + bounded probe для file IO + non-blocking initialization)
