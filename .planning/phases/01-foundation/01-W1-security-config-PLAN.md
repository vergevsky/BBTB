---
phase: 01-foundation
plan: W1-security-config
type: execute
wave: 2
depends_on:
  - W0-bootstrap
files_modified:
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
  - BBTB/Packages/PacketTunnelKit/Package.swift
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/valid-vless-reality.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-socks-inbound.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-mixed-inbound.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-tun-inbound.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-http-inbound.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-clash-api.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-v2ray-api.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-cache-file.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/malformed.json
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/no-vless-outbound.json
  - BBTB/Tools/SocksProbe/SocksProbe.xcodeproj/project.pbxproj
  - BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbeApp.swift
  - BBTB/Tools/SocksProbe/SocksProbe-iOS/Info.plist
  - BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements
  - BBTB/Tools/SocksProbe/SocksProbe-iOS/Assets.xcassets/Contents.json
  - BBTB/Tools/SocksProbe/SocksProbe-iOS/Assets.xcassets/AppIcon.appiconset/Contents.json
  - BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbeApp.swift
  - BBTB/Tools/SocksProbe/SocksProbe-macOS/Info.plist
  - BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements
  - BBTB/Tools/SocksProbe/SocksProbe-macOS/Assets.xcassets/Contents.json
  - BBTB/Tools/SocksProbe/SocksProbe-macOS/Assets.xcassets/AppIcon.appiconset/Contents.json
  - BBTB/Tools/SocksProbe/Shared/RKNPorts.swift
  - BBTB/Tools/SocksProbe/Shared/PortProber.swift
  - BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift
  - BBTB/Tools/SocksProbe/Shared/SocksProbeView.swift
  - BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift
autonomous: true
requirements:
  - SEC-01
  - SEC-02
  - SEC-03
  - SEC-06
  - PROTO-01

must_haves:
  truths:
    - "sing-box JSON-шаблон для VLESS+Vision+Reality существует и не содержит inbounds[] и experimental.{clash_api,v2ray_api,cache_file}"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.forbiddenInboundType при inbounds[type=socks]"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.forbiddenInboundType при inbounds[type=mixed]"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.forbiddenInboundType при inbounds[type=tun]"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.forbiddenInboundType при inbounds[type=http]"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.experimentalApiEnabled('clash_api') при непустом experimental.clash_api"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.experimentalApiEnabled('v2ray_api') при непустом experimental.v2ray_api"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.experimentalApiEnabled('cache_file') при experimental.cache_file.enabled=true"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.malformedJSON при невалидном JSON"
    - "SingBoxConfigLoader.validate(json:) бросает SingBoxConfigError.noVLESSOutbound при отсутствии vless outbound"
    - "SocksProbe iOS app собирается с bundle ID app.bbtb.tools.socksprobe.ios"
    - "SocksProbe macOS app собирается с bundle ID app.bbtb.tools.socksprobe.macos"
    - "SocksProbe сканирует список портов из методички РКН (1080, 9000, 5555, 16000–16100, 3128, 3127, 8000, 8080, 8081, 8888, 9050, 9051, 9150) через NWConnection с таймаутом 500ms"
    - "SocksProbe показывает getifaddrs() snapshot для utun* интерфейсов и явно вырабатывает POINTOPOINT YES/NO"
  artifacts:
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift"
      provides: "R1 + SEC-06 runtime validator"
      contains: "public enum SingBoxConfigLoader"
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json"
      provides: "Шаблон конфига sing-box для VLESS+Vision+Reality без inbounds и experimental APIs (R1)"
      contains: "vless-out"
    - path: "BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift"
      provides: "Юнит-тесты R1 + SEC-06"
      contains: "test_rejectsSocksInbound"
    - path: "BBTB/Tools/SocksProbe/SocksProbe.xcodeproj"
      provides: "Standalone Xcode project для R1-верификации (SEC-03)"
    - path: "BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements"
      provides: "Минимальные entitlements БЕЗ App Group и БЕЗ keychain-access-groups"
    - path: "BBTB/Tools/SocksProbe/Shared/RKNPorts.swift"
      provides: "Список портов из методички РКН"
      contains: "16000...16100"
    - path: "BBTB/Tools/SocksProbe/Shared/PortProber.swift"
      provides: "NWConnection-based async TCP probe с 500ms timeout"
      contains: "NWConnection"
    - path: "BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift"
      provides: "getifaddrs() + IFF_POINTOPOINT detection (R6 external check)"
      contains: "getifaddrs"
  key_links:
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift"
      to: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json"
      via: "load + validate template at runtime (Wave 3 BaseSingBoxTunnel.startTunnel use)"
      pattern: "SingBoxConfigTemplate.vless-reality"
    - from: "BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift"
      to: "BBTB/Tools/SocksProbe/Shared/PortProber.swift"
      via: "viewModel запускает NWConnection-сканирование для всех портов из RKNPorts.phase1"
      pattern: "PortProber"
    - from: "BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift"
      to: "BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift"
      via: "viewModel запрашивает snapshot utun-интерфейсов для R6-screenshot"
      pattern: "InterfaceInspector"
---

<objective>
**Wave 1 — Security foundation (R1).** Реализовать sing-box JSON-шаблон VLESS+Vision+Reality без inbounds-секций, написать `SingBoxConfigLoader.validate(json:)` который runtime-отказывает на запрещённых секциях, и создать standalone **SocksProbe** Xcode-проект (отдельный bundle, без App Group, без keychain-access) для внешней верификации R1+R6 в Wave 5.

Это **первая безопасная волна** в Phase 1: до того как BaseSingBoxTunnel получит способность запускать libbox (Wave 3), мы уже имеем (а) декларативную защиту через шаблон и (б) runtime-проверку через validate(). Без этой волны Wave 3 запустит libbox с шаблоном, который не верифицирован — что нарушает security-first принцип CONTEXT.md §4.

Purpose: закрыть R1 (no SOCKS5 / no gRPC API) на двух уровнях — конфиг + код — и подготовить инструмент (SocksProbe) для third-party verification в Wave 5. По итогам: при попытке Wave 3 ввести запрещённую секцию в шаблон → unit-тест падает в CI; при попытке Wave 4 принять malicious vless:// → validate бросает SingBoxConfigError; в Wave 5 запуск SocksProbe на устройстве с активным туннелем подтверждает что ни один порт из списка РКН не отвечает.

Output:
- `SingBoxConfigLoader.validate()` с 7 правилами reject (3 inbound-типа, 3 experimental API, 1 missing-vless-outbound) + JSON-malformed branch.
- JSON-шаблон конфига для VLESS+Vision+Reality (R1-compliant; будет дополнен парсером Wave 4 при импорте vless://).
- 10 JSON-фикстур для тестов (1 valid + 9 invalid).
- Полный SocksProbe проект (iOS + macOS), готовый к manual run в Wave 5.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/01-foundation/01-CONTEXT.md
@.planning/phases/01-foundation/01-RESEARCH.md
@.planning/phases/01-foundation/01-W0-bootstrap-SUMMARY.md
@CLAUDE.md
@prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md
@Wiki/security-gaps.md
@Wiki/xray-localhost-vulnerability.md
@Wiki/apple-detection-surface.md
@Wiki/vless-reality.md

<interfaces>
<!-- Уже созданные интерфейсы из Wave 0, на которые Wave 1 опирается. -->

From BBTB/Packages/VPNCore/Sources/VPNCore/VPNProtocolHandler.swift:
```swift
public protocol VPNProtocolHandler: Sendable { ... }
public struct ProtocolConfig: Sendable {
    public let identifier: String
    public let json: String  // sing-box subset for this protocol
}
```

From RESEARCH §3 — финальный sing-box config template (R1-compliant, без inbounds и experimental):
```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": { "servers": [...], "rules": [...], "strategy": "ipv4_only" },
  "outbounds": [
    { "type": "vless", "tag": "vless-out", "server": "${SERVER_HOST}", ... },
    { "type": "direct", "tag": "direct" }
  ],
  "route": { "rules": [...], "final": "vless-out", "auto_detect_interface": true },
  "experimental": {}
}
```

From RESEARCH §3 — точная сигнатура валидатора:
```swift
public enum SingBoxConfigError: Error, LocalizedError { ... }
public enum SingBoxConfigLoader {
    public static func validate(json: String) throws
}
```

From RESEARCH §8 — список портов:
```swift
enum RKNPorts {
    static let socks: [UInt16] = [1080, 9000, 5555]
    static let socksRange: ClosedRange<UInt16> = 16000...16100
    static let httpProxy: [UInt16] = [3128, 3127, 8000, 8080, 8081, 8888]
    static let tor: [UInt16] = [9050, 9051, 9150]
}
```
</interfaces>
</context>

<tasks>

<task id="W1-T1" type="auto" tdd="true" autonomous="true">
  <name>Task W1-T1: SingBoxConfigTemplate.vless-reality.json (R1-compliant шаблон) + SingBoxConfigLoader.validate с unit-тестами</name>
  <files>
    BBTB/Packages/PacketTunnelKit/Package.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/valid-vless-reality.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-socks-inbound.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-mixed-inbound.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-tun-inbound.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-http-inbound.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-clash-api.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-v2ray-api.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/invalid-cache-file.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/malformed.json,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/no-vless-outbound.json
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §3 «sing-box JSON schema для VLESS+Vision+Reality» (полный шаблон + список запрещённых секций + сигнатура валидатора)
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 1 описание (что именно `validate` отказывает)
    - Wiki/security-gaps.md секция R1 (контекст zachem)
    - Wiki/xray-localhost-vulnerability.md (Android precedent — почему именно эти проверки)
    - prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md строки 241-246 («Sing-box engine — обязательные проверки до v0.1»)
  </read_first>
  <behavior>
    - **Test 1 (valid)**: загрузка валидного VLESS+Reality конфига (Fixtures/valid-vless-reality.json) — `validate` НЕ бросает.
    - **Test 2 (forbiddenInboundType socks)**: при `inbounds: [{ "type": "socks", "listen": "127.0.0.1", "listen_port": 1080 }]` — бросает `.forbiddenInboundType("socks")`.
    - **Test 3 (forbiddenInboundType mixed)**: то же для type=mixed.
    - **Test 4 (forbiddenInboundType tun)**: то же для type=tun.
    - **Test 5 (forbiddenInboundType http)**: то же для type=http.
    - **Test 6 (experimentalApiEnabled clash_api)**: при непустом `experimental.clash_api = { "external_controller": "127.0.0.1:9090" }` — бросает `.experimentalApiEnabled("clash_api")`.
    - **Test 7 (experimentalApiEnabled v2ray_api)**: то же для `experimental.v2ray_api`.
    - **Test 8 (experimentalApiEnabled cache_file)**: при `experimental.cache_file.enabled = true` — бросает `.experimentalApiEnabled("cache_file")`.
    - **Test 9 (malformedJSON)**: input "{ not valid }" — бросает `.malformedJSON`.
    - **Test 10 (noVLESSOutbound)**: outbounds-список без vless-типа — бросает `.noVLESSOutbound`.
    - **Test 11 (missingOutbounds)**: пустой outbounds — бросает `.missingOutbounds`.
    - **Test 12 (template loads from bundle)**: загрузка `SingBoxConfigTemplate.vless-reality.json` через `Bundle.module` + validate проходит без ошибок.
  </behavior>
  <action>
1. **Обновить `BBTB/Packages/PacketTunnelKit/Package.swift`** чтобы добавить resource-processing для шаблона:
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

2. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`** — точно по RESEARCH §3, с `${...}` placeholder'ами (Wave 4 ConfigParser подставит реальные значения через JSON-replace или Codable mutation):
```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "cf-doh",
        "address": "https://1.1.1.1/dns-query",
        "detour": "vless-out"
      },
      {
        "tag": "bootstrap",
        "address": "1.1.1.1",
        "detour": "direct"
      }
    ],
    "rules": [
      { "domain_suffix": [".microsoft.com"], "server": "bootstrap" }
    ],
    "strategy": "ipv4_only"
  },
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "${SERVER_HOST}",
      "server_port": 443,
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "network": "tcp",
      "packet_encoding": "xudp",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "utls": {
          "enabled": true,
          "fingerprint": "${UTLS_FINGERPRINT}"
        },
        "reality": {
          "enabled": true,
          "public_key": "${REALITY_PUBLIC_KEY}",
          "short_id": "${REALITY_SHORT_ID}"
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "dns-out" }
    ],
    "final": "vless-out",
    "auto_detect_interface": true
  },
  "experimental": {}
}
```

3. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`** — по сигнатуре RESEARCH §3:
```swift
import Foundation

/// Errors thrown by SingBoxConfigLoader.validate.
/// R1 (SEC-01, SEC-02): отказ при попытке передать конфиг с локальными inbound'ами или включёнными gRPC-API.
/// SEC-06: отказ при malformed JSON / отсутствии VLESS outbound.
public enum SingBoxConfigError: Error, LocalizedError, Equatable {
    case malformedJSON
    case forbiddenInboundType(String)
    case forbiddenInboundExists
    case experimentalApiEnabled(String)
    case missingOutbounds
    case noVLESSOutbound

    public var errorDescription: String? {
        switch self {
        case .malformedJSON:
            return "sing-box config is not valid JSON"
        case .forbiddenInboundType(let t):
            return "sing-box config contains forbidden inbound type: \(t) (R1: SEC-01)"
        case .forbiddenInboundExists:
            return "sing-box config must not contain inbounds[] (R1: SEC-01)"
        case .experimentalApiEnabled(let api):
            return "sing-box experimental API enabled: \(api) (R1: SEC-02)"
        case .missingOutbounds:
            return "sing-box config has no outbounds (SEC-06)"
        case .noVLESSOutbound:
            return "sing-box config has no vless outbound (SEC-06 / PROTO-01)"
        }
    }
}

/// R1 + SEC-06 validation. Phase 1 — single source of truth для проверки безопасности sing-box конфига.
///
/// Используется:
/// - Wave 3 `BaseSingBoxTunnel.startTunnel` ПЕРЕД `LibboxNewService(configJSON, ...)`
/// - Wave 4 при `ConfigParser.buildSingBoxJSON(from: parsed)` после подстановки значений в template
///
/// Контракт:
/// - Бросает при первом нарушении (fail-fast)
/// - НЕ модифицирует конфиг
/// - Никогда не "санирует" — это runtime guard, не fixer
public enum SingBoxConfigLoader {
    public static func validate(json: String) throws {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SingBoxConfigError.malformedJSON
        }

        // R1 (SEC-01): запретить inbounds[]
        if let inbounds = root["inbounds"] as? [[String: Any]], !inbounds.isEmpty {
            let firstType = inbounds.first?["type"] as? String ?? "<unknown>"
            throw SingBoxConfigError.forbiddenInboundType(firstType)
        }

        // R1 (SEC-02): запретить experimental APIs
        if let exp = root["experimental"] as? [String: Any] {
            if let clash = exp["clash_api"] as? [String: Any], !clash.isEmpty {
                throw SingBoxConfigError.experimentalApiEnabled("clash_api")
            }
            if let v2ray = exp["v2ray_api"] as? [String: Any], !v2ray.isEmpty {
                throw SingBoxConfigError.experimentalApiEnabled("v2ray_api")
            }
            if let cache = exp["cache_file"] as? [String: Any],
               cache["enabled"] as? Bool == true {
                throw SingBoxConfigError.experimentalApiEnabled("cache_file")
            }
        }

        // SEC-06: должен быть хотя бы один outbound
        guard let outbounds = root["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
            throw SingBoxConfigError.missingOutbounds
        }
        // PROTO-01: должен быть VLESS outbound
        let hasVLESS = outbounds.contains { ($0["type"] as? String) == "vless" }
        guard hasVLESS else { throw SingBoxConfigError.noVLESSOutbound }
    }

    /// Загрузить шаблон VLESS+Vision+Reality из bundle.
    /// Используется Wave 4 ConfigParser'ом перед подстановкой ${...} placeholder'ов.
    public static func loadVLESSRealityTemplate() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "SingBoxConfigTemplate.vless-reality",
            withExtension: "json"
        ) else {
            throw SingBoxConfigError.malformedJSON
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

4. **`BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/valid-vless-reality.json`** — копия SingBoxConfigTemplate.vless-reality.json но с placeholder'ами заменёнными на реальные тестовые значения (любые непустые строки):
```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "cf-doh", "address": "https://1.1.1.1/dns-query", "detour": "vless-out" },
      { "tag": "bootstrap", "address": "1.1.1.1", "detour": "direct" }
    ],
    "strategy": "ipv4_only"
  },
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "example.com",
      "server_port": 443,
      "uuid": "550e8400-e29b-41d4-a716-446655440000",
      "flow": "xtls-rprx-vision",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "abc123", "short_id": "01234567" }
      }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": { "final": "vless-out", "auto_detect_interface": true },
  "experimental": {}
}
```

5. **`Fixtures/invalid-socks-inbound.json`:**
```json
{
  "log": {},
  "inbounds": [{ "type": "socks", "listen": "127.0.0.1", "listen_port": 1080 }],
  "outbounds": [{ "type": "vless", "tag": "x", "server": "x", "server_port": 443, "uuid": "x" }],
  "route": { "final": "x" },
  "experimental": {}
}
```

6. **`Fixtures/invalid-mixed-inbound.json`** — то же, `"type": "mixed"`.
7. **`Fixtures/invalid-tun-inbound.json`** — `"type": "tun"`.
8. **`Fixtures/invalid-http-inbound.json`** — `"type": "http"`.

9. **`Fixtures/invalid-clash-api.json`:**
```json
{
  "outbounds": [{ "type": "vless", "tag": "x", "server": "x", "server_port": 443, "uuid": "x" }],
  "route": { "final": "x" },
  "experimental": { "clash_api": { "external_controller": "127.0.0.1:9090" } }
}
```

10. **`Fixtures/invalid-v2ray-api.json`** — то же, `experimental.v2ray_api: { "listen": "127.0.0.1:8080" }`.
11. **`Fixtures/invalid-cache-file.json`** — `experimental.cache_file: { "enabled": true, "path": "cache.db" }`.

12. **`Fixtures/malformed.json`:**
```
{ "log": {, this is not valid JSON
```

13. **`Fixtures/no-vless-outbound.json`:**
```json
{
  "outbounds": [{ "type": "direct", "tag": "direct" }],
  "route": { "final": "direct" },
  "experimental": {}
}
```

14. **`BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift`:**
```swift
import XCTest
@testable import PacketTunnelKit

final class SingBoxConfigLoaderTests: XCTestCase {

    // MARK: Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).json")
            throw SingBoxConfigError.malformedJSON
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Valid

    func test_acceptsValidVLESSRealityConfig() throws {
        let json = try loadFixture("valid-vless-reality")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_templateLoadsAndValidates_afterPlaceholderReplacement() throws {
        // R1 self-check: bundled template (с ${...} placeholder'ами) после простой подстановки
        // на непустые строки должен пройти validate. Это гарантирует что Wave 4 при импорте vless://
        // получит на выходе R1-compliant конфиг.
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: filled))
    }

    // MARK: R1 — forbidden inbounds (SEC-01)

    func test_rejectsSocksInbound() throws {
        let json = try loadFixture("invalid-socks-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("socks"))
        }
    }

    func test_rejectsMixedInbound() throws {
        let json = try loadFixture("invalid-mixed-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("mixed"))
        }
    }

    func test_rejectsTunInbound() throws {
        let json = try loadFixture("invalid-tun-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("tun"))
        }
    }

    func test_rejectsHttpInbound() throws {
        let json = try loadFixture("invalid-http-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("http"))
        }
    }

    // MARK: R1 — experimental APIs (SEC-02)

    func test_rejectsClashAPI() throws {
        let json = try loadFixture("invalid-clash-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("clash_api"))
        }
    }

    func test_rejectsV2RayAPI() throws {
        let json = try loadFixture("invalid-v2ray-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("v2ray_api"))
        }
    }

    func test_rejectsCacheFile() throws {
        let json = try loadFixture("invalid-cache-file")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("cache_file"))
        }
    }

    // MARK: SEC-06 — structure validation

    func test_malformedJSON() throws {
        let json = try loadFixture("malformed")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .malformedJSON)
        }
    }

    func test_noVLESSOutbound() throws {
        let json = try loadFixture("no-vless-outbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .noVLESSOutbound)
        }
    }

    func test_missingOutbounds() throws {
        let json = "{\"outbounds\": [], \"route\": { \"final\": \"x\" }, \"experimental\": {}}"
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .missingOutbounds)
        }
    }
}
```
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`
    - `python3 -m json.tool BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json > /dev/null` → exit 0 (valid JSON)
    - `! grep -q '"inbounds"' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` (R1: НЕТ inbounds-секции)
    - `grep -q '"vless-out"' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`
    - `grep -q '"flow": "xtls-rprx-vision"' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`
    - `grep -q '"reality"' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`
    - `grep -q '"experimental": {}' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` (experimental — пустой объект)
    - `grep -q 'public enum SingBoxConfigLoader' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`
    - `grep -q 'public static func validate(json: String) throws' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`
    - `grep -q 'case forbiddenInboundType(String)' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`
    - `grep -q 'case experimentalApiEnabled(String)' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`
    - `grep -q 'case malformedJSON' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`
    - `grep -q 'case noVLESSOutbound' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`
    - Все 10 fixture-файлов существуют в `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/Fixtures/`
    - Команда `xcodebuild test -workspace BBTB.xcworkspace -scheme PacketTunnelKit -destination 'platform=macOS,arch=arm64'` (после того как scheme добавится в W0-T5 aggregate или сам PacketTunnelKit scheme автогенерится) завершается с TEST SUCCEEDED для всех 12 тестов выше.
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && xcodebuild test -workspace BBTB.xcworkspace -scheme PacketTunnelKit -destination 'platform=macOS,arch=arm64' -quiet 2>&amp;1 | grep -E "Test Suite 'SingBoxConfigLoaderTests'.*passed|Executed 12 tests"</automated>
  </verify>
  <done>Все 12 unit-тестов SingBoxConfigLoaderTests проходят; шаблон конфига R1-compliant; validate(json:) реализует все 7 правил отказа из RESEARCH §3.</done>
</task>

<task id="W1-T2" type="auto" autonomous="true">
  <name>Task W1-T2: SocksProbe Xcode project — Shared logic (RKNPorts, PortProber, InterfaceInspector, ViewModel, View)</name>
  <files>
    BBTB/Tools/SocksProbe/Shared/RKNPorts.swift,
    BBTB/Tools/SocksProbe/Shared/PortProber.swift,
    BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift,
    BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift,
    BBTB/Tools/SocksProbe/Shared/SocksProbeView.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §8 «SocksProbe» (UI Spec, Ports list, TCP-connect impl, R6 check details)
    - .planning/phases/01-foundation/01-RESEARCH.md §7 «R6 P2P=false» (IFF_POINTOPOINT detection)
    - Wiki/apple-detection-surface.md (откуда список портов 1080, 9000, 5555, 16000–16100)
  </read_first>
  <action>
1. **`BBTB/Tools/SocksProbe/Shared/RKNPorts.swift`** — список портов точно по RESEARCH §8:
```swift
import Foundation

/// Список портов из методички РосКомНадзора (РКН — Roskomnadzor) для R1-проверки.
/// Источник: Wiki/apple-detection-surface.md + Wiki/xray-localhost-vulnerability.md.
public enum RKNPorts {
    public static let socks: [UInt16] = [1080, 9000, 5555]
    public static let socksRange: ClosedRange<UInt16> = 16000...16100
    public static let httpProxy: [UInt16] = [3128, 3127, 8000, 8080, 8081, 8888]
    // ВНИМАНИЕ: 80 и 443 НЕ сканируем — конфликт с нормальным HTTP/HTTPS на устройстве.
    public static let tor: [UInt16] = [9050, 9051, 9150]

    /// Полный список для Phase 1 R1 проверки (SEC-03).
    public static var phase1: [UInt16] {
        socks + Array(socksRange) + httpProxy + tor
    }
}
```

2. **`BBTB/Tools/SocksProbe/Shared/PortProber.swift`** — `NWConnection`-based async TCP probe (см. RESEARCH §8):
```swift
import Foundation
import Network

public enum PortStatus: Equatable {
    case open
    case closed
    case timeout
    case error(String)
}

public struct PortResult: Identifiable {
    public let id = UUID()
    public let port: UInt16
    public let status: PortStatus
    public let durationMs: Int
}

public enum PortProber {
    /// Async TCP-connect probe c configurable timeout.
    /// Wave 1 default: 500ms — этого достаточно для loopback (≤1ms latency на nominal device).
    public static func probe(
        port: UInt16,
        host: String = "127.0.0.1",
        timeout: TimeInterval = 0.5
    ) async -> PortResult {
        let start = Date()
        let conn = NWConnection(
            host: .init(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let status: PortStatus = await withCheckedContinuation { (cont: CheckedContinuation<PortStatus, Never>) in
            let timer = DispatchSource.makeTimerSource(queue: .global())
            var resumed = false
            let resume: @Sendable (PortStatus) -> Void = { newStatus in
                guard !resumed else { return }
                resumed = true
                timer.cancel()
                conn.cancel()
                cont.resume(returning: newStatus)
            }
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { resume(.timeout) }
            timer.activate()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resume(.open)
                case .failed(let err):
                    resume(.error(err.localizedDescription))
                case .cancelled:
                    resume(.closed)
                case .waiting:
                    // ConnectionWaiting обычно = port closed; завершаем сразу.
                    resume(.closed)
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return PortResult(port: port, status: status, durationMs: durationMs)
    }

    /// Сканировать список портов параллельно (Task group), вернуть массив результатов
    /// в том же порядке что и input.
    public static func probeAll(
        _ ports: [UInt16],
        host: String = "127.0.0.1",
        timeout: TimeInterval = 0.5
    ) async -> [PortResult] {
        await withTaskGroup(of: (Int, PortResult).self) { group in
            for (idx, port) in ports.enumerated() {
                group.addTask {
                    let r = await probe(port: port, host: host, timeout: timeout)
                    return (idx, r)
                }
            }
            var results: [(Int, PortResult)] = []
            for await pair in group { results.append(pair) }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}
```

3. **`BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift`** — getifaddrs() + IFF_POINTOPOINT (R6 внешний check):
```swift
import Foundation
import Darwin

public struct InterfaceSnapshot: Identifiable {
    public let id = UUID()
    public let name: String
    public let addresses: [String]
    public let flagsHex: String
    public let hasPointToPoint: Bool
    public let hasBroadcast: Bool
    public let hasMulticast: Bool
    public let isUp: Bool
    public let isRunning: Bool
}

public enum InterfaceInspector {
    /// Вернуть snapshot всех utun* интерфейсов с разбором IFF_* флагов.
    /// R6 (SEC-04) external check: `hasPointToPoint` должно быть `false` для всех `utun*`
    /// когда наш BBTB tunnel активен. Это второй уровень верификации R6
    /// (первый — DEBUG-assertion внутри BaseSingBoxTunnel.assertR6_NoP2P, см. Wave 3).
    public static func snapshotUtunInterfaces() -> [InterfaceSnapshot] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        // Сгруппировать по name (IPv4 + IPv6 могут быть в разных записях для одного интерфейса).
        var byName: [String: (addrs: [String], flags: Int32)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("utun") {
                let flags = Int32(p.pointee.ifa_flags)
                var addresses = byName[name]?.addrs ?? []
                if let sa = p.pointee.ifa_addr {
                    var addr = sockaddr_storage()
                    memcpy(&addr, sa, MemoryLayout<sockaddr_storage>.size)
                    var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen: socklen_t = {
                        switch Int32(sa.pointee.sa_family) {
                        case AF_INET: return socklen_t(MemoryLayout<sockaddr_in>.size)
                        case AF_INET6: return socklen_t(MemoryLayout<sockaddr_in6>.size)
                        default: return socklen_t(sa.pointee.sa_len)
                        }
                    }()
                    let code = withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
                            getnameinfo(sap, saLen, &hostBuf, socklen_t(hostBuf.count),
                                         nil, 0, NI_NUMERICHOST)
                        }
                    }
                    if code == 0 {
                        addresses.append(String(cString: hostBuf))
                    }
                }
                byName[name] = (addresses, flags)
            }
            ptr = p.pointee.ifa_next
        }

        return byName.map { (name, tuple) in
            let flags = tuple.flags
            return InterfaceSnapshot(
                name: name,
                addresses: tuple.addrs,
                flagsHex: String(format: "0x%X", UInt32(bitPattern: flags)),
                hasPointToPoint: (flags & IFF_POINTOPOINT) != 0,
                hasBroadcast: (flags & IFF_BROADCAST) != 0,
                hasMulticast: (flags & IFF_MULTICAST) != 0,
                isUp: (flags & IFF_UP) != 0,
                isRunning: (flags & IFF_RUNNING) != 0
            )
        }.sorted { $0.name < $1.name }
    }
}
```

4. **`BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift`:**
```swift
import Foundation
import SwiftUI

@MainActor
public final class SocksProbeViewModel: ObservableObject {
    public enum ScanState: Equatable {
        case idle
        case scanning(completed: Int, total: Int)
        case done
    }

    @Published public private(set) var state: ScanState = .idle
    @Published public private(set) var portResults: [PortResult] = []
    @Published public private(set) var interfaces: [InterfaceSnapshot] = []
    @Published public private(set) var summary: String = ""

    public init() {}

    public func startScan() async {
        guard case .idle = state else { return }
        let ports = RKNPorts.phase1
        state = .scanning(completed: 0, total: ports.count)
        portResults = []
        let results = await PortProber.probeAll(ports)
        portResults = results
        interfaces = InterfaceInspector.snapshotUtunInterfaces()
        let open = results.filter { $0.status == .open }
        let pointToPointUtuns = interfaces.filter { $0.hasPointToPoint }
        summary = """
        Ports tested: \(results.count)
        Open: \(open.count)
        utun interfaces: \(interfaces.count)
        utun with POINTOPOINT: \(pointToPointUtuns.count)
        R1 verdict: \(open.isEmpty ? "PASS — no ports respond" : "FAIL — open ports detected")
        R6 verdict: \(pointToPointUtuns.isEmpty ? "PASS — no IFF_POINTOPOINT on utun*" : "FAIL — IFF_POINTOPOINT detected")
        """
        state = .done
    }

    public func reset() {
        state = .idle
        portResults = []
        interfaces = []
        summary = ""
    }
}
```

5. **`BBTB/Tools/SocksProbe/Shared/SocksProbeView.swift`** (cross-platform SwiftUI, см. RESEARCH §8 UI Spec):
```swift
import SwiftUI

public struct SocksProbeView: View {
    @StateObject private var viewModel = SocksProbeViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BBTB SocksProbe")
                .font(.system(.title2, design: .rounded).bold())
            Text("Scan 127.0.0.1 for SOCKS / HTTP-proxy / Tor ports (R1 / SEC-03)")
                .font(.caption)
                .foregroundStyle(.secondary)

            statusRow

            HStack {
                Button(scanButtonTitle, action: startScan)
                    .disabled(scanInProgress)
                Button("Reset", action: viewModel.reset)
                    .disabled(viewModel.state == .idle)
            }

            if !viewModel.summary.isEmpty {
                GroupBox(label: Text("Summary")) {
                    Text(viewModel.summary)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox(label: Text("Ports tested")) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.portResults) { r in
                            HStack {
                                Text(":\(r.port)")
                                    .frame(width: 70, alignment: .leading)
                                Text(statusLabel(r.status))
                                    .foregroundStyle(statusColor(r.status))
                                Spacer()
                                Text("\(r.durationMs) ms")
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospaced())
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            GroupBox(label: Text("utun interfaces (R6 check)")) {
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.interfaces.isEmpty {
                        Text("(no utun* interfaces — VPN not active?)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(viewModel.interfaces) { iface in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("\(iface.name)").font(.caption.monospaced().bold())
                                    Text(iface.addresses.joined(separator: ", "))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(iface.hasPointToPoint ? "POINTOPOINT: YES (R6 FAIL)" : "POINTOPOINT: NO ✓")
                                    .foregroundStyle(iface.hasPointToPoint ? .red : .green)
                                    .font(.caption.monospaced().bold())
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 600)
    }

    // MARK: - Subviews

    private var statusRow: some View {
        HStack {
            Text("Status:").font(.caption)
            switch viewModel.state {
            case .idle:
                Text("Idle").foregroundStyle(.secondary)
            case .scanning(let completed, let total):
                Text("Scanning \(completed)/\(total)")
                    .foregroundStyle(.orange)
                ProgressView()
                    .controlSize(.small)
            case .done:
                Text("Done").foregroundStyle(.green)
            }
        }
    }

    private var scanButtonTitle: String {
        switch viewModel.state {
        case .idle: return "Start Scan"
        case .scanning: return "Scanning…"
        case .done: return "Re-scan"
        }
    }

    private var scanInProgress: Bool {
        if case .scanning = viewModel.state { return true }
        return false
    }

    private func startScan() {
        Task { await viewModel.startScan() }
    }

    private func statusLabel(_ status: PortStatus) -> String {
        switch status {
        case .open: return "OPEN ⚠"
        case .closed: return "closed"
        case .timeout: return "timeout"
        case .error(let msg): return "error: \(msg)"
        }
    }

    private func statusColor(_ status: PortStatus) -> Color {
        switch status {
        case .open: return .red
        case .closed: return .green
        case .timeout: return .secondary
        case .error: return .orange
        }
    }
}
```
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Tools/SocksProbe/Shared/RKNPorts.swift && grep -q "16000...16100" BBTB/Tools/SocksProbe/Shared/RKNPorts.swift`
    - `grep -q "public static let socks: \[UInt16\] = \[1080, 9000, 5555\]" BBTB/Tools/SocksProbe/Shared/RKNPorts.swift`
    - `grep -q "import Network" BBTB/Tools/SocksProbe/Shared/PortProber.swift`
    - `grep -q "NWConnection" BBTB/Tools/SocksProbe/Shared/PortProber.swift`
    - `grep -q "timeout: TimeInterval = 0.5" BBTB/Tools/SocksProbe/Shared/PortProber.swift`
    - `grep -q "import Darwin" BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift`
    - `grep -q "getifaddrs" BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift`
    - `grep -q "IFF_POINTOPOINT" BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift`
    - `grep -q "hasPrefix(\"utun\")" BBTB/Tools/SocksProbe/Shared/InterfaceInspector.swift`
    - `grep -q "@MainActor" BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift`
    - `grep -q "RKNPorts.phase1" BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift`
    - `grep -q "InterfaceInspector.snapshotUtunInterfaces" BBTB/Tools/SocksProbe/Shared/SocksProbeViewModel.swift`
    - `grep -q "POINTOPOINT: YES" BBTB/Tools/SocksProbe/Shared/SocksProbeView.swift`
  </acceptance_criteria>
</task>

<task id="W1-T3" type="auto" autonomous="true">
  <name>Task W1-T3: SocksProbe app target'ы (iOS + macOS) — entitlements / Info.plist / @main wrappers</name>
  <files>
    BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbeApp.swift,
    BBTB/Tools/SocksProbe/SocksProbe-iOS/Info.plist,
    BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements,
    BBTB/Tools/SocksProbe/SocksProbe-iOS/Assets.xcassets/Contents.json,
    BBTB/Tools/SocksProbe/SocksProbe-iOS/Assets.xcassets/AppIcon.appiconset/Contents.json,
    BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbeApp.swift,
    BBTB/Tools/SocksProbe/SocksProbe-macOS/Info.plist,
    BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements,
    BBTB/Tools/SocksProbe/SocksProbe-macOS/Assets.xcassets/Contents.json,
    BBTB/Tools/SocksProbe/SocksProbe-macOS/Assets.xcassets/AppIcon.appiconset/Contents.json
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 1 (bundle ID app.bbtb.tools.socksprobe, без App Group, без Keychain)
    - .planning/phases/01-foundation/01-RESEARCH.md §8 (architecture, Apple Sandbox для loopback на iOS/macOS)
    - prompts/v2 строка 245 (тест-кейс на iOS и macOS)
  </read_first>
  <action>
1. **`BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbeApp.swift`:**
```swift
import SwiftUI

@main
struct SocksProbeApp: App {
    var body: some Scene {
        WindowGroup {
            SocksProbeView()
        }
    }
}
```

(`SocksProbeView` импортируется из `Shared/SocksProbeView.swift` — Xcode-target включит все файлы из `BBTB/Tools/SocksProbe/Shared/` через folder reference.)

2. **`BBTB/Tools/SocksProbe/SocksProbe-iOS/Info.plist`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>BBTB SocksProbe</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>app.bbtb.tools.socksprobe.ios</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SocksProbe</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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
</dict>
</plist>
```

3. **`BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements`** — **МИНИМАЛЬНЫЕ**. Никакого App Group, никакого keychain-access-groups. Цель — представлять «любое стороннее приложение»:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Intentionally empty. SocksProbe must NOT share App Group or Keychain with BBTB. -->
</dict>
</plist>
```

4. **`BBTB/Tools/SocksProbe/SocksProbe-iOS/Assets.xcassets/Contents.json`** и `AppIcon.appiconset/Contents.json` — пустые placeholder'ы (как в W0-T4):
```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

5. **`BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbeApp.swift`:**
```swift
import SwiftUI

@main
struct SocksProbeApp: App {
    var body: some Scene {
        Window("BBTB SocksProbe", id: "main") {
            SocksProbeView()
                .frame(minWidth: 480, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
```

6. **`BBTB/Tools/SocksProbe/SocksProbe-macOS/Info.plist`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>BBTB SocksProbe</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>app.bbtb.tools.socksprobe.macos</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SocksProbe</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
</dict>
</plist>
```

7. **`BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements`** — sandbox + ТОЛЬКО network.client (нужно для NWConnection к 127.0.0.1; на macOS sandbox блокирует loopback без явного entitlement). НИКАКОГО App Group, НИКАКОГО keychain-access-groups:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <!-- NO App Group / NO Keychain Sharing — SocksProbe represents an unrelated third-party app. -->
</dict>
</plist>
```

8. Иконки macOS — `Assets.xcassets/Contents.json` + `AppIcon.appiconset/Contents.json` пустые placeholder'ы.
  </action>
  <acceptance_criteria>
    - `grep -q "app.bbtb.tools.socksprobe.ios" BBTB/Tools/SocksProbe/SocksProbe-iOS/Info.plist`
    - `grep -q "app.bbtb.tools.socksprobe.macos" BBTB/Tools/SocksProbe/SocksProbe-macOS/Info.plist`
    - `! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements` (R1 invariant: НЕТ App Group)
    - `! grep -q "keychain-access-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements`
    - `! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements`
    - `! grep -q "keychain-access-groups" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements`
    - `grep -q "com.apple.security.network.client" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements`
    - `grep -q "@main" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbeApp.swift`
    - `grep -q "SocksProbeView" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbeApp.swift`
    - `grep -q "@main" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbeApp.swift`
  </acceptance_criteria>
</task>

<task id="W1-T4" type="checkpoint:human-action" gate="blocking" autonomous="false">
  <name>Task W1-T4: Создать SocksProbe.xcodeproj в Xcode + первая сборка обоих SocksProbe target'ов</name>
  <what-built>Standalone Xcode project `BBTB/Tools/SocksProbe/SocksProbe.xcodeproj` с двумя app target'ами (iOS + macOS), которые шарят Swift-файлы из `Shared/`. Делается ВРУЧНУЮ через Xcode UI (как W0-T5) — стандартный путь для multi-target Xcode-проектов без сторонних tool'ов.</what-built>
  <read_first>
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 1 (entitlement constraints)
    - .planning/phases/01-foundation/01-RESEARCH.md §8 (Apple Sandbox для loopback)
  </read_first>
  <how-to-verify>
    Пользователь в Xcode 16+:

    1. **Создать project:** File → New → Project → iOS → App → Product Name `SocksProbe`, Bundle ID `app.bbtb.tools.socksprobe.ios`, Team `UAN8W9Q82U`, Interface SwiftUI, Language Swift. Сохранить в `BBTB/Tools/SocksProbe/` — получится `BBTB/Tools/SocksProbe/SocksProbe.xcodeproj`.

    2. **Удалить generated файлы**, заменить ссылками на `SocksProbe-iOS/SocksProbeApp.swift`, `SocksProbe-iOS/Info.plist`, `SocksProbe-iOS/SocksProbe-iOS.entitlements`, `SocksProbe-iOS/Assets.xcassets`. Add Files → выбрать директорию `Shared/` → Create folder reference (НЕ groups). Это сделает все `Shared/*.swift` доступными в iOS target.

    3. **Добавить macOS target:** File → New → Target → macOS → App → Product Name `SocksProbe-macOS`, Bundle ID `app.bbtb.tools.socksprobe.macos`. Удалить generated файлы, добавить `SocksProbe-macOS/SocksProbeApp.swift` + плист + entitlements + Assets. Подключить тот же `Shared/` folder reference к macOS target (правый клик на Shared → Target Membership → check both SocksProbe-iOS и SocksProbe-macOS).

    4. **Привязать entitlements в Build Settings:**
       - SocksProbe-iOS: CODE_SIGN_ENTITLEMENTS = `SocksProbe-iOS/SocksProbe-iOS.entitlements`
       - SocksProbe-macOS: CODE_SIGN_ENTITLEMENTS = `SocksProbe-macOS/SocksProbe-macOS.entitlements`

    5. **Smoke-build:**
       ```bash
       cd /Users/vergevsky/ClaudeProjects/VPN/BBTB/Tools/SocksProbe
       xcodebuild build -project SocksProbe.xcodeproj -scheme SocksProbe -destination 'generic/platform=iOS Simulator' -quiet
       echo "SocksProbe iOS exit: $?"
       xcodebuild build -project SocksProbe.xcodeproj -scheme SocksProbe-macOS -destination 'generic/platform=macOS' -quiet
       echo "SocksProbe macOS exit: $?"
       ```

    Оба должны вернуть exit 0.

    6. **Записать результат:**
       ```bash
       mkdir -p /Users/vergevsky/ClaudeProjects/VPN/BBTB/.gsd
       echo "Wave 1 SocksProbe build verified: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > /Users/vergevsky/ClaudeProjects/VPN/BBTB/.gsd/wave1-socksprobe-build.log
       ```

    После — type "socksprobe green" в чате.
  </how-to-verify>
  <resume-signal>Type "socksprobe green" + (опционально) скриншот двух последних строк xcodebuild с BUILD SUCCEEDED.</resume-signal>
  <done>SocksProbe.xcodeproj существует, оба scheme собираются BUILD SUCCEEDED, `BBTB/.gsd/wave1-socksprobe-build.log` записан.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| sing-box JSON template → libbox runtime | Template читается из bundle resource, парсится `JSONSerialization`, валидируется `SingBoxConfigLoader`. Tampering bundle resource → unit-тесты ловят при build (template сам валидируется через `test_templateLoadsAndValidates`) |
| Stranger app on device → BBTB tunnel loopback | SocksProbe моделирует именно эту атаку: пытается TCP-connect к 127.0.0.1:N. Open port = R1 violation. На iOS — sandbox изолирует loopback (защита есть бесплатно), на macOS — sandbox слабее, проверка особенно важна |
| Test fixtures → production code | Fixtures лежат в Tests/.../Fixtures/, не bundle'ятся в production target |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-W1-01 | Information Disclosure | sing-box config с открытым SOCKS5 на 127.0.0.1 | mitigate | (a) Template без inbounds[] — RESEARCH §3; (b) `SingBoxConfigLoader.validate` runtime-reject (3 типа inbound: socks, mixed, tun, http); (c) `forbiddenInboundExists` для любого inbounds-присутствия в Phase 1 |
| T-01-W1-02 | Information Disclosure | sing-box experimental gRPC API экспонирует outbounds с ключами | mitigate | Template `experimental: {}`; `validate` reject при `clash_api`/`v2ray_api` непустых; `cache_file.enabled=true` reject |
| T-01-W1-03 | Tampering | Malformed sing-box JSON → libbox panic при start | mitigate | `validate(json:)` бросает `.malformedJSON` ДО `LibboxNewService` вызова в Wave 3 |
| T-01-W1-04 | Spoofing | Атакующий передаёт vless:// URI с подменённой outbound type | mitigate | `validate` требует `outbounds.contains { type == "vless" }`; non-VLESS outbound в Phase 1 — `.noVLESSOutbound` |
| T-01-W1-05 | Information Disclosure | SocksProbe в App Group / Keychain нашего bundle = нерепрезентативная проверка | mitigate | SocksProbe entitlements БЕЗ App Group и БЕЗ keychain-access (W1-T3 acceptance grep'нет это явно); bundle ID `app.bbtb.tools.socksprobe.*` — отдельный namespace |
| T-01-W1-06 | Information Disclosure | SocksProbe на macOS без `network.client` entitlement не сможет connect к 127.0.0.1 → fals positive «closed» | mitigate | `network.client = true` явно в entitlements; без `network.server` чтобы не было поверхности для listen |
</threat_model>

<verification>
**Wave 1 проверки:**

1. **Unit tests green:**
   ```bash
   xcodebuild test -workspace BBTB.xcworkspace -scheme PacketTunnelKit -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -20
   ```
   Должно вывести `** TEST SUCCEEDED **` и «Executed 12 tests» (точное число — 12 из SingBoxConfigLoaderTests).

2. **Template R1 invariant grep:**
   ```bash
   ! grep -q '"inbounds"' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
   grep -q '"experimental": {}' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
   ```

3. **SocksProbe сборка:**
   `BBTB/.gsd/wave1-socksprobe-build.log` записан с зелёными сборками обоих platform target'ов (W1-T4).

4. **SocksProbe entitlements integrity:**
   ```bash
   ! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements
   ! grep -q "keychain-access-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements
   ! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements
   ! grep -q "keychain-access-groups" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements
   ```

**Не верифицируется в Wave 1:**
- Реальный запуск SocksProbe на устройстве с активным туннелем — это Wave 5 (требует BaseSingBoxTunnel из Wave 3 + UI из Wave 4 + реальный test config от разработчика).
- R6 (IFF_POINTOPOINT) — Wave 2 (TunnelSettings) + Wave 5 (assertion + external check).
</verification>

<success_criteria>
Wave 1 завершён когда:

- [ ] `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` существует, валидный JSON, БЕЗ inbounds[], БЕЗ experimental.clash_api / v2ray_api / cache_file.
- [ ] `SingBoxConfigLoader.validate(json:)` реализован в `PacketTunnelKit` с публичным API + 7 правилами отказа + branch для `malformedJSON`.
- [ ] Все 10 JSON-фикстур существуют (1 valid + 9 invalid вариантов).
- [ ] Все 12 unit-тестов `SingBoxConfigLoaderTests` проходят через `xcodebuild test`.
- [ ] `BBTB/Tools/SocksProbe/Shared/` содержит RKNPorts, PortProber, InterfaceInspector, ViewModel, View с правильной реализацией (NWConnection + getifaddrs + IFF_POINTOPOINT detection).
- [ ] `BBTB/Tools/SocksProbe/SocksProbe.xcodeproj` существует, оба target'а (iOS + macOS) собираются BUILD SUCCEEDED.
- [ ] SocksProbe iOS bundle ID = `app.bbtb.tools.socksprobe.ios`, macOS = `app.bbtb.tools.socksprobe.macos`.
- [ ] SocksProbe entitlements (обе платформы) НЕ содержат `application-groups` и НЕ содержат `keychain-access-groups`.
- [ ] SocksProbe-macOS entitlements содержат `app-sandbox=true` + `network.client=true`.
- [ ] R1 (SEC-01, SEC-02) валидация защищена от регрессий двумя слоями: template invariant grep + validate unit-тесты.
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-W1-security-config-SUMMARY.md` с:
- Снапшот `xcodebuild test` вывода для `PacketTunnelKit` scheme (последние 10 строк)
- Снапшот `xcodebuild build` для обоих SocksProbe target'ов
- Точные пути созданных файлов (vsestraightline)
- Заметка о Wave 5 — что именно SocksProbe нужно запустить и какие результаты сохранить в `.planning/phases/01-foundation/security-evidence/`
- Если в ходе implementation обнаружились отклонения от RESEARCH (например, sing-box 1.13.x требует другое имя поля) — задокументировать
</output>
