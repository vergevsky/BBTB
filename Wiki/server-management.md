---
name: Управление серверами
description: Phase 3 — server list UI, multi-subscription, pull-to-refresh, auto-select, merge-by-identity
type: project
---

# Управление серверами

**Summary**: Phase 3 (v0.3) — полный цикл управления серверами: список с секциями по подпискам, pull-to-refresh, auto-select по latency, ручной выбор, каскадное удаление подписок. Реализован 2026-05-12.

**Sources**: Phase 3 implementation, UAT results 2026-05-12

**Last updated**: 2026-05-12

---

## Архитектура Phase 3

### SwiftData модели

| Модель | Ключевые поля | Назначение |
|--------|---------------|------------|
| `Subscription` | `id`, `url`, `name`, `lastFetched` | Подписка — группирует ServerConfig по FK |
| `ServerConfig` | `subscriptionID: UUID?`, `identity`, `sni`, `missingFromLastFetch` | Сервер; nil subscriptionID = «добавлен вручную» |

`ServerConfig.identity` = `"\(host):\(port):\(protocolID)"` — **SNI намеренно исключён** (см. ниже).

### Модули

```
AppFeatures/ServerListFeature/
  ServerListSheet.swift        — root view (ScrollView + LazyVStack)
  ServerListViewModel.swift    — @MainActor ObservableObject
  ServerRow.swift              — одна строка сервера + LatencyBadge
  SubscriptionHeader.swift     — заголовок секции подписки
  AutoCell.swift               — sticky «Авто» ячейка

ConfigParser/
  SubscriptionMergeService.swift  — merge-by-identity (D-14)
  SubscriptionURLFetcher.swift    — HTTPS fetch + SSRF blocklist
```

---

## Ключевые решения (D-01..D-14)

### D-14 Merge-by-identity при pull-to-refresh

Каждый refresh подписки выполняет **upsert**, а не replace:
- composite key = `host:port:protocolID`
- существующий row → обновляем `name` и `sni`, **сохраняем** `lastLatencyMs/lastPingedAt/failedProbeCount`
- новый identity → insert (Keychain + SwiftData)
- исчезнувший identity → `missingFromLastFetch = true` (не удаляем — пользователь решает)

Реализован в `SubscriptionMergeService.merge()`.

### SNI исключён из identity

**Проблема**: subscription-серверы ротируют SNI между запросами (Reality domain-fronting / anti-fingerprint). Если SNI входит в identity, каждый refresh видит «новый» сервер и вставляет дубль.

**Решение**: identity = `host:port:protocolID`. SNI обновляется в UPDATE-ветке вместе с `name`.

### SwiftData #Predicate UUID? — молчаливый баг

`#Predicate { $0.subscriptionID == uuid }` (где `subscriptionID: UUID?`) **тихо возвращает пустой результат** на части SwiftData runtime'ов. Симптом: все серверы каждый refresh выглядят «новыми».

**Паттерн-исправление** (применять везде где сравниваем UUID?):
```swift
// WRONG — UUID? predicate silently returns empty
let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.subscriptionID == id })

// CORRECT — fetch all + Swift filter
let allDesc = FetchDescriptor<ServerConfig>()
let rows = try context.fetch(allDesc).filter { $0.subscriptionID == id }
```

Применено в `SubscriptionMergeService` и `ServerListViewModel`.

### TunnelController: disconnect race

`stopVPNTunnel()` — fire-and-forget. Если сразу за ним вызвать `startVPNTunnel()`, poll видит `.disconnecting` → бросает ошибку.

**Решение**:
1. `disconnect()` поллит до `.disconnected`/`.invalid` (max 5 сек, шаг 0.5 сек)
2. `connect()` трактует `.disconnecting` как transient state (continue polling), не как ошибку

### swipeActions в LazyVStack не работают

`.swipeActions` работает только внутри `List`. В `LazyVStack` тихо игнорируется.

**Решение**: `.contextMenu` (long-press) для удаления серверов и подписок.

---

## Pull-to-refresh: 2-phase sequence

1. **Phase 1 — fetch all subscriptions** (sequential, не parallel — D-13): для каждой подписки `fetchAndMerge()` → `SubscriptionMergeService.merge()`
2. **Phase 2 — ping all** supported серверов: `ServerProbeService.probeAll()` → обновляем latency в SwiftData

Реализовано в `ServerListViewModel.pullToRefresh()`. Structured concurrency, нет unstructured `Task`.

Silent foreground refresh (`silentForegroundRefresh()`) — идентичен, но не меняет `state` и не показывает ошибки.

---

## Auto-select: pre-connect probe

При `selectedServerID == nil` (Auto mode) перед подключением:
1. TCP-probe все supported серверы параллельно (`ServerProbeService`)
2. `ServerScore.autoSelect()` выбирает winner: `score = latency × (1 + lossRate)`
3. `provisionTunnelProfile(for: winnerID)` → 1-outbound pool → connect

---

## Каскадное удаление

**Удаление подписки** (`confirmDeleteSubscription`):
1. Найти все `ServerConfig` с `subscriptionID == sub.id` (fetch-all + Swift filter)
2. Для каждого: `KeychainStore.delete(tag:)` + `context.delete(row)`
3. Найти и удалить `Subscription` row в локальном context (не удаляем чужой объект из чужого context — undefined behaviour в SwiftData)
4. Если deleted server был selected → `applySelection(nil)`

**Удаление сервера** (`deleteServer`): то же, один row.

---

## Разделы серверного листа

```
AutoCell (sticky top) — «Авто» с checkmark если id == nil
Section (per Subscription, sorted by lastFetched DESC)
  SubscriptionHeader — name + fetchError indicator + lastFetched
  ServerRow × N       — flag + name + LatencyBadge
Section «Добавлены вручную» (subscriptionID == nil, если есть)
```

Реализован через `ServerListViewModel.groupSections()` — pure static function, testable без SwiftData.

---

## Безопасность (Phase 3)

| Угроза | Решение |
|--------|---------|
| SSRF через subscription URL | `SubscriptionURLFetcher.isBlockedHost()` — blocklist loopback/RFC-1918/link-local/ULA/multicast перед сетевым вызовом |
| Server-controlled display name (XSS-style) | `sanitizeRowName()` — strip `\n\r\t`, clamp 100 chars |
| DNS-rebinding | Accepted risk Phase 3; carry-forward → Phase 7 (cert pinning) |
| IP exposure при pre-connect probe | Accepted risk; документировано wiki/security-gaps.md T-03-24 |

## Связанные страницы

- [[config-importer]] — import pipeline, PoolBuilder
- [[trojan]] — Trojan protocol handler
- [[security-gaps]] — T-03-23..T-03-27
