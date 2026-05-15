# Phase 11: Onboarding + UX polish — Pattern Map

**Mapped:** 2026-05-15
**Files analyzed:** 17 (8 new, 9 modified)
**Analogs found:** 16 / 17 (1 partial — MAXDetector)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.swift` *(NEW)* | view (SwiftUI screen) | request-response (UI events) | `MainScreenFeature/EmptyStateCard.swift` | **exact** (identical structure: 2 CTA + title/subtitle) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingViewModel.swift` *(NEW, optional)* | view-model | event-driven | `SettingsFeature/SettingsViewModel.swift` (`@AppStorage` flag pattern) | role-match |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MAXDetector.swift` *(NEW)* | service (silent detector) | request-response (one-shot probe) | `FailoverProvider.swift` / `TunnelWatchdog.swift` (Logger pattern) | partial (no exact analog for `canOpenURL` probe service) |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift` *(NEW)* | service (file I/O + masking) | file-I/O + transform | `PacketTunnelKit/AppGroupContainer.swift` (`exportSingBoxLogToDocuments()`) | **exact** (extends same export pattern) |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/HelpView.swift` *(NEW)* | view (FAQ screen) | request-response (read-only) | `SettingsFeature/RulesViewerSection.swift` (DisclosureGroup pattern) | role-match |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsSection.swift` *(NEW, optional)* | view (settings section) | request-response | `SettingsFeature/SecuritySection.swift` | **exact** (Section/header/footer w/ L10n) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` *(MODIFY)* | view (host) | request-response | self (existing `fullScreenCover` для QR) | self-pattern |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` *(MODIFY)* | view (button) | UI state | self (existing `ZStack { Circle + Image }`) | self-pattern |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` *(MODIFY)* | service (hardcoded → L10n) | n/a | `L10n.swift` (`importError*` keys уже паттерн) | exact |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift` *(MODIFY)* | view (picker labels → L10n) | n/a | `L10n.swift` (`serverDetail*` keys уже паттерн) | exact |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` *(MODIFY)* | view (height constants) | n/a | self (`static let serverRowH = 80`) | self-pattern |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` *(MODIFY)* | view (add 2 sections + NavLink) | request-response | self + `AdvancedSettingsView.swift` Form composition | self-pattern |
| `BBTB/Packages/Localization/Sources/Localization/L10n.swift` *(MODIFY)* | resource accessor | n/a | self (`static var x: String { tr("x") }`) | self-pattern |
| `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` *(MODIFY)* | resource (JSON) | n/a | self | self-pattern |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MAXDetectorTests.swift` *(NEW)* | test | unit | `Tests/MainScreenFeatureTests/MainScreenViewModelDeepLinkTests.swift` | role-match |
| `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/DiagnosticsExporterTests.swift` *(NEW)* | test | unit | `Tests/SettingsFeatureTests/SettingsViewModelTests.swift` | role-match |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnboardingViewModelTests.swift` *(NEW)* | test | unit | `Tests/MainScreenFeatureTests/ConnectionTimerTests.swift` (pure helper test) + `SettingsViewModelTests.swift` (UserDefaults setup/teardown) | role-match |

---

## Pattern Assignments

### `OnboardingView.swift` (NEW — view, request-response)

**Analog:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/EmptyStateCard.swift` (полные 49 строк — структура **идентична будущему OnboardingView**).

**Imports pattern** (EmptyStateCard.swift, lines 1-3):
```swift
import SwiftUI
import Localization
import DesignSystem
```

**Public struct + init pattern** (EmptyStateCard.swift, lines 6-13):
```swift
public struct EmptyStateCard: View {
    public let onAddFromClipboard: () -> Void
    public let onScanQR: () -> Void

    public init(onAddFromClipboard: @escaping () -> Void, onScanQR: @escaping () -> Void) {
        self.onAddFromClipboard = onAddFromClipboard
        self.onScanQR = onScanQR
    }
```

**Body composition** (EmptyStateCard.swift, lines 15-48 — копировать структурно):
```swift
public var body: some View {
    VStack(spacing: DS.Spacing.lg) {
        Image(systemName: "tray")
            .font(.system(size: 56))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

        Text(L10n.emptyTitle)              // ← заменить на L10n.onboardingTitle
            .font(DS.Typography.title)

        Text(L10n.emptySubtitle)           // ← заменить на L10n.onboardingSubtitle
            .font(DS.Typography.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        VStack(spacing: DS.Spacing.md) {
            Button(L10n.actionImportFromClipboard, action: onAddFromClipboard)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(Text(L10n.actionImportFromClipboard))

            Button(L10n.actionScanQR, action: onScanQR)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel(Text(L10n.actionScanQR))
        }
    }
    .padding(DS.Spacing.xl)
    .background(
        RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
            .fill(Color.secondary.opacity(0.1))
    )
    .frame(maxWidth: 360)
}
```

**Notes for planner:**
- Структура `EmptyStateCard` на 95% совпадает с задачей `OnboardingView` (D-02: title + subtitle + 2 CTA).
- Различия: Onboarding — fullScreenCover (no card background), может занимать весь экран; CTA — `L10n.onboardingPaste` / `L10n.onboardingScanQR`; иконка — на усмотрение Figma.
- Использовать `DS.Spacing.*`, `DS.Typography.*`, `DS.Radius.*` (DesignSystem package) — ни одного hardcoded pt.
- Pattern accessibility identifier: добавить `BBTB.Onboarding.PasteButton` / `BBTB.Onboarding.QRButton` (по аналогии `BBTB.ConnectionButton`, `BBTB.AddButton` в `MainScreenView.swift`).

---

### `OnboardingViewModel.swift` (NEW, optional — view-model)

**Analog:** `SettingsFeature/SettingsViewModel.swift` (lines 22-28 — `@MainActor final class` + `@AppStorage` pattern).

**Class declaration pattern** (SettingsViewModel.swift, lines 22-28):
```swift
@MainActor
public final class SettingsViewModel: ObservableObject {
    // MARK: - Stored prefs

    /// KILL-03 — kill switch toggle.
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false
```

**For OnboardingViewModel — recommended skeleton:**
```swift
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @AppStorage("app.bbtb.hasShownOnboarding") public var hasShownOnboarding: Bool = false

    public init() {}

    public func markCompleted() {
        hasShownOnboarding = true
    }
}
```

**Alternative — inline `@AppStorage` в MainScreenView без отдельного VM:** также acceptable (см. CONTEXT D-01 + RESEARCH Open Question 5). Planner выбирает. `static let dismissedKey = "app.bbtb.hasShownOnboarding"` — добавить как public static const в один из файлов, чтобы тесты могли cleanup.

---

### `MainScreenView.swift` (MODIFY — host integration)

**Analog:** self (existing `fullScreenCover` для QR scanner, lines 114-135).

**Existing fullScreenCover pattern** (MainScreenView.swift, lines 114-135 — копировать механику):
```swift
#if os(iOS)
.fullScreenCover(isPresented: $showQRScanner) {
    QRScannerView(
        onCodeScanned: { uri in
            viewModel.importFromQRString(uri)
            showQRScanner = false
        },
        onCancel: { showQRScanner = false }
    )
}
#elseif os(macOS)
.sheet(isPresented: $showQRScanner) {
    QRScannerView(
        onCodeScanned: { uri in
            viewModel.importFromQRString(uri)
            showQRScanner = false
        },
        onCancel: { showQRScanner = false }
    )
    .frame(width: 480, height: 640)
}
#endif
```

**For Onboarding — replicate same structure:**
```swift
// New @State / @AppStorage at top of MainScreenView struct (line ~13):
@AppStorage("app.bbtb.hasShownOnboarding") private var hasShownOnboarding: Bool = false

// New modifier in body (insert after existing `.fullScreenCover($showQRScanner)`, ~line 136):
.fullScreenCover(isPresented: Binding(
    get: { !hasShownOnboarding },
    set: { newValue in if newValue { hasShownOnboarding = false } }  // dismiss flips флаг
)) {
    OnboardingView(
        onPaste: {
            viewModel.importFromPasteboard()
            // Pitfall: НЕ сетим hasShownOnboarding=true сразу — ждём успешный import.
        },
        onScanQR: { showQRScanner = true },
        onImportSucceeded: { hasShownOnboarding = true }
    )
}
```

**Existing addMenu Menu pattern** (MainScreenView.swift, lines 151-167 — расширить для IMP-03 file picker):
```swift
@ViewBuilder
private var addMenu: some View {
    Menu {
        Button {
            showQRScanner = true
        } label: {
            Label(L10n.menuScanQR, systemImage: "qrcode.viewfinder")
        }
        Button(action: viewModel.importFromPasteboard) {
            Label(L10n.menuImportFromClipboard, systemImage: "doc.on.clipboard")
        }
        // ← INSERT: новый Button для file picker
        Button {
            showFileImporter = true
        } label: {
            Label(L10n.menuImportFromFile, systemImage: "doc")
        }
    } label: {
        Image(systemName: "plus")
            .font(.title3)
    }
    .accessibilityIdentifier("BBTB.AddButton")
    .accessibilityLabel(Text(L10n.menuAddConfig))
}
```

**fileImporter modifier — добавить после addMenu attachment (см. RESEARCH Pattern 2):**
```swift
@State private var showFileImporter = false

// В body — после .toolbar:
.fileImporter(
    isPresented: $showFileImporter,
    allowedContentTypes: [.json, .yaml, .yml],
    allowsMultipleSelection: false
) { result in
    Task {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                viewModel.lastError = L10n.importErrorFileAccessDenied
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                await viewModel.importFromRawString(text)
            } catch {
                viewModel.lastError = L10n.importErrorFileReadFailed
            }
        case .failure(let error):
            viewModel.lastError = error.localizedDescription
        }
    }
}
```

UTType extension (новый файл `Extensions/UTType+YAML.swift` или внизу `MainScreenView.swift`):
```swift
import UniformTypeIdentifiers
extension UTType {
    static var yaml: UTType { UTType(filenameExtension: "yaml") ?? .data }
    static var yml: UTType { UTType(filenameExtension: "yml") ?? .data }
}
```

---

### `ConnectionButton.swift` (MODIFY — add spinner overlay)

**Analog:** self (existing ZStack + Circle + Image pattern, lines 17-32).

**Existing body** (ConnectionButton.swift, lines 17-32):
```swift
public var body: some View {
    Button(action: action) {
        ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: diameter, height: diameter)
            Image(systemName: "power")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: state)
        }
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityIdentifier("BBTB.ConnectionButton")
}
```

**Pattern для Phase 11 (placeholder, replace по Figma):**
```swift
public var body: some View {
    Button(action: action) {
        ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: diameter, height: diameter)
            Image(systemName: "power")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: state)
                .opacity(isConnecting ? 0 : 1)  // скрываем icon во время spinning

            if isConnecting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.large)
            }
        }
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityIdentifier("BBTB.ConnectionButton")
}

private var isConnecting: Bool {
    if case .connecting = state { return true }
    return false
}
```

**CRITICAL constraints (RESEARCH Anti-Patterns):**
- НЕ переписывать `ZStack { Circle + Image }` целиком — это сломает `BBTB.ConnectionButton` identifier и existing snapshot tests.
- Точный стиль spinner (`ProgressView()` default vs custom `Circle().trim().rotationEffect`) — **по Figma**, пока placeholder.

---

### `MAXDetector.swift` (NEW — service, request-response one-shot probe)

**Closest analog (partial):** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` (lines 57+ — Logger initialization pattern + service struct).

**Logger initialization pattern** (TunnelWatchdog.swift, line 57; FailoverProvider.swift, line 71):
```swift
private let log = Logger(subsystem: "app.bbtb.client", category: "tunnel-watchdog")
```

**Recommended skeleton (composite of RESEARCH Pattern 5 + codebase Logger convention):**
```swift
import Foundation
import os

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public enum MAXDetector {
    private static let logger = Logger(subsystem: "app.bbtb.client", category: "detection")

    /// One-shot detection при cold start. Async-safe; никакого UI side-effect.
    @MainActor
    public static func detectAndLog() {
        #if os(iOS)
        detectIOS()
        #elseif os(macOS)
        detectMacOS()
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func detectIOS() {
        // RESEARCH A1: candidate schemes — нужна device-UAT verification.
        let schemes = ["max", "max-app", "ru-max", "vkmax"]
        for scheme in schemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
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
        // RESEARCH A2: candidate bundles — нужна device-UAT verification.
        let candidates = ["ru.vk.max", "com.vkontakte.max", "chat.max.app", "ru.max.messenger"]
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

**privacy: .public vs .private convention** — см. `ConfigImporter.swift:623, 627` и `MainScreenViewModel.swift`:
```swift
os.Logger(subsystem: "app.bbtb", category: "ConfigImporter")
    .info("Applied CDN fronting: \(profile.provider.rawValue, privacy: .public)")
```

**Test mockability (RESEARCH Wave 0 Gap):** для unit-тестов добавить protocol abstraction:
```swift
public protocol URLSchemeQueryable {
    func canOpenURL(_ url: URL) -> Bool
}
#if os(iOS)
extension UIApplication: URLSchemeQueryable {}
#endif
// MAXDetector принимает `URLSchemeQueryable = UIApplication.shared` в DI ctor для test.
```

**Info.plist (iOS app target):** добавить `LSApplicationQueriesSchemes` массив со списком candidate schemes. Файл — `BBTB/App/iOSApp/Info.plist`.

---

### `DiagnosticsExporter.swift` (NEW — service, file-I/O + transform)

**Analog:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` (`exportSingBoxLogToDocuments()`, lines 108-123 — **точная база**, extends with masking + metadata).

**Existing export pattern** (AppGroupContainer.swift, lines 108-123):
```swift
@discardableResult
public static func exportSingBoxLogToDocuments() -> URL? {
    let src = URL(fileURLWithPath: singBoxLogPath)
    guard FileManager.default.fileExists(atPath: src.path) else { return nil }
    guard let docs = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first
    else { return nil }
    let dst = docs.appendingPathComponent("sing-box.log")
    try? FileManager.default.removeItem(at: dst)
    do {
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    } catch {
        return nil
    }
}
```

**Recommended skeleton (composite of RESEARCH Pattern 4 + AppGroupContainer log path):**
```swift
import Foundation
import os
import PacketTunnelKit  // for AppGroupContainer.singBoxLogPath

public enum DiagnosticsExporter {
    private static let logger = Logger(subsystem: "app.bbtb.client", category: "diagnostics")

    /// Подготавливает .txt с tail логов + metadata + IP masking.
    /// Возвращает nil если sing-box.log отсутствует (см. RESEARCH Pitfall 8).
    public static func prepareLog() async -> URL? {
        let logPath = AppGroupContainer.singBoxLogPath
        guard FileManager.default.fileExists(atPath: logPath),
              let raw = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            logger.info("DiagnosticsExporter: no sing-box.log present")
            return nil
        }
        let tail = String(raw.suffix(2_000_000))  // 2MB cap
        let masked = maskIPv4(tail)

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

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bbtb-log-\(ISO8601DateFormatter().string(from: Date())).txt")
        do {
            try payload.write(to: tmpURL, atomically: true, encoding: .utf8)
            return tmpURL
        } catch {
            logger.error("DiagnosticsExporter: write failed \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// D-12 regex pattern. Internal для unit-тестов.
    internal static func maskIPv4(_ input: String) -> String {
        let pattern = #"(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "$1xxx")
    }

    internal static func anonymousDeviceID() -> String {
        let key = "app.bbtb.anonymousDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
```

**Notes:**
- SettingsFeature `Package.swift` currently НЕ depends on `PacketTunnelKit`. Planner должен **либо** (a) добавить dependency на PacketTunnelKit в SettingsFeature, **либо** (b) положить DiagnosticsExporter в MainScreenFeature (которая уже использует AppGroupContainer transitively через ConfigImporter), **либо** (c) переэкспортировать `singBoxLogPath` через intermediate boundary. Recommendation: (a) — explicit dependency clearest.

---

### `HelpView.swift` (NEW — view, request-response read-only)

**Analog:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift` (DisclosureGroup pattern, lines 174-228).

**DisclosureGroup pattern** (RulesViewerSection.swift, lines 188-228):
```swift
DisclosureGroup(isExpanded: $isExpanded) {
    expandedContent
} label: {
    HStack(spacing: 8) {
        Image(systemName: categoryIcon)
            .foregroundStyle(categoryColor)
            .frame(width: 22, alignment: .center)
            .accessibilityHidden(true)
        Text(matcherName)
            .font(.body)
        Spacer(minLength: 0)
        countBadge
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("\(matcherName), \(countBadgeAccessibilityLabel)"))
}
.disabled(items.isEmpty)
```

**Recommended skeleton for HelpView (5 FAQ topics):**
```swift
import SwiftUI
import Localization

public struct HelpView: View {
    public init() {}

    public var body: some View {
        List {
            Section {
                FAQRow(question: L10n.helpFaq1Question, answer: L10n.helpFaq1Answer)
                FAQRow(question: L10n.helpFaq2Question, answer: L10n.helpFaq2Answer)
                FAQRow(question: L10n.helpFaq3Question, answer: L10n.helpFaq3Answer)
                FAQRow(question: L10n.helpFaq4Question, answer: L10n.helpFaq4Answer)
                FAQRow(question: L10n.helpFaq5Question, answer: L10n.helpFaq5Answer)
            } footer: {
                Text(L10n.helpFooter)
            }
        }
        .navigationTitle(L10n.helpTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .textSelection(.enabled)
        } label: {
            Text(question)
                .font(.body)
                .multilineTextAlignment(.leading)
        }
    }
}
```

**FAQ темы из CONTEXT D-09 — 5 пунктов:**
1. Как добавить сервер
2. Что делать если не подключается
3. Что такое WebRTC (веб-RTC утечка) leak
4. Почему 22 приложения из РФ детектируют VPN (см. `wiki/vpn-detection-by-apps.md`)
5. Ограничения детектирования MAX

---

### `DiagnosticsSection.swift` / inline в `SettingsView.swift` (modify)

**Analog:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SecuritySection.swift` (полная структура — 60 строк).

**Section + header + footer pattern** (SecuritySection.swift, lines 20-58):
```swift
public var body: some View {
    Section {
        Toggle(L10n.settingsSecurityCertPinningLabel, isOn: $viewModel.certPinningEnabled)
            .accessibilityHint(Text(L10n.settingsSecurityCertPinningFooter))
        // ... other rows
    } header: {
        Text(L10n.settingsSecuritySection)
    } footer: {
        Text(L10n.settingsSecurityCertPinningFooter)
    }
}
```

**Recommended Diagnostics Section skeleton (RESEARCH Pattern 3 — ShareLink composite):**
```swift
Section {
    if let url = preparedLogURL {
        ShareLink(item: url) {
            Label(L10n.diagnosticsShareLog, systemImage: "square.and.arrow.up")
        }
    } else {
        Button {
            Task {
                preparedLogURL = await DiagnosticsExporter.prepareLog()
                if preparedLogURL == nil {
                    showNoLogsAlert = true
                }
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
        Text("v\(appVer) (\(osVer))")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }
}
```

**Settings parent integration — где помещать в SettingsView.swift:**

Existing `SettingsView.swift` Form pattern (lines 13-45):
```swift
public var body: some View {
    Form {
        Section { AutoReconnectToggleSection(...) } header: {...} footer: {...}
        Section { KillSwitchToggleSection(...) } header: {...} footer: {...}
        Section {
            NavigationLink(destination: AdvancedSettingsView(viewModel: viewModel)) {
                Text(L10n.settingsAdvancedEntryLabel)
            }
        }
        // ← ВСТАВИТЬ ПОСЛЕ AdvancedSettings (см. CONTEXT D-09/D-10):
        // Section { DiagnosticsSection(...) } header: { Text(L10n.diagnosticsSection) }
        // Section { NavigationLink(destination: HelpView()) { Text(L10n.helpTitle) } }
    }
    .navigationTitle(L10n.settingsTitle)
}
```

**NavigationLink для Help — точный образец в SettingsView.swift, lines 40-44:**
```swift
Section {
    NavigationLink(destination: AdvancedSettingsView(viewModel: viewModel)) {
        Text(L10n.settingsAdvancedEntryLabel)
    }
}
```

---

### `ConfigImporter.swift` lines 42, 984 (MODIFY — L10n cleanup)

**Current hardcoded violations:**

ConfigImporter.swift line 42:
```swift
case .noSupportedServers: return "В источнике нет поддерживаемых конфигураций."
```

ConfigImporter.swift line 984:
```swift
let derived = sanitized ?? (URL(string: url)?.host) ?? "Подписка"
```

**Replacement pattern** (existing convention — L10n.swift lines 88-92):
```swift
// ConfigImporter.swift line 42:
case .noSupportedServers: return L10n.importErrorNoSupportedConfigs  // ← УЖЕ существует в L10n!

// ConfigImporter.swift line 984:
let derived = sanitized ?? (URL(string: url)?.host) ?? L10n.subscriptionFallbackName  // ← добавить новый ключ
```

**Verify before edit:**
```bash
grep "importErrorNoSupportedConfigs\|subscriptionFallbackName" /Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/Localization/Sources/Localization/L10n.swift
```
`importErrorNoSupportedConfigs` уже существует (L10n.swift line 88). `subscriptionFallbackName` — добавить новый.

---

### `TransportPicker.swift` lines 79-83 (MODIFY — L10n cleanup)

**Current hardcoded:**
```swift
Text("TCP").tag(TransportSelection.tcp)
Text("WebSocket").tag(TransportSelection.ws)
Text("gRPC").tag(TransportSelection.grpc)
Text("HTTP/2").tag(TransportSelection.http)
Text("HTTPUpgrade").tag(TransportSelection.httpUpgrade)
```

**Replacement (per RESEARCH Pitfall 6 naming convention):**
```swift
Text(L10n.transportLabelTcp).tag(TransportSelection.tcp)
Text(L10n.transportLabelWebSocket).tag(TransportSelection.ws)
Text(L10n.transportLabelGrpc).tag(TransportSelection.grpc)
Text(L10n.transportLabelHttp2).tag(TransportSelection.http)
Text(L10n.transportLabelHttpUpgrade).tag(TransportSelection.httpUpgrade)
```

**Note:** В ru/en values оба будут идентичными ("TCP", "WebSocket" не переводятся), но per LOC-02 правилу — никаких hardcoded строк в `Text(...)`. См. RESEARCH "Don't Hand-Roll" таблицу.

---

### `ServerListSheet.swift` lines 45-51 (MODIFY — height constants)

**Current static let block** (ServerListSheet.swift, lines 43-51):
```swift
// Heights derived from DS.Spacing constants (server row minHeight=56 + padding.vertical md×2=24 = 80;
// AutoCell minHeight=72 + padding md×2=24 + parent top md=12 + bottom sm=8 = 116; etc.)
private static let headerH:     CGFloat = 81   // xl-pad + title-row + md-pad + divider
private static let autoCellH:   CGFloat = 116  // cell body + surrounding padding
private static let subHeaderH:  CGFloat = 44   // SubscriptionHeader row
private static let manHeaderH:  CGFloat = 36   // manual-section label row
private static let serverRowH:  CGFloat = 80   // minHeight 56 + vertical padding 24
private static let emptyCardH:  CGFloat = 220  // empty-state card
private static let bottomBuf:   CGFloat = 40   // safe-area / breathing room
```

**Modification approach (CONTEXT D-08):**
- Planner ЧИТАЕТ `11-FIGMA-SPEC.md` для точных pt значений.
- Обновляет numeric values (не структуру — структура `estimatedHeight()` и `computeDetents()` остаётся).
- Phase 11 UAT — RESEARCH Pitfall 7 — тестировать 3 scenario: 8 servers / 1 server / empty pool.

---

### `MAXDetectorTests.swift` (NEW — test)

**Analog:** `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConnectionTimerTests.swift` (pure helper test pattern).

**Pure helper test pattern** (ConnectionTimerTests.swift, lines 1-23):
```swift
import XCTest
@testable import MainScreenFeature

final class ConnectionTimerTests: XCTestCase {
    func test_format_zero() {
        XCTAssertEqual(ConnectionTimer.format(interval: 0), "00:00:00")
    }
    // ... другие cases
}
```

**For MAXDetector — mock URLSchemeQueryable test:**
```swift
import XCTest
@testable import MainScreenFeature

final class MAXDetectorTests: XCTestCase {
    private final class MockApp: URLSchemeQueryable {
        var registeredSchemes: Set<String> = []
        func canOpenURL(_ url: URL) -> Bool {
            registeredSchemes.contains(url.scheme ?? "")
        }
    }

    func test_iOS_detectsFirstMatchingScheme() {
        let mock = MockApp()
        mock.registeredSchemes = ["max-app"]
        let result = MAXDetector.detectInternal(query: mock, candidates: ["max", "max-app", "vkmax"])
        XCTAssertEqual(result, "max-app")
    }

    func test_iOS_returnsNilWhenNoMatches() {
        let mock = MockApp()
        let result = MAXDetector.detectInternal(query: mock, candidates: ["max", "max-app"])
        XCTAssertNil(result)
    }
}
```

**Note:** `detectInternal(query:candidates:)` — testable extraction точки. `detectAndLog()` остаётся public API, внутри вызывает `detectInternal` + logger.

---

### `DiagnosticsExporterTests.swift` (NEW — test)

**Analog:** `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift` (UserDefaults setUp/tearDown pattern, lines 15-40).

**UserDefaults cleanup pattern** (SettingsViewModelTests.swift, lines 17-40):
```swift
final class SettingsViewModelTests: XCTestCase {
    private static let dismissedKey = "app.bbtb.minAppVersion.dismissed"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.dismissedKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.dismissedKey)
        try await super.tearDown()
    }
}
```

**Recommended DiagnosticsExporterTests:**
```swift
import XCTest
@testable import SettingsFeature

final class DiagnosticsExporterTests: XCTestCase {
    private static let deviceIDKey = "app.bbtb.anonymousDeviceID"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.deviceIDKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.deviceIDKey)
        try await super.tearDown()
    }

    func test_maskIPv4_replacesLastOctet() {
        XCTAssertEqual(DiagnosticsExporter.maskIPv4("192.168.1.42"), "192.168.1.xxx")
    }

    func test_maskIPv4_preservesNonIP() {
        XCTAssertEqual(DiagnosticsExporter.maskIPv4("user@host:8080"), "user@host:8080")
    }

    func test_maskIPv4_multipleInOneString() {
        let input = "connect 10.0.0.1 -> 8.8.8.8"
        let out = DiagnosticsExporter.maskIPv4(input)
        XCTAssertEqual(out, "connect 10.0.0.xxx -> 8.8.8.xxx")
    }

    func test_anonymousDeviceID_stable() {
        let id1 = DiagnosticsExporter.anonymousDeviceID()
        let id2 = DiagnosticsExporter.anonymousDeviceID()
        XCTAssertEqual(id1, id2)
    }

    func test_prepareLog_returnsNilWhenLogAbsent() async {
        // Test runs in an environment где AppGroupContainer.singBoxLogPath
        // не существует (test process не extension). Return must be nil.
        let url = await DiagnosticsExporter.prepareLog()
        XCTAssertNil(url)
    }
}
```

---

### `OnboardingViewModelTests.swift` (NEW — test)

**Analog:** `MainScreenFeatureTests/ConnectionTimerTests.swift` (pure helper) + `SettingsViewModelTests.swift` (UserDefaults).

**Test skeleton:**
```swift
import XCTest
@testable import MainScreenFeature

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private static let key = "app.bbtb.hasShownOnboarding"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.key)
        try await super.tearDown()
    }

    func test_initial_hasShownOnboarding_isFalse() {
        let vm = OnboardingViewModel()
        XCTAssertFalse(vm.hasShownOnboarding)
    }

    func test_markCompleted_persistsFlag() {
        let vm = OnboardingViewModel()
        vm.markCompleted()
        XCTAssertTrue(vm.hasShownOnboarding)
        // Verify persistence across instances:
        let vm2 = OnboardingViewModel()
        XCTAssertTrue(vm2.hasShownOnboarding)
    }
}
```

---

### `L10n.swift` + `Localizable.xcstrings` (MODIFY — add ~30 keys)

**Analog pattern** (L10n.swift lines 47-99 — Non-launch `static var x: String { tr("x") }` block).

**Phase 11 keys recommended (по RESEARCH Pitfall 6 naming):**

```swift
// Phase 11 — Onboarding
public static var onboardingTitle: String { tr("onboarding.title") }
public static var onboardingSubtitle: String { tr("onboarding.subtitle") }
public static var onboardingPaste: String { tr("onboarding.cta_paste") }
public static var onboardingScanQR: String { tr("onboarding.cta_qr") }

// Phase 11 — Help (FAQ)
public static var helpTitle: String { tr("help.title") }
public static var helpFooter: String { tr("help.footer") }
public static var helpFaq1Question: String { tr("help.faq1.question") }
public static var helpFaq1Answer: String { tr("help.faq1.answer") }
public static var helpFaq2Question: String { tr("help.faq2.question") }
public static var helpFaq2Answer: String { tr("help.faq2.answer") }
public static var helpFaq3Question: String { tr("help.faq3.question") }
public static var helpFaq3Answer: String { tr("help.faq3.answer") }
public static var helpFaq4Question: String { tr("help.faq4.question") }
public static var helpFaq4Answer: String { tr("help.faq4.answer") }
public static var helpFaq5Question: String { tr("help.faq5.question") }
public static var helpFaq5Answer: String { tr("help.faq5.answer") }

// Phase 11 — Diagnostics
public static var diagnosticsSection: String { tr("diagnostics.section") }
public static var diagnosticsExportLog: String { tr("diagnostics.export_log") }
public static var diagnosticsShareLog: String { tr("diagnostics.share_log") }
public static var diagnosticsLast24h: String { tr("diagnostics.last_24h") }
public static var diagnosticsNoLogsTitle: String { tr("diagnostics.no_logs.title") }
public static var diagnosticsNoLogsMessage: String { tr("diagnostics.no_logs.message") }

// Phase 11 — Import (file picker)
public static var menuImportFromFile: String { tr("menu.import_from_file") }
public static var importErrorFileAccessDenied: String { tr("import.error.file_access_denied") }
public static var importErrorFileReadFailed: String { tr("import.error.file_read_failed") }

// Phase 11 — Transport labels (LOC-02)
public static var transportLabelTcp: String { tr("transport.label_tcp") }
public static var transportLabelWebSocket: String { tr("transport.label_websocket") }
public static var transportLabelGrpc: String { tr("transport.label_grpc") }
public static var transportLabelHttp2: String { tr("transport.label_http2") }
public static var transportLabelHttpUpgrade: String { tr("transport.label_http_upgrade") }

// Phase 11 — Subscription fallback name (ConfigImporter line 984)
public static var subscriptionFallbackName: String { tr("subscription.fallback_name") }
```

**xcstrings entry pattern** (verified Localizable.xcstrings:1-12):
```json
"onboarding.title": {
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "Bring back the bug" } },
    "ru": { "stringUnit": { "state": "translated", "value": "Верни жука" } }
  }
}
```

---

## Shared Patterns

### Pattern S1: SwiftUI View pure-prop init

**Source:** `MinAppVersionSheet.swift` lines 25-40, `EmptyStateCard.swift` lines 6-13.

**Apply to:** `OnboardingView`, `HelpView`, `DiagnosticsSection`.

```swift
public struct XView: View {
    public let prop1: String
    public let onAction: () -> Void

    public init(prop1: String, onAction: @escaping () -> Void) {
        self.prop1 = prop1
        self.onAction = onAction
    }

    public var body: some View {
        // ...
    }
}
```

**Justification:** Все existing modal/section views (MinAppVersionSheet, EmptyStateCard, ForceUpdateRulesButton, KillSwitchToggleSection) — pure data Views без `@StateObject`. Owner управляет state.

### Pattern S2: @AppStorage flag для one-shot UI gate

**Source:** `MainScreenViewModel.swift` line 108 (`dismissedMinAppVersion`), `SettingsViewModel.swift` line 28 (`killSwitchEnabled`).

**Apply to:** `hasShownOnboarding` (Onboarding), `anonymousDeviceID` (Diagnostics).

```swift
@AppStorage("app.bbtb.hasShownOnboarding") public var hasShownOnboarding: Bool = false
```

**Key naming convention:** `app.bbtb.<feature>.<element>` (snake_case в xcstrings, camelCase для Swift var).

### Pattern S3: Logger initialization

**Source:** `TunnelWatchdog.swift:57`, `ConfigImporter.swift:622`, `SettingsViewModel.swift:320`.

**Apply to:** `MAXDetector`, `DiagnosticsExporter`.

```swift
private static let logger = Logger(subsystem: "app.bbtb.client", category: "<feature-category>")
```

**Categories — фикс conventions:** `detection`, `diagnostics`, `tunnel-controller`, `failover`, `settings-auto-reconnect`. Не дублировать существующие.

### Pattern S4: privacy: .public / .private в Logger

**Source:** `ConfigImporter.swift:623,627`, `MAXDetector` RESEARCH Pattern 5.

**Apply to:** Любой new Logger call.

```swift
logger.info("X happened: \(value, privacy: .public)")   // safe для diagnostics
logger.info("Path: \(url.path, privacy: .private)")     // sensitive
```

### Pattern S5: L10n accessor через `static var x: String { tr("...") }`

**Source:** `L10n.swift` lines 47+ (Phase 6e Theme A — lazy resolution).

**Apply to:** Все новые ключи Phase 11 (НЕ launch-critical — `static var`, не `static let`).

```swift
public static var diagnosticsSection: String { tr("diagnostics.section") }
```

### Pattern S6: Section + header + footer + accessibilityHint

**Source:** `SecuritySection.swift:21-58`, `AntiDPISection.swift:24-69`.

**Apply to:** `DiagnosticsSection` (inline в SettingsView или standalone).

```swift
Section {
    Toggle(L10n.xLabel, isOn: $vm.x)
        .accessibilityHint(Text(L10n.xFooter))
} header: {
    Text(L10n.xSection)
} footer: {
    Text(L10n.xFooter)
}
```

### Pattern S7: Accessibility identifier `BBTB.<Feature>.<Element>`

**Source:** `MainScreenView.swift:146,166`, `ConnectionButton.swift:31`, `TransportPicker.swift:88`.

**Apply to:** `OnboardingView` CTA buttons, `HelpView` FAQ rows (если важны для UI тестов).

```swift
.accessibilityIdentifier("BBTB.Onboarding.PasteButton")
.accessibilityIdentifier("BBTB.Onboarding.QRButton")
.accessibilityIdentifier("BBTB.Settings.HelpRow")
.accessibilityIdentifier("BBTB.Settings.DiagnosticsExportButton")
```

### Pattern S8: Cross-platform fullScreenCover / sheet

**Source:** `MainScreenView.swift:114-135` (QR scanner).

**Apply to:** Onboarding (fullScreenCover iOS / sheet macOS с .frame).

```swift
#if os(iOS)
.fullScreenCover(isPresented: $flag) { OnboardingView(...) }
#elseif os(macOS)
.sheet(isPresented: $flag) {
    OnboardingView(...)
        .frame(width: 480, height: 640)
}
#endif
```

### Pattern S9: UserDefaults cleanup в test setUp/tearDown

**Source:** `SettingsViewModelTests.swift:17-40`.

**Apply to:** `OnboardingViewModelTests`, `DiagnosticsExporterTests`.

```swift
private static let key = "app.bbtb.hasShownOnboarding"

override func setUp() async throws {
    try await super.setUp()
    UserDefaults.standard.removeObject(forKey: Self.key)
}

override func tearDown() async throws {
    UserDefaults.standard.removeObject(forKey: Self.key)
    try await super.tearDown()
}
```

### Pattern S10: Async + defer для security-scoped resource (fileImporter)

**Source:** RESEARCH Pattern 2; нет существующего analog в codebase (Phase 11 — первый fileImporter).

**Apply to:** `MainScreenView.swift` fileImporter callback (IMP-03).

```swift
guard url.startAccessingSecurityScopedResource() else { return }
defer { url.stopAccessingSecurityScopedResource() }
// read
```

### Pattern S11: ProgressView() default circular spinner

**Source:** `QRScannerView.swift:46` — `ProgressView().controlSize(.large).tint(.white)`.

**Apply to:** `ConnectionButton` overlay при `.connecting` state (placeholder до Figma).

```swift
ProgressView()
    .progressViewStyle(.circular)
    .tint(.white)
    .controlSize(.large)
```

### Pattern S12: ShareLink для cross-platform export

**Source:** RESEARCH Pattern 3; нет существующего analog (Phase 11 — первый ShareLink usage).

**Apply to:** Settings `DiagnosticsSection` после `prepareLog()`.

```swift
ShareLink(item: url) {
    Label(L10n.diagnosticsShareLog, systemImage: "square.and.arrow.up")
}
```

---

## No Analog Found

| File | Role | Data Flow | Reason | Fallback |
|------|------|-----------|--------|----------|
| `MAXDetector.swift` (silent app-presence probe) | service | request-response one-shot | Codebase не имеет existing `canOpenURL` / `NSWorkspace.urlForApplication` service. | Use RESEARCH Pattern 5 + Logger convention from `TunnelWatchdog.swift:57`. **No exact analog — use composite.** |
| `fileImporter` modifier (IMP-03) | view modifier | file-I/O | Нет existing fileImporter в codebase — Phase 11 first usage. | Use RESEARCH Pattern 2 (Apple official + Use Your Loaf). Security-scoped resource handling — strict защита. |
| `ShareLink` (TELEM-02) | view modifier | cross-app system share | Phase 11 first SharePicker usage. | Use RESEARCH Pattern 3 (Apple official ShareLink iOS 16+/macOS 13+). |

---

## Metadata

**Analog search scope:**
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` (24 файла) — все прочитаны или grep'ы
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/` (13 файлов) — все прочитаны
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/` (12 файлов) — relevant прочитаны
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/` (AppGroupContainer — full read)
- `BBTB/Packages/Localization/Sources/Localization/` (L10n.swift + xcstrings — full read)
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/` (ConnectionTimerTests, MainScreenViewModelDeepLinkTests)
- `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/` (SettingsViewModelTests)

**Files scanned:** 22 source + 4 tests + Package.swift + xcstrings = 28 files

**Critical patterns to reuse (по приоритету):**
1. **EmptyStateCard → OnboardingView** — структура 1-в-1.
2. **AppGroupContainer.exportSingBoxLogToDocuments → DiagnosticsExporter.prepareLog** — file-read pattern.
3. **SecuritySection → DiagnosticsSection** — Section composition с header/footer.
4. **MainScreenView fullScreenCover(QR) → fullScreenCover(Onboarding)** — modal pattern с cross-platform `#if os(iOS) / #elseif os(macOS)`.
5. **L10n `static var x: String { tr("x") }`** — все 30+ новых ключей в этом стиле.
6. **Logger(subsystem: "app.bbtb.client", category: "...")** — единая convention для MAXDetector + DiagnosticsExporter.

**Pattern extraction date:** 2026-05-15
**Confidence:** HIGH — все аналоги — recent files (Phase 6+) с актуальными conventions; никаких legacy patterns не привлечены.

---

*Phase: 11-onboarding-ux-polish*
*Patterns mapped: 2026-05-15*
