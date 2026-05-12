---
name: SwiftData #Predicate с UUID? тихо возвращает empty
description: SwiftData #Predicate сравнение UUID? == UUID молча возвращает пустой результат на части runtime'ов
type: feedback
---

Никогда не использовать `#Predicate { $0.optionalUUID == someUUID }` в SwiftData — возвращает empty без ошибки.

**Why:** Баг SwiftData runtime; воспроизводится на реальных устройствах; в тестах (in-memory store) может работать корректно, что маскирует проблему.

**How to apply:** Везде где сравниваем UUID? в предикате — заменять на fetch-all + Swift in-memory filter:

```swift
// WRONG:
FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.subscriptionID == id })

// CORRECT:
let all = FetchDescriptor<ServerConfig>()
try context.fetch(all).filter { $0.subscriptionID == id }
```

Применено в: `SubscriptionMergeService`, `ServerListViewModel.confirmDeleteSubscription`, `pendingDeleteSubscriptionServerCount`.
