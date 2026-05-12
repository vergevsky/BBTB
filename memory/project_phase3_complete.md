---
name: Phase 3 — Server management ✓ Complete 2026-05-12
description: Phase 3 закрыта — 8/8 UAT PASS; три нетривиальных бага найдены и закрыты
type: project
---

Phase 3 (server-management, v0.3) завершена 2026-05-12 — UAT T1-T8 PASS.

**Why:** Добавлены server list с секциями по подпискам, pull-to-refresh (2-phase fetch+ping), auto-select по latency, ручной выбор сервера, каскадное удаление.

**How to apply:** Для Phase 4+ учитывать три паттерна из Phase 3 (см. ниже).

---

## Три ключевых открытия Phase 3

### 1. SwiftData #Predicate с UUID? молча возвращает empty

```swift
// BROKEN на части SwiftData runtime'ов:
let d = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.subscriptionID == id })
// id: UUID, subscriptionID: UUID? → тихо пустой результат

// CORRECT:
let all = FetchDescriptor<ServerConfig>()
let rows = try context.fetch(all).filter { $0.subscriptionID == id }
```

Применять везде, где сравниваем UUID?.

### 2. SNI ротируется subscription-серверами (Reality anti-fingerprint)

Subscription-серверы специально меняют SNI между запросами. Если SNI входит в identity key, каждый refresh вставляет дубли.

Identity key = `host:port:protocolID` (без SNI). SNI — mutable config field, обновляется в UPDATE-ветке.

Реализовано: `ServerConfig.identity`, `SubscriptionMergeService.identity(for:)`.

### 3. TunnelController: stopVPNTunnel — fire-and-forget, нужно ждать .disconnected

`stopVPNTunnel()` возвращает сразу. Если немедленно вызвать `startVPNTunnel()`, статус ещё `.disconnecting` → первый poll в connect() бросает ошибку.

Фикс: `disconnect()` поллит до `.disconnected`/`.invalid` (max 5s, шаг 0.5s). `connect()` трактует `.disconnecting` как transient (continue, не throw).

Коммит: `b5d3120`.

---

## Другие решения Phase 3

- `.swipeActions` работает только в `List`. В `LazyVStack` молча игнорируется → `.contextMenu` (long-press)
- `#Predicate { $0.isSupported == true }` (Bool) работает корректно — проблема только с UUID?
- Два ModelContext на одном modelContainer могут видеть разные данные если один ещё не сделал save
- `silentForegroundRefresh` срабатывает на каждый `.active` scenePhase — в т.ч. при старте приложения
