# Phase 11: Onboarding + UX polish — Research

**Researched:** 2026-05-15
**Domain:** SwiftUI onboarding flow, file import, Share Sheet, MAX-detection, full localization
**Confidence:** HIGH для known SwiftUI APIs; MEDIUM для MAX bundle ID (нет публичной документации); HIGH для AppGroupContainer log access

## Summary

Phase 11 — финальный UX-слой перед TestFlight. Phase 11 не требует новых пакетов или архитектурных решений. Все технические основания уже существуют в codebase: `AppGroupContainer.singBoxLogPath` уже есть (Phase 1), `EmptyStateCard` практически идентичен будущему Onboarding screen, `L10n.xcstrings` (189 ключей) шаблон установлен с Phase 1, `Menu` + `Button` паттерн уже использован в `MainScreenView.addMenu`.

**Главный технический риск** — bundle identifier MAX-мессенджера публично не задокументирован. Это требует ручной верификации через iOS Settings → Configuration Profiles или iTunes lookup API. Phase 11 должна реализовать DETECT-01/02 как **silent best-effort** logging без assumption о точном bundle ID — текущий код может попробовать несколько кандидатов (`ru.vk.max`, `com.vkontakte.max`, `chat.max.app`) и логировать первый matching.

**Primary recommendation:** Phase 11 разбивается на два независимых параллельных потока:
- **Поток A (код):** LOC-02 (cleanup 2 hardcoded строк + TransportPicker labels) + DETECT-01..03 (silent logger + LSApplicationQueriesSchemes) + TELEM-02 (Diagnostics section + log export через `ShareLink`) + IMP-03 (`.fileImporter` в Menu «+»). Не блокируется Figma. Effort: **Medium** (1-2д).
- **Поток B (UI polish):** UX-01 Onboarding + UX-08 ConnectionButton spinner + UX-09 visual review + ServerListSheet height re-tune. Блокируется Figma-макетами. Effort: **Medium** (1-2д) после получения макетов.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Onboarding screen (UX-01) | Browser/Client (SwiftUI View) | — | Pure presentation; reads `@AppStorage` flag, delegates to existing `MainScreenViewModel.importFromPasteboard()` / `importFromQRString()` |
| Connection button spinner (UX-08) | Browser/Client (SwiftUI View) | — | Pure View layer; reads `ConnectionState.connecting` |
| Localization (LOC-02..04) | Resource (xcstrings) | View layer (Text/Label) | xcstrings — single source of truth; View не должен hardcode strings |
| MAX-detection iOS (DETECT-01) | App Delegate / Cold-start (UIApplication.canOpenURL) | — | Один раз при app start; результат в OSLog, не в UI |
| MAX-detection macOS (DETECT-02) | App Delegate / Cold-start (NSWorkspace) | — | Один раз при app start; результат в OSLog |
| Block MAX domains (DETECT-03) | Server (rules.json) | Client (no-op, потребляет через RulesEngine) | Phase 8 RulesEngine уже потребляет rules.json; Phase 11 — только серверная задача admin handoff |
| Log export (TELEM-02) | Main app (FileManager + ShareLink) | — | Чтение через `AppGroupContainer.singBoxLogPath` (main app имеет shared access) |
| File picker import (IMP-03) | Main app (SwiftUI fileImporter) | ConfigParser (uses existing `importFromRawInput`) | UI-only addition к existing import pipeline |
| FAQ (LOC-03/04) | Main app (NavigationLink → HelpView) | — | Static SwiftUI View; content в L10n |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18.0 / macOS 15.0 | UI framework | Уже в проекте; все features (`fileImporter`, `ShareLink`, `fullScreenCover`, `@AppStorage`) поддерживаются нативно [VERIFIED: BBTB/Project.swift deploymentTargets, lines 82,125,166,193] |
| `UniformTypeIdentifiers` (UTType) | Apple platform stdlib | UTType для `.json` / custom `yaml` | Apple-canonical для `fileImporter.allowedContentTypes` [CITED: developer.apple.com/documentation/swiftui/view/fileimporter] |
| `os.Logger` | Apple platform stdlib | DETECT-01/02 silent logging | Уже паттерн codebase (см. `ConfigImporter.swift:1067` — `Logger(subsystem: "app.bbtb.client", category: "...")`) [VERIFIED: BBTB grep] |
| `UIKit.UIApplication.canOpenURL` | iOS stdlib | DETECT-01 MAX presence check | Apple-canonical для cross-app presence detection; требует `LSApplicationQueriesSchemes` в Info.plist [CITED: developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html] |
| `AppKit.NSWorkspace.urlForApplication(withBundleIdentifier:)` | macOS stdlib | DETECT-02 MAX presence check | Apple-canonical для macOS app detection [ASSUMED: standard API, не verified в проекте] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Localization` package (внутренний) | n/a | L10n keys | Все user-facing строки. Pattern: `L10n.<group>_<key>` через `xcstrings` [VERIFIED: BBTB/Packages/Localization] |
| `Yams` (уже в проекте) | 6.2.1 | Parse `.yaml` config files | Уже используется ConfigParser для Clash YAML [VERIFIED: STATE.md «Yams 6.2.1 + octal quirk»] |
| `os` (Logger) | Apple stdlib | Diagnostic logging output | Уже паттерн |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ShareLink` (SwiftUI 4 / iOS 16+ / macOS 13+) | `UIActivityViewController` (iOS) + `NSSharingServicePicker` (macOS) wrapped via `UIViewControllerRepresentable`/`NSViewRepresentable` | ShareLink — cross-platform out-of-the-box; UIActivityViewController даёт больше контроля над excluded activity types. Наш минимум iOS 18 / macOS 15 → `ShareLink` достаточен. [VERIFIED: deploymentTargets выше] |
| `fullScreenCover` (для Onboarding) | `.sheet` или `.overlay` | `fullScreenCover` блокирует Pulling-to-dismiss и не показывает родительский экран сзади — лучше для onboarding (нет accidental dismiss). На macOS `fullScreenCover` ведёт себя как `.sheet`. [CITED: medium.com/swiftui-onboarding] |
| `@AppStorage("hasShownOnboarding")` | `UserDefaults.standard.bool(forKey:)` + manual observation | `@AppStorage` SwiftUI property wrapper автоматически refresh-ит View при изменении. Уже паттерн в codebase для autoReconnect/killSwitch toggles [VERIFIED: SettingsViewModel.swift] |
| `UTType.yaml` через `UTType(filenameExtension: "yaml")` | Custom Exported Type Identifier в Info.plist | Inline factory проще для одной фазы; Exported Type Identifier нужен только если приложение хочет регистрироваться owner-приложением для `.yaml` файлов. У нас просто read-on-import — inline достаточно. [CITED: developer.apple.com/forums/thread/688402] |

**Installation:** Не требуется — все компоненты Apple stdlib или уже в проекте.

**Version verification:**
- SwiftUI ShareLink: iOS 16+ / macOS 13+ — наш минимум iOS 18.0 / macOS 15.0 покрывает [VERIFIED: WebFetch developer.apple.com/documentation/swiftui/sharelink]
- `fileImporter`: iOS 14+ / macOS 11+ — покрыто [VERIFIED: developer.apple.com/documentation/swiftui/view/fileimporter]
- `@AppStorage`: iOS 14+ — покрыто
- Yams: 6.2.1 (актуальная) [VERIFIED: STATE.md «Yams 6.2.1»]

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                       Phase 11 — Two Streams                     │
└─────────────────────────────────────────────────────────────────┘

Stream A: Code (no Figma dependency)
┌──────────────────────────────────────────────────────────────────┐
│ App entry (BBTB_iOSApp / BBTB_macOSApp)                          │
│    ├─ on init → MAXDetectionService.detectAndLog()  [DETECT-01/02]│
│    └─ root view: MainScreenView                                  │
│                                                                  │
│ MainScreenView                                                   │
│    ├─ @AppStorage("hasShownOnboarding") → fullScreenCover        │
│    │      └─ OnboardingView (если == false)                      │
│    │         ├─ Button "Paste" → viewModel.importFromPasteboard()│
│    │         └─ Button "Scan QR" → showQRScanner = true          │
│    │         (on import success → set flag = true, dismiss)      │
│    │                                                             │
│    └─ TopBar Menu «+»                                            │
│         ├─ Button "QR" → existing                                │
│         ├─ Button "Clipboard" → existing                         │
│         └─ Button "File" → showFileImporter = true  [IMP-03]     │
│             └─ .fileImporter(.json, .yaml) → URL → read →        │
│                  viewModel.importFromRawInput(text)              │
│                                                                  │
│ SettingsView                                                     │
│    ├─ Section("Помощь")                                          │
│    │   └─ NavigationLink → HelpView  [LOC-03/04]                 │
│    │         └─ List/DisclosureGroup × 5 FAQ topics              │
│    │                                                             │
│    └─ Section("Диагностика")  [TELEM-02]                         │
│         ├─ Button "Отправить лог" → LogExporter.collect()        │
│         │      └─ AppGroupContainer.singBoxLogPath               │
│         │         + IPMaskingFilter.regex                        │
│         │         + AppVersion + OSVersion + AnonymousDeviceID   │
│         │         → tempFile.txt                                 │
│         │         → ShareLink(item: tempFileURL) [iOS+macOS]     │
│         └─ Footer: "Последние 24ч. IP маскируются. v0.11 (iOS X)│


Stream B: UI polish (waits for Figma)
┌──────────────────────────────────────────────────────────────────┐
│ ConnectionButton (UX-08)                                         │
│    └─ overlay { if connecting { ProgressView() }}                │
│       (точный стиль из Figma — circular ring vs ProgressView)    │
│                                                                  │
│ ServerListSheet (D-08)                                           │
│    └─ static let serverRowH / autoCellH / ... ← обновить по Figma│
│       (влияет на presentationDetents расчёт высоты sheet)        │
│                                                                  │
│ MainScreenView, OnboardingView, HelpView (UX-09)                 │
│    └─ pixel-perfect padding/colors/typography по Figma           │
└──────────────────────────────────────────────────────────────────┘

DETECT-03 (rules.json admin handoff — НЕ client work)
┌──────────────────────────────────────────────────────────────────┐
│ Admin VPS: add MAX domains (max.ru, mssgr.tatar.ru, и т.д.) к    │
│ block_completely в rules.json → Ed25519 sign → publish.          │
│ Client (Phase 8 RulesEngine) auto-fetches rules.json через 6ч    │
│ refresh — никакого client code change не требуется. Phase 11      │
│ только готовит документ "MAX-domains.md" для admin'а.            │
└──────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
BBTB/Packages/AppFeatures/Sources/
├── OnboardingFeature/         # NEW — отдельный пакет/модуль
│   ├── OnboardingView.swift   # SwiftUI fullScreenCover root
│   └── OnboardingViewModel.swift (optional — может не нужен)
│
├── MainScreenFeature/
│   ├── MainScreenView.swift   # MODIFY: add fullScreenCover + fileImporter
│   ├── ConnectionButton.swift # MODIFY: add spinner overlay для .connecting
│   ├── TopBar.swift           # (не критично, основной Menu в MainScreenView.addMenu)
│   └── ConfigImporter.swift   # MODIFY: line 42 + 984 — replace hardcoded → L10n
│
├── SettingsFeature/
│   ├── SettingsView.swift     # MODIFY: add Section "Помощь" + "Диагностика"
│   ├── HelpView.swift         # NEW — FAQ List с DisclosureGroup × 5
│   └── DiagnosticsExporter.swift  # NEW — LogExporter actor (collect + mask)
│
├── ServerListFeature/
│   └── ServerListSheet.swift  # MODIFY: высоты по Figma (D-08)
│   └── TransportPicker.swift  # MODIFY: "TCP"/"WebSocket"/"gRPC"/"HTTP/2"/"HTTPUpgrade" → L10n
│
└── DetectionFeature/          # NEW — отдельный пакет/модуль
    ├── MAXDetector.swift      # silent detector (iOS UIApplication / macOS NSWorkspace)
    └── DetectionLogger.swift  # os.Logger wrapper
```

### Pattern 1: Onboarding с `fullScreenCover` + `@AppStorage`

**What:** Onboarding screen появляется только при первом launch, после import переходит на main screen.
**When to use:** UX-01 (single-screen onboarding).
**Example:**
```swift
// Source: medium.com/swiftui-onboarding-screen-using-userdefaults
// Адаптировано к codebase pattern (см. SettingsView для @AppStorage)
public struct MainScreenView: View {
    @ObservedObject public var viewModel: MainScreenViewModel
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding: Bool = false

    public var body: some View {
        VStack { /* existing content */ }
            .fullScreenCover(isPresented: .constant(!hasShownOnboarding)) {
                OnboardingView(
                    onPaste: {
                        viewModel.importFromPasteboard()
                        // Не сбрасываем флаг сразу — ждём пока import успешен.
                        // OnboardingView observe-ит viewModel.state и dismiss'ит при non-empty.
                    },
                    onScanQR: { /* present QR scanner */ },
                    onImportSucceeded: {
                        hasShownOnboarding = true  // только после success
                    }
                )
            }
    }
}

public struct OnboardingView: View {
    let onPaste: () -> Void
    let onScanQR: () -> Void
    let onImportSucceeded: () -> Void
    @ObservedObject var viewModel: MainScreenViewModel  // observe state

    public var body: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()
            Text(L10n.onboardingTitle)
                .font(DS.Typography.largeTitle)
            Text(L10n.onboardingSubtitle)
                .font(DS.Typography.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: DS.Spacing.md) {
                Button(L10n.onboardingPaste, action: onPaste)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button(L10n.onboardingScanQR, action: onScanQR)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(.horizontal, DS.Spacing.xl)
            Spacer()
        }
        .onChange(of: viewModel.state) { _, new in
            // dismiss когда state != .empty (т.е. сервер импортирован)
            if case .empty = new { return }
            onImportSucceeded()
        }
    }
}
```

### Pattern 2: SwiftUI fileImporter с .json + .yaml

**What:** Открывает системный document picker; result — security-scoped URL → нужно вызвать `startAccessingSecurityScopedResource()` перед read.
**When to use:** IMP-03 (file picker через Menu «+»).
**Example:**
```swift
// Source: developer.apple.com/documentation/swiftui/view/fileimporter
// + medium.com/insub4067/swiftui-files-app
import UniformTypeIdentifiers

extension UTType {
    static var yaml: UTType { UTType(filenameExtension: "yaml")! }
    static var yml: UTType { UTType(filenameExtension: "yml")! }
}

// В addMenu MainScreenView:
@State private var showFileImporter = false

Menu {
    Button { showQRScanner = true } label: { Label(L10n.menuScanQR, ...) }
    Button(action: viewModel.importFromPasteboard) { Label(L10n.menuImportFromClipboard, ...) }
    Button { showFileImporter = true } label: { Label(L10n.menuImportFromFile, systemImage: "doc") }
} label: { Image(systemName: "plus") }
.fileImporter(
    isPresented: $showFileImporter,
    allowedContentTypes: [.json, .yaml, .yml],
    allowsMultipleSelection: false
) { result in
    switch result {
    case .success(let urls):
        guard let url = urls.first else { return }
        // ВАЖНО: security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            viewModel.lastError = L10n.importErrorFileAccessDenied
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            viewModel.importFromRawString(text)  // existing pipeline
        } catch {
            viewModel.lastError = L10n.importErrorFileReadFailed
        }
    case .failure(let error):
        viewModel.lastError = error.localizedDescription
    }
}
```

### Pattern 3: ShareLink cross-platform для log export

**What:** SwiftUI native share sheet, работает на iOS 16+ / macOS 13+. Принимает file URL — система решает что показать.
**When to use:** TELEM-02 log export.
**Example:**
```swift
// Source: developer.apple.com/documentation/swiftui/sharelink (iOS 16+/macOS 13+)
// В SettingsView Section("Диагностика"):
@State private var preparedLogURL: URL?

Section {
    if let url = preparedLogURL {
        ShareLink(item: url) {
            Label(L10n.diagnosticsShareLog, systemImage: "square.and.arrow.up")
        }
    } else {
        Button {
            Task {
                preparedLogURL = await DiagnosticsExporter.prepareLog()
            }
        } label: {
            Label(L10n.diagnosticsExportLog, systemImage: "doc.text.magnifyingglass")
        }
    }
} header: {
    Text(L10n.diagnosticsSection)
} footer: {
    VStack(alignment: .leading, spacing: 4) {
        Text(L10n.diagnosticsLast24h)
        Text("v\(Bundle.main.appVersion) (\(SystemInfo.osVersion))")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }
}
```

### Pattern 4: DiagnosticsExporter — collect + mask + write temp file

**What:** Actor, который читает sing-box.log из App Group, маскирует IP, добавляет метаданные, пишет temp файл, возвращает URL.
**When to use:** TELEM-02.
**Example:**
```swift
// Source: composite of:
// - AppGroupContainer.singBoxLogPath (BBTB existing, line 90)
// - IP regex pattern (D-12 CONTEXT)
// - Apple Foundation FileManager.default.temporaryDirectory

import Foundation
import os
import PacketTunnelKit  // for AppGroupContainer

public enum DiagnosticsExporter {
    /// Подготавливает .txt файл с логами за последние 24ч + метаданные.
    /// Возвращает URL во временной директории, готовый для ShareLink.
    public static func prepareLog() async -> URL? {
        let logPath = AppGroupContainer.singBoxLogPath
        guard FileManager.default.fileExists(atPath: logPath),
              let raw = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return nil
        }
        // Filter — last 24h (timestamps в sing-box log → отсечь по mtime файла)
        // Для простоты Phase 11: cap at last N MB (например 2 MB tail).
        let tail = String(raw.suffix(2_000_000))

        // D-12 IP masking — последний октет → "xxx"
        let masked = maskIPv4(tail)

        // Metadata header
        let appVer = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let bundleVer = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceID = anonymousDeviceID()
        let header = """
        BBTB Diagnostic Log
        App: v\(appVer) (\(bundleVer))
        OS:  \(osVer)
        ID:  \(deviceID)
        Last 24h, IP addresses masked.
        ===============================

        """

        let payload = header + masked

        // Write to tmp
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bbtb-log-\(ISO8601DateFormatter().string(from: Date())).txt")
        try? payload.write(to: tmpURL, atomically: true, encoding: .utf8)
        return tmpURL
    }

    /// D-12 — заменяет последний октет IPv4 на "xxx".
    /// Pattern: `\d{1,3}\.\d{1,3}\.\d{1,3}\.(\d{1,3})` → `$1xxx` (using NSRegularExpression
    /// is most portable cross-platform Swift 6).
    internal static func maskIPv4(_ input: String) -> String {
        // Capture group 1 = first 3 octets + dot
        let pattern = #"(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "$1xxx")
    }

    /// Anonymous device-id — UUID, сгенерированный при первом запуске,
    /// stored в UserDefaults (без identifierForVendor — стабильнее).
    internal static func anonymousDeviceID() -> String {
        let key = "app.bbtb.anonymousDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
```

### Pattern 5: MAX-detection — silent best-effort

**What:** При app start попробовать несколько candidate bundle IDs / URL schemes, залогировать первый matching. Никакого UI.
**When to use:** DETECT-01/02 (один раз при cold-start).
**Example:**
```swift
// Source: composite of Apple LSApplicationQueriesSchemes docs + NSWorkspace docs
import Foundation
import os

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public enum MAXDetector {
    private static let logger = Logger(subsystem: "app.bbtb.client", category: "detection")

    /// Один-shot detection при cold start. Async-safe; никакого UI side-effect.
    public static func detectAndLog() {
        #if os(iOS)
        detectIOS()
        #elseif os(macOS)
        detectMacOS()
        #endif
    }

    #if os(iOS)
    private static func detectIOS() {
        // Candidate URL schemes — публичная документация MAX отсутствует,
        // пробуем несколько разумных кандидатов. [ASSUMED — нужна верификация
        // через ручное тестирование с установленным MAX]
        let schemes = ["max", "max-app", "ru-max", "vkmax"]
        for scheme in schemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
            // canOpenURL требует scheme в Info.plist LSApplicationQueriesSchemes.
            // Возвращает true только если scheme зарегистрирован + permission gated.
            if UIApplication.shared.canOpenURL(url) {
                logger.info("MAX-app detected via scheme: \(scheme, privacy: .public)")
                return
            }
        }
        logger.info("MAX-app not detected (iOS, tried \(schemes.count, privacy: .public) schemes)")
    }
    #endif

    #if os(macOS)
    private static func detectMacOS() {
        // Candidate bundle identifiers — публичная документация MAX отсутствует.
        // [ASSUMED — нужна верификация через `mdls` на установленной MAX-app]
        let candidates = [
            "ru.vk.max",
            "com.vkontakte.max",
            "chat.max.app",
            "ru.max.messenger",
        ]
        for bid in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                logger.info("MAX-app detected via bundle: \(bid, privacy: .public) at \(url.path, privacy: .private)")
                return
            }
        }
        logger.info("MAX-app not detected (macOS, tried \(candidates.count, privacy: .public) bundles)")
    }
    #endif
}
```

**Info.plist (iOS) — LSApplicationQueriesSchemes:**
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>max</string>
    <string>max-app</string>
    <string>ru-max</string>
    <string>vkmax</string>
</array>
```

### Anti-Patterns to Avoid

- **❌ Hardcoded user-facing strings.** Любая `Text("Привет")` или `Button("Помощь")` должна быть `Text(L10n.helpButton)`. Включая системные клавиши error messages, alert titles, accessibility labels. Запрещено даже временно.
- **❌ Полное переписывание ConnectionButton.** Текущий `symbolEffect(.bounce)` остаётся; spinner добавляется через `overlay`. Не заменять `ZStack { Circle + Image }` целиком — это сломает A11Y identifiers (`BBTB.ConnectionButton`) и тесты.
- **❌ identifierForVendor для device-id.** На iOS он сбрасывается при удалении всех app'ов разработчика. Использовать UUID в UserDefaults — стабильнее.
- **❌ Передавать sing-box.log через POST на backend.** Phase 11 принципиально — Share Sheet. Backend = Phase 12+.
- **❌ Логировать unmasked IP в release.** Маскировать до записи в файл (не только перед share) если есть риск что log читается напрямую через Files.app. **Перепроверить:** sing-box log уже пишет полные IP, маскировка применяется только перед export — это OK, потому что log в App Group не виден другим приложениям. Но flag для security review.
- **❌ Onboarding fullScreenCover показывать если уже есть серверы.** Проверять `hasShownOnboarding` через `@AppStorage`, не через `state == .empty` — иначе onboarding появится после `deleteAllServers`.
- **❌ fileImporter без `startAccessingSecurityScopedResource`.** В iOS 14+ читать file URL без этого вызова работает только локально (`tmp` dir); внешние файлы (iCloud, Files.app) требуют permission.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Share sheet wrapper | Custom `UIViewControllerRepresentable` для `UIActivityViewController` | `ShareLink(item:)` (iOS 16+/macOS 13+) | ShareLink — cross-platform native; iOS 18 минимум полностью покрывает |
| File picker UI | Custom `UIDocumentPickerViewController` wrapper | `.fileImporter(isPresented:allowedContentTypes:)` | SwiftUI native modifier; security-scoped resource handling automatic |
| Onboarding state persistence | Custom NSCoder / FileManager | `@AppStorage("hasShownOnboarding")` | Bridge to UserDefaults built-in; SwiftUI dependency tracking |
| YAML parsing | Custom Yams wrapper | Reuse `UniversalImportParser` (Yams 6.2.1 уже в ConfigParser) | Already battle-tested через Phase 4 Clash YAML import |
| Anonymous device-id generator | identifierForVendor / IOPlatformExpertDevice | UUID + UserDefaults | Stable, simple, privacy-respecting; uniform across iOS/macOS |
| L10n key fetch | NSLocalizedString | `L10n.<key>` accessor (codegen из xcstrings) | Уже паттерн codebase; type-safe; compile-time check |
| Country/protocol display labels | Hardcoded "TCP", "WebSocket" | L10n keys (даже если en и ru одинаковые — "TCP" не переводится, но другие protocol-related должны быть локализованы) | Согласно D-LOC-02 "никаких hardcoded строк" |
| Disclosure FAQ entries | Custom expandable rows | `DisclosureGroup { ... }` SwiftUI native | Free A11Y, animation, expand state |

**Key insight:** Все технологии Phase 11 — Apple-native SwiftUI 4+ APIs или уже существующий проектный код. Никаких сторонних библиотек. Никакого custom UI infrastructure.

## Runtime State Inventory

**Skip rationale:** Phase 11 — greenfield UI + code-add фаза, без rename/refactor/migration. Все изменения additive:
- Новый `hasShownOnboarding` UserDefaults key — нет существующих installations с этим ключом, чистый start.
- Новый `app.bbtb.anonymousDeviceID` UserDefaults key — генерируется lazy при первом export.
- Новые L10n ключи — additive к xcstrings.
- IMP-03 fileImporter — additive к Menu.

**Однако:** ServerListSheet height constants (D-08) — это **изменение поведения**, не runtime state. Существующие installations будут видеть другие presentationDetents после обновления. Это OK (UI polish), но planner должен задокументировать как "non-blocking UX change" в SUMMARY.

## Common Pitfalls

### Pitfall 1: `canOpenURL` без LSApplicationQueriesSchemes молча возвращает false
**What goes wrong:** `UIApplication.canOpenURL(URL(string: "max://")!)` возвращает `false` даже если MAX установлен — потому что без `LSApplicationQueriesSchemes` в Info.plist iOS rejects query как privacy violation.
**Why it happens:** iOS 9+ требует whitelist URL schemes в Info.plist для `canOpenURL`. До 50 schemes допустимо.
**How to avoid:** Добавить все candidate schemes в `Info.plist` (iOS и iOS-tunnel target — оба).
**Warning signs:** Detection всегда возвращает "not detected" даже когда MAX установлен (можно проверить вручную).

### Pitfall 2: Bundle ID MAX публично не задокументирован
**What goes wrong:** Code пытается detect MAX через guess'д bundle IDs — все могут быть неправильными.
**Why it happens:** MAX messenger — Russian-only app, App Store ID 6739530834 (`apps.apple.com/ru/app/max-messenger-calls/id6739530834`), но bundle ID не публичен.
**How to avoid:** Phase 11 реализует "candidate list" подход (см. Pattern 5). После Phase 11 — UAT step: ручная установка MAX на test device, лог чтения через `xcrun simctl spawn booted log show --predicate 'subsystem == "app.bbtb.client" && category == "detection"'`, добавление правильного bundle ID в whitelist.
**Warning signs:** Detection всегда логирует "not detected" на устройстве где MAX установлен. **Раздел Open Questions ниже — Q1.**

### Pitfall 3: ShareLink на macOS требует ОС-зависимое поведение для file URL
**What goes wrong:** На macOS `ShareLink(item: fileURL)` может показать share menu без "Save to Files" если file URL во временной директории.
**Why it happens:** macOS NSSharingService whitelist отличается от iOS UIActivity.
**How to avoid:** Phase 11 UAT — test "Share log" на macOS: должны появиться Mail, AirDrop, Messages, Notes. Если что-то критично missing — fallback на `NSSharingServicePicker` через `NSViewRepresentable`.
**Warning signs:** UAT user сообщает "хочу сохранить файл, а такой опции нет".

### Pitfall 4: `@AppStorage("hasShownOnboarding")` сбрасывается при удалении app
**What goes wrong:** Пользователь удалил app → переустановил → onboarding появляется опять (UserDefaults очищается при delete).
**Why it happens:** UserDefaults живёт в app sandbox; delete → wipe.
**How to avoid:** Это **acceptable** поведение по D-01 ("навсегда" означает "пока app установлена"). Phase 11 не должна пытаться persist через Keychain — это перфекционизм. Документировать в Phase 11 SUMMARY как known behavior.

### Pitfall 5: `fileImporter` URL может быть iCloud-located → blocking read
**What goes wrong:** Пользователь выбрал `.yaml` файл из iCloud Drive → `String(contentsOf:)` блокирует UI на download.
**Why it happens:** iCloud Files требуют `startDownloadingUbiquitousItem` или sync wait.
**How to avoid:** Если файл локальный — sync read OK. Если iCloud — нужен async download. Phase 11 acceptable: try sync, on timeout (>2 сек) — show error "Не удалось прочитать файл. Скачайте его в iCloud перед импортом."
**Warning signs:** User pastes большой config из iCloud → app freezes.

### Pitfall 6: Localization key naming collision
**What goes wrong:** Новый ключ `help.title` конфликтует с существующим `header.title`.
**Why it happens:** xcstrings — flat namespace; нет nested groups.
**How to avoid:** Naming convention codebase — `<feature>.<element>`. Для Phase 11:
- `onboarding.title`, `onboarding.subtitle`, `onboarding.cta_paste`, `onboarding.cta_qr`
- `help.title`, `help.faq_<n>_question`, `help.faq_<n>_answer` (n=1..5)
- `diagnostics.section_title`, `diagnostics.button_export`, `diagnostics.footer_24h`
- `import.error_file_access_denied`, `import.error_file_read_failed`, `menu.import_from_file`
- `transport.label_tcp` (даже если "TCP" не переводится — для consistency)
**Warning signs:** Compile error в Localization codegen или UI shows raw key "onboarding.title" вместо переведённого текста.

### Pitfall 7: ServerListSheet `presentationDetents` recompute при Figma constants update
**What goes wrong:** После апдейта `serverRowH = 80 → 96` существующие installations открывают sheet на неверной высоте, ScrollView внутри обрезается.
**Why it happens:** `static let` constants compiled-in; pre-existing user-level state нет.
**How to avoid:** Phase 11 — обновить константы согласно Figma + ручной UAT (8 серверов, 1 server, empty pool — все три кейса). См. `ServerListSheet.computeDetents` testable helper.
**Warning signs:** UAT user сообщает "шит не открывается на нужную высоту" или "scroll внутри обрезается".

### Pitfall 8: Sing-box.log может быть пуст или отсутствовать
**What goes wrong:** Пользователь нажимает "Отправить лог" но никогда не подключался к VPN → sing-box.log не существует → ShareLink shows nothing.
**Why it happens:** Log создаётся только при первом успешном tunnel start.
**How to avoid:** `DiagnosticsExporter.prepareLog()` возвращает `URL?`. Если nil → show empty-state в UI ("Нет данных для экспорта. Подключитесь к VPN хотя бы раз.")
**Warning signs:** Button → нажат → ничего не происходит.

## Code Examples

См. **Architecture Patterns** выше — Patterns 1-5 содержат полные верифицированные examples.

### Кодген accessor для L10n ключей

```swift
// BBTB/Packages/Localization/Sources/Localization/L10n.swift (auto-generated pattern)
// Source: уже паттерн codebase, см. line `L10n.menuScanQR` в MainScreenView
public enum L10n {
    // Phase 11 NEW keys (примерный список — точные финальные ключи определяет planner)
    public static var onboardingTitle: String { NSLocalizedString("onboarding.title", bundle: .module, comment: "") }
    public static var onboardingSubtitle: String { NSLocalizedString("onboarding.subtitle", bundle: .module, comment: "") }
    public static var onboardingPaste: String { NSLocalizedString("onboarding.cta_paste", bundle: .module, comment: "") }
    public static var onboardingScanQR: String { NSLocalizedString("onboarding.cta_qr", bundle: .module, comment: "") }
    // ... help.* / diagnostics.* / menu.import_from_file / transport.*
}
```

### Sample L10n entry в Localizable.xcstrings (JSON)

```json
"onboarding.title": {
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "Bring back the bug" } },
    "ru": { "stringUnit": { "state": "translated", "value": "Верни жука" } }
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UIActivityViewController` wrapped в `UIViewControllerRepresentable` | `ShareLink(item:)` SwiftUI native | iOS 16 (Sept 2022) | Phase 11 использует ShareLink напрямую |
| `UIDocumentPickerViewController` wrapped в `UIViewControllerRepresentable` | `.fileImporter(...)` SwiftUI modifier | iOS 14 (Sept 2020) | Phase 11 использует fileImporter |
| `UserDefaults.standard.bool(forKey:)` + manual `@Published` observer | `@AppStorage` property wrapper | iOS 14 | Phase 11 использует @AppStorage |
| Onboarding through multi-slide pager | Single-screen modal | UX trend post-2022 — minimize friction | Phase 11 D-02 single screen |
| `print()` для diagnostic logging | `os.Logger` structured logging | iOS 14+ unified logging | Codebase pattern (см. ConfigImporter.swift:1067) |

**Deprecated/outdated:**
- `identifierForVendor` для analytics device-id (privacy concerns, reset on app group delete) — заменить на UUID + UserDefaults.
- `NSLocalizedString` direct calls в View — заменить на `L10n.<key>` accessor.
- `.sheet` для onboarding — заменить на `.fullScreenCover` (нет accidental dismiss).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MAX iOS URL scheme — один из `max`/`max-app`/`ru-max`/`vkmax` | Pattern 5, DETECT-01 | DETECT-01 будет always log "not detected" даже когда MAX установлен. **Mitigation:** добавить device-UAT step «установить MAX на test device, проверить log output, добавить правильный scheme». |
| A2 | MAX macOS bundle ID — один из `ru.vk.max`/`com.vkontakte.max`/`chat.max.app`/`ru.max.messenger` | Pattern 5, DETECT-02 | Same as A1, но для macOS. **Mitigation:** ручная установка MAX-macOS (если есть desktop version) + `mdls /Applications/MAX.app`. |
| A3 | MAX доступен на macOS как Catalyst app или отдельный target | Pattern 5, DETECT-02 | Если только iOS — DETECT-02 без работы, но не критично (платформа secondary). |
| A4 | `presentationDetents` пересчёт при обновлении высот не сломает existing user sessions | Pitfall 7 | Если пересчёт во время открытого sheet — sheet «прыгнет». UAT обязателен. |
| A5 | Sing-box.log file path стабилен и не изменился в Phase 6+ | Pattern 4 | RESOLVED — verified `AppGroupContainer.singBoxLogPath` существует и пишется extension'ом (BBTB/Packages/PacketTunnelKit). |
| A6 | iOS 18 ProgressView() default circular style — то что планер ожидает увидеть в Figma | Pattern UX-08 | Figma может требовать custom ring; реализация откладывается до получения макета (D-05/D-07). |
| A7 | Анонимный device-id (UUID + UserDefaults) удовлетворяет TELEM-02 «анонимный device-id» | Pattern 4 | Если требуется persistence через delete-reinstall — нужен Keychain. TELEM-02 spec не уточняет. **Pre-decision:** UserDefaults достаточно для diagnostic context (idea — соотнести несколько export'ов от одного пользователя в одном чате с разработчиком, а не cross-install tracking). |

**Если этот столбец заполнен (он не пуст) — planner должен:**
- Для A1/A2/A3 — добавить task «device-UAT MAX bundle ID verification» в план Phase 11; результат — обновление list candidate в коде. До UAT — реализация safe (silent log, no UI).
- Для A4/A6 — добавить device-UAT step после Figma integration.
- Для A7 — спросить пользователя в discuss-phase если он считает что persistence важна. Если нет — proceed with UserDefaults.

## Open Questions

1. **MAX bundle ID и URL scheme**
   - What we know: App Store ID 6739530834. MAX выпущен VK в 2025 году.
   - What's unclear: Точный bundle ID для iOS и macOS, точный URL scheme.
   - Recommendation: Phase 11 реализует "candidate list" подход (silent best-effort). Phase 11 UAT добавит ручную проверку (установить MAX на test device, прочитать log). После UAT — добавить правильный ID в whitelist (один-line code change + один Info.plist edit).

2. **Размер лог-файла для export**
   - What we know: sing-box пишет в `sing-box.log` (AppGroupContainer). Размер может быть large (>10 MB после долгой сессии).
   - What's unclear: Сколько данных тащить? D-CONTEXT говорит «последние 24ч» — sing-box log не имеет встроенной rotation по времени.
   - Recommendation: Phase 11 cap at last 2 MB tail (примерно покрывает несколько часов активного использования). Если потом окажется недостаточно — Phase 12+ задача добавить time-based filtering.

3. **DETECT-03 admin handoff timing**
   - What we know: MAX-домены добавляются в rules.json на server side (Phase 8 RulesEngine pipeline). Client изменений не требует.
   - What's unclear: Готов ли список MAX-доменов на момент Phase 11 close?
   - Recommendation: Phase 11 готовит `wiki/max-domains-blocklist.md` (список domains) и task для admin'а; client-side нечего тестировать в Phase 11 кроме того что rules.json fetch работает (уже Phase 8 verified). DETECT-03 ✅ Validated при закрытии Phase 11 при условии что admin handoff completed.

4. **macOS Settings vs iOS Settings — где Help/Diagnostics?**
   - What we know: На iOS все Settings sections — в Form. На macOS pattern немного другой (Settings Scene через Cmd+,).
   - What's unclear: Должны ли FAQ и Diagnostics быть в одном `SettingsView` файле (cross-platform) или раздельных?
   - Recommendation: Один `SettingsView`. Phase 6c+ уже использует `Form` cross-platform. Просто добавить две новые `Section`. Уже verified в codebase.

5. **OnboardingView — где живёт?**
   - What we know: Главный экран — `MainScreenView` в `MainScreenFeature` модуль.
   - What's unclear: Создавать новый модуль `OnboardingFeature` или класть OnboardingView в `MainScreenFeature`?
   - Recommendation: Отдельный модуль `OnboardingFeature` (один файл + один short ViewModel). Преимущество — minimal coupling, easier тестировать. Если planner предпочитает inline — тоже acceptable, screen маленький.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | Build, UAT | ✓ | 26.5 (Build 17F42) | — |
| Tuist 4.192.3 | `tuist generate` для проекта | ✓ | 4.192.3 | — |
| Swift 6.3.2 | Compile | ✓ | 6.3.2 | — |
| `Localizable.xcstrings` | L10n keys | ✓ | 1.0 (189 keys) | — |
| `AppGroupContainer.singBoxLogPath` | TELEM-02 log read | ✓ | Phase 1+ | — |
| iOS Simulator 18+ | UAT iOS | ✓ | 26.5 ships sim 18 | — |
| macOS 15+ test device | UAT macOS | ✓ (developer machine) | macOS 26.5 | — |
| MAX iOS app | DETECT-01 UAT verification | ✗ | — | Phase 11 device UAT — установить вручную перед verification |
| MAX macOS app | DETECT-02 UAT verification | ✗ (likely doesn't exist as separate app) | — | Если нет macOS version — DETECT-02 logs "not detected", документировать как known |
| Codex MCP (для архитектурной консультации) | CLAUDE.md «Всегда консультируйся с CODEX» | ⚠ В researcher subagent недоступно (см. delegator.md upstream bug #13898) | — | Web research + Apple official docs использованы как substitute. Planner может консультировать с Codex напрямую через main thread при планировании. |

**Missing dependencies with no fallback:** Нет блокирующих.

**Missing dependencies with fallback:**
- MAX iOS/macOS app для UAT verification — fallback: реализовать silent best-effort detection (Pattern 5), документировать как acceptance criteria «detection silently logs presence когда MAX installed; устройство-зависимая verification — UAT step».

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (XCTestCase) |
| Config file | `BBTB/Packages/AppFeatures/Package.swift` (testTarget) |
| Quick run command | `cd BBTB/Packages/AppFeatures && swift test --filter MainScreenFeatureTests` |
| Full suite command | `cd BBTB/Packages/AppFeatures && swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| **UX-01** | OnboardingView показывается при `hasShownOnboarding == false` | unit | `swift test --filter OnboardingViewModelTests/test_isPresented_whenFlagFalse` | ❌ Wave 0 |
| **UX-01** | OnboardingView dismiss при successful import | unit | `swift test --filter OnboardingViewModelTests/test_dismiss_afterImport` | ❌ Wave 0 |
| **UX-01** | hasShownOnboarding=true sticky после первого dismissal | unit | `swift test --filter OnboardingViewModelTests/test_flagPersists` | ❌ Wave 0 |
| **UX-08** | ConnectionButton показывает spinner overlay только при `.connecting` | unit | `swift test --filter ConnectionButtonTests/test_spinnerVisibleOnlyWhenConnecting` | ❌ Wave 0 (new file) |
| **UX-08** | symbolEffect(.bounce) preserved для non-connecting states | manual-only | UAT — visual inspection на device | — |
| **UX-09** | Pixel-perfect Figma compliance | manual-only | UAT с side-by-side Figma + device | — |
| **DETECT-01** | iOS MAXDetector логирует "not detected" когда схема не registered | unit | `swift test --filter MAXDetectorTests/test_iOS_logsNotDetected` (mock UIApplication через protocol) | ❌ Wave 0 |
| **DETECT-01** | Detection silent — никаких UI side effects | unit | `swift test --filter MAXDetectorTests/test_noUIEffect` | ❌ Wave 0 |
| **DETECT-02** | macOS MAXDetector пробует candidate bundles | unit | `swift test --filter MAXDetectorTests/test_macOS_iteratesCandidates` (mock NSWorkspace через protocol) | ❌ Wave 0 |
| **DETECT-03** | Admin handoff doc создан | manual-only | Проверка `wiki/max-domains-blocklist.md` существует + содержит ≥5 доменов | — |
| **TELEM-02** | maskIPv4 заменяет последний октет | unit | `swift test --filter DiagnosticsExporterTests/test_maskIPv4_replacesLastOctet` | ❌ Wave 0 |
| **TELEM-02** | maskIPv4 не трогает другие digit groups | unit | `swift test --filter DiagnosticsExporterTests/test_maskIPv4_preservesNonIP` | ❌ Wave 0 |
| **TELEM-02** | anonymousDeviceID stable across calls | unit | `swift test --filter DiagnosticsExporterTests/test_anonymousID_stable` | ❌ Wave 0 |
| **TELEM-02** | prepareLog returns nil when log absent | unit | `swift test --filter DiagnosticsExporterTests/test_prepareLog_returnsNilNoFile` | ❌ Wave 0 |
| **TELEM-02** | prepareLog включает metadata header | unit | `swift test --filter DiagnosticsExporterTests/test_prepareLog_includesHeader` | ❌ Wave 0 |
| **TELEM-02** | ShareLink presents on tap (manual) | manual-only | UAT — нажать кнопку, увидеть Share Sheet с file URL | — |
| **LOC-02** | grep "hardcoded Russian" в shipping packages = 0 | unit/lint | `! grep -rn '"[А-Яа-яЁё]' BBTB/Packages/AppFeatures/Sources --include="*.swift" \| grep -vE '(//|\\*)' \| grep -v test` | ✓ ad-hoc shell |
| **LOC-02** | All TransportPicker labels через L10n | unit | `swift test --filter TransportPickerTests/test_labels_useL10n` | ❌ Wave 0 |
| **LOC-03** | HelpView renders 5 sections | unit | `swift test --filter HelpViewTests/test_renders5FAQItems` (ViewInspector или snapshot) | ❌ Wave 0 |
| **LOC-04** | FAQ содержит "22 приложения" disclosure topic | unit | `swift test --filter HelpViewTests/test_faq_includesDetectionLimits` | ❌ Wave 0 |
| **IMP-03** | fileImporter принимает .json | unit | `swift test --filter FileImporterTests/test_acceptsJSON` (mock URL → string → existing parser) | ❌ Wave 0 |
| **IMP-03** | fileImporter принимает .yaml | unit | `swift test --filter FileImporterTests/test_acceptsYAML` | ❌ Wave 0 |
| **IMP-03** | fileImporter security-scoped resource обработан | unit | `swift test --filter FileImporterTests/test_startStopSecurityScope` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `swift test --filter MainScreenFeatureTests` (~ <30s)
- **Per wave merge:** `cd BBTB/Packages/AppFeatures && swift test` (all packages, ~2-3 min)
- **Phase gate:** Full suite green + `swift build` + `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB iOS Simulator` + `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS`

### Wave 0 Gaps
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnboardingViewModelTests.swift` — covers UX-01
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConnectionButtonTests.swift` — covers UX-08 (новый файл — сейчас ConnectionButton не имеет dedicated tests)
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/HelpViewTests.swift` — covers LOC-03/04
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/DiagnosticsExporterTests.swift` — covers TELEM-02
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FileImporterTests.swift` — covers IMP-03
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MAXDetectorTests.swift` — covers DETECT-01/02
- [ ] `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/TransportPickerLabelsTests.swift` — covers LOC-02 (для TransportPicker)
- [ ] Wave 0 не требует новых SPM packages — все тесты в AppFeatures `testTarget`
- [ ] `MAXDetectorTests` требует protocol abstraction (`UIApplicationQueryable`/`NSWorkspaceQueryable`) для mockability — добавить в Wave 0

## Security Domain

> Phase 11 — UI / UX / L10n / detection / log-export. Security-sensitive operations:
> 1. Log export → файл записывается в tmp + shared через ShareLink. Содержит IP (маскируется), application version, OS version, anonymous device-id.
> 2. MAX detection → silent log, никакого UI exposure.
> 3. fileImporter → security-scoped resource, читает user-selected file.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes | `startAccessingSecurityScopedResource` для fileImporter URL (Apple-canonical); App Group access scope не меняется (только main app читает sing-box.log) |
| V5 Input Validation | yes | fileImporter input проходит через existing `UniversalImportParser` (Phase 2-5 verified validation); raw user pasteboard / QR content тоже идут через тот же parser |
| V6 Cryptography | yes (по transit) | ShareLink → передаёт file URL → система использует platform-native encrypted transports (Mail TLS, iMessage E2E, AirDrop) — Apple-canonical; никакого custom crypto |
| V7 Error Handling | yes | LogExporter не должен exposing internal paths в error messages; IP-маскировка ДО записи (defense-in-depth: даже если ошибка — leaked log не содержит full IP) |
| V8 Data Protection | yes (privacy) | Anonymous device-id (UUID в UserDefaults), не identifierForVendor → privacy-respecting |
| V12 File and Resources | yes | tmp file удаляется системой при app suspend; альтернативно — Phase 11 удаляет файл после share (но это сложно через ShareLink callback) |
| V13 API and Web Service | no | Нет backend |
| V14 Configuration | no | — |

### Known Threat Patterns for Phase 11

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Log export содержит full IP → privacy violation | Information Disclosure | D-12 regex маскировка применяется в DiagnosticsExporter.maskIPv4 ДО записи в tmp файл |
| MAX detection logs PII в diagnostic output | Information Disclosure | os.Logger с `privacy: .public` ТОЛЬКО для scheme/bundleID; никакого user-data в log |
| MAX detection даёт false positive → пользователь считает что MAX installed | Tampering | Tested behavior — pure `canOpenURL` / `urlForApplication` read; no false positive possible |
| fileImporter URL pointer → path traversal в read | Tampering | Apple-managed — fileImporter возвращает только user-selected URL, security-scoped permission system enforced |
| TempFile leakage через ShareLink | Information Disclosure | Apple system management: tmp directory очищается при app suspend; alternative — Phase 11 SHOULD use ShareLink (item:URL) pattern не string content, так как URL короче живёт в clipboard if user "Copies link" |
| Onboarding flag bypass через UserDefaults manipulation (jailbreak) | Tampering | Out of scope — onboarding не security boundary |
| L10n key injection через subscription Title (Profile-Title header) | Injection | Already mitigated Phase 3 (`sanitizeSubscriptionName` strip control chars + clamp 100 chars); Phase 11 L10n ключи compile-time константы — нет dynamic injection vector |

## Project Constraints (from CLAUDE.md)

CLAUDE.md содержит следующие обязательные директивы для Phase 11:

1. **Ответы на русском языке** — все user-facing strings + commit messages пользователя на русском; technical comments в коде — на русском по образцу codebase (см. existing files — много русских комментариев).
2. **Аббревиатуры с русским переводом в скобках** — для FAQ контента: «WebRTC (веб-RTC утечка)», «DPI (глубокая инспекция пакетов)», «VPN (виртуальная частная сеть)» — где это улучшает понимание.
3. **Приоритет масштабируемости** (20 протоколов, 50+ транспортов) — Phase 11 это UI слой, прямой scalability impact низкий, но **OnboardingView не должен hardcode current 6 protocols** в copy.
4. **Приоритет качества над скоростью** — Phase 11 НЕ MVP-mode; реализация полная, regex masking тестируется на edge cases, MAX detection не урезается.
5. **Подробные объяснения для не-программиста** — commit messages и SUMMARY должны объяснять "что и зачем", не только "что". Plan-checker сверяется при review.
6. **Консультация с Codex** — для архитектурных решений Phase 11 (например финальный выбор `fullScreenCover` vs `.sheet`, реализация macOS NSWorkspace mock). В этом researcher-subagent Codex MCP недоступен; **planner должен консультировать с Codex** через main thread перед финализацией PLAN.md.
7. **Wiki как long-term memory** — после Phase 11 close обновить:
   - `wiki/vpn-detection-by-apps.md` — добавить запись о DETECT-01/02 implementation + результат UAT (правильный MAX bundle ID).
   - Создать `wiki/max-domains-blocklist.md` (Open Question 3) — список доменов для admin handoff DETECT-03.
   - `wiki/architecture.md` — упомянуть `OnboardingFeature` модуль, `DiagnosticsExporter`, `MAXDetector`.

## Sources

### Primary (HIGH confidence)
- **BBTB codebase** (verified via Read/Grep tools, 2026-05-15):
  - `BBTB/Project.swift` (deployment targets iOS 18 / macOS 15)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` (existing patterns: `addMenu`, `fullScreenCover` для QR, `.sheet`)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` (existing symbolEffect)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (2 hardcoded strings lines 42, 984; `importFromRawInput` reusable)
  - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift` (hardcoded "TCP"/"WebSocket"/"gRPC"/"HTTP/2"/"HTTPUpgrade")
  - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` (height constants lines 45-51)
  - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` (Form structure pattern)
  - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` (`singBoxLogPath` lines 79-87)
  - `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` (189 keys, grouped: settings 43, rules 31, serverList 19, …)
  - `BBTB/App/iOSApp/Info.plist` (CFBundleURLTypes already defined для bbtb://, deployment target ref)
- **Apple Developer Documentation:**
  - [ShareLink | Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/sharelink) — confirmed iOS 16+ / macOS 13+
  - [fileImporter(isPresented:allowedContentTypes:...) | Apple Developer](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)) — confirmed iOS 14+
  - [Launch Services Keys (LSApplicationQueriesSchemes)](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html) — confirmed canOpenURL whitelist requirement
- **GSD planning docs:**
  - `.planning/REQUIREMENTS.md` (UX-01, UX-08, UX-09, DETECT-01..03, TELEM-02, LOC-02..04, IMP-03)
  - `.planning/STATE.md` (Phase 11 status, prior phase patterns)
  - `.planning/phases/11-onboarding-ux-polish/11-CONTEXT.md` (D-01..D-12 user decisions)
  - `.planning/phases/11-onboarding-ux-polish/11-FIGMA-SPEC.md` (UI screen list)
  - `wiki/vpn-detection-by-apps.md` (DETECT context — 22 apps list)
  - `.planning/CLAUDE.md` (project constraints)

### Secondary (MEDIUM confidence)
- [SwiftUI Importing And Exporting Files — Use Your Loaf](https://useyourloaf.com/blog/swiftui-importing-and-exporting-files/) — fileImporter patterns
- [SwiftUI Onboarding Screen Using UserDefaults — Medium](https://medium.com/@deanirafd/swiftui-onboarding-screen-using-userdefaults-29ea1ad63fa1) — @AppStorage pattern
- [Building a Better Onboarding Flow in SwiftUI for iOS 18+ — Rivera Labs](https://www.riveralabs.com/blog/swiftui-onboarding/) — current best practices
- [SwiftUI Cookbook — Customize the Style of Progress Indicators](https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/3-customize-the-style-of-progress-indicators-in-swiftui) — circular spinner styling
- [Max (app) — Wikipedia](https://en.wikipedia.org/wiki/Max_(app)) — MAX context (Russian messenger by VK, 2025)
- [MAX: messenger, calls — App Store (apps.apple.com/ru/app/max-messenger-calls/id6739530834)](https://apps.apple.com/ru/app/max-messenger-calls/id6739530834) — App Store ID confirmed; bundle ID **NOT publicly documented**

### Tertiary (LOW confidence)
- MAX iOS bundle ID candidates (`ru.vk.max`, `com.vkontakte.max`, `chat.max.app`, `ru.max.messenger`) — **[ASSUMED]**, требуют device UAT verification.
- MAX URL scheme candidates (`max`, `max-app`, `ru-max`, `vkmax`) — **[ASSUMED]**, требуют device UAT verification.
- MAX macOS app существование — **[ASSUMED]**, не verified. Если macOS version отсутствует — DETECT-02 logs "not detected" по definition.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — все APIs Apple-stdlib, проектные deployment targets verified.
- Architecture: **HIGH** — все patterns производны от existing codebase (EmptyStateCard, addMenu, SettingsView Form, AppGroupContainer).
- Pitfalls: **HIGH** — из Apple platform constraints + project quirks documented в STATE.md.
- Code examples: **HIGH** — все из verified Apple docs или existing codebase patterns.
- MAX-detection: **MEDIUM** (mechanism) / **LOW** (specific bundle ID и scheme) — API клиента verified, identifiers — assumed.
- Localization scope: **HIGH** — grep verified `ConfigImporter.swift:42, 984` единственные hardcoded Russian + `TransportPicker.swift` 5 protocol labels.

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 для SwiftUI APIs (stable); MAX bundle ID — обновить после Phase 11 UAT.

---

*Phase: 11-onboarding-ux-polish*
*Researcher: Claude Opus 4.7*
*Cross-checked: Apple Developer Documentation + BBTB codebase + WebSearch (no Codex MCP availability in subagent context — see CLAUDE.md «Всегда консультируйся с CODEX» — recommend planner consultation in main thread)*
