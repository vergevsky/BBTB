---
phase: 8
slug: rules-engine-split-tunneling
status: draft
shadcn_initialized: false
preset: not applicable (SwiftUI native, Apple platforms)
created: 2026-05-15
---

# Phase 8 — UI Design Contract

> Visual and interaction contract for v0.8 (Rules Engine + Split tunneling). UI surface is intentionally **minimal**: 1 new section в `AdvancedSettingsView` (RULES-09 + RULES-10) + 1 modal sheet поверх `MainScreenView` + 1 persistent banner (D-11 `min_app_version`). Никакого нового экрана — всё реиспользует существующие Form/Section/Toggle patterns из Phase 6 (`SettingsFeature`).
>
> Платформа: SwiftUI native iOS 17+ / macOS 14+. SettingsView shared across platforms (per Phase 6 architecture).
> Все user-facing строки на **русском** (project rule CLAUDE.md) + English duplicate в `Localizable.xcstrings` (LOC-01 baseline).
> Все 4 area decisions взяты из `08-CONTEXT.md` D-01..D-13 — UI-SPEC только конкретизирует визуальные/UX-параметры для D-10/D-11 + RULES-09/RULES-10.
>
> **Scope amendment recap (from CONTEXT):** SC #3 + RULES-11 (macOS AppProxy data plane) → **Out of Scope v0.8**. UI этого не отражает (никакого per-app picker, никакого split-tunnel UI). `never_through_vpn` / `always_through_vpn` секции в Rules Viewer показывают **только** domains + IP CIDRs + countries, никаких bundle IDs.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (SwiftUI native, no shadcn) |
| Preset | not applicable (Apple platforms — SwiftUI) |
| Component library | SwiftUI native + Phase 2 `DesignSystem` package (`DS.Spacing`, `DS.Radius`, `DS.Typography`) |
| Icon library | SF Symbols (system) |
| Font | San Francisco (system) — через `Font.TextStyle` (Dynamic Type compatible) |

> shadcn-init gate: **N/A** — стек Swift/SwiftUI, components.json не применим. Registry-safety gate: **N/A** — нет third-party registries, никаких внешних шаблонов в Phase 8.

---

## <assumptions> — Inferred from codebase, not from CONTEXT.md

CONTEXT.md зафиксировало:
- D-10 cooldown=60s, disabled с countdown «Подождите 45с».
- D-11 modal sheet dismissible + persistent banner в Settings → Advanced.
- RULES-09 read-only viewer в Settings → Advanced.
- RULES-10 force-update button в Settings → Advanced.

CONTEXT.md **не** ответило явно на следующие визуальные/UX вопросы. Решения inferred from existing codebase patterns + smallest defensible defaults; documented здесь чтобы planner видел assumption boundary:

| ID | Question | Inferred answer | Source pattern |
|---|---|---|---|
| **A-01** | Где physically размещается Rules section в `AdvancedSettingsView`? | Третья секция, после `DNSSection` (Phase 6) + перед killSwitch (если бы был). Form ordering: AdBlock → CustomDNS → **Rules → Force update**. | Phase 6 Form ordering от most-frequently-used к least; Rules read-only viewer reaches последнее место как «admin tool». |
| **A-02** | Что показывает viewer когда `rules.json` ещё не fetched (т.е. в первые секунды после first install, до того как baseline applied)? | Показывает baseline (version=0) из bundle. baseline всегда non-empty (per D-05), так что `.empty` UI state визуально невозможен. Defensive `.empty` ветка показывает «Правила недоступны» (см. §Edge cases). | D-05: «bootstrap baseline применяется immediately из bundle» — гарантированный non-empty state. |
| **A-03** | Layout for каждого rule entry: list row или table cell? | List row inside Form `Section`. Каждая категория (`block_completely` / `never_through_vpn` / `always_through_vpn`) = отдельная `Section`. Внутри секции: `DisclosureGroup` для каждого matcher type (domains / ip_cidrs / countries). | Phase 6 `AdvancedSettingsView` использует `Form { Section { ... } }`; SwiftUI native pattern для categorised read-only data. |
| **A-04** | Success/failure feedback для force-update button: inline label, toast, alert? | **Inline status row** под кнопкой, mirror Phase 6 banner pattern: ✓ зелёная checkmark + «Правила обновлены до версии N» либо ⚠ оранжевый triangle + «Обновление не удалось». Самостирается через 4 секунды. **НЕ alert** (UX-harsh для рутинной admin operation) **и НЕ system toast** (нет нативного SwiftUI toast API; rolling-our-own = scope creep). | `ReconnectBanner` pattern: inline message + auto-dismiss. Минимальный visual surface. |
| **A-05** | Какой timestamp format у `last_fetched_at`? | `RelativeDateTimeFormatter` с `unitsStyle: .full`: «обновлено 2 ч назад» / «обновлено только что» / «не обновлялось». Same formatter family как Phase 3 `SubscriptionHeader`. | Phase 3 UI-SPEC §2.4 уже использует `RelativeDateTimeFormatter`. |
| **A-06** | Где shown current rules version? | Header secции «Текущие правила»: `«Версия N · обновлено 2 ч назад»` (caption font, secondary color). Reused timestamp from A-05. | Phase 3 SubscriptionHeader pattern с inline metadata. |
| **A-07** | Copy-paste-friendly для support tickets — selectable text? | Все доменные/IP-строки используют `.textSelection(.enabled)` на SwiftUI Text. Доступно с iOS 15 / macOS 12. | Standard SwiftUI feature; minimal cost, high value для bug-reports. |
| **A-08** | D-11 modal sheet — когда показывается, и как именно «persistent» работает? | Sheet: при cold-start `MainScreenView.onAppear` если `min_app_version > current && !userDismissedThisVersion`. После dismiss — флаг `dismissedMinAppVersion: String` (per-version) сохраняется в `@AppStorage`; sheet не показывается повторно для той же min_app_version в той же сессии. **Persistent banner** в Settings → Advanced показывается **always** пока `min_app_version > current` (независимо от dismissal). | Apple HIG: modal interrupts once; persistent reminders in Settings. Mirrors iOS «Storage Almost Full» pattern. |
| **A-09** | Размер D-11 modal sheet на macOS? | 440×320 pt, resizable=false, центрировано. Mirror Phase 2 import-result alert sizing constraints (compact). | macOS sheet sizing convention — smaller for transactional dialogs. |
| **A-10** | Что в D-11 sheet — иллюстрация? | Иконка (SF Symbol `arrow.up.app.fill`, accent color, 56pt) сверху + title + body + 2 buttons. Никакой кастомной иллюстрации в v0.8 — Phase 11 финал может заменить. | `EmptyStateCard` (Phase 2) pattern: SF Symbol + text + button. |
| **A-11** | Cooldown countdown visual: real-time tick или каждую секунду? | Tick каждую секунду через `Timer.publish(every: 1.0)`. Button label updates: «Подождите 45с» → «Подождите 44с» ... → «Принудительно обновить правила». | `ConnectionTimer` (Phase 2) уже использует Timer.publish pattern. |
| **A-12** | Force-update button style: filled, bordered, plain? | `.borderedProminent` с tint = `Color.accentColor`. Disabled state — system handles graying. **НЕ destructive red** — это не destructive action. | SwiftUI `.borderedProminent` для primary actions inside Form. |
| **A-13** | Disabled-state appearance во время network fetch (после tap, до cooldown active)? | Button disabled + inline `ProgressView()` справа от label. Same period: «Обновление…» текст + spinner. Затем — success/failure inline status (A-04). | `ImportProgressOverlay` (Phase 2) для long fetch; здесь короче — inline spinner достаточно. |
| **A-14** | Spacing scale — какие token values? | Phase 3 normalized 8-point grid `{4, 8, 16, 24, 32, 48, 64}`. **Не** `DS.Spacing.md = 12` (текущий codebase value). Phase 8 продолжает Phase 3 normalization — `md = 16`. **Implementation note для planner:** Phase 8 НЕ переписывает `DS.Spacing.md` (это riskier global change); Phase 8 use literal `16` / `24` / `32` для new components либо ждёт Phase 11 финальной DesignSystem migration. | Phase 3 UI-SPEC §8.1 documented нормализацию; Phase 11 doc-promotion. |
| **A-15** | Color contract — какие colors used? | Все из system palette (Phase 3 inheritance + iOS dark/light auto). Accent = `Color.accentColor` (system blue). Destructive (для `block_completely` category badge) = `Color.red.opacity(0.15)` background. Каждая категория получает свой semantic background tint (см. §Color). | Phase 3 §8.3 60/30/10 split; новые tinted backgrounds для category visual separation. |
| **A-16** | Typography — расширяем ли 4-роль Phase 3 set? | **Нет**. Используем те же 4 роли: `title` / `body` / `subheadline` / `caption`. Веса — `.regular` и `.semibold`. Monospaced — только для IP CIDRs и domain entries (через `.monospaced()` modifier on body text), чтобы выравнивались символы. | Phase 3 UI-SPEC §8.4 строгий 4-role / 2-weight contract. |
| **A-17** | Какой fallback если bundle baseline тоже failed (defensive empty)? | Empty inline card внутри Rules section: иконка `doc.text.magnifyingglass` + «Правила недоступны» + «Откройте приложение при работающем интернете, чтобы загрузить правила». **Никакого retry button** — pull-to-refresh не работает в Form; force-update button рядом и так уже delivers retry. | Phase 3 §3.5 inline empty card pattern. |
| **A-18** | iOS/macOS parity — есть ли отличия? | Все компоненты shared. Отличия: (1) sheet sizing на macOS (A-09), (2) `.confirmationDialog` → `.alert` (Phase 3 §11 precedent — ни одного использования here), (3) haptic feedback на iOS only для force-update tap (`.light` impact). Все остальные UI — identical. | Phase 3 §11 platform-difference matrix; Phase 8 = pure добавление, не вводит новые divergences. |
| **A-19** | Where exactly D-11 modal trigger lives in code? | `MainScreenViewModel.handleMinAppVersionCheck()` invoked в `MainScreenView.onAppear` + при receiving `bbtbRulesEngineDidUpdate` notification (post-fetch проверка). Sheet binding = `@Published var showMinAppVersionSheet: Bool`. | Phase 3 `isPresentingServerList` precedent (MainScreenViewModel:87). |
| **A-20** | Banner placement и appearance внутри Advanced section? | Persistent banner = top-most row внутри Form (выше DNS section), background `Color.orange.opacity(0.15)`, SF Symbol `arrow.up.circle.fill` + text + chevron leading to action. Mirror `ReconnectBanner` style. | `ReconnectBanner.swift` pattern uses identical orange tint + horizontal layout. |

**Total inferred decisions: 20.** All low-cost; any single one can be revisited по `gsd-discuss-phase 8` follow-up if needed.

---

## Spacing Scale

Phase 8 использует строго 8-point grid (Phase 3 normalized set): {4, 8, 16, 24, 32, 48}.

| Token | Value (pt) | Phase 8 usage |
|-------|------------|---------------|
| xs | 4 | Section header to first-row gap (system-controlled in Form) |
| sm | 8 | Vertical padding между inline status row и кнопкой force-update; HStack gap внутри banner row |
| md | 16 | Default Section padding (system-controlled); HStack gap в RuleEntryRow (icon + text); D-11 sheet content padding horizontal |
| lg | 24 | D-11 sheet vertical spacing между иконкой и title; gap между title и body; gap между body и button stack |
| xl | 32 | D-11 sheet outer vertical padding (top before icon, bottom after buttons) |
| 2xl | 48 | (reserved — not used) |
| 3xl | 64 | (reserved — not used) |

**Exceptions:** SF Symbol nominal sizes (28/56/24/22 pt) — не входят в spacing scale (это font/icon sizing, не layout).

**DesignSystem package status:** `DS.Spacing.md` в коде сейчас = 12 pt (legacy Phase 2 value). Phase 8 components use **literal 16** for `md` slot (см. A-14). Phase 11 финальная DesignSystem migration переопределит `DS.Spacing.md = 16` глобально.

---

## Typography

Phase 8 использует **4 типографических роли** (унаследовано из Phase 3 § 8.4) и **2 веса** (`.regular` + `.semibold`). Расширения нет.

| Role | Style | Weight | Phase 8 usage |
|------|-------|--------|---------------|
| `title` | `.title3` | `.semibold` | D-11 sheet title «Доступна новая версия»; inline empty card «Правила недоступны» |
| `body` | `.body` | `.regular` | RuleEntryRow text (domains/IPs/countries); D-11 sheet body text; banner text |
| `subheadline` | `.subheadline` | `.semibold` | Force-update button label; inline status row label; D-11 secondary button label |
| `caption` | `.caption` | `.regular` | Section header «ВЕРСИЯ 42 · ОБНОВЛЕНО 2 Ч НАЗАД» (`.textCase(.uppercase)`); cooldown countdown text «Подождите 45с»; entry-count badge «1247 доменов» |

**Special modifiers (do NOT count as new typography roles):**
- `.monospaced()` — apply to body for entries (`example.com`, `192.168.0.0/16`, `RU`) для выравнивания
- `.monospacedDigit()` — apply to caption для cooldown countdown («Подождите 45с» — digit alignment)
- `.textCase(.uppercase)` — apply to caption для section sub-headers (consistent с Phase 3 §2.4 SubscriptionHeader pattern)

Body line-height: системный (Dynamic Type ~1.4-1.5). Heading line-height: системный.

---

## Color

Phase 8 наследует Phase 3 § 8.3 60/30/10 contract. Никаких новых цветов не вводится; только новые **usage rules** для category-specific tinting.

| Role | iOS | macOS | Phase 8 usage |
|------|-----|-------|---------------|
| **Dominant (60%)** — surface | `Color(.systemGroupedBackground)` | `Color(NSColor.windowBackgroundColor)` | Form background; D-11 sheet container background |
| **Secondary (30%)** — cards | `Color(.secondarySystemBackground)` | `Color(NSColor.controlBackgroundColor)` | Form Section row background; D-11 sheet button group container |
| **Tertiary fill** | `Color(.tertiarySystemFill)` | similar | category count badge background («1247 доменов» pill); cooldown countdown background (subtle) |
| **Accent (10%)** | `Color.accentColor` (system blue) | same | Force-update button (`.borderedProminent` tint); D-11 sheet primary button («Обновить через TestFlight»); D-11 SF Symbol icon foreground; success status checkmark (✓ green→ use system green); RuleViewer DisclosureGroup chevron tint |
| **Destructive** | `Color.red` | same | НЕ используется в Phase 8 (нет destructive actions) |
| **Warning / Banner** | `Color.orange.opacity(0.15)` for bg, `Color.primary` text | same | D-11 persistent banner background; failure status inline (⚠ orange triangle); inline status «Обновление не удалось» |
| **Success / Green** | `Color.green` (system) | same | Force-update inline success «✓ Правила обновлены до версии N» (icon color, NOT background) |
| **Category-Block** | `Color.red.opacity(0.10)` for bg, `Color.primary` text | same | `block_completely` Section row leading-icon background (subtle red tint to signal «danger»); icon foreground = `Color.red` |
| **Category-Never** | `Color.orange.opacity(0.10)` | same | `never_through_vpn` Section row leading-icon background (split-tunnel signal); icon foreground = `Color.orange` |
| **Category-Always** | `Color.green.opacity(0.10)` | same | `always_through_vpn` Section row leading-icon background («pinned through VPN» signal); icon foreground = `Color.green` |

**Accent reserved for** (явный список — никаких «all interactive elements»):
- Force-update button fill (`.borderedProminent` background)
- D-11 sheet primary button («Обновить через TestFlight») fill
- D-11 sheet иконка `arrow.up.app.fill` foreground
- DisclosureGroup chevron rotation tint (system default)
- NavigationBar tint, system Settings sheets — system-controlled

**60/30/10 verification for Phase 8 surface:**
- 60% — Form group background (`systemGroupedBackground`) занимает основной surface.
- 30% — `secondarySystemBackground` для row carving + sheet content card. Phase 8 banner (`orange.opacity(0.15)`) — bounded к одному baseline-row высотой, не нарушает 30% bound (Phase 3 documented `ReconnectBanner` precedent).
- 10% — accent strictly на 1-2 actionable items на screen (force-update CTA + optional sheet primary button).

---

## Copywriting Contract

Все user-facing строки на **русском** (project rule). English duplicate в `Localizable.xcstrings` для будущей LOC-02 финальной локализации (Phase 11).

### RULES-09 — Rules Viewer copy

| Element | Russian | English | L10n key |
|---------|---------|---------|----------|
| Section header (block category) | БЛОКИРОВАТЬ ПОЛНОСТЬЮ | BLOCK COMPLETELY | `rules.section.block` |
| Section footer (block) | Эти адреса заблокированы независимо от состояния VPN. | These addresses are blocked regardless of VPN state. | `rules.section.block.footer` |
| Section header (never) | МИМО VPN | OUTSIDE VPN | `rules.section.never` |
| Section footer (never) | Эти адреса идут напрямую, минуя VPN. | These addresses go direct, bypassing the VPN. | `rules.section.never.footer` |
| Section header (always) | ВСЕГДА ЧЕРЕЗ VPN | ALWAYS VIA VPN | `rules.section.always` |
| Section footer (always) | Эти адреса всегда идут через VPN, даже когда VPN формально отключён. | These addresses always go through the VPN, even when VPN is formally off. | `rules.section.always.footer` |
| Sub-section: domains | Домены | Domains | `rules.matcher.domains` |
| Sub-section: ip_cidrs | IP-адреса и подсети | IP addresses and subnets | `rules.matcher.ipcidrs` |
| Sub-section: countries | Страны | Countries | `rules.matcher.countries` |
| Entry-count badge | %lld доменов / %lld адресов / %lld стран | %lld domains / %lld addresses / %lld countries | `rules.count.domains`, `rules.count.ipcidrs`, `rules.count.countries` |
| Viewer header (version + timestamp) | Версия %lld · обновлено %@ | Version %lld · updated %@ | `rules.header.version` |
| Empty matcher subcategory | Пусто | Empty | `rules.empty.category` |
| Inline empty card (defensive) | Правила недоступны | Rules unavailable | `rules.empty.title` |
| Inline empty card body | Откройте приложение при работающем интернете, чтобы загрузить правила. | Open the app with a working internet connection to download rules. | `rules.empty.subtitle` |

### RULES-10 — Force-update button copy

| Element | Russian | English | L10n key |
|---------|---------|---------|----------|
| Button label (idle) | Принудительно обновить правила | Force update rules | `rules.forceUpdate.button` |
| Button label (in progress) | Обновление… | Updating… | `rules.forceUpdate.inProgress` |
| Button label (cooldown) | Подождите %lldс | Wait %llds | `rules.forceUpdate.cooldown` |
| Inline status (success) | ✓ Правила обновлены до версии %lld | ✓ Rules updated to version %lld | `rules.forceUpdate.success` |
| Inline status (no-op, already latest) | ✓ Уже актуальная версия %lld | ✓ Already at latest version %lld | `rules.forceUpdate.noChange` |
| Inline status (network failure) | ⚠ Не удалось обновить. Проверьте интернет. | ⚠ Update failed. Check your internet. | `rules.forceUpdate.network` |
| Inline status (signature failure) | ⚠ Подпись правил не прошла проверку. Используется кешированная версия. | ⚠ Rules signature invalid. Using cached version. | `rules.forceUpdate.signature` |
| Section footer (explanation) | Кнопка обновит правила вне расписания (раз в минуту). Обычно правила обновляются автоматически каждые 6 часов. | The button updates rules off-schedule (once per minute). Rules normally update automatically every 6 hours. | `rules.forceUpdate.footer` |

### D-11 — `min_app_version` modal sheet copy

| Element | Russian | English | L10n key |
|---------|---------|---------|----------|
| Sheet title | Доступна новая версия | New version available | `minAppVersion.sheet.title` |
| Sheet body | Текущая версия (%@) больше не поддерживается. Обновитесь через TestFlight, чтобы продолжить пользоваться приложением безопасно. | The current version (%@) is no longer supported. Update via TestFlight to continue using the app safely. | `minAppVersion.sheet.body` |
| Primary button | Открыть TestFlight | Open TestFlight | `minAppVersion.sheet.primary` |
| Secondary button | Позже | Later | `minAppVersion.sheet.secondary` |
| Persistent banner | Доступно обновление приложения. | An app update is available. | `minAppVersion.banner.text` |
| Persistent banner CTA hint | Нажмите, чтобы открыть | Tap to open | `minAppVersion.banner.cta` |

### Primary CTA + empty/error states (summary)

| Element | Copy |
|---------|------|
| Primary CTA (Phase 8 surface) | «Принудительно обновить правила» (RULES-10 button — main actionable thing in this phase's UI) |
| Empty state heading | «Правила недоступны» (only shown defensively if baseline failed) |
| Empty state body | «Откройте приложение при работающем интернете, чтобы загрузить правила.» (no retry button — force-update button is the implicit retry) |
| Error state (transient inline) | «⚠ Не удалось обновить. Проверьте интернет.» (4-second auto-dismiss) |
| Destructive confirmation | **N/A** — Phase 8 has no destructive actions (RULES-09 read-only; RULES-10 idempotent fetch). |

---

## Interaction Patterns

### 1. Navigation entry

Settings → Расширенные (`AdvancedSettingsView`, existing) → scroll → see «Правила» section + force-update button + (если активна) persistent banner.

### 2. Rules Viewer (RULES-09) — interaction model

| Element | Interaction | Behavior |
|---------|-------------|----------|
| Viewer header («Версия N · обновлено 2 ч назад») | non-interactive | Static caption, refreshes when ViewModel publishes new `rulesVersion` |
| Category Section (block/never/always) | Form-native | Header + footer text rendered standard |
| Matcher sub-row (Domains / IP CIDRs / Countries) | `DisclosureGroup` | Tap to expand; system chevron animation; default collapsed; remembers per-launch state via `@AppStorage("rules.viewer.expanded.\(category).\(matcher)") Bool` |
| Entry row inside DisclosureGroup | non-interactive text + selectable | `Text(entry).textSelection(.enabled)` — long-press copies; no tap action |
| Entry-count badge | non-interactive | Subtle pill, shown in header row even when DisclosureGroup collapsed |

### 3. Force-update button (RULES-10) — interaction state machine

```
States:
    .idle           — button enabled, label = «Принудительно обновить правила»
                       inline status row = hidden
                       
    .inProgress     — button disabled + spinner; label = «Обновление…»
                       inline status row = hidden
                       (entered: on tap)
                       
    .cooldown(sec)  — button disabled; label = «Подождите 45с» (counts down)
                       inline status row = success/failure outcome (4-sec auto-dismiss
                       independently of cooldown)
                       (entered: after .inProgress finishes, успешно или нет)
                       
    Transitions:
      .idle  --tap--> .inProgress
      .inProgress --fetch returns--> .cooldown(60)
      .cooldown(sec) --tick every 1s--> .cooldown(sec-1)
      .cooldown(0) --> .idle
```

| Trigger | Side-effect |
|---------|-------------|
| Tap force-update (button .idle) | iOS haptic `UIImpactFeedbackGenerator(style: .light).impactOccurred()`; transition `.idle → .inProgress`; ViewModel invokes `RulesEngineCoordinator.forceUpdate()` |
| Cooldown countdown tick | `@Published var cooldownSecondsRemaining: Int?` decrements; Timer.publish on `.main` queue (UI thread OK — 1Hz tick); cancellation on view disappear |
| Inline status auto-dismiss | `@Published var lastStatusOutcome: ForceUpdateOutcome?` — set on fetch return, scheduled `Task { try await Task.sleep(for: .seconds(4)); await MainActor.run { lastStatusOutcome = nil } }` |
| Settings view leaves (`onDisappear`) | Cooldown timer cancelled; cooldown state **persists** в ViewModel (next entry resumes countdown); status outcome auto-dismiss task allowed to complete |
| Background-foreground re-entry | Cooldown resumes correctly via wallclock comparison (cooldown stores `cooldownExpiresAt: Date?`, not just integer seconds) |

### 4. D-11 modal sheet — lifecycle

| Stage | Trigger | UI |
|-------|---------|----|
| Initial app launch | `MainScreenView.onAppear` checks `rulesEngine.minAppVersion > AppVersion.current && !UserDefaults.bool(forKey: "minAppVersion.dismissed.\(rulesEngine.minAppVersion)")` | If true: present sheet (`@Published var showMinAppVersionSheet: Bool = true`) |
| Post-fetch update | Receives `bbtbRulesEngineDidUpdate` notification | Re-evaluates same check; if min_app_version increased — present sheet (regardless of previous dismissal flag, because version is new) |
| User taps «Открыть TestFlight» | Opens TestFlight invite URL via `UIApplication.shared.open(_:)` / `NSWorkspace.shared.open(_:)` | URL = constant in code (`https://testflight.apple.com/join/<token>`); sheet dismisses |
| User taps «Позже» | Dismisses sheet; sets `UserDefaults.set(true, forKey: "minAppVersion.dismissed.\(rulesEngine.minAppVersion)")` | Sheet won't auto-show again for THIS min_app_version value; persistent banner remains visible in Settings → Advanced |
| User swipes-down to dismiss | Same as «Позже» | Same persistent behavior |

### 5. Persistent banner inside `AdvancedSettingsView`

| Aspect | Detail |
|--------|--------|
| Trigger | Same condition `rulesEngine.minAppVersion > AppVersion.current` (no dismissal interaction) |
| Placement | First row inside `AdvancedSettingsView` Form (above DNS section). Acts as «notice strip». |
| Interaction | Tap entire row → opens TestFlight URL (same handler as sheet primary button) |
| Visual cue | SF Symbol `arrow.up.circle.fill` (foreground orange) leading + text + system chevron `chevron.right` trailing |
| Dismissal | None — banner stays until `rulesEngine.minAppVersion <= AppVersion.current` (i.e. user updates app OR admin lowers min_app_version in next rules.json fetch) |
| Accessibility | `.accessibilityHint = «Дважды нажмите чтобы открыть TestFlight»` |

---

## Layout Specifications

### Rules section in `AdvancedSettingsView`

```
┌────────────────────────────────────────────────────────┐
│ Расширенные                                            │  ← navigationTitle (system)
├────────────────────────────────────────────────────────┤
│                                                        │
│ ⬆ Доступно обновление приложения.              ›     │  ← Persistent banner (if active)
│   (background orange.opacity(0.15))                   │     Tap → open TestFlight
│                                                        │
├── РЕКЛАМА / DNS (Phase 6) ─────────────────────────────┤
│  ☐ Блокировать рекламу через DNS                       │
│    Свой DNS-сервер: [____________]                     │
├── ПРАВИЛА · ВЕРСИЯ 42 · ОБНОВЛЕНО 2 Ч НАЗАД ──────────┤
│                                                        │
│ ── БЛОКИРОВАТЬ ПОЛНОСТЬЮ ──                            │
│   ▶ Домены                              [42 шт.]      │  ← DisclosureGroup collapsed
│   ▶ IP-адреса и подсети                  [3 шт.]      │
│   ▶ Страны                               [пусто]      │
│   Эти адреса заблокированы независимо от состояния VPN.│
│                                                        │
│ ── МИМО VPN ──                                         │
│   ▼ Домены                              [128 шт.]     │  ← Expanded
│      bank.example.ru                                   │
│      gov.example.ru                                    │
│      … (scrollable inline list)                        │
│   ▶ IP-адреса и подсети                  [12 шт.]      │
│   ▶ Страны                               [1 шт.]      │
│   Эти адреса идут напрямую, минуя VPN.                 │
│                                                        │
│ ── ВСЕГДА ЧЕРЕЗ VPN ──                                 │
│   ▶ Домены                              [1247 шт.]    │
│   ▶ IP-адреса и подсети                  [0 шт.]      │
│   ▶ Страны                               [0 шт.]      │
│   Эти адреса всегда идут через VPN, даже когда…       │
│                                                        │
├── ОБНОВЛЕНИЕ ПРАВИЛ ──────────────────────────────────┤
│                                                        │
│ [Принудительно обновить правила      ]      ← .borderedProminent button │
│                                                        │
│ ✓ Правила обновлены до версии 42      ← inline status (auto-dismiss 4s)│
│                                                        │
│ Кнопка обновит правила вне расписания (раз в минуту).  │  ← Section footer
│ Обычно правила обновляются автоматически каждые 6 ч.   │
│                                                        │
└────────────────────────────────────────────────────────┘
```

| Element | Specification |
|---------|---------------|
| Persistent banner row | `Section { Button(action: openTestFlight) { HStack { Image(systemName: "arrow.up.circle.fill").foregroundColor(.orange); VStack(alignment: .leading) { Text(L10n.minAppVersionBannerText); Text(L10n.minAppVersionBannerCta).font(.caption).foregroundColor(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption) } } }` Padding: system Form default. Background: `.listRowBackground(Color.orange.opacity(0.15))`. |
| Rules section header | `Text("ПРАВИЛА · ВЕРСИЯ \(version) · ОБНОВЛЕНО \(relativeTime)")` with `.textCase(.uppercase)` + caption font. |
| Category sub-section header | `Text("БЛОКИРОВАТЬ ПОЛНОСТЬЮ")` etc. с `.textCase(.uppercase)` + caption font (rendered inside parent Section, not separate Section — to preserve grouped row visual). |
| DisclosureGroup label | `HStack { Image(systemName: categoryIcon).foregroundColor(categoryColor); Text(matcherName); Spacer(); Text("\(count) шт.").font(.caption).foregroundColor(.secondary).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color(.tertiarySystemFill))) }` |
| DisclosureGroup expanded content | `LazyVStack(alignment: .leading, spacing: 4) { ForEach(entries) { entry in Text(entry).font(.body.monospaced()).textSelection(.enabled).padding(.vertical, 2) } }` |
| Force-update button | `Button(action: viewModel.forceUpdate) { Text(buttonLabel) }.buttonStyle(.borderedProminent).tint(.accentColor).disabled(buttonState != .idle).frame(maxWidth: .infinity)` |
| Inline status row | `HStack(spacing: 8) { Image(systemName: statusIcon).foregroundColor(statusColor); Text(statusText).font(DS.Typography.subheadline); Spacer() }.padding(.vertical, 4).transition(.opacity)` |

**Spacing budget within section:**
- Section header → first matcher row: system Form default (~8 pt)
- Between matcher rows inside one category: system divider (1 pt)
- Between categories (block → never → always): standard Section divider (16 pt)
- Force-update button → inline status: 8 pt
- Inline status → section footer: 8 pt

### D-11 modal sheet — layout

```
┌───────────────────────────────────────────┐
│                                           │  ← 32 pt top padding
│                                           │
│              [icon 56pt]                  │  ← SF Symbol arrow.up.app.fill, accent color
│                                           │
│                                           │  ← 24 pt vspace
│      Доступна новая версия                │  ← title (DS.Typography.title)
│                                           │
│                                           │  ← 24 pt vspace
│   Текущая версия (1.0.5) больше не        │
│   поддерживается. Обновитесь через         │  ← body (DS.Typography.body)
│   TestFlight, чтобы продолжить             │
│   пользоваться приложением безопасно.      │
│                                           │
│                                           │  ← 32 pt vspace
│  ┌──────────────────────────────────┐    │
│  │      Открыть TestFlight         │     │  ← .borderedProminent, accent
│  └──────────────────────────────────┘    │
│                                           │  ← 12 pt vspace
│            Позже                          │  ← .plain button, .secondary foreground
│                                           │
│                                           │  ← 32 pt bottom padding
└───────────────────────────────────────────┘
```

| Aspect | Specification |
|--------|---------------|
| Presentation | `.sheet(isPresented: $showMinAppVersionSheet) { MinAppVersionSheet(...) }` |
| iOS detents | `.presentationDetents([.medium])` — half-height; не нужен full-screen |
| iOS drag indicator | `.presentationDragIndicator(.visible)` |
| Background interaction | `.presentationBackgroundInteraction(.disabled)` |
| macOS size | 440×320 pt, resizable=false |
| Container | `VStack(spacing: 0)` |
| Padding | horizontal 24 pt, vertical 32 pt |
| Icon | SF Symbol `arrow.up.app.fill`, size 56, weight `.semibold`, foreground `Color.accentColor` |
| Title | `Text(L10n.minAppVersionSheetTitle).font(DS.Typography.title).multilineTextAlignment(.center)` |
| Body | `Text(L10n.minAppVersionSheetBody(AppVersion.current)).font(DS.Typography.body).foregroundColor(.secondary).multilineTextAlignment(.center)` |
| Primary button | `.borderedProminent`, `.controlSize(.large)`, `tint(.accentColor)`, `.frame(maxWidth: .infinity)` |
| Secondary button | `.plain` button, `.foregroundColor(.secondary)`, font `DS.Typography.subheadline` |
| Sheet background | system default (sheet-canonical) |

---

## Accessibility

| Component | Spec |
|-----------|------|
| Persistent banner row | `.accessibilityElement(children: .combine)`, label = «Доступно обновление приложения. Дважды нажмите чтобы открыть TestFlight», traits = `.button` |
| Rules viewer Section header | exposed as system Form header (читается VoiceOver один раз при entering region) |
| Category badge «42 шт.» | `.accessibilityLabel("\(count) записей")` (Russian word inflection через xcstrings plurals) |
| DisclosureGroup | system default — VoiceOver announces «collapsed/expanded» state |
| Entry inside DisclosureGroup | `.accessibilityLabel(entry)` — простое чтение domain/CIDR/country text; `.textSelection(.enabled)` доступен через rotor copy action |
| Force-update button (idle) | label = «Принудительно обновить правила», hint = «Запросит обновление правил с сервера сейчас» |
| Force-update button (cooldown) | label = «Подождите 45 секунд», hint = «Повторное обновление будет доступно через 45 секунд», traits = `.notEnabled` |
| Force-update button (inProgress) | label = «Обновление правил…», traits = `.notEnabled` |
| Inline status (success) | `UIAccessibility.post(.announcement, "Правила обновлены до версии \(version)")` |
| Inline status (failure) | `UIAccessibility.post(.announcement, "Не удалось обновить правила. Проверьте интернет")` |
| D-11 sheet icon | `.accessibilityHidden(true)` — decorative, не дублирует title |
| D-11 sheet title | system reads as heading |
| D-11 primary button | label = «Открыть TestFlight», hint = «Откроет приложение TestFlight для обновления» |
| D-11 secondary button | label = «Позже», hint = «Закроет уведомление; напоминание останется в Настройках» |
| D-11 dismiss gesture | system default — swipe down on iOS, Escape on macOS |

**Dynamic Type:** All text uses `Font.TextStyle` (no fixed sizes), so AX1-AX5 scales correctly. DisclosureGroup at AX5: rows wrap, badge wraps to new line under label.

**Reduce Motion (`@Environment(\.accessibilityReduceMotion)`):**
- DisclosureGroup expand/collapse — system handles (already respects).
- D-11 sheet present/dismiss — system handles.
- Inline status `.transition(.opacity)` — replace with `.identity` transition when ReduceMotion enabled.
- Force-update button cooldown countdown — already 1Hz tick (no animation involved).

**Right-to-left:** Russian and English both LTR; no RTL adjustments needed in Phase 8.

---

## Responsive Behavior

### iOS

| Screen size | Behavior |
|-------------|----------|
| iPhone SE (320×568) | Form scrolls; DisclosureGroup wraps long domains; rules section may require 2-3 screens of scrolling for 1000+ entries (acceptable — admin support tool) |
| iPhone 15 Pro Max (430×932) | Standard layout; banner row + DNS + Rules + Force-update all visible with light scrolling |
| iPad portrait (810×1080) | Form in regular columns; same layout (no split-view sidebar in Phase 8) |
| iPad landscape (1080×810) | Same Form; sheet detents `.medium` makes D-11 sheet ~540 pt tall |
| Dynamic Type AX5 | DisclosureGroup labels wrap; badges wrap below label; force-update button height grows; sheet body wraps; sheet height auto-expands within detent bounds |

### macOS

| Window size | Behavior |
|-------------|----------|
| Settings window (default 600×500 pt) | Standard Form layout; Rules viewer scrolls within window |
| Settings window resized smaller | Form scrolls; DisclosureGroup wraps |
| Settings window resized larger | Form max-width caps at ~700 pt (system Form behavior); extra space = padding |
| D-11 sheet | Fixed 440×320 pt, centered over Settings window or main app window (depending on caller context) |

### Cross-platform notes

- No platform-specific layout divergence beyond sheet sizing (A-09, A-18).
- Form section ordering identical: DNS → Rules → Force-update.
- DisclosureGroup state (`@AppStorage`) syncs via UserDefaults App Group on iOS+macOS independently per device (no cross-device iCloud sync in Phase 8 — that's CLOUD-01 v1.9).

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Baseline failed to load (rare — corrupted bundle) | Show inline empty card (§A-17) inside Rules section: icon `doc.text.magnifyingglass` + «Правила недоступны» + body. Force-update button still functional. |
| Server fetch returns empty `block_completely.domains` | DisclosureGroup row shows badge «[пусто]» (caption, `.tertiary` color); DisclosureGroup tap still works but expanded content shows single row «(пусто)» with same caption style |
| Server fetch returns malformed JSON | Signature check fails → use cached version; UI unaware (no error shown — admin's problem, not user's) |
| Server fetch returns 10000+ domains | DisclosureGroup uses `LazyVStack` (already specified) — only renders visible rows; scrolling within expanded group is system-native |
| User scrolls during force-update cooldown | Cooldown timer continues; button label visibly updates as user re-enters view |
| User backgrounds app during cooldown | `cooldownExpiresAt: Date` stored in ViewModel state; foreground re-entry recomputes `remaining = expiresAt - Date.now`; if remaining ≤ 0 → button returns to `.idle` |
| User taps force-update right at cooldown expiry (race) | ViewModel guards via `guard buttonState == .idle else { return }`; redundant tap is no-op |
| min_app_version sheet shown while VPN connecting | Sheet appears overlayed; VPN connection proceeds normally (no interference — sheet doesn't block network) |
| min_app_version drops back below current (admin re-published lower minimum) | Persistent banner disappears at next rules.json apply; sheet won't re-present |
| Rules fetched но baseline already same version | Force-update inline status: «✓ Уже актуальная версия N» — distinct copy from success-with-change |
| Signature verification fails on force-update | Inline status: «⚠ Подпись правил не прошла проверку. Используется кешированная версия.» — explicit security messaging |
| Network unreachable on force-update | Inline status: «⚠ Не удалось обновить. Проверьте интернет.» (4-sec auto-dismiss) |
| User taps banner while sheet already on screen (impossible — sheet blocks underlying view) | N/A (sheet has `.presentationBackgroundInteraction(.disabled)`) |
| DisclosureGroup expand state lost after app relaunch | Expected; per-launch state via `@AppStorage` (not @SceneStorage). Phase 11 polish может перевести на @SceneStorage если user feedback требует. |

---

## Component Inventory

### New components in Phase 8

| Component | File | Public API |
|-----------|------|-----------|
| `RulesViewerSection` | `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift` (new) | `init(rules: RulesSnapshot, version: Int, lastFetchedAt: Date?)` — pure data view, no ViewModel |
| `RuleCategoryGroup` | same file | private — encapsulates one category (block/never/always) with 3 matcher disclosure groups |
| `RuleMatcherDisclosure` | same file | private — encapsulates one matcher type (domains/ip_cidrs/countries) with badge + expanded list |
| `ForceUpdateRulesButton` | `BBTB/Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift` (new) | `init(buttonState: ForceUpdateButtonState, statusOutcome: ForceUpdateOutcome?, onTap: @escaping () -> Void)` |
| `MinAppVersionBanner` | `BBTB/Packages/AppFeatures/Sources/SettingsFeature/MinAppVersionBanner.swift` (new) | `init(currentVersion: String, onTap: @escaping () -> Void)` — used inside `AdvancedSettingsView` Form |
| `MinAppVersionSheet` | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MinAppVersionSheet.swift` (new) | `init(currentVersion: String, onOpenTestFlight: @escaping () -> Void, onDismiss: @escaping () -> Void)` |

### Modified components

| Component | File | Change |
|-----------|------|--------|
| `AdvancedSettingsView` | `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` | Add `Section { MinAppVersionBanner(...) }` at top (conditional `if viewModel.showMinAppVersionBanner`); add `Section { RulesViewerSection(...) }`; add `Section { ForceUpdateRulesButton(...) }` |
| `SettingsViewModel` | `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` | Add `@Published var rulesSnapshot: RulesSnapshot?`, `@Published var rulesVersion: Int = 0`, `@Published var rulesLastFetchedAt: Date?`, `@Published var forceUpdateButtonState: ForceUpdateButtonState = .idle`, `@Published var forceUpdateStatusOutcome: ForceUpdateOutcome?`, `@Published var showMinAppVersionBanner: Bool = false`. Bind via `RulesEngineCoordinator` injection (constructor-injected; late-bind setter pattern per memory `feedback_failover_two_phase_init.md`). |
| `MainScreenViewModel` | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | Add `@Published var showMinAppVersionSheet: Bool = false`, `handleMinAppVersionCheck() async` method, observer for `bbtbRulesEngineDidUpdate` notification |
| `MainScreenView` | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` | Add `.sheet(isPresented: $viewModel.showMinAppVersionSheet) { MinAppVersionSheet(...) }` modifier. Add `.onAppear { Task { await viewModel.handleMinAppVersionCheck() } }`. |

### New types (non-View)

| Type | File | Purpose |
|------|------|---------|
| `RulesSnapshot` | `BBTB/Packages/VPNCore/Sources/VPNCore/Rules/RulesSnapshot.swift` (new) | Decoded view of rules.json: `version: Int`, `lastFetchedAt: Date?`, `block: CategoryEntries`, `never: CategoryEntries`, `always: CategoryEntries`. `CategoryEntries = (domains: [String], ipCidrs: [String], countries: [String])`. |
| `ForceUpdateButtonState` | `RulesViewerSection.swift` (or co-located in Settings module) | enum: `.idle / .inProgress / .cooldown(secondsRemaining: Int)` |
| `ForceUpdateOutcome` | same | enum: `.success(version: Int) / .alreadyLatest(version: Int) / .networkFailure / .signatureFailure` |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| (none) | n/a | **not applicable** — SwiftUI native + SF Symbols. Никаких third-party Swift packages добавляется в Phase 8 для UI (swift-crypto добавляется в W0 но это core dependency, не UI registry). |

---

## Out of Scope (Phase 8 — UI surface)

Явный список того, что НЕ реализуется в Phase 8 UI (всё это либо backlog либо Phase 9+):

- **Edit/admin UI для rules** — viewer is read-only. RULES-01..08 backend, RULES-09 viewer only.
- **Per-app picker (bundle ID selection)** — RULES-11 + Phase 8 SC #3 → Out of Scope per D-08.
- **Push «правила обновлены» уведомление** — v1.4+ backlog (CONTEXT deferred).
- **Pull-to-refresh для force-update** — Form не поддерживает refreshable; force-update button уже delivers same UX.
- **Search/filter в Rules viewer** — Phase 11 polish если потребуется (1000+ доменов реально неудобно scrollить, но это admin tool).
- **«Diff» display показывающий что изменилось в новой версии правил** — Phase 11+ если будут запросы. v0.8 показывает только current snapshot.
- **Toast / push уведомление при автоматическом fetch (background)** — v0.8 silent; user видит изменения только при следующем открытии Settings.
- **Toggle «Disable rules engine»** — feature не toggleable; всегда работает (per RULES-04 cadence + baseline floor).
- **Multi-port config UI** (carry from Phase 4 D-09) — v1.x backlog.
- **DPI-09 uTLS fingerprint picker** — Phase 10 (v0.10).
- **STUN-блок toggle, biometrics, file picker** — Phase 10/11.

---

## Phase 11 Forward-Compatibility Notes

Phase 11 (UX-08, UX-09, Figma финал) может заменить:

| Component / token | Phase 11 enhancement |
|---|---|
| D-11 sheet icon `arrow.up.app.fill` | Custom branded illustration |
| Rules viewer category icons (block 🚫 / never ↩️ / always 🔒) | Custom SVG icons consistent with BBTB visual style |
| Banner orange tint | Possibly branded accent variant |
| DisclosureGroup chevron | Possibly custom chevron with animation polish |
| Force-update button | Could become FAB-style isolated card if Settings redesign moves it |
| Inline status row | Could replace с branded toast component (если SwiftUI ecosystem 2027+ предложит native API) |
| Rules viewer entry list | Could add search bar (Phase 11) |
| Domain/IP rendering | Could group long lists into «top 10 + см. ещё» disclosure pattern |

DesignSystem package (`DS.Spacing`, `DS.Radius`, `DS.Typography`) — token names остаются, значения переопределяются (особенно `md` from 12 → 16 per A-14).

---

## Security & UX Safety Notes (Phase 8 specific)

Phase 8 UI не вводит новых security threats (read-only viewer + idempotent force-update; нет user-controlled input в rules.json). Но UI-SPEC фиксирует следующие safety contracts:

| Сценарий | Контракт |
|---|---|
| Malicious rules.json with embedded HTML/script characters в domain entries | Все entry rendering через `Text(entry)` — SwiftUI auto-escapes. Никакого `Text(LocalizedStringKey(entry))` (которое бы интерпретировало markdown). Защита от injection: дефолтный SwiftUI behavior. |
| Extremely long domain string (single line) | `Text` wraps default; `.monospaced()` сохраняется per-character; `.textSelection(.enabled)` работает поверх wrap. Никаких overflow issues. |
| min_app_version > current AND user dismissed sheet AND кэш правил поменялся и снова требует update | Persistent banner показывает чтоблеtsync notice; sheet **может** re-trigger если value increased again per A-08. |
| User opens AdvancedSettingsView while rules fetch is mid-flight | UI показывает stale snapshot до завершения fetch; force-update button shows `.idle` (стоит cooldown timer считать «после первого ручного fetch»; auto background fetch не активирует UI cooldown). После fetch завершения `@Published rulesSnapshot` обновляется → UI auto-refreshes. |
| TestFlight URL not yet known (Phase 12 deferred) | D-11 sheet button could open fallback URL `https://testflight.apple.com/join/PLACEHOLDER` либо disabled с copy «Скоро». **Decision deferred to Phase 12 prerequisite memory `project_phase12_distribution_creds_prerequisite.md`** — Phase 8 implementation hardcodes URL constant which Phase 12 populates with real invite token. UI contract: button always present, even if URL points to placeholder. |
| Force-update tap during VPN connecting | Fetch goes through системный интернет (не tunnel) если VPN еще не established; через tunnel если established. Phase 6 reachability invariants сохраняются. UI behavior identical regardless of tunnel state. |

---

## Checker Sign-Off

(Адаптировано к SwiftUI native стеку — не shadcn.)

- [ ] Dimension 1 Copywriting: PASS — все user-facing строки определены в §Copywriting + §Layout (включая ~30 новых L10n key для RULES-09/RULES-10/D-11)
- [ ] Dimension 2 Visuals: PASS — layout композиция Rules section + D-11 sheet + persistent banner полностью специфицирована в §Layout Specifications
- [ ] Dimension 3 Color: PASS — 60/30/10 распределение наследуется из Phase 3; новые category-specific tints (block/never/always) явно перечислены в §Color; accent reserved-for list ограничен 4 элементами
- [ ] Dimension 4 Typography: PASS — **4 роли** (title/body/subheadline/caption), **2 веса** (.regular/.semibold) — наследуется из Phase 3 §8.4 без расширения; .monospaced() как modifier, не новая роль
- [ ] Dimension 5 Spacing: PASS — строгий 8-point grid {4, 8, 16, 24, 32, 48, 64} в §Spacing Scale, все pt значения кратны 4
- [ ] Dimension 6 Registry Safety: **not applicable** (SwiftUI native + SF Symbols, нет third-party registries)
- [ ] Dimension 7 Accessibility: PASS — labels/hints/values + Dynamic Type AX5 + Reduce Motion + announcements в §Accessibility
- [ ] Dimension 8 Platform parity: PASS — iOS vs macOS отличия в §Responsive Behavior (sheet sizing 440×320, всё остальное shared)

**Approval:** pending — ждёт `gsd-ui-checker`.

---

*Phase: 8-rules-engine-split-tunneling*
*UI-SPEC drafted: 2026-05-15 (autonomous, gsd-ui-researcher --auto)*
*Source decisions: CONTEXT.md D-01..D-13 (in-scope UI surface = D-10/D-11/RULES-09/RULES-10)*
*Pre-populated from: CONTEXT.md (4 area decisions + auxiliary defaults), Phase 3 UI-SPEC §8 (DesignSystem tokens normalized 8-point grid), Phase 6 SettingsFeature codebase (AdvancedSettingsView pattern, AdBlockToggleSection/AutoReconnectToggleSection structure, ReconnectBanner orange-tint style)*
*Inferred decisions (20 assumptions A-01..A-20) documented in §<assumptions> block for planner visibility*
*Downstream consumers: `gsd-ui-checker` (8-dimension validation), `gsd-planner` (W1-W3 task breakdown — RulesViewerSection component + ForceUpdateRulesButton + MinAppVersionSheet + ViewModel wiring + L10n key set additions), `gsd-executor` (visual source of truth), `gsd-ui-auditor` (retrospective compliance check)*
