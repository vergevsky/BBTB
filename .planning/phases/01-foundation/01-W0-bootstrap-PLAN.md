---
phase: 01-foundation
plan: W0-bootstrap
type: execute
wave: 1
depends_on: []
files_modified:
  - BBTB.xcworkspace/contents.xcworkspacedata
  - BBTB/BBTB.xcodeproj/project.pbxproj
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/iOSApp/Info.plist
  - BBTB/App/iOSApp/BBTB-iOS.entitlements
  - BBTB/App/iOSApp/Assets.xcassets/AppIcon.appiconset/Contents.json
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
  - BBTB/App/macOSApp/Info.plist
  - BBTB/App/macOSApp/BBTB-macOS.entitlements
  - BBTB/App/macOSApp/Assets.xcassets/AppIcon.appiconset/Contents.json
  - BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift
  - BBTB/App/PacketTunnelExtension-iOS/Info.plist
  - BBTB/App/PacketTunnelExtension-iOS/PacketTunnelExtension-iOS.entitlements
  - BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift
  - BBTB/App/PacketTunnelExtension-macOS/Info.plist
  - BBTB/App/PacketTunnelExtension-macOS/PacketTunnelExtension-macOS.entitlements
  - BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift
  - BBTB/App/AppProxyExtension-macOS/Info.plist
  - BBTB/Config/Common.xcconfig
  - BBTB/Config/Debug.xcconfig
  - BBTB/Config/Release.xcconfig
  - BBTB/Config/ExportOptions-iOS.plist
  - BBTB/Config/ExportOptions-macOS.plist
  - BBTB/Packages/VPNCore/Package.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/VPNCore.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift
  - BBTB/Packages/ProtocolRegistry/Package.swift
  - BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift
  - BBTB/Packages/ProtocolEngine/Package.swift
  - BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift
  - BBTB/Packages/ProtocolEngine/Sources/XrayFallback/XrayFallback.swift
  - BBTB/Packages/ProtocolEngine/Frameworks/.gitkeep
  - BBTB/Packages/Protocols/VLESSReality/Package.swift
  - BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSReality.swift
  - BBTB/Packages/ConfigParser/Package.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigParser.swift
  - BBTB/Packages/KillSwitch/Package.swift
  - BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift
  - BBTB/Packages/PacketTunnelKit/Package.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PacketTunnelKit.swift
  - BBTB/Packages/DesignSystem/Package.swift
  - BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift
  - BBTB/Packages/Localization/Package.swift
  - BBTB/Packages/Localization/Sources/Localization/L10n.swift
  - BBTB/Packages/AppFeatures/Package.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenFeature.swift
  - BBTB/Packages/CrashReporter/Package.swift
  - BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift
  - BBTB/Vendored/.gitkeep
  - BBTB/Vendored/README.md
  - BBTB/Tests/Fixtures/test-config.vless.local.txt.template
  - BBTB/.gitignore
autonomous: false
requirements:
  - CORE-01
  - CORE-02
  - CORE-04
  - CORE-06
  - CORE-07
user_setup:
  - service: apple-developer-portal
    why: "App IDs, App Groups, Keychain Sharing, Provisioning Profiles"
    env_vars: []
    dashboard_config:
      - task: "Зарегистрировать App IDs: app.bbtb.client.ios, app.bbtb.client.macos, app.bbtb.client.ios.tunnel, app.bbtb.client.macos.tunnel, app.bbtb.client.macos.appproxy под Team UAN8W9Q82U"
        location: "https://developer.apple.com/account/resources/identifiers/list"
      - task: "Включить capabilities на каждом App ID: Network Extensions (packet-tunnel-provider; для .appproxy — app-proxy-provider), Personal VPN, App Groups (group.app.bbtb.shared), Keychain Sharing (app.bbtb.shared), Associated Domains (применит только Phase 9 — пока просто зарегистрировать domain import.bbtb.app)"
        location: "https://developer.apple.com/account/resources/identifiers/list — выбрать каждый App ID → Edit → Capabilities"
      - task: "Зарегистрировать App Group group.app.bbtb.shared в Identifiers → App Groups и подключить ко всем 5 App ID"
        location: "https://developer.apple.com/account/resources/identifiers/list/applicationGroup"
      - task: "Создать Development + Distribution Provisioning Profiles для всех App ID (или включить Automatic Signing в Xcode)"
        location: "https://developer.apple.com/account/resources/profiles/list"

must_haves:
  truths:
    - "Xcode 16+ открывает BBTB.xcworkspace без ошибок parsing"
    - "Aggregate scheme BBTB-AllTests существует и собирается под macOS и iOS Simulator"
    - "Все 12 SwiftPM-пакетов компилируются (включая placeholder'ы) под Swift 6"
    - "Команда `xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-iOS -destination 'generic/platform=iOS Simulator'` завершается успешно"
    - "Команда `xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination 'generic/platform=macOS'` завершается успешно"
    - "Bundle ID для каждого target соответствует таблице в CONTEXT.md §1"
    - "App Group group.app.bbtb.shared указан в entitlements всех 5 target'ов"
    - "DEVELOPMENT_TEAM = UAN8W9Q82U зафиксирован в Common.xcconfig"
    - "NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel выставлен в Info.plist обоих PacketTunnelExtension target'ов"
  artifacts:
    - path: "BBTB.xcworkspace"
      provides: "Top-level Xcode workspace"
    - path: "BBTB/BBTB.xcodeproj"
      provides: "Xcode project with all 5 app/extension targets"
    - path: "BBTB/Config/Common.xcconfig"
      provides: "DEVELOPMENT_TEAM, APP_BUNDLE_ID_PREFIX, MARKETING_VERSION, CURRENT_PROJECT_VERSION"
      contains: "DEVELOPMENT_TEAM = UAN8W9Q82U"
    - path: "BBTB/App/iOSApp/BBTB-iOS.entitlements"
      provides: "iOS app entitlements"
      contains: "com.apple.developer.networking.networkextension"
    - path: "BBTB/App/macOSApp/BBTB-macOS.entitlements"
      provides: "macOS app entitlements"
      contains: "com.apple.security.app-sandbox"
    - path: "BBTB/Packages/PacketTunnelKit/Package.swift"
      provides: "Manifest for PacketTunnelKit"
      contains: "PacketTunnelKit"
    - path: "BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift"
      provides: "Protocol contract for protocol plugins (CORE-02)"
      contains: "public protocol VPNProtocolHandler"
    - path: "BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift"
      provides: "Plugin registry stub"
      contains: "public final class ProtocolRegistry"
    - path: "BBTB/Vendored/README.md"
      provides: "Инструкция куда положить libbox.xcframework"
    - path: "BBTB/.gitignore"
      provides: "Игнорирует .local.txt, build/, DerivedData/"
      contains: "test-config.vless.local.txt"
  key_links:
    - from: "BBTB/App/iOSApp/BBTB-iOS.entitlements"
      to: "BBTB/App/PacketTunnelExtension-iOS/PacketTunnelExtension-iOS.entitlements"
      via: "shared App Group group.app.bbtb.shared + shared Keychain group"
      pattern: "group\\.app\\.bbtb\\.shared"
    - from: "BBTB/App/PacketTunnelExtension-iOS/Info.plist"
      to: "NetworkExtension framework"
      via: "NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel"
      pattern: "com\\.apple\\.networkextension\\.packet-tunnel"
    - from: "BBTB/Config/Common.xcconfig"
      to: "BBTB.xcodeproj base configuration"
      via: "DEVELOPMENT_TEAM, APP_BUNDLE_ID_PREFIX inheritance"
      pattern: "UAN8W9Q82U"
---

<objective>
**Wave 0 — Bootstrap.** Создать greenfield-скелет Xcode-проекта BBTB на Swift 6 / iOS 18 / macOS 15 со всеми app- и extension-target'ами, SwiftPM-пакетами по структуре `prompts/v2 <swift_package_layout>` (плюс новый `PacketTunnelKit`), правильными entitlements и xcconfig'ами. Цель Wave 0 — собрать пустую сборку, которая компилируется и проходит unit-тестовый прогон (нулевые тесты — Wave 1 их наполнит). Это основа для всех последующих волн.

Purpose: после Wave 0 разработчик может открыть `BBTB.xcworkspace` в Xcode 16, выбрать `BBTB-iOS` или `BBTB-macOS` scheme и нажать Build — сборка должна стать `Build Succeeded` без любых SOCKS/туннельной логики. Это unblock'ает все последующие waves, которые наполнят package'ы кодом.

Output:
- Xcode workspace + project с 5 target'ами (iOS app, macOS app, 2 PacketTunnel extensions, 1 AppProxy extension placeholder)
- 12 SwiftPM пакетов (большинство — placeholder с одним `public struct <Name> {}` для компиляции)
- Entitlements для всех target'ов (R6 / KILL-01 / KILL-02 / SEC-04 будут активированы в Wave 2)
- xcconfig'и с Team ID UAN8W9Q82U
- ExportOptions plist'ы для будущих `xcodebuild -exportArchive`
- `.gitignore` и Vendored/README.md с инструкцией для libbox
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/STATE.md
@.planning/phases/01-foundation/01-CONTEXT.md
@.planning/phases/01-foundation/01-RESEARCH.md
@CLAUDE.md
@prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md
@Wiki/architecture.md
</context>

<tasks>

<task id="W0-T1" type="checkpoint:human-action" gate="blocking" autonomous="false">
  <name>Task W0-T1: Зарегистрировать App IDs, App Group и Capabilities в Apple Developer Portal</name>
  <what-built>Этот checkpoint не создаёт файлов в репозитории — он гейтит дальнейшие шаги. Apple Developer Portal действия делаются ВРУЧНУЮ в браузере (нет CLI для всех нужных операций; `fastlane produce` доступен, но в greenfield-setup быстрее через UI).</what-built>
  <read_first>
    - .planning/phases/01-foundation/01-CONTEXT.md §1 (полный список Bundle IDs)
    - .planning/phases/01-foundation/01-RESEARCH.md §5 «Entitlements» и §15 «TestFlight build»
  </read_first>
  <how-to-verify>
    Пользователь должен зайти на https://developer.apple.com/account/resources/identifiers/list под Team `UAN8W9Q82U` и:

    1. **Зарегистрировать 5 App IDs:**
       - `app.bbtb.client.ios` (тип: App)
       - `app.bbtb.client.macos` (тип: App)
       - `app.bbtb.client.ios.tunnel` (тип: App Extension)
       - `app.bbtb.client.macos.tunnel` (тип: App Extension)
       - `app.bbtb.client.macos.appproxy` (тип: App Extension) — зарезервирован для Phase 8

    2. **На каждом из 4 не-placeholder App ID включить capabilities:**
       - Network Extensions → packet-tunnel-provider (на `.tunnel` ID — единственное; на `.client` ID — выбрать packet-tunnel; на macOS-`.appproxy` — app-proxy-provider)
       - Personal VPN (на `.client` App IDs обеих платформ)
       - App Groups: `group.app.bbtb.shared`
       - Keychain Sharing: `app.bbtb.shared`
       - Associated Domains: добавить `applinks:import.bbtb.app` на `.client` App IDs (только зарегистрировать; активация в Phase 9)

    3. **App Group registration:** Identifiers → App Groups → `+` → Description «BBTB shared» → Identifier `group.app.bbtb.shared` → Save.

    4. **Provisioning Profiles:** Либо включить Xcode Automatic Signing (после W0-T2), либо вручную создать Development+Distribution profiles для каждого App ID.

    После выполнения — ответить в чате «done» или прикрепить скриншот списка зарегистрированных Identifiers.

    **Что НЕ нужно делать сейчас (отложено):**
    - Создавать App Store Connect app records (это Wave 5, перед `xcodebuild archive`)
    - Beta App Review (Phase 12)
    - Купить домен `import.bbtb.app` (опционально, нужен только в Phase 9; в Phase 1 достаточно зарегистрировать его в Associated Domains как заготовку)
  </how-to-verify>
  <resume-signal>Type "done" или прикрепить скриншот списка зарегистрированных Identifiers с включёнными capabilities.</resume-signal>
  <done>Все 5 App IDs зарегистрированы, capabilities выставлены, App Group `group.app.bbtb.shared` существует.</done>
</task>

<task id="W0-T2" type="auto" autonomous="true">
  <name>Task W0-T2: Создать корневую структуру репозитория, xcconfig'и и плейсхолдеры</name>
  <files>
    BBTB/.gitignore,
    BBTB/Config/Common.xcconfig,
    BBTB/Config/Debug.xcconfig,
    BBTB/Config/Release.xcconfig,
    BBTB/Config/ExportOptions-iOS.plist,
    BBTB/Config/ExportOptions-macOS.plist,
    BBTB/Vendored/.gitkeep,
    BBTB/Vendored/README.md,
    BBTB/Tests/Fixtures/test-config.vless.local.txt.template
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-CONTEXT.md §1 «Идентификаторы», §6 «Версионирование»
    - .planning/phases/01-foundation/01-RESEARCH.md §5 «.xcconfig для Team ID», §15 «ExportOptions.plist для TestFlight»
    - prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md `<swift_package_layout>` (строки 74-142)
  </read_first>
  <action>
1. **`BBTB/.gitignore`** — добавить (создать если нет; этот файл может уже частично существовать на уровне репозитория, но `BBTB/`-локальный нужен отдельно):
```
# Xcode
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.xcuserstate
*.xcuserdatad/

# SwiftPM
.swiftpm/
.build/
Packages/*/.build/

# Vendored binaries (vendored libbox.xcframework — НЕ коммитим, только инструкция)
Vendored/libbox.xcframework/

# Local test fixtures (содержат реальные секреты)
Tests/Fixtures/*.local.txt
!Tests/Fixtures/*.local.txt.template

# macOS
.DS_Store
```

2. **`BBTB/Config/Common.xcconfig`:**
```
// Common settings (R6: NB! применяется ко всем target'ам)
DEVELOPMENT_TEAM = UAN8W9Q82U
APP_BUNDLE_ID_PREFIX = app.bbtb.client

// Versioning (Phase 1 = v0.1.0)
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1

// Swift / deployment
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
IPHONEOS_DEPLOYMENT_TARGET = 18.0
MACOSX_DEPLOYMENT_TARGET = 15.0

// Code-signing — Automatic для Phase 1
CODE_SIGN_STYLE = Automatic

// Optimization
SWIFT_OPTIMIZATION_LEVEL = -Onone
```

3. **`BBTB/Config/Debug.xcconfig`:**
```
#include "Common.xcconfig"
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG BBTB_DEBUG
GCC_PREPROCESSOR_DEFINITIONS = DEBUG=1
ENABLE_TESTABILITY = YES
SWIFT_OPTIMIZATION_LEVEL = -Onone
```

4. **`BBTB/Config/Release.xcconfig`:**
```
#include "Common.xcconfig"
SWIFT_ACTIVE_COMPILATION_CONDITIONS = RELEASE
SWIFT_OPTIMIZATION_LEVEL = -O
ENABLE_TESTABILITY = NO
// R1 (SEC-02): release-сборка не пишет debug-логов в консоль; OSLog level controlled by code (см. Wave 3)
```

5. **`BBTB/Config/ExportOptions-iOS.plist`:** (формат plist XML, см. RESEARCH §15)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>teamID</key>
  <string>UAN8W9Q82U</string>
  <key>uploadBitcode</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
```

6. **`BBTB/Config/ExportOptions-macOS.plist`:** — идентично iOS, но без `uploadBitcode` (не применимо к macOS) либо с тем же содержимым.

7. **`BBTB/Vendored/.gitkeep`** — пустой файл.

8. **`BBTB/Vendored/README.md`:**
```markdown
# Vendored Binaries

This directory holds binary frameworks **not** committed to git.

## libbox.xcframework

Download from [SagerNet/sing-box releases](https://github.com/SagerNet/sing-box/releases/tag/v1.13.11)
the `libbox.xcframework.tar.gz` artifact, unpack into this directory so that the
path is:

`BBTB/Vendored/libbox.xcframework/`

Wave 3 (`01-W3-base-tunnel-PLAN.md`) link'ает этот xcframework через `Packages/ProtocolEngine/Package.swift` через `binaryTarget(path: "../../Vendored/libbox.xcframework")`.

Альтернатива: собрать самостоятельно:
```bash
git clone https://github.com/SagerNet/sing-box.git
cd sing-box
gomobile bind -target ios,iossimulator,macos -o libbox.xcframework ./experimental/libbox
```

Требует Go 1.24+ и `golang.org/x/mobile`. См. `.planning/phases/01-foundation/01-RESEARCH.md` §0 «Installation» для деталей.
```

9. **`BBTB/Tests/Fixtures/test-config.vless.local.txt.template`:**
```
# BBTB test fixture template — REPLACE values with your own VLESS+Reality config
# Copy this file to test-config.vless.local.txt (which is .gitignored) and fill in real values.
# Used by Wave 5 DoD validation (api.ipify.org IP-swap check).
#
# Format: one vless:// URI per file.

vless://REPLACE-UUID-HERE@your.server.example:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=REPLACE-PUBLIC-KEY-HERE&sid=REPLACE-SHORT-ID-HERE&fp=chrome&type=tcp#BBTB%20Test
```
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Config/Common.xcconfig` → success
    - `grep -q "DEVELOPMENT_TEAM = UAN8W9Q82U" BBTB/Config/Common.xcconfig` → success
    - `grep -q "SWIFT_VERSION = 6.0" BBTB/Config/Common.xcconfig` → success
    - `grep -q "IPHONEOS_DEPLOYMENT_TARGET = 18.0" BBTB/Config/Common.xcconfig` → success
    - `grep -q "MACOSX_DEPLOYMENT_TARGET = 15.0" BBTB/Config/Common.xcconfig` → success
    - `grep -q "^#include \"Common.xcconfig\"" BBTB/Config/Debug.xcconfig` → success
    - `grep -q "DEBUG BBTB_DEBUG" BBTB/Config/Debug.xcconfig` → success
    - `grep -q "<string>UAN8W9Q82U</string>" BBTB/Config/ExportOptions-iOS.plist` → success
    - `test -f BBTB/Vendored/README.md && grep -q "libbox.xcframework" BBTB/Vendored/README.md` → success
    - `test -f BBTB/Tests/Fixtures/test-config.vless.local.txt.template`
    - `grep -q "test-config.vless.local.txt$" BBTB/.gitignore`
  </acceptance_criteria>
</task>

<task id="W0-T3" type="auto" autonomous="true">
  <name>Task W0-T3: Создать 12 SwiftPM-пакетов с минимальными исходниками для компиляции</name>
  <files>
    BBTB/Packages/VPNCore/Package.swift,
    BBTB/Packages/VPNCore/Sources/VPNCore/VPNCore.swift,
    BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift,
    BBTB/Packages/VPNCore/Tests/VPNCoreTests/VPNCoreTests.swift,
    BBTB/Packages/ProtocolRegistry/Package.swift,
    BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift,
    BBTB/Packages/ProtocolEngine/Package.swift,
    BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift,
    BBTB/Packages/ProtocolEngine/Sources/XrayFallback/XrayFallback.swift,
    BBTB/Packages/ProtocolEngine/Frameworks/.gitkeep,
    BBTB/Packages/Protocols/VLESSReality/Package.swift,
    BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSReality.swift,
    BBTB/Packages/ConfigParser/Package.swift,
    BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigParser.swift,
    BBTB/Packages/KillSwitch/Package.swift,
    BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift,
    BBTB/Packages/PacketTunnelKit/Package.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PacketTunnelKit.swift,
    BBTB/Packages/DesignSystem/Package.swift,
    BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift,
    BBTB/Packages/Localization/Package.swift,
    BBTB/Packages/Localization/Sources/Localization/L10n.swift,
    BBTB/Packages/AppFeatures/Package.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenFeature.swift,
    BBTB/Packages/CrashReporter/Package.swift,
    BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift
  </files>
  <read_first>
    - prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md `<swift_package_layout>` (строки 74-142) — каноничный layout
    - .planning/phases/01-foundation/01-CONTEXT.md §3 (PacketTunnelKit структура)
    - .planning/phases/01-foundation/01-RESEARCH.md §5 «Package.swift — пример для PacketTunnelKit», §5 «Package.swift — пример для ProtocolEngine»
    - Wiki/architecture.md «Plugin-pattern для протоколов» — сигнатура VPNProtocolHandler
  </read_first>
  <action>
Создать 12 SwiftPM пакетов. **Все** Package.swift начинаются с `// swift-tools-version: 6.0` и платформы `[.iOS(.v18), .macOS(.v15)]`. Содержимое каждого Sources/ файла — placeholder с одним `public struct <Name> { public init() {} }`, ЗА ИСКЛЮЧЕНИЕМ нескольких типов:

**VPNCore** — Sources/VPNCore/VPNProtocolHandler.swift (CORE-02 контракт):
```swift
import Foundation

/// Plugin contract for VPN protocols (CORE-02 per D-02 in CONTEXT.md).
/// Implemented in Phase 1 only by VLESSReality. Future phases add Trojan, WireGuard, etc.
public protocol VPNProtocolHandler: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    var isAvailable: Bool { get }

    func validate(config: ProtocolConfig) throws
    func connect(config: ProtocolConfig) async throws -> TunnelHandle
    func disconnect(handle: TunnelHandle) async throws
    func diagnostics() async -> ProtocolDiagnostics
}

/// Opaque config (concrete types per-protocol; Phase 1 = VLESSReality only).
public struct ProtocolConfig: Sendable {
    public let identifier: String
    public let json: String  // sing-box subset for this protocol
    public init(identifier: String, json: String) {
        self.identifier = identifier
        self.json = json
    }
}

public struct TunnelHandle: Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

public struct ProtocolDiagnostics: Sendable {
    public let latencyMs: Int?
    public let lastError: String?
    public init(latencyMs: Int? = nil, lastError: String? = nil) {
        self.latencyMs = latencyMs
        self.lastError = lastError
    }
}
```

Sources/VPNCore/VPNCore.swift — entry-point типы:
```swift
public enum VPNCore {
    public static let version = "0.1.0"
}
```

Tests/VPNCoreTests/VPNCoreTests.swift:
```swift
import XCTest
@testable import VPNCore

final class VPNCoreTests: XCTestCase {
    func test_versionMatches() {
        XCTAssertEqual(VPNCore.version, "0.1.0")
    }
}
```

Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VPNCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VPNCore", targets: ["VPNCore"])],
    targets: [
        .target(name: "VPNCore"),
        .testTarget(name: "VPNCoreTests", dependencies: ["VPNCore"]),
    ]
)
```

**ProtocolRegistry** — Sources/ProtocolRegistry/ProtocolRegistry.swift:
```swift
import Foundation
import VPNCore

/// CORE-02: реестр зарегистрированных VPNProtocolHandler-типов.
/// В Phase 1 регистрируется только VLESSReality (см. 01-W3-base-tunnel-PLAN.md).
public final class ProtocolRegistry: @unchecked Sendable {
    public static let shared = ProtocolRegistry()

    private let lock = NSLock()
    private var handlers: [String: any VPNProtocolHandler.Type] = [:]

    public func register<H: VPNProtocolHandler>(_ handlerType: H.Type) {
        lock.lock(); defer { lock.unlock() }
        handlers[H.identifier] = handlerType
    }

    public func handler(for identifier: String) -> (any VPNProtocolHandler.Type)? {
        lock.lock(); defer { lock.unlock() }
        return handlers[identifier]
    }

    public var registeredIdentifiers: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(handlers.keys).sorted()
    }
}
```

Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ProtocolRegistry",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ProtocolRegistry", targets: ["ProtocolRegistry"])],
    dependencies: [.package(path: "../VPNCore")],
    targets: [
        .target(name: "ProtocolRegistry", dependencies: ["VPNCore"]),
    ]
)
```

**ProtocolEngine** — Package.swift (vendored libbox.xcframework положится в Wave 3):
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ProtocolEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SingBoxBridge", targets: ["SingBoxBridge"]),
        .library(name: "XrayFallback", targets: ["XrayFallback"]),
    ],
    targets: [
        // Placeholder без binaryTarget — vendored libbox добавится в Wave 3 после `BBTB/Vendored/libbox.xcframework` будет положен на диск.
        .target(name: "SingBoxBridge"),
        .target(name: "XrayFallback"),
    ]
)
```

Sources/SingBoxBridge/SingBoxBridge.swift:
```swift
// Wave 3 наполнит SingBoxConfigLoader, ExtensionPlatformInterface, libbox lifecycle.
// В Wave 0 — placeholder для компиляции.
public enum SingBoxBridge {
    public static let placeholder = true
}
```

Sources/XrayFallback/XrayFallback.swift:
```swift
// CORE-09 (xray-core fallback) — Phase 4+. Phase 1 — placeholder.
public enum XrayFallback {
    public static let placeholder = true
}
```

**Protocols/VLESSReality** — placeholder, наполнится в Wave 3/W4 (зарегистрирует handler):
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VLESSReality",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VLESSReality", targets: ["VLESSReality"])],
    dependencies: [.package(path: "../../VPNCore")],
    targets: [.target(name: "VLESSReality", dependencies: ["VPNCore"], path: "Sources/VLESSReality")]
)
```
Sources/VLESSReality/VLESSReality.swift:
```swift
public enum VLESSReality { public static let placeholder = true }
```

**ConfigParser** — Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ConfigParser",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ConfigParser", targets: ["ConfigParser"])],
    dependencies: [.package(path: "../VPNCore")],
    targets: [
        .target(name: "ConfigParser", dependencies: ["VPNCore"]),
        .testTarget(name: "ConfigParserTests", dependencies: ["ConfigParser"]),
    ]
)
```
Sources/ConfigParser/ConfigParser.swift:
```swift
public enum ConfigParser { public static let placeholder = true }
```

**KillSwitch** — Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "KillSwitch",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "KillSwitch", targets: ["KillSwitch"])],
    targets: [
        .target(name: "KillSwitch"),
        .testTarget(name: "KillSwitchTests", dependencies: ["KillSwitch"]),
    ]
)
```
Sources/KillSwitch/KillSwitch.swift:
```swift
public enum KillSwitch { public static let placeholder = true }
```

**PacketTunnelKit** — Package.swift (см. RESEARCH §5):
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PacketTunnelKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "PacketTunnelKit", targets: ["PacketTunnelKit"])],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../ProtocolEngine"),
    ],
    targets: [
        .target(
            name: "PacketTunnelKit",
            dependencies: [
                "VPNCore",
                .product(name: "SingBoxBridge", package: "ProtocolEngine"),
            ]
        ),
        .testTarget(name: "PacketTunnelKitTests", dependencies: ["PacketTunnelKit"]),
    ]
)
```
Sources/PacketTunnelKit/PacketTunnelKit.swift:
```swift
// Wave 1 добавит SingBoxConfigLoader.swift; Wave 2 — TunnelSettings.swift;
// Wave 3 — BaseSingBoxTunnel.swift и ExtensionPlatformInterface.swift.
// Wave 0 — placeholder для компиляции.
public enum PacketTunnelKit { public static let version = "0.1.0" }
```

**DesignSystem** — Sources/DesignSystem/DesignSystem.swift:
```swift
import SwiftUI

/// CONTEXT.md §5 default: системные SF Symbols + system colors, заготовка под Figma в v0.11.
public enum DS {
    public static let accent: Color = .accentColor
    public static let titleFont: Font = .system(.title, design: .rounded)
}
```

Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
    targets: [.target(name: "DesignSystem")]
)
```

**Localization** — Package.swift (xcstrings resource добавится в Wave 4):
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Localization",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Localization", targets: ["Localization"])],
    targets: [.target(name: "Localization")]
)
```
Sources/Localization/L10n.swift:
```swift
// Wave 4 наполнит Resources/Localizable.xcstrings + L10n keys.
public enum L10n { public static let placeholder = "BBTB" }
```

**AppFeatures** — Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AppFeatures",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "MainScreenFeature", targets: ["MainScreenFeature"])],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Localization"),
    ],
    targets: [
        .target(
            name: "MainScreenFeature",
            dependencies: ["VPNCore", "DesignSystem", "Localization"]
        )
    ]
)
```
Sources/MainScreenFeature/MainScreenFeature.swift:
```swift
// Wave 4 наполнит MainScreenView, MainScreenViewModel, ConnectionButton, ConnectionTimer.
public enum MainScreenFeature { public static let placeholder = true }
```

**CrashReporter** — Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CrashReporter",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "CrashReporter", targets: ["CrashReporter"])],
    targets: [.target(name: "CrashReporter")]
)
```
Sources/CrashReporter/CrashReporter.swift:
```swift
// Wave 5 наполнит MXMetricManagerSubscriber.
public enum CrashReporter { public static let placeholder = true }
```

`BBTB/Packages/ProtocolEngine/Frameworks/.gitkeep` — пустой файл (директория для libbox.xcframework, заполнится в Wave 3).
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Packages/VPNCore/Package.swift && grep -q '"VPNCore"' BBTB/Packages/VPNCore/Package.swift`
    - `grep -q "swift-tools-version: 6.0" BBTB/Packages/VPNCore/Package.swift`
    - `grep -q "public protocol VPNProtocolHandler" BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift`
    - `grep -q "public final class ProtocolRegistry" BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift`
    - `test -f BBTB/Packages/PacketTunnelKit/Package.swift && grep -q "PacketTunnelKit" BBTB/Packages/PacketTunnelKit/Package.swift`
    - `grep -q '.product(name: "SingBoxBridge"' BBTB/Packages/PacketTunnelKit/Package.swift`
    - `test -f BBTB/Packages/ProtocolEngine/Frameworks/.gitkeep`
    - 12 директорий пакетов существуют: `ls -d BBTB/Packages/{VPNCore,ProtocolRegistry,ProtocolEngine,Protocols/VLESSReality,ConfigParser,KillSwitch,PacketTunnelKit,DesignSystem,Localization,AppFeatures,CrashReporter}` — все exist
    - В каждом пакете кроме placeholder'ов команда `swift package describe --type json` (из директории пакета) парсится без ошибок. (Реальная компиляция через Xcode проверится в W0-T5.)
    - `find BBTB/Packages -name "Package.swift" | xargs grep -l "platforms: \[.iOS(.v18), .macOS(.v15)\]" | wc -l` ≥ 10 (большинство пакетов имеют правильные платформы; AppFeatures и DesignSystem тоже их декларируют)
  </acceptance_criteria>
</task>

<task id="W0-T4" type="auto" autonomous="true">
  <name>Task W0-T4: Создать app/extension target скелеты — Swift-исходники, Info.plist, entitlements</name>
  <files>
    BBTB/App/iOSApp/BBTB_iOSApp.swift,
    BBTB/App/iOSApp/Info.plist,
    BBTB/App/iOSApp/BBTB-iOS.entitlements,
    BBTB/App/iOSApp/Assets.xcassets/Contents.json,
    BBTB/App/iOSApp/Assets.xcassets/AppIcon.appiconset/Contents.json,
    BBTB/App/iOSApp/Assets.xcassets/AccentColor.colorset/Contents.json,
    BBTB/App/macOSApp/BBTB_macOSApp.swift,
    BBTB/App/macOSApp/Info.plist,
    BBTB/App/macOSApp/BBTB-macOS.entitlements,
    BBTB/App/macOSApp/Assets.xcassets/Contents.json,
    BBTB/App/macOSApp/Assets.xcassets/AppIcon.appiconset/Contents.json,
    BBTB/App/macOSApp/Assets.xcassets/AccentColor.colorset/Contents.json,
    BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift,
    BBTB/App/PacketTunnelExtension-iOS/Info.plist,
    BBTB/App/PacketTunnelExtension-iOS/PacketTunnelExtension-iOS.entitlements,
    BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift,
    BBTB/App/PacketTunnelExtension-macOS/Info.plist,
    BBTB/App/PacketTunnelExtension-macOS/PacketTunnelExtension-macOS.entitlements,
    BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift,
    BBTB/App/AppProxyExtension-macOS/Info.plist,
    BBTB/App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-CONTEXT.md §1 «Идентификаторы и брендинг» (точные Bundle IDs)
    - .planning/phases/01-foundation/01-RESEARCH.md §5 «Entitlements», §5 «NSExtension Info.plist»
    - prompts/v2 строки 144-154 (network_extension_targets entitlements)
  </read_first>
  <action>
1. **`BBTB/App/iOSApp/BBTB_iOSApp.swift`** — `@main App` struct с placeholder root view (полноценный UI — Wave 4):
```swift
import SwiftUI

@main
struct BBTB_iOSApp: App {
    var body: some Scene {
        WindowGroup {
            // Wave 4 заменит на MainScreenView из MainScreenFeature
            VStack {
                Text("BBTB")
                    .font(.system(.title, design: .rounded).bold())
                Text("Phase 1 bootstrap — Wave 0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
```

2. **`BBTB/App/iOSApp/Info.plist`** — минимальный iOS Info.plist:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>BBTB</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>UILaunchScreen</key>
  <dict/>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
  </dict>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
  </array>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>NSAppTransportSecurity</key>
  <dict>
    <!-- Phase 1 — нет HTTP fetch вне TLS. Дефолтные ATS-настройки нас устраивают. -->
  </dict>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ru</string>
  </array>
</dict>
</plist>
```

3. **`BBTB/App/iOSApp/BBTB-iOS.entitlements`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.networking.networkextension</key>
  <array>
    <string>packet-tunnel-provider</string>
  </array>
  <key>com.apple.developer.networking.vpn.api</key>
  <array>
    <string>allow-vpn</string>
  </array>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.app.bbtb.shared</string>
  </array>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)app.bbtb.shared</string>
  </array>
</dict>
</plist>
```

4. **`BBTB/App/iOSApp/Assets.xcassets/Contents.json`:**
```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

5. **`BBTB/App/iOSApp/Assets.xcassets/AppIcon.appiconset/Contents.json`** — пустой iOS app icon set:
```json
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

6. **`BBTB/App/iOSApp/Assets.xcassets/AccentColor.colorset/Contents.json`:**
```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "0.478", "red" : "0.000" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

7. **`BBTB/App/macOSApp/BBTB_macOSApp.swift`:**
```swift
import SwiftUI

@main
struct BBTB_macOSApp: App {
    var body: some Scene {
        Window("BBTB", id: "main") {
            VStack {
                Text("BBTB")
                    .font(.system(.title, design: .rounded).bold())
                Text("Phase 1 bootstrap — Wave 0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 380, minHeight: 520)
            .padding()
        }
        .windowResizability(.contentSize)
        // Wave 4 добавит MenuBarExtra Scene для UX-07.
    }
}
```

8. **`BBTB/App/macOSApp/Info.plist`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>BBTB</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ru</string>
  </array>
</dict>
</plist>
```

9. **`BBTB/App/macOSApp/BBTB-macOS.entitlements`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.networking.networkextension</key>
  <array>
    <string>packet-tunnel-provider</string>
    <string>app-proxy-provider</string>
  </array>
  <key>com.apple.developer.networking.vpn.api</key>
  <array>
    <string>allow-vpn</string>
  </array>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.app.bbtb.shared</string>
  </array>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.network.server</key>
  <true/>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)app.bbtb.shared</string>
  </array>
</dict>
</plist>
```

10. **`BBTB/App/macOSApp/Assets.xcassets/Contents.json`, AppIcon.appiconset/Contents.json, AccentColor.colorset/Contents.json`** — те же по сути что iOS (idiom universal/mac).

11. **`BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`** (Wave 3 наполнит):
```swift
import NetworkExtension

/// Wave 3 заменит на: class PacketTunnelProvider: BaseSingBoxTunnel
/// Wave 0 — placeholder, чтобы NSExtension target собрался.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String : NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        // TODO Wave 3: SingBoxConfigLoader.validate + libbox lifecycle
        completionHandler(NSError(domain: "BBTB.PlaceholderTunnel",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Not implemented in Wave 0"]))
    }
    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
```

12. **`BBTB/App/PacketTunnelExtension-iOS/Info.plist`** (см. RESEARCH §5):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>BBTB Tunnel</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.networkextension.packet-tunnel</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
  </dict>
</dict>
</plist>
```

13. **`BBTB/App/PacketTunnelExtension-iOS/PacketTunnelExtension-iOS.entitlements`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.networking.networkextension</key>
  <array>
    <string>packet-tunnel-provider</string>
  </array>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.app.bbtb.shared</string>
  </array>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)app.bbtb.shared</string>
  </array>
</dict>
</plist>
```

14. **`BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`** — идентично iOS (общая логика — в `PacketTunnelKit`, Wave 3 заменит).
15. **`BBTB/App/PacketTunnelExtension-macOS/Info.plist`** — идентично iOS (NSExtensionPointIdentifier тот же).
16. **`BBTB/App/PacketTunnelExtension-macOS/PacketTunnelExtension-macOS.entitlements`** — то же что iOS-tunnel entitlements + добавить `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.network.server`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.networking.networkextension</key>
  <array>
    <string>packet-tunnel-provider</string>
  </array>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.app.bbtb.shared</string>
  </array>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.network.server</key>
  <true/>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)app.bbtb.shared</string>
  </array>
</dict>
</plist>
```

17. **`BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift`** — placeholder для Phase 8:
```swift
import NetworkExtension

/// CORE-05 — реализация в Phase 8. Phase 1 — пустая заготовка чтобы target собирался.
final class AppProxyProvider: NEAppProxyProvider {
    override func startProxy(options: [String : Any]? = nil,
                             completionHandler: @escaping (Error?) -> Void) {
        completionHandler(NSError(domain: "BBTB.AppProxy",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Phase 8"]))
    }
    override func stopProxy(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
```

18. **`BBTB/App/AppProxyExtension-macOS/Info.plist`** — NSExtensionPointIdentifier = `com.apple.networkextension.app-proxy`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.networkextension.app-proxy</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).AppProxyProvider</string>
  </dict>
</dict>
</plist>
```

19. **`BBTB/App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.networking.networkextension</key>
  <array>
    <string>app-proxy-provider</string>
  </array>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.app.bbtb.shared</string>
  </array>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
</plist>
```
  </action>
  <acceptance_criteria>
    - `test -f BBTB/App/iOSApp/BBTB_iOSApp.swift && grep -q "@main" BBTB/App/iOSApp/BBTB_iOSApp.swift`
    - `grep -q "com.apple.developer.networking.networkextension" BBTB/App/iOSApp/BBTB-iOS.entitlements`
    - `grep -q "<string>packet-tunnel-provider</string>" BBTB/App/iOSApp/BBTB-iOS.entitlements`
    - `grep -q "group.app.bbtb.shared" BBTB/App/iOSApp/BBTB-iOS.entitlements`
    - `grep -q "\$(AppIdentifierPrefix)app.bbtb.shared" BBTB/App/iOSApp/BBTB-iOS.entitlements`
    - `grep -q "com.apple.security.app-sandbox" BBTB/App/macOSApp/BBTB-macOS.entitlements`
    - `grep -q "<string>app-proxy-provider</string>" BBTB/App/macOSApp/BBTB-macOS.entitlements`
    - `grep -q "com.apple.networkextension.packet-tunnel" BBTB/App/PacketTunnelExtension-iOS/Info.plist`
    - `grep -q "com.apple.networkextension.packet-tunnel" BBTB/App/PacketTunnelExtension-macOS/Info.plist`
    - `grep -q "com.apple.networkextension.app-proxy" BBTB/App/AppProxyExtension-macOS/Info.plist`
    - `grep -q "NEPacketTunnelProvider" BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`
    - `grep -q "NEAppProxyProvider" BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift`
  </acceptance_criteria>
</task>

<task id="W0-T5" type="checkpoint:human-action" gate="blocking" autonomous="false">
  <name>Task W0-T5: Создать Xcode project + workspace в Xcode UI + первая сборка</name>
  <what-built>Xcode `.xcodeproj` и `.xcworkspace` создаются ВРУЧНУЮ в Xcode UI (нет надёжного способа сгенерировать корректный pbxproj программно для multi-target проекта с extension'ами в Phase 1 — XcodeGen или Tuist не используем чтобы не вводить ещё один tool в Phase 1, см. CONTEXT.md §5 «системные ресурсы»).</what-built>
  <read_first>
    - .planning/phases/01-foundation/01-CONTEXT.md §1, §3 (точные Bundle IDs + структура target'ов)
    - .planning/phases/01-foundation/01-RESEARCH.md §5 (полный layout)
  </read_first>
  <how-to-verify>
    Пользователь в Xcode 16+:

    1. **Создать workspace:** File → New → Workspace → имя `BBTB`, расположение — `BBTB/` корень репозитория (получится `BBTB/BBTB.xcworkspace`).

    2. **Создать Xcode project:** File → New → Project → iOS → App → "Multiplatform" не выбираем (нужны отдельные iOS+macOS target'ы) → выбираем iOS App template → Product Name `BBTB`, Team `UAN8W9Q82U`, Bundle ID `app.bbtb.client.ios`, Interface SwiftUI, Language Swift, Storage SwiftData → создать в `BBTB/`.

    3. **Удалить сгенерированный шаблонный код Xcode** — оставить только структуру targets/build settings. Заменить `ContentView.swift`/`BBTBApp.swift` ссылкой на уже созданные в W0-T4 файлы:
       - В навигаторе удалить сгенерированный `BBTB/BBTBApp.swift` (с пометкой «Remove References», файлы W0-T4 уже лежат на диске)
       - Add Files → выбрать `BBTB/App/iOSApp/` директорию полностью → File → Add Folder Reference

    4. **Добавить macOS app target:** File → New → Target → macOS → App → Product Name `BBTB-macOS`, Bundle ID `app.bbtb.client.macos`. Аналогично — заменить generated файлы ссылками на `BBTB/App/macOSApp/`.

    5. **Добавить 3 extension target'а:**
       - File → New → Target → iOS → Network Extension → Packet Tunnel Provider → Product Name `BBTB-Tunnel-iOS`, Bundle ID `app.bbtb.client.ios.tunnel` → подключить к BBTB-iOS app target.
       - To же для macOS: target `BBTB-Tunnel-macOS`, Bundle ID `app.bbtb.client.macos.tunnel`, подключить к BBTB-macOS.
       - To же для AppProxy: target `BBTB-AppProxy-macOS`, Bundle ID `app.bbtb.client.macos.appproxy`, podключить к BBTB-macOS.
       - В каждом случае — заменить generated файлы ссылками на `BBTB/App/PacketTunnelExtension-iOS/`, ...

    6. **Привязать xcconfig'и:**
       - Project navigator → BBTB project → Info → Configurations → Debug = `Config/Debug.xcconfig`, Release = `Config/Release.xcconfig` (для project base configuration).

    7. **Привязать entitlements в Build Settings** каждого target'а:
       - BBTB-iOS: CODE_SIGN_ENTITLEMENTS = `App/iOSApp/BBTB-iOS.entitlements`
       - BBTB-macOS: `App/macOSApp/BBTB-macOS.entitlements`
       - BBTB-Tunnel-iOS: `App/PacketTunnelExtension-iOS/PacketTunnelExtension-iOS.entitlements`
       - BBTB-Tunnel-macOS: `App/PacketTunnelExtension-macOS/PacketTunnelExtension-macOS.entitlements`
       - BBTB-AppProxy-macOS: `App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements`

    8. **Добавить SwiftPM пакеты через Xcode UI:** Project → Package Dependencies → "+" → Add Local → выбрать каждый из 12 пакетов в `BBTB/Packages/*`. Затем в каждом app target → General → Frameworks, Libraries, and Embedded Content — добавить нужные products:
       - BBTB-iOS / BBTB-macOS: VPNCore, ProtocolRegistry, VLESSReality (Phase 1 single protocol), ConfigParser, KillSwitch, DesignSystem, Localization, MainScreenFeature, CrashReporter (НЕ PacketTunnelKit — это extension-only)
       - BBTB-Tunnel-iOS / BBTB-Tunnel-macOS: PacketTunnelKit, VPNCore, SingBoxBridge

    9. **Создать workspace ссылку на project:** File → Add Files to "BBTB"... → выбрать `BBTB.xcodeproj`.

    10. **Создать aggregate scheme BBTB-AllTests** (для CI и для последующих волн):
        Product → Scheme → Edit Scheme → или Manage Schemes → "+" → Aggregate target — добавить BBTB-iOS, BBTB-macOS, и unit-test target'ы пакетов (VPNCoreTests, ConfigParserTests, KillSwitchTests, PacketTunnelKitTests). Sharing — checked.

    11. **Первая сборка для верификации:**
        ```bash
        cd /Users/vergevsky/ClaudeProjects/VPN
        xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-iOS -destination 'generic/platform=iOS Simulator' -quiet
        echo "iOS BUILD EXIT: $?"
        xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination 'generic/platform=macOS' -quiet
        echo "macOS BUILD EXIT: $?"
        ```

    Ожидаемый exit code = 0 для обоих. Если ≠ 0 — diagnose и поправить (типовые проблемы: Bundle ID не совпадает с зарегистрированным в Apple Developer Portal — вернуться к W0-T1).

    После успешной сборки — ответить «build green» или прикрепить вывод последней строки `BUILD SUCCEEDED`.
  </how-to-verify>
  <resume-signal>Type "build green" + сообщить какие именно target'ы / scheme'ы создаются успешно. При ошибках — приложить вывод xcodebuild для триажа.</resume-signal>
  <done>BBTB.xcworkspace открывается без ошибок; обе сборки BBTB-iOS и BBTB-macOS заканчиваются BUILD SUCCEEDED; aggregate scheme BBTB-AllTests существует.</done>
</task>

<task id="W0-T6" type="auto" autonomous="true">
  <name>Task W0-T6: Финальная верификация скелета — build smoke-test + project structure invariants</name>
  <files>
    BBTB/.gsd/wave0-verification.log
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md «Validation Architecture» (test framework, sampling rate)
  </read_first>
  <action>
Создать `BBTB/.gsd/wave0-verification.log` с результатами smoke-build тестов. Запустить следующие команды (с абсолютными путями) и записать вывод в лог-файл:

```bash
mkdir -p /Users/vergevsky/ClaudeProjects/VPN/BBTB/.gsd

cd /Users/vergevsky/ClaudeProjects/VPN

{
  echo "=== Wave 0 Verification Log ==="
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "--- Bundle IDs ---"
  grep -r "PRODUCT_BUNDLE_IDENTIFIER" BBTB/BBTB.xcodeproj/project.pbxproj | sort -u | head -20
  echo ""
  echo "--- Entitlements files ---"
  find BBTB/App -name "*.entitlements" -exec echo "{}" \; -exec grep -E "networking|app-sandbox|application-groups|keychain-access" {} \;
  echo ""
  echo "--- xcconfig files ---"
  cat BBTB/Config/Common.xcconfig
  echo ""
  echo "--- Swift packages ---"
  find BBTB/Packages -name "Package.swift" -maxdepth 3
  echo ""
  echo "--- iOS Build ---"
  xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-iOS \
    -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -10
  IOS_EXIT=$?
  echo "iOS build exit code: $IOS_EXIT"
  echo ""
  echo "--- macOS Build ---"
  xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-macOS \
    -destination 'generic/platform=macOS' -quiet 2>&1 | tail -10
  MAC_EXIT=$?
  echo "macOS build exit code: $MAC_EXIT"
  echo ""
  echo "=== Result ==="
  if [ "$IOS_EXIT" = "0" ] && [ "$MAC_EXIT" = "0" ]; then
    echo "PASS: Wave 0 bootstrap complete, both platforms build green."
  else
    echo "FAIL: at least one platform did not build."
  fi
} > BBTB/.gsd/wave0-verification.log 2>&1

cat BBTB/.gsd/wave0-verification.log
```

Если log file заканчивается «PASS» — Wave 0 завершён. Если «FAIL» — debug и не возвращаться к Wave 1 до зелёной сборки.
  </action>
  <acceptance_criteria>
    - `test -f BBTB/.gsd/wave0-verification.log` → success
    - `grep -q "PASS: Wave 0 bootstrap complete" BBTB/.gsd/wave0-verification.log` → success
    - `grep -q "iOS build exit code: 0" BBTB/.gsd/wave0-verification.log` → success
    - `grep -q "macOS build exit code: 0" BBTB/.gsd/wave0-verification.log` → success
    - `grep -q "DEVELOPMENT_TEAM = UAN8W9Q82U" BBTB/.gsd/wave0-verification.log` → success
    - В логе видны все 5 product bundle identifiers: `app.bbtb.client.ios`, `app.bbtb.client.macos`, `app.bbtb.client.ios.tunnel`, `app.bbtb.client.macos.tunnel`, `app.bbtb.client.macos.appproxy` (последний — placeholder)
    - В логе видны все 12 Package.swift путей
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && grep -q "PASS: Wave 0 bootstrap complete" BBTB/.gsd/wave0-verification.log && grep -q "iOS build exit code: 0" BBTB/.gsd/wave0-verification.log && grep -q "macOS build exit code: 0" BBTB/.gsd/wave0-verification.log</automated>
  </verify>
  <done>Wave 0 verification log зафиксирован, оба platform build'а зелёные, все Bundle IDs соответствуют CONTEXT.md §1.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Apple Developer Portal → repo | Registered identifiers и provisioning profiles импортируются в Xcode; tampering портала → mis-signed builds (но user-validated через W0-T1 checkpoint) |
| Filesystem → git commit | xcconfig'и попадают в git (без секретов); test-config.vless.local.txt НЕ попадает (содержит секреты, в .gitignore) |
| Future libbox.xcframework → Wave 3 | Vendored binary — supply-chain attack surface; в Wave 0 только директория с README. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-W0-01 | Tampering | xcconfig DEVELOPMENT_TEAM | mitigate | xcconfig — read-only в git history; PR review для изменений; Wave 5 cross-check в exportarchive logs |
| T-01-W0-02 | Information Disclosure | test-config.vless.local.txt в git | mitigate | `.gitignore` исключает `*.local.txt` (acceptance grep'нет это); только `.template` коммитим |
| T-01-W0-03 | Tampering | Apple Developer Portal Bundle IDs не совпадают с проектом | accept | W0-T1 checkpoint валидирует, W0-T5 build падает если mismatch |
| T-01-W0-04 | Information Disclosure | entitlements экспонируют capabilities за пределы скоупа Phase 1 | mitigate | Каждый entitlements файл содержит ТОЛЬКО нужное; `app-proxy-provider` на macOS — зарезервирован, но не активирован в коде (AppProxyProvider.swift падает с -1) |
| T-01-W0-05 | Denial of Service | sub-package dependency cycle | mitigate | Все Package.swift зависят только «вниз» (VPNCore — без dependencies; ProtocolEngine — без dependencies; PacketTunnelKit → ProtocolEngine + VPNCore); cycle detection — xcodebuild fail в W0-T5 |
</threat_model>

<verification>
**Phase-level checks для Wave 0:**

1. **Build smoke-test:** обе сборки (BBTB-iOS + BBTB-macOS) проходят BUILD SUCCEEDED — лог в `BBTB/.gsd/wave0-verification.log`.
2. **Bundle ID integrity:** все 5 PRODUCT_BUNDLE_IDENTIFIER в `BBTB.xcodeproj/project.pbxproj` точно соответствуют таблице CONTEXT.md §1.
3. **Entitlements correctness:** iOS app entitlements содержат `packet-tunnel-provider` + `allow-vpn` + `group.app.bbtb.shared`; macOS app — ещё `app-sandbox` + `app-proxy-provider` (зарезервирован).
4. **Team ID single source:** `grep -r "UAN8W9Q82U" BBTB/` → только в `BBTB/Config/*.xcconfig` и `BBTB/Config/ExportOptions-*.plist`. В исходниках Swift НЕТ литерала Team ID.
5. **No secrets in git:** `git status` показывает что `Tests/Fixtures/test-config.vless.local.txt` НЕ tracked (если разработчик уже его создал). `.template` версия — tracked.
6. **SwiftPM structure:** все 12 Package.swift существуют, каждый декларирует platforms `iOS(.v18), .macOS(.v15)` и swift-tools-version 6.0.

**Что НЕ верифицируется в Wave 0** (отложено на следующие волны):
- R1 (SOCKS5/gRPC) — Wave 1 + Wave 5 valid
- R6 (P2P=false) — Wave 2 + Wave 5 valid
- KILL-01/02 (включение kill switch) — Wave 2
- Реальное подключение туннеля — Wave 3
- UI / Import flow — Wave 4
- Crash reporter + TestFlight archive — Wave 5
</verification>

<success_criteria>
Wave 0 завершён когда:

- [ ] **Apple Developer Portal** содержит все 5 App IDs с правильными capabilities и App Group (W0-T1).
- [ ] **Файловая структура** под `BBTB/` соответствует canonical layout из CONTEXT.md §3 + RESEARCH §5 (W0-T2, W0-T3, W0-T4).
- [ ] **`BBTB.xcworkspace`** открывается в Xcode 16 без ошибок parsing (W0-T5).
- [ ] **Bundle IDs** во всех 5 target'ах ровно совпадают с CONTEXT.md §1.
- [ ] **Entitlements** разнесены по target'ам строго по таблице CONTEXT.md §1 (iOS-tunnel ≠ iOS-app по составу).
- [ ] **12 SwiftPM пакетов** компилируются (placeholder'ами) под Swift 6 / iOS 18 / macOS 15.
- [ ] **`xcodebuild build`** обоих platform schemes завершается с exit code 0; результат зафиксирован в `BBTB/.gsd/wave0-verification.log` (W0-T6).
- [ ] **Aggregate scheme** `BBTB-AllTests` существует и shared (для последующих волн).
- [ ] **`VPNProtocolHandler` protocol** (CORE-02) объявлен в `Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift`.
- [ ] **`ProtocolRegistry`** (CORE-02) объявлен с публичным API `register`/`handler(for:)` в `Packages/ProtocolRegistry/`.
- [ ] **App Group** `group.app.bbtb.shared` (CORE-07) объявлен в entitlements всех 5 target'ов.
- [ ] **xcconfig DEVELOPMENT_TEAM** = `UAN8W9Q82U` единственный источник Team ID (CORE-06).
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-W0-bootstrap-SUMMARY.md` с:
- Список созданных файлов (укажи фактический pbxproj path)
- Snapshot вывода `xcodebuild build` для обеих платформ (первые/последние 5 строк)
- Решения принятые в ходе bootstrap (например, какой template Xcode'а использован для PacketTunnel target, как именно подключены SwiftPM пакеты — Local или path)
- Note для Wave 1 — `Packages/ProtocolEngine/Frameworks/.gitkeep` существует; в Wave 3 туда положится libbox.xcframework
- Любые отклонения от плана и почему
</output>
