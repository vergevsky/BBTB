---
phase: 2
slug: trojan-import-flow
status: draft
shadcn_initialized: false
preset: not applicable (SwiftUI native, Apple platforms)
created: 2026-05-12
---

# Phase 2 — UI Design Contract

> Контракт визуала и взаимодействий для версии v0.2 (Trojan + универсальный импорт). Промежуточный шаг к финальному Phase 11 UX (`wiki/ux-specification.md`).
> Платформа: SwiftUI native iOS 17+/macOS 14+. Никакого web/React стека — таблицы шкал ниже выражены в pt и сопоставлены с системными `Font.TextStyle` / SF Symbols.
> Все component identifiers, SF Symbols, UserDefaults keys — English. Все пользовательские строки — Russian + English через `Localizable.xcstrings`.

---

## 1. Information Architecture

### 1.1 Карта экранов

```
RootScene
├─ NavigationStack (iOS) / Window (macOS)
│   └─ MainScreenView ............................................. главный экран
│       ├─ NavigationLink → SettingsView (push iOS / Settings Scene macOS)
│       ├─ Menu "+" → action: importFromPasteboard()  ............. без отдельного экрана
│       └─ Menu "+" → action: presentQRScanner()  → QRScannerView (sheet / fullScreenCover)
│
├─ Settings Scene (macOS only) ................................... Cmd+, → SettingsView
│
└─ MenuBarExtra (macOS only) ..................................... наследие Phase 1 UX-07
    └─ открытие main window / connect-disconnect
```

### 1.2 Граф навигации

| Откуда | Куда | Trigger | Презентация |
|---|---|---|---|
| MainScreen | SettingsView | tap иконки меню (top bar leading) | NavigationStack push (iOS) / новое окно (macOS дублирующий entry) |
| MainScreen | SettingsView | Cmd+, | Settings Scene (macOS only) |
| MainScreen | Menu sheet | tap иконки `+` (top bar trailing) | SwiftUI `Menu` (нативный popup) |
| Menu sheet | importFromPasteboard | tap «Добавить из буфера» | inline action — без UI; progress / alert по результату |
| Menu sheet | QRScannerView | tap «Сканировать QR» | `.fullScreenCover` (iOS) / `.sheet` (macOS) |
| QRScannerView | dismiss + import | детектирование QR | sheet dismiss → import pipeline |
| QRScannerView | dismiss | Cancel | sheet dismiss без действий |

### 1.3 Состояния MainScreen

```
ConnectionState (наследовано из Phase 1, ConnectionState.swift — не меняется):
  .empty                   ← карточка empty-state, никаких других элементов
  .idle                    ← полный layout, таймер 00:00:00, pill «Отключено», power серый
  .connecting              ← таймер 00:00:00, pill «Подключение», power вращается
  .connected(since: Date)  ← таймер от since, pill «Подключено», power акцентный
  .error(message: String)  ← таймер 00:00:00, pill «Ошибка», power красный, сообщение
```

Top bar остаётся видимым во **всех** состояниях (включая `.empty`).

---

## 2. MainScreen — layout с конфигом (idle/connecting/connected/error) [D-09]

### 2.1 Вертикальная композиция

```
┌────────────────────────────────────────────────────┐
│  [≡]                                          [+]  │  ← TopBar (toolbar)
│                                                    │
│ ┌────────────────────────────────────────────────┐ │
│ │  Переподключитесь для применения изменений   ✕ │ │  ← ReconnectBanner (conditional)
│ └────────────────────────────────────────────────┘ │
│                                                    │
│             Время подключения                      │  ← опциональный label
│                  00:00:00                          │  ← ConnectionTimer
│                                                    │
│              ┌─────────────┐                       │
│              │ Отключено   │                       │  ← StatusPill (capsule, без chevron)
│              └─────────────┘                       │
│                                                    │
│                                                    │
│                  ┌─────────┐                       │
│                  │         │                       │
│                  │    ⏻    │                       │  ← ConnectionButton (~140 pt iPhone)
│                  │         │                       │
│                  └─────────┘                       │
│                                                    │
│                                                    │
│              Сервер: Авто                          │  ← ServerLineView (без chevron)
│                                                    │
└────────────────────────────────────────────────────┘
```

### 2.2 TopBar (общий для всех состояний)

| Slot | Контент | Action | SF Symbol | Accessibility key |
|---|---|---|---|---|
| `.topBarLeading` | NavigationLink | push SettingsView | `line.3.horizontal` | `a11y.menu_open_settings` |
| `.principal` | (пусто, нет app name) | — | — | — |
| `.topBarTrailing` | `Menu` с двумя пунктами | popup | `plus` | `a11y.menu_add_config` |

Меню `+` содержит **ровно два пункта** (порядок строго):
1. «Сканировать QR» — SF Symbol `qrcode.viewfinder`, action: `presentQRScanner()`
2. «Добавить из буфера» — SF Symbol `doc.on.clipboard`, action: `importFromPasteboard()`

IMP-03 (file picker) в это меню **не добавляется** — отложено в Phase 11.

### 2.3 ReconnectBanner [D-14]

- Видимость: `viewModel.needsReconnectForKillSwitch == true` AND туннель активен (state == `.connected`).
- Стиль: горизонтальная плашка под TopBar, фон `Color.orange.opacity(0.15)`, текст `Color.primary`, скругление 12 pt.
- Контент: SF Symbol `arrow.triangle.2.circlepath` + текст `banner.reconnect_needed` + кнопка `✕` (`xmark`) для dismiss.
- Tap по плашке (кроме крестика) — disabled на v0.2 (auto-reconnect отказались, см. CONTEXT D-14).

### 2.4 ConnectionTimer

- Шрифт: `.system(.largeTitle, design: .monospaced)`, `.monospacedDigit()`.
- Формат: `HH:MM:SS`. В `.idle` / `.connecting` / `.error` — `00:00:00` (рендерим из `nil`-значения `since`).
- Опциональный label сверху мелким шрифтом `.caption2` foreground `.secondary` — текст `timer.label = "Время подключения"`. Видим всегда когда таймер показан.
- В Phase 1 `ConnectionTimer.init(since: Date)` — non-optional. **Меняется** на `init(since: Date?)` (см. §7). Когда `since == nil` → отрисовка `00:00:00` без подписки на `Timer.publish`.

### 2.5 StatusPill (rename из `StatusBadge`)

- Capsule shape (`RadiusToken.pill = 999 pt → Capsule()`).
- Padding: 16 pt horizontal, 8 pt vertical.
- Шрифт: `.system(.subheadline, design: .rounded)`, `.fontWeight(.medium)`.
- **Без disclosure arrow** (D-09, Q2.4).
- Tap **disabled** (информационный элемент).

| state | Background | Foreground | Текст | Localization key |
|---|---|---|---|---|
| `.empty` | (компонент скрыт) | — | — | — |
| `.idle` | `Color(.tertiarySystemFill)` | `.secondary` | «Отключено» | `status.disconnected` |
| `.connecting` | `Color.orange.opacity(0.18)` | `Color.orange` | «Подключение» | `status.connecting` |
| `.connected` | `Color.green.opacity(0.18)` | `Color.green` | «Подключено» | `status.connected` |
| `.error` | `Color.red.opacity(0.18)` | `Color.red` | «Ошибка» | `status.error` |

### 2.6 ConnectionButton (refactor из Phase 1)

- Диаметр: `140 pt` на iPhone (compact), `160 pt` на iPad/macOS (regular).
- Shape: `Circle()`.
- Внутренняя SF Symbol: `power` (центрированный), size `.system(size: 56)` iPhone / `.system(size: 64)` iPad/macOS, weight `.medium`, foreground `Color.white`.
- `symbolEffect(.bounce, value: state)` сохраняется из Phase 1.

| state | Fill | Анимация | Tap action |
|---|---|---|---|
| `.empty` | (компонент скрыт) | — | — |
| `.idle` | `Color(.systemGray)` | none | `connect()` |
| `.connecting` | `Color.orange` | вращение (см. §10 Phase 11 forward-compat — анимация UX-08) | disabled |
| `.connected` | `Color.accentColor` | none | `disconnect()` |
| `.error` | `Color.red.opacity(0.85)` | none | `connect()` (retry) |

Note: `.empty` ветка остаётся в `disabled` логике как safety/future-proof, но в empty-state компонент **не рендерится вообще** (см. §3).

### 2.7 ServerLineView (новый) [D-11]

- Расположение: внизу карточки, ~24 pt от bottom safe area.
- Шрифт: `.system(.callout, design: .rounded)`, `.fontWeight(.regular)`.
- Foreground: `.secondary`.
- Composition: `"Сервер: " + name`, без иконок и без chevron `›` на v0.2 (chevron возвращает Phase 3).
- Tap **disabled** (полный server-list — Phase 3 SRV-*).

Контент `name`:
- Если в активном пуле **один** outbound → `name = ServerConfig.remark` из URI fragment (например `Латвия — VLESS`).
- Если **несколько** outbound'ов в `urltest` пуле → `name = L10n.serverAuto` («Авто»).

Localization:
- `server.label = "Сервер:"` (ru) / `"Server:"` (en).
- `server.auto = "Авто"` (ru) / `"Auto"` (en).

---

## 3. MainScreen — empty-state [D-10]

### 3.1 Layout

```
┌────────────────────────────────────────────────────┐
│  [≡]                                          [+]  │  ← TopBar остаётся видимым
│                                                    │
│                                                    │
│            ┌──────────────────────────┐            │
│            │                          │            │
│            │           📥             │            │  ← Icon (SF Symbol `tray`)
│            │                          │            │
│            │   Нет конфигурации       │            │  ← Title
│            │                          │            │
│            │  Добавьте первую         │            │  ← Subtitle (multi-line)
│            │  конфигурацию с помощью  │            │
│            │  кнопок ниже             │            │
│            │                          │            │
│            │ ┌──────────────────────┐ │            │  ← Primary button
│            │ │  Добавить из буфера  │ │            │     (filled accent)
│            │ └──────────────────────┘ │            │
│            │                          │            │
│            │ ┌──────────────────────┐ │            │  ← Secondary button
│            │ │ Отсканировать QR-код │ │            │     (outlined)
│            │ └──────────────────────┘ │            │
│            │                          │            │
│            └──────────────────────────┘            │
│                                                    │
└────────────────────────────────────────────────────┘
```

### 3.2 EmptyStateCard — спецификация компонента

| Элемент | Свойство | Значение |
|---|---|---|
| Карточка | shape | `RoundedRectangle(cornerRadius: 16)` |
| Карточка | background | `Color(.secondarySystemBackground)` (iOS) / `Color(NSColor.controlBackgroundColor)` (macOS) |
| Карточка | padding (внутренний) | 24 pt со всех сторон |
| Карточка | max-width | 360 pt (Read-screen friendly на iPad/macOS) |
| Карточка | horizontal alignment | `.center` от parent |
| Icon | SF Symbol | `tray` (Claude-default — финал Phase 11) |
| Icon | size | `.system(size: 56)` |
| Icon | foreground | `.secondary` |
| Icon | spacing-below | 16 pt |
| Title | text | `L10n.emptyTitle` = «Нет конфигурации» |
| Title | font | `.system(.title3, design: .rounded).bold()` |
| Title | spacing-below | 8 pt |
| Subtitle | text | `L10n.emptySubtitle` = «Добавьте первую конфигурацию с помощью кнопок ниже» |
| Subtitle | font | `.system(.subheadline)` |
| Subtitle | foreground | `.secondary` |
| Subtitle | alignment | `.center`, multiline |
| Subtitle | spacing-below | 24 pt |
| Primary button | style | `.borderedProminent` + `.controlSize(.large)` |
| Primary button | label | `L10n.actionImportFromClipboard` = «Добавить из буфера» |
| Primary button | spacing-below | 12 pt |
| Secondary button | style | `.bordered` + `.controlSize(.large)` |
| Secondary button | label | `L10n.actionScanQR` = «Отсканировать QR-код» |

### 3.3 Видимость других компонентов в empty-state

| Компонент | Visible? |
|---|---|
| TopBar (menu + `+`) | **Yes** (иконка `+` дублирует функцию карточки) |
| ReconnectBanner | No (не имеет смысла без конфига) |
| ConnectionTimer | No |
| Timer label | No |
| StatusPill | No |
| ConnectionButton | No |
| ServerLineView | No |

---

## 4. SettingsView (новый) [D-12, D-13, D-14]

### 4.1 Структура

```
┌────────────────────────────────────────────────────┐
│ < Назад           Настройки                        │  ← NavigationBar (iOS push)
├────────────────────────────────────────────────────┤
│                                                    │
│  БЕЗОПАСНОСТЬ                                      │  ← Section header
│  ┌──────────────────────────────────────────────┐  │
│  │  Kill Switch                            [ ]  │  │  ← Toggle row
│  └──────────────────────────────────────────────┘  │
│  Блокирует весь интернет при разрыве VPN —         │  ← Section footer
│  защищает от случайной утечки трафика.             │
│                                                    │
└────────────────────────────────────────────────────┘
```

### 4.2 Контракт

| Элемент | Свойство | Значение |
|---|---|---|
| Container | type | `Form` (iOS) / `Form` в `Settings { ... }` Scene (macOS) |
| Title | text | `L10n.settingsTitle` = «Настройки» |
| Title | placement | `.navigationBarTitleDisplayMode(.large)` (iOS) |
| Section header | text | `L10n.settingsSecuritySection` = «Безопасность» (UPPERCASE на iOS автоматически) |
| Toggle row label | text | `L10n.killSwitchLabel` = «Kill Switch» |
| Toggle binding | source | `@AppStorage("app.bbtb.killSwitchEnabled") var killSwitchEnabled = true` |
| Toggle default | value | `true` (наследуется от Phase 1 KILL-01) |
| Toggle style | platform | `SwitchToggleStyle` (default iOS) / `.checkbox` style ok на macOS |
| Toggle confirmation | — | **none** (D-13 — без alert) |
| Section footer | text | `L10n.killSwitchFooter` = «Блокирует весь интернет при разрыве VPN — защищает от случайной утечки трафика.» |
| Section footer | font | `.caption` (system default Form footer) |
| Section footer | foreground | `.secondary` |

### 4.3 Side-effect contract

При изменении значения `killSwitchEnabled`:

```swift
.onChange(of: killSwitchEnabled) { _, _ in
    if tunnelController.isTunnelActive {
        mainScreenViewModel.needsReconnectForKillSwitch = true
    }
    // Применение к profile — на следующем connect через ConfigImporter.provisionTunnelProfile
    // см. CONTEXT D-14, integration points
}
```

Никакого immediate disconnect/reconnect. Никаких overlay-ов. Только баннер на MainScreen (см. §2.3).

### 4.4 macOS отличия

- На macOS — Settings Scene открывается Cmd+,, не push.
- На macOS дублирующий entry-point через ту же кнопку меню в TopBar → `openSettings` action (`@Environment(\.openSettings)` если iOS 17 / macOS 14+).
- MenuBarExtra (UX-07 carry-forward) **не получает** Settings entry на v0.2 — остаётся как Phase 1 (только connect/disconnect/open window). Settings из MenuBar — Phase 4/11.

---

## 5. QRScannerView (новый)

### 5.1 Презентация

| Платформа | Тип | Размер |
|---|---|---|
| iOS | `.fullScreenCover` | full-screen |
| macOS | `.sheet` | 480×640 pt (resizable=false) |

### 5.2 Layout

```
┌────────────────────────────────────────────────────┐
│ Отменить        Сканирование QR-кода               │  ← Toolbar
├────────────────────────────────────────────────────┤
│                                                    │
│                 (live camera preview)              │
│                                                    │
│           ┌──────────────────────────┐             │
│           │                          │             │
│           │                          │             │
│           │  (square viewfinder)     │             │  ← overlay cutout
│           │                          │             │
│           │                          │             │
│           └──────────────────────────┘             │
│                                                    │
│        Наведите камеру на QR-код                   │  ← hint label
│                                                    │
└────────────────────────────────────────────────────┘
```

### 5.3 Контракт

| Элемент | Свойство | Значение |
|---|---|---|
| Camera backend | API | `AVCaptureSession` + `AVCaptureMetadataOutput` |
| Detected types | metadataObjectTypes | `[.qr]` (других не требуется на v0.2) |
| Preview layer | aspect | `.resizeAspectFill`, centered |
| Viewfinder | shape | `Rectangle()` со скругленными углами 16 pt, semi-transparent border 2 pt белый |
| Viewfinder | size | 280×280 pt iPhone, 360×360 pt iPad |
| Toolbar leading | text | `L10n.qrCancel` = «Отменить» |
| Toolbar leading | action | dismiss sheet без действий |
| Toolbar principal | text | `L10n.qrTitle` = «Сканирование QR-кода» |
| Hint label | text | «Наведите камеру на QR-код» — `L10n.qrHint` |
| Hint label | font | `.system(.callout)`, foreground `.white.opacity(0.9)` |

### 5.4 Detection flow

1. `AVCaptureMetadataOutput` находит `AVMetadataMachineReadableCodeObject` тип `.qr`.
2. Извлечь `stringValue`.
3. **iOS only:** `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` (buzz haptic).
4. Dismiss sheet.
5. Вызвать `ConfigImporter.import(rawInput: detectedText)` — тот же entry point что для pasteboard.
6. Результат обрабатывается как обычный import (progress overlay → success / error alert).

После dismiss `AVCaptureSession` останавливается (`session.stopRunning()`) в `.onDisappear`.

### 5.5 Permission denied state

Если `AVCaptureDevice.authorizationStatus(for: .video) == .denied`:

| Элемент | Контент |
|---|---|
| Презентация | alert (НЕ camera preview) |
| Title | `L10n.qrPermissionDeniedTitle` = «Нет доступа к камере» |
| Message | `L10n.qrPermissionDeniedMessage` = «BBTB нужен доступ к камере для сканирования QR-кодов.» |
| Primary button | `L10n.qrPermissionDeniedOpenSettings` = «Открыть настройки» → `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)` (iOS) / `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)` (macOS) |
| Cancel button | `L10n.actionCancel` = «Отмена» |

`Info.plist`:
- `NSCameraUsageDescription` (iOS+macOS) = «BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов.» (Claude-default — финал Phase 11)

---

## 6. Pasteboard import flow

### 6.1 Поведение

**Без отдельного UI** — direct action из меню `+` или primary button empty-state карточки.

```
tap «Добавить из буфера»
    ↓
ConfigImporter.import(rawInput: UIPasteboard.general.string)
    ↓
classify: URI / multi-URI / HTTP-URL (subscription / JSON-endpoint)
    ↓
[if HTTP-URL] progress overlay ......................... §6.2
    ↓
SwiftData persist + Keychain save + provisionTunnelProfile
    ↓
success alert / error alert ............................ §6.3
```

### 6.2 Progress overlay

Показывается **только** для HTTP-fetch (subscription URL или JSON endpoint).

| Элемент | Свойство | Значение |
|---|---|---|
| Презентация | `.overlay` over MainScreen, blur background `.regularMaterial` |
| Spinner | `ProgressView()` с style `.circular`, scale 1.5x |
| Label | text | `L10n.importProgress` = «Загрузка конфигурации…» |
| Label | font | `.system(.callout)` |
| Cancel | — | На v0.2 без cancel-кнопки (timeout 30s по умолчанию из `URLSession`). Phase 11 добавит cancel. |
| Dismissibility | none (модальный overlay) |

Появляется в момент классификации `case .httpURL`, исчезает по завершению `URLSession.data(from:)` (success или throw).

### 6.3 Alerts по результатам

| Случай | Title | Message | Localization keys |
|---|---|---|---|
| Success (N configs imported, M skipped as unsupported) | «Импорт завершён» | «Добавлено: \(N). Будут включены в следующих версиях: \(M).» (M=0 → строка опускается) | `import.success.title`, `import.success.message` |
| Empty pasteboard | «Буфер обмена пуст» | «Скопируйте ссылку на конфигурацию и попробуйте снова.» | `import.error.no_pasteboard` (наследие Phase 1) |
| Malformed input | «Не удалось распознать конфигурацию» | «Проверьте, что ссылка корректна и попробуйте снова.» | `import.error.malformed` (наследие Phase 1) |
| No supported configs found | «Нет поддерживаемых конфигураций» | «В источнике нет конфигураций, поддерживаемых на этой версии BBTB. Обновите приложение в следующих версиях.» | `import.error.no_supported_configs` |
| Network error (HTTP fetch failed) | «Ошибка сети» | «Не удалось загрузить конфигурацию: \(localizedDescription).» | `import.error.network` |
| Validation error (R1 reject) | «Конфигурация отклонена» | «Сервер вернул конфигурацию, нарушающую правила безопасности BBTB.» | `import.error.validation` |

Все alert'ы — один primary button «OK» (`L10n.actionOK`) который закрывает alert.

---

## 7. Component Inventory & Refactor Plan

### 7.1 Перепиcь Phase 1 components

| Файл | Действие | Что меняется |
|---|---|---|
| `MainScreenView.swift` | **rewrite** | новый layout (TopBar toolbar + EmptyStateCard branch + полный layout branch); удаляется header с app name и StatusBadge сверху |
| `StatusBadge.swift` | **rename → `StatusPill.swift`** | Capsule shape, размещение под power button (а не в header), без dot, с padded text внутри |
| `ConnectionButton.swift` | **modify** | диаметр 140/160 pt (Phase 1 был 200), fill colors по таблице §2.6 (Phase 1 idle был accent.opacity(0.85) — теперь `.systemGray`), accent перенесён на `.connected` |
| `ConnectionTimer.swift` | **modify** | `init(since: Date?)` вместо `init(since: Date)`; nil → render `"00:00:00"` без `Timer.publish` |
| `ImportFromClipboardButton.swift` | **delete** | заменяется `EmptyStateCard` |
| `ConnectionState.swift` | **no change** | enum cases сохраняются |
| `MainScreenViewModel.swift` | **modify** | добавить `@Published var needsReconnectForKillSwitch: Bool`, `func presentQRScanner()`, `func importFromPasteboard()` (уже есть); адаптировать под массив `ServerConfig` |

### 7.2 Новые компоненты (создаются с нуля в MainScreenFeature и SettingsFeature)

| Компонент | Файл | Public API |
|---|---|---|
| `EmptyStateCard` | `AppFeatures/MainScreenFeature/EmptyStateCard.swift` | `init(onImport: () -> Void, onScan: () -> Void)` |
| `ServerLineView` | `AppFeatures/MainScreenFeature/ServerLineView.swift` | `init(serverName: String?, isPool: Bool)` — если `isPool=true` → «Авто»; если `serverName=nil && !isPool` → не рендерится |
| `StatusPill` | `AppFeatures/MainScreenFeature/StatusPill.swift` | `init(state: ConnectionState)` |
| `ReconnectBanner` | `AppFeatures/MainScreenFeature/ReconnectBanner.swift` | `init(onDismiss: () -> Void)` |
| `TopBarToolbar` | inline в `MainScreenView.body` через `.toolbar { ToolbarItemGroup(...) }` — отдельного компонента не нужно | — |
| `SettingsView` | `AppFeatures/SettingsFeature/SettingsView.swift` (новый sub-module) | `init()` |
| `SettingsViewModel` | `AppFeatures/SettingsFeature/SettingsViewModel.swift` | `@AppStorage("app.bbtb.killSwitchEnabled") var killSwitchEnabled = true` |
| `KillSwitchToggle` | inline в `SettingsView` Form — отдельного компонента не нужно (просто `Toggle(...)`) | — |
| `QRScannerView` | `AppFeatures/MainScreenFeature/QRScannerView.swift` | `init(onScan: (String) -> Void, onCancel: () -> Void)` |
| `QRScannerCameraView` | `AppFeatures/MainScreenFeature/QRScannerCameraView.swift` (UIViewRepresentable / NSViewRepresentable wrapper над AVCaptureSession) | `init(onDetect: (String) -> Void)` |
| `ImportProgressOverlay` | `AppFeatures/MainScreenFeature/ImportProgressOverlay.swift` | `init(message: String)` |

### 7.3 Module boundaries

- `MainScreenFeature` остаётся главным entry point. Все новые UI-компоненты главного экрана сюда.
- **Новый sub-module:** `AppFeatures/Sources/SettingsFeature/` — содержит `SettingsView`, `SettingsViewModel`. SettingsFeature depend on `Localization`, `DesignSystem`, `KillSwitch` (для чтения текущего default), но **не** depend on `MainScreenFeature` (избежать кольцевой зависимости — баннер reconnect живёт через shared `MainScreenViewModel` ref, который передаётся через `@EnvironmentObject` из root App).
- `QRScannerView` и `QRScannerCameraView` — в `MainScreenFeature` (не в отдельный package на v0.2, чтобы не плодить модули; вынос — Phase 11 если потребуется).
- `MenuBarFeature` (macOS UX-07 carry-forward) — без изменений на v0.2.

---

## 8. Design Tokens (extend DesignSystem package)

Сейчас `DesignSystem/DesignSystem.swift` содержит только `DS.accent` и `DS.titleFont`. Phase 2 расширяет до полной шкалы.

### 8.1 Spacing scale (`DS.Spacing`)

| Token | Value | Usage |
|---|---|---|
| `xs` | 4 pt | inline padding, icon-to-text gaps |
| `sm` | 8 pt | compact spacing (title-to-subtitle) |
| `md` | 12 pt | between buttons в карточке |
| `lg` | 16 pt | внутренний padding pill / cards |
| `xl` | 24 pt | внутренний padding EmptyStateCard |
| `2xl` | 32 pt | между основными группами layout |
| `3xl` | 48 pt | вертикальные отступы между Timer / Pill / Button |

Все значения кратны 4 pt — соответствует Apple HIG 8-point grid (с допустимым 4 pt для tight spacing).

### 8.2 Corner radius scale (`DS.Radius`)

| Token | Value | Usage |
|---|---|---|
| `small` | 8 pt | inline inputs, small buttons |
| `card` | 12 pt | стандартные карточки, ReconnectBanner |
| `cardLarge` | 16 pt | EmptyStateCard, QRScannerView viewfinder |
| `button` | 12 pt | стандартные кнопки (system default `.bordered`/`.borderedProminent`) |
| `buttonLarge` | 24 pt | reserved для финального Phase 11 — не используется на v0.2 |
| `pill` | 999 pt → `Capsule()` | StatusPill |
| `circle` | use `Circle()` shape | ConnectionButton |

### 8.3 Color contract

60/30/10 распределение через системные colors (финальная палитра — Phase 11):

| Role | iOS | macOS | Usage |
|---|---|---|---|
| **Dominant (60%)** — surface | `Color(.systemBackground)` | `Color(NSColor.windowBackgroundColor)` | главный фон |
| **Secondary (30%)** — cards | `Color(.secondarySystemBackground)` | `Color(NSColor.controlBackgroundColor)` | EmptyStateCard, sections в Form |
| **Accent (10%)** | `Color.accentColor` (system blue по умолчанию — Phase 11 переопределит) | same | **зарезервирован для:** ConnectionButton в `.connected` state, primary buttons в EmptyStateCard и алёртах, NavigationLink chevrons (system-controlled) |
| **Destructive** | `Color.red` | same | ConnectionButton в `.error` state, error alert tint |
| **Success** | `Color.green` | same | StatusPill `.connected` |
| **Warning** | `Color.orange` | same | StatusPill `.connecting`, ReconnectBanner background |

**Accent reserved for** (явный список — никаких «all interactive elements»):
- `ConnectionButton` fill когда `state == .connected`
- Primary button в `EmptyStateCard` (через `.borderedProminent` который sample'ит accent)
- Primary action в alert по импорту
- NavigationBar tint (system)

Все остальные интерактивные элементы — system-default tint (что вне 10% accent rule: secondary buttons `.bordered` без явного tint, Form rows, Toggle off-state).

### 8.4 Typography scale (`DS.Typography`)

Сопоставление с системными `Font.TextStyle` (Dynamic Type compatible):

| Role | Style | Weight | Design | Usage |
|---|---|---|---|---|
| `display` | `.largeTitle` | `.medium` | `.monospaced` (для timer) | ConnectionTimer цифры |
| `title` | `.title3` | `.bold` | `.rounded` | EmptyStateCard title, SettingsView title (system) |
| `headline` | `.headline` | `.semibold` | `.default` | (зарезервирован, на v0.2 не используется) |
| `body` | `.body` | `.regular` | `.default` | body текст в alerts |
| `callout` | `.callout` | `.regular` | `.rounded` | ServerLineView, QR scanner hint |
| `subheadline` | `.subheadline` | `.medium` | `.rounded` | StatusPill text, EmptyStateCard subtitle |
| `caption` | `.caption` | `.regular` | `.default` | timer label «Время подключения», Form section footers |

Body line-height: системный (~1.4-1.5 у Dynamic Type). Не переопределяем.

### 8.5 ConnectionButton dimensions

| Platform | Diameter | Icon size |
|---|---|---|
| iPhone (compact) | 140 pt | 56 pt |
| iPad / macOS (regular) | 160 pt | 64 pt |

Определяется через `@Environment(\.horizontalSizeClass)`:
- `.compact` → 140/56
- `.regular` → 160/64

---

## 9. Localization Contract

### 9.1 Новые ключи (добавляются в `Localizable.xcstrings` + `L10n.swift`)

| Key | Russian | English |
|---|---|---|
| `empty.title` | Нет конфигурации | No configuration |
| `empty.subtitle` | Добавьте первую конфигурацию с помощью кнопок ниже | Add your first configuration using the buttons below |
| `action.scan_qr` | Отсканировать QR-код | Scan QR code |
| `action.import_from_url` | (зарезервирован — на v0.2 не используется отдельно, импорт URL = part of pasteboard import) | (reserved) |
| `action.cancel` | Отмена | Cancel |
| `action.ok` | OK | OK |
| `menu.add_config` | Добавить конфигурацию | Add configuration |
| `menu.scan_qr` | Сканировать QR | Scan QR |
| `menu.import_from_clipboard` | Добавить из буфера | Add from clipboard |
| `server.label` | Сервер: | Server: |
| `server.auto` | Авто | Auto |
| `status.disconnected` | Отключено | Disconnected |
| `status.connecting` | Подключение | Connecting |
| `status.connected` | Подключено | Connected |
| `status.error` | Ошибка | Error |
| `timer.label` | Время подключения | Connection time |
| `settings.title` | Настройки | Settings |
| `settings.security.section` | Безопасность | Security |
| `settings.kill_switch.label` | Kill Switch | Kill Switch |
| `settings.kill_switch.footer` | Блокирует весь интернет при разрыве VPN — защищает от случайной утечки трафика. | Blocks all internet traffic when the VPN drops — protects against accidental leaks. |
| `banner.reconnect_needed` | Переподключитесь для применения изменений | Reconnect to apply changes |
| `banner.dismiss` | Закрыть | Dismiss |
| `qr.title` | Сканирование QR-кода | Scan QR code |
| `qr.cancel` | Отменить | Cancel |
| `qr.hint` | Наведите камеру на QR-код | Point camera at QR code |
| `qr.permission_denied.title` | Нет доступа к камере | No camera access |
| `qr.permission_denied.message` | BBTB нужен доступ к камере для сканирования QR-кодов. | BBTB needs camera access to scan QR codes. |
| `qr.permission_denied.open_settings` | Открыть настройки | Open Settings |
| `import.error.no_supported_configs` | В источнике нет конфигураций, поддерживаемых на этой версии BBTB. Обновите приложение в следующих версиях. | The source contains no configurations supported by this version of BBTB. Update the app in future versions. |
| `import.error.network` | Не удалось загрузить конфигурацию: %@ | Failed to load configuration: %@ |
| `import.error.validation` | Сервер вернул конфигурацию, нарушающую правила безопасности BBTB. | The server returned a configuration that violates BBTB security rules. |
| `import.progress` | Загрузка конфигурации… | Loading configuration… |
| `import.success.title` | Импорт завершён | Import complete |
| `import.success.message` | Добавлено: %lld. Будут включены в следующих версиях: %lld. | Imported: %lld. Will be enabled in future versions: %lld. |

### 9.2 Ключи Phase 1 — судьба

| Phase 1 key | Phase 2 fate |
|---|---|
| `app.display_name` | оставляем (Info.plist) |
| `app.short_name` | **не используется в TopBar v0.2** (D-09 — TopBar без app name); оставляем в L10n.swift для menu bar / macOS Settings |
| `status.empty` | удаляется (state `.empty` не показывает StatusPill) |
| `status.idle` | заменяется на `status.disconnected` (более ясно для пользователя — «Отключено» вместо «Не подключено») |
| `status.connecting`, `.connected`, `.error` | переименовываются в новые keys (см. §9.1) для консистентности namespace |
| `action.import_from_clipboard` | **сохраняется**, переиспользуется как primary button в EmptyStateCard и пункт меню |
| `empty.title`, `empty.subtitle` | **переписываются** с новым текстом |
| `import.error.no_pasteboard` | сохраняется |
| `import.error.malformed` | сохраняется |
| `import.error.not_reality` | сохраняется (используется когда импортирован vless URI без `security=reality`) |
| `import.success` | переименовывается в `import.success.message` (с плейсхолдерами) |
| остальные `menubar.*`, `alert.*`, `action.*` | без изменений |

---

## 10. Accessibility

### 10.1 Все интерактивные элементы

| Component | accessibilityLabel | accessibilityHint | accessibilityValue |
|---|---|---|---|
| TopBar menu button | «Меню» | «Открывает настройки» | — |
| TopBar `+` button | «Добавить» | «Открывает меню добавления конфигурации» | — |
| Menu item «Сканировать QR» | «Сканировать QR» | «Открывает камеру для сканирования» | — |
| Menu item «Добавить из буфера» | «Добавить из буфера» | «Импортирует конфигурацию из буфера обмена» | — |
| ConnectionButton | «Кнопка подключения» | контекстный (см. ниже) | состояние из StatusPill |
| ConnectionButton (`.idle`) | accessibilityHint = «Дважды нажмите для подключения» | | |
| ConnectionButton (`.connected`) | accessibilityHint = «Дважды нажмите для отключения» | | |
| ConnectionButton (`.error`) | accessibilityHint = «Дважды нажмите для повторной попытки» | | |
| StatusPill | hidden от VoiceOver (`accessibilityHidden(true)`) — текст уже в ConnectionButton accessibilityValue | — | — |
| ConnectionTimer | «Длительность подключения» | — | текущее значение `HH часов M минут S секунд` (обновляется через `accessibilityRespondsToUserInteraction(false)` + `.accessibilityValue` каждую секунду через VM published var) |
| ServerLineView | «Текущий сервер» | — | имя сервера или «Авто» |
| EmptyStateCard primary button | «Добавить конфигурацию из буфера обмена» | — | — |
| EmptyStateCard secondary button | «Отсканировать QR-код» | — | — |
| ReconnectBanner | «Требуется переподключение» | «Изменения настроек безопасности применятся после следующего подключения» | — |
| ReconnectBanner dismiss `✕` | «Закрыть уведомление» | — | — |
| SettingsView Toggle | «Kill Switch» (system Toggle уже озвучивает state) | «Защищает от утечки трафика при разрыве VPN» | — |
| QRScannerView Cancel | «Отменить сканирование» | — | — |

### 10.2 VoiceOver order на MainScreen (idle/connected)

```
1. TopBar menu button
2. TopBar `+` button
3. ReconnectBanner (если виден)
4. ConnectionTimer
5. ConnectionButton (объединяет state + action)
6. ServerLineView
```

(StatusPill скрыт от VoiceOver — дублирует ConnectionButton state.)

### 10.3 VoiceOver order на MainScreen (empty)

```
1. TopBar menu button
2. TopBar `+` button
3. EmptyStateCard icon (decorative — `accessibilityHidden(true)`)
4. EmptyStateCard title
5. EmptyStateCard subtitle
6. Primary button «Добавить из буфера»
7. Secondary button «Отсканировать QR-код»
```

### 10.4 Dynamic Type

Все шрифты — через системные `Font.TextStyle` (см. §8.4). EmptyStateCard и SettingsView должны корректно рендериться вплоть до `AX5` (`xxxLarge` accessibility size) — multiline в title/subtitle, scrollable Form в Settings.

ConnectionTimer — `.monospacedDigit()` сохраняется чтобы цифры не дрейфовали по ширине.

---

## 11. Platform Differences

| Поведение | iOS | macOS |
|---|---|---|
| Settings entry | NavigationStack push из TopBar menu icon | Cmd+, → Settings Scene + дублирующий push через menu icon |
| QR scanner презентация | `.fullScreenCover` | `.sheet` (480×640, non-resizable) |
| QR camera permission | `NSCameraUsageDescription` + `AVCaptureDevice.requestAccess` | то же + sandbox entitlement `com.apple.security.device.camera` |
| TopBar `+` Menu | SwiftUI `Menu` (нативный action sheet popup) | SwiftUI `Menu` (нативный NSMenu popup) |
| Pasteboard API | `UIPasteboard.general.string` | `NSPasteboard.general.string(forType: .string)` |
| Haptic on QR detect | `UIImpactFeedbackGenerator` | (no-op — macOS не имеет haptic) |
| MenuBarExtra (UX-07) | n/a | сохраняется без изменений из Phase 1 |
| Open System Settings (camera permission) | `UIApplication.openSettingsURLString` | `NSWorkspace.shared.open(URL("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"))` |
| App tint | system blue (default) | system accent (default) |
| EmptyStateCard max-width | full-width minus 32 pt insets | 360 pt centered |

---

## 12. Phase 11 Forward-Compatibility Notes

Все компоненты v0.2 — **placeholder design**. Phase 11 (UX-08, UX-09, Figma финал) заменит:

| Компонент / token | Что изменится в Phase 11 |
|---|---|
| EmptyStateCard icon (`tray`) | Брендированная иллюстрация / custom SF Symbol |
| EmptyStateCard title / subtitle | Финальный copywriting под BBTB-тон (возможно «Жук ждёт возвращения» вместо «Нет конфигурации») |
| ConnectionButton fill colors | Кастомная палитра BBTB (вероятно тёмный графит → акцент бирюза/green) |
| ConnectionButton `.connecting` анимация | Spinning gradient / pulsating glow (UX-08) |
| StatusPill palette | Custom semantic colors с увеличенным contrast |
| ServerLineView | Возврат chevron `›` + signal-strength dot (зелёный/жёлтый/красный по latency) — Phase 3 SRV-* |
| TopBar menu icon | Возможно замена `line.3.horizontal` на кастомную иконку |
| SettingsView | Расширение до полного scope (Подписки, Уведомления, Внешний вид, Помощь, О приложении, Расширенные) — Phase 4/10/11 |
| TopBar app name slot | Логотип BBTB (центр) — финал Phase 11 |
| Onboarding | Полноценный onboarding screen (UX-01) — Phase 11 |
| ReconnectBanner стиль | Возможна замена на toast / inline indicator |
| Empty-state UX recovery | После удаления VPN profile из iOS Settings (UX-02 + CORE-07) — Phase 11 |

DesignSystem package (`DS.Spacing`, `DS.Radius`, `DS.Typography`) **наследуется** в Phase 11 — token names остаются, значения переопределяются.

---

## 13. Out of Scope (Phase 2)

Явный список того, что в Phase 2 НЕ реализуется (zero-confusion для planner + executor):

- ❌ **File picker entry** (IMP-03) — отложено в Phase 11 как угловая ссылка в onboarding.
- ❌ **Server list UI** (UX-04, SRV-*) — Phase 3. На v0.2 ServerLineView показывает active один сервер / «Авто», tap disabled.
- ❌ **Pull-to-refresh subscription** — Phase 3.
- ❌ **Search в server list** — Phase 3.
- ❌ **Multiple subscription URLs UI** — Phase 3 (data model уже массивный, но UI выбора нет).
- ❌ **Onboarding screen** (UX-01) — Phase 11.
- ❌ **Settings: Подписки UI** — Phase 3/4.
- ❌ **Settings: Уведомления** — Phase 4.
- ❌ **Settings: Внешний вид (theme + language)** — Phase 11.
- ❌ **Settings: Помощь** — Phase 11.
- ❌ **Settings: О приложении** — Phase 11.
- ❌ **Settings: Расширенные** (DNS, IPv6, uTLS, xray-fallback, rules editor, network diagnostics) — Phase 4/10/11.
- ❌ **Финальный дизайн UI** (Figma) — Phase 11.
- ❌ **Анимации UX-08** (вращение connecting, pulse connected) — Phase 11. На v0.2 — `symbolEffect(.bounce, value: state)` из Phase 1 сохраняется как минимум.
- ❌ **macOS R5 «Отключить enforceRoutes» toggle** (KILL-04) — Phase 10. Hook уже зарезервирован в `KillSwitch.platformShouldDisableEnforceRoutes()`.
- ❌ **Auto-reconnect при изменении kill switch** — отказались (баннер вместо принудительного reconnect, не ломаем stream / звонки).
- ❌ **Signal-strength dot в ServerLineView** — Phase 3.
- ❌ **Pasteboard auto-detect на app activate** — Phase 11.
- ❌ **Empty-state recovery после удаления VPN profile из iOS Settings** (UX-02 + CORE-07) — Phase 11 follow-up.
- ❌ **MenuBarExtra расширения** (UX-07 carry-forward без изменений) — Phase 11.
- ❌ **Биометрия (Face ID / Touch ID toggle)** — Phase 4/6.
- ❌ **Confirmation alert при выключении Kill Switch** (D-13 — отказались).

---

## Checker Sign-Off

(Адаптировано к SwiftUI native стеку — не shadcn.)

- [ ] Dimension 1 Copywriting: PASS — все user-facing строки определены в §9 + §6.3
- [ ] Dimension 2 Visuals: PASS — layout композиция MainScreen (idle/empty), Settings, QR scanner в §2-§5
- [ ] Dimension 3 Color: PASS — 60/30/10 распределение + accent reserved-for list в §8.3
- [ ] Dimension 4 Typography: PASS — 7 ролей через системные TextStyle в §8.4
- [ ] Dimension 5 Spacing: PASS — 8-point grid (с 4 pt для tight) в §8.1
- [ ] Dimension 6 Registry Safety: not applicable (нет third-party registries — SwiftUI native + SF Symbols)
- [ ] Dimension 7 Accessibility: PASS — labels/hints/values + VoiceOver order + Dynamic Type в §10
- [ ] Dimension 8 Platform parity: PASS — iOS vs macOS отличия в §11

**Approval:** pending — ждёт `gsd-ui-checker`.

---

*Phase: 2-trojan-import-flow*
*UI-SPEC drafted: 2026-05-12*
*Source decisions: CONTEXT.md D-08 (Trojan URI), D-09 (MainScreen layout), D-10 (empty-state), D-11 (ServerLineView), D-12/13/14 (Settings + Kill Switch), Q2.1-Q2.6 в DISCUSSION-LOG.md*
*Pre-populated from: CONTEXT.md (15 decisions), Phase 1 carry-forward (ConnectionState, MainScreenViewModel skeleton, L10n pattern), wiki/ux-specification.md (Phase 11 target — forward-compat notes §12)*
*Downstream consumers: `gsd-planner` (W2/W3/W4 task breakdown), `gsd-executor` (visual source of truth), `gsd-ui-checker` (6+2 dimension validation), `gsd-ui-auditor` (retrospective compliance check)*
