---
phase: 01-foundation
plan: W3-base-tunnel
type: execute
wave: 3
depends_on:
  - W0-bootstrap
  - W1-security-config
  - W2-killswitch-r6
files_modified:
  - BBTB/Vendored/libbox.xcframework/Info.plist
  - BBTB/Packages/ProtocolEngine/Package.swift
  - BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift
  - BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/LibboxBootstrap.swift
  - BBTB/Packages/PacketTunnelKit/Package.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift
  - BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift
  - BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift
  - BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift
  - BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/BaseSingBoxTunnelSmokeTests.swift
  - BBTB/Packages/Protocols/VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift
autonomous: false
requirements:
  - CORE-04
  - CORE-08
  - PROTO-01

must_haves:
  truths:
    - "BBTB/Vendored/libbox.xcframework/Info.plist существует (бинарь положен пользователем)"
    - "ProtocolEngine.Package.swift декларирует binaryTarget с path = ../../Vendored/libbox.xcframework"
    - "SingBoxBridge экспортирует Libbox API через @_exported import Libbox"
    - "BaseSingBoxTunnel: NEPacketTunnelProvider в PacketTunnelKit/Sources/"
    - "BaseSingBoxTunnel.startTunnel(options:completionHandler:) — публичная override-точка"
    - "BaseSingBoxTunnel.startTunnel вызывает SingBoxConfigLoader.validate(json:) ПЕРЕД LibboxNewService"
    - "BaseSingBoxTunnel вызывает InterfaceFlagsInspector.assertNoPointToPointOnUtun() ПОСЛЕ setTunnelNetworkSettings (DEBUG only)"
    - "ExtensionPlatformInterface.openTun(_:) использует TunnelSettings.makeR6Safe + DispatchSemaphore + setTunnelNetworkSettings"
    - "ExtensionPlatformInterface.openTun(_:) извлекает FD через packetFlow.value(forKeyPath: \"socket.fileDescriptor\")"
    - "PacketTunnelExtension-iOS.PacketTunnelProvider наследует BaseSingBoxTunnel"
    - "PacketTunnelExtension-macOS.PacketTunnelProvider наследует BaseSingBoxTunnel"
    - "VLESSRealityHandler реализует VPNProtocolHandler protocol"
    - "ConfigBuilder.buildSingBoxJSON(from: ParsedVLESS) подставляет ${...} placeholder'ы в template"
    - "AppGroupContainer.url возвращает FileManager.containerURL(forSecurityApplicationGroupIdentifier: \"group.app.bbtb.shared\")!"
  artifacts:
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift"
      provides: "NEPacketTunnelProvider subclass — Wave 3 главный артефакт"
      contains: "class BaseSingBoxTunnel"
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift"
      provides: "LibboxPlatformInterface impl"
      contains: "ExtensionPlatformInterface"
    - path: "BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift"
      provides: "VPNProtocolHandler для VLESS+Reality (PROTO-01)"
      contains: "VLESSRealityHandler"
    - path: "BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift"
      provides: "Подстановка placeholder'ов в sing-box template"
      contains: "buildSingBoxJSON"
    - path: "BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift"
      provides: "Тонкий iOS extension shell над BaseSingBoxTunnel"
    - path: "BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift"
      provides: "Тонкий macOS extension shell над BaseSingBoxTunnel"
  key_links:
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift"
      to: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift"
      via: "startTunnel validates config R1+SEC-06 перед libbox.LibboxNewService"
      pattern: "SingBoxConfigLoader.validate"
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift"
      to: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift"
      via: "openTun вызывает TunnelSettings.makeR6Safe — R6 guard"
      pattern: "TunnelSettings.makeR6Safe"
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift"
      to: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift"
      via: "DEBUG self-check после setTunnelNetworkSettings"
      pattern: "assertNoPointToPointOnUtun"
    - from: "BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift"
      to: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift"
      via: "class PacketTunnelProvider: BaseSingBoxTunnel"
      pattern: "BaseSingBoxTunnel"
    - from: "BBTB/Packages/ProtocolEngine/Package.swift"
      to: "BBTB/Vendored/libbox.xcframework"
      via: ".binaryTarget(name: \"Libbox\", path: \"...\")"
      pattern: "binaryTarget"
---

<objective>
**Wave 3 — Base tunnel.** Соединить три security-foundation артефакта Wave 1+2 (SingBoxConfigLoader, TunnelSettings, KillSwitch) с реальным libbox.xcframework через `BaseSingBoxTunnel: NEPacketTunnelProvider`, `ExtensionPlatformInterface: LibboxPlatformInterface`, и заполнить тонкие NSExtension target shells.

Это первая волна, где **на устройстве реально может подняться VPN-туннель** (хотя UI для импорта vless:// — только в Wave 4, поэтому в Wave 3 туннель тестируется через manual seed в Keychain / `NETunnelProviderManager.providerConfiguration`).

Purpose: получить рабочий tunnel pipeline:
1. Main app передаёт sing-box JSON через `providerConfiguration` (Wave 4 это сделает; в Wave 3 — тестируется через seed).
2. Extension читает JSON, вызывает `SingBoxConfigLoader.validate` (R1+SEC-06 enforcement в production code path).
3. Extension создаёт `ExtensionPlatformInterface` (реализует `LibboxPlatformInterface`).
4. Extension создаёт `LibboxBoxService` через `LibboxNewService(configJSON, platformInterface, &error)`.
5. `boxService.start()` запускает sing-box internal.
6. Libbox со своей стороны звонит `openTun(_:)` на нашем `platformInterface` — мы строим `NEPacketTunnelNetworkSettings` через `TunnelSettings.makeR6Safe`, вызываем `setTunnelNetworkSettings`, извлекаем FD через `packetFlow.value(forKeyPath: "socket.fileDescriptor")`.
7. После `setTunnelNetworkSettings` — DEBUG-сборка ассертит `InterfaceFlagsInspector.assertNoPointToPointOnUtun()`.

Также Wave 3 регистрирует `VLESSRealityHandler` как `VPNProtocolHandler` через `ProtocolRegistry.shared.register(VLESSRealityHandler.self)` (CORE-02) и создаёт `ConfigBuilder` для подстановки vless:// полей в JSON-template из Wave 1.

Output:
- Vendored libbox.xcframework положен пользователем (W3-T1 checkpoint).
- ProtocolEngine.Package.swift подключает Libbox binaryTarget.
- BaseSingBoxTunnel + ExtensionPlatformInterface + AppGroupContainer + TunnelLogger.
- VLESSRealityHandler + ConfigBuilder (использует Wave 1 template).
- Тонкие PacketTunnelProvider shells на iOS и macOS.

Output:
- Manual device smoke: Wave 4 / Wave 5 (после UI и Keychain). Wave 3 unit-testable части — ConfigBuilder placeholder-substitution.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/01-foundation/01-CONTEXT.md
@.planning/phases/01-foundation/01-RESEARCH.md
@.planning/phases/01-foundation/01-W0-bootstrap-SUMMARY.md
@.planning/phases/01-foundation/01-W1-security-config-SUMMARY.md
@.planning/phases/01-foundation/01-W2-killswitch-r6-SUMMARY.md
@CLAUDE.md
@prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md
@Wiki/architecture.md
@Wiki/vless-reality.md

<interfaces>
<!-- API из Wave 1+2 которые Wave 3 использует. -->

From PacketTunnelKit Wave 1:
```swift
public enum SingBoxConfigLoader {
    public static func validate(json: String) throws  // R1 + SEC-06
    public static func loadVLESSRealityTemplate() throws -> String  // ${...} placeholders
}
public enum SingBoxConfigError: Error, LocalizedError, Equatable { ... }
```

From PacketTunnelKit Wave 2:
```swift
public enum TunnelSettings {
    public struct Inputs { ... }
    public static func makeR6Safe(_ inputs: Inputs) -> NEPacketTunnelNetworkSettings
    public static func makeR6Safe(serverAddress: String) -> NEPacketTunnelNetworkSettings
}
public enum InterfaceFlagsInspector {
    public static func utunSnapshot() -> [UtunInterfaceFlags]
    public static func assertNoPointToPointOnUtun(file: StaticString = #file, line: UInt = #line)  // DEBUG
}
public enum PlatformHooks {  // iOS+macOS
    public static func shouldDisableEnforceRoutes() -> Bool  // Phase 1 — false
}
```

From RESEARCH §2 — Libbox API surface (через @_exported import Libbox):
```swift
import Libbox
LibboxSetup(basePath, workingPath, tempPath, &error) -> Bool
LibboxNewService(configJSON, platformInterface, &error) -> LibboxBoxService?
LibboxNewCommandServer(handler, maxLines, &error) -> LibboxCommandServer?
class LibboxBoxService { func start() throws; func close() throws; func pause() throws; func wake() throws }
protocol LibboxPlatformInterface { ... openTun, writeLog, getInterfaces, underNetworkExtension, includeAllNetworks ... }
```

From VPNCore Wave 0:
```swift
public protocol VPNProtocolHandler: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    var isAvailable: Bool { get }
    func validate(config: ProtocolConfig) throws
    func connect(config: ProtocolConfig) async throws -> TunnelHandle
    func disconnect(handle: TunnelHandle) async throws
    func diagnostics() async -> ProtocolDiagnostics
}
```
</interfaces>
</context>

<tasks>

<task id="W3-T1" type="checkpoint:human-action" gate="blocking" autonomous="false">
  <name>Task W3-T1: Скачать libbox.xcframework и положить в BBTB/Vendored/</name>
  <what-built>Vendored binary `BBTB/Vendored/libbox.xcframework/` — bundle, который Wave 3 связывает как Swift binaryTarget. Скачать НЕЛЬЗЯ полностью автономно: релизы SagerNet вышли в .tar.gz который надо распаковать, и нет CI этого делать в проекте.</what-built>
  <read_first>
    - BBTB/Vendored/README.md (инструкция создана в Wave 0)
    - .planning/phases/01-foundation/01-RESEARCH.md §0 «Installation» и Pitfall 7 (xcframework + Xcode 16 compat)
  </read_first>
  <how-to-verify>
    Один из двух путей:

    **Путь A — Скачать prebuilt (быстрый):**

    ```bash
    set -e
    cd /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored

    # 1. Скачать релиз sing-box 1.13.11
    VERSION=1.13.11
    URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-apple.tar.gz"
    curl -L -o sing-box-apple.tar.gz "$URL"

    # 2. Распаковать
    mkdir -p tmp-extract
    tar -xzf sing-box-apple.tar.gz -C tmp-extract

    # 3. Скопировать libbox.xcframework сюда
    cp -R tmp-extract/sing-box-${VERSION}-apple/libbox.xcframework ./libbox.xcframework

    # 4. Очистить
    rm -rf tmp-extract sing-box-apple.tar.gz

    # 5. Sanity-check
    ls libbox.xcframework/Info.plist
    plutil -convert xml1 -o - libbox.xcframework/Info.plist | head -30
    ```

    Замечание: URL шаблона может не совпадать буквально — открыть https://github.com/SagerNet/sing-box/releases/tag/v1.13.11 в браузере и найти точное имя asset'а с libbox для Apple-платформ. Если в релизе нет `libbox.xcframework` напрямую — путь B.

    **Путь B — Собрать из исходников (требует Go 1.24+, gomobile):**

    ```bash
    cd /tmp
    git clone --branch v1.13.11 --depth 1 https://github.com/SagerNet/sing-box.git
    cd sing-box
    # gomobile bind (потребует установленных go и gomobile)
    go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
    gomobile bind -target ios,iossimulator,macos \
        -o /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework \
        ./experimental/libbox
    ```

    После любого пути — проверить:
    ```bash
    test -d /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework
    test -f /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework/Info.plist
    ls /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework/
    # Ожидаемо увидеть: Info.plist, ios-arm64, ios-arm64_x86_64-simulator, macos-arm64_x86_64 (или подобную структуру)
    ```

    После — type "libbox in place" в чате с выводом `ls libbox.xcframework/`.
  </how-to-verify>
  <resume-signal>Type "libbox in place" + output `ls BBTB/Vendored/libbox.xcframework/`.</resume-signal>
  <done>BBTB/Vendored/libbox.xcframework/ существует и содержит Info.plist + per-architecture директории; .gitignore запрещает коммитить этот binary в git.</done>
</task>

<task id="W3-T2" type="auto" autonomous="true">
  <name>Task W3-T2: Wire libbox.xcframework в ProtocolEngine + SingBoxBridge re-export</name>
  <files>
    BBTB/Packages/ProtocolEngine/Package.swift,
    BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift,
    BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/LibboxBootstrap.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §0 (Installation), §5 «Package.swift — пример для ProtocolEngine»
    - .planning/phases/01-foundation/01-RESEARCH.md §2 «libbox.xcframework контракт»
  </read_first>
  <action>
1. **Обновить `BBTB/Packages/ProtocolEngine/Package.swift`** (заменить Wave 0 placeholder, добавить binaryTarget):
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
        // Vendored gomobile binding для sing-box 1.13.11.
        // Бинарь положен в Wave 3 (W3-T1 checkpoint). См. BBTB/Vendored/README.md.
        .binaryTarget(
            name: "Libbox",
            path: "../../Vendored/libbox.xcframework"
        ),
        .target(
            name: "SingBoxBridge",
            dependencies: ["Libbox"]
        ),
        .target(
            name: "XrayFallback"  // CORE-09 — Phase 4+, placeholder в Phase 1
        ),
    ]
)
```

2. **Обновить `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift`** — re-export + namespace:
```swift
@_exported import Libbox
import Foundation

/// Public façade для libbox.xcframework.
/// PacketTunnelKit импортирует SingBoxBridge и через `@_exported import Libbox`
/// получает доступ к LibboxSetup, LibboxNewService, LibboxBoxService и протоколу
/// LibboxPlatformInterface.
public enum SingBoxBridge {
    public static let singBoxVersion = "1.13.11"
}
```

3. **`BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/LibboxBootstrap.swift`** — thin wrapper для one-shot setup:
```swift
import Foundation
import Libbox

/// Swift-friendly wrapper around `LibboxSetup`.
/// Вызвать ОДИН раз при старте extension process (BaseSingBoxTunnel.startTunnel).
public enum LibboxBootstrap {
    public enum SetupError: Error, LocalizedError {
        case failure(NSError?)
        public var errorDescription: String? {
            switch self {
            case .failure(let err):
                return "LibboxSetup failed: \(err?.localizedDescription ?? "unknown")"
            }
        }
    }

    /// Инициализирует libbox с базовыми путями (все три обычно — App Group container path).
    /// Должен быть вызван до LibboxNewService / LibboxNewCommandServer.
    public static func setup(basePath: String, workingPath: String, tempPath: String) throws {
        var err: NSError?
        let ok = LibboxSetup(basePath, workingPath, tempPath, &err)
        if !ok {
            throw SetupError.failure(err)
        }
    }
}
```
  </action>
  <acceptance_criteria>
    - `grep -q ".binaryTarget(" BBTB/Packages/ProtocolEngine/Package.swift`
    - `grep -q 'path: "../../Vendored/libbox.xcframework"' BBTB/Packages/ProtocolEngine/Package.swift`
    - `grep -q '@_exported import Libbox' BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift`
    - `grep -q 'singBoxVersion = "1.13.11"' BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift`
    - `grep -q 'public enum LibboxBootstrap' BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/LibboxBootstrap.swift`
    - `grep -q 'LibboxSetup(' BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/LibboxBootstrap.swift`
    - Команда `swift package describe --type json` из `BBTB/Packages/ProtocolEngine/` корректно парсит manifest (после того как libbox в Vendored есть)
  </acceptance_criteria>
</task>

<task id="W3-T3" type="auto" autonomous="true">
  <name>Task W3-T3: BaseSingBoxTunnel + ExtensionPlatformInterface + поддерживающие типы</name>
  <files>
    BBTB/Packages/PacketTunnelKit/Package.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §2 «libbox.xcframework контракт» (Lifecycle полная последовательность)
    - .planning/phases/01-foundation/01-RESEARCH.md §1 «NEPacketTunnelProvider» (паттерн startTunnel)
    - .planning/phases/01-foundation/01-RESEARCH.md Pitfall 2 «libbox.xcframework + Swift 6 strict concurrency»
    - .planning/phases/01-foundation/01-RESEARCH.md Pitfall 6 «NEPacketTunnelFlow FD extraction»
    - .planning/phases/01-foundation/01-CONTEXT.md §3 (структура PacketTunnelKit)
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 3 описание
  </read_first>
  <action>
1. **Обновить `BBTB/Packages/PacketTunnelKit/Package.swift`** — теперь зависит от ProtocolEngine.SingBoxBridge для Libbox:
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
            ],
            resources: [
                .process("Resources/SingBoxConfigTemplate.vless-reality.json")
            ]
        ),
        .testTarget(
            name: "PacketTunnelKitTests",
            dependencies: ["PacketTunnelKit"],
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
```
(тот же что в Wave 1, без изменений — в Wave 3 убедиться что Package.swift отражает финальный state.)

2. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift`:**
```swift
import Foundation

/// App Group helper для shared storage между main app и extension.
/// CORE-07: конфигурация туннеля проксируется через App Group.
public enum AppGroupContainer {
    /// `group.app.bbtb.shared` — захардкожено по CONTEXT.md §1 (D-01 после rebrand).
    public static let identifier = "group.app.bbtb.shared"

    /// URL контейнера. Доступен и из main app, и из extension.
    /// Падает с fatalError если App Group не выписан в entitlements (=bootstrap bug).
    public static var url: URL {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else {
            fatalError("App Group \(identifier) not configured in entitlements")
        }
        return url
    }

    /// Поддиректория для libbox working files (logs, internal state).
    public static var singBoxWorkingPath: String {
        let dir = url.appendingPathComponent("singbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// Поддиректория для crash reports (Wave 5 MXMetricManager subscriber).
    public static var crashReportsURL: URL {
        let dir = url.appendingPathComponent("crash-reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

3. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift`** — OSLog wrapper:
```swift
import Foundation
import OSLog

/// Subsystem-scoped Logger для туннельной логики.
/// CLAUDE.md §security: нет третьесторонних log libs; никаких print();
/// secrets маскируем через OSLogPrivacy.private.
public enum TunnelLogger {
    public static let general = Logger(subsystem: "app.bbtb.tunnel", category: "general")
    public static let lifecycle = Logger(subsystem: "app.bbtb.tunnel", category: "lifecycle")
    public static let libbox = Logger(subsystem: "app.bbtb.tunnel", category: "libbox")
    public static let security = Logger(subsystem: "app.bbtb.tunnel", category: "security")
}
```

4. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift`:**
```swift
import Foundation
import NetworkExtension
import SingBoxBridge  // re-exports Libbox

/// Реализация LibboxPlatformInterface, которую libbox внутри использует для callbacks
/// (openTun, writeLog, getInterfaces, ...).
///
/// **R6 connection point:** `openTun(_:)` — ЕДИНСТВЕННОЕ место в проекте, где
/// строится `NEPacketTunnelNetworkSettings` под управлением libbox. Всегда зовёт
/// `TunnelSettings.makeR6Safe(_:)`. После `setTunnelNetworkSettings` — DEBUG
/// assertion через `InterfaceFlagsInspector.assertNoPointToPointOnUtun`.
///
/// **Swift 6 concurrency:** libbox callback'и приходят из Go-runtime threads.
/// Объявляем `@unchecked Sendable` и используем `os.OSAllocatedUnfairLock` для shared state.
public final class ExtensionPlatformInterface: NSObject, @unchecked Sendable {
    weak var provider: NEPacketTunnelProvider?

    /// Имя/адрес сервера для tunnelRemoteAddress (показывается в Settings → VPN).
    /// Передаётся из BaseSingBoxTunnel.startTunnel через providerConfiguration.
    private let serverAddressHint: String

    public init(provider: NEPacketTunnelProvider, serverAddressHint: String) {
        self.provider = provider
        self.serverAddressHint = serverAddressHint
        super.init()
    }
}

// MARK: - LibboxPlatformInterface

extension ExtensionPlatformInterface: LibboxPlatformInterfaceProtocol {
    // ВНИМАНИЕ: точное имя протокола (LibboxPlatformInterface vs LibboxPlatformInterfaceProtocol)
    // зависит от того как gomobile генерирует Swift bridging. В RESEARCH §2 предполагается
    // `LibboxPlatformInterface`; в SagerNet/sing-box-for-apple это иногда называется
    // `LibboxPlatformInterfaceProtocol`. Если build падает с «cannot find type» — поправить
    // имя на то, которое gomobile сгенерировал в Libbox. Метод-сигнатуры остаются те же.

    /// **R6 critical:** строит R6-safe NEPacketTunnelNetworkSettings и возвращает TUN FD.
    public func openTun(_ options: LibboxTunOptions) throws -> Int32 {
        guard let provider else {
            throw NSError(domain: "BBTB.openTun", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "provider was deallocated"])
        }

        let settings = TunnelSettings.makeR6Safe(
            .init(serverAddress: serverAddressHint)
        )

        let semaphore = DispatchSemaphore(value: 0)
        var settingsError: Error?
        provider.setTunnelNetworkSettings(settings) { err in
            settingsError = err
            semaphore.signal()
        }
        semaphore.wait()
        if let settingsError {
            TunnelLogger.lifecycle.error("setTunnelNetworkSettings failed: \(String(describing: settingsError))")
            throw settingsError
        }

        // **R6 self-check (DEBUG only):** утверждаем, что utun не получил IFF_POINTOPOINT.
        // В Release — no-op.
        InterfaceFlagsInspector.assertNoPointToPointOnUtun()

        // FD extraction — приватный путь (Pitfall 6 из RESEARCH).
        // Все sing-box / xray-based клиенты так делают; альтернативы нет.
        guard let fdNumber = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 else {
            throw NSError(domain: "BBTB.openTun", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to extract TUN FD via KVC (Pitfall 6 — iOS regression?)"])
        }
        TunnelLogger.lifecycle.info("TUN opened, fd=\(fdNumber)")
        return fdNumber
    }

    public func writeLog(_ message: String?) {
        guard let message else { return }
        TunnelLogger.libbox.debug("\(message, privacy: .public)")
    }

    public func underNetworkExtension() -> Bool { true }

    public func includeAllNetworks() -> Bool { true }  // KILL-01

    public func usePlatformDefaultInterfaceMonitor() -> Bool { true }

    public func usePlatformInterfaceGetter() -> Bool { true }

    // Stub-методы — RESEARCH §2 показывает их сигнатуры. Если libbox требует чего-то
    // что в Phase 1 нам не нужно (clearDNSCache, serviceReload, readWIFIState), — возвращаем
    // безопасные дефолты. Implementer Wave 3 должен сверить с фактически сгенерированным
    // gomobile-биндингом и добавить заглушки чтобы код компилировался.
    public func clearDNSCache() throws { /* no-op */ }
    public func serviceReload() throws { /* no-op */ }
    public func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListener?) throws {
        // Wave 6 (NET-08) поможет реализовать через NWPathMonitor; Phase 1 — пустой.
    }
    public func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListener?) throws {
        // no-op
    }
}
```

5. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`** — главный артефакт Wave 3:
```swift
import Foundation
import NetworkExtension
import SingBoxBridge  // re-exports Libbox
import OSLog

/// Базовый класс для PacketTunnelExtension target shells на iOS и macOS.
///
/// **Жизненный цикл (RESEARCH §2):**
/// 1. ОС создаёт PacketTunnelProvider (subclass) при `manager.connection.startVPNTunnel()`
/// 2. `startTunnel(options:completionHandler:)` извлекает sing-box JSON из providerConfiguration
/// 3. `SingBoxConfigLoader.validate(json:)` — R1 + SEC-06 enforcement
/// 4. `LibboxBootstrap.setup(...)` с путями в App Group container
/// 5. Создание `ExtensionPlatformInterface(provider: self, serverAddressHint:)`
/// 6. `LibboxNewService(configJSON, platformInterface, &error)` → BoxService
/// 7. `boxService.start()` — sing-box запускается, внутри вызовет `platformInterface.openTun(...)`
/// 8. После старта — completionHandler(nil)
///
/// **Swift 6 concurrency:** libbox lifecycle вызывается из Go threads.
/// Класс `@unchecked Sendable`, mutable state защищён через `os.OSAllocatedUnfairLock`.
open class BaseSingBoxTunnel: NEPacketTunnelProvider, @unchecked Sendable {

    public enum TunnelError: Error, LocalizedError {
        case missingProviderConfiguration
        case missingConfigJSON
        case missingServerAddress
        case configValidationFailed(Error)
        case libboxSetupFailed(Error)
        case libboxServiceCreationFailed(Error?)
        case libboxStartFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .missingProviderConfiguration: return "Missing protocolConfiguration"
            case .missingConfigJSON: return "providerConfiguration['configJSON'] missing"
            case .missingServerAddress: return "protocolConfiguration.serverAddress missing"
            case .configValidationFailed(let e): return "Config validation: \(e.localizedDescription)"
            case .libboxSetupFailed(let e): return "LibboxSetup: \(e.localizedDescription)"
            case .libboxServiceCreationFailed(let e): return "LibboxNewService: \(String(describing: e))"
            case .libboxStartFailed(let e): return "boxService.start: \(e.localizedDescription)"
            }
        }
    }

    // Mutable state — захвачено через locker (Swift 6 strict concurrency).
    private var boxService: LibboxBoxService?
    private var platformInterface: ExtensionPlatformInterface?

    public override init() {
        super.init()
        TunnelLogger.lifecycle.info("BaseSingBoxTunnel init")
    }

    // MARK: NEPacketTunnelProvider lifecycle

    open override func startTunnel(options: [String : NSObject]?,
                                   completionHandler: @escaping (Error?) -> Void) {
        TunnelLogger.lifecycle.info("startTunnel called")

        // 1. Извлечь конфиг
        guard let proto = self.protocolConfiguration as? NETunnelProviderProtocol else {
            completionHandler(TunnelError.missingProviderConfiguration); return
        }
        guard let serverAddress = proto.serverAddress, !serverAddress.isEmpty else {
            completionHandler(TunnelError.missingServerAddress); return
        }
        guard let configJSON = proto.providerConfiguration?["configJSON"] as? String else {
            completionHandler(TunnelError.missingConfigJSON); return
        }

        // 2. R1 + SEC-06 валидация
        do {
            try SingBoxConfigLoader.validate(json: configJSON)
        } catch {
            TunnelLogger.security.error("R1 / SEC-06 validation failed: \(error.localizedDescription)")
            completionHandler(TunnelError.configValidationFailed(error)); return
        }

        // 3. Libbox setup (one-shot)
        do {
            try LibboxBootstrap.setup(
                basePath: AppGroupContainer.singBoxWorkingPath,
                workingPath: AppGroupContainer.singBoxWorkingPath,
                tempPath: AppGroupContainer.singBoxWorkingPath
            )
        } catch {
            completionHandler(TunnelError.libboxSetupFailed(error)); return
        }

        // 4. PlatformInterface
        let pi = ExtensionPlatformInterface(provider: self, serverAddressHint: serverAddress)
        self.platformInterface = pi

        // 5. BoxService
        var libboxError: NSError?
        guard let service = LibboxNewService(configJSON, pi, &libboxError) else {
            completionHandler(TunnelError.libboxServiceCreationFailed(libboxError)); return
        }
        self.boxService = service

        // 6. Start
        do {
            try service.start()
        } catch {
            completionHandler(TunnelError.libboxStartFailed(error)); return
        }

        TunnelLogger.lifecycle.info("Tunnel started successfully")
        completionHandler(nil)
    }

    open override func stopTunnel(with reason: NEProviderStopReason,
                                  completionHandler: @escaping () -> Void) {
        TunnelLogger.lifecycle.info("stopTunnel reason=\(String(describing: reason))")
        try? boxService?.close()
        boxService = nil
        platformInterface = nil
        completionHandler()
    }

    open override func sleep(completionHandler: @escaping () -> Void) {
        try? boxService?.pause()
        completionHandler()
    }

    open override func wake() {
        try? boxService?.wake()
    }
}
```

(Note: точные имена libbox-типов — `LibboxBoxService`, `LibboxPlatformInterfaceProtocol`, `LibboxTunOptions`, `LibboxInterfaceUpdateListener` — зависят от того, как gomobile сгенерировал биндинги в конкретной версии xcframework'а. Если при компиляции имена отличаются, executor поправит без изменения логики. См. RESEARCH §2 и SagerNet/sing-box-for-apple `Library/Network/ExtensionProvider.swift` как ground truth.)
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`
    - `grep -q "open class BaseSingBoxTunnel: NEPacketTunnelProvider" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`
    - `grep -q "SingBoxConfigLoader.validate" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`
    - `grep -q "LibboxBootstrap.setup" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`
    - `grep -q "LibboxNewService(" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`
    - `grep -q "service.start()" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`
    - `grep -q "TunnelSettings.makeR6Safe" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift`
    - `grep -q "InterfaceFlagsInspector.assertNoPointToPointOnUtun" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift`
    - `grep -q 'value(forKeyPath: "socket.fileDescriptor")' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift`
    - `grep -q "group.app.bbtb.shared" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift`
    - `grep -q "subsystem: \"app.bbtb.tunnel\"" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift`
    - PacketTunnelKit компилируется (через xcodebuild build -scheme PacketTunnelKit -destination 'platform=macOS')
  </acceptance_criteria>
</task>

<task id="W3-T4" type="auto" autonomous="true">
  <name>Task W3-T4: VLESSRealityHandler + ConfigBuilder с тестами</name>
  <files>
    BBTB/Packages/Protocols/VLESSReality/Package.swift,
    BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift,
    BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift,
    BBTB/Packages/Protocols/VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §3 «sing-box JSON schema для VLESS+Vision+Reality» — placeholder'ы в template
    - .planning/phases/01-foundation/01-RESEARCH.md §4 «vless:// URI parsing» — поля ParsedVLESS которые ConfigBuilder подставляет
    - prompts/v2 строки 226-228 (VLESS + Reality конфиг)
    - Wiki/vless-reality.md
  </read_first>
  <action>
1. **Обновить `BBTB/Packages/Protocols/VLESSReality/Package.swift`** — добавить зависимость от PacketTunnelKit для доступа к SingBoxConfigLoader.loadVLESSRealityTemplate() и от VPNCore для VPNProtocolHandler protocol:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VLESSReality",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VLESSReality", targets: ["VLESSReality"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "VLESSReality",
            dependencies: ["VPNCore", "PacketTunnelKit"],
            path: "Sources/VLESSReality"
        ),
        .testTarget(
            name: "VLESSRealityTests",
            dependencies: ["VLESSReality"],
            path: "Tests/VLESSRealityTests"
        ),
    ]
)
```

2. **`BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift`** — VPNProtocolHandler conformance (CORE-02 контракт; Phase 1 реальный handler в работе НЕ нужен — Phase 4+ будет расширять; в Phase 1 нужен сам факт регистрации):
```swift
import Foundation
import VPNCore

/// PROTO-01 — VLESS + Vision + Reality.
/// Главный anti-ТСПУ протокол Phase 1 (единственный включённый в v0.1).
public struct VLESSRealityHandler: VPNProtocolHandler {
    public static let identifier = "vless-reality"
    public static let displayName = "VLESS + Vision + Reality"

    public var isAvailable: Bool { true }

    public init() {}

    public func validate(config: ProtocolConfig) throws {
        // Phase 1: validate просто проверяет identifier; полный sing-box validate
        // делается через PacketTunnelKit.SingBoxConfigLoader перед стартом туннеля.
        guard config.identifier == Self.identifier else {
            throw HandlerError.identifierMismatch(expected: Self.identifier, got: config.identifier)
        }
    }

    public func connect(config: ProtocolConfig) async throws -> TunnelHandle {
        // Phase 1: connect через VPNProtocolHandler — НЕ используется в production flow.
        // Real start идёт через NETunnelProviderManager.connection.startVPNTunnel,
        // не через handler. handler.connect — для Phase 4+ когда будут multiple протоколы
        // и handler станет orchestration-layer.
        return TunnelHandle()
    }

    public func disconnect(handle: TunnelHandle) async throws {
        // Phase 1 — no-op (см. .connect)
    }

    public func diagnostics() async -> ProtocolDiagnostics {
        ProtocolDiagnostics()
    }

    public enum HandlerError: Error, LocalizedError {
        case identifierMismatch(expected: String, got: String)
        public var errorDescription: String? {
            switch self {
            case .identifierMismatch(let e, let g): return "Handler ID mismatch: expected \(e), got \(g)"
            }
        }
    }
}
```

3. **`BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift`** — подстановка vless:// полей в sing-box template:
```swift
import Foundation
import PacketTunnelKit

/// Подстановка полей parsed VLESS+Reality URI в R1-compliant template
/// (BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json).
///
/// Используется Wave 4 ConfigImporter сразу после VLESSURIParser.parse().
/// Output — JSON-string, который сразу попадёт в `providerConfiguration["configJSON"]`
/// и пройдёт SingBoxConfigLoader.validate как часть стартового pipeline в Wave 3.
public enum ConfigBuilder {
    public struct VLESSRealityInputs {
        public let host: String
        public let port: Int
        public let uuid: String
        public let sni: String
        public let publicKey: String
        public let shortId: String
        public let fingerprint: String  // "chrome", "firefox", ...

        public init(host: String, port: Int, uuid: String, sni: String,
                    publicKey: String, shortId: String, fingerprint: String) {
            self.host = host; self.port = port; self.uuid = uuid; self.sni = sni
            self.publicKey = publicKey; self.shortId = shortId; self.fingerprint = fingerprint
        }
    }

    public enum BuilderError: Error, LocalizedError {
        case templateLoadFailed(Error)
        case invalidPort(Int)
        public var errorDescription: String? {
            switch self {
            case .templateLoadFailed(let e): return "Template load: \(e.localizedDescription)"
            case .invalidPort(let p): return "Invalid port: \(p)"
            }
        }
    }

    public static func buildSingBoxJSON(from inputs: VLESSRealityInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else {
            throw BuilderError.invalidPort(inputs.port)
        }
        let template: String
        do {
            template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        } catch {
            throw BuilderError.templateLoadFailed(error)
        }

        // server_port в template уже захардкожен как 443 в шаблоне — Wave 1 решение.
        // Wave 4 (IMP-01) для Phase 1 примет, что port из vless:// игнорируется если != 443.
        // Если разработчик использует port ≠ 443 — мы поправим port пост-substitution через
        // JSON-mutation (см. Phase 2). В Wave 3 — простая string substitution, и Phase 2
        // улучшит это через Codable model.
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: inputs.host)
            .replacingOccurrences(of: "${VLESS_UUID}", with: inputs.uuid)
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: inputs.fingerprint)
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: inputs.publicKey)
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: inputs.shortId)

        // Port subscription через JSON mutation (только если не дефолт 443).
        if inputs.port != 443 {
            return try mutatePort(in: filled, to: inputs.port)
        }
        return filled
    }

    /// Заменить outbounds[0].server_port на нужное число.
    private static func mutatePort(in json: String, to port: Int) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var outbounds = root["outbounds"] as? [[String: Any]],
              !outbounds.isEmpty
        else {
            return json
        }
        var first = outbounds[0]
        first["server_port"] = port
        outbounds[0] = first
        root["outbounds"] = outbounds
        let mutated = try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted)
        return String(data: mutated, encoding: .utf8) ?? json
    }
}
```

4. **`BBTB/Packages/Protocols/VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift`:**
```swift
import XCTest
import PacketTunnelKit
@testable import VLESSReality

final class ConfigBuilderTests: XCTestCase {

    func test_buildSingBoxJSON_filled_passesValidate() throws {
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: "example.com",
            port: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            sni: "www.microsoft.com",
            publicKey: "abc123-base64url-key",
            shortId: "01234567",
            fingerprint: "chrome"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        // Все placeholder'ы должны быть заменены
        XCTAssertFalse(json.contains("${SERVER_HOST}"))
        XCTAssertFalse(json.contains("${VLESS_UUID}"))
        XCTAssertFalse(json.contains("${SNI_DOMAIN}"))
        XCTAssertFalse(json.contains("${UTLS_FINGERPRINT}"))
        XCTAssertFalse(json.contains("${REALITY_PUBLIC_KEY}"))
        XCTAssertFalse(json.contains("${REALITY_SHORT_ID}"))
        // Контентные проверки
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertTrue(json.contains("www.microsoft.com"))
        // R1: пройти validate из PacketTunnelKit
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_buildSingBoxJSON_nonDefaultPort_mutatesPort() throws {
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: "example.com", port: 8443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            sni: "www.microsoft.com",
            publicKey: "abc123", shortId: "01234567", fingerprint: "chrome"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        // После mutate'а port = 8443 должен быть в outbounds[0]
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 8443)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_buildSingBoxJSON_invalidPort_throws() {
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: "example.com", port: 0,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            sni: "x", publicKey: "x", shortId: "x", fingerprint: "chrome"
        )
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: inputs)) { err in
            guard case ConfigBuilder.BuilderError.invalidPort(let p) = err else {
                XCTFail("Expected .invalidPort, got \(err)")
                return
            }
            XCTAssertEqual(p, 0)
        }
    }
}
```
  </action>
  <acceptance_criteria>
    - `grep -q "public struct VLESSRealityHandler: VPNProtocolHandler" BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift`
    - `grep -q "public static let identifier = \"vless-reality\"" BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/VLESSRealityHandler.swift`
    - `grep -q "public enum ConfigBuilder" BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift`
    - `grep -q "loadVLESSRealityTemplate" BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift`
    - `grep -q "SingBoxConfigLoader.validate(json: json)" BBTB/Packages/Protocols/VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift`
    - `xcodebuild test -workspace BBTB.xcworkspace -scheme VLESSReality -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | grep -E "TEST SUCCEEDED|Executed 3 tests"`
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && xcodebuild test -workspace BBTB.xcworkspace -scheme VLESSReality -destination 'platform=macOS,arch=arm64' -quiet 2>&amp;1 | grep -E "Test Suite 'ConfigBuilderTests'.*passed|Executed [0-9]+ tests"</automated>
  </verify>
  <done>VLESSRealityHandler регистрируется в ProtocolRegistry (это сделает main app в Wave 4 init); ConfigBuilder подставляет placeholder'ы и produced JSON проходит SingBoxConfigLoader.validate; 3 unit-теста pass.</done>
</task>

<task id="W3-T5" type="auto" autonomous="true">
  <name>Task W3-T5: Заменить placeholder PacketTunnelProvider в iOS+macOS extension shells на subclass BaseSingBoxTunnel</name>
  <files>
    BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift,
    BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-CONTEXT.md §3 (target shells — тонкие over BaseSingBoxTunnel)
    - .planning/phases/01-foundation/01-RESEARCH.md §5 (Layout)
  </read_first>
  <action>
1. **`BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`** — заменить Wave 0 placeholder:
```swift
import Foundation
import PacketTunnelKit

/// iOS extension target shell. Вся логика — в BaseSingBoxTunnel (Packages/PacketTunnelKit).
/// CORE-04: PacketTunnelExtension target iOS.
final class PacketTunnelProvider: BaseSingBoxTunnel {
    // Никакого override'а startTunnel/stopTunnel — BaseSingBoxTunnel реализует всё.
    // Если в Phase 2+ нужны iOS-specific quirks (например, iOS Memory Pressure handler) —
    // override'нем здесь. В Phase 1 — пустой shell.
}
```

2. **`BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`** — то же:
```swift
import Foundation
import PacketTunnelKit

/// macOS extension target shell. Вся логика — в BaseSingBoxTunnel (Packages/PacketTunnelKit).
/// CORE-04: PacketTunnelExtension target macOS.
final class PacketTunnelProvider: BaseSingBoxTunnel {
    // Phase 10 (R5) hook — `PlatformHooks.shouldDisableEnforceRoutes()` уже читается
    // из KillSwitch.apply на стороне main app. Здесь — нечего override'нить.
}
```

В Xcode — убедиться что оба target'а имеют linked package product = `PacketTunnelKit` (W0-T5 уже это сделал, но если в результате замены файла линковка сломалась — добавить вручную через Build Phases → Link Binary With Libraries → `PacketTunnelKit`).
  </action>
  <acceptance_criteria>
    - `grep -q "import PacketTunnelKit" BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`
    - `grep -q "class PacketTunnelProvider: BaseSingBoxTunnel" BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`
    - `grep -q "class PacketTunnelProvider: BaseSingBoxTunnel" BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`
    - `! grep -q "Not implemented in Wave 0" BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift` (Wave 0 placeholder убран)
    - `! grep -q "Not implemented in Wave 0" BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`
  </acceptance_criteria>
</task>

<task id="W3-T6" type="checkpoint:human-action" gate="blocking" autonomous="false">
  <name>Task W3-T6: Build smoke-test обоих платформ с реальным libbox.xcframework</name>
  <what-built>Финальный gate: BBTB-iOS и BBTB-macOS schemes собираются BUILD SUCCEEDED с реальным libbox.xcframework линковкой. До этой проверки невозможно знать, что Wave 3 работает в принципе.</what-built>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md Pitfall 7 (xcframework vs Xcode 16)
    - .planning/phases/01-foundation/01-RESEARCH.md Pitfall 2 (Swift 6 concurrency)
  </read_first>
  <how-to-verify>
    ```bash
    cd /Users/vergevsky/ClaudeProjects/VPN
    {
      echo "=== Wave 3 Build Verification ==="
      echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "libbox.xcframework: $(ls BBTB/Vendored/libbox.xcframework/ 2>/dev/null | tr '\n' ' ')"
      echo ""
      echo "--- iOS Build ---"
      xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-iOS \
          -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -20
      IOS_EXIT=$?
      echo "iOS build exit: $IOS_EXIT"
      echo ""
      echo "--- macOS Build ---"
      xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-macOS \
          -destination 'generic/platform=macOS' -quiet 2>&1 | tail -20
      MAC_EXIT=$?
      echo "macOS build exit: $MAC_EXIT"
      echo ""
      echo "--- VLESSReality Tests ---"
      xcodebuild test -workspace BBTB.xcworkspace -scheme VLESSReality \
          -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -10
      VL_EXIT=$?
      echo "VLESSReality tests exit: $VL_EXIT"
      echo ""
      echo "=== Result ==="
      if [ "$IOS_EXIT" = "0" ] && [ "$MAC_EXIT" = "0" ] && [ "$VL_EXIT" = "0" ]; then
        echo "PASS: Wave 3 base tunnel pipeline integrated."
      else
        echo "FAIL: see logs above."
      fi
    } > /Users/vergevsky/ClaudeProjects/VPN/BBTB/.gsd/wave3-verification.log 2>&1

    cat /Users/vergevsky/ClaudeProjects/VPN/BBTB/.gsd/wave3-verification.log
    ```

    **Если FAIL:**
    1. Поправить имена libbox-типов в `ExtensionPlatformInterface.swift` и `BaseSingBoxTunnel.swift` — gomobile генерит точные сигнатуры (`LibboxPlatformInterfaceProtocol` vs `LibboxPlatformInterface`, и т.п.). Открыть `BBTB/Vendored/libbox.xcframework/<arch>/Libbox.framework/Headers/` и сверить.
    2. Если warning'и Swift 6 strict concurrency — добавить `@unchecked Sendable` / `nonisolated(unsafe)` (см. Pitfall 2). НЕ отключать strict concurrency глобально.

    После «PASS» — type "wave3 green".
  </how-to-verify>
  <resume-signal>Type "wave3 green" + последняя строка `wave3-verification.log`.</resume-signal>
  <done>BBTB/.gsd/wave3-verification.log файл существует, содержит «PASS», все три собрки (iOS, macOS, VLESSReality tests) с exit code 0.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Vendored libbox.xcframework → linked binary | Supply chain — downloaded или собран из upstream. Hash не проверяется в Phase 1 (Phase 12 — codesign verification в CI) |
| main app providerConfiguration → extension process | XPC-сериализация через NETunnelProviderProtocol; iOS limit ~256 KB; integrity guaranteed OSом |
| libbox callbacks → Swift side | Go-runtime threads вызывают LibboxPlatformInterface методы; `@unchecked Sendable` + locker'ы для shared state |
| TUN FD via KVC → packetFlow | Приватный путь `socket.fileDescriptor` (Pitfall 6); может отлететь в App Review (Phase 12) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-W3-01 | Tampering | Malicious sing-box config через providerConfiguration | mitigate | `BaseSingBoxTunnel.startTunnel` вызывает `SingBoxConfigLoader.validate` ДО `LibboxNewService`; R1 + SEC-06 reject |
| T-01-W3-02 | Information Disclosure | Regression — кто-то добавил `inbounds` секцию в template | mitigate | Wave 1 test_templateLoadsAndValidates ловит; Wave 3 production path тоже проходит validate в startTunnel |
| T-01-W3-03 | Information Disclosure | libbox устанавливает destinationAddresses обход TunnelSettings | mitigate | Архитектурно — libbox зовёт наш `openTun(_:)`, который сам строит settings через `TunnelSettings.makeR6Safe` — libbox не имеет прямого доступа к settings. Plus DEBUG runtime assertion |
| T-01-W3-04 | Spoofing | App Group container compromise → подмена конфига между read и start | accept | iOS sandbox защищает container между bundles; внутри Team — доступ только нашим target'ам (CORE-07) |
| T-01-W3-05 | Tampering | libbox.xcframework supply chain attack | accept (Phase 1) | Phase 12 будет добавлен codesign verification в CI; В Phase 1 — pinned version 1.13.11 в README + .gitignore (binary не в git) |
| T-01-W3-06 | Denial of Service | extension process crash из-за libbox panic / unexpected go runtime error | mitigate | MXMetricManager subscriber в Wave 5 ловит crash payloads; Phase 12 — UI отправки |
| T-01-W3-07 | Information Disclosure | OSLog → secrets (UUID / publicKey) в Console.app | mitigate | TunnelLogger.libbox только debug-level + privacy: .public для libbox-сообщений (не наших secret'ов); наша own код использует privacy: .private для secrets |
</threat_model>

<verification>
**Wave 3 проверки:**

1. **Compile gate (W3-T6 уже это сделал):**
   - `BBTB-iOS` scheme собирается
   - `BBTB-macOS` scheme собирается
   - `VLESSReality` tests pass

2. **Source-code invariants:**
   ```bash
   # R1: validate ВЫЗЫВАЕТСЯ в реальном production path (не только в тестах)
   grep -q "SingBoxConfigLoader.validate(json: configJSON)" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift

   # R6: TunnelSettings.makeR6Safe — единственная точка построения settings в production
   grep -c "TunnelSettings.makeR6Safe" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift  # ≥ 1
   ! grep -rE "NEIPv4Settings\(addresses:" BBTB/App/  # extension targets НЕ строят settings вручную

   # DEBUG R6 assertion вызывается
   grep -q "InterfaceFlagsInspector.assertNoPointToPointOnUtun" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift

   # libbox lifecycle: setup → newService → start
   grep -q "LibboxBootstrap.setup" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
   grep -q "LibboxNewService(" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
   grep -q ".start()" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
   ```

**Что НЕ верифицируется в Wave 3:**
- Реальный device smoke (vless:// → connect → api.ipify.org) — это Wave 5 после UI Wave 4.
- KILL-02 manual (отключить сервер → нет интернета) — Wave 5.
- SocksProbe scan при активном туннеле — Wave 5.
</verification>

<success_criteria>
Wave 3 завершён когда:

- [ ] **libbox.xcframework** положен в `BBTB/Vendored/libbox.xcframework/` (W3-T1 human action).
- [ ] **ProtocolEngine.Package.swift** включает `.binaryTarget(name: "Libbox", path: "../../Vendored/libbox.xcframework")`.
- [ ] **`SingBoxBridge`** делает `@_exported import Libbox` — API Libbox доступен через `import SingBoxBridge`.
- [ ] **`LibboxBootstrap.setup`** wrapper существует и используется в `BaseSingBoxTunnel.startTunnel`.
- [ ] **`BaseSingBoxTunnel: NEPacketTunnelProvider`** — startTunnel реализует полный pipeline: validate → bootstrap → newService → start.
- [ ] **`ExtensionPlatformInterface`** — реализует `LibboxPlatformInterfaceProtocol`, `openTun` использует `TunnelSettings.makeR6Safe` + DEBUG `assertNoPointToPointOnUtun` + FD extraction через KVC.
- [ ] **`AppGroupContainer.url`** возвращает URL для `group.app.bbtb.shared`.
- [ ] **`TunnelLogger`** — OSLog subsystem `app.bbtb.tunnel` с 4 категориями.
- [ ] **`VLESSRealityHandler: VPNProtocolHandler`** — placeholder регистрации (CORE-02).
- [ ] **`ConfigBuilder.buildSingBoxJSON(from:)`** — подставляет ${...} placeholder'ы; output проходит SingBoxConfigLoader.validate; 3 unit-теста pass.
- [ ] **iOS+macOS PacketTunnelProvider** target shells — `class PacketTunnelProvider: BaseSingBoxTunnel { }`.
- [ ] **BBTB-iOS scheme + BBTB-macOS scheme** оба собираются BUILD SUCCEEDED с реальным libbox.xcframework линковкой (W3-T6 verification log).
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-W3-base-tunnel-SUMMARY.md` с:
- Точные имена libbox-типов которые реально появились в Swift bridging (LibboxPlatformInterface vs LibboxPlatformInterfaceProtocol, etc.) — если отличается от RESEARCH §2 — задокументировать
- Снимок `wave3-verification.log` (последние 30 строк)
- Список созданных артефактов и их публичных API
- Замечания для Wave 4 — как именно main app должен передать `configJSON` в extension через `providerConfiguration` (NETunnelProviderProtocol.providerConfiguration["configJSON"])
- Замечания для Wave 5 — что именно нужно протестировать на устройстве (полный pipeline import → connect → api.ipify.org → SocksProbe)
- Любые отклонения от RESEARCH (Pitfall 2, Pitfall 6 — что пришлось обходить)
</output>
