# Swift pixel-perfect rebuild (Phase 12 / v0.12-design)

**Summary**: Phase 12 (v0.12 design milestone, 2026-05-16) привёл Swift код в pixel-perfect соответствие с Figma BBTB v3 после Phase 11 cleanup. Никаких protocol/network/security изменений — только визуал. **2026-05-16 (late):** Figma file полностью прошёл variable binding pass через `use_figma` Plugin API (170 fill/stroke bindings) + designer finalized Light mode + добавил variable `DS/Color/alwaysWhite`. Figma теперь true source-of-truth с полностью функциональным Dark↔Light mode switching.

**Sources**: `.planning/phases/12-swift-pixel-perfect-rebuild-from-figma-v0-12-design/{12-CONTEXT.md,12-RESEARCH.md,12-UI-SPEC.md,12-PATTERNS.md,12-01-PLAN.md,12-02-PLAN.md,12-01-SUMMARY.md,12-02-SUMMARY.md}`, `BBTB/Packages/DesignSystem/Tokens/{CODE-CONNECT.md,figma-tokens.json}`.

**Last updated**: 2026-05-16

---

## Контекст

Phase 11 закрылся с UX-09 в статусе `figma-pending` — Figma file BBTB v3 был очищен и токенизирован (51 переменная, 5 компонентов, semantic naming), а 10 mismatches между Swift кодом и Figma зафиксированы в `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §4. Phase 12 закрывает этот разрыв.

Старый scope Phase 12 («TestFlight & Distribution») перенесён на **Phase 13**.

## Локированные решения (CONTEXT.md D-01..D-12)

| ID | Решение | Обоснование |
|---|---|---|
| D-01 | 2 плана: Foundation + Application | DS extension отделён от view rebuild — снижает blast radius |
| D-02 | Foundation первым | После — application slices тривиальны |
| D-03 | Quick wins (M1-M5) перед heavy lifts (M6-M10) внутри Plan 12-02 | Низкорисковые подмены сначала, потом тяжёлые перестройки |
| D-04 | **Tight scope** — только M1-M10 | Adjacent issues → backlog через `gsd-capture` |
| D-05 | **Wire-only Light mode** | Все 15 DS.Color получают Light value placeholder из figma-tokens.json, визуал остаётся dark-only до designer Light pass |
| D-06 | Light placeholder values из figma-tokens.json | Уже разумные дефолты заведены в Figma DS collection |
| D-07 | System auto-switch | Нет in-app theme toggle; iOS Settings рулит |
| D-08 | **Hybrid verification** — snapshots для компонентов + manual UAT для full screens | Pragmatic balance — automated regression + human eye на финальные экраны |
| D-09 | Snapshot library = pointfreeco/swift-snapshot-testing | Resolved by researcher (HIGH conf) |
| D-10 | ≤2px diff acceptance | Anti-aliasing на тексте/градиентах — known platform difference, exempt |
| D-11 | iOS-only Phase 12 | macOS pixel-perfect — backlog после v1.0 |
| D-12 | macOS Figma cleanup deferred | Делается вместе с macOS pixel-perfect фазой когда подойдёт очередь |

## Технические решения (RESEARCH §2, HIGH confidence)

### Custom Spinner (M6)
**Решение:** `Circle().trim(from: 0, to: 0.85).stroke(AngularGradient(...), lineWidth: 6).rotationEffect(.degrees(rotation))` с `.linear(duration: 1.2).repeatForever`. **НЕ iOS 18 `.symbolEffect(.rotate)`** — он работает только на SF Symbols, не на shapes с AngularGradient stroke. См. `BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift`.

**Reduce Motion fallback (W4 lock):** static ring + pulsating opacity 0.6↔1.0 cycle 1.0s через `@Environment(\.accessibilityReduceMotion)`. НЕТ alternative «discrete snap».

### SF Pro Expanded шрифт (M4)
**Решение:** SwiftUI `.fontWidth(.expanded)` modifier через `Font.system(size:weight:).width(.expanded)` (iOS 16+). **Бандлить .otf запрещено Apple Font SLA §2B** — это App Store rejection risk. Helper в `DS.Typography.expanded(_:weight:)`.

### DS.Color storage
**Решение:** Swift literal enum `DS.Color.*` с `Color(uiColor: UIColor(dynamicProvider:))` для авто Dark/Light switch. **НЕ Asset Catalog** — Xcode 16 nested SPM `Bundle.module` имеет preview crash bug (Swift Forums #41736), что хрупко для BBTB (AppFeatures depends on DesignSystem). См. `BBTB/Packages/DesignSystem/Sources/DesignSystem/DSColor.swift`.

### Snapshot library
**Решение:** `pointfreeco/swift-snapshot-testing` ≥1.18.3 (resolved 1.19.2). **Pin минимум 1.18.3** — 1.18.0 имеет main-thread deadlock. `perceptualPrecision: 0.97-0.99` маппится на D-10 ≤2px diff target.

### Sheet corner (M9)
**Решение:** `UnevenRoundedRectangle(cornerRadii: .init(topLeading: 32, topTrailing: 32, bottomLeading: 0, bottomTrailing: 0)).clipShape` — pure SwiftUI iOS 16+. **НЕ** UIBezierPath through UIKit.

### Custom ButtonStyles (M7)
**Решение:** `BBTBPrimaryButtonStyle` + `BBTBSecondaryButtonStyle` в DesignSystem package с `.sensoryFeedback` haptic. Pressed state scale 0.97/0.92/0.12s. См. `BBTB/Packages/DesignSystem/Sources/DesignSystem/ButtonStyles.swift`.

### ConnectionButton spinner overlay (W3 fix)
**Решение:** Spinner монтируется через `.overlay { if isConnecting { BBTBSpinner(diameter: diameter + 24, ...).accessibilityHidden(true) } }` **на самом Circle**, НЕ как sibling в ZStack. Это критично — parent VStack/HStack frame НЕ пересчитывается при connecting↔connected toggle (иначе layout jumps на 24pt).

## Что построено (15 commits на main)

### Plan 12-01 Foundation (DesignSystem package)
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift` — расширен: `DS.Color`, `DS.Typography.Size` (7 размеров) + `expanded()` helper + 9 пресетов, `DS.Radius.section/sheet`, `DS.Blur.pill`, новые `DS.ConnectionButtonSize.*` (280/320 + 112/128). Existing API сохранён.
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/DSColor.swift` (NEW) — 15 семантических токенов с UIColor/NSColor dynamic provider.
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/ButtonStyles.swift` (NEW) — BBTBPrimaryButtonStyle + BBTBSecondaryButtonStyle.
- `BBTB/Packages/DesignSystem/Package.swift` — `swift-snapshot-testing` ≥1.18.3 dep + DesignSystemTests + DesignSystemSnapshotTests target'ы со StrictConcurrency=complete.
- `BBTB/Packages/DesignSystem/Tests/DesignSystemTests/{DSColorTests,DSTokensTests}.swift` — 10 unit tests PASS.
- `BBTB/Packages/DesignSystem/Tests/DesignSystemSnapshotTests/ButtonStyleSnapshotTests.swift` — 3 baseline PNG (iOS 17 Simulator) PASS.

### Plan 12-02 Application (AppFeatures package)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` — fillColor `private`→`internal` + DS.Color tokens switch (M3); BBTBSpinner overlay W3 (M6); auto-pick из DS.ConnectionButtonSize (M1, M2).
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.swift` — hero text split (white + accent green) с `DS.Typography.expanded(.display=48, .semibold)`; PrimaryButton + SecondaryButton; haptic feedback (M7).
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` — UnevenRoundedRectangle 32pt top corners (M9).
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.swift` — pill design с DS.Radius.section (24pt) + accent/surfaceSunken fills + Reduce-Motion gate (M10).
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift` — text/icon DS.Color tokens + selected accent background + Reduce-Motion-gated animation (M8).
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift` (NEW) — BBTBSpinner view.
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/Snapshots/{ConnectionButtonSnapshotTests,OnboardingViewSnapshotTests}.swift` (NEW) — 5 + 1 snapshot тестов.
- `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/Snapshots/{ServerListSnapshotTests,ServerRowFixtures}.swift` (NEW) — 4 snapshot тестов + @MainActor fixture для Swift 6 strict concurrency.
- `BBTB/Packages/DesignSystem/Tests/DesignSystemSnapshotTests/SpinnerSnapshotTests.swift` (NEW) — 1 snapshot baseline PASS на iOS 17.

### Тесты
- **AppFeatures: 210/210 PASS** (было 207; +3 новых `test_fillColor_*` в ConnectionButtonTests).
- **DesignSystem: 10/10 unit + 4/4 snapshot PASS** (3 ButtonStyle + 1 Spinner на iOS 17 Simulator).
- **iOS xcodebuild: SUCCEEDED** на iPhone 17.

## Carve-outs (НЕ блокируют Phase 12 closure)

1. **AppFeatures snapshot baseline recording через xcodebuild test** — линкер ошибка `_res_9_ninit/_res_9_nsearch` (libbox.xcframework transitive deps требуют `-lresolv` в SwiftPM test target ИЛИ exposed Tuist test scheme). Source-уровень готов; baseline зафиксируется в follow-up commit. Workaround: добавить `.linkerSettings([.linkedLibrary("resolv")])` в `MainScreenFeatureTests`/`ServerListFeatureTests` test targets, либо expose test scheme через Tuist Project.swift.
2. **Tuist BBTB workspace test scheme** — `BBTB`/`BBTB-Workspace` схемы не сконфигурированы для test action. `swift test --package-path` работает на macOS host.

## Patterns зафиксированные в Phase 12

### `DS.Color` Swift literal pattern
```swift
public enum Color {
    public static let accent = SwiftUI.Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x14/255.0, green: 0x66/255.0, blue: 0x4B/255.0, alpha: 1.0)
            : UIColor(red: 0x14/255.0, green: 0x66/255.0, blue: 0x4B/255.0, alpha: 1.0)
    })
}
```

### Spinner overlay-not-sibling
```swift
Circle()
    .fill(fillColor)
    .frame(width: diameter, height: diameter)
    .overlay {
        if isConnecting {
            BBTBSpinner(diameter: diameter + 24, lineWidth: 6, speed: 1.2)
                .accessibilityHidden(true)
        }
    }
```

### Hero text split (Onboarding)
```swift
(Text("Интернет, каким он ").foregroundStyle(DS.Color.textPrimary)
 + Text("должен быть").foregroundStyle(DS.Color.accent))
    .font(DS.Typography.expanded(DS.Typography.Size.display, weight: .semibold))
    .multilineTextAlignment(.center)
```

### @MainActor on snapshot fixtures (Swift 6 strict concurrency)
```swift
@MainActor
enum ServerRowFixtures {
    static let sample = ServerConfig(...)  // ServerConfig не Sendable — нужен @MainActor
}
```

### N3 snapshot recording protocol
- Default `record: .missing` — first run FAIL + записывает PNG → commit → re-run PASS.
- Re-record: `SNAPSHOT_TESTING_RECORD=1 xcodebuild test ...` ИЛИ обернуть в `withSnapshotTesting(record: .all) { ... }` block.
- Никакого manual `isRecording = true` uncomment/commit/re-comment протокола.

## Figma binding (post-2026-05-16-late)

После Phase 12 closure user попросил аудит реального состояния Figma file (визуал «плохо перенёсся»). Аудит обнаружил: 51 variables были определены (`figma-tokens.json`), но почти не привязаны к canvas nodes — почти все fills были raw hex literals. **9 из 51 variables** были bound где-либо (mostly text styles + Color/canvas + Color/iconPrimary).

Через `mcp__plugin_figma_figma__use_figma` Plugin API было применено **170 fill/stroke bindings** в 5 шагов:

| Step | Что bound | Count |
|---|---|---|
| 1 | Components page — Button_BG ellipse fills × 3 + Button variant texts × 9 + ServerRow / ServerRow Selected (9 fills) + Spinner gradient stops × 4 | 25 |
| 2 | Onboarding — hero text split, tip, PrimaryButton, SecondaryButton (D-05 wire-only inversion pattern) | 7 |
| 3 | 4× Home screens — TopBar icons, ServerStatusLabel, Уведомление | 18 |
| 4 | Selected + Auto sheets — sheet bg, drag indicator, header, AutoCell, sections, 16 ServerRows × 4 fills, ServerRowSelected, progress bar | 102 |
| 5 | Fix — screen frame backgrounds × 5 (canvas) + 11 Button instance text overrides | 16 |
| 6 (post-audit) | Designer finalized Light mode + added `alwaysWhite` variable → 17 rebinds на accent/error backgrounds | 17 |
| **Total** | | **170** |

### Light mode values (designer-finalized 2026-05-16)

| Token | Dark | Light | Note |
|---|---|---|---|
| canvas | #000000 | #FFFFFF | |
| surface | #222222 | **#FFFFFF** | sheet visually = canvas в Light, разделение через drag indicator + section headers |
| surfaceSunken | #1A1A1A | **#F0F0F0** | section backgrounds Light |
| surfaceHeader | #333333 | **#E0E0E0** | section headers Light |
| controlIdle | #222222 | #E8E8EC | |
| accent | #14664B | #14664B | unchanged (brand green) |
| error | #661414 | #B3261E | brighter red в Light |
| textPrimary | #FFFFFF | #111113 | |
| **alwaysWhite (NEW)** | #FFFFFF | #FFFFFF | static white — text на accent/error fills; scope TEXT_FILL |
| iconPrimary | #FFFFFF | #111113 | |
| iconMuted | #CCCCCC | #A5A5AC | |

### Pattern: `alwaysWhite` для text на цветном background

Применяется на nodes где background — `Color/accent` или `Color/error` (которые не инвертируются в Light) — текст должен оставаться белым в обоих modes, иначе становится нечитаемым:

- ConnectionButton variant `.connected` тексты («подключен», «00:01:07», «нажми чтобы отключиться»)
- ConnectionButton variant `.error` тексты («ошибка», «нажми чтобы переподключиться»)
- PrimaryButton text «Добавить из буфера»
- Уведомление text «Ошибка подключения»
- ServerRowSelected name text
- AutoCell selected text «Автовыбор по скорости» (Auto sheet)
- Lightning Vector в AutoCell-Auto selected variant

## 2026-05-16 (late) — User-driven UI fix-loop

После закрытия M1-M10 и Figma binding pass — interactive design pass с user'ом
прошёл по 7 экранам BBTB v3 и закрыл все визуальные расхождения. 9 коммитов
на main (`d7f35da` → `98c52a3`).

### Архитектурные patterns зафиксированные

- **Phosphor Icons Bold** интегрированы через DesignSystem re-export
  (`@_exported import PhosphorSwift` в `PhosphorReexport.swift`) → все features
  получают `Ph.list.bold` / `Ph.plus.bold` / etc. через `import DesignSystem`.
  Package: `phosphor-icons/swift 2.1.0`. Xcode build корректно генерирует
  `PhosphorSwift_PhosphorSwift.bundle` (CLI `swift build` спотыкается о
  undeclared `Assets.xcassets` resource — known limitation, не блокер).
- **Inline TopBar pattern** (`BBTBTopBar` component в DesignSystem) заменяет
  native `.toolbar` чтобы избежать iOS 26 Liquid Glass auto-applied circle
  backdrop под toolbar items (`.buttonStyle(.plain)` ослабляет но не убирает
  полностью). Применён к 4 экранам: MainScreen (custom inline), Settings/
  Help/AdvancedSettings (через `BBTBTopBar(title:, onBack:)` convenience init).
  Padding [horizontal:28, top:32, bottom:16]. Все экраны делают
  `.toolbar(.hidden, for: .navigationBar)`.
- **SectionCard wrapper** (ServerListFeature) — RoundedRectangle 24pt fill
  surfaceSunken; ServerListSheet sections (Подписка/Конфигурации) обёрнуты в
  SectionCard + clipShape RoundedRectangle 24 для smooth corners при
  collapsible animations.
- **Floating banner overlay** — `ReconnectBanner` вынесен из inline VStack в
  `.overlay(alignment: .top)` с `.transition(.move(.top).combined(opacity))`
  + animation `.easeInOut(0.25)`. Banner НЕ shift'ит underlying content
  layout (старая inline implementation сдвигала ConnectionButton вниз при
  появлении). Horizontal padding 80pt = 28 (edge→icon) + 24 (icon width) +
  28 (icon→banner gap) — banner живёт между TopBar ≡ и + кнопками.

### Per-screen изменения

**Empty Home (Figma 3115:325)** — `EmptyStateCard` full rewrite:
hero «Нет конфигураций» 16pt Semibold + 10pt Light subtitle + 2 CTAs
через `PrimaryButtonStyle`/`SecondaryButtonStyle`. Lightning circle backdrop
+ checkmark + subtitle убраны. ConnectionButton + ServerStatusLabel
`visible:false` в Figma → не рендерятся в Swift.

**Home Disconnected/Connecting/Connected/Error (Figma 3043:341 +
3047:538/598/568)** — unified `ConnectionButton` per-state composition:
- `.idle/.empty` → «СТАРТ» 48pt Bold (controlIdle)
- `.connecting` → «подключение» 16pt + inset stroke ring (controlIdle 6pt
  `.strokeBorder` inside 280pt Circle) + BBTBSpinner gradient arc на том же
  radius (loading wheel pattern)
- `.connected` → ZStack: «подключен» 16pt @ y=-48.5 + inline TimelineView
  timer 32pt @ y=0 + «нажми чтобы отключиться» 10pt Light @ y=+42
  (accent bg, alwaysWhite text)
- `.error` → ZStack: «ошибка» 16pt @ y=0 + «нажми чтобы переподключиться»
  10pt Light @ y=+42 (error red bg)

External `ConnectionTimer` + `StatusPill` удалены из `MainScreenView.content`
(visual noise per user feedback — теперь живут внутри button). Файлы остаются
для MenuBarFeature.

**ServerListSheet (Figma 3064:350 + 3064:1579 unified)**:
- Header «Список серверов» 16pt Semibold + Phosphor ArrowClockwise refresh
  (iconSecondary). Top padding 32pt («дыхание» сверху per user feedback).
- AutoCell single-line «Автовыбор по скорости» 12pt Regular + Phosphor
  Lightning 20pt (alwaysWhite | iconSecondary). bg accent (auto active) /
  surfaceHeader (server selected).
- ServerRow Phosphor Globe + 12pt Regular name + LatencyBadge (9pt
  Expanded Regular «N мс», tier colors + iconMuted override на accent bg) +
  Phosphor CaretRight. Hairline overlay `.top` 0.5pt surfaceHeader (был
  `.bottom` → последняя строка оставляла полосу на закруглении section card).
- SubscriptionHeader collapsible: Button toggle → CaretDown rotates -90°
  CCW при `isCollapsed`. Manual section header («Конфигурации») — same
  pattern. ViewModel: `collapsedSectionIDs: Set<String>` + helpers.
- Quota progress bar пока не рендерится — `Subscription` модель содержит
  только `{id, url, name, lastFetched}`; все подписки = бессрочные. Условный
  render вернётся когда добавим `usedBytes/totalBytes/expiresAt` fields.
- Bottom dark strip fix — `.ignoresSafeArea(edges: .bottom)` после
  `.clipShape` чтобы surface bg заполнял home indicator область до края
  экрана (иначе underlying modal backdrop виден через safe area inset).
- `.toolbar(.hidden, for: .navigationBar)` — consistent с sub-screens.

**ServerDetailView** — inline back TopBar (Phosphor CaretLeft + server name
title) + `.toolbar(.hidden)` для устранения layout jump при push/pop из
ServerListSheet (раньше Form.navigationTitle вызывал native nav bar только
на detail screen → content shift при transition).

**Sub-screens (Settings, AdvancedSettings, Help)** — migrated на
`BBTBTopBar(title:, onBack: { dismiss() })` + `.toolbar(.hidden)`. Existing
inline TopBar'ы в MainScreenView / ServerListSheet / ServerDetailView пока
НЕ migrated (оба pattern совместимы, миграция отложена до user request).

### Floating banner (Figma 3047:568 «Ошибка подключения» pill)

`ReconnectBanner` restyle + behavior:
- bg accent green + alwaysWhite text + cornerRadius 16 + shadow (radius 6,
  opacity 0.25) для elevation
- 10pt SF Pro Expanded Regular (Figma 8pt bumped до 10pt — Apple HIG min)
- Dismiss X (9pt semibold) только для kill-switch reconfigure; .error и
  auto-reconnect — auto-dismiss при state change
- `MainScreenView.effectiveBannerMessage` derived: `.error` state →
  `L10n.bannerConnectionError` priority, иначе `viewModel.reconnectBannerMessage`
- Animation `.easeInOut(0.25)` + transition `.move(edge: .top).combined(opacity)`

### Hardening (post UI fix-loop, 5 commits `d52dc13 → 25bfda6`)

После закрытия UI fix-loop пройден pass technical hardening:

1. **BBTBTopBar migration completed** (`20f0d78`) — последние 3 inline TopBar
   (MainScreenView/ServerListSheet/ServerDetailView) мигрированы на единый
   reusable component. Дублирование ~60 строк устранено. Все 6 экранов
   используют единый pattern: padding [h:28, t:32, b:16], 16pt Expanded
   Semibold title, Phosphor icon slots.

2. **Snapshot baselines recorded** (`94e7b78`) — 11 PNG (5 ConnectionButton +
   1 OnboardingView + 5 ServerList) на iPhone 17 simulator. Закрыт Phase 13
   carve-out «AppFeatures snapshot baseline linker» — добавлены
   `linkerSettings: [.linkedLibrary("resolv"), ...]` к ServerListFeatureTests
   и SettingsFeatureTests (раньше падало с `_res_9_ninit` undefined symbol).
   Verify run TEST SUCCEEDED 11/11 за 27 секунд.

3. **Snapshot tests dark mode fix** (`7f60783`) — `.preferredColorScheme(.dark)`
   → `.environment(\.colorScheme, .dark)` во всех 3 test файлах (11 occurrences).
   `.preferredColorScheme` это hint для parent presentation containers; для
   standalone snapshot рендера нужен direct env override. Baselines
   re-recorded — теперь корректный Dark trait (черный canvas + dark gray
   controlIdle + alwaysWhite text на accent/error).

4. **UX fix sheet onDismiss refresh** (`25bfda6`) — `.sheet(isPresented:onDismiss:)`
   теперь зовёт `viewModel.refresh()` async после закрытия ServerListSheet.
   До фикса: user удаляет все серверы → закрывает sheet → MainScreen
   продолжает показывать ConnectionButton (state stale в `.idle`). После
   фикса: refresh recomputes supported count → state .idle → .empty →
   EmptyStateCard рендерится. Phase 11 D-01 sticky-forever
   `hasShownOnboarding` preserved — Onboarding sheet не переоткрывается.

### Deferred (carry-forward за пределы Phase 12)

- **Subscription quota fields** — расширить `VPNCore.Subscription` model
  (`usedBytes`, `totalBytes`, `expiresAt`) + conditional progress bar в
  SubscriptionHeader (Figma 3064:1154 рисует «11 Гб / 100 Гб» + capsule
  track + accent fill). Backend support тоже needed.
- **Visual UAT** всех 4 Home states + 2 Server variants — требует реального
  config import; simctl нет UI tap automation. User проверяет manually на
  device build.

### Known unbound nodes (acceptable)

- **Frame 14 / Frame 15** (Servers Selected/Auto scrim overlays) — black @20% opacity full-screen overlay. Works visually in both modes. Hex literal, не bound.
- **Spinner gradient stop[0]** — alpha=0 transparent (intentional fade-arc), не bind-able single variable preserving transparency.
- **4× Rectangle 2 (accent green) в hidden Group 1** — внутри AutoCell + Конфигурации Frame 12 instances где progress bar `visible:false`. Dead nodes.

## Phase 13 prerequisites (carry-forward)

- DETECT-03 admin handoff (rules.json sign MAX-domains — Phase 11 carry-out)
- Apple Distribution credentials (Phase 1 DIST-02 carry-over — cert + App Store profiles для `app.bbtb.client.ios` + `.tunnel`)
- SPKI subscription pins replacement (Phase 10 placeholder — `PinStore.swift` 64 `a`s/`b`s)
- macOS UAT replay (Phase 6e D-03 defer)
- Numerical Instruments baseline (Phase 6e D-02 defer)
- **Phase 12 carve-out:** AppFeatures snapshot baseline recording через `.linkedLibrary("resolv")` или Tuist test scheme

## Backlog (post-v1.0)

- macOS pixel-perfect rebuild (включая cleanup macOS + macOS popover Figma страниц)
- Full Light mode (после того как designer дорисует Light версии экранов в Figma)
- In-app Theme toggle в Settings (System/Light/Dark) — v1.1+
- Power-Glow effect восстановление — отдельный design pass если решим вернуть
- Code Connect SDK publish — Education Figma plan blocker (нужен Org tier upgrade для `code_connect:write` scope)

## Related pages

- [[onboarding-ux-polish-2026]] — Phase 11 closure: Figma cleanup + Code Connect documentation contracts
- [[architecture]] — общая архитектура SwiftPM monorepo
- [[performance-baseline]] — Phase 6d/6e perf decisions (DEC-06d-01..06)
- [[security-gaps]] — R10/R11 sing-box invariants (Phase 12 не трогает)
