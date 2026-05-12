---
name: Импорт конфигурации
description: Универсальный pipeline импорта конфигов — 3 формата, PoolBuilder, urltest selector
type: project
---

# Импорт конфигурации

**Summary**: Универсальный pipeline приёма VPN-конфигураций от пользователя. Три формата ввода (subscription URL, JSON endpoint, QR-код) сходятся в единый `ConfigImporter` → `PoolBuilder` → sing-box JSON. В результате: один или несколько outbound-ов с `urltest` автовыбором лучшего сервера.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md, Phase 2 implementation 2026-05-12, Phase 3 implementation 2026-05-12

**Last updated**: 2026-05-12

---

## Три формата импорта

| Формат | Описание | Статус |
|--------|----------|--------|
| **Subscription URL** | Пользователь вставляет URL. Приложение скачивает текст — base64 или plain — с N строк `vless://...` или `trojan://...`. | ✓ v0.2 |
| **Multi-line URI block** | Несколько URI прямо в буфере обмена (через текстовое поле). | ✓ v0.2 |
| **JSON endpoint** | URL отдаёт sing-box / Clash / ShadowSocks JSON напрямую. Парсится отдельным путём. | ✓ v0.2 |
| **QR-код** | Сканирование камерой — декодируется URI или URL. | ✓ v0.2 |
| **Файл** | Открытие файла через Files.app. | Phase 11 (отложено) |

## Схема pipeline

```
Subscription URL ──┐
Multi-line URI    ──┤
JSON endpoint     ──┤──► ConfigImporter ──► [ParsedConfig] ──► PoolBuilder ──► sing-box JSON
QR-код            ──┘                                                           │
                                                                               ▼
                                                            NETunnelProviderManager
                                                            (загружается в iOS VPN profile)
```

### ConfigImporter (MainScreenFeature)

Оркестратор всего pipeline (`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`):

1. Определяет формат ввода (URL vs multi-line URIs vs QR-данные).
2. При URL — `async` скачивает контент (URLSession).
3. Передаёт текст в `URIParser` (VLESS или Trojan) или JSON-парсер.
4. Собирает `[AnyParsedConfig]` — типизированный массив.
5. Вызывает `PoolBuilder.buildSingBoxJSON(from:)` → получает `Data` (JSON).
6. Устанавливает `NETunnelProviderManager` с полученным конфигом через `provisionTunnelProfile(configJSON:serverHost:)`.

### serverHost и tunnelRemoteAddress

`NETunnelNetworkSettings.tunnelRemoteAddress` требует **валидный IP или hostname** (iOS отвергает произвольные строки → NetworkExtension падает до старта sing-box, без логов). Правило:

```swift
// ConfigImporter.swift
let serverHost = firstSupportedOutbound.host  // IP или hostname из URI
provisionTunnelProfile(configJSON: json, serverHost: serverHost)
```

`serverHost` = `host`-поле первого outbound из `[AnyParsedConfig]`. Для display-label — `manager.localizedDescription` (можно ставить любую строку). Подробнее — [[security-gaps]] R13.

## PoolBuilder

`PoolBuilder.buildSingBoxJSON(from: [AnyParsedConfig]) throws -> Data` — ключевой компонент.

**Логика:**
- 1 outbound → прямой `trojan://` или `vless://` outbound без selector.
- 2+ outbound → все обёртываются в `urltest` outbound:
  ```json
  { "type": "urltest", "tag": "selector", "outbounds": [...], "interval": "1m" }
  ```
  Traffic routing: `route.rules[].outbound = "selector"`.

**ALPN-фильтрация для Trojan-WS** — выполняется в `PoolBuilder`, не в `TrojanURIParser`. Парсер сохраняет ALPN «как есть», builder корректирует при генерации outbound (strip `h2` для WS).

## URI-парсеры

| Парсер | Файл | Протокол |
|--------|------|----------|
| `VLESSURIParser` | `ConfigParser/VLESSURIParser.swift` | `vless://` |
| `TrojanURIParser` | `ConfigParser/TrojanURIParser.swift` | `trojan://` |

Оба возвращают `ParsedVLESS` / `ParsedTrojan`, затем оборачиваются в `AnyParsedConfig` (type-erased enum) для единого хранения в массиве.

## Безопасность импорта

**T-02-04 (resolved)**: rawURI — потенциальная утечка секретов в логах sing-box. Фикс: `rawURI` поле у поддерживаемых parsed конфигов = `nil` перед передачей в провайдер — sing-box не видит исходный URI.

**W-02-09 (deferred → Phase 7)**: Subscription fetcher не имеет cap на размер тела ответа и длину redirect-цепочки. Defence-in-depth gap, отложен до Phase 7 (DPI-08, cert pinning).

**T-02-03 (accepted → Phase 12)**: Нет audit-логов импорта. Приоритет — приватность (не логировать URI с паролями). Дополнительный лог можно добавить в Phase 12 с opt-in.

## SubscriptionMergeService (v0.3)

В Phase 3 к pipeline добавился `SubscriptionMergeService` — persistent хранилище серверов с инкрементальным merge (вместо replace-all при каждом refresh).

**Файл**: `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift`

### Алгоритм merge (4 шага)

1. **Fetch** — скачать текущий список URI из `subscriptionURL` через `SubscriptionURLFetcher`.
2. **Dedup cleanup** — удалить дублирующие строки в существующих данных (один identity, несколько SwiftData объектов). Накапливались из-за SNI-ротации до Phase 3 фикса.
3. **3-way merge** по `identity = host:port:protocolID`:
   - (3a) **UPDATE** — сервер есть в fetch и в store → обновить mutable поля (latency, sni, isSupported). SNI обновляется, т.к. subscription-серверы ротируют SNI (anti-fingerprint Reality).
   - (3b) **INSERT** — сервер есть в fetch, нет в store → создать новый `ServerConfig`.
   - (3c) **missingFromLastFetch** — сервер есть в store, не пришёл в текущем fetch → пометить `isSupported = false` (не удалять, сохранять Keychain tag).
4. **Save** — `try context.save()`.

### Ключевые паттерны

**Identity key без SNI**:

```swift
// ServerConfig.identity:
public var identity: String { "\(host):\(port):\(protocolID)" }
```

SNI намеренно исключён из ключа. Subscription-серверы с Reality ротируют SNI между запросами (anti-fingerprint: yandexcloud.net → rbc.ru → s3.yandexcloud.net). Если SNI в ключе — каждый refresh даёт INSERT вместо UPDATE → сервер дублируется.

**SwiftData #Predicate с UUID? — не использовать**:

```swift
// НЕПРАВИЛЬНО — тихо возвращает empty на части SwiftData runtime:
FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.subscriptionID == id })

// ПРАВИЛЬНО — fetch-all + Swift in-memory filter:
let all = try context.fetch(FetchDescriptor<ServerConfig>())
let rows = all.filter { $0.subscriptionID == id }
```

**SSRF-guard** (`SubscriptionURLFetcher.isBlockedHost()`):
- HTTPS-only
- Блокирует loopback (`127.x`, `::1`), link-local (`169.254.x`, `fe80:`), RFC-1918, multicast, ULA

### silentForegroundRefresh

`MainScreenView.onChange(of: scenePhase)` триггерит refresh при каждом `.active` — в т.ч. при старте приложения. Создаёт собственный `ModelContext` и вызывает `fetchAndMerge` параллельно с pull-to-refresh (если пользователь потянул список в тот же момент). Два `ModelContext` на одном `modelContainer` могут видеть несинхронизированный snapshot до `save()`.

## Форматы подписки

На v0.2 поддерживаются:

- **Flat URI list** — каждая строка: `vless://...` или `trojan://...` (самый распространённый формат, v2ray-compatible)
- **Base64-encoded flat list** — тот же список, закодированный в base64 (ShadowSocks-style subscription)
- **sing-box JSON** — прямой outbound-массив в формате sing-box

Clash YAML, Outline access keys — деferred на v0.4 вместе с расширением протоколов.

## Roadmap

- ✓ **v0.2** — subscription URL + multi-line + QR + JSON endpoint
- **v0.4** — Outline access keys, hy2://, ss://, Clash YAML
- **v0.9** — [[deep-links|bbtb:// deep links + Universal Links]] для импорта одним тапом
- **Phase 11** — импорт файла (.json, .yaml, .txt)

## Related pages

- [[trojan]]
- [[vless-reality]]
- [[architecture]]
- [[deep-links]]
- [[security-gaps]]
- [[release-roadmap]]
- [[config-parser-singbox-launcher]]
- [[server-management]]
