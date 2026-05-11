---
name: Обзор продукта
description: Что мы строим, для кого, как раздаём — высокоуровневый обзор VPN-клиента
type: project
---

# Обзор продукта

**Summary**: VPN-клиент для macOS и iOS, ориентированный на обход ТСПУ при минималистичном UX. Узкая аудитория «друзей разработчика», только TestFlight, без монетизации на MVP.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Имя и идентификаторы

**Project codename**: `BBTB` (Bring Back The Bug, аббревиатура — используется в Xcode-проекте, репозитории, bundle ID, файлах конфигов).

**Display name** (то, что видит пользователь под иконкой и в App Store):
- Русский: **«Верни жука»**
- English: **«Bring Back the Bug»**

**Apple-инфраструктура** (фиксируем в одном месте, чтобы не возвращаться):
- Apple Developer Team ID: `UAN8W9Q82U`
- Bundle ID prefix: `app.bbtb.*`
  - iOS app: `app.bbtb.client.ios`
  - macOS app: `app.bbtb.client.macos`
  - iOS PacketTunnelExtension: `app.bbtb.client.ios.tunnel`
  - macOS PacketTunnelExtension: `app.bbtb.client.macos.tunnel`
  - macOS AppProxyExtension (v0.8): `app.bbtb.client.macos.appproxy`
- App Group: `group.app.bbtb.shared`
- Universal Links домен: `import.bbtb.app`
- Custom URL scheme: `bbtb://`

**История**: workname проекта изначально был `YourVPN`. Переименован на `BBTB` 2026-05-11 в `/gsd-discuss-phase 1` для Phase 1 (Foundation). Все референсы в `.planning/`, `prompts/v2`, wiki обновлены.

## Что строим

VPN-клиент (Virtual Private Network — виртуальная частная сеть) для нетехнических пользователей в РФ с обходом ТСПУ (Технические Средства Противодействия Угрозам) через современные anti-DPI (Deep Packet Inspection — глубокая инспекция пакетов) протоколы. Главный экран — одна кнопка «Подключиться» и выбор сервера; вся техническая сложность спрятана в раздел «Расширенные».

Принципиальный баланс продукта: **технически богатый внутри** (9 протоколов, 4 транспорта, anti-DPI, kill switch, DNS-стратегия), **визуально минималистичный снаружи** — primary-пользователь никогда не увидит слов «Reality», «uTLS», «sniffing».

## Платформы

- macOS 15+ и iOS 18+ одновременно
- Общая бизнес-логика в Swift Package
- Отдельные UI-таргеты под каждую платформу
- Xcode 16+, Swift 5.10+ / Swift 6 mode

## Дистрибуция

- TestFlight (External Testing) с публичной invite-ссылкой
- До 10 000 тестировщиков, 90 дней жизни сборки
- Никакого публичного App Store на MVP (Minimum Viable Product — минимально жизнеспособный продукт)
- См. [[distribution-testflight]]

## Монетизация

Полностью бесплатно на MVP. Никакой рекламы и donations. См. [[release-roadmap]] — в v2.0 появляется опциональная подписка с managed-инфраструктурой.

## Лицензия

Гибрид: ядро под AGPL-3.0 (Affero General Public License) в публичном репозитории, GUI и pro-фичи закрытые. Подробности — [[licensing]].

## Целевая аудитория

- **Primary**: русскоязычные пользователи в РФ без IT-бэкграунда. Используют iPhone и MacBook. Получают приглашение в TestFlight от знакомого. Один тап — подключение.
- **Secondary**: технически грамотные пользователи (включая самого разработчика) — доступ к расширенным настройкам через отдельный раздел.
- **НЕ целевая**: журналисты и активисты под государственной слежкой. Защита от массового DPI-сканирования, не от таргетированной слежки.

## Языки

Русский и английский с первого дня, две локализации.

## Команда

Один разработчик + Claude Code как co-pilot. Workflow GSD (Get Shit Done). Жёстких сроков нет, приоритет — качество архитектуры над скоростью.

## Related pages

- [[architecture]]
- [[tech-stack]]
- [[release-roadmap]]
- [[ux-specification]]
- [[distribution-testflight]]
- [[licensing]]
