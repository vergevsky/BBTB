# Phase 4: Protocol expansion — Research

**Researched:** 2026-05-12
**Domain:** Protocol handler-расширение (VLESS+TLS / Shadowsocks-2022 / Hysteria2) + завершение универсального ConfigParser (Clash YAML, Outline access keys, auto-upgrade ранее stub-парсенных серверов)
**Confidence:** HIGH (стек, парсеры, паттерны — verified против official docs sing-box/Hysteria2/SIP002 + полная прозрачность existing codebase)

## Summary

Phase 4 расширяет поддержку до 5 протоколов и финализирует import-pipeline. С точки зрения архитектуры это **не greenfield** — Phase 1/2/3 уже зафиксировали стек: `libbox.xcframework` (sing-box v1.13.11), Package-per-handler (`Protocols/Trojan`, `Protocols/VLESSReality`), `ConfigParser/UniversalImportParser` (actor), `PoolBuilder.buildSingBoxJSON`, R1 default-deny inbound whitelist в `SingBoxConfigLoader`, SwiftData `ServerConfig.rawURI` для re-parse.

Все 3 новых protocol package'а строятся по точному образцу `Protocols/Trojan` (одинаковая структура: `Sources/<Name>/<Name>Handler.swift` + `ConfigBuilder.swift` + `Resources/SingBoxConfigTemplate.*.json`). URI-парсеры — по образцу `TrojanURIParser` (одна функция `parse(_:)`, fail-fast, всё в `ConfigParser` package). `PoolBuilder` получает 3 новых case'а в `switch parsed`, `AnyParsedConfig` enum — 3 новых case'а. `SingBoxConfigLoader.proxyOutboundTypes` уже содержит `shadowsocks` и `hysteria2` (Phase 2 W0.T4), поэтому **валидатор править не нужно**.

Главные нестандартные точки:

1. **Hysteria2 — единственное исключение из R1.** `tls.insecure: true` разрешён при `insecure=1` / `allowInsecure=1` / `skip-cert-verify=1` в URI (D-08). PoolBuilder должен пропустить это поле через до sing-box JSON. SingBoxConfigLoader.validate **не блокирует** `tls.insecure` (R1 контролирует только inbound, не outbound — verified в `SingBoxConfigLoader.swift:75-131`).
2. **SIP002 base64 vs percent-encoding для SS-2022.** AEAD-2022 ciphers (`2022-blake3-*`) per SIP002 spec **MUST NOT** использовать base64url для userinfo, только percent-encoded `method:password`. Legacy ciphers (`aes-256-gcm`, `chacha20-ietf-poly1305`) — base64url **рекомендуется** но опционален. Парсер должен поддерживать оба варианта.
3. **Clash YAML — добавляется одна dependency (Yams 6.2.1).** Других известных Swift-нативных YAML-парсеров с активной поддержкой Swift 6 нет; Yams — de-facto стандарт (5+ лет на рынке, MIT, jpsim).
4. **isSupported auto-upgrade (D-14)** — паттерн уже есть в `ConfigImporter.reparseFromKeychain`, но он работает по обратному пути (ServerConfig → AnyParsedConfig из Keychain). Новый upgrade-flow читает `rawURI` (для unsupported `keychainTag = nil`), прогоняет через `UniversalImportParser`, при success — генерирует Keychain payload + обновляет `isSupported` + `outboundJSON` + `keychainTag`.

**Primary recommendation:** Реализовать в строгом соответствии с существующими паттернами Phase 2 (Trojan). Никаких новых архитектурных решений не вводить. Единственная новая зависимость — Yams (Clash YAML parsing).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**VLESS без Reality (PROTO-03):**
- **D-01:** Новый `AnyParsedConfig.vlessTLS(ParsedVLESSTLS)` case. Охватывает весь спектр VLESS+TLS — и Vision (`flow=xtls-rprx-vision`) и plain VLESS без flow. Решение в пользу максимального покрытия.
- **D-02:** Роутинг в `VLESSURIParser`: если URI содержит `pbk` или `security=reality` → `case vlessReality` (Phase 1, без изменений). Если `security=tls` и нет `pbk`/`sid` → `case vlessTLS`. Если `security=none` → `isSupported=false` (no-TLS VLESS нарушает R1).
- **D-03:** `ParsedVLESSTLS` содержит: `uuid`, `host`, `port`, `flow: String?` (nil если отсутствует), `sni`, `fingerprint`, `alpn`, транспорт (на Phase 4 только `tcp`/`raw` — остальные транспорты Phase 5). Новый Package: `Protocols/VLESSTLSHandler/`.

**Shadowsocks-2022 (PROTO-04):**
- **D-04:** Один `ShadowsocksURIParser` для всех `ss://` URI (SIP002: `ss://base64(method:password)@host:port#tag`). Поддерживаемые методы: все `2022-blake3-*` (`aes-128-gcm`, `aes-256-gcm`, `chacha20-poly1305`) + legacy (`aes-128-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`, `xchacha20-ietf-poly1305`). Неизвестный метод → `isSupported=false`.
- **D-05:** `AnyParsedConfig.shadowsocks(ParsedShadowsocks)`. `ParsedShadowsocks`: `host`, `port`, `method`, `password`. Новый Package: `Protocols/ShadowsocksHandler/`.
- **D-06:** В sing-box outbound: `type: "shadowsocks"`, `method`, `password`. Для SS-2022 методов — те же поля, sing-box различает их по строке метода.

**Hysteria2 (PROTO-05):**
- **D-07:** `AnyParsedConfig.hysteria2(ParsedHysteria2)`. `ParsedHysteria2`: `host`, `port`, `auth` (password), `sni`, `fingerprint: String?`, `obfs: String?`, `obfsPassword: String?`, `allowInsecure: Bool`, `pinSHA256: String?`.
- **D-08:** **Исключение из R1:** `insecure=1` / `allowInsecure=1` / `skip-cert-verify=1` в URI → `allowInsecure: true` в `ParsedHysteria2` → `tls.insecure: true` в sing-box JSON. Единственный протокол с таким исключением — обусловлено реальностью self-hosted Hysteria2 серверов с self-signed сертификатами.
- **D-09:** Поддержка обеих схем: `hy2://` и `hysteria2://` (короткая официальная форма). Multi-port формат в порте (`123,5000-6000`) → `isSupported=false` на Phase 4 (sing-box требует одного порта; multi-port = Phase 7 или позже).
- **D-10:** Новый Package: `Protocols/Hysteria2Handler/`. Sing-box outbound: `type: "hysteria2"`, `server`, `server_port`, `password`, `tls.server_name`, `obfs`.

**Outline access keys (IMP-05 — часть):**
- **D-11:** Outline access keys — стандартный SIP002 `ss://` формат. Покрывается `ShadowsocksURIParser` из D-04 без дополнительной логики. `ssconf://` (ссылка на JSON с SS-конфигом) — не в скоупе Phase 4 (обрабатывается как неизвестная схема → `isSupported=false`).

**Clash YAML (IMP-05 — часть):**
- **D-12:** Новый `ClashYAMLParser` в `ConfigParser`. Разбирает только секцию `proxies:`. Маппит поддерживаемые типы: `vless` → `ParsedVLESSTLS` (или `ParsedVLESSReality` если есть `reality-opts`), `trojan` → `ParsedTrojan`, `ss` → `ParsedShadowsocks`, `vmess` → `isSupported=false`, `hysteria2` / `hy2` → `ParsedHysteria2`. Секции `rules:`, `proxy-groups:`, `dns:` игнорируются.
- **D-13:** Детектирование Clash YAML в `UniversalImportParser`: строка начинается с `proxies:` или содержит yaml-маркеры (`mixed-port:`, `allow-lan:`) → передаётся в `ClashYAMLParser`. Иначе — обычный URI-пайплайн.

**isSupported auto-upgrade:**
- **D-14:** При запуске приложения (foreground) `ConfigImporter` сканирует все `ServerConfig` с `isSupported=false` и `rawURI != nil`. Каждый `rawURI` прогоняется через `UniversalImportParser`. Если теперь парсится в `supported` → `isSupported=true` + `outboundJSON` обновляется. Паттерн: запускается как background Task, не блокирует UI. Это решение из Phase 2 D-04 («флаг снимается без реимпорта»).

### Claude's Discretion

- Конкретные sing-box JSON-шаблоны для VLESSTLSHandler, ShadowsocksHandler, Hysteria2Handler — по образцу существующих `SingBoxConfigTemplate.trojan-tcp.json` / `vless-reality.json`.
- Структура тестов — по образцу `VLESSURIParserTests`, `TrojanURIParserTests`, `PoolBuilderSingleOutboundTests`.
- Порядок регистрации handler'ов в `AppDelegate` / startup — по образцу Phase 1/2.

### Deferred Ideas (OUT OF SCOPE)

- `ssconf://` (Outline JSON config URL) — обрабатывается как неизвестная схема → `isSupported=false`. Возможно Phase 6+ если появится запрос.
- Multi-port Hysteria2 (`port: 123,5000-6000`) — `isSupported=false` на Phase 4. Phase 7 или отдельный тикет.
- VMess handler — не в roadmap MVP, stub остаётся.
- VLESS транспорты (XHTTP, gRPC, HTTPUpgrade, WebSocket для VLESS) — Phase 5.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PROTO-03 | VLESS + XTLS-Vision (без Reality) — для серверов без поддержки Reality | Раздел «Стандартный стек», «VLESS+TLS — детали парсинга», sing-box outbound `vless` (verified [CITED: sing-box.sagernet.org/configuration/outbound/vless]); template — копия `vless-reality.json` минус блок `tls.reality`, плюс `${VLESS_FLOW}` placeholder уже работающий (commit `9aa3e93`) |
| PROTO-04 | Shadowsocks-2022 (SS-2022, AEAD-2022) — AES-128-GCM | Раздел «Shadowsocks — детали парсинга», SIP002 spec [CITED: github.com/shadowsocks/shadowsocks-org/wiki/SIP002-URI-Scheme], sing-box outbound `shadowsocks` (verified [CITED: sing-box.sagernet.org/configuration/outbound/shadowsocks]); key lengths 16/32/32 byte verified [CITED: shadowsocks.org/doc/sip022.html] |
| PROTO-05 | Hysteria2 — UDP-based, QUIC-обёртка | Раздел «Hysteria2 — детали парсинга», URI spec [CITED: v2.hysteria.network/docs/developers/URI-Scheme/], sing-box outbound `hysteria2` (verified [CITED: sing-box.sagernet.org/configuration/outbound/hysteria2]); R1 exception для `tls.insecure` обусловлен реальностью self-signed setups |
| IMP-04 finish | ConfigParser handler'ы для всех URI-форматов | Раздел «Архитектурные паттерны», `UniversalImportParser.parseSingleURI` switch расширяется тремя case'ами; `PoolBuilder` `switch parsed` тоже |
| IMP-05 finish | Outline access keys + Clash YAML | Outline = SIP002 `ss://` (D-11), покрывается одним парсером; Clash YAML — Yams 6.2.1 dependency; раздел «Clash YAML — детали парсинга» |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| URI parsing (vless/ss/hy2) | ConfigParser package (app process) | — | All parsers — pure Swift, no networking, no engine. Live in same module as TrojanURIParser/VLESSURIParser для consistency. |
| sing-box outbound JSON генерация | ConfigParser/PoolBuilder + Protocols/<Name>/ConfigBuilder | — | PoolBuilder строит multi-outbound pool (urltest); per-handler ConfigBuilder — для single-server case (use в `ConfigImporter` debug-flow). Pattern from Phase 2 Trojan. |
| sing-box engine execution | PacketTunnelKit (NEPacketTunnelProvider extension) | libbox.xcframework | Phase 4 не меняет engine — все 3 новых outbound type'а уже поддерживаются sing-box v1.13.11 нативно. |
| R1/SEC validation | PacketTunnelKit/SingBoxConfigLoader (extension) | ConfigParser (build-time validation) | `SingBoxConfigLoader.validate` уже whitelists `shadowsocks` + `hysteria2` (verified). Outbound-side validation для R1 не нужна (R1 — про inbound). |
| Clash YAML parsing | ConfigParser package | Yams (external SPM dep) | Pure parsing, no networking; Yams 6.2.1 для YAML→Swift dictionary, потом mapping в `AnyParsedConfig`. |
| isSupported auto-upgrade | ConfigImporter (MainScreenFeature) → ConfigParser | SwiftData (storage) | Background Task на foreground hook, читает `ServerConfig.rawURI`, делегирует в `UniversalImportParser`, обновляет SwiftData строки. Pattern from existing `reparseFromKeychain`. |
| SwiftData persistence | VPNCore/ServerConfig (`@Model`) | — | Schema **не меняется**: все нужные поля (`isSupported`, `rawURI`, `outboundJSON`, `keychainTag`, `protocolID`) уже есть. |

## Project Constraints (from CLAUDE.md)

- **Wiki-as-decision-log:** Каждое архитектурное/технологическое решение (например, выбор Yams) фиксируется в `wiki/security-gaps.md` или новой wiki-странице (R17 / R18 etc.) — не оставлять только в `.planning/`.
- **Источник истины:** `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — ROADMAP.md и REQUIREMENTS.md производны от него.
- **Язык ответов:** Все обоснования в коммитах, PR, документации — на русском (как и весь wiki). Code comments — русский для бизнес-логики, английский для технических деталей (стиль уже устоявшийся в codebase).
- **Аббревиатуры:** При первом использовании давать русский перевод в скобках (SIP — Shadowsocks Improvement Proposal; PSK — Pre-Shared Key, общий ключ).

## Standard Stack

### Core (без изменений — наследуется из Phase 1/2/3)

| Library / Component | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| sing-box engine (через libbox.xcframework) | 1.13.11 | Все 5 outbound type'ов: vless, trojan, shadowsocks, hysteria2, urltest [VERIFIED: BBTB/Packages/PacketTunnelKit/Package.swift + SingBoxConfigLoader.proxyOutboundTypes] | Phase 1 принятый стек (R8 wiki). Все 3 новых протокола поддерживаются нативно. |
| Foundation `URLComponents` | iOS 18 SDK | URI parsing для vless://, trojan://, ss://, hy2:// | Уже используется во всех существующих парсерах (`VLESSURIParser`, `TrojanURIParser`); единообразие. |
| SwiftData `@Model ServerConfig` | iOS 18 / macOS 15 | Persistence — БЕЗ изменения schema на Phase 4 | Все нужные поля уже добавлены в Phase 2 (`isSupported`, `rawURI`, `outboundJSON`). |
| `KeychainStore` (custom — VPNCore) | — | Secrets storage для supported configs | Pattern из Phase 1; ShadowsocksHandler / Hysteria2Handler / VLESSTLSHandler пишут payload через тот же helper. |

### Supporting (новое на Phase 4)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **Yams** | 6.2.1 (последний релиз 2026-02-05) [VERIFIED: github.com/jpsim/Yams] | YAML parsing для Clash subscription configs | Только в `ClashYAMLParser` для разбора секции `proxies:`. Swift 6 совместим, MIT, активный maintainer (jpsim). |

**Установка (добавить в `BBTB/Packages/ConfigParser/Package.swift`):**

```swift
dependencies: [
    .package(path: "../VPNCore"),
    .package(path: "../PacketTunnelKit"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
],
targets: [
    .target(name: "ConfigParser", dependencies: ["VPNCore", "Yams"]),
    // ...
]
```

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Yams | swift-yaml (apple/swift-yaml) | apple/swift-yaml не существует как stable public package на 2026-05; Yams — de-facto стандарт. |
| Yams | Hand-rolled YAML parser | YAML — нетривиальный грамматический формат (multiline strings, anchors, references, types coercion). Hand-roll = месяцы багов. |
| Per-protocol parser module | Один монолитный `ProtocolURIParser` | Текущая архитектура (`VLESSURIParser`, `TrojanURIParser` в одном package) уже одобрена и работает. Phase 4 продолжает паттерн — никакой реорганизации. |

**Версионная верификация:**

Команда `npm view` не применима (Swift / SPM). Версия Yams 6.2.1 подтверждена через GitHub releases (2026-02-05) и Swift Package Index. Минимальная требуемая Swift 5.7+ — наш target Swift 6.0 ✓.

## Architecture Patterns

### System Architecture Diagram

```
                       ┌──────────────────────────────────────────┐
                       │  Main App (BBTB-iOS / BBTB-macOS)        │
                       │                                          │
   raw input ─────────▶│ ConfigImporter.importFromRawInput        │
   (paste/QR/sub URL)  │       │                                  │
                       │       ▼                                  │
                       │  UniversalImportParser (actor)           │
                       │   ├─ classify()  ◀── + Clash YAML branch │
                       │   ├─ parseSingleURI ──────────┐          │
                       │   │     switch scheme:        │          │
                       │   │       vless → VLESSURIParser ◀─── + tls branch (D-02)
                       │   │       trojan → TrojanURIParser       │
                       │   │       ss → ShadowsocksURIParser ✨   │
                       │   │       hy2/hysteria2 → Hysteria2URIParser ✨
                       │   ├─ fetchAndParseSubscription           │
                       │   └─ parseClashYAML ✨ (Yams)            │
                       │                                          │
                       │  Result: AnyParsedConfig                 │
                       │    .vlessReality / .vlessTLS ✨ /        │
                       │    .trojan / .shadowsocks ✨ /           │
                       │    .hysteria2 ✨                         │
                       │                                          │
                       │  ConfigImporter:                         │
                       │    ├─ persistKeychainSecret(for:)        │
                       │    │   ←─ buildKeychainPayload ─ + 3 new cases
                       │    ├─ buildServerConfig(...)             │
                       │    └─ provisionTunnelProfile(for:)       │
                       │         ├─ reparseFromKeychain ─ + 3 new cases
                       │         └─ PoolBuilder.buildSingBoxJSON  │
                       │              └─ switch parsed ─ + 3 new builders
                       │                                          │
                       │  json ─────────────▶ NETunnelProvider    │
                       └──────────────────────────────────────────┘
                                              │ providerConfiguration
                                              ▼
                       ┌──────────────────────────────────────────┐
                       │  PacketTunnel Extension                  │
                       │   BaseSingBoxTunnel.startTunnel          │
                       │     SingBoxConfigLoader.validate ✓ (R1)  │
                       │     expandConfigForTunnel (+TUN inbound) │
                       │     libbox.startOrReloadService ──▶ engine
                       └──────────────────────────────────────────┘

Startup hook (D-14 auto-upgrade):
   App foreground → ConfigImporter.runIsSupportedUpgrade (Task) →
     fetch SwiftData {isSupported: false, rawURI != nil} →
       for each: UniversalImportParser.parseSingleURI(rawURI) →
         if .supported: rebuild Keychain payload + outboundJSON +
                        flip isSupported=true → save context
```

✨ = новое на Phase 4

### Recommended Project Structure (изменения)

```
BBTB/Packages/
├── ConfigParser/
│   └── Sources/ConfigParser/
│       ├── ImportedServer.swift          # AnyParsedConfig: + 3 case'а
│       ├── StubParsers.swift             # supportedSchemesInPhase4: {vless, trojan, ss, hy2, hysteria2}
│       ├── UniversalImportParser.swift   # parseSingleURI: + 3 case'а; classify(): + Clash YAML detection
│       ├── PoolBuilder.swift             # buildSingBoxJSON: + 3 outbound builders
│       ├── VLESSURIParser.swift          # parse(): + vlessTLS branch (D-02)
│       ├── TrojanURIParser.swift         # (без изменений)
│       ├── ShadowsocksURIParser.swift    # ✨ новый
│       ├── Hysteria2URIParser.swift      # ✨ новый
│       └── ClashYAMLParser.swift         # ✨ новый
│   └── Tests/ConfigParserTests/
│       ├── ShadowsocksURIParserTests.swift   # ✨
│       ├── Hysteria2URIParserTests.swift     # ✨
│       ├── ClashYAMLParserTests.swift        # ✨
│       ├── VLESSURIParserTLSTests.swift      # ✨ (новый набор для tls-branch)
│       ├── PoolBuilderTests.swift            # + 3 outbound-builder smoke tests
│       └── Fixtures/
│           ├── ss-2022-aes-128-gcm.txt       # ✨
│           ├── ss-legacy-chacha20.txt        # ✨
│           ├── hy2-with-obfs.txt             # ✨
│           ├── hy2-insecure.txt              # ✨
│           ├── vless-tls-no-flow.txt         # ✨
│           ├── vless-tls-vision.txt          # ✨
│           ├── clash-mixed-proxies.yaml      # ✨
│           └── outline-access-key.txt        # ✨ (= SIP002 ss://)
│
├── Protocols/
│   ├── Trojan/                # образец
│   ├── VLESSReality/          # образец
│   ├── VLESSTLS/              # ✨ новый
│   │   ├── Package.swift
│   │   ├── Sources/VLESSTLS/
│   │   │   ├── VLESSTLSHandler.swift   # identifier = "vless-tls"
│   │   │   ├── ConfigBuilder.swift     # single-server JSON
│   │   │   └── Resources/
│   │   │       └── SingBoxConfigTemplate.vless-tls.json
│   │   └── Tests/VLESSTLSTests/
│   │       └── ConfigBuilderTests.swift
│   ├── Shadowsocks/           # ✨ новый (имя package — Shadowsocks, identifier — "shadowsocks")
│   │   └── ... (та же структура)
│   └── Hysteria2/             # ✨ новый
│       └── ... (та же структура; template содержит ${ALLOW_INSECURE})
│
├── AppFeatures/Sources/MainScreenFeature/
│   └── ConfigImporter.swift
│       # + reparseFromKeychain: + 3 cases
│       # + buildKeychainPayload: + 3 cases
│       # + buildServerConfig: + 3 cases
│       # + provisionTunnelProfile.serverHost switch: + 3 cases
│       # + НОВЫЙ метод: runIsSupportedUpgrade() async — D-14
│
└── (нигде schema migration не требуется — все поля уже есть)
```

### Pattern 1: URI Parser

**What:** Pure Swift enum с `parse(_ uri: String) throws -> Parsed<X>`. Использует `URLComponents`, нет внешних зависимостей.

**When to use:** Любой single-line URI: `ss://`, `hy2://`, `vless://?security=tls`.

**Example (Hysteria2 — новый):**

```swift
// Source: BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift (паттерн)
// + Hysteria2 URI spec: https://v2.hysteria.network/docs/developers/URI-Scheme/

public struct ParsedHysteria2: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let auth: String                  // password (URL-decoded)
    public let sni: String
    public let fingerprint: String?
    public let obfs: String?                 // только "salamander" actually supported
    public let obfsPassword: String?
    public let allowInsecure: Bool           // D-08 exception
    public let pinSHA256: String?
    public let remarks: String?
}

public enum Hysteria2URIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingAuth
    case multiPortNotSupported(String)        // D-09: `123,5000-6000` рejects
    case unsupportedObfs(String)              // не "salamander"
}

public enum Hysteria2URIParser {
    public static func parse(_ uri: String) throws -> ParsedHysteria2 {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              scheme == "hy2" || scheme == "hysteria2",
              let host = comps.host, !host.isEmpty,
              let user = comps.user
        else { throw Hysteria2URIError.malformedURI }

        // D-09: multi-port reject. URLComponents.port == nil if "443,8443" — try parse string.
        let portStr = String(trimmed
            .split(separator: "@", maxSplits: 1).last ?? "")
            .split(separator: "/").first
            .map(String.init) ?? ""
        if portStr.contains(",") || portStr.contains("-") {
            throw Hysteria2URIError.multiPortNotSupported(portStr)
        }
        let port = comps.port ?? 443

        let auth = user.removingPercentEncoding ?? user
        guard !auth.isEmpty else { throw Hysteria2URIError.missingAuth }

        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }

        // D-08 — three URI param synonyms.
        let allowInsecure = ["1", "true", "yes"].contains(
            (q["insecure"] ?? q["allowInsecure"] ?? q["skip-cert-verify"] ?? "0").lowercased()
        )

        // obfs check: только salamander supported в sing-box.
        if let obfs = q["obfs"], !obfs.isEmpty, obfs != "salamander" {
            throw Hysteria2URIError.unsupportedObfs(obfs)
        }

        return ParsedHysteria2(
            host: host, port: port, auth: auth,
            sni: q["sni"] ?? host,
            fingerprint: q["fingerprint"] ?? q["fp"],
            obfs: q["obfs"],
            obfsPassword: q["obfs-password"],
            allowInsecure: allowInsecure,
            pinSHA256: q["pinSHA256"],
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
```

### Pattern 2: Outbound Builder в PoolBuilder

**What:** Один статический private метод `buildXxxOutbound(parsed: ParsedX, tag: String) -> [String: Any]`. Добавляется case в существующий `switch parsed`.

**When to use:** Каждый раз когда добавляется новый `AnyParsedConfig` case.

**Example (Shadowsocks):**

```swift
// Source: BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift (паттерн)
// + sing-box outbound shadowsocks: https://sing-box.sagernet.org/configuration/outbound/shadowsocks/

private static func buildShadowsocksOutbound(parsed: ParsedShadowsocks, tag: String) -> [String: Any] {
    return [
        "type": "shadowsocks",
        "tag": tag,
        "server": parsed.host,
        "server_port": parsed.port,
        "method": parsed.method,        // e.g. "2022-blake3-aes-256-gcm"
        "password": parsed.password,    // base64 для 2022 (32 bytes), произвольная строка для legacy
        "network": "tcp",               // PROTO-04 Phase 4: только TCP; UDP может быть later
    ]
}
```

### Pattern 3: Hysteria2 outbound — единственное исключение R1

```swift
private static func buildHysteria2Outbound(parsed: ParsedHysteria2, tag: String) -> [String: Any] {
    var tls: [String: Any] = [
        "enabled": true,
        "server_name": parsed.sni,
        "insecure": parsed.allowInsecure,   // D-08 — EXCEPTION TO R1 (только для Hy2)
    ]
    if let fp = parsed.fingerprint {
        tls["utls"] = ["enabled": true, "fingerprint": fp]
    }
    if let pin = parsed.pinSHA256 {
        // sing-box accepts certificate_public_key_sha256 (array of base64 hashes).
        // [CITED: sing-box.sagernet.org/configuration/shared/tls — `certificate_public_key_sha256` field].
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

### Pattern 4: Clash YAML Parser

**What:** Загрузить YAML → Swift dictionary → итерировать `proxies` → mapping в `AnyParsedConfig`.

**When to use:** Только в `ClashYAMLParser`, вызывается из `UniversalImportParser.classify` ветка `.clashYAML`.

**Example:**

```swift
// Source: github.com/jpsim/Yams (Yams 6.2.1 — Yams.load API)
// + Clash YAML field reference: https://wiki.metacubex.one/en/config/proxies/

import Yams

public enum ClashYAMLParser {
    public static func parse(_ body: String) throws -> [ImportedServer] {
        guard let root = try Yams.load(yaml: body) as? [String: Any],
              let proxies = root["proxies"] as? [[String: Any]]
        else {
            return []  // proxies: section missing or empty — no servers extracted
        }
        var results: [ImportedServer] = []
        for proxy in proxies {
            guard let type = proxy["type"] as? String,
                  let name = proxy["name"] as? String,
                  let server = proxy["server"] as? String,
                  let port = proxy["port"] as? Int
            else { continue }
            let raw = (try? Yams.dump(object: proxy)) ?? ""
            switch type {
            case "ss":
                if let cipher = proxy["cipher"] as? String,
                   let password = proxy["password"] as? String,
                   isSupportedSSMethod(cipher) {
                    let p = ParsedShadowsocks(host: server, port: port,
                                              method: cipher, password: password,
                                              remarks: name)
                    results.append(.supported(name: name, parsed: .shadowsocks(p), rawURI: raw))
                } else {
                    results.append(.unsupported(name: name, scheme: "ss",
                                                host: server, port: port, rawURI: raw,
                                                reason: .schemaUnsupportedInPhase4))
                }
            case "trojan":
                // ... mapping в ParsedTrojan
            case "vless":
                // если есть "reality-opts" → ParsedVLESS; иначе ParsedVLESSTLS
            case "hysteria2", "hy2":
                // mapping в ParsedHysteria2; skip-cert-verify → allowInsecure
            case "vmess":
                results.append(.unsupported(name: name, scheme: "vmess",
                                            host: server, port: port, rawURI: raw,
                                            reason: .schemaUnsupportedInPhase4))
            default:
                results.append(.unsupported(name: name, scheme: type,
                                            host: server, port: port, rawURI: raw,
                                            reason: .schemaUnsupportedInPhase4))
            }
        }
        return results
    }
}
```

### Anti-Patterns to Avoid

- **❌ Использовать Codable struct для Clash YAML.** Yams Codable требует строгой type-safe schema, но Clash YAML field types варьируются (alpn может быть string или array, port может быть string или int в дикой природе). Использовать `Yams.load` → `[String: Any]` → manual cast — намного устойчивее к real-world YAML.
- **❌ Парсить SS-2022 password как base64 строго.** SIP002 говорит: для AEAD-2022 userinfo MUST NOT быть base64. Парсер должен пробовать (1) split на `:` напрямую (percent-encoded path), (2) base64-decode userinfo и тогда split (legacy path). Не падать на одном из вариантов.
- **❌ Добавлять `tls.insecure: true` в любой outbound кроме Hysteria2.** R1 invariant. Для VLESS-TLS / Trojan / SS — `allowInsecure=1` парсится но игнорируется (как в TrojanURIParser сейчас).
- **❌ Менять `SingBoxConfigLoader.validate`.** Все 3 новых outbound type'а уже в `proxyOutboundTypes` set (verified `SingBoxConfigLoader.swift:69-73`). Изменение validator'а породит regression-риск для Phase 1/2/3 тестов.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML parsing | Custom parser для Clash YAML | **Yams 6.2.1** | YAML 1.2 spec — 100+ страниц, multiline strings, anchors, type tags, flow vs block. Реализовать корректно за месяц нельзя. |
| Base64 decode (URL-safe + padding tolerance) | Custom decoder | Foundation `Data(base64Encoded:options:)` + manual padding adjustment | Already есть в `SubscriptionURLFetcher.decodeBase64` (`StubParsers` / Fixtures) — переиспользовать. |
| URI parsing | Регуларки или string split | `URLComponents` (Foundation) | Уже стандарт во всех существующих парсерах. Корректно обрабатывает percent-encoding, IPv6 in brackets, userinfo escaping. |
| sing-box outbound JSON генерация | Прямая string concatenation | `JSONSerialization.data(withJSONObject:)` через `[String: Any]` | Уже паттерн в `PoolBuilder`. JSONSerialization гарантирует валидный JSON (escape special chars автоматически). |
| sing-box Shadowsocks/Hysteria2 protocol implementation | Реализовать AEAD-2022 / QUIC / Hysteria2 руками | **sing-box engine (libbox)** — нативная поддержка | Phase 1 уже принял libbox. Все 3 outbound type'а работают из коробки. |
| TLS validation / pinning | Реализовать через Network.framework | Делегировать sing-box's `tls.certificate_public_key_sha256` | sing-box делает hash-pin внутри QUIC handshake. |

**Key insight:** Phase 4 — чисто **glue code**: парсеры URI ↔ sing-box JSON. Никакая сетевая логика, никакая криптография, никакая обработка пакетов в Swift не пишется. Это снижает риск bug'ов на 90%.

## Runtime State Inventory

> Phase 4 — feature-expansion, не refactor. Тем не менее есть критичные runtime artefacts.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | SwiftData `ServerConfig` строки с `isSupported=false` + `rawURI != nil` из Phase 2/3 — после deploy Phase 4 их нужно re-evaluate. | D-14 auto-upgrade Task — обязателен в плане; без него существующие пользовательские конфиги останутся «не поддерживается v0.2» навсегда. |
| **Stored data** | SwiftData schema — БЕЗ изменений. Все поля для VLESS-TLS / SS / Hy2 уже есть (`host`, `port`, `protocolID: String`, `keychainTag`, `outboundJSON`, `rawURI`). `protocolID` будет принимать новые значения: `"vless-tls"`, `"shadowsocks"`, `"hysteria2"`. | None — verified в `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` (нет enum restriction на protocolID). |
| **Stored data** | Keychain payload schema — изменяется (новые ключи для VLESS-TLS / SS / Hy2). | `buildKeychainPayload` + `reparseFromKeychain` в `ConfigImporter.swift` расширяются параллельно. Старые VLESS-Reality / Trojan payload'ы остаются совместимы (новые ключи — additive). |
| **Live service config** | None — Phase 4 не трогает external сервисов. | — |
| **OS-registered state** | None — `NETunnelProviderManager.providerConfiguration` обновляется при connect (`provisionTunnelProfile`), сам manager не пересоздаётся. | None. |
| **Secrets/env vars** | `team_id` / `bundle_prefix` — без изменений. SOPS / .env — не задействованы (mobile app). | — |
| **Build artifacts** | SPM `.build/` для ConfigParser package — будет инвалидирован при добавлении Yams dependency (норма). | `swift package resolve && swift build` после правки `Package.swift`. |
| **Build artifacts** | iOS/macOS targets — после добавления Yams в ConfigParser потребуется добавить как transitive dep для Tests; для Production targets — Tuist Project.swift не требует ручной регистрации (SPM resolution автоматический). | Проверить что Tuist resolve видит Yams во всех таргетах, использующих ConfigParser. |
| **App Group / file paths** | sing-box.log path — без изменений (R10). | — |

**Nothing found in category "Live service config" / "OS-registered state":** Verified — Phase 4 чисто app-side feature.

## Common Pitfalls

### Pitfall 1: SIP002 — base64url userinfo vs percent-encoded для SS-2022
**What goes wrong:** Парсер ожидает только base64-encoded `method:password` в `ss://...@host:port`, падает на percent-encoded формате для AEAD-2022 (или vice versa).
**Why it happens:** SIP002 spec [CITED] эволюционировал: legacy ciphers использовали base64url, AEAD-2022 (SIP022) **MUST NOT** использовать base64url (вместо этого — `method:password` percent-encoded прямо в userinfo).
**How to avoid:**
1. Сначала попробовать прямой split: `user.split(separator: ":", maxSplits: 1)` — если получились 2 ненулевые части → percent-decode и проверить, что первая часть в `knownSSMethods` set.
2. Если первая попытка не дала валидного method → попробовать `Data(base64Encoded:)` (с padding tolerance — добавить `=` до длины % 4 == 0) → decode UTF-8 → split на `:`.
3. Оба пути должны давать одинаковую структуру `ParsedShadowsocks`.

**Warning signs:** Если test fixture `ss://2022-blake3-aes-256-gcm:YctP...@host:8388` парсится в supported, но реальный Outline access key `ss://Y2hhY2hh...@host:8388#name` — нет.

### Pitfall 2: Hysteria2 `tls.insecure` обходит R1 — не должно быть случайно применено к другим outbound'ам
**What goes wrong:** Программист копирует hysteria2 outbound builder для следующего протокола → `tls.insecure: parsed.allowInsecure` копируется → теперь Trojan / VLESS тоже allow self-signed → R1 нарушение.
**Why it happens:** Copy-paste код-стиль pool builder'ов.
**How to avoid:**
1. В `buildHysteria2Outbound` поставить большой комментарий-маркер `// R1 EXCEPTION — only Hysteria2 (D-08)` непосредственно над `"insecure":` строкой.
2. Добавить assertion-test: `PoolBuilderTests.test_nonHy2_outbounds_neverHaveInsecureTrue` — итерирует все outbounds в pool, для tag не начинающегося с `hy2-` проверяет `tls.insecure == false`.
3. Wiki R17 — задокументировать как security-decision: «Hysteria2 — единственный outbound type, где `tls.insecure: true` legitimate. Любое другое появление этого поля в pool builder'е — bug».

**Warning signs:** PR-review должен flag'ить любой `outbound["tls"]["insecure"] = parsed.allowInsecure` вне `buildHysteria2Outbound`.

### Pitfall 3: VLESS+TLS branch не должен trigger'иться на Reality URI
**What goes wrong:** `VLESSURIParser.parse` теперь имеет две ветки. Если check для `pbk`/`security=reality` стоит после `security=tls` check — Reality URI ошибочно классифицируется как vlessTLS (потому что Reality URI тоже может содержать `security=reality`, но `security=tls` НЕ содержит).
**Why it happens:** Reality detection логика — два независимых маркера (`pbk` query OR `security=reality`); забыть OR-ить.
**How to avoid:**
1. Branch order: **СНАЧАЛА** проверять Reality (`if q["pbk"] != nil || q["security"] == "reality"` → vlessReality path), **ПОТОМ** vlessTLS (`else if q["security"] == "tls"` → vlessTLS path), **ИНАЧЕ** throw.
2. Test fixture с Reality URI + дополнительно `&security=tls` (некоторые subscription провайдеры так делают) — должен парситься в vlessReality.

**Warning signs:** Существующий тест `VLESSURIParserTests.test_realityWithExtraSecurityTLS` не fail'ится при добавлении tls-ветки.

### Pitfall 4: Clash YAML `alpn` поле — string vs array
**What goes wrong:** Yams возвращает `alpn: "h2,http/1.1"` как `String` для одних YAML файлов и `["h2", "http/1.1"]` как `[String]` для других. Парсер cast'ит as `[String]` → nil → ALPN теряется.
**Why it happens:** Реальные Clash YAML — un-typed; some implementations пишут CSV, some — YAML array.
**How to avoid:** Wrapper-функция в `ClashYAMLParser`:

```swift
private static func parseALPN(_ raw: Any?) -> [String] {
    if let arr = raw as? [String] { return arr }
    if let s = raw as? String {
        return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    return ["h2", "http/1.1"]  // default
}
```

**Warning signs:** Clash YAML fixture парсится, но в результате `alpn` всегда default.

### Pitfall 5: isSupported auto-upgrade race с user import
**What goes wrong:** D-14 Task запускается на foreground, начинает обрабатывать строки с `isSupported=false`. Параллельно пользователь импортирует тот же subscription URL → re-fetch создаёт новые строки → merge → одновременная запись в SwiftData → конфликт.
**Why it happens:** SwiftData ModelContext не designed для concurrent writes без actor isolation.
**How to avoid:**
1. `runIsSupportedUpgrade()` — `async` функция, использует свой `ModelContext` (создаётся в начале метода).
2. Перед каждым `context.save()` — повторно fetch'ить строку по id (она могла быть delete'нута user'ом).
3. Если save throws `.modelContextDataIsStale` — пропустить и продолжить (не блокирующая ошибка).
4. Best-effort семантика: «попробуем upgrade'нуть; если не получилось — следующий запуск попробует снова».

**Warning signs:** Crash в `runIsSupportedUpgrade` после pull-to-refresh.

### Pitfall 6: Hysteria2 multi-port URI парсится как 0
**What goes wrong:** `URLComponents.port` возвращает `nil` для `hy2://auth@host:443,8443/?sni=...`. Парсер делает `port ?? 443` → теряет multi-port intent silently → server подключается на 443 → fail.
**Why it happens:** D-09 решено reject'ить multi-port на Phase 4, но реализация должна **детектить** многопортовый формат, а не fallback на default.
**How to avoid:** До вызова `URLComponents`, regex или string-scan на pattern `@<host>:[0-9,\-]+` — если в port-части присутствуют `,` или `-` → throw `multiPortNotSupported`. Это видно в `Hysteria2URIParser` example выше.

**Warning signs:** Fixture `hy2://auth@host:443,8443/` парсится в supported с `port=443`.

### Pitfall 7: ConfigImporter `serverHost` switch — забыть новые case'ы
**What goes wrong:** `provisionTunnelProfile` берёт первый parsed → `switch parsed { case .vlessReality: ... case .trojan: ... }` — без `default` или новых case'ов компилятор НЕ предупредит (Swift's exhaustiveness check тут не сработает потому что extracted в closure).
**Why it happens:** Существующий код использует `let serverHost: String = { switch parsedList[0] { ... } }()` — без `@unknown default` либо exhaustive enum.
**How to avoid:**
1. `AnyParsedConfig` — public enum в `ConfigParser`. Swift exhaustiveness check работает в switch на public enum. Должен fail на компиляции после добавления 3 case'ов в enum, если switch не обновлён.
2. Добавить test: `ConfigImporterTests.test_provisionForVLESSTLS_extractsHostCorrectly` (плюс 2 аналогичных для ss / hy2).

**Warning signs:** Compile fails в `ConfigImporter.swift:501` после добавления `.shadowsocks` case в enum (это **хороший** signal — означает компилятор поймал missing case).

## Code Examples

### Example 1: VLESS+TLS template (новый файл)

```json
// Source: BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json
// (модификация — убран reality block, оставлен flow placeholder)
// Save to: BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/Resources/SingBoxConfigTemplate.vless-tls.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": { /* same as vless-reality template */ },
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "${SERVER_HOST}",
      "server_port": 443,
      "uuid": "${VLESS_UUID}",
      "flow": "${VLESS_FLOW}",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
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
    "final": "vless-out",
    "auto_detect_interface": true
  },
  "experimental": {}
}
```

### Example 2: Shadowsocks-2022 password handling

```swift
// Source: SIP002 spec — https://github.com/shadowsocks/shadowsocks-org/wiki/SIP002-URI-Scheme

private static let supportedSSMethods: Set<String> = [
    // 2022-blake3 (AEAD-2022, SIP022)
    "2022-blake3-aes-128-gcm",
    "2022-blake3-aes-256-gcm",
    "2022-blake3-chacha20-poly1305",
    // Legacy AEAD
    "aes-128-gcm", "aes-192-gcm", "aes-256-gcm",
    "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
]

public static func parse(_ uri: String) throws -> ParsedShadowsocks {
    let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let comps = URLComponents(string: trimmed),
          comps.scheme?.lowercased() == "ss",
          let host = comps.host, !host.isEmpty,
          let port = comps.port,
          let user = comps.user
    else { throw ShadowsocksURIError.malformedURI }

    let (method, password) = try decodeUserinfo(user)
    guard supportedSSMethods.contains(method) else {
        throw ShadowsocksURIError.unsupportedMethod(method)
    }
    return ParsedShadowsocks(
        host: host, port: port, method: method, password: password,
        remarks: comps.fragment?.removingPercentEncoding
    )
}

/// SIP002 + SIP022 dual-path decoder.
/// - 2022-blake3 methods: userinfo MUST be percent-encoded `method:password`.
/// - Legacy methods: userinfo MAY be base64url(method:password) or percent-encoded.
private static func decodeUserinfo(_ user: String) throws -> (method: String, password: String) {
    // Path 1: try as percent-encoded `method:password`.
    let decoded = user.removingPercentEncoding ?? user
    if let colonIdx = decoded.firstIndex(of: ":") {
        let method = String(decoded[..<colonIdx])
        let password = String(decoded[decoded.index(after: colonIdx)...])
        if supportedSSMethods.contains(method) {
            return (method, password)
        }
    }
    // Path 2: try as base64url (legacy SIP002).
    // Add padding to length % 4 == 0.
    var padded = user
    while padded.count % 4 != 0 { padded.append("=") }
    let base64Std = padded.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
    if let data = Data(base64Encoded: base64Std),
       let s = String(data: data, encoding: .utf8),
       let colonIdx = s.firstIndex(of: ":") {
        let method = String(s[..<colonIdx])
        let password = String(s[s.index(after: colonIdx)...])
        return (method, password)
    }
    throw ShadowsocksURIError.malformedUserinfo
}
```

### Example 3: VLESSURIParser tls-branch addition (D-02)

```swift
// Source: BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift (изменение)
// Pattern: VLESSURIParser.parse — добавить ветку до Reality-only-throw.

public static func parse(_ uri: String) throws -> AnyParsedConfig {
    // ... existing URLComponents extraction ...
    let security = q["security"] ?? ""

    // Phase 4 D-02: Reality detection через pbk OR explicit security=reality.
    let hasReality = (q["pbk"] != nil && !(q["pbk"] ?? "").isEmpty)
                   || security == "reality"

    if hasReality {
        // Existing Phase 1 path → vlessReality
        return .vlessReality(/* existing ParsedVLESS construction */)
    }

    // Phase 4 D-02: TLS branch.
    if security == "tls" {
        let alpn: [String] = (q["alpn"]?.split(separator: ",").map { String($0) }) ?? ["h2", "http/1.1"]
        let parsed = ParsedVLESSTLS(
            uuid: uuid, host: host, port: port,
            flow: q["flow"],          // nil если отсутствует — sing-box примет ""
            sni: q["sni"] ?? host,
            fingerprint: q["fp"] ?? "chrome",
            alpn: alpn,
            networkType: q["type"] ?? "tcp",
            remarks: comps.fragment?.removingPercentEncoding
        )
        return .vlessTLS(parsed)
    }

    // D-02: security=none → throw (handled by UniversalImportParser as failed.invalid).
    throw VLESSURIError.unsupportedSecurity(security)
}
```

**ВАЖНО:** Текущая сигнатура `parse(_:) throws -> ParsedVLESS`. После Phase 4 — `throws -> AnyParsedConfig`. Это **breaking change** для callers. Нужно проверить:

```bash
grep -rn "VLESSURIParser.parse" BBTB/Packages --include="*.swift"
```

Callers: `UniversalImportParser.parseSingleURI` (case "vless"), `VLESSURIParserTests.*`. Обновить оба + 5+ тестов будет.

### Example 4: isSupported auto-upgrade (D-14)

```swift
// Source: BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
// + Pattern: existing `reparseFromKeychain` + `persistKeychainSecret` методы.

/// D-14 — переоценить SwiftData строки с `isSupported=false` через current parsers.
/// Запускается async из AppDelegate.applicationDidBecomeActive (foreground).
/// Best-effort: ошибки логируются, не пробрасываются user'у.
public func runIsSupportedUpgrade() async {
    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.isSupported == false }
    )
    let candidates: [ServerConfig]
    do {
        candidates = try context.fetch(descriptor)
    } catch {
        TunnelLogger.lifecycle.error("runIsSupportedUpgrade: fetch failed: \(error.localizedDescription)")
        return
    }

    var upgradedCount = 0
    for cfg in candidates {
        guard let rawURI = cfg.rawURI, !rawURI.isEmpty else { continue }
        let parser = UniversalImportParser()
        let result: ImportResult
        do {
            result = try await parser.import(rawInput: rawURI, source: .pasteboard)
        } catch {
            continue  // still not parseable
        }
        guard let supported = result.supported.first,
              case let .supported(_, parsed, _) = supported
        else { continue }

        // Re-fetch by id — мог быть удалён user'ом (Pitfall 5 mitigation).
        let id = cfg.id
        let refetchDesc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
        guard let live = try? context.fetch(refetchDesc).first else { continue }

        do {
            let payload = buildKeychainPayload(for: supported)
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let tag = "bbtb-config-\(live.id.uuidString)"
            try KeychainStore.save(data: payloadData, tag: tag)
            live.isSupported = true
            live.keychainTag = tag
            live.protocolID = protocolID(from: parsed)
            live.protocolDisplayName = displayName(from: parsed)
            // Don't store rawURI for supported configs (T-02-04 invariant).
            live.rawURI = nil
            try context.save()
            upgradedCount += 1
        } catch {
            TunnelLogger.lifecycle.error("runIsSupportedUpgrade: upgrade failed for \(live.id): \(error.localizedDescription)")
            continue
        }
    }
    TunnelLogger.lifecycle.info("runIsSupportedUpgrade: upgraded \(upgradedCount)/\(candidates.count) servers")
}

private func protocolID(from parsed: AnyParsedConfig) -> String {
    switch parsed {
    case .vlessReality: return "vless-reality"
    case .vlessTLS:     return "vless-tls"
    case .trojan:       return "trojan"
    case .shadowsocks:  return "shadowsocks"
    case .hysteria2:    return "hysteria2"
    }
}
```

### Example 5: Yams usage для Clash YAML

```swift
// Source: github.com/jpsim/Yams (Yams 6.2.1 — Yams.load API)
import Yams

let yamlString = """
proxies:
  - name: "DE Hysteria2"
    type: hysteria2
    server: example.com
    port: 443
    password: "hy2pass"
    sni: example.com
    skip-cert-verify: true
"""

if let root = try Yams.load(yaml: yamlString) as? [String: Any],
   let proxies = root["proxies"] as? [[String: Any]] {
    for p in proxies {
        print(p["name"] as? String ?? "")  // "DE Hysteria2"
        print(p["type"] as? String ?? "")  // "hysteria2"
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-roll Hysteria2 protocol (Go reference impl) | Use sing-box engine — нативная поддержка `hysteria2` outbound | sing-box v1.5+ (2023) | Phase 4 Just Works™ — JSON outbound с правильными полями. |
| Shadowsocks AEAD legacy (`aes-256-gcm`, `chacha20-ietf-poly1305`) | Shadowsocks-2022 (`2022-blake3-*`) с pre-shared key derivation через BLAKE3 [CITED: shadowsocks.org/doc/sip022.html] | SIP022 spec (2022) | Современные subscription панели генерируют SS-2022 ключи. Legacy остаётся работающим для обратной совместимости. |
| VLESS+Reality (anti-fingerprint TLS hijack) | VLESS+XTLS-Vision (без Reality) для серверов без Reality keypair | Phase 4 (расширение coverage) | Не deprecation; параллельное использование. Reality более устойчив к DPI, но требует server-side rotation pubkey. |
| `hy2://` сокращение | `hysteria2://` — официально preferred с Hysteria 2 docs | 2024 | Поддерживать оба (D-09). |
| Clash subscription → конвертировать в sing-box JSON руками | Native Clash YAML parsing → `AnyParsedConfig` → PoolBuilder → sing-box JSON | Phase 4 IMP-05 finish | Пользователь paste'ит любой формат, не должен знать о разнице. |

**Deprecated/outdated:**
- **Shadowsocks stream ciphers** (`aes-256-cfb`, `rc4-md5`): considered insecure since 2017, не включать в `supportedSSMethods`. Если в URI приходит — `isSupported=false`.
- **`{type: "dns"}` outbound в sing-box** (deprecated in 1.13): уже handled в `SingBoxConfigLoader.expandConfigForTunnel` (R10).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| libbox.xcframework (sing-box engine) | All protocols | ✓ | 1.13.11 | — (engine — фундамент Phase 1+) |
| Swift 6 toolchain | Build | ✓ | iOS 18 SDK / macOS 15 SDK | — |
| Yams Swift package | ClashYAMLParser | ✗ (новое) | 6.2.1 | None — required, SPM resolve добавит. |
| iOS device для UAT | Phase 4 UAT (как Phase 1-3) | ✓ (iPhone) | iOS 18+ | — |
| macOS device для UAT | Phase 4 UAT macOS path | ✓ (Apple Silicon) | macOS 15+ | — |
| Тестовый VLESS-TLS server | UAT — manual proof connectivity | ⚠ User-dependent | — | Если нет — UAT step pending до получения. |
| Тестовый Shadowsocks-2022 server | UAT — manual proof | ⚠ User-dependent | — | Outline-generated key подходит. |
| Тестовый Hysteria2 server | UAT — manual proof | ⚠ User-dependent | — | self-hosted Docker setup (1 ноды достаточно). |

**Missing dependencies with no fallback:**
- Yams 6.2.1 — будет добавлен через `Package.swift` edit + `swift package resolve`. Без него ClashYAMLParser не компилируется.

**Missing dependencies with fallback:**
- Тестовые серверы для трёх новых протоколов — желательны для UAT, но не блокеры для code-completion и юнит-тестов. План должен включать early-warning task: «убедиться, что у пользователя есть тестовые credentials до UAT phase».

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Swift 6) — same as Phase 1/2/3 |
| Config file | Per-package `Package.swift` `.testTarget` |
| Quick run command | `cd BBTB/Packages/ConfigParser && swift test --filter ShadowsocksURIParserTests` |
| Full suite command | `cd BBTB && for pkg in Packages/ConfigParser Packages/Protocols/VLESSTLS Packages/Protocols/Shadowsocks Packages/Protocols/Hysteria2 Packages/AppFeatures; do swift test --package-path "$pkg"; done` |
| Xcode test cmd | `xcodebuild test -workspace BBTB.xcworkspace -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 15'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PROTO-03 | VLESS+TLS without Reality парсится | unit | `swift test --filter VLESSURIParserTLSTests` | ❌ Wave 0 |
| PROTO-03 | vlessTLS outbound builds correctly в pool | unit | `swift test --filter PoolBuilderTests/test_vlessTLS` | ❌ Wave 0 |
| PROTO-03 | sing-box JSON c vless-tls passes `SingBoxConfigLoader.validate` | integration | `swift test --filter IntegrationTests/test_vlessTLS_validates` | ❌ Wave 0 |
| PROTO-04 | SS-2022 base64 SIP002 URI парсится | unit | `swift test --filter ShadowsocksURIParserTests/test_2022_base64` | ❌ Wave 0 |
| PROTO-04 | SS-2022 percent-encoded URI (SIP022) парсится | unit | `swift test --filter ShadowsocksURIParserTests/test_2022_percentEncoded` | ❌ Wave 0 |
| PROTO-04 | Legacy SS (chacha20-ietf-poly1305) парсится | unit | `swift test --filter ShadowsocksURIParserTests/test_legacy_chacha20` | ❌ Wave 0 |
| PROTO-04 | Unknown SS method → unsupported | unit | `swift test --filter ShadowsocksURIParserTests/test_unknownMethod_unsupported` | ❌ Wave 0 |
| PROTO-04 | Outline access key (= SIP002) парсится | unit | `swift test --filter ShadowsocksURIParserTests/test_outlineAccessKey` | ❌ Wave 0 |
| PROTO-05 | Hysteria2 URI парсится с обеими схемами | unit | `swift test --filter Hysteria2URIParserTests/test_bothSchemes` | ❌ Wave 0 |
| PROTO-05 | insecure=1 → allowInsecure=true (D-08) | unit | `swift test --filter Hysteria2URIParserTests/test_insecureFlag` | ❌ Wave 0 |
| PROTO-05 | Multi-port URI → throws | unit | `swift test --filter Hysteria2URIParserTests/test_multiPort_rejects` | ❌ Wave 0 |
| PROTO-05 | obfs=salamander handled correctly | unit | `swift test --filter Hysteria2URIParserTests/test_obfsSalamander` | ❌ Wave 0 |
| PROTO-05 | hy2 outbound builds с tls.insecure: true | unit | `swift test --filter PoolBuilderTests/test_hy2_insecure_passes_through` | ❌ Wave 0 |
| PROTO-05 | non-hy2 outbounds NEVER have tls.insecure: true (R1 invariant) | unit | `swift test --filter PoolBuilderTests/test_nonHy2_outbounds_neverInsecure` | ❌ Wave 0 |
| IMP-04 | UniversalImportParser routes ss / hy2 / vless-tls | integration | `swift test --filter UniversalImportParserTests/test_routes_phase4_protocols` | ❌ Wave 0 |
| IMP-04 | sing-box outbound types {vless, trojan, shadowsocks, hysteria2} все validate | integration | `swift test --filter IntegrationTests/test_allProtocols_validate` | ❌ Wave 0 |
| IMP-05 | Clash YAML parsing extracts proxies | unit | `swift test --filter ClashYAMLParserTests/test_extractsProxies` | ❌ Wave 0 |
| IMP-05 | UniversalImportParser detect Clash YAML format | unit | `swift test --filter UniversalImportParserTests/test_classify_clashYAML` | ❌ Wave 0 |
| IMP-05 | Clash YAML с mixed types (ss + trojan + hy2) → правильно классифицировано | integration | `swift test --filter ClashYAMLParserTests/test_mixedProxies` | ❌ Wave 0 |
| D-14 | isSupported auto-upgrade flips legacy unsupported configs | integration | `swift test --filter ConfigImporterTests/test_runIsSupportedUpgrade` | ❌ Wave 0 |
| D-14 | auto-upgrade is no-op when no rawURI | integration | `swift test --filter ConfigImporterTests/test_runIsSupportedUpgrade_skipsWithoutRawURI` | ❌ Wave 0 |
| D-14 | auto-upgrade survives delete-during-upgrade race | integration | `swift test --filter ConfigImporterTests/test_runIsSupportedUpgrade_handlesDeleteRace` | ❌ Wave 0 |
| UAT-1 | Real VLESS+TLS server connects | manual | Manual on iPhone — `T1_vlessTLS_connect.md` | ❌ Wave UAT |
| UAT-2 | Real SS-2022 server connects | manual | Manual on iPhone — `T2_ss2022_connect.md` | ❌ Wave UAT |
| UAT-3 | Real Hysteria2 server connects (self-signed cert) | manual | Manual on iPhone — `T3_hy2_insecure_connect.md` | ❌ Wave UAT |
| UAT-4 | Auto-failover работает в pool с 4 разными протоколами | manual | Manual — kill primary, observe failover | ❌ Wave UAT |
| UAT-5 | Clash YAML subscription import работает | manual | Manual на iPhone — `T5_clashYAML.md` | ❌ Wave UAT |

### Sampling Rate
- **Per task commit:** `swift test --filter <relevant package>Tests` (< 15s for ConfigParser)
- **Per wave merge:** Full suite через все 4 affected packages (~ 1 min)
- **Phase gate:** Full suite green + iOS device UAT (5 tests) перед `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/ShadowsocksURIParserTests.swift` — covers PROTO-04
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Hysteria2URIParserTests.swift` — covers PROTO-05
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/ClashYAMLParserTests.swift` — covers IMP-05 partial
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTLSTests.swift` — covers PROTO-03 partial
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/ss-2022-aes-128-gcm.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/ss-2022-percent-encoded.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/ss-legacy-chacha20.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/outline-access-key.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/hy2-with-obfs.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/hy2-insecure.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/hy2-multi-port.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-no-flow.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-vision.txt`
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/clash-mixed-proxies.yaml`
- [ ] `BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/ConfigBuilderTests.swift`
- [ ] `BBTB/Packages/Protocols/Shadowsocks/Tests/ShadowsocksTests/ConfigBuilderTests.swift`
- [ ] `BBTB/Packages/Protocols/Hysteria2/Tests/Hysteria2Tests/ConfigBuilderTests.swift`
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/IsSupportedUpgradeTests.swift` — covers D-14
- [ ] Framework install: `swift package resolve` после правки `BBTB/Packages/ConfigParser/Package.swift` (Yams dep)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Shadowsocks PSK (pre-shared key) хранится в Keychain (как Trojan password в Phase 2). Hy2 password — то же. |
| V3 Session Management | no | sing-box engine handles QUIC/TLS sessions. |
| V4 Access Control | no | Single-user mobile app. |
| V5 Input Validation | yes | URI parsers — strict validation. SingBoxConfigLoader.validate — JSON structure. Clash YAML — Yams parsing (LibYAML proven). |
| V6 Cryptography | no | Never hand-roll. sing-box engine + libbox handles all crypto. |
| V10 Malicious Code | yes | Yams — new dependency. Audit: jpsim trusted maintainer, 1.2k stars, MIT, libYAML well-audited C library. |
| V11 Business Logic | yes | R1 — outbound `tls.insecure: true` allowed ONLY for Hysteria2 (D-08). |
| V13 API & Web Service | yes | Subscription URL fetcher (Phase 2) reuse. Body-size cap deferred to Phase 7 (W-02-09 carry-forward). |
| V14 Configuration | yes | sing-box `experimental: {}` empty — already validated. |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious subscription serves YAML with embedded shell strings | Tampering | Yams `load` returns `Any`, not Codable; no code execution path. URLs/paths from YAML never `Process.run`'d. |
| Subscription claims `type: vless` but `reality-opts` malformed → crash | DoS | `ClashYAMLParser` per-proxy try/catch — bad proxy → `.unsupported`, не throws на весь YAML. |
| User pastes Hysteria2 URI with `insecure=1` pointing to attacker server | Spoofing | **Accepted risk (D-08):** обусловлено реальностью self-hosted Hy2 setups. Mitigation: UI warning при импорте Hy2-insecure config? — vNext (Phase 11 UX polish). На Phase 4 — silent (user-trust model). |
| `pinSHA256` параметр невалидный → false sense of security | Authentication | Pin invalid → sing-box handshake fails → no connection (fail-safe). |
| SS-2022 URI с очень коротким password (< 16 bytes) для AEAD-2022 | Cryptographic | sing-box validates key length при handshake → fail. Parser НЕ validate'ит длину (полагаемся на engine). Risk: silent fail при connect; mitigation: UI error message при connect failure. |
| Clash YAML с recursion / anchors → infinite parse | DoS | LibYAML имеет встроенный depth limit. Yams 6.2.1 exposes default. |
| Unknown URI scheme passes как `isSupported=false` → пользователь видит мусор | Repudiation | UI shows `protocolDisplayName` = `"X (не поддерживается v0.4)"` — clear feedback. |
| User imports thousands of configs → SwiftData/Keychain bloat | DoS | `PoolBuilder.buildSingBoxJSON` capped at 50 outbounds (Phase 2 RESEARCH §9.5). SwiftData — limited by device disk. No hard cap on Phase 4. |

**Security audit:** Phase 4 carry-forward — wiki R17 (новая) должна задокументировать:
1. Hysteria2 `tls.insecure` exception (D-08).
2. Yams dependency provenance (jpsim, MIT, audit status).
3. R1 invariant test (`PoolBuilderTests.test_nonHy2_outbounds_neverInsecure`).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | sing-box 1.13.11 accepts `flow: ""` (empty string) для VLESS без Vision | Code Examples (vless-tls template) | Если sing-box rejects empty flow → нужно `flow` field вообще убрать из JSON при `parsed.flow == nil`. Mitigation: integration test `IntegrationTests.test_vlessTLS_emptyFlow_validates` обнаружит. [ASSUMED] |
| A2 | sing-box `certificate_public_key_sha256` принимает base64-encoded SHA256 hashes (как massive [String]) | Hysteria2 outbound builder | Если ожидается hex или Data — pinSHA256 не работает. На Phase 4: НЕ блокирует основной flow; pinSHA256 — optional URI param. Mitigation: integration test или просто не support'ить pinSHA256 на Phase 4 (defer to Phase 10 security polish). [ASSUMED] |
| A3 | iOS NEPacketTunnel extension не имеет дополнительных restrictions на UDP QUIC handshake для Hysteria2 (Phase 1 testing only validated TCP) | UAT | Если UDP-blocked в extension sandbox → Hy2 не работает на iOS. Известный риск Phase 1 не покрыл. Mitigation: early UAT — connect к Hy2 серверу как первый шаг Phase 4 testing. [ASSUMED] |
| A4 | Outline access keys — это **только** SIP002 `ss://` (не `ssconf://` JSON) для типичных Outline-сгенерированных ключей | Standard Stack | Если Outline начал выдавать `ssconf://` по дефолту в 2026 → IMP-05 не покрывает Outline полностью. Verification: попросить пользователя сгенерировать тестовый Outline access key и проверить формат. [ASSUMED] |
| A5 | Существующие SwiftData rows с `isSupported=false` имеют корректный `rawURI` (не nil, не пустой) | Runtime State Inventory | Если Phase 2/3 не всегда заполняли rawURI → auto-upgrade пропустит часть rows. Verification: SQL-fetch (через debug Xcode) на iPhone — count rows where rawURI IS NULL AND isSupported = 0. [ASSUMED] |
| A6 | Yams 6.2.1 не требует exception handling для broken YAML (returns nil вместо throw) | Pattern 4 (Clash YAML) | Если throws — нужен try/catch. Уже учтено в example code (`try Yams.load`). Mitigation: тест `ClashYAMLParserTests.test_brokenYAML_returnsEmpty`. [VERIFIED: Yams API uses `throws`] — A6 actually verified, not assumed. |
| A7 | sing-box 1.13.11 supports `obfs.type: salamander` для Hysteria2 outbound | Pattern 3 (Hy2 builder) | Если salamander не реализован — `obfs` поле в outbound вызовет engine error. [CITED: sing-box.sagernet.org/configuration/outbound/hysteria2 — obfs field, only salamander] — это CITED, not assumed. |

**Total assumptions requiring user confirmation:** A1, A2, A3, A4, A5 (5 items). Все они — не блокеры для планирования, но должны быть на early UAT-list для Phase 4.

## Open Questions

1. **Тестовые серверы для UAT — есть ли у пользователя?**
   - What we know: Phase 1-3 UAT успешно прошли на пользовательском VLESS-Reality + Trojan сервере (vergevsky.ru).
   - What's unclear: Есть ли у пользователя VLESS-TLS (без Reality) сервер? Shadowsocks-2022 сервер? Hysteria2 сервер?
   - Recommendation: Перед планированием уточнить в discuss-phase, иначе UAT step имеет блокер на «получить тестовые credentials» (может быть Outline access key для SS-2022 — generated в Outline app, и Docker self-host Hy2 — 30 min setup).

2. **Phase 11 UX backlog — выводить ли warning при импорте Hy2 с `insecure=1`?**
   - What we know: D-08 принимает insecure=1 без warning (silent — user-trust model).
   - What's unclear: Не противоречит ли это «помоги пользователю не выстрелить себе в ногу» UX-принципу.
   - Recommendation: На Phase 4 — silent (D-08). Записать в `.planning/STATE.md` blockers как Phase 11 UX-task: «UI warning при импорте Hy2-insecure».

3. **isSupported auto-upgrade — частота?**
   - What we know: D-14 говорит «при foreground» — то есть applicationDidBecomeActive.
   - What's unclear: Это запускается каждые секунды если user быстро переключается? Throttling нужен?
   - Recommendation: Throttle на 1 раз / 5 минут через UserDefaults timestamp. Если последний запуск < 5min назад — skip. Дешёво и достаточно (rare event).

4. **ConfigImporter — где регистрируется новые protocol handler'ы в ProtocolRegistry?**
   - What we know: ProtocolRegistry существует (Phase 1 CORE-02). Trojan / VLESS-Reality зарегистрированы.
   - What's unclear: Где конкретно происходит registration (в `App.swift`? `AppDelegate`? init в каком-то синглтоне?).
   - Recommendation: При планировании Phase 4 проверить `grep -rn "ProtocolRegistry" BBTB/` — найдётся registration point, добавить туда 3 новых handler'а.

## Sources

### Primary (HIGH confidence)

- **sing-box official docs:**
  - [Shadowsocks outbound](https://sing-box.sagernet.org/configuration/outbound/shadowsocks/) — fields: type, server, server_port, method, password, plugin, network. Verified.
  - [Hysteria2 outbound](https://sing-box.sagernet.org/configuration/outbound/hysteria2/) — fields: server, server_port, password, obfs, tls, network. Verified.
  - [Shared TLS configuration](https://sing-box.sagernet.org/configuration/shared/tls/) — fields: enabled, server_name, insecure, alpn, utls, certificate_public_key_sha256.

- **Hysteria2 URI scheme spec:**
  - [v2.hysteria.network/docs/developers/URI-Scheme](https://v2.hysteria.network/docs/developers/URI-Scheme/) — query params: obfs, obfs-password, sni, insecure, pinSHA256. Scheme aliases hy2 / hysteria2.

- **SIP002 spec:**
  - [github.com/shadowsocks/shadowsocks-org/wiki/SIP002-URI-Scheme](https://github.com/shadowsocks/shadowsocks-org/wiki/SIP002-URI-Scheme) — userinfo encoding: base64url (legacy) vs percent-encoded (AEAD-2022).

- **SIP022 (AEAD-2022) spec:**
  - [shadowsocks.org/doc/sip022.html](https://shadowsocks.org/doc/sip022.html) — key length requirements: 16/32/32 bytes для aes-128-gcm / aes-256-gcm / chacha20-poly1305.

- **Clash YAML field reference:**
  - [wiki.metacubex.one/en/config/proxies/vless](https://wiki.metacubex.one/en/config/proxies/vless/) — VLESS YAML fields.
  - [wiki.metacubex.one/en/config/proxies/hysteria2](https://wiki.metacubex.one/en/config/proxies/hysteria2/) — Hysteria2 YAML fields.
  - [wiki.metacubex.one/en/config/proxies/ss](https://wiki.metacubex.one/en/config/proxies/ss/) — Shadowsocks YAML fields.

- **Existing codebase (canonical references — read before planning):**
  - `BBTB/Packages/ConfigParser/Sources/ConfigParser/{ImportedServer.swift, UniversalImportParser.swift, PoolBuilder.swift, VLESSURIParser.swift, TrojanURIParser.swift, StubParsers.swift, ConfigImporting.swift}`
  - `BBTB/Packages/Protocols/Trojan/{Package.swift, Sources/Trojan/{TrojanHandler.swift, ConfigBuilder.swift}, Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json}`
  - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` (line 69-73 — verified `shadowsocks` + `hysteria2` уже whitelisted)
  - `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` (schema — no change needed)
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (reparseFromKeychain, buildKeychainPayload — паттерн для D-14)

### Secondary (MEDIUM confidence)

- **Yams Swift YAML parser:**
  - [github.com/jpsim/Yams](https://github.com/jpsim/Yams) — version 6.2.1 (2026-02-05), MIT, Swift 5.7+. Verified via GitHub releases page.

- **Hysteria2 URI parameters extended list:**
  - WebSearch summary через v2.hysteria.network — `alpn`, `fingerprint` упоминаются в некоторых third-party docs, но не в official URI spec. Использовать с осторожностью.

### Tertiary (LOW confidence)

- **Leadaxe singbox-launcher ParserConfig docs** — упомянуто в CONTEXT.md `<canonical_refs>` как эталонная спецификация. URL [github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md] not fully accessible (raw fetch returned partial); for production Phase 4 implementation — рекомендуется prep'er загрузить repo, прочитать docs/ParserConfig.md полностью и портировать edge cases.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — sing-box engine выбран в Phase 1, все 3 новых outbound type'а нативно supported.
- Architecture: HIGH — Phase 4 строго копирует паттерны Phase 2 (Trojan). Никаких новых архитектурных решений.
- Pitfalls: MEDIUM — SS-2022 userinfo dual-encoding (Pitfall 1) и VLESS branching (Pitfall 3) — реальные риски, нужно strict test coverage.
- D-14 auto-upgrade: MEDIUM — race condition (Pitfall 5) и pattern совместимости с существующим `reparseFromKeychain` — есть, но требуют осторожной реализации.
- Yams dependency: HIGH — verified 6.2.1, MIT, активный maintainer.

**Research date:** 2026-05-12
**Valid until:** 2026-06-12 (30 days — sing-box релизы обычно раз в 2-3 месяца; Hysteria2 spec стабилен с 2024).
