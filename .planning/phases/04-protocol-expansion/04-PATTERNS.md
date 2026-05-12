# Phase 4: Protocol Expansion — Pattern Map

**Mapped:** 2026-05-12
**Files analyzed:** 27 (создаются/модифицируются)
**Analogs found:** 26 / 27 (один файл — Clash YAML parser — без прямого in-repo аналога, использует Yams patterns из RESEARCH §pattern-4)

## Обзор

Phase 4 — чистая **glue-code expansion**: добавление 3 protocol handler packages + 3 URI-парсеров + 1 YAML-парсера + расширение enum'ов на 3 case'а в трёх местах + auto-upgrade Task. Никаких новых архитектурных решений. Все аналоги — из Phase 2 Trojan implementation (наиболее свежий и canonical pattern).

**Ключевые аналоги:**
- **Protocol handler package** → `BBTB/Packages/Protocols/Trojan/` (Package.swift, Handler, ConfigBuilder, Template)
- **URI parser** → `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift`
- **PoolBuilder outbound builder** → `buildTrojanOutbound(parsed:tag:)` в `PoolBuilder.swift:127-164`
- **AnyParsedConfig switch расширения** → `ImportedServer.swift:9-13` + все callers в `ConfigImporter.swift` (lines 254-262, 360-370, 501-506, 527-568, 573-601)
- **URI parser tests** → `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift`
- **ConfigBuilder tests** → `BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift`
- **Phase 1 registration** → `BBTB/App/iOSApp/BBTB_iOSApp.swift:34-35`, `BBTB/App/macOSApp/BBTB_macOSApp.swift:22-23`

## File Classification

### Новые файлы — Protocol handlers (Packages/Protocols/)

| Файл | Role | Data Flow | Closest Analog | Match |
|------|------|-----------|----------------|-------|
| `BBTB/Packages/Protocols/VLESSTLS/Package.swift` | config | build-time | `BBTB/Packages/Protocols/Trojan/Package.swift` | exact |
| `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift` | handler | request-response | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift` | exact |
| `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` | service | transform (URI→JSON) | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` | exact |
| `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/Resources/SingBoxConfigTemplate.vless-tls.json` | template | build-time resource | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` | exact (минус Reality block) |
| `BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/ConfigBuilderTests.swift` | test | unit | `BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift` | exact |
| `BBTB/Packages/Protocols/Shadowsocks/Package.swift` | config | build-time | `BBTB/Packages/Protocols/Trojan/Package.swift` | exact |
| `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ShadowsocksHandler.swift` | handler | request-response | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift` | exact |
| `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift` | service | transform | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` | exact |
| `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/Resources/SingBoxConfigTemplate.shadowsocks.json` | template | resource | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json` | exact (только method/password; без TLS block) |
| `BBTB/Packages/Protocols/Shadowsocks/Tests/ShadowsocksTests/ConfigBuilderTests.swift` | test | unit | `BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift` | exact |
| `BBTB/Packages/Protocols/Hysteria2/Package.swift` | config | build-time | `BBTB/Packages/Protocols/Trojan/Package.swift` | exact |
| `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Hysteria2Handler.swift` | handler | request-response | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift` | exact |
| `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift` | service | transform | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` | exact (+ R1 EXCEPTION для `tls.insecure`) |
| `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Resources/SingBoxConfigTemplate.hysteria2.json` | template | resource | `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json` | role-match (+ `${ALLOW_INSECURE}` placeholder) |
| `BBTB/Packages/Protocols/Hysteria2/Tests/Hysteria2Tests/ConfigBuilderTests.swift` | test | unit | `BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift` | exact |

### Новые файлы — ConfigParser (Packages/ConfigParser/Sources/)

| Файл | Role | Data Flow | Closest Analog | Match |
|------|------|-----------|----------------|-------|
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/ShadowsocksURIParser.swift` | service | transform (URI→Parsed) | `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` | exact |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/Hysteria2URIParser.swift` | service | transform | `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` | exact |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift` | service | transform (YAML→[Parsed]) | `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` (parseSingBoxJSON pattern) | partial — нет точного YAML аналога |

### Новые файлы — Test fixtures (Packages/ConfigParser/Tests/.../Fixtures/)

| Файл | Role | Closest Analog |
|------|------|----------------|
| `Fixtures/ss-2022-aes-128-gcm.txt` | fixture | `Fixtures/unsupported-ss-uri.txt` (формат `ss://base64@host:port#tag`) |
| `Fixtures/ss-2022-percent-encoded.txt` | fixture | `Fixtures/unsupported-ss-uri.txt` (вариант percent-encoded) |
| `Fixtures/ss-legacy-chacha20.txt` | fixture | `Fixtures/unsupported-ss-uri.txt` |
| `Fixtures/outline-access-key.txt` | fixture | `Fixtures/unsupported-ss-uri.txt` (Outline = SIP002 ss://) |
| `Fixtures/hy2-with-obfs.txt` | fixture | `Fixtures/unsupported-hy2-uri.txt` |
| `Fixtures/hy2-insecure.txt` | fixture | `Fixtures/unsupported-hy2-uri.txt` |
| `Fixtures/hy2-multi-port.txt` | fixture | `Fixtures/unsupported-hy2-uri.txt` |
| `Fixtures/vless-tls-no-flow.txt` | fixture | `Fixtures/trojan-tcp-uri.txt` (структура `proto://uuid@host:port?…`) |
| `Fixtures/vless-tls-vision.txt` | fixture | `Fixtures/trojan-tcp-uri.txt` |
| `Fixtures/clash-mixed-proxies.yaml` | fixture | (новый формат, не имеет аналога) |

### Новые тесты (Packages/ConfigParser/Tests/ConfigParserTests/)

| Файл | Role | Closest Analog |
|------|------|----------------|
| `ShadowsocksURIParserTests.swift` | test | `TrojanURIParserTests.swift` |
| `Hysteria2URIParserTests.swift` | test | `TrojanURIParserTests.swift` |
| `ClashYAMLParserTests.swift` | test | `TrojanURIParserTests.swift` (структура) + `UniversalImportParserTests.swift` (multi-result) |
| `VLESSURIParserTLSTests.swift` | test | `VLESSURIParserTests.swift` |

### Модифицируемые файлы

| Файл | Role | Изменения | Closest Analog для расширения |
|------|------|-----------|-------------------------------|
| `BBTB/Packages/ConfigParser/Package.swift` | config | + Yams dep | `BBTB/Packages/Protocols/Trojan/Package.swift` (стиль dependency declaration) |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift` | model | + 3 enum case'а (vlessTLS / shadowsocks / hysteria2) + новые structs | `ImportedServer.swift:9-13` (existing pattern) |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift` | utility | `supportedSchemesInPhase2` → `supportedSchemesInPhase4`; обновить displayName messages | `StubParsers.swift:11-13` |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` | service | + classify Clash YAML branch; + 3 case'а в `parseSingleURI`; + 3 case'а в `parseSingBoxJSON` outbound switch | `UniversalImportParser.swift:113-145` (classify), `:156-209` (parseSingleURI), `:266-310` (parseSingBoxJSON) |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` | service | сигнатура `parse` → `throws -> AnyParsedConfig`; + branch `security=tls` (D-02) | `VLESSURIParser.swift:43-88` (текущий single-branch parse) |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` | service | + 3 case'а в `switch parsed`; + 3 outbound builder функции | `PoolBuilder.swift:42-49` (switch), `:127-164` (buildTrojanOutbound) |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` | service | + 3 case'а в `buildServerConfig` (361-386), `reparseFromKeychain` (527-568), `buildKeychainPayload` (573-601), `serverHost` switches (254-262, 501-506); + новый метод `runIsSupportedUpgrade()` (D-14) | `ConfigImporter.swift:354-421` + `:515-601` |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` | service | **НЕ менять** — `proxyOutboundTypes` уже содержит `shadowsocks`, `hysteria2` (verified `SingBoxConfigLoader.swift:69-73`) | n/a |
| `BBTB/App/iOSApp/BBTB_iOSApp.swift` | bootstrap | + 3 строки `ProtocolRegistry.shared.register(...)` | `BBTB_iOSApp.swift:34-35` |
| `BBTB/App/macOSApp/BBTB_macOSApp.swift` | bootstrap | + 3 строки `ProtocolRegistry.shared.register(...)` | `BBTB_macOSApp.swift:22-23` |
| `BBTB/Project.swift` | config | + 3 localPackages entries + 3 dependencies в iOS/macOS targets | `Project.swift:39-40` (Trojan entry), `:82-84` (target dep) |

## Pattern Assignments

### 1. `Protocols/VLESSTLS/Package.swift` (config, build-time)

**Analog:** `BBTB/Packages/Protocols/Trojan/Package.swift`

Полностью копировать структуру — only difference: name, target paths, resources list (template `.vless-tls.json` вместо `.trojan-tcp.json` / `.trojan-ws.json`).

**Critical excerpt** (`Trojan/Package.swift:1-36`):
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trojan",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Trojan", targets: ["Trojan"])],
    dependencies: [
        .package(path: "../../VPNCore"),
        .package(path: "../../PacketTunnelKit"),
    ],
    targets: [
        .target(
            name: "Trojan",
            dependencies: ["VPNCore", "PacketTunnelKit"],
            path: "Sources/Trojan",
            resources: [
                .process("Resources/SingBoxConfigTemplate.trojan-tcp.json"),
                .process("Resources/SingBoxConfigTemplate.trojan-ws.json"),
            ]
        ),
        .testTarget(
            name: "TrojanTests",
            dependencies: ["Trojan"],
            path: "Tests/TrojanTests",
            linkerSettings: [
                // libbox transitive deps — Trojan → PacketTunnelKit → SingBoxBridge → libbox.
                .linkedLibrary("resolv"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
```

**Для VLESSTLS / Shadowsocks / Hysteria2 — точно так же**, только переименовать `Trojan` → `VLESSTLS` / `Shadowsocks` / `Hysteria2` и обновить resource list.

### 2. `Protocols/VLESSTLS/Sources/VLESSTLS/VLESSTLSHandler.swift` (handler, request-response)

**Analog:** `BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift`

**Identifier** должен быть `"vless-tls"` для VLESSTLS, `"shadowsocks"` для Shadowsocks, `"hysteria2"` для Hysteria2. **DisplayName** — `"VLESS + TLS"`, `"Shadowsocks"`, `"Hysteria2"` соответственно.

**Core pattern** (`Trojan/TrojanHandler.swift:11-49`):
```swift
public struct TrojanHandler: VPNProtocolHandler {
    public static let identifier = "trojan"  // lowercase, matches URI scheme
    public static let displayName = "Trojan"

    public var isAvailable: Bool { true }

    public init() {}

    public func validate(config: ProtocolConfig) throws {
        guard config.identifier == Self.identifier else {
            throw HandlerError.identifierMismatch(expected: Self.identifier, got: config.identifier)
        }
    }

    public func connect(config: ProtocolConfig) async throws -> TunnelHandle {
        return TunnelHandle()  // unused — real start через NETunnelProviderManager
    }

    public func disconnect(handle: TunnelHandle) async throws { /* no-op */ }

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

Эта структура **stub-handler'а** одинакова для всех новых protocol packages — handler в production flow не делает реальной работы, real start идёт через `NETunnelProviderManager.connection.startVPNTunnel`. Phase 4 не меняет этот контракт.

### 3. `Protocols/*/Sources/*/ConfigBuilder.swift` (service, transform)

**Analog:** `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift`

**Imports pattern** (lines 1-2):
```swift
import Foundation
import PacketTunnelKit
```

**Inputs struct + builder pattern** (`ConfigBuilder.swift:9-81`):
```swift
public enum ConfigBuilder {
    public struct TrojanInputs: Sendable, Equatable {
        public let host: String
        public let port: Int
        public let password: String
        public let sni: String
        public let fingerprint: String
        public let alpn: [String]
        public let transport: TransportType
        public let remark: String?
        // … init
    }

    public enum BuilderError: Error, LocalizedError, Equatable {
        case templateLoadFailed(String)
        case invalidPort(Int)
        case missingPassword
        case missingSNI
        // … errorDescription
    }

    public static func buildSingBoxJSON(from inputs: TrojanInputs) throws -> String {
        guard inputs.port > 0 && inputs.port <= 65535 else { throw BuilderError.invalidPort(inputs.port) }
        guard !inputs.password.isEmpty else { throw BuilderError.missingPassword }
        guard !inputs.sni.isEmpty else { throw BuilderError.missingSNI }
        // …
        let template = try loadTemplate(named: templateName)
        var filled = template
            .replacingOccurrences(of: "${SERVER_HOST}",      with: inputs.host)
            .replacingOccurrences(of: "${TROJAN_PASSWORD}",  with: inputs.password)
            .replacingOccurrences(of: "${SNI_DOMAIN}",       with: inputs.sni)
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: inputs.fingerprint)
            .replacingOccurrences(of: "${DNS_DETOUR}",       with: "trojan-out")
        if inputs.port != 443 {
            return try mutatePort(in: filled, to: inputs.port)
        }
        return filled
    }

    private static func mutatePort(in json: String, to port: Int) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var outbounds = root["outbounds"] as? [[String: Any]],
              !outbounds.isEmpty
        else { return json }
        var first = outbounds[0]
        first["server_port"] = port
        outbounds[0] = first
        root["outbounds"] = outbounds
        let mutated = try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted)
        return String(data: mutated, encoding: .utf8) ?? json
    }

    private static func loadTemplate(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw BuilderError.templateLoadFailed("\(name).json not found in bundle")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw BuilderError.templateLoadFailed(error.localizedDescription)
        }
    }
}
```

**Применение per protocol:**

- **VLESSTLS ConfigBuilder:** Inputs — `uuid`, `host`, `port`, `flow`, `sni`, `fingerprint`, `alpn`. Placeholders: `${SERVER_HOST}`, `${VLESS_UUID}`, `${VLESS_FLOW}`, `${SNI_DOMAIN}`, `${UTLS_FINGERPRINT}`. DNS detour = `"vless-out"`.
- **Shadowsocks ConfigBuilder:** Inputs — `host`, `port`, `method`, `password`. Placeholders: `${SERVER_HOST}`, `${SS_METHOD}`, `${SS_PASSWORD}`. DNS detour = `"shadowsocks-out"`. **Нет SNI / fingerprint** (Shadowsocks не TLS).
- **Hysteria2 ConfigBuilder:** Inputs — `host`, `port`, `password`, `sni`, `obfs?`, `obfsPassword?`, `allowInsecure`. Placeholders: `${SERVER_HOST}`, `${HY2_PASSWORD}`, `${SNI_DOMAIN}`, `${ALLOW_INSECURE}` (string "true"/"false"). **R1 EXCEPTION:** комментарий-маркер `// R1 EXCEPTION — only Hysteria2 (D-08)` непосредственно над строкой подстановки `${ALLOW_INSECURE}`. DNS detour = `"hysteria2-out"`.

### 4. `Protocols/*/Sources/*/Resources/SingBoxConfigTemplate.*.json` (template, resource)

**Analog (для VLESSTLS):** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` — копировать минус `tls.reality` блок, оставить `flow` (placeholder `${VLESS_FLOW}` уже работает с commit 9aa3e93).

**Analog (для Shadowsocks/Hysteria2):** `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json` — копировать структуру (log/dns/outbounds/route/experimental).

**Critical structure** (`trojan-tcp.json:1-73`):
```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "dns-remote", "address": "https://cloudflare-dns.com/dns-query",
        "address_resolver": "dns-bootstrap", "address_strategy": "ipv4_only",
        "detour": "${DNS_DETOUR}" },
      { "tag": "dns-bootstrap", "address": "tcp://77.88.8.8",
        "detour": "direct", "strategy": "ipv4_only" },
      { "tag": "dns-fakeip", "address": "fakeip" }
    ],
    "rules": [
      { "outbound": "any", "server": "dns-bootstrap" },
      { "query_type": ["HTTPS", "SVCB"], "action": "predefined", "rcode": "NXDOMAIN" },
      { "query_type": ["A", "AAAA"], "server": "dns-fakeip" }
    ],
    "fakeip": { "enabled": true, "inet4_range": "100.64.0.0/10", "inet6_range": "fc00::/18" },
    "final": "dns-remote",
    "strategy": "ipv4_only",
    "independent_cache": true
  },
  "outbounds": [
    {
      "type": "trojan",
      "tag": "trojan-out",
      "server": "${SERVER_HOST}",
      "server_port": 443,
      "password": "${TROJAN_PASSWORD}",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "insecure": false,
        "alpn": ["h2", "http/1.1"],
        "utls": { "enabled": true, "fingerprint": "${UTLS_FINGERPRINT}" }
      }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "action": "sniff", "timeout": "1s" },
      { "protocol": "dns", "action": "hijack-dns" }
    ],
    "final": "trojan-out",
    "auto_detect_interface": true
  },
  "experimental": {}
}
```

**Per-protocol modifications:**
- **VLESSTLS:** outbound type `vless`, tag `vless-out`, fields `uuid` + `flow`, TLS block без `reality`. `route.final = vless-out`.
- **Shadowsocks:** outbound type `shadowsocks`, tag `shadowsocks-out`, fields `method` + `password`. **БЕЗ `tls` блока** (Shadowsocks работает без TLS — encrypted на уровне протокола). `route.final = shadowsocks-out`.
- **Hysteria2:** outbound type `hysteria2`, tag `hysteria2-out`, fields `password`, `tls.server_name`, `tls.insecure` (placeholder `${ALLOW_INSECURE}`). `route.final = hysteria2-out`.

**R1 invariant:** Все три template поддерживают `insecure: false` (hardcoded для VLESSTLS, Shadowsocks not applicable, Hysteria2 — placeholder который parser выставляет на основе D-08).

### 5. `ConfigParser/Sources/ConfigParser/ShadowsocksURIParser.swift` (service, transform)

**Analog:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift`

**Imports pattern** (line 1):
```swift
import Foundation
```

**Parser structure** (`TrojanURIParser.swift:4-127`):
```swift
public struct ParsedTrojan: Sendable, Equatable {
    public let password: String
    public let host: String
    public let port: Int
    public let security: String
    public let sni: String
    public let fingerprint: String
    public let alpn: [String]
    public let transport: TransportType
    public let remarks: String?
    // … init
}

public enum TrojanURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingPassword
    case notTLSSecurity(String?)
    case invalidTransport(String)
    // … errorDescription
}

public enum TrojanURIParser {
    public static func parse(_ uri: String) throws -> ParsedTrojan {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "trojan",
              let host = comps.host, !host.isEmpty,
              let port = comps.port,
              let user = comps.user
        else {
            throw TrojanURIError.malformedURI
        }
        let password = user.removingPercentEncoding ?? user
        guard !password.isEmpty else { throw TrojanURIError.missingPassword }

        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }
        // … strict TLS check, fallbacks, transport switch
        return ParsedTrojan(/* ... */)
    }
}
```

**Per parser — additional logic:**

- **ShadowsocksURIParser:** Дуальный decoder для userinfo (Pitfall 1 в RESEARCH §pitfall-1):
  1. Path 1 — percent-encoded `method:password` (SS-2022 / SIP022).
  2. Path 2 — base64url(method:password) с padding tolerance (legacy SIP002).
  Подробнее — RESEARCH «Example 2» (lines 622-680). Поддерживаемые методы whitelist в `supportedSSMethods` set. Не-supported → throw `unsupportedMethod(String)`.

- **Hysteria2URIParser:** Scheme allows `hy2` OR `hysteria2` (D-09). До `URLComponents` сделать regex-check на multi-port в port-части (`,` или `-`) → throw `multiPortNotSupported` (Pitfall 6). D-08 flag — collapse трёх синонимов (`insecure`, `allowInsecure`, `skip-cert-verify`) в `allowInsecure: Bool`. Подробнее — RESEARCH §pattern-1 (lines 266-339).

### 6. `ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` — MODIFY (D-02 branch)

**Текущая сигнатура:** `parse(_:) throws -> ParsedVLESS` (`VLESSURIParser.swift:44`).

**Новая сигнатура:** `parse(_:) throws -> AnyParsedConfig`.

**Breaking change** — callers нужно обновить:
- `UniversalImportParser.parseSingleURI` case "vless" (`UniversalImportParser.swift:161-174`)
- `VLESSURIParserTests` все тесты (12+ test methods)

**Pattern для расширения** (см. RESEARCH §example-3, lines 683-718):
```swift
public static func parse(_ uri: String) throws -> AnyParsedConfig {
    // … existing URLComponents extraction (VLESSURIParser.swift:45-60) …
    let security = q["security"] ?? ""

    // Phase 4 D-02: Reality detection via pbk OR explicit security=reality.
    // PORYADOK: СНАЧАЛА Reality (Pitfall 3 — иначе Reality URI с extra security=tls
    // ошибочно классифицируется как vlessTLS).
    let hasReality = (q["pbk"] != nil && !(q["pbk"] ?? "").isEmpty)
                   || security == "reality"

    if hasReality {
        // Existing Phase 1 path — собрать ParsedVLESS и вернуть .vlessReality
        // … existing code from VLESSURIParser.swift:71-86 …
        return .vlessReality(parsed)
    }

    if security == "tls" {
        let parsed = ParsedVLESSTLS(/* see RESEARCH lines 700-712 */)
        return .vlessTLS(parsed)
    }

    // security=none / missing → throw (UniversalImportParser routes as .invalid)
    throw VLESSURIError.unsupportedSecurity(security)
}
```

**Новый struct в ImportedServer.swift или VLESSURIParser.swift:**
```swift
public struct ParsedVLESSTLS: Sendable, Equatable {
    public let uuid: UUID
    public let host: String
    public let port: Int
    public let flow: String?          // nil если отсутствует в URI
    public let sni: String
    public let fingerprint: String
    public let alpn: [String]
    public let networkType: String    // только "tcp"/"raw" на Phase 4
    public let remarks: String?
}
```

### 7. `ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — MODIFY (3 case'а + 3 builders)

**Analog:** `buildTrojanOutbound(parsed:tag:)` в `PoolBuilder.swift:127-164`.

**Switch expansion** (`PoolBuilder.swift:42-52`):
```swift
// СТАРОЕ (Phase 2)
switch parsed {
case .vlessReality(let v):
    tag = "vless-\(index)"
    outbound = buildVLESSOutbound(parsed: v, tag: tag)
case .trojan(let t):
    tag = "trojan-\(index)"
    outbound = buildTrojanOutbound(parsed: t, tag: tag)
}

// НОВОЕ (Phase 4) — добавить 3 case'а
case .vlessTLS(let v):
    tag = "vless-tls-\(index)"
    outbound = buildVLESSTLSOutbound(parsed: v, tag: tag)
case .shadowsocks(let s):
    tag = "ss-\(index)"
    outbound = buildShadowsocksOutbound(parsed: s, tag: tag)
case .hysteria2(let h):
    tag = "hy2-\(index)"
    outbound = buildHysteria2Outbound(parsed: h, tag: tag)
```

**Core builder pattern** (`PoolBuilder.swift:127-164` — buildTrojanOutbound):
```swift
private static func buildTrojanOutbound(parsed: ParsedTrojan, tag: String) -> [String: Any] {
    // WS upgrade is HTTP/1.1 — strip h2 for WS.
    let isWS: Bool
    if case .ws = parsed.transport { isWS = true } else { isWS = false }
    let alpn: [String]
    if isWS {
        let filtered = parsed.alpn.filter { $0 != "h2" }
        alpn = filtered.isEmpty ? ["http/1.1"] : filtered
    } else {
        alpn = parsed.alpn
    }

    var outbound: [String: Any] = [
        "type": "trojan",
        "tag": tag,
        "server": parsed.host,
        "server_port": parsed.port,
        "password": parsed.password,
        "network": "tcp",
        "tls": [
            "enabled": true,
            "server_name": parsed.sni,
            "insecure": false,                 // R1 invariant — Trojan = strict TLS
            "alpn": alpn,
            "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
        ] as [String: Any],
    ]
    if case let .ws(path, host) = parsed.transport { /* … */ }
    return outbound
}
```

**Per-protocol builder implementations:**

- **buildVLESSTLSOutbound:** Структура как `buildVLESSOutbound` (PoolBuilder.swift:102-125), но **БЕЗ `reality` блока в `tls`** (только `server_name` + `utls` + `alpn`). Поле `flow` — если `parsed.flow != nil` → set as string, иначе omit или empty (RESEARCH §assumption-1).

- **buildShadowsocksOutbound** (RESEARCH §pattern-2, lines 354-364):
  ```swift
  private static func buildShadowsocksOutbound(parsed: ParsedShadowsocks, tag: String) -> [String: Any] {
      return [
          "type": "shadowsocks",
          "tag": tag,
          "server": parsed.host,
          "server_port": parsed.port,
          "method": parsed.method,
          "password": parsed.password,
          "network": "tcp",
      ]
  }
  ```

- **buildHysteria2Outbound** (RESEARCH §pattern-3, lines 370-397) — **R1 EXCEPTION**:
  ```swift
  private static func buildHysteria2Outbound(parsed: ParsedHysteria2, tag: String) -> [String: Any] {
      var tls: [String: Any] = [
          "enabled": true,
          "server_name": parsed.sni,
          // R1 EXCEPTION — only Hysteria2 (D-08). Любое появление этого поля
          // в pool builder'е для других протоколов = security bug.
          "insecure": parsed.allowInsecure,
      ]
      if let fp = parsed.fingerprint {
          tls["utls"] = ["enabled": true, "fingerprint": fp]
      }
      if let pin = parsed.pinSHA256 {
          tls["certificate_public_key_sha256"] = [pin]
      }
      var outbound: [String: Any] = [
          "type": "hysteria2",
          "tag": tag,
          "server": parsed.host,
          "server_port": parsed.port,
          "password": parsed.auth,
          "tls": tls,
      ]
      if let obfs = parsed.obfs, obfs == "salamander",
         let obfsPwd = parsed.obfsPassword, !obfsPwd.isEmpty {
          outbound["obfs"] = ["type": "salamander", "password": obfsPwd]
      }
      return outbound
  }
  ```

### 8. `ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — MODIFY (3 case'а + Clash YAML branch)

**Analogs:**
- Switch в `parseSingleURI` (`UniversalImportParser.swift:160-208`) — добавить case'ы для "ss", "hy2", "hysteria2"; vless case остаётся, но `VLESSURIParser.parse` теперь возвращает `AnyParsedConfig` напрямую (см. §6).
- Switch в `parseSingBoxJSON` outbound type (`UniversalImportParser.swift:285-310`) — добавить case'ы для "shadowsocks" / "hysteria2" + `extractParsedShadowsocks` / `extractParsedHysteria2` функции по образцу `extractParsedTrojan` (`UniversalImportParser.swift:339-364`).
- Classify (`UniversalImportParser.swift:92-146`) — добавить Clash YAML detection branch ДО HTTPS URL check (line 94). Условие — `trimmed.hasPrefix("proxies:")` OR содержит `mixed-port:` / `allow-lan:` YAML markers.

**parseSingleURI case pattern** (`UniversalImportParser.swift:176-189` — Trojan):
```swift
case "trojan":
    do {
        let parsed = try TrojanURIParser.parse(trimmed)
        let name = parsed.remarks ?? "\(parsed.host):\(parsed.port)"
        return ImportResult(
            supported: [.supported(name: name, parsed: .trojan(parsed), rawURI: trimmed)],
            unsupported: [], failed: [],
            subscriptionURL: subscriptionURL, source: source, metadata: nil
        )
    } catch {
        return ImportResult(supported: [], unsupported: [],
                            failed: [.invalid(rawURI: trimmed, error: error.localizedDescription)],
                            subscriptionURL: subscriptionURL, source: source, metadata: nil)
    }
```

**Применить идентично для:**
- `case "ss":` → `ShadowsocksURIParser.parse` → `.shadowsocks(parsed)`
- `case "hy2", "hysteria2":` → `Hysteria2URIParser.parse` → `.hysteria2(parsed)`
- `case "vless":` — modify (VLESSURIParser теперь возвращает AnyParsedConfig напрямую — не оборачивать в `.vlessReality(parsed)`).

### 9. `AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — MODIFY

**Analog для расширения switches:** `ConfigImporter.swift:354-421` (buildServerConfig), `:515-601` (reparseFromKeychain + buildKeychainPayload), `:254-262` + `:501-506` (serverHost extraction).

**Imports modification** (line 5):
```swift
import VLESSReality
// Phase 4 — добавить
import VLESSTLS
import Shadowsocks
import Hysteria2
```

**buildServerConfig switch** (`ConfigImporter.swift:361-370` — current Phase 2/3):
```swift
switch parsed {
case .vlessReality(let v):
    host = v.host; port = v.port; sni = v.sni
    protocolID = VLESSRealityHandler.identifier
    displayName = "VLESS + Reality"
case .trojan(let t):
    host = t.host; port = t.port; sni = t.sni
    protocolID = "trojan"
    displayName = "Trojan"
}
```

**Добавить 3 case'а:**
```swift
case .vlessTLS(let v):
    host = v.host; port = v.port; sni = v.sni
    protocolID = VLESSTLSHandler.identifier  // "vless-tls"
    displayName = "VLESS + TLS"
case .shadowsocks(let s):
    host = s.host; port = s.port; sni = nil  // SS не TLS
    protocolID = ShadowsocksHandler.identifier  // "shadowsocks"
    displayName = "Shadowsocks"
case .hysteria2(let h):
    host = h.host; port = h.port; sni = h.sni
    protocolID = Hysteria2Handler.identifier  // "hysteria2"
    displayName = "Hysteria2"
```

**buildKeychainPayload pattern** (`ConfigImporter.swift:573-601`):
```swift
private func buildKeychainPayload(for server: ImportedServer) -> [String: String] {
    guard case let .supported(_, parsed, _) = server else { return [:] }
    switch parsed {
    case .vlessReality(let v):
        return [
            "uuid": v.uuid.uuidString,
            "publicKey": v.publicKey,
            "shortId": v.shortId,
            "sni": v.sni,
            "fingerprint": v.fingerprint,
            "flow": v.flow,
        ]
    case .trojan(let t):
        var p: [String: String] = [
            "password": t.password,
            "sni": t.sni,
            "fingerprint": t.fingerprint,
            "alpn": t.alpn.joined(separator: ","),
        ]
        // … transport handling
        return p
    }
}
```

**Добавить 3 case'а — для каждого новый набор Keychain ключей:**

- `.vlessTLS(let v)`: `uuid`, `flow` (nil-safe — пустая строка если nil), `sni`, `fingerprint`, `alpn` (CSV).
- `.shadowsocks(let s)`: `method`, `password`. (Никакого TLS/SNI.)
- `.hysteria2(let h)`: `password`, `sni`, `fingerprint` (nil-safe), `allowInsecure` (string "true"/"false"), `obfs` (nil-safe), `obfsPassword` (nil-safe), `pinSHA256` (nil-safe).

**reparseFromKeychain pattern** (`ConfigImporter.swift:517-569`):
```swift
private func reparseFromKeychain(_ cfg: ServerConfig, tag: String) throws -> AnyParsedConfig? {
    // … load Keychain payload as [String: String] …
    switch cfg.protocolID {
    case "vless-reality":
        // … reconstruct ParsedVLESS from payload … return .vlessReality(parsed)
    case "trojan":
        // … reconstruct ParsedTrojan from payload … return .trojan(parsed)
    default:
        return nil
    }
}
```

**Добавить 3 case'а:** `"vless-tls"`, `"shadowsocks"`, `"hysteria2"` — обратный mapping из Keychain payload в `ParsedVLESSTLS` / `ParsedShadowsocks` / `ParsedHysteria2`.

**serverHost switch** (`ConfigImporter.swift:254-262` + `:501-506`):
```swift
let serverHost: String = {
    switch parsedList[0] {
    case .vlessReality(let v): return v.host
    case .trojan(let t): return t.host
    // Phase 4 — добавить
    case .vlessTLS(let v): return v.host
    case .shadowsocks(let s): return s.host
    case .hysteria2(let h): return h.host
    }
}()
```

**Pitfall 7 mitigation:** `AnyParsedConfig` — public enum в ConfigParser. Swift exhaustiveness check работает в switch на public enum — компиляция падёт после добавления 3 case'ов в enum, если switch не обновлён (это **хороший** signal).

### 10. `AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — НОВЫЙ метод `runIsSupportedUpgrade()` (D-14)

**Analog:** существующий `reparseFromKeychain` + `persistKeychainSecret` методы (`ConfigImporter.swift:327-345`, `:517-569`).

**Полный код метода — см. RESEARCH §example-4 (lines 731-800).** Ключевые точки:

1. **Fetch unsupported candidates** через `FetchDescriptor<ServerConfig>` с `predicate: #Predicate { $0.isSupported == false }`.
2. **Per-row** — попытка `parser.import(rawInput: cfg.rawURI, source: .pasteboard)`.
3. **Re-fetch by id** перед save (Pitfall 5 mitigation — row мог быть удалён user'ом).
4. **Update fields:** `isSupported = true`, `keychainTag = "bbtb-config-\(id.uuidString)"`, `protocolID = protocolID(from: parsed)`, `protocolDisplayName = displayName(from: parsed)`, `rawURI = nil` (T-02-04 invariant).
5. **context.save()** обёрнут в do/catch; ошибка → `continue` (best-effort семантика).
6. **Helper:** `protocolID(from: AnyParsedConfig)` switch на все 5 case'ов — возвращает `"vless-reality"` / `"vless-tls"` / `"trojan"` / `"shadowsocks"` / `"hysteria2"`.

**Throttling (Pitfall — RESEARCH §open-question-3):** в начале метода — проверка `UserDefaults.standard.double(forKey: "lastIsSupportedUpgrade")` — skip если <300s назад.

**Hook в App.swift:**
- iOS: `BBTB_iOSApp.swift` — в `body.scene` добавить `.onChange(of: scenePhase)` для `.active` → `Task { await importer.runIsSupportedUpgrade() }`.
- macOS: `BBTB_macOSApp.swift` — аналогично через `NSApplicationDelegate.applicationDidBecomeActive`.

### 11. `BBTB/App/iOSApp/BBTB_iOSApp.swift` + `BBTB_macOSApp.swift` — MODIFY (ProtocolRegistry)

**Analog (iOS):** `BBTB_iOSApp.swift:33-35`:
```swift
// CORE-02: регистрируем протоколы
ProtocolRegistry.shared.register(VLESSRealityHandler.self)
ProtocolRegistry.shared.register(TrojanHandler.self)  // Phase 2 PROTO-02
```

**Добавить 3 строки:**
```swift
ProtocolRegistry.shared.register(VLESSTLSHandler.self)     // Phase 4 PROTO-03
ProtocolRegistry.shared.register(ShadowsocksHandler.self)  // Phase 4 PROTO-04
ProtocolRegistry.shared.register(Hysteria2Handler.self)    // Phase 4 PROTO-05
```

**Imports:** добавить `import VLESSTLS`, `import Shadowsocks`, `import Hysteria2`.

### 12. `BBTB/Project.swift` — MODIFY (Tuist project)

**Analog для localPackages entry:** `Project.swift:39-40`:
```swift
.package(path: .relativeToManifest("Packages/Protocols/VLESSReality")),
.package(path: .relativeToManifest("Packages/Protocols/Trojan")),
```

**Добавить 3 entries:**
```swift
.package(path: .relativeToManifest("Packages/Protocols/VLESSTLS")),
.package(path: .relativeToManifest("Packages/Protocols/Shadowsocks")),
.package(path: .relativeToManifest("Packages/Protocols/Hysteria2")),
```

**Analog для target dependencies (iOS):** `Project.swift:82-84`:
```swift
.package(product: "VLESSReality"),
.package(product: "Trojan"),  // Phase 2 PROTO-02
```

**Добавить 3 deps в iOS И macOS targets:**
```swift
.package(product: "VLESSTLS"),     // Phase 4 PROTO-03
.package(product: "Shadowsocks"),  // Phase 4 PROTO-04
.package(product: "Hysteria2"),    // Phase 4 PROTO-05
```

### 13. `ConfigParser/Package.swift` — MODIFY (Yams dep)

**Analog:** `BBTB/Packages/ConfigParser/Package.swift:7-14` (existing dependencies declaration).

**Current:**
```swift
dependencies: [
    .package(path: "../VPNCore"),
    .package(path: "../PacketTunnelKit"),
],
targets: [
    .target(name: "ConfigParser", dependencies: ["VPNCore"]),
```

**Добавить:**
```swift
dependencies: [
    .package(path: "../VPNCore"),
    .package(path: "../PacketTunnelKit"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
],
targets: [
    .target(name: "ConfigParser", dependencies: [
        "VPNCore",
        .product(name: "Yams", package: "Yams"),
    ]),
```

### 14. URI Parser Tests (ConfigParserTests/*ParserTests.swift)

**Analog:** `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift`

**Imports pattern** (lines 1-2):
```swift
import XCTest
@testable import ConfigParser
```

**Fixture loader pattern** (`TrojanURIParserTests.swift:6-15`):
```swift
private func loadFixture(_ name: String, ext: String = "txt") -> String {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: nil)
        ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
    else {
        XCTFail("Fixture not found: \(name).\(ext)")
        return ""
    }
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}
```

**Test method pattern** (`TrojanURIParserTests.swift:40-48`):
```swift
func test_tcpMinimal_parses() throws {
    let p = try TrojanURIParser.parse("trojan://pwd@host:443?security=tls#TCP")
    XCTAssertEqual(p.password, "pwd")
    XCTAssertEqual(p.host, "host")
    XCTAssertEqual(p.port, 443)
    XCTAssertEqual(p.transport, .tcp)
    XCTAssertEqual(p.sni, "host")
    XCTAssertEqual(p.remarks, "TCP")
}
```

**Negative test pattern** (`TrojanURIParserTests.swift:73-77`):
```swift
func test_securityNone_throws() {
    XCTAssertThrowsError(try TrojanURIParser.parse("trojan://pwd@host:443?security=none")) { err in
        XCTAssertEqual(err as? TrojanURIError, .notTLSSecurity("none"))
    }
}
```

**Per-parser test coverage** (RESEARCH §Phase Requirements → Test Map):

- **ShadowsocksURIParserTests:** test_2022_base64, test_2022_percentEncoded, test_legacy_chacha20, test_unknownMethod_unsupported, test_outlineAccessKey, test_malformedURI_throws.
- **Hysteria2URIParserTests:** test_bothSchemes (hy2:// + hysteria2://), test_insecureFlag (3 синонима — Pitfall 6 mitigation), test_multiPort_rejects (Pitfall 6), test_obfsSalamander, test_obfsNotSalamander_throws.
- **VLESSURIParserTLSTests:** test_securityTLS_returnsVlessTLS, test_visionFlow_preserved, test_noFlow_nilField, test_realityWithExtraTLS_returnsReality (Pitfall 3 mitigation).
- **ClashYAMLParserTests:** test_extractsProxies, test_mixedProxies (ss + trojan + hy2 + vmess + reality), test_brokenYAML_returnsEmpty, test_alpnStringVsArray (Pitfall 4 mitigation).

### 15. ConfigBuilder Tests (Protocols/*/Tests/*Tests/ConfigBuilderTests.swift)

**Analog:** `BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift`

**Imports + helper pattern** (lines 1-19):
```swift
import XCTest
import PacketTunnelKit
@testable import Trojan

final class ConfigBuilderTests: XCTestCase {

    private func tcpInputs(
        host: String = "example.com",
        port: Int = 443,
        password: String = "secret",
        sni: String = "vpn.example.ru",
        fingerprint: String = "chrome"
    ) -> ConfigBuilder.TrojanInputs {
        ConfigBuilder.TrojanInputs(
            host: host, port: port, password: password, sni: sni,
            fingerprint: fingerprint, alpn: ["h2", "http/1.1"],
            transport: .tcp, remark: nil
        )
    }
```

**Critical test — placeholder check + validate** (`ConfigBuilderTests.swift:34-45`):
```swift
func test_tcp_buildsConfigWithoutPlaceholders() throws {
    let json = try ConfigBuilder.buildSingBoxJSON(from: tcpInputs())
    XCTAssertFalse(json.contains("${SERVER_HOST}"))
    XCTAssertFalse(json.contains("${TROJAN_PASSWORD}"))
    XCTAssertFalse(json.contains("${SNI_DOMAIN}"))
    XCTAssertFalse(json.contains("${UTLS_FINGERPRINT}"))
    XCTAssertFalse(json.contains("${DNS_DETOUR}"))
    XCTAssertTrue(json.contains("secret"))
    XCTAssertTrue(json.contains("vpn.example.ru"))
    XCTAssertTrue(json.contains("trojan-out"))
    XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))  // R1 self-test
}
```

Per protocol — заменить ${SERVER_HOST} / ${TROJAN_PASSWORD} / ... на свои placeholders и финальный assertion `XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))` оставить (это и есть R1 invariant test).

**Critical для Hysteria2 — R1 EXCEPTION test** (новый pattern, нет точного аналога — RESEARCH §pitfall-2):
```swift
func test_hy2_insecure_setsTrue() throws {
    let inputs = Hysteria2Inputs(/*…*/, allowInsecure: true)
    let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
    let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    let outbound = (root["outbounds"] as! [[String: Any]])[0]
    let tls = outbound["tls"] as! [String: Any]
    XCTAssertEqual(tls["insecure"] as? Bool, true)  // D-08 — единственный outbound type где true allowed
}

func test_hy2_insecure_false_default() throws {
    let inputs = Hysteria2Inputs(/*…*/, allowInsecure: false)
    let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
    let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    let outbound = (root["outbounds"] as! [[String: Any]])[0]
    let tls = outbound["tls"] as! [String: Any]
    XCTAssertEqual(tls["insecure"] as? Bool, false)
}
```

### 16. `ConfigParser/Sources/ConfigParser/ImportedServer.swift` — MODIFY (enum extension)

**Analog:** существующий enum `ImportedServer.swift:9-13`:
```swift
public enum AnyParsedConfig: Sendable, Equatable {
    case vlessReality(ParsedVLESS)
    case trojan(ParsedTrojan)
    // Phase 4+ добавит ss, vmess, hy2, wireguard
}
```

**Расширить:**
```swift
public enum AnyParsedConfig: Sendable, Equatable {
    case vlessReality(ParsedVLESS)
    case vlessTLS(ParsedVLESSTLS)        // Phase 4 — D-01
    case trojan(ParsedTrojan)
    case shadowsocks(ParsedShadowsocks)  // Phase 4 — D-05
    case hysteria2(ParsedHysteria2)      // Phase 4 — D-07
}
```

**UnsupportedReason** — добавить новый case если нужен для Phase 4-specific reason'ов:
```swift
public enum UnsupportedReason: String, Sendable, Equatable {
    case schemaUnsupportedInPhase2  // legacy — оставить для backward compat
    case schemaUnsupportedInPhase4  // NEW — Phase 4 unsupported (vmess, wireguard etc)
    case transportUnsupported
    case malformedURI
    case unsupportedSSMethod        // NEW — для SS с неизвестным cipher
    case multiPortNotSupported      // NEW — для Hysteria2 multi-port
}
```

## Shared Patterns

### Pattern A: R1 invariant — strict TLS для всех outbound types кроме Hysteria2

**Source:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift:147-153`, `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json:48-57`.

**Apply to:**
- VLESSTLS template + builder: `tls.insecure: false` hardcoded.
- Shadowsocks: не имеет TLS блока (encrypted в самом протоколе) — Pattern не применим.
- Hysteria2: **R1 EXCEPTION** — `tls.insecure` бывает true при D-08; обязательно отметить комментарием `// R1 EXCEPTION — only Hysteria2 (D-08)` непосредственно над строкой.

**Test invariant** (новый pattern — `PoolBuilderTests.test_nonHy2_outbounds_neverInsecure`, нет точного аналога):
```swift
func test_nonHy2_outbounds_neverHaveInsecureTrue() throws {
    let configs: [AnyParsedConfig] = [
        .vlessReality(makeVLESS()),
        .vlessTLS(makeVLESSTLS()),
        .trojan(makeTrojan()),
        .shadowsocks(makeShadowsocks()),
        .hysteria2(makeHysteria2(allowInsecure: true)),  // D-08 exception
    ]
    let json = try PoolBuilder.buildSingBoxJSON(from: configs)
    let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    let outbounds = root["outbounds"] as! [[String: Any]]
    for outbound in outbounds {
        guard let tag = outbound["tag"] as? String,
              !tag.hasPrefix("hy2-"),
              let tls = outbound["tls"] as? [String: Any]
        else { continue }
        XCTAssertEqual(tls["insecure"] as? Bool, false,
                       "R1 violation: \(tag) has tls.insecure=true (only hy2 allowed)")
    }
}
```

### Pattern B: SingBoxConfigLoader.validate self-test после buildSingBoxJSON

**Source:** `BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/ConfigBuilderTests.swift:44`, `ConfigImporter.swift:244-248`.

**Apply to:** все builder тесты + ConfigImporter pipeline.

**Excerpt:**
```swift
// In tests:
XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))

// In ConfigImporter.importFromRawInput (line 244-248):
do {
    try SingBoxConfigLoader.validate(json: poolJSON)
} catch {
    throw ImporterError.configBuildFailed(error)
}
```

**Phase 4 — нет необходимости менять `SingBoxConfigLoader`:** `proxyOutboundTypes` уже включает `shadowsocks` + `hysteria2` (`SingBoxConfigLoader.swift:69-73`):
```swift
private static let proxyOutboundTypes: Set<String> = [
    "vless", "trojan",
    "urltest", "selector",
    "shadowsocks", "vmess", "hysteria2", "wireguard", "tuic",  // future-supported
]
```

### Pattern C: ServerConfig persistence (SwiftData)

**Source:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:371-386` (supported case).

**Apply to:** Phase 4 для всех 3 новых protocol case'ов в `buildServerConfig`.

**Excerpt** (the `.supported` case):
```swift
return ServerConfig(
    id: id,
    name: name,
    host: host,
    port: port,
    protocolID: protocolID,
    keychainTag: keychainTag,
    isSupported: true,
    subscriptionURL: nil,
    outboundJSON: "",
    protocolDisplayName: displayName,
    sni: sni,
    rawURI: nil,                          // T-02-04 invariant — секреты не дублируются
    subscriptionID: subscriptionID
)
```

**SwiftData schema** — НЕ меняется в Phase 4. Все нужные поля уже добавлены в Phase 2/3 (`ServerConfig.swift:23-58`).

### Pattern D: Keychain payload — JSON dictionary `[String: String]`

**Source:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:573-601` (buildKeychainPayload), `:517-569` (reparseFromKeychain inverse op).

**Apply to:** все 3 новых protocol payload builders + reparse functions в Phase 4.

**Contract:**
1. `buildKeychainPayload` — возвращает `[String: String]` (только String values для SwiftData/Keychain compatibility); nil поля → "" или skip.
2. JSON serialize через `JSONSerialization.data(withJSONObject:)`.
3. Save через `KeychainStore.save(secret:tag:)` где tag = `"bbtb-config-\(uuid)"`.
4. Reverse — `KeychainStore.load(tag:)` → `JSONSerialization.jsonObject` → `[String: String]` cast → reconstruct `AnyParsedConfig`.

### Pattern E: Default-port-for-scheme в URI parsers

**Source:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift:44-53`:
```swift
private static func defaultPortForScheme(_ s: String) -> Int {
    switch s {
    case "ss": return 8388
    case "vmess": return 443
    case "hy2", "hysteria2": return 443
    case "wireguard": return 51820
    case "ssh": return 22
    case "socks5", "socks": return 1080
    default: return 0
    }
}
```

**Apply to:** Hysteria2URIParser (default 443) — `port = comps.port ?? 443`. ShadowsocksURIParser — `comps.port` required (SIP002 spec — port MUST be in URI).

## No Analog Found

| Файл | Role | Data Flow | Why no analog |
|------|------|-----------|---------------|
| `ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift` | service | transform (YAML→[Parsed]) | YAML parsing — новая dependency (Yams). Используется паттерн из RESEARCH §pattern-4 (lines 408-462) + Pitfall 4 (lines 533-548 alpn handling). Closest in-repo pattern для multi-result parsing — `UniversalImportParser.parseSingBoxJSON` (`:266-313`): итерация outbounds + per-entry switch + accumulate в `[ImportedServer]`. Структура error-handling per-proxy (try/catch на каждый proxy) — без аналога; описан в RESEARCH §threat (proxy malformed → unsupported, не throws на весь YAML). |

## Cross-Cutting File Modifications Summary

| File | Lines to modify | Pattern from |
|------|-----------------|--------------|
| `ImportedServer.swift` | +5 lines (3 enum cases + new structs reference) | self (existing pattern at lines 9-13) |
| `StubParsers.swift` | `supportedSchemesInPhase2` rename → `supportedSchemesInPhase4`; +3 schemes (vmess unsupported, остаются в `knownSchemes`); displayName messages "v0.2" → "v0.4" | self (lines 11-13) |
| `VLESSURIParser.swift` | Return type breaking change `ParsedVLESS` → `AnyParsedConfig`; +1 branch для `security=tls` | RESEARCH §example-3 (lines 685-718) |
| `UniversalImportParser.swift` | +Clash YAML branch в classify; +3 case в parseSingleURI; +2 case в parseSingBoxJSON outbound switch; +2 helper `extractParsed*` functions | self (lines 92-146, 156-208, 285-313, 339-364) |
| `PoolBuilder.swift` | +3 case в switch (line 42-49); +3 builder private functions (analog buildTrojanOutbound line 127-164) | self (lines 42-49, 127-164) |
| `ConfigImporter.swift` | 5 mod points: serverHost ×2 switches, buildServerConfig switch (361-370), reparseFromKeychain switch (527-568), buildKeychainPayload switch (573-601); +1 new method `runIsSupportedUpgrade()` (D-14 — RESEARCH §example-4) | self + RESEARCH §example-4 (lines 731-800) |
| `Package.swift` (ConfigParser) | +1 dependency Yams 6.2.1; +1 target dep entry | self (lines 7-14) |
| `Project.swift` (Tuist) | +3 entries в localPackages; +3 entries в iOS target deps; +3 entries в macOS target deps | self (lines 39-40, 82-84) |
| `BBTB_iOSApp.swift` + `BBTB_macOSApp.swift` | +3 imports; +3 ProtocolRegistry.shared.register lines; +1 scenePhase/applicationDidBecomeActive hook для runIsSupportedUpgrade | self (lines 33-35 + body.scene structure) |

## Metadata

**Analog search scope:**
- `BBTB/Packages/Protocols/Trojan/` (Phase 2 canonical)
- `BBTB/Packages/Protocols/VLESSReality/` (Phase 1 canonical)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/` (все 9 файлов)
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/` (4 test файла + Fixtures)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (Phase 2/3 import pipeline)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` (R1 validator — verified no change needed)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`
- `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift`
- `BBTB/Packages/VPNCore/Sources/VPNCore/{ServerConfig.swift, VPNProtocolHandler.swift}`
- `BBTB/App/iOSApp/BBTB_iOSApp.swift`, `BBTB/App/macOSApp/BBTB_macOSApp.swift`
- `BBTB/Project.swift`

**Files scanned:** 19 (in addition to CONTEXT.md + RESEARCH.md).

**Pattern extraction date:** 2026-05-12

**Coverage:**
- Files with exact analog: 22 (Protocols/* по образцу Trojan; URI parsers по образцу TrojanURIParser; tests; ConfigImporter expansion; App registration)
- Files with role-match analog: 4 (Hysteria2 template — Trojan template + ${ALLOW_INSECURE}; Hysteria2 outbound builder — Trojan builder + R1 exception; VLESSURIParser modify — self pattern; ImportedServer enum — self pattern)
- Files with no analog: 1 (ClashYAMLParser — use RESEARCH §pattern-4 + Yams API docs).
