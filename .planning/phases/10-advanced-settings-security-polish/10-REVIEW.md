---
phase: 10-advanced-settings-security-polish
reviewed: 2026-05-15T12:00:00Z
depth: standard
files_reviewed: 28
files_reviewed_list:
  - BBTB/Packages/AppFeatures/Package.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/AntiDPISection.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SecuritySection.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/SettingsFeature/UTLSPickerView.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/PinManifest.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/PinnedSessionDelegate.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CDNProviderAdapter.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CloudflareAdapter.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CustomCDNAdapter.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FastlyAdapter.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingError.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingFailureCache.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingFallbackChain.swift
  - BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingProfile.swift
  - BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift
  - BBTB/Project.swift
  - scripts/generate-spki-pin.swift
findings:
  critical: 6
  warning: 8
  info: 4
  total: 18
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-05-15T12:00:00Z
**Depth:** standard
**Files Reviewed:** 28
**Status:** issues_found

## Summary

Проверено 28 файлов Phase 10 (Advanced Settings + Security polish): новые настройки Anti-DPI (CDN fronting, Mux, uTLS picker, STUN block), cert pinning (PinStore/PinnedSessionDelegate/SubscriptionPinManager), macOS enforceRoutes toggle (KILL-04), FrontingEngine (CDN overlay), интеграция в ConfigImporter.

Реализация архитектурно качественная. Однако обнаружено 6 критических проблем, которые требуют исправления до релиза: force-unwrap в production-инициализации SubscriptionPinManager, placeholder Bootstrap pins которые буквально блокируют все real-TLS соединения, отсутствие валидации FrontingProfile полей (server-injected данные попадают в sing-box JSON без sanitization), некорректное CDN-fetch в auto-mode (второй ModelContext вместо уже загруженного), UserDefaults injection attack через key "app.bbtb.cdnFrontingEnabled" читаемый без валидации, и архитектурное дублирование BootstrapPins в KillSwitch (hardcoded suite name разъезжается с AppGroupContainer.identifier).

---

## Critical Issues

### CR-01: Force-unwrap при инициализации SubscriptionPinManager с невалидным defaultPublicKeyBytes

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift:109-112`
**Issue:** Если `publicKeyBytes` равен `nil` или невалиден, код падает в else-ветку и делает force-unwrap `try? Curve25519.Signing.PublicKey(rawRepresentation:)!`. Если `defaultPublicKeyBytes` (32 байта PLACEHOLDER) не являются валидным Curve25519 ключом, это приведёт к краш в `init` при вызове `SubscriptionPinManager(cacheDir:, publicKeyBytes: nil)`. Даже если нынешние байты случайно валидны — паттерн опасен: любое редактирование `defaultPublicKeyBytes` без проверки может вызвать crash в production.

```swift
// Текущий код (небезопасный):
} else {
    self.publicKey = (try? Curve25519.Signing.PublicKey(
        rawRepresentation: Data(Self.defaultPublicKeyBytes)
    ))!  // CRASH если bytes невалидны
}

// Исправление:
} else {
    guard let key = try? Curve25519.Signing.PublicKey(
        rawRepresentation: Data(Self.defaultPublicKeyBytes)
    ) else {
        // В production это bootstrap failure — разумно fatalError с ясным сообщением
        fatalError("SubscriptionPinManager: defaultPublicKeyBytes is not a valid Curve25519 key. Update before shipping.")
    }
    self.publicKey = key
}
```

**Fix:** Заменить `!` на `guard let` + `fatalError` с читаемым сообщением. Добавить юнит-тест, что дефолтные байты создают валидный ключ.

---

### CR-02: Bootstrap placeholder pins (0x00/0x01) блокируют все HTTPS-соединения при certPinningEnabled=true

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift:28-33`
**Issue:** `BootstrapPins.vpnVergevskyRu` содержит `[UInt8](repeating: 0x00, count: 32)` и `[UInt8](repeating: 0x01, count: 32)`. При `certPinningEnabled = true` (дефолт `true` в SettingsViewModel) каждое subscription-fetch к `vpn.vergevsky.ru` будет отвергнуто `PinnedSessionDelegate`, потому что ни один реальный сертификат не имеет SHA-256(SPKI) = all-zeros. Это значит функция cert pinning **полностью нефункциональна**: либо все запросы падают (режим с pinning), либо pinning обходится отключением (режим без него).

Это не просто TODO — при `certPinningEnabled=true` приложение не сможет обновлять subscription вообще. Default ON-значение certPinningEnabled превращает это в production-blocker.

**Fix:** До Phase 12 TestFlight upload необходимо:
1. Запустить `swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru`
2. Скопировать leaf hash в `BootstrapPins.vpnVergevskyRu[0]`
3. Скопировать intermediate hash в `[1]`

Временный workaround до получения реальных пинов: изменить default `certPinningEnabled = false` в SettingsViewModel, чтобы не блокировать subscription update у всех пользователей по умолчанию.

---

### CR-03: FrontingProfile поля не валидируются — server-controlled данные попадают в sing-box JSON

**File:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingProfile.swift:78-92`, `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CloudflareAdapter.swift:48-84`
**Issue:** `FrontingProfile.connectHost`, `sniHost`, `httpHost` приходят из server-side subscription JSON (Phase 11 admin handoff). Эти значения записываются напрямую в sing-box outbound JSON через `outbound["server"] = profile.connectHost` и `tls["server_name"] = profile.sniHost` без какой-либо валидации. Атакующий admin (или MITM при подмене subscription до верификации) может:
- Внедрить `connectHost = "127.0.0.1"` или `"[::1]"` → sing-box коннектится к loopback (SSRF)
- Внедрить `sniHost` с null-байтами или очень длинную строку → sing-box crash
- Внедрить `connectPort = 0` или `65536` → invalid port

В `SubscriptionURLFetcher` есть SSRF-проверка `isBlockedHost` для subscription URL, но она не применяется к FrontingProfile полям.

**Fix:** Добавить валидацию в `FrontingProfile.init` или в `FrontingConfigApplier.apply`:

```swift
// В FrontingProfile.init или отдельный validator:
static func validate(_ profile: FrontingProfile) throws {
    guard !SubscriptionURLFetcher.isBlockedHost(profile.connectHost) else {
        throw FrontingValidationError.blockedHost(profile.connectHost)
    }
    guard (1...65535).contains(profile.connectPort) else {
        throw FrontingValidationError.invalidPort(profile.connectPort)
    }
    guard profile.connectHost.count <= 253,
          !profile.connectHost.isEmpty else {
        throw FrontingValidationError.invalidHost
    }
}
```

---

### CR-04: CDN apply в auto-mode (selectedID == nil) создаёт второй ModelContext и делает повторный fetch

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:614-618`
**Issue:** В `provisionTunnelProfile(for:)` при `selectedID != nil` код создаёт новый `ModelContext(modelContainer)` и выполняет отдельный `context.fetch(FetchDescriptor<ServerConfig>())` чтобы найти selected config. Это происходит после того, как в начале метода уже была выполнена операция `context.fetch(supportedDesc)` на другом `context`. Два разных ModelContext могут видеть несогласованные данные (один может поймать изменения, которые другой не видит). Кроме того, `FetchDescriptor<ServerConfig>()` без предиката загружает **все** ServerConfig объекты в память только для того, чтобы найти один по ID — в pool с 50+ серверами это избыточно.

```swift
// Проблемный код (строки 614-618):
if let selectedID = selectedID,
   let selectedCfg = try? ModelContext(modelContainer).fetch(
       FetchDescriptor<ServerConfig>()
   ).first(where: { $0.id == selectedID }),
```

**Fix:** Переиспользовать уже полученный список `supported` из начала метода:

```swift
if let selectedID = selectedID,
   let selectedCfg = supported.first(where: { $0.id == selectedID }),
   let profile = extractFrontingProfile(for: selectedCfg) {
```

Это также устраняет второй ModelContext и нагрузку на SwiftData.

---

### CR-05: UserDefaults injection — cdnFrontingEnabled читается из `.standard`, а не из App Group

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:608`
**Issue:** `UserDefaults.standard.bool(forKey: "app.bbtb.cdnFrontingEnabled")` читает toggle из стандартного UserDefaults. Это задокументировано как intentional (main-app-only). Однако `SettingsViewModel.cdnFrontingEnabled` декларирован как `@AppStorage("app.bbtb.cdnFrontingEnabled")` без явного `store:` параметра, то есть тоже пишет в `.standard`. Проблема в другом: `ConfigImporter` — `@unchecked Sendable` и может вызываться из разных Task'ов. Чтение `UserDefaults.standard` из background task (внутри `withThrowingTaskGroup`) не является потокобезопасным на всех версиях iOS (UserDefaults.standard thread-safe только при чтении через main queue согласно Apple documentation).

Более серьёзная проблема: нет защиты от state injection через `UserDefaults.standard`. Любая другая библиотека в процессе (SDK, third-party framework) может записать `"app.bbtb.cdnFrontingEnabled" = true` в `.standard`, активировав CDN overlay неожиданно.

**Fix:** Использовать App Group suite для cdnFrontingEnabled (как это сделано для muxEnabled), либо читать значение только с MainActor и передавать через параметр в `provisionTunnelProfile`.

---

### CR-06: KillSwitch.platformShouldDisableEnforceRoutes hardcodes suite name независимо от AppGroupContainer.identifier

**File:** `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:60`, `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift:20`
**Issue:** В `KillSwitch.swift` захардкожен `UserDefaults(suiteName: "group.app.bbtb.shared")`, а в `macOS.swift` используется `AppGroupContainer.identifier`. Это два разных источника suite name. Если App Group identifier когда-либо изменится (rebrand, migration), KillSwitch.swift не обновится автоматически — enforceRoutes перестанет читать значение из правильного suite, что приведёт к **молчаливому откату к enforceRoutes=true** на macOS независимо от пользовательского toggle. Это нарушение принципа DRY и явный источник будущих багов.

```swift
// KillSwitch.swift (строка 60) — hardcoded:
let defaults = UserDefaults(suiteName: "group.app.bbtb.shared")

// macOS.swift (строка 20) — правильный паттерн через константу:
let defaults = UserDefaults(suiteName: AppGroupContainer.identifier)
```

**Fix:** KillSwitch пакет не должен зависеть от PacketTunnelKit (архитектурное решение Phase 1). Правильное решение — принять suite name как параметр через dependency injection или через статическую конфигурацию при app start, вместо hardcode внутри пакета. Минимальный fix — вынести `"group.app.bbtb.shared"` в константу внутри KillSwitch пакета и синхронизировать её с `AppGroupContainer.identifier` через комментарий-контракт или lint check.

---

## Warnings

### WR-01: STUN block не применяется к уже открытым WebRTC connections

**File:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:395-406`
**Issue:** STUN block инжектируется в sing-box config только при `expandConfigForTunnel`. Если пользователь включает toggle когда туннель уже активен, блок не применяется до следующего переподключения. Нет механизма live-apply (reload config без tunnel restart). Это снижает эффективность: WebRTC peer может определить реальный IP пока туннель работает. В UI (`AntiDPISection`) нет предупреждения об этом.

**Fix:** Добавить footer/hint в `AntiDPISection` что STUN block применяется после следующего переподключения (аналогично поведению `autoReconnectEnabled` toggle). Это информационная проблема, не техническая.

---

### WR-02: FrontingFallbackChain.nextEndpoint — actor reentrancy между cursor reserve и shouldSkip

**File:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingFallbackChain.swift:62-85`
**Issue:** Комментарий в коде честно описывает проблему: cursor резервируется до `await cache.shouldSkip` suspension point. Но если два вызывающих приходят одновременно, оба могут зарезервировать разные слоты до первого suspension — это корректно. Однако если profile[0] заблокирован и cursor=0, первый caller резервирует slot 0 (blocked) → cursor=1 → awaits shouldSkip → returns blocked → continue → reserving slot 1 → cursor=2. Второй concurrent caller может начать после первого cursor=1 advance и сразу зарезервировать slot 1 (cursor=2), пока первый caller ещё ждёт в shouldSkip. Это **не** баг в простом сценарии, но если `shouldSkip` для slot 1 тоже заблокирован, порядок возврата будет недетерминированным. Profile[2] может быть отдан обоим вызывающим если третий вызов приходит после.

Реальный риск: два concurrent вызова могут получить одинаковый profile (slot занят, но второй caller ещё не видит advance). Нет.wait — cursor advance атомарен (один момент), и повторная выдача одного profile невозможна при правильном actor serialization. Но: **тест 11 проверяет только уникальность при 5 concurrent calls на 5 profiles без cooldown**. Тест не проверяет сценарий с cooldown + concurrent — это покрытие gap.

**Fix:** Добавить тест: 5 profiles, 3 в cooldown (включая slot 0, 1, 2), 3 concurrent callers → проверить что каждый получает уникальный profile из {3, 4} или exhausted.

---

### WR-03: SubscriptionPinManager.performBackgroundRefresh — validFrom не проверяется

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift:209`
**Issue:** Код проверяет только `validUntil > clock()` (manifest не истёк). Но не проверяется `validFrom <= clock()`. Таким образом, manifest с `validFrom` в будущем (например, `2030-01-01`) и `validUntil` в будущем (`2031-01-01`) будет принят и применён немедленно. Это создаёт окно для replay-атаки: администратор может "преждевременно активировать" набор пинов, которые должны были стать активными в будущем — это снижает контроль над pin rotation timeline.

```swift
// Текущий код проверяет только expiry:
guard decoded.validUntil > clock() else {
    throw PinManagerError.manifestExpired
}

// Исправление — добавить validFrom check:
guard decoded.validFrom <= clock() else {
    throw PinManagerError.manifestNotYetValid  // новый case
}
guard decoded.validUntil > clock() else {
    throw PinManagerError.manifestExpired
}
```

**Fix:** Добавить `case manifestNotYetValid` в `PinManagerError` и проверку `validFrom <= clock()`.

---

### WR-04: AntiDPISection — STUN cancel не сбрасывает toggle UI корректно

**File:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AntiDPISection.swift:63-65`
**Issue:** При нажатии Cancel в alert: `pendingStunBlock = false`. Но toggle binding читает `viewModel.stunBlockEnabled`, который остаётся `false`. Toggle визуально должен вернуться в OFF. Однако поскольку alert `isPresented` binding ссылается на `$viewModel.stunBlockShowConfirm` (который `@Published`), а не на локальный `@State`, может возникнуть ситуация когда `stunBlockShowConfirm` уже false (alert исчез), но `pendingStunBlock` не был сброшен если пользователь дисмисил alert через swipe-down (без нажатия кнопки Cancel). SwiftUI вызывает `completionHandler` для `.cancel` кнопки, но при системном dismiss (swipe) кнопка Cancel может не вызываться.

**Fix:** Добавить `onDismiss` closure в `.alert` для сброса `pendingStunBlock`:

```swift
.alert(..., isPresented: $viewModel.stunBlockShowConfirm) {
    // кнопки
} message: {
    // ...
}
// Добавить:
.onChange(of: viewModel.stunBlockShowConfirm) { _, newValue in
    if !newValue {
        pendingStunBlock = false  // reset if alert dismissed any way
    }
}
```

---

### WR-05: MockPinFetcher использует nonisolated(unsafe) static var — data race в параллельных тестах

**File:** `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionPinManagerTests.swift:13`
**Issue:** `nonisolated(unsafe) static var responses: [String: Result<Data, Error>] = [:]` — это глобальное изменяемое состояние без синхронизации. В тесте `setUp` и `tearDown` мутируют `MockPinFetcher.responses = [:]`, но если тесты запускаются параллельно (Xcode parallel test execution), один тест может читать stale responses от другого.

**Fix:** Использовать actor или `@MainActor` для изоляции. Минимально: добавить `NSLock` или `DispatchQueue(label:)` вокруг мутаций. Либо использовать instance-based mock вместо static state.

---

### WR-06: SingBoxConfigLoader.expandConfigForTunnel читает UserDefaults из extension (потенциально nil)

**File:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:384-385`
**Issue:** `UserDefaults(suiteName: AppGroupContainer.identifier)?.bool(forKey: "app.bbtb.stunBlockEnabled") ?? false` — если `UserDefaults(suiteName:)` возвращает nil (App Group не настроен в entitlements extension), `stunBlockEnabled` всегда `false`. Аналогично для `muxEnabled` (строка 423). Это silent failure: пользователь включил STUN block, но extension не применяет его, без каких-либо ошибок или логов.

```swift
// Добавить предупреждение при nil:
let groupDefaults = UserDefaults(suiteName: AppGroupContainer.identifier)
if groupDefaults == nil {
    // В production extension это критично — App Group entitlement missing
    // Logger нельзя использовать до init, но можно добавить assertion:
    assertionFailure("App Group suite unavailable in PacketTunnel — entitlements misconfigured")
}
let stunBlockEnabled = groupDefaults?.bool(forKey: "app.bbtb.stunBlockEnabled") ?? false
```

**Fix:** Добавить os.Logger warning при `groupDefaults == nil` (не assertionFailure в production code, но logging).

---

### WR-07: SettingsViewModel.applyEnforceRoutesToManager читает killSwitchEnabled из .standard вместо App Group

**File:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:576`
**Issue:** `UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? false` — дефолт `false` при отсутствии значения. Но `SettingsViewModel.killSwitchEnabled` имеет дефолт `false` через `@AppStorage`. Это согласовано. Однако: при вызове `applyEnforceRoutesToManager` из `nonisolated` контекста, чтение из `.standard` происходит вне MainActor. `@AppStorage` также читает из `.standard`, но через PropertyWrapper который не гарантирует thread-safety из background. В отличие от `applyAutoReconnectToManager`, здесь нет даже документации об этом риске.

Кроме того, дефолт при отсутствии ключа — `false` (kill switch off), тогда как в `DefaultTunnelProvisioner` дефолт — `true`. Несоответствие дефолтов может привести к тому что после первой установки kill switch временно disabled.

**Fix:** Унифицировать дефолт: `UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true` (соответствует дефолту в `DefaultTunnelProvisioner`).

---

### WR-08: FrontingConfigApplier применяет overlay ко всем outbounds включая "direct" и "urltest"

**File:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:47-53`
**Issue:** Цикл `for i in outbounds.indices` применяет `adapter.applyFronting` к **всем** outbounds в массиве — включая `{"type": "direct"}`, `{"type": "urltest"}`, `{"type": "dns"}` и прочие. Adapter'ы (Cloudflare/Fastly/Custom) возвращают false для TUIC/Hysteria2, но не проверяют type="direct" или type="urltest". На практике: для "direct" outbound нет поля `tls`, поэтому Step 2 создаст пустой `tls` dict и запишет `server_name`. Для "urltest" аналогично. Это может corrupt non-proxy outbounds в sing-box config.

```swift
// Пример: direct outbound после CDN overlay:
// {"type": "direct", "tag": "direct", "server": "1.1.1.1", "server_port": 443, "tls": {"server_name": "cdn.example.com"}}
// sing-box может отвергнуть "direct" с неожиданными полями
```

**Fix:** Добавить проверку типа в adapters или в `FrontingConfigApplier.apply`:

```swift
// В начале цикла или в каждом adapter:
let proxyTypes: Set<String> = ["vless", "trojan", "shadowsocks", "hysteria2", "tuic", "vmess", "wireguard"]
guard let type_ = outbound["type"] as? String, proxyTypes.contains(type_) else {
    continue  // skip non-proxy outbounds
}
```

---

## Info

### IN-01: generate-spki-pin.swift не обрабатывает случай когда NWConnection.metadata возвращает nil

**File:** `scripts/generate-spki-pin.swift:97-98`
**Issue:** `if let tlsMetadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata` — если TLS metadata недоступна (например, соединение к non-TLS порту, или TLS не установлен до cancel), `extractedPins` остаётся пустым и скрипт завершается с ошибкой "no certificates extracted". Нет инструктивного сообщения почему это произошло. Также `trust` (строка 98) присваивается но не используется (dead variable).

**Fix:** Добавить else-ветку с диагностическим сообщением. Удалить неиспользуемую переменную `trust`.

---

### IN-02: Placeholder TestFlight URL содержит force-unwrap

**File:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:604`
**Issue:** `URL(string: "https://testflight.apple.com/join/PLACEHOLDER")!` — force-unwrap. Строка статична и не изменяется в runtime, поэтому crash невозможен, но паттерн нежелателен. При замене PLACEHOLDER на реальный token нужно убедиться что итоговая строка остаётся валидным URL.

**Fix:** Использовать `URL(string:)!` с комментарием что статический literal гарантированно валиден, или использовать `#URL("https://testflight.apple.com/join/PLACEHOLDER")` (Swift 5.9+) для compile-time проверки.

---

### IN-03: PinStore WARNING лог использует print() вместо os.Logger

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift:83-85`
**Issue:** `print("[PinStore] WARNING: invalid hex pin...")` — только в `#if DEBUG`. В production сборке невалидный hex pin молча пропускается без какого-либо логирования. Если manifest содержит невалидный pin (например, из-за truncation), это тихо снижает уровень pin coverage.

**Fix:** Использовать `os.Logger` вместо `print` — без `#if DEBUG` guard (WARNING-уровень не создаёт spam, но информирует об аномалиях).

---

### IN-04: ConfigImporter.provisionTunnelProfile(for:) не логирует когда CDN overlay skipped в auto-mode

**File:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:630-632`
**Issue:** Комментарий "auto-mode CDN fronting will apply in Phase 11" без logging. Если разработчик включает `cdnFrontingEnabled = true` в auto-mode, ничего не происходит молча. Это затруднит диагностику в Phase 11 когда CDN overlay начнёт применяться — неясно было ли оно применено.

**Fix:** Добавить `Logger.debug("CDN fronting: auto-mode skipped (Phase 11 pending)")` чтобы в логах было видно состояние.

---

_Reviewed: 2026-05-15T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
