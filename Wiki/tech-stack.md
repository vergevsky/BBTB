---
name: Технологический стек
description: Языки, фреймворки, движки, минимальные версии и внешние зависимости
type: project
---

# Технологический стек

**Summary**: Swift 5.10+/6 mode, SwiftUI, Swift Concurrency, NetworkExtension, sing-box через libbox.xcframework и xray-core как fallback. Никаких сторонних аналитических SDK.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Языки и UI

- **Swift 5.10+**, целимся в Swift 6 mode где это возможно (concurrency safety)
- **SwiftUI** как основной UI-фреймворк
- **AppKit** только для Menu Bar app (`NSStatusItem`)
- **Swift Concurrency**: async/await, actors, AsyncSequence
- **Combine не используем** (legacy) — там, где было бы оправдано, используем AsyncSequence

## Хранение

- **SwiftData** — конфиги, серверы, локальная история
- **Keychain** — секреты (приватные ключи, токены)
- Конфиги в Keychain с access flag `kSecAttrAccessibleWhenUnlocked`

## Сеть

- **NetworkExtension framework**: `NEPacketTunnelProvider`, `NEAppProxyProvider`, `NETunnelProviderManager`
- **sing-box** через `libbox.xcframework` (gomobile-биндинги): https://github.com/SagerNet/sing-box — основной движок
- **xray-core** через отдельный xcframework — fallback для специфичных случаев Reality
- **WireGuardKit** от ZX2C4 — нативный WireGuard: https://git.zx2c4.com/wireguard-apple

## Криптография

- **swift-crypto** от Apple — Ed25519 проверка подписи rules.json (см. [[rules-engine]])

## Логирование и диагностика

- **OSLog** — структурированное логирование, фильтрация по subsystem
- **Локальный debug-лог** через кольцевой буфер на N MB на устройстве пользователя
- **НЕТ сторонних SDK**: ни Crashlytics, ни Mixpanel, ни Sentry, никаких других

## Минимальные версии

- iOS 18.0
- macOS 15.0
- Xcode 16+

## Менеджер пакетов

SwiftPM (Swift Package Manager — менеджер пакетов Swift). Никаких CocoaPods и Carthage.

## Принципы выбора зависимостей

Только проверенные библиотеки:

- WireGuardKit от ZX2C4 (автор WireGuard)
- swift-crypto от Apple

Не тащим зависимости ради удобства — выбираем минимально необходимый набор. Сторонние аналитические SDK исключены принципиально (privacy, App Store ревью, поверхность атаки).

## Related pages

- [[architecture]]
- [[protocols-overview]]
- [[anti-dpi-techniques]]
- [[rules-engine]]
