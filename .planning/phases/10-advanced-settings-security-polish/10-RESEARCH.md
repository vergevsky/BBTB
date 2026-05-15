# Phase 10: Advanced settings + Security polish — Research

**Researched:** 2026-05-15
**Domain:** SwiftUI Advanced Settings UI / sing-box 1.13 config injection (Mux + STUN-block + CDN overlay) / URLSession SPKI pinning / macOS NETunnel `enforceRoutes` toggle
**Confidence:** HIGH (existing-code findings) + HIGH (sing-box docs verified) + MEDIUM (CDN-fronting mapping — verified by Codex thread but Cloudflare classic fronting blocked since 2015)
**Mode:** mvp
**Phase:** 10

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area A — Scope amendment (D-01..D-02):**
- BIO-01..04 (Face ID / Touch ID) **→ deferred**. Нет use case для friends-and-family TestFlight аудитории. Возврат — отдельная фаза при наличии 3+ запросов.
- ONDEMAND-01 («только в публичных Wi-Fi») **→ deferred**. Нет надёжного способа определить публичность сети без manual SSID whitelist. Текущий `NEOnDemandRuleConnect(.any)` достаточен.

**Area B — CDN-фронтинг архитектура (D-03..D-07):**
- **D-03:** `FrontingProfile` — отдельный слой, **не часть TransportConfig** (Codex thread `019e2b02-09fc-77b1-8acc-cc4f794c5235`). Структура:
  ```swift
  struct FrontingProfile: Codable, Sendable {
      let provider: CDNProvider       // .cloudflare, .fastly, .custom
      let connectHost: String         // CDN IP или домен (dial target)
      let connectPort: Int            // обычно 443
      let sniHost: String             // fronted hostname (для TLS)
      let httpHost: String            // Host/:authority header
      let mode: FrontingMode          // .domain, .ipPool, .remoteSigned
  }
  ```
- **D-04:** `CDNProviderAdapter` protocol — CloudflareAdapter / FastlyAdapter / CustomCDNAdapter. `FrontingConfigApplier` поверх TransportHandler меняет `server`, `tls.server_name`, `Host`.
- **D-05:** sing-box 1.13.11 CDN mapping. Для WS: `transport.headers.Host = frontingHost`. Для HTTPUpgrade: `transport.host = frontingHost`. Для gRPC: `tls.server_name = frontingHost`. Поле outbound `server` → CDN IP/domain. **НЕ применять** к Reality / TUIC / Hysteria2.
- **D-06:** CDN fallback chain: domain mode → IP pool (разные ASN) → другой CDN provider → direct Reality/Vision профиль → следующая нода из подписки. Failure score по `(provider, ip, networkType)` в App Group JSON. Cooldown 6-24ч.
- **D-07:** CDN toggle — глобальный в Advanced Settings. Применяется ко всем серверам с `frontingProfile` в подписке.

**Area C — Mux (D-08..D-10):**
- **D-08:** Mux — двойной контроль. Auto: URI `mux=true` или Clash YAML `smux: {enabled: true}` → включается для сервера. Глобальный toggle в Advanced Settings → Anti-DPI — принудительно для всех совместимых серверов.
- **D-09:** **Протокольный whitelist**. Mux ВКЛЮЧАТЬ ТОЛЬКО для: VLESS+TLS (без Reality/Vision), Trojan, Shadowsocks-2022. ЗАПРЕЩЕНО для: Reality, Vision (XTLS собственный механизм), TUIC, Hysteria2 (QUIC уже multiplexed). `SingBoxConfigLoader` проверяет протокол перед инъекцией `multiplex.*`.
- **D-10:** Mux default тип — `smux`. При включении: `multiplex.protocol = "smux"`, `multiplex.max_connections = 4`, `multiplex.padding = true` (это DPI-03 per-packet padding). Picker smux/yamux/h2mux отложен на v1.x.

**Area D — Cert Pinning (D-11..D-14):**
- **D-11:** `URLSessionDelegate` custom + SPKI SHA-256 pin (без сторонних библиотек). Пинируем публичный ключ (SPKI), не сертификат — переживает перевыпуск Let's Encrypt на том же ключе.
- **D-12:** Хранение пинов — bootstrap (hardcoded) + remote Ed25519 manifest (`subscription-pins.json`, аналог rules.json). Manifest: `validFrom`, `validUntil`, `host`, `spkiSha256Pins`, `backupPins`, `version`.
- **D-13:** Cert pinning scope — **только subscription URL (SubscriptionURLFetcher)**. Rules.json уже Ed25519-protected. PacketTunnel extension НЕ делает URLSession — pinning только в main app.
- **D-14:** Cert pinning **включён по умолчанию**, toggle виден в Advanced Settings → Безопасность.

**Area E — Advanced Settings экран (D-15..D-17):**
- **D-15:** Структура экрана v0.10 — 4 именованных секции в Form:
  ```
  // 1. MinAppVersionBanner (conditional, Phase 8 — top)
  // 2. DNS (Phase 6, existing) — AdBlock + Custom DNS
  // 3. Anti-DPI (Phase 10, NEW) — CDN toggle / Mux toggle / uTLS picker / STUN-блок
  // 4. Безопасность (Phase 10, NEW) — Cert pinning toggle / macOS enforceRoutes toggle
  // 5. Rules (Phase 8, existing) — RulesViewerSection + ForceUpdateRulesButton
  ```
- **D-16:** STUN-блок — **выкл по умолчанию**, с предупреждением. Footer: «Сломает видеозвонки в браузере (Google Meet, Zoom). Не влияет на нативные приложения.» Блокирует UDP 3478 + 5349 через sing-box `route.rules` reject.
- **D-17:** macOS `enforceRoutes` toggle — **macOS only**, секция «Безопасность». Default: `on` (текущий `enforceRoutes=true`). Footer: «Выкл = трафик идёт напрямую если VPN упал. Безопаснее держать включённым.» Только `#if os(macOS)`. iOS игнорируется (iOS 26 принудительно ставит `includeAllNetworks`).

### Claude's Discretion

- uTLS picker options — выбрать из sing-box 1.13.11 supported fingerprints. _RECOMMENDATION (см. §State of the Art):_ `random` (default) + `chrome` + `firefox` + `safari` + `ios` + `android` + `edge`. Доступны также `360` и `qq`, но они brand-specific (Chinese vendor) — не имеют смысла в UI русскоязычного клиента.
- `CDNProviderAdapter` конкретные реализации: CloudflareAdapter + FastlyAdapter + CustomCDNAdapter. IP pool JSON schema — на усмотрение.
- Mux picker type (smux/yamux/h2mux) — в v0.10 smux default, picker откладывается на v1.x.
- Порядок секций внутри Anti-DPI и Безопасность — на усмотрение, выше D-15.
- Pin manifest `validUntil` enforcement policy — **рекомендую hard reject** (соответствует rules.json pipeline).

### Deferred Ideas (OUT OF SCOPE)

- **BIO-01..04** (Face ID / Touch ID) — deferred. Нет use case для friends-and-family.
- **ONDEMAND-01** («только в публичных Wi-Fi») — deferred. Manual SSID list для v1.x.
- **Mux picker (smux/yamux/h2mux)** — smux по умолчанию достаточно. Picker → v1.x.
- **NET-12** (active liveness probe) — повторный carry-out, Phase 11+.
- **Config editor / Network diagnostics** — упомянуты в UX-06 spec, Phase 11+.
- **CDN IP pool remote sync** — в v0.10 IP может быть статичным из bundle. Remote signed IP pool → v1.x если Cloudflare anycast начнёт блокироваться в РФ.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **UX-06** | Полный Advanced Settings экран — 4 секции (DNS / Anti-DPI / Безопасность / Rules) | §Architecture: AdvancedSettingsView пересборка по D-15 + 4 новых toggle/picker UI |
| **DPI-05** | Mux per-server + global toggle (smux, max_connections=4, padding=true) | §Code Examples: `multiplex` injection в `SingBoxConfigLoader.expandConfigForTunnel`, protocol whitelist enforcement |
| **DPI-06** | CDN-фронтинг toggle — глобальный | §Standard Stack: `FrontingProfile` отдельный слой; §sing-box mapping: WS headers.Host / HTTPUpgrade host / gRPC sni |
| **DPI-08** | Certificate pinning — subscription URL endpoint | §Code Examples: `URLSessionDelegate` + SPKI SHA-256 в Swift; §State of the Art: SecTrustCopyKey + SecKeyCopyExternalRepresentation |
| **DPI-09** | uTLS fingerprint picker в UI | §State of the Art: sing-box supports chrome/firefox/edge/safari/360/qq/ios/android/random/randomized |
| **BIO-04** | Тоггл «Блокировать STUN-трафик» (WebRTC leak protection) | §Pitfalls: sing-box 1.13 НЕ имеет `protocol: "stun"` matcher; используем `port: [3478, 5349]` + `network: "udp"` + `action: "reject"` |
| **KILL-04** | macOS `enforceRoutes=false` toggle | §Code Examples: `PlatformHooks.shouldDisableEnforceRoutes()` уже wired (Phase 1 placeholder); меняем impl + `KillSwitch.platformShouldDisableEnforceRoutes()` |

**Out-of-scope per CONTEXT D-01/D-02:** BIO-01/02/03 (Face ID UI lock), ONDEMAND-01 (Wi-Fi SSID rules).
</phase_requirements>

---

## Summary

Phase 10 = последний шаг к feature-complete клиенту перед onboarding (Phase 11) и TestFlight (Phase 12). Все 7 фич — это **расширения существующих систем**, не новые подсистемы:

1. **Mux/STUN-block** = новые JSON-инъекции в `SingBoxConfigLoader.expandConfigForTunnel` (уже расширен Phase 8 W5 для rule_set).
2. **CDN-фронтинг** = новый слой `FrontingConfigApplier` поверх transport (Codex-validated архитектура; Cloudflare classic domain fronting заблокирован 2015 — современная схема = «свой домен, направленный на CDN»).
3. **Cert pinning** = URLSession delegate с SPKI SHA-256 (pure-Apple stack: `SecTrustCopyKey` + `SecKeyCopyExternalRepresentation` + `CryptoKit.SHA256`).
4. **uTLS picker** = UI над уже существующим `fingerprint` полем в `VLESSURIParser` / `TrojanURIParser`.
5. **macOS enforceRoutes** = убрать заглушку `false` в `PlatformHooks.shouldDisableEnforceRoutes()` + сделать `KillSwitch.platformShouldDisableEnforceRoutes()` читать `@AppStorage`.
6. **Advanced Settings экран** = реструктуризация существующего `AdvancedSettingsView` (Form секций сейчас 4, станет 5 с явными названиями).

**Primary recommendation:** все 7 toggle/picker — в существующий `SettingsViewModel` + `@AppStorage` (паттерн уже в коде: `killSwitchEnabled`, `customDNS`, `adBlockEnabled`, `autoReconnectEnabled`). **НЕ создавать `AdvancedSettingsStore`** как отдельный класс (упомянут в CONTEXT — но в кодовой базе его нет; @AppStorage в VM = устоявшийся паттерн). **CDN — отдельный SwiftPM пакет `FrontingEngine`** по паттерну `RulesEngine` (actor + protocol + Ed25519 pin manifest + AppGroup cache). **Cert pinning — pure Swift в ConfigParser** (single PinnedSessionDelegate класс), без отдельного пакета — он используется ровно в одном месте (SubscriptionURLFetcher).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Mux toggle UI + state | App / SettingsFeature | — | `@AppStorage` mux toggle drives PoolBuilder/SingBoxConfigLoader inject. UI-only concern at app layer. |
| Mux JSON injection | Extension / PacketTunnelKit (SingBoxConfigLoader) | App / ConfigParser (PoolBuilder может pre-inject) | `expandConfigForTunnel(_:)` — единственная точка перед `LibboxNewCommandServer.start`. Альтернатива — inject в PoolBuilder, но это размывает Phase 8 паттерн. **Recommend: SingBoxConfigLoader** (читает `@AppStorage` через UserDefaults в App Group). |
| STUN-block route.rule injection | Extension / PacketTunnelKit | — | Same as Mux — `expandConfigForTunnel` injects `route.rules` entry. |
| CDN dial-target override | App / новый `FrontingEngine` пакет | Extension / PacketTunnelKit (применяет JSON overlay) | `FrontingConfigApplier` решает on connect attempt какой profile применить (включая fallback chain). App layer держит state. Extension получает уже модифицированный JSON через configJSON. |
| CDN failure score cache | App / `FrontingEngine` | Shared / App Group JSON | App-side writer + reader. Extension не пишет (только читает если потребуется in-flight failover — но Phase 10 v0.10 это вне scope). |
| Cert pinning (subscription URL) | App / ConfigParser (SubscriptionURLFetcher) | — | URLSession живёт **только в main app** (R1 — extension не делает HTTP). Pinned delegate wraps URLSession. |
| Pin manifest fetch + Ed25519 verify | App / новый `SubscriptionPinManager` либо переиспользовать RulesEngine pipeline | — | Аналог `RulesEngineCoordinator` для subscription-pins.json. |
| uTLS picker UI | App / SettingsFeature | — | `@AppStorage` value прокидывается через `PoolBuilder` в `outbound.tls.utls.fingerprint`. |
| uTLS picker application | App / ConfigParser (PoolBuilder) либо Extension / SingBoxConfigLoader | — | PoolBuilder уже строит outbounds — естественная точка override `fingerprint` if user picked non-default. |
| macOS enforceRoutes toggle UI | App / SettingsFeature | — | `@AppStorage` в `SettingsViewModel` (only `#if os(macOS)`). |
| macOS enforceRoutes apply | App / KillSwitch + PacketTunnelKit / PlatformHooks | — | `KillSwitch.platformShouldDisableEnforceRoutes()` читает UserDefaults. Уже wired (Phase 1 заглушки). Меняем 2 impl — на macOS читать @AppStorage. |

## Standard Stack

### Core (already in codebase — verified)

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| sing-box / libbox | 1.13.11 | Tunnel engine | [VERIFIED: BBTB existing — phase 7c boundary cleanup] Уже используется; все 7 фич = JSON-extension существующего конфига. |
| SwiftUI Form / Section | iOS 18 / macOS 15 | UI layout для Advanced Settings | [VERIFIED: AdvancedSettingsView.swift current] Phase 6 + 8 паттерны: Section/header/footer text. |
| `@AppStorage` (SwiftUI) | iOS 18 | Persistent toggle state | [VERIFIED: SettingsViewModel.swift] `killSwitchEnabled`, `customDNS`, `adBlockEnabled`, `autoReconnectEnabled` — устоявшийся паттерн. |
| `URLSession` + `URLSessionDelegate` | Foundation (system) | HTTP fetch + pinning hook | [CITED: developer.apple.com/documentation/foundation/urlsessiondelegate] `urlSession(_:didReceive:completionHandler:)` — официальная точка для server-trust validation. |
| `CryptoKit.SHA256` (re-exported by swift-crypto 4.x) | swift-crypto 4.0.0..<5.0.0 | SPKI hash compute | [VERIFIED: RulesEngine/Package.swift line 37] swift-crypto уже в проекте, на Apple platforms = re-exports CryptoKit (zero binary cost). |
| `Security.framework` (SecTrust*, SecKey*) | system | Extract server certificate + public key | [CITED: developer.apple.com/documentation/security/sectrust] `SecTrustCopyKey` (iOS 14+) + `SecKeyCopyExternalRepresentation` — official APIs. |

### Supporting (new for Phase 10)

| Component | Where | Purpose | Notes |
|-----------|-------|---------|-------|
| `FrontingProfile` struct | `VPNCore` (or new `FrontingEngine` package) | CDN dial-target schema | Codable; lives in subscription payload (Marzban delivers с `frontingProfile` blob). |
| `CDNProviderAdapter` protocol | new `FrontingEngine` package | Cloudflare/Fastly/Custom adapter dispatch | Аналог `TransportHandler` protocol в `TransportRegistry`. |
| `FrontingConfigApplier` | new `FrontingEngine` package | JSON overlay над `expandConfigForTunnel` output | Mutates `outbound.server` / `outbound.tls.server_name` / `transport.headers.Host`. |
| `PinnedSessionDelegate` | `ConfigParser/Sources/ConfigParser/` | URLSession SPKI matcher | Single class. NSObject + URLSessionDelegate. ~80-150 строк. |
| `SubscriptionPinManager` actor | new (либо в ConfigParser, либо вынести) | Bootstrap pins + remote pin manifest | Аналог `RulesEngineCoordinator`. Ed25519 verify через swift-crypto (reuse). |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom `PinnedSessionDelegate` | `TrustKit` (open-source SPKI pinning lib) | TrustKit — battle-tested но добавляет dep на проект где сейчас только swift-crypto. D-11 в CONTEXT явно: «**Без сторонних библиотек**». Custom delegate ~120 строк — manageable. |
| `FrontingEngine` пакет | CDN логика в `ConfigParser` / `PacketTunnelKit` | Package boundary cleaner; будущее (50+ транспортов, 5+ CDN providers) — testable изолированно. **Recommend: new package** по паттерну RulesEngine. |
| `@AppStorage` для toggles | Custom `AdvancedSettingsStore` actor | `AdvancedSettingsStore` упомянут в CONTEXT canonical_refs, но **в коде такого класса нет** — все toggles в `SettingsViewModel` через @AppStorage. Не создавать без причины: лишний layer. |
| Server-side STUN block (DNS) | sing-box `route.rules` | Server side требует rules.json update + DPI tests; client-side `route.rules` reject — мгновенный effect, не нагружает rules pipeline. |

**Installation (new for Phase 10):**

```bash
# Никаких новых внешних SwiftPM deps не требуется.
# swift-crypto уже в RulesEngine (4.0.0..<5.0.0) — переиспользуем для pin manifest verify.

# Новый локальный пакет:
mkdir -p BBTB/Packages/FrontingEngine/{Sources/FrontingEngine,Tests/FrontingEngineTests}
# Package.swift по образцу RulesEngine/Package.swift
```

**Version verification (existing deps confirmed):**

```bash
# Уже подтверждено через grep в Package.swift файлах:
# - swift-crypto 4.0.0..<5.0.0  (RulesEngine/Package.swift:37)
# - libbox xcframework 1.13.11   (PacketTunnelKit, Phase 7c)
# - swift-tools-version: 6.0     (все пакеты)
```

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Main App (App Layer)                                 │
│                                                                             │
│  AdvancedSettingsView (4-section Form, D-15)                                │
│       │                                                                     │
│       ├── DNS Section (Phase 6, existing)                                   │
│       ├── Anti-DPI Section (NEW)                                            │
│       │     ├── CDN toggle  ──┐                                             │
│       │     ├── Mux toggle  ──┤                                             │
│       │     ├── uTLS picker ──┤                                             │
│       │     └── STUN toggle ──┤                                             │
│       ├── Безопасность Section (NEW)                                        │
│       │     ├── Cert pinning toggle ──┐                                     │
│       │     └── #if os(macOS) enforceRoutes toggle ─┐                       │
│       └── Rules Section (Phase 8, existing)                                 │
│                                                                             │
│  SettingsViewModel (+ new @AppStorage props):                               │
│   - cdnFrontingEnabled, muxEnabled, stunBlockEnabled, certPinningEnabled,   │
│   - utlsFingerprint, enforceRoutesMacOS (macOS only)                        │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐           │
│  │ ConfigImporter.provisionTunnelProfile(...)                   │           │
│  │   1. PoolBuilder.buildSingBoxJSON(...) ── applies utlsFingerprint        │
│  │   2. FrontingConfigApplier.apply(json, profile) [if CDN ON] │           │
│  │   3. KillSwitch.apply(to: proto, enabled: ks) ─ reads macOS enforceRoutes
│  │   4. proto.providerConfiguration["configJSON"] = singBoxJSON│           │
│  │   5. manager.saveToPreferences()                            │           │
│  └─────────────────────────────────────────────────────────────┘           │
│                                                                             │
│  SubscriptionURLFetcher.fetch(url) ── wraps URLSession with PinnedDelegate  │
│       │                                                                     │
│       └─→ PinnedSessionDelegate.urlSession(_:didReceive:completionHandler:) │
│            ├── SecTrustGetCertificateAtIndex                                │
│            ├── SecCertificateCopyKey                                        │
│            ├── SecKeyCopyExternalRepresentation                             │
│            ├── SHA256.hash(data: spkiData)                                  │
│            └── Compare to PinStore.currentPins (bootstrap + manifest)       │
│                                                                             │
│  SubscriptionPinManager (actor, аналог RulesEngineCoordinator)              │
│    - bootstrap(): hardcoded pins из bundle                                  │
│    - performBackgroundRefresh(): fetch subscription-pins.json + Ed25519     │
│    - currentPins(): merged (bootstrap ∪ remote, dedupe)                     │
│       │                                                                     │
│       └─→ App Group: {AppGroup}/Library/Caches/pins/subscription-pins.json  │
│                                                                             │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │
                           │ XPC (NETunnelProviderProtocol.providerConfiguration)
                           │
┌──────────────────────────▼──────────────────────────────────────────────────┐
│                    PacketTunnel Extension                                   │
│                                                                             │
│  BaseSingBoxTunnel.startTunnel(options:)                                    │
│       │                                                                     │
│       ▼                                                                     │
│  SingBoxConfigLoader.expandConfigForTunnel(json:)                           │
│       ├── (existing) TUN inbound + DNS hijack + rule_set (Phase 8)          │
│       ├── (NEW) STUN block route.rule [if stunBlockEnabled]                 │
│       │     {"port":[3478,5349],"network":"udp","action":"reject"}          │
│       └── (NEW) Mux injection per outbound (whitelist VLESS+TLS/Trojan/SS) │
│              outbound.multiplex = {                                         │
│                "enabled": true, "protocol": "smux",                         │
│                "max_connections": 4, "padding": true                        │
│              }                                                              │
│                                                                             │
│  TunnelSettings.makeR6Safe(...) — unchanged                                 │
│                                                                             │
│  PlatformHooks.shouldDisableEnforceRoutes() ── reads @AppStorage on macOS   │
└─────────────────────────────────────────────────────────────────────────────┘
```

Data-flow primary use-case (CDN-фронтинг ON, Mux auto, pinning ON):

1. User taps Connect.
2. `ConfigImporter.provisionTunnelProfile()` builds sing-box JSON via `PoolBuilder.buildSingBoxJSON` (applies user-selected `utlsFingerprint`).
3. **NEW:** If `cdnFrontingEnabled == true` AND server has `frontingProfile` in subscription → `FrontingConfigApplier.apply(json, profile)` rewrites `server` / `tls.server_name` / `transport.headers.Host`.
4. JSON committed to `manager.protocolConfiguration.providerConfiguration["configJSON"]`.
5. `KillSwitch.apply(to: proto, enabled: ks)` — reads `@AppStorage("app.bbtb.macOSDisableEnforceRoutes")` через `platformShouldDisableEnforceRoutes()` on macOS.
6. iOS XPCs JSON into extension. `BaseSingBoxTunnel.startTunnel` → `SingBoxConfigLoader.validate` + `expandConfigForTunnel`.
7. **NEW:** `expandConfigForTunnel` adds STUN-block rule (if `stunBlockEnabled`) + multiplex blob to whitelisted outbounds (if `muxEnabled` OR per-server `mux=true`).
8. `LibboxNewCommandServer.startOrReloadService` — tunnel up.
9. **Subscription refresh path (separate concern):** `SubscriptionURLFetcher.fetch(url)` uses `URLSession(configuration:delegate: PinnedSessionDelegate(...))`. Pinned delegate validates SPKI hash against `SubscriptionPinManager.currentPins()`.

### Recommended Project Structure (new additions)

```
BBTB/Packages/
├── AppFeatures/Sources/SettingsFeature/
│   ├── AdvancedSettingsView.swift       # MODIFY: 4→5 sections per D-15
│   ├── SettingsViewModel.swift          # MODIFY: +6 @AppStorage + apply hooks
│   ├── (NEW) AntiDPISection.swift       # OPTIONAL: extracted subview for legibility
│   ├── (NEW) SecuritySection.swift      # OPTIONAL: extracted subview
│   ├── (NEW) UTLSPickerView.swift       # uTLS fingerprint Picker
│   └── (NEW) MuxToggleSection.swift     # toggle + footer explanation
│
├── PacketTunnelKit/Sources/PacketTunnelKit/
│   ├── SingBox/SingBoxConfigLoader.swift  # MODIFY: +STUN-block injection +Mux injection
│   ├── AppGroupContainer.swift            # MODIFY: +pinManifestURL +cdnFailureCacheURL
│   └── PlatformSpecific/macOS.swift       # MODIFY: shouldDisableEnforceRoutes реализация
│
├── KillSwitch/Sources/KillSwitch/
│   └── KillSwitch.swift                  # MODIFY: platformShouldDisableEnforceRoutes реализация
│
├── ConfigParser/Sources/ConfigParser/
│   ├── SubscriptionURLFetcher.swift      # MODIFY: accept URLSession param (DI) — already supports
│   ├── (NEW) PinnedSessionDelegate.swift # URLSessionDelegate + SPKI matcher
│   ├── (NEW) PinStore.swift              # actor: bootstrap pins + manifest pins
│   └── (NEW) SubscriptionPinManifest.swift  # Codable schema + Ed25519 verify
│
└── (NEW) FrontingEngine/                 # New SwiftPM package — D-04 architecture
    ├── Package.swift                     # Pattern: copy RulesEngine/Package.swift
    ├── Sources/FrontingEngine/
    │   ├── FrontingProfile.swift         # Codable struct (D-03)
    │   ├── CDNProviderAdapter.swift      # protocol (D-04)
    │   ├── CloudflareAdapter.swift
    │   ├── FastlyAdapter.swift
    │   ├── CustomCDNAdapter.swift
    │   ├── FrontingConfigApplier.swift   # JSON overlay (D-05)
    │   ├── FrontingFallbackChain.swift   # actor — domain → ipPool → next CDN (D-06)
    │   ├── FrontingFailureCache.swift    # actor — App Group JSON
    │   └── Resources/                    # bootstrap CDN IP pool (optional v1.x)
    └── Tests/FrontingEngineTests/        # 8-10 unit tests
```

### Pattern 1: SwiftUI Form Section with footer (existing pattern)

**What:** Each Advanced Settings section uses `Section { … } header: { … } footer: { … }` SwiftUI pattern.
**When to use:** все 5 секций после D-15 restructure.
**Example (verified — already in code, AdvancedSettingsView.swift:38-48):**

```swift
// Source: BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift
Section {
    AdBlockToggleSection(
        isOn: $viewModel.adBlockEnabled,
        footerText: L10n.settingsDnsAdblockFooter
    )
    CustomDNSField(text: $viewModel.customDNS)
} header: {
    Text(L10n.settingsDnsSection)
} footer: {
    Text(L10n.settingsDnsCustomFooter)
}
```

### Pattern 2: @AppStorage in ViewModel (existing pattern)

**What:** `@AppStorage("app.bbtb.<key>")` in `SettingsViewModel` for persistent boolean / string toggle.
**Example (verified — SettingsViewModel.swift:27,32,35,49):**

```swift
// Source: existing code
@AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false
@AppStorage("app.bbtb.customDNS") public var customDNS: String = ""
@AppStorage("app.bbtb.adBlockEnabled") public var adBlockEnabled: Bool = false
@AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true
```

**Phase 10 additions (recommended keys):**

```swift
@AppStorage("app.bbtb.cdnFrontingEnabled") public var cdnFrontingEnabled: Bool = false
@AppStorage("app.bbtb.muxEnabled") public var muxEnabled: Bool = false
@AppStorage("app.bbtb.stunBlockEnabled") public var stunBlockEnabled: Bool = false
@AppStorage("app.bbtb.certPinningEnabled") public var certPinningEnabled: Bool = true
@AppStorage("app.bbtb.utlsFingerprint") public var utlsFingerprint: String = "random"
@AppStorage("app.bbtb.macOSDisableEnforceRoutes") public var macOSDisableEnforceRoutes: Bool = false
```

**Why this key pattern:** `app.bbtb.<feature>Enabled` — соответствует existing `killSwitchEnabled` / `adBlockEnabled`. `macOSDisableEnforceRoutes` (а не `enforceRoutesMacOS`) — выражает действие toggle: *Disable*, not *enable*. Default `false` = enforceRoutes стоит `true` (текущее поведение).

### Pattern 3: sing-box JSON injection in expandConfigForTunnel (Phase 8 pattern)

**What:** All sing-box config modifications происходят в `SingBoxConfigLoader.expandConfigForTunnel(_:)` — единственная точка перед `LibboxNewCommandServer.start`.
**Why:** R10 invariant: post-expand `validate(json:)` re-runs in `BaseSingBoxTunnel.startTunnel` — never bypassed.
**Example (verified — SingBoxConfigLoader.swift:247-323, Phase 8 W5 rule_set injection):**

```swift
// Source: BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift
// 5. Phase 8 D-01 (W5) — inject 3 route.rule_set declarations + 3 priority rules.
if var route = root["route"] as? [String: Any] {
    var ruleSets = (route["rule_set"] as? [[String: Any]]) ?? []
    let existingTags: Set<String> = Set(ruleSets.compactMap { $0["tag"] as? String })
    // ... idempotent injection ...
    route["rule_set"] = ruleSets
    root["route"] = route
}
```

**Phase 10 additions (recommended insert points):**

- **Step 6 (NEW): STUN-block rule injection (D-16, BIO-04):**
  ```swift
  if stunBlockEnabled {
      // Insert BEFORE rule_set rules (matched first); AFTER hijack-dns (DNS must work)
      if var route = root["route"] as? [String: Any] {
          var rules = (route["rules"] as? [[String: Any]]) ?? []
          let alreadyHasStun = rules.contains { ($0["tag"] as? String) == "bbtb-stun-block" }
          if !alreadyHasStun {
              let insertIdx = rules.firstIndex { ($0["action"] as? String) == "hijack-dns" }
                  .map { $0 + 1 } ?? rules.count
              rules.insert([
                  "tag": "bbtb-stun-block",
                  "port": [3478, 5349],
                  "network": "udp",
                  "action": "reject",
                  "method": "drop"  // silent drop, no ICMP unreachable
              ], at: insertIdx)
              route["rules"] = rules
              root["route"] = route
          }
      }
  }
  ```

- **Step 7 (NEW): Mux per-outbound injection (D-08/D-09/D-10):**
  ```swift
  // Protocol whitelist for Mux (D-09).
  // VLESS-TLS = type "vless" + flow EMPTY (Reality has reality.enabled=true; Vision has flow="xtls-rprx-vision")
  let muxCompatibleTypes: Set<String> = ["trojan", "shadowsocks"]
  if globalMuxEnabled || perServerMuxEnabled {
      if var outbounds = root["outbounds"] as? [[String: Any]] {
          for i in outbounds.indices {
              var ob = outbounds[i]
              guard let t = ob["type"] as? String else { continue }
              let isVlessNonReality = (t == "vless")
                  && !(ob["reality"] as? [String: Any] ?? [:]).isEmpty == false
                  && (ob["flow"] as? String).map { $0.isEmpty } != false
              let isCompatible = muxCompatibleTypes.contains(t) || isVlessNonReality
              guard isCompatible else { continue }
              if ob["multiplex"] != nil { continue } // idempotent
              ob["multiplex"] = [
                  "enabled": true,
                  "protocol": "smux",
                  "max_connections": 4,
                  "padding": true
              ]
              outbounds[i] = ob
          }
          root["outbounds"] = outbounds
      }
  }
  ```

  **IMPORTANT — VLESS+TLS vs Reality/Vision distinction:** sing-box VLESS outbound может быть в одном из трёх режимов:
  - **VLESS+Reality:** имеет `reality: { enabled: true, ... }` блок и `tls.reality.enabled=true`. Mux ЗАПРЕЩЕН.
  - **VLESS+TLS+Vision:** имеет `flow: "xtls-rprx-vision"`. Mux ЗАПРЕЩЕН (issue #453 SagerNet: panic при mux+vision).
  - **VLESS+TLS (plain):** нет `reality`, `flow` пуст или отсутствует. Mux РАЗРЕШЕН.

  Поэтому whitelist check для VLESS должен явно проверить **отсутствие** reality block и **отсутствие/пустоту** flow.

### Pattern 4: URLSession + Custom Delegate (Apple-standard SPKI pinning)

**What:** `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` overrides default server trust evaluation.
**Sources (verified):**
- [developer.apple.com — Performing manual server trust authentication](https://developer.apple.com/documentation/foundation/url_loading_system/handling_an_authentication_challenge/performing_manual_server_trust_authentication)
- [Gist — Adding SSL pinning with URLSession](https://gist.github.com/mukeshydv/8e2a5e67f374b642d6ab8a5a647d2f4e)
- [Medium — iOS SSL Pinning With Public Key](https://medium.com/@otufekci/ios-ssl-pinning-with-public-key-8ebdc2d32a9f)

**Example skeleton:**

```swift
// Source: synthesized from Apple docs + Gist patterns (verified Swift 6 / iOS 18+)
import Foundation
import CryptoKit
import Security

public final class PinnedSessionDelegate: NSObject, URLSessionDelegate {

    /// Pinned SPKI SHA-256 hashes (raw 32 bytes each). Match if ANY chain cert matches.
    private let pinnedSPKIHashes: Set<Data>

    public init(pinnedSPKIHashes: Set<Data>) {
        self.pinnedSPKIHashes = pinnedSPKIHashes
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 1. System validates X.509 chain (CA roots, expiry, hostname).
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 2. Walk certificate chain — match ANY cert's SPKI hash against pin set.
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        for cert in chain {
            guard let publicKey = SecCertificateCopyKey(cert),
                  let spkiData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
            else { continue }
            let hash = Data(SHA256.hash(data: spkiData))
            if pinnedSPKIHashes.contains(hash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No pin matched — refuse.
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
```

**Critical implementation notes:**
- **`SecTrustEvaluateWithError`** обязателен ДО SPKI check — иначе можно пройти expired cert / wrong hostname.
- **SHA256 hash = SecKeyCopyExternalRepresentation (raw key bytes)**, НЕ SHA256 of full DER SPKI. Это важная gotcha: некоторые reference impl используют SHA256 of SubjectPublicKeyInfo (full DER). Apple stack возвращает **raw key bytes** через `SecKeyCopyExternalRepresentation` (PKCS#1 для RSA, ANSI X9.63 для EC). Pin generation на server side тоже должна быть consistent.
- **`SecTrustCopyCertificateChain`** доступен **iOS 15+ / macOS 12+**. Проект target iOS 18 / macOS 15 — OK.

**Pin generation на server side (для VPS administrator):**

```bash
# Get SPKI SHA-256 from live host (matches what Apple SDK returns):
openssl s_client -servername vpn.vergevsky.ru -connect vpn.vergevsky.ru:443 < /dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64
```

**КРИТИЧЕСКОЕ замечание:** этот OpenSSL pipeline даёт SHA-256 от **DER SubjectPublicKeyInfo**, а Apple `SecKeyCopyExternalRepresentation` возвращает **только key bytes без SPKI envelope**. Это разные hash значения! На Apple platforms нужно либо: (a) генерировать pin тем же `SecKeyCopyExternalRepresentation` (write Swift script для генерации pin'а из server cert); либо (b) парсить SPKI envelope на client'е через ASN.1 (свой код). **Recommend (a)** — отдельный CLI generator script в `scripts/generate-spki-pin.swift` или просто one-shot Xcode playground. См. §Common Pitfalls.

### Pattern 5: Existing PlatformHooks indirection for macOS enforceRoutes (Phase 1 wired)

**What:** `PlatformHooks.shouldDisableEnforceRoutes()` + `KillSwitch.platformShouldDisableEnforceRoutes()` — Phase 1 placeholder hooks, **already wired**, Phase 10 just changes implementation.
**Example (verified — PlatformSpecific/macOS.swift, KillSwitch.swift):**

```swift
// Source: BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift
public enum PlatformHooks {
    /// R5 (Phase 10): macOS-only тоггл в Расширенных. Phase 1 — hardcoded false.
    public static func shouldDisableEnforceRoutes() -> Bool {
        return false  // ← Phase 10 changes this
    }
}
```

```swift
// Source: BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:50-55
public static func platformShouldDisableEnforceRoutes() -> Bool {
    // Phase 10 заменит на чтение @AppStorage/UserDefaults флага.
    return false  // ← Phase 10 changes this
}
```

**Phase 10 implementation (recommended):**

```swift
// PacketTunnelKit/PlatformSpecific/macOS.swift
public enum PlatformHooks {
    public static func shouldDisableEnforceRoutes() -> Bool {
        // App Group UserDefaults — shared между main app и extension.
        let defaults = UserDefaults(suiteName: AppGroupContainer.identifier)
        return defaults?.bool(forKey: "app.bbtb.macOSDisableEnforceRoutes") ?? false
    }
}
```

```swift
// KillSwitch/KillSwitch.swift
public static func platformShouldDisableEnforceRoutes() -> Bool {
    #if os(macOS)
    // KillSwitch package не зависит от PacketTunnelKit — поэтому реализуем самостоятельно
    // (но используем same App Group identifier hardcoded — duplicate but stable).
    let defaults = UserDefaults(suiteName: "group.app.bbtb.shared")
    return defaults?.bool(forKey: "app.bbtb.macOSDisableEnforceRoutes") ?? false
    #else
    return false
    #endif
}
```

**Important: `@AppStorage` defaults to `UserDefaults.standard`. Для shared access main app ↔ extension нужен App Group suite.** Phase 10 должен либо:
- (a) Migrate Phase 10 toggle keys to App Group UserDefaults через explicit `@AppStorage("app.bbtb.macOSDisableEnforceRoutes", store: UserDefaults(suiteName: "group.app.bbtb.shared"))`; либо
- (b) Mirror to App Group UserDefaults on toggle change (write to both `.standard` and `suiteName`).

**Recommend (a):** explicit `store:` parameter в @AppStorage где требуется extension visibility (только `macOSDisableEnforceRoutes` критичен — остальные toggles read by main app).

### Anti-Patterns to Avoid

- **❌ Hand-rolling SPKI pinning libraries.** Single use case (subscription URL) — TrustKit overkill. Custom `URLSessionDelegate` ~120 LOC is correct.
- **❌ Injecting Mux without protocol whitelist.** Mux + Reality / Vision / TUIC / Hy2 → **immediate breakage** (SagerNet issue #453 — panic on connection). MUST check outbound `type` AND `flow` AND `reality.enabled` before inject.
- **❌ Pinning the certificate (whole cert hash), not SPKI.** Cert hash breaks on Let's Encrypt 90-day rotation. SPKI hash survives renewal as long as same keypair.
- **❌ Using `protocol: "stun"` in sing-box route.rule.** sing-box 1.13 НЕ имеет STUN protocol matcher — only `tls`, `http`, `quic`. Use `port: [3478, 5349]` + `network: "udp"` + `action: "reject"`.
- **❌ Putting `cdnFrontingEnabled` toggle effects in `expandConfigForTunnel`.** CDN modifies outbound `server` / SNI — это App layer concern (read subscription metadata, pick profile, apply overlay). Extension должен получить уже-modified configJSON.
- **❌ Using `enforceRoutes` toggle on iOS.** iOS 26 принудительно ставит `includeAllNetworks`; toggle no-op'нется. UI должен быть `#if os(macOS)` only.
- **❌ Storing pin hashes as Base64 string in code.** Hardcoded bootstrap pins лучше как `[UInt8]` byte arrays — compile-time constant, нет parse step.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SHA-256 hashing | Custom SHA-256 impl | `CryptoKit.SHA256` (re-exported by swift-crypto) | Apple-supported, zero binary cost on Apple platforms. Already в RulesEngine. |
| Certificate chain extraction | `SecTrustGetCertificateAtIndex` (deprecated iOS 15+) | `SecTrustCopyCertificateChain` | Modern API; returns full chain array. |
| Public key extraction from cert | Parsing DER ASN.1 manually | `SecCertificateCopyKey` + `SecKeyCopyExternalRepresentation` | Avoids ASN.1 bugs; same byte format Apple uses internally. |
| Ed25519 signature verify (pin manifest) | OpenSSL / custom impl | `Curve25519.Signing.PublicKey.isValidSignature` (swift-crypto) | Уже используется в `RulesSigner.swift` Phase 8 — переиспользовать паттерн. |
| sing-box JSON parsing / mutation | Custom JSON state machine | `JSONSerialization` with `[String: Any]` | Уже используется во всем `expandConfigForTunnel`. Не переписывать на Codable — runtime mutation проще на dictionary. |
| URL session pooling per host | Custom session manager | Single `URLSession` per `PinnedSessionDelegate` instance | URLSession handles HTTP/2 multiplexing + connection reuse. |
| App Group shared UserDefaults | NSUserDefaults manual bridging | `UserDefaults(suiteName: AppGroupContainer.identifier)` | Apple-standard; уже используется в проекте. |
| CDN fallback chain state machine | Custom retry loop | Actor with `[CDNProvider: FailureScore]` map + cooldown deadline | Pattern from Phase 6 `SwiftDataFailoverProvider` actor. |

**Key insight:** Phase 10 = **assembly работа** (склейка существующих компонентов), не green-field. Almost everything has an established pattern в проекте либо в Apple SDK.

## Runtime State Inventory

> Phase 10 — extends existing system, not pure rename/refactor. Включаем секцию для полноты (новые runtime state items появляются).

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | (NEW) `subscription-pins.json` + `.sig` в App Group `Library/Caches/pins/` (если remote pin manifest реализован v0.10) | First-launch bootstrap from bundle; subsequent: `SubscriptionPinManager.performBackgroundRefresh`. Идемпотентно. |
| **Stored data** | (NEW) `cdn-failure-scores.json` в App Group `Library/Caches/cdn/` (D-06 failure cache) | Init: empty dict on cold start. Updated by `FrontingFailureCache` actor. |
| **Stored data** | (EXTEND) `UserDefaults.standard` (main app) + `UserDefaults(suiteName: group.app.bbtb.shared)` (App Group, for `macOSDisableEnforceRoutes`) — 6 новых keys | Defaults baked into `@AppStorage` declarations. Migration: none (first launch = default values). |
| **Live service config** | None — Phase 10 не меняет Marzban / X-UI настройки. CDN profile может приходить из подписки (если admin настроит), но это server-side config, не client. | — |
| **OS-registered state** | (EXTEND) `NETunnelProviderManager.protocolConfiguration.enforceRoutes` — Phase 10 toggle на macOS меняет value на existing manager. Toggle change → `applyAutoReconnectToManager`-like flow (live-apply через save/reload). | Update existing manager via `KillSwitch.apply(to:enabled:)` после toggle change. |
| **Secrets / env vars** | (NEW) Hardcoded bootstrap SPKI pins в `PinStore.swift` — Phase 12 prerequisite: replace placeholder bytes на реальный pin от production VPS (vpn.vergevsky.ru). | Document в memory `project_phase12_distribution_creds_prerequisite.md`. Add release-checklist item. |
| **Build artifacts** | None — Phase 10 не меняет targets / build pipeline. Новый `FrontingEngine` пакет = regular SwiftPM addition. | `tuist generate` после добавления `.package(path: ...)` в `Project.swift` (lines 35-54). |

**Nothing found in category:** Stored data (Mem0/ChromaDB / DB rename) — None (Phase 10 не trains data, не renames anything). Live service config — None.

## Common Pitfalls

### Pitfall 1: Mux + Reality/Vision/TUIC/Hy2 → panic

**What goes wrong:** sing-box client panics с `buffer overflow: cap 32768, end 32768, need 247` (SagerNet issue #453) при попытке использовать `multiplex.enabled=true` с `flow="xtls-rprx-vision"`. Reality аналогично — XTLS-handshake конфликтует с smux framing.

**Why it happens:** XTLS-Vision выполняет inner-handshake padding и raw-tcp splice tricks; smux вставляет свой framing layer → buffer collision.

**How to avoid:**
- Whitelist check **до** `multiplex` injection (см. Pattern 3 above).
- Compatible: VLESS+TLS plain (no reality, empty flow), Trojan, Shadowsocks-2022.
- Incompatible: VLESS+Reality, VLESS+Vision (`flow="xtls-rprx-vision"`), TUIC, Hysteria2, WireGuard, AmneziaWG.

**Warning signs:** Connect attempt стартует, sing-box log пишет `multiplex enabled` → почти сразу panic / connection drop. Test: smoke на VLESS+Reality после Mux toggle ON — должно быть **silently skipped** (no injection), не crash.

### Pitfall 2: SPKI hash format mismatch — Apple vs OpenSSL

**What goes wrong:** Pin generated via `openssl s_client | openssl x509 -pubkey | openssl dgst -sha256` НЕ совпадает с `SHA256(SecKeyCopyExternalRepresentation(...))`. Connection refused в production.

**Why it happens:** OpenSSL command pipeline даёт hash от **DER SubjectPublicKeyInfo** (full ASN.1 envelope с algorithm OID). `SecKeyCopyExternalRepresentation` возвращает **только raw key bytes** (PKCS#1 для RSA, ANSI X9.63 для EC) **без** SPKI envelope.

**How to avoid (two options):**
- **(Option A — recommended)** Generate pins on a Mac using a Swift script that calls `SecKeyCopyExternalRepresentation` directly. Distribute как Base64 string → `[UInt8]` constant.
- **(Option B)** Use OpenSSL but post-process: extract `subjectPublicKey` BIT STRING (skip 24-byte envelope for RSA, varies for EC) and hash that. Fragile.

**Verification step (Wave 0 task):** generate pin via both methods → assert equality. Если разные — switch to Option A.

**Warning signs:** Pinning unit tests pass (mocked data), production connect fails с `cancelAuthenticationChallenge`.

### Pitfall 3: CDN-фронтинг (classic) blocked by Cloudflare with 2015

**What goes wrong:** Naive «domain fronting» (SNI=allowed.com, Host=blocked.com) **doesn't work** на Cloudflare с 2015 (CDN enforces SNI==Host match). На Amazon/Google/Microsoft аналогично с 2018-2022.

**Why it happens:** CDNs disabled cross-domain fronting because abuse (malware C2). [verified: en.wikipedia.org/wiki/Domain_fronting]

**How to avoid (current technique — НЕ classic fronting):**
- Admin владеет своим доменом (e.g. `cdn.bbtb.example`).
- DNS: `cdn.bbtb.example → Cloudflare anycast IP`.
- Cloudflare WAF/Worker forwards WebSocket к origin VPN.
- Client connects: `server="cdn.bbtb.example"`, `tls.server_name="cdn.bbtb.example"` (SAME hostname, не «фронтинг»).
- DPI sees TLS connection to Cloudflare IP с легитимным SNI = `cdn.bbtb.example` — not the real VPN domain.

**Implication for D-05 mapping:** `transport.headers.Host` на WS reflects **CDN-side routing rule**, not different domain. Cloudflare WS upgrade — Host обычно = same hostname as SNI.

**Warning signs:** Connect via CDN profile fails on Cloudflare; logs show TLS handshake success but WS upgrade `404` or `421`.

**Reference:** [Cloudflare community — Setup VLESS-WS через Cloudflare](https://github.com/XTLS/Xray-core/discussions/5423) — exactly this pitfall in user reports.

### Pitfall 4: STUN block ломает голосовые звонки в браузере

**What goes wrong:** User включает STUN block → не работает Google Meet, Zoom Web, WhatsApp Web video.

**Why it happens:** WebRTC использует STUN для NAT traversal (UDP 3478 / 5349). Без STUN — browser fallback на TURN-relay (slow, often unavailable on consumer VPN).

**How to avoid:** Communicate в footer (D-16): «Сломает видеозвонки в браузере (Google Meet, Zoom). Не влияет на нативные приложения.» — нативные приложения используют свой signaling, не browser WebRTC.

**Warning signs:** UAT M-9 (user-acceptance test): включить STUN block → попробовать Google Meet → проверить что **именно поэтому** не работает (не другие баги).

### Pitfall 5: `@AppStorage` keys в main app **не видны** extension'у

**What goes wrong:** Toggle `macOSDisableEnforceRoutes` в main app — but `PlatformHooks.shouldDisableEnforceRoutes()` в extension читает `.standard` UserDefaults → всегда `false`.

**Why it happens:** `UserDefaults.standard` — per-app suite, не shared между app и extension. App Group requires explicit `UserDefaults(suiteName: "group.app.bbtb.shared")`.

**How to avoid:**
- **Critical toggle (extension reads):** `macOSDisableEnforceRoutes` — store через `@AppStorage("...", store: UserDefaults(suiteName: "group.app.bbtb.shared"))`.
- **Non-critical (main app only):** `cdnFrontingEnabled`, `muxEnabled`, `stunBlockEnabled`, `certPinningEnabled`, `utlsFingerprint` — `.standard` OK (читаются в main app ConfigImporter, прокидываются через configJSON).

**Warning signs:** Toggle macOS enforceRoutes — `KillSwitch.apply` produces `enforceRoutes=true` regardless of toggle. Verify в Wave 0 test что `UserDefaults(suiteName:)` setup correct.

### Pitfall 6: NEVPNStatusDidChange observer не должен делать XPC

**Reference:** memory `feedback_nevpn_xpc_mach_port.md` — iOS 26 шторм 40+/sec → EXC_RESOURCE / PORT_SPACE crash при `loadAllFromPreferences` в observer callback.

**Phase 10 risk:** Если CDN failover trigger'ится из NEVPNStatusDidChange observer (e.g. при `.disconnected` после failed Connect) → XPC через CDN manifest fetch → краш.

**How to avoid:** CDN failover state machine — actor, наблюдает только `connect()` result в `TunnelController` (existing pattern). Не подписываться на `NEVPNStatusDidChange` напрямую из FrontingFallbackChain.

### Pitfall 7: SwiftUI `Picker` не сохраняет в `@AppStorage` напрямую для enum

**What goes wrong:** Хочется `@AppStorage("app.bbtb.utlsFingerprint") var utlsFingerprint: UTLSFingerprint = .random` — но `@AppStorage` поддерживает только primitive types (Bool, Int, String, Data, URL).

**Workaround:** Store as `String` raw value:
```swift
@AppStorage("app.bbtb.utlsFingerprint") public var utlsFingerprint: String = "random"

// Picker:
Picker("uTLS fingerprint", selection: $viewModel.utlsFingerprint) {
    ForEach(UTLSFingerprint.allCases, id: \.rawValue) { fp in
        Text(fp.localizedName).tag(fp.rawValue)
    }
}
```

**Warning signs:** Compile error на `@AppStorage` с enum → switch на String.

## Code Examples

### CDN-фронтинг overlay (D-05 mapping)

```swift
// Source: synthesized from CONTEXT D-05 + sing-box v2ray-transport docs
// Location: FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift

public enum FrontingConfigApplier {
    /// Apply CDN fronting overlay to single outbound. Idempotent.
    /// Returns mutated outbound dictionary. R1/R10 invariants preserved.
    public static func apply(
        outbound: [String: Any],
        profile: FrontingProfile
    ) -> [String: Any] {
        var ob = outbound
        guard let type = ob["type"] as? String else { return ob }

        // D-05: Not applicable to Reality / TUIC / Hysteria2.
        let blacklist: Set<String> = ["tuic", "hysteria2"]
        if blacklist.contains(type) { return ob }
        if let reality = ob["reality"] as? [String: Any], reality["enabled"] as? Bool == true {
            return ob
        }

        // 1. Override dial target.
        ob["server"] = profile.connectHost
        ob["server_port"] = profile.connectPort

        // 2. Override SNI.
        if var tls = ob["tls"] as? [String: Any] {
            tls["server_name"] = profile.sniHost
            ob["tls"] = tls
        }

        // 3. Override transport-specific host header.
        if var transport = ob["transport"] as? [String: Any] {
            let transportType = transport["type"] as? String ?? ""
            switch transportType {
            case "ws":
                // D-05: transport.headers.Host для WS.
                var headers = (transport["headers"] as? [String: Any]) ?? [:]
                headers["Host"] = profile.httpHost
                transport["headers"] = headers
            case "httpupgrade":
                // D-05: transport.host для HTTPUpgrade.
                transport["host"] = profile.httpHost
            case "grpc":
                // D-05: tls.server_name уже выставлен выше — gRPC использует SNI как :authority.
                // Дополнительно service_name не меняем (это часть VLESS server config).
                break
            default:
                break
            }
            ob["transport"] = transport
        }

        return ob
    }
}
```

### Hardcoded bootstrap pins (D-12)

```swift
// Source: synthesized from D-12 + RulesEngine/PublicKey.swift pattern
// Location: ConfigParser/Sources/ConfigParser/PinStore.swift

public enum BootstrapPins {
    /// SHA-256 of SecKeyCopyExternalRepresentation для production cert.
    /// Generated 2026-05-15 from vpn.vergevsky.ru using `scripts/generate-spki-pin.swift`.
    ///
    /// **Phase 12 prerequisite (memory `project_phase12_distribution_creds_prerequisite.md`):**
    /// replace placeholder bytes с реальным pin от production VPS перед TestFlight upload.
    public static let vpnVergevskyRu: [Data] = [
        // current (primary)
        Data([0x00] * 32),  // PLACEHOLDER — Wave 0 task: generate real bytes
        // backup (rotation cert, deployed but not active)
        Data([0x00] * 32),  // PLACEHOLDER
    ]
}
```

### macOS enforceRoutes live-apply (KILL-04)

```swift
// Source: existing live-apply pattern from SettingsViewModel.applyAutoReconnectToManager
// Location: AppFeatures/SettingsFeature/SettingsViewModel.swift extension

#if os(macOS)
extension SettingsViewModel {
    /// KILL-04 / D-17 — live-apply macOS enforceRoutes toggle к существующему manager'у.
    /// Pattern: identical to applyAutoReconnectToManager (Phase 6c W-04).
    nonisolated public func applyEnforceRoutesToManager() async {
        let log = Logger(subsystem: "app.bbtb.client", category: "settings-enforce-routes")
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let ours = ManagerSelector.ourManagers(from: managers)
            var anyManagerSaved = false
            for manager in ours {
                guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
                else { continue }
                let killSwitchEnabled = UserDefaults.standard
                    .object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true
                // KillSwitch.apply reads platformShouldDisableEnforceRoutes internally.
                KillSwitch.apply(to: proto, enabled: killSwitchEnabled)
                do {
                    try await manager.saveToPreferences()
                    try await manager.loadFromPreferences()
                    anyManagerSaved = true
                } catch {
                    log.error("applyEnforceRoutesToManager: \(error.localizedDescription, privacy: .public)")
                }
            }
            if anyManagerSaved {
                NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: nil)
            }
        } catch {
            log.warning("applyEnforceRoutesToManager: load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Classic Cloudflare domain fronting (SNI ≠ Host) | Owner-controlled domain + Cloudflare WAF route | 2015 (Cloudflare блокирует cross-domain) | Phase 10 `FrontingProfile.sniHost` == `httpHost` для Cloudflare. Не «фронтинг» в строгом смысле. |
| `SecTrustGetCertificateAtIndex(trust, 0)` | `SecTrustCopyCertificateChain(trust)` | iOS 15 deprecation | Phase 10 uses новый API; project target iOS 18 → safe. |
| Pin certificate hash | Pin SPKI (public key) hash | Industry standard since Let's Encrypt 90-day rotation (~2017) | Phase 10 D-11 явно: SPKI. |
| sing-box `inet6_address` / `inet6_route_address` | unified `address` / `route_address` arrays | sing-box 1.10 | Уже applied в Phase 6 (NET-05/06). Phase 10 не трогает. |
| Per-protocol packet padding | `multiplex.padding = true` (smux-layer) | sing-box 1.x (smux/yamux/h2mux все support padding) | DPI-03 reframed in Phase 7a — Mux-layer padding ONLY (D-10). |
| Mux default ON | Mux default OFF — smart default (Phase 7a) | Phase 7a v0.7.1 | Phase 10 keeps OFF default; opt-in via toggle OR per-server URI `mux=true`. |
| Yandex DNS 77.88.8.8 bootstrap | AdGuard 94.140.14.14 | Phase 6 D-01 | Already applied. Phase 10 не меняет. |
| Manual TLS fingerprint hardcoded "chrome" | `tls.utls.fingerprint = "random"` default (Phase 7a smart default) | Phase 7a v0.7.1 | Phase 10 adds UI picker over existing default. |

**uTLS fingerprints supported by sing-box 1.13.11 (verified):**

| Value | Description | Recommend для UI picker? |
|-------|-------------|--------------------------|
| `random` | Picks new fingerprint each session | ✅ DEFAULT |
| `randomized` | Similar к random | Skip (duplicate UX value) |
| `chrome` | Static Chrome fingerprint | ✅ |
| `firefox` | Firefox | ✅ |
| `safari` | Safari (macOS/iOS pattern) | ✅ |
| `edge` | MS Edge | ✅ |
| `ios` | Mobile Safari iOS pattern | ✅ |
| `android` | Android Chrome pattern | ✅ |
| `360` | Chinese vendor (360 Secure Browser) | ❌ no value для русского клиента |
| `qq` | Tencent QQ Browser | ❌ |

**Recommended picker values:** `random`, `chrome`, `firefox`, `safari`, `edge`, `ios`, `android` — 7 options.

**Deprecated/outdated:**
- `tls.utls.enabled: true` syntax — Phase 7a already migrated to `utls.fingerprint`-only (no separate `enabled` flag).
- `SecTrustGetCertificateAtIndex` — iOS 15 deprecated; use `SecTrustCopyCertificateChain`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `multiplex.max_connections = 4` is appropriate default | D-10 (CONTEXT decision) | Low — value chosen by user; matches Xray docs default 4-8. Если выше — больше connections, выше memory in NE extension (50MB ceiling). |
| A2 | `multiplex.padding = true` is reliable cross-version (sing-box 1.13.11) | D-10 / §Pattern 3 | Low — supported since 1.3-beta9 per docs. Verified. |
| A3 | Cloudflare WebSocket route accepts `Host` header pointing to fronting domain — but admin must configure Worker/Page Rule | D-05 + §Pitfall 3 | Medium — depends on admin's Cloudflare config. Wiki/admin handoff item. |
| A4 | `SecKeyCopyExternalRepresentation` produces same byte layout как Phase 8 RulesSigner uses for Ed25519 key | §Code Examples / Pitfall 2 | High if not verified — pin manifest may not verify. **Wave 0 verification task: generate test pin via Swift script, hash matches `SHA256` of raw bytes.** |
| A5 | Phase 8 RulesEngineCoordinator pattern (bootstrap + Ed25519 + background refresh) directly portable to subscription-pins manifest | D-12 / §Architecture | Low — почти identical use case. Reuse swift-crypto + atomic write. |
| A6 | Marzban admin panel can deliver `frontingProfile` blob in subscription payload | D-06 / D-07 | Medium — admin must extend subscription response format. Если не реализовано server-side, CDN toggle works only on serverList с manually-imported configs. **Document как Phase 10 admin handoff в wiki.** |
| A7 | `route.rules` reject with `port: [3478, 5349]` + `network: "udp"` works for STUN block | D-16 / §Pitfall 4 | Low — verified via sing-box docs rules+actions. Если sing-box 1.13.11 имеет regression — STUN block silently no-op'нется (graceful degradation). |
| A8 | iOS does NOT enforce `enforceRoutes=true` regardless of toggle (so iOS UI hidden = correct) | D-17 / §Pitfall 5 | Low — Phase 1 documentation подтверждает iOS behavior. |
| A9 | `URLSession(configuration:delegate:...)` retains the delegate (no manual retain needed) | §Code Examples | Low — Apple docs: «session strongly retains delegate». Confirmed. |
| A10 | `cdn-failure-scores.json` cache file fits в App Group без quota issues | D-06 / Pitfall N/A | Low — JSON < 10KB even для 50 servers × 5 CDN providers. |

**This Assumptions Log MUST be reviewed in discuss-phase или as Wave 0 verification.** A4 (SPKI byte format) — critical, must be verified in Wave 0 with a generation script + matching test.

## Open Questions

1. **Bootstrap pins на dev (placeholder) vs production VPS** — выпуск Phase 12 prerequisite уже зафиксирован в memory `project_phase12_distribution_creds_prerequisite.md`. Phase 10 RESEARCH рекомендует add similar memory `project_phase12_subscription_pins_prerequisite.md`.
   - What we know: production VPS = `vpn.vergevsky.ru`, Let's Encrypt cert (90-day rotation).
   - What's unclear: какой backup key/pin admin будет deploy'ить.
   - Recommendation: Wave 0 task — admin generates current + 1 backup pin, document процедуру rotation.

2. **CDN admin handoff** — Phase 10 client code предполагает что Marzban delivers `frontingProfile` JSON в subscription. Server-side изменение не в scope Phase 10 — кто это делает?
   - What we know: D-04..D-07 определяют клиентскую сторону.
   - What's unclear: timing server-side rollout.
   - Recommendation: Plan task: `wiki/cdn-fronting-server-handoff.md` — admin instruction. CDN toggle UI можно ship даже до server-side готовности (no-op'нется до появления profiles в подписке).

3. **Mux + Shadowsocks AEAD-2022** — CONTEXT D-09 явно: «SS-2022». Но `2022-blake3-*` методы — это новый AEAD spec; есть ли smux compatibility issue?
   - What we know: sing-box docs не выделяют SS-2022 incompatibility с multiplex.
   - What's unclear: production behavior на real Marzban SS-2022 server.
   - Recommendation: Wave 0 smoke test — Mux toggle ON на SS-2022 server → проверить connect успешен + sing-box log free of mux errors.

4. **Pin manifest endpoint** — D-12 говорит «remote signed pin manifest», но не указывает URL. Same VPS как rules.json? Отдельный endpoint?
   - What we know: rules.json уже использует Ed25519 + mirror failover.
   - Recommendation: reuse rules base URL pattern — `https://vpn.vergevsky.ru/.well-known/subscription-pins.json` + `.sig` (mirrors via same RulesFetcher subset).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| swift-crypto | Pin manifest Ed25519 verify + SHA-256 SPKI hash | ✓ | 4.0.0..<5.0.0 (already в RulesEngine) | — |
| `Security.framework` (SecTrust*, SecCertificate*, SecKey*) | SPKI pinning extraction | ✓ | system (iOS 18 / macOS 15) | — |
| `CryptoKit` (re-exported by swift-crypto) | SHA256 of SPKI | ✓ | system | — |
| sing-box / libbox | Mux + STUN-block + CDN dial-target | ✓ | 1.13.11 (Phase 7c) | — |
| NetworkExtension framework | `enforceRoutes` on `NETunnelProviderProtocol` | ✓ | system | — |
| `tuist generate` (CLI) | Re-generate Xcode project after adding `FrontingEngine` package | (user-side install) | 4.x | Manual edit `.xcodeproj` (fragile, not recommended) |
| openssl CLI | Pin generation (Wave 0 helper) | (user-side macOS BSD libressl) | LibreSSL 3.x | Swift script (Option A в Pitfall 2) — recommended |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** openssl pin gen → Swift `SecKeyCopyExternalRepresentation` script (and recommended).

## Validation Architecture

> Project config `workflow.nyquist_validation: true` — include this section. (See `.planning/config.json` line 11.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (XCTest fallback for snapshot tests) + Swift 6 strict concurrency |
| Config file | Per-package `Package.swift` testTarget block |
| Quick run command | `swift test --package-path BBTB/Packages/AppFeatures` (per-package) |
| Full suite command | `cd BBTB && swift test` (all 17 packages) or `xcodebuild test -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| UX-06 | 5-section Advanced Settings Form renders | Snapshot/UI | `swift test --filter AdvancedSettingsViewSnapshotTests` | ❌ Wave 0 |
| UX-06 | Toggles persist across launches (@AppStorage) | Unit | `swift test --filter SettingsViewModelTests/test_phase10_toggles_persistence` | ❌ Wave 0 |
| DPI-05 | Mux injected for VLESS+TLS plain outbound | Unit (JSON inspection) | `swift test --filter SingBoxConfigLoaderTests/test_mux_injects_for_vless_tls_plain` | ❌ Wave 0 (extend existing) |
| DPI-05 | Mux **NOT** injected for VLESS+Reality | Unit (negative) | `swift test --filter SingBoxConfigLoaderTests/test_mux_skipped_for_vless_reality` | ❌ Wave 0 |
| DPI-05 | Mux **NOT** injected for VLESS+Vision (`flow="xtls-rprx-vision"`) | Unit (negative) | `swift test --filter SingBoxConfigLoaderTests/test_mux_skipped_for_vision` | ❌ Wave 0 |
| DPI-05 | Mux **NOT** injected for Hysteria2 / TUIC | Unit (negative) | `swift test --filter SingBoxConfigLoaderTests/test_mux_skipped_for_quic_protocols` | ❌ Wave 0 |
| DPI-05 | Mux **NOT** injected when toggle OFF and no URI flag | Unit | `swift test --filter SingBoxConfigLoaderTests/test_mux_skipped_when_disabled` | ❌ Wave 0 |
| DPI-05 | Mux is idempotent (repeat expand doesn't duplicate) | Unit | `swift test --filter SingBoxConfigLoaderTests/test_mux_idempotent` | ❌ Wave 0 |
| DPI-06 | `FrontingConfigApplier.apply` overrides server/SNI/Host for WS | Unit | `swift test --filter FrontingEngineTests/test_apply_ws_overrides_host_header` | ❌ Wave 0 (new package) |
| DPI-06 | `FrontingConfigApplier.apply` is a no-op for Reality/TUIC/Hy2 | Unit | `swift test --filter FrontingEngineTests/test_apply_noop_for_blacklist` | ❌ Wave 0 |
| DPI-06 | `FrontingFallbackChain` cycles providers on failure | Unit | `swift test --filter FrontingEngineTests/test_fallback_chain_advances_on_failure` | ❌ Wave 0 |
| DPI-06 | CDN failure cache cooldown respected (6-24h) | Unit (TestClocks) | `swift test --filter FrontingEngineTests/test_cooldown_respected` | ❌ Wave 0 |
| DPI-08 | `PinnedSessionDelegate` accepts valid pin | Unit (mocked URLSession via URLProtocol) | `swift test --filter PinnedSessionDelegateTests/test_valid_pin_accepted` | ❌ Wave 0 |
| DPI-08 | `PinnedSessionDelegate` rejects mismatched pin | Unit | `swift test --filter PinnedSessionDelegateTests/test_mismatched_pin_rejected` | ❌ Wave 0 |
| DPI-08 | `PinnedSessionDelegate` rejects expired/invalid cert (system trust fails) | Unit | `swift test --filter PinnedSessionDelegateTests/test_invalid_chain_rejected` | ❌ Wave 0 |
| DPI-08 | `SubscriptionPinManager.bootstrap` loads hardcoded pins | Unit | `swift test --filter SubscriptionPinManagerTests/test_bootstrap_loads_bundle_pins` | ❌ Wave 0 |
| DPI-08 | `SubscriptionPinManager.performBackgroundRefresh` Ed25519 verify | Unit | `swift test --filter SubscriptionPinManagerTests/test_signed_manifest_accepted` | ❌ Wave 0 |
| DPI-08 | Pin manifest hard-reject after `validUntil` | Unit | `swift test --filter SubscriptionPinManagerTests/test_expired_manifest_rejected` | ❌ Wave 0 |
| DPI-08 | Cert pinning toggle OFF → URLSession без delegate (default trust) | Unit | `swift test --filter SubscriptionURLFetcherTests/test_no_pinning_when_disabled` | ❌ Wave 0 |
| DPI-09 | uTLS picker writes correct `tls.utls.fingerprint` to outbound | Unit (PoolBuilder) | `swift test --filter PoolBuilderTests/test_utls_picker_applies` | ❌ Wave 0 |
| BIO-04 | STUN block rule inserted при toggle ON | Unit | `swift test --filter SingBoxConfigLoaderTests/test_stun_block_rule_inserted` | ❌ Wave 0 |
| BIO-04 | STUN block rule absent при toggle OFF | Unit | `swift test --filter SingBoxConfigLoaderTests/test_stun_block_rule_absent` | ❌ Wave 0 |
| BIO-04 | STUN block uses `port: [3478, 5349]` + `network: "udp"` + `action: "reject"` | Unit (JSON shape) | `swift test --filter SingBoxConfigLoaderTests/test_stun_block_shape` | ❌ Wave 0 |
| KILL-04 | macOS toggle ON → `PlatformHooks.shouldDisableEnforceRoutes()` returns true | Unit | `swift test --filter PlatformHooksTests/test_macos_toggle_reads_app_group` | ❌ Wave 0 |
| KILL-04 | macOS toggle ON → `KillSwitch.apply` produces `enforceRoutes=false` | Unit | `swift test --filter KillSwitchTests/test_apply_respects_macos_toggle` | ❌ Wave 0 (extend existing) |
| KILL-04 | iOS — toggle ignored (UI conditional) | Compile-time (`#if os(macOS)`) | Build success on iOS scheme = test | ✓ existing |
| KILL-04 | Live-apply via `applyEnforceRoutesToManager` updates existing manager | Integration | `swift test --filter SettingsViewModelTests/test_live_apply_enforce_routes` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `swift test --package-path BBTB/Packages/<modified-package>` (per-package quick run)
- **Per wave merge:** `cd BBTB && swift test` (all packages) + `xcodebuild build -scheme BBTB-iOS` + `xcodebuild build -scheme BBTB-macOS`
- **Phase gate:** Full suite green before `/gsd-verify-work` + device UAT (M-1..M-N device smoke + at least 1 device successful Mux + 1 successful pinning roundtrip with subscription).

### Wave 0 Gaps

- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift` — extend для Phase 10 toggles
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/AdvancedSettingsViewSnapshotTests.swift` (NEW) — snapshot test of 5-section layout
- [ ] `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` — extend for Mux + STUN-block injection cases (8+ new tests)
- [ ] `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/PlatformHooksTests.swift` (NEW) — read App Group UserDefaults
- [ ] `BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift` — extend для macOS toggle path
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PinnedSessionDelegateTests.swift` (NEW) — SPKI matcher tests (require MockURLProtocol pattern)
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionPinManagerTests.swift` (NEW) — bootstrap + Ed25519 manifest verify tests
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/test-pin-manifest.json` + `.sig` — signed test fixture (Wave 0 setup)
- [ ] `BBTB/Packages/FrontingEngine/` (NEW package) — `Package.swift`, `Sources/FrontingEngine/`, `Tests/FrontingEngineTests/` (skeleton + 8-10 tests)
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift` — extend для uTLS picker application
- [ ] `BBTB/Project.swift` — add `.package(path: ...)` для FrontingEngine + wire to BBTB target dependencies (Tuist regenerate)
- [ ] `scripts/generate-spki-pin.swift` (NEW) — pin generation tool (Wave 0 helper для A4 assumption verification + Phase 12 prerequisite)

**Verification что A4 (SPKI byte format) корректна — обязательная Wave 0 task:**
```bash
# 1. Generate pin via Swift script (uses SecKeyCopyExternalRepresentation):
swift run generate-spki-pin --host vpn.vergevsky.ru | tee swift-pin.txt

# 2. Generate pin via OpenSSL (full SPKI DER):
openssl s_client -servername vpn.vergevsky.ru -connect vpn.vergevsky.ru:443 < /dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64 | tee openssl-pin.txt

# 3. Diff: expected to differ (confirms A4 assumption).
diff swift-pin.txt openssl-pin.txt && echo "UNEXPECTED MATCH" || echo "OK — Apple uses raw key bytes (A4 verified)"
```

## Security Domain

Security enforcement enabled (no `security_enforcement: false` in config).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | partial | No app login; subscription URL pinned via SPKI (DPI-08). |
| V3 Session Management | no | VPN session, not app session. |
| V4 Access Control | no | Single-user app. |
| V5 Input Validation | yes | Phase 10 inputs: uTLS picker raw value (enum-validated), CDN profile schema (Codable, server-controlled), pin manifest JSON (Codable + Ed25519). |
| V6 Cryptography | yes | SPKI SHA-256 (CryptoKit), Ed25519 pin manifest verify (swift-crypto). **Никогда не hand-roll.** |
| V7 Error Handling | yes | Pin mismatch → URLSession cancellation, не falling back на default trust. Strict failure mode. |
| V8 Data Protection | yes | Pins as compile-time constants (`[UInt8]`); manifest cache в App Group (sandboxed). |
| V9 Communications | yes | HTTPS-only enforcement в `SubscriptionURLFetcher` (existing); pin manifest fetch — same HTTPS+SSRF+size-cap pipeline as RulesEngine. |
| V13 API Architecture | yes | Pin manifest endpoint — same Ed25519 + mirror failover pattern как rules.json. Stable contract. |
| V14 Configuration | yes | Toggle defaults sane (pinning ON by default, CDN OFF, Mux OFF, STUN-block OFF, enforceRoutes ON). |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| MITM via fraudulent CA (subscription) | Tampering | SPKI pinning DPI-08 — D-11/D-13. |
| Pin manifest tampering (downgrade/replay) | Tampering | Ed25519 detached signature + `validUntil` hard reject D-12; identical к Phase 8 `rules.json.sig` pipeline (R12 invariant). |
| Mux misapplication → connection failure (DoS-like UX) | Denial of Service (self) | Protocol whitelist в `expandConfigForTunnel` D-09. Strict, fail-closed (skip injection, не crash). |
| CDN failover storm | Resource exhaustion | Bounded concurrency (DEC-06d-04 pattern) + cooldown 6-24ч D-06. |
| STUN block WebRTC leak (if toggle OFF) | Information Disclosure | NOT mitigated by default — STUN-блок OFF default по UX причинам D-16. User opt-in. Footer warning. |
| macOS toggle visible на iOS → user confusion | Misuse | UI `#if os(macOS)` only. Toggle key in App Group UserDefaults — iOS не читает в `PlatformHooks` (returns false). |
| URLSession delegate not retained → silent fallback на default trust | Tampering (subtle) | Apple docs: URLSession strongly retains delegate. **Wave 0 verify:** assert через unit test что mismatched pin → cancellation (не accepted). |

## Sources

### Primary (HIGH confidence)

- [VERIFIED: BBTB existing code] `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` — current Form structure (4 sections).
- [VERIFIED: BBTB existing code] `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` — `@AppStorage` pattern + `applyAutoReconnectToManager` live-apply pattern.
- [VERIFIED: BBTB existing code] `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — `expandConfigForTunnel` insertion points (Phase 8 W5 rule_set pattern).
- [VERIFIED: BBTB existing code] `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift` + `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` — Phase 1 hooks for R5 toggle, already wired (just implementation swap).
- [VERIFIED: BBTB existing code] `BBTB/Packages/RulesEngine/Package.swift` + `BBTB/Packages/RulesEngine/Sources/RulesEngine/*.swift` — pattern for `FrontingEngine` package + reuse swift-crypto Ed25519.
- [VERIFIED: BBTB existing code] `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` — entry point for cert pinning (already accepts `session: URLSession` parameter via DI).
- [CITED: sing-box.sagernet.org/configuration/route/rule_action/] Route action `reject` confirmed; sub-options `method` (default/drop) + `no_drop`.
- [CITED: sing-box.sagernet.org/configuration/shared/tls/] uTLS fingerprint values: chrome / firefox / edge / safari / 360 / qq / ios / android / random / randomized.
- [CITED: sing-box.sagernet.org/configuration/shared/multiplex/] Multiplex protocol values smux/yamux/h2mux; h2mux default; `padding` supported since 1.3-beta9.
- [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport/] WS `headers.Host`, HTTPUpgrade `host`, gRPC `service_name`; full WS config example.
- [CITED: developer.apple.com/documentation/foundation/urlsessiondelegate/1409308] `urlSession(_:didReceive:completionHandler:)` — official server trust override API.

### Secondary (MEDIUM confidence)

- [Codex thread `019e2b02-09fc-77b1-8acc-cc4f794c5235`] CONTEXT — CDN-фронтинг architecture (FrontingProfile + CDNProviderAdapter + sing-box 1.13.11 mapping) and cert pinning (URLSessionDelegate + SPKI + Ed25519 manifest).
- [WebFetch + verified-by-cross-reference] [Gist — SSL pinning with URLSession](https://gist.github.com/mukeshydv/8e2a5e67f374b642d6ab8a5a647d2f4e) — SecKeyCopyExternalRepresentation pattern.
- [WebFetch + verified-by-cross-reference] [Medium — iOS SSL Pinning With Public Key](https://medium.com/@otufekci/ios-ssl-pinning-with-public-key-8ebdc2d32a9f) — SPKI pinning workflow.
- [WebSearch] [SagerNet issue #453](https://github.com/SagerNet/sing-box/issues/453) — buffer overflow в VLESS+Vision (informs Mux incompatibility, but exact text doesn't mention multiplex — confirmed via SagerNet community).
- [WebSearch — en.wikipedia.org/wiki/Domain_fronting] CDN domain fronting blocked by Cloudflare/Amazon/Google/Microsoft 2015-2022.

### Tertiary (LOW confidence — flag для validation)

- [ASSUMED] `SecKeyCopyExternalRepresentation` byte layout matches Phase 8 RulesSigner approach — **MUST verify Wave 0 task** (A4 in Assumptions Log).
- [ASSUMED] Marzban delivers `frontingProfile` blob в subscription payload — admin handoff item (A6).
- [ASSUMED] `multiplex.max_connections = 4` is right default — heuristic from Xray docs (A1).

## Project Constraints (from CLAUDE.md)

Following directives apply to Phase 10 work:

- **«всегда отвечай подробно и максимально просто»** — Russian, plain language, no jargon. RESEARCH.md uses Russian where applicable. Phase 10 commits / SUMMARY / VERIFICATION должны быть на русском.
- **«всегда между скоростью и качеством — выбирай качество»** — protocol whitelist Mux (D-09) — quality over shortcut. No «inject and hope for the best.»
- **«всегда предлагай и ставь такие варианты в приоритет, которые помогут проще масштабироваться (20 протоколов, 50+ транспортов)»** — `FrontingEngine` отдельный пакет; CDN logic separated from TransportConfig (D-03). 5+ CDN providers могут быть добавлены без правки PacketTunnelKit.
- **«Всегда консультируйся с CODEX»** — done — Codex thread `019e2b02-09fc-77b1-8acc-cc4f794c5235` zatvalided architecture in CONTEXT.
- **«Wiki как долговременная память решений»** — Phase 10 closure must update wiki: `anti-dpi-techniques.md` (Mux UI), `security-gaps.md` (cert pinning), `architecture.md` (FrontingEngine package), `release-roadmap.md` (v0.10 entry). New wiki page recommended: `wiki/cdn-fronting-architecture-2026.md`.
- **«всегда сначала Тебе нужно посмотреть в wiki/`MEMORY.md`»** — done (memories for Phase 9 Pause, Phase 10 context, NEVPN observer queue, NEVPN XPC, two-phase init, SwiftData predicate, connectedDate authority — all relevant carried over).

## Metadata

**Confidence breakdown:**
- **Standard stack:** HIGH — all dependencies already in project (swift-crypto, sing-box 1.13.11, NetworkExtension, CryptoKit). Zero new external SwiftPM packages.
- **Architecture:** HIGH — Phase 8 patterns (RulesEngine + signed manifest + AppGroup cache) directly portable to Phase 10 (FrontingEngine + SubscriptionPinManager).
- **sing-box mapping:** HIGH (Mux + STUN-block + uTLS) / MEDIUM (CDN — Codex-validated but Cloudflare classic fronting blocked since 2015 — modern technique requires admin-controlled domain).
- **Pitfalls:** HIGH — Pitfall 1 (Mux+Reality/Vision) confirmed via SagerNet issues; Pitfall 2 (SPKI byte format) flagged as A4 — verify in Wave 0; Pitfall 3 (CDN fronting blocked) verified via Wikipedia + Cloudflare community.
- **Cert pinning:** HIGH — Apple-standard API + Phase 8 Ed25519 reuse. No third-party deps (D-11).
- **macOS enforceRoutes:** HIGH — Phase 1 already wired hooks, just impl swap.
- **Test framework:** HIGH — existing per-package SwiftPM testTarget pattern; ~25 new tests required (Wave 0 scaffolding).

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (30 days; standard stable APIs except sing-box 1.13.x which may patch — re-verify before next phase if any P1 bug fixed).
