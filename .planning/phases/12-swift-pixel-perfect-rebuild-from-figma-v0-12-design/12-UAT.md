# Phase 12 — Visual UAT (Real Device)

**Date started:** 2026-05-16
**Tester:** _______
**Build:** BBTB main HEAD @ commit `37a7ba1` (Phase 12 hardening + UAT plan)
**Device model:** _______ (e.g. iPhone 16 Pro / iPhone 15 / etc.)
**iOS version:** _______ (iOS 18.x / 19.x / 26.x)
**Mode:** ☐ Dark / ☐ Light / ☐ both

> **Зачем real device, а не simulator:** Network Extension (VPN tunnel)
> на simulator работает только частично — Connecting/Connected/Error states
> требуют actual outbound socket flow. На device — честный тест полного UX.
> iOS 26 Liquid Glass + Phosphor icons тоже рендерятся аутентично только
> на железе.

---

## Preparation

### 1. Prerequisites (one-time setup)

- Apple Developer Program subscription активна ($99/год). Personal Apple
  ID free tier НЕ даст Network Extension entitlement.
- Apple ID logged in: **Xcode → Settings → Accounts**, верифицируй
  что team есть в списке.
- iPhone подключён к Mac (USB cable или Wi-Fi pairing если настраивал раньше).
- Device registered в Apple Developer team (обычно auto при первом Run).

### 2. Build & install via Xcode UI (recommended)

1. Открой `/Users/vergevsky/ClaudeProjects/VPN/BBTB/BBTB.xcworkspace` в Xcode.
2. Top toolbar → **Scheme = BBTB** → **Destination = твой iPhone** (выбери из
   dropdown; должен показать имя устройства, не «Any iOS Device»).
3. ⌘B (Build) → дождись `Build Succeeded` (cold build ~3-5 min из-за
   libbox + Phosphor SPM).
4. ⌘R (Run) → Xcode signs, installs, launches на device.
5. **Первый раз** — на iPhone:
   - Settings → General → VPN & Device Management → Developer App →
     твой Apple ID team → **Trust**
   - Verify App (если требуется) → ⌘R повторно в Xcode

### 3. Build & install via CLI (alternative)

```bash
# 1. Узнать UDID + name устройства
xcrun devicectl list devices

# 2. Build для iOS device target
cd /Users/vergevsky/ClaudeProjects/VPN/BBTB
xcodebuild -workspace BBTB.xcworkspace -scheme BBTB \
  -destination 'platform=iOS,name=<твой-iPhone-name>' \
  -allowProvisioningUpdates \
  -configuration Debug build

# 3. Install на устройство
APP_PATH=$(find /Users/vergevsky/Library/Developer/Xcode/DerivedData/BBTB-* \
  -path '*/Build/Products/Debug-iphoneos/BBTB.app' -type d | head -1)
xcrun devicectl device install app --device <UDID> "$APP_PATH"

# 4. Запуск (или просто tap на BBTB icon на iPhone)
xcrun devicectl device process launch --device <UDID> app.bbtb.client.ios
```

### 4. Sample VLESS Reality config

На iPhone скопируй один рабочий VLESS Reality URL — обычно через BBTB
Telegram-бота, mail или Notes. Формат:

```
vless://<uuid>@<host>:<port>?security=reality&flow=xtls-rprx-vision&fp=chrome&pbk=<public-key>&sni=<sni-domain>&sid=<short-id>&type=tcp#<server-name>
```

**Где взять:** свой production-провайдер (если есть) ИЛИ тестовый сервер
из BBTB Telegram-бота `@bring_back_the_bug_test_bot` (если он у тебя).

Скопируй URL в iOS clipboard (long-press → Copy) перед тестом Empty Home /
Onboarding paste flow.

### 5. Reset state for clean run (optional)

**Полный wipe (тестировать с нуля включая Onboarding):**
- iPhone → long-press BBTB icon → Remove App → Delete App
- Xcode → ⌘R → fresh install → Onboarding появится автоматически

**Точечный reset только `hasShownOnboarding` (сохраняет imported конфиги):**
- На iPhone нет defaults CLI; либо delete app, либо в коде временно сбросить
  флаг через debug build.

**Pro tip:** для UAT каждого экрана не обязательно reset — переходи между
states через UI: Empty → Disconnected (import) → Connecting (tap СТАРТ) →
Connected → Disconnect → Error (kill internet + tap) → etc.

### 6. Device-specific UAT setup

- **Dark/Light mode** — iPhone Settings → Display & Brightness → Dark/Light.
  Тестируй оба mode.
- **Reduce Motion** — Settings → Accessibility → Motion → Reduce Motion ON
  для Screen 4.5 (BBTBSpinner pulsating opacity fallback).
- **VoiceOver** — Settings → Accessibility → VoiceOver ON (triple-click
  Home/Side button quick toggle если настроен).
- **Dynamic Type** — Settings → Display → Text Size → max slider.

---

## Test Matrix

Чек: ✅ pass / ❌ fail / ➖ skipped

### Screen 1: Onboarding (Figma `3062:307`)

**Trigger:** fresh install OR `defaults delete ... hasShownOnboarding`

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 1.1 | Skip X кнопка top-right (Phosphor xmark, не SF Symbol — но SF здесь ok, см. notes) | top-right | |
| 1.2 | Hero "Интернет, каким он " (textPrimary white) + "должен быть" (accent green) | 40pt Expanded Semibold, left-aligned | |
| 1.3 | Subtitle «Добавьте конфигурацию» (tip text 10pt Light) над CTAs | center | |
| 1.4 | Primary CTA «Добавить из буфера» (accent green pill, alwaysWhite text) | RoundedRect 32pt corner | |
| 1.5 | Secondary CTA «Сканировать QR-код» (textPrimary fill, textInverse text) | RoundedRect 32pt corner | |
| 1.6 | Buttons gap = 12pt (DS.Spacing.md); tip→CTAs gap = 28pt | — | |
| 1.7 | Background = canvas (#000 Dark / #FFF Light) | — | |
| 1.8 | Tap «Добавить из буфера» с пустым clipboard → alert "Буфер пуст" | — | |
| 1.9 | Tap Skip X → переход на Empty Home (НЕ Onboarding повторно) | — | |

### Screen 2: Empty Home (Figma `3115:325`)

**Trigger:** `hasShownOnboarding = true` AND `supported.isEmpty`

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 2.1 | TopBar: ≡ Phosphor List Bold left + ➕ Phosphor Plus Bold right (БЕЗ circle backdrop) | naked glyphs | |
| 2.2 | Hero «Нет конфигураций» 16pt Semibold center | textPrimary | |
| 2.3 | Subtitle «Добавьте конфигурацию с помощью кнопок ниже» 10pt Light | center, wrap | |
| 2.4 | Primary CTA «Добавить из буфера» (accent green pill) | RoundedRect 32pt | |
| 2.5 | Secondary CTA «Сканировать QR-код» (white pill в Dark / black в Light) | RoundedRect 32pt | |
| 2.6 | Footer "Сервер: Авто" — **отсутствует** (per UX fix `23cdabd`) | — | |
| 2.7 | Tap ≡ → открывает Settings | — | |
| 2.8 | Tap ➕ → menu с 3 пунктами (QR / Clipboard / File) | — | |

### Screen 3: Home Disconnected / .idle (Figma `3043:341`)

**Trigger:** clipboard содержит valid VLESS Reality URL → Empty Home → tap «Добавить из буфера» → state переходит в .idle

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 3.1 | TopBar identical Empty Home (≡ + ➕) | — | |
| 3.2 | ConnectionButton 280×280 Circle, controlIdle bg (#222 Dark / lighter Light) | — | |
| 3.3 | Текст «СТАРТ» 48pt Expanded **Bold**, textPrimary (white Dark / black Light) | center | |
| 3.4 | Footer "Сервер: Авто" 12pt Expanded Semibold textPrimary (или server name если выбран) | bottom | |
| 3.5 | Tap "Сервер: Авто" → открывает ServerListSheet | — | |
| 3.6 | НЕТ external ConnectionTimer / StatusPill вверху | per `bd9f8c2` | |

### Screen 4: Home Connecting (Figma `3047:538`)

**Trigger:** tap СТАРТ → ~2-5 секунд connecting state

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 4.1 | Circle clear fill (transparent) + inset stroke ring 6pt controlIdle | hollow ring | |
| 4.2 | Rotating gradient arc spinner ON TOP of static ring (same radius) | loading wheel | |
| 4.3 | Текст «подключение» 16pt Semibold center, textPrimary | — | |
| 4.4 | Spinner вращается smoothly (1.2s/full rotation linear) | — | |
| 4.5 | При Reduce Motion (Settings → Accessibility → Motion → Reduce Motion ON) — pulsating opacity 0.6↔1.0 cycle 1.0s | UI-SPEC §3.8 | |
| 4.6 | Footer "Сервер: <name>" остаётся видимым | — | |
| 4.7 | Tap кнопки во время connecting — disabled (gracefully) | — | |

### Screen 5: Home Connected (Figma `3047:598`)

**Trigger:** Connecting → tunnel established → state .connected

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 5.1 | Circle accent green fill (#14664B) | — | |
| 5.2 | «подключен» 16pt Semibold @ top (y≈-48.5 от center), alwaysWhite | inside Circle | |
| 5.3 | Inline timer HH:MM:SS 32pt Semibold @ center, monospaced digits, alwaysWhite | counts up | |
| 5.4 | «нажми чтобы отключиться» 10pt Light @ bottom (y≈+42), alwaysWhite | hint text | |
| 5.5 | Timer тикает каждую секунду без visual jitter | — | |
| 5.6 | Footer "Сервер: <name>" 12pt Semibold textPrimary | — | |
| 5.7 | Tap кнопки → возврат в .idle (timer останавливается) | — | |
| 5.8 | Кнопка прыгает при tap (sensoryFeedback haptic light) | iOS only | |

### Screen 6: Home Error (Figma `3047:568`)

**Trigger:** интернет выключен / invalid server → tunnel fails

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 6.1 | Circle error red fill (#661414) | — | |
| 6.2 | «ошибка» 16pt Semibold @ center, alwaysWhite | inside Circle | |
| 6.3 | «нажми чтобы переподключиться» 10pt Light @ bottom (y≈+42), alwaysWhite | — | |
| 6.4 | **Floating banner** «Ошибка подключения» сверху экрана (accent green pill 10pt) | overlay, не сдвигает контент | |
| 6.5 | Banner живёт МЕЖДУ ≡ и ➕ иконками (80pt horizontal padding) — не перекрывает их | — | |
| 6.6 | Banner appears smoothly с slide-in (top) + opacity transition | 0.25s easeInOut | |
| 6.7 | Tap кнопки → re-attempt connection (state → .connecting → ...) | — | |
| 6.8 | Banner исчезает при state change | — | |

### Screen 7: Servers — Selected variant (Figma `3064:350`)

**Trigger:** Disconnected → tap "Сервер: <name>" → ServerListSheet → выбрать конкретный сервер

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 7.1 | Sheet header «Список серверов» 16pt Semibold textPrimary | top-left | |
| 7.2 | Refresh Phosphor ArrowClockwise top-right (iconSecondary, 18pt) | — | |
| 7.3 | Header padding-top = 32pt (НЕ прилип к верху) | — | |
| 7.4 | AutoCell «Автовыбор по скорости» 12pt Regular + Phosphor Lightning Bold | bg = surfaceHeader (НЕ accent) | |
| 7.5 | Section card «Подписка / Конфигурации» surfaceSunken + cornerRadius 24 | — | |
| 7.6 | Section header: Phosphor CaretDown 20pt iconSecondary + subscription name 12pt Regular textPrimary | surfaceHeader bg | |
| 7.7 | **Selected** ServerRow: accent green bg + alwaysWhite name + iconMuted Globe + iconMuted ping | inside section | |
| 7.8 | Non-selected rows: Phosphor Globe iconSecondary + name 12pt Regular textPrimary + ping textSecondary с tier colors | — | |
| 7.9 | Tap CaretDown → секция collapse'ится (rows скрываются), icon поворачивается -90° CCW | smooth 0.2s | |
| 7.10 | Pull-to-refresh → spinning indicator + fetch | — | |
| 7.11 | Bottom края sheet БЕЗ темной полосы (per `ignoresSafeArea(.bottom)` fix) | — | |
| 7.12 | Tap ServerRow chevron → push ServerDetailView (без layout jump) | — | |
| 7.13 | Удалить ВСЕ серверы (long-press → Delete) → закрыть sheet → MainScreen показывает **EmptyStateCard** | per UX fix `25bfda6` | |

### Screen 8: Servers — Auto variant (Figma `3064:1579`)

**Trigger:** ServerListSheet → tap AutoCell → mode = auto

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 8.1 | AutoCell **active**: accent green bg + alwaysWhite text + alwaysWhite Lightning | per `9a29eba` | |
| 8.2 | Все ServerRow в default state (не selected) | — | |
| 8.3 | Footer "Сервер: Авто" на главном экране после dismiss | — | |
| 8.4 | Tap СТАРТ → подключается к лучшему по latency серверу | — | |

### Screen 9: ServerDetailView

**Trigger:** ServerListSheet → ServerRow chevron tap

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 9.1 | Inline TopBar: Phosphor CaretLeft back + server.name 16pt Semibold | per BBTBTopBar | |
| 9.2 | **НЕТ layout jump** при push (sheet header → detail TopBar в одной позиции) | per `a704cb8` | |
| 9.3 | Tap back → возврат на ServerListSheet (тоже без jump) | — | |
| 9.4 | Form sections: General / Protocol / Transport — стандартные iOS Form rows | — | |

### Screen 10-12: Settings / Help / AdvancedSettings

**Trigger:** Empty Home → tap ≡ → Settings → tap rows

| # | Что проверить | Figma reference | ✅/❌/Note |
|---|---|---|---|
| 10.1 | SettingsView: BBTBTopBar(title: «Настройки», onBack: dismiss) | per `0ce1daa` | |
| 10.2 | AdvancedSettingsView: BBTBTopBar(title: «Дополнительные») | — | |
| 10.3 | HelpView: BBTBTopBar(title: «Помощь») | — | |
| 10.4 | Все back buttons работают без layout jump | — | |
| 10.5 | НЕТ native nav bar — только inline BBTBTopBar | per migration | |

---

## Accessibility checks (UI-SPEC §3)

| # | Что проверить | ✅/❌/Note |
|---|---|---|
| A.1 | VoiceOver: «BBTB.ConnectionButton», «BBTB.Onboarding.PasteButton», etc. читаются | |
| A.2 | Reduce Motion: BBTBSpinner pulsating opacity 0.6↔1.0 вместо rotation | |
| A.3 | Color contrast 4.5:1 на текстах (Dark + Light) — controlIdle/textPrimary, accent/alwaysWhite, error/alwaysWhite | |
| A.4 | Tap targets ≥44pt — все Phosphor icons 18-24pt с buttonStyle `.plain` + достаточный padding | |
| A.5 | Dynamic Type на body text (Settings → Display → Text Size) — текст scaleит соответственно | |

---

## Network resilience (real-device only — НЕ работает на simulator)

| # | Что проверить | ✅/❌/Note |
|---|---|---|
| N.1 | Connecting → real handshake VLESS Reality + tls inner channel | |
| N.2 | Connected → realtime traffic через tunnel (Wi-Fi → tunnel IP via [whatismyipaddress.com](https://whatismyipaddress.com/) — должен показывать server IP, НЕ ISP) | |
| N.3 | Network change (Wi-Fi → 4G/LTE) → auto-reconnect или graceful fallback per Phase 6 | |
| N.4 | Airplane Mode toggle → tunnel paused, reconnect при возврате интернета | |
| N.5 | Background → foreground (lock + unlock) → tunnel survives, timer continues | |
| N.6 | Force quit app (swipe up) → tunnel выключается (on-demand НЕ держит без app) | |

---

## Final signoff

- **Verdict:** ☐ approved / ☐ retry / ☐ borderline-accept
- **Failed tests (IDs):** _______
- **Notes:** _______
- **Tester signature + date:** _______
- **Device + iOS version:** _______

После UAT — заполни Final signoff блок, скриншоты failed tests положи в
`.planning/phases/12-swift-pixel-perfect-rebuild-from-figma-v0-12-design/uat-evidence/`,
закоммить как `docs(12): UAT signoff — N/M pass`.
